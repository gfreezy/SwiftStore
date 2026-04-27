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

    @Test("pending push round-trips")
    func pendingPushRoundTrip() async throws {
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

        let map = [change.id.description: change]
        try await store.savePendingPush(map)

        let loaded = try await store.loadPendingPush()
        #expect(loaded.count == 1)
        #expect(loaded[change.id.description]?.id == change.id)
    }

    @Test("setup flags default empty when no file")
    func setupFlagsDefault() async throws {
        let dir = makeTempDir()
        let store = try FileCloudKitSyncStateStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let flags = try await store.loadSetupFlags()
        #expect(flags.didCreateZone == false)
        #expect(flags.didSubscribe == false)
    }

    @Test("setup flags round-trip")
    func setupFlagsRoundTrip() async throws {
        let dir = makeTempDir()
        let store = try FileCloudKitSyncStateStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        try await store.saveSetupFlags(CloudKitSetupFlags(didCreateZone: true, didSubscribe: true))
        let loaded = try await store.loadSetupFlags()
        #expect(loaded.didCreateZone == true)
        #expect(loaded.didSubscribe == true)
    }

    @Test("corrupt pending-push file falls back to empty")
    func corruptFileFallback() async throws {
        let dir = makeTempDir()
        let store = try FileCloudKitSyncStateStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Write a broken blob where the plist is expected.
        let url = dir.appendingPathComponent("pending-push.plist")
        try Data([0x00, 0x01, 0x02, 0xFF]).write(to: url)

        let loaded = try await store.loadPendingPush()
        #expect(loaded.isEmpty)
    }

    @Test("corrupt setup-flags file falls back to defaults")
    func corruptSetupFlagsFallback() async throws {
        let dir = makeTempDir()
        let store = try FileCloudKitSyncStateStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("setup-flags.plist")
        try Data([0xDE, 0xAD]).write(to: url)

        let loaded = try await store.loadSetupFlags()
        #expect(loaded.didCreateZone == false)
        #expect(loaded.didSubscribe == false)
    }

    @Test("engine state returns nil when absent")
    func engineStateAbsent() async throws {
        let dir = makeTempDir()
        let store = try FileCloudKitSyncStateStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let loaded = try await store.loadEngineState()
        #expect(loaded == nil)
    }

    @Test("engine state returns nil when corrupt")
    func engineStateCorrupt() async throws {
        let dir = makeTempDir()
        let store = try FileCloudKitSyncStateStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("engine-state.plist")
        try Data([0xFF, 0xFE, 0xFD]).write(to: url)

        let loaded = try await store.loadEngineState()
        #expect(loaded == nil)
    }
}
