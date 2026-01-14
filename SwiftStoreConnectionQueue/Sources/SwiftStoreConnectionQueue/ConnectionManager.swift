import Foundation
import SwiftStoreCore
import SwiftStoreSync

// Re-export commonly used types from SwiftStoreSync
public typealias SyncState = SwiftStoreSync.SyncState
public typealias SyncResult = SwiftStoreSync.SyncResult
public typealias SyncConfiguration = SwiftStoreSync.SyncConfiguration

/// Sync configuration for ConnectionManager
/// A simplified wrapper that doesn't require registeredEntities (uses entities from ConnectionManager)
public struct SyncOptions: Sendable {
    /// Path to the changelog database file (nil to auto-generate from main database path)
    public let changeLogDbPath: String?
    /// Device ID for identifying the source of changes
    public let deviceId: UUIDV7
    /// Remote sync transport
    public let transport: any SyncTransport
    /// Initial sync state (must be persisted to storage and restored on app restart)
    public let initialState: SyncState
    /// Data schema version number. Lower versions cannot accept higher version data, higher versions can accept lower version data
    public let schemaVersion: Int
    /// Logical clock function that generates incrementing timestamps, defaults to current timestamp in milliseconds
    public let tickClock: @Sendable () -> Int64
    /// Table name for pending delete records
    public let pendingDeletesTable: String
    /// Sync configuration including batch size settings
    public let syncConfiguration: SyncConfiguration
    /// NTP time offset tolerance in milliseconds, nil to disable NTP verification
    public let ntpToleranceMs: Int64?

    /// Initialize sync configuration
    /// - Parameters:
    ///   - deviceId: Unique device identifier to distinguish change sources from different devices
    ///   - transport: Sync transport layer responsible for communicating with the remote server
    ///   - initialState: Initial sync state containing the last synced server and local clock values. Must be persisted to storage and restored on app restart
    ///   - schemaVersion: Data schema version number. Lower versions cannot accept higher version data, higher versions can accept lower version data
    ///   - changeLogDbPath: Path to the change log database file, nil to auto-generate from main database path (e.g., db.sqlite -> db_changelog.sqlite)
    ///   - tickClock: Logical clock function that generates incrementing timestamps, defaults to current timestamp in milliseconds
    ///   - pendingDeletesTable: Table name for pending delete records, defaults to "__swiftstore_pending_deletes"
    ///   - syncConfiguration: Sync configuration including batch size settings
    ///   - ntpToleranceMs: NTP time offset tolerance in milliseconds, nil to disable NTP verification
    public init(
        deviceId: UUIDV7,
        transport: any SyncTransport,
        initialState: SyncState,
        schemaVersion: Int,
        changeLogDbPath: String? = nil,
        tickClock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        pendingDeletesTable: String = "__swiftstore_pending_deletes",
        syncConfiguration: SyncConfiguration = SyncConfiguration(),
        ntpToleranceMs: Int64? = 5000
    ) {
        self.changeLogDbPath = changeLogDbPath
        self.deviceId = deviceId
        self.transport = transport
        self.initialState = initialState
        self.schemaVersion = schemaVersion
        self.tickClock = tickClock
        self.pendingDeletesTable = pendingDeletesTable
        self.syncConfiguration = syncConfiguration
        self.ntpToleranceMs = ntpToleranceMs
    }

    /// Convert to SwiftStoreSync.SyncConfig with registered entities
    /// - Parameters:
    ///   - entities: Entity types to sync
    ///   - dbPath: Main database path (used to generate changelog path if not specified)
    func toSyncManagerConfig(entities: [any EntityProtocol.Type], dbPath: String) -> SwiftStoreSync.SyncConfig {
        let resolvedChangeLogPath = changeLogDbPath ?? Self.defaultChangeLogPath(from: dbPath)
        return SwiftStoreSync.SyncConfig(
            changeLogDbPath: resolvedChangeLogPath,
            deviceId: deviceId,
            registeredEntities: entities,
            transport: transport,
            initialState: initialState,
            schemaVersion: schemaVersion,
            tickClock: tickClock,
            pendingDeletesTable: pendingDeletesTable,
            syncConfiguration: syncConfiguration,
            ntpToleranceMs: ntpToleranceMs
        )
    }

    /// Get the resolved changelog database path
    /// - Parameter dbPath: Main database path (used if changeLogDbPath is nil)
    /// - Returns: The resolved changelog database path
    func resolvedChangeLogPath(dbPath: String) -> String {
        changeLogDbPath ?? Self.defaultChangeLogPath(from: dbPath)
    }

