import Foundation

/// A CloudKit write may replace a committed record only with a greater business timestamp.
package struct TimestampConflictResolver: Sendable {
    package init() {}
    package func shouldReplace(_ committed: SyncChange, with incoming: SyncChange) -> Bool {
        (incoming.updatedAt.timeIntervalSince1970 * 1000).rounded() >
            (committed.updatedAt.timeIntervalSince1970 * 1000).rounded()
    }
}
