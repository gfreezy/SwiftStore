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
let migrations = try StoreMigrations.all()
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
    let migrations = try StoreMigrations.all()
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

    # No stored/generated catalog in the source directory.
    assert not (target / 'Migrations/StoreMigrations.swift').exists()
    # Source edits must invalidate the build output and change the recorded checksum.
    with (target / 'Migrations/002_rename.swift').open('a') as file:
        file.write('\n// An impermissible edit to an already applied migration.\n')
    run(['swift', 'build'], root)
    run([executable, db], root, expected=1, contains='Applied migrations were removed, reordered or modified')
    print('PASS: build recomputes hashes; runtime refuses edited published history.', flush=True)
