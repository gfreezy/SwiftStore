import Testing
import Foundation
import SwiftStoreProtocols
@testable import SwiftStoreCore
import SwiftStoreMacros

// MARK: - Test Entities using @Entity macro

/// Simple entity to test basic macro expansion
@Entity
struct MacroUser {
    var id: UUIDV7 = UUIDV7()
    var name: String
    var email: String
    var age: Int?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

/// Entity with nested Codable type (must use @Embedded for compile-time validation)
@Embedded
struct UserSettings: Codable, Sendable {
    var theme: String = "light"
    var notifications: Bool = true
}

@Entity
struct MacroProfile {
    #Index<Self>(\.settings.theme, \.settings.notifications)
    #Index<Self>(\.settings.theme, \.id)
    var id: UUIDV7 = UUIDV7()
    var bio: String
    var settings: UserSettings
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

/// Enum for testing Codable enum storage (stored as JSON)
@Embedded
enum TaskStatus: String, Codable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed
}

@Entity
struct MacroTask {
    var id: UUIDV7 = UUIDV7()
    var title: String
    var status: TaskStatus
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

/// Integer enum for testing Codable enum storage
@Embedded
enum Priority: Int, Codable, Sendable {
    case low = 0
    case medium = 1
    case high = 2
}

@Entity
struct MacroItem {
    var id: UUIDV7 = UUIDV7()
    var name: String
    var priority: Priority
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

/// Optional enum for testing Codable enum storage
@Entity
struct MacroOrder {
    var id: UUIDV7 = UUIDV7()
    var orderNumber: String
    var status: TaskStatus?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

// MARK: - SyncKey Test Entities

/// Entity with single field sync key (no id field)
@Entity
struct SyncKeyUser {
    #SyncKey<SyncKeyUser>(\.email)
    var email: String
    var name: String
    var age: Int?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

/// Entity with composite sync key (no id field)
@Entity
struct SyncKeyEmployee {
    #SyncKey<SyncKeyEmployee>(\.companyCode, \.employeeCode)
    var companyCode: String
    var employeeCode: String
    var name: String
    var department: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

/// Entity with property default values
@Entity
struct UserPosts {
    #SyncKey<UserPosts>(\.slug)
    var slug: String
    var title: String = ""
    var content: String = ""
    var views: Int = 0
    var isPublished: Bool = false
    var tags: [String] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

// MARK: - @Embedded Test Structs

/// Simple Codable struct with all default values
@Embedded
struct DefaultSettings: Codable {
    var theme: String = "light"
    var fontSize: Int = 14
    var notifications: Bool = true
}

/// Codable struct with mixed required and default fields
@Embedded
struct DefaultUserPrefs: Codable {
    var userId: String           // Required field (no default)
    var theme: String = "light"  // Has default
    var language: String = "en"  // Has default
}

/// Codable struct with optional fields
@Embedded
struct DefaultConfig: Codable {
    var apiUrl: String = "https://api.example.com"
    var timeout: Int = 30
    var debugMode: Bool?  // Optional, no default needed
}

/// Comprehensive test struct covering all common types with defaults
@Embedded
struct AllTypesWithDefaults: Codable {
    // String types
    var stringEmpty: String = ""
    var stringValue: String = "hello"

    // Integer types
    var intZero: Int = 0
    var intValue: Int = 42
    var int8Value: Int8 = 8
    var int16Value: Int16 = 16
    var int32Value: Int32 = 32
    var int64Value: Int64 = 64

    // Unsigned integer types
    var uintZero: UInt = 0
    var uintValue: UInt = 100

    // Floating point types
    var doubleZero: Double = 0.0
    var doubleValue: Double = 3.14
    var floatValue: Float = 2.5

    // Boolean types
    var boolFalse: Bool = false
    var boolTrue: Bool = true

