# SwiftStore

A lightweight SQLite-based data persistence framework for Swift, with multi-device sync support.

## Features

- **Declarative API** - Swift macros auto-generate boilerplate code
- **Type-safe Queries** - Compile-time checked query builder
- **Auto Migration** - Smart schema migration without manual SQL
- **Multi-device Sync** - Changelog-based bidirectional synchronization
- **High Performance** - SQLite WAL mode + single-writer multiple-reader connection pool

## Quick Start

### Define Entities

```swift
import SwiftStoreCore

@Entity
struct User {
    let id: UUIDV4
    var name: String
    var email: String
    var age: Int?
    let createdAt: Date
    let updatedAt: Date
}
```

### Database Operations

```swift
// Create connection
let connection = try SQLiteConnection(path: "database.sqlite")

// Auto migrate
let migrator = Migrator(connection: connection)
try migrator.apply(try migrator.plan(for: [User.self]))

// Insert
let user = User(name: "Alice", email: "alice@example.com", age: 25)
try user.insert(connection)

// Query
let users = try User.filter { $0.age > 18 }
    .order(by: \.name)
    .limit(10)
    .all(connection)

// Update
var updatedUser = user
updatedUser.name = "Alice Smith"
try updatedUser.update(connection)

// Delete
try user.delete(connection)
```

### Index Definition

```swift
@Entity
struct User {
    #Index<Self>(\.email, unique: true)           // Unique index
    #Index<Self>(\.firstName, \.lastName)         // Composite index

    let id: UUIDV4
    var email: String
    var firstName: String
    var lastName: String
    let createdAt: Date
    let updatedAt: Date
}
```

### Multi-device Sync

```swift
// Create connection manager with sync
let manager = try ConnectionManager(
    path: "database.sqlite",
    syncConfig: SyncConfig(
        changeLogDbPath: "changelog.sqlite",
        deviceId: myDeviceId,
        registeredEntities: [User.self],
        tickClock: { clock.tick() },
        transport: myTransport,
        syncableEntities: [User.self]
    )
)

// Perform sync
let result = try await manager.sync()
print("Pulled: \(result.pulledCount), Pushed: \(result.pushedCount)")
```

## Complete Example

The following example demonstrates all core features of SwiftStore:

### 1. Define Models

```swift
import SwiftStoreCore
import SwiftStoreConnectionQueue

// MARK: - Nested Codable Types (with @Default fault-tolerant decoding)

@Default
struct Address: Codable, Sendable {
    var street: String = ""
    var city: String = ""
    var zipCode: String = ""
}

@Default
struct Profile: Codable, Sendable {
    var bio: String = ""
    var avatarUrl: String?
    var settings: UserSettings = UserSettings()
}

@Default
struct UserSettings: Codable, Sendable {
    var theme: String = "light"
    var fontSize: Int = 14
    var notifications: Bool = true
}

// MARK: - Standard Entity (using id as primary key)

@Entity
struct User {
    #Index<Self>(\.email, unique: true)              // Unique index
    #Index<Self>(\.name)                             // Regular index
    #Index<Self>(\.address.city)                     // Nested field index
    #Index<Self>(\.profile.settings.theme)           // Deep nested index

    let id: UUIDV4
    var name: String
    var email: String
    var age: Int?
    var address: Address                             // Nested Codable type
    var profile: Profile                             // Deep nested type
    var tags: [String]                               // Array type
    let createdAt: Date
    let updatedAt: Date
}

@Entity
struct Post {
    #Index<Self>(\.authorId)
    #Index<Self>(\.status, \.createdAt)              // Composite index

    let id: UUIDV4
    var authorId: UUIDV4
    var title: String
    var content: String
    var status: String
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - Sync Entity (using #SyncKey as primary key, no id field)

@Entity
struct UserDevice {
    #SyncKey<Self>(\.userId, \.deviceId)             // Composite sync key

    var userId: UUIDV4
    var deviceId: String
    var deviceName: String
    var lastActiveAt: Date
    let createdAt: Date
    let updatedAt: Date
}

@Entity
struct Favorite {
    #SyncKey<Self>(\.userId, \.postId)               // Many-to-many sync key

    var userId: UUIDV4
    var postId: UUIDV4
    let createdAt: Date
    let updatedAt: Date
}
```

### 2. Basic Database Operations

