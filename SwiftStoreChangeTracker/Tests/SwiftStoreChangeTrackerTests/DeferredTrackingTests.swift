import Foundation
import Testing
@testable import SwiftStoreCore
@testable import SwiftStoreChangeTracker

@Suite("Deferred change tracking")
struct DeferredTrackingTests {
    private enum Failure: Error { case expected }

    private func fixture() throws -> (SQLiteConnection, ChangeTracker) {
        let db = try SQLiteConnection(path: ":memory:")
        let migrator = Migrator(connection: db, createUpdateTrigger: false)
        try migrator.apply(migrator.plan(for: [TestEntity.self]))
        let tracker = try ChangeTracker(connection: db, changeLogDbPath: ":memory:",
            deviceId: UUIDV7(),
            registeredEntities: [TestEntity.self], tickClock: { 1 })
        try tracker.start()
        return (db, tracker)
    }

    private func logs(_ tracker: ChangeTracker) throws -> [ChangeLog] {
        try ChangeLog.all(tracker.connection).sorted { $0.logicalClock < $1.logicalClock }
    }

    @Test("RETURNING is logged only at DONE; reset rolls back an unfinished write")
    func returning() throws {
        let (db, tracker) = try fixture()
        let stmt = try db.prepare("INSERT INTO test_entity (id, name, value) VALUES (X'01', 'one', 1) RETURNING name")
        #expect(try stmt.step())
        #expect(try logs(tracker).isEmpty)
        #expect(throws: (any Error).self) {
            try db.execute("INSERT INTO test_entity (id, name, value) VALUES (X'02', 'interleaved', 2)")
        }
        stmt.reset()
        #expect(try db.queryScalar("SELECT COUNT(*) FROM test_entity", type: Int64.self) == 0)
        #expect(try logs(tracker).isEmpty)

