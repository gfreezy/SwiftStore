import Foundation

/// Errors that can occur during sync
public enum SyncError: Error, LocalizedError {
    case accountChanged
    case scopeChanged
    case invalidPayload(String)
    case unknownEntityType(String)
    case applyFailed(String)
    case notConfigured(String)

    public var errorDescription: String? {
        switch self {
        case .accountChanged: return "iCloud account changed; preserve this database for its original account."
        case .scopeChanged: return "CloudKit container, zone or checkpoint driver changed; the existing checkpoint cannot be reused."
        case .invalidPayload(let message):
            return "Invalid payload: \(message)"
        case .unknownEntityType(let type):
            return "Unknown entity type: \(type)"
        case .applyFailed(let message):
            return "Failed to apply change: \(message)"
        case .notConfigured(let message):
            return "Sync not configured: \(message)"
        }
    }
}
