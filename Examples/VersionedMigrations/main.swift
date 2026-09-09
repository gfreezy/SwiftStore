import Foundation
import SwiftStoreCore

// Fresh install: replay all committed steps.
let history = try StoreMigrations.all()
let fresh = try SQLiteConnection(path: ":memory:")
try VersionedMigrator(connection: fresh, migrations: history).migrate()
try SchemaSnapshot(entities: [Person.self], createUpdateTrigger: false).verify(on: fresh)

// Upgrade from the first released schema with representative user data.
let existing = try SQLiteConnection(path: ":memory:")
try VersionedMigrator(connection: existing, migrations: Array(history.prefix(1))).migrate()
try existing.execute("INSERT INTO person (id, name) VALUES (?, ?)", values: [.blob(Data(repeating: 1, count: 16)), .text(" Ada ")])
try VersionedMigrator(connection: existing, migrations: history).migrate()
let name: String? = try existing.queryScalar("SELECT display_name FROM person")
guard name == "Ada" else { throw VersionedMigrationError.invalidHistory("Example lost the user's name") }
try VersionedMigrator(connection: existing, migrations: history).migrate()
print("Fresh install, cross-version upgrade, manual data conversion, and repeat startup passed.")
