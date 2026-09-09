import Foundation
import SwiftStoreProtocols

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
    let expectedSchemaVersion: Int64?

    init(statements: [String], expectedSchemaVersion: Int64? = nil) {
        self.statements = statements
        self.expectedSchemaVersion = expectedSchemaVersion
    }

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
        let dropTriggers = statements.filter { $0.uppercased().hasPrefix("DROP TRIGGER") }.count

        var summary: [String] = []
        if createTables > 0 { summary.append("\(createTables) CREATE TABLE") }
        if addColumns > 0 { summary.append("\(addColumns) ADD COLUMN") }
        if dropIndexes > 0 { summary.append("\(dropIndexes) DROP INDEX") }
        if dropColumns > 0 { summary.append("\(dropColumns) DROP COLUMN") }
        if createIndexes > 0 { summary.append("\(createIndexes) CREATE INDEX") }
        if createTriggers > 0 { summary.append("\(createTriggers) CREATE TRIGGER") }
        if dropTriggers > 0 { summary.append("\(dropTriggers) DROP TRIGGER") }

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
/// let migrator = Migrator(connection: connection)
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

    /// Initialize a migrator
    /// - Parameters:
    ///   - connection: SQLite connection
    ///   - createUpdateTrigger: Whether to create update triggers
    ///   - dropUnusedColumns: Whether to drop columns that exist in database but not in entity (default: false)
    public init(
        connection: SQLiteConnection,
        createUpdateTrigger: Bool = true,
        dropUnusedColumns: Bool = false
    ) {
        self.connection = connection
        self.dropUnusedColumns = dropUnusedColumns

        self.schemaReader = DatabaseSchemaReader(connection: connection)

        self.schemaBuilder = DatabaseSchemaBuilder(
            options: DatabaseSchemaBuildOptions(
                createUpdateTrigger: createUpdateTrigger
            )
        )

        self.sqlGenerator = MigrationSQLGenerator()
    }

    // MARK: - Public API

    /// Generate migration plan for entity types
    /// - Throws: `MigrationValidationError` if new non-nullable columns don't have default values
    public func plan(for types: [any EntityProtocol.Type]) throws -> MigrationPlan {
        let version: Int64 = try connection.queryScalar("PRAGMA schema_version") ?? 0
        let diff = try computeDiff(for: types)
        try validate(diff)
        let plan = sqlGenerator.generatePlan(from: diff)
        var updates: [String] = []
        for table in diff.tableDiffs {
            guard let current = table.current else { continue }
            let addedDates = table.columnsToAdd.filter {
                !$0.isNullable && $0.defaultValue == SQLiteTimestampSQL.now
            }
            let defaults = table.timestampDefaultsToUpgrade + addedDates
            guard !defaults.isEmpty else { continue }
            // Preview the post-ALTER definition in an empty database. This also
            // upgrades the temporary literal DEFAULT used when adding a Date column.
            var options = SQLiteConnection.Options()
            options.foreignKeys = false
            let preview = try SQLiteConnection(path: ":memory:", options: options)
            try preview.execute(current.sql)
            // Existing triggers/indexes are needed for DROP/replace statements.
            for index in current.indexes where !index.sql.isEmpty { try preview.execute(index.sql) }
            for trigger in current.triggers { try preview.execute(trigger.sql) }
            // Backfill UPDATEs do not affect schema and may invoke user triggers
            // that depend on other tables absent from this isolated preview.
            for statement in sqlGenerator.generateStatements(for: table) where !statement.hasPrefix("UPDATE ") {
                try preview.execute(statement)
            }
            let after: String = try preview.queryScalar(
                "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
                values: [.text(table.tableName)]) ?? ""
            let sql = try TimestampDefaultMigration.rewrite(after, columns: defaults,
                addedColumns: Set(addedDates.map(\.name)))
            let validation = try SQLiteConnection(path: ":memory:", options: options)
            try validation.execute(sql)
            updates.append("UPDATE sqlite_master SET sql = \(TimestampDefaultMigration.literal(sql)) WHERE type = 'table' AND name = \(TimestampDefaultMigration.literal(table.tableName))")
        }
        guard !updates.isEmpty else { return plan }
        let latestVersion: Int64? = try connection.queryScalar("PRAGMA schema_version")
        guard latestVersion == version else { throw TimestampDefaultMigration.Failure.stalePlan }
        // SQLite's documented DEFAULT-only migration changes the schema text,
        // not table contents. The schema cookie invalidates other connections' caches.
        // Each preceding DDL statement increments the cookie at most once.
        let statements = plan.statements + ["PRAGMA writable_schema = ON"] + updates + [
            "PRAGMA schema_version = \(version + Int64(plan.statements.count) + 1)",
            "PRAGMA writable_schema = RESET"
        ]
        return MigrationPlan(statements: statements, expectedSchemaVersion: version)
    }

    /// Compute diff without generating SQL
    public func diff(for types: [any EntityProtocol.Type]) throws -> DatabaseDiff {
        try computeDiff(for: types)
    }

    /// Apply a migration plan atomically, including trigger replacements.
    public func apply(_ plan: MigrationPlan) throws {
        guard plan.hasChanges else { return }
        if plan.expectedSchemaVersion != nil {
            try connection.withSchemaEditing { try applyStatements(plan) }
        } else {
            try applyStatements(plan)
        }
    }

    private func applyStatements(_ plan: MigrationPlan) throws {
        do {
            try connection.transaction {
                if let expected = plan.expectedSchemaVersion {
                    let current: Int64? = try connection.queryScalar("PRAGMA schema_version")
                    guard current == expected else { throw TimestampDefaultMigration.Failure.stalePlan }
                }
                for statement in plan.statements {
                    try connection.execute(statement)
                }
                if plan.expectedSchemaVersion != nil {
                    // Force parsing with writable_schema disabled before committing.
                    for name in try schemaReader.readAllSchemas().keys {
                        let quoted = name.replacingOccurrences(of: "\"", with: "\"\"")
                        _ = try connection.prepare("SELECT * FROM \"\(quoted)\" LIMIT 0")
                    }
                }
            }
        } catch {
            // writable_schema is connection state, so transaction rollback alone
            // does not disable it. Reload the restored schema after any failure.
            if plan.expectedSchemaVersion != nil { try connection.execute("PRAGMA writable_schema = RESET") }
            throw error
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
