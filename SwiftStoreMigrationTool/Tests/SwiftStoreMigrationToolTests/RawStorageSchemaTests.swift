import Foundation
import Testing
import SwiftStoreCore
import SwiftStoreMigrationTool

private enum StorageNamespace {
    typealias Code = Swift.Int64
    @Embedded enum Level: Code { case low = 1, high = 10 }
}

private typealias StorageRatioRaw = Double
@Embedded private enum StorageRatio: StorageRatioRaw { case half = 0.5 }
@Embedded private enum StoragePlainState: Sendable { case ready, waiting }

@Embedded private struct StorageBlob {
    var value: String
    static var sqliteType: SQLiteType { .blob }
    static var sqliteIsJSONEncoded: Bool { false }
    func sqliteEncode() throws -> SQLiteValue { .blob(Data(value.utf8)) }
    init(from value: SQLiteValue) throws { self.value = String(decoding: try Data(from: value), as: UTF8.self) }
}
@Embedded private struct StorageRawWrapper: RawRepresentable {
    typealias RawValue = StorageBlob
    var rawValue: RawValue
}

@Entity(readonly: true) private struct StorageSchemaRow {
    var id: Int
    var level: StorageNamespace.Level = .low
    var ratio: StorageRatio?
    var state: StoragePlainState
    var blob: StorageRawWrapper
    var levels: [StorageNamespace.Level]
}

@Suite("Protocol-driven source schema")
struct RawStorageSchemaTests {
    @Test func compiledMetadataAndSourceExtractionAgree() throws {
        let schema = try EntitySourceSchema.extract(files: [URL(fileURLWithPath: #filePath)])
        #expect(schema == SchemaSnapshot(entities: [StorageSchemaRow.self]))
        #expect(schema.tables[0].columns.first { $0.name == "level" }?.defaultValue == nil)
        #expect(schema.tables[0].columns.map(\.type) == ["INTEGER", "INTEGER", "REAL", "TEXT", "BLOB", "TEXT"])
    }

    @Test func syncOptOutDoesNotChangeSourceSchema() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Row.swift")
        let source = """
            @Entity(sync: false) struct Row {
                var id: UUIDV7
                var title: String
                var createdAt: Date = Date()
                var updatedAt: Date = Date()
            }
            """
        try source.write(to: file, atomically: true, encoding: .utf8)
        let local = try EntitySourceSchema.extract(files: [file])
        try source.replacingOccurrences(of: "sync: false", with: "sync: true")
            .write(to: file, atomically: true, encoding: .utf8)
        #expect(local == (try EntitySourceSchema.extract(files: [file])))
        #expect(local.tables.map(\.name) == ["row"])
    }

    @Test func resolvesAliasesAcrossFilesAndRejectsUnknownOrCyclicTypes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let aliases = dir.appendingPathComponent("Aliases.swift")
        let enums = dir.appendingPathComponent("Enums.swift")
        let model = dir.appendingPathComponent("Model.swift")
        try "typealias Code = Swift.Int32".write(to: aliases, atomically: true, encoding: .utf8)
        try "@Embedded enum State: Code { case ready = 1 }".write(to: enums, atomically: true, encoding: .utf8)
        try "@Entity(readonly: true) struct Row { var id: Int; var state: State }".write(to: model, atomically: true, encoding: .utf8)
        #expect(try EntitySourceSchema.extract(files: [model, enums, aliases]).tables[0].columns[1].type == "INTEGER")
        #expect(throws: VersionedMigrationError.self) { try EntitySourceSchema.extract(files: [model, enums]) }
        try "typealias Code = Other; typealias Other = Code".write(to: aliases, atomically: true, encoding: .utf8)
        #expect(throws: VersionedMigrationError.self) { try EntitySourceSchema.extract(files: [model, enums, aliases]) }
    }
}
