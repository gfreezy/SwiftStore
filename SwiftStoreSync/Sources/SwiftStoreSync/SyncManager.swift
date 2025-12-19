import Foundation
import SwiftStoreCore

/// Manages sync operations for the store
public final class SyncManager {
    /// Pending deletes table name
    public static let pendingDeletesTable = "__swiftstore_pending_deletes"

    private let connection: SQLiteConnection
    private let dbPath: String

    // Sync state
    private var syncEnabled: Bool = false
    private var deviceId: String?
    private var clock: HybridClock = HybridClock()

    // Change tracker (writes to separate changelog database)
    private var changeTracker: ChangeTracker?

    // Registered entity types
    private var registeredEntities: [String: any EntityProtocol.Type] = [:]
    private var relationEntities: Set<String> = []

    public init(connection: SQLiteConnection, dbPath: String) {
        self.connection = connection
        self.dbPath = dbPath
    }

    // MARK: - Entity Registration

    /// Register entity types for sync
    public func registerEntities(_ entities: [String: any EntityProtocol.Type], relations: Set<String>) {
        self.registeredEntities = entities
        self.relationEntities = relations
    }

    // MARK: - Sync Control

    /// Check if sync is enabled
    public var isEnabled: Bool { syncEnabled }

    /// Enable sync with device ID
    public func enable(deviceId: String) throws {
        syncEnabled = true
        self.deviceId = deviceId

        // Clear pending_deletes table (stale from previous runs)
        let clearSQL: SQL = "DELETE FROM \(raw: Self.pendingDeletesTable)"
        try connection.execute(clearSQL)

        // Create change tracker (writes directly to separate changelog database)
        changeTracker = try ChangeTracker(
            connection: connection,
            changeLogDbPath: dbPath + ".changelog",
            deviceId: deviceId,
            pendingDeletesTable: Self.pendingDeletesTable,
            registeredEntities: registeredEntities,
            tickClock: { [weak self] in self?.clock.tick() ?? 0 }
        )
        changeTracker?.start()
    }

    /// Disable sync
    public func disable() {
        // Stop change tracker (removes hook)
        changeTracker?.stop()
        changeTracker = nil

        syncEnabled = false
        deviceId = nil
    }

    /// Get current logical clock value
    public func currentClock() -> Int64 {
        return clock.current
    }

    // MARK: - Time Verification

    /// Verify that local time is within acceptable range of NTP time
    public func verifyTime(
        toleranceMs: Int64 = 5000,
        servers: [String] = NTPClient.defaultServers
    ) async throws -> NTPVerificationResult {
        try await NTPClient.verifyTime(toleranceMs: toleranceMs, servers: servers)
    }

    /// Check if local time is valid before enabling sync
    public func validateTimeForSync(toleranceMs: Int64 = 5000) async throws {
        let result = try await verifyTime(toleranceMs: toleranceMs)
        if !result.isValid {
            throw StoreError.timeOutOfSync(offsetMs: result.offsetMs, toleranceMs: toleranceMs)
        }
    }

    // MARK: - Change Log Operations

    /// Get changelog database connection
    public var changeLogConnection: SQLiteConnection? {
        changeTracker?.connection
    }

    /// Get changes since a given clock value
    public func changesSince(clock: Int64) throws -> [ChangeLog] {
        let reader = try ChangeTrackerReader(changeLogDbPath: dbPath + ".changelog")
        return try reader.changesSince(clock: clock)
    }

    /// Apply a remote delete operation
    public func applyDelete(entityType: String, entityId: UUIDV4) throws {
        guard syncEnabled else {
            throw StoreError.syncNotEnabled
        }

        let sql: SQL = "DELETE FROM \(raw: entityType) WHERE id = \(entityId)"
        try connection.execute(sql)
    }

    /// Update local clock from received remote clock
    public func updateClock(received: Int64) {
        clock.update(received: received)
    }
}
