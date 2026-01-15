import Foundation

// MARK: - Core Protocols

/// Protocol for types that can be encoded to SQLiteValue.
///
/// Similar to Swift's `Encodable` protocol.
///
/// Example:
/// ```swift
/// extension Status: SQLiteValueEncodable {
///     public static var sqliteType: SQLiteType { .text }
///     public func sqliteEncode() throws -> SQLiteValue { .text(rawValue) }
/// }
/// ```
public protocol SQLiteValueEncodable: Sendable {
    /// The SQLite column type for this Swift type
    static var sqliteType: SQLiteType { get }

    /// Encode this value to SQLiteValue for storage
    func sqliteEncode() throws -> SQLiteValue
}

/// Protocol for types that can be decoded from SQLiteValue.
///
/// Similar to Swift's `Decodable` protocol.
///
/// Example:
/// ```swift
/// extension Status: SQLiteValueDecodable {
///     public init(from sqliteValue: SQLiteValue) throws {
///         guard case .text(let v) = sqliteValue,
///               let status = Status(rawValue: v) else {
///             throw SQLiteValueError.decodingFailed("Invalid Status value")
///         }
///         self = status
///     }
/// }
/// ```
public protocol SQLiteValueDecodable: Sendable {
    /// Initialize from a SQLiteValue
    /// - Parameter sqliteValue: The SQLite value to decode from
    /// - Throws: SQLiteValueError if decoding fails
    init(from sqliteValue: SQLiteValue) throws
}

/// Combined protocol for types that can be both encoded to and decoded from SQLiteValue.
///
/// This is the primary protocol for types used as Entity properties.
/// Similar to Swift's `Codable = Encodable & Decodable`.
public typealias SQLiteValueCodable = SQLiteValueEncodable & SQLiteValueDecodable

// MARK: - SQLiteComparable

/// Protocol for types that can be used in SQL predicates (WHERE clauses).
///
/// Inherits from `SQLiteValueCodable` to ensure types can be both
/// encoded to and decoded from SQLite values.
///
/// Types conforming to this protocol can be used in filter predicates:
/// ```swift
/// store.query(User.self).filter { $0.status == .active }
/// ```
///
/// **Important**: Types conforming to `SQLiteComparable` must have infallible encoding.
/// The `sqliteValue` property provides non-optional access for use in predicates.
public protocol SQLiteValueComparable: SQLiteValueCodable {
    /// Non-optional SQLite value for use in predicates.
    /// Types conforming to SQLiteComparable must guarantee encoding never fails.
    var sqliteValue: SQLiteValue { get }
}

// MARK: - Errors

/// Errors that can occur during SQLite value encoding/decoding
public enum SQLiteValueError: Error, CustomStringConvertible {
    case encodingFailed(String)
    case decodingFailed(String)
    case typeMismatch(expected: String, actual: SQLiteValue)
    case nullValue

    public var description: String {
        switch self {
        case .encodingFailed(let message):
            return "SQLite encoding failed: \(message)"
        case .decodingFailed(let message):
            return "SQLite decoding failed: \(message)"
        case .typeMismatch(let expected, let actual):
            return "SQLite type mismatch: expected \(expected), got \(actual)"
        case .nullValue:
            return "Unexpected NULL value"
        }
    }
}

// MARK: - Primitive Type Extensions

extension String: SQLiteValueCodable {
    public static var sqliteType: SQLiteType { .text }
    public func sqliteEncode() throws -> SQLiteValue { .text(self) }
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .text(let v) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "text", actual: sqliteValue)
        }
        self = v
    }
}

extension Int: SQLiteValueCodable {
    public static var sqliteType: SQLiteType { .integer }
    public func sqliteEncode() throws -> SQLiteValue { .integer(Int64(self)) }
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .integer(let v) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "integer", actual: sqliteValue)
        }
        self = Int(v)
    }
}

extension Int64: SQLiteValueCodable {
    public static var sqliteType: SQLiteType { .integer }
    public func sqliteEncode() throws -> SQLiteValue { .integer(self) }
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .integer(let v) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "integer", actual: sqliteValue)
        }
        self = v
    }
}

extension Int32: SQLiteValueCodable {
    public static var sqliteType: SQLiteType { .integer }
    public func sqliteEncode() throws -> SQLiteValue { .integer(Int64(self)) }
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .integer(let v) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "integer", actual: sqliteValue)
        }
        self = Int32(v)
    }
}

extension Int16: SQLiteValueCodable {
    public static var sqliteType: SQLiteType { .integer }
    public func sqliteEncode() throws -> SQLiteValue { .integer(Int64(self)) }
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .integer(let v) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "integer", actual: sqliteValue)
        }
        self = Int16(v)
    }
}

extension Int8: SQLiteValueCodable {
    public static var sqliteType: SQLiteType { .integer }
    public func sqliteEncode() throws -> SQLiteValue { .integer(Int64(self)) }
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .integer(let v) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "integer", actual: sqliteValue)
        }
        self = Int8(v)
    }
}

