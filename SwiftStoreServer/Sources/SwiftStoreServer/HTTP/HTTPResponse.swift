import Foundation

/// HTTP status codes
public enum HTTPStatus: Int, Sendable {
    case ok = 200
    case created = 201
    case noContent = 204
    case found = 302
    case badRequest = 400
    case unauthorized = 401
    case forbidden = 403
    case notFound = 404
    case methodNotAllowed = 405
    case internalServerError = 500

    var reasonPhrase: String {
        switch self {
        case .ok: return "OK"
        case .created: return "Created"
        case .noContent: return "No Content"
        case .found: return "Found"
        case .badRequest: return "Bad Request"
        case .unauthorized: return "Unauthorized"
        case .forbidden: return "Forbidden"
        case .notFound: return "Not Found"
        case .methodNotAllowed: return "Method Not Allowed"
        case .internalServerError: return "Internal Server Error"
        }
    }
}

/// HTTP response builder
public struct HTTPResponse: Sendable {
    /// Status code
    public var status: HTTPStatus

    /// Response headers
    public var headers: [String: String]

    /// Response body
    public var body: Data?

    public init(
        status: HTTPStatus = .ok,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    /// Build the raw HTTP response data
    public func build() -> Data {
        var response = "HTTP/1.1 \(status.rawValue) \(status.reasonPhrase)\r\n"

        var allHeaders = headers
        if let body = body {
            allHeaders["Content-Length"] = "\(body.count)"
        } else {
            allHeaders["Content-Length"] = "0"
        }

        for (key, value) in allHeaders {
            response += "\(key): \(value)\r\n"
        }
        response += "\r\n"

        var data = Data(response.utf8)
        if let body = body {
            data.append(body)
        }
        return data
    }

    /// Create a JSON response
    public static func json<T: Encodable>(_ value: T, status: HTTPStatus = .ok, corsEnabled: Bool = true) -> HTTPResponse {
        var headers = [
            "Content-Type": "application/json; charset=utf-8",
        ]

        if corsEnabled {
            headers["Access-Control-Allow-Origin"] = "*"
            headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
            headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let body = try encoder.encode(value)
            return HTTPResponse(status: status, headers: headers, body: body)
        } catch {
            return HTTPResponse.error("Failed to encode response: \(error)", corsEnabled: corsEnabled)
        }
    }

    /// Create an error response
    public static func error(_ message: String, status: HTTPStatus = .internalServerError, corsEnabled: Bool = true) -> HTTPResponse {
        let errorResponse = ["success": false, "error": message] as [String: Any]

        var headers = [
            "Content-Type": "application/json; charset=utf-8",
        ]

        if corsEnabled {
            headers["Access-Control-Allow-Origin"] = "*"
            headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
            headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
        }

        if let body = try? JSONSerialization.data(withJSONObject: errorResponse) {
            return HTTPResponse(status: status, headers: headers, body: body)
        }
        return HTTPResponse(status: status, headers: headers)
    }

    /// Create a CORS preflight response
    public static func corsPreflightResponse() -> HTTPResponse {
        HTTPResponse(
            status: .noContent,
            headers: [
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type, Authorization",
                "Access-Control-Max-Age": "86400",
            ]
        )
    }

    /// Create a not found response
    public static func notFound(corsEnabled: Bool = true) -> HTTPResponse {
        HTTPResponse.error("Not Found", status: .notFound, corsEnabled: corsEnabled)
    }

    /// Create a method not allowed response
    public static func methodNotAllowed(corsEnabled: Bool = true) -> HTTPResponse {
        HTTPResponse.error("Method Not Allowed", status: .methodNotAllowed, corsEnabled: corsEnabled)
    }

    /// Create an HTML response
    public static func html(_ content: String, status: HTTPStatus = .ok) -> HTTPResponse {
        HTTPResponse(
            status: status,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: Data(content.utf8)
        )
    }

    /// Create a redirect response
    public static func redirect(to location: String) -> HTTPResponse {
        HTTPResponse(
            status: .found,
            headers: ["Location": location]
        )
    }
}
