import Foundation
import Testing
import SwiftParser
import SwiftSyntax
import SwiftStoreCore
@testable import SwiftStoreMigrationTool

@Embedded
struct FTSMigrationBody {
    var text: String?
}

@Entity(tableName: "fts_migration_article")
struct FTSMigrationArticle {
    #FullTextIndex<Self>(\.title, \.body.text, name: "article_search", tokenizer: .porter)
    var id: UUIDV7 = UUIDV7()
    var title: String
    var body: FTSMigrationBody
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

private final class ExecuteSQLVisitor: SyntaxVisitor {
    var statements: [String] = []
    init() { super.init(viewMode: .sourceAccurate) }
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if node.calledExpression.trimmedDescription == "db.execute",
           let sql = node.arguments.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue {
            statements.append(sql)
        }
        return .visitChildren
    }
}

@Suite("Full-text migrations")
struct FullTextMigrationTests {
    private var indexed: SchemaSnapshot { SchemaSnapshot(entities: [FTSMigrationArticle.self]) }
    private var original: SchemaSnapshot {
        let table = indexed.tables[0]
        return SchemaSnapshot(tables: [TableSchema(name: table.name, columns: table.columns,
            indexes: table.indexes, triggers: table.triggers)])
    }
    private func migration(_ id: String, from old: SchemaSnapshot, to new: SchemaSnapshot) throws -> StoreMigration {
        let source = try MigrationSourceGenerator.source(symbol: "Migration_\(id)", from: old, to: new)
        #expect(!source.contains("#error"))
        let visitor = ExecuteSQLVisitor()
        visitor.walk(Parser.parse(source: source))
        let statements = visitor.statements
        return StoreMigration(id: id, checksum: id, target: new) { db in
            for sql in statements { try db.execute(sql) }
        }
    }

