import Foundation

/// Migration plan containing SQL statements to be executed
public struct MigrationPlan: Sendable {
    public let statements: [String]

    public var hasChanges: Bool { !statements.isEmpty }

    public var script: String {
        statements.joined(separator: ";\n") + (statements.isEmpty ? "" : ";")
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
