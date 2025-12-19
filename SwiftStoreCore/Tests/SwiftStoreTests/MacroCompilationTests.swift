import Testing
import Foundation
import SwiftStoreProtocols
@testable import SwiftStoreCore
import SwiftStoreMacros

// MARK: - Test Entities using @Entity macro

/// Simple entity to test basic macro expansion
@Entity
struct MacroUser {
    let id: UUIDV4
    var name: String
    var email: String
    var age: Int?
    let createdAt: Date
    let updatedAt: Date
}

/// Entity with nested Codable type
struct UserSettings: Codable, Sendable {
    var theme: String
    var notifications: Bool
}

@Entity
struct MacroProfile {
    let id: UUIDV4
    var bio: String
    var settings: UserSettings
    let createdAt: Date
    let updatedAt: Date
}

/// Enum for testing Codable enum storage (stored as JSON)
enum TaskStatus: String, Codable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed
}

@Entity
struct MacroTask {
    let id: UUIDV4
    var title: String
    var status: TaskStatus
    let createdAt: Date
    let updatedAt: Date
}

/// Integer enum for testing Codable enum storage
enum Priority: Int, Codable, Sendable {
    case low = 0
    case medium = 1
    case high = 2
}

@Entity
struct MacroItem {
    let id: UUIDV4
    var name: String
    var priority: Priority
    let createdAt: Date
    let updatedAt: Date
}

/// Optional enum for testing Codable enum storage
@Entity
struct MacroOrder {
    let id: UUIDV4
    var orderNumber: String
    var status: TaskStatus?
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - Compilation Tests

@Suite("Macro Compilation Tests")
struct MacroCompilationTests {

    @Test("MacroUser entity compiles and CRUD works")
    func testMacroUserCRUD() throws {
        let store = try createTestStore()
        try store.migrate(entities: [MacroUser.self])

        // Create
        let user = MacroUser(
            id: UUIDV4(),
            name: "Alice",
            email: "alice@example.com",
            age: 25,
            createdAt: Date(),
            updatedAt: Date()
        )
        try store.connection.insert(user)

        // Read
        let fetched = try store.connection.get(MacroUser.self, id: user.id)
        #expect(fetched != nil)
        #expect(fetched?.name == "Alice")
        #expect(fetched?.email == "alice@example.com")
        #expect(fetched?.age == 25)

        // Update
        var updated = fetched!
        updated.name = "Alice Updated"
        updated.age = 26
        try store.connection.update(updated)

        let fetchedAfterUpdate = try store.connection.get(MacroUser.self, id: user.id)
        #expect(fetchedAfterUpdate?.name == "Alice Updated")
        #expect(fetchedAfterUpdate?.age == 26)

        // Delete
        try store.connection.delete(updated)
        let fetchedAfterDelete = try store.connection.get(MacroUser.self, id: user.id)
        #expect(fetchedAfterDelete == nil)
    }

