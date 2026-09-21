import Foundation

/// SQL predicate for WHERE clauses
public struct Predicate<T>: Sendable {
    public let sql: String
    public let values: [SQLiteValue]
    let validationError: StoreError?

    public init(sql: String, values: [SQLiteValue] = []) {
        self.validationError = nil
        self.sql = sql
        self.values = values
    }

    init(resolving body: () throws -> Self) {
        do { self = try body() }
        catch {
            self.sql = ""
            self.values = []
            self.validationError = error as? StoreError ?? .invalidSchema(String(describing: error))
        }
    }

    func validate() throws {
        if let validationError { throw validationError }
    }

    /// Combine predicates with AND
    public func and(_ other: Predicate<T>) -> Predicate<T> {
        Predicate(resolving: {
            try self.validate()
            try other.validate()
            return Predicate(sql: "(\(self.sql)) AND (\(other.sql))", values: self.values + other.values)
        })
    }

    /// Combine predicates with OR
    public func or(_ other: Predicate<T>) -> Predicate<T> {
        Predicate(resolving: {
            try self.validate()
            try other.validate()
            return Predicate(sql: "(\(self.sql)) OR (\(other.sql))", values: self.values + other.values)
        })
    }

    /// Negate predicate
    public var not: Predicate<T> {
        Predicate(resolving: {
            try self.validate()
            return Predicate(sql: "NOT (\(self.sql))", values: values)
        })
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


/// Resolve a declared column without depending on KeyPath's debugging representation.
public func columnName<T, V>(for keyPath: KeyPath<T, V>) throws -> String {
    guard let entity = T.self as? any EntityProtocol.Type,
          let name = entity.columnName(for: keyPath) else {
        throw StoreError.invalidSchema("Unmapped SQLite key path on \(T.self)")
    }
    return name
}

// MARK: - Dynamic Member Lookup for Predicate Building

/// Wrapper around KeyPath that provides type context
public struct Column<T, V> {
    public let keyPath: KeyPath<T, V>

    public init(_ keyPath: KeyPath<T, V>) {
        self.keyPath = keyPath
    }

    public var name: String {
        get throws { try columnName(for: keyPath) }
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

public func == <T, V: SQLiteValueComparable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> {
    Predicate(resolving: {
        return Predicate(sql: "\(try lhs.name) = ?", values: [rhs.sqliteValue])
    })
}

public func == <T, V: SQLiteValueComparable>(lhs: Column<T, V?>, rhs: V?) -> Predicate<T> {
    Predicate(resolving: {
        if let value = rhs {
            return Predicate(sql: "\(try lhs.name) = ?", values: [value.sqliteValue])
        } else {
            return Predicate(sql: "\(try lhs.name) IS NULL", values: [])
        }
    })
}

public func != <T, V: SQLiteValueComparable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> {
    Predicate(resolving: {
        return Predicate(sql: "\(try lhs.name) != ?", values: [rhs.sqliteValue])
    })
}

public func != <T, V: SQLiteValueComparable>(lhs: Column<T, V?>, rhs: V?) -> Predicate<T> {
    Predicate(resolving: {
        if let value = rhs {
            return Predicate(sql: "\(try lhs.name) != ?", values: [value.sqliteValue])
        } else {
            return Predicate(sql: "\(try lhs.name) IS NOT NULL", values: [])
        }
    })
}

public func < <T, V: SQLiteValueComparable & Comparable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> {
    Predicate(resolving: {
        return Predicate(sql: "\(try lhs.name) < ?", values: [rhs.sqliteValue])
    })
}

public func < <T, V: SQLiteValueComparable & Comparable>(lhs: Column<T, V?>, rhs: V) -> Predicate<T> {
    Predicate(resolving: {
        return Predicate(sql: "\(try lhs.name) < ?", values: [rhs.sqliteValue])
    })
}

public func <= <T, V: SQLiteValueComparable & Comparable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> {
    Predicate(resolving: {
        return Predicate(sql: "\(try lhs.name) <= ?", values: [rhs.sqliteValue])
    })
}

public func <= <T, V: SQLiteValueComparable & Comparable>(lhs: Column<T, V?>, rhs: V) -> Predicate<T> {
    Predicate(resolving: {
        return Predicate(sql: "\(try lhs.name) <= ?", values: [rhs.sqliteValue])
    })
}

public func > <T, V: SQLiteValueComparable & Comparable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> {
    Predicate(resolving: {
        return Predicate(sql: "\(try lhs.name) > ?", values: [rhs.sqliteValue])
    })
}

public func > <T, V: SQLiteValueComparable & Comparable>(lhs: Column<T, V?>, rhs: V) -> Predicate<T> {
    Predicate(resolving: {
        return Predicate(sql: "\(try lhs.name) > ?", values: [rhs.sqliteValue])
    })
}

public func >= <T, V: SQLiteValueComparable & Comparable>(lhs: Column<T, V>, rhs: V) -> Predicate<T> {
    Predicate(resolving: {
        return Predicate(sql: "\(try lhs.name) >= ?", values: [rhs.sqliteValue])
    })
}

public func >= <T, V: SQLiteValueComparable & Comparable>(lhs: Column<T, V?>, rhs: V) -> Predicate<T> {
    Predicate(resolving: {
        return Predicate(sql: "\(try lhs.name) >= ?", values: [rhs.sqliteValue])
    })
}

/// IN operator for Column
public func ~= <T, V: SQLiteValueComparable>(lhs: Column<T, V>, rhs: [V]) -> Predicate<T> {
    Predicate(resolving: {
        let column = try lhs.name
        guard !rhs.isEmpty else {
            return Predicate(sql: "0 = 1", values: [])
        }
        let placeholders = rhs.map { _ in "?" }.joined(separator: ", ")
        let values = rhs.map { $0.sqliteValue }
        return Predicate(sql: "\(column) IN (\(placeholders))", values: values)
    })
}

// MARK: - Column extensions for string operations

public extension Column where V == String {
    func like(_ pattern: String) -> Predicate<T> {
        Predicate(resolving: {
            return Predicate(sql: "\(try name) LIKE ?", values: [.text(pattern)])
        })
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
        Predicate(resolving: {
            return Predicate(sql: "\(try name) LIKE ?", values: [.text(pattern)])
        })
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

public extension Column where V: SQLiteValueComparable & Comparable {
    func between(_ lower: V, and upper: V) -> Predicate<T> {
        Predicate(resolving: {
            return Predicate(
                sql: "\(try name) BETWEEN ? AND ?",
                values: [lower.sqliteValue, upper.sqliteValue]
            )
        })
    }

    func `in`(_ values: [V]) -> Predicate<T> {
        self ~= values
    }

    func notIn(_ values: [V]) -> Predicate<T> {
        Predicate(resolving: {
            let column = try name
            guard !values.isEmpty else {
                return Predicate(sql: "1 = 1", values: [])
            }
            let placeholders = values.map { _ in "?" }.joined(separator: ", ")
            let sqliteValues = values.map { $0.sqliteValue }
            return Predicate(sql: "\(column) NOT IN (\(placeholders))", values: sqliteValues)
        })
    }
}

// MARK: - Column NULL checks

public extension Column {
    var isNull: Predicate<T> {
        Predicate(resolving: {
            return Predicate(sql: "\(try name) IS NULL", values: [])
        })
    }

    var isNotNull: Predicate<T> {
        Predicate(resolving: {
            return Predicate(sql: "\(try name) IS NOT NULL", values: [])
        })
    }
}

// MARK: - Operator overloads for building predicates

public func == <T, V: SQLiteValueComparable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> {
    Predicate(resolving: {
        let column = try columnName(for: lhs)
        return Predicate(sql: "\(column) = ?", values: [rhs.sqliteValue])
    })
}

public func == <T, V: SQLiteValueComparable>(lhs: KeyPath<T, V?>, rhs: V?) -> Predicate<T> {
    Predicate(resolving: {
        let column = try columnName(for: lhs)
        if let value = rhs {
            return Predicate(sql: "\(column) = ?", values: [value.sqliteValue])
        } else {
            return Predicate(sql: "\(column) IS NULL", values: [])
        }
    })
}

public func != <T, V: SQLiteValueComparable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> {
    Predicate(resolving: {
        let column = try columnName(for: lhs)
        return Predicate(sql: "\(column) != ?", values: [rhs.sqliteValue])
    })
}

public func != <T, V: SQLiteValueComparable>(lhs: KeyPath<T, V?>, rhs: V?) -> Predicate<T> {
    Predicate(resolving: {
        let column = try columnName(for: lhs)
        if let value = rhs {
            return Predicate(sql: "\(column) != ?", values: [value.sqliteValue])
        } else {
            return Predicate(sql: "\(column) IS NOT NULL", values: [])
        }
    })
}

public func < <T, V: SQLiteValueComparable & Comparable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> {
    Predicate(resolving: {
        let column = try columnName(for: lhs)
        return Predicate(sql: "\(column) < ?", values: [rhs.sqliteValue])
    })
}

public func <= <T, V: SQLiteValueComparable & Comparable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> {
    Predicate(resolving: {
        let column = try columnName(for: lhs)
        return Predicate(sql: "\(column) <= ?", values: [rhs.sqliteValue])
    })
}

public func > <T, V: SQLiteValueComparable & Comparable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> {
    Predicate(resolving: {
        let column = try columnName(for: lhs)
        return Predicate(sql: "\(column) > ?", values: [rhs.sqliteValue])
    })
}

public func >= <T, V: SQLiteValueComparable & Comparable>(lhs: KeyPath<T, V>, rhs: V) -> Predicate<T> {
    Predicate(resolving: {
        let column = try columnName(for: lhs)
        return Predicate(sql: "\(column) >= ?", values: [rhs.sqliteValue])
    })
}

// MARK: - Optional comparison operators

public func < <T, V: SQLiteValueComparable & Comparable>(lhs: KeyPath<T, V?>, rhs: V) -> Predicate<T> {
    Predicate(resolving: {
        let column = try columnName(for: lhs)
        return Predicate(sql: "\(column) < ?", values: [rhs.sqliteValue])
    })
}

public func <= <T, V: SQLiteValueComparable & Comparable>(lhs: KeyPath<T, V?>, rhs: V) -> Predicate<T> {
    Predicate(resolving: {
        let column = try columnName(for: lhs)
        return Predicate(sql: "\(column) <= ?", values: [rhs.sqliteValue])
    })
}

public func > <T, V: SQLiteValueComparable & Comparable>(lhs: KeyPath<T, V?>, rhs: V) -> Predicate<T> {
    Predicate(resolving: {
        let column = try columnName(for: lhs)
        return Predicate(sql: "\(column) > ?", values: [rhs.sqliteValue])
    })
}

public func >= <T, V: SQLiteValueComparable & Comparable>(lhs: KeyPath<T, V?>, rhs: V) -> Predicate<T> {
    Predicate(resolving: {
        let column = try columnName(for: lhs)
        return Predicate(sql: "\(column) >= ?", values: [rhs.sqliteValue])
    })
}

// MARK: - String specific predicates

public extension KeyPath where Value == String {
    func like(_ pattern: String) -> Predicate<Root> {
        Predicate(resolving: {
            let column = try columnName(for: self)
            return Predicate(sql: "\(column) LIKE ?", values: [.text(pattern)])
        })
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
        Predicate(resolving: {
            let column = try columnName(for: self)
            return Predicate(sql: "\(column) LIKE ?", values: [.text(pattern)])
        })
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

public func ~= <T, V: SQLiteValueComparable>(lhs: KeyPath<T, V>, rhs: [V]) -> Predicate<T> {
    Predicate(resolving: {
        let column = try columnName(for: lhs)
        guard !rhs.isEmpty else {
            // Empty array - always false
            return Predicate(sql: "0 = 1", values: [])
        }
        let placeholders = rhs.map { _ in "?" }.joined(separator: ", ")
        let values = rhs.map { $0.sqliteValue }
        return Predicate(sql: "\(column) IN (\(placeholders))", values: values)
    })
}

// MARK: - BETWEEN predicate

public extension KeyPath where Value: SQLiteValueComparable & Comparable {
    /// Create a BETWEEN predicate
    func between(_ lower: Value, and upper: Value) -> Predicate<Root> {
        Predicate(resolving: {
            let column = try columnName(for: self)
            return Predicate(
                sql: "\(column) BETWEEN ? AND ?",
                values: [lower.sqliteValue, upper.sqliteValue]
            )
        })
    }
}

public extension KeyPath where Value: SQLiteValueComparable {
    /// IN predicate with array (alternative syntax)
    func `in`(_ values: [Value]) -> Predicate<Root> {
        self ~= values
    }

    /// NOT IN predicate
    func notIn(_ values: [Value]) -> Predicate<Root> {
        Predicate(resolving: {
            let column = try columnName(for: self)
            guard !values.isEmpty else {
                // Empty array - always true
                return Predicate(sql: "1 = 1", values: [])
            }
            let placeholders = values.map { _ in "?" }.joined(separator: ", ")
            let sqliteValues = values.map { $0.sqliteValue }
            return Predicate(sql: "\(column) NOT IN (\(placeholders))", values: sqliteValues)
        })
    }
}

// MARK: - NULL checks

public extension KeyPath {
    var isNull: Predicate<Root> {
        Predicate(resolving: {
            let column = try columnName(for: self)
            return Predicate(sql: "\(column) IS NULL", values: [])
        })
    }

    var isNotNull: Predicate<Root> {
        Predicate(resolving: {
            let column = try columnName(for: self)
            return Predicate(sql: "\(column) IS NOT NULL", values: [])
        })
    }
}

// MARK: - Entity identity metadata

extension Predicate where T: EntityProtocol {
    static func identities(_ ids: [Any]) -> Self {
        Predicate(resolving: {
            let predicates = ids.map { identity($0) }
            for predicate in predicates { try predicate.validate() }
            guard !predicates.isEmpty else { return Predicate(sql: "0 = 1") }
            let values = predicates.flatMap { $0.values }
            if T.syncKeyColumns.count == 1 {
                // Retain IN for single keys so large ID lists do not create deep OR expressions.
                let column = T.syncKeyColumns[0]
                let placeholders = values.map { _ in "?" }.joined(separator: ", ")
                var terms = values.isEmpty ? [] : ["\(column) IN (\(placeholders))"]
                if predicates.contains(where: { $0.values.isEmpty }) {
                    terms.append("\(column) IS NULL")
                }
                return Predicate(sql: "(" + terms.joined(separator: " OR ") + ")", values: values)
            }
            return Predicate(sql: "(" + predicates.map { "(\($0.sql))" }.joined(separator: " OR ") + ")", values: values)
        })
    }

    static func identity(_ id: Any) -> Self {
        Predicate(resolving: {
            let values = try T.sqliteIdentityValues(for: id)
            let columns = T.syncKeyColumns
            guard !columns.isEmpty, columns.count == values.count,
                  columns.allSatisfy({ name in T.columns.contains { $0.name == name } }) else {
                throw StoreError.invalidSchema("Invalid identity metadata for \(T.self)")
            }
            let terms = zip(columns, values).map { column, value in
                value == .null ? "\(column) IS NULL" : "\(column) = ?"
            }
            return Predicate(sql: terms.joined(separator: " AND "), values: values.filter { $0 != .null })
        })
    }
}
