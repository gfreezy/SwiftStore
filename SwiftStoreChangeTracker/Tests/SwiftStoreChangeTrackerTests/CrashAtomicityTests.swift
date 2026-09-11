#if os(macOS) && compiler(>=6.3)
import Darwin
import Foundation
import Testing
import SwiftStoreCore
@testable import SwiftStoreChangeTracker

private final class ExitAfterLog: SQLiteUpdateHookHandler {
    let tracker: ChangeTracker
    init(_ tracker: ChangeTracker) { self.tracker = tracker }
    func tracksTable(_ table: String) -> Bool { tracker.tracksTable(table) }
    func handleUpdate(_ info: SQLiteUpdateInfo) {}
    func handleUpdates(_ updates: [SQLiteUpdateInfo]) throws {
        try tracker.handleUpdates(updates)
        _exit(73) // No deinit, rollback, or normal process shutdown.
    }
}

private func crashWriter(path: String, point: Int) throws {
    var options = SQLiteConnection.Options(); options.synchronous = 2
    let db = try SQLiteConnection(path: path, options: options)
    try migrateTestEntities([TestEntity.self], on: db)
    let tracker = try ChangeTracker(connection: db, deviceId: UUIDV7(), registeredEntities: [TestEntity.self])
    try tracker.start()
    let exitHandler = ExitAfterLog(tracker)
    if point == 1 { try db.setPreUpdateHook(exitHandler) }
    if point == 2 { try db.execute("BEGIN") }
    if point == 0 {
        let statement = try db.prepare("INSERT INTO test_entity(id,name,value) VALUES(?, 'unfinished', 1) RETURNING name")
        try statement.bind(1, UUIDV7().data)
        _ = try statement.step()
        _exit(73)
    }
    try db.insert(TestEntity(name: "committed", value: 1))
    withExtendedLifetime(exitHandler) { _exit(73) }
}

@Suite("Process crash atomicity")
struct CrashAtomicityTests {
    @Test("Crash before statement completion, after log append, before outer commit, or after commit", arguments: [0, 1, 2, 3])
    func crash(point: Int) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path: String = directory.appendingPathComponent("crash.sqlite").path
        await #expect(processExitsWith: .exitCode(73)) { [path = path as String, point] in
            try crashWriter(path: path, point: point)
        }
        let reopened = try SQLiteConnection(path: path)
        let expected = point == 3 ? 1 : 0
        #expect(try TestEntity.count(reopened) == expected)
        #expect(try ChangeTrackerReader(connection: reopened).count(after: 0) == expected)
        #expect(try reopened.queryScalar("PRAGMA integrity_check", type: String.self) == "ok")
    }
}
#endif
