# SwiftStore

A lightweight SQLite-based data persistence framework for Swift, with multi-device sync support.

## Features

- **Declarative API** - Swift macros auto-generate boilerplate code
- **Type-safe Queries** - Compile-time checked query builder
- **Versioned Migrations** - [Checked-in migrations, incremental table snapshots, a build plugin and optional CLI](#schema-migrations), with editable data migrations
- **Multi-device Sync** - Changelog-based bidirectional synchronization
- **High Performance** - SQLite WAL mode + single-writer multiple-reader connection pool
- **Dev Server** - Built-in web admin UI for database inspection and file management

## Requirements

- Swift 6.0+
- Xcode 16+
- macOS 14+ / iOS 16+ / tvOS 17+ / watchOS 10+

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/gfreezy/SwiftStore", from: "2.0.1")
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

First [enable the migration plugin and generate the initial migration](#schema-migrations) for the target containing your Entities. The build generates `StoreMigrations.all()`, used below.

```swift
// Create connection
let connection = try SQLiteConnection(path: "database.sqlite")

// Apply committed migrations before accessing data.
try VersionedMigrator(connection: connection, migrations: StoreMigrations.all()).migrate()

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

Generate the history as described in [Schema Migrations](#schema-migrations). Tables with `updated_at` automatically receive an update trigger, whether or not sync is enabled.

```swift
// Create connection manager with sync
let manager = try ConnectionManager(
    path: "database.sqlite",
    entities: [User.self],
    syncConfig: SyncOptions(
        deviceId: myDeviceId,
        transport: myTransport,          // e.g. CloudKitSyncTransport
        schemaVersion: 1
    )
)

// Complete setup before reading, writing, or syncing.
try await manager.migrate(migrations: try StoreMigrations.all())

// Perform sync. The transport is lazily started on the first call;
// subsequent remote-change notifications auto-trigger sync in the background.
let result = try await manager.sync()
print("Pulled: \(result.pulledCount), Pushed: \(result.pushedCount)")
```

See [§6.1 CloudKit transport](#61-cloudkit-transport) for the ready-made
CloudKit implementation, and [§6 Multi-device Sync](#6-multi-device-sync)
for a full example including how to implement `SyncTransport` yourself.

## Schema Migrations

SwiftStore uses checked-in versioned migrations for schema and data changes. Review the generated SQL, add data transformations, and replay the committed history on fresh installs and upgrades. Runtime schema auto-alignment has been removed. An existing database without migration history requires explicit baseline adoption.

### 1. Enable the build plugin

Add `SwiftStoreMigrationCheck` to the target containing your Entities and migration Swift files:

```swift
// In Package.swift's targets array
.target(
    name: "MyModels",
    dependencies: [.product(name: "SwiftStore", package: "SwiftStore")],
    plugins: [.plugin(name: "SwiftStoreMigrationCheck", package: "SwiftStore")]
)
```

The plugin checks that the latest migration schema matches the target's Entities and generates `StoreMigrations.all()` during the build. Keep the Entities and migration declarations in the same target. For Xcode setup and CLI installation, see the [full migration guide](docs/versioned-migrations.md).

Tables with an `updated_at` column automatically receive an update trigger. The CLI, build plugin, and runtime use this same rule for both local and sync-enabled stores; no migration configuration file is needed. The trigger supplies the current time when an update leaves `updated_at` unchanged and preserves an explicitly changed timestamp.

If an existing history lacks these triggers, generate a new migration to add them. Keep earlier migration files unchanged. Enabling sync later does not itself require a schema migration.

### 2. Generate and review migrations

Create the initial migration from the current Entities before changing their schema:

```sh
swiftstore migration add 001_initial --target Sources/MyModels
```

After changing an Entity, generate the next migration:

```sh
swiftstore migration add 002_display_name --target Sources/MyModels
```

Each migration has a Swift file and, for schema changes, a JSON delta:

```text
Sources/MyModels/Migrations/
├── 001_initial.swift
├── 001_initial.schema.json
├── 002_display_name.swift
└── 002_display_name.schema.json
```

- IDs use `<digits>_<description>` and sort by the numeric prefix: `2` comes before `10`. Numbers must be unique ignoring leading zeros, and each new number must exceed the latest one. Descriptions can contain Chinese, spaces, or punctuation allowed in filenames; quote IDs containing spaces in shell commands.
- The Swift type uses only the numeric prefix: `002_display_name.swift` declares `Migration_002` with `static func up(_ db: SQLiteConnection) throws`.
- Safe additions generate SQL. Renames, removals, and changes requiring backfills generate a `#error` placeholder; replace it with SQL that preserves existing data.
- JSON files contain complete definitions of changed tables. Unchanged tables inherit their previous definitions. A data-only migration needs only its Swift file.

Commit the migration files. Keep published migrations immutable: editing an applied migration changes its checksum and causes startup to reject the history. Builds check schema agreement and compile the migration code; test historical upgrades to verify data transformations.

To check schema agreement without building:

```sh
swiftstore migration check --target Sources/MyModels
```

### 3. Apply migrations at startup

For a target whose schema contains `User` and `Post`, register the same entities with the manager and apply the generated history before any reads, writes, or sync:

```swift
let manager = try ConnectionManager(path: dbPath, entities: [User.self, Post.self])
try await manager.migrate(migrations: try StoreMigrations.all())
```

For a direct connection:

```swift
let connection = try SQLiteConnection(path: dbPath)
try VersionedMigrator(connection: connection, migrations: StoreMigrations.all()).migrate()
```

The runner verifies applied checksums and schemas, executes pending migrations in order, and commits the pending batch atomically. A failure rolls back the batch. Repeated startup does not rerun applied migrations. `manager.previewMigrations(...)` returns pending IDs without executing bodies or completing setup.

For an existing database without migration history, explicitly adopt a migration whose target schema matches that database:

```swift
try await manager.migrate(
    migrations: try StoreMigrations.all(),
    adoptingBaseline: "001_initial"
)
```

Baseline adoption verifies the schema and records the selected prefix without executing its bodies, then applies later migrations. Use this startup call in place of the normal migration call when adopting a legacy database; it also works for fresh and already tracked databases.

## Complete Example

The following examples use a plugin-enabled target containing `User`, `Post`, `UserDevice`, and `Favorite`. Generate its initial migration after defining those models. Connection and sync setups are alternatives: use the trigger configuration matching the selected setup. Enabling sync on an existing database requires a new migration adding the update triggers.

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

```

Keep readonly mappings for separately managed databases in another target, outside this migration history:

```swift
// MARK: - Readonly Entity (flexible id type)

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

// The build plugin generates this history from the committed migration files.
try VersionedMigrator(connection: connection, migrations: StoreMigrations.all()).migrate()

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
    entities: [User.self, Post.self, UserDevice.self, Favorite.self]
)
try await manager.migrate(migrations: try StoreMigrations.all())

// Custom options
let managerWithOptions = try ConnectionManager(
    path: dbPath,
    entities: [User.self, Post.self, UserDevice.self, Favorite.self],
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
    entities: [LocalConfig.self],  // Requires @Entity(readonly: true)
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

`SyncTransport` is a lifecycle-aware, observer-style protocol. Implementations
own their own remote-cursor state; `SyncManager` only tracks `lastLocalClock`
locally. You implement four methods plus an `AsyncStream` for remote-activity
signals:

```swift
public protocol SyncTransport: Sendable {
    /// Signal-only stream: yields when the transport observes remote
    /// activity (push notification, poll tick, etc.). WritableConnectionActor
    /// consumes it to auto-trigger a sync.
    var remoteChanges: AsyncStream<Void> { get }

    /// Activate. Idempotent. Called lazily on the first sync.
    func start(deviceId: UUIDV7) async throws

    /// Deactivate. Finishes `remoteChanges`.
    func stop() async

    /// Stage local changes for the next cycle. No network I/O here.
    func enqueue(_ changes: [SyncChange]) async throws

    /// Run upload arbitration, then pull and reconcile rejected keys.
    func syncNow() async throws -> SyncCycleResult
}
```

#### Implementing SyncTransport for a REST backend

```swift
import SwiftStoreSync

actor RESTSyncTransport: SyncTransport {
    private let serverURL: URL
    private var cursor: String?      // opaque server cursor
    private var pending: [SyncChange] = []
    private var deviceId: UUIDV7?

    private nonisolated let _stream: AsyncStream<Void>
    private nonisolated let _continuation: AsyncStream<Void>.Continuation
    nonisolated var remoteChanges: AsyncStream<Void> { _stream }

    init(serverURL: URL) {
        self.serverURL = serverURL
        let (s, c) = AsyncStream<Void>.makeStream()
        self._stream = s
        self._continuation = c
    }

    func start(deviceId: UUIDV7) async throws { self.deviceId = deviceId }

    func stop() async { _continuation.finish() }

    func enqueue(_ changes: [SyncChange]) async throws {
        pending.append(contentsOf: changes)
    }

    func syncNow() async throws -> SyncCycleResult {
        guard let deviceId else { throw MySyncError.notStarted }

        // 1. Pull
        var pullReq = URLRequest(url: serverURL.appendingPathComponent("pull"))
        pullReq.httpMethod = "POST"
        pullReq.httpBody = try JSONEncoder().encode(
            PullBody(cursor: cursor, deviceId: deviceId.description))
        let (pullData, _) = try await URLSession.shared.data(for: pullReq)
        let pullResp = try JSONDecoder().decode(PullResp.self, from: pullData)
        cursor = pullResp.nextCursor

        // 2. Push what was staged
        let toPush = pending
        pending.removeAll()
        var pushReq = URLRequest(url: serverURL.appendingPathComponent("push"))
        pushReq.httpMethod = "POST"
        pushReq.httpBody = try JSONEncoder().encode(
            PushBody(changes: toPush, deviceId: deviceId.description))
        let (pushData, _) = try await URLSession.shared.data(for: pushReq)
        let pushResp = try JSONDecoder().decode(PushResp.self, from: pushData)

        return SyncCycleResult(
            pulled: pullResp.changes,
            pushed: toPush.map(\.id).filter { !pushResp.conflictIds.contains($0) },
            conflicts: toPush.filter { pushResp.conflictIds.contains($0.id) }
        )
    }
}
```

#### Wiring sync into ConnectionManager

The same migration history supports local and sync-enabled managers. `syncConfig` controls synchronization without changing the generated table schema.

```swift
let deviceId = loadOrGenerateDeviceId()      // persist across launches
let transport = RESTSyncTransport(serverURL: URL(string: "https://api.example.com")!)

let manager = try ConnectionManager(
    path: dbPath,
    entities: [User.self, Post.self, UserDevice.self, Favorite.self],
    syncConfig: SyncOptions(
        deviceId: deviceId,
        transport: transport,
        schemaVersion: 1,
        ntpToleranceMs: 5000        // reject sync if clock drifts > 5s
    )
)

try await manager.migrate(migrations: try StoreMigrations.all())

// Trigger sync. First call lazily starts the transport and spawns a
// background observer that re-triggers sync() whenever the transport
// yields on `remoteChanges`. The `lastLocalClock` watermark is persisted
// automatically in the changelog DB — no manual save/restore needed.
do {
    let result = try await manager.sync()
    print("""
    Sync completed:
    - Pulled:    \(result.pulledCount)
    - Pushed:    \(result.pushedCount)
    - Conflicts: \(result.conflictCount)
    """)

    // Optional: inspect the current watermark for UI / telemetry.
    if let state = await manager.syncState {
        print("last local clock: \(state.lastLocalClock)")
    }
} catch let error as NTPError {
    print("Time out of sync: \(error)")
} catch let error as SyncError {
    print("Sync error: \(error)")
}
```

Both built-in transports share the same conflict policy: newer `updatedAt` in
Unix milliseconds wins; equal timestamps keep the committed remote version.
`SyncTransport` resolves uploads first, then uses normal pull to reconcile
`rejectedKeys`. Missing versions use carried CloudKit content or an HTTP key lookup.
`SyncCycleResult` retains corrections until applied; `SyncManager` does not resolve conflicts again.
CloudKit implements this behind the adapter with conditional change-tag saves;
HTTP delegates it to the server. See the [shared backend contract](docs/sync-backend-contract.md)
for interfaces, durability requirements, and custom-transport migration.

Local changes are captured as owned row snapshots through SQLite's pre-update
hook. Remote writes are excluded at capture time, and timestamp-trigger events
are coalesced before logging. Deletes are captured directly without delete-tracking
triggers or intermediate tables. See [change tracking internals](docs/preupdate-change-tracking.md)
for transaction behavior and platform requirements.

### 6.1 CloudKit transport

For iCloud-backed sync, import `SwiftStoreSyncCloudTransport` — a
ready-made `SyncTransport` using `CKSyncEngine` on iOS 17+ and CloudKit zone
operations on iOS 16. Both share the same durable journal and conflict rules.
For iOS 16 background push integration, see [iOS 16 support](docs/ios16-compatibility.md). Inserts, updates,
and deletion tombstones share a `CKRecord.ID` using the same opaque SHA-256 key
as HTTP. Both transports use `SyncRecordEnvelope`: Unix-millisecond `updatedAt`
and a complete opaque payload. CloudKit stores the payload as a Base64 string or
`CKAsset`; entity metadata and modification IDs are only inside that payload.
Only strictly newer timestamps replace committed versions. Equal-time retries
also retain the cloud version and enter rejection reconciliation, without an
ID-based success shortcut. Logical clocks only track the local upload watermark.

```swift
import CloudKit
import SwiftStoreConnectionQueue
import SwiftStoreSyncCloudTransport

// 1. Keep device-local state outside iCloud Drive. Use a separate directory
//    for each database/account/container. Never share this directory across devices.
let stateDir = URL.applicationSupportDirectory.appending(path: "sync-cloud-state")
let stateStore = try FileCloudKitSyncStateStore(directory: stateDir)

// 2. Build the transport.
let cloudTransport = CloudKitSyncTransport(
    config: CloudKitTransportConfig(
        container: CKContainer(identifier: "iCloud.com.example.MyApp")
        // zoneName, recordType, assetThreshold, subscriptionID all have defaults
    ),
    stateStore: stateStore
)

// 3. Wire it into ConnectionManager like any other transport.
let manager = try ConnectionManager(
    path: dbPath,
    entities: [User.self, Post.self, UserDevice.self, Favorite.self],
    syncConfig: SyncOptions(
        deviceId: loadOrGenerateDeviceId(),
        transport: cloudTransport,
        schemaVersion: 1
    )
)

// 4. Migrate first: this activates tracking and captures preexisting rows.
try await manager.migrate(migrations: try StoreMigrations.all())

// Start sync at launch, and request another round on foreground/manual refresh.
// Subsequent local writes and CloudKit background activity trigger sync automatically.
try await manager.sync()

// Optional: pause networking while continuing to track local edits.
// await manager.stopSync()
// try await manager.sync() // resumes using persisted queues
```

**Project setup:** enable *iCloud / CloudKit* with the configured container,
*Push Notifications*, and (on iOS) *Background Modes / Remote notifications*.
Register for remote notifications in the host app. The transport ensures its
private-DB subscription exists, assigns it to `CKSyncEngine`, and creates
`SwiftStoreSyncChanges` on first sync. Background scheduling and retry timing
are controlled by the system; manual `manager.sync()` remains available.
See [Apple's CKSyncEngine sample](https://github.com/apple/sample-cloudkit-sync-engine)
for host-app capabilities and notification registration.

**Durability:** the engine cursor, pending uploads, downloaded changes,
acknowledgements, and record system fields are saved together in `journal.plist`.
Downloaded changes remain there until their local application is acknowledged.
Time verification is mandatory: `SyncOptions.ntpToleranceMs` defaults to 5000
(±5 seconds), must be positive, and no longer accepts `nil`. The same tolerance
is passed to CloudKit for automatic uploads and fetches. If verification fails
or the clock is outside the range, uploads/local application are blocked and
queued data is retained. Direct transport users configure the required tolerance
on `CloudKitTransportConfig`.
Invalid payloads and future-schema changes remain pending for repair or app upgrade.
`await cloudTransport.lastError` exposes callback failures, including background failures.

**Deletion:** deletions are retained as timestamped tombstone records. Physical
CloudKit record deletions lack a timestamp and are reported as errors.

**Custom state storage:** implementations of `CloudKitSyncStateStore` must
implement `loadJournal()` and `saveJournal(_:)` with atomic persistence.

**Account and reset handling:** state is bound to one account/container/zone.
Account switches and remote zone deletion stop synchronization with an explicit
error and preserve local data. Use a separate local database, changelog, and state
directory for a different account. Do not reuse a cursor with a different database,
and do not clear only `journal.plist` to repair a reset.

See [implementation and verification notes](SwiftStoreSyncCloudTransport/README.md)
for the complete data flow, upgrade details, and device verification steps.

### 6.2 Custom HTTP sync server

`SwiftStoreSyncHTTPTransport` provides a durable HTTP transport for an existing
backend. Implement `POST /sync/v1/push`, `GET /sync/v1/pull`, and
`POST /sync/v1/records` according to the
[server API specification](docs/http-sync-server-api.md). It includes authentication,
wire examples, timestamp encoding, server-owned conflict decisions, opaque payloads,
idempotent retries, pagination, and a cross-device acceptance checklist.

Configure `HTTPSyncTransport` with the server URL, namespace, Bearer Token and a
dedicated state file, then pass it to `SyncOptions.transport`. Pending uploads,
unapplied downloads and cursor checkpoints survive restarts. Polling signals
`SyncManager` every 30 seconds by default; clock validation remains mandatory.
Each cycle freezes its upload list, confirms all batches, then pulls every page
and looks up unresolved rejected keys. New edits wait for the next cycle.
The HTTP envelope contains only `key`, `updatedAt`, and `payload`; rejection entries
contain `key` and `sequence`. The server needs no modification IDs or receipt table:
strictly increasing timestamps make retries safe without appending duplicate deltas.
The server compares only `updatedAt` (Unix milliseconds) for an opaque record key;
equal timestamps retain the existing server version. Entity type, business fields,
schema version and deletion details stay inside the payload. The HTTP client applies
server decisions directly, using server sequence numbers only to discard stale delivery.

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

This standalone example assumes a plugin-enabled target containing `User`, `Post`, and their committed migrations, with update triggers disabled.

```swift
import SwiftStore
import SwiftStoreServer

let manager = try ConnectionManager(
    path: "app.sqlite",
    entities: [User.self, Post.self]
)
try await manager.migrate(migrations: try StoreMigrations.all())

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
| [SwiftStoreChangeTracker](./SwiftStoreChangeTracker/) | Change tracking - pre-update row snapshots, trigger coalescing, and durable change logs |
| [SwiftStoreSync](./SwiftStoreSync/) | Data sync - Bidirectional sync, conflict resolution, NTP validation |
| [SwiftStoreConnectionQueue](./SwiftStoreConnectionQueue/) | Connection management - Single-writer multiple-reader pool, readonly mode |
| [SwiftStoreServer](./SwiftStoreServer/) | Development HTTP server with Web admin UI for database inspection |

## License

MIT
