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
        return try ChangeLog
            .filter(\.logicalClock > clock)
            .order(by: \.logicalClock)
            .all(connection)
    }

    /// Get all changes (for initial sync)
    public func allChanges() throws -> [ChangeLog] {
        return try ChangeLog.order(by: \.logicalClock).all(connection)
    }

    /// Get the latest clock value in the changelog
    public func latestClock() throws -> Int64 {
        return try ChangeLog.filter().max(\.logicalClock, connection) ?? 0
    }

    /// Count changes since a given clock value
    public func countChangesSince(clock: Int64) throws -> Int {
        return try ChangeLog.filter(\.logicalClock > clock).count(connection)
    }
}
