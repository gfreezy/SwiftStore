import Testing
import Foundation
@testable import SwiftStoreCore
import SwiftStoreMacros
import SwiftStoreProtocols

/// Normalize SQL by removing extra whitespace for comparison
func normalizeSQL(_ sql: String) -> String {
    sql.components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .lowercased()
}

@Suite("Migration Dry Run Tests")
struct MigrationDryRunTests {
    @Test("Plan migration for new table")
    func testPlanMigrationNewTable() throws {
        var store = try createTestStore()
        try store.register(TestUser.self)

        let plan = try store.planMigration(for: TestUser.self)

        #expect(plan.hasChanges == true)

        // Check CREATE TABLE statement
        let createStatements = plan.statements.filter { $0.uppercased().contains("CREATE TABLE") }
        #expect(createStatements.count == 1)

        let createSQL = normalizeSQL(createStatements[0])
        let expectedCreateSQL = normalizeSQL("""
            CREATE TABLE test_user (
                id BLOB NOT NULL PRIMARY KEY,
                name TEXT NOT NULL,
                email TEXT NOT NULL,
                age INTEGER,
                address TEXT NOT NULL,
                created_at REAL NOT NULL DEFAULT (strftime('%s', 'now')),
                updated_at REAL NOT NULL DEFAULT (strftime('%s', 'now'))
            )
        """)
        #expect(createSQL == expectedCreateSQL)

        // Check CREATE INDEX statement
        let indexStatements = plan.statements.filter { $0.uppercased().contains("CREATE") && $0.uppercased().contains("INDEX") }
        #expect(indexStatements.count == 1)
        #expect(normalizeSQL(indexStatements[0]) == normalizeSQL("CREATE UNIQUE INDEX IF NOT EXISTS idx_test_user_email ON test_user(email)"))

        // Check trigger statement
        let triggerStatements = plan.statements.filter { $0.uppercased().contains("CREATE TRIGGER") }
        #expect(triggerStatements.count == 1)
    }

    @Test("Plan migration for existing table with no changes")
    func testPlanMigrationNoChanges() throws {
        var store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let plan = try store.planMigration(for: TestUser.self)

        // Only trigger statement (already exists via IF NOT EXISTS)
        let nonTriggerStatements = plan.statements.filter { !$0.uppercased().contains("TRIGGER") }
        #expect(nonTriggerStatements.isEmpty)
    }

    @Test("Plan migration for existing table with new column")
    func testPlanMigrationNewColumn() throws {
        var store = try createTestStore()

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

        // Verify ALTER TABLE statements
        let alterStatements = plan.statements.filter { $0.uppercased().contains("ALTER TABLE") }
        #expect(alterStatements.count == 3)

        let expectedAlters = [
            normalizeSQL("ALTER TABLE test_user ADD COLUMN email TEXT NOT NULL DEFAULT ''"),
            normalizeSQL("ALTER TABLE test_user ADD COLUMN age INTEGER"),
            normalizeSQL("ALTER TABLE test_user ADD COLUMN address TEXT NOT NULL DEFAULT ''")
        ]

        for expected in expectedAlters {
            #expect(alterStatements.contains { normalizeSQL($0) == expected })
        }

        // Verify CREATE INDEX statement
        let indexStatements = plan.statements.filter { $0.uppercased().contains("CREATE") && $0.uppercased().contains("INDEX") }
        #expect(indexStatements.count == 1)
        #expect(normalizeSQL(indexStatements[0]) == normalizeSQL("CREATE UNIQUE INDEX IF NOT EXISTS idx_test_user_email ON test_user(email)"))
    }

