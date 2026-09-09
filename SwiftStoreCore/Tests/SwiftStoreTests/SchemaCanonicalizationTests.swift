import Foundation
import Testing
@testable import SwiftStoreCore

@Suite("Schema canonicalization")
struct SchemaCanonicalizationTests {
    private func snapshot(_ column: String = #"{"name":"id","type":"BLOB","isPrimaryKey":true}"#,
                          fields: String = "") throws -> SchemaSnapshot {
        try SchemaSnapshot.decode(Data("{\"tables\":[{\"name\":\"sample\",\"columns\":[\(column)]\(fields)}]}".utf8))
    }

    @Test("Absent, null and empty optional collections have one canonical encoding")
    func collections() throws {
        let baseline = try snapshot()
        let json = try #require(JSONSerialization.jsonObject(with: baseline.json()) as? [String: Any])
        let table = try #require((json["tables"] as? [[String: Any]])?.first)
        for field in ["indexes", "triggers", "foreignKeys", "fullTextIndexes"] {
            #expect((table[field] as? [Any])?.isEmpty == true)
            for value in ["null", "[]"] {
                let other = try snapshot(fields: ",\"\(field)\":\(value)")
                #expect(try baseline.isEquivalent(to: other))
                #expect(try baseline.json() == other.json())
            }
            for value in ["{}", "\"\""] {
                #expect(throws: (any Error).self) { try snapshot(fields: ",\"\(field)\":\(value)") }
            }
        }
    }

    @Test("SQL defaults retain NULL and empty-string semantics")
    func defaults() throws {
        let absent = try snapshot(#"{"name":"id","type":"TEXT"}"#)
        let null = try snapshot(#"{"name":"id","type":"TEXT","defaultValue":null,"generatedAs":null}"#)
        let sqlNull = try snapshot(#"{"name":"id","type":"TEXT","defaultValue":"NULL"}"#)
        let emptyString = try snapshot(#"{"name":"id","type":"TEXT","defaultValue":"''"}"#)
        #expect(try absent.isEquivalent(to: null))
        #expect(try !absent.isEquivalent(to: sqlNull))
        #expect(try !sqlNull.isEquivalent(to: emptyString))
        #expect(throws: (any Error).self) { try snapshot(#"{"name":"id","type":"TEXT","generatedAs":""}"#) }
        #expect(throws: (any Error).self) { try snapshot(#"{"name":"id","type":"TEXT","defaultValue":""}"#) }
    }

    @Test("Missing booleans use defaults; explicit null and wrong types are invalid")
    func booleans() throws {
        let absent = try snapshot(#"{"name":"id","type":"TEXT"}"#)
        let explicit = try snapshot(#"{"name":"id","type":"TEXT","isNullable":false,"isPrimaryKey":false}"#)
        #expect(try absent.isEquivalent(to: explicit))
        for field in ["isNullable", "isPrimaryKey"] {
            for value in ["null", "\"\"", "0"] {
                #expect(throws: (any Error).self) {
                    try snapshot("{\"name\":\"id\",\"type\":\"TEXT\",\"\(field)\":\(value)}")
                }
            }
        }
        #expect(throws: (any Error).self) {
            try snapshot(fields: #", "indexes":[{"name":"idx","columns":["id"],"isUnique":null}]"#)
        }
    }

    @Test("Required fields and required collections remain invalid after normalization")
    func requiredFields() throws {
        for column in [#"{"name":"","type":"TEXT"}"#, #"{"name":"id","type":""}"#,
                       #"{"name":null,"type":"TEXT"}"#, #"{"type":"TEXT"}"#] {
            #expect(throws: (any Error).self) { try snapshot(column) }
        }
        for field in ["", #", "columns":null"#, #", "columns":[]"#] {
            let data = Data("{\"tables\":[{\"name\":\"sample\"\(field)}]}".utf8)
            #expect(throws: (any Error).self) { try SchemaSnapshot.decode(data) }
        }
        #expect(throws: (any Error).self) {
            try snapshot(fields: #", "indexes":[{"name":"idx","columns":[]}]"#)
        }
    }

    @Test("Table order is canonical; compound index column order is preserved")
    func order() throws {
        let columns = [ColumnSchema(name: "a", type: "TEXT"), ColumnSchema(name: "b", type: "TEXT")]
        let left = TableSchema(name: "left", columns: columns)
        let right = TableSchema(name: "right", columns: columns)
        let ordered = SchemaSnapshot(tables: [left, right])
        let data = Data(#"""
            {"tables":[
                {"name":"right","columns":[{"name":"a","type":"TEXT"},{"name":"b","type":"TEXT"}]},
                {"name":"left","columns":[{"name":"a","type":"TEXT"},{"name":"b","type":"TEXT"}]}
            ]}
            """#.utf8)
        let unordered = try JSONDecoder().decode(SchemaSnapshot.self, from: data)
        #expect(try ordered.isEquivalent(to: unordered))
        #expect(try ordered.json() == unordered.json())
        let ab = SchemaSnapshot(tables: [TableSchema(name: "test", columns: columns,
            indexes: [IndexSchema(name: "idx", columns: ["a", "b"])])])
        let ba = SchemaSnapshot(tables: [TableSchema(name: "test", columns: columns,
            indexes: [IndexSchema(name: "idx", columns: ["b", "a"])])])
        #expect(try !ab.isEquivalent(to: ba))
    }

    @Test("Missing enum settings use declared defaults; null and unknown enums are rejected")
    func enums() throws {
        let base = #", "fullTextIndexes":[{"name":"search","columns":[{"name":"id","column":"id"}],"keyColumns":["id"]TOKENIZER}]"#
        let missing = try snapshot(#"{"name":"id","type":"TEXT","isPrimaryKey":true}"#,
            fields: base.replacingOccurrences(of: "TOKENIZER", with: ""))
        let explicit = try snapshot(#"{"name":"id","type":"TEXT","isPrimaryKey":true}"#,
            fields: base.replacingOccurrences(of: "TOKENIZER", with: #", "tokenizer":"unicode61""#))
        #expect(try missing.isEquivalent(to: explicit))
        for value in ["null", "\"\"", "\"unknown\""] {
            #expect(throws: (any Error).self) {
                try snapshot(fields: base.replacingOccurrences(of: "TOKENIZER", with: ",\"tokenizer\":\(value)"))
            }
        }
        let key = #", "foreignKeys":[{"column":"id","referencesTable":"parent","referencesColumn":"id"ACTIONS}]"#
        let defaultKey = try snapshot(fields: key.replacingOccurrences(of: "ACTIONS", with: ""))
        let explicitKey = try snapshot(fields: key.replacingOccurrences(of: "ACTIONS", with: #", "onDelete":"NO ACTION","onUpdate":"NO ACTION""#))
        #expect(try defaultKey.isEquivalent(to: explicitKey))
        #expect(throws: (any Error).self) {
            try snapshot(fields: key.replacingOccurrences(of: "ACTIONS", with: #", "onDelete":null"#))
        }
    }
}
