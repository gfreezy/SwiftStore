import Dispatch
import Foundation
import Testing
import SwiftStoreCore
import SwiftStoreConnectionQueue

@Suite("On-demand connection pool")
struct ConnectionPoolTests {
    @Test("A readonly reader retries opening and caches the successful connection")
    func retryReaderOpen() async throws {
        enum ReadFailure: Error { case intentional }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("store.sqlite").path
        let manager = try ConnectionManager(path: path, entities: [], options: .init(readonly: true))
        await #expect(throws: StoreError.self) { try await manager.read { _ in } }
        #expect(!FileManager.default.fileExists(atPath: directory.path))

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try SQLiteConnection(path: path).execute("CREATE TABLE items (value INTEGER)")
        #expect(try await manager.read { try $0.tableExists("items") })
        let reader = try await manager.read { ObjectIdentifier($0) }
        await #expect(throws: ReadFailure.self) { try await manager.read { _ in throw ReadFailure.intentional } }
        #expect(try await manager.read { ObjectIdentifier($0) } == reader)
    }

    @Test("The pool opens another reader when the first is busy, then reuses idle readers")
    func growWhenBusy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("store.sqlite").path
        try SQLiteConnection(path: path).execute("CREATE TABLE items (value INTEGER)")
        let manager = try ConnectionManager(path: path, entities: [], options: .init(readonly: true, maxReadConnections: 2))
        let initialReader = try await manager.read { ObjectIdentifier($0) }

        let (started, startSignal) = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let busyRead = Task {
            defer { startSignal.finish() }
            return try await manager.read { connection in
                startSignal.yield(())
                #expect(release.wait(timeout: .now() + .seconds(5)) == .success)
                return ObjectIdentifier(connection)
            }
        }
        var events = started.makeAsyncIterator()
        #expect(await events.next() != nil)
        let secondReader: ObjectIdentifier
        do {
            defer { release.signal() }
            secondReader = try await manager.read { ObjectIdentifier($0) }
            #expect(secondReader != initialReader)
            #expect(try await manager.read { ObjectIdentifier($0) } == secondReader)
        }

        #expect(try await busyRead.value == initialReader)
        #expect(try await manager.read { ObjectIdentifier($0) } == initialReader)
    }

    @Test("Concurrent reads respect pool capacity and never share a connection simultaneously",
          arguments: [1, 2, 4])
    func concurrentReadCapacity(limit: Int) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("store.sqlite").path
        try SQLiteConnection(path: path).execute("CREATE TABLE items (value INTEGER)")
        let manager = try ConnectionManager(path: path, entities: [], options: .init(readonly: true, maxReadConnections: limit))
        let activeReaders = Mutex(Set<ObjectIdentifier>())

        let connections = try await withThrowingTaskGroup(of: ObjectIdentifier.self) { group in
            for _ in 0..<48 {
                group.addTask {
                    try await manager.read { connection in
                        let id = ObjectIdentifier(connection)
                        let exclusive = activeReaders.withLock { $0.insert(id).inserted }
                        try #require(exclusive)
                        defer { activeReaders.withLock { _ = $0.remove(id) } }
                        Thread.sleep(forTimeInterval: 0.002)
                        let hasTable = try connection.tableExists("items")
                        #expect(hasTable)
                        return id
                    }
                }
            }
            var observed: Set<ObjectIdentifier> = []
            for try await id in group { observed.insert(id) }
            return observed
        }

        #expect(connections.count <= limit)
    }

    @Test("Nonpositive pool sizes are rejected", arguments: [0, -1])
    func invalidReaderLimit(limit: Int) {
        #expect(throws: ConnectionManagerError.self) {
            _ = try ConnectionManager(path: ":memory:", entities: [], options: .init(maxReadConnections: limit))
        }
    }
}
