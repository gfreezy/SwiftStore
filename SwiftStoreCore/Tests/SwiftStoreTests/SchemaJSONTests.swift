import Foundation
import Testing
import SwiftStoreCore

@Suite("Readable schema JSON")
struct SchemaJSONTests {
    @Test("Snapshots and deltas have stable indentation and inline empty arrays")
    func layout() throws {
        #expect(String(decoding: try SchemaSnapshot.empty.json(), as: UTF8.self) == "{\n  \"tables\": []\n}")
        #expect(String(decoding: try SchemaDelta().json(), as: UTF8.self) == """
            {
              "droppedTables": [],
              "formatVersion": 1,
              "tables": []
            }
            """)
        let table = TableSchema(name: "sample", columns: [ColumnSchema(name: "id", type: "INTEGER")])
        let snapshot = SchemaSnapshot(tables: [table])
        for data in [try snapshot.json(), try SchemaDelta(tables: [table]).json()] {
            let text = String(decoding: data, as: UTF8.self)
            #expect(!text.contains("\" :"))
            #expect(!text.contains("[\n\n"))
            #expect(text.contains("      \"indexes\": []"))
            #expect(!text.components(separatedBy: "\n").contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        }
        #expect(try SchemaSnapshot.decode(snapshot.json()) == snapshot)
    }

    @Test("JSON formatting preserves SQL literals, whitespace, Unicode and escapes exactly")
    func sqlStrings() throws {
        let literal = #"' A  B : [], {} \ " 中文 '"#
        let body = "  UPDATE sample SET value = \(literal);\n\n  -- keep this indentation\n"
        let trigger = TriggerSchema(name: "custom", event: .update, timing: .after, body: body,
                                    sql: "CREATE TRIGGER custom AFTER UPDATE ON sample BEGIN\n\(body)END")
        let table = TableSchema(name: "sample", columns: [
            ColumnSchema(name: "value", type: "TEXT", defaultValue: literal)
        ], triggers: [trigger])
        let snapshot = SchemaSnapshot(tables: [table])
        #expect(try SchemaSnapshot.decode(snapshot.json()) == snapshot)
        let delta = SchemaDelta(tables: [table])
        #expect(try SchemaDelta.decode(delta.json()) == delta)
    }

    @Test("Timestamp trigger templates have no leading body indentation and execute correctly")
    func triggerTemplate() throws {
        let trigger = DatabaseSchemaBuilder.updateTrigger(for: "sample")
        #expect(trigger.body.hasPrefix("UPDATE sample"))
        #expect(trigger.body.components(separatedBy: "\n")[1] == "WHERE rowid = NEW.rowid;")
        #expect(trigger.sql.contains("\n    UPDATE sample"))
        #expect(trigger.sql.contains("\n    WHERE rowid = NEW.rowid;\nEND"))
        let db = try SQLiteConnection(path: ":memory:")
        try db.execute("CREATE TABLE sample (value TEXT, updated_at REAL)")
        try db.execute(trigger.sql)
        try db.execute("INSERT INTO sample VALUES (' A  B ', 1)")
        try db.execute("UPDATE sample SET value = ' C  D '")
        #expect(try db.queryScalar("SELECT value FROM sample", type: String.self) == " C  D ")
        #expect(try db.queryScalar("SELECT updated_at FROM sample", type: Double.self)! > 1)
    }
}
