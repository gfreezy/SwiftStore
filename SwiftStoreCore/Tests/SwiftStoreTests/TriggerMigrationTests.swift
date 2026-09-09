import Foundation
import Testing
@testable import SwiftStoreCore

@Suite("Versioned trigger migration")
struct TriggerMigrationTests {
    private var legacyTrigger: TriggerSchema {
        TriggerSchema(name: "__swiftstore_update_test_tag", event: .update, timing: .after,
            condition: "NEW.updated_at = OLD.updated_at", body: "", sql: """
            CREATE TRIGGER __swiftstore_update_test_tag AFTER UPDATE ON test_tag
            FOR EACH ROW WHEN NEW.updated_at = OLD.updated_at BEGIN
                UPDATE test_tag SET updated_at = strftime('%s', 'now') WHERE rowid = NEW.rowid;
            END
            """)
    }

    private func snapshot(trigger: TriggerSchema) -> SchemaSnapshot {
        SchemaSnapshot(tables: [TableSchema(name: "test_tag", columns: [
            ColumnSchema(name: "id", type: "BLOB", isPrimaryKey: true),
            ColumnSchema(name: "name", type: "TEXT", defaultValue: "''"),
            ColumnSchema(name: "created_at", type: "REAL", defaultValue: "0"),
            ColumnSchema(name: "updated_at", type: "REAL", defaultValue: "0")
        ], triggers: [trigger, TriggerSchema(name: "user_tag_trigger", event: .insert, timing: .after,
            body: "SELECT 1;", sql: "CREATE TRIGGER user_tag_trigger AFTER INSERT ON test_tag BEGIN SELECT 1; END")])])
    }

    private func history(fail: Bool = false) -> [StoreMigration] {
        let initial = snapshot(trigger: legacyTrigger)
        let replacement = DatabaseSchemaBuilder.updateTrigger(for: "test_tag")
        return [
            StoreMigration(id: "001_initial", checksum: "initial", target: initial) { db in
                for sql in initial.creationStatements { try db.execute(sql) }
            },
            StoreMigration(id: "002_trigger", checksum: "trigger", target: snapshot(trigger: replacement)) { db in
                try db.execute("DROP TRIGGER __swiftstore_update_test_tag")
                if fail { try db.execute("INVALID SQL") }
                try db.execute(replacement.sql)
            }
        ]
    }

    private func triggerSQL(_ connection: SQLiteConnection) throws -> String {
        try #require(try connection.queryScalar(
            "SELECT sql FROM sqlite_master WHERE name = '__swiftstore_update_test_tag'"))
    }

    @Test("Explicit trigger upgrade preserves data and other triggers and runs once")
    func upgrade() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        let migrations = history()
        try VersionedMigrator(connection: connection, migrations: Array(migrations.prefix(1))).migrate()
        let before = try triggerSQL(connection)
        try connection.execute("INSERT INTO test_tag VALUES (X'01', 'before', 123.125, 123.125)")
        let runner = VersionedMigrator(connection: connection, migrations: migrations)
        #expect(try runner.pendingMigrationIDs() == ["002_trigger"])
        #expect(try triggerSQL(connection) == before)
        try connection.transaction { try runner.migrate() }
        try runner.migrate()
        #expect(try runner.pendingMigrationIDs().isEmpty)
        #expect(try connection.queryScalar("SELECT COUNT(*) FROM sqlite_master WHERE name = 'user_tag_trigger'", type: Int.self) == 1)
        #expect(try connection.queryScalar("SELECT updated_at FROM test_tag", type: Double.self) == 123.125)
        try connection.execute("UPDATE test_tag SET name = 'after'")
        let updated: Double = try #require(try connection.queryScalar("SELECT updated_at FROM test_tag"))
        #expect(abs(updated - Date().timeIntervalSince1970) < 5)
        #expect(try connection.queryScalar("SELECT typeof(updated_at) FROM test_tag", type: String.self) == "real")
        try connection.execute("UPDATE test_tag SET updated_at = 456.875")
        #expect(try connection.queryScalar("SELECT updated_at FROM test_tag", type: Double.self) == 456.875)
    }

    @Test("Failure after DROP restores the old trigger and history")
    func rollback() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try VersionedMigrator(connection: connection, migrations: Array(history().prefix(1))).migrate()
        let before = try triggerSQL(connection)
        #expect(throws: (any Error).self) {
            try VersionedMigrator(connection: connection, migrations: history(fail: true)).migrate()
        }
        #expect(try triggerSQL(connection) == before)
        #expect(try VersionedMigrator(connection: connection, migrations: history()).pendingMigrationIDs() == ["002_trigger"])
    }

    @Test("Timestamp expression stores fractional Unix seconds")
    func fractionalSeconds() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        let trigger = DatabaseSchemaBuilder.updateTrigger(for: "test_tag")
        let expression = try #require(trigger.body.components(separatedBy: "SET updated_at = ").last?
            .components(separatedBy: "\n").first)
            .replacingOccurrences(of: "'subsec'", with: "'2024-01-01 00:00:12.125', 'subsec'")
        #expect(try connection.queryScalar("SELECT \(expression)", type: Double.self) == 1704067212.125)
    }
}
