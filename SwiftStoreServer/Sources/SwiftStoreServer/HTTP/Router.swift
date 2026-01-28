import Foundation

/// Route handler type
public typealias RouteHandler = @Sendable (HTTPRequest) async throws -> HTTPResponse

/// Simple HTTP router
public actor Router {
    /// Route entry
    private struct Route: Sendable {
        let method: HTTPMethod
        let path: String
        let handler: RouteHandler
    }

    private var routes: [Route] = []
    private var corsEnabled: Bool

    public init(corsEnabled: Bool = true) {
        self.corsEnabled = corsEnabled
    }

    /// Register a route
    public func register(_ method: HTTPMethod, _ path: String, handler: @escaping RouteHandler) {
        routes.append(Route(method: method, path: path, handler: handler))
    }

    /// Register a GET route
    public func get(_ path: String, handler: @escaping RouteHandler) {
        register(.get, path, handler: handler)
    }

    /// Register a POST route
    public func post(_ path: String, handler: @escaping RouteHandler) {
        register(.post, path, handler: handler)
    }

    /// Register a PUT route
    public func put(_ path: String, handler: @escaping RouteHandler) {
        register(.put, path, handler: handler)
    }

    /// Register a DELETE route
    public func delete(_ path: String, handler: @escaping RouteHandler) {
        register(.delete, path, handler: handler)
    }

    /// Handle an incoming request
    public func handle(_ request: HTTPRequest) async -> HTTPResponse {
        // Handle CORS preflight
        if request.method == .options && corsEnabled {
            return HTTPResponse.corsPreflightResponse()
        }

        // Find matching route
        for route in routes {
            if route.method == request.method && matchPath(route.path, request.path) {
                do {
                    return try await route.handler(request)
                } catch let error as HTTPError {
                    return HTTPResponse.error(error.localizedDescription, status: error.status, corsEnabled: corsEnabled)
                } catch {
                    return HTTPResponse.error(error.localizedDescription, corsEnabled: corsEnabled)
                }
            }
        }

        // Check if path exists with different method
        for route in routes {
            if matchPath(route.path, request.path) {
                return HTTPResponse.methodNotAllowed(corsEnabled: corsEnabled)
            }
        }

        return HTTPResponse.notFound(corsEnabled: corsEnabled)
    }

    /// Simple path matching (exact match for now)
    private func matchPath(_ pattern: String, _ path: String) -> Bool {
        pattern == path
    }
}
