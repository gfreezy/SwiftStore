# Versioned migrations

Enable **SwiftStoreMigrationCheck** on the target containing your Entities and migration Swift files.
The plugin only checks schemas and registration metadata during builds; it does not generate Swift
code or change application behavior. The `swiftstore` CLI writes migration Swift files, incremental
JSON snapshots and an editable `StoreMigrations.swift` catalog. Commit the catalog and compile it
with the migration files. Projects can also maintain these files manually.

## Enable once

For a SwiftPM target:

```swift
.target(
    name: "MyApp",
    dependencies: [.product(name: "SwiftStore", package: "SwiftStore")],
    resources: [.copy("Migrations/001_initial.schema.json"),
                .copy("Migrations/002_display_name.schema.json")],
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
    ├── 003_clean_data.swift
    └── StoreMigrations.swift
```

In the default single-database layout, the plugin reads the target's Swift sources and `Migrations` directory. JSON files are also runtime resources: list each JSON file in SwiftPM `resources` as above and call `StoreMigrations.all(bundle: .module)`. Add a resource declaration when adding a schema file. Do not copy or process the entire mixed `Migrations` directory: SwiftPM would treat its Swift files as resources too. For automatic inclusion of new JSON files, use a separate `schemas` directory and copy that directory as described in the [multiple-database guide](multiple-databases.md#bundle-schema-resources).

For an Xcode project, add the package, select the target, and add **SwiftStoreMigrationCheck** under **Build Phases → Run Build Tool Plug-ins**. Put `Migrations` beside the `.xcodeproj`, and add its Swift files to that target's Compile Sources. Add JSON snapshots to Copy Bundle Resources; preserve separate resource subdirectories for multiple databases. The default bundle is `.main`. The plugin scans the selected target's input Swift files, not every file in the project.

If Xcode reports `sandbox-exec: execvp()` with a missing `SwiftStoreMigrationCLI`, the
host tool has not been built, so migration checking has not started. Releases through
3.0.1 share one executable target between two products, which can leave the tool out
of Xcode's build dependencies. Upgrade to 3.0.2 or later: each product has its own
executable target and shares the command implementation. If staying on an affected
version, omit the optional plugin and run `swiftstore migration check` before building.

Without `swiftstore.json`, each plugin-enabled target uses one database, one `Migrations` directory,
and the `StoreMigrations.all()` entry point. In a configured project, omitting `namespace` or
setting it to `"default"` preserves exactly these names; only one default namespace is allowed per target. For multiple databases in the same target, configure
separate Entity sources, migration directories and Swift namespaces in
[swiftstore.json](multiple-databases.md). `migration check` defaults to checking **all configured
databases**, while the build plugin checks all databases belonging to its current target.

Entities in another module are not discovered through imports; put the plugin, Entities, and
migration declarations together in their owning module. In the unconfigured Xcode layout,
targets sharing the project-root history must have the same Entity schema and compile the same
migration declarations.

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

The CLI first looks for `swiftstore.json`, stopping at the repository boundary. If found, paths
are relative to that file; use `--database` to select a database for generation and `--target-name`
to narrow a multi-target configuration. Without configuration or `--target`, the CLI walks up from the current directory looking for an existing migration directory, an Xcode project, or `Package.swift`. It stops at the repository boundary. For SwiftPM it selects the enclosing source target when invoked from inside one; otherwise it selects the plugin-enabled target, or the sole target containing Entities/history. Static custom target paths are supported. Test targets are not candidates.

If no project/target is found, or more than one target matches, the command fails without generating files. It never silently treats an arbitrary current directory as a project. A computed Package.swift target list/path requires an explicit override; discovery does not execute the manifest or fetch dependencies.

Override detection when necessary:

```sh
swiftstore migration add 002_display_name --target Sources/MyModels
```

For an Xcode project, the schema root is the directory containing the `.xcodeproj` and `Migrations`. The CLI recursively scans Swift files below that directory, skipping hidden directories. For projects containing unrelated targets/tests, pass `--sources-file <json-file>` with an array of the exact source file paths for the model-owning target, matching the plugin's scope.

The generator writes only changed tables and never overwrites a migration. It also creates the
catalog, or appends the new registration while preserving existing source and comments. IDs use
`<digits>_<description>`; the underscore is required, and descriptions may contain Chinese or spaces.
Numbers sort numerically and must be unique, ignoring leading zeros (`001_initial` conflicts with `1_other`).
New numbers must exceed the latest migration; gaps are allowed.

