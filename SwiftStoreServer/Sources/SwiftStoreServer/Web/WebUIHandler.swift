import Foundation

/// Handler for Web UI routes
struct WebUIHandler: Sendable {
    /// Handle the admin page request
    func handleAdminPage(_ request: HTTPRequest) -> HTTPResponse {
        HTTPResponse.html(HTMLTemplates.adminPage)
    }

    /// Handle the root redirect
    func handleRootRedirect(_ request: HTTPRequest) -> HTTPResponse {
        HTTPResponse.redirect(to: "/admin")
    }
}