extension UInt: SQLiteValueCodable {
    public static var sqliteType: SQLiteType { .integer }
    public func sqliteEncode() throws -> SQLiteValue { .integer(Int64(self)) }
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .integer(let v) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "integer", actual: sqliteValue)
        }
        self = UInt(v)
    }
}

extension UInt64: SQLiteValueCodable {
    public static var sqliteType: SQLiteType { .integer }
    public func sqliteEncode() throws -> SQLiteValue { .integer(Int64(self)) }
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .integer(let v) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "integer", actual: sqliteValue)
        }
        self = UInt64(v)
    }
}

extension UInt32: SQLiteValueCodable {
    public static var sqliteType: SQLiteType { .integer }
    public func sqliteEncode() throws -> SQLiteValue { .integer(Int64(self)) }
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .integer(let v) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "integer", actual: sqliteValue)
        }
        self = UInt32(v)
    }
}

extension UInt16: SQLiteValueCodable {
    public static var sqliteType: SQLiteType { .integer }
    public func sqliteEncode() throws -> SQLiteValue { .integer(Int64(self)) }
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .integer(let v) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "integer", actual: sqliteValue)
        }
        self = UInt16(v)
    }
}

extension UInt8: SQLiteValueCodable {
    public static var sqliteType: SQLiteType { .integer }
    public func sqliteEncode() throws -> SQLiteValue { .integer(Int64(self)) }
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .integer(let v) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "integer", actual: sqliteValue)
        }
        self = UInt8(v)
    }
}

extension Double: SQLiteValueCodable {
    public static var sqliteType: SQLiteType { .real }
    public func sqliteEncode() throws -> SQLiteValue { .real(self) }
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .real(let v) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "real", actual: sqliteValue)
        }
        self = v
    }
}

extension Float: SQLiteValueCodable {
    public static var sqliteType: SQLiteType { .real }
    public func sqliteEncode() throws -> SQLiteValue { .real(Double(self)) }
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .real(let v) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "real", actual: sqliteValue)
        }
        self = Float(v)
    }
}

extension CGFloat: SQLiteValueCodable {
    public static var sqliteType: SQLiteType { .real }
    public func sqliteEncode() throws -> SQLiteValue { .real(Double(self)) }
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .real(let v) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "real", actual: sqliteValue)
        }
        self = CGFloat(v)
    }
}

extension Bool: SQLiteValueCodable {
    public static var sqliteType: SQLiteType { .integer }
    public func sqliteEncode() throws -> SQLiteValue { .integer(self ? 1 : 0) }
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .integer(let v) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "integer", actual: sqliteValue)
        }
        self = v != 0
    }
}

extension Date: SQLiteValueCodable {
    public static var sqliteType: SQLiteType { .real }
    public func sqliteEncode() throws -> SQLiteValue { .real(timeIntervalSince1970) }
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .real(let v) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "real", actual: sqliteValue)
        }
        self = Date(timeIntervalSince1970: v)
    }
}

extension UUID: SQLiteValueCodable {
    public static var sqliteType: SQLiteType { .text }
    public func sqliteEncode() throws -> SQLiteValue { .text(uuidString) }
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .text(let v) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "text", actual: sqliteValue)
        }
        guard let uuid = UUID(uuidString: v) else {
            throw SQLiteValueError.decodingFailed("Invalid UUID string: \(v)")
        }
        self = uuid
    }
}

extension UUIDV7: SQLiteValueCodable {
    public static var sqliteType: SQLiteType { .blob }
    public func sqliteEncode() throws -> SQLiteValue { .blob(data) }
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .blob(let v) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "blob", actual: sqliteValue)
        }
        guard let uuid = UUIDV7(data: v) else {
            throw SQLiteValueError.decodingFailed("Invalid UUIDV7 data")
        }
        self = uuid
    }
}

extension Data: SQLiteValueCodable {
    public static var sqliteType: SQLiteType { .blob }
    public func sqliteEncode() throws -> SQLiteValue { .blob(self) }
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .blob(let v) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "blob", actual: sqliteValue)
        }
        self = v
    }
}

extension URL: SQLiteValueCodable {
    public static var sqliteType: SQLiteType { .text }
    public func sqliteEncode() throws -> SQLiteValue { .text(absoluteString) }
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .text(let v) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "text", actual: sqliteValue)
        }
        guard let url = URL(string: v) else {
            throw SQLiteValueError.decodingFailed("Invalid URL string: \(v)")
        }
        self = url
    }
}

// MARK: - Optional Extension

extension Optional: SQLiteValueEncodable where Wrapped: SQLiteValueEncodable {
    public static var sqliteType: SQLiteType { Wrapped.sqliteType }
    public func sqliteEncode() throws -> SQLiteValue {
        switch self {
        case .some(let value):
            return try value.sqliteEncode()
        case .none:
            return .null
        }
    }
}

extension Optional: SQLiteValueDecodable where Wrapped: SQLiteValueDecodable {
    public init(from sqliteValue: SQLiteValue) throws {
        if case .null = sqliteValue {
            self = .none
        } else {
            self = .some(try Wrapped(from: sqliteValue))
        }
    }
}

