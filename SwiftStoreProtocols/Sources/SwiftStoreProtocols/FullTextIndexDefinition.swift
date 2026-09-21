import Foundation

/// Built-in FTS5 tokenizers. Trigram MATCH requires at least three Unicode characters.
public enum FullTextTokenizer: String, Codable, Sendable {
    case unicode61
    case porter
    case trigram
}

/// One text projection in an external-content view. JSON paths follow Embedded's original Swift property names.
public struct FullTextColumn: Codable, Sendable, Equatable {
    public let name: String
    public let column: String
    public let jsonPath: String?
    /// Array paths, relative to the column and then to each preceding element.
    public let arrayPaths: [String]?

    public init(name: String, column: String, jsonPath: String? = nil, arrayPaths: [String]? = nil) {
        self.name = name
        self.column = column
        self.jsonPath = jsonPath
        self.arrayPaths = arrayPaths
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

// Declaration markers only. The macro reads these expressions; their return value is the
// array key path so ordinary key paths and recursive markers share a contextual root type.
extension PartialKeyPath {
    public static func each<Element>(_ array: KeyPath<Root, [Element]>,
                                     fields: PartialKeyPath<Element>...) -> PartialKeyPath<Root> { array }
    public static func each<Element>(_ array: KeyPath<Root, [Element]?>,
                                     fields: PartialKeyPath<Element>...) -> PartialKeyPath<Root> { array }
}

// Unexecuted closures emitted by the macro let Swift validate every array and text leaf.
public func _validateFullTextFields<Root>(_ root: Root.Type, fields: (Root) -> Void) {}
public func _validateFullTextEach<Root, Element>(_ root: Root, _ path: KeyPath<Root, [Element]>,
                                                fields: (Element) -> Void) {}
public func _validateFullTextEach<Root, Element>(_ root: Root, _ path: KeyPath<Root, [Element]?>,
                                                fields: (Element) -> Void) {}
public func _validateFullTextColumn<Root>(_ root: Root, _ path: KeyPath<Root, String>) {}
public func _validateFullTextColumn<Root>(_ root: Root, _ path: KeyPath<Root, String?>) {}