    @Test("Source extraction, runtime metadata and persisted history agree")
    func sourceParity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Model.swift")
        try #"""
        @Entity(tableName: "fts_migration_article")
        struct FTSMigrationArticle {
            #FullTextIndex<Self>(\.title, \.body.text, name: "article_search", tokenizer: .porter)
            var id: UUIDV7 = UUIDV7()
            var title: String
            var body: FTSMigrationBody
            var createdAt: Date = Date()
            var updatedAt: Date = Date()
        }
        """#.write(to: file, atomically: true, encoding: .utf8)
        let extracted = try EntitySourceSchema.extract(files: [file])
        #expect(extracted == indexed)
        let migrations = directory.appendingPathComponent("Migrations")
        try MigrationTool.generate(id: "001_initial", target: original, directory: migrations)
        // A new declaration must not pass check until its migration is generated.
        #expect(throws: (any Error).self) { try MigrationTool.check(target: indexed, directory: migrations) }
        try MigrationTool.generate(id: "002_search", target: extracted, directory: migrations)
        _ = try MigrationTool.check(target: indexed, directory: migrations)
        // Removing an index or changing its tokenizer also requires a migration.
        #expect(throws: (any Error).self) { try MigrationTool.check(target: original, directory: migrations) }
        let table = indexed.tables[0]
        let index = table.fullTextIndexes[0]
        let changed = SchemaSnapshot(tables: [TableSchema(name: table.name, columns: table.columns,
            indexes: table.indexes, triggers: table.triggers, fullTextIndexes: [
                FullTextIndexDefinition(name: index.name, columns: index.columns,
                    keyColumns: index.keyColumns, tokenizer: .unicode61)
            ])])
        #expect(throws: (any Error).self) { try MigrationTool.check(target: changed, directory: migrations) }
        #expect(try SchemaSnapshot.decode(indexed.json()) == indexed)
    }

    @Test("Adding, changing and removing indexes replays on upgrades and fresh installs")
    func lifecycle() throws {
        let one = try migration("001", from: .empty, to: original)
        let two = try migration("002", from: original, to: indexed)
        let previous = indexed.tables[0]
        let replacement = FullTextIndexDefinition(name: "renamed_search", columns: [FullTextColumn(name: "title", column: "title")])
        let changed = SchemaSnapshot(tables: [TableSchema(name: previous.name, columns: previous.columns,
            triggers: previous.triggers, fullTextIndexes: [replacement])])
        let three = try migration("003", from: indexed, to: changed)
        let four = try migration("004", from: changed, to: original)
        let db = try SQLiteConnection(path: ":memory:")
        try VersionedMigrator(connection: db, migrations: [one]).migrate()
        let article = FTSMigrationArticle(title: "running", body: FTSMigrationBody(text: "existing searchable content"))
        try article.insert(db)
        let uuid = try db.queryScalar("SELECT hex(id) FROM fts_migration_article", type: String.self)
        try VersionedMigrator(connection: db, migrations: [one, two]).migrate()
        #expect(try Query(FTSMigrationArticle.self).search("run").count(db) == 1)
        #expect(try Query(FTSMigrationArticle.self).search("searchable").count(db) == 1)
        try VersionedMigrator(connection: db, migrations: [one, two, three]).migrate()
        #expect(try db.queryScalar("SELECT count(*) FROM renamed_search WHERE renamed_search MATCH 'running'", type: Int.self) == 1)
        #expect(try !db.tableExists("article_search"))
        try VersionedMigrator(connection: db, migrations: [one, two, three, four]).migrate()
        #expect(try !db.tableExists("__swiftstore_fts_fts_migration_article_map"))
        #expect(try db.queryScalar("SELECT hex(id) FROM fts_migration_article", type: String.self) == uuid)
        #expect(try FTSMigrationArticle.all(db).count == 1)
        try VersionedMigrator(connection: db, migrations: [one, two, three, four]).migrate()
        let fresh = try SQLiteConnection(path: ":memory:")
        try VersionedMigrator(connection: fresh, migrations: [one, two, three, four]).migrate()
        try original.verify(on: fresh)
    }

    @Test("Failed index migration rolls back auxiliary objects and history")
    func rollback() throws {
        let one = try migration("001", from: .empty, to: original)
        let target = indexed
        let failing = StoreMigration(id: "002", checksum: "002", target: target) { db in
            for sql in FullTextSchema(table: target.tables[0]).creationStatements { try db.execute(sql) }
            try db.execute("INVALID SQL")
        }
        let db = try SQLiteConnection(path: ":memory:")
        try VersionedMigrator(connection: db, migrations: [one]).migrate()
        #expect(throws: (any Error).self) { try VersionedMigrator(connection: db, migrations: [one, failing]).migrate() }
        #expect(try !db.tableExists("article_search"))
        #expect(try !db.tableExists("__swiftstore_fts_fts_migration_article_map"))
        try original.verify(on: db)
        #expect(try VersionedMigrator(connection: db, migrations: [one, failing]).pendingMigrationIDs() == ["002"])
    }

    @Test("Invalid full-text declarations fail source extraction with diagnostics")
    func invalidDeclarations() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Model.swift")
        let declarations = [
            #"#FullTextIndex<Self>(\.amount)"#,
            #"#FullTextIndex<Self>(\.missing)"#,
            #"#FullTextIndex<Self>(\.title, \.title)"#,
            #"#FullTextIndex<Self>(\.title, tokenizer: .unknown)"#,
            #"#FullTextIndex<Self>(\.body.text[0])"#,
            #"#FullTextIndex<Self>()"#,
            #"#FullTextIndex<Self>(\.title, name: "sqlite_reserved")"#,
            #"#FullTextIndex<Self>(\.title) #FullTextIndex<Self>(\.title)"#
        ]
        for declaration in declarations {
            let source = """
                @Entity struct InvalidSearch {
                    \(declaration)
                    var id: UUIDV7 = UUIDV7()
                    var title: String
                    var amount: Int
                    var body: FTSMigrationBody
                    var createdAt: Date = Date()
                    var updatedAt: Date = Date()
                }
                """
            try source.write(to: file, atomically: true, encoding: .utf8)
            #expect(throws: (any Error).self) { try EntitySourceSchema.extract(files: [file]) }
        }
    }

    @Test("Missing cleanup and colliding names cannot silently pass verification")
    func invalidSchemas() throws {
        let one = try migration("001", from: .empty, to: indexed)
        let db = try SQLiteConnection(path: ":memory:")
        try VersionedMigrator(connection: db, migrations: [one]).migrate()
        let noCleanup = StoreMigration(id: "002", checksum: "002", target: original) { db in
            for name in FullTextSchema(table: indexed.tables[0]).triggerNames {
                try db.execute("DROP TRIGGER \"\(name)\"")
            }
        }
        #expect(throws: (any Error).self) { try VersionedMigrator(connection: db, migrations: [one, noCleanup]).migrate() }
        let collision = TableSchema(name: "article_search_data", columns: [ColumnSchema(name: "id", type: "INTEGER")])
        #expect(throws: (any Error).self) { try SchemaSnapshot(tables: indexed.tables + [collision]).validate() }
    }
}
