import Foundation
@_exported import SwiftStoreSync
@_exported import SwiftStoreCore

/// The v1 path selects the wire protocol. Scope and database identity are
/// common request metadata, not duplicated in every body.
public struct HTTPSyncPushRequest: Codable, Sendable {
    public let changes: [SyncChange]

    public init(changes: [SyncChange]) { self.changes = changes }

    private enum CodingKeys: String, CodingKey { case changes }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        changes = try values.decode([HTTPSyncRecord].self, forKey: .changes).map { try $0.decodeChange() }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(changes.map { try HTTPSyncRecord(change: $0) }, forKey: .changes)
    }
}

/// Key-level correction: the server does not identify individual modifications.
/// The client associates the key with this batch's local changes; sequence is
/// the minimum committed version needed to resolve them through pull or lookup.
public struct HTTPSyncRejection: Codable, Sendable {
    public let key: String
    public let sequence: Int64

    public init(key: String, sequence: Int64) {
        self.key = key
        self.sequence = sequence
    }
}

/// HTTP 200 confirms the whole submitted batch, including rejected changes.
public struct HTTPSyncPushResponse: Codable, Sendable {
    public let rejected: [HTTPSyncRejection]
    public init(rejected: [HTTPSyncRejection]) { self.rejected = rejected }
}

public struct HTTPSyncPullResponse: Codable, Sendable {
    public let changes: [HTTPSyncRecord]
    public let cursor: Int64
    public let hasMore: Bool

    public init(changes: [HTTPSyncRecord], cursor: Int64, hasMore: Bool) {
        self.changes = changes
        self.cursor = cursor
        self.hasMore = hasMore
    }
}

public struct HTTPSyncLookupRequest: Codable, Sendable {
    public let keys: [String]
    public init(keys: [String]) { self.keys = keys }
}

public struct HTTPSyncLookupResponse: Codable, Sendable {
    public let records: [HTTPSyncRecord]
    public init(records: [HTTPSyncRecord]) { self.records = records }
}

public enum HTTPSyncError: Error, LocalizedError {
    case invalidConfiguration(String)
    case invalidResponse
    case httpStatus(Int)
    case stateIdentityMismatch
    case serverIdentityChanged
    case stopped
    case busy

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason): return "Invalid HTTP sync configuration: \(reason)"
        case .invalidResponse: return "Invalid HTTP sync response; pending work was retained"
        case .httpStatus(let status): return "HTTP sync failed with status \(status); pending work was retained"
        case .stateIdentityMismatch: return "Sync journal belongs to another endpoint, namespace, or device"
        case .serverIdentityChanged: return "Sync server database identity changed; restore the server database or explicitly configure a new sync identity"
        case .stopped: return "HTTP sync transport is stopped"
        case .busy: return "HTTP sync cycle already in progress"
        }
    }
}

public struct HTTPSyncConfiguration: Sendable {
    public let serverURL: URL
    public let namespace: String
    public let bearerToken: String
    /// Dedicated file for this endpoint + namespace + device. Never share between live transports.
    public let stateURL: URL
    public let batchSize: Int
    public let pollInterval: TimeInterval?
    public let ntpToleranceMs: Int64
    public let allowInsecureHTTP: Bool

    public init(serverURL: URL, namespace: String, bearerToken: String, stateURL: URL,
                batchSize: Int = 100, pollInterval: TimeInterval? = 30,
                ntpToleranceMs: Int64 = 5000, allowInsecureHTTP: Bool = false) {
        self.serverURL = serverURL
        self.namespace = namespace
        self.bearerToken = bearerToken
        self.stateURL = stateURL
        self.batchSize = batchSize
        self.pollInterval = pollInterval
        self.ntpToleranceMs = ntpToleranceMs
        self.allowInsecureHTTP = allowInsecureHTTP
    }

    func validate() throws {
        guard (1...500).contains(batchSize), !namespace.isEmpty, namespace.utf8.count <= 200,
              !bearerToken.isEmpty, !bearerToken.contains(where: { $0.isNewline }),
              stateURL.isFileURL, ntpToleranceMs > 0,
              pollInterval.map({ $0.isFinite && $0 >= 1 && $0 <= 86_400 }) ?? true,
              serverURL.host != nil, serverURL.user == nil, serverURL.password == nil,
              serverURL.query == nil, serverURL.fragment == nil,
              serverURL.scheme == "https" || (allowInsecureHTTP && serverURL.scheme == "http") else {
            throw HTTPSyncError.invalidConfiguration("Use HTTPS, a token, a dedicated state file, batch size 1...500, and positive time tolerance. HTTP requires explicit opt-in.")
        }
    }
}