    // Collection types
    var arrayEmpty: [String] = []
    var arrayValue: [Int] = [1, 2, 3]
    var dictEmpty: [String: Int] = [:]
    var dictValue: [String: String] = ["key": "value"]
}

/// Test struct with optional types (nil defaults)
@Embedded
struct AllOptionalTypes: Codable {
    var optString: String?
    var optInt: Int?
    var optDouble: Double?
    var optBool: Bool?
    var optArray: [String]?
    var optDict: [String: Int]?
}

/// Test struct with mixed optional and non-optional
@Embedded
struct MixedOptionalTypes: Codable {
    var required: String                    // Required, throws if missing
    var withDefault: String = "default"    // Has default
    var optional: String?                   // Optional, nil if missing
    var optionalWithNil: Int? = nil        // Explicit nil default
}

/// Nested struct for testing
@Embedded
struct NestedAddress: Codable, Equatable {
    var street: String = ""
    var city: String = ""
    var zip: String = ""
}

/// Enum with @Embedded for nested usage
@Embedded
enum Status: String, Codable {
    case active
    case inactive
    case pending
}

/// Test struct with nested @Embedded type
@Embedded
struct PersonWithAddress: Codable {
    var name: String = ""
    var address: NestedAddress = NestedAddress()
}

/// Comprehensive struct with nested types, collections, and enums
@Embedded
struct ComplexNestedTypes: Codable {
    // Nested struct
    var address: NestedAddress = NestedAddress()
    var optionalAddress: NestedAddress?

    // Enum
    var status: Status = .active
    var optionalStatus: Status?

    // Array of primitives
    var tags: [String] = []
    var scores: [Int] = [0, 0, 0]

    // Array of nested struct
    var addresses: [NestedAddress] = [NestedAddress(), NestedAddress()]

    // Dictionary with primitives
    var metadata: [String: String] = ["key": "value"]
    var counts: [String: Int] = ["default": 0]

    // Optional collections
    var optionalTags: [String]?
    var optionalMetadata: [String: String]?
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
            id: UUIDV7(),
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
            id: UUIDV7(),
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
            id: UUIDV7(),
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
            id: UUIDV7(),
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
            id: UUIDV7(),
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
            id: UUIDV7(),
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
            id: UUIDV7(),
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
                id: UUIDV7(),
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

        // Test count
        let count = try MacroUser.filter().count(store.connection)
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

    @Test("Virtual columns for nested index are generated correctly")
    func testVirtualColumnsForNestedIndex() {
        // MacroProfile has indexes on nested properties:
        // #Index<Self>(\.settings.theme, \.settings.notifications)
        // #Index<Self>(\.settings.theme, \.id)

        let profileColumns = MacroProfile.columns

        // Find virtual columns (they have generatedAs != nil)
        let virtualColumns = profileColumns.filter { $0.generatedAs != nil }

        // Should have 2 virtual columns: settings__theme and settings__notifications
        #expect(virtualColumns.count == 2)

        // Verify settings__theme virtual column
        let themeColumn = virtualColumns.first { $0.name == "settings__theme" }
        #expect(themeColumn != nil)
        #expect(themeColumn?.type == .text)
        #expect(themeColumn?.nullable == true)
        #expect(themeColumn?.generatedAs == "json_extract(settings, '$.theme')")

        // Verify settings__notifications virtual column
        let notificationsColumn = virtualColumns.first { $0.name == "settings__notifications" }
        #expect(notificationsColumn != nil)
        #expect(notificationsColumn?.type == .text)
        #expect(notificationsColumn?.nullable == true)
        #expect(notificationsColumn?.generatedAs == "json_extract(settings, '$.notifications')")

        // Verify indexes
        let profileIndexes = MacroProfile.indexes
        #expect(profileIndexes.count == 2)

        // First index: settings__theme, settings__notifications
        let firstIndex = profileIndexes.first { $0.columns.contains("settings__theme") && $0.columns.contains("settings__notifications") }
        #expect(firstIndex != nil)
        #expect(firstIndex?.columns == ["settings__theme", "settings__notifications"])

        // Second index: settings__theme, id
        let secondIndex = profileIndexes.first { $0.columns.contains("settings__theme") && $0.columns.contains("id") }
        #expect(secondIndex != nil)
        #expect(secondIndex?.columns == ["settings__theme", "id"])
    }

