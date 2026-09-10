import Foundation

/// Shared by the CLI and build plugin (the plugin compiles this file through a source symlink).
public struct MigrationConfiguration: Decodable {
    public struct Database: Decodable {
        public let id: String
        /// Missing or "default" keeps the existing unprefixed migration API.
        public let namespace: String?
        public let sources: [String]
        public let migrations: String
        public let schemas: String?

        private enum CodingKeys: String, CodingKey { case id, namespace, sources, migrations, schemas }

        public init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            let name = try values.decodeIfPresent(String.self, forKey: .namespace)
            namespace = name == "default" ? nil : name
            sources = try values.decode([String].self, forKey: .sources)
            migrations = try values.decode(String.self, forKey: .migrations)
            schemas = try values.decodeIfPresent(String.self, forKey: .schemas)
        }
    }

    public struct Target: Decodable {
        public let databases: [Database]
    }

    public let formatVersion: Int
    public let targets: [String: Target]

    public static func find(from directory: URL) -> URL? {
        var current = directory.standardizedFileURL.resolvingSymlinksInPath()
        while true {
            let file = current.appendingPathComponent("swiftstore.json")
            if FileManager.default.fileExists(atPath: file.path) { return file }
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(".git").path) { return nil }
            let parent = current.deletingLastPathComponent()
            if parent == current { return nil }
            current = parent
        }
    }

    public static func read(at file: URL) throws -> MigrationConfiguration {
        let config = try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
        guard config.formatVersion == 1, !config.targets.isEmpty else {
            throw ConfigurationError("swiftstore.json requires formatVersion 1 and at least one target")
        }
        let root = file.deletingLastPathComponent()
        for (name, target) in config.targets {
            guard !name.isEmpty, !target.databases.isEmpty else {
                throw ConfigurationError("Target names and database lists must not be empty")
            }
            var ids = Set<String>()
            var namespaces = Set<String>()
            var directories: [URL] = []
            for database in target.databases {
                guard !database.id.isEmpty, ids.insert(database.id).inserted,
                      database.namespace.map(validNamespace) ?? true, namespaces.insert(database.namespace ?? "default").inserted,
                      !database.sources.isEmpty else {
                    throw ConfigurationError("[target: \(name)] Database IDs and namespaces must be unique and nonempty; sources are required. Named namespaces must be ASCII Swift identifier prefixes; only one default namespace is allowed per target.")
                }
                let directory = try resolve(database.migrations, relativeTo: root)
                let schemaDirectory = try database.schemas.map { try resolve($0, relativeTo: root) }
                let locations = Array(Set([directory] + (schemaDirectory.map { [$0] } ?? [])))
                guard locations.allSatisfy({ location in
                    directories.allSatisfy { !contains($0, location) && !contains(location, $0) }
                }) else {
                    throw ConfigurationError("[target: \(name)] Migration and schema directories of different databases must not overlap")
                }
                directories += locations
                for path in database.sources { _ = try resolve(path, relativeTo: root) }
            }
        }
        return config
    }

    public static func resolve(_ path: String, relativeTo root: URL) throws -> URL {
        guard !path.isEmpty, !(path as NSString).isAbsolutePath else {
            throw ConfigurationError("Configuration paths must be nonempty and relative: \(path)")
        }
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let url = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard contains(root, url) else { throw ConfigurationError("Configuration path escapes the project: \(path)") }
        return url
    }

    public static func contains(_ directory: URL, _ file: URL) -> Bool {
        file.path == directory.path || file.path.hasPrefix(directory.path + "/")
    }

    private static func validNamespace(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        func start(_ byte: UInt8) -> Bool { byte == 95 || (65...90).contains(byte) || (97...122).contains(byte) }
        return bytes.first.map(start) == true && bytes.dropFirst().allSatisfy { start($0) || (48...57).contains($0) }
    }
}

public struct ConfigurationError: Error, CustomStringConvertible {
    public let description: String
    public init(_ message: String) { description = message }
}
