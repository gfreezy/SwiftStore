import Foundation
import SwiftStoreCore
import SwiftStoreSync
import os.log

// MARK: - Errors

/// Errors thrown by ConnectionManager
public enum ConnectionManagerError: Error, CustomStringConvertible {
    case invalidConfiguration(String)
    case readonlyMode(String)

    public var description: String {
        switch self {
        case .invalidConfiguration(let message):
            return "ConnectionManager configuration error: \(message)"
        case .readonlyMode(let message):
            return "ConnectionManager readonly error: \(message)"
        }
    }
}

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
    func toSyncManagerConfig(entities: [any EntityProtocol.Type], dbPath: String)
        -> SwiftStoreSync.SyncConfig
    {
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
        return directory.isEmpty
            ? changeLogFilename : (directory as NSString).appendingPathComponent(changeLogFilename)
    }
}

/// Connection options for ConnectionManager
public struct ConnectionOptions: Sendable {
    /// Open database in read-only mode (no writer connection will be created)
    public var readonly: Bool
    /// Synchronous mode: 0=OFF (fastest, risky), 1=NORMAL (balanced), 2=FULL (safest, slowest)
    public var synchronous: Int
    /// Cache size in KB (negative value means KB, positive means pages)
    public var cacheSize: Int
    /// Maximum number of read connections in the pool
    public var maxReadConnections: Int

    public init(
        readonly: Bool = false,
        synchronous: Int = 1,
        cacheSize: Int = -2000,
        maxReadConnections: Int = 4
    ) {
        self.readonly = readonly
        self.synchronous = synchronous
        self.cacheSize = cacheSize
        self.maxReadConnections = maxReadConnections
    }

    /// Convert to SQLiteConnection.Options with computed walMode
    /// - Parameter needsWal: Whether WAL mode is needed (based on readonly and syncConfig)
    func toSQLiteOptions(walMode: Bool) -> SQLiteConnection.Options {
        var opts = SQLiteConnection.Options()
        opts.readonly = readonly
        opts.walMode = walMode
        opts.synchronous = synchronous
        opts.cacheSize = cacheSize
        return opts
    }
}

/// Manages database connections with a single writer and multiple readers.
/// This ensures thread-safety and optimal performance using SQLite's WAL mode.
/// Thread safety is handled by the internal actor instances.
open class ConnectionManager: @unchecked Sendable {
    public let path: String
    public let options: ConnectionOptions
    private let setupSignal = AsyncSignal()
    private let migrationStarted = Lock<Bool>(false)
    public let entities: [any EntityProtocol.Type]
    public let syncEnabled: Bool

    private let writer: WritableConnectionActor?
    private let readers: [ReaderEntry]

    private struct ReaderEntry: Sendable {
        let actor: ConnectionActor
        let isInUse: Mutex<Bool>
    }