    @Test("Plan migration generates correct script")
    func testPlanMigrationScript() throws {
        var store = try createTestStore()
        try store.register(TestTag.self)

        let plan = try store.planMigration(for: TestTag.self)

        // Check CREATE TABLE statement
        let createStatements = plan.statements.filter { $0.uppercased().contains("CREATE TABLE") }
        #expect(createStatements.count == 1)

        let createSQL = normalizeSQL(createStatements[0])
        let expectedSQL = normalizeSQL("""
            CREATE TABLE test_tag (
                id BLOB NOT NULL PRIMARY KEY,
                name TEXT NOT NULL,
                created_at REAL NOT NULL DEFAULT (strftime('%s', 'now')),
                updated_at REAL NOT NULL DEFAULT (strftime('%s', 'now'))
            )
        """)
        #expect(createSQL == expectedSQL)
        #expect(plan.script.hasSuffix(";"))
    }

    @Test("Plan migrations for multiple entities")
    func testPlanMigrationsMultiple() throws {
        var store = try createTestStore()
        try store.register(TestUser.self)
        try store.register(TestTag.self)

        let plan = try store.planMigrations()

        #expect(plan.hasChanges == true)

        // Find CREATE TABLE statements
        let createStatements = plan.statements.filter { $0.uppercased().contains("CREATE TABLE") }
        #expect(createStatements.count == 2)

        let testUserCreate = createStatements.first { normalizeSQL($0).contains("test_user") }
        let testTagCreate = createStatements.first { normalizeSQL($0).contains("test_tag") }

        #expect(testUserCreate != nil)
        #expect(testTagCreate != nil)

        let expectedUserSQL = normalizeSQL("""
            CREATE TABLE test_user (
                id BLOB NOT NULL PRIMARY KEY,
                name TEXT NOT NULL,
                email TEXT NOT NULL,
                age INTEGER,
                address TEXT NOT NULL,
                created_at REAL NOT NULL DEFAULT (strftime('%s', 'now')),
                updated_at REAL NOT NULL DEFAULT (strftime('%s', 'now'))
            )
        """)
        #expect(normalizeSQL(testUserCreate!) == expectedUserSQL)

        let expectedTagSQL = normalizeSQL("""
            CREATE TABLE test_tag (
                id BLOB NOT NULL PRIMARY KEY,
                name TEXT NOT NULL,
                created_at REAL NOT NULL DEFAULT (strftime('%s', 'now')),
                updated_at REAL NOT NULL DEFAULT (strftime('%s', 'now'))
            )
        """)
        #expect(normalizeSQL(testTagCreate!) == expectedTagSQL)

        // Check triggers for both entities
        let triggerStatements = plan.statements.filter { $0.uppercased().contains("CREATE TRIGGER") }
        #expect(triggerStatements.count == 2)
    }

    @Test("Plan generates CREATE TABLE SQL")
    func testPlanGeneratesCreateTableSQL() throws {
        var store = try createTestStore()
        try store.register(TestTag.self)

        let plan = try store.planMigration(for: TestTag.self)
        let createStatement = plan.statements.first { $0.uppercased().contains("CREATE TABLE") }

        #expect(createStatement != nil)
        let sql = normalizeSQL(createStatement!)
        let expectedSQL = normalizeSQL("""
            CREATE TABLE test_tag (
                id BLOB NOT NULL PRIMARY KEY,
                name TEXT NOT NULL,
                created_at REAL NOT NULL DEFAULT (strftime('%s', 'now')),
                updated_at REAL NOT NULL DEFAULT (strftime('%s', 'now'))
            )
        """)
        #expect(sql == expectedSQL)
    }

    @Test("Plan migration with missing index")
    func testPlanMigrationMissingIndex() throws {
        var store = try createTestStore()

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

        // Should have 1 CREATE INDEX + 1 trigger
        let indexStatements = plan.statements.filter { $0.uppercased().contains("CREATE") && $0.uppercased().contains("INDEX") }
        #expect(indexStatements.count == 1)
        #expect(normalizeSQL(indexStatements[0]) == normalizeSQL("CREATE UNIQUE INDEX IF NOT EXISTS idx_test_user_email ON test_user(email)"))
    }

