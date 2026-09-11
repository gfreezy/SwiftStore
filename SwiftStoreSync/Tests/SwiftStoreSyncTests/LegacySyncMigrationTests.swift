import Foundation
import Testing
import SwiftStoreCore
import SwiftStoreChangeTracker
@testable import SwiftStoreSync

private struct ImportJournal: Encodable {
    let accountID = "original-account"
    let namespace = "container/zone/type"
    var queuedPush: [SyncChange] = []
    var inbox: [SyncChange] = []
    var didCreateZone = true
}

private final class ImportFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let db: SQLiteConnection
    let old: SQLiteConnection
    let migration: LegacySyncMigration
    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        migration = LegacySyncMigration(changeLogDatabase: directory.appendingPathComponent("old.sqlite"),
            cloudKitJournal: directory.appendingPathComponent("journal.plist"), backupDirectory: directory.appendingPathComponent("backups"))
        db = try SQLiteConnection(path: directory.appendingPathComponent("business.sqlite").path)
        old = try SQLiteConnection(path: migration.changeLogDatabase.path)
        for sql in SchemaSnapshot(entities: [CloudStoreNote.self]).creationStatements { try db.execute(sql) }
        try old.execute("""
            CREATE TABLE change_log(id BLOB PRIMARY KEY,entity_type TEXT,sync_key BLOB,operation TEXT,payload TEXT,
                device_id BLOB,logical_clock INTEGER,schema_version INTEGER,created_at REAL,updated_at REAL)
            """)
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
    func change(_ note: CloudStoreNote, deletion: Bool = false) throws -> SyncChange {
        SyncChange(id: UUIDV7(), entityType: CloudStoreNote.tableName,
            syncKey: SyncKeyEncoder.encode([.blob(note.id.data)]), operation: deletion ? .delete : .update,
            payload: deletion ? nil : String(decoding: try JSONEncoder().encode(note), as: UTF8.self),
            deviceId: UUIDV7(), logicalClock: Int64(note.updatedAt.timeIntervalSince1970 * 1000), schemaVersion: 1, createdAt: note.updatedAt)
    }
    func appendOld(_ change: SyncChange) throws {
        try old.execute("INSERT INTO change_log VALUES(?,?,?,?,?,?,?,?,?,?)", values: [
            .blob(change.id.data), .text(change.entityType), .blob(change.syncKey),
            .text(String(decoding: try JSONEncoder().encode(change.operation), as: UTF8.self)),
            change.payload.map(SQLiteValue.text) ?? .null, .blob(change.deviceId.data), .integer(change.logicalClock),
            .integer(Int64(change.schemaVersion)), .real(change.createdAt.timeIntervalSince1970), .real(change.createdAt.timeIntervalSince1970)])
    }
    func manager(_ journal: ImportJournal) throws -> SyncManager {
        try PropertyListEncoder().encode(journal).write(to: migration.cloudKitJournal)
        return try SyncManager(connection: db, deviceID: UUIDV7(), entities: [CloudStoreNote.self], schemaVersion: 1,
            migration: migration, scope: journal.namespace, now: { 1 })
    }
}

