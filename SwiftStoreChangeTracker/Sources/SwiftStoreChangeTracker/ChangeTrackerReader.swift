import Foundation
import SwiftStoreCore

/// Reads local changes from the changelog database
public final class ChangeTrackerReader {
    private let connection: SQLiteConnection
    private let deviceId: UUIDV7

    /// Initialize with changelog database path and device ID
    /// Only changes from this device will be returned
    /// - Parameters:
    ///   - changeLogDbPath: Path to the changelog database
    ///   - deviceId: The device ID to filter changes by
    public init(changeLogDbPath: String, deviceId: UUIDV7) throws {
        var options = SQLiteConnection.Options()
        options.readonly = true
        self.connection = try SQLiteConnection(path: changeLogDbPath, options: options)
        self.deviceId = deviceId
    }

    /// Get local changes since a given clock value
    public func changesSince(clock: Int64) throws -> [ChangeLog] {
        return try ChangeLog
            .filter(\.deviceId == deviceId && \.logicalClock > clock)
            .order(by: \.logicalClock)
            .all(connection)
    }

    /// Get all local changes (for initial sync)
    public func allChanges() throws -> [ChangeLog] {
        return try ChangeLog
            .filter(\.deviceId == deviceId)
            .order(by: \.logicalClock)
            .all(connection)
    }

    /// Get the latest clock value in the local changelog
    public func latestClock() throws -> Int64 {
        return try ChangeLog
            .filter(\.deviceId == deviceId)
            .max(\.logicalClock, connection) ?? 0
    }

    /// Count local changes since a given clock value
    public func countChangesSince(clock: Int64) throws -> Int {
        return try ChangeLog
            .filter(\.deviceId == deviceId && \.logicalClock > clock)
            .count(connection)
    }
}
