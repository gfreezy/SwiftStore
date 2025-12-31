import Foundation

/// SQL predicate for WHERE clauses
public struct Predicate<T>: Sendable {
    public let sql: String
    public let values: [SQLiteValue]

    public init(sql: String, values: [SQLiteValue] = []) {
        self.sql = sql
        self.values = values
    }

    /// Combine predicates with AND
    public func and(_ other: Predicate<T>) -> Predicate<T> {
        Predicate(
            sql: "(\(self.sql)) AND (\(other.sql))",
            values: self.values + other.values
        )
    }

    /// Combine predicates with OR
    public func or(_ other: Predicate<T>) -> Predicate<T> {
        Predicate(
            sql: "(\(self.sql)) OR (\(other.sql))",
            values: self.values + other.values
        )
    }

    /// Negate predicate
    public var not: Predicate<T> {
        Predicate(sql: "NOT (\(self.sql))", values: values)
    }
}

// MARK: - Predicate logical operators

/// Combine predicates with AND using &&
public func && <T>(lhs: Predicate<T>, rhs: Predicate<T>) -> Predicate<T> {
    lhs.and(rhs)
}

/// Combine predicates with OR using ||
public func || <T>(lhs: Predicate<T>, rhs: Predicate<T>) -> Predicate<T> {
    lhs.or(rhs)
}

/// Negate predicate using !
public prefix func ! <T>(predicate: Predicate<T>) -> Predicate<T> {
    predicate.not
}

// MARK: - KeyPath based predicates

/// Protocol for comparable values in predicates
public protocol SQLiteComparable: Sendable {
    var sqliteValue: SQLiteValue { get }
}

extension String: SQLiteComparable {
    public var sqliteValue: SQLiteValue { .text(self) }
}

extension Int: SQLiteComparable {
    public var sqliteValue: SQLiteValue { .integer(Int64(self)) }
}

extension Int64: SQLiteComparable {
    public var sqliteValue: SQLiteValue { .integer(self) }
}

extension Double: SQLiteComparable {
    public var sqliteValue: SQLiteValue { .real(self) }
}

extension Bool: SQLiteComparable {
    public var sqliteValue: SQLiteValue { .integer(self ? 1 : 0) }
}

extension UUID: SQLiteComparable {
    public var sqliteValue: SQLiteValue { .text(self.uuidString) }
}


extension Date: SQLiteComparable {
    public var sqliteValue: SQLiteValue { .real(self.timeIntervalSince1970) }
}

extension Optional: SQLiteComparable where Wrapped: SQLiteComparable {
    public var sqliteValue: SQLiteValue {
        switch self {
        case .some(let value):
            return value.sqliteValue
        case .none:
            return .null
        }
    }
}

/// Helper to convert KeyPath to column name
public func columnName<T, V>(for keyPath: KeyPath<T, V>) -> String {
    // This is a simplified implementation
    // In production, this would use reflection or code generation
    let keyPathString = String(describing: keyPath)

    // Extract property name from KeyPath string representation
    // e.g., \User.name -> name
    if let dotIndex = keyPathString.lastIndex(of: ".") {
        let propertyName = String(keyPathString[keyPathString.index(after: dotIndex)...])
        return propertyName.camelCaseToSnakeCase()
    }

    return keyPathString.camelCaseToSnakeCase()
}

// MARK: - Dynamic Member Lookup for Predicate Building

/// Wrapper around KeyPath that provides type context
public struct Column<T, V> {
    public let keyPath: KeyPath<T, V>

    public init(_ keyPath: KeyPath<T, V>) {
        self.keyPath = keyPath
    }

    public var name: String {
        columnName(for: keyPath)
    }
}

/// Dynamic member lookup type for building predicates with closure syntax
/// Usage: `.filter { $0.age >= 25 }`
@dynamicMemberLookup
public struct Columns<T>: Sendable {
    public init() {}

    public subscript<V>(dynamicMember keyPath: KeyPath<T, V>) -> Column<T, V> {
        Column(keyPath)
    }
}

// MARK: - Column-based operators

public func == <T, V: SQLiteComparable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> {
    Predicate(sql: "\(lhs.name) = ?", values: [rhs.sqliteValue])
}

public func == <T, V: SQLiteComparable>(lhs: Column<T, V?>, rhs: V?) -> Predicate<T> {
    if let value = rhs {
        return Predicate(sql: "\(lhs.name) = ?", values: [value.sqliteValue])
    } else {
        return Predicate(sql: "\(lhs.name) IS NULL", values: [])
    }
}

public func != <T, V: SQLiteComparable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> {
    Predicate(sql: "\(lhs.name) != ?", values: [rhs.sqliteValue])
}

public func != <T, V: SQLiteComparable>(lhs: Column<T, V?>, rhs: V?) -> Predicate<T> {
    if let value = rhs {
        return Predicate(sql: "\(lhs.name) != ?", values: [value.sqliteValue])
    } else {
        return Predicate(sql: "\(lhs.name) IS NOT NULL", values: [])
    }
}

public func < <T, V: SQLiteComparable & Comparable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> {
    Predicate(sql: "\(lhs.name) < ?", values: [rhs.sqliteValue])
}

