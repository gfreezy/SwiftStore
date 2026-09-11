import Foundation

struct CloudItem: Sendable {
    let path: String
    var downloaded = true
    var uploaded = false
    var conflict = false
    var issue: FileIssue?
    var version: String = ""
    var uploadProgress: Double?
    var downloadProgress: Double?
}

struct CloudSnapshot: Sendable {
    var ready: Bool
    var items: [CloudItem]
    var removed: Set<String> = []
}

/// The adapter knows no cloud write was attempted, so retrying cannot resurrect an old handoff.
struct PublicationNotStarted: Error {
    let underlying: any Error
}

/// Internal seam for deterministic filesystem tests, not a public backend API.
protocol CloudFiles: Sendable {
    func snapshot() async throws -> CloudSnapshot
    func verifyAccount() async throws
    func publish(_ source: URL, path: String) async throws
    /// Returns an owned temporary copy, or nil after requesting a download.
    func fetch(_ path: String) async throws -> URL?
    func remove(_ path: String) async throws
    func start(_ changed: @escaping @Sendable () -> Void) async
    func stop() async
    func conflictVersions(_ path: String) async throws -> [FileConflictVersion]
    func exportVersion(_ id: String, path: String) async throws -> URL
    func evict(_ path: String) async throws
}

extension CloudFiles {
    func conflictVersions(_ path: String) async throws -> [FileConflictVersion] { [] }
    func exportVersion(_ id: String, path: String) async throws -> URL { throw FileStoreError.unavailable }
    func evict(_ path: String) async throws { throw FileStoreError.unavailable }
}

#if os(iOS) || os(macOS)
@MainActor
private enum CloudIdentity {
    static func verify(binding: URL) throws {
        guard let token = FileManager.default.ubiquityIdentityToken else { throw FileStoreError.unavailable }
        if FileManager.default.fileExists(atPath: binding.path) {
            let decoder = try NSKeyedUnarchiver(forReadingFrom: Data(contentsOf: binding))
            decoder.requiresSecureCoding = false
            defer { decoder.finishDecoding() }
            guard let previous = decoder.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? NSObject else {
                throw FileStoreError.corruptState
            }
            guard token.isEqual(previous) else { throw FileStoreError.accountMismatch }
        } else {
            try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
                .write(to: binding, options: .atomic)
        }
    }
}

@MainActor
private final class CloudMetadata: NSObject {
    private var query: NSMetadataQuery?
    private var root: URL?
    private var ready = false
    private var removed: Set<String> = []
    private var changed: (@Sendable () -> Void)?

    func start(_ changed: @escaping @Sendable () -> Void) {
        self.changed = changed
        NotificationCenter.default.removeObserver(self)
        if let query { query.stop(); self.query = nil; root = nil; ready = false }
        NotificationCenter.default.addObserver(self, selector: #selector(identityChanged),
            name: .NSUbiquityIdentityDidChange, object: nil)
    }

    func snapshot(root: URL) throws -> CloudSnapshot {
        if self.root != root || query == nil {
            if let query {
                query.stop()
                NotificationCenter.default.removeObserver(self, name: nil, object: query)
            }
            self.root = root
            ready = false
            removed.removeAll()
            let query = NSMetadataQuery()
            query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
            query.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, "*")
            query.notificationBatchingInterval = 1
            NotificationCenter.default.addObserver(self, selector: #selector(gathered), name: .NSMetadataQueryDidFinishGathering, object: query)
            NotificationCenter.default.addObserver(self, selector: #selector(updated), name: .NSMetadataQueryDidUpdate, object: query)
            self.query = query
            guard query.start() else { self.query = nil; throw FileStoreError.unavailable }
        }
        guard let query, ready else { return CloudSnapshot(ready: false, items: []) }
        query.disableUpdates()
        defer { query.enableUpdates() }
        let items = query.results.compactMap { result -> CloudItem? in
            guard let item = result as? NSMetadataItem,
                  let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  let path = FilePaths.relative(url, in: root),
                  (item.value(forAttribute: NSMetadataItemContentTypeKey) as? String) != "public.folder",
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { return nil }
            let downloaded = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            let error = (item.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) as? NSError)
                ?? (item.value(forAttribute: NSMetadataUbiquitousItemDownloadingErrorKey) as? NSError)
            let date = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
            let size = item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber
            return CloudItem(path: path,
                downloaded: downloaded == NSMetadataUbiquitousItemDownloadingStatusCurrent,
                uploaded: item.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? Bool ?? false,
                conflict: item.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? Bool ?? false,
                issue: error.map(FileIssue.init),
                version: "\(date?.timeIntervalSince1970 ?? 0)/\(size?.int64Value ?? 0)",
                uploadProgress: (item.value(forAttribute: NSMetadataUbiquitousItemPercentUploadedKey) as? Double).map { $0 / 100 },
                downloadProgress: (item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double).map { $0 / 100 })
        }
        // Keep deletion observations until this query session ends. Consumers are idempotent.
        return CloudSnapshot(ready: true, items: items, removed: removed.subtracting(items.map(\.path)))
    }