    @Test("MacroUser with nil optional field")
    func testMacroUserNilOptional() throws {
        let store = try createTestStore()
        try store.migrate(entities: [MacroUser.self])

        let user = MacroUser(
            id: UUIDV4(),
            name: "Bob",
            email: "bob@example.com",
            age: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        try store.connection.insert(user)

        let fetched = try store.connection.get(MacroUser.self, id: user.id)
        #expect(fetched != nil)
        #expect(fetched?.age == nil)
    }

    @Test("MacroProfile with nested Codable type")
    func testMacroProfileNestedType() throws {
        let store = try createTestStore()
        try store.migrate(entities: [MacroProfile.self])

        let settings = UserSettings(theme: "dark", notifications: true)
        let profile = MacroProfile(
            id: UUIDV4(),
            bio: "Hello world",
            settings: settings,
            createdAt: Date(),
            updatedAt: Date()
        )
        try store.connection.insert(profile)

        let fetched = try store.connection.get(MacroProfile.self, id: profile.id)
        #expect(fetched != nil)
        #expect(fetched?.bio == "Hello world")
        #expect(fetched?.settings.theme == "dark")
        #expect(fetched?.settings.notifications == true)

        // Update nested type
        var updated = fetched!
        updated.settings = UserSettings(theme: "light", notifications: false)
        try store.connection.update(updated)

        let fetchedAfterUpdate = try store.connection.get(MacroProfile.self, id: profile.id)
        #expect(fetchedAfterUpdate?.settings.theme == "light")
        #expect(fetchedAfterUpdate?.settings.notifications == false)
    }

    @Test("MacroTask with Codable String enum")
    func testMacroTaskCodableEnum() throws {
        let store = try createTestStore()
        try store.migrate(entities: [MacroTask.self])

        let task = MacroTask(
            id: UUIDV4(),
            title: "Test Task",
            status: .pending,
            createdAt: Date(),
            updatedAt: Date()
        )
        try store.connection.insert(task)

        let fetched = try store.connection.get(MacroTask.self, id: task.id)
        #expect(fetched != nil)
        #expect(fetched?.title == "Test Task")
        #expect(fetched?.status == .pending)

        // Update status
        var updated = fetched!
        updated.status = .inProgress
        try store.connection.update(updated)

        let fetchedAfterUpdate = try store.connection.get(MacroTask.self, id: task.id)
        #expect(fetchedAfterUpdate?.status == .inProgress)

        // Update to completed
        updated.status = .completed
        try store.connection.update(updated)

        let fetchedCompleted = try store.connection.get(MacroTask.self, id: task.id)
        #expect(fetchedCompleted?.status == .completed)
    }

    @Test("MacroItem with Codable Integer enum")
    func testMacroItemCodableIntegerEnum() throws {
        let store = try createTestStore()
        try store.migrate(entities: [MacroItem.self])

        let item = MacroItem(
            id: UUIDV4(),
            name: "Test Item",
            priority: .low,
            createdAt: Date(),
            updatedAt: Date()
        )
        try store.connection.insert(item)

        let fetched = try store.connection.get(MacroItem.self, id: item.id)
        #expect(fetched != nil)
        #expect(fetched?.name == "Test Item")
        #expect(fetched?.priority == .low)

        // Update priority
        var updated = fetched!
        updated.priority = .high
        try store.connection.update(updated)

        let fetchedAfterUpdate = try store.connection.get(MacroItem.self, id: item.id)
        #expect(fetchedAfterUpdate?.priority == .high)
    }

    @Test("MacroOrder with optional Codable enum")
    func testMacroOrderOptionalCodableEnum() throws {
        let store = try createTestStore()
        try store.migrate(entities: [MacroOrder.self])

        // Test with nil status
        let orderWithNil = MacroOrder(
            id: UUIDV4(),
            orderNumber: "ORD-001",
            status: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        try store.connection.insert(orderWithNil)

        let fetchedNil = try store.connection.get(MacroOrder.self, id: orderWithNil.id)
        #expect(fetchedNil != nil)
        #expect(fetchedNil?.status == nil)

        // Test with non-nil status
        let orderWithStatus = MacroOrder(
            id: UUIDV4(),
            orderNumber: "ORD-002",
            status: .pending,
            createdAt: Date(),
            updatedAt: Date()
        )
        try store.connection.insert(orderWithStatus)

        let fetchedWithStatus = try store.connection.get(MacroOrder.self, id: orderWithStatus.id)
        #expect(fetchedWithStatus != nil)
        #expect(fetchedWithStatus?.status == .pending)

        // Update from nil to non-nil
        var updated = fetchedNil!
        updated.status = .completed
        try store.connection.update(updated)

        let fetchedAfterUpdate = try store.connection.get(MacroOrder.self, id: orderWithNil.id)
        #expect(fetchedAfterUpdate?.status == .completed)
    }

    @Test("Query with macro-generated entities")
    func testQueryWithMacroEntities() throws {
        let store = try createTestStore()
        try store.migrate(entities: [MacroUser.self])

        // Insert multiple users
        for i in 0..<5 {
            let user = MacroUser(
                id: UUIDV4(),
                name: "User\(i)",
                email: "user\(i)@example.com",
                age: 20 + i,
                createdAt: Date(),
                updatedAt: Date()
            )
            try store.connection.insert(user)
        }

        // Test filter with EntityProtocol extension
        let filtered = try MacroUser
            .filter { $0.age >= 22 }
            .all(store.connection)
        #expect(filtered.count == 3)

        // Test order
        let ordered = try MacroUser
            .orderDesc(by: \MacroUser.age)
            .all(store.connection)
        #expect(ordered.first?.age == 24)

        // Test limit
        let limited = try MacroUser
            .limit(2)
            .all(store.connection)
        #expect(limited.count == 2)

        // Test count
        let count = try MacroUser.query().count(store.connection)
        #expect(count == 5)
    }

    @Test("Table name conversion works correctly")
    func testTableNameConversion() {
        // Verify CamelCase to snake_case conversion
        #expect(MacroUser.tableName == "macro_user")
        #expect(MacroProfile.tableName == "macro_profile")
        #expect(MacroTask.tableName == "macro_task")
        #expect(MacroItem.tableName == "macro_item")
        #expect(MacroOrder.tableName == "macro_order")
    }

    @Test("Columns are generated correctly")
    func testColumnsGenerated() {
        // MacroUser columns
        let userColumns = MacroUser.columns
        #expect(userColumns.count == 6)
        #expect(userColumns[0].name == "id")
        #expect(userColumns[0].primaryKey == true)
        #expect(userColumns[1].name == "name")
        #expect(userColumns[2].name == "email")
        #expect(userColumns[3].name == "age")
        #expect(userColumns[3].nullable == true)
        #expect(userColumns[4].name == "created_at")
        #expect(userColumns[5].name == "updated_at")

        // MacroProfile with nested type
        let profileColumns = MacroProfile.columns
        #expect(profileColumns[2].name == "settings")
        #expect(profileColumns[2].isJSONEncoded == true)

        // MacroTask with Codable enum (stored as JSON)
        let taskColumns = MacroTask.columns
        #expect(taskColumns[2].name == "status")
        #expect(taskColumns[2].type == .text)
        #expect(taskColumns[2].isJSONEncoded == true)

        // MacroItem with Codable enum (stored as JSON)
        let itemColumns = MacroItem.columns
        #expect(itemColumns[2].name == "priority")
        #expect(itemColumns[2].type == .text)
        #expect(itemColumns[2].isJSONEncoded == true)
    }
}
