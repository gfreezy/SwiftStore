import Foundation

public enum VersionedMigrationError: Error, CustomStringConvertible {
    case invalidHistory(String)
    case schemaMismatch(String)
    case baselineRequired

    public var description: String {
        switch self {
        case .invalidHistory(let message): return "Migration history: \(message)"
        case .schemaMismatch(let table): return "Schema mismatch for \(table). Generate/review a migration; runtime auto-alignment is disabled."
        case .baselineRequired: return "Existing database has no migration history. Explicitly adopt a matching baseline first."
        }
    }
}

/// A frozen migration. The generation tool supplies a hash of its source and target snapshot.
/// Bodies must only change this database; external side effects cannot be rolled back.
public struct StoreMigration: Sendable {
    public let id: String
    public let checksum: String
    public let target: SchemaSnapshot
    public let up: @Sendable (SQLiteConnection) throws -> Void

    public init(id: String, checksum: String, target: SchemaSnapshot,
                up: @escaping @Sendable (SQLiteConnection) throws -> Void) {
        self.id = id
        self.checksum = checksum
        self.target = target
        self.up = up
    }
}

/// Executes committed migrations in registration order, with no runtime schema generation.
public struct VersionedMigrator {
    private let connection: SQLiteConnection
    private let migrations: [StoreMigration]
    private static let historyTable = "__swiftstore_migrations"

    public init(connection: SQLiteConnection, migrations: [StoreMigration]) {
        self.connection = connection
        self.migrations = migrations
    }

    /// Read-only preview. Validates the history prefix and the last applied schema, never runs bodies.
    public func pendingMigrationIDs() throws -> [String] {
        let count = try appliedCount()
        try verifyState(at: count)
        return migrations.dropFirst(count).map(\.id)
    }

    /// All pending steps, their schema checks and bookkeeping commit together or roll back together.
    public func migrate() throws {
        try connection.transaction {
            let count = try appliedCount()
            try verifyState(at: count)
            try createHistory()
            for (offset, migration) in migrations.enumerated().dropFirst(count) {
                try migration.up(connection)
                try verifyTarget(migration.target)
                let check = try connection.prepare("PRAGMA foreign_key_check")
                guard try !check.step() else {
                    throw VersionedMigrationError.invalidHistory("Foreign key violation after \(migration.id)")
                }
                try record(migration, position: offset)
            }
        }
    }

    /// Explicit opt-in for a legacy database. Verifies the entire selected schema before recording
    /// the prefix, without running its bodies. Never guesses a version or marks a mismatched DB current.
    public func adoptBaseline(through id: String) throws {
        try connection.transaction {
            guard try appliedCount() == 0,
                  let index = migrations.firstIndex(where: { $0.id == id }) else {
                throw VersionedMigrationError.invalidHistory("Baseline requires empty history and a known ID")
            }
            try verifyTarget(migrations[index].target)
            try createHistory()
            for position in 0...index { try record(migrations[position], position: position) }
        }
    }

    private func validateHistory() throws {
        guard !migrations.isEmpty, Set(migrations.map(\.id)).count == migrations.count,
              migrations.allSatisfy({ !$0.id.isEmpty && !$0.checksum.isEmpty }) else {
            throw VersionedMigrationError.invalidHistory("Supply a nonempty ordered list with unique IDs and checksums")
        }
        for migration in migrations { try migration.target.validate() }
    }

    private func appliedCount() throws -> Int {
        try validateHistory()
        guard try connection.tableExists(Self.historyTable) else { return 0 }
        let stmt = try connection.prepare("SELECT position, id, checksum FROM __swiftstore_migrations ORDER BY position")
        var count = 0
        while try stmt.step() {
            guard count < migrations.count, stmt.columnInt64(0) == Int64(count),
                  stmt.columnString(1) == migrations[count].id,
                  stmt.columnString(2) == migrations[count].checksum else {
                throw VersionedMigrationError.invalidHistory("Applied migrations were removed, reordered or modified at position \(count)")
            }
            count += 1
        }
        return count
    }

    private func verifyState(at count: Int) throws {
        if count > 0 {
            try verifyTarget(migrations[count - 1].target)
        } else {
            for name in Set(migrations.flatMap { $0.target.tables.map(\.name) }) {
                if try connection.tableExists(name) { throw VersionedMigrationError.baselineRequired }
            }
        }
    }

    private func verifyTarget(_ target: SchemaSnapshot) throws {
        try target.verify(on: connection)
        let present = Set(target.managedObjectNames)
        for name in Set(migrations.flatMap { $0.target.managedObjectNames }).subtracting(present) {
            if try connection.queryScalar("SELECT COUNT(*) FROM sqlite_master WHERE name = ?", values: [.text(name)], type: Int.self) != 0 {
                throw VersionedMigrationError.schemaMismatch(name)
            }
        }
    }

    private func createHistory() throws {
        try connection.execute("""
            CREATE TABLE IF NOT EXISTS __swiftstore_migrations (
                position INTEGER NOT NULL UNIQUE,
                id TEXT NOT NULL PRIMARY KEY,
                checksum TEXT NOT NULL,
                applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
            """)
    }

    private func record(_ migration: StoreMigration, position: Int) throws {
        try connection.execute("INSERT INTO __swiftstore_migrations (position, id, checksum) VALUES (?, ?, ?)",
            values: [.integer(Int64(position)), .text(migration.id), .text(migration.checksum)])
    }
}
