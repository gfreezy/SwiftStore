import Foundation

/// Protocol for types that can be embedded in @Entity structs as JSON.
///
/// Types conforming to this protocol:
/// - Are stored as JSON TEXT in SQLite
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
