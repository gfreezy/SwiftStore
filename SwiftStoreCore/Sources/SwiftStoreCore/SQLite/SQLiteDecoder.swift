import Foundation
import SwiftStoreProtocols

/// Decodes SQLite rows to Swift entities
public struct SQLiteDecoder: Sendable {
    private let jsonDecoder: JSONDecoder

    public init() {
        self.jsonDecoder = JSONDecoder()
        self.jsonDecoder.dateDecodingStrategy = .secondsSince1970
    }

    /// Decode a statement row to an entity
    /// Entity must conform to SQLiteDecodable (use @Entity macro)
    public func decode<E: EntityProtocol>(_ type: E.Type, from statement: SQLiteStatementImpl) throws -> E {
        return try type.sqliteDecode(from: statement)
    }

    /// Decode an entity from JSON string
    public func decode<E: EntityProtocol>(_ type: E.Type, fromJSON json: String) throws -> E {
        guard let data = json.data(using: .utf8) else {
            throw StoreError.decodingFailed("Invalid JSON string")
        }
        return try jsonDecoder.decode(E.self, from: data)
    }

    /// Decode multiple entities from a statement
    public func decodeAll<E: EntityProtocol>(_ type: E.Type, from statement: SQLiteStatementImpl) throws -> [E] {
        var results: [E] = []
        while try statement.step() {
            let entity = try decode(type, from: statement)
            results.append(entity)
        }
        return results
    }
}
