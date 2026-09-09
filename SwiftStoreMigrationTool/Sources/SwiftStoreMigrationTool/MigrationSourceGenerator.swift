import Foundation
import SwiftStoreCore

/// Generates editable Swift code from immutable schemas. Ambiguous/destructive changes produce
/// a compiler error at the point where a developer must supply a data-preserving transformation.
public enum MigrationSourceGenerator {
    public static func source(symbol: String, from old: SchemaSnapshot, to new: SchemaSnapshot) throws -> String {
        try old.validate()
        try new.validate()
        var lines = ["import SwiftStoreCore", "", "// Review before publishing. Published migrations must never be edited.",
                     "enum \(symbol) {", "    static func up(_ db: SQLiteConnection) throws {"]
        func emit(_ sql: String) { lines.append("        try db.execute(\(String(reflecting: sql)))") }
        func manual(_ message: String) { lines.append("        #error(\(String(reflecting: message)))") }
        let oldTables = Dictionary(uniqueKeysWithValues: old.tables.map { ($0.name, $0) })
        for table in new.tables {
            guard let previous = oldTables[table.name] else {
                for sql in SchemaSnapshot(tables: [table]).creationStatements { emit(sql) }
                continue
            }
            let previousColumns = Dictionary(uniqueKeysWithValues: previous.columns.map { ($0.name, $0) })
            let additions = table.columns.filter { previousColumns[$0.name] == nil }
            let changedExisting = previous.columns.contains { !table.columns.contains($0) }
            let unsafeAddition = additions.contains {
                $0.isGenerated || $0.isPrimaryKey || (!$0.isNullable && $0.defaultValue == nil) ||
                ($0.defaultValue.map { value in
                    let value = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    return value.hasPrefix("(") || ["CURRENT_TIME", "CURRENT_DATE", "CURRENT_TIMESTAMP"].contains(value)
                } ?? false)
            }
            if changedExisting || unsafeAddition || previous.foreignKeys != table.foreignKeys ||
                table.columns.map(\.name) != previous.columns.map(\.name) + additions.map(\.name) {
                manual("Manual migration required for \(table.name): rename, rebuild, or backfill columns/constraints. Replace this error with SQL; preserve old data.")
                lines.append("        // Target table definition (reference only):")
                for sql in SchemaSnapshot(tables: [table]).creationStatements {
                    lines.append("        // " + String(reflecting: sql))
                }
                continue
            }
            for trigger in previous.triggers where !table.triggers.contains(trigger) {
                emit("DROP TRIGGER \(quote(trigger.name))")
            }
            for index in previous.indexes where !table.indexes.contains(index) {
                emit("DROP INDEX \(quote(index.name))")
            }
            for column in additions { emit("ALTER TABLE \(quote(table.name)) ADD COLUMN \(column.toSQL())") }
            for index in table.indexes where !previous.indexes.contains(index) { emit(index.toSQL(tableName: table.name)) }
            for trigger in table.triggers where !previous.triggers.contains(trigger) { emit(trigger.sql) }
        }
        for table in old.tables where !new.tables.contains(where: { $0.name == table.name }) {
            manual("Table \(table.name) removed: explicitly migrate its data and DROP TABLE, or implement a rename.")
        }
        lines += ["        // Add data migration SQL here, or between the schema statements above.", "    }", "}", ""]
        return lines.joined(separator: "\n")
    }

    private static func quote(_ name: String) -> String { "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
}