@Suite("Legacy CloudKit migration")
struct LegacySyncMigrationTests {
    @Test("Backups retain originals; pending IDs, uncovered rows, inbox and tombstones migrate once")
    func importPreservesWork() throws {
        let f = try ImportFixture()
        var local = CloudStoreNote(title: "local", updatedAt: Date(timeIntervalSince1970: 10))
        let original = try f.change(local); try f.appendOld(original)
        // A business write can be newer than its old separate-database log.
        local.value = 8; local.updatedAt = Date(timeIntervalSince1970: 15); try f.db.insert(local)
        let deleted = CloudStoreNote(title: "deleted", updatedAt: Date(timeIntervalSince1970: 12))
        let deletion = try f.change(deleted, deletion: true); try f.appendOld(deletion)
        let queued = try f.change(CloudStoreNote(title: "queued", updatedAt: Date(timeIntervalSince1970: 18)))
        let remote = try f.change(CloudStoreNote(title: "downloaded", updatedAt: Date(timeIntervalSince1970: 20)))
        let tombstone = CloudStoreNote(title: "old tombstone")
        let key = SyncKeyEncoder.encode([.blob(tombstone.id.data)])
        try f.db.execute("CREATE TABLE __swiftstore_sync_tombstones(key TEXT PRIMARY KEY,deleted_at REAL NOT NULL)")
        try f.db.execute("INSERT INTO __swiftstore_sync_tombstones VALUES(?,50)",
            values: [.text(CloudStoreNote.tableName + ":" + key.base64EncodedString())])
        let manager = try f.manager(ImportJournal(queuedPush: [original, queued], inbox: [remote]))
        let originalJournal = try Data(contentsOf: f.migration.cloudKitJournal)
        try manager.startTracking()
        let log = try ChangeTrackerReader(connection: f.db).changes(after: 0, limit: 100)
        #expect(log.count == 4)
        #expect(Set(log.prefix(3).map(\.id)) == Set([original.id, deletion.id, queued.id]))
        let captured = try JSONDecoder().decode(CloudStoreNote.self, from: Data(#require(log.last?.payload).utf8))
        #expect(captured.id == local.id && captured.value == local.value && captured.updatedAt == local.updatedAt)
        #expect(!log.contains { $0.id == remote.id })
        #expect(try CloudStoreNote.all(f.db).map(\.title).sorted() == ["downloaded", "local"])
        let bound = try manager.bind(accountID: "original-account", scope: "container/zone/type", driver: .operations)
        #expect(bound.didCreateZone && bound.state.pushCursor == 0 && bound.checkpoint.data == nil)
        #expect(throws: SyncError.self) { try manager.bind(accountID: "other", scope: "container/zone/type", driver: .operations) }
        try manager.startTracking()
        #expect(try ChangeTrackerReader(connection: f.db).count(after: 0) == 4)
        try f.db.insert(tombstone)
        #expect(try CloudStoreNote.filter(\.id == tombstone.id).first(f.db).map { Int64(($0.updatedAt.timeIntervalSince1970 * 1000).rounded()) } == 50_001)
        #expect(try f.old.queryScalar("SELECT COUNT(*) FROM change_log", type: Int.self) == 2)
        #expect(try Data(contentsOf: f.migration.cloudKitJournal) == originalJournal)
        let backups = try FileManager.default.contentsOfDirectory(at: f.migration.backupDirectory, includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        let backup = try SQLiteConnection(path: backups[0].appendingPathComponent("business.sqlite").path)
        #expect(try !backup.tableExists("__swiftstore_change_log"))
        #expect(try CloudStoreNote.count(backup) == 1)
        #expect(try Data(contentsOf: backups[0].appendingPathComponent("journal.plist")) == originalJournal)
    }

    @Test("Invalid legacy inbox rolls back the entire import and leaves backup available")
    func importRollback() throws {
        let f = try ImportFixture()
        let note = CloudStoreNote(title: "untouched")
        try f.db.insert(note); try f.appendOld(f.change(note))
        var invalid = try f.change(CloudStoreNote(title: "bad"))
        invalid = SyncChange(id: invalid.id, entityType: invalid.entityType, syncKey: invalid.syncKey,
            operation: .update, payload: "broken-json", deviceId: invalid.deviceId, logicalClock: 1, schemaVersion: 1, createdAt: invalid.createdAt)
        let manager = try f.manager(ImportJournal(inbox: [invalid]))
        #expect(throws: (any Error).self) { try manager.startTracking() }
        #expect(try ChangeTrackerReader(connection: f.db).count(after: 0) == 0)
        #expect(try f.db.queryScalar("SELECT legacy_imported FROM __swiftstore_cloud_state", type: Int.self) == 0)
        #expect(try CloudStoreNote.first(f.db)?.title == "untouched")
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.migration.backupDirectory.path).count == 1)
    }
}
