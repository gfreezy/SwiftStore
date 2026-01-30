# SwiftStore

A lightweight SQLite-based data persistence framework for Swift, with multi-device sync support.

## Features

- **Declarative API** - Swift macros auto-generate boilerplate code
- **Type-safe Queries** - Compile-time checked query builder
- **Auto Migration** - Smart schema migration without manual SQL
- **Multi-device Sync** - Changelog-based bidirectional synchronization
- **High Performance** - SQLite WAL mode + single-writer multiple-reader connection pool
- **Dev Server** - Built-in web admin UI for database inspection and file management

## Requirements

- Swift 6.0+
- Xcode 16+
- macOS 14+ / iOS 17+ / tvOS 17+ / watchOS 10+

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/gfreezy/SwiftStore", from: "1.0.0")
]
```

```swift
// Import modules
import SwiftStoreCore              // Basic functionality
import SwiftStoreConnectionQueue   // With sync support

#if DEBUG
import SwiftStoreServer            // Development server
#endif
```

## Quick Start

### Define Entities

| Entity Type | Primary Key | `createdAt` | `updatedAt` | Sync Support |
|-------------|-------------|-------------|-------------|--------------|
| `@Entity` (standard) | `id: UUIDV7` **or** `#SyncKey` **required** | `Date` **required** | `Date` **required** | ✅ Yes |
| `@Entity(readonly: true)` | `id` of any type (Int, String, etc.) | Optional | Optional | ❌ No |

> **⚠️ Required Fields**: Standard entities **MUST** have:
> - **Primary key**: Either `id: UUIDV7` or `#SyncKey` (composite key, no `id` field needed)
> - `createdAt: Date` - Creation timestamp, auto-set on insert
> - `updatedAt: Date` - Update timestamp, auto-updated on save
>
> These fields are required for sync functionality and data integrity.

**Option 1: Using `id` field**

```swift
import SwiftStoreCore

@Entity
struct User {
    @Default(UUIDV7())
    let id: UUIDV7          // ✅ Primary key with default
    var name: String
    var email: String
    var age: Int?
    @Default(Date())
    let createdAt: Date     // ✅ Required with default
    @Default(Date())
    let updatedAt: Date     // ✅ Required with default
}
```

> **💡 `@Default` Macro**: Use `@Default(value)` to specify default values for `let` properties. This allows memberwise initializers to work while providing sensible defaults for fields like `id`, `createdAt`, and `updatedAt`.

**Option 2: Using `#SyncKey` (composite primary key)**

```swift
@Entity
struct UserDevice {
    #SyncKey<Self>(\.userId, \.deviceId)  // ✅ Composite primary key (no id field)

    var userId: UUIDV7
    var deviceId: String
    var deviceName: String
    @Default(Date())
    let createdAt: Date     // ✅ Required with default
    @Default(Date())
    let updatedAt: Date     // ✅ Required with default
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
    #Index<Self>(\.address.city)                  // JSON field index
    #Index<Self>(\.profile.settings.theme)        // Deep nested JSON field index

    let id: UUIDV7
    var email: String
    var firstName: String
    var lastName: String
    var address: Address                          // Nested Codable type (stored as JSON)
    var profile: Profile                          // Deep nested type (stored as JSON)
    let createdAt: Date
    let updatedAt: Date
}
```

> **JSON Field Indexing**: SwiftStore supports indexing nested fields within JSON columns using keypath syntax (e.g., `\.address.city`). The index is created on the extracted JSON value using SQLite's `json_extract()` function.

### Readonly Entities (readonly: true)

For entities that don't need synchronization (local cache, settings, imported data, etc.):

> **💡 Readonly Exception**: `readonly: true` entities do NOT require `id: UUIDV7`, `createdAt`, or `updatedAt` fields.

