import Foundation

/// Immutable, checked-in schema metadata. Never capture historical schemas using live Entity types.
public struct SchemaSnapshot: Codable, Sendable, Equatable {
    public let tables: [TableSchema]

    public init(tables: [TableSchema]) {
        self.tables = tables.sorted { $0.name < $1.name }
    }

    public init(entities: [any EntityProtocol.Type], createUpdateTrigger: Bool = true) {
        self.init(tables: DatabaseSchemaBuilder(options: .init(createUpdateTrigger: createUpdateTrigger))
            .buildSchemas(from: entities))
    }

    public static let empty = SchemaSnapshot(tables: [])

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> SchemaSnapshot {
        let snapshot = try JSONDecoder().decode(Self.self, from: data)
        try snapshot.validate()
        return snapshot
    }

    public func validate() throws {
        guard Set(tables.map { $0.name.lowercased() }).count == tables.count else {
            throw VersionedMigrationError.invalidHistory("Duplicate table names")
        }
        let objectNames = tables.flatMap { [$0.name] + $0.indexes.map(\.name) }.map { $0.lowercased() }
        let triggerNames = tables.flatMap { $0.triggers.map(\.name) }.map { $0.lowercased() }
        guard Set(objectNames).count == objectNames.count, Set(triggerNames).count == triggerNames.count else {
            throw VersionedMigrationError.invalidHistory("Duplicate table, index or trigger names")
        }
        for table in tables {
            guard !table.name.lowercased().hasPrefix("__swiftstore_"), !table.name.lowercased().hasPrefix("sqlite_"),
                  !table.name.isEmpty, !table.columns.isEmpty,
                  Set(table.columns.map { $0.name.lowercased() }).count == table.columns.count else {
                throw VersionedMigrationError.invalidHistory("Invalid or reserved table: \(table.name)")
            }
        }
    }

    /// SQL for a fresh database, also used to validate the result of historical migrations.
    public var creationStatements: [String] {
        let diff = DatabaseDiff(tableDiffs: tables.map { SchemaDiff(current: nil, target: $0) })
        return MigrationSQLGenerator().generatePlan(from: diff).statements
    }

    /// Strict comparison includes constraints, defaults, generated columns, indexes and triggers.
    /// Extra tables are allowed (e.g. sync metadata); removed managed tables are checked by the runner.
    public func verify(on connection: SQLiteConnection) throws {
        try validate()
        var options = SQLiteConnection.Options()
        options.foreignKeys = false
        let reference = try SQLiteConnection(path: ":memory:", options: options)
        for sql in creationStatements { try reference.execute(sql) }
        for table in tables {
            let expected = try Self.definitions(table: table.name, on: reference)
            let actual = try Self.definitions(table: table.name, on: connection)
            guard expected == actual else {
                throw VersionedMigrationError.schemaMismatch(table.name)
            }
        }
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
