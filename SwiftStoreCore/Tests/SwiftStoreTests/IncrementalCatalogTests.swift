import Foundation
import Testing
import SwiftStoreCore

@Suite("Runtime incremental migration catalog")
struct IncrementalCatalogTests {
    private func catalog() throws -> StoreMigrationCatalog {
        let people = TableSchema(name: "people", columns: [
            ColumnSchema(name: "id", type: "INTEGER", isPrimaryKey: true),
            ColumnSchema(name: "name", type: "TEXT", isNullable: true)
        ], indexes: [IndexSchema(name: "people_name", columns: ["name"])])
        let cache = TableSchema(name: "cache", columns: [ColumnSchema(name: "value", type: "TEXT")])
        let posts = TableSchema(name: "posts", columns: [ColumnSchema(name: "message", type: "TEXT")])
        let initial = SchemaSnapshot(tables: [people, cache, posts])
        let renamed = TableSchema(name: "people", columns: [people.columns[0],
            ColumnSchema(name: "display_name", type: "TEXT", isNullable: true)])
        var result = StoreMigrationCatalog()
        try result.append(id: "001_initial", delta: SchemaDelta(tables: initial.tables)) { db in
            for sql in initial.creationStatements { try db.execute(sql) }
            try db.execute("INSERT INTO people VALUES (1, ' Ada ')")
            try db.execute("INSERT INTO posts VALUES ('untouched')")
        }
        try result.append(id: "002_rename", delta: SchemaDelta(tables: [renamed])) { db in
            try db.execute("DROP INDEX people_name")
            try db.execute("ALTER TABLE people RENAME COLUMN name TO display_name")
        }
        try result.append(id: "003_data") { db in
            try db.execute("UPDATE people SET display_name = trim(display_name) || '!'")
        }
        try result.append(id: "004_drop", delta: SchemaDelta(droppedTables: ["cache"])) { db in
            try db.execute("DROP TABLE cache")
        }
        return result
    }

    @Test("Replacement, inheritance, deletion and data-only targets are resolved at runtime")
    func targets() throws {
        let steps = try catalog().migrations
        #expect(steps[0].target.tables.map(\.name) == ["cache", "people", "posts"])
        #expect(steps[0].target.tables[1].indexes.count == 1)
        #expect(steps[1].target.tables[1].indexes.isEmpty)
        #expect(steps[1].target.tables[1].columns.map(\.name) == ["id", "display_name"])
        #expect(steps[1].target.tables[2] == steps[0].target.tables[2])
        #expect(steps[2].target == steps[1].target)
        #expect(steps[3].target.tables == Array(steps[2].target.tables.dropFirst()))
    }

    @Test("Fresh installs and upgrades from every intermediate version preserve data")
    func upgrades() throws {
        let steps = try catalog().migrations
        for prefix in 0...steps.count {
            let db = try SQLiteConnection(path: ":memory:")
            if prefix > 0 {
                try VersionedMigrator(connection: db, migrations: Array(steps.prefix(prefix))).migrate()
            }
            let runner = VersionedMigrator(connection: db, migrations: steps)
            #expect(try runner.pendingMigrationIDs() == steps.dropFirst(prefix).map(\.id))
            try runner.migrate()
            try runner.migrate()
            #expect(try !db.tableExists("cache"))
            #expect(try db.queryScalar("SELECT display_name FROM people", type: String.self) == "Ada!")
            #expect(try db.queryScalar("SELECT message FROM posts", type: String.self) == "untouched")
            #expect(try db.queryScalar("SELECT COUNT(*) FROM __swiftstore_migrations", type: Int.self) == 4)
            let columns = try db.prepare("PRAGMA table_info(__swiftstore_migrations)")
            var names = [String]()
            while try columns.step() { names.append(columns.columnString(1) ?? "") }
            #expect(names == ["position", "id", "applied_at"])
        }
    }

    @Test("Every reconstructed target can be explicitly adopted as a baseline")
    func baselines() throws {
        let steps = try catalog().migrations
        for index in steps.indices {
            let db = try SQLiteConnection(path: ":memory:")
            for sql in steps[index].target.creationStatements { try db.execute(sql) }
            let runner = VersionedMigrator(connection: db, migrations: steps)
            try runner.adoptBaseline(through: steps[index].id)
            #expect(try runner.pendingMigrationIDs() == steps.dropFirst(index + 1).map(\.id))
            try runner.migrate()
        }
        let db = try SQLiteConnection(path: ":memory:")
        for sql in steps[0].target.creationStatements { try db.execute(sql) }
        #expect(throws: VersionedMigrationError.self) {
            try VersionedMigrator(connection: db, migrations: steps).adoptBaseline(through: steps[1].id)
        }
        #expect(try !db.tableExists("__swiftstore_migrations"))
    }

    @Test("Invalid deltas fail without appending a partial step")
    func invalidDelta() throws {
        var result = try catalog()
        let invalid = [
            SchemaDelta(droppedTables: ["missing"]),
            SchemaDelta(droppedTables: ["people", "people"]),
            SchemaDelta(tables: result.migrations.last!.target.tables, droppedTables: ["people"]),
            try SchemaDelta.decode(Data(#"{"formatVersion":2}"#.utf8))
        ]
        for delta in invalid {
            #expect(throws: VersionedMigrationError.self) {
                try result.append(id: "005_invalid", delta: delta) { _ in }
            }
            #expect(result.migrations.count == 4)
        }
    }

    @Test("The runner still verifies each intermediate target and removal")
    func failedStep() throws {
        let steps = try catalog().migrations
        for failingIndex in [1, 3] {
            var broken = steps
            broken[failingIndex] = StoreMigration(id: steps[failingIndex].id, target: steps[failingIndex].target) { _ in }
            let db = try SQLiteConnection(path: ":memory:")
            #expect(throws: VersionedMigrationError.self) {
                try VersionedMigrator(connection: db, migrations: broken).migrate()
            }
            #expect(try !db.tableExists("people"))
            #expect(try !db.tableExists("__swiftstore_migrations"))
        }
    }
}