    @Test("Virtual column index works in database")
    func testVirtualColumnIndexInDatabase() throws {
        let store = try createTestStore()
        try store.migrate(entities: [MacroProfile.self])

        // Insert some profiles with different settings
        let profiles = [
            MacroProfile(id: UUIDV7(), bio: "Bio 1", settings: UserSettings(theme: "dark", notifications: true), createdAt: Date(), updatedAt: Date()),
            MacroProfile(id: UUIDV7(), bio: "Bio 2", settings: UserSettings(theme: "light", notifications: false), createdAt: Date(), updatedAt: Date()),
            MacroProfile(id: UUIDV7(), bio: "Bio 3", settings: UserSettings(theme: "dark", notifications: false), createdAt: Date(), updatedAt: Date()),
        ]

        for profile in profiles {
            try store.connection.insert(profile)
        }

        // Verify index exists by checking sqlite_master
        let indexSQL = "SELECT sql FROM sqlite_master WHERE type='index' AND tbl_name='macro_profile'"
        let stmt = try store.connection.prepare(indexSQL)
        var indexSQLs: [String] = []
        while try stmt.step() {
            if let sql = stmt.columnString(0) {
                indexSQLs.append(sql)
            }
        }

        // Should have indexes on virtual columns
        let hasThemeNotificationsIndex = indexSQLs.contains { $0.contains("settings__theme") && $0.contains("settings__notifications") }
        let hasThemeIdIndex = indexSQLs.contains { $0.contains("settings__theme") && $0.contains("id") }

        #expect(hasThemeNotificationsIndex)
        #expect(hasThemeIdIndex)
    }

    // MARK: - SyncKey Tests

    @Test("SyncKeyUser entity with single field sync key")
    func testSyncKeyUserCRUD() throws {
        let store = try createTestStore()
        try store.migrate(entities: [SyncKeyUser.self])

        // Create
        let user = SyncKeyUser(
            email: "alice@example.com",
            name: "Alice",
            age: 25,
            createdAt: Date(),
            updatedAt: Date()
        )
        try store.connection.insert(user)

        // Read using query (no get by id since there's no id field)
        let fetched = try SyncKeyUser
            .filter { $0.email == "alice@example.com" }
            .first(store.connection)
        #expect(fetched != nil)
        #expect(fetched?.name == "Alice")
        #expect(fetched?.email == "alice@example.com")
        #expect(fetched?.age == 25)

        // Delete using query
        let deleted = try SyncKeyUser
            .filter { $0.email == "alice@example.com" }
            .deleteAll(store.connection)
        #expect(deleted == 1)

        let fetchedAfterDelete = try SyncKeyUser
            .filter { $0.email == "alice@example.com" }
            .first(store.connection)
        #expect(fetchedAfterDelete == nil)
    }

    @Test("SyncKeyEmployee entity with composite sync key")
    func testSyncKeyEmployeeCRUD() throws {
        let store = try createTestStore()
        try store.migrate(entities: [SyncKeyEmployee.self])

        // Create employees in different companies with same employee code
        let emp1 = SyncKeyEmployee(
            companyCode: "ACME",
            employeeCode: "E001",
            name: "Alice",
            department: "Engineering",
            createdAt: Date(),
            updatedAt: Date()
        )
        let emp2 = SyncKeyEmployee(
            companyCode: "CORP",
            employeeCode: "E001",
            name: "Bob",
            department: "Sales",
            createdAt: Date(),
            updatedAt: Date()
        )
        try store.connection.insert(emp1)
        try store.connection.insert(emp2)

        // Both should exist (different composite keys)
        let count = try SyncKeyEmployee.filter().count(store.connection)
        #expect(count == 2)

        // Query by composite key
        let acmeEmployee = try SyncKeyEmployee
            .filter { $0.companyCode == "ACME" && $0.employeeCode == "E001" }
            .first(store.connection)
        #expect(acmeEmployee?.name == "Alice")

        let corpEmployee = try SyncKeyEmployee
            .filter { $0.companyCode == "CORP" && $0.employeeCode == "E001" }
            .first(store.connection)
        #expect(corpEmployee?.name == "Bob")
    }

