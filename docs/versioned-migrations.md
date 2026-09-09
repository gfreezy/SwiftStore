# Versioned migrations

Enable **SwiftStoreMigrationCheck** on the target containing your Entities and migration Swift files.
The plugin checks the schema during builds and generates `StoreMigrations.all()`.
The optional `swiftstore` CLI generates migration Swift files and incremental JSON snapshots.

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
└── Migrations/
    ├── 001_initial.swift
    ├── 001_initial.schema.json
    ├── 002_display_name.swift
    ├── 002_display_name.schema.json
    └── 003_clean_data.swift
```

The plugin reads the target's Swift sources and `Migrations` directory. SwiftPM may report JSON snapshots as unhandled files; they are plugin inputs and are not needed as application resources. You may list the JSON files in the target's `exclude` argument to silence that warning; the plugin still reads them.

For an Xcode project, add the package, select the target, and add **SwiftStoreMigrationCheck** under **Build Phases → Run Build Tool Plug-ins**. Put `Migrations` beside the `.xcodeproj`, and add its Swift files to that target's Compile Sources. JSON snapshots do not need target membership or copying into the application. The plugin scans the selected target's input Swift files, not every file in the project.

Use one schema/history per plugin-enabled target. Entities in another module are not discovered through imports; put the plugin, Entities, and migration declarations together in their owning module. If multiple Xcode targets use the same project-root history, they must have the same Entity schema and compile the same migration declarations.

## Generate with the optional tool

Download the macOS arm64 (Apple Silicon) CLI archive and `SHA256SUMS` from the selected
[GitHub Release](https://github.com/gfreezy/SwiftStore/releases) into an empty directory, then:

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

Without `--target`, the CLI walks up from the current directory looking for an existing migration directory, an Xcode project, or `Package.swift`. It stops at the repository boundary. For SwiftPM it selects the enclosing source target when invoked from inside one; otherwise it selects the plugin-enabled target, or the sole target containing Entities/history. Static custom target paths are supported. Test targets are not candidates.

If no project/target is found, or more than one target matches, the command fails without generating files. It never silently treats an arbitrary current directory as a project. A computed Package.swift target list/path requires an explicit override; discovery does not execute the manifest or fetch dependencies.

Override detection when necessary:

```sh
swiftstore migration add 002_display_name --target Sources/MyModels
```

For an Xcode project, the schema root is the directory containing the `.xcodeproj` and `Migrations`. The CLI recursively scans Swift files below that directory, skipping hidden directories. For projects containing unrelated targets/tests, pass `--sources-file <json-file>` with an array of the exact source file paths for the model-owning target, matching the plugin's scope.

The generator writes only changed tables and never overwrites a migration. IDs use
`<digits>_<description>`; the underscore is required, and descriptions may contain Chinese or spaces.
Numbers sort numerically and must be unique, ignoring leading zeros (`001_initial` conflicts with `1_other`).
New numbers must exceed the latest migration; gaps are allowed.

Safe structural additions generate SQL. Renames, dropped tables/columns, changed types or constraints, and additions requiring backfills produce a `#error` placeholder with the target definition. Replace it with the required SQL. A normal build checks the snapshots and compiles your migration code.

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

Each listed table replaces its previous definition **in full**, including its columns, indexes, triggers, foreign keys and full-text indexes. Do not list unchanged tables. In normal sync-capable Entities, include the actual UUID and timestamp columns too; the generator handles these automatically.

For columns, omitted `isNullable` and `isPrimaryKey` default to `false`; omitted `defaultValue` and `generatedAs` mean no default/generated expression. For tables, omitted `indexes`, `triggers`, `foreignKeys` and `fullTextIndexes` default to empty arrays.
Column order is part of the schema. See [canonical comparison rules](schema-canonicalization.md)
for null handling and checksum encoding.

Explicitly mark table deletion:

```json
{"formatVersion": 1, "droppedTables": ["old_cache"]}
```

Omission never means deletion. A table rename consists of deleting the old name and supplying the new table definition in the delta; the Swift body can use `ALTER TABLE ... RENAME TO ...` to preserve data. Deleting an unknown table, replacing and deleting the same table, orphan snapshots, and duplicate IDs are errors.

