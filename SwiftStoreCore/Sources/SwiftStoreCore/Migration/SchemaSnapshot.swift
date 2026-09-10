import Foundation

/// Immutable, checked-in schema metadata. Never capture historical schemas using live Entity types.
public struct SchemaSnapshot: Codable, Sendable, Equatable {
    public let tables: [TableSchema]

    public init(tables: [TableSchema]) {
        self.tables = tables.sorted { $0.name < $1.name }
    }

    public init(entities: [any EntityProtocol.Type]) {
        self.init(tables: DatabaseSchemaBuilder().buildSchemas(from: entities))
    }

    public static let empty = SchemaSnapshot(tables: [])

    /// Canonical typed representation used before encoding or comparing schemas.
    /// Decoders resolve field-specific defaults (including absent/null/empty collections).
    /// Only table order is normalized; column/index-column order and SQL expressions are semantic.
    public func canonicalized() throws -> SchemaSnapshot {
        let snapshot = SchemaSnapshot(tables: tables)
        try snapshot.validate()
        return snapshot
    }

    public func isEquivalent(to other: SchemaSnapshot) throws -> Bool {
        try canonicalized() == other.canonicalized()
    }

    public func json() throws -> Data {
        try SchemaJSON.encode(canonicalized())
    }

    public static func decode(_ data: Data) throws -> SchemaSnapshot {
        let snapshot = try JSONDecoder().decode(Self.self, from: data)
        return try snapshot.canonicalized()
    }

    public func validate() throws {
        guard Set(tables.map { $0.name.lowercased() }).count == tables.count else {
            throw VersionedMigrationError.invalidHistory("Duplicate table names")
        }
        let objectNames = tables.flatMap { table in
            [table.name] + table.indexes.map(\.name) + FullTextSchema(table: table).objectNames +
                FullTextSchema(table: table).shadowTableNames
        }.map { $0.lowercased() }
        let triggerNames = tables.flatMap { table in
            table.triggers.map(\.name) + (table.fullTextIndexes.isEmpty ? [] : FullTextSchema(table: table).triggerNames)
        }.map { $0.lowercased() }
        guard Set(objectNames).count == objectNames.count, Set(triggerNames).count == triggerNames.count else {
            throw VersionedMigrationError.invalidHistory("Duplicate table, index or trigger names")
        }
        for table in tables {
            try FullTextSchema(table: table).validate()
            guard !table.name.lowercased().hasPrefix("__swiftstore_"), !table.name.lowercased().hasPrefix("sqlite_"),
                  !table.name.isEmpty, !table.columns.isEmpty,
                  Set(table.columns.map { $0.name.lowercased() }).count == table.columns.count else {
                throw VersionedMigrationError.invalidHistory("Invalid or reserved table: \(table.name)")
            }
            for column in table.columns {
                guard !column.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !column.type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      column.generatedAs.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true,
                      column.defaultValue.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true else {
                    throw VersionedMigrationError.invalidHistory("Invalid column or empty SQL expression: \(table.name).\(column.name)")
                }
            }
            for index in table.indexes {
                guard !index.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !index.columns.isEmpty,
                      index.columns.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                    throw VersionedMigrationError.invalidHistory("Invalid index: \(index.name)")
                }
            }
            for key in table.foreignKeys {
                guard [key.column, key.referencesTable, key.referencesColumn].allSatisfy({
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }) else { throw VersionedMigrationError.invalidHistory("Invalid foreign key on \(table.name)") }
            }
        }
    }

    /// SQL for a fresh database, also used to validate the result of historical migrations.
    public var creationStatements: [String] {
        tables.flatMap { table in
            let definitions = table.columns.map { $0.toSQL() } + table.foreignKeys.map { $0.toSQL() }
            let create = "CREATE TABLE \(table.name) (\n    \(definitions.joined(separator: ",\n    "))\n)"
            return [create] + table.indexes.map { $0.toSQL(tableName: table.name) } + table.triggers.map(\.sql) +
                FullTextSchema(table: table).creationStatements
        }
    }

    /// Strict comparison includes constraints, defaults, generated columns, indexes and triggers.
    /// Extra tables are allowed (e.g. sync metadata); removed managed tables are checked by the runner.
    public func verify(on connection: SQLiteConnection) throws {
        try validate()
        var options = SQLiteConnection.Options()
        options.foreignKeys = false
        let reference = try SQLiteConnection(path: ":memory:", options: options)
        for sql in creationStatements { try reference.execute(sql) }
        for name in managedObjectNames {
            let expected = try Self.definitions(table: name, on: reference)
            let actual = try Self.definitions(table: name, on: connection)
            guard expected == actual else {
                throw VersionedMigrationError.schemaMismatch(name)
            }
        }
    }

    /// Includes auxiliary objects so removal is checked by the migration runner.
    public var managedObjectNames: [String] {
        tables.flatMap { [$0.name] + FullTextSchema(table: $0).objectNames + FullTextSchema(table: $0).shadowTableNames }
    }

    private static func definitions(table: String, on db: SQLiteConnection) throws -> [String] {
        let stmt = try db.prepare("""
            SELECT type, name, sql FROM sqlite_master
            WHERE tbl_name = ? AND sql IS NOT NULL ORDER BY type, name
            """)
        try stmt.bind(1, table)
        var result: [String] = []
        while try stmt.step() {
            result.append((stmt.columnString(0) ?? "") + ":" + (stmt.columnString(1) ?? "") + ":" +
                normalizedSQL(stmt.columnString(2) ?? ""))
        }
        // SQLite permits legacy bare-word and double-quoted DEFAULT literals. Keep the parsed
        // defaults verbatim too, so identifier normalization cannot hide a changed default value.
        let quoted = table.replacingOccurrences(of: "\"", with: "\"\"")
        let columns = try db.prepare("PRAGMA table_xinfo(\"\(quoted)\")")
        while try columns.step() {
            if let value = columns.columnString(4) {
                result.append("default:" + (columns.columnString(1) ?? "") + ":" + value)
            }
        }
        return result
    }

    // Tokenize rather than collapsing whitespace inside literals. SQLite rewrites CREATE headers
    // and quotes identifiers after ALTER TABLE; neither should invalidate a migrated schema.
    private static func normalizedSQL(_ sql: String) -> String {
        let pattern = #"'(?:''|[^'])*'|"(?:""|[^"])*"|`(?:``|[^`])*`|\[[^\]]*\]|[A-Za-z_][A-Za-z_0-9]*|[0-9]+(?:\.[0-9]+)?|[^\s]"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let source = sql as NSString
        var tokens = regex.matches(in: sql, range: NSRange(location: 0, length: source.length)).map {
            let token = source.substring(with: $0.range)
            if token.first == "'" { return token }
            if token.first == "\"" { return String(token.dropFirst().dropLast()).replacingOccurrences(of: "\"\"", with: "\"").lowercased() }
            if token.first == "`" { return String(token.dropFirst().dropLast()).replacingOccurrences(of: "``", with: "`").lowercased() }
            if token.first == "[" { return String(token.dropFirst().dropLast()).lowercased() }
            return token.lowercased()
        }
        // IF NOT EXISTS is omitted from sqlite_master by SQLite.
        if let index = tokens.indices.first(where: { index in
            index < 4 && index + 2 < tokens.count && Array(tokens[index...index + 2]) == ["if", "not", "exists"]
        }) { tokens.removeSubrange(index...index + 2) }
        while tokens.last == ";" { tokens.removeLast() }
        return tokens.joined(separator: "\u{1f}")
    }
}
