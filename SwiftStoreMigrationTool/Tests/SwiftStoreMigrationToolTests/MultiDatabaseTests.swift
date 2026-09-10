import Foundation
import Testing
import SwiftStoreCore
import SwiftStoreMigrationTool

@Suite("Multiple database migration projects")
struct MultiDatabaseTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent(".git"))
        for name in ["Main", "Dictionary"] {
            try write("Sources/App/\(name)/Models/Item.swift", in: root, text:
                "@Entity(tableName: \"items\", readonly: true) struct \(name)Item { var id: Int }")
        }
        try write("Package.swift", in: root, text:
            "import PackageDescription\nlet package = Package(name: \"Fixture\", targets: [.target(name: \"App\")])")
        try configure(root)
        return root
    }

    private func write(_ path: String, in root: URL, text: String) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    private func databases() -> [[String: Any]] {
        [("main", "Main"), ("dictionary", "Dictionary")].map { id, name in
            ["id": id, "namespace": name + "Store", "sources": ["Sources/App/\(name)/Models"],
             "migrations": "Sources/App/\(name)/Migrations"]
        }
    }

    private func configure(_ root: URL, databases: [[String: Any]]? = nil, version: Int = 1,
                           targets: [String: Any]? = nil) throws {
        let value: [String: Any] = ["formatVersion": version,
            "targets": targets ?? ["App": ["databases": databases ?? self.databases()]]]
        try JSONSerialization.data(withJSONObject: value).write(to: root.appendingPathComponent("swiftstore.json"))
    }

    private func generateBoth(_ root: URL) throws -> MigrationProject {
        let project = try MigrationProject.load(root: root)
        try project.generate(id: "001_initial", databaseID: "main")
        try project.generate(id: "001_initial", databaseID: "dictionary")
        return project
    }

    @Test("No configuration retains one database and the original symbols")
    func singleDefault() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("swiftstore.json"))
        let project = try MigrationProject.load(root: root.appendingPathComponent("Sources/App/Main"))
        #expect(project.databases.count == 1)
        try project.generate(id: "001_initial")
        let catalog = String(decoding: try project.check(), as: UTF8.self)
        #expect(catalog.contains("public enum StoreMigrations"))
        #expect(catalog.contains("up: Migration_001.up"))
    }

    @Test("Independent histories can share migration numbers and SQL table names")
    func independentHistories() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try generateBoth(root)
        #expect(project.databases.map(\.id) == ["main", "dictionary"])
        try MigrationTool.check(root: root)
        let catalog = String(decoding: try project.check(), as: UTF8.self)
        #expect(catalog.contains("public enum MainStoreMigrations"))
        #expect(catalog.contains("public enum DictionaryStoreMigrations"))
        #expect(catalog.contains("up: MainStoreMigration_001.up"))
        #expect(catalog.contains("up: DictionaryStoreMigration_001.up"))
        #expect(!catalog.contains("up: Migration_001.up"))
        try project.generate(id: "002_data", databaseID: "main")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/App/Dictionary/Migrations/DictionaryStore_002_data.swift").path))
        #expect(try MigrationTool.readHistory(directory: project.databases[0].migrations, namespace: "MainStore").count == 2)
        #expect(try MigrationTool.readHistory(directory: project.databases[1].migrations, namespace: "DictionaryStore").count == 1)
        let source = try String(contentsOf: project.databases[0].migrations.appendingPathComponent("MainStore_001_initial.swift"), encoding: .utf8)
        #expect(source.contains("enum MainStoreMigration_001"))
    }

    @Test("Add requires a selector; unknown selectors fail without creating files")
    func selectors() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try MigrationProject.load(root: root)
        #expect(throws: ConfigurationError.self) { try project.generate(id: "001_initial") }
        #expect(throws: ConfigurationError.self) { try project.generate(id: "001_initial", databaseID: "unknown") }
        #expect(throws: ConfigurationError.self) { try project.check(databaseID: "unknown") }
        #expect(throws: ConfigurationError.self) { try MigrationProject.load(root: root, targetName: "Unknown") }
        #expect(project.databases.allSatisfy { !FileManager.default.fileExists(atPath: $0.migrations.path) })
    }

    @Test("Default check reports every drift and never overwrites catalogs on failure")
    func checksAll() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try generateBoth(root)
        let output = MigrationTool.catalogFile(directory: project.databases[0].migrations, namespace: "MainStore")
        let original = try String(contentsOf: output, encoding: .utf8)
        for name in ["Main", "Dictionary"] {
            try write("Sources/App/\(name)/Models/Item.swift", in: root, text:
                "@Entity(tableName: \"items\", readonly: true) struct \(name)Item { var id: Int; var value: String? }")
        }
        do {
            try project.check()
            Issue.record("Expected both database errors")
        } catch {
            #expect(String(describing: error).contains("database: main"))
            #expect(String(describing: error).contains("database: dictionary"))
        }
        #expect(try String(contentsOf: output, encoding: .utf8) == original)
        try project.generate(id: "002_value", databaseID: "main")
        _ = try project.check(databaseID: "main")
        #expect(throws: ConfigurationError.self) { try project.check() }
    }

    @Test("Every Entity must belong to exactly one database")
    func ownership() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("Sources/App/Unassigned.swift", in: root, text: "@Entity(readonly: true) struct Unassigned { var id: Int }")
        #expect(throws: ConfigurationError.self) { try MigrationProject.load(root: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("Sources/App/Unassigned.swift"))
        var entries = databases()
        entries[0]["sources"] = ["Sources/App"]
        try configure(root, databases: entries)
        #expect(throws: ConfigurationError.self) { try MigrationProject.load(root: root) }
    }

    @Test("Exact plugin membership rejects excluded Entities and uncompiled migrations")
    func membership() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = try MigrationTool.sourceFiles(at: root.appendingPathComponent("Sources/App"))
        #expect(throws: ConfigurationError.self) {
            try MigrationProject.load(root: root, targetName: "App", sources: [files[0]])
        }
        _ = try generateBoth(root)
        #expect(throws: ConfigurationError.self) {
            try MigrationProject.load(root: root, targetName: "App", sources: files)
        }
        let all = try MigrationTool.sourceFiles(at: root.appendingPathComponent("Sources/App"))
        _ = try MigrationProject.load(root: root, targetName: "App", sources: all).check()
    }

    @Test("Bad configuration is rejected before generation")
    func validation() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for field in ["id", "namespace", "migrations"] {
            var entries = databases()
            entries[1][field] = entries[0][field]
            try configure(root, databases: entries)
            #expect(throws: ConfigurationError.self) { try MigrationProject.load(root: root) }
        }
        for namespace in ["", "1bad", "Bad.Name", "Bad\nCode"] {
            var entries = databases()
            entries[0]["namespace"] = namespace
            try configure(root, databases: entries)
            #expect(throws: ConfigurationError.self) { try MigrationProject.load(root: root) }
        }
        for path in ["../escape", "/tmp/absolute", ""] {
            var entries = databases()
            entries[0]["migrations"] = path
            try configure(root, databases: entries)
            #expect(throws: ConfigurationError.self) { try MigrationProject.load(root: root) }
        }
        var entries = databases()
        entries[1]["migrations"] = "Sources/App/Main/Migrations/Nested"
        try configure(root, databases: entries)
        #expect(throws: ConfigurationError.self) { try MigrationProject.load(root: root) }
        try configure(root, version: 2)
        #expect(throws: ConfigurationError.self) { try MigrationProject.load(root: root) }
    }

    @Test("Explicit files, empty schemas and configuration discovery from nested history work")
    func sourcePaths() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var entries = databases()
        entries[0]["sources"] = ["Sources/App/Main/Models/Item.swift"]
        try configure(root, databases: entries)
        let project = try generateBoth(root)
        #expect(MigrationConfiguration.find(from: project.databases[0].migrations)?.path == root.appendingPathComponent("swiftstore.json").path)
        try write("Sources/App/Main/Models/Item.swift", in: root, text: "// All managed tables removed")
        let empty = try MigrationProject.load(root: root)
        try empty.generate(id: "002_drop", databaseID: "main")
        let delta = try SchemaDelta.decode(Data(contentsOf: project.databases[0].migrations.appendingPathComponent("MainStore_002_drop.schema.json")))
        #expect(delta.droppedTables == ["items"])
        _ = try empty.check()
        entries[0]["sources"] = ["missing"]
        try configure(root, databases: entries)
        #expect(throws: ConfigurationError.self) { try MigrationProject.load(root: root) }
    }

    @Test("Default check includes all configured targets; plugin output is scoped to one target")
    func multipleTargets() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("Sources/Other/Models/Item.swift", in: root, text: "@Entity(readonly: true) struct OtherItem { var id: Int }")
        try write("Package.swift", in: root, text:
            "import PackageDescription\nlet package = Package(name: \"Fixture\", targets: [.target(name: \"App\"), .target(name: \"Other\")])")
        try configure(root, targets: ["App": ["databases": databases()], "Other": ["databases": [[
            "id": "main", "namespace": "MainStore", "sources": ["Sources/Other/Models"], "migrations": "Sources/Other/Migrations"
        ]]]])
        let app = try MigrationProject.load(root: root, targetName: "App")
        try app.generate(id: "001_initial", databaseID: "main")
        try app.generate(id: "001_initial", databaseID: "dictionary")
        let all = try MigrationProject.load(root: root)
        #expect(all.databases.count == 3)
        #expect(throws: ConfigurationError.self) { try all.generate(id: "001_initial", databaseID: "main") }
        #expect(throws: ConfigurationError.self) { try all.check() }
        try MigrationProject.load(root: root, targetName: "Other").generate(id: "001_initial")
        _ = try all.check()
        try all.writeCatalogs()
        let catalog = String(decoding: try app.check(), as: UTF8.self)
        #expect(!catalog.contains("other_item"))
    }
}