```swift
// readonly: true allows:
// - Any id type (Int, String, UUID, etc.) instead of UUIDV7
// - No createdAt/updatedAt fields required
// - Can only be used with readonly ConnectionManager

@Entity(readonly: true)
struct LocalSettings {
    var id: Int                    // ✅ Int id allowed (not UUIDV7)
    var key: String
    var value: String
    // ✅ No createdAt/updatedAt required
}

@Entity(readonly: true)
struct CacheEntry {
    var id: String                 // ✅ String id allowed
    var data: String
    var timestamp: Date = Date()   // Optional, not required
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
import SwiftStore

// MARK: - Nested Codable Types (with @Embedded fault-tolerant decoding)

@Embedded
struct Address: Codable, Sendable {
    var street: String = ""
    var city: String = ""
    var zipCode: String = ""
}

@Embedded
struct Profile: Codable, Sendable {
    var bio: String = ""
    var avatarUrl: String?
    var settings: UserSettings = UserSettings()
}

@Embedded
struct UserSettings: Codable, Sendable {
    var theme: String = "light"
    var fontSize: Int = 14
    var notifications: Bool = true
}

// MARK: - Standard Entity (using id as primary key)
// ⚠️ Required fields: id (UUIDV7), createdAt (Date), updatedAt (Date)

@Entity
struct User {
    #Index<Self>(\.email, unique: true)              // Unique index
    #Index<Self>(\.name)                             // Regular index
    #Index<Self>(\.address.city)                     // Nested field index
    #Index<Self>(\.profile.settings.theme)           // Deep nested index

    @Default(UUIDV7())
    let id: UUIDV7                                   // ✅ Required with default
    var name: String
    var email: String
    var age: Int?
    var address: Address                             // Nested Codable type
    var profile: Profile                             // Deep nested type
    var tags: [String]                               // Array type
    @Default(Date())
    let createdAt: Date                              // ✅ Required with default
    @Default(Date())
    let updatedAt: Date                              // ✅ Required with default
}

@Entity
struct Post {
    #Index<Self>(\.authorId)
    #Index<Self>(\.status, \.createdAt)              // Composite index

    @Default(UUIDV7())
    let id: UUIDV7
    var authorId: UUIDV7
    var title: String
    var content: String
    var status: String
    @Default(Date())
    let createdAt: Date
    @Default(Date())
    let updatedAt: Date
}

// MARK: - Sync Entity (using #SyncKey instead of id field)
// ⚠️ When using #SyncKey, do NOT define id field. createdAt/updatedAt still required.

@Entity
struct UserDevice {
    #SyncKey<Self>(\.userId, \.deviceId)             // ✅ Composite primary key (replaces id)

    var userId: UUIDV7                               // Part of SyncKey
    var deviceId: String                             // Part of SyncKey
    var deviceName: String
    var lastActiveAt: Date
    @Default(Date())
    let createdAt: Date                              // ✅ Required with default
    @Default(Date())
    let updatedAt: Date                              // ✅ Required with default
}

@Entity
struct Favorite {
    #SyncKey<Self>(\.userId, \.postId)               // ✅ Many-to-many composite key

    var userId: UUIDV7
    var postId: UUIDV7
    @Default(Date())
    let createdAt: Date                              // ✅ Required with default
    @Default(Date())
    let updatedAt: Date                              // ✅ Required with default
}

// MARK: - Readonly Entity (for local-only data, flexible id type)

@Entity(readonly: true)
struct LocalConfig {
    var id: Int                                      // Can use Int, String, or any type
    var key: String
    var value: String
    // No createdAt/updatedAt required
}

@Entity(readonly: true)
struct CacheEntry {
    var id: String                                   // String id
    var data: String
    var expiry: Int?
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
// Create connection manager with default options
let manager = try ConnectionManager(
    path: dbPath,
    entities: [User.self, Post.self]
)

// Custom options
let managerWithOptions = try ConnectionManager(
    path: dbPath,
    entities: [User.self, Post.self],
    options: ConnectionOptions(
        readonly: false,           // Read-write mode (default)
        synchronous: 1,            // NORMAL sync mode
        cacheSize: -2000,          // 2MB cache
        maxReadConnections: 4      // Reader pool size
    )
)

// Readonly mode - for read-only access to existing database
let readonlyManager = try ConnectionManager(
    path: dbPath,
    entities: [User.self],
    options: ConnectionOptions(readonly: true)
)
// Note: readonly mode disables WAL, write(), migrate(), and sync()

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

    func pull(sinceClock: Int64, deviceId: UUIDV7) async throws -> PullResponse {
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

    func push(changes: [SyncChange], deviceId: UUIDV7) async throws -> PushResponse {
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
let deviceId = UUIDV7()
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

### 7. @Embedded Fault-tolerant Decoding

```swift
// @Embedded macro makes decoding more robust, missing fields use default values
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