    /// Initialize with database path and options
    /// - Parameters:
    ///   - path: Path to the database file
    ///   - entities: Entity types to manage
    ///   - options: Connection options (readonly, synchronous, etc.)
    ///   - syncConfig: Optional sync configuration (includes change tracking). Cannot be used with readonly mode.
    public init(
        path: String,
        entities: [any EntityProtocol.Type],
        options: ConnectionOptions = .init(),
        syncConfig: SyncOptions? = nil
    ) throws {
        // Validate: readonly mode cannot be used with sync
        if options.readonly && syncConfig != nil {
            throw ConnectionManagerError.invalidConfiguration(
                "Cannot use sync with readonly mode. Sync requires write access.")
        }

        // Validate: readonly entities can only be used with readonly connection
        let readonlyEntities = entities.filter { $0.isReadonly }
        let nonReadonlyEntities = entities.filter { !$0.isReadonly }

        if options.readonly && !nonReadonlyEntities.isEmpty {
            let names = nonReadonlyEntities.map { $0.tableName }.joined(separator: ", ")
            throw ConnectionManagerError.invalidConfiguration(
                "Readonly connection can only use readonly entities. Non-readonly entities found: \(names)")
        }

        if !options.readonly && !readonlyEntities.isEmpty {
            let names = readonlyEntities.map { $0.tableName }.joined(separator: ", ")
            throw ConnectionManagerError.invalidConfiguration(
                "Readonly entities can only be used with readonly connection. Readonly entities found: \(names)")
        }

        self.path = path
        self.options = options
        self.entities = entities
        self.syncEnabled = syncConfig != nil

        // Compute WAL mode: enabled when not readonly or when sync is enabled
        // WAL provides better concurrent read performance even in write mode
        let walMode = !options.readonly

        // Ensure directory exists for main database
        let directoryPath = (path as NSString).deletingLastPathComponent
        if !directoryPath.isEmpty {
            try FileManager.default.createDirectory(
                atPath: directoryPath,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        // Create writer connection only if not readonly
        if options.readonly {
            self.writer = nil
        } else {
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

            let writeOptions = options.toSQLiteOptions(walMode: walMode)
            let writerConn = try SQLiteConnection(path: path, options: writeOptions)
            let managerConfig = syncConfig?.toSyncManagerConfig(entities: entities, dbPath: path)
            self.writer = try WritableConnectionActor(connection: writerConn, syncConfig: managerConfig)
        }

        // Create reader connections
        var readerEntries: [ReaderEntry] = []
        let readOptions = options.toSQLiteOptions(walMode: walMode)
        for _ in 0..<options.maxReadConnections {
            let conn = try SQLiteConnection(path: path, options: readOptions)
            readerEntries.append(
                ReaderEntry(
                    actor: ConnectionActor(connection: conn),
                    isInUse: Mutex<Bool>(false)
                ))
        }
        self.readers = readerEntries
    }

    /// Run database migration
    /// - Parameter dryRun: If true, only generates the migration plan without applying it
    /// - Throws: `ConnectionManagerError.readonlyMode` if in readonly mode
    public func migrate(dryRun: Bool = true, dropUnusedColumns: Bool = false) async throws {
        guard !options.readonly else {
            throw ConnectionManagerError.readonlyMode("Cannot migrate in readonly mode.")
        }

        let shouldRun = migrationStarted.withLock { started -> Bool in
            if started { return false }
            started = true
            return true
        }

        if shouldRun {
            do {
                try await _write { connection in
                    let migrator = Migrator(
                        connection: connection, trackDeletes: self.syncEnabled,
                        createUpdateTrigger: self.syncEnabled, dropUnusedColumns: dropUnusedColumns)
                    let plan: MigrationPlan = try migrator.plan(for: self.entities)
                    if !dryRun {
                        do {
                            try migrator.apply(plan)
                        } catch {
                            SwiftStoreLogger.error("Migration Error: \(error)")
                            #if DEBUG
                                fatalError("SwiftStore Migration Error: \(error)")
                            #else
                                throw error
                            #endif

                        }
                    }
                    SwiftStoreLogger.info("Migration Plan:\n\(plan)")
                }
                try await self.performAdditionalSetup()
                await setupSignal.signal()
            } catch {
                await setupSignal.signal(result: .failure(error))
                throw error
            }
        } else {
            try await setupSignal.wait()
        }
    }

    /// Subclasses can override this method to add additional initialization logic.
    /// This method is called after migration completes but before setupTask is marked as complete.
    open func performAdditionalSetup() async throws {
        // Default implementation is empty, subclasses can override
    }

    /// Wait for setup (migration) to complete before performing operations.
    /// If migrate() hasn't been called yet, suspends until it is called and completes.
    private func waitForSetup() async throws {
        try await setupSignal.wait()
    }

    /// Internal write that bypasses waitForSetup (used by migrate to avoid deadlock)
    private func _write<T: Sendable>(
        _ block: @Sendable (SQLiteConnection) throws -> T, transaction: Bool = true
    ) async throws -> T {
        guard let writer else {
            throw ConnectionManagerError.readonlyMode("Cannot write in readonly mode.")
        }
        return try await writer.run { conn in
            if transaction {
                try conn.transaction {
                    try block(conn)
                }
            } else {
                try block(conn)
            }
        }
    }

    /// Execute a block with the write connection.
    /// Only one write operation can happen at a time.
    /// - Throws: `ConnectionManagerError.readonlyMode` if in readonly mode
    public func write<T: Sendable>(
        _ block: @Sendable (SQLiteConnection) throws -> T, transaction: Bool = true
    ) async throws -> T {
        try await waitForSetup()
        return try await _write(block, transaction: transaction)
    }

    /// Execute a block with one of the read connections.
    /// Multiple read operations can happen concurrently.
    /// Uses a pool pattern to find an available reader.
    public func read<T: Sendable>(_ block: @Sendable (SQLiteConnection) throws -> T) async throws
        -> T
    {
        try await waitForSetup()
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
        syncEnabled
    }

    /// Check if connection is in readonly mode
    public var isReadonly: Bool {
        options.readonly
    }

    /// Perform a full sync (pull then push)
    /// - Returns: Sync result with statistics
    /// - Throws: `ConnectionManagerError.readonlyMode` if in readonly mode
    public func sync() async throws -> SyncResult {
        try await waitForSetup()
        guard let writer else {
            throw ConnectionManagerError.readonlyMode("Cannot sync in readonly mode.")
        }
        return try await writer.sync()
    }

    /// Get current sync state
    public var syncState: SyncState? {
        get async {
            await writer?.syncState
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
            throw SyncError.notConfigured(
                "SyncManager not initialized. Provide syncConfig when creating ConnectionManager.")
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
