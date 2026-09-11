import Foundation
import SwiftStoreCore

/// Bounded reads of immutable local events, using the owning writer connection.
public final class ChangeTrackerReader {
    private let connection: SQLiteConnection

    public init(connection: SQLiteConnection) { self.connection = connection }

    public func changes(after seq: Int64, limit: Int = 200) throws -> [ChangeLog] {
        guard seq >= 0, limit > 0 else { throw StoreError.invalidPayload("Invalid changelog read bounds") }
        return try ChangeLog.filter(\.seq > seq).order(by: \.seq).limit(limit).all(connection)
    }

    public func latestSequence() throws -> Int64 {
        try connection.queryScalar("SELECT MAX(seq) FROM __swiftstore_change_log") ?? 0
    }

    public func count(after seq: Int64) throws -> Int {
        try connection.queryScalar("SELECT COUNT(*) FROM __swiftstore_change_log WHERE seq > ?", values: [.integer(seq)]) ?? 0
    }
}
