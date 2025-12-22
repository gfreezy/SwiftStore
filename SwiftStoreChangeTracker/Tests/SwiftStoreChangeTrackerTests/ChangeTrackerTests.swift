import Testing
import Foundation
@testable import SwiftStoreChangeTracker
@testable import SwiftStoreCore

// MARK: - Test Entity (Manual implementation for reliable encoding)
@Entity
struct TestEntity {
    let id: UUIDV4
    var name: String
    var value: Int
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - Test Helpers

/// Fixed device ID for testing
let testDeviceId = UUIDV4()

/// Helper to verify sync key contains expected entity id
func verifySyncKeyContainsId(_ syncKey: Data, expectedId: UUIDV4) -> Bool {
    let values = SyncKeyEncoder.decode(syncKey)
    guard values.count == 1, case .blob(let data) = values[0] else {
        return false
    }
    return data == expectedId.data
}

func createTestConnection() throws -> SQLiteConnection {
    let tempPath = NSTemporaryDirectory() + "swiftstore_sync_test_\(UUID().uuidString).sqlite"
    return try SQLiteConnection(path: tempPath)
}

func createAndMigrateTestDatabase(trackDeletes: Bool = true) throws -> (connection: SQLiteConnection, dbPath: String) {
    let tempPath = NSTemporaryDirectory() + "swiftstore_sync_test_\(UUID().uuidString).sqlite"
    let connection = try SQLiteConnection(path: tempPath)

    // Migrate TestEntity table (disable update trigger to avoid double-counting in tests)
    let migrator = Migrator(connection: connection, trackDeletes: trackDeletes, createUpdateTrigger: false)
    let plan = try migrator.plan(for: [TestEntity.self])
    try migrator.apply(plan)

    return (connection, tempPath)
}

// MARK: - ChangeTracker Tests

@Suite("ChangeTracker Tests")
struct ChangeTrackerTests {

    @Test("ChangeTracker captures INSERT operation")
    func testCaptureInsert() throws {
        let (connection, dbPath) = try createAndMigrateTestDatabase()

        var clockValue: Int64 = 0
        let changeTracker = try ChangeTracker(
            connection: connection,
            changeLogDbPath: dbPath + ".changelog",
            deviceId: testDeviceId,
            pendingDeletesTable: Migrator.pendingDeletesTableName,
            registeredEntities: [TestEntity.self],
            tickClock: { clockValue += 1; return clockValue }
        )

        try changeTracker.start()

        // Insert entity
        let entity = TestEntity(
            id: UUIDV4(),
            name: "Test",
            value: 42,
            createdAt: Date(),
            updatedAt: Date()
        )
        try connection.insert(entity)

        changeTracker.stop()

        // Verify change log
        let reader = try ChangeTrackerReader(changeLogDbPath: dbPath + ".changelog", deviceId: testDeviceId)
        let changes = try reader.changesSince(clock: 0)

        #expect(changes.count == 1)
        #expect(changes[0].entityType == "test_entity")
        #expect(verifySyncKeyContainsId(changes[0].syncKey, expectedId: entity.id))
        #expect(changes[0].operation == .insert)
        #expect(changes[0].deviceId == testDeviceId)
        #expect(changes[0].logicalClock == 1)
        #expect(changes[0].payload != nil)
    }

