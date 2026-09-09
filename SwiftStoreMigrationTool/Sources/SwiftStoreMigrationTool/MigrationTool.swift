import CryptoKit
import Foundation
import SwiftStoreCore

/// One migration's table-level changes. Missing tables inherit their previous definition.
public struct SchemaDelta: Codable, Sendable, Equatable {
    public let formatVersion: Int
    public let tables: [TableSchema]
    public let droppedTables: [String]

    public init(tables: [TableSchema] = [], droppedTables: [String] = []) {
        self.formatVersion = 1
        self.tables = tables.sorted { $0.name < $1.name }
        self.droppedTables = droppedTables.sorted()
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try values.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        tables = try values.decodeIfPresent([TableSchema].self, forKey: .tables) ?? []
        droppedTables = try values.decodeIfPresent([String].self, forKey: .droppedTables) ?? []
    }

    public static func between(_ old: SchemaSnapshot, _ new: SchemaSnapshot) -> SchemaDelta {
        SchemaDelta(tables: new.tables.filter { !old.tables.contains($0) },
                    droppedTables: old.tables.map(\.name).filter { name in !new.tables.contains { $0.name == name } })
    }

    public func applying(to previous: SchemaSnapshot) throws -> SchemaSnapshot {
        try SchemaSnapshot(tables: tables).validate()
        guard formatVersion == 1, Set(droppedTables).count == droppedTables.count,
              Set(droppedTables).isDisjoint(with: tables.map(\.name)) else {
            throw VersionedMigrationError.invalidHistory("Invalid schema delta: unsupported format, duplicate deletion, or replacement/deletion overlap")
        }
        var merged = Dictionary(uniqueKeysWithValues: previous.tables.map { ($0.name, $0) })
        for name in droppedTables {
            guard merged.removeValue(forKey: name) != nil else {
                throw VersionedMigrationError.invalidHistory("Cannot drop unknown table \(name)")
            }
        }
        for table in tables { merged[table.name] = table }
        let result = SchemaSnapshot(tables: Array(merged.values))
        return try result.canonicalized()
    }
}

public struct MigrationFile {
    public let id: String
    public let target: SchemaSnapshot
    public let checksum: String
    public var symbol: String { "Migration_" + id.prefix { $0 != "_" } }
}

/// Shared implementation for the optional CLI and the build plugin. No source files are changed
/// during a build: only the registration catalog in the plugin output directory is generated.
public enum MigrationTool {
    public static func sourceFiles(at root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { throw failure("Cannot read \(root.path)") }
        return try enumerator.compactMap { value -> URL? in
            guard let url = value as? URL, url.pathExtension == "swift",
                  try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { return nil }
            return url
        }.sorted { $0.path < $1.path }
    }

    public static func currentSchema(at root: URL, sources: [URL]? = nil) throws -> SchemaSnapshot {
        try EntitySourceSchema.extract(files: sources ?? sourceFiles(at: root))
    }

    /// IDs use a numeric prefix followed by "_" and a free-form description, ordered numerically.
    /// Only changed table definitions are written. A data-only step has no JSON file.
    public static func generate(id: String, target: SchemaSnapshot, directory: URL) throws {
        let number = try migrationNumber(id)
        let target = try target.canonicalized()
        let history = try readHistory(directory: directory)
        if history.contains(where: { (try? migrationNumber($0.id)) == number }) {
            throw failure("Duplicate migration number: \(number)")
        }
        if let last = history.last, !numberLess(try migrationNumber(last.id), number) {
            throw failure("New migration number must be greater than \(last.id)")
        }
        let previous = history.last?.target ?? .empty
        let delta = SchemaDelta.between(previous, target)
        let source = try MigrationSourceGenerator.source(symbol: "Migration_" + id.prefix { $0 != "_" }, from: previous, to: target)
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let swift = directory.appendingPathComponent(id + ".swift")
        let json = directory.appendingPathComponent(id + ".schema.json")
        guard !fm.fileExists(atPath: swift.path), !fm.fileExists(atPath: json.path) else { throw failure("Refusing to overwrite migration \(id)") }
        try Data(source.utf8).write(to: swift, options: .withoutOverwriting)
        if !delta.tables.isEmpty || !delta.droppedTables.isEmpty {
            do { try encode(delta).write(to: json, options: .withoutOverwriting) }
            catch { try? fm.removeItem(at: swift); throw error }
        }
    }

