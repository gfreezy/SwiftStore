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
    let placeholders = rhs.map { _ in "?" }.joined(separator: ", ")
    let values = rhs.map { $0.sqliteValue }
    return Predicate(sql: "\(column) IN (\(placeholders))", values: values)
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
