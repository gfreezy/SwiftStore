import Foundation

/// Processes the file-based change queue and inserts into change_log table
public final class ChangeQueueProcessor {
    private let queue: ChangeQueue
    private let dbPath: String
    private let deviceId: String
    private let connection: Mutex<SQLiteConnection?> = Mutex(nil)
    private let processingQueue = DispatchQueue(label: "com.swiftstore.change-processor")
    private let timer: Mutex<DispatchSourceTimer?> = Mutex(nil)
    private let isRunning: Mutex<Bool> = Mutex(false)

    // Reference to registered entities for encoding
    private let registeredEntities: [String: any EntityProtocol.Type]

    /// Initialize processor
    /// - Parameters:
    ///   - queue: The change queue to process
    ///   - dbPath: Database path for creating separate connection
    ///   - deviceId: Device ID for change records
    ///   - registeredEntities: Map of table names to entity types
    public init(
        queue: ChangeQueue,
        dbPath: String,
        deviceId: String,
        registeredEntities: [String: any EntityProtocol.Type]
    ) {
        self.queue = queue
        self.dbPath = dbPath
        self.deviceId = deviceId
        self.registeredEntities = registeredEntities
    }

    deinit {
        stop()
    }

    /// Start processing queue periodically
    public func start() {
        guard !isRunning.value() else { return }
        isRunning.withLock { $0 = true }

        // Create separate connection for writing
        do {
            let connection = try SQLiteConnection(path: dbPath)
            self.connection.withLock { $0 = connection }
        } catch {
            print("SwiftStore: Failed to create processor connection: \(error)")
            return
        }

        // Start periodic processing
        let timer = DispatchSource.makeTimerSource(queue: processingQueue)
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1) // Every 100ms
        timer.setEventHandler { [weak self] in
            self?.processQueue()
        }
        timer.resume()
        self.timer.withLock { $0 = timer }
    }

    /// Stop processing
    public func stop() {
        guard isRunning.value() else { return }
        isRunning.withLock { $0 = false }

        timer.withLock { 
            $0?.cancel() 
            $0 = nil
        }

        // Final flush
        processQueue()

        connection.withLock { $0 = nil }
    }

    /// Flush all pending changes immediately
    public func flush() {
        processingQueue.sync {
            processQueue()
        }
    }

    /// Process all pending changes in the queue
    private func processQueue() {
        guard let connection = connection.value() else { return }

        do {
            let changes = try queue.readAll()
            guard !changes.isEmpty else { return }

            try connection.transaction {
                for change in changes {
                    try processChange(change, connection: connection)
                }
            }

            try queue.truncate()
        } catch {
            print("SwiftStore: Failed to process change queue: \(error)")
        }
    }

    /// Process a single change
    private func processChange(_ change: PendingChange, connection: SQLiteConnection) throws {
        // Get entity type for encoding
        guard let entityType = registeredEntities[change.table] else {
            // For pending_deletes, extract table info from the row
            if change.table == Store.pendingDeletesTable {
                // This is handled specially - already a delete operation
                return
            }
            return
        }

        var payload: String? = nil
        var entityId: UUIDV4

        switch change.op {
        case .insert, .update:
            guard let rowId = change.rowId else { return }

            // Fetch the row data
            let stmt = try connection.prepareRowById(change.table, rowId: rowId)
            guard try stmt.step() else { return }

            // Get entity ID
            guard let idData = stmt.columnData(0),
                  let id = UUIDV4(data: idData) else { return }
            entityId = id

            // Encode row to JSON
            payload = try encodeRowToJSON(stmt: stmt, entityType: entityType)

        case .delete:
            guard let entityIdStr = change.entityId,
                  let id = UUIDV4(uuidString: entityIdStr) else { return }
            entityId = id
        }

        // Insert into change_log
        let now = Date()
        let changeId = UUIDV4()

        let sql: SQL = """
            INSERT INTO \(ChangeLog.self) (\(\ChangeLog.id), \(\ChangeLog.entityType), \(\ChangeLog.entityId), \(\ChangeLog.operation), \(\ChangeLog.payload), \(\ChangeLog.deviceId), \(\ChangeLog.logicalClock), \(\ChangeLog.createdAt), \(\ChangeLog.updatedAt))
            VALUES (\(changeId.data), \(change.table), \(entityId.data), \(change.op.rawValue), \(payload), \(deviceId), \(change.clock), \(now.timeIntervalSince1970), \(now.timeIntervalSince1970))
            """

        try connection.execute(sql)
    }

    /// Encode row data to JSON
    private func encodeRowToJSON(stmt: SQLiteStatement, entityType: any EntityProtocol.Type) throws -> String {
        var dict: [String: Any] = [:]

        for (index, column) in entityType.columns.enumerated() {
            let propertyName = column.name.snakeCaseToCamelCase()

            if stmt.isNull(Int32(index)) {
                continue
            }

            switch column.type {
            case .text:
                if let value = stmt.columnString(Int32(index)) {
                    dict[propertyName] = value
                }
            case .integer:
                dict[propertyName] = stmt.columnInt64(Int32(index))
            case .real:
                dict[propertyName] = stmt.columnDouble(Int32(index))
            case .blob:
                if let data = stmt.columnData(Int32(index)) {
                    // For UUIDV4, convert to string representation
                    if column.name == "id" || column.name.hasSuffix("_id") {
                        if let uuid = UUIDV4(data: data) {
                            dict[propertyName] = uuid.uuidString
                        }
                    } else {
                        dict[propertyName] = data.base64EncodedString()
                    }
                }
            }
        }

        let jsonData = try JSONSerialization.data(withJSONObject: dict)
        return String(data: jsonData, encoding: .utf8) ?? "{}"
    }
}
