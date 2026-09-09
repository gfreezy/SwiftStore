import Foundation
import SwiftStoreProtocols

/// Local derived objects for a table's full-text indexes. Never register these as sync entities.
public struct FullTextSchema {
    public let table: TableSchema
    public init(table: TableSchema) { self.table = table }

    public var mappingName: String { "__swiftstore_fts_\(table.name)_map" }
    public func contentName(for index: FullTextIndexDefinition) -> String { "__swiftstore_fts_\(index.name)_content" }
    public var triggerNames: [String] { ["ai", "au", "bd"].map { "__swiftstore_fts_\(table.name)_\($0)" } }

    /// Objects owned by the schema (FTS shadow tables are owned/dropped by SQLite).
    public var objectNames: [String] {
        guard !table.fullTextIndexes.isEmpty else { return [] }
        return [mappingName] + triggerNames + table.fullTextIndexes.flatMap { [$0.name, contentName(for: $0)] }
    }

    /// External-content FTS5 owns these shadow tables; include them in schema verification.
    public var shadowTableNames: [String] {
        table.fullTextIndexes.flatMap { index in ["_data", "_idx", "_docsize", "_config"].map { index.name + $0 } }
    }

    private var keys: [String] { table.fullTextIndexes.first?.keyColumns ?? [] }
    private func q(_ value: String) -> String { Self.quote(value) }
    public static func quote(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    private func literal(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "''") + "'" }
    private var keyList: String { keys.map(q).joined(separator: ", ") }
    private func keyValues(_ alias: String) -> String { keys.map { "\(alias).\(q($0))" }.joined(separator: ", ") }
    private func keyMatch(_ alias: String, mapping: String? = nil) -> String {
        keys.map { "\(mapping.map { $0 + "." } ?? "")\(q($0)) = \(alias).\(q($0))" }.joined(separator: " AND ")
    }
    private func projection(_ field: FullTextColumn, alias: String) -> String {
        let column = "\(alias).\(q(field.column))"
        return field.jsonPath.map { "json_extract(\(column), \(literal($0)))" } ?? column
    }
    private func rowID(_ alias: String) -> String {
        "(SELECT fts_id FROM \(q(mappingName)) WHERE \(keyMatch(alias)))"
    }
    private func insert(_ index: FullTextIndexDefinition, alias: String) -> String {
        "INSERT INTO \(q(index.name))(rowid, \(index.columns.map { q($0.name) }.joined(separator: ", "))) VALUES (\(rowID(alias)), \(index.columns.map { projection($0, alias: alias) }.joined(separator: ", ")));"
    }
    private func delete(_ index: FullTextIndexDefinition) -> String {
        "INSERT INTO \(q(index.name))(\(q(index.name)), rowid, \(index.columns.map { q($0.name) }.joined(separator: ", "))) VALUES ('delete', \(rowID("OLD")), \(index.columns.map { projection($0, alias: "OLD") }.joined(separator: ", ")));"
    }

