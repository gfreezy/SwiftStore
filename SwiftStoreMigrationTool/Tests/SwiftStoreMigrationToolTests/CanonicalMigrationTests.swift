import Foundation
import Testing
import SwiftStoreCore
@testable import SwiftStoreMigrationTool

@Suite("Canonical migration comparison")
struct CanonicalMigrationTests {
    @Test("Equivalent schema encodings pass check and produce the same catalog")
    func canonicalCatalog() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("001_initial.swift")
        try "import SwiftStoreCore\n".write(to: source, atomically: true, encoding: .utf8)
        let file = directory.appendingPathComponent("001_initial.schema.json")
        let target = SchemaSnapshot(tables: [TableSchema(name: "legacy", columns: [
            ColumnSchema(name: "id", type: "BLOB", isPrimaryKey: true)
        ])])
        var catalogs: [Data] = []
        for extra in ["", #", "indexes":null,"triggers":null,"foreignKeys":null,"fullTextIndexes":null"#,
                      #", "indexes":[],"triggers":[],"foreignKeys":[],"fullTextIndexes":[]"#] {
            let json = "{\"tables\":[{\"name\":\"legacy\",\"columns\":[{\"name\":\"id\",\"type\":\"BLOB\",\"isPrimaryKey\":true}]\(extra)}]}"
            try json.write(to: file, atomically: true, encoding: .utf8)
            try MigrationTool.writeCatalog(directory: directory)
            catalogs.append(try MigrationTool.check(target: target, directory: directory))
        }
        #expect(Set(catalogs).count == 1)
        try "import SwiftStoreCore\n// changed\n".write(to: source, atomically: true, encoding: .utf8)
        #expect(try MigrationTool.check(target: target, directory: directory) == catalogs[0])
    }
}
