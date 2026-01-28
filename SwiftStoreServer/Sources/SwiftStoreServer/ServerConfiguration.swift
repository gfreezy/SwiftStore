import Foundation

/// Configuration for the development HTTP server
public struct ServerConfiguration: Sendable {
    /// Host address to bind to (default: "127.0.0.1" for local-only access)
    public var host: String

    /// Port to listen on
    public var port: Int

    /// Whether to restrict to read-only operations
    public var readOnly: Bool

    /// Maximum allowed page size for pagination
    public var maxPageSize: Int

    /// Default page size when not specified
    public var defaultPageSize: Int

    /// Whether to enable CORS headers for cross-origin requests
    public var enableCORS: Bool

    /// Initialize server configuration
    /// - Parameters:
    ///   - host: Host address (default: "127.0.0.1")
    ///   - port: Port number (default: 8080)
    ///   - readOnly: Restrict to read-only operations (default: false)
    ///   - maxPageSize: Maximum page size (default: 1000)
    ///   - defaultPageSize: Default page size (default: 50)
    ///   - enableCORS: Enable CORS headers (default: true)
    public init(
        host: String = "127.0.0.1",
        port: Int = 8080,
        readOnly: Bool = false,
        maxPageSize: Int = 1000,
        defaultPageSize: Int = 50,
        enableCORS: Bool = true
    ) {
        self.host = host
        self.port = port
        self.readOnly = readOnly
        self.maxPageSize = maxPageSize
        self.defaultPageSize = defaultPageSize
        self.enableCORS = enableCORS
    }
}