    @Test("Dry run does not modify database")
    func testDryRunNoModification() throws {
        var store = try createTestStore()
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

        // Dry run should show only trigger (which uses IF NOT EXISTS)
        let plan3 = try store.planMigration(for: TestUser.self)
        let nonTriggerStatements = plan3.statements.filter { !$0.uppercased().contains("TRIGGER") }
        #expect(nonTriggerStatements.isEmpty)
    }

    @Test("Plan migration for entity with virtual columns")
    func testPlanMigrationVirtualColumns() throws {
        var store = try createTestStore()
        try store.register(MacroProfile.self)

        let plan = try store.planMigration(for: MacroProfile.self)

        #expect(plan.hasChanges == true)

        // Check CREATE TABLE
        let createStatements = plan.statements.filter { $0.uppercased().contains("CREATE TABLE") }
        #expect(createStatements.count == 1)

        let createSQL = normalizeSQL(createStatements[0])
        let expectedCreateSQL = normalizeSQL("""
            CREATE TABLE macro_profile (
                id BLOB NOT NULL PRIMARY KEY,
                bio TEXT NOT NULL,
                settings TEXT NOT NULL,
                created_at REAL NOT NULL DEFAULT (strftime('%s', 'now')),
                updated_at REAL NOT NULL DEFAULT (strftime('%s', 'now')),
                settings__theme TEXT GENERATED ALWAYS AS (json_extract(settings, '$.theme')) VIRTUAL,
                settings__notifications TEXT GENERATED ALWAYS AS (json_extract(settings, '$.notifications')) VIRTUAL
            )
        """)
        #expect(createSQL == expectedCreateSQL)

        // Check indexes
        let indexStatements = plan.statements.filter { $0.uppercased().contains("CREATE") && $0.uppercased().contains("INDEX") }
        #expect(indexStatements.count == 2)

        let expectedIndex1 = normalizeSQL("CREATE INDEX IF NOT EXISTS idx_macro_profile_settings__theme_settings__notifications ON macro_profile(settings__theme, settings__notifications)")
        let expectedIndex2 = normalizeSQL("CREATE INDEX IF NOT EXISTS idx_macro_profile_settings__theme_id ON macro_profile(settings__theme, id)")

        #expect(indexStatements.contains { normalizeSQL($0) == expectedIndex1 })
        #expect(indexStatements.contains { normalizeSQL($0) == expectedIndex2 })
    }

    @Test("Migration creates virtual column indexes")
    func testMigrationCreatesVirtualColumnIndexes() throws {
        let store = try createTestStore()
        try store.migrate(entities: [MacroProfile.self])

        // Verify indexes exist
        let indexSQL = "SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name='macro_profile'"
        let stmt = try store.connection.prepare(indexSQL)

        var indexes: [String: String] = [:]
        while try stmt.step() {
            if let name = stmt.columnString(0), let sql = stmt.columnString(1) {
                indexes[name] = sql
            }
        }

        // Should have indexes on virtual columns
        #expect(indexes.keys.contains { $0.contains("settings__theme") })

        // Check index SQL includes virtual column names
        let themeNotificationsIndex = indexes.first { $0.key.contains("settings__theme") && $0.key.contains("settings__notifications") }
        #expect(themeNotificationsIndex != nil)
        #expect(themeNotificationsIndex?.value.contains("settings__theme") == true)
        #expect(themeNotificationsIndex?.value.contains("settings__notifications") == true)

        let themeIdIndex = indexes.first { $0.key.contains("settings__theme") && $0.key.contains("id") }
        #expect(themeIdIndex != nil)
    }

