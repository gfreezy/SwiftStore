import Foundation
import Testing
import SwiftStoreCore
import SwiftStoreMigrationTool

@Entity(readonly: true)
struct SourceParity {
    var id: Int
    var title: String = "guest"
    var amount: Double = 1.25
    var label: String?
    #Index<SourceParity>(\.title, unique: true)
}

@Embedded
struct SourceSettings { var theme: String = "dark" }

@Entity
struct SourceSyncParity {
    var id: UUIDV7 = UUIDV7()
    @Default("guest") let title: String
    var settings: SourceSettings = SourceSettings()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    #Index<SourceSyncParity>(\.settings.theme)
}

@Entity
struct SourceKeyParity {
    #SyncKey<SourceKeyParity>(\.email)
    var email: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

@Suite("Incremental migration tooling")
struct MigrationToolTests {
    private var people: TableSchema { TableSchema(name: "people", columns: [ColumnSchema(name: "id", type: "INTEGER", isPrimaryKey: true)]) }
    private var posts: TableSchema { TableSchema(name: "posts", columns: [ColumnSchema(name: "id", type: "INTEGER", isPrimaryKey: true)]) }
    private var changedPeople: TableSchema { TableSchema(name: "people", columns: people.columns + [ColumnSchema(name: "name", type: "TEXT", isNullable: true)]) }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Only changed tables are saved; unchanged tables survive reconstruction")
    func incremental() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let v1 = SchemaSnapshot(tables: [people, posts])
        let v2 = SchemaSnapshot(tables: [changedPeople, posts])
        try MigrationTool.generate(id: "001_initial", target: v1, directory: dir)
        try MigrationTool.generate(id: "002_name", target: v2, directory: dir)
        let delta = try JSONDecoder().decode(SchemaDelta.self, from: Data(contentsOf: dir.appendingPathComponent("002_name.schema.json")))
        #expect(delta.tables == [changedPeople])
        #expect(delta.droppedTables.isEmpty)
        #expect(try MigrationTool.readHistory(directory: dir).last?.target == v2)
        let catalog = try MigrationTool.check(target: v2, directory: dir)
        #expect(String(decoding: catalog, as: UTF8.self).contains("Migration_002.up"))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("StoreMigrations.swift").path))
    }

