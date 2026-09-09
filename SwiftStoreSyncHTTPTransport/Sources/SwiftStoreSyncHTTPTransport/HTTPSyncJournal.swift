import Foundation

struct HTTPSyncJournal: Codable, Sendable {
    var formatVersion = 3
    var endpoint: String?
    var namespace: String?
    var deviceID: UUIDV7?
    var serverID: String?
    var cursor: Int64 = 0
    var receivedSequences: [String: Int64] = [:]
    var pending: [SyncChange] = []
    var inbox: [SyncChange] = []
    var pushed: [UUIDV7] = []
    var conflicts: [SyncChange] = []

    var rejections = SyncRejectionStore()
    var rejectionSequences: [UUIDV7: Int64] = [:]
    /// Historical pages must not temporarily overwrite this round's accepted edits.
    var awaitingPullKeys: Set<String> = []

    mutating func receive(_ record: HTTPSyncRecord) throws {
        let sequence = record.sequence!
        let previous = receivedSequences[record.key] ?? 0
        let satisfied = Set(rejections.entries.filter {
            HTTPSyncRecord.key(for: $0.change) == record.key
                && sequence >= (rejectionSequences[$0.changeID] ?? Int64.max)
        }.map(\.changeID))
        // Equal-sequence redelivery is necessary after a new local rejection.
        guard sequence > previous || (sequence == previous && !satisfied.isEmpty) else { return }
        let change = try record.decodeChange()
        inbox.removeAll { SyncRejectionStore.sameKey($0, change) }
        inbox.append(change)
        receivedSequences[record.key] = sequence
        rejections.receive(change, satisfying: satisfied)
    }

    var result: SyncCycleResult {
        .init(pulled: inbox.filter { !rejections.blocks($0) && !awaitingPullKeys.contains(HTTPSyncRecord.key(for: $0)) }, pushed: pushed, conflicts: conflicts,
              pendingChanges: pending, rejectedKeys: rejections.entries)
    }

    mutating func acknowledge(_ result: SyncCycleResult) {
        rejections.acknowledge(applied: result.pulled, rejectedKeys: result.rejectedKeys)
        let remaining = Set(rejections.entries.map(\.changeID))
        rejectionSequences = rejectionSequences.filter { remaining.contains($0.key) }
        let pulled = Set(result.pulled.map(\.id))
        let pushed = Set(result.pushed)
        let conflicts = Set(result.conflicts.map(\.id))
        let retained = Set(rejections.entries.compactMap { $0.serverVersion?.id })
        inbox.removeAll { pulled.contains($0.id) && !retained.contains($0.id) }
        self.pushed.removeAll { pushed.contains($0) }
        self.conflicts.removeAll { conflicts.contains($0.id) }
    }
}

final class HTTPSyncSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private var finished = false
    var stream: AsyncStream<Void> { lock.withLock { pair.stream } }
    func start() {
        lock.withLock {
            if finished { pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1)); finished = false }
        }
    }
    func yield() { lock.withLock { _ = pair.continuation.yield(()) } }
    func finish() { lock.withLock { finished = true; pair.continuation.finish() } }
}