    @Test("SyncKey columns are generated correctly")
    func testSyncKeyColumnsGenerated() {
        // SyncKeyUser - single field sync key
        #expect(SyncKeyUser.syncKeyColumns == ["email"])

        // Verify email is primary key (single column sync key uses column-level PRIMARY KEY)
        let emailColumn = SyncKeyUser.columns.first { $0.name == "email" }
        #expect(emailColumn?.primaryKey == true)

        // SyncKeyEmployee - composite sync key
        #expect(SyncKeyEmployee.syncKeyColumns == ["company_code", "employee_code"])

        // For composite sync keys, individual columns are NOT marked as primary key
        // (SQLite doesn't support multiple PRIMARY KEY columns, uniqueness is enforced via unique index)
        let companyColumn = SyncKeyEmployee.columns.first { $0.name == "company_code" }
        let employeeColumn = SyncKeyEmployee.columns.first { $0.name == "employee_code" }
        #expect(companyColumn?.primaryKey == false)
        #expect(employeeColumn?.primaryKey == false)
    }

    @Test("SyncKey creates unique index")
    func testSyncKeyCreatesUniqueIndex() throws {
        let store = try createTestStore()
        try store.migrate(entities: [SyncKeyUser.self, SyncKeyEmployee.self])

        // Check SyncKeyUser index
        let userIndexes = SyncKeyUser.indexes
        let userSyncKeyIndex = userIndexes.first { $0.name.contains("sync_key") }
        #expect(userSyncKeyIndex != nil)
        #expect(userSyncKeyIndex?.columns == ["email"])
        #expect(userSyncKeyIndex?.unique == true)

        // Check SyncKeyEmployee index
        let empIndexes = SyncKeyEmployee.indexes
        let empSyncKeyIndex = empIndexes.first { $0.name.contains("sync_key") }
        #expect(empSyncKeyIndex != nil)
        #expect(empSyncKeyIndex?.columns == ["company_code", "employee_code"])
        #expect(empSyncKeyIndex?.unique == true)

        // Verify indexes exist in database
        let indexSQL = "SELECT name, sql FROM sqlite_master WHERE type='index' AND (tbl_name='sync_key_user' OR tbl_name='sync_key_employee')"
        let stmt = try store.connection.prepare(indexSQL)
        var indexNames: [String] = []
        while try stmt.step() {
            if let name = stmt.columnString(0) {
                indexNames.append(name)
            }
        }

        let hasUserSyncKeyIndex = indexNames.contains { $0.contains("sync_key_user") && $0.contains("sync_key") }
        let hasEmpSyncKeyIndex = indexNames.contains { $0.contains("sync_key_employee") && $0.contains("sync_key") }
        #expect(hasUserSyncKeyIndex)
        #expect(hasEmpSyncKeyIndex)
    }

