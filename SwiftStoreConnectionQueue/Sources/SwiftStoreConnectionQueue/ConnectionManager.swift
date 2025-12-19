import Foundation
import OSLog
import SwiftStoreCore

/// Manages database connections with a single writer and multiple readers.
/// This ensures thread-safety and optimal performance using SQLite's WAL mode.
/// Thread safety is handled by the internal ConnectionActor instances.
public final class ConnectionManager: @unchecked Sendable {
    private let path: String
    private let options: SQLiteConnection.Options
    private let maxReadConnections: Int
    
    internal let writerConnection: SQLiteConnection
    private let writer: ConnectionActor
    private let readers: [ReaderEntry]
    
    private struct ReaderEntry: Sendable {
        let actor: ConnectionActor
        let isInUse: Mutex<Bool>
    }
    
    /// Initialize with database path and options
    public init(path: String, options: SQLiteConnection.Options = .init(), maxReadConnections: Int = 4) throws {
        self.path = path
        self.options = options
        self.maxReadConnections = maxReadConnections
        
        // Ensure WAL mode is enabled for concurrent read/write
        var writeOptions = options
        writeOptions.walMode = true
        
        // Create writer connection
        let writerConn = try SQLiteConnection(path: path, options: writeOptions)
        self.writerConnection = writerConn
        self.writer = ConnectionActor(connection: writerConn)
        
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
}

/// Internal actor to serialize access to a single SQLite connection
actor ConnectionActor {
    private let connection: SQLiteConnection
    
    init(connection: SQLiteConnection) {
        self.connection = connection
    }
    
    func run<T>(_ block: @Sendable (SQLiteConnection) throws -> T) throws -> T {
        try block(connection)
    }
}

