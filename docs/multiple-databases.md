# Multiple databases in one target

Each database has its own Entity sources, migration directory, Swift namespace and
runtime connection. Migration numbers and SQL table names may repeat across databases.

Without a configuration file, SwiftStore uses the existing single-database layout:
`Migrations/`, `Migration_001`, and `StoreMigrations.all()`. No configuration is required for that case.

## Configuration

Place `swiftstore.json` beside `Package.swift` or the `.xcodeproj`:

```json
{
  "formatVersion": 1,
  "targets": {
    "Reed": {
      "databases": [
        {
          "id": "main",
          "sources": ["Reed/Core/Storage/MainStore/Models"],
          "migrations": "Reed/Core/Storage/MainStore/Migrations"
        },
        {
          "id": "dictionary",
          "namespace": "DictionaryStore",
          "sources": ["Reed/Core/Storage/DictionaryStore/Models"],
          "migrations": "Reed/Core/Storage/DictionaryStore/Migrations",
          "schemas": "Reed/Resources/DictionarySchemas"
        }
      ]
    }
  }
}
```

Use the actual SwiftPM or Xcode target name as the key. All paths are relative to the configuration
file, must stay inside its directory, and may contain spaces. `sources` entries may be Swift files
or directories scanned recursively; glob expressions are not supported. A source path must exist,
even when it no longer contains any Entity. A migration directory is created on the first `add`.

Database IDs and namespaces must be unique within a target. Omit `namespace` or set it to
`"default"` to use the original unprefixed names. A target may have only one default namespace.
Named namespaces are nonempty ASCII Swift identifier prefixes, such as `DictionaryStore`.
Migration and schema directories belonging to different databases within a target must not overlap.
Optional `schemas` selects the JSON output/input directory, relative to the configuration file;
omitting it keeps JSON beside the Swift migrations. It does not specify the runtime bundle path.

Every Entity file in the selected target must match exactly one database. Unassigned Entity files
and overlapping ownership are errors. All Entities declared in one file share its database.
Split a file if its Entities belong to different databases. Sharing an Entity across database groups
in the same target is not supported; multiple database files with the same schema can instead use
the same catalog. Helpers and `@Embedded` declarations do not need their own database assignment.

## Move from a single database without renaming history

Assign the existing database to the default namespace. Its files stay `001_initial.swift` and
`001_initial.schema.json`, its types stay `Migration_001`, and application code continues calling
`StoreMigrations.all()`. Keep its existing database path, IDs, SQL bodies and snapshots unchanged.
Give only new databases named namespaces. They can start their own IDs at `001_initial`.

If the existing catalog previously came from the build plugin, run `swiftstore migration catalog`
once to create the ordinary source file. Resource-based CLI-owned catalogs need no renaming or rewriting.
If the old catalog embeds JSON, regenerate it once and bundle the JSON files as described below.
The runtime records migration IDs, not source filenames or namespaces, so the old database resumes
its applied history without rerunning migration bodies. Configuration does not move tables or data
between database files.

Changing an existing *named* namespace later requires renaming that namespace's Swift files, types
and registration entry point. Keep the default namespace for the original database to avoid this.

## CLI

```sh
swiftstore migration add 001_initial --database main
swiftstore migration add 001_initial --database dictionary

swiftstore migration check
swiftstore migration check --database main
swiftstore migration check --target-name Reed
swiftstore migration catalog --database dictionary
```

**`check` defaults to every configured database in every configured target.** It reports schema
errors from all selected databases together. `--database` filters by database ID, and
`--target-name` filters by target. With repeated IDs across targets, both are checked unless a
target is selected. `add` must resolve to exactly one database; otherwise it fails before writing.

The CLI finds the nearest configuration by walking up from the working directory or the explicit
`--target <directory>` starting point, stopping at the repository boundary. This works from inside
a database's migration directory too; the directory location does not implicitly select a database.

For standalone SwiftPM commands, the tool reads static target paths from `Package.swift` without
executing it. For precise compilation membership, including exclusions, supply `--sources-file`
with the selected target's Swift source paths. Computed manifests also require this list.
Standalone Xcode commands scan project sources and exclude files explicitly assigned to other
configured targets; they do not infer Xcode Compile Sources membership or build conditions.
The build plugin always supplies the actual target source list and target name.

