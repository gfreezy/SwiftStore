import Testing
import Foundation
@testable import SwiftStoreCore

@Suite("Migration Dry Run Tests")
struct MigrationDryRunTests {
    @Test("Plan migration for new table")
    func testPlanMigrationNewTable() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)

        let plan = try store.planMigration(for: TestUser.self)

        #expect(plan.hasChanges == true)
        #expect(plan.statements.count == 2) // CREATE TABLE + 1 index

        let createSQL = plan.statements[0].lowercased()
        #expect(createSQL.contains("create table test_user"))
        #expect(createSQL.contains("id blob"))
        #expect(createSQL.contains("primary key"))
        #expect(createSQL.contains("name text"))
        #expect(createSQL.contains("email text"))

        let indexSQL = plan.statements[1].lowercased()
        #expect(indexSQL.contains("create unique index"))
        #expect(indexSQL.contains("idx_test_user_email"))
    }

    @Test("Plan migration for existing table with no changes")
    func testPlanMigrationNoChanges() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let plan = try store.planMigration(for: TestUser.self)

        #expect(plan.hasChanges == false)
        #expect(plan.statements.isEmpty)
    }

    @Test("Plan migration for existing table with new column")
    func testPlanMigrationNewColumn() throws {
        let store = try createTestStore()

        // Create a minimal table first
        try store.connection.execute("""
            CREATE TABLE test_user (
                id blob PRIMARY KEY,
                name text NOT NULL,
                created_at real NOT NULL,
                updated_at real NOT NULL
            )
        """)

        try store.register(TestUser.self)

        let plan = try store.planMigration(for: TestUser.self)

        #expect(plan.hasChanges == true)

        // Should have ALTER TABLE statements for missing columns
        let script = plan.script
        #expect(script.contains("ALTER TABLE test_user ADD COLUMN email"))
        #expect(script.contains("ALTER TABLE test_user ADD COLUMN age"))
        #expect(script.contains("ALTER TABLE test_user ADD COLUMN address"))
    }

    @Test("Plan migration generates correct script")
    func testPlanMigrationScript() throws {
        let store = try createTestStore()
        try store.register(TestTag.self)

        let plan = try store.planMigration(for: TestTag.self)

        let script = plan.script
        #expect(script.contains("CREATE TABLE test_tag"))
        #expect(script.hasSuffix(";"))
    }

    @Test("Plan migrations for multiple entities")
    func testPlanMigrationsMultiple() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.register(TestTag.self)

        let plan = try store.planMigrations()

        #expect(plan.hasChanges == true)
        // Should have statements for both tables
        let script = plan.script
        #expect(script.contains("CREATE TABLE test_user"))
        #expect(script.contains("CREATE TABLE test_tag"))
    }

    @Test("Generate CREATE TABLE SQL")
    func testGenerateCreateTableSQL() throws {
        let store = try createTestStore()

        let sql = store.generateCreateTableSQL(for: TestTag.self).lowercased()

        #expect(sql.contains("create table test_tag"))
        #expect(sql.contains("id blob"))
        #expect(sql.contains("primary key"))
        #expect(sql.contains("name text"))
        #expect(sql.contains("created_at real"))
        #expect(sql.contains("updated_at real"))
    }

    @Test("Plan migration with missing index")
    func testPlanMigrationMissingIndex() throws {
        let store = try createTestStore()

        // Create table without the index
        try store.connection.execute("""
            CREATE TABLE test_user (
                id blob PRIMARY KEY,
                name text NOT NULL,
                email text NOT NULL,
                age integer,
                address text NOT NULL,
                created_at real NOT NULL,
                updated_at real NOT NULL
            )
        """)

        try store.register(TestUser.self)

        let plan = try store.planMigration(for: TestUser.self)

        #expect(plan.hasChanges == true)
        #expect(plan.statements.count == 1)
        #expect(plan.statements[0].lowercased().contains("create unique index"))
        #expect(plan.statements[0].lowercased().contains("idx_test_user_email"))
    }

    @Test("Dry run does not modify database")
    func testDryRunNoModification() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)

        // Run dry run
        let plan = try store.planMigration(for: TestUser.self)
        #expect(plan.hasChanges == true)

        // Run dry run again - should get same result (table still doesn't exist)
        let plan2 = try store.planMigration(for: TestUser.self)
        #expect(plan2.hasChanges == true)
        #expect(plan.statements.count == plan2.statements.count)

        // Now actually migrate
        try store.migrate()

        // Dry run should show no changes
        let plan3 = try store.planMigration(for: TestUser.self)
        #expect(plan3.hasChanges == false)
    }
}
