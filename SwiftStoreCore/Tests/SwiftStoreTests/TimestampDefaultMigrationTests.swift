import Foundation
import Testing
@testable import SwiftStoreCore

@Suite("Versioned timestamp default migration")
struct TimestampDefaultMigrationTests {
    private func snapshot(defaultValue: String) -> SchemaSnapshot {
        SchemaSnapshot(tables: [TableSchema(name: "test_tag", columns: [
            ColumnSchema(name: "id", type: "BLOB", isPrimaryKey: true),
            ColumnSchema(name: "name", type: "TEXT", defaultValue: "''"),
            ColumnSchema(name: "created_at", type: "REAL", defaultValue: defaultValue),
            ColumnSchema(name: "updated_at", type: "REAL", defaultValue: defaultValue)
        ])])
    }

    private func history(fail: Bool = false) -> [StoreMigration] {
        let initial = snapshot(defaultValue: "(strftime('%s', 'now'))")
        let target = snapshot(defaultValue: "(COALESCE(unixepoch('subsec'), CAST(strftime('%s', 'now') AS REAL) + CAST(substr(strftime('%f', 'now'), 3) AS REAL)))")
        return [
            StoreMigration(id: "001_initial", checksum: "initial", target: initial) { db in
                for sql in initial.creationStatements { try db.execute(sql) }
            },
            StoreMigration(id: "002_defaults", checksum: "defaults", target: target) { db in
                // Historical SQL deliberately rebuilds the table rather than editing sqlite_master.
                try db.execute("""
                    CREATE TABLE replacement (
                        id BLOB NOT NULL PRIMARY KEY, name TEXT NOT NULL DEFAULT '',
                        created_at REAL NOT NULL DEFAULT (COALESCE(unixepoch('subsec'), CAST(strftime('%s', 'now') AS REAL) + CAST(substr(strftime('%f', 'now'), 3) AS REAL))),
                        updated_at REAL NOT NULL DEFAULT (COALESCE(unixepoch('subsec'), CAST(strftime('%s', 'now') AS REAL) + CAST(substr(strftime('%f', 'now'), 3) AS REAL)))
                    )
                    """)
                try db.execute("INSERT INTO replacement SELECT id, name, created_at, updated_at FROM test_tag")
                try db.execute("DROP TABLE test_tag")
                if fail { try db.execute("INVALID SQL") }
                try db.execute("ALTER TABLE replacement RENAME TO test_tag")
            }
        ]
    }

    @Test("Explicit default upgrade preserves timestamps and refreshes other connections")
    func existingDatabase() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        let writer = try SQLiteConnection(path: path)
        let migrations = history()
        try VersionedMigrator(connection: writer, migrations: Array(migrations.prefix(1))).migrate()
        try writer.execute("INSERT INTO test_tag VALUES (X'01', 'original', 123.125, 456.875)")
        let reader = try SQLiteConnection(path: path)
        _ = try reader.tableInfo("test_tag")
        let runner = VersionedMigrator(connection: writer, migrations: migrations)
        try runner.migrate()
        try runner.migrate()
        #expect(try runner.pendingMigrationIDs().isEmpty)
        for connection in [writer, reader, try SQLiteConnection(path: path)] {
            #expect(try connection.queryScalar("SELECT created_at FROM test_tag WHERE id = X'01'", type: Double.self) == 123.125)
            #expect(try connection.queryScalar("SELECT updated_at FROM test_tag WHERE id = X'01'", type: Double.self) == 456.875)
            try connection.execute("INSERT INTO test_tag (id, name) VALUES (randomblob(16), 'new')")
            let created: Double = try #require(try connection.queryScalar("SELECT created_at FROM test_tag WHERE name = 'new' ORDER BY rowid DESC LIMIT 1"))
            #expect(abs(created - Date().timeIntervalSince1970) < 5)
            #expect(try connection.queryScalar("SELECT typeof(created_at) FROM test_tag WHERE name = 'new' LIMIT 1", type: String.self) == "real")
        }
    }

    @Test("Failed rebuild rolls back schema, data and migration history")
    func rollback() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        let migrations = history()
        try VersionedMigrator(connection: connection, migrations: Array(migrations.prefix(1))).migrate()
        try connection.execute("INSERT INTO test_tag VALUES (X'01', 'original', 123.125, 456.875)")
        #expect(throws: (any Error).self) {
            try VersionedMigrator(connection: connection, migrations: history(fail: true)).migrate()
        }
        try migrations[0].target.verify(on: connection)
        #expect(try !connection.tableExists("replacement"))
        #expect(try connection.queryScalar("SELECT name FROM test_tag", type: String.self) == "original")
        #expect(try VersionedMigrator(connection: connection, migrations: migrations).pendingMigrationIDs() == ["002_defaults"])
    }

    @Test("Schema drift is rejected before running the default migration")
    func drift() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        let migrations = history()
        try VersionedMigrator(connection: connection, migrations: Array(migrations.prefix(1))).migrate()
        try connection.execute("ALTER TABLE test_tag ADD COLUMN later TEXT")
        #expect(throws: VersionedMigrationError.self) {
            try VersionedMigrator(connection: connection, migrations: migrations).migrate()
        }
        #expect(try connection.tableInfo("test_tag").contains { $0["name"] as? String == "later" })
    }
}
