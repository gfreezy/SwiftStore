import Foundation
import Testing
import SwiftStoreCore

@Suite("Bundled schema resources")
struct SchemaResourceTests {
    @Test("Same-named resources stay isolated and missing paths never fall back")
    func bundleLookup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data("<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>test.schemas</string><key>CFBundlePackageType</key><string>BNDL</string></dict></plist>".utf8)
            .write(to: root.appendingPathComponent("Contents/Info.plist"))
        let bundle = try #require(Bundle(url: root))
        for name in ["Main", "Dictionary"] {
            let directory = resources.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let delta = SchemaDelta(tables: [TableSchema(name: name.lowercased(), columns: [ColumnSchema(name: "id", type: "INTEGER")])])
            try delta.json().write(to: directory.appendingPathComponent("001_initial.schema.json"))
            #expect(try SchemaDelta.load("001_initial.schema.json", in: bundle, subdirectory: name) == delta)
        }
        for subdirectory: String? in [nil, "Missing", "../Main", "/Main"] {
            #expect(throws: VersionedMigrationError.self) {
                try SchemaDelta.load("001_initial.schema.json", in: bundle, subdirectory: subdirectory)
            }
        }
        #expect(throws: VersionedMigrationError.self) {
            try SchemaDelta.load("Main/001_initial.schema.json", in: bundle)
        }
        try Data("invalid JSON".utf8).write(to: resources.appendingPathComponent("bad.schema.json"))
        #expect(throws: VersionedMigrationError.self) { try SchemaDelta.load("bad.schema.json", in: bundle) }
        try SchemaDelta(droppedTables: ["main"]).json().write(to: resources.appendingPathComponent("002_drop.schema.json"))
        var catalog = StoreMigrationCatalog()
        try catalog.append(id: "001_initial", delta: SchemaDelta.load("001_initial.schema.json", in: bundle, subdirectory: "Main")) { _ in }
        try catalog.append(id: "002_drop", delta: SchemaDelta.load("002_drop.schema.json", in: bundle)) { _ in }
        try catalog.append(id: "003_data") { _ in }
        #expect(catalog.migrations[0].target.tables.count == 1)
        #expect(catalog.migrations[1].target == .empty)
        #expect(catalog.migrations[2].target == .empty)
    }
}
