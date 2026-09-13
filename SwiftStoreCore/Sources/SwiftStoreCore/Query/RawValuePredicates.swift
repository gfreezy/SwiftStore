import Foundation

// RawRepresentable values are queryable when their stored RawValue is queryable.
// Swift cannot synthesize conditional conformances on non-generic enums, so these
// overloads express that constraint directly. No concrete raw-type list is needed.
public func == <T, V: RawRepresentable & SQLiteValueCodable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable {
    Predicate(sql: "\(lhs.name) = ?", values: [rhs.rawValue.sqliteValue])
}

public func == <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable {
    Predicate(sql: "\(lhs.name) = ?", values: [rhs.sqliteValue])
}

public func == <T, V: RawRepresentable & SQLiteValueCodable>(lhs: Column<T, V?>, rhs: V?) -> Predicate<T> where V.RawValue: SQLiteValueComparable {
    guard let rhs else { return Predicate(sql: "\(lhs.name) IS NULL") }
    return Predicate(sql: "\(lhs.name) = ?", values: [rhs.rawValue.sqliteValue])
}

public func == <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable>(lhs: Column<T, V?>, rhs: V?) -> Predicate<T> where V.RawValue: SQLiteValueComparable {
    guard let rhs else { return Predicate(sql: "\(lhs.name) IS NULL") }
    return Predicate(sql: "\(lhs.name) = ?", values: [rhs.sqliteValue])
}

public func != <T, V: RawRepresentable & SQLiteValueCodable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable {
    Predicate(sql: "\(lhs.name) != ?", values: [rhs.rawValue.sqliteValue])
}

public func != <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable {
    Predicate(sql: "\(lhs.name) != ?", values: [rhs.sqliteValue])
}

public func != <T, V: RawRepresentable & SQLiteValueCodable>(lhs: Column<T, V?>, rhs: V?) -> Predicate<T> where V.RawValue: SQLiteValueComparable {
    guard let rhs else { return Predicate(sql: "\(lhs.name) IS NOT NULL") }
    return Predicate(sql: "\(lhs.name) != ?", values: [rhs.rawValue.sqliteValue])
}

public func != <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable>(lhs: Column<T, V?>, rhs: V?) -> Predicate<T> where V.RawValue: SQLiteValueComparable {
    guard let rhs else { return Predicate(sql: "\(lhs.name) IS NOT NULL") }
    return Predicate(sql: "\(lhs.name) != ?", values: [rhs.sqliteValue])
}

public func < <T, V: RawRepresentable & SQLiteValueCodable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(lhs.name) < ?", values: [rhs.rawValue.sqliteValue])
}

public func < <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable & Comparable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(lhs.name) < ?", values: [rhs.sqliteValue])
}

public func < <T, V: RawRepresentable & SQLiteValueCodable>(lhs: Column<T, V?>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(lhs.name) < ?", values: [rhs.rawValue.sqliteValue])
}

public func < <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable & Comparable>(lhs: Column<T, V?>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(lhs.name) < ?", values: [rhs.sqliteValue])
}

public func <= <T, V: RawRepresentable & SQLiteValueCodable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(lhs.name) <= ?", values: [rhs.rawValue.sqliteValue])
}

public func <= <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable & Comparable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(lhs.name) <= ?", values: [rhs.sqliteValue])
}

public func <= <T, V: RawRepresentable & SQLiteValueCodable>(lhs: Column<T, V?>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(lhs.name) <= ?", values: [rhs.rawValue.sqliteValue])
}

public func <= <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable & Comparable>(lhs: Column<T, V?>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(lhs.name) <= ?", values: [rhs.sqliteValue])
}

public func > <T, V: RawRepresentable & SQLiteValueCodable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(lhs.name) > ?", values: [rhs.rawValue.sqliteValue])
}

public func > <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable & Comparable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(lhs.name) > ?", values: [rhs.sqliteValue])
}

public func > <T, V: RawRepresentable & SQLiteValueCodable>(lhs: Column<T, V?>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(lhs.name) > ?", values: [rhs.rawValue.sqliteValue])
}

public func > <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable & Comparable>(lhs: Column<T, V?>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(lhs.name) > ?", values: [rhs.sqliteValue])
}

public func >= <T, V: RawRepresentable & SQLiteValueCodable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(lhs.name) >= ?", values: [rhs.rawValue.sqliteValue])
}

public func >= <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable & Comparable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(lhs.name) >= ?", values: [rhs.sqliteValue])
}

public func >= <T, V: RawRepresentable & SQLiteValueCodable>(lhs: Column<T, V?>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(lhs.name) >= ?", values: [rhs.rawValue.sqliteValue])
}

public func >= <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable & Comparable>(lhs: Column<T, V?>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(lhs.name) >= ?", values: [rhs.sqliteValue])
}

