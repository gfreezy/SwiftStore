import Foundation

/// Pending change record written to file queue
struct PendingChange: Codable, Sendable {
    enum Operation: String, Codable, Sendable {
        case insert
        case update
        case delete
    }

    let op: Operation
    let table: String
    let rowId: Int64?      // For insert/update
    let entityId: String?  // For delete (UUID string)
    let clock: Int64
    let ts: Int64          // Timestamp in milliseconds

    init(op: Operation, table: String, rowId: Int64? = nil, entityId: String? = nil, clock: Int64) {
        self.op = op
        self.table = table
        self.rowId = rowId
        self.entityId = entityId
        self.clock = clock
        self.ts = Int64(Date().timeIntervalSince1970 * 1000)
    }
}

/// File-based change queue for sqlite3_update_hook
/// Writes changes to a file that can be processed by a background thread
public final class ChangeQueue {
    private let filePath: String
    private let fileHandle: FileHandle
    private let encoder = JSONEncoder()

    /// Initialize with database path
    /// Creates queue file at {dbPath}.changes
    public init(dbPath: String) throws {
        self.filePath = dbPath + ".changes"

        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: filePath) {
            FileManager.default.createFile(atPath: filePath, contents: nil)
        }

        // Open for appending
        guard let handle = FileHandle(forUpdatingAtPath: filePath) else {
            throw StoreError.queryFailed("Failed to open change queue file: \(filePath)")
        }

        self.fileHandle = handle
        try fileHandle.seekToEnd()
    }

    deinit {
        try? fileHandle.close()
    }

    /// Append a change to the queue
    func append(_ change: PendingChange) {
        do {
            let data = try encoder.encode(change)
            fileHandle.write(data)
            fileHandle.write(Data([0x0A])) // newline
        } catch {
            print("SwiftStore: Failed to write change to queue: \(error)")
        }
    }

    /// Read all pending changes from the queue
    func readAll() throws -> [PendingChange] {
        try fileHandle.seek(toOffset: 0)
        guard let data = try fileHandle.readToEnd(), !data.isEmpty else {
            return []
        }

        let decoder = JSONDecoder()
        var changes: [PendingChange] = []

        // Parse JSON lines
        let lines = data.split(separator: 0x0A) // newline
        for line in lines {
            if line.isEmpty { continue }
            if let change = try? decoder.decode(PendingChange.self, from: Data(line)) {
                changes.append(change)
            }
        }

        return changes
    }

    /// Clear all processed changes
    func truncate() throws {
        try fileHandle.seek(toOffset: 0)
        try fileHandle.truncate(atOffset: 0)
    }

    /// Get the file path
    var path: String { filePath }

    /// Check if queue has pending changes
    var hasPendingChanges: Bool {
        do {
            let currentOffset = try fileHandle.offset()
            try fileHandle.seek(toOffset: 0)
            let data = try fileHandle.readToEnd()
            try fileHandle.seek(toOffset: currentOffset)
            return (data?.count ?? 0) > 0
        } catch {
            return false
        }
    }
}
