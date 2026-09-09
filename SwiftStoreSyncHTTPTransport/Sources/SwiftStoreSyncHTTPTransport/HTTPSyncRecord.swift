import Foundation
import SwiftStoreSync
import SwiftStoreCore

/// Server-visible envelope. The server compares updatedAt only and never parses payload.
public struct HTTPSyncRecord: Codable, Sendable {
    public let key: String
    /// Unix milliseconds, rounded to the nearest millisecond (ties away from zero).
    public let updatedAt: Int64
    /// Base64 on the wire. Contains the complete client-owned SyncChange JSON.
    public let payload: Data
    /// Assigned only by the server; absent on upload. Orders delivery, not conflicts.
    public let sequence: Int64?

    public init(change: SyncChange, sequence: Int64? = nil) throws {
        let envelope: SyncRecordEnvelope
        do { envelope = try SyncRecordEnvelope(change: change) }
        catch { throw HTTPSyncError.invalidConfiguration(error.localizedDescription) }
        self.sequence = sequence
        key = envelope.key
        updatedAt = envelope.updatedAt
        payload = envelope.payload
    }

    public init(key: String, updatedAt: Int64, payload: Data, sequence: Int64? = nil) {
        self.key = key
        self.updatedAt = updatedAt
        self.payload = payload
        self.sequence = sequence
    }

    public func decodeChange() throws -> SyncChange {
        do {
            return try SyncRecordEnvelope(key: key, updatedAt: updatedAt, payload: payload).decodeChange()
        } catch {
            throw HTTPSyncError.invalidResponse
        }
    }

    static func key(for change: SyncChange) -> String {
        SyncRecordEnvelope.key(for: change)
    }
}