public func ~= <T, V: RawRepresentable & SQLiteValueCodable>(lhs: Column<T, V>, rhs: [V]) -> Predicate<T> where V.RawValue: SQLiteValueComparable {
    rawMembership(name: lhs.name, values: rhs.map { $0.rawValue.sqliteValue }, negated: false)
}

public func ~= <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable>(lhs: Column<T, V>, rhs: [V]) -> Predicate<T> where V.RawValue: SQLiteValueComparable {
    rawMembership(name: lhs.name, values: rhs.map { $0.sqliteValue }, negated: false)
}

public func == <T, V: RawRepresentable & SQLiteValueCodable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable {
    Predicate(sql: "\(columnName(for: lhs)) = ?", values: [rhs.rawValue.sqliteValue])
}

public func == <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable {
    Predicate(sql: "\(columnName(for: lhs)) = ?", values: [rhs.sqliteValue])
}

public func == <T, V: RawRepresentable & SQLiteValueCodable>(lhs: KeyPath<T, V?>, rhs: V?) -> Predicate<T> where V.RawValue: SQLiteValueComparable {
    guard let rhs else { return Predicate(sql: "\(columnName(for: lhs)) IS NULL") }
    return Predicate(sql: "\(columnName(for: lhs)) = ?", values: [rhs.rawValue.sqliteValue])
}

public func == <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable>(lhs: KeyPath<T, V?>, rhs: V?) -> Predicate<T> where V.RawValue: SQLiteValueComparable {
    guard let rhs else { return Predicate(sql: "\(columnName(for: lhs)) IS NULL") }
    return Predicate(sql: "\(columnName(for: lhs)) = ?", values: [rhs.sqliteValue])
}

public func != <T, V: RawRepresentable & SQLiteValueCodable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable {
    Predicate(sql: "\(columnName(for: lhs)) != ?", values: [rhs.rawValue.sqliteValue])
}

public func != <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable {
    Predicate(sql: "\(columnName(for: lhs)) != ?", values: [rhs.sqliteValue])
}

public func != <T, V: RawRepresentable & SQLiteValueCodable>(lhs: KeyPath<T, V?>, rhs: V?) -> Predicate<T> where V.RawValue: SQLiteValueComparable {
    guard let rhs else { return Predicate(sql: "\(columnName(for: lhs)) IS NOT NULL") }
    return Predicate(sql: "\(columnName(for: lhs)) != ?", values: [rhs.rawValue.sqliteValue])
}

public func != <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable>(lhs: KeyPath<T, V?>, rhs: V?) -> Predicate<T> where V.RawValue: SQLiteValueComparable {
    guard let rhs else { return Predicate(sql: "\(columnName(for: lhs)) IS NOT NULL") }
    return Predicate(sql: "\(columnName(for: lhs)) != ?", values: [rhs.sqliteValue])
}

public func < <T, V: RawRepresentable & SQLiteValueCodable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(columnName(for: lhs)) < ?", values: [rhs.rawValue.sqliteValue])
}

public func < <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable & Comparable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(columnName(for: lhs)) < ?", values: [rhs.sqliteValue])
}

public func < <T, V: RawRepresentable & SQLiteValueCodable>(lhs: KeyPath<T, V?>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(columnName(for: lhs)) < ?", values: [rhs.rawValue.sqliteValue])
}

public func < <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable & Comparable>(lhs: KeyPath<T, V?>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(columnName(for: lhs)) < ?", values: [rhs.sqliteValue])
}

public func <= <T, V: RawRepresentable & SQLiteValueCodable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(columnName(for: lhs)) <= ?", values: [rhs.rawValue.sqliteValue])
}

public func <= <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable & Comparable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(columnName(for: lhs)) <= ?", values: [rhs.sqliteValue])
}

public func <= <T, V: RawRepresentable & SQLiteValueCodable>(lhs: KeyPath<T, V?>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(columnName(for: lhs)) <= ?", values: [rhs.rawValue.sqliteValue])
}

public func <= <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable & Comparable>(lhs: KeyPath<T, V?>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(columnName(for: lhs)) <= ?", values: [rhs.sqliteValue])
}

public func > <T, V: RawRepresentable & SQLiteValueCodable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(columnName(for: lhs)) > ?", values: [rhs.rawValue.sqliteValue])
}

public func > <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable & Comparable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(columnName(for: lhs)) > ?", values: [rhs.sqliteValue])
}

public func > <T, V: RawRepresentable & SQLiteValueCodable>(lhs: KeyPath<T, V?>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(columnName(for: lhs)) > ?", values: [rhs.rawValue.sqliteValue])
}

public func > <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable & Comparable>(lhs: KeyPath<T, V?>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(columnName(for: lhs)) > ?", values: [rhs.sqliteValue])
}

public func >= <T, V: RawRepresentable & SQLiteValueCodable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(columnName(for: lhs)) >= ?", values: [rhs.rawValue.sqliteValue])
}

public func >= <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable & Comparable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(columnName(for: lhs)) >= ?", values: [rhs.sqliteValue])
}

