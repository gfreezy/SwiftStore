import Foundation

/// HTTP-related errors
public enum HTTPError: Error, LocalizedError {
    case badRequest(String)
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    case methodNotAllowed(String)
    case internalError(String)

    public var errorDescription: String? {
        switch self {
        case .badRequest(let message): return "Bad Request: \(message)"
        case .unauthorized(let message): return "Unauthorized: \(message)"
        case .forbidden(let message): return "Forbidden: \(message)"
        case .notFound(let message): return "Not Found: \(message)"
        case .methodNotAllowed(let message): return "Method Not Allowed: \(message)"
        case .internalError(let message): return "Internal Error: \(message)"
        }
    }

    public var status: HTTPStatus {
        switch self {
        case .badRequest: return .badRequest
        case .unauthorized: return .unauthorized
        case .forbidden: return .forbidden
        case .notFound: return .notFound
        case .methodNotAllowed: return .methodNotAllowed
        case .internalError: return .internalServerError
        }
    }
}