    @Test("Virtual column can be queried directly")
    func testVirtualColumnQuery() throws {
        let store = try createTestStore()
        try store.migrate(entities: [MacroProfile.self])

        // Insert some profiles
        let profile1 = MacroProfile(
            id: UUIDV4(),
            bio: "Bio 1",
            settings: UserSettings(theme: "dark", notifications: true),
            createdAt: Date(),
            updatedAt: Date()
        )
        let profile2 = MacroProfile(
            id: UUIDV4(),
            bio: "Bio 2",
            settings: UserSettings(theme: "light", notifications: false),
            createdAt: Date(),
            updatedAt: Date()
        )
        try store.connection.insert(profile1)
        try store.connection.insert(profile2)

        // Query using virtual column directly via raw SQL
        let sql = "SELECT id, bio FROM macro_profile WHERE settings__theme = ?"
        let stmt = try store.connection.prepare(sql)
        try stmt.bind(1, "dark")

        var results: [String] = []
        while try stmt.step() {
            if let bio = stmt.columnString(1) {
                results.append(bio)
            }
        }

        #expect(results.count == 1)
        #expect(results.first == "Bio 1")
    }

    @Test("Virtual column index improves query performance")
    func testVirtualColumnIndexUsed() throws {
        let store = try createTestStore()
        try store.migrate(entities: [MacroProfile.self])

        // Insert a profile
        let profile = MacroProfile(
            id: UUIDV4(),
            bio: "Test Bio",
            settings: UserSettings(theme: "dark", notifications: true),
            createdAt: Date(),
            updatedAt: Date()
        )
        try store.connection.insert(profile)

        // Use EXPLAIN QUERY PLAN to verify index usage
        let explainSQL = "EXPLAIN QUERY PLAN SELECT * FROM macro_profile WHERE settings__theme = 'dark'"
        let stmt = try store.connection.prepare(explainSQL)

        var queryPlan = ""
        while try stmt.step() {
            if let detail = stmt.columnString(3) {
                queryPlan += detail
            }
        }

        // Query plan should show index usage (SEARCH or USING INDEX)
        #expect(queryPlan.lowercased().contains("index") || queryPlan.lowercased().contains("search"))
    }
}

// MARK: - Migrator.plan SQL Verification Tests

@Suite("Migrator Plan SQL Tests")
struct MigratorPlanSQLTests {

    // MARK: - CREATE TABLE Tests

    @Test("Plan creates correct CREATE TABLE SQL for simple entity")
    func testPlanCreateTableSimple() throws {
        let store = try createTestStore()
        let migrator = Migrator(connection: store.connection)

        let plan = try migrator.plan(for: [TestTag.self])

        let createStatements = plan.statements.filter { $0.uppercased().contains("CREATE TABLE") }
        #expect(createStatements.count == 1)

        let expectedSQL = normalizeSQL("""
            CREATE TABLE test_tag (
                id BLOB NOT NULL PRIMARY KEY,
                name TEXT NOT NULL,
                created_at REAL NOT NULL DEFAULT (strftime('%s', 'now')),
                updated_at REAL NOT NULL DEFAULT (strftime('%s', 'now'))
            )
        """)
        #expect(normalizeSQL(createStatements[0]) == expectedSQL)
    }

    @Test("Plan creates correct CREATE TABLE SQL with all column types")
    func testPlanCreateTableAllColumnTypes() throws {
        let store = try createTestStore()
        let migrator = Migrator(connection: store.connection)

        let plan = try migrator.plan(for: [TestUser.self])

        let createStatements = plan.statements.filter { $0.uppercased().contains("CREATE TABLE") }
        #expect(createStatements.count == 1)

        let expectedSQL = normalizeSQL("""
            CREATE TABLE test_user (
                id BLOB NOT NULL PRIMARY KEY,
                name TEXT NOT NULL,
                email TEXT NOT NULL,
                age INTEGER,
                address TEXT NOT NULL,
                created_at REAL NOT NULL DEFAULT (strftime('%s', 'now')),
                updated_at REAL NOT NULL DEFAULT (strftime('%s', 'now'))
            )
        """)
        #expect(normalizeSQL(createStatements[0]) == expectedSQL)
    }

    @Test("Plan creates correct CREATE TABLE SQL with foreign keys")
    func testPlanCreateTableWithForeignKeys() throws {
        let store = try createTestStore()
        let migrator = Migrator(connection: store.connection)

        let plan = try migrator.plan(for: [TestUserTags.self])

        let createStatements = plan.statements.filter { $0.uppercased().contains("CREATE TABLE") }
        #expect(createStatements.count == 1)

        let sql = normalizeSQL(createStatements[0])

        // Verify foreign key constraints are included
        #expect(sql.contains("foreign key (user_id) references test_user(id)"))
        #expect(sql.contains("foreign key (tag_id) references test_tag(id)"))
    }

