import Foundation
import Testing
import SwiftStoreCore
import SwiftStoreChangeTracker
import SwiftStoreSync
@testable import SwiftStoreConnectionQueue

@Entity
struct ConnectionSyncNote {
    var id: UUIDV7 = UUIDV7()
    var title: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

private final class SeededConnectionManager: ConnectionManager, @unchecked Sendable {
    override func performAdditionalSetup(connection: SQLiteConnection) throws {
        if try ConnectionSyncNote.count(connection) == 0 {
            try connection.insert(ConnectionSyncNote(title: "seeded during setup"))
        }
    }
}

private final class FailingDatabaseSetupManager: ConnectionManager, @unchecked Sendable {
    enum Failure: Error { case intentional }
    override func performAdditionalSetup(connection: SQLiteConnection) throws {
        try connection.insert(ConnectionSyncNote(title: "rolled back setup"))
        throw Failure.intentional
    }
}

@Suite("CloudKit connection writer")
struct ConnectionSyncTests {
    private func options() -> SyncOptions {
        SyncOptions(deviceId: UUIDV7(), schemaVersion: 1,
            cloudKit: .init(containerIdentifier: "iCloud.com.swiftstore.tests", automaticallySync: false))
    }
    private var snapshot: SchemaSnapshot { SchemaSnapshot(entities: [ConnectionSyncNote.self]) }

    @Test("Database setup inserts are tracked before access is released and seeds survive reopening",
          arguments: [false, true])
    func databaseSetupTracksWrites(syncEnabled: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("business.sqlite").path
        let schema = snapshot
        let syncOptions = syncEnabled ? options() : nil
        for _ in 0..<2 {
            let manager = try SeededConnectionManager(path: path, entities: [ConnectionSyncNote.self],
                migrations: [.init(id: "001", target: schema) { db in
                    for sql in schema.creationStatements { try db.execute(sql) }
                }], syncConfig: syncOptions)
            try await manager.read { db in
                #expect(try ConnectionSyncNote.count(db) == 1)
                #expect(try db.queryScalar("SELECT title FROM connection_sync_note", type: String.self) == "seeded during setup")
                if syncEnabled {
                    let events = try ChangeTrackerReader(connection: db).changes(after: 0)
                    #expect(events.count == 1)
                    #expect(events.first?.entityType == "connection_sync_note")
                    #expect(events.first?.operation == .insert)
                    #expect(events.first?.payload?.contains("seeded during setup") == true)
                } else {
                    #expect(try !db.tableExists("__swiftstore_change_log"))
                }
            }
        }
    }

    @Test("Database setup failure rolls back inserted rows and changelog together")
    func databaseSetupRollback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("business.sqlite").path
        let schema = snapshot
        let manager = try FailingDatabaseSetupManager(path: path, entities: [ConnectionSyncNote.self],
            migrations: [.init(id: "001", target: schema) { db in
                for sql in schema.creationStatements { try db.execute(sql) }
            }], syncConfig: options())
        await #expect(throws: FailingDatabaseSetupManager.Failure.self) { try await manager.waitForMigration() }
        await #expect(throws: FailingDatabaseSetupManager.Failure.self) { try await manager.read { try ConnectionSyncNote.count($0) } }
        let db = try SQLiteConnection(path: path)
        #expect(try ConnectionSyncNote.count(db) == 0)
        #expect(try ChangeLog.count(db) == 0)
        #expect(try db.queryScalar("SELECT COUNT(*) FROM __swiftstore_migrations", type: Int.self) == 1)
    }

    @Test("Public CloudKit configuration stores its log and FULL durability in the business database")
    func sameDatabase() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("business.sqlite").path
        let schema = snapshot
        let manager = try ConnectionManager(path: path, entities: [ConnectionSyncNote.self],
            migrations: [.init(id: "001", target: schema) { db in
                for sql in schema.creationStatements { try db.execute(sql) }
            }], syncConfig: options())
        try await manager.write { try $0.insert(ConnectionSyncNote(title: "one")) }
        let counts = try await manager.write { db in
            (try ChangeLog.count(db), try db.queryScalar("PRAGMA synchronous", type: Int.self))
        }
        #expect(counts.0 == 1 && counts.1 == 2)
        #expect(await manager.syncState?.pushCursor == 0)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("business_changelog.sqlite").path))
        await manager.stopSync()
        try await manager.write { try $0.insert(ConnectionSyncNote(title: "two")) }
        #expect(try await manager.read { try ChangeLog.count($0) } == 2)
    }

    @Test("An existing legacy log requires explicit migration instead of silently losing pending deletions")
    func requiresLegacyMigration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = try SQLiteConnection(path: directory.appendingPathComponent("business_changelog.sqlite").path)
        try old.execute("CREATE TABLE pending_deletion(id INTEGER)")
        try old.execute("INSERT INTO pending_deletion VALUES(1)")
        let path = directory.appendingPathComponent("business.sqlite").path
        #expect(throws: ConnectionManagerError.self) {
            try ConnectionManager(path: path, entities: [ConnectionSyncNote.self], syncConfig: options())
        }
        #expect(try old.queryScalar("SELECT COUNT(*) FROM pending_deletion", type: Int.self) == 1)
        let untouched = try SQLiteConnection(path: path)
        #expect(try !untouched.tableExists("__swiftstore_change_log"))
    }

    @Test("An old driver session cannot update the checkpoint after stop")
    func sessionFence() async throws {
        let db = try SQLiteConnection(path: ":memory:")
        for sql in snapshot.creationStatements { try db.execute(sql) }
        let writer = try WritableConnectionActor(connection: db, entities: [ConnectionSyncNote.self], syncConfig: options())
        try await writer.startTracking()
        let session = await writer.cloudSessionID
        _ = try await writer.bindCloudAccount("account", scope: "scope", driver: .operations, session: session)
        await writer.stopSync()
        await #expect(throws: CancellationError.self) {
            try await writer.saveCloudCheckpoint(.init(driver: .operations, data: Data([1])), session: session)
        }
    }

    @Test("Raw transaction rollback cannot publish its uncommitted events to a waiting sync")
    func rawWriterBoundary() async throws {
        let db = try SQLiteConnection(path: ":memory:")
        for sql in snapshot.creationStatements { try db.execute(sql) }
        let writer = try WritableConnectionActor(connection: db, entities: [ConnectionSyncNote.self], syncConfig: options())
        try await writer.startTracking()
        let session = await writer.cloudSessionID
        _ = try await writer.bindCloudAccount("account", scope: "scope", driver: .operations, session: session)
        try await writer.run({ db in
            try db.execute("BEGIN")
            try db.insert(ConnectionSyncNote(title: "uncommitted"))
        }, transaction: false)
        let pending = Task { try await writer.nextCloudBatch(limit: 200, session: session) }
        for _ in 0..<20 { await Task.yield() }
        _ = try await writer.run({ try $0.execute("ROLLBACK") }, transaction: false)
        #expect(try await pending.value == nil)
        #expect(try await writer.run { try ChangeLog.count($0) } == 0)
    }
}
