import Foundation

/// HTTP request method
public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case options = "OPTIONS"
    case head = "HEAD"
    case patch = "PATCH"
}

/// Parsed HTTP request
public struct HTTPRequest: Sendable {
    /// HTTP method
    public let method: HTTPMethod

    /// Request path (e.g., "/api/query")
    public let path: String

    /// Query parameters
    public let queryParams: [String: String]

    /// HTTP headers
    public let headers: [String: String]

    /// Request body data
    public let body: Data?

    public init(
        method: HTTPMethod,
        path: String,
        queryParams: [String: String] = [:],
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.method = method
        self.path = path
        self.queryParams = queryParams
        self.headers = headers
        self.body = body
    }

    /// Decode the request body as JSON
    public func decodeBody<T: Decodable>(_ type: T.Type) throws -> T {
        guard let data = body else {
            throw HTTPError.badRequest("Missing request body")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw HTTPError.badRequest("Invalid JSON: \(error.localizedDescription)")
        }
    }
}

/// HTTP request parser
public struct HTTPRequestParser {
    /// Parse raw HTTP request data
    public static func parse(_ data: Data) throws -> HTTPRequest {
        guard let string = String(data: data, encoding: .utf8) else {
            throw HTTPError.badRequest("Invalid UTF-8 in request")
        }

        // Split headers and body
        let parts = string.components(separatedBy: "\r\n\r\n")
        let headerSection = parts[0]
        let bodyData: Data?

        if parts.count > 1 && !parts[1].isEmpty {
            bodyData = parts[1].data(using: .utf8)
        } else {
            bodyData = nil
        }

        let lines = headerSection.components(separatedBy: "\r\n")
        guard !lines.isEmpty else {
            throw HTTPError.badRequest("Empty request")
        }

        // Parse request line
        let requestLine = lines[0].components(separatedBy: " ")
        guard requestLine.count >= 2 else {
            throw HTTPError.badRequest("Invalid request line")
        }

        let methodString = requestLine[0]
        guard let method = HTTPMethod(rawValue: methodString.uppercased()) else {
            throw HTTPError.methodNotAllowed("Unknown method: \(methodString)")
        }

        let urlPath = requestLine[1]

        // Parse path and query parameters
        let (path, queryParams) = parseURL(urlPath)

        // Parse headers
        var headers: [String: String] = [:]
        for i in 1..<lines.count {
            let line = lines[i]
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        return HTTPRequest(
            method: method,
            path: path,
            queryParams: queryParams,
            headers: headers,
            body: bodyData
        )
    }

    /// Parse URL into path and query parameters
    private static func parseURL(_ url: String) -> (path: String, params: [String: String]) {
        guard let questionIndex = url.firstIndex(of: "?") else {
            return (url, [:])
        }

        let path = String(url[..<questionIndex])
        let queryString = String(url[url.index(after: questionIndex)...])

        var params: [String: String] = [:]
        for pair in queryString.components(separatedBy: "&") {
            let parts = pair.components(separatedBy: "=")
            if parts.count == 2 {
                let key = parts[0].removingPercentEncoding ?? parts[0]
                let value = parts[1].removingPercentEncoding ?? parts[1]
                params[key] = value
            }
        }

        return (path, params)
    }
}