### 8. @Default Marker Macro for `let` Properties

The `@Default` macro allows specifying default values for `let` properties in `@Entity` and `@Embedded` structs. This is essential because `let` properties cannot have inline initializers while still allowing a memberwise init to be generated.

```swift
@Entity
struct User {
    @Default(UUIDV7())
    let id: UUIDV7                      // Default: new UUIDV7

    var name: String                     // No default, required in init

    @Default(nil)
    let nickname: String?                // Default: nil

    @Default(Date())
    let createdAt: Date                  // Default: current date

    @Default(Date())
    let updatedAt: Date                  // Default: current date
}

// Now you can create User with minimal parameters:
let user = User(name: "Alice")  // id, createdAt, updatedAt auto-generated

// Or provide custom values:
let customUser = User(
    id: specificId,
    name: "Bob",
    nickname: "Bobby",
    createdAt: pastDate,
    updatedAt: pastDate
)
```

`@Default` also works with `@Embedded` types:

```swift
@Embedded
struct Settings {
    @Default("light")
    let theme: String                    // Default: "light"

    @Default(14)
    let fontSize: Int                    // Default: 14

    @Default(true)
    let notifications: Bool              // Default: true

    @Default(nil)
    let customColor: String?             // Default: nil
}
```

> **Note**: Use `@Default(nil)` for optional properties that should default to `nil`. The macro uses a special `OptionalNil` type to handle nil literals.

### 9. Decoding Behavior by Type

SwiftStore provides fault-tolerant decoding with different behaviors based on type and default value presence.

#### @Embedded / @Entity JSON Decoding (Codable)

| Type | With Default | Without Default |
|------|-------------|-----------------|
| `T?` (Optional) | do-catch → fallback to default | `decodeIfPresent` → `nil` if missing, throws if fails |
| `T` (Non-optional) | do-catch → fallback to default | `decode` → throws if missing/invalid |
| `NestedType` (Embedded struct) | Same as above + compile-time `Embedded` check | Same as above + compile-time `Embedded` check |

```swift
@Embedded
struct Settings: Codable {
    var theme: String = "light"     // With default: fallback to "light" on any error
    var fontSize: Int?              // Optional without default: nil if missing
    var locale: String              // Non-optional without default: throws if missing
    var advanced: AdvancedSettings = AdvancedSettings()  // Nested with default
}
```

#### @Entity SQLite Decoding (sqliteDecode)

| Type | With Default | Without Default |
|------|-------------|-----------------|
| `T?` (Optional) | do-catch → fallback to default | `Optional<T>(from:)` → `nil` for NULL, throws if decode fails |
| `T` (Non-optional) | do-catch → fallback to default | `T(from:)` → throws if decode fails |
| `NestedType` (JSON in TEXT) | Stored as JSON TEXT, same rules apply | Same as non-optional |

```swift
@Entity
struct User {
    let id: UUIDV7                          // Required, auto-generated default
    var name: String = "Anonymous"          // With default: fallback on error
    var email: String                       // Required: throws if decode fails
    var age: Int?                           // Optional: nil for NULL column, throws if decode fails
    var score: Int? = 0                     // Optional with default: fallback to 0
    var settings: Settings = Settings()    // Nested JSON with default
    let createdAt: Date                     // Required, auto-generated default
    let updatedAt: Date                     // Required, auto-generated default
}
```

#### Behavior Summary

1. **With default value**: Uses do-catch, any decoding error falls back to default (logged via `os_log`)
2. **Optional without default**: Returns `nil` for missing/null values, throws if decode fails
3. **Non-optional without default**: Throws error if value is missing or invalid
4. **Nested types**: Must conform to `Embedded` protocol (compile-time validation)

## Development Server

SwiftStore provides a built-in development server with a Web admin interface (similar to phpMyAdmin) for easy database inspection and management during development.

### Quick Start

```swift
import SwiftStore
import SwiftStoreServer

let manager = try ConnectionManager(
    path: "app.sqlite",
    entities: [User.self, Post.self]
)
try await manager.migrate(dryRun: false)

#if DEBUG
// You must store server to a variable to keep it running
let server = try await SwiftStoreServer(
    connectionManager: manager,
    configuration: .init(port: 8080)
)
print("Dev server: http://127.0.0.1:8080")
try await server.start()
#endif
```

