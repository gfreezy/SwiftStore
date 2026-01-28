import Foundation

/// Pagination information
public struct PaginationInfo: Codable, Sendable {
    /// Current page number (1-indexed)
    public let page: Int

    /// Number of rows per page
    public let pageSize: Int

    /// Total number of rows matching the query
    public let totalRows: Int

    /// Total number of pages
    public let totalPages: Int

    public init(page: Int, pageSize: Int, totalRows: Int) {
        self.page = page
        self.pageSize = pageSize
        self.totalRows = totalRows
        self.totalPages = pageSize > 0 ? max(1, (totalRows + pageSize - 1) / pageSize) : 1
    }
}

/// Response model for SQL query
public struct QueryResponse: Codable, Sendable {
    /// Whether the query succeeded
    public let success: Bool

    /// Error message if query failed
    public let error: String?

    /// Query result data
    public let data: [JSONValue]?

    /// Column names in order
    public let columns: [String]?

    /// Number of rows returned
    public let rowCount: Int?

    /// Pagination information (if pagination was requested)
    public let pagination: PaginationInfo?

    public init(
        success: Bool,
        error: String? = nil,
        data: [JSONValue]? = nil,
        columns: [String]? = nil,
        rowCount: Int? = nil,
        pagination: PaginationInfo? = nil
    ) {
        self.success = success
        self.error = error
        self.data = data
        self.columns = columns
        self.rowCount = rowCount
        self.pagination = pagination
    }

    /// Create a success response
    public static func success(
        data: [JSONValue],
        columns: [String],
        pagination: PaginationInfo? = nil
    ) -> QueryResponse {
        QueryResponse(
            success: true,
            data: data,
            columns: columns,
            rowCount: data.count,
            pagination: pagination
        )
    }

    /// Create an error response
    public static func error(_ message: String) -> QueryResponse {
        QueryResponse(success: false, error: message)
    }
}

/// Response model for SQL execute (INSERT/UPDATE/DELETE)
public struct ExecuteResponse: Codable, Sendable {
    /// Whether the execution succeeded
    public let success: Bool

    /// Error message if execution failed
    public let error: String?

    /// Number of rows affected
    public let rowsAffected: Int?

    public init(success: Bool, error: String? = nil, rowsAffected: Int? = nil) {
        self.success = success
        self.error = error
        self.rowsAffected = rowsAffected
    }

    /// Create a success response
    public static func success(rowsAffected: Int) -> ExecuteResponse {
        ExecuteResponse(success: true, rowsAffected: rowsAffected)
    }

    /// Create an error response
    public static func error(_ message: String) -> ExecuteResponse {
        ExecuteResponse(success: false, error: message)
    }
}

/// Response model for schema query
public struct SchemaResponse: Codable, Sendable {
    /// Whether the query succeeded
    public let success: Bool

    /// Error message if query failed
    public let error: String?

    /// List of tables with their columns
    public let tables: [TableInfo]?

    public init(success: Bool, error: String? = nil, tables: [TableInfo]? = nil) {
        self.success = success
        self.error = error
        self.tables = tables
    }

    /// Create a success response
    public static func success(tables: [TableInfo]) -> SchemaResponse {
        SchemaResponse(success: true, tables: tables)
    }

    /// Create an error response
    public static func error(_ message: String) -> SchemaResponse {
        SchemaResponse(success: false, error: message)
    }
}

/// Table information
public struct TableInfo: Codable, Sendable {
    /// Table name
    public let name: String

    /// Column definitions
    public let columns: [ColumnInfo]

    public init(name: String, columns: [ColumnInfo]) {
        self.name = name
        self.columns = columns
    }
}

/// Column information
public struct ColumnInfo: Codable, Sendable {
    /// Column name
    public let name: String

    /// Column type (e.g., "TEXT", "INTEGER", "BLOB")
    public let type: String

    /// Whether the column is nullable
    public let nullable: Bool

    /// Whether the column is a primary key
    public let pk: Bool

    /// Default value (if any)
    public let defaultValue: String?

    public init(
        name: String,
        type: String,
        nullable: Bool,
        pk: Bool,
        defaultValue: String? = nil
    ) {
        self.name = name
        self.type = type
        self.nullable = nullable
        self.pk = pk
        self.defaultValue = defaultValue
    }
}

/// Health check response
public struct HealthResponse: Codable, Sendable {
    /// Server status
    public let status: String

    /// Server timestamp
    public let timestamp: String

    public init(status: String = "ok") {
        self.status = status
        let formatter = ISO8601DateFormatter()
        self.timestamp = formatter.string(from: Date())
    }
}