    @Test("SyncKey entity is not Identifiable")
    func testSyncKeyEntityNotIdentifiable() {
        // SyncKeyUser should not conform to Identifiable since it has no id field
        // This is a compile-time check - if this compiles, SyncKeyUser doesn't have id
        let user = SyncKeyUser(
            email: "test@example.com",
            name: "Test",
            age: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Verify the entity has no id property at runtime
        let columns = SyncKeyUser.columns
        let hasIdColumn = columns.contains { $0.name == "id" }
        #expect(!hasIdColumn)

        // Use the user to avoid compiler warning
        #expect(user.email == "test@example.com")
    }

    @Test("SyncKey table name conversion works correctly")
    func testSyncKeyTableNameConversion() {
        #expect(SyncKeyUser.tableName == "sync_key_user")
        #expect(SyncKeyEmployee.tableName == "sync_key_employee")
    }

    // MARK: - Property Default Value Tests

    @Test("Entity with property default values")
    func testEntityWithDefaultValues() throws {
        let store = try createTestStore()
        try store.migrate(entities: [UserPosts.self])

        // Create using only required parameters (slug), others use defaults
        let post = UserPosts(slug: "hello-world")
        #expect(post.title == "")
        #expect(post.content == "")
        #expect(post.views == 0)
        #expect(post.isPublished == false)
        #expect(post.tags == [])

        // Insert and verify
        try store.connection.insert(post)

        let fetched = try UserPosts
            .filter { $0.slug == "hello-world" }
            .first(store.connection)
        #expect(fetched != nil)
        #expect(fetched?.title == "")
        #expect(fetched?.content == "")
        #expect(fetched?.views == 0)
        #expect(fetched?.isPublished == false)
    }

    @Test("Entity with partial default values override")
    func testEntityWithPartialDefaultValuesOverride() throws {
        let store = try createTestStore()
        try store.migrate(entities: [UserPosts.self])

        // Create with some parameters overridden
        let post = UserPosts(
            slug: "my-first-post",
            title: "My First Post",
            views: 100,
            isPublished: true
        )
        #expect(post.title == "My First Post")
        #expect(post.content == "")  // default
        #expect(post.views == 100)
        #expect(post.isPublished == true)
        #expect(post.tags == [])  // default

        // Insert and verify
        try store.connection.insert(post)

        let fetched = try UserPosts
            .filter { $0.slug == "my-first-post" }
            .first(store.connection)
        #expect(fetched != nil)
        #expect(fetched?.title == "My First Post")
        #expect(fetched?.views == 100)
        #expect(fetched?.isPublished == true)
    }

    @Test("Backward compatible JSON decoding with missing fields")
    func testBackwardCompatibleDecoding() throws {
        // Simulate old version JSON payload that doesn't have new fields (views, isPublished, tags)
        let oldVersionJson = """
        {
            "slug": "old-post",
            "title": "Old Post",
            "content": "Old content",
            "createdAt": 1703203200.0,
            "updatedAt": 1703203200.0
        }
        """

        let decoder = JSONDecoder()
        let data = oldVersionJson.data(using: .utf8)!

        // Should decode successfully using default values for missing fields
        let post = try decoder.decode(UserPosts.self, from: data)

        #expect(post.slug == "old-post")
        #expect(post.title == "Old Post")
        #expect(post.content == "Old content")
        // These fields are missing from JSON, should use default values
        #expect(post.views == 0)
        #expect(post.isPublished == false)
        #expect(post.tags == [])
    }

    @Test("Backward compatible decoding with partial fields")
    func testBackwardCompatibleDecodingPartialFields() throws {
        // JSON with some new fields present, some missing
        let partialJson = """
        {
            "slug": "partial-post",
            "title": "Partial Post",
            "content": "Some content",
            "views": 50,
            "createdAt": 1703203200.0,
            "updatedAt": 1703203200.0
        }
        """

        let decoder = JSONDecoder()
        let data = partialJson.data(using: .utf8)!

        let post = try decoder.decode(UserPosts.self, from: data)

        #expect(post.slug == "partial-post")
        #expect(post.title == "Partial Post")
        #expect(post.views == 50)  // Present in JSON
        #expect(post.isPublished == false)  // Missing, use default
        #expect(post.tags == [])  // Missing, use default
    }

    // MARK: - @Embedded Macro Tests

    @Test("@Embedded struct conforms to Embedded protocol")
    func testDefaultProtocolConformance() {
        // This compiles only if DefaultSettings conforms to Default
        func checkDefault<T: Default>(_ type: T.Type) -> Bool { true }
        #expect(checkDefault(DefaultSettings.self))
        #expect(checkDefault(DefaultUserPrefs.self))
        #expect(checkDefault(DefaultConfig.self))
    }

    @Test("@Entity struct conforms to expected protocols")
    func testEntityProtocolConformance() {
        // @Entity types conform to EntityProtocol
        func checkEntityProtocol<T: EntityProtocol>(_ type: T.Type) -> Bool { true }
        #expect(checkEntityProtocol(MacroUser.self))
        #expect(checkEntityProtocol(MacroProfile.self))
        #expect(checkEntityProtocol(MacroTask.self))
        #expect(checkEntityProtocol(SyncKeyUser.self))
        #expect(checkEntityProtocol(UserPosts.self))
    }

    @Test("@Embedded with all default values - missing fields use defaults")
    func testDefaultAllDefaultValues() throws {
        let json = """
        {}
        """

        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!

        let settings = try decoder.decode(DefaultSettings.self, from: data)

        #expect(settings.theme == "light")
        #expect(settings.fontSize == 14)
        #expect(settings.notifications == true)
    }

    @Test("@Embedded with all default values - partial fields override defaults")
    func testDefaultPartialFields() throws {
        let json = """
        {
            "theme": "dark",
            "fontSize": 18
        }
        """

        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!

        let settings = try decoder.decode(DefaultSettings.self, from: data)

        #expect(settings.theme == "dark")
        #expect(settings.fontSize == 18)
        #expect(settings.notifications == true)  // Default used
    }

    @Test("@Embedded with required field - throws when missing")
    func testDefaultRequiredFieldThrows() throws {
        let json = """
        {
            "theme": "dark"
        }
        """

        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!

        // Should throw because userId is required
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(DefaultUserPrefs.self, from: data)
        }
    }

