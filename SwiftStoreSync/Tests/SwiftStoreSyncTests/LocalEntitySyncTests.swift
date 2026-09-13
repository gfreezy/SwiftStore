import Foundation
import Testing
import SwiftStoreCore
@testable import SwiftStoreSync
@testable import SwiftStoreChangeTracker

@Entity(sync: false)
struct LocalOnlyNote {
    var id: UUIDV7 = UUIDV7()
    var title: String
    var createdAt: Date = Date(timeIntervalSince1970: 1)
    var updatedAt: Date = Date(timeIntervalSince1970: 1)
}

private final class LocalEntityFixture {
    let db: SQLiteConnection
    let manager: SyncManager
    init() throws {
        db = try SQLiteConnection(path: ":memory:")
        for sql in SchemaSnapshot(entities: [CloudStoreNote.self, LocalOnlyNote.self]).creationStatements {
            try db.execute(sql)
        }
        manager = try SyncManager(connection: db, deviceID: UUIDV7(),
            entities: [CloudStoreNote.self, LocalOnlyNote.self], schemaVersion: 1, now: { 10_000 })
        try manager.startTracking()
        _ = try manager.bind(accountID: "account", scope: "scope", driver: .operations)
    }
    // Simulate existing immutable logs. Local-only payloads are deliberately invalid
    // and use a future schema: exclusion happens before business payload validation.
    func appendLocal(entity: String = LocalOnlyNote.tableName) throws {
        try SyncLogStorage.append(ChangeLog(entityType: entity, syncKey: Data([1]), operation: .insert,
            payload: "invalid", deviceId: UUIDV7(), logicalClock: 1, schemaVersion: 100), to: db)
    }
    func receipt(_ item: CloudUploadItem) -> CloudUploadDecision {
        .init(changeID: item.change.id, outcome: .committed,
            record: .init(change: item.change, systemFields: Data()))
    }
    func localRecord() -> CloudRecord {
        .init(change: .init(id: UUIDV7(), entityType: LocalOnlyNote.tableName, syncKey: Data([1]),
            operation: .insert, payload: "invalid", deviceId: UUIDV7(), logicalClock: 0,
            schemaVersion: 100, createdAt: Date(timeIntervalSince1970: 20)), systemFields: Data())
    }
    func noteRecord(entity: String = CloudStoreNote.tableName) throws -> CloudRecord {
        let note = CloudStoreNote(title: "remote", updatedAt: Date(timeIntervalSince1970: 20))
        return .init(change: .init(id: UUIDV7(), entityType: entity,
            syncKey: SyncKeyEncoder.encode([.blob(note.id.data)]), operation: .insert,
            payload: String(decoding: try JSONEncoder().encode(note), as: UTF8.self),
            deviceId: UUIDV7(), logicalClock: 0, schemaVersion: 1, createdAt: note.updatedAt), systemFields: Data())
    }
}

@Suite("Local-only entity sync exclusion")
struct LocalEntitySyncTests {
    @Test func bootstrapAndDirectSQLOnlyTrackSynchronizedEntities() throws {
        let db = try SQLiteConnection(path: ":memory:")
        let entities: [any EntityProtocol.Type] = [CloudStoreNote.self, LocalOnlyNote.self]
        for sql in SchemaSnapshot(entities: entities).creationStatements { try db.execute(sql) }
        try db.insert(CloudStoreNote(title: "existing"))
        try db.insert(LocalOnlyNote(title: "existing"))
        // Direct ChangeTracker users get the same filtering as ConnectionManager.
        let tracker = try ChangeTracker(connection: db, deviceId: UUIDV7(), registeredEntities: entities)
        try tracker.captureExistingRows()
        try tracker.start()
        #expect(CloudStoreNote.isSyncEnabled)
        #expect(!LocalOnlyNote.isSyncEnabled && !LocalOnlyNote.isReadonly)
        #expect(!tracker.tracksTable(LocalOnlyNote.tableName))
        try db.execute("INSERT INTO local_only_note SELECT randomblob(16), 'second', 1, 1")
        try db.execute("UPDATE local_only_note SET title='updated'")
        #expect(try LocalOnlyNote.count(db) == 2)
        try db.execute("DELETE FROM local_only_note")
        let log = try ChangeTrackerReader(connection: db).changes(after: 0)
        #expect(log.count == 1 && log.first?.entityType == CloudStoreNote.tableName)
        #expect(try db.queryScalar("SELECT COUNT(*) FROM __swiftstore_sync_bootstrap", type: Int.self) == 1)
    }

