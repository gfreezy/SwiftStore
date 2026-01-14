import Foundation
import SwiftStoreCore
import SwiftStoreChangeTracker

// MARK: - Sync Types

/// Sync state tracking
public struct SyncState: Codable, Sendable {
    /// Last synced server clock value
    public var lastServerClock: Int64
    /// Last synced local clock value
    public var lastLocalClock: Int64

    public init(lastServerClock: Int64, lastLocalClock: Int64) {
        self.lastServerClock = lastServerClock
        self.lastLocalClock = lastLocalClock
    }
}

/// Configuration for sync batch processing
public struct SyncConfiguration: Sendable {
    /// Number of changes to process per batch during pull
    public var batchSize: Int

    /// Whether to yield between batches to avoid blocking
    public var yieldBetweenBatches: Bool

    public init(batchSize: Int = 50, yieldBetweenBatches: Bool = true) {
        self.batchSize = batchSize
        self.yieldBetweenBatches = yieldBetweenBatches
    }
}

/// Result of a sync operation
public struct SyncResult: Sendable {
    /// Number of changes pulled from remote
    public let pulledCount: Int
    /// Number of changes pushed to remote
    public let pushedCount: Int
    /// Number of conflicts encountered
    public let conflictCount: Int
    /// Updated sync state
    public let state: SyncState

    public init(pulledCount: Int, pushedCount: Int, conflictCount: Int, state: SyncState) {
        self.pulledCount = pulledCount
        self.pushedCount = pushedCount
        self.conflictCount = conflictCount
        self.state = state
    }
}

// MARK: - Sync Config

/// Configuration for sync operations (includes change tracking config)
public struct SyncConfig: Sendable {
    // MARK: - Change Tracker Config
    /// Path to the changelog database file
    public let changeLogDbPath: String
    /// Device ID for identifying the source of changes
    public let deviceId: UUIDV7
    /// Name of the pending deletes table
    public let pendingDeletesTable: String
    /// Entity types to track changes for
    public let registeredEntities: [any EntityProtocol.Type]
    /// Function to tick the logical clock
    public let tickClock: @Sendable () -> Int64

    // MARK: - Sync Config
    /// Remote sync transport
    public let transport: any SyncTransport
    /// Sync configuration (batch size, etc.)
    public let syncConfiguration: SyncConfiguration
    /// Initial sync state
    public let initialState: SyncState
    /// Current schema version for migration compatibility
    /// Higher versions can process lower version data, lower versions ignore higher version data
    public let schemaVersion: Int
    /// Maximum acceptable time offset in milliseconds for NTP verification (nil to disable)
    public let ntpToleranceMs: Int64?

    /// Initialize sync manager configuration
    /// - Parameters:
    ///   - changeLogDbPath: Path to the change log database file for storing local change records
    ///   - deviceId: Unique device identifier to distinguish change sources from different devices
    ///   - registeredEntities: List of entity types to be synchronized
    ///   - tickClock: Logical clock function that generates incrementing timestamps, defaults to current timestamp in milliseconds
    ///   - transport: Sync transport layer responsible for communicating with the remote server
    ///   - initialState: Initial sync state containing the last synced server and local clock values. Must be persisted to storage and restored on app restart
    ///   - schemaVersion: Data schema version number. Lower versions cannot accept higher version data, higher versions can accept lower version data
    ///   - pendingDeletesTable: Table name for pending delete records, defaults to "__swiftstore_pending_deletes"
    ///   - syncConfiguration: Sync configuration including batch size settings
    ///   - ntpToleranceMs: NTP time offset tolerance in milliseconds, nil to disable NTP verification
    public init(
        changeLogDbPath: String,
        deviceId: UUIDV7,
        registeredEntities: [any EntityProtocol.Type],
        transport: any SyncTransport,
        initialState: SyncState,
        schemaVersion: Int,
        tickClock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        pendingDeletesTable: String = "__swiftstore_pending_deletes",
        syncConfiguration: SyncConfiguration = SyncConfiguration(),
        ntpToleranceMs: Int64? = 5000
    ) {
        self.changeLogDbPath = changeLogDbPath
        self.deviceId = deviceId
        self.pendingDeletesTable = pendingDeletesTable
        self.registeredEntities = registeredEntities
        self.tickClock = tickClock
        self.transport = transport
        self.syncConfiguration = syncConfiguration
        self.initialState = initialState
        self.schemaVersion = schemaVersion
        self.ntpToleranceMs = ntpToleranceMs
    }
}

/// Class that manages change tracking and synchronization
/// Combines ChangeTracker and sync logic
/// Thread-safety is provided by the containing WritableConnectionActor
public final class SyncManager {
    private let connection: SQLiteConnection
    private let changeTracker: ChangeTracker
    private let changeLogReader: ChangeTrackerReader
    private let transport: any SyncTransport
    private let deviceId: UUIDV7
    private let changeLogDbPath: String
    private let applierRegistry: EntityApplierRegistry
    private let configuration: SyncConfiguration
    private let schemaVersion: Int
    private let ntpToleranceMs: Int64?
    private var state: SyncState

