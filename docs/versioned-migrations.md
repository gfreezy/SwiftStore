# Incremental migrations: build plugin and optional CLI

Add SwiftStore and enable **SwiftStoreMigrationCheck** on the target containing your Entities and migration Swift files. The plugin checks the schema during normal builds and generates `StoreMigrations.all()`. You do not need a schema executable, a separate model module, a manually maintained registration list, or a `seal` command.

The optional `swiftstore` CLI writes the same files that you can maintain by hand. This format replaces the earlier `schema-history.json` / committed catalog format; there is no compatibility layer for those artifacts.

## Enable once

For a SwiftPM target:

```swift
.target(
    name: "MyApp",
    dependencies: [.product(name: "SwiftStore", package: "SwiftStore")],
    plugins: [.plugin(name: "SwiftStoreMigrationCheck", package: "SwiftStore")]
)
```

Place the files like this:

```text
Sources/MyApp/
├── User.swift
├── Post.swift
├── Migrations/
│   ├── 001_initial.swift
│   ├── 001_initial.schema.json
│   ├── 002_display_name.swift
│   ├── 002_display_name.schema.json
│   └── 003_clean_data.swift
└── swiftstore-migrations.json    # optional, for sync-enabled stores
```

The plugin reads the target's Swift sources and `Migrations` directory. SwiftPM may report JSON snapshots as unhandled files; they are plugin inputs and are not needed as application resources. You may list the JSON files in the target's `exclude` argument to silence that warning; the plugin still reads them.

For an Xcode project, add the package, select the target, and add **SwiftStoreMigrationCheck** under **Build Phases → Run Build Tool Plug-ins**. Put `Migrations` beside the `.xcodeproj`, and add its Swift files to that target's Compile Sources. JSON snapshots do not need target membership or copying into the application. The plugin scans the selected target's input Swift files, not every file in the project.

Use one schema/history per plugin-enabled target. Entities in another module are not discovered through imports; put the plugin, Entities, and migration declarations together in their owning module. If multiple Xcode targets use the same project-root history, they must have the same Entity schema and compile the same migration declarations.

## Generate with the optional tool

