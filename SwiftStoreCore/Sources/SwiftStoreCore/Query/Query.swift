import Foundation

/// Query builder for fetching entities
/// Inspired by GRDB's query interface
public struct Query<T: EntityProtocol> {
    private var predicates: [Predicate<T>] = []
    private var orderBys: [(column: String, ascending: Bool)] = []
    private var limitValue: Int?
    private var offsetValue: Int?
    private var isDistinct: Bool = false

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

    /// Build SQL for specific columns (internal use for type-safe select)
    func buildSQL(columns: [String]) -> (sql: String, values: [SQLiteValue]) {
        let selectClause = columns.joined(separator: ", ")
        let distinctClause = isDistinct ? "DISTINCT " : ""
        var sql = "SELECT \(distinctClause)\(selectClause) FROM \(T.tableName)"
        var values: [SQLiteValue] = []

        if !predicates.isEmpty {
            let whereClause = predicates.map { $0.sql }.joined(separator: " AND ")
            sql += " WHERE \(whereClause)"
            values = predicates.flatMap { $0.values }
        }

        if !orderBys.isEmpty {
            let orderClause = orderBys.map { "\($0.column) \($0.ascending ? "ASC" : "DESC")" }
                .joined(separator: ", ")
            sql += " ORDER BY \(orderClause)"
        }

        if let limit = limitValue {
            sql += " LIMIT \(limit)"
        }

        if let offset = offsetValue {
            sql += " OFFSET \(offset)"
        }

        return (sql, values)
    }