    @Test("@Embedded with required field - succeeds when present")
    func testDefaultRequiredFieldPresent() throws {
        let json = """
        {
            "userId": "user123"
        }
        """

        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!

        let prefs = try decoder.decode(DefaultUserPrefs.self, from: data)

        #expect(prefs.userId == "user123")
        #expect(prefs.theme == "light")  // Default
        #expect(prefs.language == "en")  // Default
    }

    @Test("@Embedded with optional fields - nil when missing")
    func testDefaultOptionalFields() throws {
        let json = """
        {}
        """

        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!

        let config = try decoder.decode(DefaultConfig.self, from: data)

        #expect(config.apiUrl == "https://api.example.com")
        #expect(config.timeout == 30)
        #expect(config.debugMode == nil)
    }

    @Test("@Embedded with optional fields - present when specified")
    func testDefaultOptionalFieldsPresent() throws {
        let json = """
        {
            "debugMode": true
        }
        """

        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!

        let config = try decoder.decode(DefaultConfig.self, from: data)

        #expect(config.apiUrl == "https://api.example.com")
        #expect(config.timeout == 30)
        #expect(config.debugMode == true)
    }

    @Test("@Embedded type error uses default value with do-catch fallback")
    func testDefaultTypeErrorFallsBackToDefault() throws {
        let json = """
        {
            "theme": 123,
            "fontSize": 14
        }
        """

        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!

        // With do-catch pattern, type errors fall back to default values
        let settings = try decoder.decode(DefaultSettings.self, from: data)
        #expect(settings.theme == "light")  // Falls back to default
        #expect(settings.fontSize == 14)    // Successfully decoded
        #expect(settings.notifications == true)  // Default
    }

    // MARK: - Comprehensive Type Coverage Tests

    @Test("All primitive types with defaults - empty JSON uses all defaults")
    func testAllPrimitiveTypesDefaults() throws {
        let json = "{}"
        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!

        let obj = try decoder.decode(AllTypesWithDefaults.self, from: data)

        // String defaults
        #expect(obj.stringEmpty == "")
        #expect(obj.stringValue == "hello")

        // Integer defaults
        #expect(obj.intZero == 0)
        #expect(obj.intValue == 42)
        #expect(obj.int8Value == 8)
        #expect(obj.int16Value == 16)
        #expect(obj.int32Value == 32)
        #expect(obj.int64Value == 64)

        // Unsigned integer defaults
        #expect(obj.uintZero == 0)
        #expect(obj.uintValue == 100)

        // Floating point defaults
        #expect(obj.doubleZero == 0.0)
        #expect(obj.doubleValue == 3.14)
        #expect(obj.floatValue == 2.5)

        // Boolean defaults
        #expect(obj.boolFalse == false)
        #expect(obj.boolTrue == true)

        // Collection defaults
        #expect(obj.arrayEmpty == [])
        #expect(obj.arrayValue == [1, 2, 3])
        #expect(obj.dictEmpty == [:])
        #expect(obj.dictValue == ["key": "value"])
    }

