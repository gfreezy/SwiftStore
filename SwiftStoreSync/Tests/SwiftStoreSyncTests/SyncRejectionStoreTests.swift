import Foundation
import Testing
import SwiftStoreCore
@testable import SwiftStoreSync

@Suite("Shared rejected upload reconciliation")
struct SyncRejectionStoreTests {
    private func change(_ key: UInt8) -> SyncChange {
        SyncChange(id: UUIDV7(), entityType: "note", syncKey: Data([key]), operation: .delete,
            payload: nil, deviceId: UUIDV7(), logicalClock: 1, createdAt: Date())
    }

    @Test("Carried versions wait for pull; absent versions require lookup")
    func fallback() {
        let local = change(1), server = change(1), other = change(2)
        var store = SyncRejectionStore()
        store.record(local, serverVersion: server)
        store.record(other)
        #expect(store.blocks(server))
        store.finishPull()
        #expect(!store.blocks(server))
        #expect(store.missing.map(\.changeID) == [other.id])
        #expect(store.blocks(other))
    }

    @Test("Only verified same-key downloads resolve a rejection, without comparing timestamps")
    func verifiedPull() {
        let local = change(1), carried = change(1), pulled = change(1), unrelated = change(2)
        var store = SyncRejectionStore()
        store.record(local, serverVersion: carried)
        store.receive(unrelated, satisfying: [local.id])
        #expect(store.blocks(carried))
        store.receive(pulled, satisfying: [local.id])
        store.finishPull()
        #expect(store.entries.first?.serverVersion?.id == pulled.id)
    }

    @Test("Persisted rejection survives receipt-only ACK and a later rejection survives old apply ACK")
    func durableAcknowledgement() throws {
        let first = change(1), second = change(1), remote = change(1)
        var store = SyncRejectionStore()
        store.record(first, serverVersion: remote)
        store.finishPull()
        let snapshot = store.entries
        store = try JSONDecoder().decode(SyncRejectionStore.self, from: JSONEncoder().encode(store))
        store.acknowledge(applied: [], rejectedKeys: snapshot)
        #expect(store.entries.count == 1)
        store.record(second, serverVersion: remote)
        store.finishPull()
        store.acknowledge(applied: [remote], rejectedKeys: snapshot)
        #expect(store.entries.map(\.changeID) == [second.id])
    }
}
