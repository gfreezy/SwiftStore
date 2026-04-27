import Foundation
import os.log
import SwiftStoreCore
import SwiftStoreChangeTracker

// MARK: - Sync Types

/// Sync state tracking.
///
/// Only tracks the local push watermark. Remote watermark (if any) is
/// owned by the `SyncTransport` implementation.
public struct SyncState: Codable, Sendable {
    /// Last logical clock value of a local change that has been handed to the transport.
    public var lastLocalClock: Int64

    public init(lastLocalClock: Int64) {
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
    ///   - schemaVersion: Data schema version number. Lower versions cannot accept higher version data, higher versions can accept lower version data
    ///   - pendingDeletesTable: Table name for pending delete records, defaults to "__swiftstore_pending_deletes"
    ///   - syncConfiguration: Sync configuration including batch size settings
    ///   - ntpToleranceMs: NTP time offset tolerance in milliseconds, nil to disable NTP verification
    public init(
        changeLogDbPath: String,
        deviceId: UUIDV7,
        registeredEntities: [any EntityProtocol.Type],
        transport: any SyncTransport,
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
    private let statePersistence: SyncStatePersistence
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

        // Load persisted sync state (reusing the changelog DB's writable connection).
        self.statePersistence = try SyncStatePersistence(
            connection: self.changeTracker.connection)
        self.state = try statePersistence.load()
    }

    // MARK: - Sync State

    /// Get current sync state
    public var syncState: SyncState {
        state
    }

    // MARK: - Transport Lifecycle

    /// Activate the underlying transport. Idempotent; safe to call multiple times.
    /// Typically invoked by the containing `WritableConnectionActor` before the first sync.
    nonisolated(nonsending)
    public func startTransport() async throws {
        try await transport.start(deviceId: deviceId)
    }

    /// Deactivate the underlying transport.
    nonisolated(nonsending)
    public func stopTransport() async {
        await transport.stop()
    }

    /// Stream of remote-activity signals from the transport. Consumers may
    /// observe it to auto-trigger a sync when remote changes are detected.
    public var remoteChanges: AsyncStream<Void> {
        transport.remoteChanges
    }

    // MARK: - Sync Operations

    /// Perform a full sync cycle: enqueue local changes, run a fetch+send round
    /// through the transport, and apply any pulled remote changes locally.
    /// - Returns: Sync result with statistics
    nonisolated(nonsending)
    public func sync() async throws -> SyncResult {
        if let tolerance = ntpToleranceMs {
            let result = try await NTPClient.verifyTime(toleranceMs: tolerance)
            if !result.isValid {
                throw NTPError.timeOutOfSync(offsetMs: result.offsetMs, toleranceMs: tolerance)
            }
        }

        let localChanges = try changeLogReader.changesSince(clock: state.lastLocalClock)
        try Task.checkCancellation()

        if !localChanges.isEmpty {
            try await transport.enqueue(localChanges.map { SyncChange(from: $0) })
        }

        let cycle = try await transport.syncNow()

        try Task.checkCancellation()

        let remoteChanges = cycle.pulled.filter {
            $0.deviceId != deviceId && $0.schemaVersion <= schemaVersion
        }

        var applied = 0
        var applyConflicts = 0
        if !remoteChanges.isEmpty {
            let batches = remoteChanges.chunked(into: configuration.batchSize)
            for batch in batches {
                try Task.checkCancellation()
                let result = try applyBatch(batch)
                applied += result.applied
                applyConflicts += result.conflicts
                if configuration.yieldBetweenBatches {
                    await Task.yield()
                }
            }
        }

        if let last = localChanges.last {
            state.lastLocalClock = last.logicalClock
            do {
                try statePersistence.save(state)
            } catch {
                // Recoverable: next sync re-pushes, applier is idempotent on syncKey.
                SwiftStoreLogger.error("Failed to persist sync state: \(error)")
            }
        }

        return SyncResult(
            pulledCount: applied,
            pushedCount: cycle.pushed.count,
            conflictCount: cycle.conflicts.count + applyConflicts,
            state: state
        )
    }

    // MARK: - Private Helpers

    /// Apply a batch of changes atomically (tracker stopped during apply)
    private func applyBatch(_ changes: [SyncChange]) throws -> (applied: Int, conflicts: Int) {
        var applied = 0
        var conflicts = 0

        changeTracker.stop()
        defer {
            do {
                try changeTracker.start()
            } catch {
                SwiftStoreLogger.error("Failed to restart change tracking: \(error)")
            }
        }

        for change in changes {
            do {
                try applierRegistry.apply(change: change, to: connection)
                applied += 1
            } catch {
                SwiftStoreLogger.error("Failed to apply change \(change.id): \(error)")
                conflicts += 1
            }
        }

        return (applied, conflicts)
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
