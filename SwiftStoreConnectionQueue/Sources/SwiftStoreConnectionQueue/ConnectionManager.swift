import Foundation
import OSLog
import SwiftStoreCore
import SwiftStoreSync

/// Configuration for ChangeTracker
public struct ChangeTrackerConfig: Sendable {
    /// Path to the changelog database file
    public let changeLogDbPath: String
    /// Device ID for identifying the source of changes
    public let deviceId: UUIDV4
    /// Name of the pending deletes table
    public let pendingDeletesTable: String
    /// Entity types to track changes for
    public let registeredEntities: [any EntityProtocol.Type]
    /// Function to tick the logical clock
    public let tickClock: @Sendable () -> Int64

    public init(
        changeLogDbPath: String,
        deviceId: UUIDV4,
        pendingDeletesTable: String = "__swiftstore_pending_deletes",
        registeredEntities: [any EntityProtocol.Type],
        tickClock: @escaping @Sendable () -> Int64
    ) {
        self.changeLogDbPath = changeLogDbPath
        self.deviceId = deviceId
        self.pendingDeletesTable = pendingDeletesTable
        self.registeredEntities = registeredEntities
        self.tickClock = tickClock
    }
}

/// Manages database connections with a single writer and multiple readers.
/// This ensures thread-safety and optimal performance using SQLite's WAL mode.
/// Thread safety is handled by the internal ConnectionActor instances.
public final class ConnectionManager: Sendable {
    private let path: String
    private let options: SQLiteConnection.Options
    private let maxReadConnections: Int

    private let writer: WritableConnectionActor
    private let readers: [ReaderEntry]
    private let changeLogReader: ChangeLogReaderActor?

    private struct ReaderEntry: Sendable {
        let actor: ConnectionActor
        let isInUse: Mutex<Bool>
    }

    /// Initialize with database path and options
    /// - Parameters:
    ///   - path: Path to the database file
    ///   - options: SQLite connection options
    ///   - maxReadConnections: Maximum number of read connections in the pool
    ///   - changeTrackerConfig: Optional configuration for change tracking
    public init(
        path: String,
        options: SQLiteConnection.Options = .init(),
        maxReadConnections: Int = 4,
        changeTrackerConfig: ChangeTrackerConfig? = nil
    ) throws {
        self.path = path
        self.options = options
        self.maxReadConnections = maxReadConnections

        // Ensure WAL mode is enabled for concurrent read/write
        var writeOptions = options
        writeOptions.walMode = true

        // Create writer connection with optional change tracking
        let writerConn = try SQLiteConnection(path: path, options: writeOptions)
        self.writer = try WritableConnectionActor(
            connection: writerConn,
            changeTrackerConfig: changeTrackerConfig
        )

        // Create changelog reader actor if change tracking is configured
        if let config = changeTrackerConfig {
            self.changeLogReader = try ChangeLogReaderActor(
                changeLogDbPath: config.changeLogDbPath,
                deviceId: config.deviceId
            )
        } else {
            self.changeLogReader = nil
        }

        // Create reader connections
        var readerEntries: [ReaderEntry] = []
        for _ in 0..<maxReadConnections {
            var readOptions = options
            readOptions.walMode = true
            let conn = try SQLiteConnection(path: path, options: readOptions)
            readerEntries.append(ReaderEntry(
                actor: ConnectionActor(connection: conn),
                isInUse: Mutex<Bool>(false)
            ))
        }
        self.readers = readerEntries
    }

    /// Execute a block with the write connection.
    /// Only one write operation can happen at a time.
    public func write<T: Sendable>(_ block: @Sendable (SQLiteConnection) throws -> T) async throws -> T {
        try await writer.run(block)
    }

    /// Execute a block with one of the read connections.
    /// Multiple read operations can happen concurrently.
    /// Uses a pool pattern to find an available reader.
    public func read<T: Sendable>(_ block: @Sendable (SQLiteConnection) throws -> T) async throws -> T {
        // Try to find a reader that is not in use
        for reader in readers {
            let found = reader.isInUse.withLock { isInUse in
                if !isInUse {
                    isInUse = true
                    return true
                }
                return false
            }

            if found {
                defer { reader.isInUse.withLock { $0 = false } }
                return try await reader.actor.run(block)
            }
        }

        // Fallback: if all are in use, pick one and wait (using round-robin-ish behavior via actor serialization)
        // This ensures we always provide a connection even if under heavy load.
        let randomReader = readers.randomElement()!
        randomReader.isInUse.withLock { $0 = true }
        defer { randomReader.isInUse.withLock { $0 = false } }
        return try await randomReader.actor.run(block)
    }

