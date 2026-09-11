import Foundation
import SwiftStoreCore
import SwiftStoreSync
import SwiftStoreSyncCloudTransport
import CloudKit
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

public typealias CloudKitSyncConfiguration = SwiftStoreSyncCloudTransport.CloudKitSyncConfiguration
public typealias LegacySyncMigration = SwiftStoreSync.LegacySyncMigration

/// CloudKit-only synchronization. All durable state resides in the business database.
public struct SyncOptions: Sendable {
    public let deviceId: UUIDV7
    public let schemaVersion: Int
    public let cloudKit: CloudKitSyncConfiguration
    public let syncConfiguration: SyncConfiguration
    public let migration: LegacySyncMigration?

    public init(deviceId: UUIDV7, schemaVersion: Int, cloudKit: CloudKitSyncConfiguration,
                syncConfiguration: SyncConfiguration = .init(), migration: LegacySyncMigration? = nil) {
        self.deviceId = deviceId; self.schemaVersion = schemaVersion; self.cloudKit = cloudKit
        self.syncConfiguration = syncConfiguration; self.migration = migration
    }

    var scope: String {
        [cloudKit.containerIdentifier, cloudKit.zoneName, cloudKit.recordType].joined(separator: "/")
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
    // Configured only during initialization, before the manager escapes to callers.
    private var setupSignal = AsyncSignal(timeout: .seconds(10))
    private let migrationStarted = Lock<Bool>(false)
    public let entities: [any EntityProtocol.Type]
    public let syncEnabled: Bool
    private let cloudSubscriptionID: String?

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
        self.cloudSubscriptionID = syncConfig?.cloudKit.subscriptionID

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
            var writeOptions = options.toSQLiteOptions(walMode: walMode)
            // Sync acknowledgement durability must include the business write and its log.
            if syncConfig != nil { writeOptions.synchronous = 2 }
            let writerConn = try SQLiteConnection(path: path, options: writeOptions)
            if let syncConfig, syncConfig.migration == nil {
                let imported: Int64 = try writerConn.tableExists("__swiftstore_cloud_state")
                    ? writerConn.queryScalar("SELECT legacy_imported FROM __swiftstore_cloud_state WHERE singleton=1") ?? 0 : 0
                let url = URL(fileURLWithPath: path)
                let ext = url.pathExtension
                let oldName = url.deletingPathExtension().lastPathComponent + "_changelog" + (ext.isEmpty ? "" : "." + ext)
                let oldPath = url.deletingLastPathComponent().appendingPathComponent(oldName).path
                let hasOldTombstones = try writerConn.tableExists("__swiftstore_sync_tombstones")
                if imported == 0 && (FileManager.default.fileExists(atPath: oldPath) || hasOldTombstones) {
                    throw ConnectionManagerError.invalidConfiguration("Legacy sync data found; supply LegacySyncMigration with the original changelog and CloudKit journal paths")
                }
            }
            self.writer = try WritableConnectionActor(connection: writerConn, entities: entities, syncConfig: syncConfig)
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

    /// Initialize synchronously and automatically start applying committed migrations.
    /// Reads, writes and sync wait for setup and propagate migration or additional setup errors.
    /// Readonly mode is rejected. Omit migrations and call migrate separately to preview first.
    /// - Parameter adoptingBaseline: Optional legacy baseline; defaults to the first migration.
    public convenience init(
        path: String,
        entities: [any EntityProtocol.Type],
        migrations: [StoreMigration],
        options: ConnectionOptions = .init(),
        syncConfig: SyncOptions? = nil,
        adoptingBaseline baselineID: String? = nil
    ) throws {
        guard !options.readonly else {
            throw ConnectionManagerError.readonlyMode("Cannot migrate in readonly mode.")
        }
        try self.init(path: path, entities: entities, options: options, syncConfig: syncConfig)
        // Automatic setup is already scheduled, so the missing-migrate watchdog is unnecessary.
        // Large migrations must not permanently fail waiting callers after ten seconds.
        setupSignal = AsyncSignal()
        migrationStarted.withLock { $0 = true }
        Task {
            do { try await applyMigrations(migrations, adoptingBaseline: baselineID) }
            catch { /* applyMigrations records the failure in setupSignal for all callers. */ }
        }
    }

    /// Apply committed migrations before exposing connections or starting sync tracking.
    /// A database without migration history adopts the first migration if its schema matches.
    /// Supply adoptingBaseline to adopt a later version instead; fresh databases run all steps.
    /// Use previewMigrations for a read-only preview; preview does not complete setup.
    public func migrate(migrations: [StoreMigration], adoptingBaseline baselineID: String? = nil) async throws {
        guard !options.readonly else {
            throw ConnectionManagerError.readonlyMode("Cannot migrate in readonly mode.")
        }
        let shouldRun = migrationStarted.withLock { started -> Bool in
            if started { return false }
            started = true
            return true
        }
        guard shouldRun else {
            try await setupSignal.wait()
            return
        }
        try await applyMigrations(migrations, adoptingBaseline: baselineID)
    }

    private func applyMigrations(_ migrations: [StoreMigration], adoptingBaseline baselineID: String?) async throws {
        do {
            try await _write { connection in
                let expected = SchemaSnapshot(entities: self.entities)
                guard migrations.last?.target == expected else {
                    throw VersionedMigrationError.invalidHistory("Latest migration does not match registered entities")
                }
                let runner = VersionedMigrator(connection: connection, migrations: migrations)
                if let baselineID = baselineID ?? migrations.first?.id {
                    guard migrations.contains(where: { $0.id == baselineID }) else {
                        throw VersionedMigrationError.invalidHistory("Unknown baseline ID: \(baselineID)")
                    }
                    do {
                        _ = try runner.pendingMigrationIDs()
                    } catch VersionedMigrationError.baselineRequired {
                        try runner.adoptBaseline(through: baselineID)
                    }
                }
                try runner.migrate()
            }
            try await writer?.startTracking()
            try await performAdditionalSetup()
            await setupSignal.signal()
        } catch {
            await setupSignal.signal(result: .failure(error))
            throw error
        }
    }

    /// Does not execute migration bodies, write history, or release the setup gate.
    public func previewMigrations(_ migrations: [StoreMigration]) async throws -> [String] {
        try await _write({ connection in
            try VersionedMigrator(connection: connection, migrations: migrations).pendingMigrationIDs()
        }, transaction: false)
    }

    /// Subclasses can override this method to add additional initialization logic.
    /// This method is called after migration completes but before migration completion is signaled.
    open func performAdditionalSetup() async throws {
        // Default implementation is empty, subclasses can override
    }

    /// Optionally wait for migrations, sync tracking and additional setup to complete.
    /// read, write and sync already wait automatically. Repeated and concurrent calls share
    /// the same result. Migration/setup failures are thrown to all current and future callers.
    public func waitForMigration() async throws {
        try await setupSignal.wait()
    }

    /// Internal write that bypasses waitForMigration (used by migrate to avoid deadlock)
    private func _write<T: Sendable>(
        isolation: isolated (any Actor)? = #isolation,
        _ block: @Sendable (SQLiteConnection) throws -> T, transaction: Bool = true
    ) async throws -> T {
        guard let writer else {
            throw ConnectionManagerError.readonlyMode("Cannot write in readonly mode.")
        }
        return try await writer.run(block, transaction: transaction)
    }

    /// Execute a block with the write connection.
    /// Only one write operation can happen at a time.
    /// - Throws: `ConnectionManagerError.readonlyMode` if in readonly mode
    public func write<T: Sendable>(
        isolation: isolated (any Actor)? = #isolation,
        _ block: @Sendable (SQLiteConnection) throws -> T, transaction: Bool = true
    ) async throws -> T {
        try await waitForMigration()
        return try await _write(block, transaction: transaction)
    }

    /// Execute a block with one of the read connections.
    /// Multiple read operations can happen concurrently.
    /// Uses a pool pattern to find an available reader.
    public func read<T: Sendable>(
        isolation: isolated (any Actor)? = #isolation,
        _ block: @Sendable (SQLiteConnection) throws -> T
    ) async throws -> T {
        try await waitForMigration()
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

    /// Send a bounded changelog batch sequence, then fetch CloudKit changes.
    /// - Returns: Sync result with statistics
    /// - Throws: `ConnectionManagerError.readonlyMode` if in readonly mode
    public func sync() async throws -> SyncResult {
        try await waitForMigration()
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

    /// Forward CloudKit silent notifications. On iOS 16 this wakes the Operations driver.
    @discardableResult
    public func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let id = CKNotification(fromRemoteNotificationDictionary: userInfo)?.subscriptionID,
              id == cloudSubscriptionID, let writer else { return false }
        // Parse the non-Sendable UIKit dictionary on the caller's executor.
        Task { [weak writer] in _ = await writer?.handleCloudNotification(id) }
        return true
    }

    public var lastSyncError: Error? { get async { await writer?.lastSyncError } }

    /// Suspend automatic syncing while continuing to track local writes.
    public func stopSync() async {
        await writer?.stopSync()
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

/// Owns both the business writer and the synchronous CloudKit persistence core.
public actor WritableConnectionActor {
    private let connection: SQLiteConnection
    private let syncManager: SyncManager?
    private let syncOptions: SyncOptions?
    private var controller: CloudKitSyncController?
    private var session = UUID()
    private var trackingReady = false
    private var automaticSyncStopped = false
    private var lastSignaledSequence: Int64 = 0
    package var cloudSessionID: UUID { session }
    private var transactionWaiters: [CheckedContinuation<Void, Never>] = []

    init(connection: SQLiteConnection, entities: [any EntityProtocol.Type], syncConfig: SyncOptions?) throws {
        self.connection = connection; syncOptions = syncConfig
        if let config = syncConfig {
            guard (1...200).contains(config.syncConfiguration.batchSize), config.cloudKit.ntpToleranceMs > 0,
                  config.cloudKit.assetThreshold > 0 else { throw ConnectionManagerError.invalidConfiguration("Invalid CloudKit sync limits") }
            syncManager = try SyncManager(connection: connection, deviceID: config.deviceId, entities: entities,
                schemaVersion: config.schemaVersion, migration: config.migration, scope: config.scope)
        } else { syncManager = nil }
    }

    func run<T>(_ block: @Sendable (SQLiteConnection) throws -> T, transaction: Bool = true) throws -> T {
        defer { writerDidFinish() }
        return try transaction ? connection.transaction { try block(connection) } : block(connection)
    }

    private func writerDidFinish() {
        guard !connection.isInTransaction else { return }
        let waiters = transactionWaiters; transactionWaiters = []
        for waiter in waiters { waiter.resume() }
        guard trackingReady, !automaticSyncStopped, syncOptions?.cloudKit.automaticallySync == true,
              let latest = try? syncManager?.latestSequence(), latest != lastSignaledSequence else { return }
        lastSignaledSequence = latest
        let generation = session
        Task { [weak self] in await self?.schedule(generation: generation) }
    }

    func startTracking() throws {
        try syncManager?.startTracking(); trackingReady = true
        if syncOptions?.cloudKit.automaticallySync == true {
            let generation = session
            Task { [weak self] in await self?.schedule(generation: generation) }
        }
    }

    private func cloudController() throws -> CloudKitSyncController {
        guard trackingReady, let options = syncOptions else { throw SyncError.notConfigured("CloudKit sync is not configured or migration is incomplete") }
        if let controller { return controller }
        let controller = CloudKitSyncController(configuration: options.cloudKit, store: WeakCloudWriter(self),
            session: session, batchSize: options.syncConfiguration.batchSize)
        self.controller = controller
        return controller
    }

    private func schedule(generation: UUID) async {
        guard !automaticSyncStopped, session == generation, let controller = try? cloudController() else { return }
        await controller.localChangesAvailable()
    }

    func sync() async throws -> SyncResult { automaticSyncStopped = false; return try await cloudController().sync() }
    var syncState: SyncState? { try? syncManager?.state() }
    var lastSyncError: Error? { get async { await controller?.lastError } }

    func handleCloudNotification(_ id: String) async -> Bool {
        guard !automaticSyncStopped, let controller = try? cloudController() else { return false }
        return await controller.handleRemoteNotification(subscriptionID: id)
    }

    func stopSync() async {
        automaticSyncStopped = true
        session = UUID()
        let previous = controller; controller = nil
        syncManager?.abandonBatch()
        let waiters = transactionWaiters; transactionWaiters = []
        for waiter in waiters { waiter.resume() }
        await previous?.stop()
    }

    private func committedWriter(_ generation: UUID) async throws -> SyncManager {
        while connection.isInTransaction && generation == session {
            await withCheckedContinuation { transactionWaiters.append($0) }
        }
        guard generation == session, trackingReady, let syncManager else { throw CancellationError() }
        return syncManager
    }
}

extension WritableConnectionActor: CloudSyncStore {
    package func bindCloudAccount(_ accountID: String, scope: String, driver: CloudDriverKind, session: UUID) async throws -> CloudStoreState {
        try await committedWriter(session).bind(accountID: accountID, scope: scope, driver: driver)
    }
    package func nextCloudBatch(limit: Int, session: UUID) async throws -> CloudUploadBatch? {
        try await committedWriter(session).nextBatch(limit: limit)
    }
    package func commitCloudBatch(_ batch: CloudUploadBatch, decisions: [CloudUploadDecision], session: UUID) async throws -> CloudCommitCounts {
        try await committedWriter(session).commit(batch, incoming: decisions)
    }
    package func applyCloudRecords(_ records: [CloudRecord], checkpoint: CloudCheckpoint?, session: UUID) async throws -> Int {
        try await committedWriter(session).receive(records, checkpoint: checkpoint)
    }
    package func saveCloudCheckpoint(_ checkpoint: CloudCheckpoint, session: UUID) async throws {
        try await committedWriter(session).saveCheckpoint(checkpoint)
    }
    package func markCloudZoneCreated(session: UUID) async throws { try await committedWriter(session).markZoneCreated() }
    package func cloudSyncState(session: UUID) async throws -> SyncState { try await committedWriter(session).state() }
}

/// The driver must not keep the database owner alive through its store callbacks.
/// The weak reference is assigned only during initialization; ARC synchronizes loads.
private final class WeakCloudWriter: CloudSyncStore, @unchecked Sendable {
    private weak var writer: WritableConnectionActor?
    init(_ writer: WritableConnectionActor) { self.writer = writer }
    private func owner() throws -> WritableConnectionActor {
        guard let writer else { throw CancellationError() }
        return writer
    }
    func bindCloudAccount(_ accountID: String, scope: String, driver: CloudDriverKind, session: UUID) async throws -> CloudStoreState {
        try await owner().bindCloudAccount(accountID, scope: scope, driver: driver, session: session)
    }
    func nextCloudBatch(limit: Int, session: UUID) async throws -> CloudUploadBatch? {
        try await owner().nextCloudBatch(limit: limit, session: session)
    }
    func commitCloudBatch(_ batch: CloudUploadBatch, decisions: [CloudUploadDecision], session: UUID) async throws -> CloudCommitCounts {
        try await owner().commitCloudBatch(batch, decisions: decisions, session: session)
    }
    func applyCloudRecords(_ records: [CloudRecord], checkpoint: CloudCheckpoint?, session: UUID) async throws -> Int {
        try await owner().applyCloudRecords(records, checkpoint: checkpoint, session: session)
    }
    func saveCloudCheckpoint(_ checkpoint: CloudCheckpoint, session: UUID) async throws {
        try await owner().saveCloudCheckpoint(checkpoint, session: session)
    }
    func markCloudZoneCreated(session: UUID) async throws { try await owner().markCloudZoneCreated(session: session) }
    func cloudSyncState(session: UUID) async throws -> SyncState { try await owner().cloudSyncState(session: session) }
}
