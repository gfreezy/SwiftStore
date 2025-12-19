import Foundation

/// Encodes Swift values to SQLite compatible values
public struct SQLiteEncoder: Sendable {
    private let jsonEncoder: JSONEncoder

    public init() {
        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.dateEncodingStrategy = .secondsSince1970
    }

    /// Encode an entity to a dictionary of column name to SQLite value
    /// Uses optimized macro-generated implementation if available, otherwise falls back to reflection
    public func encode<E: EntityProtocol>(_ entity: E) throws -> [String: SQLiteValue] {
        // Use optimized path if entity conforms to SQLiteEncodable
        if let encodable = entity as? any SQLiteEncodable {
            return try encodable.sqliteEncode()
        }

        // Fallback to reflection-based encoding
        return try encodeFallback(entity)
    }

    /// Fallback encoding using JSONSerialization (slower, but works for non-macro entities)
    private func encodeFallback<E: EntityProtocol>(_ entity: E) throws -> [String: SQLiteValue] {
        let data = try jsonEncoder.encode(entity)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StoreError.encodingFailed("Failed to serialize entity to dictionary")
        }

        var result: [String: SQLiteValue] = [:]

        for (key, value) in dict {
            let columnName = key.camelCaseToSnakeCase()
            result[columnName] = try encodeValue(value, forKey: key, in: E.columns)
        }

        return result
    }

    private func encodeValue(_ value: Any, forKey key: String, in columns: [ColumnDefinition]) throws -> SQLiteValue {
        // Handle nested Codable types (store as JSON)
        if let dict = value as? [String: Any] {
            let jsonData = try JSONSerialization.data(withJSONObject: dict)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw StoreError.encodingFailed("Failed to encode nested object to JSON string")
            }
            return .text(jsonString)
        }

        if let array = value as? [Any] {
            let jsonData = try JSONSerialization.data(withJSONObject: array)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw StoreError.encodingFailed("Failed to encode array to JSON string")
            }
            return .text(jsonString)
        }

        // Handle primitive types
        switch value {
        case let string as String:
            return .text(string)
        case let int as Int:
            return .integer(Int64(int))
        case let int64 as Int64:
            return .integer(int64)
        case let double as Double:
            return .real(double)
        case let bool as Bool:
            return .integer(bool ? 1 : 0)
        case is NSNull:
            return .null
        default:
            // Try to encode as JSON
            if JSONSerialization.isValidJSONObject([value]) {
                let jsonData = try JSONSerialization.data(withJSONObject: value)
                guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                    throw StoreError.encodingFailed("Failed to encode value to JSON")
                }
                return .text(jsonString)
            }
            throw StoreError.encodingFailed("Unsupported value type: \(type(of: value))")
        }
    }

    /// Encode entity to JSON string for sync payload
    public func encodeToJSON<E: EntityProtocol>(_ entity: E) throws -> String {
        let data = try jsonEncoder.encode(entity)
        guard let string = String(data: data, encoding: .utf8) else {
            throw StoreError.encodingFailed("Failed to encode entity to JSON string")
        }
        return string
    }
}

/// SQLite value types
public enum SQLiteValue: Sendable, Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    /// Bind this value to a statement at the given index
    public func bind(to statement: SQLiteStatement, at index: Int32) throws {
        switch self {
        case .null:
            try statement.bindNull(index)
        case .integer(let value):
            try statement.bind(index, value)
        case .real(let value):
            try statement.bind(index, value)
        case .text(let value):
            try statement.bind(index, value)
        case .blob(let value):
            try statement.bind(index, value)
        }
    }
}

extension String {
    func camelCaseToSnakeCase() -> String {
        var result = ""
        for (index, char) in self.enumerated() {
            if char.isUppercase {
                if index > 0 {
                    result.append("_")
                }
                result.append(char.lowercased())
            } else {
                result.append(char)
            }
        }
        return result
    }

    func snakeCaseToCamelCase() -> String {
        let parts = self.split(separator: "_")
        guard let first = parts.first else { return self }

        var result = String(first)
        for part in parts.dropFirst() {
            result += part.capitalized
        }
        return result
    }
}
