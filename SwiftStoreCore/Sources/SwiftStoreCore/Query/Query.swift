import Foundation

/// Query builder for fetching entities
/// Inspired by GRDB's query interface
public struct Query<T: EntityProtocol> {
    private var predicates: [Predicate<T>] = []
    private var orderBys: [(column: String, ascending: Bool)] = []
    private var limitValue: Int?
    private var offsetValue: Int?
    private var isDistinct: Bool = false
    private var selectedColumns: [String]?

    // MARK: - Filtering
    public init(_ type: T.Type) {
    }

    /// Add a WHERE predicate (GRDB-style alias for `where`)
    public func filter(_ predicate: Predicate<T>) -> Query<T> {
        var query = self
        query.predicates.append(predicate)
        return query
    }

    /// Add a WHERE predicate using closure with dynamic member lookup
    /// Usage: `.filter { $0.age >= 25 }`
    public func filter(_ buildPredicate: (Columns<T>) -> Predicate<T>) -> Query<T> {
        filter(buildPredicate(Columns()))
    }

    // MARK: - Distinct

    /// Add DISTINCT to the query
    public func distinct() -> Query<T> {
        var query = self
        query.isDistinct = true
        return query
    }

    // MARK: - Column Selection

    /// Select specific columns (for partial fetches)
    public func select(_ columns: String...) -> Query<T> {
        var query = self
        query.selectedColumns = columns
        return query
    }

    /// Select columns using KeyPaths
    public func select<V>(_ keyPaths: KeyPath<T, V>...) -> Query<T> {
        var query = self
        query.selectedColumns = keyPaths.map { columnName(for: $0) }
        return query
    }

    // MARK: - Ordering

    /// Add ORDER BY clause
    public func order<V>(by keyPath: KeyPath<T, V>, ascending: Bool = true) -> Query<T> {
        var query = self
        let column = columnName(for: keyPath)
        query.orderBys.append((column, ascending))
        return query
    }

    /// Add ORDER BY clause using column name
    public func order(by column: String, ascending: Bool = true) -> Query<T> {
        var query = self
        query.orderBys.append((column, ascending))
        return query
    }

    /// Order by ascending
    public func order<V>(by keyPath: KeyPath<T, V>) -> Query<T> {
        order(by: keyPath, ascending: true)
    }

    /// Order by descending
    public func orderDesc<V>(by keyPath: KeyPath<T, V>) -> Query<T> {
        order(by: keyPath, ascending: false)
    }

    // MARK: - Pagination

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

    // MARK: - SQL Building

