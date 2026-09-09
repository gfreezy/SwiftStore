import Foundation
import Testing
import SwiftStoreCore
import SwiftStoreConnectionQueue

@Suite("Versioned ConnectionManager setup")
struct VersionedConnectionTests {
    private func history() -> [StoreMigration] {
        let schema = SchemaSnapshot(entities: [ConnectionSyncNote.self])
        return [StoreMigration(id: "001", checksum: "initial", target: schema) { db in
            for sql in schema.creationStatements { try db.execute(sql) }
        }]
    }

    @Test("Preview can be followed by migration and normal read/write")
    func previewAndApply() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = try ConnectionManager(path: directory.appendingPathComponent("store.sqlite").path,
                                            entities: [ConnectionSyncNote.self])
        #expect(try await manager.previewMigrations(history()) == ["001"])
        try await manager.migrate(migrations: history())
        try await manager.write { try $0.insert(ConnectionSyncNote(title: "ready")) }
        #expect(try await manager.read { try $0.queryScalar("SELECT COUNT(*) FROM connection_sync_note", type: Int.self) } == 1)
        #expect(try await manager.previewMigrations(history()).isEmpty)
    }

    @Test("A local store maintains updated_at without enabling sync")
    func localUpdateTimestamp() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = try ConnectionManager(path: directory.appendingPathComponent("store.sqlite").path,
                                            entities: [ConnectionSyncNote.self])
        try await manager.migrate(migrations: history())
        try await manager.write { db in
            try db.execute("INSERT INTO connection_sync_note (id, title, created_at, updated_at) VALUES (randomblob(16), 'before', 123, 123)")
            try db.execute("UPDATE connection_sync_note SET title = 'after'")
            let timestamp = try db.queryScalar("SELECT updated_at FROM connection_sync_note", type: Double.self)
            #expect(abs((timestamp ?? 0) - Date().timeIntervalSince1970) < 5)
            try db.execute("UPDATE connection_sync_note SET title = 'imported', updated_at = 456.875")
            #expect(try db.queryScalar("SELECT updated_at FROM connection_sync_note", type: Double.self) == 456.875)
        }
    }

    @Test("Baseline configuration works for legacy, fresh and already tracked databases")
    func baselineConfiguration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for legacy in [false, true] {
            let path = directory.appendingPathComponent("store-\(legacy).sqlite").path
            if legacy {
                let db = try SQLiteConnection(path: path)
                for sql in history()[0].target.creationStatements { try db.execute(sql) }
                try db.insert(ConnectionSyncNote(title: "legacy"))
            }
            for _ in 0..<2 {
                let manager = try ConnectionManager(path: path, entities: [ConnectionSyncNote.self])
                try await manager.migrate(migrations: history(), adoptingBaseline: "001")
                let count = try await manager.read {
                    try $0.queryScalar("SELECT COUNT(*) FROM connection_sync_note", type: Int.self)
                }
                #expect(count == (legacy ? 1 : 0))
            }
        }
    }

    @Test("A failed migration propagates to waiting readers")
    func failedSetup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = try ConnectionManager(path: directory.appendingPathComponent("store.sqlite").path,
                                            entities: [ConnectionSyncNote.self])
        let bad = StoreMigration(id: "bad", checksum: "bad", target: history()[0].target) { db in
            try db.execute("INVALID SQL")
        }
        await #expect(throws: (any Error).self) { try await manager.migrate(migrations: [bad]) }
        await #expect(throws: (any Error).self) { try await manager.read { try $0.tableExists("connection_sync_note") } }
    }
}
