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

    /// Parse multipart/form-data body
    public func parseMultipart() throws -> [MultipartPart] {
        guard let body = body else {
            throw HTTPError.badRequest("Missing request body")
        }

        guard let contentType = headers["content-type"],
              contentType.contains("multipart/form-data") else {
            throw HTTPError.badRequest("Content-Type must be multipart/form-data")
        }

        // Extract boundary from Content-Type header
        guard let boundaryMatch = contentType.range(of: "boundary="),
              boundaryMatch.upperBound < contentType.endIndex else {
            throw HTTPError.badRequest("Missing boundary in Content-Type")
        }

        var boundary = String(contentType[boundaryMatch.upperBound...])
        // Remove quotes if present
        if boundary.hasPrefix("\"") && boundary.hasSuffix("\"") {
            boundary = String(boundary.dropFirst().dropLast())
        }
        // Handle potential semicolon after boundary
        if let semicolonIndex = boundary.firstIndex(of: ";") {
            boundary = String(boundary[..<semicolonIndex])
        }
        boundary = boundary.trimmingCharacters(in: .whitespaces)

        let boundaryData = Data("--\(boundary)".utf8)

        var parts: [MultipartPart] = []
        var position = 0

        // Find parts separated by boundary
        while position < body.count {
            // Find next boundary
            guard let boundaryRange = body.range(of: boundaryData, in: position..<body.count) else {
                break
            }

            // Skip to after the boundary
            position = boundaryRange.upperBound

            // Skip CRLF after boundary
            if position + 2 <= body.count,
               body[position] == 0x0D, body[position + 1] == 0x0A {
                position += 2
            }

            // Check if this is the end boundary
            if position < body.count {
                let remaining = body.subdata(in: position..<min(position + 2, body.count))
                if remaining == Data("--".utf8) {
                    break
                }
            }

            // Find the end of headers (double CRLF)
            guard let headerEndRange = body.range(of: Data("\r\n\r\n".utf8), in: position..<body.count) else {
                break
            }

            // Parse headers
            let headerData = body.subdata(in: position..<headerEndRange.lowerBound)
            guard let headerString = String(data: headerData, encoding: .utf8) else {
                position = headerEndRange.upperBound
                continue
            }

            var partName: String?
            var partFilename: String?
            var partContentType: String?

            for line in headerString.components(separatedBy: "\r\n") {
                let lowercaseLine = line.lowercased()
                if lowercaseLine.hasPrefix("content-disposition:") {
                    // Parse name and filename from Content-Disposition
                    if let nameMatch = line.range(of: "name=\"") {
                        let start = nameMatch.upperBound
                        if let endQuote = line[start...].firstIndex(of: "\"") {
                            partName = String(line[start..<endQuote])
                        }
                    }
                    if let filenameMatch = line.range(of: "filename=\"") {
                        let start = filenameMatch.upperBound
                        if let endQuote = line[start...].firstIndex(of: "\"") {
                            partFilename = String(line[start..<endQuote])
                        }
                    }
                } else if lowercaseLine.hasPrefix("content-type:") {
                    partContentType = line.dropFirst(13).trimmingCharacters(in: .whitespaces)
                }
            }

            // Move to content start
            let contentStart = headerEndRange.upperBound

            // Find next boundary or end
            let nextBoundaryRange = body.range(of: boundaryData, in: contentStart..<body.count)
            let contentEnd: Int

            if let nextRange = nextBoundaryRange {
                // Content ends at boundary minus CRLF
                contentEnd = nextRange.lowerBound - 2
            } else {
                contentEnd = body.count
            }

            if contentEnd > contentStart, let name = partName {
                let partData = body.subdata(in: contentStart..<contentEnd)
                parts.append(MultipartPart(
                    name: name,
                    filename: partFilename,
                    contentType: partContentType,
                    data: partData
                ))
            }
        }

        return parts
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