    @Test("All primitive types - values override defaults")
    func testAllPrimitiveTypesOverride() throws {
        let json = """
        {
            "stringEmpty": "not empty",
            "stringValue": "world",
            "intZero": 999,
            "intValue": 0,
            "boolFalse": true,
            "boolTrue": false,
            "arrayEmpty": ["a", "b"],
            "arrayValue": [],
            "dictEmpty": {"x": 1},
            "dictValue": {}
        }
        """
        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!

        let obj = try decoder.decode(AllTypesWithDefaults.self, from: data)

        #expect(obj.stringEmpty == "not empty")
        #expect(obj.stringValue == "world")
        #expect(obj.intZero == 999)
        #expect(obj.intValue == 0)
        #expect(obj.boolFalse == true)
        #expect(obj.boolTrue == false)
        #expect(obj.arrayEmpty == ["a", "b"])
        #expect(obj.arrayValue == [])
        #expect(obj.dictEmpty == ["x": 1])
        #expect(obj.dictValue == [:])
    }

    @Test("All optional types - empty JSON gives nil")
    func testAllOptionalTypesNil() throws {
        let json = "{}"
        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!

        let obj = try decoder.decode(AllOptionalTypes.self, from: data)

        #expect(obj.optString == nil)
        #expect(obj.optInt == nil)
        #expect(obj.optDouble == nil)
        #expect(obj.optBool == nil)
        #expect(obj.optArray == nil)
        #expect(obj.optDict == nil)
    }

    @Test("All optional types - values present")
    func testAllOptionalTypesPresent() throws {
        let json = """
        {
            "optString": "hello",
            "optInt": 42,
            "optDouble": 3.14,
            "optBool": true,
            "optArray": ["a", "b"],
            "optDict": {"x": 1}
        }
        """
        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!

        let obj = try decoder.decode(AllOptionalTypes.self, from: data)

        #expect(obj.optString == "hello")
        #expect(obj.optInt == 42)
        #expect(obj.optDouble == 3.14)
        #expect(obj.optBool == true)
        #expect(obj.optArray == ["a", "b"])
        #expect(obj.optDict == ["x": 1])
    }

    @Test("Mixed optional types - required field throws when missing")
    func testMixedOptionalRequiredThrows() throws {
        let json = """
        {
            "withDefault": "custom",
            "optional": "value"
        }
        """
        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(MixedOptionalTypes.self, from: data)
        }
    }

    @Test("Mixed optional types - all fields present")
    func testMixedOptionalAllPresent() throws {
        let json = """
        {
            "required": "must have",
            "withDefault": "custom",
            "optional": "value",
            "optionalWithNil": 42
        }
        """
        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!

        let obj = try decoder.decode(MixedOptionalTypes.self, from: data)

        #expect(obj.required == "must have")
        #expect(obj.withDefault == "custom")
        #expect(obj.optional == "value")
        #expect(obj.optionalWithNil == 42)
    }

    @Test("Mixed optional types - only required field")
    func testMixedOptionalOnlyRequired() throws {
        let json = """
        {
            "required": "must have"
        }
        """
        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!

        let obj = try decoder.decode(MixedOptionalTypes.self, from: data)

        #expect(obj.required == "must have")
        #expect(obj.withDefault == "default")
        #expect(obj.optional == nil)
        #expect(obj.optionalWithNil == nil)
    }

    @Test("Nested struct - empty JSON uses nested defaults")
    func testNestedStructDefaults() throws {
        let json = "{}"
        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!

        let obj = try decoder.decode(PersonWithAddress.self, from: data)

        #expect(obj.name == "")
        #expect(obj.address.street == "")
        #expect(obj.address.city == "")
        #expect(obj.address.zip == "")
    }

