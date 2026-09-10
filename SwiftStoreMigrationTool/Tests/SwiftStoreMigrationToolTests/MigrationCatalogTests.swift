import Foundation
import Testing
import SwiftStoreCore
import SwiftStoreMigrationTool

@Suite("CLI-owned migration catalogs")
struct MigrationCatalogTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent(".git"))
        return root
    }

    private var schema: SchemaSnapshot {
        SchemaSnapshot(tables: [TableSchema(name: "items", columns: [ColumnSchema(name: "id", type: "INTEGER")])])
    }

    @Test("Separate schema directory supports resources, explicit empty deltas and orphan checks")
    func separateResources() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let migrations = root.appendingPathComponent("Migrations")
        let schemas = root.appendingPathComponent("Resources/MainSchemas")
        try MigrationTool.generate(id: "001_initial", target: schema, directory: migrations, schemas: schemas)
        #expect(!FileManager.default.fileExists(atPath: migrations.appendingPathComponent("001_initial.schema.json").path))
        #expect(try SchemaDelta.load(from: schemas.appendingPathComponent("001_initial.schema.json")).tables == schema.tables)
        try MigrationTool.generate(id: "002_data", target: schema, directory: migrations, schemas: schemas)
        try SchemaDelta().json().write(to: schemas.appendingPathComponent("002_data.schema.json"))
        #expect(throws: VersionedMigrationError.self) { try MigrationTool.check(target: schema, directory: migrations, schemas: schemas) }
        try MigrationTool.writeCatalog(directory: migrations, schemas: schemas)
        _ = try MigrationTool.check(target: schema, directory: migrations, schemas: schemas)
        let catalog = try String(contentsOf: MigrationTool.catalogFile(directory: migrations), encoding: .utf8)
        #expect(catalog.contains("002_data.schema.json"))
        #expect(!catalog.contains("SchemaDelta.decode"))
        try FileManager.default.removeItem(at: migrations)
        #expect(throws: VersionedMigrationError.self) { try MigrationTool.readHistory(directory: migrations, schemas: schemas) }
    }

    @Test("Add creates a compiled source catalog and preserves manual edits when appending")
    func editable() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try MigrationTool.generate(id: "001_initial", target: schema, directory: root)
        let file = MigrationTool.catalogFile(directory: root)
        var source = try String(contentsOf: file, encoding: .utf8)
        source = "// My project comment\n" + source.replacingOccurrences(of: "        return catalog.migrations",
            with: "        // Preserve this comment, too.\n        return catalog.migrations")
        source += "\nprivate func helper() -> String { \"untouched\" }\n"
        try source.write(to: file, atomically: true, encoding: .utf8)
        _ = try MigrationTool.check(target: schema, directory: root)
        #expect(try String(contentsOf: file, encoding: .utf8) == source)
        try MigrationTool.generate(id: "002_data", target: schema, directory: root)
        let appended = try String(contentsOf: file, encoding: .utf8)
        #expect(appended.hasPrefix("// My project comment\n"))
        #expect(appended.contains("// Preserve this comment, too."))
        #expect(appended.contains("private func helper() -> String { \"untouched\" }"))
        #expect(appended.contains("up: Migration_002.up"))
        #expect(try MigrationTool.readHistory(directory: root).count == 2)
        _ = try MigrationTool.check(target: schema, directory: root)
    }

    @Test("Checks detect stale catalog resource paths, missing IDs, order changes and wrong up methods")
    func staleMetadata() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try MigrationTool.generate(id: "001_initial", target: schema, directory: root)
        try MigrationTool.generate(id: "002_data", target: schema, directory: root)
        let file = MigrationTool.catalogFile(directory: root)
        let original = try String(contentsOf: file, encoding: .utf8)
        let edits = [
            original.replacingOccurrences(of: "001_initial.schema.json", with: "wrong.schema.json"),
            original.replacingOccurrences(of: "id: \"001_initial\"", with: "id: \"002_data\""),
            original.replacingOccurrences(of: "up: Migration_002.up", with: "up: Migration_001.up"),
            original.replacingOccurrences(of: "try catalog.append(id: \"002_data\",\n            up: Migration_002.up)", with: "")
        ]
        for edit in edits {
            try edit.write(to: file, atomically: true, encoding: .utf8)
            #expect(throws: VersionedMigrationError.self) { try MigrationTool.check(target: schema, directory: root) }
            #expect(try String(contentsOf: file, encoding: .utf8) == edit)
        }
        try MigrationTool.writeCatalog(directory: root)
        #expect(try String(contentsOf: file, encoding: .utf8) == original)
        _ = try MigrationTool.check(target: schema, directory: root)
    }

    @Test("Missing catalogs are never created by check")
    func readOnlyCheck() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try MigrationTool.generate(id: "001_initial", target: schema, directory: root)
        let file = MigrationTool.catalogFile(directory: root)
        try FileManager.default.removeItem(at: file)
        #expect(throws: VersionedMigrationError.self) { try MigrationTool.check(target: schema, directory: root) }
        #expect(!FileManager.default.fileExists(atPath: file.path))
        try MigrationTool.writeCatalog(directory: root)
        _ = try MigrationTool.check(target: schema, directory: root)
    }

    @Test("An unsupported manual catalog is preserved and add leaves no partial migration")
    func atomicAdd() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try MigrationTool.generate(id: "001_initial", target: schema, directory: root)
        let file = MigrationTool.catalogFile(directory: root)
        let edited = "enum StoreMigrations { static func all() { /* manual implementation */ } }"
        try edited.write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: VersionedMigrationError.self) {
            try MigrationTool.generate(id: "002_data", target: schema, directory: root)
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("002_data.swift").path))
        #expect(try String(contentsOf: file, encoding: .utf8) == edited)
    }

    @Test("The default namespace preserves a single database's files, types and catalog")
    func defaultNamespaceUpgrade() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Main", "Dictionary"] {
            let path = root.appendingPathComponent(name + "/Models")
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            try "@Entity(readonly: true) struct \(name)Item { var id: Int }".write(
                to: path.appendingPathComponent(name + "Item.swift"), atomically: true, encoding: .utf8)
        }
        let main = root.appendingPathComponent("Main")
        let legacy = try MigrationProject.load(root: main)
        try legacy.generate(id: "001_initial")
        let directory = main.appendingPathComponent("Migrations")
        let original = try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
        for namespace in ["", #", "namespace":"default""#] {
            let config = """
            {"formatVersion":1,"targets":{"App":{"databases":[
              {"id":"main"\(namespace),"sources":["Main/Models"],"migrations":"Main/Migrations"},
              {"id":"dictionary","namespace":"DictionaryStore","sources":["Dictionary/Models"],"migrations":"Dictionary/Migrations"}
            ]}}}
            """
            try config.write(to: root.appendingPathComponent("swiftstore.json"), atomically: true, encoding: .utf8)
            let project = try MigrationProject.load(root: root)
            #expect(project.databases[0].namespace == nil)
            if !FileManager.default.fileExists(atPath: root.appendingPathComponent("Dictionary/Migrations").path) {
                try project.generate(id: "001_initial", databaseID: "dictionary")
            }
            _ = try project.check()
            for (name, data) in original { #expect(try Data(contentsOf: directory.appendingPathComponent(name)) == data) }
            let dictionary = root.appendingPathComponent("Dictionary/Migrations/DictionaryStore_001_initial.swift")
            #expect(try String(contentsOf: dictionary, encoding: .utf8).contains("enum DictionaryStoreMigration_001"))
            #expect(try MigrationTool.readHistory(directory: directory).map(\.id) == ["001_initial"])
        }
    }

    @Test("A target can have only one default namespace")
    func duplicateDefault() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = #"{"formatVersion":1,"targets":{"App":{"databases":[{"id":"a","sources":["A"],"migrations":"A/Migrations"},{"id":"b","namespace":"default","sources":["B"],"migrations":"B/Migrations"}]}}}"#
        let file = root.appendingPathComponent("swiftstore.json")
        try config.write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: ConfigurationError.self) { try MigrationConfiguration.read(at: file) }
    }
}
