import Foundation

/// Request model for SQL query execution
public struct QueryRequest: Codable, Sendable {
    /// The SQL statement to execute
    public let sql: String

    /// Parameters to bind to the SQL statement
    public let params: [JSONValue]?

    /// Page number for pagination (1-indexed)
    public let page: Int?

    /// Number of rows per page
    public let pageSize: Int?

    public init(
        sql: String,
        params: [JSONValue]? = nil,
        page: Int? = nil,
        pageSize: Int? = nil
    ) {
        self.sql = sql
        self.params = params
        self.page = page
        self.pageSize = pageSize
    }
}

/// Request model for SQL execute (INSERT/UPDATE/DELETE)
public struct ExecuteRequest: Codable, Sendable {
    /// The SQL statement to execute
    public let sql: String

    /// Parameters to bind to the SQL statement
    public let params: [JSONValue]?

    public init(sql: String, params: [JSONValue]? = nil) {
        self.sql = sql
        self.params = params
    }
}
