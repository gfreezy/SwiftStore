#!/usr/bin/env python3
"""End-to-end check with a separate consumer package. Run after swift build --product swiftstore."""
import json
import pathlib
import shutil
import subprocess
import tempfile

REPO = pathlib.Path(__file__).resolve().parents[2]
BUILT_CLI = REPO / '.build/debug/swiftstore'


def run(args, cwd, expected=0, contains=None):
    # Model the consumer maintaining its Package.swift resource declarations.
    if args[:2] in (['swift', 'build'], ['swift', 'run']):
        target = cwd / 'Sources/Consumer'
        resources = [f'.copy({json.dumps(str(p.relative_to(target)))})'
                     for p in sorted(target.rglob('*.schema.json'))]
        manifest = cwd / 'Package.swift'
        lines = manifest.read_text().splitlines()
        manifest.write_text('\n'.join(
            '        resources: [' + ', '.join(resources) + ']' + (',' if any('plugins:' in x for x in lines) else '') + ' // schema resources'
            if '// schema resources' in line else line for line in lines) + '\n')
    result = subprocess.run([str(arg) for arg in args], cwd=cwd, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if (expected == 0 and result.returncode != 0) or (expected != 0 and result.returncode == 0):
        raise AssertionError(result.stdout[-12000:])
    if contains and contains not in result.stdout:
        raise AssertionError(result.stdout[-12000:])
    return result.stdout


with tempfile.TemporaryDirectory(prefix='swiftstore-consumer-') as temporary:
    root = pathlib.Path(temporary)
    CLI = root / 'swiftstore'
    shutil.copy2(BUILT_CLI, CLI)  # Verify the optional executable works outside its build directory.
    target = root / 'Sources/Consumer'
    target.mkdir(parents=True)
    # Local package identity derives from the dependency directory name.
    identity = REPO.name.lower()
    (root / 'Package.swift').write_text(f'''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Consumer", platforms: [.macOS(.v14)],
    dependencies: [.package(path: {json.dumps(str(REPO))})],
    targets: [.executableTarget(name: "Consumer",
        dependencies: [.product(name: "SwiftStore", package: "{identity}")],
        resources: [], // schema resources
        plugins: [.plugin(name: "SwiftStoreMigrationCheck", package: "{identity}")])])
''')
    if (REPO / 'Package.resolved').exists():
        shutil.copyfile(REPO / 'Package.resolved', root / 'Package.resolved')
    model = target / 'Models.swift'
    initial = '''import SwiftStore
@Entity(readonly: true) struct Person { var id: Int; var name: String? }
@Entity(readonly: true) struct Post { var id: Int; var message: String? }
'''
    model.write_text(initial)
    (target / 'main.swift').write_text('''import SwiftStore
let migrations = try StoreMigrations.all(bundle: .module)
let db = try SQLiteConnection(path: ":memory:")
try VersionedMigrator(connection: db, migrations: migrations).migrate()
print("fresh install passed")
''')
    run([CLI, 'migration', 'add', '001_initial', '--target', target], root)
    run(['swift', 'run', 'Consumer'], root, contains='fresh install passed')
    print('PASS: external package builds with only the published plugin and library.', flush=True)

    model.write_text(initial.replace('var name: String?', 'var displayName: String?'))
    run(['swift', 'build'], root, expected=1, contains='Entity schema changed')
    print('PASS: Entity drift fails the consumer build.', flush=True)

    run([CLI, 'migration', 'add', '002_rename', '--target', target], root)
    delta = json.loads((target / 'Migrations/002_rename.schema.json').read_text())
    assert [table['name'] for table in delta['tables']] == ['person']
    assert '#error' in (target / 'Migrations/002_rename.swift').read_text()
    (target / 'Migrations/002_rename.swift').write_text('''import SwiftStore
    enum Migration_002 {
        static func up(_ db: SQLiteConnection) throws {
            try db.execute("ALTER TABLE person RENAME COLUMN name TO display_name")
            try db.execute("UPDATE person SET display_name = trim(display_name)")
        }
    }
    ''')
    run([CLI, 'migration', 'add', '003_data', '--target', target], root)
    assert not (target / 'Migrations/003_data.schema.json').exists()
    (target / 'Migrations/003_data.swift').write_text('''import SwiftStore
    enum Migration_003 {
        static func up(_ db: SQLiteConnection) throws {
            try db.execute("UPDATE person SET display_name = display_name || '!'")
        }
    }
    ''')
    (target / 'main.swift').write_text('''import SwiftStore
    let migrations = try StoreMigrations.all(bundle: .module)
    let db = try SQLiteConnection(path: CommandLine.arguments[1])
    if try !db.tableExists("__swiftstore_migrations") {
        try VersionedMigrator(connection: db, migrations: Array(migrations.prefix(1))).migrate()
        try db.execute("INSERT INTO person VALUES (1, ' Ada ')")
        try db.execute("INSERT INTO post VALUES (1, 'untouched')")
    }
    try VersionedMigrator(connection: db, migrations: migrations).migrate()
    let name: String? = try db.queryScalar("SELECT display_name FROM person")
    let message: String? = try db.queryScalar("SELECT message FROM post")
    guard name == "Ada!", message == "untouched" else { fatalError("Data lost") }
    print("upgrade passed")
    ''')
    run(['swift', 'build'], root)
    db = root / 'data.sqlite'
    executable = root / '.build/debug/Consumer'
    run([executable, db], root, contains='upgrade passed')
    run([executable, db], root, contains='upgrade passed')
    print('PASS: table deltas, manual migration without seal, data-only step and repeated startup.', flush=True)

    # Catalogs are ordinary checked-in source files; builds produce no registration Swift.
    assert (target / 'Migrations/StoreMigrations.swift').exists()
    # Generated code references bundled deltas, without embedding JSON or checksums.
    assert not list((root / '.build/plugins/outputs').rglob('StoreMigrations.swift'))
    catalog = (target / 'Migrations/StoreMigrations.swift').read_text()
    assert '"tables"' not in catalog
    assert catalog.count('SchemaDelta.load') == 2
    assert 'SchemaSnapshot.decode' not in catalog
    assert 'checksum' not in catalog
    # Source-only edits do not reject already applied history now that checksums are removed.
    with (target / 'Migrations/002_rename.swift').open('a') as file:
        file.write('\n// An impermissible edit to an already applied migration.\n')
    run(['swift', 'build'], root)
    run([executable, db], root, contains='upgrade passed')
    print('PASS: compact catalog compiles; source-only edits do not invalidate recorded IDs.', flush=True)

    # Renaming an applied ID still rejects the history prefix.
    (target / 'Migrations/003_data.swift').rename(target / 'Migrations/003_renamed.swift')
    run(['swift', 'build'], root, expected=1, contains='Catalog ID, order or up reference differs')
    run([CLI, 'migration', 'catalog'], root)
    run(['swift', 'build'], root)
    run([executable, db], root, expected=1, contains='Applied migrations were removed, reordered or renamed')
    print('PASS: runtime still rejects renamed applied migration IDs.', flush=True)

    # Switch the consumer to two databases in the same compilation target.
    model.unlink()
    shutil.rmtree(target / 'Migrations')
    main_models = target / 'Main/Models'
    dictionary_models = target / 'Dictionary/Models'
    main_models.mkdir(parents=True)
    dictionary_models.mkdir(parents=True)
    main_model = main_models / 'MainItem.swift'
    dictionary_model = dictionary_models / 'DictionaryItem.swift'
    main_model.write_text('''import SwiftStore
@Entity(tableName: "items") struct MainItem { var id: UUIDV7 = UUIDV7(); var name: String?; var createdAt: Date = Date(); var updatedAt: Date = Date() }
''')
    dictionary_model.write_text('''import SwiftStore
@Entity(tableName: "items") struct DictionaryItem { var id: UUIDV7 = UUIDV7(); var term: String?; var createdAt: Date = Date(); var updatedAt: Date = Date() }
''')
    configuration = {'formatVersion': 1, 'targets': {'Consumer': {'databases': [
        {'id': 'main', 'sources': ['Sources/Consumer/Main/Models'],
         'migrations': 'Sources/Consumer/Main/Migrations'},
        {'id': 'dictionary', 'namespace': 'DictionaryStore', 'sources': ['Sources/Consumer/Dictionary/Models'],
         'migrations': 'Sources/Consumer/Dictionary/Migrations',
         'schemas': 'Sources/Consumer/Resources/DictionarySchemas'}
    ]}}}
    # Start main as an unconfigured single database, then opt into a multi-database target.
    run([CLI, 'migration', 'add', '001_initial', '--target', target / 'Main'], root)
    original_main = {file.name: file.read_bytes() for file in (target / 'Main/Migrations').iterdir()}
    config_file = root / 'swiftstore.json'
    config_file.write_text(json.dumps(configuration))
    run([CLI, 'migration', 'add', '001_initial'], root, expected=1, contains='Select one database')
    run([CLI, 'migration', 'add', '001_initial', '--database', 'dictionary'], root)
    run([CLI, 'migration', 'check'], root, contains='Schema, migration history and catalogs match')
    (target / 'main.swift').write_text('''import SwiftStore
    let main = try SQLiteConnection(path: CommandLine.arguments[1])
    let dictionary = try SQLiteConnection(path: CommandLine.arguments[2])
    let mainHistory = try StoreMigrations.all(bundle: .module)
    let dictionaryHistory = try DictionaryStoreMigrations.all(bundle: .module)
    try VersionedMigrator(connection: main, migrations: mainHistory).migrate()
    try VersionedMigrator(connection: dictionary, migrations: dictionaryHistory).migrate()
    try main.execute("INSERT OR IGNORE INTO items (id, name) VALUES (X'00000000000000000000000000000001', 'main')")
    try dictionary.execute("INSERT OR IGNORE INTO items (id, term) VALUES (X'00000000000000000000000000000001', 'dictionary')")
    guard try main.queryScalar("SELECT name FROM items", type: String.self) == CommandLine.arguments[3],
          try dictionary.queryScalar("SELECT term FROM items", type: String.self) == "dictionary"
    else { fatalError("Database histories or data were mixed") }
    // The registered entities must also match each generated catalog independently.
    let mainManager = try ConnectionManager(path: ":memory:", entities: [MainItem.self])
    try await mainManager.migrate(migrations: mainHistory)
    let dictionaryManager = try ConnectionManager(path: ":memory:", entities: [DictionaryItem.self])
    try await dictionaryManager.migrate(migrations: dictionaryHistory)
    print("multiple databases passed")
    ''')
    run(['swift', 'build'], root)
    main_db, dictionary_db = root / 'main.sqlite', root / 'dictionary.sqlite'
    run([executable, main_db, dictionary_db, 'main'], root, contains='multiple databases passed')
    assert original_main == {file.name: file.read_bytes() for file in (target / 'Main/Migrations').iterdir()}
    assert not list((root / '.build/plugins/outputs').rglob('StoreMigrations.swift'))
    print('PASS: default namespace preserves all old files; a named second database shares IDs and SQL table names.', flush=True)

    dictionary_history = {file.name: file.read_bytes() for file in (target / 'Dictionary/Migrations').iterdir()}
    main_model.write_text(main_model.read_text().replace(' }', '; var label: String? }'))
    run(['swift', 'build'], root, expected=1, contains='database: main')
    run([CLI, 'migration', 'add', '002_label', '--database', 'main'], target / 'Main/Migrations')
    main_step = target / 'Main/Migrations/002_label.swift'
    main_step.write_text(main_step.read_text().replace(
        '// Add data migration SQL here, or between the schema statements above.',
        '''try db.execute("UPDATE items SET name = name || '!'")'''))
    run(['swift', 'build'], root)
    run([executable, main_db, dictionary_db, 'main!'], root, contains='multiple databases passed')
    run([executable, main_db, dictionary_db, 'main!'], root, contains='multiple databases passed')
    assert dictionary_history == {file.name: file.read_bytes() for file in (target / 'Dictionary/Migrations').iterdir()}
    print('PASS: upgrading one database preserves its data and leaves the other history untouched.', flush=True)

    dictionary_model.write_text(dictionary_model.read_text().replace(' }', '; var meaning: String? }'))
    run([CLI, 'migration', 'check'], root, expected=1, contains='database: dictionary')
    run([CLI, 'migration', 'check', '--database', 'main'], root)
    run(['swift', 'build'], root, expected=1, contains='database: dictionary')
    run([CLI, 'migration', 'add', '002_meaning', '--database', 'dictionary'], root)
    run(['swift', 'build'], root)
    run([executable, main_db, dictionary_db, 'main!'], root, contains='multiple databases passed')
    print('PASS: check and plugin validate every database; both histories can advance to 002.', flush=True)

    unassigned = target / 'Unassigned.swift'
    unassigned.write_text('import SwiftStore\n@Entity(readonly: true) struct Unassigned { var id: Int }\n')
    run(['swift', 'build'], root, expected=1, contains='must belong to exactly one database')
    unassigned.unlink()
    # Moving a model and changing only configuration should refresh grouping automatically.
    relocated = target / 'Dictionary/Entities'
    dictionary_models.rename(relocated)
    configuration['targets']['Consumer']['databases'][1]['sources'] = ['Sources/Consumer/Dictionary/Entities']
    config_file.write_text(json.dumps(configuration))
    run(['swift', 'build'], root)
    print('PASS: unassigned Entities fail; source moves and configuration changes invalidate the build.', flush=True)

    run([CLI, 'migration', 'add', '003_data', '--database', 'main'], root)
    snapshot = target / 'Main/Migrations/003_data.schema.json'
    snapshot.write_text('{"droppedTables": ["items"]}')
    run(['swift', 'build'], root, expected=1, contains='database: main')
    snapshot.unlink()
    run(['swift', 'build'], root)
    run([executable, main_db, dictionary_db, 'main!'], root, contains='multiple databases passed')
    print('PASS: adding and removing snapshot inputs reruns checks, including data-only steps.', flush=True)

    catalog_file = target / 'Main/Migrations/StoreMigrations.swift'
    original_catalog = catalog_file.read_text()
    edited_catalog = '// User comment preserved by builds.\n' + original_catalog
    catalog_file.write_text(edited_catalog)
    run(['swift', 'build'], root)
    assert catalog_file.read_text() == edited_catalog
    catalog_file.write_text(edited_catalog.replace('001_initial.schema.json', 'wrong.schema.json'))
    run(['swift', 'build'], root, expected=1, contains='Catalog schema resource differs')
    catalog_file.unlink()
    run([CLI, 'migration', 'check'], root, expected=1, contains='Missing StoreMigrations.swift')
    assert not catalog_file.exists()
    run([CLI, 'migration', 'catalog', '--database', 'main'], root)
    run(['swift', 'build'], root)
    print('PASS: checks preserve manual source and reject stale/missing catalogs; only CLI regenerates them.', flush=True)

    manifest = root / 'Package.swift'
    manifest.write_text(manifest.read_text().replace(
        f'        plugins: [.plugin(name: "SwiftStoreMigrationCheck", package: "{identity}")]', ''))
    run(['swift', 'build'], root)
    run([executable, main_db, dictionary_db, 'main!'], root, contains='multiple databases passed')
    print('PASS: removing the plugin leaves compiled catalog behavior unchanged.', flush=True)
