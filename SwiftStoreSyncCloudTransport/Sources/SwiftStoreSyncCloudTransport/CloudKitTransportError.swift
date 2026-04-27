import Foundation

/// Errors thrown by `CloudKitSyncTransport`.
public enum CloudKitTransportError: Error, LocalizedError {
    /// iCloud account is not signed in or not available.
    case notSignedIn(String)
    /// `start()` has not been called yet.
    case notStarted
    /// A persisted state blob could not be decoded.
    case stateCorrupt(String)
    /// A `SyncChange` could not be encoded into a `CKRecord` or vice versa.
    case encodingFailed(String)
    /// CloudKit reported a non-conflict failure during send.
    case sendFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn(let detail):
            return "iCloud account not available: \(detail)"
        case .notStarted:
            return "CloudKitSyncTransport.start() must be called before use."
        case .stateCorrupt(let detail):
            return "Persisted CloudKit state is corrupt: \(detail)"
        case .encodingFailed(let detail):
            return "Failed to encode/decode SyncChange: \(detail)"
        case .sendFailed(let underlying):
            return "CloudKit send failed: \(underlying)"
        }
    }
}
