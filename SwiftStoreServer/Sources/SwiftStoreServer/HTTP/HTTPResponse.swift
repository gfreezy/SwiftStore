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
            encoder.dateEncodingStrategy = .iso8601
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

    /// Create a file download response
    public static func fileDownload(
        data: Data,
        filename: String,
        mimeType: String? = nil,
        corsEnabled: Bool = true
    ) -> HTTPResponse {
        let contentType = mimeType ?? Self.mimeType(for: filename)

        var headers = [
            "Content-Type": contentType,
            "Content-Disposition": "attachment; filename=\"\(filename)\"",
        ]

        if corsEnabled {
            headers["Access-Control-Allow-Origin"] = "*"
            headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
            headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
        }

        return HTTPResponse(status: .ok, headers: headers, body: data)
    }

    /// Create an inline file response (for viewing in browser)
    public static func fileInline(
        data: Data,
        filename: String,
        mimeType: String? = nil,
        corsEnabled: Bool = true
    ) -> HTTPResponse {
        let contentType = mimeType ?? Self.mimeType(for: filename)

        var headers = [
            "Content-Type": contentType,
            "Content-Disposition": "inline; filename=\"\(filename)\"",
        ]

        if corsEnabled {
            headers["Access-Control-Allow-Origin"] = "*"
            headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
            headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
        }

        return HTTPResponse(status: .ok, headers: headers, body: data)
    }

    /// Get MIME type for a filename based on extension
    public static func mimeType(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()

        switch ext {
        // Text
        case "txt": return "text/plain"
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "js": return "application/javascript"
        case "json": return "application/json"
        case "xml": return "application/xml"
        case "csv": return "text/csv"
        case "md": return "text/markdown"

        // Images
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        case "webp": return "image/webp"
        case "heic", "heif": return "image/heic"
        case "bmp": return "image/bmp"

        // Documents
        case "pdf": return "application/pdf"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"

        // Archives
        case "zip": return "application/zip"
        case "tar": return "application/x-tar"
        case "gz": return "application/gzip"
        case "rar": return "application/vnd.rar"
        case "7z": return "application/x-7z-compressed"

        // Audio/Video
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "m4a": return "audio/mp4"
        case "aac": return "audio/aac"
        case "flac": return "audio/flac"
        case "ogg": return "audio/ogg"
        case "mp4": return "video/mp4"
        case "m4v": return "video/mp4"
        case "webm": return "video/webm"
        case "mov": return "video/quicktime"

        // Code
        case "swift": return "text/x-swift"
        case "py": return "text/x-python"
        case "rb": return "text/x-ruby"
        case "java": return "text/x-java"
        case "c", "h": return "text/x-c"
        case "cpp", "hpp": return "text/x-c++src"
        case "rs": return "text/x-rust"
        case "go": return "text/x-go"
        case "ts": return "application/typescript"
        case "sh": return "application/x-sh"
        case "yaml", "yml": return "text/yaml"

        // Database
        case "sqlite", "db": return "application/x-sqlite3"
        case "sql": return "application/sql"

        default: return "application/octet-stream"
        }
    }
}