public func >= <T, V: RawRepresentable & SQLiteValueCodable>(lhs: KeyPath<T, V?>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(columnName(for: lhs)) >= ?", values: [rhs.rawValue.sqliteValue])
}

public func >= <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable & Comparable>(lhs: KeyPath<T, V?>, rhs: V) -> Predicate<T> where V.RawValue: SQLiteValueComparable & Comparable {
    Predicate(sql: "\(columnName(for: lhs)) >= ?", values: [rhs.sqliteValue])
}

public func ~= <T, V: RawRepresentable & SQLiteValueCodable>(lhs: KeyPath<T, V>, rhs: [V]) -> Predicate<T> where V.RawValue: SQLiteValueComparable {
    rawMembership(name: columnName(for: lhs), values: rhs.map { $0.rawValue.sqliteValue }, negated: false)
}

public func ~= <T, V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable>(lhs: KeyPath<T, V>, rhs: [V]) -> Predicate<T> where V.RawValue: SQLiteValueComparable {
    rawMembership(name: columnName(for: lhs), values: rhs.map { $0.sqliteValue }, negated: false)
}

public extension Column where V: RawRepresentable & SQLiteValueCodable, V.RawValue: SQLiteValueComparable {
    func `in`(_ values: [V]) -> Predicate<T> {
        rawMembership(name: name, values: values.map { $0.rawValue.sqliteValue }, negated: false)
    }
    func notIn(_ values: [V]) -> Predicate<T> {
        rawMembership(name: name, values: values.map { $0.rawValue.sqliteValue }, negated: true)
    }
}

public extension Column where V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable & Comparable, V.RawValue: SQLiteValueComparable {
    func `in`(_ values: [V]) -> Predicate<T> {
        rawMembership(name: name, values: values.map { $0.sqliteValue }, negated: false)
    }
    func notIn(_ values: [V]) -> Predicate<T> {
        rawMembership(name: name, values: values.map { $0.sqliteValue }, negated: true)
    }
}

public extension Column where V: RawRepresentable & SQLiteValueCodable, V.RawValue: SQLiteValueComparable & Comparable {
    func between(_ lower: V, and upper: V) -> Predicate<T> {
        Predicate(sql: "\(name) BETWEEN ? AND ?", values: [lower.rawValue.sqliteValue, upper.rawValue.sqliteValue])
    }
}

public extension Column where V: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable & Comparable, V.RawValue: SQLiteValueComparable & Comparable {
    func between(_ lower: V, and upper: V) -> Predicate<T> {
        Predicate(sql: "\(name) BETWEEN ? AND ?", values: [lower.sqliteValue, upper.sqliteValue])
    }
}

public extension KeyPath where Value: RawRepresentable & SQLiteValueCodable, Value.RawValue: SQLiteValueComparable {
    func `in`(_ values: [Value]) -> Predicate<Root> {
        rawMembership(name: columnName(for: self), values: values.map { $0.rawValue.sqliteValue }, negated: false)
    }
    func notIn(_ values: [Value]) -> Predicate<Root> {
        rawMembership(name: columnName(for: self), values: values.map { $0.rawValue.sqliteValue }, negated: true)
    }
}

public extension KeyPath where Value: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable, Value.RawValue: SQLiteValueComparable {
    func `in`(_ values: [Value]) -> Predicate<Root> {
        rawMembership(name: columnName(for: self), values: values.map { $0.sqliteValue }, negated: false)
    }
    func notIn(_ values: [Value]) -> Predicate<Root> {
        rawMembership(name: columnName(for: self), values: values.map { $0.sqliteValue }, negated: true)
    }
}

public extension KeyPath where Value: RawRepresentable & SQLiteValueCodable, Value.RawValue: SQLiteValueComparable & Comparable {
    func between(_ lower: Value, and upper: Value) -> Predicate<Root> {
        Predicate(sql: "\(columnName(for: self)) BETWEEN ? AND ?", values: [lower.rawValue.sqliteValue, upper.rawValue.sqliteValue])
    }
}

public extension KeyPath where Value: RawRepresentable & SQLiteValueCodable & SQLiteValueComparable & Comparable, Value.RawValue: SQLiteValueComparable & Comparable {
    func between(_ lower: Value, and upper: Value) -> Predicate<Root> {
        Predicate(sql: "\(columnName(for: self)) BETWEEN ? AND ?", values: [lower.sqliteValue, upper.sqliteValue])
    }
}

private func rawMembership<T>(name: String, values: [SQLiteValue], negated: Bool) -> Predicate<T> {
    guard !values.isEmpty else { return Predicate(sql: negated ? "1 = 1" : "0 = 1") }
    let placeholders = Array(repeating: "?", count: values.count).joined(separator: ", ")
    return Predicate(sql: "\(name) \(negated ? "NOT IN" : "IN") (\(placeholders))", values: values)
}
