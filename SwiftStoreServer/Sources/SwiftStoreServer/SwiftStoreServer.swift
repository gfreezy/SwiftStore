import Foundation
import SwiftStoreConnectionQueue

/// Development HTTP server for SwiftStore database access
///
/// Provides REST API endpoints for executing SQL queries and managing database data.
/// Intended for development use only - not for production deployment.
///
/// Example usage:
/// ```swift
/// import SwiftStore
/// import SwiftStoreServer
///
/// let manager = try ConnectionManager(
///     path: "app.sqlite",
///     entities: [User.self]
/// )
/// try await manager.migrate(dryRun: false)
///
/// #if DEBUG
/// let server = try await SwiftStoreServer(
///     connectionManager: manager,
///     configuration: .init(port: 8080)
/// )
/// print("Dev server: http://127.0.0.1:8080")
/// try await server.start()
/// #endif
/// ```
public actor SwiftStoreServer {
    private let httpServer: HTTPServer
    private let configuration: ServerConfiguration
    private var isRunning = false

    /// Initialize the SwiftStore development server
    /// - Parameters:
    ///   - connectionManager: The ConnectionManager to use for database access
    ///   - configuration: Server configuration
    public init(
        connectionManager: ConnectionManager,
        configuration: ServerConfiguration = ServerConfiguration()
    ) async throws {
        self.configuration = configuration

        // Create handlers
        let queryHandler = QueryHandler(connectionManager: connectionManager, configuration: configuration)
        let schemaHandler = SchemaHandler(connectionManager: connectionManager)
        let webUIHandler = WebUIHandler()

        // Create router and register routes
        let router = Router(corsEnabled: configuration.enableCORS)
        await Self.registerRoutes(
            router: router,
            queryHandler: queryHandler,
            schemaHandler: schemaHandler,
            webUIHandler: webUIHandler,
            configuration: configuration
        )

        // Create HTTP server
        self.httpServer = try HTTPServer(router: router, configuration: configuration)
    }

    /// Register all API routes
    private static func registerRoutes(
        router: Router,
        queryHandler: QueryHandler,
        schemaHandler: SchemaHandler,
        webUIHandler: WebUIHandler,
        configuration: ServerConfiguration
    ) async {
        // Web UI routes
        await router.get("/") { request in
            webUIHandler.handleRootRedirect(request)
        }

        await router.get("/admin") { request in
            webUIHandler.handleAdminPage(request)
        }

        // Health check
        await router.get("/api/health") { _ in
            HTTPResponse.json(HealthResponse(), corsEnabled: configuration.enableCORS)
        }

        // Query endpoint (SELECT queries with pagination)
        await router.post("/api/query") { request in
            let queryRequest = try request.decodeBody(QueryRequest.self)
            let response = try await queryHandler.handleQuery(queryRequest)
            return HTTPResponse.json(response, corsEnabled: configuration.enableCORS)
        }

        // Execute endpoint (INSERT/UPDATE/DELETE)
        await router.post("/api/execute") { request in
            let executeRequest = try request.decodeBody(ExecuteRequest.self)
            let response = try await queryHandler.handleExecute(executeRequest)
            return HTTPResponse.json(response, corsEnabled: configuration.enableCORS)
        }

        // Schema endpoint
        await router.get("/api/schema") { _ in
            let response = try await schemaHandler.getSchema()
            return HTTPResponse.json(response, corsEnabled: configuration.enableCORS)
        }
    }

    /// Start the server
    public func start() async throws {
        guard !isRunning else { return }
        isRunning = true
        try await httpServer.start()
    }

    /// Stop the server
    public func stop() async {
        guard isRunning else { return }
        isRunning = false
        await httpServer.stop()
    }

    /// Get the server URL
    public var url: String {
        "http://\(configuration.host):\(configuration.port)"
    }
}

// MARK: - Re-exports

@_exported import SwiftStoreConnectionQueue