    /// Build the SQL query
    func buildSQL() -> (sql: String, values: [SQLiteValue]) {
        let selectClause: String
        if let columns = selectedColumns {
            selectClause = columns.joined(separator: ", ")
        } else {
            selectClause = "*"
        }

        let distinctClause = isDistinct ? "DISTINCT " : ""
        var sql = "SELECT \(distinctClause)\(selectClause) FROM \(T.tableName)"
        var values: [SQLiteValue] = []

        // WHERE clause
        if !predicates.isEmpty {
            let whereClause = predicates.map { $0.sql }.joined(separator: " AND ")
            sql += " WHERE \(whereClause)"
            values = predicates.flatMap { $0.values }
        }

        // ORDER BY clause
        if !orderBys.isEmpty {
            let orderClause = orderBys.map { "\($0.column) \($0.ascending ? "ASC" : "DESC")" }
                .joined(separator: ", ")
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

    // MARK: - Execution

    /// Execute query and return all results
    public func all(_ connection: SQLiteConnection) throws -> [T] {
        let (sql, values) = buildSQL()
        return try connection.executeQuery(sql: sql, values: values, type: T.self)
    }

    /// Execute query and return all results (GRDB-style alias)
    public func fetchAll(_ connection: SQLiteConnection) throws -> [T] {
        try all(connection)
    }

    /// Execute query and return first result
    public func first(_ connection: SQLiteConnection) throws -> T? {
        let query = self.limit(1)
        let results = try query.all(connection)
        return results.first
    }

    /// Execute query and return first result (GRDB-style alias)
    public func fetchOne(_ connection: SQLiteConnection) throws -> T? {
        try first(connection)
    }

    /// Execute query and return count
    public func count(_ connection: SQLiteConnection) throws -> Int {
        var sql = "SELECT COUNT(\(isDistinct ? "DISTINCT *" : "*")) FROM \(T.tableName)"
        var values: [SQLiteValue] = []

        if !predicates.isEmpty {
            let whereClause = predicates.map { $0.sql }.joined(separator: " AND ")
            sql += " WHERE \(whereClause)"
            values = predicates.flatMap { $0.values }
        }

        return try connection.queryScalar(sql, values: values, type: Int.self) ?? 0
    }

    /// Check if any records exist matching the query
    public func exists(_ connection: SQLiteConnection) throws -> Bool {
        try count(connection) > 0
    }

    /// Check if no records exist matching the query
    public func isEmpty(_ connection: SQLiteConnection) throws -> Bool {
        try count(connection) == 0
    }

    // MARK: - Aggregate Functions

    /// Get the minimum value of a column
    public func min<V: SQLiteComparable>(_ keyPath: KeyPath<T, V>, _ connection: SQLiteConnection) throws -> V? {
        let column = columnName(for: keyPath)
        var sql = "SELECT MIN(\(column)) FROM \(T.tableName)"
        var values: [SQLiteValue] = []

        if !predicates.isEmpty {
            let whereClause = predicates.map { $0.sql }.joined(separator: " AND ")
            sql += " WHERE \(whereClause)"
            values = predicates.flatMap { $0.values }
        }

        return try connection.queryScalar(sql, values: values, type: V.self)
    }

    /// Get the minimum value of an optional column
    public func min<V: SQLiteComparable>(_ keyPath: KeyPath<T, V?>, _ connection: SQLiteConnection) throws -> V? {
        let column = columnName(for: keyPath)
        var sql = "SELECT MIN(\(column)) FROM \(T.tableName)"
        var values: [SQLiteValue] = []

        if !predicates.isEmpty {
            let whereClause = predicates.map { $0.sql }.joined(separator: " AND ")
            sql += " WHERE \(whereClause)"
            values = predicates.flatMap { $0.values }
        }

        return try connection.queryScalar(sql, values: values, type: V.self)
    }

    /// Get the maximum value of a column
    public func max<V: SQLiteComparable>(_ keyPath: KeyPath<T, V>, _ connection: SQLiteConnection) throws -> V? {
        let column = columnName(for: keyPath)
        var sql = "SELECT MAX(\(column)) FROM \(T.tableName)"
        var values: [SQLiteValue] = []

        if !predicates.isEmpty {
            let whereClause = predicates.map { $0.sql }.joined(separator: " AND ")
            sql += " WHERE \(whereClause)"
            values = predicates.flatMap { $0.values }
        }

        return try connection.queryScalar(sql, values: values, type: V.self)
    }

    /// Get the maximum value of an optional column
    public func max<V: SQLiteComparable>(_ keyPath: KeyPath<T, V?>, _ connection: SQLiteConnection) throws -> V? {
        let column = columnName(for: keyPath)
        var sql = "SELECT MAX(\(column)) FROM \(T.tableName)"
        var values: [SQLiteValue] = []

        if !predicates.isEmpty {
            let whereClause = predicates.map { $0.sql }.joined(separator: " AND ")
            sql += " WHERE \(whereClause)"
            values = predicates.flatMap { $0.values }
        }

        return try connection.queryScalar(sql, values: values, type: V.self)
    }

    /// Get the sum of a column (Int)
    public func sum(_ keyPath: KeyPath<T, Int>, _ connection: SQLiteConnection) throws -> Int {
        let column = columnName(for: keyPath)
        var sql = "SELECT SUM(\(column)) FROM \(T.tableName)"
        var values: [SQLiteValue] = []

        if !predicates.isEmpty {
            let whereClause = predicates.map { $0.sql }.joined(separator: " AND ")
            sql += " WHERE \(whereClause)"
            values = predicates.flatMap { $0.values }
        }

        return try connection.queryScalar(sql, values: values, type: Int.self) ?? 0
    }

    /// Get the sum of an optional Int column
    public func sum(_ keyPath: KeyPath<T, Int?>, _ connection: SQLiteConnection) throws -> Int {
        let column = columnName(for: keyPath)
        var sql = "SELECT SUM(\(column)) FROM \(T.tableName)"
        var values: [SQLiteValue] = []

        if !predicates.isEmpty {
            let whereClause = predicates.map { $0.sql }.joined(separator: " AND ")
            sql += " WHERE \(whereClause)"
            values = predicates.flatMap { $0.values }
        }

        return try connection.queryScalar(sql, values: values, type: Int.self) ?? 0
    }

    /// Get the sum of a column (Double)
    public func sum(_ keyPath: KeyPath<T, Double>, _ connection: SQLiteConnection) throws -> Double {
        let column = columnName(for: keyPath)
        var sql = "SELECT SUM(\(column)) FROM \(T.tableName)"
        var values: [SQLiteValue] = []

        if !predicates.isEmpty {
            let whereClause = predicates.map { $0.sql }.joined(separator: " AND ")
            sql += " WHERE \(whereClause)"
            values = predicates.flatMap { $0.values }
        }

        return try connection.queryScalar(sql, values: values, type: Double.self) ?? 0.0
    }

    /// Get the sum of an optional Double column
    public func sum(_ keyPath: KeyPath<T, Double?>, _ connection: SQLiteConnection) throws -> Double {
        let column = columnName(for: keyPath)
        var sql = "SELECT SUM(\(column)) FROM \(T.tableName)"
        var values: [SQLiteValue] = []

        if !predicates.isEmpty {
            let whereClause = predicates.map { $0.sql }.joined(separator: " AND ")
            sql += " WHERE \(whereClause)"
            values = predicates.flatMap { $0.values }
        }

        return try connection.queryScalar(sql, values: values, type: Double.self) ?? 0.0
    }

    /// Get the average value of a column (Int -> Double)
    public func avg(_ keyPath: KeyPath<T, Int>, _ connection: SQLiteConnection) throws -> Double? {
        let column = columnName(for: keyPath)
        var sql = "SELECT AVG(\(column)) FROM \(T.tableName)"
        var values: [SQLiteValue] = []

        if !predicates.isEmpty {
            let whereClause = predicates.map { $0.sql }.joined(separator: " AND ")
            sql += " WHERE \(whereClause)"
            values = predicates.flatMap { $0.values }
        }

        return try connection.queryScalar(sql, values: values, type: Double.self)
    }

    /// Get the average value of an optional Int column
    public func avg(_ keyPath: KeyPath<T, Int?>, _ connection: SQLiteConnection) throws -> Double? {
        let column = columnName(for: keyPath)
        var sql = "SELECT AVG(\(column)) FROM \(T.tableName)"
        var values: [SQLiteValue] = []

        if !predicates.isEmpty {
            let whereClause = predicates.map { $0.sql }.joined(separator: " AND ")
            sql += " WHERE \(whereClause)"
            values = predicates.flatMap { $0.values }
        }

        return try connection.queryScalar(sql, values: values, type: Double.self)
    }

    /// Get the average value of a column (Double)
    public func avg(_ keyPath: KeyPath<T, Double>, _ connection: SQLiteConnection) throws -> Double? {
        let column = columnName(for: keyPath)
        var sql = "SELECT AVG(\(column)) FROM \(T.tableName)"
        var values: [SQLiteValue] = []

        if !predicates.isEmpty {
            let whereClause = predicates.map { $0.sql }.joined(separator: " AND ")
            sql += " WHERE \(whereClause)"
            values = predicates.flatMap { $0.values }
        }

        return try connection.queryScalar(sql, values: values, type: Double.self)
    }

    /// Get the average value of an optional Double column
    public func avg(_ keyPath: KeyPath<T, Double?>, _ connection: SQLiteConnection) throws -> Double? {
        let column = columnName(for: keyPath)
        var sql = "SELECT AVG(\(column)) FROM \(T.tableName)"
        var values: [SQLiteValue] = []

        if !predicates.isEmpty {
            let whereClause = predicates.map { $0.sql }.joined(separator: " AND ")
            sql += " WHERE \(whereClause)"
            values = predicates.flatMap { $0.values }
        }

        return try connection.queryScalar(sql, values: values, type: Double.self)
    }

    // MARK: - Batch Operations

    /// Delete all records matching the query
    public func deleteAll(_ connection: SQLiteConnection) throws -> Int {
        var sql = "DELETE FROM \(T.tableName)"
        var values: [SQLiteValue] = []

        if !predicates.isEmpty {
            let whereClause = predicates.map { $0.sql }.joined(separator: " AND ")
            sql += " WHERE \(whereClause)"
            values = predicates.flatMap { $0.values }
        }

        return try connection.execute(sql, values: values)
    }

    /// Update all records matching the query with given values (raw SQL values)
    public func updateAll( _ connection: SQLiteConnection, _ assignments: [String: SQLiteValue]) throws -> Int {
        guard !assignments.isEmpty else { return 0 }

        let setClause = assignments.keys.map { "\($0) = ?" }.joined(separator: ", ")
        var sql = "UPDATE \(T.tableName) SET \(setClause)"
        var values = Array(assignments.values)

        if !predicates.isEmpty {
            let whereClause = predicates.map { $0.sql }.joined(separator: " AND ")
            sql += " WHERE \(whereClause)"
            values += predicates.flatMap { $0.values }
        }

        return try connection.execute(sql, values: values)
    }

    /// Update all records matching the query using KeyPath assignments
    /// Example: `query.updateAll([\.status <- "active", \.updatedAt <- Date()])`
    public func updateAll(_ connection: SQLiteConnection, _ assignments: [ColumnAssignment<T>]) throws -> Int {
        guard !assignments.isEmpty else { return 0 }

        let setClause = assignments.map { $0.sql }.joined(separator: ", ")
        var sql = "UPDATE \(T.tableName) SET \(setClause)"
        var values = assignments.filter { $0.hasValue }.map { $0.value }

        if !predicates.isEmpty {
            let whereClause = predicates.map { $0.sql }.joined(separator: " AND ")
            sql += " WHERE \(whereClause)"
            values += predicates.flatMap { $0.values }
        }

        return try connection.execute(sql, values: values)
    }

    /// Update all records matching the query using result builder syntax
    /// Example: `query.updateAll { $0.score += 100 }`
    public func updateAll(_ connection: SQLiteConnection, @AssignmentBuilder<T> _ buildAssignments: (Columns<T>) -> [ColumnAssignment<T>]) throws -> Int {
        try updateAll(connection, buildAssignments(Columns()))
    }
}

// MARK: - Column Assignment

/// Represents a column assignment for UPDATE queries
public struct ColumnAssignment<T>: Sendable {
    public let column: String
    public let sql: String
    public let value: SQLiteValue
    public let hasValue: Bool

    public init(column: String, value: SQLiteValue) {
        self.column = column
        self.sql = "\(column) = ?"
        self.value = value
        self.hasValue = true
    }

    public init(column: String, sql: String, value: SQLiteValue, hasValue: Bool = true) {
        self.column = column
        self.sql = sql
        self.value = value
        self.hasValue = hasValue
    }
}

/// Result builder for column assignments
@resultBuilder
public struct AssignmentBuilder<T> {
    public static func buildBlock(_ assignments: ColumnAssignment<T>...) -> [ColumnAssignment<T>] {
        assignments
    }

    public static func buildExpression(_ assignment: ColumnAssignment<T>) -> ColumnAssignment<T> {
        assignment
    }
}

/// Assignment operator for KeyPath to value (array syntax)
/// Example: `.updateAll([\.name <- "Alice"])`
infix operator <- : AssignmentPrecedence

public func <- <T, V: SQLiteComparable>(keyPath: KeyPath<T, V>, value: V) -> ColumnAssignment<T> {
    ColumnAssignment(column: columnName(for: keyPath), value: value.sqliteValue)
}

public func <- <T, V: SQLiteComparable>(keyPath: KeyPath<T, V?>, value: V?) -> ColumnAssignment<T> {
    if let value = value {
        return ColumnAssignment(column: columnName(for: keyPath), value: value.sqliteValue)
    } else {
        return ColumnAssignment(column: columnName(for: keyPath), value: .null)
    }
}

// MARK: - Column assignment operators for closure syntax

public extension Column where V: SQLiteComparable {
    /// Set column to value: `$0.name.set("Alice")`
    func set(_ value: V) -> ColumnAssignment<T> {
        ColumnAssignment(column: name, value: value.sqliteValue)
    }

    /// Set column using raw SQL expression: `$0.score.setRaw("score + bonus * 2")`
    func setRaw(_ sql: String) -> ColumnAssignment<T> {
        ColumnAssignment(column: name, sql: "\(name) = \(sql)", value: .null, hasValue: false)
    }

    /// Set column using raw SQL with parameter: `$0.score.setRaw("score + ?", value: 100)`
    func setRaw(_ sql: String, value: V) -> ColumnAssignment<T> {
        ColumnAssignment(column: name, sql: "\(name) = \(sql)", value: value.sqliteValue, hasValue: true)
    }
}

/// Increment operator: `$0.score += 100`
public func += <T>(column: Column<T, Int>, value: Int) -> ColumnAssignment<T> {
    ColumnAssignment(column: column.name, sql: "\(column.name) = \(column.name) + ?", value: value.sqliteValue)
}

public func += <T>(column: Column<T, Int?>, value: Int) -> ColumnAssignment<T> {
    ColumnAssignment(column: column.name, sql: "\(column.name) = \(column.name) + ?", value: value.sqliteValue)
}

/// Decrement operator: `$0.score -= 50`
public func -= <T>(column: Column<T, Int>, value: Int) -> ColumnAssignment<T> {
    ColumnAssignment(column: column.name, sql: "\(column.name) = \(column.name) - ?", value: value.sqliteValue)
}

public func -= <T>(column: Column<T, Int?>, value: Int) -> ColumnAssignment<T> {
    ColumnAssignment(column: column.name, sql: "\(column.name) = \(column.name) - ?", value: value.sqliteValue)
}

public func += <T>(column: Column<T, Double>, value: Double) -> ColumnAssignment<T> {
    ColumnAssignment(column: column.name, sql: "\(column.name) = \(column.name) + ?", value: value.sqliteValue)
}

public func -= <T>(column: Column<T, Double>, value: Double) -> ColumnAssignment<T> {
    ColumnAssignment(column: column.name, sql: "\(column.name) = \(column.name) - ?", value: value.sqliteValue)
}

// MARK: - Convenience Extensions

public extension Query {
    /// Filter where column equals value (convenience for simple equality)
    func filter<V: SQLiteComparable>(_ keyPath: KeyPath<T, V>, equals value: V) -> Query<T> {
        filter(keyPath == value)
    }

    /// Filter where column is in array
    func filter<V: SQLiteComparable>(_ keyPath: KeyPath<T, V>, in values: [V]) -> Query<T> {
        filter(keyPath ~= values)
    }

    /// Filter where column is between two values
    func filter<V: SQLiteComparable & Comparable>(
        _ keyPath: KeyPath<T, V>,
        between lower: V,
        and upper: V
    ) -> Query<T> {
        filter(keyPath.between(lower, and: upper))
    }
}

// MARK: - Identifiable Entity Extensions

public extension Query where T: Identifiable, T.ID == UUIDV4 {
    /// Filter by primary key (only available for entities with id field)
    func filter(id: UUIDV4) -> Query<T> {
        filter(\T.id == id)
    }

    /// Filter by multiple primary keys (only available for entities with id field)
    func filter(ids: [UUIDV4]) -> Query<T> {
        filter(\T.id ~= ids)
    }
}
