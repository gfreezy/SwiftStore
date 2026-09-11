import Foundation

/// Errors reported by CloudKit synchronization.
public enum CloudKitTransportError: Error, LocalizedError {
    /// iCloud account is not signed in or not available.
    case notSignedIn(String)
    /// The native driver is not running.
    case notStarted
    case zoneDeleted
    /// A persisted state blob could not be decoded.
    case stateCorrupt(String)
    /// A `SyncChange` could not be encoded into a `CKRecord` or vice versa.
    case encodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn(let detail):
            return "iCloud account not available: \(detail)"
        case .zoneDeleted:
            return "The CloudKit sync zone was deleted. Synchronization is paused; preserve the local database and restore the original zone before retrying."
        case .notStarted:
            return "CloudKit synchronization is not running."
        case .stateCorrupt(let detail):
            return "Persisted CloudKit state is corrupt: \(detail)"
        case .encodingFailed(let detail):
            return "Failed to encode/decode SyncChange: \(detail)"
        }
    }
}
