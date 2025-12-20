import Foundation
import SwiftStoreProtocols

/// Options for building target schema
public struct DatabaseSchemaBuildOptions: Sendable {
    /// Add update trigger to schema
    public var createUpdateTrigger: Bool

    /// Add delete trigger to schema
    public var trackDeletes: Bool

    public init(
        createUpdateTrigger: Bool = true,
        trackDeletes: Bool = false,
    ) {
        self.createUpdateTrigger = createUpdateTrigger
        self.trackDeletes = trackDeletes
    }

    public static let `default` = DatabaseSchemaBuildOptions()
}

/// Builds TableSchema from EntityProtocol definitions
public struct DatabaseSchemaBuilder {
    public static let pendingDeletesTableName = "__swiftstore_pending_deletes"
    public let options: DatabaseSchemaBuildOptions

    public init(options: DatabaseSchemaBuildOptions = .default) {
        self.options = options
    }

    /// Build TableSchema for multiple entities
    public func buildSchemas(from entities: [any EntityProtocol.Type]) -> [TableSchema] {
        var schemas = entities.map { buildSchema(from: $0) }

        // Add delete tracking table if needed
        if options.trackDeletes {
            schemas.append(buildDeleteTrackingTable())
        }

        return schemas
    }

    // MARK: - Private

    /// Build TableSchema from an EntityProtocol type
    private func buildSchema(from entity: any EntityProtocol.Type) -> TableSchema {
        let columns = buildColumns(from: entity)
        let indexes = buildIndexes(from: entity)
        let triggers = buildTriggers(for: entity.tableName)
        let foreignKeys = buildForeignKeys(from: entity)

        return TableSchema(
            name: entity.tableName,
            columns: columns,
            indexes: indexes,
            triggers: triggers,
            foreignKeys: foreignKeys
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

    private func buildForeignKeys(from entity: any EntityProtocol.Type) -> [ForeignKeySchema] {
        entity.foreignKeys.map { fk in
            ForeignKeySchema(
                column: fk.column,
                referencesTable: fk.referencesTable,
                referencesColumn: fk.referencesColumn,
                onDelete: ForeignKeySchema.ForeignKeyAction(rawValue: fk.onDelete.rawValue) ?? .noAction,
                onUpdate: ForeignKeySchema.ForeignKeyAction(rawValue: fk.onUpdate.rawValue) ?? .noAction
            )
        }
    }

    private func buildTriggers(for tableName: String) -> [TriggerSchema] {
        var triggers: [TriggerSchema] = []

        if options.createUpdateTrigger {
            triggers.append(buildUpdateTrigger(for: tableName))
        }

        if options.trackDeletes {
            triggers.append(buildDeleteTrigger(for: tableName))
        }

        return triggers
    }

    private func buildUpdateTrigger(for tableName: String) -> TriggerSchema {
        let name = "__swiftstore_update_\(tableName)"
        let body = """
            UPDATE \(tableName) SET updated_at = strftime('%s', 'now')
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

    private func buildDeleteTrigger(for tableName: String) -> TriggerSchema {
        let name = "__swiftstore_delete_\(tableName)"
        let body = """
            INSERT INTO __swiftstore_pending_deletes (table_name, entity_id)
            VALUES ('\(tableName)', OLD.id);
        """
        let sql = """
            CREATE TRIGGER IF NOT EXISTS \(name)
            BEFORE DELETE ON \(tableName)
            FOR EACH ROW
            BEGIN
                \(body)
            END
            """

        return TriggerSchema(
            name: name,
            event: .delete,
            timing: .before,
            condition: nil,
            body: body,
            sql: sql
        )
    }

    private func buildDeleteTrackingTable() -> TableSchema {
        TableSchema(
            name: Self.pendingDeletesTableName,
            columns: [
                ColumnSchema(name: "id", type: "INTEGER", isPrimaryKey: true),
                ColumnSchema(name: "table_name", type: "TEXT"),
                ColumnSchema(name: "entity_id", type: "BLOB")
            ]
        )
    }
}

