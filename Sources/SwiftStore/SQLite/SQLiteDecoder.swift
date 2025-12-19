import Foundation

/// Decodes SQLite rows to Swift entities
public struct SQLiteDecoder: Sendable {
    private let jsonDecoder: JSONDecoder

    public init() {
        self.jsonDecoder = JSONDecoder()
        self.jsonDecoder.dateDecodingStrategy = .secondsSince1970
    }

    /// Decode a statement row to an entity
    /// Uses optimized macro-generated implementation if available, otherwise falls back to reflection
    public func decode<E: EntityProtocol>(_ type: E.Type, from statement: SQLiteStatement) throws -> E {
        // Use optimized path if entity conforms to SQLiteDecodable
        if let decodableType = type as? any SQLiteDecodable.Type {
            // We need to call the static method through the protocol
            return try decodableType.sqliteDecode(from: statement) as! E
        }

        // Fallback to reflection-based decoding
        return try decodeFallback(type, from: statement)
    }

    /// Fallback decoding using JSONSerialization (slower, but works for non-macro entities)
    private func decodeFallback<E: EntityProtocol>(_ type: E.Type, from statement: SQLiteStatement) throws -> E {
        var dict: [String: Any] = [:]

        for i in 0..<statement.columnCount {
            guard let columnName = statement.columnName(i) else { continue }
            let propertyName = columnName.snakeCaseToCamelCase()

            if statement.isNull(i) {
                dict[propertyName] = NSNull()
                continue
            }

            // Find the column definition to determine the expected type
            let columnDef = E.columns.first { $0.name == columnName }

            if let def = columnDef {
                switch def.type {
                case .text:
                    if let text = statement.columnString(i) {
                        // Only try to parse as JSON if the column is marked as JSON-encoded
                        if def.isJSONEncoded,
                           let jsonData = text.data(using: .utf8),
                           let jsonValue = try? JSONSerialization.jsonObject(with: jsonData) {
                            dict[propertyName] = jsonValue
                        } else {
                            dict[propertyName] = text
                        }
                    }
                case .integer:
                    dict[propertyName] = statement.columnInt64(i)
                case .real:
                    dict[propertyName] = statement.columnDouble(i)
                case .blob:
                    if let data = statement.columnData(i) {
                        // Check if this is a 16-byte UUID blob
                        if data.count == 16 {
                            if let uuidv4 = UUIDV4(data: data) {
                                dict[propertyName] = uuidv4.uuidString
                            } else {
                                dict[propertyName] = data.base64EncodedString()
                            }
                        } else {
                            dict[propertyName] = data.base64EncodedString()
                        }
                    }
                }
            } else {
                // Fallback: try to infer type
                if let text = statement.columnString(i) {
                    dict[propertyName] = text
                }
            }
        }

        // Convert dictionary to JSON data and decode
        let jsonData = try JSONSerialization.data(withJSONObject: dict)
        return try jsonDecoder.decode(E.self, from: jsonData)
    }

    /// Decode an entity from JSON string
    public func decode<E: EntityProtocol>(_ type: E.Type, fromJSON json: String) throws -> E {
        guard let data = json.data(using: .utf8) else {
            throw StoreError.decodingFailed("Invalid JSON string")
        }
        return try jsonDecoder.decode(E.self, from: data)
    }

    /// Decode multiple entities from a statement
    public func decodeAll<E: EntityProtocol>(_ type: E.Type, from statement: SQLiteStatement) throws -> [E] {
        var results: [E] = []
        while try statement.step() {
            let entity = try decode(type, from: statement)
            results.append(entity)
        }
        return results
    }
}
