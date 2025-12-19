import Foundation

/// Main store class for database operations
public final class Store {
    public let connection: SQLiteConnection
    private let migrationManager: MigrationManager
    private let dbPath: String

    // Sync manager
    private var syncManager: SyncManager?

    // Registered entity types
    private var registeredEntities: [String: any EntityProtocol.Type] = [:]
    private var relationEntities: Set<String> = []

    // System table names (prefixed with __swiftstore_ to indicate internal tables)
    internal static let changeLogTable = SyncManager.changeLogTable
    internal static let pendingDeletesTable = SyncManager.pendingDeletesTable

    /// Initialize store with database path
    public init(path: String) throws {
        self.dbPath = path
        self.connection = try SQLiteConnection(path: path)
        self.migrationManager = MigrationManager(connection: connection)
    }

    // MARK: - Schema Management

    /// Register an entity type
    public func register<E: EntityProtocol>(_ type: E.Type) throws {
        registeredEntities[E.tableName] = type

        // Check if it's a relation entity
        if type is any RelationMarker.Type {
            relationEntities.insert(E.tableName)
        }
    }

    /// Run migrations for all registered entities
    public func migrate() throws {
        // Create change_log table first if sync might be enabled
        try migrationManager.createTable(for: ChangeLog.self)

        // Create system tables (pending_deletes, etc.)
        try migrationManager.createSystemTables()

        // Create tables for all registered entities
        // Sort to ensure non-relation entities are created first
        let sortedEntities = registeredEntities.sorted { a, b in
            let aIsRelation = relationEntities.contains(a.key)
            let bIsRelation = relationEntities.contains(b.key)
            if aIsRelation != bIsRelation {
                return !aIsRelation
            }
            return a.key < b.key
        }

        for (_, entityType) in sortedEntities {
            try migrationManager.createTableForAnyType(entityType)
        }
    }

    // MARK: - Query Builder

    /// Create a query builder for fetching entities
    public func fetch<E: EntityProtocol>(_ type: E.Type) -> Query<E> {
        Query(E.self)
    }

    // MARK: - Sync Support

    /// Enable sync with device ID
    public func enableSync(deviceId: String) throws {
        if syncManager == nil {
            syncManager = SyncManager(connection: connection, dbPath: dbPath)
        }
        syncManager?.registerEntities(registeredEntities, relations: relationEntities)
        try syncManager?.enable(deviceId: deviceId)
    }

    /// Disable sync
    public func disableSync() {
        syncManager?.disable()
    }

    /// Flush pending changes to change_log
    public func flushChanges() {
        syncManager?.flushChanges()
    }

    /// Get current logical clock value
    public func currentClock() -> Int64 {
        return syncManager?.currentClock() ?? 0
    }

    /// Get changes since a given clock value
    public func changesSince(clock: Int64) throws -> [ChangeLog] {
        guard let syncManager = syncManager else {
            throw StoreError.syncNotEnabled
        }
        return try syncManager.changesSince(clock: clock)
    }

    /// Apply remote changes
    public func applyChanges(_ changes: [ChangeLog]) throws {
        guard let syncManager = syncManager else {
            throw StoreError.syncNotEnabled
        }
        try syncManager.applyChanges(changes)
    }

    /// Prune old change logs
    public func pruneChanges(before clock: Int64) throws {
        guard let syncManager = syncManager else {
            throw StoreError.syncNotEnabled
        }
        try syncManager.pruneChanges(before: clock)
    }

    // MARK: - Relation Helpers

    /// Check if an entity type is a relation
    public func isRelationEntity(_ tableName: String) -> Bool {
        relationEntities.contains(tableName)
    }

    // MARK: - Migration Dry Run

    /// Generate migration plan for a single entity type without executing (dry run)
    public func planMigration<E: EntityProtocol>(for type: E.Type) throws -> MigrationPlan {
        try migrationManager.planMigration(for: type)
    }

    /// Generate migration plan for all registered entities without executing (dry run)
    public func planMigrations() throws -> MigrationPlan {
        let sortedEntities = registeredEntities.sorted { a, b in
            let aIsRelation = relationEntities.contains(a.key)
            let bIsRelation = relationEntities.contains(b.key)
            if aIsRelation != bIsRelation {
                return !aIsRelation
            }
            return a.key < b.key
        }

        let types = sortedEntities.map { $0.value }
        return try migrationManager.planMigrations(for: types)
    }

    /// Generate CREATE TABLE SQL for an entity type
    public func generateCreateTableSQL<E: EntityProtocol>(for type: E.Type) -> String {
        migrationManager.generateCreateTableSQL(for: type)
    }
}
