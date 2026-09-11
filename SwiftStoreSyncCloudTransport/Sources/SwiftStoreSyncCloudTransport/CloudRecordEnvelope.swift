import Foundation
import CryptoKit
import SwiftStoreSync

/// CloudKit record encoding. Stable record names preserve existing iCloud data.
package struct CloudRecordEnvelope: Codable, Sendable {
    package let key: String
    package let updatedAt: Int64
    package let payload: Data

    package init(change: SyncChange) throws {
        guard !change.entityType.isEmpty, !change.syncKey.isEmpty else {
            throw SyncError.invalidPayload("Empty sync identity")
        }
        key = Self.key(for: change)
        updatedAt = try Self.timestamp(for: change)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        payload = try encoder.encode(change)
    }

    package init(key: String, updatedAt: Int64, payload: Data) {
        self.key = key
        self.updatedAt = updatedAt
        self.payload = payload
    }

    package func decodeChange() throws -> SyncChange {
        let change = try JSONDecoder().decode(SyncChange.self, from: payload)
        guard !change.entityType.isEmpty, !change.syncKey.isEmpty,
              key == Self.key(for: change), updatedAt == (try Self.timestamp(for: change)),
              change.operation == .delete || change.payload != nil else {
            throw SyncError.invalidPayload("Envelope identity, timestamp, or content does not match its payload")
        }
        return change
    }

    package static func key(for change: SyncChange) -> String {
        key(entityType: change.entityType, syncKey: change.syncKey)
    }

    package static func key(entityType: String, syncKey: Data) -> String {
        let name = Data(entityType.utf8)
        var length = UInt64(name.count).bigEndian
        var identity = withUnsafeBytes(of: &length) { Data($0) }
        identity.append(name)
        identity.append(syncKey)
        return SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
    }

    private static func timestamp(for change: SyncChange) throws -> Int64 {
        let time = (change.updatedAt.timeIntervalSince1970 * 1000).rounded()
        guard time.isFinite, abs(time) <= 9_007_199_254_740_991 else {
            throw SyncError.invalidPayload("Timestamp must fit a JSON safe integer in Unix milliseconds")
        }
        return Int64(time)
    }
}
