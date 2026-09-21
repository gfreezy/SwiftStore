import Foundation
import Testing
@testable import SwiftStoreCore

@Embedded
struct ArraySearchParagraph {
    var text: String
    var translation: String?
    var ignored: String = "metadataonly"
}

@Embedded
struct ArraySearchChapter {
    var title: String
    var paragraphs: [ArraySearchParagraph]?
}

@Embedded
struct ArraySearchBody {
    var chapters: [ArraySearchChapter]
}

@Entity(tableName: "array_search")
struct ArraySearchDocument {
    #FullTextIndex<Self>(\.title,
        .each(\.body.chapters, fields: \.title,
            .each(\.paragraphs, fields: \.text, \.translation)))
    var id: UUIDV7 = UUIDV7()
    var title: String
    var body: ArraySearchBody
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

@Suite("FullText array projections")
struct FullTextArrayTests {
    private func setup() throws -> SQLiteConnection {
        let db = try SQLiteConnection(path: ":memory:")
        let schema = SchemaSnapshot(entities: [ArraySearchDocument.self])
        for sql in schema.creationStatements {
            do { try db.execute(sql) }
            catch { throw StoreError.queryFailed("Failed SQL: \(sql): \(error)") }
        }
        return db
    }

    private func integrity(_ db: SQLiteConnection) throws {
        try db.execute("INSERT INTO array_search_fts(array_search_fts, rank) VALUES ('integrity-check', 1)")
    }

    @Test func nestedArraysMaintainIndependentColumns() throws {
        let db = try setup()
        var document = ArraySearchDocument(title: "Overview", body: .init(chapters: [
            .init(title: "Science", paragraphs: [
                .init(text: "first", translation: "bonjour"),
                .init(text: "second", translation: nil)
            ]),
            .init(title: "History", paragraphs: [.init(text: "third", translation: "salut")]),
            .init(title: "Empty", paragraphs: nil)
        ]))
        try document.insert(db)
        #expect(try ArraySearchDocument.search("Science").count(db) == 1)
        #expect(try ArraySearchDocument.search("bonjour").count(db) == 1)
        #expect(try ArraySearchDocument.search("metadataonly").count(db) == 0)
        #expect(try ArraySearchDocument.matching("body__chapters__paragraphs__translation: bonjour").count(db) == 1)
        #expect(try ArraySearchDocument.matching("body__chapters__paragraphs__text: bonjour").count(db) == 0)
        #expect(try db.queryScalar("SELECT body__chapters__paragraphs__text FROM __swiftstore_fts_array_search_fts_content", type: String.self) == "first\nsecond\nthird")
        try integrity(db)

        document.body.chapters[0].paragraphs = [.init(text: "replacement", translation: nil)]
        try document.update(db)
        #expect(try ArraySearchDocument.search("bonjour").count(db) == 0)
        #expect(try ArraySearchDocument.search("replacement").count(db) == 1)
        // Raw writes exercise the same trigger path as incoming synchronization writes.
        try db.execute("UPDATE array_search SET body = '{\"chapters\":[{\"title\":\"Remote\",\"paragraphs\":[{\"text\":\"remotecontent\",\"translation\":null}]}]}'")
        #expect(try ArraySearchDocument.search("replacement").count(db) == 0)
        #expect(try ArraySearchDocument.search("remotecontent").count(db) == 1)
        try integrity(db)
        try db.execute("INSERT INTO array_search_fts(array_search_fts) VALUES ('rebuild')")
        #expect(try ArraySearchDocument.search("remotecontent").count(db) == 1)
        try integrity(db)
        try document.delete(db)
        #expect(try ArraySearchDocument.search("remotecontent").count(db) == 0)
        try integrity(db)
    }

    @Test func emptyMissingAndMalformedValuesDoNotIndexMetadata() throws {
        let db = try setup()
        let document = ArraySearchDocument(title: "", body: .init(chapters: []))
        try document.insert(db)
        for json in ["{}", "null", "not json", "{\"chapters\":null}",
                     "{\"chapters\":{\"title\":\"notanarray\"}}",
                     "{\"chapters\":[null,42,\"text\",{\"paragraphs\":[{\"text\":42},{\"text\":{\"x\":\"hidden\"}}]}]}"] {
            try db.execute("UPDATE array_search SET body = ?", values: [.text(json)])
            #expect(try db.queryScalar("SELECT body__chapters__paragraphs__text FROM __swiftstore_fts_array_search_fts_content", type: String.self) == "")
            try integrity(db)
        }
    }

    @Test func scalarFunctionPreservesUnicodeOrderAndRejectsInvalidRules() throws {
        let db = try SQLiteConnection(path: ":memory:")
        let rule = #"["$", "$.text"]"#
        let values: [[String: String]] = (0..<2000).map { ["text": "正文\($0) 🌍"] }
        let json = String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
        let result = try db.queryScalar("SELECT swiftstore_fts_text_v1(?, ?)",
            values: [.text(json), .text(rule)], type: String.self)
        #expect(result == values.map { $0["text"]! }.joined(separator: "\n"))
        #expect(throws: (any Error).self) {
            try db.queryScalar("SELECT swiftstore_fts_text_v1('[]', 'invalid')", type: String.self)
        }
        #expect(try db.queryScalar("SELECT swiftstore_fts_text_v1(NULL, ?)",
            values: [.text(rule)], type: String.self) == "")
        #expect(try db.queryScalar("SELECT hex(swiftstore_fts_text_v1(?, ?))",
            values: [.text(#"[{"text":"a\u0000b"}]"#), .text(rule)], type: String.self) == "610062")
    }

    @Test func reopeningReadOnlyAndUntrustedSchemaRegisterTheFunction() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("search.sqlite").path
        let schema = SchemaSnapshot(entities: [ArraySearchDocument.self])
        do {
            let db = try SQLiteConnection(path: path)
            try db.execute("PRAGMA trusted_schema = OFF")
            for sql in schema.creationStatements { try db.execute(sql) }
            try ArraySearchDocument(title: "", body: .init(chapters: [
                .init(title: "", paragraphs: [.init(text: "persistedbody", translation: nil)])
            ])).insert(db)
            try integrity(db)
        }
        var options = SQLiteConnection.Options()
        options.readonly = true
        options.walMode = false
        let reader = try SQLiteConnection(path: path, options: options)
        #expect(try reader.queryScalar("SELECT body__chapters__paragraphs__text FROM __swiftstore_fts_array_search_fts_content", type: String.self) == "persistedbody")
        let writer = try SQLiteConnection(path: path)
        try schema.verify(on: writer)
        try writer.execute("INSERT INTO array_search_fts(array_search_fts) VALUES ('rebuild')")
        try integrity(writer)
        #expect(try ArraySearchDocument.search("persistedbody").count(reader) == 1)
    }

    @Test func oldMetadataDecodesWithoutArrayPaths() throws {
        let old = Data(#"{"name":"body","column":"body","jsonPath":"$.text"}"#.utf8)
        let column = try JSONDecoder().decode(FullTextColumn.self, from: old)
        #expect(column.arrayPaths == nil)
        #expect(!String(decoding: try JSONEncoder().encode(column), as: UTF8.self).contains("arrayPaths"))
    }
}
