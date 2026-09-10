import Foundation

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

    /// Readable deterministic JSON. SQL strings are preserved byte-for-byte.
    public func json() throws -> Data {
        guard formatVersion == 1 else {
            throw VersionedMigrationError.invalidHistory("Unsupported schema delta format")
        }
        return try SchemaJSON.encode(SchemaDelta(tables: tables, droppedTables: droppedTables))
    }

    public static func decode(_ data: Data) throws -> SchemaDelta {
        try JSONDecoder().decode(Self.self, from: data)
    }

    /// Load one frozen delta from an application or SwiftPM resource bundle. Lookup is exact:
    /// a missing database subdirectory never falls back to another database's same-named file.
    public static func load(_ filename: String, in bundle: Bundle = .main,
                            subdirectory: String? = nil) throws -> SchemaDelta {
        guard let root = bundle.resourceURL else {
            throw VersionedMigrationError.invalidHistory("Bundle has no resource directory: \(bundle.bundlePath)")
        }
        guard !filename.isEmpty, !filename.contains("/"), filename != ".", filename != ".." else {
            throw VersionedMigrationError.invalidHistory("Invalid schema resource filename: \(filename)")
        }
        var directory = root
        if let subdirectory, !subdirectory.isEmpty {
            guard !(subdirectory as NSString).isAbsolutePath,
                  !subdirectory.split(separator: "/").contains("..") else {
                throw VersionedMigrationError.invalidHistory("Schema resource subdirectory must stay inside the bundle")
            }
            directory = directory.appendingPathComponent(subdirectory, isDirectory: true)
        }
        return try load(from: directory.appendingPathComponent(filename))
    }

    public static func load(from file: URL) throws -> SchemaDelta {
        do { return try decode(Data(contentsOf: file)) }
        catch { throw VersionedMigrationError.invalidHistory("Cannot load schema resource \(file.path): \(error)") }
    }

    public static func between(_ old: SchemaSnapshot, _ new: SchemaSnapshot) -> SchemaDelta {
        SchemaDelta(tables: new.tables.filter { !old.tables.contains($0) },
                    droppedTables: old.tables.map(\.name).filter { name in !new.tables.contains { $0.name == name } })
    }

    public func applying(to previous: SchemaSnapshot) throws -> SchemaSnapshot {
        try previous.validate()
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