    public var creationStatements: [String] {
        guard !table.fullTextIndexes.isEmpty else { return [] }
        let keyDefinitions = keys.map { key in
            let type = table.columns.first { $0.name == key }!.type
            return "\(q(key)) \(type) NOT NULL"
        }.joined(separator: ", ")
        var sql = ["CREATE TABLE \(q(mappingName)) (fts_id INTEGER PRIMARY KEY, \(keyDefinitions), UNIQUE (\(keyList)))"]
        for index in table.fullTextIndexes {
            let fields = index.columns.map { "\(projection($0, alias: "a")) AS \(q($0.name))" }.joined(separator: ", ")
            sql.append("CREATE VIEW \(q(contentName(for: index))) AS SELECT m.fts_id, \(fields) FROM \(q(table.name)) AS a JOIN \(q(mappingName)) AS m ON \(keyMatch("a", mapping: "m"))")
            sql.append("CREATE VIRTUAL TABLE \(q(index.name)) USING fts5(\(index.columns.map { q($0.name) }.joined(separator: ", ")), content=\(literal(contentName(for: index))), content_rowid='fts_id', tokenize=\(literal(index.tokenizer.rawValue)))")
        }
        let inserts = table.fullTextIndexes.map { insert($0, alias: "NEW") }.joined(separator: "\n")
        let deletes = table.fullTextIndexes.map(delete).joined(separator: "\n")
        let conditions = keys.map { "OLD.\(q($0)) IS NOT NEW.\(q($0))" } + table.fullTextIndexes.flatMap { index in
            index.columns.map { "\(projection($0, alias: "OLD")) IS NOT \(projection($0, alias: "NEW"))" }
        }
        sql.append("""
            CREATE TRIGGER \(q(triggerNames[0])) AFTER INSERT ON \(q(table.name)) BEGIN
                INSERT INTO \(q(mappingName))(\(keyList)) VALUES (\(keyValues("NEW")));
                \(inserts)
            END
            """)
        sql.append("""
            CREATE TRIGGER \(q(triggerNames[1])) AFTER UPDATE ON \(q(table.name))
            WHEN \(conditions.joined(separator: " OR ")) BEGIN
                \(deletes)
                UPDATE \(q(mappingName)) SET \(keys.map { "\(q($0)) = NEW.\(q($0))" }.joined(separator: ", ")) WHERE \(keyMatch("OLD"));
                \(inserts)
            END
            """)
        sql.append("""
            CREATE TRIGGER \(q(triggerNames[2])) BEFORE DELETE ON \(q(table.name)) BEGIN
                \(deletes)
                DELETE FROM \(q(mappingName)) WHERE \(keyMatch("OLD"));
            END
            """)
        // The view must contain all existing rows before FTS5 rebuild reads it.
        sql.append("INSERT INTO \(q(mappingName))(\(keyList)) SELECT \(keyList) FROM \(q(table.name))")
        sql += table.fullTextIndexes.map { "INSERT INTO \(q($0.name))(\(q($0.name))) VALUES ('rebuild')" }
        return sql
    }

    public var dropStatements: [String] {
        guard !table.fullTextIndexes.isEmpty else { return [] }
        return triggerNames.map { "DROP TRIGGER \(q($0))" } + table.fullTextIndexes.flatMap {
            ["DROP TABLE \(q($0.name))", "DROP VIEW \(q(contentName(for: $0)))"]
        } + ["DROP TABLE \(q(mappingName))"]
    }

    public func validate() throws {
        guard !table.fullTextIndexes.isEmpty else { return }
        func fail(_ reason: String) -> VersionedMigrationError { .invalidHistory("FTS on \(table.name): \(reason)") }
        guard !keys.isEmpty, Set(keys).count == keys.count,
              keys.allSatisfy({ key in table.columns.contains { $0.name == key && !$0.isNullable && !$0.isGenerated } }),
              !keys.contains(where: { $0.lowercased() == "fts_id" }) else { throw fail("invalid identity columns") }
        let primary = table.columns.filter(\.isPrimaryKey).map(\.name)
        guard primary == keys || table.indexes.contains(where: { $0.isUnique && $0.columns == keys }) else {
            throw fail("identity columns must have a primary key or unique index")
        }
        for index in table.fullTextIndexes {
            guard !index.name.isEmpty, !index.name.contains("\0"),
                  !index.name.lowercased().hasPrefix("sqlite_"), !index.name.lowercased().hasPrefix("__swiftstore_"),
                  index.keyColumns == keys, !index.columns.isEmpty else { throw fail("invalid index \(index.name)") }
            let names = index.columns.map { $0.name.lowercased() }
            guard Set(names).count == names.count,
                  !names.contains(where: { ["rank", "rowid", "fts_id", index.name.lowercased()].contains($0) || $0.isEmpty || $0.contains("\0") }) else {
                throw fail("duplicate or reserved FTS column names")
            }
            for field in index.columns {
                guard let column = table.columns.first(where: { $0.name == field.column }), column.type.uppercased() == "TEXT",
                      field.jsonPath.map({ $0.hasPrefix("$.") && !$0.contains("\0") }) ?? true else {
                    throw fail("\(field.name) must reference a text column or JSON text property")
                }
            }
        }
    }
}
