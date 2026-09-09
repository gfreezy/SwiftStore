import Foundation
import SwiftStoreCore

/// A completed upload whose local version did not remain the committed version.
public struct RejectedChange: Codable, Sendable {
    public let change: SyncChange
    /// Optional upload-response content, used only if normal pull does not resolve the key.
    public fileprivate(set) var serverVersion: SyncChange?
    public fileprivate(set) var isResolved = false

    public var changeID: UUIDV7 { change.id }

    public init(change: SyncChange, serverVersion: SyncChange? = nil) {
        self.change = change
        self.serverVersion = serverVersion
    }
}

/// Shared durable reconciliation for both transports. Adapters verify version
/// ordering before supplying pull/lookup results; this type never chooses a winner.
public struct SyncRejectionStore: Codable, Sendable {
    public private(set) var entries: [RejectedChange] = []

    public init() {}

    public mutating func record(_ change: SyncChange, serverVersion: SyncChange? = nil) {
        guard !entries.contains(where: { $0.changeID == change.id }) else { return }
        entries.append(RejectedChange(change: change, serverVersion: serverVersion))
    }

    public mutating func remove(changeID: UUIDV7) {
        entries.removeAll { $0.changeID == changeID }
    }

    /// Only IDs whose upload decision is covered by this version may be resolved.
    public mutating func receive(_ version: SyncChange, satisfying ids: Set<UUIDV7>) {
        for index in entries.indices where ids.contains(entries[index].changeID)
            && Self.sameKey(entries[index].change, version) {
            entries[index].serverVersion = version
            entries[index].isResolved = true
        }
    }

    /// Called after normal pull: use content carried by the upload response.
    /// Entries without content remain unresolved until an explicit lookup succeeds.
    public mutating func finishPull() {
        for index in entries.indices where entries[index].serverVersion != nil {
            entries[index].isResolved = true
        }
    }

    public var missing: [RejectedChange] { entries.filter { !$0.isResolved && $0.serverVersion == nil } }

    public func blocks(_ version: SyncChange) -> Bool {
        entries.contains { !$0.isResolved && Self.sameKey($0.change, version) }
    }

    /// Receipt acknowledgement alone cannot discard an unapplied correction.
    public mutating func acknowledge(applied: [SyncChange], rejectedKeys: [RejectedChange]) {
        let ids = Set(applied.map(\.id))
        let acknowledged = Set(rejectedKeys.map(\.changeID))
        entries.removeAll { acknowledged.contains($0.changeID) && $0.isResolved
            && $0.serverVersion.map { ids.contains($0.id) } == true }
    }

    public static func sameKey(_ lhs: SyncChange, _ rhs: SyncChange) -> Bool {
        lhs.entityType == rhs.entityType && lhs.syncKey == rhs.syncKey
    }
}