    @Test("Plan creates correct CREATE TABLE SQL with virtual columns")
    func testPlanCreateTableWithVirtualColumns() throws {
        let store = try createTestStore()
        let migrator = Migrator(connection: store.connection)

        let plan = try migrator.plan(for: [MacroProfile.self])

        let createStatements = plan.statements.filter { $0.uppercased().contains("CREATE TABLE") }
        #expect(createStatements.count == 1)

        let sql = normalizeSQL(createStatements[0])

        // Verify virtual columns
        #expect(sql.contains("settings__theme text generated always as (json_extract(settings, '$.theme')) virtual"))
        #expect(sql.contains("settings__notifications text generated always as (json_extract(settings, '$.notifications')) virtual"))
    }

    // MARK: - CREATE INDEX Tests

    @Test("Plan creates correct CREATE INDEX SQL for unique index")
    func testPlanCreateUniqueIndex() throws {
        let store = try createTestStore()
        let migrator = Migrator(connection: store.connection)

        let plan = try migrator.plan(for: [TestUser.self])

        let indexStatements = plan.statements.filter {
            $0.uppercased().contains("CREATE") && $0.uppercased().contains("INDEX")
        }
        #expect(indexStatements.count == 1)

        let expectedSQL = normalizeSQL("CREATE UNIQUE INDEX IF NOT EXISTS idx_test_user_email ON test_user(email)")
        #expect(normalizeSQL(indexStatements[0]) == expectedSQL)
    }

    @Test("Plan creates correct CREATE INDEX SQL for composite index")
    func testPlanCreateCompositeIndex() throws {
        let store = try createTestStore()
        let migrator = Migrator(connection: store.connection)

        let plan = try migrator.plan(for: [TestUserTags.self])

        let indexStatements = plan.statements.filter {
            $0.uppercased().contains("CREATE") && $0.uppercased().contains("INDEX")
        }
        #expect(indexStatements.count == 1)

        let expectedSQL = normalizeSQL("CREATE UNIQUE INDEX IF NOT EXISTS idx_test_user_tags_unique ON test_user_tags(user_id, tag_id)")
        #expect(normalizeSQL(indexStatements[0]) == expectedSQL)
    }

    @Test("Plan creates correct CREATE INDEX SQL for virtual column indexes")
    func testPlanCreateVirtualColumnIndexes() throws {
        let store = try createTestStore()
        let migrator = Migrator(connection: store.connection)

        let plan = try migrator.plan(for: [MacroProfile.self])

        let indexStatements = plan.statements.filter {
            $0.uppercased().contains("CREATE") && $0.uppercased().contains("INDEX")
        }
        #expect(indexStatements.count == 2)

        let expectedIndex1 = normalizeSQL("CREATE INDEX IF NOT EXISTS idx_macro_profile_settings__theme_settings__notifications ON macro_profile(settings__theme, settings__notifications)")
        let expectedIndex2 = normalizeSQL("CREATE INDEX IF NOT EXISTS idx_macro_profile_settings__theme_id ON macro_profile(settings__theme, id)")

        #expect(indexStatements.contains { normalizeSQL($0) == expectedIndex1 })
        #expect(indexStatements.contains { normalizeSQL($0) == expectedIndex2 })
    }

    // MARK: - CREATE TRIGGER Tests

