import Foundation
import SwiftStoreConnectionQueue
import SwiftStoreCore
import SwiftStoreProtocols

/// Handler for SQL query operations
public struct QueryHandler: Sendable {
    private let connectionManager: ConnectionManager
    private let configuration: ServerConfiguration

    public init(connectionManager: ConnectionManager, configuration: ServerConfiguration) {
        self.connectionManager = connectionManager
        self.configuration = configuration
    }

    /// Handle SQL query with pagination
    public func handleQuery(_ request: QueryRequest) async throws -> QueryResponse {
        let sql = request.sql.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate SQL is a SELECT query (not empty and starts with SELECT)
        guard !sql.isEmpty else {
            return .error("SQL cannot be empty")
        }

        let upperSQL = sql.uppercased()
        guard upperSQL.hasPrefix("SELECT") || upperSQL.hasPrefix("WITH") || upperSQL.hasPrefix("PRAGMA") else {
            return .error("Only SELECT, WITH, or PRAGMA queries are allowed. Use /api/execute for modifications.")
        }

        // Convert parameters
        let params = (request.params ?? []).map { $0.toSQLiteValue() }

        // Determine pagination
        let page = max(1, request.page ?? 1)
        let requestedPageSize = request.pageSize ?? configuration.defaultPageSize
        let pageSize = min(max(1, requestedPageSize), configuration.maxPageSize)

        do {
            // Execute query with pagination
            let result = try await connectionManager.read { connection in
                try executeWithPagination(
                    connection: connection,
                    sql: sql,
                    params: params,
                    page: page,
                    pageSize: pageSize
                )
            }
            return result
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Execute query with pagination
    private func executeWithPagination(
        connection: SQLiteConnection,
        sql: String,
        params: [SQLiteValue],
        page: Int,
        pageSize: Int
    ) throws -> QueryResponse {
        // First, get total count
        let countSQL = "SELECT COUNT(*) FROM (\(sql)) AS _counted"
        let totalRows: Int

        do {
            if let count: Int64 = try connection.queryScalar(countSQL, values: params) {
                totalRows = Int(count)
            } else {
                totalRows = 0
            }
        } catch {
            // If count fails (e.g., for PRAGMA), proceed without pagination
            return try executeWithoutPagination(connection: connection, sql: sql, params: params)
        }

        // Execute paginated query
        let offset = (page - 1) * pageSize
        let paginatedSQL = "\(sql) LIMIT \(pageSize) OFFSET \(offset)"

        let stmt = try connection.prepareAndBind(paginatedSQL, values: params)

        // Get column names
        var columns: [String] = []
        for i in 0..<stmt.columnCount {
            if let name = stmt.columnName(i) {
                columns.append(name)
            }
        }

        // Collect rows as JSONValue objects
        var data: [JSONValue] = []
        while try stmt.step() {
            var row: [String: JSONValue] = [:]
            for i in 0..<stmt.columnCount {
                if let name = stmt.columnName(i) {
                    row[name] = JSONValue(sqliteValue: stmt.sqliteValue(i))
                }
            }
            data.append(.object(row))
        }

        let pagination = PaginationInfo(page: page, pageSize: pageSize, totalRows: totalRows)
        return .success(data: data, columns: columns, pagination: pagination)
    }

    /// Execute query without pagination (for PRAGMA or when count fails)
    private func executeWithoutPagination(
        connection: SQLiteConnection,
        sql: String,
        params: [SQLiteValue]
    ) throws -> QueryResponse {
        let stmt = try connection.prepareAndBind(sql, values: params)

        // Get column names
        var columns: [String] = []
        for i in 0..<stmt.columnCount {
            if let name = stmt.columnName(i) {
                columns.append(name)
            }
        }

        // Collect all rows
        var data: [JSONValue] = []
        while try stmt.step() {
            var row: [String: JSONValue] = [:]
            for i in 0..<stmt.columnCount {
                if let name = stmt.columnName(i) {
                    row[name] = JSONValue(sqliteValue: stmt.sqliteValue(i))
                }
            }
            data.append(.object(row))
        }

        return .success(data: data, columns: columns)
    }

    /// Handle SQL execute (INSERT/UPDATE/DELETE)
    public func handleExecute(_ request: ExecuteRequest) async throws -> ExecuteResponse {
        // Check read-only mode
        if configuration.readOnly {
            return .error("Server is in read-only mode")
        }

        let sql = request.sql.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate SQL is not empty
        guard !sql.isEmpty else {
            return .error("SQL cannot be empty")
        }

        // Block SELECT queries
        let upperSQL = sql.uppercased()
        if upperSQL.hasPrefix("SELECT") || upperSQL.hasPrefix("WITH") {
            return .error("SELECT queries should use /api/query endpoint")
        }

        // Convert parameters
        let params = (request.params ?? []).map { $0.toSQLiteValue() }

        do {
            let rowsAffected = try await connectionManager.write { connection in
                try connection.execute(sql, values: params)
            }
            return .success(rowsAffected: rowsAffected)
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
