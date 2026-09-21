import Foundation

/// Upload counts durable local changelog events (coalesced edits still count separately).
/// Download counts fetched records after their page has been applied, including unchanged records.
public struct SyncProgress: Sendable, Equatable {
    public enum Direction: Sendable { case upload, download }
    public let direction: Direction
    public let completedCount: Int
    /// CloudKit does not provide a download total until fetching has finished.
    /// Upload totals can grow if the application writes during synchronization.
    public let totalCount: Int?
    public let isComplete: Bool

    public init(direction: Direction, completedCount: Int, totalCount: Int?, isComplete: Bool = false) {
        self.direction = direction
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.isComplete = isComplete
    }
}

public typealias SyncProgressHandler = @Sendable (SyncProgress) async -> Void
