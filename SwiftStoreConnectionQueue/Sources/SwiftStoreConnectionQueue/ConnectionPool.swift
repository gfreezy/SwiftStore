import Foundation
import SwiftStoreCore

final class ConnectionPool: Sendable {
    private enum WriterState {
        case unopened(syncStopped: Bool)
        case open(WritableConnectionActor)
    }

    private struct ReaderSlot {
        let actor: ReadConnection
        var pendingReads = 0
    }

    private struct State {
        var writer = WriterState.unopened(syncStopped: false)
        var readers: [ReaderSlot] = []
    }

    private let state = Mutex(State())
    private let path: String
    private let options: ConnectionOptions
    private let entities: [any EntityProtocol.Type]
    private let syncConfig: SyncOptions?

    init(path: String, options: ConnectionOptions, entities: [any EntityProtocol.Type], syncConfig: SyncOptions?) {
        self.path = path
        self.options = options
        self.entities = entities
        self.syncConfig = syncConfig
    }

    var cachedWriter: WritableConnectionActor? {
        state.withLock { state in
            if case .open(let writer) = state.writer { return writer }
            return nil
        }
    }

    func openWriter(readonlyMessage: String = "Cannot write in readonly mode.") throws -> WritableConnectionActor {
        guard !options.readonly else {
            throw ConnectionManagerError.readonlyMode(readonlyMessage)
        }

        return try state.withLock { state in
            switch state.writer {
            case .open(let writer):
                return writer
            case .unopened(let syncStopped):
                let directoryPath = (path as NSString).deletingLastPathComponent
                if !directoryPath.isEmpty {
                    try FileManager.default.createDirectory(atPath: directoryPath, withIntermediateDirectories: true)
                }

                var writeOptions = options.toSQLiteOptions(walMode: true)
                // Sync acknowledgement durability must include the business write and its log.
                if syncConfig != nil { writeOptions.synchronous = 2 }
                let connection = try SQLiteConnection(path: path, options: writeOptions)
                let writer = try WritableConnectionActor(connection: connection, entities: entities,
                    syncConfig: syncConfig, automaticSyncStopped: syncStopped)
                state.writer = .open(writer)
                return writer
            }
        }
    }

    func read<T: Sendable>(
        isolation: isolated (any Actor)? = #isolation,
        _ block: @Sendable (SQLiteConnection) throws -> T
    ) async throws -> T {
        let (index, reader) = state.withLock { state -> (Int, ReadConnection) in
            let index: Int
            let leastBusy = state.readers.indices.min { state.readers[$0].pendingReads < state.readers[$1].pendingReads }
            if let leastBusy, state.readers[leastBusy].pendingReads == 0 || state.readers.count == options.maxReadConnections {
                index = leastBusy
            } else {
                let reader = ReadConnection(path: path, options: options.toSQLiteOptions(walMode: !options.readonly))
                index = state.readers.count
                state.readers.append(ReaderSlot(actor: reader))
            }
            state.readers[index].pendingReads += 1
            return (index, state.readers[index].actor)
        }
        defer { state.withLock { $0.readers[index].pendingReads -= 1 } }
        return try await reader.run(block)
    }

    func stopSync() async {
        let writer = state.withLock { state -> WritableConnectionActor? in
            if case .open(let writer) = state.writer { return writer }
            state.writer = .unopened(syncStopped: true)
            return nil
        }
        await writer?.stopSync()
    }
}

private actor ReadConnection {
    private let path: String
    private let options: SQLiteConnection.Options
    private var connection: SQLiteConnection?

    init(path: String, options: SQLiteConnection.Options) {
        self.path = path
        self.options = options
    }

    func run<T>(_ block: @Sendable (SQLiteConnection) throws -> T) throws -> T {
        if let connection { return try block(connection) }
        let opened = try SQLiteConnection(path: path, options: options)
        connection = opened
        return try block(opened)
    }
}