        // Use a real entity UUID so payload decoding is exercised.
        let entity = TestEntity(name: "complete", value: 3)
        let complete = try db.prepare("INSERT INTO test_entity (id, name, value) VALUES (?, 'complete', 3) RETURNING name")
        try complete.bind(1, entity.id.data)
        #expect(try complete.step())
        #expect(try logs(tracker).isEmpty)
        #expect(try !complete.step())
        #expect(try logs(tracker).count == 1)
    }

    @Test("Deallocating an unfinished RETURNING statement rolls back its events and data")
    func abandonedReturning() throws {
        let (db, tracker) = try fixture()
        do {
            let stmt = try db.prepare("INSERT INTO test_entity (id, name, value) VALUES (X'01', 'abandoned', 1) RETURNING name")
            #expect(try stmt.step())
        }
        #expect(try db.queryScalar("SELECT COUNT(*) FROM test_entity", type: Int64.self) == 0)
        #expect(try logs(tracker).isEmpty)
        try db.insert(TestEntity(name: "next", value: 2))
        #expect(try logs(tracker).count == 1)
    }

    @Test("Snapshots include AFTER trigger changes and SQL scripts flush each statement")
    func finalSnapshots() throws {
        let (db, tracker) = try fixture()
        try db.execute("""
            CREATE TRIGGER adjust_value AFTER INSERT ON test_entity BEGIN
                UPDATE test_entity SET value = 42 WHERE rowid = NEW.rowid;
            END
            """)
        let entity = TestEntity(name: "snapshot", value: 1)
        try db.insert(entity)
        for log in try logs(tracker) {
            let payload = try #require(log.payload)
            let row = try JSONDecoder().decode(TestEntity.self, from: Data(payload.utf8))
            #expect(row.value == 42)
        }
        try db.execute("UPDATE test_entity SET name = 'last'; DELETE FROM test_entity;")
        let changes = try logs(tracker)
        #expect(changes.last?.operation == .delete)
        let update = try #require(changes.dropLast().last?.payload)
        #expect(try JSONDecoder().decode(TestEntity.self, from: Data(update.utf8)).name == "last")
    }

    @Test("Remote writes never enter the outbox and source is restored after errors")
    func source() throws {
        let (db, tracker) = try fixture()
        let entity = TestEntity(name: "download", value: 1)
        #expect(throws: Failure.self) {
            try db.withWriteSource(.remote) {
                try db.insert(entity)
                try db.execute("UPDATE test_entity SET name = 'remote update'")
                throw Failure.expected
            }
        }
        #expect(db.writeSource == .local)
        #expect(try logs(tracker).isEmpty)
        try db.execute("UPDATE test_entity SET name = 'local edit'")
        #expect(try logs(tracker).count == 1)
        try db.withWriteSource(.remote) { try db.execute("DELETE FROM test_entity") }
        #expect(try logs(tracker).count == 1)
        try db.insert(TestEntity(name: "local insert", value: 2))
        #expect(try logs(tracker).count == 2)
    }

    @Test("Deferred delivery keeps the hook-time origin after the connection scope changes",
        arguments: [SQLiteWriteSource.local, .remote])
    func sourceAcrossReturningSteps(origin: SQLiteWriteSource) throws {
        let (db, tracker) = try fixture()
        let entity = TestEntity(name: "cross-scope", value: 1)
        let statement = try db.prepare("INSERT INTO test_entity (id, name, value) VALUES (?, 'cross-scope', 1) RETURNING name")
        try statement.bind(1, entity.id.data)

        // SQLite performs the write and calls the native hook on this first
        // step, but our handler deliberately waits for SQLITE_DONE.
        let hasRow = try db.withWriteSource(origin) { try statement.step() }
        #expect(hasRow)
        #expect(db.writeSource == .local)
        #expect(try logs(tracker).isEmpty)

        // Deliver under the opposite scope: a remote event must not become
        // local, and a captured local event must not be suppressed as remote.
        let deliverySource: SQLiteWriteSource = origin == .local ? .remote : .local
        let hasMoreRows = try db.withWriteSource(deliverySource) { try statement.step() }
        #expect(!hasMoreRows)
        let expectedCount = origin == .local ? 1 : 0
        #expect(try logs(tracker).count == expectedCount)
        #expect(try TestEntity.all(db).first?.name == "cross-scope")

        // Restoring either scope must also leave subsequent local edits tracked.
        try db.execute("UPDATE test_entity SET name = 'later local edit'")
        #expect(try logs(tracker).count == expectedCount + 1)
    }

    @Test("Nested rollback removes only the rolled-back log rows")
    func nestedRollback() throws {
        let (db, tracker) = try fixture()
        try db.transaction {
            try db.insert(TestEntity(name: "before", value: 1))
            #expect(throws: Failure.self) {
                try db.transaction {
                    try db.insert(TestEntity(name: "rolled back", value: 2))
                    throw Failure.expected
                }
            }
            try db.insert(TestEntity(name: "after", value: 3))
        }
        #expect(try logs(tracker).count == 2)
        #expect(try TestEntity.count(db) == 2)
        #expect(!db.isInTransaction)
        #expect(throws: Failure.self) {
            try db.transaction {
                try db.execute("DELETE FROM test_entity")
                throw Failure.expected
            }
        }
        #expect(try logs(tracker).count == 2)
        #expect(try TestEntity.count(db) == 2)
    }

    @Test("Statement and changelog failures roll back business data without phantom events")
    func failures() throws {
        let (db, tracker) = try fixture()
        let entity = TestEntity(name: "original", value: 1)
        try db.insert(entity)
        #expect(throws: (any Error).self) {
            try db.execute("UPDATE OR FAIL test_entity SET name = NULL")
        }
        #expect(try logs(tracker).count == 1)
        try tracker.connection.execute("""
            CREATE TRIGGER reject_log BEFORE INSERT ON change_log BEGIN
                SELECT RAISE(ABORT, 'test log failure');
            END
            """)
        #expect(throws: (any Error).self) { try db.execute("UPDATE test_entity SET name = 'lost'") }
        #expect(try TestEntity.all(db).first?.name == "original")
        #expect(try logs(tracker).count == 1)
        try tracker.connection.execute("DROP TRIGGER reject_log")
        try db.execute("UPDATE test_entity SET name = 'recovered'")
        #expect(try logs(tracker).count == 2)
    }
}