public func < <T, V: SQLiteComparable & Comparable>(lhs: Column<T, V?>, rhs: V) -> Predicate<T> {
    Predicate(sql: "\(lhs.name) < ?", values: [rhs.sqliteValue])
}

public func <= <T, V: SQLiteComparable & Comparable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> {
    Predicate(sql: "\(lhs.name) <= ?", values: [rhs.sqliteValue])
}

public func <= <T, V: SQLiteComparable & Comparable>(lhs: Column<T, V?>, rhs: V) -> Predicate<T> {
    Predicate(sql: "\(lhs.name) <= ?", values: [rhs.sqliteValue])
}

public func > <T, V: SQLiteComparable & Comparable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> {
    Predicate(sql: "\(lhs.name) > ?", values: [rhs.sqliteValue])
}

public func > <T, V: SQLiteComparable & Comparable>(lhs: Column<T, V?>, rhs: V) -> Predicate<T> {
    Predicate(sql: "\(lhs.name) > ?", values: [rhs.sqliteValue])
}

public func >= <T, V: SQLiteComparable & Comparable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> {
    Predicate(sql: "\(lhs.name) >= ?", values: [rhs.sqliteValue])
}

public func >= <T, V: SQLiteComparable & Comparable>(lhs: Column<T, V?>, rhs: V) -> Predicate<T> {
    Predicate(sql: "\(lhs.name) >= ?", values: [rhs.sqliteValue])
}

/// IN operator for Column
public func ~= <T, V: SQLiteComparable>(lhs: Column<T, V>, rhs: [V]) -> Predicate<T> {
    guard !rhs.isEmpty else {
        return Predicate(sql: "0 = 1", values: [])
    }
    let placeholders = rhs.map { _ in "?" }.joined(separator: ", ")
    let values = rhs.map { $0.sqliteValue }
    return Predicate(sql: "\(lhs.name) IN (\(placeholders))", values: values)
}

// MARK: - Column extensions for string operations

public extension Column where V == String {
    func like(_ pattern: String) -> Predicate<T> {
        Predicate(sql: "\(name) LIKE ?", values: [.text(pattern)])
    }

    func contains(_ substring: String) -> Predicate<T> {
        like("%\(substring)%")
    }

    func hasPrefix(_ prefix: String) -> Predicate<T> {
        like("\(prefix)%")
    }

    func hasSuffix(_ suffix: String) -> Predicate<T> {
        like("%\(suffix)")
    }
}

public extension Column where V == String? {
    func like(_ pattern: String) -> Predicate<T> {
        Predicate(sql: "\(name) LIKE ?", values: [.text(pattern)])
    }

    func contains(_ substring: String) -> Predicate<T> {
        like("%\(substring)%")
    }

    func hasPrefix(_ prefix: String) -> Predicate<T> {
        like("\(prefix)%")
    }

    func hasSuffix(_ suffix: String) -> Predicate<T> {
        like("%\(suffix)")
    }
}

// MARK: - Column extensions for BETWEEN and IN

public extension Column where V: SQLiteComparable & Comparable {
    func between(_ lower: V, and upper: V) -> Predicate<T> {
        Predicate(
            sql: "\(name) BETWEEN ? AND ?",
            values: [lower.sqliteValue, upper.sqliteValue]
        )
    }

    func `in`(_ values: [V]) -> Predicate<T> {
        self ~= values
    }

    func notIn(_ values: [V]) -> Predicate<T> {
        guard !values.isEmpty else {
            return Predicate(sql: "1 = 1", values: [])
        }
        let placeholders = values.map { _ in "?" }.joined(separator: ", ")
        let sqliteValues = values.map { $0.sqliteValue }
        return Predicate(sql: "\(name) NOT IN (\(placeholders))", values: sqliteValues)
    }
}

// MARK: - Column NULL checks

public extension Column {
    var isNull: Predicate<T> {
        Predicate(sql: "\(name) IS NULL", values: [])
    }

    var isNotNull: Predicate<T> {
        Predicate(sql: "\(name) IS NOT NULL", values: [])
    }
}

// MARK: - Operator overloads for building predicates

public func == <T, V: SQLiteComparable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> {
    let column = columnName(for: lhs)
    return Predicate(sql: "\(column) = ?", values: [rhs.sqliteValue])
}

public func == <T, V: SQLiteComparable>(lhs: KeyPath<T, V?>, rhs: V?) -> Predicate<T> {
    let column = columnName(for: lhs)
    if let value = rhs {
        return Predicate(sql: "\(column) = ?", values: [value.sqliteValue])
    } else {
        return Predicate(sql: "\(column) IS NULL", values: [])
    }
}

public func != <T, V: SQLiteComparable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> {
    let column = columnName(for: lhs)
    return Predicate(sql: "\(column) != ?", values: [rhs.sqliteValue])
}

public func != <T, V: SQLiteComparable>(lhs: KeyPath<T, V?>, rhs: V?) -> Predicate<T> {
    let column = columnName(for: lhs)
    if let value = rhs {
        return Predicate(sql: "\(column) != ?", values: [value.sqliteValue])
    } else {
        return Predicate(sql: "\(column) IS NOT NULL", values: [])
    }
}

