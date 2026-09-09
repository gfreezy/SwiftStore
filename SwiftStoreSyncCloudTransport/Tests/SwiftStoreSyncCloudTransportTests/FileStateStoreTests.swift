import Testing
import Foundation
@testable import SwiftStoreSyncCloudTransport
import SwiftStoreSync
import SwiftStoreCore
import SwiftStoreChangeTracker

@Suite("FileCloudKitSyncStateStore")
struct FileStateStoreTests {

    private func makeTempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftstore-cloud-state-tests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("Journal preserves pending uploads and zone setup across restart")
    func journalRoundTrip() async throws {
        let dir = makeTempDir()
        let store = try FileCloudKitSyncStateStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let change = SyncChange(
            id: UUIDV7(),
            entityType: "user",
            syncKey: Data([0x01]),
            operation: .insert,
            payload: "{}",
            deviceId: UUIDV7(),
            logicalClock: 1,
            schemaVersion: 1,
            createdAt: Date()
        )

        var journal = CloudKitSyncJournal()
        journal.pendingPush[change.id.description] = change
        journal.didCreateZone = true
        try await store.saveJournal(journal)

        let reopened = try FileCloudKitSyncStateStore(directory: dir)
        let loaded = try #require(try await reopened.loadJournal())
        #expect(loaded.pendingPush.count == 1)
        #expect(loaded.pendingPush[change.id.description]?.id == change.id)
        #expect(loaded.didCreateZone)
    }

    @Test("Corrupt journal reports an error")
    func corruptJournal() async throws {
        let dir = makeTempDir()
        let store = try FileCloudKitSyncStateStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Write a broken blob where the plist is expected.
        let url = dir.appendingPathComponent("journal.plist")
        try Data([0x00, 0x01, 0x02, 0xFF]).write(to: url)

        await #expect(throws: CloudKitTransportError.self) { try await store.loadJournal() }
    }

    @Test("Journal returns nil when absent")
    func journalAbsent() async throws {
        let dir = makeTempDir()
        let store = try FileCloudKitSyncStateStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let loaded = try await store.loadJournal()
        #expect(loaded == nil)
    }


}
