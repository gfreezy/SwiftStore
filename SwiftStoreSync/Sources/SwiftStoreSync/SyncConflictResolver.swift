import Foundation

/// Backend-side conflict decision. Callers pass the already committed version
/// first; equality must preserve it. SyncManager does not invoke this interface.
public protocol SyncConflictResolver: Sendable {
    func shouldReplace(_ committed: SyncChange, with incoming: SyncChange) -> Bool
}

/// The common CloudKit / HTTP protocol policy. Operation, content, schema,
/// device ID and logical clock do not break ties. HTTP servers implement the
/// same strict comparison on the envelope's integer Unix-millisecond updatedAt.
public struct TimestampConflictResolver: SyncConflictResolver {
    public init() {}

    public func shouldReplace(_ committed: SyncChange, with incoming: SyncChange) -> Bool {
        let current = (committed.updatedAt.timeIntervalSince1970 * 1000).rounded()
        let candidate = (incoming.updatedAt.timeIntervalSince1970 * 1000).rounded()
        return candidate > current
    }
}
