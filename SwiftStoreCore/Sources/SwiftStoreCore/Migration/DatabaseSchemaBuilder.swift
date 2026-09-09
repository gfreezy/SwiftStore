import Foundation
import SwiftStoreProtocols

/// Options for building target schema
public struct DatabaseSchemaBuildOptions: Sendable {
    /// Add update trigger to schema
    public var createUpdateTrigger: Bool

    public init(
        createUpdateTrigger: Bool = true,
    ) {
        self.createUpdateTrigger = createUpdateTrigger
    }

    public static let `default` = DatabaseSchemaBuildOptions()
}

/// Builds TableSchema from EntityProtocol definitions
public struct DatabaseSchemaBuilder {
    public let options: DatabaseSchemaBuildOptions

    public init(options: DatabaseSchemaBuildOptions = .default) {
        self.options = options
    }

    /// Build TableSchema for multiple entities
    public func buildSchemas(from entities: [any EntityProtocol.Type]) -> [TableSchema] {
        entities.map { buildSchema(from: $0) }
    }

    // MARK: - Private

    /// Build TableSchema from an EntityProtocol type
    private func buildSchema(from entity: any EntityProtocol.Type) -> TableSchema {
        let columns = buildColumns(from: entity)
        let indexes = buildIndexes(from: entity)
        let triggers = buildTriggers(for: entity)

        return TableSchema(
            name: entity.tableName,
            columns: columns,
            indexes: indexes,
            triggers: triggers
        )
    }

    private func buildColumns(from entity: any EntityProtocol.Type) -> [ColumnSchema] {
        entity.columns.map { col in
            return ColumnSchema(
                name: col.name,
                type: col.type.rawValue,
                isNullable: col.nullable,
                isPrimaryKey: col.primaryKey,
                defaultValue: col.defaultValue,
                generatedAs: col.generatedAs
            )
        }
    }

    private func buildIndexes(from entity: any EntityProtocol.Type) -> [IndexSchema] {
        entity.indexes.map { idx in
            IndexSchema(
                name: idx.name,
                columns: idx.columns,
                isUnique: idx.unique
            )
        }
    }

    private func buildTriggers(for entity: any EntityProtocol.Type) -> [TriggerSchema] {
        var triggers: [TriggerSchema] = []

        // Only create update trigger if entity has updated_at column
        let hasUpdatedAt = entity.columns.contains { $0.name == "updated_at" }
        if options.createUpdateTrigger && hasUpdatedAt {
            triggers.append(buildUpdateTrigger(for: entity.tableName))
        }

        return triggers
    }

    private func buildUpdateTrigger(for tableName: String) -> TriggerSchema {
        let name = "__swiftstore_update_\(tableName)"
        let body = """
            UPDATE \(tableName) SET updated_at = \(SQLiteTimestampSQL.now)
            WHERE rowid = NEW.rowid;
        """
        let sql = """
            CREATE TRIGGER IF NOT EXISTS \(name)
            AFTER UPDATE ON \(tableName)
            FOR EACH ROW
            WHEN NEW.updated_at = OLD.updated_at
            BEGIN
                \(body)
            END
            """

        return TriggerSchema(
            name: name,
            event: .update,
            timing: .after,
            condition: "NEW.updated_at = OLD.updated_at",
            body: body,
            sql: sql
        )
    }
}