```swift
// Create database connection
let dbPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("app.sqlite").path
let connection = try SQLiteConnection(path: dbPath, options: .init(walMode: true))

// Auto migrate schema
let migrator = Migrator(connection: connection)
let plan = try migrator.plan(for: [User.self, Post.self, UserDevice.self, Favorite.self])
try migrator.apply(plan)

// Insert data (instance method style)
let user = User(
    name: "Alice",
    email: "alice@example.com",
    age: 28,
    address: Address(street: "123 Main St", city: "Beijing", zipCode: "100000"),
    profile: Profile(bio: "Swift Developer", settings: UserSettings(theme: "dark")),
    tags: ["developer", "swift"]
)
try user.insert(connection)

let post = Post(
    authorId: user.id,
    title: "Hello SwiftStore",
    content: "This is my first post!",
    status: "published"
)
try post.insert(connection)

// Insert sync entity (using SyncKey)
let device = UserDevice(
    userId: user.id,
    deviceId: "iPhone-001",
    deviceName: "My iPhone",
    lastActiveAt: Date()
)
try device.insert(connection)

let favorite = Favorite(userId: user.id, postId: post.id)
try favorite.insert(connection)
```

### 3. Type-safe Queries

```swift
// Simple condition query
let adultUsers = try User.filter { $0.age >= 18 }.all(connection)

// Multiple conditions
let activeUsers = try User
    .filter { $0.age >= 18 && $0.profile.settings.theme == "dark" }
    .order(by: \.createdAt, ascending: false)
    .limit(20)
    .all(connection)

// Nested field query
let beijingUsers = try User.filter { $0.address.city == "Beijing" }.all(connection)

// Optional field query
let usersWithAge = try User.filter { $0.age != nil }.all(connection)

// Compound conditions
let publishedPosts = try Post
    .filter { $0.status == "published" && $0.authorId == user.id }
    .orderDesc(by: \.createdAt)
    .all(connection)

// Query by sync key
let userDevices = try UserDevice.filter { $0.userId == user.id }.all(connection)

// Query by ID
let foundUser = try User.find(user.id, connection)        // Returns Optional
let requiredUser = try User.get(user.id, connection)      // Throws if not found

// Aggregate queries
let totalUsers = try User.count(connection)
let hasUsers = try User.exists(connection)
let firstUser = try User.first(connection)

// Batch operations
let deletedCount = try User.filter { $0.age < 18 }.deleteAll(connection)
let updatedCount = try User.filter { $0.status == "inactive" }
    .updateAll(connection, [\.status <- "archived"])
```

### 4. Update and Delete

```swift
// Update entity (instance method)
var updatedUser = user
updatedUser.name = "Alice Smith"
updatedUser.profile.bio = "Senior Swift Developer"
try updatedUser.update(connection)

// Save entity (auto insert or update)
var newOrExisting = User(name: "Bob", email: "bob@example.com", ...)
try newOrExisting.save(connection)  // Insert if new, update if exists

// Reload entity
if let reloaded = try updatedUser.reload(connection) {
    print("Latest data: \(reloaded.name)")
}

// Delete entity (instance method)
try post.delete(connection)
try favorite.delete(connection)

// Delete by ID
try User.delete(user.id, connection)

// Batch delete
try User.filter { $0.age < 18 }.deleteAll(connection)
try User.deleteAll(connection)  // Delete all
```

### 5. Connection Pool (Single-Writer Multiple-Reader)

```swift
// Create connection manager
let manager = try ConnectionManager(
    path: dbPath,
    options: .init(walMode: true),
    maxReadConnections: 4
)

// Concurrent reads (using connection pool)
async let users1 = manager.read { conn in
    try User.filter { $0.age > 20 }.all(conn)
}
async let users2 = manager.read { conn in
    try User.filter { $0.address.city == "Shanghai" }.all(conn)
}
let (result1, result2) = try await (users1, users2)

// Write operations (serialized)
try await manager.write { conn in
    try User(
        name: "Bob",
        email: "bob@example.com",
        age: 30,
        address: Address(city: "Shanghai"),
        profile: Profile(),
        tags: []
    ).insert(conn)
}

// Convenience static methods
try await manager.read { conn in
    let count = try User.count(conn)
    let first = try User.first(conn)
    let all = try User.all(conn)
}
```

### 6. Multi-device Sync