    @Test("Nested struct - partial nested values")
    func testNestedStructPartialValues() throws {
        let json = """
        {
            "name": "John",
            "address": {
                "city": "NYC"
            }
        }
        """
        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!

        let obj = try decoder.decode(PersonWithAddress.self, from: data)

        #expect(obj.name == "John")
        #expect(obj.address.street == "")  // default
        #expect(obj.address.city == "NYC")  // from JSON
        #expect(obj.address.zip == "")  // default
    }

    @Test("Complex nested types - empty JSON uses all defaults")
    func testComplexNestedDefaults() throws {
        let json = "{}"
        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!

        let obj = try decoder.decode(ComplexNestedTypes.self, from: data)

        // Nested struct defaults
        #expect(obj.address.street == "")
        #expect(obj.optionalAddress == nil)

        // Enum defaults
        #expect(obj.status == .active)
        #expect(obj.optionalStatus == nil)

        // Array defaults
        #expect(obj.tags == [])
        #expect(obj.scores == [0, 0, 0])
        // addresses has default [NestedAddress(), NestedAddress()]
        #expect(obj.addresses.count == 2)
        #expect(obj.addresses[0].street == "")
        #expect(obj.addresses[1].city == "")

        // Dictionary defaults
        // metadata has default ["key": "value"]
        #expect(obj.metadata == ["key": "value"])
        #expect(obj.counts == ["default": 0])

        // Optional collection defaults
        #expect(obj.optionalTags == nil)
        #expect(obj.optionalMetadata == nil)
    }

    @Test("Complex nested types - full values override")
    func testComplexNestedFullValues() throws {
        let json = """
        {
            "address": {"street": "123 Main", "city": "NYC", "zip": "10001"},
            "optionalAddress": {"street": "456 Oak", "city": "LA", "zip": "90001"},
            "status": "inactive",
            "optionalStatus": "pending",
            "tags": ["swift", "ios"],
            "scores": [100, 200],
            "addresses": [{"street": "A", "city": "B", "zip": "C"}],
            "metadata": {"key": "value"},
            "counts": {"items": 5},
            "optionalTags": ["opt"],
            "optionalMetadata": {"opt": "data"}
        }
        """
        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!

        let obj = try decoder.decode(ComplexNestedTypes.self, from: data)

        // Nested struct
        #expect(obj.address.street == "123 Main")
        #expect(obj.address.city == "NYC")
        #expect(obj.optionalAddress?.city == "LA")

        // Enum
        #expect(obj.status == .inactive)
        #expect(obj.optionalStatus == .pending)

        // Arrays
        #expect(obj.tags == ["swift", "ios"])
        #expect(obj.scores == [100, 200])
        #expect(obj.addresses.count == 1)
        #expect(obj.addresses[0].street == "A")

        // Dictionaries
        #expect(obj.metadata == ["key": "value"])
        #expect(obj.counts == ["items": 5])

        // Optional collections
        #expect(obj.optionalTags == ["opt"])
        #expect(obj.optionalMetadata == ["opt": "data"])
    }

    @Test("Enum with @Embedded - memberwise init works")
    func testEnumMemberwiseInit() {
        // Verify enum can be created and used
        let status = Status.active
        #expect(status.rawValue == "active")

        let inactive = Status.inactive
        #expect(inactive.rawValue == "inactive")
    }

    @Test("Nested struct in array - partial data")
    func testNestedArrayPartialData() throws {
        let json = """
        {
            "addresses": [
                {"city": "NYC"},
                {"street": "Oak St", "zip": "12345"},
                {}
            ]
        }
        """
        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!

        let obj = try decoder.decode(ComplexNestedTypes.self, from: data)

        #expect(obj.addresses.count == 3)

        // First address: only city
        #expect(obj.addresses[0].street == "")
        #expect(obj.addresses[0].city == "NYC")
        #expect(obj.addresses[0].zip == "")

        // Second address: street and zip
        #expect(obj.addresses[1].street == "Oak St")
        #expect(obj.addresses[1].city == "")
        #expect(obj.addresses[1].zip == "12345")

        // Third address: all defaults
        #expect(obj.addresses[2].street == "")
        #expect(obj.addresses[2].city == "")
        #expect(obj.addresses[2].zip == "")
    }
}
