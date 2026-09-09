import Foundation
import Testing
@testable import SwiftStoreCore
@testable import SwiftStoreChangeTracker

@Entity
private struct SnapshotMembership {
    #SyncKey<SnapshotMembership>(\.team, \.member)
    var team: String
    var member: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

@Suite("Pre-update snapshot tracking")
struct PreUpdateTrackingTests {
    private enum Failure: Error { case rollback }

    private func setup(updateTrigger: Bool = false) throws -> (SQLiteConnection, ChangeTracker) {
        let db = try SQLiteConnection(path: ":memory:")
        try migrateTestEntities([TestEntity.self], on: db, includeFixtureTriggers: updateTrigger)
        let tracker = try ChangeTracker(connection: db, changeLogDbPath: ":memory:", deviceId: UUIDV7(),
            registeredEntities: [TestEntity.self], tickClock: { 1 })
        try tracker.start()
        return (db, tracker)
    }

    private func logs(_ tracker: ChangeTracker) throws -> [ChangeLog] {
        try ChangeLog.all(tracker.connection).sorted { $0.logicalClock < $1.logicalClock }
    }

    @Test("Deletion needs no trigger or intermediate table, including DELETE without a WHERE clause")
    func directDeletion() throws {
        let (db, tracker) = try setup()
        let one = TestEntity(name: "one", value: 1), two = TestEntity(name: "two", value: 2)
        try db.insert(one)
        try db.insert(two)
        #expect(try !db.tableExists("__swiftstore_pending_deletes"))
        let before = Date()
        try db.execute("DELETE FROM test_entity")
        let deleted = try logs(tracker).filter { $0.operation == .delete }
        #expect(deleted.count == 2)
        #expect(deleted.allSatisfy { $0.payload == nil && $0.createdAt >= before })
        #expect(deleted.contains { verifySyncKeyContainsId($0.syncKey, expectedId: one.id) })
        #expect(deleted.contains { verifySyncKeyContainsId($0.syncKey, expectedId: two.id) })
    }

    @Test("Automatic timestamp updates coalesce into one final row snapshot")
    func timestampTrigger() throws {
        let (db, tracker) = try setup(updateTrigger: true)
        var entity = TestEntity(name: "before", value: 1)
        entity.updatedAt = Date(timeIntervalSince1970: 1)
        try db.insert(entity)
        try db.execute("UPDATE test_entity SET name = 'after'")
        let changes = try logs(tracker)
        #expect(changes.count == 2)
        let payload = try #require(changes.last?.payload)
        let row = try JSONDecoder().decode(TestEntity.self, from: Data(payload.utf8))
        #expect(row.name == "after")
        #expect(try row.updatedAt == TestEntity.all(db).first?.updatedAt)
        #expect(row.updatedAt > entity.updatedAt)
    }

    @Test("REPLACE captures the implicit deletion even with recursive triggers disabled")
    func replacement() throws {
        let (db, tracker) = try setup()
        try db.execute("PRAGMA recursive_triggers = OFF")
        try db.execute("CREATE UNIQUE INDEX unique_name ON test_entity(name)")
        let old = TestEntity(name: "same", value: 1), new = TestEntity(name: "same", value: 2)
        try db.insert(old)
        try db.execute("INSERT OR REPLACE INTO test_entity (id, name, value) VALUES (?, 'same', 2)", values: [.blob(new.id.data)])
        let changes = try logs(tracker)
        #expect(changes.count == 3)
        #expect(changes[1].operation == .delete)
        #expect(verifySyncKeyContainsId(changes[1].syncKey, expectedId: old.id))
        #expect(changes[2].operation == .insert)
        #expect(verifySyncKeyContainsId(changes[2].syncKey, expectedId: new.id))
    }

