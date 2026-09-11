import Foundation
import Testing
import SwiftStoreCore
@testable import SwiftStoreChangeTracker

@Suite("Same-database append-only changelog")
struct ChangeLogMigrationTests {
    @Test("Bootstrap preserves timestamps and repeats safely")
    func bootstrap() throws {
        let db = try SQLiteConnection(path: ":memory:")
        try migrateTestEntities([TestEntity.self], on: db)
        let row = TestEntity(name: "existing", value: 1, updatedAt: Date(timeIntervalSince1970: 42))
        try db.insert(row)
        let tracker = try ChangeTracker(connection: db, deviceId: UUIDV7(), registeredEntities: [TestEntity.self])
        try tracker.captureExistingRows(); try tracker.captureExistingRows()
        let events = try ChangeLog.all(db)
        #expect(events.count == 1 && events[0].seq == 1)
        let decoded = try JSONDecoder().decode(TestEntity.self, from: Data(try #require(events.first?.payload).utf8))
        #expect(decoded.updatedAt == row.updatedAt)
        #expect(tracker.connection === db)
    }

    @Test("UPDATE, DELETE and REPLACE cannot rewrite a committed event")
    func immutable() throws {
        let db = try SQLiteConnection(path: ":memory:")
        try migrateTestEntities([TestEntity.self], on: db)
        let tracker = try ChangeTracker(connection: db, deviceId: UUIDV7(), registeredEntities: [TestEntity.self])
        try tracker.start(); try db.insert(TestEntity(name: "one", value: 1))
        let log = try #require(try ChangeLog.first(db))
        #expect(throws: (any Error).self) { try db.execute("UPDATE __swiftstore_change_log SET logical_clock=1") }
        #expect(throws: (any Error).self) { try db.execute("DELETE FROM __swiftstore_change_log") }
        #expect(throws: (any Error).self) { try db.execute("INSERT OR REPLACE INTO __swiftstore_change_log SELECT * FROM __swiftstore_change_log") }
        #expect(try ChangeLog.first(db)?.id == log.id)
    }

    @Test("Raw BEGIN, SAVEPOINT and ROLLBACK control data and log together")
    func rawTransactions() throws {
        let db = try SQLiteConnection(path: ":memory:")
        try migrateTestEntities([TestEntity.self], on: db)
        let tracker = try ChangeTracker(connection: db, deviceId: UUIDV7(), registeredEntities: [TestEntity.self])
        try tracker.start()
        try db.execute("BEGIN")
        try db.insert(TestEntity(name: "before", value: 1))
        try db.execute("SAVEPOINT user_savepoint")
        try db.insert(TestEntity(name: "discard", value: 2))
        try db.execute("ROLLBACK TO user_savepoint; RELEASE user_savepoint")
        try db.transaction { try db.insert(TestEntity(name: "nested helper", value: 3)) }
        #expect(try ChangeLog.count(db) == 2)
        try db.execute("ROLLBACK")
        #expect(try ChangeLog.count(db) == 0 && TestEntity.count(db) == 0)
        #expect(!db.isInTransaction)
    }
}