    @Test("Generated catalogs embed only deltas as readable raw JSON and omit data-only payloads")
    func catalogDeltas() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let v1 = SchemaSnapshot(tables: [people, posts])
        let v2 = SchemaSnapshot(tables: [changedPeople, posts])
        try MigrationTool.generate(id: "001_initial", target: v1, directory: dir)
        try MigrationTool.generate(id: "002_name", target: v2, directory: dir)
        try MigrationTool.generate(id: "003_data", target: v2, directory: dir)
        let final = SchemaSnapshot(tables: [changedPeople])
        try MigrationTool.generate(id: "004_drop", target: final, directory: dir)
        let source = String(decoding: try MigrationTool.check(target: final, directory: dir), as: UTF8.self)
        #expect(source.contains("var catalog = StoreMigrationCatalog()"))
        #expect(source.components(separatedBy: "try catalog.append").count - 1 == 4)
        #expect(source.components(separatedBy: "SchemaDelta.decode").count - 1 == 3)
        #expect(source.components(separatedBy: "\"name\": \"posts\"").count - 1 == 1)
        #expect(source.components(separatedBy: "\"name\": \"people\"").count - 1 == 2)
        #expect(source.contains("\"droppedTables\": [\n                    \"posts\""))
        #expect(!source.contains("SchemaSnapshot.decode"))
        #expect(!source.contains("checksum"))
        #expect(!source.contains(#"\"name\""#))
        #expect(source.contains("return catalog.migrations"))
        let json = try String(contentsOf: dir.appendingPathComponent("002_name.schema.json"), encoding: .utf8)
        #expect(json.contains("\"indexes\": []"))
        #expect(!json.contains("\" :"))
    }

    @Test("Raw JSON delimiters cannot be closed or interpolated by SQL strings")
    func catalogEscaping() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = SchemaSnapshot(tables: [TableSchema(name: "sample", columns: [
            ColumnSchema(name: "value", type: "TEXT", defaultValue: ##"'"# \#(unsafe)  中文 []'"##)
        ])])
        try MigrationTool.generate(id: "001_initial", target: target, directory: dir)
        let source = String(decoding: try MigrationTool.check(target: target, directory: dir), as: UTF8.self)
        #expect(source.contains("Data(##\"\"\""))
        #expect(source.contains("\"\"\"##.utf8)"))
    }

    @Test("Data-only migration needs no snapshot or checksum")
    func manualDataOnly() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = SchemaSnapshot(tables: [people])
        try MigrationTool.generate(id: "001_step", target: target, directory: dir)
        try MigrationTool.generate(id: "002_step", target: target, directory: dir)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("002_step.schema.json").path))
        let before = try MigrationTool.readHistory(directory: dir)
        let file = dir.appendingPathComponent("002_step.swift")
        let original = try String(contentsOf: file, encoding: .utf8)
        try (original + "\n// Manual data transformation\n").write(to: file, atomically: true, encoding: .utf8)
        _ = try MigrationTool.check(target: target, directory: dir)
        let after = try MigrationTool.readHistory(directory: dir)
        #expect(before[0].target == after[0].target)
        #expect(before[1].target == after[1].target)
    }

    @Test("Deletion is explicit and a rename preserves unrelated tables")
    func removal() throws {
        let previous = SchemaSnapshot(tables: [people, posts])
        let target = SchemaSnapshot(tables: [posts])
        let delta = SchemaDelta.between(previous, target)
        #expect(delta.tables.isEmpty)
        #expect(delta.droppedTables == ["people"])
        #expect(try delta.applying(to: previous) == target)
        #expect(try SchemaDelta().applying(to: previous) == previous)
        #expect(throws: (any Error).self) { try SchemaDelta(droppedTables: ["unknown"]).applying(to: previous) }
        #expect(throws: (any Error).self) { try SchemaDelta(tables: [people], droppedTables: ["people"]).applying(to: previous) }
    }

    @Test("Orphan snapshots, old formats, invalid IDs and insertion before history fail")
    func invalidHistory() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = SchemaSnapshot(tables: [people])
        try MigrationTool.generate(id: "002_step", target: target, directory: dir)
        #expect(throws: (any Error).self) { try MigrationTool.generate(id: "001_step", target: target, directory: dir) }
        #expect(throws: (any Error).self) { try MigrationTool.generate(id: "../bad", target: target, directory: dir) }
        #expect(throws: (any Error).self) { try MigrationTool.check(target: .empty, directory: dir) }
        let orphan = dir.appendingPathComponent("003_step.schema.json")
        try Data("{}".utf8).write(to: orphan)
        #expect(throws: (any Error).self) { try MigrationTool.readHistory(directory: dir) }
        try FileManager.default.removeItem(at: orphan)
        try Data("{}".utf8).write(to: dir.appendingPathComponent("schema-history.json"))
        #expect(throws: (any Error).self) { try MigrationTool.readHistory(directory: dir) }
    }

    @Test("Numeric prefixes sort numerically, descriptions are free-form, and numbers are unique")
    func numericIDs() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = SchemaSnapshot(tables: [people])
        try MigrationTool.generate(id: "002_初始化 - hello_世界!", target: target, directory: dir)
        try MigrationTool.generate(id: "10_", target: target, directory: dir)
        try MigrationTool.generate(id: "999999999999999999999999999999_大编号", target: target, directory: dir)
        let history = try MigrationTool.readHistory(directory: dir)
        #expect(history.map(\.symbol) == ["Migration_002", "Migration_10", "Migration_999999999999999999999999999999"])
        let source = try String(contentsOf: dir.appendingPathComponent("002_初始化 - hello_世界!.swift"), encoding: .utf8)
        #expect(source.contains("enum Migration_002 {"))
        let catalog = String(decoding: try MigrationTool.check(target: target, directory: dir), as: UTF8.self)
        #expect(catalog.contains("Migration_002.up"))
        #expect(throws: (any Error).self) {
            try MigrationTool.generate(id: "2_重复", target: target, directory: dir)
        }
        // Hand-maintained histories go through the same duplicate check.
        try Data().write(to: dir.appendingPathComponent("0002_another.swift"))
        #expect(throws: (any Error).self) { try MigrationTool.readHistory(directory: dir) }
    }

    @Test("Migration IDs require a numeric prefix and an underscore")
    func invalidNumericIDs() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        for id in ["001", "1abc_description", "_description", "-1_description", "１_description", "1_bad/path"] {
            #expect(throws: (any Error).self) {
                try MigrationTool.generate(id: id, target: .empty, directory: dir)
            }
        }
        try Data().write(to: dir.appendingPathComponent("1abc_description.swift"))
        #expect(throws: (any Error).self) { try MigrationTool.readHistory(directory: dir) }
    }

    @Test("Handwritten minimal table JSON can be merged")
    func handWritten() throws {
        let data = Data(#"{"tables":[{"name":"people","columns":[{"name":"id","type":"INTEGER","isPrimaryKey":true}]}]}"#.utf8)
        let delta = try JSONDecoder().decode(SchemaDelta.self, from: data)
        #expect(try delta.applying(to: .empty) == SchemaSnapshot(tables: [people]))
    }

    @Test("Source extraction matches compiled Entity metadata")
    func macroParity() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Model.swift")
        try #"""
        import SwiftStoreCore
        @Entity(readonly: true)
        struct SourceParity {
            var id: Int
            var title: String = "guest"
            var amount: Double = 1.25
            var label: String?
            #Index<SourceParity>(\.title, unique: true)
        }
        """#.write(to: file, atomically: true, encoding: .utf8)
        let extracted = try EntitySourceSchema.extract(files: [file])
        #expect(extracted == SchemaSnapshot(entities: [SourceParity.self]))
        #expect(extracted.tables.allSatisfy { $0.triggers.isEmpty })
    }

    @Test("Source extraction includes default markers, sync keys, JSON index columns and timestamp triggers")
    func complexMacroParity() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Models.swift")
        try #"""
        @Embedded struct SourceSettings { var theme: String = "dark" }
        @Entity struct SourceSyncParity {
            var id: UUIDV7 = UUIDV7()
            @Default("guest") let title: String
            var settings: SourceSettings = SourceSettings()
            var createdAt: Date = Date()
            var updatedAt: Date = Date()
            #Index<SourceSyncParity>(\.settings.theme)
        }
        @Entity struct SourceKeyParity {
            #SyncKey<SourceKeyParity>(\.email)
            var email: String = ""
            var createdAt: Date = Date()
            var updatedAt: Date = Date()
        }
        """#.write(to: file, atomically: true, encoding: .utf8)
        let extracted = try EntitySourceSchema.extract(files: [file])
        #expect(extracted == SchemaSnapshot(entities: [SourceSyncParity.self, SourceKeyParity.self]))
        #expect(try MigrationTool.currentSchema(at: dir) == extracted)
        let table = try #require(extracted.tables.first { $0.name == "source_sync_parity" })
        #expect(table.columns.contains { $0.generatedAs != nil })
        #expect(table.triggers.count == 1)
    }

    @Test("Conditional Entity definitions fail instead of guessing the build configuration")
    func conditional() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Model.swift")
        try "#if DEBUG\n@Entity(readonly: true) struct Model { var id: Int }\n#endif".write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try EntitySourceSchema.extract(files: [file]) }
    }

    @Test("Dangerous changes produce a compiler placeholder; safe additions preserve defaults")
    func source() throws {
        let before = SchemaSnapshot(tables: [people])
        let after = SchemaSnapshot(tables: [changedPeople])
        #expect(try !MigrationSourceGenerator.source(symbol: "Migration_001", from: before, to: after).contains("#error"))
        #expect(try MigrationSourceGenerator.source(symbol: "Migration_002", from: after, to: before).contains("#error"))
    }
}
