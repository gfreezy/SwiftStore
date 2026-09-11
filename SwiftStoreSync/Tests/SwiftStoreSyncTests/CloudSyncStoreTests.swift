import Foundation
import Testing
import SwiftStoreCore
@testable import SwiftStoreSync
@testable import SwiftStoreChangeTracker

@Entity
struct CloudStoreNote {
    #Index<Self>(\.title, unique: true)
    var id: UUIDV7 = UUIDV7()
    var title: String
    var value: Int = 0
    var createdAt: Date = Date(timeIntervalSince1970: 1)
    var updatedAt: Date = Date(timeIntervalSince1970: 1)
}

final class CloudStoreFixture {
    final class Clock { var time: Int64 = 10_000 }
    let db: SQLiteConnection
    let clock = Clock()
    let device = UUIDV7()
    let manager: SyncManager
    init(path: String = ":memory:") throws {
        db = try SQLiteConnection(path: path)
        if try !db.tableExists(CloudStoreNote.tableName) {
            for sql in SchemaSnapshot(entities: [CloudStoreNote.self]).creationStatements { try db.execute(sql) }
        }
        let clock = clock
        manager = try SyncManager(connection: db, deviceID: device, entities: [CloudStoreNote.self], schemaVersion: 1, now: { clock.time })
        try manager.startTracking()
        _ = try manager.bind(accountID: "account", scope: "scope", driver: .operations)
    }
    func insert(_ title: String) throws -> CloudStoreNote {
        let note = CloudStoreNote(title: title); try db.insert(note)
        return try #require(try CloudStoreNote.filter(\.id == note.id).first(db))
    }
    func update(_ note: CloudStoreNote, title: String) throws {
        try db.execute("UPDATE cloud_store_note SET title=? WHERE id=?", values: [.text(title), .blob(note.id.data)])
    }
    func log() throws -> [ChangeLog] { try ChangeTrackerReader(connection: db).changes(after: 0, limit: 10000) }
    func remote(_ note: CloudStoreNote, time: Double, title: String? = nil, deletion: Bool = false, schema: Int = 1) throws -> CloudRecord {
        var note = note; note.updatedAt = Date(timeIntervalSince1970: time)
        if let title { note.title = title }
        let change = SyncChange(id: UUIDV7(), entityType: CloudStoreNote.tableName,
            syncKey: SyncKeyEncoder.encode([.blob(note.id.data)]), operation: deletion ? .delete : .update,
            payload: deletion ? nil : String(decoding: try JSONEncoder().encode(note), as: UTF8.self),
            deviceId: UUIDV7(), logicalClock: 0, schemaVersion: schema, createdAt: note.updatedAt)
        return CloudRecord(change: change, systemFields: Data())
    }
    func receipt(_ item: CloudUploadItem) -> CloudUploadDecision {
        CloudUploadDecision(changeID: item.change.id, outcome: .committed,
            record: CloudRecord(change: item.change, systemFields: Data()))
    }
}

@Suite("CloudKit SQLite sync core")
struct CloudSyncStoreTests {
    @Test("Coalescing stays within the fixed window and confirmation cannot cross a hole")
    func coalescingAndPrefix() throws {
        let f = try CloudStoreFixture()
        let a = try f.insert("A"); _ = try f.insert("B"); try f.update(a, title: "A2")
        let batch = try #require(try f.manager.nextBatch(limit: 3))
        #expect(batch.items.count == 2)
        let item = try #require(batch.items.first { $0.coveredSequences == [1,3] })
        _ = try f.manager.commit(batch, incoming: [f.receipt(item)])
        #expect(try f.manager.state().pushCursor == 1)
        try f.update(a, title: "A3")
        let remaining = try #require(batch.items.first { $0.coveredSequences == [2] })
        _ = try f.manager.commit(batch, incoming: [f.receipt(remaining)])
        #expect(try f.manager.state().pushCursor == 3)
        let next = try #require(try f.manager.nextBatch(limit: 3))
        #expect(next.events.map(\.seq) == [4])
        #expect(try CloudStoreNote.filter(\.id == a.id).first(f.db)?.title == "A3")
        #expect(try f.log().count == 4)
    }

