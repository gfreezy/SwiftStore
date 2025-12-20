import Foundation

/// Result of a dry run migration
public struct MigrationPlan: Sendable {
    /// SQL statements that would be executed
    public let statements: [String]

    /// Whether there are any changes to apply
    public var hasChanges: Bool {
        !statements.isEmpty
    }

    /// Combined SQL as a single script
    public var script: String {
        statements.joined(separator: ";\n") + (statements.isEmpty ? "" : ";")
    }
}

/// Manages database schema migrations
public final class MigrationManager {
    private let connection: SQLiteConnection
    public let pendingDeletesTable: String = "__swiftstore_pending_deletes"

    init(connection: SQLiteConnection) {
        self.connection = connection
    }

    /// Create table for an entity type
    public func createTable<E: EntityProtocol>(for type: E.Type) throws {
        try createTableForAnyType(type)
    }

    /// Create table for any entity type (type-erased)
    public func createTableForAnyType(_ type: any EntityProtocol.Type) throws {
        let tableName = type.tableName

        // Check if table exists
        if try connection.tableExists(tableName) {
            // Table exists, check for schema changes
            try migrateTableForAnyType(type)
            return
        }

        // Build CREATE TABLE SQL with timestamp defaults
        var columnDefs: [String] = []

        for column in type.columns {
            // Add DEFAULT for timestamp columns
            if column.name == "created_at" || column.name == "updated_at" {
                let colWithDefault = ColumnDefinition(
                    name: column.name,
                    type: column.type,
                    nullable: column.nullable,
                    defaultValue: "(strftime('%s', 'now'))"
                )
                columnDefs.append(colWithDefault.toSQL())
            } else {
                columnDefs.append(column.toSQL())
            }
        }

        // Add foreign key constraints
        for fk in type.foreignKeys {
            columnDefs.append(fk.toSQL())
        }

        let sql = "CREATE TABLE \(tableName) (\n    \(columnDefs.joined(separator: ",\n    "))\n)"
        try connection.execute(sql)

        // Create indexes
        for index in type.indexes {
            let indexSQL = index.toSQL(tableName: tableName)
            try connection.execute(indexSQL)
        }

        // Create UPDATE trigger for updated_at
        try createUpdateTimestampTrigger(for: tableName)
    }

    /// Create trigger to auto-update updated_at on UPDATE
    private func createUpdateTimestampTrigger(for tableName: String) throws {
        let trigger = """
            CREATE TRIGGER IF NOT EXISTS __swiftstore_update_\(tableName)
            AFTER UPDATE ON \(tableName)
            FOR EACH ROW
            WHEN NEW.updated_at = OLD.updated_at
            BEGIN
                UPDATE \(tableName) SET updated_at = strftime('%s', 'now')
                WHERE rowid = NEW.rowid;
            END
            """
        try connection.execute(trigger)
    }

    /// Migrate existing table (type-erased version)
    private func migrateTableForAnyType(_ type: any EntityProtocol.Type) throws {
        let tableName = type.tableName
        let existingColumns = try connection.tableInfo(tableName)
        let existingColumnNames = Set(existingColumns.compactMap { $0["name"] as? String })

        // Add new columns
        for column in type.columns {
            if !existingColumnNames.contains(column.name) {
                // Skip virtual columns for ALTER TABLE
                if column.generatedAs != nil {
                    continue
                }

                var alterSQL =
                    "ALTER TABLE \(tableName) ADD COLUMN \(column.name) \(column.type.rawValue)"
                if !column.nullable {
                    if let defaultValue = column.defaultValue {
                        alterSQL += " NOT NULL DEFAULT \(defaultValue)"
                    } else if column.name == "created_at" || column.name == "updated_at" {
                        alterSQL += " NOT NULL DEFAULT (strftime('%s', 'now'))"
                    } else {
                        let defaultVal = defaultValueForType(column.type)
                        alterSQL += " NOT NULL DEFAULT \(defaultVal)"
                    }
                }
                try connection.execute(alterSQL)
            }
        }

        // Ensure all indexes exist
        for index in type.indexes {
            let indexSQL = index.toSQL(tableName: tableName).replacingOccurrences(
                of: "CREATE INDEX",
                with: "CREATE INDEX IF NOT EXISTS"
            ).replacingOccurrences(
                of: "CREATE UNIQUE INDEX",
                with: "CREATE UNIQUE INDEX IF NOT EXISTS"
            )
            try connection.execute(indexSQL)
        }
    }