    @Test("Plan creates correct update trigger SQL")
    func testPlanCreateUpdateTrigger() throws {
        let store = try createTestStore()
        let migrator = Migrator(connection: store.connection)

        let plan = try migrator.plan(for: [TestTag.self])

        let triggerStatements = plan.statements.filter { $0.uppercased().contains("CREATE TRIGGER") }
        #expect(triggerStatements.count == 1)

        let sql = normalizeSQL(triggerStatements[0])

        #expect(sql.contains("create trigger if not exists __swiftstore_update_test_tag"))
        #expect(sql.contains("after update on test_tag"))
        #expect(sql.contains("for each row"))
        #expect(sql.contains("when new.updated_at = old.updated_at"))
        #expect(sql.contains("update test_tag set updated_at = strftime('%s', 'now')"))
    }

    @Test("Plan creates delete trigger when trackDeletes enabled")
    func testPlanCreateDeleteTrigger() throws {
        let store = try createTestStore()
        let migrator = Migrator(connection: store.connection, trackDeletes: true)

        let plan = try migrator.plan(for: [TestTag.self])

        let triggerStatements = plan.statements.filter { $0.uppercased().contains("CREATE TRIGGER") }
        #expect(triggerStatements.count == 2) // update + delete triggers

        let deleteTrigger = triggerStatements.first { normalizeSQL($0).contains("__swiftstore_delete_") }
        #expect(deleteTrigger != nil)

        let sql = normalizeSQL(deleteTrigger!)
        #expect(sql.contains("before delete on test_tag"))
        #expect(sql.contains("insert into __swiftstore_pending_deletes"))
    }

    // MARK: - Track Deletes Tests

    @Test("Plan creates pending deletes table when trackDeletes enabled")
    func testPlanCreatesPendingDeletesTable() throws {
        let store = try createTestStore()
        let migrator = Migrator(connection: store.connection, trackDeletes: true)

        let plan = try migrator.plan(for: [TestTag.self])

        let createStatements = plan.statements.filter { $0.uppercased().contains("CREATE TABLE") }
        #expect(createStatements.count == 2) // test_tag + __swiftstore_pending_deletes

        let deletesTable = createStatements.first { normalizeSQL($0).contains("__swiftstore_pending_deletes") }
        #expect(deletesTable != nil)

        let expectedSQL = normalizeSQL("""
            CREATE TABLE __swiftstore_pending_deletes (
                id INTEGER NOT NULL PRIMARY KEY,
                table_name TEXT NOT NULL,
                entity_id BLOB NOT NULL
            )
        """)
        #expect(normalizeSQL(deletesTable!) == expectedSQL)
    }

    // MARK: - ALTER TABLE Tests

    @Test("Plan creates correct ALTER TABLE ADD COLUMN SQL for nullable column")
    func testPlanAlterTableAddNullableColumn() throws {
        let store = try createTestStore()

        // Create table without age column
        try store.connection.execute("""
            CREATE TABLE test_user (
                id blob PRIMARY KEY,
                name text NOT NULL,
                email text NOT NULL,
                address text NOT NULL,
                created_at real NOT NULL,
                updated_at real NOT NULL
            )
        """)

        let migrator = Migrator(connection: store.connection)
        let plan = try migrator.plan(for: [TestUser.self])

        let alterStatements = plan.statements.filter { $0.uppercased().contains("ALTER TABLE") }
        #expect(alterStatements.count == 1)

        // age is nullable, so no DEFAULT needed
        let expectedSQL = normalizeSQL("ALTER TABLE test_user ADD COLUMN age INTEGER")
        #expect(normalizeSQL(alterStatements[0]) == expectedSQL)
    }

    @Test("Plan creates correct ALTER TABLE ADD COLUMN SQL for non-nullable column")
    func testPlanAlterTableAddNonNullableColumn() throws {
        let store = try createTestStore()

        // Create table without email column
        try store.connection.execute("""
            CREATE TABLE test_user (
                id blob PRIMARY KEY,
                name text NOT NULL,
                age integer,
                address text NOT NULL,
                created_at real NOT NULL,
                updated_at real NOT NULL
            )
        """)

        let migrator = Migrator(connection: store.connection)
        let plan = try migrator.plan(for: [TestUser.self])

        let alterStatements = plan.statements.filter { $0.uppercased().contains("ALTER TABLE") }
        #expect(alterStatements.count == 1)

        // email is NOT NULL, so needs DEFAULT
        let expectedSQL = normalizeSQL("ALTER TABLE test_user ADD COLUMN email TEXT NOT NULL DEFAULT ''")
        #expect(normalizeSQL(alterStatements[0]) == expectedSQL)
    }