    @Test("Newer downloads apply immediately despite pending local uploads and never echo")
    func directPull() throws {
        let f = try CloudStoreFixture(); let note = try f.insert("local")
        let remote = try f.remote(note, time: 20, title: "cloud")
        #expect(try f.manager.receive([remote], checkpoint: .init(driver: .operations, data: Data([1]))) == 1)
        #expect(try CloudStoreNote.first(f.db)?.title == "cloud")
        #expect(try CloudStoreNote.first(f.db)?.updatedAt.timeIntervalSince1970 == 20)
        #expect(try f.log().count == 1)
        #expect(try f.manager.receive([remote], checkpoint: nil) == 0)
        let batch = try #require(try f.manager.nextBatch(limit: 200))
        _ = try f.manager.commit(batch, incoming: [.init(changeID: batch.items[0].change.id, outcome: .superseded)])
        #expect(try f.manager.state().pushCursor == 1)
        #expect(try f.log().count == 1)
    }

    @Test("Older downloads are ignored but their page checkpoint advances")
    func olderPull() throws {
        let f = try CloudStoreFixture(); let note = try f.insert("local")
        #expect(try f.manager.receive([f.remote(note, time: 5, title: "old")],
            checkpoint: .init(driver: .operations, data: Data([2]))) == 0)
        #expect(try CloudStoreNote.first(f.db)?.title == "local")
        let saved = try f.manager.bind(accountID: "account", scope: "scope", driver: .operations)
        #expect(saved.checkpoint.data == Data([2]))
    }

    @Test("Equal-time different content uses the authoritative server record without retimestamping")
    func tie() throws {
        let f = try CloudStoreFixture(); let note = try f.insert("local")
        let remote = try f.remote(note, time: 10, title: "cloud")
        #expect(try f.manager.receive([remote], checkpoint: nil) == 1)
        #expect(try CloudStoreNote.first(f.db)?.updatedAt.timeIntervalSince1970 == 10)
        #expect(try f.log().count == 1)
        #expect(try f.db.queryScalar("SELECT COUNT(*) FROM sqlite_master WHERE type='trigger' AND name='__swiftstore_update_cloud_store_note'", type: Int.self) == 1)
    }

    @Test("Clock rollback and delete/recreate produce increasing versions only for real local edits")
    func monotonic() throws {
        let f = try CloudStoreFixture(); let note = try f.insert("first")
        f.clock.time = 1
        try f.update(note, title: "second")
        try f.db.execute("DELETE FROM cloud_store_note")
        try f.db.insert(CloudStoreNote(id: note.id, title: "reborn"))
        let times = try f.log().map { Int64((SyncChange(from: $0).updatedAt.timeIntervalSince1970 * 1000).rounded()) }
        #expect(times == [10_000,10_001,10_002,10_003])
        try f.db.execute("UPDATE cloud_store_note SET title=title")
        #expect(try f.log().count == 4)
        #expect(try CloudStoreNote.first(f.db).map { Int64(($0.updatedAt.timeIntervalSince1970 * 1000).rounded()) } == 10_003)
    }

    @Test("Tombstones reject stale resurrection and are replaced only by a newer live version")
    func tombstone() throws {
        let f = try CloudStoreFixture(); let note = try f.insert("note")
        _ = try f.manager.receive([f.remote(note, time: 30, deletion: true)], checkpoint: nil)
        _ = try f.manager.receive([f.remote(note, time: 20)], checkpoint: nil)
        #expect(try CloudStoreNote.count(f.db) == 0)
        _ = try f.manager.receive([f.remote(note, time: 40, title: "reborn")], checkpoint: nil)
        #expect(try CloudStoreNote.first(f.db)?.title == "reborn")
        #expect(try f.log().count == 1)
    }

    @Test("A failing page rolls back records, version metadata and its token")
    func atomicPullFailure() throws {
        let f = try CloudStoreFixture()
        let a = CloudStoreNote(title: "same"), b = CloudStoreNote(title: "same")
        #expect(throws: (any Error).self) {
            try f.manager.receive([f.remote(a, time: 20), f.remote(b, time: 21)],
                checkpoint: .init(driver: .operations, data: Data([4])))
        }
        #expect(try CloudStoreNote.count(f.db) == 0)
        #expect(try f.db.queryScalar("SELECT COUNT(*) FROM __swiftstore_cloud_versions", type: Int.self) == 0)
        #expect(try f.manager.bind(accountID: "account", scope: "scope", driver: .operations).checkpoint.data == nil)
    }

    @Test("Future schema anywhere in a page blocks the entire page")
    func futureSchema() throws {
        let f = try CloudStoreFixture()
        #expect(throws: (any Error).self) {
            try f.manager.receive([f.remote(CloudStoreNote(title: "ok"), time: 20),
                f.remote(CloudStoreNote(title: "future"), time: 30, schema: 2)],
                checkpoint: .init(driver: .operations, data: Data([5])))
        }
        #expect(try CloudStoreNote.count(f.db) == 0)
    }

    @Test("Checkpoint write failure rolls back the downloaded page and upload corrections")
    func checkpointFailure() throws {
        let f = try CloudStoreFixture(); let note = try f.insert("local")
        try f.db.execute("CREATE TRIGGER fail_checkpoint BEFORE UPDATE ON __swiftstore_cloud_state BEGIN SELECT RAISE(ABORT,'checkpoint failure'); END")
        #expect(throws: (any Error).self) {
            try f.manager.receive([f.remote(note, time: 20, title: "remote")], checkpoint: .init(driver: .operations, data: Data([6])))
        }
        let batch = try #require(try f.manager.nextBatch(limit: 200))
        #expect(throws: (any Error).self) {
            try f.manager.commit(batch, incoming: [.init(changeID: batch.items[0].change.id, outcome: .superseded,
                record: f.remote(note, time: 20, title: "winner"))])
        }
        #expect(try CloudStoreNote.first(f.db)?.title == "local")
        #expect(try f.manager.state().pushCursor == 0)
        try f.db.execute("DROP TRIGGER fail_checkpoint")
        _ = try f.manager.commit(batch, incoming: [f.receipt(batch.items[0])])
        #expect(try f.manager.state().pushCursor == 1)
    }

    @Test("Driver migration clears only the download state; account and scope never change silently")
    func driverChange() throws {
        let f = try CloudStoreFixture(); _ = try f.insert("note")
        let batch = try #require(try f.manager.nextBatch(limit: 200))
        _ = try f.manager.commit(batch, incoming: [f.receipt(batch.items[0])])
        try f.manager.saveCheckpoint(.init(driver: .operations, data: Data([7])))
        let next = try f.manager.bind(accountID: "account", scope: "scope", driver: .engine)
        #expect(next.state.pushCursor == 1 && next.checkpoint.data == nil)
        #expect(throws: SyncError.self) { try f.manager.bind(accountID: "other", scope: "scope", driver: .engine) }
        #expect(throws: SyncError.self) { try f.manager.bind(accountID: "account", scope: "other", driver: .engine) }
    }

    @Test("Sequence holes are harmless; cursor follows actual committed event order")
    func sequenceHoles() throws {
        let f = try CloudStoreFixture(); _ = try f.insert("one")
        try f.db.execute("UPDATE sqlite_sequence SET seq=100 WHERE name='__swiftstore_change_log'")
        _ = try f.insert("two")
        let batch = try #require(try f.manager.nextBatch(limit: 200))
        #expect(batch.events.map(\.seq) == [1,101])
        _ = try f.manager.commit(batch, incoming: batch.items.map(f.receipt))
        #expect(try f.manager.state().pushCursor == 101)
    }

    @Test("Restart after a lost response replays the same change ID and immutable payload")
    func lostResponse() throws {
        let f = try CloudStoreFixture(); _ = try f.insert("pending")
        let original = try #require(try f.manager.nextBatch(limit: 200))
        let restarted = try SyncManager(connection: f.db, deviceID: f.device, entities: [CloudStoreNote.self], schemaVersion: 1)
        try restarted.startTracking()
        let replay = try #require(try restarted.nextBatch(limit: 200))
        #expect(replay.items[0].change.id == original.items[0].change.id)
        #expect(replay.items[0].change.payload == original.items[0].change.payload)
        _ = try restarted.commit(replay, incoming: [f.receipt(replay.items[0])])
        #expect(try restarted.state().pushCursor == 1)
        #expect(try f.log().count == 1)
    }

    @Test("Unsupported events block at their sequence and never stop local writes")
    func blockedEvent() throws {
        let f = try CloudStoreFixture(); let note = try f.insert("valid")
        let invalid = try f.remote(note, time: 20, schema: 2).change
        try SyncLogStorage.append(ChangeLog(id: invalid.id, entityType: invalid.entityType, syncKey: invalid.syncKey,
            operation: invalid.operation, payload: invalid.payload, deviceId: invalid.deviceId, logicalClock: 20,
            schemaVersion: 2, createdAt: invalid.createdAt, updatedAt: invalid.createdAt), to: f.db)
        let batch = try #require(try f.manager.nextBatch(limit: 200))
        #expect(batch.events.map(\.seq) == [1])
        _ = try f.manager.commit(batch, incoming: batch.items.map(f.receipt))
        #expect(throws: SyncError.self) { try f.manager.nextBatch(limit: 200) }
        _ = try f.insert("still writable")
        #expect(try f.log().count == 3 && f.manager.state().pushCursor == 1)
    }
}