    /// Build the SQL query
    func buildSQL() -> (sql: String, values: [SQLiteValue]) {
        // Use explicit column names from entity definition to ensure correct ordering
        // This is critical for migrations where ALTER TABLE ADD COLUMN appends at the end
        let entityColumns = T.columns.filter { $0.generatedAs == nil }.map { $0.name }
        return buildSQL(columns: entityColumns)
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
    public func min<V: SQLiteComparable>(_ connection: SQLiteConnection, _ keyPath: KeyPath<T, V>) throws -> V? {
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
    public func min<V: SQLiteComparable>(_ connection: SQLiteConnection, _ keyPath: KeyPath<T, V?>) throws -> V? {
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
    public func sum(_ connection: SQLiteConnection, _ keyPath: KeyPath<T, Int>) throws -> Int {
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
    public func sum(_ connection: SQLiteConnection, _ keyPath: KeyPath<T, Int?>) throws -> Int {
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
    public func sum(_ connection: SQLiteConnection, _ keyPath: KeyPath<T, Double>) throws -> Double
    {
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
    public func sum(_ connection: SQLiteConnection, _ keyPath: KeyPath<T, Double?>) throws -> Double
    {
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
    public func avg(_ connection: SQLiteConnection, _ keyPath: KeyPath<T, Int>) throws -> Double? {
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
    public func avg(_ connection: SQLiteConnection, _ keyPath: KeyPath<T, Int?>) throws -> Double? {
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
    public func avg(_ connection: SQLiteConnection, _ keyPath: KeyPath<T, Double>) throws -> Double?
    {
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
    public func avg(_ connection: SQLiteConnection, _ keyPath: KeyPath<T, Double?>) throws
        -> Double?
    {
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
    @discardableResult
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
    @discardableResult
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
    @discardableResult
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
    @discardableResult
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

extension Column where V: SQLiteComparable {
    /// Set column to value: `$0.name.set("Alice")`
    public func set(_ value: V) -> ColumnAssignment<T> {
        ColumnAssignment(column: name, value: value.sqliteValue)
    }

    /// Set column using raw SQL expression: `$0.score.setRaw("score + bonus * 2")`
    public func setRaw(_ sql: String) -> ColumnAssignment<T> {
        ColumnAssignment(column: name, sql: "\(name) = \(sql)", value: .null, hasValue: false)
    }

    /// Set column using raw SQL with parameter: `$0.score.setRaw("score + ?", value: 100)`
    public func setRaw(_ sql: String, value: V) -> ColumnAssignment<T> {
        ColumnAssignment(
            column: name, sql: "\(name) = \(sql)", value: value.sqliteValue, hasValue: true)
    }
}

/// Increment operator: `$0.score += 100`
public func += <T>(column: Column<T, Int>, value: Int) -> ColumnAssignment<T> {
    ColumnAssignment(
        column: column.name, sql: "\(column.name) = \(column.name) + ?", value: value.sqliteValue)
}

public func += <T>(column: Column<T, Int?>, value: Int) -> ColumnAssignment<T> {
    ColumnAssignment(
        column: column.name, sql: "\(column.name) = \(column.name) + ?", value: value.sqliteValue)
}

/// Decrement operator: `$0.score -= 50`
public func -= <T>(column: Column<T, Int>, value: Int) -> ColumnAssignment<T> {
    ColumnAssignment(
        column: column.name, sql: "\(column.name) = \(column.name) - ?", value: value.sqliteValue)
}

public func -= <T>(column: Column<T, Int?>, value: Int) -> ColumnAssignment<T> {
    ColumnAssignment(
        column: column.name, sql: "\(column.name) = \(column.name) - ?", value: value.sqliteValue)
}

public func += <T>(column: Column<T, Double>, value: Double) -> ColumnAssignment<T> {
    ColumnAssignment(
        column: column.name, sql: "\(column.name) = \(column.name) + ?", value: value.sqliteValue)
}

public func -= <T>(column: Column<T, Double>, value: Double) -> ColumnAssignment<T> {
    ColumnAssignment(
        column: column.name, sql: "\(column.name) = \(column.name) - ?", value: value.sqliteValue)
}

// MARK: - Convenience Extensions

extension Query {
    /// Filter where column equals value (convenience for simple equality)
    public func filter<V: SQLiteComparable>(_ keyPath: KeyPath<T, V>, equals value: V) -> Query<T> {
        filter(keyPath == value)
    }

    /// Filter where column is in array
    public func filter<V: SQLiteComparable>(_ keyPath: KeyPath<T, V>, in values: [V]) -> Query<T> {
        filter(keyPath ~= values)
    }

    /// Filter where column is between two values
    public func filter<V: SQLiteComparable & Comparable>(
        _ keyPath: KeyPath<T, V>,
        between lower: V,
        and upper: V
    ) -> Query<T> {
        filter(keyPath.between(lower, and: upper))
    }
}

// MARK: - Identifiable Entity Extensions

extension Query where T: Identifiable, T.ID == UUIDV7 {
    /// Filter by primary key (only available for entities with id field)
    public func filter(id: UUIDV7) -> Query<T> {
        filter(\T.id == id)
    }

    /// Filter by multiple primary keys (only available for entities with id field)
    public func filter(ids: [UUIDV7]) -> Query<T> {
        filter(\T.id ~= ids)
    }
}

// MARK: - Type-Safe Select Methods

extension Query {
    /// Select single column - returns array of values
    public func select<V: SQLiteValueDecodable>(
        _ connection: SQLiteConnection,
        _ kp: KeyPath<T, V>
    ) throws -> [V] {
        let c = columnName(for: kp)
        let (sql, values) = buildSQL(columns: [c])
        let rows: [Row] = try connection.query(sql, values: values)
        return rows.map { row in
            row[kp]
        }
    }

    /// Select 2 columns - returns array of tuples
    public func select<V1: SQLiteValueDecodable, V2: SQLiteValueDecodable>(
        _ connection: SQLiteConnection,
        _ kp1: KeyPath<T, V1>,
        _ kp2: KeyPath<T, V2>,
    ) throws -> [(V1, V2)] {
        let c1 = columnName(for: kp1)
        let c2 = columnName(for: kp2)
        let (sql, values) = buildSQL(columns: [c1, c2])
        let rows = try connection.query(sql, values: values)
        return rows.map { row in
            (
                row[kp1],
                row[kp2]
            )
        }
    }

    /// Select 3 columns - returns array of tuples
    public func select<V1: SQLiteValueDecodable, V2: SQLiteValueDecodable, V3: SQLiteValueDecodable>(
        _ connection: SQLiteConnection,
        _ kp1: KeyPath<T, V1>,
        _ kp2: KeyPath<T, V2>,
        _ kp3: KeyPath<T, V3>,
    ) throws -> [(V1, V2, V3)] {
        let c1 = columnName(for: kp1)
        let c2 = columnName(for: kp2)
        let c3 = columnName(for: kp3)
        let (sql, values) = buildSQL(columns: [c1, c2, c3])
        let rows = try connection.query(sql, values: values)
        return rows.map { row in
            (
                row[kp1],
                row[kp2],
                row[kp3]
            )
        }
    }

    /// Select 4 columns - returns array of tuples
    public func select<
        V1: SQLiteValueDecodable, V2: SQLiteValueDecodable, V3: SQLiteValueDecodable, V4: SQLiteValueDecodable
    >(
        _ connection: SQLiteConnection,
        _ kp1: KeyPath<T, V1>,
        _ kp2: KeyPath<T, V2>,
        _ kp3: KeyPath<T, V3>,
        _ kp4: KeyPath<T, V4>,
    ) throws -> [(V1, V2, V3, V4)] {
        let c1 = columnName(for: kp1)
        let c2 = columnName(for: kp2)
        let c3 = columnName(for: kp3)
        let c4 = columnName(for: kp4)
        let (sql, values) = buildSQL(columns: [c1, c2, c3, c4])
        let rows = try connection.query(sql, values: values)
        return rows.map { row in
            (
                row[kp1],
                row[kp2],
                row[kp3],
                row[kp4]
            )
        }
    }

    /// Select 5 columns - returns array of tuples
    public func select<
        V1: SQLiteValueDecodable, V2: SQLiteValueDecodable, V3: SQLiteValueDecodable, V4: SQLiteValueDecodable,
        V5: SQLiteValueDecodable
    >(
        _ connection: SQLiteConnection,
        _ kp1: KeyPath<T, V1>,
        _ kp2: KeyPath<T, V2>,
        _ kp3: KeyPath<T, V3>,
        _ kp4: KeyPath<T, V4>,
        _ kp5: KeyPath<T, V5>,
    ) throws -> [(V1, V2, V3, V4, V5)] {
        let c1 = columnName(for: kp1)
        let c2 = columnName(for: kp2)
        let c3 = columnName(for: kp3)
        let c4 = columnName(for: kp4)
        let c5 = columnName(for: kp5)
        let (sql, values) = buildSQL(columns: [c1, c2, c3, c4, c5])
        let rows = try connection.query(sql, values: values)
        return rows.map { row in
            (
                row[kp1],
                row[kp2],
                row[kp3],
                row[kp4],
                row[kp5]
            )
        }
    }

    /// Select 6 columns - returns array of tuples
    public func select<
        V1: SQLiteValueDecodable, V2: SQLiteValueDecodable, V3: SQLiteValueDecodable, V4: SQLiteValueDecodable,
        V5: SQLiteValueDecodable, V6: SQLiteValueDecodable
    >(
        _ connection: SQLiteConnection,
        _ kp1: KeyPath<T, V1>,
        _ kp2: KeyPath<T, V2>,
        _ kp3: KeyPath<T, V3>,
        _ kp4: KeyPath<T, V4>,
        _ kp5: KeyPath<T, V5>,
        _ kp6: KeyPath<T, V6>,
    ) throws -> [(V1, V2, V3, V4, V5, V6)] {
        let c1 = columnName(for: kp1)
        let c2 = columnName(for: kp2)
        let c3 = columnName(for: kp3)
        let c4 = columnName(for: kp4)
        let c5 = columnName(for: kp5)
        let c6 = columnName(for: kp6)
        let (sql, values) = buildSQL(columns: [c1, c2, c3, c4, c5, c6])
        let rows = try connection.query(sql, values: values)
        return rows.map { row in
            (
                row[kp1],
                row[kp2],
                row[kp3],
                row[kp4],
                row[kp5],
                row[kp6]
            )
        }
    }

    /// Select 7 columns - returns array of tuples
    public func select<
        V1: SQLiteValueDecodable, V2: SQLiteValueDecodable, V3: SQLiteValueDecodable, V4: SQLiteValueDecodable,
        V5: SQLiteValueDecodable, V6: SQLiteValueDecodable, V7: SQLiteValueDecodable
    >(
        _ connection: SQLiteConnection,
        _ kp1: KeyPath<T, V1>,
        _ kp2: KeyPath<T, V2>,
        _ kp3: KeyPath<T, V3>,
        _ kp4: KeyPath<T, V4>,
        _ kp5: KeyPath<T, V5>,
        _ kp6: KeyPath<T, V6>,
        _ kp7: KeyPath<T, V7>,
    ) throws -> [(V1, V2, V3, V4, V5, V6, V7)] {
        let c1 = columnName(for: kp1)
        let c2 = columnName(for: kp2)
        let c3 = columnName(for: kp3)
        let c4 = columnName(for: kp4)
        let c5 = columnName(for: kp5)
        let c6 = columnName(for: kp6)
        let c7 = columnName(for: kp7)
        let (sql, values) = buildSQL(columns: [c1, c2, c3, c4, c5, c6, c7])
        let rows = try connection.query(sql, values: values)
        return rows.map { row in
            (
                row[kp1],
                row[kp2],
                row[kp3],
                row[kp4],
                row[kp5],
                row[kp6],
                row[kp7]
            )
        }
    }

    /// Select 8 columns - returns array of tuples
    public func select<
        V1: SQLiteValueDecodable, V2: SQLiteValueDecodable, V3: SQLiteValueDecodable, V4: SQLiteValueDecodable,
        V5: SQLiteValueDecodable, V6: SQLiteValueDecodable, V7: SQLiteValueDecodable, V8: SQLiteValueDecodable
    >(
        _ connection: SQLiteConnection,
        _ kp1: KeyPath<T, V1>,
        _ kp2: KeyPath<T, V2>,
        _ kp3: KeyPath<T, V3>,
        _ kp4: KeyPath<T, V4>,
        _ kp5: KeyPath<T, V5>,
        _ kp6: KeyPath<T, V6>,
        _ kp7: KeyPath<T, V7>,
        _ kp8: KeyPath<T, V8>,
    ) throws -> [(V1, V2, V3, V4, V5, V6, V7, V8)] {
        let c1 = columnName(for: kp1)
        let c2 = columnName(for: kp2)
        let c3 = columnName(for: kp3)
        let c4 = columnName(for: kp4)
        let c5 = columnName(for: kp5)
        let c6 = columnName(for: kp6)
        let c7 = columnName(for: kp7)
        let c8 = columnName(for: kp8)
        let (sql, values) = buildSQL(columns: [c1, c2, c3, c4, c5, c6, c7, c8])
        let rows = try connection.query(sql, values: values)
        return rows.map { row in
            (
                row[kp1],
                row[kp2],
                row[kp3],
                row[kp4],
                row[kp5],
                row[kp6],
                row[kp7],
                row[kp8]
            )
        }
    }

    /// Select 9 columns - returns array of tuples
    public func select<
        V1: SQLiteValueDecodable, V2: SQLiteValueDecodable, V3: SQLiteValueDecodable, V4: SQLiteValueDecodable,
        V5: SQLiteValueDecodable, V6: SQLiteValueDecodable, V7: SQLiteValueDecodable, V8: SQLiteValueDecodable,
        V9: SQLiteValueDecodable
    >(
        _ connection: SQLiteConnection,
        _ kp1: KeyPath<T, V1>,
        _ kp2: KeyPath<T, V2>,
        _ kp3: KeyPath<T, V3>,
        _ kp4: KeyPath<T, V4>,
        _ kp5: KeyPath<T, V5>,
        _ kp6: KeyPath<T, V6>,
        _ kp7: KeyPath<T, V7>,
        _ kp8: KeyPath<T, V8>,
        _ kp9: KeyPath<T, V9>,
    ) throws -> [(V1, V2, V3, V4, V5, V6, V7, V8, V9)] {
        let c1 = columnName(for: kp1)
        let c2 = columnName(for: kp2)
        let c3 = columnName(for: kp3)
        let c4 = columnName(for: kp4)
        let c5 = columnName(for: kp5)
        let c6 = columnName(for: kp6)
        let c7 = columnName(for: kp7)
        let c8 = columnName(for: kp8)
        let c9 = columnName(for: kp9)
        let (sql, values) = buildSQL(columns: [c1, c2, c3, c4, c5, c6, c7, c8, c9])
        let rows = try connection.query(sql, values: values)
        return rows.map { row in
            (
                row[kp1],
                row[kp2],
                row[kp3],
                row[kp4],
                row[kp5],
                row[kp6],
                row[kp7],
                row[kp8],
                row[kp9]
            )
        }
    }

    /// Select 10 columns - returns array of tuples
    public func select<
        V1: SQLiteValueDecodable, V2: SQLiteValueDecodable, V3: SQLiteValueDecodable, V4: SQLiteValueDecodable,
        V5: SQLiteValueDecodable, V6: SQLiteValueDecodable, V7: SQLiteValueDecodable, V8: SQLiteValueDecodable,
        V9: SQLiteValueDecodable, V10: SQLiteValueDecodable
    >(
        _ connection: SQLiteConnection,
        _ kp1: KeyPath<T, V1>,
        _ kp2: KeyPath<T, V2>,
        _ kp3: KeyPath<T, V3>,
        _ kp4: KeyPath<T, V4>,
        _ kp5: KeyPath<T, V5>,
        _ kp6: KeyPath<T, V6>,
        _ kp7: KeyPath<T, V7>,
        _ kp8: KeyPath<T, V8>,
        _ kp9: KeyPath<T, V9>,
        _ kp10: KeyPath<T, V10>,
    ) throws -> [(V1, V2, V3, V4, V5, V6, V7, V8, V9, V10)] {
        let c1 = columnName(for: kp1)
        let c2 = columnName(for: kp2)
        let c3 = columnName(for: kp3)
        let c4 = columnName(for: kp4)
        let c5 = columnName(for: kp5)
        let c6 = columnName(for: kp6)
        let c7 = columnName(for: kp7)
        let c8 = columnName(for: kp8)
        let c9 = columnName(for: kp9)
        let c10 = columnName(for: kp10)
        let (sql, values) = buildSQL(columns: [c1, c2, c3, c4, c5, c6, c7, c8, c9, c10])
        let rows = try connection.query(sql, values: values)
        return rows.map { row in
            (
                row[kp1],
                row[kp2],
                row[kp3],
                row[kp4],
                row[kp5],
                row[kp6],
                row[kp7],
                row[kp8],
                row[kp9],
                row[kp10]
            )
        }
    }
}
