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
public typealias SyncProgress = SwiftStoreSync.SyncProgress
public typealias SyncProgressHandler = SwiftStoreSync.SyncProgressHandler
public typealias SyncConfiguration = SwiftStoreSync.SyncConfiguration

public typealias CloudKitSyncConfiguration = SwiftStoreSyncCloudTransport.CloudKitSyncConfiguration

/// CloudKit-only synchronization. All durable state resides in the business database.
public struct SyncOptions: Sendable {
    public let deviceId: UUIDV7
    public let schemaVersion: Int
    public let cloudKit: CloudKitSyncConfiguration
    public let syncConfiguration: SyncConfiguration

    public init(deviceId: UUIDV7, schemaVersion: Int, cloudKit: CloudKitSyncConfiguration,
                syncConfiguration: SyncConfiguration = .init()) {
        self.deviceId = deviceId; self.schemaVersion = schemaVersion; self.cloudKit = cloudKit
        self.syncConfiguration = syncConfiguration
    }

    fileprivate func validateLimits() throws {
        guard (1...200).contains(syncConfiguration.batchSize), cloudKit.ntpToleranceMs > 0,
              cloudKit.assetThreshold > 0 else {
            throw ConnectionManagerError.invalidConfiguration("Invalid CloudKit sync limits")
        }
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
    /// Maximum number of read connections in the pool; must be at least one.
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

/// Opens database connections on demand, with a single writer and a bounded pool of readers.
/// This ensures thread-safety and optimal performance using SQLite's WAL mode.
open class ConnectionManager: @unchecked Sendable {
    public enum Initialization: Sendable {
        /// Start opening the writer and running setup from the initializer.
        case immediate
        /// Start setup on first access. A failed database open can be retried on the next access.
        case onFirstUse
    }

    private enum SetupState {
        case manual
        case onFirstUse([StoreMigration], baselineID: String?)
        case started(Task<Void, Error>)
    }

    public let path: String
    public let options: ConnectionOptions
    public let entities: [any EntityProtocol.Type]
    public let syncEnabled: Bool
    private let cloudSubscriptionID: String?
    private let pool: ConnectionPool
    private let setup = Mutex<SetupState>(.manual)

    /// Validate configuration without opening the database.
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
        guard options.maxReadConnections > 0 else {
            throw ConnectionManagerError.invalidConfiguration("maxReadConnections must be at least one.")
        }

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

        try syncConfig?.validateLimits()
        self.path = path
        self.options = options
        self.entities = entities
        self.syncEnabled = syncConfig != nil
        self.cloudSubscriptionID = syncConfig?.cloudKit.subscriptionID
        self.pool = ConnectionPool(path: path, options: options, entities: entities, syncConfig: syncConfig)
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
        try self.init(path: path, entities: entities, migrations: migrations, options: options,
                      syncConfig: syncConfig, adoptingBaseline: baselineID, initialization: .immediate)
    }

    /// Choose when to open the database and apply the supplied migration history.
    /// With `.onFirstUse`, read, write, sync or waitForMigration starts one shared attempt.
    /// After the writer opens, migration and additional setup failures remain cached.
    public convenience init(
        path: String,
        entities: [any EntityProtocol.Type],
        migrations: [StoreMigration],
        options: ConnectionOptions = .init(),
        syncConfig: SyncOptions? = nil,
        adoptingBaseline baselineID: String? = nil,
        initialization: Initialization
    ) throws {
        guard !options.readonly else {
            throw ConnectionManagerError.readonlyMode("Cannot migrate in readonly mode.")
        }
        try self.init(path: path, entities: entities, options: options, syncConfig: syncConfig)
        setup.withLock { state in
            switch initialization {
            case .immediate:
                state = .started(startSetup(migrations, baselineID: baselineID, initialization: .immediate))
            case .onFirstUse:
                state = .onFirstUse(migrations, baselineID: baselineID)
            }
        }
    }

    private func startSetup(_ migrations: [StoreMigration], baselineID: String?,
                            initialization: Initialization) -> Task<Void, Error> {
        Task {
            let writer: WritableConnectionActor
            do {
                writer = try pool.openWriterForSetup()
            } catch let failure as ConnectionPool.DatabaseOpenFailure {
                if initialization == .onFirstUse {
                    // Only the task that encountered the open failure can rearm setup.
                    setup.withLock { $0 = .onFirstUse(migrations, baselineID: baselineID) }
                }
                throw failure.underlying
            }
            try await applyMigrations(migrations, adoptingBaseline: baselineID, using: writer)
        }
    }

    /// Apply committed migrations before exposing connections or starting sync tracking.
    /// A database without migration history adopts the first migration if its schema matches.
    /// Supply adoptingBaseline to adopt a later version instead; fresh databases run all steps.
    /// Use previewMigrations for a read-only preview; preview does not complete setup.
    public func migrate(migrations: [StoreMigration], adoptingBaseline baselineID: String? = nil) async throws {
        try await migrationTask(manualMigrations: migrations, baselineID: baselineID).value
    }

    private func migrationTask(manualMigrations: [StoreMigration]? = nil,
                               baselineID: String? = nil) throws -> Task<Void, Error> {
        try setup.withLock { state in
            let task: Task<Void, Error>
            switch state {
            case .started(let started):
                return started
            case .onFirstUse(let migrations, let configuredBaseline):
                task = startSetup(migrations, baselineID: configuredBaseline, initialization: .onFirstUse)
            case .manual:
                guard let manualMigrations else {
                    throw ConnectionManagerError.invalidConfiguration(
                        "Migration has not started. Pass migrations at initialization or call migrate(migrations:) first.")
                }
                let writer = try pool.openWriter(readonlyMessage: "Cannot migrate in readonly mode.")
                task = Task { try await applyMigrations(manualMigrations, adoptingBaseline: baselineID, using: writer) }
            }
            state = .started(task)
            return task
        }
    }

    private func applyMigrations(_ migrations: [StoreMigration], adoptingBaseline baselineID: String?,
                                 using writer: WritableConnectionActor) async throws {
        try await writer.run { connection in
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
        try await writer.startTracking()
        try await writer.run { connection in
            try self.performAdditionalSetup(connection: connection)
        }
        try await performAdditionalSetup()
    }

    /// Does not execute migration bodies, write history, or release the setup gate.
    public func previewMigrations(_ migrations: [StoreMigration]) async throws -> [String] {
        try await pool.openWriter().run({ connection in
            try VersionedMigrator(connection: connection, migrations: migrations).pendingMigrationIDs()
        }, transaction: false)
    }

    /// Database setup runs on the serialized writer, in a transaction after tracking starts.
    /// With sync configured, changes to registered entities and their changelog commit together;
    /// throwing rolls back this setup transaction, but not already committed migrations.
    /// Runs once per manager setup, including reopening a migrated database; make seeds idempotent.
    /// Do not retain the connection, manually finish its transaction, or call manager read/write/sync
    /// from this hook. Use the supplied connection directly; public operations still wait for setup.
    open func performAdditionalSetup(connection: SQLiteConnection) throws {
        // Default implementation is empty, subclasses can override.
    }

    /// Additional asynchronous initialization after database setup has committed.
    /// Completion is signaled only after this hook returns. Use the connection-taking overload
    /// for database writes; public manager operations would wait for this hook and deadlock.
    open func performAdditionalSetup() async throws {
        // Default implementation is empty, subclasses can override
    }

    /// Optionally wait for migrations, sync tracking and additional setup to complete.
    /// Readonly managers do not require setup.
    /// read, write and sync already wait automatically. Repeated and concurrent calls share
    /// the same result. Migration/setup failures are thrown to all current and future callers.
    /// Starts deferred setup. In manual mode, throws if migrate has not been called.
    public func waitForMigration() async throws {
        guard !options.readonly else { return }
        try await migrationTask().value
    }

    /// Execute a block with the write connection.
    /// Only one write operation can happen at a time.
    /// - Throws: `ConnectionManagerError.readonlyMode` if in readonly mode
    public func write<T: Sendable>(
        isolation: isolated (any Actor)? = #isolation,
        _ block: @Sendable (SQLiteConnection) throws -> T, transaction: Bool = true
    ) async throws -> T {
        try await waitForMigration()
        return try await pool.openWriter().run(block, transaction: transaction)
    }

    /// Execute a block with one of the read connections.
    /// Multiple read operations can happen concurrently.
    /// Reuses an idle reader, grows the pool up to its limit, or queues behind a busy reader.
    public func read<T: Sendable>(
        isolation: isolated (any Actor)? = #isolation,
        _ block: @Sendable (SQLiteConnection) throws -> T
    ) async throws -> T {
        try await waitForMigration()
        return try await pool.read(block)
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
    public func sync(progress: SyncProgressHandler? = nil) async throws -> SyncResult {
        try await waitForMigration()
        return try await pool.openWriter(readonlyMessage: "Cannot sync in readonly mode.").sync(progress: progress)
    }

    /// Get current sync state
    public var syncState: SyncState? {
        get async {
            await pool.cachedWriter?.syncState
        }
    }

    /// Forward CloudKit silent notifications. On iOS 16 this wakes the Operations driver.
    @discardableResult
    public func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let id = CKNotification(fromRemoteNotificationDictionary: userInfo)?.subscriptionID,
              id == cloudSubscriptionID, let writer = pool.cachedWriter else { return false }
        // Parse the non-Sendable UIKit dictionary on the caller's executor.
        Task { [weak writer] in _ = await writer?.handleCloudNotification(id) }
        return true
    }

    public var lastSyncError: Error? { get async { await pool.cachedWriter?.lastSyncError } }

    /// Suspend automatic syncing while continuing to track local writes.
    public func stopSync() async {
        await pool.stopSync()
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
    private var automaticSyncStopped: Bool
    private var lastSignaledSequence: Int64 = 0
    package var cloudSessionID: UUID { session }
    private var transactionWaiters: [CheckedContinuation<Void, Never>] = []

    init(connection: SQLiteConnection, entities: [any EntityProtocol.Type], syncConfig: SyncOptions?,
         automaticSyncStopped: Bool = false) throws {
        self.connection = connection; syncOptions = syncConfig
        self.automaticSyncStopped = automaticSyncStopped
        if let config = syncConfig {
            try config.validateLimits()
            syncManager = try SyncManager(connection: connection, deviceID: config.deviceId, entities: entities,
                schemaVersion: config.schemaVersion)
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

    func sync(progress: SyncProgressHandler?) async throws -> SyncResult { automaticSyncStopped = false; return try await cloudController().sync(progress: progress) }
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
    package func cloudUploadProgress(after sequence: Int64, session: UUID) async throws -> SyncProgress { try await committedWriter(session).uploadProgress(after: sequence) }
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
    func cloudUploadProgress(after sequence: Int64, session: UUID) async throws -> SyncProgress { try await owner().cloudUploadProgress(after: sequence, session: session) }
    func cloudSyncState(session: UUID) async throws -> SyncState { try await owner().cloudSyncState(session: session) }
}
