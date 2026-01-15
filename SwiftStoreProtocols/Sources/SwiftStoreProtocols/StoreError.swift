import Foundation

/// Errors that can occur during store operations
public enum StoreError: Error, Sendable {
    case databaseNotFound
    case invalidSchema(String)
    case entityNotFound(SQLiteValue)
    case constraintViolation(String)
    case migrationFailed(String)
    case queryFailed(String)
    case encodingFailed(String)
    case decodingFailed(String)
    case transactionFailed(String)
    case syncNotEnabled
    case invalidPayload(String)
    case timeOutOfSync(offsetMs: Int64, toleranceMs: Int64)
}

extension StoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "Database file not found"
        case .invalidSchema(let message):
            return "Invalid schema: \(message)"
        case .entityNotFound(let id):
            return "Entity not found with id: \(id)"
        case .constraintViolation(let message):
            return "Constraint violation: \(message)"
        case .migrationFailed(let message):
            return "Migration failed: \(message)"
        case .queryFailed(let message):
            return "Query failed: \(message)"
        case .encodingFailed(let message):
            return "Encoding failed: \(message)"
        case .decodingFailed(let message):
            return "Decoding failed: \(message)"
        case .transactionFailed(let message):
            return "Transaction failed: \(message)"
        case .syncNotEnabled:
            return "Sync is not enabled. Call enableSync(deviceId:) first."
        case .invalidPayload(let message):
            return "Invalid payload: \(message)"
        case .timeOutOfSync(let offsetMs, let toleranceMs):
            return "Local time is out of sync with NTP. Offset: \(offsetMs)ms, tolerance: \(toleranceMs)ms"
        }
    }
}
