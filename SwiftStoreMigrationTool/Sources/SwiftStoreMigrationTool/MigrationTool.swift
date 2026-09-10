import Foundation
import SwiftStoreCore

public struct MigrationFile {
    public let id: String
    public let target: SchemaSnapshot
    public let delta: SchemaDelta
    public let namespace: String?
    public let hasSnapshot: Bool
    public var symbol: String { (namespace ?? "") + "Migration_" + id.prefix { $0 != "_" } }
}

/// CLI generation writes editable Swift files. Build checks never modify application source.
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
    public static func generate(id: String, target: SchemaSnapshot, directory: URL, namespace: String? = nil, schemas: URL? = nil) throws {
        let number = try migrationNumber(id)
        let target = try target.canonicalized()
        let history = try readHistory(directory: directory, namespace: namespace, schemas: schemas)
        if history.contains(where: { (try? migrationNumber($0.id)) == number }) {
            throw failure("Duplicate migration number: \(number)")
        }
        if let last = history.last, !numberLess(try migrationNumber(last.id), number) {
            throw failure("New migration number must be greater than \(last.id)")
        }
        let previous = history.last?.target ?? .empty
        let delta = SchemaDelta.between(previous, target)
        let source = try MigrationSourceGenerator.source(symbol: (namespace ?? "") + "Migration_" + id.prefix { $0 != "_" }, from: previous, to: target)
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let swift = directory.appendingPathComponent((namespace.map { $0 + "_" } ?? "") + id + ".swift")
        let json = (schemas ?? directory).appendingPathComponent(id + ".schema.json")
        guard !fm.fileExists(atPath: swift.path), !fm.fileExists(atPath: json.path) else { throw failure("Refusing to overwrite migration \(id)") }
        let catalog = catalogFile(directory: directory, namespace: namespace)
        let entry = MigrationFile(id: id, target: target, delta: delta, namespace: namespace,
                                  hasSnapshot: !delta.tables.isEmpty || !delta.droppedTables.isEmpty)
        let catalogSource: String
        if fm.fileExists(atPath: catalog.path) {
            catalogSource = try MigrationCatalogSource.appending(entry, to: String(contentsOf: catalog, encoding: .utf8),
                history: history, namespace: namespace)
        } else {
            catalogSource = try MigrationCatalogSource.render(history: history + [entry], namespace: namespace)
        }
        // Prepare the catalog first so malformed manual edits do not leave a partial new migration.
        try Data(source.utf8).write(to: swift, options: .withoutOverwriting)
        do {
            if !delta.tables.isEmpty || !delta.droppedTables.isEmpty {
                try fm.createDirectory(at: json.deletingLastPathComponent(), withIntermediateDirectories: true)
                try delta.json().write(to: json, options: .withoutOverwriting)
            }
            try Data(catalogSource.utf8).write(to: catalog, options: .atomic)
        } catch {
            try? fm.removeItem(at: swift)
            if fm.fileExists(atPath: json.path) { try? fm.removeItem(at: json) }
            throw error
        }
    }

    public static func readHistory(directory: URL, namespace: String? = nil, schemas: URL? = nil) throws -> [MigrationFile] {
        let names = FileManager.default.fileExists(atPath: directory.path)
            ? try FileManager.default.contentsOfDirectory(atPath: directory.path) : []
        guard !names.contains("schema-history.json") else {
            throw failure("Old full-snapshot/catalog format is unsupported. Use ID.swift and optional ID.schema.json files.")
        }
        var numbered: [(id: String, number: String)] = []
        var seen = Set<String>()
        for name in names where name.hasSuffix(".swift") && name != "StoreMigrations.swift" &&
            name != catalogFile(directory: directory, namespace: namespace).lastPathComponent {
            let stem = String(name.dropLast(6))
            let id: String
            if let namespace {
                let prefix = namespace + "_"
                guard stem.hasPrefix(prefix) else {
                    throw failure("Configured Swift migration filenames must start with \(prefix): \(name)")
                }
                id = String(stem.dropFirst(prefix.count))
            } else { id = stem }
            let number = try migrationNumber(id)
            guard seen.insert(number).inserted else { throw failure("Duplicate migration number: \(number)") }
            numbered.append((id, number))
        }
        let ids = numbered.sorted { numberLess($0.number, $1.number) }.map(\.id)
        let schemaNames = try schemas.map { url in
            FileManager.default.fileExists(atPath: url.path) ? try FileManager.default.contentsOfDirectory(atPath: url.path) : []
        } ?? names
        for name in schemaNames where name.hasSuffix(".schema.json") {
            guard ids.contains(String(name.dropLast(12))) else { throw failure("Snapshot \(name) has no matching Swift migration") }
        }
        var target = SchemaSnapshot.empty
        var result: [MigrationFile] = []
        for id in ids {
            let json = (schemas ?? directory).appendingPathComponent(id + ".schema.json")
            let delta = FileManager.default.fileExists(atPath: json.path)
                ? try JSONDecoder().decode(SchemaDelta.self, from: Data(contentsOf: json)) : SchemaDelta()
            target = try delta.applying(to: target)
            result.append(MigrationFile(id: id, target: target, delta: delta, namespace: namespace,
                                        hasSnapshot: FileManager.default.fileExists(atPath: json.path)))
        }
        return result
    }

    /// Checks the reconstructed schema and the checked-in catalog without changing either.
    public static func check(target: SchemaSnapshot, directory: URL, namespace: String? = nil, schemas: URL? = nil) throws -> Data {
        let target = try target.canonicalized()
        let history = try readHistory(directory: directory, namespace: namespace, schemas: schemas)
        guard let latest = history.last else { throw failure("No migrations. Run swiftstore migration add 001_initial --target <target-directory>, or add a migration manually.") }
        guard try latest.target.isEquivalent(to: target) else {
            let delta = SchemaDelta.between(latest.target, target)
            throw failure("Entity schema changed. Add a migration. Changed tables: \(delta.tables.map(\.name)); removed tables: \(delta.droppedTables)")
        }
        let file = catalogFile(directory: directory, namespace: namespace)
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw failure("Missing \(file.lastPathComponent). Run swiftstore migration catalog")
        }
        try MigrationCatalogSource.validate(String(contentsOf: file, encoding: .utf8), history: history, namespace: namespace)
        return try Data(MigrationCatalogSource.render(history: history, namespace: namespace).utf8)
    }

    public static func catalogFile(directory: URL, namespace: String? = nil) -> URL {
        directory.appendingPathComponent(MigrationCatalogSource.name(namespace: namespace) + ".swift")
    }

    /// Explicitly regenerate a catalog after manual history edits. This replaces its contents.
    public static func writeCatalog(directory: URL, namespace: String? = nil, schemas: URL? = nil) throws {
        let history = try readHistory(directory: directory, namespace: namespace, schemas: schemas)
        guard !history.isEmpty else { throw failure("No migrations to register") }
        let source = try MigrationCatalogSource.render(history: history, namespace: namespace)
        try Data(source.utf8).write(to: catalogFile(directory: directory, namespace: namespace), options: .atomic)
    }

    public static func check(root: URL, sources: [URL]? = nil,
                             targetName: String? = nil, databaseID: String? = nil) throws {
        try MigrationProject.load(root: root, targetName: targetName, sources: sources)
            .check(databaseID: databaseID)
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
