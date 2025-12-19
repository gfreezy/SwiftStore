import Foundation

/// Query builder for fetching entities
public struct Query<T: EntityProtocol>: Sendable {
    private let store: Store
    private var predicates: [Predicate<T>] = []
    private var orderBys: [(column: String, ascending: Bool)] = []
    private var limitValue: Int?
    private var offsetValue: Int?

    init(store: Store) {
        self.store = store
    }

    /// Add a WHERE predicate
    public func `where`(_ predicate: Predicate<T>) -> Query<T> {
        var query = self
        query.predicates.append(predicate)
        return query
    }

    /// Add ORDER BY clause
    public func order<V>(by keyPath: KeyPath<T, V>, ascending: Bool = true) -> Query<T> {
        var query = self
        let column = columnName(for: keyPath)
        query.orderBys.append((column, ascending))
        return query
    }

    /// Add LIMIT clause
    public func limit(_ count: Int) -> Query<T> {
        var query = self
        query.limitValue = count
        return query
    }

    /// Add OFFSET clause
    public func offset(_ count: Int) -> Query<T> {
        var query = self
        query.offsetValue = count
        return query
    }

    /// Build the SQL query
    func buildSQL() -> (sql: String, values: [SQLiteValue]) {
        var sql = "SELECT * FROM \(T.tableName)"
        var values: [SQLiteValue] = []

        // WHERE clause
        if !predicates.isEmpty {
            let whereClause = predicates.map { $0.sql }.joined(separator: " AND ")
            sql += " WHERE \(whereClause)"
            values = predicates.flatMap { $0.values }
        }

        // ORDER BY clause
        if !orderBys.isEmpty {
            let orderClause = orderBys.map { "\($0.column) \($0.ascending ? "ASC" : "DESC")" }.joined(separator: ", ")
            sql += " ORDER BY \(orderClause)"
        }

        // LIMIT clause
        if let limit = limitValue {
            sql += " LIMIT \(limit)"
        }

        // OFFSET clause
        if let offset = offsetValue {
            sql += " OFFSET \(offset)"
        }

        return (sql, values)
    }

    /// Execute query and return all results
    public func all() throws -> [T] {
        let (sql, values) = buildSQL()
        return try store.executeQuery(sql: sql, values: values, type: T.self)
    }

    /// Execute query and return first result
    public func first() throws -> T? {
        let query = self.limit(1)
        let results = try query.all()
        return results.first
    }

    /// Execute query and return count
    public func count() throws -> Int {
        var sql = "SELECT COUNT(*) FROM \(T.tableName)"
        var values: [SQLiteValue] = []

        if !predicates.isEmpty {
            let whereClause = predicates.map { $0.sql }.joined(separator: " AND ")
            sql += " WHERE \(whereClause)"
            values = predicates.flatMap { $0.values }
        }

        return try store.executeCount(sql: sql, values: values)
    }

    /// Check if any records exist matching the query
    public func exists() throws -> Bool {
        try count() > 0
    }
}