### Web Admin Interface

Visit `http://127.0.0.1:8080/admin` to access the admin panel:

```
┌─────────────────────────────────────────────────┐
│  SwiftStore Admin                               │
├────────────┬────────────────────────────────────┤
│            │  SQL Query Input                   │
│  Tables    │  [                              ]  │
│  ────────  │  [Execute]                         │
│  - users   ├────────────────────────────────────┤
│  - posts   │  Table: users                      │
│            │  ┌────┬──────┬─────────┐          │
│            │  │ id │ name │ email   │          │
│            │  ├────┼──────┼─────────┤          │
│            │  │ 1  │ John │ j@x.com │          │
│            │  └────┴──────┴─────────┘          │
│            │  [< Prev] Page 1/10 [Next >]       │
└────────────┴────────────────────────────────────┘
```

Features:
- View all tables in the database
- Browse table data with pagination
- Execute custom SQL queries (Ctrl/Cmd+Enter)
- View table schema (columns, types, constraints)
- Smart BLOB display (auto-decode as UUID, UTF-8 string, or show size)
- Double-click cell to view full content in modal
- JSON syntax highlighting with format toggle
- SQL history with localStorage persistence
- Download query results as CSV

### File Manager

Visit `http://127.0.0.1:8080/files` to access the file manager:

```
┌─────────────────────────────────────────────────────┐
│  SwiftStore Admin    [Database] [Files]             │
├─────────────────────────────────────────────────────┤
│  Root / Documents                [Upload] [Refresh] │
├─────────────────────────────────────────────────────┤
│  Type │ Name           │ Size    │ Modified         │
│  ──── │ ────────────── │ ─────── │ ──────────────── │
│  📁   │ ..             │ -       │ -                │
│  📁   │ images         │ -       │ 2024-01-15 10:30 │
│  📄   │ config.json    │ 2.3 KB  │ 2024-01-14 15:22 │
│  🖼️   │ avatar.png     │ 45.2 KB │ 2024-01-13 09:15 │
└─────────────────────────────────────────────────────┘
```

Features:
- Browse files and directories
- Upload files with drag-and-drop support
- Download files directly
- Navigate with breadcrumb trail
- Browser back/forward navigation support
- File type icons for common formats

### REST API

The server also exposes REST endpoints:

**Database API:**

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/health` | GET | Health check |
| `/api/schema` | GET | Get database schema |
| `/api/query` | POST | Execute SELECT queries |
| `/api/execute` | POST | Execute INSERT/UPDATE/DELETE |

**File API:**

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/files/list` | GET | List files in directory |
| `/api/files/download` | GET | Download a file |
| `/api/files/upload` | POST | Upload a file |
| `/api/files/info` | GET | Get file information |

## Architecture

```
SwiftStore
├── SwiftStoreProtocols     # Protocol definitions
├── SwiftStoreMacros        # Macro definitions
├── SwiftStoreCore          # Core (connection, query, migration)
├── SwiftStoreChangeTracker # Change tracking
├── SwiftStoreSync          # Sync layer
├── SwiftStoreConnectionQueue # Connection management
└── SwiftStoreServer        # Development HTTP server with Web UI
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
       ↓
SwiftStoreServer (development only)
```

## Packages

| Package | Description |
|---------|-------------|
| [SwiftStoreProtocols](./SwiftStoreProtocols/) | Protocol definitions - EntityProtocol, SQLiteCodable, etc. |
| [SwiftStoreMacros](./SwiftStoreMacros/) | Macro definitions - @Entity(readonly:), #Index, #SyncKey, @Embedded, @Default |
| [SwiftStoreCore](./SwiftStoreCore/) | Core functionality - SQLite connection, query builder, migration |
| [SwiftStoreChangeTracker](./SwiftStoreChangeTracker/) | Change tracking - SQLite update hook to record changes |
| [SwiftStoreSync](./SwiftStoreSync/) | Data sync - Bidirectional sync, conflict resolution, NTP validation |
| [SwiftStoreConnectionQueue](./SwiftStoreConnectionQueue/) | Connection management - Single-writer multiple-reader pool, readonly mode |
| [SwiftStoreServer](./SwiftStoreServer/) | Development HTTP server with Web admin UI for database inspection |

## License

MIT