Safe structural additions generate SQL. Renames, dropped tables/columns, changed types or constraints, and additions requiring backfills produce a `#error` placeholder with the target definition. Replace it with the required SQL. A normal build checks the snapshots and compiles your migration code.

You can also check without building:

```sh
swiftstore migration check
```

## Editable registration catalog

`migration add` writes `Migrations/StoreMigrations.swift` (or `NamespaceMigrations.swift` for a named
database namespace). Add this file to Xcode Compile Sources along with the migration Swift files;
SwiftPM discovers them in the target directory automatically. The catalog references bundled JSON deltas and each migration's ordinary compiled `up` method; no JSON payload is embedded in Swift.

After adding/removing migration files or adding/removing their JSON files manually, update the corresponding catalog
entries yourself or explicitly regenerate the catalog:

```sh
swiftstore migration catalog
swiftstore migration catalog --database dictionary
```

`catalog` replaces the selected catalogs' contents; it does not edit migration bodies or snapshots.
`add` preserves existing catalog source and inserts its new entry before the final return. If it
cannot safely extend the existing catalog, it fails before creating migration files.

Comments, formatting and helper code may be edited. For static validation, keep registrations as
direct `catalog.append` calls in `all()`, with literal IDs, `Migration_NUMBER.up` references (prefixed
for named namespaces), and `SchemaDelta.load("ID.schema.json", in: bundle, subdirectory: subdirectory)` resource references. Keep `bundle` and `subdirectory` as parameters of `all`. A data-only entry
omits `delta`. Check verifies their count, order, IDs, method references and resource filenames against
the migration files, and merges the source JSON deltas to compare with Entities. Editing an existing JSON file does not require regenerating the catalog. It does not evaluate arbitrary Swift control flow or prove data transformations.
The compiler and runtime schema verification remain necessary.

Missing or stale catalogs fail `check`; builds never regenerate or overwrite them. Without the
plugin, the same checked-in Swift files still compile and execute the same migration bodies.
If upgrading from a version that generated catalogs during builds or embedded JSON in Swift, run `migration catalog` once and configure the JSON bundle resources.

## Maintain files manually

In the default namespace, a migration consists of `ID.swift` and an optional
`ID.schema.json`. Named namespaces prefix Swift filenames with `Namespace_` to avoid duplicate
basenames in one target; JSON filenames and IDs remain unchanged. The Swift file declares `Migration_NUMBER` with a synchronous, throwing `static func up(_ db: SQLiteConnection)` method. In the default namespace, the type uses only the numeric prefix, preserving leading zeros: `002_修改姓名.swift` declares `Migration_002`. No special annotation is needed.

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
for null handling and readable JSON encoding.

Explicitly mark table deletion:

```json
{"formatVersion": 1, "droppedTables": ["old_cache"]}
```

Omission never means deletion. A table rename consists of deleting the old name and supplying the new table definition in the delta; the Swift body can use `ALTER TABLE ... RENAME TO ...` to preserve data. Deleting an unknown table, replacing and deleting the same table, orphan snapshots, and duplicate IDs are errors.

A pure data migration, such as `003_clean_data.swift`, does not need a JSON file. Its target schema is inherited unchanged. The first migration must describe every initial table and create it in its body.

## What the build does

1. Reads the selected target's `@Entity` declarations.
2. Uses the **same Entity macro expansion implementation** as the compiler to derive columns, defaults, generated index columns, ordinary indexes and FTS5 declarations.
3. Partitions Entity files by database when configured, then sorts each database's migration IDs by numeric prefix and merges its table deltas into each historical target schema.
4. Compares the canonical latest schema with the current Entity schema, including removed tables and FTS changes.
5. Checks the committed catalog's registration IDs, order, `up` references and decoded deltas against each database's migration files.

The build does not write to the project's source directory or run migration bodies. Missing or incorrectly declared `Migration_NUMBER.up` methods are caught when the committed catalog is compiled. The configuration file, source membership list, migration files and snapshots are build inputs.
Changing their contents or adding/removing files reruns the check. The plugin writes only source/input
lists and a success stamp in its work directory, with no generated Swift output.

