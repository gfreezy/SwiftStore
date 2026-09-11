import Foundation

/// Persist this reference with your business data, rather than an absolute URL.
public struct FileReference: Codable, Hashable, Sendable {
    public let scope: String
    public let path: String

    public init(scope: String, path: String) {
        self.scope = scope
        self.path = path
    }
}

public enum FileStoreError: Error, Equatable, Sendable {
    case invalidPath(String)
    case wrongScope
    case alreadyOpen
    case closed
    case unavailable
    case accountMismatch
    case notFound
    case timedOut
    case conflict(String)
    case localDiskFull
    case corruptState
    case deliveryUncertain
    case fileInUse
}

extension FileStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path): "Invalid file path: \(path)"
        case .wrongScope: "The file belongs to another store."
        case .alreadyOpen: "This file store already has an active writer."
        case .closed: "The file store is closed."
        case .unavailable: "The file or its iCloud account is currently unavailable."
        case .accountMismatch: "Sign in to the original iCloud account to resume synchronization."
        case .notFound: "The file does not exist or has been deleted."
        case .timedOut: "Timed out waiting for the file."
        case .conflict(let path): "Conflicting content must be reviewed: \(path)"
        case .localDiskFull: "There is not enough space on this device."
        case .corruptState: "File store recovery data is invalid. Existing files have been retained."
        case .deliveryUncertain: "The previous upload handoff could not be confirmed. Local content has been retained."
        case .fileInUse: "Close active file access handles before closing the store."
        }
    }
}

/// Original system error information is retained without making clients inspect NSError.
public struct FileIssue: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case unavailable, accountMismatch, quota, diskFull, conflict, uncertain, other
    }
    public let kind: Kind
    public let domain: String
    public let code: Int
    public let message: String

    init(_ error: Error) {
        let ns = error as NSError
        domain = ns.domain
        code = ns.code
        message = ns.localizedDescription
        if error as? FileStoreError == .accountMismatch { kind = .accountMismatch }
        else if error as? FileStoreError == .unavailable { kind = .unavailable }
        else if error as? FileStoreError == .deliveryUncertain { kind = .uncertain }
        else if case .conflict = error as? FileStoreError { kind = .conflict }
        else if error as? FileStoreError == .localDiskFull { kind = .diskFull }
        else {
            var current: NSError? = ns
            var result: Kind = .other
            for _ in 0..<8 {
                guard let value = current else { break }
                if value.domain == NSCocoaErrorDomain {
                    if value.code == CocoaError.Code.ubiquitousFileNotUploadedDueToQuota.rawValue { result = .quota; break }
                    if value.code == CocoaError.Code.fileWriteOutOfSpace.rawValue { result = .diskFull; break }
                }
                if value.domain == NSPOSIXErrorDomain, value.code == 28 { result = .diskFull; break }
                current = value.userInfo[NSUnderlyingErrorKey] as? NSError
            }
            kind = result
        }
    }
}

public enum FileSyncState: String, Codable, Sendable {
    case localOnly, pending, handedOff, uploaded, remoteOnly, conflict, uncertain, deleted
}

public struct FileStatus: Sendable {
    public let file: FileReference
    public let isLocal: Bool
    public let syncState: FileSyncState
    public let isInUse: Bool
    public let issue: FileIssue?
    /// Fractions in 0...1, or nil when the system hasn't provided progress.
    public let uploadProgress: Double?
    public let downloadProgress: Double?
}

public struct FileListing: Sendable {
    public enum Discovery: String, Sendable { case disabled, unavailable, gathering, ready }
    public let files: [FileStatus]
    public let discovery: Discovery
    public let issue: FileIssue?
}

public struct DeletionResult: Sendable {
    /// The deletion intent is durable; new reads cannot acquire this file.
    public let isRegistered: Bool
    public let localCleanupPending: Bool
    public let cloudDeletionPending: Bool
}

public enum FileStoreEvent: Sendable {
    case changed(FileReference)
    case discoveryChanged(FileListing.Discovery)
    case issue(FileIssue)
}

/// A retained version that can be exported for review. IDs are valid for this store session.
public struct FileConflictVersion: Sendable {
    public enum Source: String, Sendable { case local, cloudCurrent, cloudConflict }
    public let id: String
    public let source: Source
    public let modifiedAt: Date?

    init(id: String, source: Source, modifiedAt: Date? = nil) {
        self.id = id; self.source = source; self.modifiedAt = modifiedAt
    }
}

/// Holds a local file stable until close(). Multiple readers can hold independent leases.
/// Do not edit or delete url directly. Close only after the consumer has stopped reading.
public final class FileAccess: Sendable {
    public let url: URL
    let token: UUID
    private let store: SwiftFileStore

    init(url: URL, token: UUID, store: SwiftFileStore) {
        self.url = url
        self.token = token
        self.store = store
    }

    public func close() async { await store.release(token) }

    deinit {
        let store = store
        let token = token
        Task { await store.release(token) }
    }
}
