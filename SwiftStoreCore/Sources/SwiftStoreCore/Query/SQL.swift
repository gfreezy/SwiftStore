import Foundation

/// Type-safe SQL string with interpolation support
/// Supports parameterized queries for safe value interpolation
/// Usage:
/// ```swift
/// let status = "active"
/// let count = 10
/// let sql: SQL = "UPDATE \(User.self) SET \(\User.status) = \(status) AND \(\User.count) = \(count)"
/// try store.execute(sql)
/// ```
public struct SQL: ExpressibleByStringInterpolation, Sendable {
    public let sql: String
    public let values: [SQLiteValue]

    public init(stringLiteral value: String) {
        self.sql = value
        self.values = []
    }

    public init(stringInterpolation: StringInterpolation) {
        self.sql = stringInterpolation.sql
        self.values = stringInterpolation.values
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        var sql: String = ""
        var values: [SQLiteValue] = []

        public init(literalCapacity: Int, interpolationCount: Int) {
            sql.reserveCapacity(literalCapacity)
            values.reserveCapacity(interpolationCount)
        }

        public mutating func appendLiteral(_ literal: String) {
            sql += literal
        }

        /// Interpolate entity type as table name: `\(User.self)`
        public mutating func appendInterpolation<E: EntityProtocol>(_ type: E.Type) {
            sql += E.tableName
        }

        /// Interpolate KeyPath as column name: `\(\.name)` or `\(\User.name)`
        public mutating func appendInterpolation<T, V>(_ keyPath: KeyPath<T, V>) {
            sql += columnName(for: keyPath)
        }

        /// Interpolate Column as column name: `\($0.name)`
        public mutating func appendInterpolation<T, V>(_ column: Column<T, V>) {
            sql += column.name
        }

        /// Interpolate raw string (NOT parameterized - use with caution)
        public mutating func appendInterpolation(raw value: String) {
            sql += value
        }

        // MARK: - Value Interpolation (Parameterized)

        /// Interpolate String value as parameter
        public mutating func appendInterpolation(_ value: String) {
            sql += "?"
            values.append(.text(value))
        }

        /// Interpolate Int value as parameter
        public mutating func appendInterpolation(_ value: Int) {
            sql += "?"
            values.append(.integer(Int64(value)))
        }

        /// Interpolate Int64 value as parameter
        public mutating func appendInterpolation(_ value: Int64) {
            sql += "?"
            values.append(.integer(value))
        }

        /// Interpolate Double value as parameter
        public mutating func appendInterpolation(_ value: Double) {
            sql += "?"
            values.append(.real(value))
        }

        /// Interpolate Bool value as parameter
        public mutating func appendInterpolation(_ value: Bool) {
            sql += "?"
            values.append(.integer(value ? 1 : 0))
        }

        /// Interpolate Date value as parameter
        public mutating func appendInterpolation(_ value: Date) {
            sql += "?"
            values.append(.real(value.timeIntervalSince1970))
        }

        /// Interpolate UUID value as parameter
        public mutating func appendInterpolation(_ value: UUID) {
            sql += "?"
            values.append(.text(value.uuidString))
        }

        /// Interpolate UUIDV7 value as parameter
        public mutating func appendInterpolation(_ value: UUIDV7) {
            sql += "?"
            values.append(.blob(value.data))
        }

        /// Interpolate Data value as parameter
        public mutating func appendInterpolation(_ value: Data) {
            sql += "?"
            values.append(.blob(value))
        }

        /// Interpolate optional value as parameter
        public mutating func appendInterpolation<V: SQLiteComparable>(_ value: V?) {
            sql += "?"
            if let value = value {
                values.append(value.sqliteValue)
            } else {
                values.append(.null)
            }
        }

        /// Interpolate SQLiteValue directly
        public mutating func appendInterpolation(_ value: SQLiteValue) {
            sql += "?"
            values.append(value)
        }
    }
}

// MARK: - Row type with KeyPath subscript

/// A row result that supports KeyPath-based access
/// Usage:
/// ```swift
/// let rows = try store.queryRows("SELECT * FROM \(User.self)" as SQL)
/// for row in rows {
///     let name: String? = row[\User.name]
///     let age: Int? = row[\User.age]
/// }
/// ```
public struct Row: Sendable {
    public let data: [String: SQLiteValue]

    public init(_ data: [String: SQLiteValue]) {
        self.data = data
    }

    /// Access column by string key
    public subscript(key: String) -> SQLiteValue? {
        data[key]
    }

    /// Access column by KeyPath, returns non-optional typed value
    /// Crashes if column is missing or value cannot be extracted
    public subscript<T, V: SQLiteExtractable>(keyPath: KeyPath<T, V>) -> V {
        let column = columnName(for: keyPath)
        guard let value = data[column], let extracted = V.extract(from: value) else {
            fatalError("Column '\(column)' not found or cannot be extracted as \(V.self)")
        }
        return extracted
    }

    /// Access optional column by KeyPath, returns optional typed value
    public subscript<T, V: SQLiteExtractable>(keyPath: KeyPath<T, V?>) -> V? {
        let column = columnName(for: keyPath)
        guard let value = data[column] else { return nil }
        if case .null = value { return nil }
        return V.extract(from: value)
    }

    /// Access column by KeyPath, returns optional typed value
    public func get<T, V: SQLiteExtractable>(_ keyPath: KeyPath<T, V>) -> V? {
        let column = columnName(for: keyPath)
        guard let value = data[column] else { return nil }
        return V.extract(from: value)
    }

    /// Access optional column by KeyPath, returns optional typed value
    public func get<T, V: SQLiteExtractable>(_ keyPath: KeyPath<T, V?>) -> V? {
        let column = columnName(for: keyPath)
        guard let value = data[column] else { return nil }
        return V.extract(from: value)
    }
}

/// Protocol for types that can be extracted from SQLiteValue
public protocol SQLiteExtractable {
    static func extract(from value: SQLiteValue) -> Self?
}

extension String: SQLiteExtractable {
    public static func extract(from value: SQLiteValue) -> String? {
        if case .text(let v) = value { return v }
        return nil
    }
}

extension Int: SQLiteExtractable {
    public static func extract(from value: SQLiteValue) -> Int? {
        if case .integer(let v) = value { return Int(v) }
        return nil
    }
}

extension Int64: SQLiteExtractable {
    public static func extract(from value: SQLiteValue) -> Int64? {
        if case .integer(let v) = value { return v }
        return nil
    }
}

extension Double: SQLiteExtractable {
    public static func extract(from value: SQLiteValue) -> Double? {
        if case .real(let v) = value { return v }
        return nil
    }
}

extension Bool: SQLiteExtractable {
    public static func extract(from value: SQLiteValue) -> Bool? {
        if case .integer(let v) = value { return v != 0 }
        return nil
    }
}

extension Date: SQLiteExtractable {
    public static func extract(from value: SQLiteValue) -> Date? {
        if case .real(let v) = value { return Date(timeIntervalSince1970: v) }
        return nil
    }
}

extension Data: SQLiteExtractable {
    public static func extract(from value: SQLiteValue) -> Data? {
        if case .blob(let v) = value { return v }
        return nil
    }
}

extension UUIDV7: SQLiteExtractable {
    public static func extract(from value: SQLiteValue) -> UUIDV7? {
        if case .blob(let v) = value { return UUIDV7(data: v) }
        return nil
    }
}

extension UUID: SQLiteExtractable {
    public static func extract(from value: SQLiteValue) -> UUID? {
        if case .text(let v) = value { return UUID(uuidString: v) }
        return nil
    }
}