    /// Generate default changelog database path from main database path
    /// e.g., /path/to/db.sqlite -> /path/to/db_changelog.sqlite
    private static func defaultChangeLogPath(from dbPath: String) -> String {
        let nsPath = dbPath as NSString
        let directory = nsPath.deletingLastPathComponent
        let filename = nsPath.lastPathComponent as NSString
        let ext = filename.pathExtension
        let name = filename.deletingPathExtension

        let changeLogFilename = ext.isEmpty ? "\(name)_changelog" : "\(name)_changelog.\(ext)"
        return directory.isEmpty ? changeLogFilename : (directory as NSString).appendingPathComponent(changeLogFilename)
    }
}

/// Manages database connections with a single writer and multiple readers.
/// This ensures thread-safety and optimal performance using SQLite's WAL mode.
/// Thread safety is handled by the internal actor instances.
public final class ConnectionManager: Sendable {
    private let path: String
    private let options: SQLiteConnection.Options
    private let maxReadConnections: Int
    private let setupTask: Lock<Task<Void, Error>?> = Lock(nil)
    private let entities: [any EntityProtocol.Type]
    private let syncEnabled: Bool

    private let writer: WritableConnectionActor
    private let readers: [ReaderEntry]

    private struct ReaderEntry: Sendable {
        let actor: ConnectionActor
        let isInUse: Mutex<Bool>
    }

    /// Initialize with database path and options
    /// - Parameters:
    ///   - path: Path to the database file
    ///   - options: SQLite connection options, `wal` is always set to true
    ///   - maxReadConnections: Maximum number of read connections in the pool
    ///   - syncConfig: Optional sync configuration (includes change tracking)
    public init(
        path: String,
        entities: [any EntityProtocol.Type],
        options: SQLiteConnection.Options = .init(),
        maxReadConnections: Int = 4,
        syncConfig: SyncOptions? = nil
    ) throws {
        self.path = path
        self.options = options
        self.maxReadConnections = maxReadConnections
        self.entities = entities
        self.syncEnabled = syncConfig != nil

        // Ensure directory exists for main database
        let directoryPath = (path as NSString).deletingLastPathComponent
        if !directoryPath.isEmpty {
            try FileManager.default.createDirectory(
                atPath: directoryPath,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        // Ensure directory exists for changelog database
        if let syncConfig {
            let changeLogPath = syncConfig.resolvedChangeLogPath(dbPath: path)
            let changeLogDir = (changeLogPath as NSString).deletingLastPathComponent
            if !changeLogDir.isEmpty {
                try FileManager.default.createDirectory(
                    atPath: changeLogDir,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            }
        }

        // Ensure WAL mode is enabled for concurrent read/write
        var writeOptions = options
        writeOptions.walMode = true

        // Create writer connection with optional sync
        let writerConn = try SQLiteConnection(path: path, options: writeOptions)
        let managerConfig = syncConfig?.toSyncManagerConfig(entities: entities, dbPath: path)
        self.writer = try WritableConnectionActor(connection: writerConn, syncConfig: managerConfig)

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

    public func migrate(dryRun: Bool = true) async throws {
        if setupTask.value() == nil {
            let task = Task {
                try await self.write { connection in
                    let migrator = Migrator(connection: connection, trackDeletes: syncEnabled, createUpdateTrigger: syncEnabled)
                    let plan: MigrationPlan = try migrator.plan(for: self.entities)
                    if !dryRun {
                        try migrator.apply(plan)
                    }
                    print("Migration Plan:")
                    print(plan)
                }
            }
            setupTask.setValue(task)
        }
        if let task = setupTask.value() {
            try await task.value
        }
    }

    /// Execute a block with the write connection.
    /// Only one write operation can happen at a time.
    public func write<T: Sendable>(_ block: @Sendable (SQLiteConnection) throws -> T, transaction: Bool = true) async throws -> T {
        try await writer.run { conn in
            if transaction {
                try conn.transaction {
                    try block(conn)
                }
            } else {
                try block(conn)
            }
        }
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

    init(connection: SQLiteConnection, syncConfig: SwiftStoreSync.SyncConfig? = nil) throws {
        self.connection = connection
        if let config = syncConfig {
            self.syncManager = try SyncManager(connection: connection, config: config)
        } else {
            self.syncManager = nil
        }
    }

    /// Execute a block with the connection
    /// To ensure connection is not used concurrently, block must not be async, it will be executed in sequence.
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
