import Foundation

// MARK: - Migration Validation Errors

/// Error thrown when new non-nullable columns don't have default values
public struct MigrationValidationError: Error, CustomStringConvertible {
    public let columnsWithoutDefault: [(tableName: String, columnName: String)]

    public var description: String {
        let details = columnsWithoutDefault.map { "\($0.tableName).\($0.columnName)" }.joined(separator: ", ")
        return "Migration validation failed: New non-nullable columns must have a default value: \(details)"
    }
}

/// Error thrown when column types don't match between database and entity
public struct ColumnTypeMismatchError: Error, CustomStringConvertible {
    public let mismatches: [(tableName: String, columnName: String, databaseType: String, entityType: String)]

    public var description: String {
        let details = mismatches.map {
            "\($0.tableName).\($0.columnName): database has '\($0.databaseType)', entity expects '\($0.entityType)'"
        }.joined(separator: "; ")
        return "Migration validation failed: Column type mismatch: \(details)"
    }
}

/// Migration plan containing SQL statements to be executed
public struct MigrationPlan: Sendable, CustomStringConvertible {
    public let statements: [String]

    public var hasChanges: Bool { !statements.isEmpty }

    public var script: String {
        statements.joined(separator: ";\n") + (statements.isEmpty ? "" : ";")
    }

    public var description: String {
        guard hasChanges else {
            return "MigrationPlan: No changes needed"
        }

        var lines: [String] = []
        lines.append("MigrationPlan: \(statements.count) statement(s)")

        // Count statement types
        let createTables = statements.filter { $0.uppercased().hasPrefix("CREATE TABLE") }.count
        let addColumns = statements.filter { $0.uppercased().contains("ADD COLUMN") }.count
        let dropIndexes = statements.filter { $0.uppercased().hasPrefix("DROP INDEX") }.count
        let dropColumns = statements.filter { $0.uppercased().contains("DROP COLUMN") }.count
        let createIndexes = statements.filter {
            $0.uppercased().hasPrefix("CREATE INDEX") || $0.uppercased().hasPrefix("CREATE UNIQUE INDEX")
        }.count
        let createTriggers = statements.filter { $0.uppercased().hasPrefix("CREATE TRIGGER") }.count

        var summary: [String] = []
        if createTables > 0 { summary.append("\(createTables) CREATE TABLE") }
        if addColumns > 0 { summary.append("\(addColumns) ADD COLUMN") }
        if dropIndexes > 0 { summary.append("\(dropIndexes) DROP INDEX") }
        if dropColumns > 0 { summary.append("\(dropColumns) DROP COLUMN") }
        if createIndexes > 0 { summary.append("\(createIndexes) CREATE INDEX") }
        if createTriggers > 0 { summary.append("\(createTriggers) CREATE TRIGGER") }

        if !summary.isEmpty {
            lines.append("  " + summary.joined(separator: ", "))
        }

        lines.append("")
        lines.append("SQL:")
        lines.append(script)

        return lines.joined(separator: "\n")
    }
}

/// Database schema migrator
///
/// Usage:
/// ```swift
/// let migrator = Migrator(connection: connection, trackDeletes: true)
///
/// // Step 1: Generate migration plan
/// let plan = try migrator.plan(for: [User.self, Post.self])
///
/// // Step 2: Apply the plan
/// try migrator.apply(plan)
/// ```
public final class Migrator {
    private let connection: SQLiteConnection
    private let schemaReader: DatabaseSchemaReader
    private let schemaBuilder: DatabaseSchemaBuilder
    private let sqlGenerator: MigrationSQLGenerator
    private let dropUnusedColumns: Bool

    public static var pendingDeletesTableName: String { DatabaseSchemaBuilder.pendingDeletesTableName }

    /// Initialize a migrator
    /// - Parameters:
    ///   - connection: SQLite connection
    ///   - trackDeletes: Whether to track deletes for sync
    ///   - createUpdateTrigger: Whether to create update triggers
    ///   - dropUnusedColumns: Whether to drop columns that exist in database but not in entity (default: false)
    public init(
        connection: SQLiteConnection,
        trackDeletes: Bool = false,
        createUpdateTrigger: Bool = true,
        dropUnusedColumns: Bool = false
    ) {
        self.connection = connection
        self.dropUnusedColumns = dropUnusedColumns

        self.schemaReader = DatabaseSchemaReader(connection: connection)

        self.schemaBuilder = DatabaseSchemaBuilder(
            options: DatabaseSchemaBuildOptions(
                createUpdateTrigger: createUpdateTrigger,
                trackDeletes: trackDeletes
            )
        )

        self.sqlGenerator = MigrationSQLGenerator()
    }

    // MARK: - Public API

    /// Generate migration plan for entity types
    /// - Throws: `MigrationValidationError` if new non-nullable columns don't have default values
    public func plan(for types: [any EntityProtocol.Type]) throws -> MigrationPlan {
        let diff = try computeDiff(for: types)
        try validate(diff)
        return sqlGenerator.generatePlan(from: diff)
    }

    /// Compute diff without generating SQL
    public func diff(for types: [any EntityProtocol.Type]) throws -> DatabaseDiff {
        try computeDiff(for: types)
    }

    /// Apply a migration plan
    public func apply(_ plan: MigrationPlan) throws {
        for statement in plan.statements {
            try connection.execute(statement)
        }
    }

    // MARK: - Private

    /// Validate schema compatibility
    private func validate(_ diff: DatabaseDiff) throws {
        var columnsWithoutDefault: [(tableName: String, columnName: String)] = []
        var typeMismatches: [(tableName: String, columnName: String, databaseType: String, entityType: String)] = []

        for tableDiff in diff.tableDiffs {
            // Check for type mismatches (applies to existing tables only)
            if !tableDiff.needsCreate {
                for mismatch in tableDiff.columnsWithTypeMismatch {
                    typeMismatches.append((
                        tableName: tableDiff.tableName,
                        columnName: mismatch.name,
                        databaseType: mismatch.currentType,
                        entityType: mismatch.targetType
                    ))
                }

                // Check for missing default values on new columns
                for column in tableDiff.columnsToAdd {
                    if !column.isNullable && column.defaultValue == nil {
                        columnsWithoutDefault.append((tableDiff.tableName, column.name))
                    }
                }
            }
        }

        // Type mismatch is a more serious error, check it first
        if !typeMismatches.isEmpty {
            throw ColumnTypeMismatchError(mismatches: typeMismatches)
        }

        if !columnsWithoutDefault.isEmpty {
            throw MigrationValidationError(columnsWithoutDefault: columnsWithoutDefault)
        }
    }

    private func computeDiff(for types: [any EntityProtocol.Type]) throws -> DatabaseDiff {
        // Build all target schemas
        let targetSchemas = schemaBuilder.buildSchemas(from: types)

        // Read all current schemas from database
        let currentSchemas = try schemaReader.readAllSchemas()

        // Compute diffs
        let tableDiffs = targetSchemas.map { target in
            // currentSchemas[target.name] is nil if table doesn't exist yet -> needsCreate
            let current = currentSchemas[target.name]
            return SchemaDiff(current: current, target: target, dropUnusedColumns: dropUnusedColumns)
        }

        return DatabaseDiff(tableDiffs: tableDiffs)
    }
}
