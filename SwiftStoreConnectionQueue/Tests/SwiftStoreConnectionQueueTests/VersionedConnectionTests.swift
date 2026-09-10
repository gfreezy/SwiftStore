import Foundation
import Testing
import SwiftStoreCore
import SwiftStoreConnectionQueue

@Suite("Versioned ConnectionManager setup")
struct VersionedConnectionTests {
    private func history() -> [StoreMigration] {
        let schema = SchemaSnapshot(entities: [ConnectionSyncNote.self])
        return [StoreMigration(id: "001", checksum: "initial", target: schema) { db in
            for sql in schema.creationStatements { try db.execute(sql) }
        }]
    }

    @Test("Preview can be followed by migration and normal read/write")
    func previewAndApply() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = try ConnectionManager(path: directory.appendingPathComponent("store.sqlite").path,
                                            entities: [ConnectionSyncNote.self])
        #expect(try await manager.previewMigrations(history()) == ["001"])
        try await manager.migrate(migrations: history())
        try await manager.write { try $0.insert(ConnectionSyncNote(title: "ready")) }
        #expect(try await manager.read { try $0.queryScalar("SELECT COUNT(*) FROM connection_sync_note", type: Int.self) } == 1)
        #expect(try await manager.previewMigrations(history()).isEmpty)
    }

    @Test("A local store maintains updated_at without enabling sync")
    func localUpdateTimestamp() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = try ConnectionManager(path: directory.appendingPathComponent("store.sqlite").path,
                                            entities: [ConnectionSyncNote.self])
        try await manager.migrate(migrations: history())
        try await manager.write { db in
            try db.execute("INSERT INTO connection_sync_note (id, title, created_at, updated_at) VALUES (randomblob(16), 'before', 123, 123)")
            try db.execute("UPDATE connection_sync_note SET title = 'after'")
            let timestamp = try db.queryScalar("SELECT updated_at FROM connection_sync_note", type: Double.self)
            #expect(abs((timestamp ?? 0) - Date().timeIntervalSince1970) < 5)
            try db.execute("UPDATE connection_sync_note SET title = 'imported', updated_at = 456.875")
            #expect(try db.queryScalar("SELECT updated_at FROM connection_sync_note", type: Double.self) == 456.875)
        }
    }

    @Test("Default and explicit baselines work for legacy, fresh and already tracked databases",
          arguments: [Optional<String>.none, "001"])
    func baselineConfiguration(baselineID: String?) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = history()[0].target
        let migrations = [
            StoreMigration(id: "001", checksum: "initial", target: schema) { db in
                for sql in schema.creationStatements { try db.execute(sql) }
                try db.insert(ConnectionSyncNote(title: "fresh"))
            },
            StoreMigration(id: "002", checksum: "update", target: schema) { db in
                try db.execute("UPDATE connection_sync_note SET title = title || '!'")
            }
        ]
        for legacy in [false, true] {
            let path = directory.appendingPathComponent("store-\(legacy).sqlite").path
            if legacy {
                let db = try SQLiteConnection(path: path)
                for sql in history()[0].target.creationStatements { try db.execute(sql) }
                try db.insert(ConnectionSyncNote(title: "legacy"))
            }
            for _ in 0..<2 {
                let manager = try ConnectionManager(path: path, entities: [ConnectionSyncNote.self])
                try await manager.migrate(migrations: migrations, adoptingBaseline: baselineID)
                try await manager.read { db throws -> Void in
                    #expect(try db.queryScalar("SELECT COUNT(*) FROM connection_sync_note", type: Int.self) == 1)
                    #expect(try db.queryScalar("SELECT title FROM connection_sync_note", type: String.self) == (legacy ? "legacy!" : "fresh!"))
                    #expect(try db.queryScalar("SELECT COUNT(*) FROM __swiftstore_migrations", type: Int.self) == 2)
                }
            }
        }
    }

    @Test("A legacy schema at a later version requires an explicit baseline")
    func laterBaseline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("store.sqlite").path
        let db = try SQLiteConnection(path: path)
        let schema = history()[0].target
        for sql in schema.creationStatements { try db.execute(sql) }
        try db.insert(ConnectionSyncNote(title: "legacy"))
        let initial = SchemaSnapshot(tables: schema.tables + [
            TableSchema(name: "legacy_metadata", columns: [ColumnSchema(name: "value", type: "TEXT")])
        ])
        let migrations = [
            StoreMigration(id: "001", checksum: "initial", target: initial) { db in
                for sql in initial.creationStatements { try db.execute(sql) }
            },
            StoreMigration(id: "002", checksum: "remove_metadata", target: schema) { db in
                try db.execute("DROP TABLE legacy_metadata")
            },
            StoreMigration(id: "003", checksum: "update", target: schema) { db in
                try db.execute("UPDATE connection_sync_note SET title = title || '!'")
            }
        ]

        let defaultManager = try ConnectionManager(path: path, entities: [ConnectionSyncNote.self])
        do {
            try await defaultManager.migrate(migrations: migrations)
            Issue.record("Expected the first baseline to reject a mismatched schema")
        } catch VersionedMigrationError.schemaMismatch {
            // The default must not search for a later matching version.
        }
        #expect(try !db.tableExists("__swiftstore_migrations"))
        #expect(try db.queryScalar("SELECT title FROM connection_sync_note", type: String.self) == "legacy")

        let explicitManager = try ConnectionManager(path: path, entities: [ConnectionSyncNote.self])
        try await explicitManager.migrate(migrations: migrations, adoptingBaseline: "002")
        #expect(try db.queryScalar("SELECT title FROM connection_sync_note", type: String.self) == "legacy!")
        #expect(try db.queryScalar("SELECT COUNT(*) FROM __swiftstore_migrations", type: Int.self) == 3)
    }

    @Test("An unknown explicit baseline is rejected before executing migrations")
    func unknownBaseline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("store.sqlite").path
        let manager = try ConnectionManager(path: path, entities: [ConnectionSyncNote.self])
        await #expect(throws: VersionedMigrationError.self) {
            try await manager.migrate(migrations: history(), adoptingBaseline: "unknown")
        }
        let db = try SQLiteConnection(path: path)
        #expect(try !db.tableExists("connection_sync_note"))
        #expect(try !db.tableExists("__swiftstore_migrations"))
    }

    @Test("A failed migration propagates to waiting readers")
    func failedSetup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = try ConnectionManager(path: directory.appendingPathComponent("store.sqlite").path,
                                            entities: [ConnectionSyncNote.self])
        let bad = StoreMigration(id: "bad", checksum: "bad", target: history()[0].target) { db in
            try db.execute("INVALID SQL")
        }
        await #expect(throws: (any Error).self) { try await manager.migrate(migrations: [bad]) }
        await #expect(throws: (any Error).self) { try await manager.read { try $0.tableExists("connection_sync_note") } }
    }
}
