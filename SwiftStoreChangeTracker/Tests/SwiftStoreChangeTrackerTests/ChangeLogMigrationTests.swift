import Foundation
import Testing
import SwiftStoreCore
@testable import SwiftStoreChangeTracker

@Suite("Changelog versioned setup")
struct ChangeLogMigrationTests {
    @Test("Frozen history matches the current changelog schema")
    func schemaParity() throws {
        let latest = try #require(ChangeLogMigrations.all().last)
        // The internal append-only log uses a manually frozen schema without update triggers.
        let tables = DatabaseSchemaBuilder().buildSchemas(from: [ChangeLog.self]).map { table in
            TableSchema(name: table.name, columns: table.columns, indexes: table.indexes,
                        foreignKeys: table.foreignKeys)
        }
        #expect(latest.target == SchemaSnapshot(tables: tables))
    }

    @Test("Legacy changelog rows survive baseline adoption and repeated startup")
    func legacyBaseline() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("changes.sqlite").path
        let db = try SQLiteConnection(path: path)
        let migrations = try ChangeLogMigrations.all()
        for sql in migrations[0].target.creationStatements { try db.execute(sql) }
        let deviceId = UUIDV7()
        let log = ChangeLog(entityType: "test_entity", syncKey: Data([1]), operation: .insert,
            payload: nil, deviceId: deviceId, logicalClock: 42, schemaVersion: 1)
        try db.insert(log)
        let main = try SQLiteConnection(path: ":memory:")
        for _ in 0..<2 {
            let tracker = try ChangeTracker(connection: main, changeLogDbPath: path,
                deviceId: deviceId, registeredEntities: [], tickClock: { 1 })
            #expect(try ChangeLog.count(tracker.connection) == 1)
            #expect(try ChangeLog.first(tracker.connection)?.id == log.id)
            #expect(try VersionedMigrator(connection: tracker.connection, migrations: migrations).pendingMigrationIDs().isEmpty)
        }
    }

    @Test("Mismatched legacy changelog fails without recording a baseline")
    func mismatchedBaseline() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("changes.sqlite").path
        let db = try SQLiteConnection(path: path)
        try db.execute("CREATE TABLE change_log (id BLOB PRIMARY KEY)")
        let main = try SQLiteConnection(path: ":memory:")
        #expect(throws: VersionedMigrationError.self) {
            _ = try ChangeTracker(connection: main, changeLogDbPath: path,
                deviceId: UUIDV7(), registeredEntities: [], tickClock: { 1 })
        }
        #expect(try !db.tableExists("__swiftstore_migrations"))
        #expect(try db.tableInfo("change_log").count == 1)
    }
}
