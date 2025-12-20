import Testing
import Foundation
@testable import SwiftStoreCore
import SwiftStoreProtocols

// MARK: - DatabaseSchemaBuilder Tests

@Suite("DatabaseSchemaBuilder Tests")
struct DatabaseSchemaBuilderTests {

    @Test("Build schema with default options")
    func testBuildSchemaDefaultOptions() {
        let builder = DatabaseSchemaBuilder()
        let schemas = builder.buildSchemas(from: [TestUser.self])

        #expect(schemas.count == 1)
        let schema = schemas[0]
        #expect(schema.name == "test_user")
        #expect(schema.columns.count == 7)
        #expect(schema.indexes.count == 1)
        #expect(schema.triggers.count == 1) // update trigger only
    }

    @Test("Build schema with trackDeletes enabled")
    func testBuildSchemaWithTrackDeletes() {
        let builder = DatabaseSchemaBuilder(
            options: DatabaseSchemaBuildOptions(
                createUpdateTrigger: true,
                trackDeletes: true
            )
        )
        let schemas = builder.buildSchemas(from: [TestUser.self])

        // Should have entity schema + delete tracking table
        #expect(schemas.count == 2)

        let userSchema = schemas.first { $0.name == "test_user" }
        #expect(userSchema != nil)
        #expect(userSchema?.triggers.count == 2) // update + delete triggers

        let deleteTableSchema = schemas.first { $0.name == "__swiftstore_pending_deletes" }
        #expect(deleteTableSchema != nil)
        #expect(deleteTableSchema?.columns.count == 3)
    }

    @Test("Build schema without update trigger")
    func testBuildSchemaWithoutUpdateTrigger() {
        let builder = DatabaseSchemaBuilder(
            options: DatabaseSchemaBuildOptions(
                createUpdateTrigger: false,
                trackDeletes: false
            )
        )
        let schemas = builder.buildSchemas(from: [TestUser.self])

        #expect(schemas.count == 1)
        #expect(schemas[0].triggers.isEmpty)
    }

    @Test("Build schema uses column defaultValue from entity")
    func testBuildSchemaUsesColumnDefaultValue() {
        let builder = DatabaseSchemaBuilder()
        let schemas = builder.buildSchemas(from: [TestUser.self])

        let schema = schemas[0]
        let createdAt = schema.columns.first { $0.name == "created_at" }
        let updatedAt = schema.columns.first { $0.name == "updated_at" }

        // Default values come from the entity's ColumnDefinition
        #expect(createdAt?.defaultValue == "(strftime('%s', 'now'))")
        #expect(updatedAt?.defaultValue == "(strftime('%s', 'now'))")
    }

    @Test("Build schema with all column types")
    func testBuildSchemaColumnTypes() {
        let builder = DatabaseSchemaBuilder()
        let schemas = builder.buildSchemas(from: [TestUser.self])

        let schema = schemas[0]

        // Check id column (BLOB, primary key)
        let idCol = schema.columns.first { $0.name == "id" }
        #expect(idCol?.type == "BLOB")
        #expect(idCol?.isPrimaryKey == true)
        #expect(idCol?.isNullable == false)

        // Check name column (TEXT, not null)
        let nameCol = schema.columns.first { $0.name == "name" }
        #expect(nameCol?.type == "TEXT")
        #expect(nameCol?.isNullable == false)

        // Check age column (INTEGER, nullable)
        let ageCol = schema.columns.first { $0.name == "age" }
        #expect(ageCol?.type == "INTEGER")
        #expect(ageCol?.isNullable == true)
    }

    @Test("Build schema with indexes")
    func testBuildSchemaIndexes() {
        let builder = DatabaseSchemaBuilder()
        let schemas = builder.buildSchemas(from: [TestUser.self])

        let schema = schemas[0]
        #expect(schema.indexes.count == 1)

        let emailIndex = schema.indexes[0]
        #expect(emailIndex.name == "idx_test_user_email")
        #expect(emailIndex.columns == ["email"])
        #expect(emailIndex.isUnique == true)
    }

