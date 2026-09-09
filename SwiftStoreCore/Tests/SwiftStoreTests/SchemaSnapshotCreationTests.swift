import Foundation
import Testing
@testable import SwiftStoreCore

@Suite("Schema snapshot creation")
struct SchemaSnapshotCreationTests {
    @Test("Fresh snapshots create generated columns and their indexes")
    func generatedColumns() throws {
        let store = try createTestStore()
        try store.migrate(entities: [MacroProfile.self])
        let profile = MacroProfile(bio: "sample", settings: UserSettings(theme: "dark", notifications: true))
        try store.connection.insert(profile)
        #expect(try store.connection.queryScalar("SELECT settings__theme FROM macro_profile", type: String.self) == "dark")
        #expect(try store.connection.queryScalar("SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_macro_profile_%'", type: Int.self) == 2)
        try SchemaSnapshot(entities: [MacroProfile.self]).verify(on: store.connection)
    }

    @Test("Fresh snapshots retain foreign key constraints")
    func foreignKeys() throws {
        let snapshot = SchemaSnapshot(tables: [
            TableSchema(name: "parent", columns: [ColumnSchema(name: "id", type: "INTEGER", isPrimaryKey: true)]),
            TableSchema(name: "child", columns: [ColumnSchema(name: "parent_id", type: "INTEGER")],
                foreignKeys: [ForeignKeySchema(column: "parent_id", referencesTable: "parent", referencesColumn: "id")])
        ])
        let connection = try SQLiteConnection(path: ":memory:")
        let initial = StoreMigration(id: "001_initial", checksum: "initial", target: snapshot) { db in
            for sql in snapshot.creationStatements { try db.execute(sql) }
        }
        try VersionedMigrator(connection: connection, migrations: [initial]).migrate()
        #expect(throws: (any Error).self) { try connection.execute("INSERT INTO child VALUES (1)") }
        try connection.execute("INSERT INTO parent VALUES (1)")
        try connection.execute("INSERT INTO child VALUES (1)")
        #expect(try connection.queryScalar("SELECT COUNT(*) FROM child", type: Int.self) == 1)
    }
}