    @Test("ChangeTracker captures UPDATE operation")
    func testCaptureUpdate() throws {
        let (connection, dbPath) = try createAndMigrateTestDatabase()

        // Insert entity before starting tracker
        var entity = TestEntity(
            id: UUIDV4(),
            name: "Original",
            value: 1,
            createdAt: Date(),
            updatedAt: Date()
        )
        try connection.insert(entity)

        var clockValue: Int64 = 0
        let changeTracker = try ChangeTracker(
            connection: connection,
            changeLogDbPath: dbPath + ".changelog",
            deviceId: testDeviceId,
            pendingDeletesTable: Migrator.pendingDeletesTableName,
            registeredEntities: [TestEntity.self],
            tickClock: { clockValue += 1; return clockValue }
        )

        try changeTracker.start()

        // Update entity
        entity.name = "Updated"
        entity.value = 100
        try connection.update(entity)

        changeTracker.stop()

        // Verify change log
        let reader = try ChangeTrackerReader(changeLogDbPath: dbPath + ".changelog", deviceId: testDeviceId)
        let changes = try reader.changesSince(clock: 0)

        #expect(changes.count == 1)
        #expect(changes[0].entityType == "test_entity")
        #expect(verifySyncKeyContainsId(changes[0].syncKey, expectedId: entity.id))
        #expect(changes[0].operation == .update)
        #expect(changes[0].payload != nil)

        // Verify payload contains updated data
        if let payload = changes[0].payload,
           let data = payload.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            #expect(json["name"] as? String == "Updated")
            #expect(json["value"] as? Int64 == 100)
        }
    }

    @Test("ChangeTracker captures DELETE operation via pending_deletes trigger")
    func testCaptureDelete() throws {
        let (connection, dbPath) = try createAndMigrateTestDatabase(trackDeletes: true)

        // Insert entity before starting tracker
        let entity = TestEntity(
            id: UUIDV4(),
            name: "ToDelete",
            value: 999,
            createdAt: Date(),
            updatedAt: Date()
        )
        try connection.insert(entity)

        var clockValue: Int64 = 0
        let changeTracker = try ChangeTracker(
            connection: connection,
            changeLogDbPath: dbPath + ".changelog",
            deviceId: testDeviceId,
            pendingDeletesTable: Migrator.pendingDeletesTableName,
            registeredEntities: [TestEntity.self],
            tickClock: { clockValue += 1; return clockValue }
        )

        try changeTracker.start()

        // Delete entity (this triggers the delete trigger which inserts into pending_deletes)
        let deleteSQL: SQL = "DELETE FROM test_entity WHERE id = \(entity.id)"
        try connection.execute(deleteSQL)

        changeTracker.stop()

        // Verify change log
        let reader = try ChangeTrackerReader(changeLogDbPath: dbPath + ".changelog", deviceId: testDeviceId)
        let changes = try reader.changesSince(clock: 0)

        #expect(changes.count == 1)
        #expect(changes[0].entityType == "test_entity")
        #expect(verifySyncKeyContainsId(changes[0].syncKey, expectedId: entity.id))
        #expect(changes[0].operation == .delete)
        #expect(changes[0].payload == nil) // Delete operations don't have payload
    }

    @Test("ChangeTracker captures multiple operations in sequence")
    func testCaptureMultipleOperations() throws {
        let (connection, dbPath) = try createAndMigrateTestDatabase(trackDeletes: true)

        var clockValue: Int64 = 0
        let changeTracker = try ChangeTracker(
            connection: connection,
            changeLogDbPath: dbPath + ".changelog",
            deviceId: testDeviceId,
            pendingDeletesTable: Migrator.pendingDeletesTableName,
            registeredEntities: [TestEntity.self],
            tickClock: { clockValue += 1; return clockValue }
        )

        try changeTracker.start()

        // 1. Insert
        var entity = TestEntity(
            id: UUIDV4(),
            name: "First",
            value: 1,
            createdAt: Date(),
            updatedAt: Date()
        )
        try connection.insert(entity)

        // 2. Update
        entity.name = "Updated"
        entity.value = 2
        try connection.update(entity)

        // 3. Delete
        let deleteSQL: SQL = "DELETE FROM test_entity WHERE id = \(entity.id)"
        try connection.execute(deleteSQL)

        changeTracker.stop()

        // Verify all changes captured
        let reader = try ChangeTrackerReader(changeLogDbPath: dbPath + ".changelog", deviceId: testDeviceId)
        let changes = try reader.changesSince(clock: 0)

        #expect(changes.count == 3)

        // Check operations in order (by logical clock)
        let sortedChanges = changes.sorted { $0.logicalClock < $1.logicalClock }

        #expect(sortedChanges[0].operation == .insert)
        #expect(sortedChanges[0].logicalClock == 1)

        #expect(sortedChanges[1].operation == .update)
        #expect(sortedChanges[1].logicalClock == 2)

        #expect(sortedChanges[2].operation == .delete)
        #expect(sortedChanges[2].logicalClock == 3)

        // All changes for same entity
        for change in changes {
            #expect(verifySyncKeyContainsId(change.syncKey, expectedId: entity.id))
            #expect(change.entityType == "test_entity")
        }
    }