    @Test("Plan creates ALTER TABLE for multiple missing columns")
    func testPlanAlterTableMultipleColumns() throws {
        let store = try createTestStore()

        // Create minimal table
        try store.connection.execute("""
            CREATE TABLE test_user (
                id blob PRIMARY KEY,
                name text NOT NULL,
                created_at real NOT NULL,
                updated_at real NOT NULL
            )
        """)

        let migrator = Migrator(connection: store.connection)
        let plan = try migrator.plan(for: [TestUser.self])

        let alterStatements = plan.statements.filter { $0.uppercased().contains("ALTER TABLE") }
        #expect(alterStatements.count == 3)

        let expectedAlters = [
            normalizeSQL("ALTER TABLE test_user ADD COLUMN email TEXT NOT NULL DEFAULT ''"),
            normalizeSQL("ALTER TABLE test_user ADD COLUMN age INTEGER"),
            normalizeSQL("ALTER TABLE test_user ADD COLUMN address TEXT NOT NULL DEFAULT ''")
        ]

        for expected in expectedAlters {
            #expect(alterStatements.contains { normalizeSQL($0) == expected })
        }
    }

    // MARK: - Missing Index Tests

    @Test("Plan creates index for existing table with missing index")
    func testPlanAddMissingIndex() throws {
        let store = try createTestStore()

        // Create table without index
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

        let migrator = Migrator(connection: store.connection)
        let plan = try migrator.plan(for: [TestUser.self])

        let indexStatements = plan.statements.filter {
            $0.uppercased().contains("CREATE") && $0.uppercased().contains("INDEX")
        }
        #expect(indexStatements.count == 1)

        let expectedSQL = normalizeSQL("CREATE UNIQUE INDEX IF NOT EXISTS idx_test_user_email ON test_user(email)")
        #expect(normalizeSQL(indexStatements[0]) == expectedSQL)
    }

    // MARK: - Multiple Tables Tests

    @Test("Plan creates correct SQL for multiple tables")
    func testPlanMultipleTables() throws {
        let store = try createTestStore()
        let migrator = Migrator(connection: store.connection)

        let plan = try migrator.plan(for: [TestUser.self, TestTag.self])

        let createStatements = plan.statements.filter { $0.uppercased().contains("CREATE TABLE") }
        #expect(createStatements.count == 2)

        let userSQL = createStatements.first { normalizeSQL($0).contains("test_user") }
        let tagSQL = createStatements.first { normalizeSQL($0).contains("test_tag") }

        #expect(userSQL != nil)
        #expect(tagSQL != nil)

        let expectedUserSQL = normalizeSQL("""
            CREATE TABLE test_user (
                id BLOB NOT NULL PRIMARY KEY,
                name TEXT NOT NULL,
                email TEXT NOT NULL,
                age INTEGER,
                address TEXT NOT NULL,
                created_at REAL NOT NULL DEFAULT (strftime('%s', 'now')),
                updated_at REAL NOT NULL DEFAULT (strftime('%s', 'now'))
            )
        """)
        #expect(normalizeSQL(userSQL!) == expectedUserSQL)

        let expectedTagSQL = normalizeSQL("""
            CREATE TABLE test_tag (
                id BLOB NOT NULL PRIMARY KEY,
                name TEXT NOT NULL,
                created_at REAL NOT NULL DEFAULT (strftime('%s', 'now')),
                updated_at REAL NOT NULL DEFAULT (strftime('%s', 'now'))
            )
        """)
        #expect(normalizeSQL(tagSQL!) == expectedTagSQL)

        // Check indexes
        let indexStatements = plan.statements.filter {
            $0.uppercased().contains("CREATE") && $0.uppercased().contains("INDEX")
        }
        #expect(indexStatements.count == 1) // Only TestUser has an index

        // Check triggers
        let triggerStatements = plan.statements.filter { $0.uppercased().contains("CREATE TRIGGER") }
        #expect(triggerStatements.count == 2) // One for each table
    }

