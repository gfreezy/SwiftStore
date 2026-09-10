import Foundation
import Testing
@testable import SwiftStoreCore

@Suite("Versioned migrations")
struct VersionedMigrationTests {
    private var v1: SchemaSnapshot { SchemaSnapshot(tables: [TableSchema(name: "people", columns: [
        ColumnSchema(name: "id", type: "INTEGER", isPrimaryKey: true),
        ColumnSchema(name: "name", type: "TEXT", isNullable: true)
    ])]) }
    private var v2: SchemaSnapshot { SchemaSnapshot(tables: [TableSchema(name: "people", columns: [
        ColumnSchema(name: "id", type: "INTEGER", isPrimaryKey: true),
        ColumnSchema(name: "display_name", type: "TEXT", isNullable: true)
    ])]) }
    private var steps: [StoreMigration] {
        let first = v1
        return [
            StoreMigration(id: "001", target: v1) { db in
                for sql in first.creationStatements { try db.execute(sql) }
            },
            StoreMigration(id: "002", target: v2) { db in
                try db.execute("ALTER TABLE people RENAME COLUMN name TO display_name")
                try db.execute("UPDATE people SET display_name = trim(display_name)")
            },
            StoreMigration(id: "003", target: v2) { db in
                try db.execute("UPDATE people SET display_name = display_name || '!' ")
            }
        ]
    }

    @Test("Cross-version upgrade preserves data and each body executes once")
    func upgrade() throws {
        let db = try SQLiteConnection(path: ":memory:")
        try VersionedMigrator(connection: db, migrations: Array(steps.prefix(1))).migrate()
        try db.execute("INSERT INTO people VALUES (1, ' Ada ')")
        let runner = VersionedMigrator(connection: db, migrations: steps)
        #expect(try runner.pendingMigrationIDs() == ["002", "003"])
        try runner.migrate()
        try runner.migrate()
        #expect(try db.queryScalar("SELECT display_name FROM people", type: String.self) == "Ada!")
        #expect(try runner.pendingMigrationIDs().isEmpty)
    }

    @Test("Fresh database replays the entire history; preview writes nothing")
    func fresh() throws {
        let db = try SQLiteConnection(path: ":memory:")
        let runner = VersionedMigrator(connection: db, migrations: steps)
        #expect(try runner.pendingMigrationIDs() == ["001", "002", "003"])
        #expect(try !db.tableExists("__swiftstore_migrations"))
        try runner.migrate()
        try v2.verify(on: db)
    }