    @Test("Changing a sync key deletes the old identity and publishes the new identity")
    func changedIdentity() throws {
        let (db, tracker) = try setup()
        let entity = TestEntity(name: "moved", value: 1), newID = UUIDV7()
        try db.insert(entity)
        try db.execute("UPDATE test_entity SET id = ?", values: [.blob(newID.data)])
        let changes = try logs(tracker)
        #expect(changes.count == 3)
        #expect(changes[1].operation == .delete)
        #expect(verifySyncKeyContainsId(changes[1].syncKey, expectedId: entity.id))
        #expect(verifySyncKeyContainsId(changes[2].syncKey, expectedId: newID))
        let row = try JSONDecoder().decode(TestEntity.self, from: Data(try #require(changes[2].payload).utf8))
        #expect(row.id == newID)
    }

    @Test("Snapshots own embedded-NUL text and blobs after the callback returns")
    func ownedValues() throws {
        let (db, tracker) = try setup()
        let entity = TestEntity(name: "before\0after 😀", value: 7)
        try db.execute("INSERT INTO test_entity (id, name, value) VALUES (?, 'before' || char(0) || 'after 😀', 7)",
            values: [.blob(entity.id.data)])
        let row = try JSONDecoder().decode(TestEntity.self, from: Data(try #require(logs(tracker).last?.payload).utf8))
        #expect(row.name == entity.name)
        #expect(row.id == entity.id)
    }

    @Test("A local scope inside a remote transaction rolls back with the business transaction")
    func nestedSourceRollback() throws {
        let (db, tracker) = try setup()
        #expect(throws: Failure.self) {
            try db.withWriteSource(.remote) {
                try db.transaction {
                    try db.withWriteSource(.local) { try db.insert(TestEntity(name: "local", value: 1)) }
                    throw Failure.rollback
                }
            }
        }
        #expect(try logs(tracker).isEmpty)
        #expect(try TestEntity.count(db) == 0)
    }

    @Test("A prepared statement reused after reset snapshots its new execution source")
    func sourceOnReuse() throws {
        let (db, tracker) = try setup()
        let entity = TestEntity(name: "existing", value: 1)
        try db.withWriteSource(.remote) { try db.insert(entity) }
        let stmt = try db.prepare("UPDATE test_entity SET value = value + 1 RETURNING value")
        _ = try db.withWriteSource(.remote) { try stmt.step() }
        stmt.reset() // Remote write and captured origin both get discarded.
        while try stmt.step() {}
        #expect(try logs(tracker).count == 1)
        #expect(try TestEntity.all(db).first?.value == 2)
    }

    @Test("Column snapshots follow entity order even when the physical schema differs")
    func reorderedColumns() throws {
        let db = try SQLiteConnection(path: ":memory:")
        try db.execute("""
            CREATE TABLE test_entity (value INTEGER, unused TEXT, updated_at REAL,
                id BLOB PRIMARY KEY, name TEXT, created_at REAL)
            """)
        let tracker = try ChangeTracker(connection: db, changeLogDbPath: ":memory:", deviceId: UUIDV7(),
            registeredEntities: [TestEntity.self], tickClock: { 1 })
        try tracker.start()
        let id = UUIDV7()
        try db.execute("INSERT INTO test_entity VALUES (42, 'ignored', 100.125, ?, 'correct', 1)", values: [.blob(id.data)])
        let change = try #require(logs(tracker).last)
        let row = try JSONDecoder().decode(TestEntity.self, from: Data(try #require(change.payload).utf8))
        #expect(row.id == id && row.name == "correct" && row.value == 42)
        #expect(row.updatedAt.timeIntervalSince1970 == 100.125)
    }
    @Test("Composite sync keys work without declaring a PRIMARY KEY")
    func compositeKey() throws {
        let db = try SQLiteConnection(path: ":memory:")
        try migrateTestEntities([SnapshotMembership.self], on: db, includeFixtureTriggers: true)
        let tracker = try ChangeTracker(connection: db, changeLogDbPath: ":memory:", deviceId: UUIDV7(),
            registeredEntities: [SnapshotMembership.self], tickClock: { 1 })
        try tracker.start()
        try db.insert(SnapshotMembership(team: "one", member: "alice"))
        try db.execute("UPDATE snapshot_membership SET team = 'two'")
        let changes = try logs(tracker)
        #expect(changes.count == 3)
        #expect(changes[1].operation == .delete)
        #expect(SyncKeyEncoder.decode(changes[1].syncKey) == [.text("one"), .text("alice")])
        #expect(SyncKeyEncoder.decode(changes[2].syncKey) == [.text("two"), .text("alice")])
    }

    @Test("Foreign-key cascades capture deleted children under the originating source")
    func cascade() throws {
        let db = try SQLiteConnection(path: ":memory:")
        try db.execute("""
            CREATE TABLE parent (id INTEGER PRIMARY KEY);
            INSERT INTO parent VALUES (1);
            CREATE TABLE test_entity (id BLOB PRIMARY KEY, name TEXT,
                value INTEGER REFERENCES parent(id) ON DELETE CASCADE,
                created_at REAL DEFAULT 1, updated_at REAL DEFAULT 1);
            """)
        let tracker = try ChangeTracker(connection: db, changeLogDbPath: ":memory:", deviceId: UUIDV7(),
            registeredEntities: [TestEntity.self], tickClock: { 1 })
        try tracker.start()
        try db.insert(TestEntity(name: "child", value: 1))
        try db.execute("DELETE FROM parent")
        #expect(try logs(tracker).last?.operation == .delete)
        try db.execute("INSERT INTO parent VALUES (1)")
        try db.insert(TestEntity(name: "remote deletion", value: 1))
        _ = try db.withWriteSource(.remote) { try db.execute("DELETE FROM parent") }
        #expect(try logs(tracker).count == 3)
        #expect(try TestEntity.count(db) == 0)
    }

    @Test("An AFTER trigger can delete an inserted row without requiring a later row lookup")
    func deletedBeforeDone() throws {
        let (db, tracker) = try setup()
        try db.execute("""
            CREATE TRIGGER remove_insert AFTER INSERT ON test_entity BEGIN
                DELETE FROM test_entity WHERE rowid = NEW.rowid;
            END
            """)
        let entity = TestEntity(name: "removed", value: 1)
        try db.insert(entity)
        let changes = try logs(tracker)
        #expect(changes.count == 1)
        #expect(changes[0].operation == .delete && changes[0].payload == nil)
        #expect(verifySyncKeyContainsId(changes[0].syncKey, expectedId: entity.id))
        #expect(try TestEntity.count(db) == 0)
    }

}
