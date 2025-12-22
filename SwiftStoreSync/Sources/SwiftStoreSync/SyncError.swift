import Foundation

/// Errors that can occur during sync
public enum SyncError: Error, LocalizedError {
    case invalidPayload(String)
    case unknownEntityType(String)
    case applyFailed(String)
    case pushFailed(String)
    case pullFailed(String)
    case conflictDetected([SyncChange])
    case notConfigured(String)
    case syncAlreadyInProgress(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPayload(let message):
            return "Invalid payload: \(message)"
        case .unknownEntityType(let type):
            return "Unknown entity type: \(type)"
        case .applyFailed(let message):
            return "Failed to apply change: \(message)"
        case .pushFailed(let message):
            return "Failed to push changes: \(message)"
        case .pullFailed(let message):
            return "Failed to pull changes: \(message)"
        case .conflictDetected(let changes):
            return "Conflict detected for \(changes.count) changes"
        case .notConfigured(let message):
            return "Sync not configured: \(message)"
        case .syncAlreadyInProgress(let message):
            return "Sync already in progress: \(message)"
        }
    }
}