    public static func readHistory(directory: URL) throws -> [MigrationFile] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        guard !names.contains("schema-history.json"), !names.contains("StoreMigrations.swift") else {
            throw failure("Old full-snapshot/catalog format is unsupported. Use ID.swift and optional ID.schema.json files.")
        }
        var numbered: [(id: String, number: String)] = []
        var seen = Set<String>()
        for name in names where name.hasSuffix(".swift") {
            let id = String(name.dropLast(6))
            let number = try migrationNumber(id)
            guard seen.insert(number).inserted else { throw failure("Duplicate migration number: \(number)") }
            numbered.append((id, number))
        }
        let ids = numbered.sorted { numberLess($0.number, $1.number) }.map(\.id)
        for name in names where name.hasSuffix(".schema.json") {
            guard ids.contains(String(name.dropLast(12))) else { throw failure("Snapshot \(name) has no matching Swift migration") }
        }
        var target = SchemaSnapshot.empty
        var result: [MigrationFile] = []
        for id in ids {
            let json = directory.appendingPathComponent(id + ".schema.json")
            let delta = FileManager.default.fileExists(atPath: json.path)
                ? try JSONDecoder().decode(SchemaDelta.self, from: Data(contentsOf: json)) : SchemaDelta()
            target = try delta.applying(to: target)
            let source = try Data(contentsOf: directory.appendingPathComponent(id + ".swift"))
            var bytes = Data(id.utf8)
            bytes.append(0)
            bytes.append(try target.json())
            bytes.append(0)
            bytes.append(source)
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            result.append(MigrationFile(id: id, target: target, checksum: hash))
        }
        return result
    }

    /// Checks the reconstructed full schema and returns catalog source for the current compilation.
    public static func check(target: SchemaSnapshot, directory: URL) throws -> Data {
        let target = try target.canonicalized()
        let history = try readHistory(directory: directory)
        guard let latest = history.last else { throw failure("No migrations. Run swiftstore migration add 001_initial --target <target-directory>, or add a migration manually.") }
        guard try latest.target.isEquivalent(to: target) else {
            let delta = SchemaDelta.between(latest.target, target)
            throw failure("Entity schema changed. Add a migration. Changed tables: \(delta.tables.map(\.name)); removed tables: \(delta.droppedTables)")
        }
        var lines = ["// Generated during build. Do not commit this file.", "import Foundation", "import SwiftStoreCore", "",
                     "public enum StoreMigrations {", "    public static func all() throws -> [StoreMigration] {", "        ["]
        for entry in history {
            let json = String(decoding: try entry.target.json(), as: UTF8.self)
            lines += ["            StoreMigration(id: \(String(reflecting: entry.id)), checksum: \(String(reflecting: entry.checksum)),",
                      "                target: try SchemaSnapshot.decode(Data(\(String(reflecting: json)).utf8)),",
                      "                up: \(entry.symbol).up),"]
        }
        lines += ["        ]", "    }", "}", ""]
        return Data(lines.joined(separator: "\n").utf8)
    }

    public static func check(root: URL, sources: [URL]? = nil, output: URL? = nil) throws {
        let data = try check(target: currentSchema(at: root, sources: sources), directory: root.appendingPathComponent("Migrations"))
        if let output { try data.write(to: output, options: .atomic) }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func migrationNumber(_ id: String) throws -> String {
        guard let separator = id.firstIndex(of: "_"),
              !id.contains("/"), !id.contains("\0") else {
            throw failure("Migration IDs must use <digits>_<description> and be valid filenames")
        }
        let prefix = id[..<separator]
        guard !prefix.isEmpty, prefix.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            throw failure("Migration number before the first underscore must contain only ASCII digits")
        }
        let normalized = prefix.drop { $0 == "0" }
        return normalized.isEmpty ? "0" : String(normalized)
    }

    // Compare arbitrary-length numbers without integer overflow.
    private static func numberLess(_ lhs: String, _ rhs: String) -> Bool {
        lhs.count == rhs.count ? lhs < rhs : lhs.count < rhs.count
    }
    private static func failure(_ message: String) -> VersionedMigrationError { .invalidHistory(message) }
}
