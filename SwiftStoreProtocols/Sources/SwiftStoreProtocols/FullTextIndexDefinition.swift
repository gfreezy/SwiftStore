import Foundation

/// Built-in FTS5 tokenizers. Trigram MATCH requires at least three Unicode characters.
public enum FullTextTokenizer: String, Codable, Sendable {
    case unicode61
    case porter
    case trigram
}

/// One text projection in an external-content view. JSON paths follow Embedded's snake_case keys.
public struct FullTextColumn: Codable, Sendable, Equatable {
    public let name: String
    public let column: String
    public let jsonPath: String?

    public init(name: String, column: String, jsonPath: String? = nil) {
        self.name = name
        self.column = column
        self.jsonPath = jsonPath
    }
}

/// Immutable metadata emitted by #FullTextIndex and saved in migration snapshots.
public struct FullTextIndexDefinition: Codable, Sendable, Equatable {
    public let name: String
    public let columns: [FullTextColumn]
    public let keyColumns: [String]
    public let tokenizer: FullTextTokenizer

    public init(name: String, columns: [FullTextColumn], keyColumns: [String] = ["id"],
                tokenizer: FullTextTokenizer = .unicode61) {
        self.name = name
        self.columns = columns
        self.keyColumns = keyColumns
        self.tokenizer = tokenizer
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        columns = try values.decodeIfPresent([FullTextColumn].self, forKey: .columns) ?? []
        keyColumns = try values.decodeIfPresent([String].self, forKey: .keyColumns) ?? []
        tokenizer = try values.contains(.tokenizer)
            ? values.decode(FullTextTokenizer.self, forKey: .tokenizer) : .unicode61
    }
}

// Used by the declaration macro to type-check the leaves of nested key paths.
public func _validateFullTextColumn<T>(_ keyPath: KeyPath<T, String>) {}
public func _validateFullTextColumn<T>(_ keyPath: KeyPath<T, String?>) {}