    /// Initialize with database connection and sync configuration
    /// - Parameters:
    ///   - connection: The main database connection (used for writes)
    ///   - config: Sync configuration
    public init(connection: SQLiteConnection, config: SyncConfig) throws {
        self.connection = connection
        self.transport = config.transport
        self.deviceId = config.deviceId
        self.changeLogDbPath = config.changeLogDbPath
        self.configuration = config.syncConfiguration
        self.schemaVersion = config.schemaVersion
        self.ntpToleranceMs = config.ntpToleranceMs
        self.state = config.initialState

        // Create ChangeTracker
        self.changeTracker = try ChangeTracker(
            connection: connection,
            changeLogDbPath: config.changeLogDbPath,
            deviceId: config.deviceId,
            pendingDeletesTable: config.pendingDeletesTable,
            registeredEntities: config.registeredEntities,
            tickClock: config.tickClock,
            schemaVersion: config.schemaVersion
        )

        // Create EntityApplierRegistry from entity types
        self.applierRegistry = EntityApplierRegistry(entityTypes: config.registeredEntities)

        // Create ChangeTrackerReader
        self.changeLogReader = try ChangeTrackerReader(
            changeLogDbPath: config.changeLogDbPath,
            deviceId: config.deviceId
        )
    }

    // MARK: - Sync State

    /// Get current sync state
    public var syncState: SyncState {
        state
    }

    // MARK: - Sync Operations

    /// Perform a full sync (pull then push)
    /// - Returns: Sync result with statistics
    nonisolated(nonsending)
    public func sync() async throws -> SyncResult {
        // 0. Verify time sync if NTP tolerance is configured
        if let tolerance = ntpToleranceMs {
            let result = try await NTPClient.verifyTime(toleranceMs: tolerance)
            if !result.isValid {
                throw NTPError.timeOutOfSync(offsetMs: result.offsetMs, toleranceMs: tolerance)
            }
        }

        // 1. Pull changes from remote
        let pullResult = try await pull()

        // 2. Push local changes to remote
        let pushResult = try await push()

        return SyncResult(
            pulledCount: pullResult.pulledCount,
            pushedCount: pushResult.pushedCount,
            conflictCount: pullResult.conflictCount + pushResult.conflictCount,
            state: state
        )
    }

    // MARK: - Private Helpers

    /// Pull changes from remote and apply locally
    /// - Returns: Sync result for pull operation
    nonisolated(nonsending)
    private func pull() async throws -> SyncResult {
        // Get changes from remote since last sync
        let response = try await transport.pull(
            sinceClock: state.lastServerClock,
            deviceId: deviceId
        )

        try Task.checkCancellation()

        // Filter out:
        // 1. Changes from this device (they're already local)
        // 2. Changes with higher schema version (incompatible with current version)
        let remoteChanges = response.changes.filter {
            $0.deviceId != deviceId && $0.schemaVersion <= schemaVersion
        }

        guard !remoteChanges.isEmpty else {
            state.lastServerClock = response.serverClock
            return SyncResult(
                pulledCount: 0,
                pushedCount: 0,
                conflictCount: 0,
                state: state
            )
        }

        var appliedCount = 0
        var conflictCount = 0

        // Process changes in batches
        let batches = remoteChanges.chunked(into: configuration.batchSize)

        for batch in batches {
            try Task.checkCancellation()
            let result = try applyBatch(batch)
            appliedCount += result.applied
            conflictCount += result.conflicts

            // Yield between batches (tracker is re-enabled, safe for other writes)
            if configuration.yieldBetweenBatches {
                await Task.yield()
            }
        }

        // Update sync state
        state.lastServerClock = response.serverClock

        return SyncResult(
            pulledCount: appliedCount,
            pushedCount: 0,
            conflictCount: conflictCount,
            state: state
        )
    }

    /// Apply a batch of changes atomically (tracker stopped during apply)
    private func applyBatch(_ changes: [SyncChange]) throws -> (applied: Int, conflicts: Int) {
        var applied = 0
        var conflicts = 0

        changeTracker.stop()
        defer {
            do {
                try changeTracker.start()
            } catch {
                print("SwiftStoreSync: Failed to restart change tracking: \(error)")
            }
        }

        for change in changes {
            do {
                try applierRegistry.apply(change: change, to: connection)
                applied += 1
            } catch {
                print("SwiftStoreSync: Failed to apply change \(change.id): \(error)")
                conflicts += 1
            }
        }

        return (applied, conflicts)
    }

    /// Push local changes to remote
    /// - Returns: Sync result for push operation
    nonisolated(nonsending)
    private func push() async throws -> SyncResult {
        // Get local changes since last push
        let localChanges = try changeLogReader.changesSince(clock: state.lastLocalClock)
        
        guard !localChanges.isEmpty else {
            return SyncResult(
                pulledCount: 0,
                pushedCount: 0,
                conflictCount: 0,
                state: state
            )
        }

        try Task.checkCancellation()

        // Convert to SyncChange
        let syncChanges = localChanges.map { SyncChange(from: $0) }

        // Push to remote
        let response = try await transport.push(
            changes: syncChanges,
            deviceId: deviceId
        )

        // Update local clock to latest pushed
        if let lastChange = localChanges.last {
            state.lastLocalClock = lastChange.logicalClock
        }

        // Update server clock if provided
        state.lastServerClock = max(state.lastServerClock, response.serverClock)

        return SyncResult(
            pulledCount: 0,
            pushedCount: localChanges.count - response.conflicts.count,
            conflictCount: response.conflicts.count,
            state: state
        )
    }

    // MARK: - Change Log Reading

    /// Get changes since a given clock value
    public func changesSince(clock: Int64) throws -> [ChangeLog] {
        try changeLogReader.changesSince(clock: clock)
    }

    /// Get all changes (for initial sync)
    public func allChanges() throws -> [ChangeLog] {
        try changeLogReader.allChanges()
    }

    /// Get the latest clock value in the changelog
    public func latestClock() throws -> Int64 {
        try changeLogReader.latestClock()
    }

    /// Count changes since a given clock value
    public func countChangesSince(clock: Int64) throws -> Int {
        try changeLogReader.countChangesSince(clock: clock)
    }
}

// MARK: - Array Extension

extension Array {
    /// Split array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
