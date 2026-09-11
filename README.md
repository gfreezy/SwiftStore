# SwiftStore

SQLite persistence for Swift, with macro-defined models, type-safe queries, FTS5 search,
versioned migrations, and multi-device synchronization through CloudKit.

## Requirements

Swift 6.0 / Xcode 16 or later. Supported platforms: macOS 14+, iOS 16+, tvOS 17+, watchOS 10+.
See [iOS 16 compatibility](docs/ios16-compatibility.md) for SQLite and CloudKit details.

## Installation

Add [SwiftStore](https://github.com/gfreezy/SwiftStore) as a Swift package dependency and
select a version from [Releases](https://github.com/gfreezy/SwiftStore/releases).

| Product | Use |
| --- | --- |
| `SwiftStore` | Core, connection pool and sync support |
| `SwiftStoreCore` | Models, queries, SQLite connections and migrations |
| `SwiftStoreConnectionQueue` | Serialized writes, pooled reads and sync coordination |
| `SwiftStoreMacros` | Macro declarations |
| `SwiftStoreSyncCloudTransport` | CloudKit sync client |
| `SwiftFileStore` | Independent local attachments with iCloud Drive synchronization (4.1.0+) |
| `SwiftStoreServer` | Development web interface and HTTP API |
| `SwiftStoreMigrationCheck` | Build plugin for migration checks |
| `swiftstore` | Migration CLI |

See [SwiftFileStore](SwiftFileStore/README.md) for its standalone package, stable local
URLs, offline saves, and reader lifetime handling. It does not require a SwiftStore database.

## Quick Start

### Define Entities

A writable `@Entity` requires `id: UUIDV7` or a `#SyncKey`, plus `createdAt: Date` and
`updatedAt: Date`. Use `@Embedded` for nested types stored as JSON.

```swift
import SwiftStoreCore

@Embedded
struct Address {
    var city: String = ""
}

@Entity
struct User {
    #Index<Self>(\.email, unique: true)
    #Index<Self>(\.address.city)

    var id: UUIDV7 = UUIDV7()
    var name: String
    var email: String
    var age: Int?
    var address: Address = Address()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}
```

Table and column names default to snake_case. Override the table with
`@Entity(tableName: "users")`. `#Index` supports multiple fields and nested JSON properties.

### Database Operations

[Enable the migration plugin and generate the initial migration](#schema-migrations) first.
The CLI writes `StoreMigrations.swift` alongside your migrations. Commit and compile it like ordinary Swift source; the build plugin only checks.
Bundle the `.schema.json` files as resources: SwiftPM callers pass `.module`, while Xcode apps can use `.main`. See [resource setup](docs/versioned-migrations.md) and [multiple databases](docs/multiple-databases.md#bundle-schema-resources).

```swift
let connection = try SQLiteConnection(path: "app.sqlite")
try VersionedMigrator(connection: connection, migrations: StoreMigrations.all(bundle: .module)).migrate()

var user = User(name: "Alice", email: "alice@example.com", age: 25)
try user.insert(connection)

let users = try User.filter { $0.age >= 18 }
    .order(by: \.name)
    .limit(20)
    .all(connection)

user.name = "Alice Smith"
try user.update(connection)
try user.delete(connection)
```

`save(connection)` inserts or updates by ID. `User.find(id, connection)` returns an optional;
`User.get(id, connection)` throws if the record is missing.

Queries also support nested fields, counts and bulk updates:

```swift
let count = try User.filter(\.address.city == "Beijing").count(connection)
let updated = try User.filter { $0.age == nil }.updateAll(connection, [\.age <- 18])
```

For custom SQL, use interpolation to bind values:

```swift
let minimumAge = 18
let sql: SQL = "SELECT name FROM user WHERE age >= \(minimumAge)"
let rows = try connection.query(sql)
```

### Sync Keys

Use a single or composite business key instead of an `id` property:

```swift
@Entity
struct UserDevice {
    #SyncKey<Self>(\.userId, \.deviceId)

    var userId: UUIDV7
    var deviceId: String
    var deviceName: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}
```

The macro generates the identity and uniqueness constraint. Do not declare an `id` property
alongside `#SyncKey`.

### Defaults and JSON Decoding

Use inline defaults for `var` properties or `@Default` for `let` properties:

```swift
@Embedded
struct Settings {
    @Default("light")
    let theme: String
    @Default(nil)
    let nickname: String?
}
```

`@Entity` and `@Embedded` generate Codable conformance and memberwise initializers.
A decoding error falls back to a declared default; without a default, invalid values throw.
For JSON, missing or null optional fields decode as `nil`, even with a non-nil default.
Required fields without defaults must be present. Nested structs must conform to `Embedded`.

### Full-text search (FTS5)

Use `#FullTextIndex` for `String` or `String?` fields, including nested `@Embedded` properties:

```swift
@Embedded
struct ArticleContent {
    var body: String?
}

@Entity
struct Article {
    #FullTextIndex<Self>(\.title, \.content.body)

    var id: UUIDV7 = UUIDV7()
    var title: String
    var content: ArticleContent
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

// Search a literal phrase.
let articles = try Article.search("database indexing")
    .limit(20)
    .all(connection)

// Use FTS5 operators, column filters and prefixes.
let matches = try Article.matching("title: swift OR content__body: index*")
    .all(connection)
```

After adding, changing or removing an index, generate and apply a
[migration](docs/versioned-migrations.md). `check` detects declarations without corresponding
migrations. Existing data is indexed during migration; later writes maintain indexes automatically.
Indexes stay local to each device.

The default name is `<table_name>_fts`. For multiple indexes, set distinct `name` arguments
and select one with `Article.search("text", index: "name")` or `Article.matching(..., index: "name")`.

Set `tokenizer:` to `.unicode61` (default), `.porter` (English stemming), or `.trigram`
(substring matching). Trigram requires at least three characters for MATCH; `unicode61`
does not segment Chinese words. Custom tokenizers, subscripts and optional chaining are unsupported.

The deployed SQLite library must support FTS5 and the selected tokenizer. For raw SQL writes,
prefer UPDATE or UPSERT. `REPLACE` requires `PRAGMA recursive_triggers = ON` on each writing
connection so deleted records are removed from the index.

### Readonly Entities

Use `@Entity(readonly: true)` to read an existing database with a different ID type or no
timestamp columns. It must be paired with a readonly `ConnectionManager`:

```swift
import SwiftStoreConnectionQueue

@Entity(readonly: true)
struct ImportedItem {
    var id: Int
    var title: String
}

let readonlyManager = try ConnectionManager(
    path: "existing.sqlite",
    entities: [ImportedItem.self],
    options: .init(readonly: true)
)
let items = try await readonlyManager.read { try ImportedItem.all($0) }
```

Readonly managers do not migrate, write or sync. For writable local data, use a normal
`@Entity` and omit `syncConfig`.

## Schema Migrations

Enable the build plugin on the target containing your Entities and migration Swift files:

```swift
.target(
    name: "MyApp",
    dependencies: [.product(name: "SwiftStore", package: "SwiftStore")],
    plugins: [.plugin(name: "SwiftStoreMigrationCheck", package: "SwiftStore")]
)
```

Generate the initial migration before changing the models, then add a migration for each
schema change:

```sh
swiftstore migration add 001_initial
# After editing models:
swiftstore migration add 002_add_fields
swiftstore migration check
```

Review the generated SQL. Renames, table rebuilds and required backfills produce a `#error`
placeholder for your SQL. Published migrations must remain unchanged.

Apply migrations before accessing the database. Tables containing `updated_at` receive an
update trigger; explicitly changed timestamps are preserved. FTS declarations participate in
migration generation and checks, including backfilling existing records.

For multiple databases in the same target, use [database groups in swiftstore.json](docs/multiple-databases.md).
Each database has independent Entity sources, migrations and generated Swift names.

See the [migration guide](docs/versioned-migrations.md) for CLI installation, Xcode setup,
manual migrations and adopting existing databases, and [schema comparison rules](docs/schema-canonicalization.md)
for snapshot defaults and JSON formatting.

## Connection Pool

Import `SwiftStore` or `SwiftStoreConnectionQueue` for `ConnectionManager`.
Writes are serialized and transactional; reads use a connection pool.

```swift
import SwiftStore

let manager = try ConnectionManager(path: "app.sqlite", entities: [User.self])
try await manager.migrate(migrations: try StoreMigrations.all(bundle: .module))

try await manager.write { connection in
    try User(name: "Bob", email: "bob@example.com", age: 30).insert(connection)
}
let users = try await manager.read { connection in
    try User.filter { $0.age >= 18 }.all(connection)
}
```

Use `ConnectionOptions` to configure the reader count, cache size and SQLite synchronous mode.
A raw `SQLiteConnection` must not be used concurrently.

## Multi-device Sync

Configure CloudKit and a stable, installation-local device ID. All sync state and the
append-only change log live in the business SQLite database, on its writer connection.

```swift
import SwiftStore

let manager = try ConnectionManager(
    path: "app.sqlite",
    entities: [User.self],
    syncConfig: SyncOptions(
        deviceId: deviceId,
        schemaVersion: 1,
        cloudKit: CloudKitSyncConfiguration(containerIdentifier: "iCloud.com.example.app")
    )
)
try await manager.migrate(migrations: try StoreMigrations.all(bundle: .module))
let result = try await manager.sync()
```

Migration captures existing rows once without changing their timestamps. Local changes
schedule synchronization by default. Set `automaticallySync: false` for manual control;
`stopSync()` pauses networking while local changes remain tracked. `sync()` resumes it.

The implementation uses CKSyncEngine on iOS 17+ and CloudKit Operations on iOS 16.
Newer business `updatedAt` wins; equal timestamps retain the authoritative CloudKit version.
Deletions are versioned tombstones. Remote writes never generate upload echoes.
Only events inside each fixed upload batch are coalesced; retries replay the original IDs
and payloads. A successful later item cannot advance the upload cursor past an unresolved item.

- [CloudKit setup and legacy migration](SwiftStoreSyncCloudTransport/README.md).
- [Sync architecture and recovery](docs/sync-architecture.md).
- [Change tracking and transaction behavior](docs/preupdate-change-tracking.md).

## Development Server

The development server provides SQL inspection at `/admin`. Add `SwiftStoreServer` as a target
dependency and retain the server instance for its lifetime:

```swift
#if DEBUG
import SwiftStoreServer

let server = try await SwiftStoreServer(
    connectionManager: manager,
    configuration: .init(port: 8080)
)
try await server.start()
#endif
```

Open [the admin UI](http://127.0.0.1:8080/admin) to browse tables, inspect schemas, run SQL and
export results as CSV. Configure `fileServerRoot` to enable `/files` and file API routes.
Use this server only for development and SQL inspection.

| Method | Endpoint | Use |
| --- | --- | --- |
| GET | `/api/health` | Health check |
| GET | `/api/schema` | Database schema |
| POST | `/api/query` | SELECT queries |
| POST | `/api/execute` | Write statements |
| GET | `/api/files/list` | List a directory |
| GET | `/api/files/download` | Download a file |
| POST | `/api/files/upload` | Upload a file |
| GET | `/api/files/info` | File metadata |

## Development

```sh
swift build
swift test
swift run MigrationExample
```

CloudKit driver tests use a simulated network service with real SQLite persistence. See
[CloudKit verification](SwiftStoreSyncCloudTransport/README.md#验证范围) for device testing requirements.

## License

MIT