A pure data migration, such as `003_clean_data.swift`, does not need a JSON file. Its target schema is inherited unchanged. The first migration must describe every initial table and create it in its body.

## What the build does

1. Reads the selected target's `@Entity` declarations.
2. Uses the **same Entity macro expansion implementation** as the compiler to derive columns, defaults, generated index columns, ordinary indexes and FTS5 declarations.
3. Sorts migration IDs by numeric prefix and merges their table deltas into each historical target schema.
4. Compares the canonical latest schema with the current Entity schema, including removed tables and FTS changes.
5. Generates the ordered registration code, embedded full target schemas, and source checksums into the plugin work directory.

The build does not write to the project's source directory or run migration bodies. Missing or incorrectly declared `Migration_NUMBER.up` methods are caught when the generated catalog is compiled. Changed source files or snapshots invalidate the catalog build output.

Source extraction does not type-check user code or evaluate build conditions. Conditional `@Entity` declarations and `#if` members inside an Entity are rejected rather than guessed. Keep the persisted schema stable across configurations. Handwritten `EntityProtocol` conformances and Entities produced by other code generators are outside this source-scanning workflow. Macro type/default mapping remains exactly the library's current behavior.

Only the final structural state is checked during build. A schema can match even if a data backfill is wrong; migration tests must verify historical upgrades and business data.

## Runtime

Apply committed migrations before accessing a database. Changing live Entity definitions alone does not upgrade existing data.

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

Runtime verification checks managed tables, defaults, indexes, triggers and FTS auxiliary objects.
Managed objects must match their snapshots; unrelated tables are permitted. Some structurally different
SQL definitions are rejected even if semantically equivalent. Large backfills hold the migration
transaction for their duration.

## Adopt an existing database

For a database created before versioned history was enabled, generate an initial migration from its original Entity definitions, before making further schema changes. Then opt into adopting that matching baseline at startup:

```swift
try await manager.migrate(
    migrations: try StoreMigrations.all(),
    adoptingBaseline: "001_initial"
)
```

The manager verifies the selected schema, records its history prefix without executing those bodies, and applies later migrations. This call also works on fresh and already tracked databases. A mismatched legacy schema is rejected; it is never automatically aligned or silently marked current.

## Update timestamps and sync

Tables with an `updated_at` column always receive an automatic update trigger when their schema is generated. Tables without that column receive no such trigger. The CLI, build plugin, and ConnectionManager use the same rule; it does not depend on `syncConfig`. Local updates maintain modification times even before sync is enabled. An explicitly changed `updated_at` value is preserved.

Enabling or disabling sync alone does not require a schema migration. Migration IDs are independent
of the sync protocol's schema version.

## Full-text indexes

`#FullTextIndex` participates in generation and `check`, including nested JSON paths, index names,
indexed fields and tokenizer selection. Add a migration after changing or removing a declaration.

The generated migration creates local mapping tables, content views, FTS5 tables and maintenance
triggers, then indexes existing data. When an indexed table's schema changes, its derived search
objects are rebuilt together. Removing FTS drops those objects while retaining business data.

For manual table rebuilds, also recreate the target FTS objects shown in the generated reference SQL.
Do not preserve an FTS index while discarding or reassigning its mapping IDs. The runtime verifies
auxiliary objects and checks that removed objects were cleaned up.

Declaration and query examples are in the [FTS5 guide](../README.md#full-text-search-fts5).

## Example and tests

From the library checkout:

```sh
swift run swiftstore migration check --target Examples/VersionedMigrations
swift run MigrationExample
swift test
python3 IntegrationTests/VersionedMigrations/test_external_package.py
```

The example uses the public plugin directly, with no schema tool target. The external-package test verifies consumer dependency setup, a rejected schema change, table-level deltas, a manually completed rename, a data-only step, preserved data in unchanged tables, repeat startup and rejection of modified applied history.

CLI packaging is defined in the [release workflow](../.github/workflows/release-cli.yml).
