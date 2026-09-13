import Foundation

/// Protocol for types embedded in @Entity structs using a raw-value codec or JSON.
///
/// Types conforming to this protocol:
/// - Delegate raw-value storage to RawValue; other embedded values use JSON TEXT
/// - Support fault-tolerant decoding (missing keys use defaults)
/// - Conform to SQLiteValueCodable for unified encode/decode
///
/// Use the @Embedded macro to automatically generate conformance.
/// Note: Do NOT declare Codable on your type - the macro adds it automatically.
///
/// Example:
/// ```swift
/// @Embedded
/// struct Address {
///     var street: String = ""
///     var city: String = ""
/// }
///
/// @Embedded
/// enum Status: String {
///     case active, inactive
/// }
/// ```
public protocol Embedded: Codable, Sendable, SQLiteValueCodable {}

extension Array: Embedded where Element: Embedded {
}

extension Dictionary: Embedded where Key: Codable, Value: Embedded {
}

extension Set: Embedded where Element: Embedded {
}

extension Optional: Embedded where Wrapped: Embedded {
}

// MARK: - Default SQLiteValueCodable Implementation for Embedded Types

extension Embedded {
    /// Embedded types are stored as TEXT (JSON)
    public static var sqliteType: SQLiteType { .text }
    public static var sqliteIsJSONEncoded: Bool { true }

    /// Encode to JSON string
    public func sqliteEncode() throws -> SQLiteValue {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let jsonData = try encoder.encode(self)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw SQLiteValueError.encodingFailed("Failed to encode \(Self.self) to JSON string")
        }
        return .text(jsonString)
    }

    /// Decode from JSON string
    public init(from sqliteValue: SQLiteValue) throws {
        guard case .text(let jsonString) = sqliteValue else {
            throw SQLiteValueError.typeMismatch(expected: "text", actual: sqliteValue)
        }
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw SQLiteValueError.decodingFailed("Failed to convert JSON string to data")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self = try decoder.decode(Self.self, from: jsonData)
    }
}

/// RawRepresentable storage follows the RawValue codec without type-specific branches.
/// Codable inside a containing JSON document is unchanged. Historical formats belong in migrations.
extension Embedded where Self: RawRepresentable, RawValue: SQLiteValueCodable {
    public static var sqliteType: SQLiteType { RawValue.sqliteType }
    public static var sqliteIsJSONEncoded: Bool { RawValue.sqliteIsJSONEncoded }
    public func sqliteEncode() throws -> SQLiteValue { try rawValue.sqliteEncode() }

    public init(from sqliteValue: SQLiteValue) throws {
        let value = try RawValue(from: sqliteValue)
        guard let decoded = Self(rawValue: value) else {
            throw SQLiteValueError.decodingFailed("Invalid raw value for \(Self.self): \(value)")
        }
        self = decoded
    }
}
