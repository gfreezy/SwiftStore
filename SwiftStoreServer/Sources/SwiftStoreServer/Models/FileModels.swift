import Foundation

/// Response for file list API
public struct FileListResponse: Codable, Sendable {
    public let success: Bool
    public let path: String
    public let items: [FileItem]?
    public let error: String?

    public init(success: Bool, path: String, items: [FileItem]? = nil, error: String? = nil) {
        self.success = success
        self.path = path
        self.items = items
        self.error = error
    }

    public static func success(path: String, items: [FileItem]) -> FileListResponse {
        FileListResponse(success: true, path: path, items: items, error: nil)
    }

    public static func failure(path: String, error: String) -> FileListResponse {
        FileListResponse(success: false, path: path, items: nil, error: error)
    }
}

/// File item information
public struct FileItem: Codable, Sendable {
    public let name: String
    public let isDirectory: Bool
    public let size: Int64?
    public let modified: Date?
    public let permissions: String?

    public init(
        name: String,
        isDirectory: Bool,
        size: Int64? = nil,
        modified: Date? = nil,
        permissions: String? = nil
    ) {
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
        self.permissions = permissions
    }
}

/// Response for file info API
public struct FileInfoResponse: Codable, Sendable {
    public let success: Bool
    public let path: String
    public let exists: Bool
    public let isDirectory: Bool?
    public let size: Int64?
    public let modified: Date?
    public let error: String?

    public init(
        success: Bool,
        path: String,
        exists: Bool,
        isDirectory: Bool? = nil,
        size: Int64? = nil,
        modified: Date? = nil,
        error: String? = nil
    ) {
        self.success = success
        self.path = path
        self.exists = exists
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
        self.error = error
    }
}

/// Response for file upload API
public struct FileUploadResponse: Codable, Sendable {
    public let success: Bool
    public let path: String?
    public let filename: String?
    public let size: Int64?
    public let error: String?

    public init(
        success: Bool,
        path: String? = nil,
        filename: String? = nil,
        size: Int64? = nil,
        error: String? = nil
    ) {
        self.success = success
        self.path = path
        self.filename = filename
        self.size = size
        self.error = error
    }

    public static func success(path: String, filename: String, size: Int64) -> FileUploadResponse {
        FileUploadResponse(success: true, path: path, filename: filename, size: size, error: nil)
    }

    public static func failure(error: String) -> FileUploadResponse {
        FileUploadResponse(success: false, path: nil, filename: nil, size: nil, error: error)
    }
}

/// Parsed multipart form data part
public struct MultipartPart: Sendable {
    public let name: String
    public let filename: String?
    public let contentType: String?
    public let data: Data

    public init(name: String, filename: String? = nil, contentType: String? = nil, data: Data) {
        self.name = name
        self.filename = filename
        self.contentType = contentType
        self.data = data
    }
}

/// Response for file root info API
public struct FileRootInfoResponse: Codable, Sendable {
    public let success: Bool
    public let root: String

    public init(success: Bool, root: String) {
        self.success = success
        self.root = root
    }
}
