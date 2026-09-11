import Foundation

/// Local attachment storage with automatic iCloud Drive replication.
/// Business associations are owned by the caller. All returned URLs are local Files URLs.
public actor SwiftFileStore {
    public nonisolated let rootPath: String
    public nonisolated let iCloudEnabled: Bool
    public nonisolated let scope: String
    /// The local files directory, including rootPath. Do not persist this absolute URL.
    /// New files written here must be finished and closed before registerFile(path:).
    public nonisolated let localRootURL: URL
    private let disk: LocalStorage
    private let namespaceLock: NamespaceLock
    private let cloud: (any CloudFiles)?
    private let automaticallySynchronize: Bool
    private var stopped = false
    private var running = false
    private var scheduled: Task<Void, Never>?
    private var needsAnotherPass = false
    private var leases: [UUID: String] = [:]
    private var transfers: Set<String> = []
    private var remote: [String: CloudItem] = [:]
    private var discovery: FileListing.Discovery
    private var lastIssue: FileIssue?
    private var subscribers: [UUID: AsyncStream<FileStoreEvent>.Continuation] = [:]
    private var retryDelay: Double = 2
    private var completedPasses = 0
    private var requestedDownloads: [String: Int] = [:]

    /// localDirectory optionally overrides the Application Support storage base.
    /// rootPath is a relative subdirectory, not an absolute filesystem path.
    public init(rootPath: String = "", iCloudEnabled: Bool = true,
                containerIdentifier: String? = nil, localDirectory: URL? = nil) async throws {
        try await self.init(rootPath: rootPath, iCloudEnabled: iCloudEnabled,
                            containerIdentifier: containerIdentifier, localDirectory: localDirectory,
                            driver: nil, automaticallySynchronize: true)
    }

    init(rootPath: String = "", iCloudEnabled: Bool = true, containerIdentifier: String? = nil,
         localDirectory: URL? = nil, driver: (any CloudFiles)?, automaticallySynchronize: Bool) async throws {
        try FilePaths.validate(rootPath, allowEmpty: true)
        self.rootPath = rootPath
        self.iCloudEnabled = iCloudEnabled
        self.automaticallySynchronize = automaticallySynchronize
        // Stable across enabling/disabling sync, distinct for different container/root scopes.
        scope = FilePaths.key("\(containerIdentifier ?? "<default>")\n\(rootPath)")
        let base = try localDirectory ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("SwiftFileStore")
        namespaceLock = try NamespaceLock(base: base, container: containerIdentifier ?? "<default>", rootPath: rootPath)
        disk = try LocalStorage(base: base, scope: scope, rootPath: rootPath)
        localRootURL = disk.filesRoot
        discovery = iCloudEnabled ? .unavailable : .disabled
        if iCloudEnabled {
            cloud = if let driver { driver } else {
                await NativeCloudFiles(containerIdentifier: containerIdentifier, rootPath: rootPath,
                    binding: disk.directory.appendingPathComponent("identity.archive"))
            }
        } else { cloud = nil }
        // An unacknowledged attempt must be reconciled, never blindly republished.
        for (path, entry) in disk.manifest.files where entry.state == .deleted {
            try? FilePaths.removeIfPresent(disk.url(path))
        }
        if automaticallySynchronize, let cloud {
            await cloud.start { [weak self] in Task { await self?.requestPass() } }
            requestPass()
        }
    }

    /// Create a reference for a path received from a business record on another device.
    public func reference(path: String) throws -> FileReference {
        try validate(path)
        return FileReference(scope: scope, path: path)
    }

    public func importFile(from sourceURL: URL, path: String? = nil) throws -> FileReference {
        try checkOpen()
        let ext = sourceURL.pathExtension
        let path = path ?? UUID().uuidString.lowercased() + (ext.isEmpty ? "" : ".\(ext)")
        try validate(path)
        _ = try disk.url(path)
        guard sourceURL.isFileURL else { throw FileStoreError.invalidPath(sourceURL.absoluteString) }
        try Task.checkCancellation()
        let staged = disk.staging.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staged) }
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        let resources = try sourceURL.resourceValues(forKeys: [.isRegularFileKey])
        guard resources.isRegularFile == true else { throw FileStoreError.invalidPath(sourceURL.path) }
        try FileManager.default.copyItem(at: sourceURL, to: staged)
        let digest = try FilePaths.digest(staged)
        if let existing = disk.manifest.files[path] {
            guard existing.state != .deleted, existing.digest == digest else { throw FileStoreError.conflict(path) }
            return FileReference(scope: scope, path: path)
        }
        // An untracked file or case/Unicode alias must not be silently replaced.
        guard !disk.exists(path) else { throw FileStoreError.conflict(path) }
        try Task.checkCancellation()
        let entry = StoredFile(origin: .local, digest: digest, state: iCloudEnabled ? .pending : .localOnly)
        try disk.install(staged, path: path, entry: entry)
        let file = FileReference(scope: scope, path: path)
        emit(.changed(file)); requestPass()
        return file
    }

    /// Registers a completed regular file already under localRootURL without copying or moving it.
    /// After registration, do not modify the file directly. Existing registrations retain their
    /// origin and sync state; changed content and deleted paths cannot be registered again.
    public func registerFile(path: String) throws -> FileReference {
        try checkOpen()
        return try registerFiles(paths: [path])[0]
    }

    /// Registers completed files under a local directory; an empty path selects localRootURL.
    /// Hidden entries are skipped. Symbolic links and unsupported file types are rejected.
    /// The batch commits atomically after all files pass validation. Empty directories have no
    /// registration of their own. This is a one-time scan, not a watch for future local writes.
    public func registerDirectory(path: String = "", recursive: Bool = true) throws -> [FileReference] {
        try checkOpen()
        try FilePaths.validate(path, allowEmpty: true)
        let directory = path.isEmpty ? disk.filesRoot : try disk.url(path)
        guard FileManager.default.fileExists(atPath: directory.path) else { throw FileStoreError.notFound }
        guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw FileStoreError.invalidPath(path)
        }
        var directories = [(path, directory)]
        var paths: [String] = []
        while let (parent, url) = directories.popLast() {
            try Task.checkCancellation()
            let children = try FileManager.default.contentsOfDirectory(at: url,
                includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            for child in children {
                let childPath = parent.isEmpty ? child.lastPathComponent : parent + "/" + child.lastPathComponent
                let checked = try disk.url(childPath) // Reject symlinks before inspecting their targets.
                if try checked.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                    if recursive { directories.append((childPath, checked)) }
                } else {
                    paths.append(childPath)
                }
            }
        }
        return try registerFiles(paths: paths.sorted())
    }

    private func registerFiles(paths: [String]) throws -> [FileReference] {
        var identities: [String: String] = [:]
        for path in disk.manifest.files.keys {
            identities[path.precomposedStringWithCanonicalMapping.lowercased()] = path
        }
        var entries: [String: StoredFile] = [:]
        for path in paths {
            try Task.checkCancellation()
            try validate(path)
            let normalized = path.precomposedStringWithCanonicalMapping.lowercased()
            if let other = identities[normalized], other != path { throw FileStoreError.conflict(path) }
            identities[normalized] = path
            if let entry = try registrationEntry(path: path) { entries[path] = entry }
        }
        try Task.checkCancellation()
        // Bytes are already installed by the caller; only the manifest needs an atomic commit.
        if !entries.isEmpty {
            try disk.set(entries)
            for path in entries.keys.sorted() { emit(.changed(FileReference(scope: scope, path: path))) }
            requestPass()
        }
        return paths.map { FileReference(scope: scope, path: $0) }
    }

    private func registrationEntry(path: String) throws -> StoredFile? {
        let url = try disk.url(path)
        let existing = disk.manifest.files[path]
        if existing?.state == .deleted || existing?.state == .conflict {
            throw FileStoreError.conflict(path)
        }
        guard disk.exists(path) else { throw FileStoreError.notFound }
        let resources = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard resources.isRegularFile == true else { throw FileStoreError.invalidPath(path) }
        let digest = try FilePaths.digest(url)
        if let existing {
            guard existing.digest == digest else { throw FileStoreError.conflict(path) }
            return nil
        }
        return StoredFile(origin: .local, digest: digest, state: iCloudEnabled ? .pending : .localOnly)
    }

    public func write(_ data: Data, path: String? = nil) throws -> FileReference {
        try checkOpen()
        let staged = disk.staging.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staged) }
        try data.write(to: staged, options: .atomic)
        return try importFile(from: staged, path: path ?? UUID().uuidString.lowercased())
    }

    public func url(for file: FileReference, timeout: Duration = .seconds(30)) async throws -> URL {
        try validate(file)
        let deadline = ContinuousClock.now.advanced(by: timeout)
        let initialPass = completedPasses
        requestedDownloads[file.path, default: 0] += 1
        defer {
            requestedDownloads[file.path, default: 1] -= 1
            if requestedDownloads[file.path] == 0 { requestedDownloads.removeValue(forKey: file.path) }
        }
        // Do not await the transfer itself: each waiter has its own timeout/cancellation.
        if !disk.exists(file.path), cloud != nil, !running {
            Task { [weak self] in await self?.synchronize() }
        }
        while true {
            try checkOpen()
            try Task.checkCancellation()
            let entry = disk.manifest.files[file.path]
            if entry?.state == .deleted { throw FileStoreError.notFound }
            if entry?.state == .conflict { throw FileStoreError.conflict(file.path) }
            if disk.exists(file.path) { return try disk.url(file.path) }
            guard cloud != nil else { throw FileStoreError.unavailable }
            if !running, completedPasses > initialPass, discovery == .unavailable { throw FileStoreError.unavailable }
            guard ContinuousClock.now < deadline else { throw FileStoreError.timedOut }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    public func open(_ file: FileReference, timeout: Duration = .seconds(30)) async throws -> FileAccess {
        _ = try await url(for: file, timeout: timeout)
        // Recheck after the suspension; delete may have been registered meanwhile.
        try checkOpen(); try validate(file)
        guard disk.manifest.files[file.path]?.state != .deleted, disk.exists(file.path) else { throw FileStoreError.notFound }
        if disk.manifest.files[file.path]?.state == .conflict { throw FileStoreError.conflict(file.path) }
        let token = UUID()
        leases[token] = file.path
        return FileAccess(url: try disk.url(file.path), token: token, store: self)
    }

    public func read(_ file: FileReference, timeout: Duration = .seconds(30)) async throws -> Data {
        let access = try await open(file, timeout: timeout)
        defer { release(access.token) }
        return try Data(contentsOf: access.url)
    }

    public func exportCopy(of file: FileReference, timeout: Duration = .seconds(30)) async throws -> URL {
        let access = try await open(file, timeout: timeout)
        defer { release(access.token) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID())")
            .appendingPathExtension(access.url.pathExtension)
        try FileManager.default.copyItem(at: access.url, to: url)
        return url
    }

    public func download(_ file: FileReference, timeout: Duration = .seconds(30)) async throws {
        _ = try await url(for: file, timeout: timeout)
    }

    /// Copies retained local bytes even if the file is conflicted or awaiting physical deletion.
    /// Useful for recovering content under a new unique path. The caller owns the export.
    public func exportRetainedCopy(of file: FileReference) throws -> URL {
        try checkOpen(); try validate(file)
        guard disk.exists(file.path) else { throw FileStoreError.notFound }
        let source = try disk.url(file.path)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("retained-\(UUID())")
            .appendingPathExtension(source.pathExtension)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    public func conflicts(of file: FileReference) async throws -> [FileConflictVersion] {
        try checkOpen(); try validate(file)
        var result: [FileConflictVersion] = disk.exists(file.path)
            ? [FileConflictVersion(id: "local", source: .local)] : []
        if let cloud { result += try await cloud.conflictVersions(file.path) }
        try checkOpen()
        return result
    }

    /// Review versions, import the desired bytes at a new path, then explicitly remove the old file.
    public func exportVersion(_ version: FileConflictVersion, of file: FileReference) async throws -> URL {
        try checkOpen(); try validate(file)
        if version.source == .local { return try exportRetainedCopy(of: file) }
        guard let cloud else { throw FileStoreError.unavailable }
        return try await cloud.exportVersion(version.id, path: file.path)
    }

    /// Releases only the system's iCloud-container cache. The stable App-local file is retained.
    /// It can be downloaded again by the system; this is not a permanent disk-size guarantee.
    public func evictCloudCache(for file: FileReference) async throws {
        try checkOpen(); try validate(file)
        guard disk.exists(file.path), let entry = disk.manifest.files[file.path],
              entry.state == .uploaded, !entry.deletePending, let cloud else { throw FileStoreError.unavailable }
        try await cloud.evict(file.path)
    }

    public func remove(_ file: FileReference) throws -> DeletionResult {
        try checkOpen(); try validate(file)
        let prior = disk.manifest.files[file.path]
        var entry = prior ?? StoredFile(origin: .cloud, digest: nil, state: .remoteOnly)
        if entry.state != .deleted {
            let neverPublished = entry.origin == .local && (entry.state == .pending || entry.state == .localOnly)
                && remote[file.path] == nil && !transfers.contains(file.path)
            entry.deletePending = !neverPublished
            entry.state = .deleted
            entry.revision = UUID()
            entry.issue = nil
            try disk.set(entry, for: file.path)
        }
        cleanup(file.path)
        emit(.changed(file)); requestPass()
        return DeletionResult(isRegistered: true, localCleanupPending: disk.exists(file.path),
                              cloudDeletionPending: entry.deletePending)
    }

    public func status(of file: FileReference) throws -> FileStatus {
        try checkOpen(); try validate(file)
        return status(file.path)
    }

    public func list(in path: String = "") throws -> FileListing {
        try checkOpen(); try FilePaths.validate(path, allowEmpty: true)
        let paths = Set(disk.manifest.files.keys).union(remote.keys).filter {
            (path.isEmpty || $0.hasPrefix(path + "/")) && disk.manifest.files[$0]?.state != .deleted
        }
        return FileListing(files: paths.sorted().map(status), discovery: discovery, issue: lastIssue)
    }

    public func events() -> AsyncStream<FileStoreEvent> {
        let id = UUID()
        let pair = AsyncStream<FileStoreEvent>.makeStream(bufferingPolicy: .bufferingNewest(128))
        if stopped { pair.continuation.finish(); return pair.stream }
        subscribers[id] = pair.continuation
        pair.continuation.yield(.discoveryChanged(discovery))
        pair.continuation.onTermination = { [weak self] _ in Task { await self?.unsubscribe(id) } }
        return pair.stream
    }

    /// Also call when the host app returns to the foreground.
    /// This checks pending work; it cannot force iCloud to finish a transfer.
    public func retryPendingOperations() async throws {
        try checkOpen()
        scheduled?.cancel(); scheduled = nil
        await synchronize()
    }

    public func waitUntilUploaded(_ file: FileReference, timeout: Duration = .seconds(30)) async throws {
        try validate(file)
        guard iCloudEnabled else { throw FileStoreError.unavailable }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        requestPass()
        while true {
            try checkOpen(); try Task.checkCancellation()
            if disk.manifest.files[file.path]?.state == .deleted { throw FileStoreError.notFound }
            // A disk checkpoint alone is not an upload acknowledgement for this session.
            if remote[file.path]?.uploaded == true, disk.manifest.files[file.path]?.state == .uploaded { return }
            guard ContinuousClock.now < deadline else { throw FileStoreError.timedOut }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Close before reopening the same scope. Active readers must be closed first.
    public func close() async throws {
        guard leases.isEmpty else { throw FileStoreError.fileInUse }
        stopped = true
        scheduled?.cancel(); scheduled = nil
        await cloud?.stop()
        // In-flight cloud work must finish before its source files can change under a new instance.
        while running {
            // Finish releasing the directory lock even if the caller cancels close().
            await Task.detached { try? await Task.sleep(for: .milliseconds(20)) }.value
        }
        for continuation in subscribers.values { continuation.finish() }
        subscribers.removeAll()
        disk.close()
        namespaceLock.close()
    }

    func release(_ token: UUID) {
        guard let path = leases.removeValue(forKey: token) else { return }
        cleanup(path)
        requestPass()
    }

    private func unsubscribe(_ id: UUID) { subscribers.removeValue(forKey: id) }
    private func emit(_ event: FileStoreEvent) { for subscriber in subscribers.values { subscriber.yield(event) } }
    private func validate(_ path: String) throws { try FilePaths.validate(path) }
    private func validate(_ file: FileReference) throws {
        guard file.scope == scope else { throw FileStoreError.wrongScope }
        try validate(file.path)
    }
    private func checkOpen() throws {
        guard !stopped else { throw FileStoreError.closed }
        try disk.recover()
    }
    private func used(_ path: String) -> Bool { leases.values.contains(path) || transfers.contains(path) }
    private func cleanup(_ path: String) {
        guard disk.manifest.files[path]?.state == .deleted, !used(path) else { return }
        do { try FilePaths.removeIfPresent(disk.url(path)) }
        catch { record(error, path: path) }
    }
    private func status(_ path: String) -> FileStatus {
        let entry = disk.manifest.files[path]
        let state: FileSyncState = if entry?.state == .uploaded, remote[path]?.uploaded != true {
            .handedOff // A historical checkpoint isn't current system acknowledgement.
        } else { entry?.state ?? .remoteOnly }
        return FileStatus(file: FileReference(scope: scope, path: path),
            isLocal: disk.exists(path), syncState: state,
            isInUse: leases.values.contains(path), issue: entry?.issue ?? remote[path]?.issue,
            uploadProgress: remote[path]?.uploadProgress, downloadProgress: remote[path]?.downloadProgress)
    }
    private func record(_ error: Error, path: String? = nil) {
        let issue = FileIssue(error)
        if let path, var entry = disk.manifest.files[path] {
            entry.issue = issue
            if issue.kind == .conflict, entry.state != .deleted { entry.state = .conflict }
            do { try disk.set(entry, for: path) } catch { lastIssue = FileIssue(error) }
        }
        lastIssue = issue
        emit(.issue(issue))
    }

    private func requestPass(after delay: Double = 0) {
        guard cloud != nil, automaticallySynchronize, !stopped else { return }
        if running { needsAnotherPass = true; return }
        if delay == 0 { scheduled?.cancel(); scheduled = nil }
        guard scheduled == nil else { return }
        scheduled = Task { [weak self] in
            do { if delay > 0 { try await Task.sleep(for: .seconds(delay)) } }
            catch { return }
            await self?.scheduledPass()
        }
    }
    private func scheduledPass() async { scheduled = nil; await synchronize() }

    private func synchronize() async {
        guard let cloud, !stopped else { return }
        guard !running else { needsAnotherPass = true; return }
        running = true
        needsAnotherPass = false
        defer {
            running = false
            completedPasses += 1
            if !stopped {
                // Bounded foreground retry; OS owns actual upload/download timing.
                requestPass(after: needsAnotherPass ? 1 : retryDelay)
            }
        }
        do {
            try disk.recover()
            let snapshot = try await cloud.snapshot()
            guard !stopped else { return }
            discovery = snapshot.ready ? .ready : .gathering
            emit(.discoveryChanged(discovery))
            guard snapshot.ready else { retryDelay = 2; return }
            lastIssue = nil
            remote = Dictionary(snapshot.items.map { ($0.path, $0) }, uniquingKeysWith: { _, last in last })
            // Explicit metadata removals only. A missing item in an initial query is not a deletion.
            for path in snapshot.removed {
                guard var entry = disk.manifest.files[path] else { continue }
                if entry.origin == .local && (entry.state == .pending || entry.state == .localOnly) { continue }
                entry.state = .deleted; entry.deletePending = false; entry.revision = UUID()
                try disk.set(entry, for: path)
                cleanup(path); emit(.changed(FileReference(scope: scope, path: path)))
            }
            var quotaBlocked = snapshot.items.contains(where: { $0.issue?.kind == .quota })
            for path in disk.manifest.files.keys.sorted() {
                guard !stopped else { return }
                guard var entry = disk.manifest.files[path] else { continue }
                if entry.state == .deleted {
                    cleanup(path)
                    if entry.deletePending {
                        do {
                            try await cloud.remove(path)
                            guard !stopped else { return }
                            entry = disk.manifest.files[path] ?? entry
                            entry.deletePending = false; entry.issue = nil
                            try disk.set(entry, for: path)
                        } catch { record(error, path: path) }
                    }
                    continue
                }
                guard entry.origin == .local, entry.state == .pending || entry.state == .localOnly else { continue }
                if quotaBlocked { continue }
                let revision = entry.revision
                entry.state = .uncertain // Persist before crossing the filesystem boundary.
                try disk.set(entry, for: path)
                transfers.insert(path)
                do {
                    try await cloud.publish(disk.url(path), path: path)
                    if !stopped, var current = disk.manifest.files[path], current.revision == revision {
                        current.state = .handedOff; current.issue = nil
                        try disk.set(current, for: path)
                    }
                } catch {
                    let underlying = (error as? PublicationNotStarted)?.underlying ?? error
                    // A quota rejection is retryable; unknown outcomes require reconciliation.
                    if (error is PublicationNotStarted || FileIssue(underlying).kind == .quota),
                       var current = disk.manifest.files[path], current.revision == revision {
                        quotaBlocked = FileIssue(underlying).kind == .quota
                        current.state = .pending
                        try disk.set(current, for: path)
                    }
                    record(underlying, path: path)
                }
                transfers.remove(path); cleanup(path)
            }
            // Downloads remain independent of failed uploads and deletes.
            let downloads = snapshot.items.sorted {
                let left = requestedDownloads[$0.path] != nil
                let right = requestedDownloads[$1.path] != nil
                return left == right ? $0.path < $1.path : left && !right
            }
            for item in downloads {
                guard !stopped else { return }
                do { try await receive(item, cloud: cloud) }
                catch { record(error, path: item.path) }
            }
            retryDelay = lastIssue == nil ? 15 : min(max(retryDelay * 2, 4), 300)
        } catch {
            discovery = .unavailable
            remote.removeAll()
            emit(.discoveryChanged(discovery))
            record(error)
            retryDelay = min(max(retryDelay * 2, 4), 300)
        }
    }

    private func receive(_ item: CloudItem, cloud: any CloudFiles) async throws {
        try validate(item.path)
        let existing = disk.manifest.files[item.path]
        guard existing?.state != .deleted else { return }
        if existing == nil {
            try disk.set(StoredFile(origin: .cloud, digest: nil, state: .remoteOnly), for: item.path)
        }
        if let issue = item.issue { lastIssue = issue; emit(.issue(issue)) }
        if item.conflict { throw FileStoreError.conflict(item.path) }
        if !item.version.isEmpty, existing?.cloudVersion == item.version,
           existing?.state == .uploaded || existing?.state == .handedOff, disk.exists(item.path) {
            if item.uploaded, var entry = disk.manifest.files[item.path], entry.state == .handedOff {
                entry.state = .uploaded; entry.issue = nil
                try disk.set(entry, for: item.path)
            }
            return
        }
        if used(item.path) { return } // Last close schedules a fresh fetch; no third permanent copy.
        let revision = disk.manifest.files[item.path]?.revision
        guard let temporary = try await cloud.fetch(item.path) else { return }
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await cloud.verifyAccount()
        guard !stopped, !used(item.path), let current = disk.manifest.files[item.path],
              current.revision == revision, current.state != .deleted else { return }
        let digest = try FilePaths.digest(temporary)
        if let previous = current.digest, previous != digest { throw FileStoreError.conflict(item.path) }
        var entry = current
        entry.digest = digest; entry.issue = nil
        entry.cloudVersion = item.version
        entry.state = item.uploaded ? .uploaded : .handedOff
        if disk.exists(item.path) {
            guard try FilePaths.digest(disk.url(item.path)) == digest else { throw FileStoreError.conflict(item.path) }
            try disk.set(entry, for: item.path)
        } else { try disk.install(temporary, path: item.path, entry: entry) }
        emit(.changed(FileReference(scope: scope, path: item.path)))
    }
}