    // MARK: - No Changes Tests

    @Test("Plan returns empty when no changes needed")
    func testPlanNoChanges() throws {
        var store = try createTestStore()
        try store.register(TestTag.self)
        try store.migrate()

        let migrator = Migrator(connection: store.connection)
        let plan = try migrator.plan(for: [TestTag.self])

        // Only trigger statement (uses IF NOT EXISTS, so harmless)
        let nonTriggerStatements = plan.statements.filter { !$0.uppercased().contains("TRIGGER") }
        #expect(nonTriggerStatements.isEmpty)
    }

    @Test("Plan returns empty for fully migrated table with all columns")
    func testPlanNoChangesFullTable() throws {
        var store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let migrator = Migrator(connection: store.connection)
        let plan = try migrator.plan(for: [TestUser.self])

        // Only trigger statement
        let nonTriggerStatements = plan.statements.filter { !$0.uppercased().contains("TRIGGER") }
        #expect(nonTriggerStatements.isEmpty)
    }

    // MARK: - Script Generation Tests

    @Test("Plan script joins statements with semicolons")
    func testPlanScriptFormat() throws {
        let store = try createTestStore()
        let migrator = Migrator(connection: store.connection)

        let plan = try migrator.plan(for: [TestTag.self])

        #expect(plan.hasChanges == true)
        #expect(plan.script.hasSuffix(";"))

        // Should have CREATE TABLE, CREATE TRIGGER separated by ;\n
        let script = plan.script
        #expect(script.contains(";\n") || plan.statements.count == 1)
    }

    @Test("Plan script is empty when no changes")
    func testPlanScriptEmpty() throws {
        var store = try createTestStore()
        try store.register(TestTag.self)
        try store.migrate()

        let migrator = Migrator(connection: store.connection)
        let plan = try migrator.plan(for: [TestTag.self])

        // Only trigger which uses IF NOT EXISTS
        let nonTriggerPlan = MigrationPlan(statements: plan.statements.filter { !$0.uppercased().contains("TRIGGER") })
        #expect(nonTriggerPlan.script.isEmpty || nonTriggerPlan.script == "")
    }

    // MARK: - Full SQL Comparison Tests

    @Test("Plan creates complete correct SQL for entity with all features")
    func testPlanCompleteSQL() throws {
        let store = try createTestStore()
        let migrator = Migrator(connection: store.connection, trackDeletes: true)

        let plan = try migrator.plan(for: [TestUserTags.self])

        // Verify all statements in order
        let createTableStatements = plan.statements.filter { $0.uppercased().contains("CREATE TABLE") }
        let indexStatements = plan.statements.filter { $0.uppercased().contains("CREATE") && $0.uppercased().contains("INDEX") && !$0.uppercased().contains("TABLE") }
        let triggerStatements = plan.statements.filter { $0.uppercased().contains("CREATE TRIGGER") }

        // 2 tables: test_user_tags + __swiftstore_pending_deletes
        #expect(createTableStatements.count == 2)

        // 1 composite unique index
        #expect(indexStatements.count == 1)

        // 2 triggers: update + delete
        #expect(triggerStatements.count == 2)

        // Verify exact CREATE TABLE SQL
        let userTagsTable = createTableStatements.first { normalizeSQL($0).contains("test_user_tags") }!
        let sql = normalizeSQL(userTagsTable)

        #expect(sql.contains("id blob not null primary key"))
        #expect(sql.contains("user_id blob not null"))
        #expect(sql.contains("tag_id blob not null"))
        #expect(sql.contains("foreign key (user_id) references test_user(id)"))
        #expect(sql.contains("foreign key (tag_id) references test_tag(id)"))
    }
}