```swift
// Implement SyncTransport protocol
struct MySyncTransport: SyncTransport {
    let serverURL: URL

    func pull(sinceClock: Int64, deviceId: UUIDV4) async throws -> PullResponse {
        // Pull changes from server
        var request = URLRequest(url: serverURL.appendingPathComponent("pull"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode([
            "sinceClock": sinceClock,
            "deviceId": deviceId.uuidString
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(PullResponse.self, from: data)
    }

    func push(changes: [SyncChange], deviceId: UUIDV4) async throws -> PushResponse {
        // Push local changes to server
        var request = URLRequest(url: serverURL.appendingPathComponent("push"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode([
            "changes": changes,
            "deviceId": deviceId.uuidString
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(PushResponse.self, from: data)
    }
}

// Create hybrid logical clock
let clock = HybridClock()

// Configure sync
let deviceId = UUIDV4()
let syncConfig = SyncConfig(
    changeLogDbPath: dbPath.replacingOccurrences(of: ".sqlite", with: "_changelog.sqlite"),
    deviceId: deviceId,
    pendingDeletesTable: "__pending_deletes",
    registeredEntities: [User.self, Post.self, UserDevice.self, Favorite.self],
    tickClock: { clock.tick() },
    transport: MySyncTransport(serverURL: URL(string: "https://api.example.com/sync")!),
    syncableEntities: [User.self, Post.self, UserDevice.self, Favorite.self],
    syncConfiguration: SyncConfiguration(batchSize: 50, yieldBetweenBatches: true),
    schemaVersion: 1,
    ntpToleranceMs: 5000  // Time offset tolerance: 5 seconds
)

// Create connection manager with sync
let syncManager = try ConnectionManager(
    path: dbPath,
    syncConfig: syncConfig
)

// Check sync status
if await syncManager.hasSyncEnabled {
    print("Sync is enabled")

    // Perform sync
    do {
        let result = try await syncManager.sync()
        print("""
        Sync completed:
        - Pulled: \(result.pulledCount) changes
        - Pushed: \(result.pushedCount) changes
        - Conflicts: \(result.conflictCount)
        - Server clock: \(result.state.lastServerClock)
        """)
    } catch let error as NTPError {
        print("Time sync error: \(error)")
    } catch let error as SyncError {
        print("Sync error: \(error)")
    }

    // Get current sync state
    if let state = await syncManager.syncState {
        print("Last server clock: \(state.lastServerClock)")
        print("Last local clock: \(state.lastLocalClock)")
    }
}
```

### 7. @Default Fault-tolerant Decoding

```swift
// @Default macro makes decoding more robust, missing fields use default values
let json = """
{
    "street": "456 Oak Ave"
}
""".data(using: .utf8)!

// Even if city and zipCode are missing, decoding succeeds
let address = try JSONDecoder().decode(Address.self, from: json)
print(address.street)   // "456 Oak Ave"
print(address.city)     // "" (default value)
print(address.zipCode)  // "" (default value)

// Nested scenarios also work
let profileJson = """
{
    "bio": "Hello"
}
""".data(using: .utf8)!

let profile = try JSONDecoder().decode(Profile.self, from: profileJson)
print(profile.bio)                      // "Hello"
print(profile.settings.theme)           // "light" (nested default)
print(profile.settings.notifications)   // true (nested default)
```

## Architecture

```
SwiftStore
├── SwiftStoreProtocols     # Protocol definitions
├── SwiftStoreMacros        # Macro definitions
├── SwiftStoreCore          # Core (connection, query, migration)
├── SwiftStoreChangeTracker # Change tracking
├── SwiftStoreSync          # Sync layer
└── SwiftStoreConnectionQueue # Connection management
```

### Dependency Graph

```
SwiftStoreProtocols (no dependencies)
       ↓
SwiftStoreMacros (depends on swift-syntax)
       ↓
SwiftStoreCore
       ↓
SwiftStoreChangeTracker
       ↓
SwiftStoreSync
       ↓
SwiftStoreConnectionQueue
```

## Packages

| Package | Description |
|---------|-------------|
| [SwiftStoreProtocols](./SwiftStoreProtocols/) | Protocol definitions - EntityProtocol, SQLiteCodable, etc. |
| [SwiftStoreMacros](./SwiftStoreMacros/) | Macro definitions - @Entity, #Index, #SyncKey, @Default |
| [SwiftStoreCore](./SwiftStoreCore/) | Core functionality - SQLite connection, query builder, migration |
| [SwiftStoreChangeTracker](./SwiftStoreChangeTracker/) | Change tracking - SQLite update hook to record changes |
| [SwiftStoreSync](./SwiftStoreSync/) | Data sync - Bidirectional sync, conflict resolution, NTP validation |
| [SwiftStoreConnectionQueue](./SwiftStoreConnectionQueue/) | Connection management - Single-writer multiple-reader pool |

## Supported Platforms

- macOS 14+
- iOS 17+
- tvOS 17+
- watchOS 10+

## Requirements

- Swift 6.0+
- Xcode 16+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/gfreezy/SwiftStore", from: "1.0.0")
]
```

Import the modules you need:

```swift
// Basic functionality
import SwiftStoreCore

// With sync support
import SwiftStoreConnectionQueue
```

## License

MIT