`migration add` creates or appends the database's editable catalog in its migration directory.
`migration catalog` explicitly writes/replaces selected catalogs after manual changes; by default
it regenerates all configured catalogs. `check` never changes them. See the
[editable catalog rules](versioned-migrations.md#editable-registration-catalog) for supported
registration metadata and how manual edits are preserved.

## Generated code

Each group keeps independent IDs and JSON filenames. The example above produces:

| Database | Swift file | Type | Catalog file and entry point |
| --- | --- | --- | --- |
| main (default) | `001_initial.swift` | `Migration_001` | `StoreMigrations.swift`, `StoreMigrations.all()` |
| dictionary | `DictionaryStore_001_initial.swift` | `DictionaryStoreMigration_001` | `DictionaryStoreMigrations.swift`, `DictionaryStoreMigrations.all()` |

Both JSON files are called `001_initial.schema.json` in their respective directories. Named
namespaces prefix Swift filenames because Swift requires unique source basenames within a target,
even across directories. Name Entity source files uniquely too, such as `MainItem.swift` and
`DictionaryItem.swift`.

Both migration files and catalogs compile as ordinary Swift sources. No source conversion or
special runtime interpreter is involved. Each catalog independently merges its initial schema and
subsequent deltas at runtime, preserving full-table replacement, inherited tables, explicit
`droppedTables` and data-only steps. There are no migration checksums.

## Build plugin

Enable `SwiftStoreMigrationCheck` on the target as described in the
[versioned migration guide](versioned-migrations.md). The plugin checks every database for that
target, including committed catalogs; it generates no Swift files. It writes only a check stamp
and dependency lists in its build work directory. Removing the plugin removes build-time checks
without changing which migration code compiles or executes.

All migration and catalog Swift files must belong to that target's Compile Sources. Configured Entity files
outside the target's source list are errors. Configuration, source membership and the migration
input list participate in build dependencies, including additions, removals and moves. A missing
configuration entry for a plugin-enabled target is an error rather than a single-database fallback.

## Bundle schema resources

JSON deltas must ship with the application. Swift migration bodies and catalogs remain compiled
Swift sources; the plugin only checks them. Catalogs reference the JSON files without embedding their contents.

For an existing single database, keep the current layout and list each JSON file in SwiftPM
`resources: [.copy("Migrations/001_initial.schema.json"), ...]`. These files land at the bundle root.
Use `StoreMigrations.all(bundle: .module)`; keep that setup when assigning the default namespace.

For a new database, configure `schemas` to a JSON-only directory inside its target, for example
`Sources/MyApp/Resources/DictionarySchemas`, and add `.copy("Resources/DictionarySchemas")` to the
target's resources. Future JSON files in that directory are included automatically. Do not copy
an entire directory that also contains migration Swift files: SwiftPM treats those as resources
instead of compiling them. To use JSON-only directories for all databases, configure distinct
`schemas` paths and move the existing JSON files there without renaming them.

For Xcode, include JSON files in Copy Bundle Resources. Keep each database's files in a preserved
resource subdirectory (for example a folder reference) to avoid flattening duplicate filenames.
Pass its name as `subdirectory`. Configuration itself does not need to be bundled.

`all(bundle:subdirectory:)` defaults to `.main` and the bundle root. SwiftPM callers must pass
`.module`; a framework can pass its own resource bundle. Lookup is exact and does not recursively
search or fall back to another database. Missing or invalid JSON throws before migrations run.

## Runtime

```swift
let main = try ConnectionManager(path: mainPath, entities: mainEntities)
try await main.migrate(migrations: StoreMigrations.all(bundle: .module))

let dictionary = try ConnectionManager(
    path: dictionaryPath,
    entities: dictionaryEntities
)
try await dictionary.migrate(migrations: DictionaryStoreMigrations.all(bundle: .module, subdirectory: "DictionarySchemas"))
```

Database file paths stay in application code. Each connection verifies its registered Entities
against its own final snapshot and stores its history in that database. Baseline adoption and
schema checks remain independent. Transactions do not span database managers: if one migration
fails, it does not roll back another database's successful migration. Finish initializing required
databases before exposing the application's storage operations.