    @Test("ChangeTracker ignores unregistered entities")
    func testIgnoreUnregisteredEntities() throws {
        let (connection, dbPath) = try createAndMigrateTestDatabase()

        // Create another table that is not registered
        try connection.execute("""
            CREATE TABLE unregistered_table (
                id BLOB PRIMARY KEY,
                data TEXT
            )
        """)

        var clockValue: Int64 = 0
        let changeTracker = try ChangeTracker(
            connection: connection,
            changeLogDbPath: dbPath + ".changelog",
            deviceId: testDeviceId,
            pendingDeletesTable: Migrator.pendingDeletesTableName,
            registeredEntities: [TestEntity.self], // Only TestEntity registered
            tickClock: { clockValue += 1; return clockValue }
        )

        try changeTracker.start()

        // Insert into unregistered table
        let id = UUIDV4()
        try connection.execute("INSERT INTO unregistered_table (id, data) VALUES (?, 'test')", values: [.blob(id.data)])

        // Insert into registered table
        let entity = TestEntity(
            id: UUIDV4(),
            name: "Registered",
            value: 1,
            createdAt: Date(),
            updatedAt: Date()
        )
        try connection.insert(entity)

        changeTracker.stop()

        // Verify only registered entity change is captured
        let reader = try ChangeTrackerReader(changeLogDbPath: dbPath + ".changelog", deviceId: testDeviceId)
        let changes = try reader.changesSince(clock: 0)

        #expect(changes.count == 1)
        #expect(changes[0].entityType == "test_entity")
    }

    @Test("ChangeTracker clears pending_deletes on start")
    func testClearsPendingDeletesOnStart() throws {
        let (connection, dbPath) = try createAndMigrateTestDatabase(trackDeletes: true)

        // Manually insert stale pending delete using the new sync_key_json schema
        let staleId = UUIDV4()
        let syncKeyJson = "{\"id\": \"\(staleId.data.map { String(format: "%02X", $0) }.joined())\"}"
        try connection.execute("""
            INSERT INTO \(Migrator.pendingDeletesTableName) (table_name, sync_key_json)
            VALUES ('test_entity', ?)
        """, values: [.text(syncKeyJson)])

        // Verify it exists
        let countBefore = try connection.prepare("SELECT COUNT(*) FROM \(Migrator.pendingDeletesTableName)")
        _ = try countBefore.step()
        #expect(countBefore.columnInt64(0) == 1)

        var clockValue: Int64 = 0
        let changeTracker = try ChangeTracker(
            connection: connection,
            changeLogDbPath: dbPath + ".changelog",
            deviceId: testDeviceId,
            pendingDeletesTable: Migrator.pendingDeletesTableName,
            registeredEntities: [TestEntity.self],
            tickClock: { clockValue += 1; return clockValue }
        )

        // Start should clear the table
        try changeTracker.start()

        // Verify pending_deletes is cleared
        let countAfter = try connection.prepare("SELECT COUNT(*) FROM \(Migrator.pendingDeletesTableName)")
        _ = try countAfter.step()
        #expect(countAfter.columnInt64(0) == 0)

        changeTracker.stop()
    }