    func stop() {
        query?.stop(); query = nil; root = nil; ready = false; removed.removeAll()
        NotificationCenter.default.removeObserver(self)
        changed = nil
    }

    @objc private func gathered(_ notification: Notification) { ready = true; changed?() }

    @objc private func updated(_ notification: Notification) {
        if let root, let items = notification.userInfo?[NSMetadataQueryUpdateRemovedItemsKey] as? [NSMetadataItem] {
            for item in items {
                if let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                   let path = FilePaths.relative(url, in: root) { removed.insert(path) }
            }
        }
        changed?()
    }

    @objc private func identityChanged(_ notification: Notification) {
        query?.stop()
        if let query { NotificationCenter.default.removeObserver(self, name: nil, object: query) }
        query = nil; root = nil; ready = false; removed.removeAll()
        changed?()
    }
}

actor NativeCloudFiles: CloudFiles {
    private let containerIdentifier: String?
    private let rootPath: String
    private let binding: URL
    private let metadata: CloudMetadata
    private var retainedVersions: [String: (path: String, version: NSFileVersion)] = [:]

    init(containerIdentifier: String?, rootPath: String, binding: URL) async {
        self.containerIdentifier = containerIdentifier
        self.rootPath = rootPath
        self.binding = binding
        metadata = await CloudMetadata()
    }

    func start(_ changed: @escaping @Sendable () -> Void) async { await metadata.start(changed) }
    func stop() async { retainedVersions.removeAll(); await metadata.stop() }
    func verifyAccount() async throws { try await CloudIdentity.verify(binding: binding) }

    private func root() async throws -> URL {
        try await verifyAccount()
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            throw FileStoreError.unavailable
        }
        let base = container.appendingPathComponent("Attachments", isDirectory: true)
        let result = rootPath.isEmpty ? base : try FilePaths.url(rootPath, in: base)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        return result
    }

    func snapshot() async throws -> CloudSnapshot {
        let root = try await root()
        let snapshot = try await metadata.snapshot(root: root)
        try await verifyAccount()
        return snapshot
    }

    private static func coordinate(_ url: URL, write: Bool, deleting: Bool = false, body: (URL) throws -> Void) throws {
        var coordination: NSError?
        var failure: Error?
        let accessor: (URL) -> Void = { location in
            do { try body(location) } catch { failure = error }
        }
        let coordinator = NSFileCoordinator()
        if write {
            coordinator.coordinate(writingItemAt: url, options: deleting ? .forDeleting : [], error: &coordination, byAccessor: accessor)
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordination, byAccessor: accessor)
        }
        if let coordination { throw coordination }
        if let failure { throw failure }
    }

    private static func requireCurrent(_ url: URL) throws {
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if values?.isUbiquitousItem == true, values?.ubiquitousItemDownloadingStatus != .current {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            throw FileStoreError.unavailable
        }
        if NSFileVersion.unresolvedConflictVersionsOfItem(at: url)?.isEmpty == false {
            throw FileStoreError.conflict(url.lastPathComponent)
        }
    }

    func publish(_ source: URL, path: String) async throws {
        let destination: URL
        do { destination = try FilePaths.url(path, in: await root()) }
        catch { throw PublicationNotStarted(underlying: error) }
        try Self.coordinate(destination, write: true) { url in
            do { try Self.requireCurrent(url) }
            catch { throw PublicationNotStarted(underlying: error) }
            if FileManager.default.fileExists(atPath: url.path) {
                guard try FilePaths.digest(source) == FilePaths.digest(url) else { throw FileStoreError.conflict(path) }
            } else { try FilePaths.copy(source, to: url) }
        }
        try await verifyAccount()
    }

    func fetch(_ path: String) async throws -> URL? {
        let source = try FilePaths.url(path, in: await root())
        do { try Self.requireCurrent(source) }
        catch FileStoreError.unavailable { return nil }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("icloud-file-\(UUID())")
        do {
            try Self.coordinate(source, write: false) { url in
                try Self.requireCurrent(url)
                try FileManager.default.copyItem(at: url, to: temporary)
            }
            try await verifyAccount()
            return temporary
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    func remove(_ path: String) async throws {
        let url = try FilePaths.url(path, in: await root())
        try Self.coordinate(url, write: true, deleting: true) { location in
            // Missing metadata is not a server acknowledgement. Keep the request pending.
            guard FileManager.default.fileExists(atPath: location.path)
                || FileManager.default.isUbiquitousItem(at: location) else { throw FileStoreError.unavailable }
            try FileManager.default.removeItem(at: location)
        }
        try await verifyAccount()
    }

    func conflictVersions(_ path: String) async throws -> [FileConflictVersion] {
        let url = try FilePaths.url(path, in: await root())
        var versions: [NSFileVersion] = []
        try Self.coordinate(url, write: false) { location in
            versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: location) ?? []
        }
        retainedVersions = retainedVersions.filter { $0.value.path != path }
        var result = [FileConflictVersion(id: "cloud-current", source: .cloudCurrent)]
        for version in versions {
            let id = UUID().uuidString
            retainedVersions[id] = (path, version)
            result.append(FileConflictVersion(id: id, source: .cloudConflict, modifiedAt: version.modificationDate))
        }
        return result
    }

    func exportVersion(_ id: String, path: String) async throws -> URL {
        let root = try await root()
        let source: URL
        if id == "cloud-current" { source = try FilePaths.url(path, in: root) }
        else {
            guard let retained = retainedVersions[id], retained.path == path else { throw FileStoreError.notFound }
            source = retained.version.url
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("icloud-version-\(UUID())")
        do {
            try Self.coordinate(source, write: false) { location in
                try FileManager.default.copyItem(at: location, to: temporary)
            }
            try await verifyAccount()
            return temporary
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    func evict(_ path: String) async throws {
        let url = try FilePaths.url(path, in: await root())
        let values = try url.resourceValues(forKeys: [.ubiquitousItemIsUploadedKey, .ubiquitousItemHasUnresolvedConflictsKey])
        guard values.ubiquitousItemIsUploaded == true, values.ubiquitousItemHasUnresolvedConflicts != true else {
            throw FileStoreError.unavailable
        }
        // This system API coordinates internally; do not wrap it in a coordinated write.
        try FileManager.default.evictUbiquitousItem(at: url)
    }
}
#else
actor NativeCloudFiles: CloudFiles {
    init(containerIdentifier: String?, rootPath: String, binding: URL) async {}
    func start(_ changed: @escaping @Sendable () -> Void) async {}
    func stop() async {}
    func verifyAccount() throws { throw FileStoreError.unavailable }
    func snapshot() throws -> CloudSnapshot { throw FileStoreError.unavailable }
    func publish(_ source: URL, path: String) throws { throw FileStoreError.unavailable }
    func fetch(_ path: String) throws -> URL? { throw FileStoreError.unavailable }
    func remove(_ path: String) throws { throw FileStoreError.unavailable }
}
#endif