    // MARK: - Dry Run

    /// Generate migration plan without executing (dry run)
    /// - Parameter type: The entity type to generate migration for
    /// - Returns: MigrationPlan containing SQL statements that would be executed
    public func planMigration<E: EntityProtocol>(for type: E.Type) throws -> MigrationPlan {
        let tableName = E.tableName
        var statements: [String] = []

        // Check if table exists
        if try connection.tableExists(tableName) {
            // Table exists, generate ALTER statements
            let alterStatements = try planTableMigration(for: type)
            statements.append(contentsOf: alterStatements)
        } else {
            // Generate CREATE TABLE statement
            let createStatement = generateCreateTableSQL(for: type)
            statements.append(createStatement)

            // Generate CREATE INDEX statements
            for index in E.indexes {
                let indexSQL = index.toSQL(tableName: tableName)
                statements.append(indexSQL)
            }
        }

        return MigrationPlan(statements: statements)
    }

    /// Generate CREATE TABLE SQL for an entity type
    public func generateCreateTableSQL<E: EntityProtocol>(for type: E.Type) -> String {
        let tableName = E.tableName
        var columnDefs: [String] = []

        for column in E.columns {
            columnDefs.append(column.toSQL())
        }

        for fk in E.foreignKeys {
            columnDefs.append(fk.toSQL())
        }

        return "CREATE TABLE \(tableName) (\n    \(columnDefs.joined(separator: ",\n    "))\n)"
    }

    /// Generate migration plan for multiple entity types
    public func planMigrations(for types: [any EntityProtocol.Type]) throws -> MigrationPlan {
        var allStatements: [String] = []

        for type in types {
            let plan = try planMigrationForAnyType(type)
            allStatements.append(contentsOf: plan.statements)
        }

        return MigrationPlan(statements: allStatements)
    }

    /// Plan migration for any EntityProtocol type (type-erased version)
    private func planMigrationForAnyType(_ type: any EntityProtocol.Type) throws -> MigrationPlan {
        let tableName = type.tableName
        var statements: [String] = []

        if try connection.tableExists(tableName) {
            let alterStatements = try planTableMigrationForAnyType(type)
            statements.append(contentsOf: alterStatements)
        } else {
            let createStatement = generateCreateTableSQLForAnyType(type)
            statements.append(createStatement)

            for index in type.indexes {
                let indexSQL = index.toSQL(tableName: tableName)
                statements.append(indexSQL)
            }
        }

        return MigrationPlan(statements: statements)
    }

    /// Generate CREATE TABLE SQL for any entity type (type-erased version)
    private func generateCreateTableSQLForAnyType(_ type: any EntityProtocol.Type) -> String {
        let tableName = type.tableName
        var columnDefs: [String] = []

        for column in type.columns {
            columnDefs.append(column.toSQL())
        }

        for fk in type.foreignKeys {
            columnDefs.append(fk.toSQL())
        }

        return "CREATE TABLE \(tableName) (\n    \(columnDefs.joined(separator: ",\n    "))\n)"
    }

    /// Plan migration for existing table (type-erased version)
    private func planTableMigrationForAnyType(_ type: any EntityProtocol.Type) throws -> [String] {
        let tableName = type.tableName
        let existingColumns = try connection.tableInfo(tableName)
        let existingColumnNames = Set(existingColumns.compactMap { $0["name"] as? String })

        var statements: [String] = []

        for column in type.columns {
            if !existingColumnNames.contains(column.name) {
                if column.generatedAs != nil {
                    continue
                }

                var alterSQL =
                    "ALTER TABLE \(tableName) ADD COLUMN \(column.name) \(column.type.rawValue)"
                if !column.nullable {
                    if let defaultValue = column.defaultValue {
                        alterSQL += " NOT NULL DEFAULT \(defaultValue)"
                    } else {
                        let defaultVal = defaultValueForType(column.type)
                        alterSQL += " NOT NULL DEFAULT \(defaultVal)"
                    }
                }
                statements.append(alterSQL)
            }
        }

        let existingIndexes = try getExistingIndexNames(for: tableName)
        for index in type.indexes {
            if !existingIndexes.contains(index.name) {
                let indexSQL = index.toSQL(tableName: tableName)
                statements.append(indexSQL)
            }
        }

        return statements
    }

