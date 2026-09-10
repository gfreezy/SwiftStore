import Foundation
import Testing
import SwiftStoreCore
import SwiftStoreMigrationTool

@Suite("Namespaced schema resources")
struct NamespaceSchemaResourceTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func schema(_ table: String) -> SchemaSnapshot {
        SchemaSnapshot(tables: [TableSchema(name: table, columns: [ColumnSchema(name: "id", type: "INTEGER")])])
    }

    @Test("Two databases with identical IDs load distinct schemas from a flat bundle")
    func flatBundle() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundleURL = root.appendingPathComponent("Schemas.bundle")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "test.schemas", "CFBundlePackageType": "BNDL"],
            format: .xml, options: 0).write(to: bundleURL.appendingPathComponent("Info.plist"))
        let bundle = try #require(Bundle(url: bundleURL))
        let resources = try #require(bundle.resourceURL)
        for (namespace, table) in [("MainStore", "books"), ("DictionaryStore", "words")] {
            let directory = root.appendingPathComponent(namespace)
            let schemas = root.appendingPathComponent(namespace + "Schemas")
            let target = schema(table)
            try MigrationTool.generate(id: "001_initial", target: target, directory: directory, namespace: namespace, schemas: schemas)
            let filename = namespace + "_001_initial.schema.json"
            try FileManager.default.copyItem(at: schemas.appendingPathComponent(filename), to: resources.appendingPathComponent(filename))
            let history = try MigrationTool.readHistory(directory: directory, namespace: namespace, schemas: schemas)
            #expect(history.map(\.id) == ["001_initial"])
            #expect(history.first?.schemaFilename == filename)
            let catalog = String(decoding: try MigrationTool.check(target: target, directory: directory, namespace: namespace, schemas: schemas), as: UTF8.self)
            #expect(catalog.contains("SchemaDelta.load(\"\(filename)\""))
            #expect(try SchemaDelta.load(filename, in: bundle).tables == target.tables)
        }
        #expect(throws: VersionedMigrationError.self) { try SchemaDelta.load("001_initial.schema.json", in: bundle) }
    }

    @Test("Unprefixed, foreign namespace and orphan resources are rejected")
    func invalidNames() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = schema("books")
        try MigrationTool.generate(id: "001_initial", target: target, directory: root, namespace: "MainStore")
        let prefixed = root.appendingPathComponent("MainStore_001_initial.schema.json")
        for name in ["001_initial.schema.json", "DictionaryStore_001_initial.schema.json", "MainStore_999_orphan.schema.json"] {
            let invalid = root.appendingPathComponent(name)
            try FileManager.default.moveItem(at: prefixed, to: invalid)
            #expect(throws: VersionedMigrationError.self) { try MigrationTool.readHistory(directory: root, namespace: "MainStore") }
            #expect(throws: VersionedMigrationError.self) { try MigrationTool.writeCatalog(directory: root, namespace: "MainStore") }
            try FileManager.default.moveItem(at: invalid, to: prefixed)
        }
        // Old and new names cannot silently coexist either.
        let duplicate = root.appendingPathComponent("001_initial.schema.json")
        try FileManager.default.copyItem(at: prefixed, to: duplicate)
        #expect(throws: VersionedMigrationError.self) { try MigrationTool.check(target: target, directory: root, namespace: "MainStore") }
    }

    @Test("Catalog regeneration updates resource names without changing IDs or JSON bytes")
    func staleCatalog() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = schema("books")
        try MigrationTool.generate(id: "001_initial", target: target, directory: root, namespace: "MainStore")
        try MigrationTool.generate(id: "002_data", target: target, directory: root, namespace: "MainStore")
        let json = root.appendingPathComponent("MainStore_001_initial.schema.json")
        let original = try Data(contentsOf: json)
        let file = MigrationTool.catalogFile(directory: root, namespace: "MainStore")
        let catalog = try String(contentsOf: file, encoding: .utf8)
        try catalog.replacingOccurrences(of: "MainStore_001_initial.schema.json", with: "001_initial.schema.json")
            .write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: VersionedMigrationError.self) { try MigrationTool.check(target: target, directory: root, namespace: "MainStore") }
        try MigrationTool.writeCatalog(directory: root, namespace: "MainStore")
        _ = try MigrationTool.check(target: target, directory: root, namespace: "MainStore")
        #expect(try String(contentsOf: file, encoding: .utf8) == catalog)
        let history = try MigrationTool.readHistory(directory: root, namespace: "MainStore")
        #expect(history.map(\.id) == ["001_initial", "002_data"])
        #expect(history.map(\.hasSnapshot) == [true, false])
        #expect(try Data(contentsOf: json) == original)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("MainStore_002_data.schema.json").path))
    }
}
