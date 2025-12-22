import Foundation
import SwiftStoreCore
import SwiftStoreSync

/// Manages database connections with a single writer and multiple readers.
/// This ensures thread-safety and optimal performance using SQLite's WAL mode.
/// Thread safety is handled by the internal actor instances.
public final class ConnectionManager: Sendable {
    private let path: String
    private let options: SQLiteConnection.Options
    private let maxReadConnections: Int

    private let writer: WritableConnectionActor
    private let readers: [ReaderEntry]

    private struct ReaderEntry: Sendable {
        let actor: ConnectionActor
        let isInUse: Mutex<Bool>
    }

    /// Initialize with database path and options
    /// - Parameters:
    ///   - path: Path to the database file
    ///   - options: SQLite connection options
    ///   - maxReadConnections: Maximum number of read connections in the pool
    ///   - syncConfig: Optional sync configuration (includes change tracking)
    public init(
        path: String,
        options: SQLiteConnection.Options = .init(),
        maxReadConnections: Int = 4,
        syncConfig: SyncConfig? = nil
    ) throws {
        self.path = path
        self.options = options
        self.maxReadConnections = maxReadConnections

        // Ensure WAL mode is enabled for concurrent read/write
        var writeOptions = options
        writeOptions.walMode = true

        // Create writer connection with optional sync
        let writerConn = try SQLiteConnection(path: path, options: writeOptions)
        self.writer = try WritableConnectionActor(connection: writerConn, syncConfig: syncConfig)

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

    // MARK: - Sync Convenience Methods

    /// Check if sync is configured
    public var hasSyncEnabled: Bool {
        get async {
            await writer.hasSyncEnabled
        }
    }

    /// Perform a full sync (pull then push)
    /// - Returns: Sync result with statistics
    public func sync() async throws -> SyncResult {
        try await writer.sync()
    }

    /// Get current sync state
    public var syncState: SyncState? {
        get async {
            await writer.syncState
        }
    }
}

/// Internal actor to serialize access to a single SQLite connection (read-only)
actor ConnectionActor {
    let connection: SQLiteConnection

    init(connection: SQLiteConnection) {
        self.connection = connection
    }

    func run<T>(_ block: @Sendable (SQLiteConnection) throws -> T) throws -> T {
        try block(connection)
    }
}

/// Actor for writable connection with optional sync support
public actor WritableConnectionActor {
    private let connection: SQLiteConnection
    private let syncManager: SyncManager?
    private var isSyncing: Bool = false

    init(connection: SQLiteConnection, syncConfig: SyncConfig? = nil) throws {
        self.connection = connection
        if let config = syncConfig {
            self.syncManager = try SyncManager(connection: connection, config: config)
        } else {
            self.syncManager = nil
        }
    }

    /// Execute a block with the connection
    func run<T>(_ block: @Sendable (SQLiteConnection) throws -> T) throws -> T {
        try block(connection)
    }

    // MARK: - Sync Operations

    var hasSyncEnabled: Bool {
        syncManager != nil
    }

    func sync() async throws -> SyncResult {
        guard let manager = syncManager else {
            throw SyncError.notConfigured("SyncManager not initialized. Provide syncConfig when creating ConnectionManager.")
        }
        guard !isSyncing else {
            throw SyncError.syncAlreadyInProgress("Sync is already in progress.")
        }
        isSyncing = true
        defer { isSyncing = false }
        return try await manager.sync()
    }

    var syncState: SyncState? {
        syncManager?.syncState
    }
}