    /// Plan migration for existing table (returns ALTER statements)
    private func planTableMigration<E: EntityProtocol>(for type: E.Type) throws -> [String] {
        let tableName = E.tableName
        let existingColumns = try connection.tableInfo(tableName)
        let existingColumnNames = Set(existingColumns.compactMap { $0["name"] as? String })

        var statements: [String] = []

        // Check for new columns
        for column in E.columns {
            if !existingColumnNames.contains(column.name) {
                // Skip virtual columns for ALTER TABLE
                if column.generatedAs != nil {
                    continue
                }

                var alterSQL =
                    "ALTER TABLE \(tableName) ADD COLUMN \(column.name) \(column.type.rawValue)"
                if !column.nullable {
                    if let defaultValue = column.defaultValue {
                        alterSQL += " NOT NULL DEFAULT \(defaultValue)"
                    } else {
                        let defaultVal = defaultValueForType(column.type)
                        alterSQL += " NOT NULL DEFAULT \(defaultVal)"
                    }
                }
                statements.append(alterSQL)
            }
        }

        // Check for missing indexes
        let existingIndexes = try getExistingIndexNames(for: tableName)
        for index in E.indexes {
            if !existingIndexes.contains(index.name) {
                let indexSQL = index.toSQL(tableName: tableName)
                statements.append(indexSQL)
            }
        }

        return statements
    }

    /// Get existing index names for a table
    private func getExistingIndexNames(for tableName: String) throws -> Set<String> {
        let sql = "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name=?"
        let stmt = try connection.prepare(sql)
        try stmt.bind(1, tableName)

        var indexNames: Set<String> = []
        while try stmt.step() {
            if let name = stmt.columnString(0) {
                indexNames.insert(name)
            }
        }
        return indexNames
    }

    /// Create system tables (pending_deletes, etc.)
    public func createSystemTables() throws {
        let sql = """
            CREATE TABLE IF NOT EXISTS \(pendingDeletesTable) (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                table_name TEXT NOT NULL,
                entity_id BLOB NOT NULL
            )
            """
        try connection.execute(sql)
    }

    /// Create delete triggers for sync (captures deletes before they happen)
    public func createDeleteTriggers(for entityTypes: [String]) throws {
        for tableName in entityTypes {
            let triggerName = "__swiftstore_delete_\(tableName)"
            let sql = """
                CREATE TRIGGER IF NOT EXISTS \(triggerName)
                BEFORE DELETE ON \(tableName)
                FOR EACH ROW
                BEGIN
                    INSERT INTO \(pendingDeletesTable) (table_name, entity_id)
                    VALUES ('\(tableName)', OLD.id);
                END
                """
            try connection.execute(sql)
        }
    }

    /// Drop delete triggers for all entity types
    public func dropDeleteTriggers(for entityTypes: [String]) {
        for tableName in entityTypes {
            let triggerName = "__swiftstore_delete_\(tableName)"
            _ = try? connection.execute("DROP TRIGGER IF EXISTS \(triggerName)")
        }
    }

    private func defaultValueForType(_ type: SQLiteType) -> String {
        switch type {
        case .text:
            return "''"
        case .integer:
            return "0"
        case .real:
            return "0.0"
        case .blob:
            return "X''"
        }
    }

    /// Drop a table
    public func dropTable(_ tableName: String) throws {
        try connection.execute("DROP TABLE IF EXISTS \(tableName)")
    }

    /// Get all table names
    public func allTables() throws -> [String] {
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        let stmt = try connection.prepare(sql)

        var tables: [String] = []
        while try stmt.step() {
            if let name = stmt.columnString(0) {
                tables.append(name)
            }
        }
        return tables
    }
}