    @Test func mixedUploadSkipsLocalEventsWithoutCrossingUnconfirmedHoles() throws {
        let f = try LocalEntityFixture()
        try f.appendLocal() // 1
        try f.db.insert(CloudStoreNote(title: "A")) // 2
        try f.appendLocal() // 3
        try f.db.insert(CloudStoreNote(title: "B")) // 4
        try f.appendLocal() // 5
        let batch = try #require(try f.manager.nextBatch(limit: 5))
        #expect(batch.events.map(\.seq) == [1, 2, 3, 4, 5])
        #expect(batch.items.map(\.coveredSequences) == [[2], [4]])
        let partial = try f.manager.commit(batch, incoming: [f.receipt(batch.items[1])])
        #expect(partial.pushed == 1 && !partial.batchComplete)
        #expect(try f.manager.state().pushCursor == 1)
        f.manager.abandonBatch() // Retry recreates the same pending work from durable state.
        let retry = try #require(try f.manager.nextBatch(limit: 5))
        #expect(retry.items.map(\.change.id) == batch.items.map(\.change.id))
        let done = try f.manager.commit(retry, incoming: retry.items.map(f.receipt))
        #expect(done.batchComplete)
        #expect(try f.manager.state().pushCursor == 5)
        #expect(try ChangeTrackerReader(connection: f.db).count(after: 0) == 5)
        #expect(try f.manager.nextBatch(limit: 5) == nil)
    }

    @Test func localOnlyWindowsAdvanceDurablyAndDoNotProduceEmptyUploads() throws {
        let f = try LocalEntityFixture()
        for _ in 0..<7 { try f.appendLocal() }
        #expect(try f.manager.nextBatch(limit: 2) == nil)
        #expect(try f.manager.state().pushCursor == 7)
        let reopened = try SyncManager(connection: f.db, deviceID: UUIDV7(),
            entities: [CloudStoreNote.self, LocalOnlyNote.self], schemaVersion: 1)
        #expect(try reopened.state().pushCursor == 7)
        try f.appendLocal() // 8
        try f.db.insert(CloudStoreNote(title: "later")) // 9
        let batch = try #require(try f.manager.nextBatch(limit: 1))
        #expect(batch.events.map(\.seq) == [9])
        #expect(try f.manager.state().pushCursor == 8)
    }

    @Test func failedLocalCursorCommitRollsBackAndCanRetry() throws {
        let f = try LocalEntityFixture()
        try f.appendLocal()
        try f.db.execute("""
            CREATE TRIGGER reject_cursor BEFORE UPDATE OF push_seq ON __swiftstore_cloud_state
            BEGIN SELECT RAISE(ABORT, 'Simulated disk failure'); END
            """)
        #expect(throws: (any Error).self) { _ = try f.manager.nextBatch(limit: 2) }
        #expect(try f.manager.state().pushCursor == 0)
        try f.db.execute("DROP TRIGGER reject_cursor")
        #expect(try f.manager.nextBatch(limit: 2) == nil)
        #expect(try f.manager.state().pushCursor == 1)
    }

    @Test func unknownUploadStillBlocksAfterSkippedLocalPrefix() throws {
        let f = try LocalEntityFixture()
        try f.appendLocal()
        let unknown = try f.noteRecord(entity: "unknown").change
        try SyncLogStorage.append(ChangeLog(id: unknown.id, entityType: unknown.entityType,
            syncKey: unknown.syncKey, operation: unknown.operation, payload: unknown.payload,
            deviceId: unknown.deviceId, logicalClock: 1, schemaVersion: 1), to: f.db)
        #expect(throws: SyncError.self) { _ = try f.manager.nextBatch(limit: 2) }
        #expect(try f.manager.state().pushCursor == 1)
    }

    @Test func downloadsSkipLocalEntitiesButCommitOtherRowsAndPageCheckpoint() throws {
        let f = try LocalEntityFixture()
        try f.db.insert(LocalOnlyNote(title: "preserved"))
        #expect(try f.manager.receive([f.localRecord(), f.noteRecord()],
            checkpoint: .init(driver: .operations, data: Data([1]))) == 1)
        #expect(try LocalOnlyNote.first(f.db)?.title == "preserved")
        #expect(try CloudStoreNote.first(f.db)?.title == "remote")
        #expect(try ChangeLog.count(f.db) == 0)
        #expect(try f.db.queryScalar("SELECT COUNT(*) FROM __swiftstore_cloud_versions", type: Int.self) == 1)
        #expect(try f.manager.receive([f.localRecord()],
            checkpoint: .init(driver: .operations, data: Data([2]))) == 0)
        #expect(try f.db.queryScalar("SELECT checkpoint FROM __swiftstore_cloud_state", type: Data.self) == Data([2]))
        #expect(throws: SyncError.self) {
            _ = try f.manager.receive([f.localRecord(), f.noteRecord(entity: "unknown")],
                checkpoint: .init(driver: .operations, data: Data([3])))
        }
        #expect(try f.db.queryScalar("SELECT checkpoint FROM __swiftstore_cloud_state", type: Data.self) == Data([2]))
    }
}