    @Test("Failure rolls back schema, data and history together")
    func rollback() throws {
        let db = try SQLiteConnection(path: ":memory:")
        let initial = Array(steps.prefix(1))
        try VersionedMigrator(connection: db, migrations: initial).migrate()
        try db.execute("INSERT INTO people VALUES (1, ' Ada ')")
        let broken = StoreMigration(id: "004", target: v2) { db in
            try db.execute("UPDATE people SET display_name = 'lost'")
            try db.execute("INVALID SQL")
        }
        #expect(throws: (any Error).self) {
            try VersionedMigrator(connection: db, migrations: steps + [broken]).migrate()
        }
        try v1.verify(on: db)
        #expect(try db.queryScalar("SELECT name FROM people", type: String.self) == " Ada ")
        #expect(try VersionedMigrator(connection: db, migrations: steps).pendingMigrationIDs() == ["002", "003"])
    }

    @Test("Renamed, removed, reordered and duplicate histories are rejected")
    func invalidHistory() throws {
        let db = try SQLiteConnection(path: ":memory:")
        try VersionedMigrator(connection: db, migrations: steps).migrate()
        let changed = StoreMigration(id: "003_renamed", target: v2) { _ in }
        for history in [Array(steps.prefix(2)), [steps[1], steps[0], steps[2]], steps + [steps[2]], Array(steps.prefix(2)) + [changed]] {
            #expect(throws: VersionedMigrationError.self) {
                try VersionedMigrator(connection: db, migrations: history).migrate()
            }
        }
    }

    @Test("Baseline is explicit and validates schema before recording")
    func baseline() throws {
        let db = try SQLiteConnection(path: ":memory:")
        for sql in v1.creationStatements { try db.execute(sql) }
        try db.execute("INSERT INTO people VALUES (1, ' Ada ')")
        let runner = VersionedMigrator(connection: db, migrations: steps)
        #expect(throws: VersionedMigrationError.self) { try runner.migrate() }
        #expect(throws: VersionedMigrationError.self) { try runner.adoptBaseline(through: "002") }
        #expect(try !db.tableExists("__swiftstore_migrations"))
        try runner.adoptBaseline(through: "001")
        try runner.migrate()
        #expect(try db.queryScalar("SELECT display_name FROM people", type: String.self) == "Ada!")
    }

    @Test("A body that leaves the wrong schema is rolled back")
    func incompleteBody() throws {
        let db = try SQLiteConnection(path: ":memory:")
        let wrong = StoreMigration(id: "001", target: v1) { db in
            try db.execute("CREATE TABLE people (id INTEGER NOT NULL PRIMARY KEY, name TEXT NOT NULL)")
        }
        #expect(throws: VersionedMigrationError.self) {
            try VersionedMigrator(connection: db, migrations: [wrong]).migrate()
        }
        #expect(try !db.tableExists("people"))
        #expect(try !db.tableExists("__swiftstore_migrations"))
    }

    @Test("Mixed-case table renames preserve data on fresh installs and upgrades")
    func mixedCaseTableRename() throws {
        let initial = v1
        let renamed = SchemaSnapshot(tables: [TableSchema(name: "Members", columns: initial.tables[0].columns)])
        let history = [
            StoreMigration(id: "001", target: initial) { db in
                for sql in initial.creationStatements { try db.execute(sql) }
                try db.execute("INSERT INTO people VALUES (1, 'Ada')")
            },
            StoreMigration(id: "002", target: renamed) { db in
                try db.execute("ALTER TABLE people RENAME TO Members")
            }
        ]
        for upgrading in [false, true] {
            let db = try SQLiteConnection(path: ":memory:")
            if upgrading {
                try VersionedMigrator(connection: db, migrations: Array(history.prefix(1))).migrate()
            }
            let runner = VersionedMigrator(connection: db, migrations: history)
            try runner.migrate()
            try runner.migrate()
            #expect(try runner.pendingMigrationIDs().isEmpty)
            #expect(try !db.tableExists("people"))
            #expect(try db.queryScalar("SELECT name FROM Members WHERE id = 1", type: String.self) == "Ada")
        }
    }

    @Test("Legacy default literal case is not normalized as an identifier")
    func defaultLiteralCase() throws {
        for literal in ["ABC", "\"ABC\""] {
            let db = try SQLiteConnection(path: ":memory:")
            let target = SchemaSnapshot(tables: [TableSchema(name: "defaults", columns: [
                ColumnSchema(name: "value", type: "TEXT", defaultValue: literal)
            ])])
            try db.execute("CREATE TABLE defaults (value TEXT NOT NULL DEFAULT \(literal.lowercased()))")
            #expect(throws: VersionedMigrationError.self) { try target.verify(on: db) }
        }
    }

    @Test("Schema validation preserves literals and detects external drift")
    func drift() throws {
        let db = try SQLiteConnection(path: ":memory:")
        try VersionedMigrator(connection: db, migrations: steps).migrate()
        try db.execute("CREATE INDEX external_index ON people(display_name)")
        #expect(throws: VersionedMigrationError.self) {
            try VersionedMigrator(connection: db, migrations: steps).migrate()
        }
        let quoted = SchemaSnapshot(tables: [TableSchema(name: "quotes", columns: [
            ColumnSchema(name: "value", type: "TEXT", defaultValue: "'A  B'")
        ])])
        try db.execute("CREATE TABLE quotes (value TEXT NOT NULL DEFAULT 'A B')")
        #expect(throws: VersionedMigrationError.self) { try quoted.verify(on: db) }
    }
}
