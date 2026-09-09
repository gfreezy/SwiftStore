import Foundation
import Testing
@testable import SwiftStoreCore

@Suite("Trigger migration")
struct TriggerMigrationTests {
    private func legacyDatabase() throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: ":memory:")
        let migrator = Migrator(connection: connection)
        try migrator.apply(migrator.plan(for: [TestTag.self]))
        try connection.execute("DROP TRIGGER __swiftstore_update_test_tag")
        try connection.execute("""
            CREATE TRIGGER __swiftstore_update_test_tag AFTER UPDATE ON test_tag
            FOR EACH ROW WHEN NEW.updated_at = OLD.updated_at BEGIN
                UPDATE test_tag SET updated_at = strftime('%s', 'now') WHERE rowid = NEW.rowid;
            END
            """)
        return connection
    }

    private func triggerSQL(_ connection: SQLiteConnection) throws -> String {
        try #require(try connection.queryScalar(
            "SELECT sql FROM sqlite_master WHERE name = '__swiftstore_update_test_tag'"))
    }

    @Test("Normal migration previews and upgrades timestamp triggers exactly once")
    func upgrade() throws {
        let connection = try legacyDatabase()
        let before = try triggerSQL(connection)
        try connection.execute("""
            INSERT INTO test_tag (id, name, created_at, updated_at)
            VALUES (X'01', 'before', 123.125, 123.125)
            """)
        try connection.execute("""
            CREATE TRIGGER user_tag_trigger AFTER INSERT ON test_tag BEGIN SELECT 1; END
            """)
        let migrator = Migrator(connection: connection)
        let diff = try migrator.diff(for: [TestTag.self])
        #expect(diff.hasChanges)
        #expect(diff.triggersToReplaceCount == 1)
        #expect(diff.triggersToAddCount == 0)
        let plan = try migrator.plan(for: [TestTag.self])
        #expect(plan.statements.count == 2)
        #expect(plan.statements[0] == "DROP TRIGGER \"__swiftstore_update_test_tag\"")
        #expect(plan.statements[1].contains("(COALESCE(unixepoch('subsec'), CAST(strftime('%s', 'now') AS REAL) + CAST(substr(strftime('%f', 'now'), 3) AS REAL)))"))
        #expect(try triggerSQL(connection) == before) // Planning is read-only.

        // Applying inside an existing transaction must work too (ConnectionManager).
        try connection.transaction { try migrator.apply(plan) }
        #expect(try !migrator.plan(for: [TestTag.self]).hasChanges)
        let customCount: Int64? = try connection.queryScalar(
            "SELECT COUNT(*) FROM sqlite_master WHERE name = 'user_tag_trigger'")
        #expect(customCount == 1)
        let preserved: Double? = try connection.queryScalar("SELECT updated_at FROM test_tag")
        #expect(preserved == 123.125)
        try connection.execute("UPDATE test_tag SET name = 'after'")
        let updated: Double = try #require(try connection.queryScalar("SELECT updated_at FROM test_tag"))
        #expect(abs(updated - Date().timeIntervalSince1970) < 5)
        let storage: String? = try connection.queryScalar("SELECT typeof(updated_at) FROM test_tag")
        #expect(storage == "real")
        // Explicit remote timestamps must survive the automatic trigger.
        try connection.execute("UPDATE test_tag SET updated_at = 456.875")
        let explicit: Double? = try connection.queryScalar("SELECT updated_at FROM test_tag")
        #expect(explicit == 456.875)
    }

    @Test("A failed migration restores the old trigger")
    func rollback() throws {
        let connection = try legacyDatabase()
        let before = try triggerSQL(connection)
        let migrator = Migrator(connection: connection)
        let plan = try migrator.plan(for: [TestTag.self])
        // Fail after DROP, before the replacement can be created.
        let broken = MigrationPlan(statements: [plan.statements[0], "INVALID SQL"])
        #expect(throws: (any Error).self) { try migrator.apply(broken) }
        #expect(try triggerSQL(connection) == before)
        try migrator.apply(plan)
        #expect(try !migrator.plan(for: [TestTag.self]).hasChanges)
    }

    @Test("Disabled update triggers are not upgraded")
    func disabled() throws {
        let connection = try legacyDatabase()
        let migrator = Migrator(connection: connection, createUpdateTrigger: false)
        #expect(try !migrator.plan(for: [TestTag.self]).hasChanges)
    }

    @Test("Timestamp expression stores fractional Unix seconds")
    func fractionalSeconds() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        let schema = try #require(DatabaseSchemaBuilder().buildSchemas(from: [TestTag.self]).first)
        let trigger = try #require(schema.triggers.first)
        // Use a fixed time so a test running on a whole-second boundary is reliable.
        let expression = try #require(trigger.body.components(separatedBy: "SET updated_at = ").last?
            .components(separatedBy: "\n").first)
            .replacingOccurrences(of: "'subsec'", with: "'2024-01-01 00:00:12.125', 'subsec'")
        let seconds: Double? = try connection.queryScalar("SELECT \(expression)")
        #expect(seconds == 1704067212.125)
    }
}