    @Test("Build schema with foreign keys")
    func testBuildSchemaForeignKeys() {
        let builder = DatabaseSchemaBuilder()
        let schemas = builder.buildSchemas(from: [TestUserTags.self])

        let schema = schemas[0]
        #expect(schema.foreignKeys.count == 2)

        let userFk = schema.foreignKeys.first { $0.column == "user_id" }
        #expect(userFk?.referencesTable == "test_user")
        #expect(userFk?.referencesColumn == "id")

        let tagFk = schema.foreignKeys.first { $0.column == "tag_id" }
        #expect(tagFk?.referencesTable == "test_tag")
        #expect(tagFk?.referencesColumn == "id")
    }

    @Test("Build multiple schemas")
    func testBuildMultipleSchemas() {
        let builder = DatabaseSchemaBuilder()
        let schemas = builder.buildSchemas(from: [TestUser.self, TestTag.self])

        #expect(schemas.count == 2)
        #expect(schemas.contains { $0.name == "test_user" })
        #expect(schemas.contains { $0.name == "test_tag" })
    }

    @Test("Build schema with virtual columns")
    func testBuildSchemaVirtualColumns() {
        let builder = DatabaseSchemaBuilder()
        let schemas = builder.buildSchemas(from: [MacroProfile.self])

        let schema = schemas[0]

        // Check virtual columns
        let themeCol = schema.columns.first { $0.name == "settings__theme" }
        #expect(themeCol != nil)
        #expect(themeCol?.isGenerated == true)
        #expect(themeCol?.generatedAs?.contains("json_extract") == true)
    }

    @Test("Update trigger SQL is correct")
    func testUpdateTriggerSQL() {
        let builder = DatabaseSchemaBuilder()
        let schemas = builder.buildSchemas(from: [TestUser.self])

        let schema = schemas[0]
        let updateTrigger = schema.triggers.first { $0.name.contains("update") }

        #expect(updateTrigger != nil)
        #expect(updateTrigger?.event == .update)
        #expect(updateTrigger?.timing == .after)
        #expect(updateTrigger?.condition == "NEW.updated_at = OLD.updated_at")
        #expect(updateTrigger?.sql.contains("CREATE TRIGGER") == true)
    }

    @Test("Delete trigger SQL is correct")
    func testDeleteTriggerSQL() {
        let builder = DatabaseSchemaBuilder(
            options: DatabaseSchemaBuildOptions(trackDeletes: true)
        )
        let schemas = builder.buildSchemas(from: [TestUser.self])

        let schema = schemas.first { $0.name == "test_user" }
        let deleteTrigger = schema?.triggers.first { $0.name.contains("delete") }

        #expect(deleteTrigger != nil)
        #expect(deleteTrigger?.event == .delete)
        #expect(deleteTrigger?.timing == .before)
        #expect(deleteTrigger?.sql.contains("__swiftstore_pending_deletes") == true)
    }
}

// MARK: - DatabaseSchemaReader Tests

@Suite("DatabaseSchemaReader Tests")
struct DatabaseSchemaReaderTests {

    @Test("Read schema from non-existent table")
    func testReadSchemaFromNonExistentTable() throws {
        let store = try createTestStore()
        let reader = DatabaseSchemaReader(connection: store.connection)

        let schemas = try reader.readAllSchemas()
        #expect(schemas["non_existent_table"] == nil)
    }

    @Test("Read schema from existing table")
    func testReadSchemaFromExistingTable() throws {
        var store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let reader = DatabaseSchemaReader(connection: store.connection)
        let schemas = try reader.readAllSchemas()

        let schema = schemas["test_user"]
        #expect(schema != nil)
        #expect(schema?.name == "test_user")
        #expect(schema?.columns.count == 7)
    }

    @Test("Read all schemas from empty database")
    func testReadAllSchemasEmptyDatabase() throws {
        let store = try createTestStore()
        let reader = DatabaseSchemaReader(connection: store.connection)

        let schemas = try reader.readAllSchemas()
        #expect(schemas.isEmpty)
    }

