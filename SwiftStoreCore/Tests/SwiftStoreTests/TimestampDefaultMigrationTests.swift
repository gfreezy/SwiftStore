import Foundation
import Testing
@testable import SwiftStoreCore

@Suite("Timestamp default migration")
struct TimestampDefaultMigrationTests {
    private func createLegacy(_ connection: SQLiteConnection) throws {
        try connection.execute("""
            CREATE TABLE parent (id TEXT PRIMARY KEY);
            INSERT INTO parent VALUES ('parent');
            CREATE TABLE test_tag (
                id BLOB NOT NULL PRIMARY KEY,
                name TEXT NOT NULL DEFAULT '',
                created_at REAL NOT NULL DEFAULT (strftime('%s', 'now')),
                "updated_at" REAL NOT NULL DEFAULT (STRFTIME( '%s', 'now' )),
                parent_id TEXT REFERENCES parent(id),
                extra TEXT NOT NULL DEFAULT 'DEFAULT (strftime(''%s'', ''now''))',
                length INTEGER GENERATED ALWAYS AS (length(name)) VIRTUAL,
                CHECK (length(name) < 100)
            );
            CREATE INDEX custom_tag_index ON test_tag(name) WHERE name <> '';
            CREATE VIEW custom_tag_view AS SELECT id, name FROM test_tag;
            CREATE TRIGGER custom_tag_trigger AFTER INSERT ON test_tag BEGIN SELECT 1; END;
            INSERT INTO test_tag (id, name, created_at, updated_at, parent_id)
            VALUES (X'01', 'original', 123.125, 456.875, 'parent');
            """)
    }

    private func assertDefaults(_ connection: SQLiteConnection) throws {
        let columns = try connection.tableInfo("test_tag")
        for name in ["created_at", "updated_at"] {
            let value = columns.first { $0["name"] as? String == name }?["dflt_value"] as? String
            #expect(value == "COALESCE(unixepoch('subsec'), CAST(strftime('%s', 'now') AS REAL) + CAST(substr(strftime('%f', 'now'), 3) AS REAL))")
        }
        try connection.execute("INSERT INTO test_tag (id, name) VALUES (randomblob(16), 'new')")
        let created: Double = try #require(try connection.queryScalar(
            "SELECT created_at FROM test_tag WHERE name = 'new' ORDER BY rowid DESC LIMIT 1"))
        #expect(abs(created - Date().timeIntervalSince1970) < 5)
        let storage: String? = try connection.queryScalar(
            "SELECT typeof(created_at) || ',' || typeof(updated_at) FROM test_tag WHERE name = 'new' LIMIT 1")
        #expect(storage == "real,real")
    }

    @Test("Old defaults upgrade without changing data, constraints, or other schema objects")
    func existingDatabase() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        let writer = try SQLiteConnection(path: path)
        try createLegacy(writer)
        let reader = try SQLiteConnection(path: path)
        // Populate the second connection's schema cache before upgrading.
        _ = try reader.tableInfo("test_tag")
        let migrator = Migrator(connection: writer)
        let plan = try migrator.plan(for: [TestTag.self])
        #expect(plan.statements.contains { $0.hasPrefix("UPDATE sqlite_master") })
        let oldSQL: String? = try writer.queryScalar("SELECT sql FROM sqlite_master WHERE name = 'test_tag'")
        #expect(oldSQL?.contains("DEFAULT (strftime('%s', 'now'))") == true)
        try writer.transaction { try migrator.apply(plan) }
        try assertDefaults(writer)
        try assertDefaults(reader)
        try assertDefaults(SQLiteConnection(path: path))
        #expect(try !migrator.plan(for: [TestTag.self]).hasChanges)
        let created: Double? = try writer.queryScalar("SELECT created_at FROM test_tag WHERE id = X'01'")
        let updated: Double? = try writer.queryScalar("SELECT updated_at FROM test_tag WHERE id = X'01'")
        #expect(created == 123.125)
        #expect(updated == 456.875)
        let extra: String? = try writer.queryScalar("SELECT extra FROM test_tag WHERE id = X'01'")
        #expect(extra == "DEFAULT (strftime('%s', 'now'))")
        let objects: Int64? = try writer.queryScalar("SELECT COUNT(*) FROM sqlite_master WHERE name LIKE 'custom_tag_%'")
        #expect(objects == 3)
        let length: Int64? = try writer.queryScalar("SELECT length FROM test_tag WHERE id = X'01'")
        #expect(length == 8)
        #expect(throws: (any Error).self) {
            try writer.execute("INSERT INTO test_tag (id, parent_id) VALUES (X'02', 'missing')")
        }
        let integrity: String? = try writer.queryScalar("PRAGMA integrity_check")
        #expect(integrity == "ok")
    }

    @Test("Newly added timestamps retain dynamic defaults after backfill")
    func addedColumns() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try connection.execute("CREATE TABLE test_tag (id BLOB PRIMARY KEY NOT NULL, name TEXT NOT NULL DEFAULT '')")
        try connection.execute("INSERT INTO test_tag VALUES (X'01', 'existing')")
        let migrator = Migrator(connection: connection)
        try migrator.apply(migrator.plan(for: [TestTag.self]))
        try assertDefaults(connection)
        let backfill: Double? = try connection.queryScalar("SELECT updated_at FROM test_tag WHERE id = X'01'")
        #expect((backfill ?? 0) > 1_700_000_000)
        #expect(try !migrator.plan(for: [TestTag.self]).hasChanges)
    }

    @Test("Failed default migration restores schema and disables schema editing")
    func rollback() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try createLegacy(connection)
        let before: String? = try connection.queryScalar("SELECT sql FROM sqlite_master WHERE name = 'test_tag'")
        let migrator = Migrator(connection: connection)
        let plan = try migrator.plan(for: [TestTag.self])
        let broken = MigrationPlan(statements: plan.statements.dropLast() + ["INVALID SQL"],
            expectedSchemaVersion: plan.expectedSchemaVersion)
        #expect(throws: (any Error).self) { try migrator.apply(broken) }
        let after: String? = try connection.queryScalar("SELECT sql FROM sqlite_master WHERE name = 'test_tag'")
        #expect(after == before)
        let enabled: Int64? = try connection.queryScalar("PRAGMA writable_schema")
        #expect(enabled == 0)
        try migrator.apply(plan)
        try assertDefaults(connection)
    }

    @Test("A schema change after planning invalidates a default migration plan")
    func stalePlan() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try createLegacy(connection)
        let migrator = Migrator(connection: connection)
        let plan = try migrator.plan(for: [TestTag.self])
        try connection.execute("ALTER TABLE test_tag ADD COLUMN later TEXT")
        #expect(throws: TimestampDefaultMigration.Failure.stalePlan) { try migrator.apply(plan) }
        try migrator.apply(migrator.plan(for: [TestTag.self]))
        #expect(try connection.tableInfo("test_tag").contains { $0["name"] as? String == "later" })
    }
}