public func < <T, V: SQLiteComparable & Comparable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> {
    let column = columnName(for: lhs)
    return Predicate(sql: "\(column) < ?", values: [rhs.sqliteValue])
}

public func <= <T, V: SQLiteComparable & Comparable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> {
    let column = columnName(for: lhs)
    return Predicate(sql: "\(column) <= ?", values: [rhs.sqliteValue])
}

public func > <T, V: SQLiteComparable & Comparable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> {
    let column = columnName(for: lhs)
    return Predicate(sql: "\(column) > ?", values: [rhs.sqliteValue])
}

public func >= <T, V: SQLiteComparable & Comparable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> {
    let column = columnName(for: lhs)
    return Predicate(sql: "\(column) >= ?", values: [rhs.sqliteValue])
}

// MARK: - Optional comparison operators

public func < <T, V: SQLiteComparable & Comparable>(lhs: KeyPath<T, V?>, rhs: V) -> Predicate<T> {
    let column = columnName(for: lhs)
    return Predicate(sql: "\(column) < ?", values: [rhs.sqliteValue])
}

public func <= <T, V: SQLiteComparable & Comparable>(lhs: KeyPath<T, V?>, rhs: V) -> Predicate<T> {
    let column = columnName(for: lhs)
    return Predicate(sql: "\(column) <= ?", values: [rhs.sqliteValue])
}

public func > <T, V: SQLiteComparable & Comparable>(lhs: KeyPath<T, V?>, rhs: V) -> Predicate<T> {
    let column = columnName(for: lhs)
    return Predicate(sql: "\(column) > ?", values: [rhs.sqliteValue])
}

public func >= <T, V: SQLiteComparable & Comparable>(lhs: KeyPath<T, V?>, rhs: V) -> Predicate<T> {
    let column = columnName(for: lhs)
    return Predicate(sql: "\(column) >= ?", values: [rhs.sqliteValue])
}

// MARK: - String specific predicates

public extension KeyPath where Value == String {
    func like(_ pattern: String) -> Predicate<Root> {
        let column = columnName(for: self)
        return Predicate(sql: "\(column) LIKE ?", values: [.text(pattern)])
    }

    func contains(_ substring: String) -> Predicate<Root> {
        like("%\(substring)%")
    }

    func hasPrefix(_ prefix: String) -> Predicate<Root> {
        like("\(prefix)%")
    }

    func hasSuffix(_ suffix: String) -> Predicate<Root> {
        like("%\(suffix)")
    }
}

public extension KeyPath where Value == String? {
    func like(_ pattern: String) -> Predicate<Root> {
        let column = columnName(for: self)
        return Predicate(sql: "\(column) LIKE ?", values: [.text(pattern)])
    }

    func contains(_ substring: String) -> Predicate<Root> {
        like("%\(substring)%")
    }

    func hasPrefix(_ prefix: String) -> Predicate<Root> {
        like("\(prefix)%")
    }

    func hasSuffix(_ suffix: String) -> Predicate<Root> {
        like("%\(suffix)")
    }
}

// MARK: - IN predicate

public func ~= <T, V: SQLiteComparable>(lhs: KeyPath<T, V>, rhs: [V]) -> Predicate<T> {
    let column = columnName(for: lhs)
    guard !rhs.isEmpty else {
        // Empty array - always false
        return Predicate(sql: "0 = 1", values: [])
    }
    let placeholders = rhs.map { _ in "?" }.joined(separator: ", ")
    let values = rhs.map { $0.sqliteValue }
    return Predicate(sql: "\(column) IN (\(placeholders))", values: values)
}

// MARK: - BETWEEN predicate

public extension KeyPath where Value: SQLiteComparable & Comparable {
    /// Create a BETWEEN predicate
    func between(_ lower: Value, and upper: Value) -> Predicate<Root> {
        let column = columnName(for: self)
        return Predicate(
            sql: "\(column) BETWEEN ? AND ?",
            values: [lower.sqliteValue, upper.sqliteValue]
        )
    }
}

public extension KeyPath where Value: SQLiteComparable {
    /// IN predicate with array (alternative syntax)
    func `in`(_ values: [Value]) -> Predicate<Root> {
        self ~= values
    }

    /// NOT IN predicate
    func notIn(_ values: [Value]) -> Predicate<Root> {
        let column = columnName(for: self)
        guard !values.isEmpty else {
            // Empty array - always true
            return Predicate(sql: "1 = 1", values: [])
        }
        let placeholders = values.map { _ in "?" }.joined(separator: ", ")
        let sqliteValues = values.map { $0.sqliteValue }
        return Predicate(sql: "\(column) NOT IN (\(placeholders))", values: sqliteValues)
    }
}

// MARK: - NULL checks

public extension KeyPath {
    var isNull: Predicate<Root> {
        let column = columnName(for: self)
        return Predicate(sql: "\(column) IS NULL", values: [])
    }

    var isNotNull: Predicate<Root> {
        let column = columnName(for: self)
        return Predicate(sql: "\(column) IS NOT NULL", values: [])
    }
}