    @Test("Read all schemas from database with multiple tables")
    func testReadAllSchemasMultipleTables() throws {
        var store = try createTestStore()
        try store.register(TestUser.self)
        try store.register(TestTag.self)
        try store.migrate()

        let reader = DatabaseSchemaReader(connection: store.connection)
        let schemas = try reader.readAllSchemas()

        #expect(schemas.count >= 2)
        #expect(schemas["test_user"] != nil)
        #expect(schemas["test_tag"] != nil)
    }

    @Test("Read column schema correctly")
    func testReadColumnSchema() throws {
        var store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let reader = DatabaseSchemaReader(connection: store.connection)
        let schemas = try reader.readAllSchemas()
        let schema = schemas["test_user"]!

        // Check primary key column
        let idCol = schema.columns.first { $0.name == "id" }
        #expect(idCol != nil)
        #expect(idCol?.isPrimaryKey == true)

        // Check nullable column
        let ageCol = schema.columns.first { $0.name == "age" }
        #expect(ageCol != nil)
        #expect(ageCol?.isNullable == true)

        // Check non-null column
        let nameCol = schema.columns.first { $0.name == "name" }
        #expect(nameCol != nil)
        #expect(nameCol?.isNullable == false)
    }

    @Test("Read column default value")
    func testReadColumnDefaultValue() throws {
        var store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let reader = DatabaseSchemaReader(connection: store.connection)
        let schemas = try reader.readAllSchemas()
        let schema = schemas["test_user"]!

        let createdAt = schema.columns.first { $0.name == "created_at" }
        #expect(createdAt?.defaultValue != nil)
        #expect(createdAt?.defaultValue?.contains("strftime") == true)
    }

    @Test("Read index schema correctly")
    func testReadIndexSchema() throws {
        var store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let reader = DatabaseSchemaReader(connection: store.connection)
        let schemas = try reader.readAllSchemas()
        let schema = schemas["test_user"]!

        let emailIndex = schema.indexes.first { $0.name == "idx_test_user_email" }
        #expect(emailIndex != nil)
        #expect(emailIndex?.columns == ["email"])
        #expect(emailIndex?.isUnique == true)
    }

    @Test("Read trigger schema correctly")
    func testReadTriggerSchema() throws {
        var store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let reader = DatabaseSchemaReader(connection: store.connection)
        let schemas = try reader.readAllSchemas()
        let schema = schemas["test_user"]!

        let updateTrigger = schema.triggers.first { $0.name.contains("update") }
        #expect(updateTrigger != nil)
        #expect(updateTrigger?.event == .update)
        #expect(updateTrigger?.timing == .after)
    }

    @Test("Read schema excludes sqlite system tables")
    func testReadSchemaExcludesSystemTables() throws {
        var store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let reader = DatabaseSchemaReader(connection: store.connection)
        let schemas = try reader.readAllSchemas()

        // Should not include sqlite_* tables
        let systemTables = schemas.keys.filter { $0.hasPrefix("sqlite_") }
        #expect(systemTables.isEmpty)
    }

    @Test("Read schema with composite index")
    func testReadSchemaCompositeIndex() throws {
        var store = try createTestStore()
        try store.register(TestUserTags.self)
        try store.migrate()

        let reader = DatabaseSchemaReader(connection: store.connection)
        let schemas = try reader.readAllSchemas()
        let schema = schemas["test_user_tags"]!

        let compositeIndex = schema.indexes.first { $0.columns.count > 1 }
        #expect(compositeIndex != nil)
        #expect(compositeIndex?.columns.count == 2)
    }
}

// MARK: - Integration Tests

@Suite("Schema Builder and Reader Integration Tests")
struct SchemaIntegrationTests {