    @Test("ChangeTracker payload contains correct entity data")
    func testPayloadContainsCorrectData() throws {
        let (connection, dbPath) = try createAndMigrateTestDatabase()

        var clockValue: Int64 = 0
        let changeTracker = try ChangeTracker(
            connection: connection,
            changeLogDbPath: dbPath + ".changelog",
            deviceId: testDeviceId,
            pendingDeletesTable: Migrator.pendingDeletesTableName,
            registeredEntities: [TestEntity.self],
            tickClock: { clockValue += 1; return clockValue }
        )

        try changeTracker.start()

        let entity = TestEntity(
            id: UUIDV4(),
            name: "PayloadTest",
            value: 12345,
            createdAt: Date(),
            updatedAt: Date()
        )
        try connection.insert(entity)

        changeTracker.stop()

        // Verify payload
        let reader = try ChangeTrackerReader(changeLogDbPath: dbPath + ".changelog", deviceId: testDeviceId)
        let changes = try reader.changesSince(clock: 0)

        #expect(changes.count == 1)

        guard let payload = changes[0].payload,
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            #expect(Bool(false), "Failed to parse payload")
            return
        }

        #expect(json["id"] as? String == entity.id.uuidString)
        #expect(json["name"] as? String == "PayloadTest")
        #expect(json["value"] as? Int64 == 12345)
        #expect(json["createdAt"] != nil)
        #expect(json["updatedAt"] != nil)
    }

    @Test("ChangeTracker stops capturing after stop()")
    func testStopsCaptureAfterStop() throws {
        let (connection, dbPath) = try createAndMigrateTestDatabase()

        var clockValue: Int64 = 0
        let changeTracker = try ChangeTracker(
            connection: connection,
            changeLogDbPath: dbPath + ".changelog",
            deviceId: testDeviceId,
            pendingDeletesTable: Migrator.pendingDeletesTableName,
            registeredEntities: [TestEntity.self],
            tickClock: { clockValue += 1; return clockValue }
        )

        try changeTracker.start()

        // Insert while tracking
        let entity1 = TestEntity(
            id: UUIDV4(),
            name: "Before",
            value: 1,
            createdAt: Date(),
            updatedAt: Date()
        )
        try connection.insert(entity1)

        changeTracker.stop()

        // Insert after stop
        let entity2 = TestEntity(
            id: UUIDV4(),
            name: "After",
            value: 2,
            createdAt: Date(),
            updatedAt: Date()
        )
        try connection.insert(entity2)

        // Verify only first insert captured
        let reader = try ChangeTrackerReader(changeLogDbPath: dbPath + ".changelog", deviceId: testDeviceId)
        let changes = try reader.changesSince(clock: 0)

        #expect(changes.count == 1)
        #expect(verifySyncKeyContainsId(changes[0].syncKey, expectedId: entity1.id))
    }

    @Test("ChangeTracker changesSince returns changes after clock value")
    func testChangesSinceFilter() throws {
        let (connection, dbPath) = try createAndMigrateTestDatabase()

        var clockValue: Int64 = 0
        let changeTracker = try ChangeTracker(
            connection: connection,
            changeLogDbPath: dbPath + ".changelog",
            deviceId: testDeviceId,
            pendingDeletesTable: Migrator.pendingDeletesTableName,
            registeredEntities: [TestEntity.self],
            tickClock: { clockValue += 1; return clockValue }
        )

        try changeTracker.start()

        // Insert 3 entities
        for i in 1...3 {
            let entity = TestEntity(
                id: UUIDV4(),
                name: "Entity\(i)",
                value: i,
                createdAt: Date(),
                updatedAt: Date()
            )
            try connection.insert(entity)
        }

        changeTracker.stop()

        let reader = try ChangeTrackerReader(changeLogDbPath: dbPath + ".changelog", deviceId: testDeviceId)

        // Get all changes
        let allChanges = try reader.changesSince(clock: 0)
        #expect(allChanges.count == 3)

        // Get changes since clock 1 (should get 2 changes: clock 2 and 3)
        let changesAfter1 = try reader.changesSince(clock: 1)
        #expect(changesAfter1.count == 2)

        // Get changes since clock 2 (should get 1 change: clock 3)
        let changesAfter2 = try reader.changesSince(clock: 2)
        #expect(changesAfter2.count == 1)

        // Get changes since clock 3 (should get 0 changes)
        let changesAfter3 = try reader.changesSince(clock: 3)
        #expect(changesAfter3.count == 0)
    }
}
