import Foundation
import SwiftStoreConnectionQueue
import SwiftStoreCore

/// Handler for schema queries
public struct SchemaHandler: Sendable {
    private let connectionManager: ConnectionManager

    public init(connectionManager: ConnectionManager) {
        self.connectionManager = connectionManager
    }

    /// Get database schema
    public func getSchema() async throws -> SchemaResponse {
        do {
            let tables = try await connectionManager.read { connection in
                try self.readAllTables(connection: connection)
            }
            return .success(tables: tables)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Read all table schemas
    private func readAllTables(connection: SQLiteConnection) throws -> [TableInfo] {
        // Get all table names (excluding sqlite system tables)
        let tableNames = try getTableNames(connection: connection)

        var tables: [TableInfo] = []
        for tableName in tableNames {
            let columns = try getColumns(connection: connection, tableName: tableName)
            tables.append(TableInfo(name: tableName, columns: columns))
        }

        return tables.sorted { $0.name < $1.name }
    }

    /// Get all table names
    private func getTableNames(connection: SQLiteConnection) throws -> [String] {
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        let stmt = try connection.prepare(sql)

        var names: [String] = []
        while try stmt.step() {
            if let name = stmt.columnString(0) {
                names.append(name)
            }
        }
        return names
    }

    /// Get columns for a table
    private func getColumns(connection: SQLiteConnection, tableName: String) throws -> [ColumnInfo] {
        let tableInfo = try connection.tableInfo(tableName)

        return tableInfo.compactMap { row -> ColumnInfo? in
            guard let name = row["name"] as? String,
                  let type = row["type"] as? String else {
                return nil
            }

            let notNull = row["notnull"] as? Bool ?? false
            let isPrimaryKey = row["pk"] as? Bool ?? false
            let defaultValue = row["dflt_value"] as? String

            return ColumnInfo(
                name: name,
                type: type,
                nullable: !notNull,
                pk: isPrimaryKey,
                defaultValue: defaultValue
            )
        }
    }
}
