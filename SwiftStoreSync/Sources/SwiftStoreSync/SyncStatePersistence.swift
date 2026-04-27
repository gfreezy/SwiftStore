import Foundation
import SwiftStoreCore

/// Internal helper that persists `SyncState` inside the changelog SQLite
/// database. Uses a single metadata table with one key-value row, so the
/// caller of `SyncManager` does not have to load/save `SyncState`.
final class SyncStatePersistence {
    private let connection: SQLiteConnection

    private static let tableName = "__swiftstore_sync_state"
    private static let lastLocalClockKey = "last_local_clock"

    init(connection: SQLiteConnection) throws {
        self.connection = connection
        try createTableIfNeeded()
    }

    private func createTableIfNeeded() throws {
        try connection.execute("""
            CREATE TABLE IF NOT EXISTS \(Self.tableName) (
                key TEXT PRIMARY KEY,
                value INTEGER NOT NULL
            )
            """)
    }

    /// Read the persisted `SyncState`, or return a zero-initialized state if
    /// the row is missing.
    func load() throws -> SyncState {
        let clock: Int64 = try connection.queryScalar(
            "SELECT value FROM \(Self.tableName) WHERE key = ?",
            values: [.text(Self.lastLocalClockKey)]
        ) ?? 0
        return SyncState(lastLocalClock: clock)
    }

    /// Persist the given `SyncState`.
    func save(_ state: SyncState) throws {
        try connection.execute(
            "INSERT OR REPLACE INTO \(Self.tableName) (key, value) VALUES (?, ?)",
            values: [
                .text(Self.lastLocalClockKey),
                .integer(state.lastLocalClock),
            ]
        )
    }
}
