import Foundation

/// Handler for file management operations
public struct FileHandler: Sendable {
    private let rootPath: String
    private let configuration: ServerConfiguration

    public init(rootPath: String, configuration: ServerConfiguration) {
        // Normalize root path
        self.rootPath = (rootPath as NSString).standardizingPath
        self.configuration = configuration
    }

    /// List directory contents
    public func handleList(_ request: HTTPRequest) async throws -> HTTPResponse {
        let requestPath = request.queryParams["path"] ?? "/"
        let fullPath = resolvePath(requestPath)

        guard let safePath = validatePath(fullPath) else {
            return HTTPResponse.json(
                FileListResponse.failure(path: requestPath, error: "Access denied: path is outside root directory"),
                status: .forbidden,
                corsEnabled: configuration.enableCORS
            )
        }

        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: safePath) else {
            return HTTPResponse.json(
                FileListResponse.failure(path: requestPath, error: "Path does not exist"),
                status: .notFound,
                corsEnabled: configuration.enableCORS
            )
        }

        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: safePath, isDirectory: &isDirectory)

        guard isDirectory.boolValue else {
            return HTTPResponse.json(
                FileListResponse.failure(path: requestPath, error: "Path is not a directory"),
                status: .badRequest,
                corsEnabled: configuration.enableCORS
            )
        }

        do {
            let contents = try fileManager.contentsOfDirectory(atPath: safePath)
            var items: [FileItem] = []

            for name in contents.sorted() {
                // Skip hidden files
                if name.hasPrefix(".") {
                    continue
                }

                let itemPath = (safePath as NSString).appendingPathComponent(name)
                var itemIsDir: ObjCBool = false
                fileManager.fileExists(atPath: itemPath, isDirectory: &itemIsDir)

                var size: Int64? = nil
                var modified: Date? = nil

                if let attrs = try? fileManager.attributesOfItem(atPath: itemPath) {
                    if !itemIsDir.boolValue {
                        size = attrs[.size] as? Int64
                    }
                    modified = attrs[.modificationDate] as? Date
                }

                items.append(FileItem(
                    name: name,
                    isDirectory: itemIsDir.boolValue,
                    size: size,
                    modified: modified
                ))
            }

            // Sort: directories first, then files, both alphabetically
            items.sort { a, b in
                if a.isDirectory != b.isDirectory {
                    return a.isDirectory
                }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }

            return HTTPResponse.json(
                FileListResponse.success(path: requestPath, items: items),
                corsEnabled: configuration.enableCORS
            )
        } catch {
            return HTTPResponse.json(
                FileListResponse.failure(path: requestPath, error: "Failed to read directory: \(error.localizedDescription)"),
                status: .internalServerError,
                corsEnabled: configuration.enableCORS
            )
        }
    }

    /// Download or view a file
    /// Query params:
    /// - path: file path (required)
    /// - download: if "true", force download; if "false", force inline; otherwise auto-detect
    public func handleDownload(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let requestPath = request.queryParams["path"] else {
            return HTTPResponse.error("Missing path parameter", status: .badRequest, corsEnabled: configuration.enableCORS)
        }

        let fullPath = resolvePath(requestPath)

        guard let safePath = validatePath(fullPath) else {
            return HTTPResponse.error("Access denied: path is outside root directory", status: .forbidden, corsEnabled: configuration.enableCORS)
        }

        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: safePath, isDirectory: &isDirectory) else {
            return HTTPResponse.error("File not found", status: .notFound, corsEnabled: configuration.enableCORS)
        }

        if isDirectory.boolValue {
            return HTTPResponse.error("Cannot download a directory", status: .badRequest, corsEnabled: configuration.enableCORS)
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: safePath))
            let filename = (safePath as NSString).lastPathComponent

            // Download if explicitly requested, otherwise open inline
            let shouldDownload = request.queryParams["download"] == "true"

            if shouldDownload {
                return HTTPResponse.fileDownload(data: data, filename: filename, corsEnabled: configuration.enableCORS)
            } else {
                return HTTPResponse.fileInline(data: data, filename: filename, corsEnabled: configuration.enableCORS)
            }
        } catch {
            return HTTPResponse.error("Failed to read file: \(error.localizedDescription)", status: .internalServerError, corsEnabled: configuration.enableCORS)
        }
    }

    /// Upload a file
    public func handleUpload(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard configuration.allowFileUpload else {
            return HTTPResponse.json(
                FileUploadResponse.failure(error: "File upload is disabled"),
                status: .forbidden,
                corsEnabled: configuration.enableCORS
            )
        }

        guard !configuration.readOnly else {
            return HTTPResponse.json(
                FileUploadResponse.failure(error: "Server is in read-only mode"),
                status: .forbidden,
                corsEnabled: configuration.enableCORS
            )
        }

        let parts: [MultipartPart]
        do {
            parts = try request.parseMultipart()
        } catch {
            return HTTPResponse.json(
                FileUploadResponse.failure(error: "Failed to parse multipart data: \(error.localizedDescription)"),
                status: .badRequest,
                corsEnabled: configuration.enableCORS
            )
        }

        // Get destination path from form data
        let destPath = parts.first { $0.name == "path" }.flatMap { String(data: $0.data, encoding: .utf8) } ?? "/"

        // Get file part
        guard let filePart = parts.first(where: { $0.name == "file" && $0.filename != nil }) else {
            return HTTPResponse.json(
                FileUploadResponse.failure(error: "No file provided"),
                status: .badRequest,
                corsEnabled: configuration.enableCORS
            )
        }

        guard let filename = filePart.filename, !filename.isEmpty else {
            return HTTPResponse.json(
                FileUploadResponse.failure(error: "Invalid filename"),
                status: .badRequest,
                corsEnabled: configuration.enableCORS
            )
        }

        // Check file size
        if filePart.data.count > configuration.maxUploadSize {
            return HTTPResponse.json(
                FileUploadResponse.failure(error: "File too large. Maximum size is \(configuration.maxUploadSize / (1024 * 1024))MB"),
                status: .badRequest,
                corsEnabled: configuration.enableCORS
            )
        }

        // Resolve and validate destination path
        let destDir = resolvePath(destPath)
        guard let safeDest = validatePath(destDir) else {
            return HTTPResponse.json(
                FileUploadResponse.failure(error: "Access denied: destination is outside root directory"),
                status: .forbidden,
                corsEnabled: configuration.enableCORS
            )
        }

        // Sanitize filename (remove path components)
        let sanitizedFilename = (filename as NSString).lastPathComponent
        let filePath = (safeDest as NSString).appendingPathComponent(sanitizedFilename)

        // Validate the final file path
        guard validatePath(filePath) != nil else {
            return HTTPResponse.json(
                FileUploadResponse.failure(error: "Access denied: invalid filename"),
                status: .forbidden,
                corsEnabled: configuration.enableCORS
            )
        }

        let fileManager = FileManager.default

        // Ensure destination directory exists
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: safeDest, isDirectory: &isDirectory) || !isDirectory.boolValue {
            return HTTPResponse.json(
                FileUploadResponse.failure(error: "Destination directory does not exist"),
                status: .badRequest,
                corsEnabled: configuration.enableCORS
            )
        }

        do {
            try filePart.data.write(to: URL(fileURLWithPath: filePath))
            return HTTPResponse.json(
                FileUploadResponse.success(
                    path: destPath,
                    filename: sanitizedFilename,
                    size: Int64(filePart.data.count)
                ),
                corsEnabled: configuration.enableCORS
            )
        } catch {
            return HTTPResponse.json(
                FileUploadResponse.failure(error: "Failed to save file: \(error.localizedDescription)"),
                status: .internalServerError,
                corsEnabled: configuration.enableCORS
            )
        }
    }

    /// Get file or directory info
    public func handleInfo(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let requestPath = request.queryParams["path"] else {
            return HTTPResponse.error("Missing path parameter", status: .badRequest, corsEnabled: configuration.enableCORS)
        }

        let fullPath = resolvePath(requestPath)

        guard let safePath = validatePath(fullPath) else {
            return HTTPResponse.json(
                FileInfoResponse(
                    success: false,
                    path: requestPath,
                    exists: false,
                    error: "Access denied: path is outside root directory"
                ),
                status: .forbidden,
                corsEnabled: configuration.enableCORS
            )
        }

        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: safePath, isDirectory: &isDirectory)

        if !exists {
            return HTTPResponse.json(
                FileInfoResponse(success: true, path: requestPath, exists: false),
                corsEnabled: configuration.enableCORS
            )
        }

        var size: Int64? = nil
        var modified: Date? = nil

        if let attrs = try? fileManager.attributesOfItem(atPath: safePath) {
            if !isDirectory.boolValue {
                size = attrs[.size] as? Int64
            }
            modified = attrs[.modificationDate] as? Date
        }

        return HTTPResponse.json(
            FileInfoResponse(
                success: true,
                path: requestPath,
                exists: true,
                isDirectory: isDirectory.boolValue,
                size: size,
                modified: modified
            ),
            corsEnabled: configuration.enableCORS
        )
    }

    /// Get the root path info
    public func handleRootInfo(_ request: HTTPRequest) async throws -> HTTPResponse {
        return HTTPResponse.json(
            FileRootInfoResponse(success: true, root: rootPath),
            corsEnabled: configuration.enableCORS
        )
    }

    // MARK: - Path Security

    /// Resolve a request path to a full filesystem path
    private func resolvePath(_ path: String) -> String {
        var path = path

        // Handle URL decoding
        if let decoded = path.removingPercentEncoding {
            path = decoded
        }

        // Remove leading slash if present
        if path.hasPrefix("/") {
            path = String(path.dropFirst())
        }

        // Combine with root
        if path.isEmpty {
            return rootPath
        }

        return (rootPath as NSString).appendingPathComponent(path)
    }

    /// Validate that a path is within the allowed root directory
    /// Returns the canonicalized path if valid, nil if invalid
    private func validatePath(_ path: String) -> String? {
        // Get canonical path by resolving symlinks
        let url = URL(fileURLWithPath: path)
        let resolvedPath = url.standardized.path

        // Ensure path starts with root
        let rootURL = URL(fileURLWithPath: rootPath)
        let resolvedRoot = rootURL.standardized.path

        // Check if the resolved path is within root
        // Must either equal root or be a subdirectory of root
        if resolvedPath == resolvedRoot {
            return resolvedPath
        }

        if resolvedPath.hasPrefix(resolvedRoot + "/") {
            return resolvedPath
        }

        return nil
    }
}
