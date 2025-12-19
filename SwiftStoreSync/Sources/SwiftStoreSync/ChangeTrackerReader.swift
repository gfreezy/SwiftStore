import Foundation
import SwiftStoreCore

/// Reads changes from the changelog database
public final class ChangeTrackerReader {
    private let connection: SQLiteConnection

    /// Initialize with changelog database path (opens in readonly mode)
    public init(changeLogDbPath: String) throws {
        var options = SQLiteConnection.Options()
        options.readonly = true
        self.connection = try SQLiteConnection(path: changeLogDbPath, options: options)
    }

    /// Get changes since a given clock value
    public func changesSince(clock: Int64) throws -> [ChangeLog] {
        let sql = """
            SELECT id, entity_type, entity_id, operation, payload, device_id, logical_clock, created_at, updated_at
            FROM \(ChangeTracker.changeLogTable)
            WHERE logical_clock > ?
            ORDER BY logical_clock ASC
            """
        let stmt = try connection.prepare(sql)
        try SQLiteValue.integer(clock).bind(to: stmt, at: 1)

        var entries: [ChangeLog] = []
        while try stmt.step() {
            if let entry = decodeEntry(from: stmt) {
                entries.append(entry)
            }
        }
        return entries
    }

    /// Get all changes (for initial sync)
    public func allChanges() throws -> [ChangeLog] {
        let sql = """
            SELECT id, entity_type, entity_id, operation, payload, device_id, logical_clock, created_at, updated_at
            FROM \(ChangeTracker.changeLogTable)
            ORDER BY logical_clock ASC
            """
        let stmt = try connection.prepare(sql)

        var entries: [ChangeLog] = []
        while try stmt.step() {
            if let entry = decodeEntry(from: stmt) {
                entries.append(entry)
            }
        }
        return entries
    }

    /// Get the latest clock value in the changelog
    public func latestClock() throws -> Int64 {
        let sql = "SELECT MAX(logical_clock) FROM \(ChangeTracker.changeLogTable)"
        let stmt = try connection.prepare(sql)
        if try stmt.step() {
            return stmt.columnInt64(0)
        }
        return 0
    }

    /// Count changes since a given clock value
    public func countChangesSince(clock: Int64) throws -> Int {
        let sql = "SELECT COUNT(*) FROM \(ChangeTracker.changeLogTable) WHERE logical_clock > ?"
        let stmt = try connection.prepare(sql)
        try SQLiteValue.integer(clock).bind(to: stmt, at: 1)
        if try stmt.step() {
            return Int(stmt.columnInt64(0))
        }
        return 0
    }

    private func decodeEntry(from stmt: SQLiteStatement) -> ChangeLog? {
        guard let idData = stmt.columnData(0),
              let id = UUIDV4(data: idData),
              let entityType = stmt.columnString(1),
              let entityIdData = stmt.columnData(2),
              let entityId = UUIDV4(data: entityIdData),
              let operationStr = stmt.columnString(3),
              let operation = ChangeOperation(rawValue: operationStr),
              let deviceId = stmt.columnString(5)
        else { return nil }

        return ChangeLog(
            id: id,
            entityType: entityType,
            entityId: entityId,
            operation: operation,
            payload: stmt.columnString(4),
            deviceId: deviceId,
            logicalClock: stmt.columnInt64(6),
            createdAt: Date(timeIntervalSince1970: stmt.columnDouble(7)),
            updatedAt: Date(timeIntervalSince1970: stmt.columnDouble(8))
        )
    }
}