Source extraction does not type-check user code or evaluate build conditions. Conditional `@Entity` declarations and `#if` members inside an Entity are rejected rather than guessed. Keep the persisted schema stable across configurations. Handwritten `EntityProtocol` conformances and Entities produced by other code generators are outside this source-scanning workflow. Macro type/default mapping remains exactly the library's current behavior.

Only the final structural state is checked during build. A schema can match even if a data backfill is wrong; migration tests must verify historical upgrades and business data.

## Runtime

Apply committed migrations before accessing a database. Changing live Entity definitions alone does not upgrade existing data.

```swift
let manager = try ConnectionManager(path: databasePath, entities: [User.self, Post.self])
try await manager.migrate(migrations: try StoreMigrations.all(bundle: .module))
```

For direct connections:

```swift
try VersionedMigrator(connection: db, migrations: StoreMigrations.all(bundle: .module)).migrate()
```

`StoreMigrations.all()` creates a `StoreMigrationCatalog` and appends each frozen `SchemaDelta`
in migration order at runtime. Each append merges the delta into the preceding target and retains
that step's complete `SchemaSnapshot` for verification. The initial delta starts from an empty
schema; listed tables replace their entire definition, unlisted tables inherit, and `droppedTables`
explicitly removes tables. Data-only steps omit the delta and inherit the preceding target. Full
snapshots are not duplicated in generated source. Only the original JSON deltas are bundled; complete snapshots are assembled in memory. Missing or invalid resources throw while constructing the catalog, before migration SQL executes.

The runner verifies the ordered prefix of applied IDs and the actual schema, executes pending steps
in order, checks each resulting schema/foreign keys, and records successful IDs atomically. A failure rolls back the entire pending batch. ConnectionManager releases its read/write setup gate and starts tracking only after success.

A fresh database replays all steps, including data-only migrations. Cross-version upgrades execute every pending step. Unchanged tables are not rebuilt by the incremental format. SQL bodies can still explicitly change any table when needed.

Keep business transformations within each migration's own file and use historical SQL, not current Entity types. Do not commit, roll back, perform network actions, or call `manager.write` from a body.

Keep published migration files immutable and add new migrations for corrections. There are no
checksums: source-only changes to an already applied migration are not detected or replayed.
Removed, reordered or renamed applied IDs are rejected, and schema drift is still rejected.
The build itself cannot know which versions users have already installed.

Starting with 3.0.0, `StoreMigration` takes `id`, `target` and `up`; remove the old `checksum` argument from manual
registrations. New history tables contain `position`, `id` and `applied_at`. This is a breaking
change with no compatibility path for old history tables that require a checksum column or old
timestamp-trigger metadata layouts.

Runtime verification checks managed tables, defaults, indexes, triggers and FTS auxiliary objects.
Managed objects must match their snapshots; unrelated tables are permitted. Some structurally different
SQL definitions are rejected even if semantically equivalent. Large backfills hold the migration
transaction for their duration.

## Adopt an existing database

For a database created before versioned history was enabled, generate an initial migration from its original Entity definitions, before making further schema changes. ConnectionManager defaults to adopting the first migration as the baseline:

```swift
try await manager.migrate(migrations: try StoreMigrations.all(bundle: .module))
```

The manager verifies that the legacy schema matches the first migration's target, records that migration without executing its body, and applies later migrations. A mismatched legacy schema is rejected. Fresh databases execute every migration; databases with recorded history continue from the last applied version.

If the legacy database already matches a later version, specify its ID explicitly:

```swift
try await manager.migrate(
    migrations: try StoreMigrations.all(bundle: .module),
    adoptingBaseline: "002_display_name"
)
```

The selected baseline and all earlier migrations are recorded without executing their bodies. Schema verification cannot establish whether their data transformations already happened; the legacy data must already reflect those steps.

For direct connections, VersionedMigrator still requires an explicit `adoptBaseline(through:)` call before migrating a legacy database. `previewMigrations` remains read-only and reports `baselineRequired` until a legacy database is adopted.

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

The example uses the public plugin directly, with no schema tool target. The external-package test verifies consumer dependency setup, a rejected schema change, table-level deltas, a manually completed rename, a data-only step, preserved data in unchanged tables, repeat startup, acceptance of source-only edits, and rejection of renamed applied IDs. It also compiles two databases in one target, upgrades their
independent histories, and checks configuration, Entity ownership and snapshot input changes.

CLI packaging is defined in the [release workflow](../.github/workflows/release-cli.yml).
