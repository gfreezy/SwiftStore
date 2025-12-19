import Foundation

/// Pending delete entry for sync - records entity deletions before they happen
/// Used by BEFORE DELETE triggers to capture delete operations
/// This is a simple helper table, not a full sync entity
struct PendingDelete: Sendable {
    let id: Int64
    let tableName: String
    let entityId: UUIDV4

    static var ddl: String {
        """
        CREATE TABLE IF NOT EXISTS \(SyncManager.pendingDeletesTable) (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            table_name TEXT NOT NULL,
            entity_id BLOB NOT NULL
        )
        """
    }
}