// MARK: - SQLiteComparable Conformances

extension String: SQLiteValueComparable {
    public var sqliteValue: SQLiteValue { .text(self) }
}
extension Int: SQLiteValueComparable {
    public var sqliteValue: SQLiteValue { .integer(Int64(self)) }
}
extension Int64: SQLiteValueComparable {
    public var sqliteValue: SQLiteValue { .integer(self) }
}
extension Int32: SQLiteValueComparable {
    public var sqliteValue: SQLiteValue { .integer(Int64(self)) }
}
extension Int16: SQLiteValueComparable {
    public var sqliteValue: SQLiteValue { .integer(Int64(self)) }
}
extension Int8: SQLiteValueComparable {
    public var sqliteValue: SQLiteValue { .integer(Int64(self)) }
}
extension UInt: SQLiteValueComparable {
    public var sqliteValue: SQLiteValue { .integer(Int64(self)) }
}
extension UInt64: SQLiteValueComparable {
    public var sqliteValue: SQLiteValue { .integer(Int64(self)) }
}
extension UInt32: SQLiteValueComparable {
    public var sqliteValue: SQLiteValue { .integer(Int64(self)) }
}
extension UInt16: SQLiteValueComparable {
    public var sqliteValue: SQLiteValue { .integer(Int64(self)) }
}
extension UInt8: SQLiteValueComparable {
    public var sqliteValue: SQLiteValue { .integer(Int64(self)) }
}
extension Double: SQLiteValueComparable {
    public var sqliteValue: SQLiteValue { .real(self) }
}
extension Float: SQLiteValueComparable {
    public var sqliteValue: SQLiteValue { .real(Double(self)) }
}
extension Bool: SQLiteValueComparable {
    public var sqliteValue: SQLiteValue { .integer(self ? 1 : 0) }
}
extension Date: SQLiteValueComparable {
    public var sqliteValue: SQLiteValue { .real(timeIntervalSince1970) }
}
extension UUID: SQLiteValueComparable {
    public var sqliteValue: SQLiteValue { .text(uuidString) }
}
extension UUIDV7: SQLiteValueComparable {
    public var sqliteValue: SQLiteValue { .blob(data) }
}
extension Data: SQLiteValueComparable {
    public var sqliteValue: SQLiteValue { .blob(self) }
}
extension URL: SQLiteValueComparable {
    public var sqliteValue: SQLiteValue { .text(absoluteString) }
}

extension Optional: SQLiteValueComparable where Wrapped: SQLiteValueComparable {
    public var sqliteValue: SQLiteValue {
        switch self {
        case .some(let value): return value.sqliteValue
        case .none: return .null
        }
    }
}

// MARK: - Array Extension (stored as JSON)

extension Array: SQLiteValueEncodable where Element: Encodable {
    public static var sqliteType: SQLiteType { .text }
    public func sqliteEncode() throws -> SQLiteValue {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SQLiteValueError.encodingFailed("Failed to encode array to JSON string")
        }
        return .text(json)
    }
}

extension Array: SQLiteValueDecodable where Element: Decodable {
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .text(let json) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "text (JSON)", actual: sqliteValue)
        }
        guard let data = json.data(using: .utf8) else {
            throw SQLiteValueError.decodingFailed("Invalid JSON string")
        }
        let decoder = JSONDecoder()
        self = try decoder.decode([Element].self, from: data)
    }
}

// MARK: - Set Extension (stored as JSON)

extension Set: SQLiteValueEncodable where Element: Encodable {
    public static var sqliteType: SQLiteType { .text }
    public func sqliteEncode() throws -> SQLiteValue {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SQLiteValueError.encodingFailed("Failed to encode array to JSON string")
        }
        return .text(json)
    }
}

extension Set: SQLiteValueDecodable where Element: Decodable {
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .text(let json) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "text (JSON)", actual: sqliteValue)
        }
        guard let data = json.data(using: .utf8) else {
            throw SQLiteValueError.decodingFailed("Invalid JSON string")
        }
        let decoder = JSONDecoder()
        self = try decoder.decode(Set<Element>.self, from: data)
    }
}

// MARK: - Dictionary Extension (stored as JSON)

extension Dictionary: SQLiteValueEncodable where Key: Encodable, Value: Encodable {
    public static var sqliteType: SQLiteType { .text }
    public func sqliteEncode() throws -> SQLiteValue {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SQLiteValueError.encodingFailed("Failed to encode dictionary to JSON string")
        }
        return .text(json)
    }
}

extension Dictionary: SQLiteValueDecodable where Key: Decodable, Value: Decodable {
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .text(let json) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "text (JSON)", actual: sqliteValue)
        }
        guard let data = json.data(using: .utf8) else {
            throw SQLiteValueError.decodingFailed("Invalid JSON string")
        }
        let decoder = JSONDecoder()
        self = try decoder.decode([Key: Value].self, from: data)
    }
}
