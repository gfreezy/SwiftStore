import Foundation
import SwiftStoreProtocols

/// A JSON-compatible value that can be encoded/decoded
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case data(Data)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .data(let value):
            // Encode Data as object with type marker for frontend to identify
            try container.encode([
                "_type": "blob",
                "base64": value.base64EncodedString(),
                "size": "\(value.count)"
            ])
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

extension JSONValue: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int64.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode JSONValue"
            )
        }
    }
}

// MARK: - SQLiteValue Conversion

extension JSONValue {
    /// Create JSONValue from SQLiteValue
    public init(sqliteValue: SQLiteValue) {
        switch sqliteValue {
        case .null:
            self = .null
        case .integer(let value):
            self = .int(value)
        case .real(let value):
            self = .double(value)
        case .text(let value):
            self = .string(value)
        case .blob(let value):
            self = .data(value)
        }
    }

    /// Convert to SQLiteValue for binding to queries
    public func toSQLiteValue() -> SQLiteValue {
        switch self {
        case .null:
            return .null
        case .bool(let value):
            return .integer(value ? 1 : 0)
        case .int(let value):
            return .integer(value)
        case .double(let value):
            return .real(value)
        case .string(let value):
            return .text(value)
        case .data(let value):
            return .blob(value)
        case .array, .object:
            // Encode complex types as JSON text
            if let data = try? JSONEncoder().encode(self),
               let string = String(data: data, encoding: .utf8) {
                return .text(string)
            }
            return .null
        }
    }
}

// MARK: - Row Conversion

extension JSONValue {
    /// Convert a dictionary of SQLiteValues to a JSON object
    public static func fromRow(_ row: [String: SQLiteValue]) -> JSONValue {
        var dict: [String: JSONValue] = [:]
        for (key, value) in row {
            dict[key] = JSONValue(sqliteValue: value)
        }
        return .object(dict)
    }
}
