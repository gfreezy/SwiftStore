import Foundation
import SwiftStoreCore

/// Only deleted rows need separate metadata; live rows carry updated_at themselves.
final class SyncTombstoneStore {
    private let connection: SQLiteConnection

    init(connection: SQLiteConnection) throws {
        self.connection = connection
        try connection.execute("""
            CREATE TABLE IF NOT EXISTS __swiftstore_sync_tombstones (
                key TEXT PRIMARY KEY, deleted_at REAL NOT NULL
            )
            """)
    }

    static func key(_ change: SyncChange) -> String {
        change.entityType + ":" + change.syncKey.base64EncodedString()
    }

    func load(_ change: SyncChange) throws -> SyncChange? {
        let stmt = try connection.prepareAndBind(
            "SELECT deleted_at FROM __swiftstore_sync_tombstones WHERE key = ?",
            values: [.text(Self.key(change))])
        guard try stmt.step() else { return nil }
        return SyncChange(id: change.id, entityType: change.entityType, syncKey: change.syncKey,
            operation: .delete, payload: nil, deviceId: change.deviceId, logicalClock: 0,
            schemaVersion: change.schemaVersion, createdAt: Date(timeIntervalSince1970: stmt.columnDouble(0)))
    }

    func save(_ change: SyncChange) throws {
        if change.operation == .delete {
            try connection.execute(
                "INSERT OR REPLACE INTO __swiftstore_sync_tombstones (key, deleted_at) VALUES (?, ?)",
                values: [.text(Self.key(change)), .real(change.updatedAt.timeIntervalSince1970)])
        } else {
            try connection.execute("DELETE FROM __swiftstore_sync_tombstones WHERE key = ?",
                values: [.text(Self.key(change))])
        }
    }
}