The CI release workflow publishes **macOS arm64 (Apple Silicon)** archives and `SHA256SUMS` on [GitHub Releases](https://github.com/gfreezy/SwiftStore/releases). After a release containing the CLI is published, download `swiftstore-<version>-macos-arm64.tar.gz` and `SHA256SUMS` into an empty directory, then:

```sh
shasum -a 256 -c SHA256SUMS
tar -xzf swiftstore-*-macos-arm64.tar.gz
mkdir -p "$HOME/.local/bin"
install -m 755 swiftstore "$HOME/.local/bin/swiftstore"
```

Ensure `$HOME/.local/bin` is on your PATH. The build plugin supplies its own tool from the package dependency; this separate installation is only for convenient generation. Alternatively, build from a SwiftStore checkout with `swift build -c release --product swiftstore` and use `.build/release/swiftstore`.

Inside your business project, create the first migration **before changing the current Entity definitions**:

```sh
swiftstore migration add 001_initial
```

After changing an Entity:

```sh
swiftstore migration add 002_display_name
```

Without `--target`, the CLI walks up from the current directory looking for an existing migration/configuration directory, an Xcode project, or `Package.swift`. It stops at the repository boundary. For SwiftPM it selects the enclosing source target when invoked from inside one; otherwise it selects the plugin-enabled target, or the sole target containing Entities/history. Static custom target paths are supported. Test targets are not candidates.

If no project/target is found, or more than one target matches, the command fails without generating files. It never silently treats an arbitrary current directory as a project. A computed Package.swift target list/path requires an explicit override; discovery does not execute the manifest or fetch dependencies.

Override detection when necessary:

```sh
swiftstore migration add 002_display_name --target Sources/MyModels
```

For an Xcode project, the schema root is the directory containing the `.xcodeproj` and `Migrations`. The CLI recursively scans Swift files below that directory, skipping hidden directories. For projects containing unrelated targets/tests, pass `--sources-file <json-file>` with an array of the exact source file paths for the model-owning target, matching the plugin's scope.

The generator writes only the tables that changed. Unchanged tables inherit their most recent definition. It never overwrites an existing migration. Use `<digits>_<description>`: the first underscore separates an ASCII numeric prefix from an unrestricted description (subject to filename restrictions). The underscore is required; the description may be empty and may contain Chinese, spaces, punctuation, or more underscores. Numbers must be unique, ignoring leading zeros: `001_initial` and `1_other` conflict. Migrations sort numerically (`2` before `10`), and a new number must exceed the latest one. Gaps and arbitrary digit lengths are allowed.

Safe structural additions generate SQL. Renames, dropped tables/columns, changed types or constraints, and additions requiring backfills produce a `#error` placeholder with the target definition. Replace it with the required SQL. A normal build then checks the snapshots and compiles your migration code. There is no sealing step.

You can also check without building:

```sh
swiftstore migration check
```

## Maintain files manually

A migration consists of `ID.swift` and an optional `ID.schema.json`. The Swift file declares `Migration_NUMBER` with a synchronous, throwing `static func up(_ db: SQLiteConnection)` method. The type uses only the numeric prefix, preserving leading zeros: `002_修改姓名.swift` declares `Migration_002`. No special annotation is needed.

For example, `002_display_name.swift`:

```swift
import SwiftStoreCore

enum Migration_002 {
    static func up(_ db: SQLiteConnection) throws {
        try db.execute("ALTER TABLE users RENAME COLUMN name TO display_name")
        try db.execute("UPDATE users SET display_name = trim(display_name)")
    }
}
```

If the previous `users` table contained only an integer primary key and a nullable name, its new `002_display_name.schema.json` can be:

```json
{
  "formatVersion": 1,
  "tables": [
    {
      "name": "users",
      "columns": [
        {"name": "id", "type": "INTEGER", "isPrimaryKey": true},
        {"name": "display_name", "type": "TEXT", "isNullable": true}
      ]
    }
  ]
}
```

Each listed table replaces its previous definition **in full**, including its columns, indexes, triggers and foreign keys. Do not list unchanged tables. In normal sync-capable Entities, include the actual UUID and timestamp columns too; the generator handles these automatically.

For columns, omitted `isNullable` and `isPrimaryKey` default to `false`; omitted `defaultValue` and `generatedAs` mean no default/generated expression. For tables, omitted `indexes`, `triggers` and `foreignKeys` default to empty arrays. Column order is part of the schema.

Explicitly mark table deletion:

```json
{"formatVersion": 1, "droppedTables": ["old_cache"]}
```

Omission never means deletion. A table rename consists of deleting the old name and supplying the new table definition in the delta; the Swift body can use `ALTER TABLE ... RENAME TO ...` to preserve data. Deleting an unknown table, replacing and deleting the same table, orphan snapshots, and duplicate IDs are errors.

A pure data migration, such as `003_clean_data.swift`, does not need a JSON file. Its target schema is inherited unchanged. The first migration must describe every initial table and create it in its body.

## What the build does

1. Reads the selected target's `@Entity` declarations.
2. Uses the **same Entity macro expansion implementation** as the compiler to derive columns, defaults, generated index columns and indexes.
3. Sorts migration IDs by numeric prefix and merges their table deltas into each historical target schema.
4. Compares the latest reconstructed schema with the current Entity schema, including deleted Entities/tables.
5. Generates the ordered registration code, embedded full target schemas, and source checksums into the plugin work directory.

The build does not write to the project's source directory or run migration bodies. Missing or incorrectly declared `Migration_NUMBER.up` methods are caught when the generated catalog is compiled. Changed source files or snapshots invalidate the catalog build output.

Source extraction does not type-check user code or evaluate build conditions. Conditional `@Entity` declarations and `#if` members inside an Entity are rejected rather than guessed. Keep the persisted schema stable across configurations. Handwritten `EntityProtocol` conformances and Entities produced by other code generators are outside this source-scanning workflow. Macro type/default mapping remains exactly the library's current behavior.

Only the final structural state is checked during build. A schema can match even if a data backfill is wrong; migration tests must verify historical upgrades and business data.

## Runtime

```swift
let manager = try ConnectionManager(path: databasePath, entities: [User.self, Post.self])
try await manager.migrate(migrations: try StoreMigrations.all())
```

For direct connections:

```swift
try VersionedMigrator(connection: db, migrations: StoreMigrations.all()).migrate()
```

The generated registry reconstructs complete snapshots for the runner; full snapshots are not duplicated in the project's JSON files. The runner verifies applied history and schema, executes pending steps in order, checks the resulting schema/foreign keys, and records successful IDs and checksums atomically. A failure rolls back the entire pending batch. ConnectionManager releases its read/write setup gate and starts tracking only after success.

A fresh database replays all steps, including data-only migrations. Cross-version upgrades execute every pending step. Unchanged tables are not rebuilt by the incremental format. SQL bodies can still explicitly change any table when needed.

Keep business transformations within each migration's own file and use historical SQL, not current Entity types. The checksum covers the source file and reconstructed target schema; it cannot freeze external helper implementations. Do not commit, roll back, perform network actions, or call `manager.write` from a body.

Published migration files must remain immutable. Editing them changes the generated checksum, so a database that already executed them rejects the history. Add a new migration for corrections. The build itself cannot know which versions users have already installed.

Schema validation is intentionally strict. It checks managed table definitions, defaults, indexes and triggers and permits unrelated tables. Custom schema objects must be represented in snapshots. Some semantically equivalent but structurally different SQL definitions may be rejected. Large backfills hold the migration transaction for their duration; resumable online migration is outside this API.

## Sync configuration

If ConnectionManager enables sync, create `swiftstore-migrations.json` in the schema root:

```json
{"createUpdateTrigger": true}
```

The default is `false`. Both CLI and plugin read this setting. It must match the manager's sync configuration. A configuration change that alters triggers requires a new migration. Migration IDs are independent of the sync protocol's schema version. Whether migrated data is uploaded later by sync bootstrap is a separate application policy.

## Example and tests

From the library checkout:

```sh
swift run swiftstore migration check --target Examples/VersionedMigrations
swift run MigrationExample
swift test
python3 IntegrationTests/VersionedMigrations/test_external_package.py
```

The example uses the public plugin directly, with no schema tool target. The external-package test verifies consumer dependency setup, a rejected schema change, table-level deltas, a manually completed rename, a data-only step, preserved data in unchanged tables, repeat startup and rejection of modified applied history.

## Binary release CI

`.github/workflows/release-cli.yml` builds the CLI natively on a macOS arm64 runner when a version tag is pushed (`1.3.0` or `v1.3.0` style). It can also be dispatched manually with an existing version tag that contains the workflow/tool changes.

CI verifies the checkout against the tag, builds an optimized standalone binary, checks its architecture and executes it outside the build directory, packages it with SHA-256 checksums, and uploads both assets to the tag's GitHub Release. A new release remains a draft until uploads finish. It then downloads the published files, verifies their checksums and runs the downloaded executable. Workflow artifacts are retained as well. Intel and Linux binaries are not produced.