    /// Start change tracking (if configured)
    public func startChangeTracking() async throws {
        try await writer.startChangeTracking()
    }

    /// Stop change tracking (if configured)
    public func stopChangeTracking() async {
        await writer.stopChangeTracking()
    }

    /// Check if change tracking is enabled
    public var isChangeTrackingEnabled: Bool {
        get async {
            await writer.isChangeTrackingEnabled
        }
    }

    /// Get changes since a given clock value
    /// Returns nil if change tracking is not configured
    public func changesSince(clock: Int64) async throws -> [ChangeLog]? {
        guard let reader = changeLogReader else { return nil }
        return try await reader.changesSince(clock: clock)
    }

    /// Get all changes (for initial sync)
    /// Returns nil if change tracking is not configured
    public func allChanges() async throws -> [ChangeLog]? {
        guard let reader = changeLogReader else { return nil }
        return try await reader.allChanges()
    }

    /// Get the latest clock value in the changelog
    /// Returns nil if change tracking is not configured
    public func latestClock() async throws -> Int64? {
        guard let reader = changeLogReader else { return nil }
        return try await reader.latestClock()
    }

    /// Count changes since a given clock value
    /// Returns nil if change tracking is not configured
    public func countChangesSince(clock: Int64) async throws -> Int? {
        guard let reader = changeLogReader else { return nil }
        return try await reader.countChangesSince(clock: clock)
    }

    /// Check if change tracking is configured
    public var hasChangeTracking: Bool {
        changeLogReader != nil
    }
}

/// Internal actor to serialize access to a single SQLite connection (read-only)
actor ConnectionActor {
    private let connection: SQLiteConnection

    init(connection: SQLiteConnection) {
        self.connection = connection
    }

    func run<T>(_ block: @Sendable (SQLiteConnection) throws -> T) throws -> T {
        try block(connection)
    }
}

/// Actor for writable connection with optional ChangeTracker support
public actor WritableConnectionActor {
    private let connection: SQLiteConnection
    private let changeTracker: ChangeTracker?
    private var isTracking: Bool = false

    /// Initialize with connection and optional change tracker config
    init(connection: SQLiteConnection, changeTrackerConfig: ChangeTrackerConfig?) throws {
        self.connection = connection

        if let config = changeTrackerConfig {
            self.changeTracker = try ChangeTracker(
                connection: connection,
                changeLogDbPath: config.changeLogDbPath,
                deviceId: config.deviceId,
                pendingDeletesTable: config.pendingDeletesTable,
                registeredEntities: config.registeredEntities,
                tickClock: config.tickClock
            )
        } else {
            self.changeTracker = nil
        }
    }

    /// Execute a block with the connection
    func run<T>(_ block: @Sendable (SQLiteConnection) throws -> T) throws -> T {
        try block(connection)
    }

    /// Start change tracking
    func startChangeTracking() throws {
        guard let tracker = changeTracker else { return }
        guard !isTracking else { return }
        try tracker.start()
        isTracking = true
    }

    /// Stop change tracking
    func stopChangeTracking() {
        guard let tracker = changeTracker else { return }
        guard isTracking else { return }
        tracker.stop()
        isTracking = false
    }

    /// Check if change tracking is enabled and active
    var isChangeTrackingEnabled: Bool {
        changeTracker != nil && isTracking
    }
}

/// Actor for reading changes from the changelog database
public actor ChangeLogReaderActor {
    private let reader: ChangeTrackerReader

    /// Initialize with changelog database path and device ID
    init(changeLogDbPath: String, deviceId: UUIDV4) throws {
        self.reader = try ChangeTrackerReader(changeLogDbPath: changeLogDbPath, deviceId: deviceId)
    }

    /// Get changes since a given clock value
    func changesSince(clock: Int64) throws -> [ChangeLog] {
        try reader.changesSince(clock: clock)
    }

    /// Get all changes (for initial sync)
    func allChanges() throws -> [ChangeLog] {
        try reader.allChanges()
    }

    /// Get the latest clock value in the changelog
    func latestClock() throws -> Int64 {
        try reader.latestClock()
    }

    /// Count changes since a given clock value
    func countChangesSince(clock: Int64) throws -> Int {
        try reader.countChangesSince(clock: clock)
    }
}

