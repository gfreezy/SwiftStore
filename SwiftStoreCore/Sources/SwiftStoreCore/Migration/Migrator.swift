import Foundation

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
        let alterTables = statements.filter { $0.uppercased().hasPrefix("ALTER TABLE") }.count
        let createIndexes = statements.filter {
            $0.uppercased().hasPrefix("CREATE INDEX") || $0.uppercased().hasPrefix("CREATE UNIQUE INDEX")
        }.count
        let createTriggers = statements.filter { $0.uppercased().hasPrefix("CREATE TRIGGER") }.count

        var summary: [String] = []
        if createTables > 0 { summary.append("\(createTables) CREATE TABLE") }
        if alterTables > 0 { summary.append("\(alterTables) ALTER TABLE") }
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

    public static var pendingDeletesTableName: String { DatabaseSchemaBuilder.pendingDeletesTableName }

    public init(connection: SQLiteConnection, trackDeletes: Bool = false, createUpdateTrigger: Bool = true) {
        self.connection = connection

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
    public func plan(for types: [any EntityProtocol.Type]) throws -> MigrationPlan {
        let diff = try computeDiff(for: types)
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

    private func computeDiff(for types: [any EntityProtocol.Type]) throws -> DatabaseDiff {
        // Build all target schemas
        let targetSchemas = schemaBuilder.buildSchemas(from: types)

        // Read all current schemas from database
        let currentSchemas = try schemaReader.readAllSchemas()

        // Compute diffs
        let tableDiffs = targetSchemas.map { target in
            // currentSchemas[target.name] is nil if table doesn't exist yet -> needsCreate
            let current = currentSchemas[target.name]
            return SchemaDiff(current: current, target: target)
        }

        return DatabaseDiff(tableDiffs: tableDiffs)
    }
}