    @Test("Builder and Reader produce consistent results")
    func testBuilderReaderConsistency() throws {
        var store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let builder = DatabaseSchemaBuilder()
        let reader = DatabaseSchemaReader(connection: store.connection)

        let builtSchemas = builder.buildSchemas(from: [TestUser.self])
        let readSchemas = try reader.readAllSchemas()

        let builtSchema = builtSchemas[0]
        let readSchema = readSchemas["test_user"]!

        // Column names should match
        let builtColumnNames = Set(builtSchema.columns.map { $0.name })
        let readColumnNames = Set(readSchema.columns.map { $0.name })
        #expect(builtColumnNames == readColumnNames)

        // Index names should match
        let builtIndexNames = Set(builtSchema.indexes.map { $0.name })
        let readIndexNames = Set(readSchema.indexes.map { $0.name })
        #expect(builtIndexNames == readIndexNames)
    }

    @Test("Diff detects new table correctly")
    func testDiffDetectsNewTable() throws {
        let store = try createTestStore()
        let builder = DatabaseSchemaBuilder()
        let reader = DatabaseSchemaReader(connection: store.connection)

        let targetSchemas = builder.buildSchemas(from: [TestUser.self])
        let currentSchemas = try reader.readAllSchemas()

        // Table doesn't exist yet
        #expect(currentSchemas["test_user"] == nil)

        // Diff should show needsCreate
        let diff = SchemaDiff(current: currentSchemas["test_user"], target: targetSchemas[0])
        #expect(diff.needsCreate == true)
        #expect(diff.hasChanges == true)
    }

    @Test("Diff detects no changes for existing table")
    func testDiffDetectsNoChanges() throws {
        var store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let builder = DatabaseSchemaBuilder()
        let reader = DatabaseSchemaReader(connection: store.connection)

        let targetSchemas = builder.buildSchemas(from: [TestUser.self])
        let currentSchemas = try reader.readAllSchemas()

        let diff = SchemaDiff(current: currentSchemas["test_user"], target: targetSchemas[0])
        #expect(diff.needsCreate == false)
        #expect(diff.columnsToAdd.isEmpty)
        #expect(diff.indexesToAdd.isEmpty)
    }

    @Test("Diff detects new columns")
    func testDiffDetectsNewColumns() throws {
        var store = try createTestStore()

        // Create table with fewer columns
        try store.connection.execute("""
            CREATE TABLE test_user (
                id blob PRIMARY KEY,
                name text NOT NULL,
                created_at real NOT NULL DEFAULT (strftime('%s', 'now')),
                updated_at real NOT NULL DEFAULT (strftime('%s', 'now'))
            )
        """)

        try store.register(TestUser.self)

        let builder = DatabaseSchemaBuilder()
        let reader = DatabaseSchemaReader(connection: store.connection)

        let targetSchemas = builder.buildSchemas(from: [TestUser.self])
        let currentSchemas = try reader.readAllSchemas()

        let diff = SchemaDiff(current: currentSchemas["test_user"], target: targetSchemas[0])
        #expect(diff.needsCreate == false)
        #expect(diff.columnsToAdd.count >= 2) // email, age, address missing
    }

    @Test("Diff detects missing indexes")
    func testDiffDetectsMissingIndexes() throws {
        var store = try createTestStore()

        // Create table without index
        try store.connection.execute("""
            CREATE TABLE test_user (
                id blob PRIMARY KEY,
                name text NOT NULL,
                email text NOT NULL,
                age integer,
                address text NOT NULL,
                created_at real NOT NULL DEFAULT (strftime('%s', 'now')),
                updated_at real NOT NULL DEFAULT (strftime('%s', 'now'))
            )
        """)

        try store.register(TestUser.self)

        let builder = DatabaseSchemaBuilder()
        let reader = DatabaseSchemaReader(connection: store.connection)

        let targetSchemas = builder.buildSchemas(from: [TestUser.self])
        let currentSchemas = try reader.readAllSchemas()

        let diff = SchemaDiff(current: currentSchemas["test_user"], target: targetSchemas[0])
        #expect(diff.indexesToAdd.count == 1)
        #expect(diff.indexesToAdd[0].name == "idx_test_user_email")
    }
}
