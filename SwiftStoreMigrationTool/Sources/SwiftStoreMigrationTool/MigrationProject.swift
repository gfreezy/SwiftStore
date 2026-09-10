import Foundation
import SwiftStoreCore

/// Resolves database ownership once for both CLI generation and build-time checks.
public struct MigrationProject {
    public struct Database {
        public let targetName: String?
        public let id: String
        public let namespace: String?
        public let sources: [URL]
        public let migrations: URL
        public let schemas: URL?

        public var label: String {
            targetName.map { "[target: \($0), database: \(id)]" } ?? "[database: \(id)]"
        }
    }

    public let databases: [Database]

    public static func load(root: URL, targetName: String? = nil, sources: [URL]? = nil) throws -> MigrationProject {
        guard let file = MigrationConfiguration.find(from: root) else {
            return MigrationProject(databases: [Database(targetName: targetName, id: "default", namespace: nil,
                sources: try sources ?? MigrationTool.sourceFiles(at: root), migrations: root.appendingPathComponent("Migrations"), schemas: nil)])
        }
        let config = try MigrationConfiguration.read(at: file)
        let projectRoot = file.deletingLastPathComponent()
        let names: [String]
        if let targetName {
            guard config.targets[targetName] != nil else { throw ConfigurationError("Unknown configured target: \(targetName)") }
            names = [targetName]
        } else {
            guard sources == nil || config.targets.count == 1 else {
                throw ConfigurationError("--sources-file requires --target-name when multiple targets are configured")
            }
            names = config.targets.keys.sorted()
        }
        var result: [Database] = []
        // A standalone Xcode invocation cannot infer Compile Sources. Exclude files explicitly
        // assigned to other configured targets; plugin invocations always use exact membership.
        let allSourceRoots = try config.targets.mapValues { target in
            try target.databases.flatMap { database in
                try database.sources.map { try MigrationConfiguration.resolve($0, relativeTo: projectRoot) }
            }
        }
        for name in names {
            let target = config.targets[name]!
            let sourceRoot = try sources == nil ? ProjectDiscovery.sourceDirectory(targetName: name, projectRoot: projectRoot) : nil
            let exactMembership = sources != nil || sourceRoot != nil
            var inventory = try sources ?? MigrationTool.sourceFiles(at: sourceRoot ?? projectRoot)
            inventory = inventory.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
            if !exactMembership {
                let otherRoots = allSourceRoots.filter { $0.key != name }.values.flatMap { $0 }
                let ownRoots = allSourceRoots[name]!
                inventory = inventory.filter { file in
                    ownRoots.contains { MigrationConfiguration.contains($0, file) } ||
                        !otherRoots.contains { MigrationConfiguration.contains($0, file) }
                }
            }
            let inventorySet = Set(inventory)
            var ownership: [URL: [String]] = [:]
            var targetDatabases: [Database] = []
            for database in target.databases {
                let label = "[target: \(name), database: \(database.id)]"
                var selected = Set<URL>()
                for path in database.sources {
                    let url = try MigrationConfiguration.resolve(path, relativeTo: projectRoot)
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                        throw ConfigurationError("\(label) Source path does not exist: \(path)")
                    }
                    guard isDirectory.boolValue || url.pathExtension == "swift" else {
                        throw ConfigurationError("\(label) Source paths must be directories or Swift files: \(path)")
                    }
                    let files = try isDirectory.boolValue ? MigrationTool.sourceFiles(at: url) : [url]
                    for candidate in files {
                        let candidate = candidate.standardizedFileURL.resolvingSymlinksInPath()
                        if !inventorySet.contains(candidate) {
                            if try EntitySourceSchema.containsEntity(files: [candidate]) {
                                throw ConfigurationError("\(label) Entity file is not in the selected target's sources: \(candidate.path)")
                            }
                            continue
                        }
                        selected.insert(candidate)
                    }
                }
                for file in selected { ownership[file, default: []].append(database.id) }
                let migrations = try MigrationConfiguration.resolve(database.migrations, relativeTo: projectRoot)
                if sources != nil, FileManager.default.fileExists(atPath: migrations.path) {
                    let files = try FileManager.default.contentsOfDirectory(at: migrations, includingPropertiesForKeys: nil)
                    for file in files where file.pathExtension == "swift" {
                        guard inventorySet.contains(file.standardizedFileURL.resolvingSymlinksInPath()) else {
                            throw ConfigurationError("\(label) Migration file is not in the selected target's sources: \(file.path)")
                        }
                    }
                }
                targetDatabases.append(Database(targetName: name, id: database.id, namespace: database.namespace,
                    sources: selected.sorted { $0.path < $1.path }, migrations: migrations,
                    schemas: try database.schemas.map { try MigrationConfiguration.resolve($0, relativeTo: projectRoot) }))
            }
            for file in inventory.sorted(by: { $0.path < $1.path }) where try EntitySourceSchema.containsEntity(files: [file]) {
                let owners = ownership[file] ?? []
                guard owners.count == 1 else {
                    throw ConfigurationError("[target: \(name)] Entity file \(file.path) must belong to exactly one database; matched: \(owners)")
                }
            }
            result += targetDatabases
        }
        return MigrationProject(databases: result)
    }

    public func generate(id: String, databaseID: String? = nil) throws {
        let selected = try select(databaseID)
        guard selected.count == 1, let database = selected.first else {
            throw ConfigurationError("Select one database with --database and, if needed, --target-name. Available: \(databases.map(\.label).joined(separator: ", "))")
        }
        do {
            try MigrationTool.generate(id: id, target: MigrationTool.currentSchema(at: database.migrations, sources: database.sources),
                directory: database.migrations, namespace: database.namespace, schemas: database.schemas)
        } catch { throw ConfigurationError("\(database.label) \(error)") }
    }

    /// Without a selector, check every configured database, without changing application files.
    @discardableResult
    public func check(databaseID: String? = nil) throws -> Data {
        let selected = try select(databaseID)
        var catalogs: [String] = []
        var errors: [String] = []
        for database in selected {
            do {
                let data = try MigrationTool.check(target: MigrationTool.currentSchema(at: database.migrations, sources: database.sources),
                    directory: database.migrations, namespace: database.namespace, schemas: database.schemas)
                catalogs.append(String(decoding: data, as: UTF8.self))
            } catch {
                errors.append("\(database.label) \(error)\nRun: swiftstore migration add <ID> --database \(database.id)" +
                    (database.targetName.map { " --target-name \($0)" } ?? ""))
            }
        }
        guard errors.isEmpty else { throw ConfigurationError(errors.joined(separator: "\n\n")) }
        let data = Data(catalogs.joined(separator: "\n").utf8)
        return data
    }

    /// Explicit CLI action: write or replace catalogs, separately from read-only checks.
    public func writeCatalogs(databaseID: String? = nil) throws {
        for database in try select(databaseID) {
            do { try MigrationTool.writeCatalog(directory: database.migrations, namespace: database.namespace, schemas: database.schemas) }
            catch { throw ConfigurationError("\(database.label) \(error)") }
        }
    }

    private func select(_ id: String?) throws -> [Database] {
        guard let id else { return databases }
        let selected = databases.filter { $0.id == id }
        guard !selected.isEmpty else { throw ConfigurationError("Unknown database: \(id)") }
        return selected
    }
}
