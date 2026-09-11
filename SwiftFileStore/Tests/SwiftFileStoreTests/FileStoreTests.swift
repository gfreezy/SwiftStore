import Foundation
import Testing
@testable import SwiftFileStore

actor TestCloud: CloudFiles {
    let directory: URL
    var available = true
    var accountMatches = true
    var full = false
    var ready = true
    var items: [String: CloudItem] = [:]
    var removed: Set<String> = []
    var publishes = 0
    var fetches = 0
    var deletes = 0
    var callback: (@Sendable () -> Void)?
    var suspendedFetch: CheckedContinuation<Void, Never>?
    var pauseFetch = false
    var rejectNextPublication = false

    init(_ directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func configure(available: Bool? = nil, accountMatches: Bool? = nil, full: Bool? = nil, ready: Bool? = nil) {
        if let available { self.available = available }
        if let accountMatches { self.accountMatches = accountMatches }
        if let full { self.full = full }
        if let ready { self.ready = ready }
    }
    func verifyAccount() throws {
        guard available else { throw FileStoreError.unavailable }
        guard accountMatches else { throw FileStoreError.accountMismatch }
    }
    func snapshot() throws -> CloudSnapshot {
        try verifyAccount()
        return CloudSnapshot(ready: ready, items: Array(items.values), removed: removed)
    }
    func start(_ changed: @escaping @Sendable () -> Void) { callback = changed }
    func stop() { callback = nil }
    func publish(_ source: URL, path: String) throws {
        if rejectNextPublication {
            rejectNextPublication = false
            throw PublicationNotStarted(underlying: FileStoreError.unavailable)
        }
        try verifyAccount()
        if full { throw CocoaError(.ubiquitousFileNotUploadedDueToQuota) }
        publishes += 1
        let url = try FilePaths.url(path, in: directory)
        if FileManager.default.fileExists(atPath: url.path) {
            guard try FilePaths.digest(source) == FilePaths.digest(url) else { throw FileStoreError.conflict(path) }
        } else { try FilePaths.copy(source, to: url) }
        items[path] = CloudItem(path: path, uploaded: true, version: UUID().uuidString)
        removed.remove(path)
    }
    func fetch(_ path: String) async throws -> URL? {
        try verifyAccount()
        fetches += 1
        if pauseFetch { await withCheckedContinuation { suspendedFetch = $0 } }
        guard items[path]?.downloaded == true else { return nil }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: FilePaths.url(path, in: directory), to: temp)
        return temp
    }
    func remove(_ path: String) throws {
        try verifyAccount()
        deletes += 1
        try FilePaths.removeIfPresent(FilePaths.url(path, in: directory))
        items.removeValue(forKey: path); removed.insert(path)
    }
    func seed(_ value: String, path: String) throws {
        let url = try FilePaths.url(path, in: directory)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: url)
        items[path] = CloudItem(path: path, uploaded: true, version: UUID().uuidString)
        removed.remove(path)
    }
    func beginPausingFetch() { pauseFetch = true }
    func resumeFetch() { pauseFetch = false; suspendedFetch?.resume(); suspendedFetch = nil }
    func isFetchingPaused() -> Bool { suspendedFetch != nil }
    func notifyChange() { callback?() }
    func rejectPublicationOnce() { rejectNextPublication = true }
}

struct FileStoreTests {
    func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("file-store-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    func store(_ root: URL, cloud: TestCloud? = nil, enabled: Bool = false, path: String = "") async throws -> SwiftFileStore {
        try await SwiftFileStore(rootPath: path, iCloudEnabled: enabled,
            localDirectory: root, driver: cloud, automaticallySynchronize: false)
    }

    @Test func customPathLocalURLAndRestart() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try await store(root, path: "Reed")
        let file = try await first.write(Data("book".utf8), path: "books/a.pdf")
        let url = try await first.url(for: file)
        #expect(url.path.hasSuffix("/Files/Reed/books/a.pdf"))
        #expect(try await first.read(file) == Data("book".utf8))
        try await first.close()
        let reopened = try await store(root, path: "Reed")
        #expect(try await reopened.url(for: file) == url)
        #expect(try await reopened.read(file) == Data("book".utf8))
        try await reopened.close()
    }

    @Test func directoryRegistrationSupportsRecursionAndSkipsHiddenEntries() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let cloud = try TestCloud(root.appendingPathComponent("cloud"))
        let files = try await store(root, cloud: cloud, enabled: true, path: "Reed")
        for path in ["books/a.pdf", "books/sub/b.pdf", "books/.DS_Store", "books/.hidden/c.pdf", "outside.pdf"] {
            let url = files.localRootURL.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(path.utf8).write(to: url)
        }
        let first = try await files.registerDirectory(path: "books", recursive: false)
        #expect(first.map(\.path) == ["books/a.pdf"])
        let recursive = try await files.registerDirectory(path: "books")
        #expect(recursive.map(\.path) == ["books/a.pdf", "books/sub/b.pdf"])
        #expect(try await files.registerDirectory(path: "books") == recursive)
        try await files.retryPendingOperations()
        #expect(await cloud.publishes == 2)
        #expect(try await files.read(recursive[1]) == Data("books/sub/b.pdf".utf8))
        let all = try await files.registerDirectory()
        #expect(all.map(\.path) == ["books/a.pdf", "books/sub/b.pdf", "outside.pdf"])
        try await files.close()
    }

    @Test func directoryRegistrationDoesNotPartiallyCommitOnConflict() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let files = try await store(root)
        let existing = try await files.write(Data("original".utf8), path: "books/z.pdf")
        let added = files.localRootURL.appendingPathComponent("books/a.pdf")
        let changed = try await files.url(for: existing)
        try Data("new".utf8).write(to: added)
        try Data("changed".utf8).write(to: changed)
        await #expect(throws: FileStoreError.conflict("books/z.pdf")) {
            _ = try await files.registerDirectory(path: "books")
        }
        #expect(try await files.list().files.map(\.file.path) == ["books/z.pdf"])
        #expect(try Data(contentsOf: added) == Data("new".utf8))
        try await files.close()
        let reopened = try await store(root)
        #expect(try await reopened.list().files.map(\.file.path) == ["books/z.pdf"])
        try Data("original".utf8).write(to: changed)
        #expect(try await reopened.registerDirectory(path: "books").map(\.path) == ["books/a.pdf", "books/z.pdf"])
        try await reopened.close()
    }

    @Test func directoryRegistrationValidatesDirectoriesAndRejectsSymlinks() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let files = try await store(root)
        #expect(try await files.registerDirectory().isEmpty)
        for path in ["../escape", "/absolute", "a//b"] {
            await #expect(throws: FileStoreError.invalidPath(path)) {
                _ = try await files.registerDirectory(path: path)
            }
        }
        await #expect(throws: FileStoreError.notFound) { _ = try await files.registerDirectory(path: "missing") }
        try Data().write(to: files.localRootURL.appendingPathComponent("file"))
        await #expect(throws: FileStoreError.invalidPath("file")) { _ = try await files.registerDirectory(path: "file") }
        let empty = files.localRootURL.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(try await files.registerDirectory(path: "empty").isEmpty)
        try FileManager.default.createSymbolicLink(at: empty.appendingPathComponent("link"), withDestinationURL: root)
        await #expect(throws: FileStoreError.invalidPath("empty/link")) {
            _ = try await files.registerDirectory()
        }
        #expect(try await files.list().files.isEmpty)
        try await files.close()
    }

    @Test func registrationKeepsExistingFileAndPersistsUploadIntent() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let cloud = try TestCloud(root.appendingPathComponent("cloud"))
        await cloud.configure(available: false)
        let files = try await store(root, cloud: cloud, enabled: true, path: "Reed")
        let path = "books/existing.pdf"
        let url = files.localRootURL.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("existing book".utf8).write(to: url)
        let inode = try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? NSNumber
        let file = try await files.registerFile(path: path)
        #expect(try await files.url(for: file) == url)
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? NSNumber == inode)
        #expect(try await files.registerFile(path: path) == file)
        try await files.retryPendingOperations()
        #expect(try await files.status(of: file).syncState == .pending)
        #expect(await cloud.publishes == 0)
        try await files.close()
        let reopened = try await store(root, cloud: cloud, enabled: true, path: "Reed")
        #expect(try await reopened.read(file) == Data("existing book".utf8))
        await cloud.configure(available: true)
        try await reopened.retryPendingOperations()
        #expect(await cloud.publishes == 1)
        #expect(try await reopened.url(for: file) == url)
        try await reopened.close()
    }

    @Test func registrationRejectsInvalidMissingAndChangedFiles() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let files = try await store(root)
        for path in ["../escape", "/absolute", "", "a//b"] {
            await #expect(throws: FileStoreError.invalidPath(path)) {
                _ = try await files.registerFile(path: path)
            }
        }
        await #expect(throws: FileStoreError.notFound) { _ = try await files.registerFile(path: "missing") }
        let directory = files.localRootURL.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        await #expect(throws: FileStoreError.invalidPath("folder")) { _ = try await files.registerFile(path: "folder") }
        try FileManager.default.createSymbolicLink(at: files.localRootURL.appendingPathComponent("link"), withDestinationURL: root)
        await #expect(throws: FileStoreError.invalidPath("link/outside")) {
            _ = try await files.registerFile(path: "link/outside")
        }
        let url = files.localRootURL.appendingPathComponent("book")
        try Data("original".utf8).write(to: url)
        let file = try await files.registerFile(path: "book")
        #expect(try await files.status(of: file).syncState == .localOnly)
        await #expect(throws: FileStoreError.conflict("BOOK")) { _ = try await files.registerFile(path: "BOOK") }
        try Data("changed".utf8).write(to: url)
        await #expect(throws: FileStoreError.conflict("book")) { _ = try await files.registerFile(path: "book") }
        try Data("original".utf8).write(to: url)
        #expect(try await files.registerFile(path: "book") == file)
        let access = try await files.open(file)
        _ = try await files.remove(file)
        await #expect(throws: FileStoreError.conflict("book")) { _ = try await files.registerFile(path: "book") }
        await access.close()
        try await files.close()
        await #expect(throws: FileStoreError.closed) { _ = try await files.registerFile(path: "book") }
    }

    @Test func registeringDownloadedFilesDoesNotCreateUploadIntent() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let cloud = try TestCloud(root.appendingPathComponent("cloud"))
        try await cloud.seed("downloaded", path: "book")
        let files = try await store(root, cloud: cloud, enabled: true)
        try await files.retryPendingOperations()
        let file = try await files.registerFile(path: "book")
        #expect(try await files.status(of: file).syncState == .uploaded)
        try await files.close()
        // An empty initial query is not evidence that a downloaded copy should be uploaded.
        let emptyCloud = try TestCloud(root.appendingPathComponent("empty-cloud"))
        let reopened = try await store(root, cloud: emptyCloud, enabled: true)
        #expect(try await reopened.registerFile(path: "book") == file)
        try await reopened.retryPendingOperations()
        #expect(await emptyCloud.publishes == 0)
        #expect(try await reopened.read(file) == Data("downloaded".utf8))
        try await reopened.close()
    }

    @Test func pathTraversalScopeAndDuplicateWriterAreRejected() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let files = try await store(root)
        for path in ["../escape", "/absolute", "a//b", "a/../b", "a/", ""] {
            await #expect(throws: FileStoreError.invalidPath(path)) {
                _ = try await files.write(Data(), path: path)
            }
        }
        await #expect(throws: FileStoreError.alreadyOpen) { _ = try await store(root) }
        await #expect(throws: FileStoreError.wrongScope) {
            _ = try await files.url(for: FileReference(scope: "other", path: "a"))
        }
        let localRoot = root.appendingPathComponent(files.scope).appendingPathComponent("Files")
        try FileManager.default.createSymbolicLink(at: localRoot.appendingPathComponent("escape"), withDestinationURL: root)
        await #expect(throws: FileStoreError.invalidPath("escape/file")) {
            _ = try await files.write(Data(), path: "escape/file")
        }
        let valid = try await files.write(Data("valid".utf8), path: "valid")
        #expect(try await files.read(valid) == Data("valid".utf8))
        try await files.close()
    }

    @Test func overlappingRootsCannotWriteTheSameCloudNamespace() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try await store(root, path: "Reed")
        await #expect(throws: FileStoreError.alreadyOpen) { _ = try await store(root, path: "Reed/books") }
        await #expect(throws: FileStoreError.alreadyOpen) { _ = try await store(root, path: "reed") }
        let sibling = try await store(root, path: "Other")
        try await sibling.close()
        try await first.close()
        let rootStore = try await store(root)
        try await rootStore.close()
    }

    @Test func metadataNotificationsAutomaticallyInstallFilesWithoutExplicitReads() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let cloud = try TestCloud(root.appendingPathComponent("cloud"))
        try await cloud.seed("first", path: "first")
        let files = try await SwiftFileStore(iCloudEnabled: true, localDirectory: root,
            driver: cloud, automaticallySynchronize: true)
        let first = try await files.reference(path: "first")
        try await waitUntilLocal(first, store: files)
        try await cloud.seed("second", path: "second")
        await cloud.notifyChange()
        let second = try await files.reference(path: "second")
        try await waitUntilLocal(second, store: files)
        #expect(await cloud.publishes == 0)
        try await files.close()
    }

    @Test func failureBeforeCloudWriteAutomaticallyRemainsRetryable() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let cloud = try TestCloud(root.appendingPathComponent("cloud"))
        let files = try await store(root, cloud: cloud, enabled: true)
        let file = try await files.write(Data("pending".utf8), path: "book")
        await cloud.rejectPublicationOnce()
        try await files.retryPendingOperations()
        #expect(try await files.status(of: file).syncState == .pending)
        try await files.retryPendingOperations()
        #expect(await cloud.publishes == 1)
        try await files.close()
    }

    @Test func offlineSaveThenUploadKeepsTheSameLocalURL() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let cloud = try TestCloud(root.appendingPathComponent("cloud"))
        await cloud.configure(available: false)
        let files = try await store(root, cloud: cloud, enabled: true)
        let file = try await files.write(Data("offline".utf8), path: "book")
        let before = try await files.url(for: file)
        try await files.retryPendingOperations()
        #expect(try await files.read(file) == Data("offline".utf8))
        #expect(await cloud.publishes == 0)
        await cloud.configure(available: true)
        try await files.retryPendingOperations()
        try await files.retryPendingOperations()
        #expect(try await files.status(of: file).syncState == .uploaded)
        #expect(try await files.url(for: file) == before)
        #expect(FileManager.default.fileExists(atPath: before.path))
        try await files.close()
    }

    @Test func automaticReceptionDoesNotGenerateUploadsAndDeletionWaitsForReaders() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let cloud = try TestCloud(root.appendingPathComponent("cloud"))
        try await cloud.seed("remote", path: "audio/a.m4a")
        let files = try await store(root, cloud: cloud, enabled: true)
        try await files.retryPendingOperations()
        let file = try await files.reference(path: "audio/a.m4a")
        let first = try await files.open(file)
        let second = try await files.open(file)
        #expect(try String(contentsOf: first.url, encoding: .utf8) == "remote")
        try await cloud.remove(file.path)
        try await files.retryPendingOperations()
        #expect(try await files.list().files.isEmpty)
        #expect(FileManager.default.fileExists(atPath: first.url.path))
        await first.close()
        #expect(FileManager.default.fileExists(atPath: second.url.path))
        await second.close(); await second.close()
        #expect(!FileManager.default.fileExists(atPath: second.url.path))
        try await files.retryPendingOperations()
        #expect(await cloud.publishes == 0)
        try await files.close()
        let reopened = try await store(root, cloud: cloud, enabled: true)
        try await reopened.retryPendingOperations()
        #expect(await cloud.publishes == 0)
        try await reopened.close()
    }

    @Test func quotaDoesNotPreventLocalSaveOrOtherDownloads() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let cloud = try TestCloud(root.appendingPathComponent("cloud"))
        await cloud.configure(full: true)
        try await cloud.seed("download", path: "remote")
        let files = try await store(root, cloud: cloud, enabled: true)
        let local = try await files.write(Data("new".utf8), path: "local")
        try await files.retryPendingOperations()
        #expect(try await files.status(of: local).issue?.kind == .quota)
        #expect(try await files.read(local) == Data("new".utf8))
        let remote = try await files.reference(path: "remote")
        #expect(try await files.read(remote) == Data("download".utf8))
        await cloud.configure(full: false)
        try await files.retryPendingOperations()
        #expect(await cloud.publishes == 1)
        try await files.close()
    }

    @Test func offlineDeletionSurvivesRestartAndWrongAccountIsBlocked() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let cloud = try TestCloud(root.appendingPathComponent("cloud"))
        let files = try await store(root, cloud: cloud, enabled: true)
        let file = try await files.write(Data("book".utf8), path: "book")
        try await files.retryPendingOperations()
        await cloud.configure(available: false)
        let deletion = try await files.remove(file)
        #expect(deletion.cloudDeletionPending)
        try await files.close()
        let reopened = try await store(root, cloud: cloud, enabled: true)
        await cloud.configure(available: true, accountMatches: false)
        try await reopened.retryPendingOperations()
        #expect(await cloud.deletes == 0)
        #expect(try await reopened.list().issue?.kind == .accountMismatch)
        await cloud.configure(accountMatches: true)
        try await reopened.retryPendingOperations()
        #expect(await cloud.deletes == 1)
        #expect(!(try await reopened.remove(file)).cloudDeletionPending)
        try await reopened.close()
    }

    @Test func turningSyncOffKeepsDownloadedFilesAndDoesNotRepublishThem() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let cloud = try TestCloud(root.appendingPathComponent("cloud"))
        try await cloud.seed("remote", path: "remote")
        let online = try await store(root, cloud: cloud, enabled: true)
        try await online.retryPendingOperations()
        let file = try await online.reference(path: "remote")
        try await online.close()
        let offline = try await store(root)
        #expect(try await offline.read(file) == Data("remote".utf8))
        let local = try await offline.write(Data("new".utf8), path: "new")
        try await offline.close()
        let enabled = try await store(root, cloud: cloud, enabled: true)
        try await enabled.retryPendingOperations()
        #expect(await cloud.publishes == 1)
        #expect(try await enabled.read(local) == Data("new".utf8))
        try await enabled.close()
    }

    @Test func differentBytesNeverOverwriteAnOpenFile() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let cloud = try TestCloud(root.appendingPathComponent("cloud"))
        try await cloud.seed("original", path: "book")
        let files = try await store(root, cloud: cloud, enabled: true)
        try await files.retryPendingOperations()
        let file = try await files.reference(path: "book")
        let access = try await files.open(file)
        try await cloud.seed("different", path: "book")
        try await files.retryPendingOperations()
        #expect(try String(contentsOf: access.url, encoding: .utf8) == "original")
        await access.close()
        try await files.retryPendingOperations()
        #expect(try await files.status(of: file).syncState == .conflict)
        #expect(try String(contentsOf: access.url, encoding: .utf8) == "original")
        try await files.close()
    }

    @Test func deletionDuringDownloadCannotResurrectLocalContent() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let cloud = try TestCloud(root.appendingPathComponent("cloud"))
        try await cloud.seed("remote", path: "book")
        await cloud.beginPausingFetch()
        let files = try await store(root, cloud: cloud, enabled: true)
        let work = Task { try await files.retryPendingOperations() }
        try await waitForPausedFetch(cloud)
        let file = try await files.reference(path: "book")
        _ = try await files.remove(file)
        await cloud.resumeFetch()
        try await work.value
        #expect(try await files.status(of: file).syncState == .deleted)
        #expect(!(try await files.status(of: file)).isLocal)
        try await files.retryPendingOperations()
        #expect(await cloud.deletes == 1)
        #expect(await cloud.publishes == 0)
        try await files.close()
    }

    @Test func accountChangeDuringDownloadDoesNotInstallItsResult() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let cloud = try TestCloud(root.appendingPathComponent("cloud"))
        try await cloud.seed("account A", path: "book")
        await cloud.beginPausingFetch()
        let files = try await store(root, cloud: cloud, enabled: true)
        let work = Task { try await files.retryPendingOperations() }
        try await waitForPausedFetch(cloud)
        await cloud.configure(accountMatches: false)
        await cloud.resumeFetch()
        try await work.value
        let file = try await files.reference(path: "book")
        #expect(!(try await files.status(of: file)).isLocal)
        #expect(try await files.status(of: file).issue?.kind == .accountMismatch)
        await cloud.configure(accountMatches: true)
        try await files.retryPendingOperations()
        #expect(try await files.read(file) == Data("account A".utf8))
        try await files.close()
    }

    @Test func independentWaitersCanTimeoutAndCancelWithoutStoppingTheDownload() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let cloud = try TestCloud(root.appendingPathComponent("cloud"))
        try await cloud.seed("shared", path: "book")
        await cloud.beginPausingFetch()
        let files = try await store(root, cloud: cloud, enabled: true)
        let file = try await files.reference(path: "book")
        let first = Task { try await files.url(for: file, timeout: .seconds(5)) }
        try await waitForPausedFetch(cloud)
        await #expect(throws: FileStoreError.timedOut) {
            _ = try await files.url(for: file, timeout: .milliseconds(20))
        }
        let cancelled = Task { try await files.url(for: file) }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
        #expect(await cloud.fetches == 1)
        await cloud.resumeFetch()
        let url = try await first.value
        #expect(try String(contentsOf: url, encoding: .utf8) == "shared")
        try await files.close()
    }

    @Test func initialEmptyQueryDoesNotDeleteOrRepublishDownloadedFiles() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let cloud = try TestCloud(root.appendingPathComponent("cloud"))
        try await cloud.seed("retain", path: "book")
        let files = try await store(root, cloud: cloud, enabled: true)
        try await files.retryPendingOperations()
        let file = try await files.reference(path: "book")
        await cloud.configure(ready: false)
        try await files.retryPendingOperations()
        #expect(try await files.read(file) == Data("retain".utf8))
        #expect(try await files.list().discovery == .gathering)
        #expect(await cloud.publishes == 0)
        try await files.close()
    }

    @Test func unchangedDownloadsAreNotCopiedAgainAfterRestart() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let cloud = try TestCloud(root.appendingPathComponent("cloud"))
        try await cloud.seed("once", path: "book")
        let files = try await store(root, cloud: cloud, enabled: true)
        try await files.retryPendingOperations()
        #expect(await cloud.fetches == 1)
        try await files.close()
        let reopened = try await store(root, cloud: cloud, enabled: true)
        try await reopened.retryPendingOperations()
        #expect(await cloud.fetches == 1)
        try await reopened.close()
    }

    @Test func committedInstallationRecoversWithoutLosingTheUploadIntent() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let scope = FilePaths.key("<default>\n")
        let disk = try LocalStorage(base: root, scope: scope, rootPath: "")
        let transaction = disk.directory.appendingPathComponent("Transaction")
        try FileManager.default.createDirectory(at: transaction, withIntermediateDirectories: true)
        let content = transaction.appendingPathComponent("content")
        try Data("committed before exit".utf8).write(to: content)
        let entry = StoredFile(origin: .local, digest: try FilePaths.digest(content), state: .pending)
        try JSONEncoder().encode(LocalStorage.Install(path: "book", entry: entry))
            .write(to: transaction.appendingPathComponent("install.json"))
        disk.close() // Simulate exit after the journal commit, before installing content/manifest.
        let cloud = try TestCloud(root.appendingPathComponent("cloud"))
        let reopened = try await store(root, cloud: cloud, enabled: true)
        let file = try await reopened.reference(path: "book")
        #expect(try await reopened.read(file) == Data("committed before exit".utf8))
        #expect(try await reopened.status(of: file).syncState == .pending)
        try await reopened.retryPendingOperations()
        #expect(await cloud.publishes == 1)
        try await reopened.close()
    }

    @Test func unacknowledgedUploadIsReconciledWithoutBlindlyRecreatingMissingCloudData() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let files = try await store(root)
        let file = try await files.write(Data("original".utf8), path: "book")
        try await files.close()
        let disk = try LocalStorage(base: root, scope: file.scope, rootPath: "")
        var entry = try #require(disk.manifest.files[file.path])
        entry.state = .uncertain
        try disk.set(entry, for: file.path)
        disk.close()
        let cloud = try TestCloud(root.appendingPathComponent("cloud"))
        let reopened = try await store(root, cloud: cloud, enabled: true)
        try await reopened.retryPendingOperations()
        #expect(await cloud.publishes == 0)
        #expect(try await reopened.read(file) == Data("original".utf8))
        try await cloud.seed("original", path: "book")
        try await reopened.retryPendingOperations()
        #expect(try await reopened.status(of: file).syncState == .uploaded)
        #expect(await cloud.publishes == 0)
        try await reopened.close()
    }

    @Test func corruptManifestNeverSilentlyRescansLocalFilesForUpload() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let files = try await store(root)
        let file = try await files.write(Data("retain".utf8), path: "book")
        let url = try await files.url(for: file)
        try await files.close()
        try Data("broken".utf8).write(to: root.appendingPathComponent(file.scope).appendingPathComponent("manifest.json"))
        await #expect(throws: FileStoreError.corruptState) { _ = try await store(root) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "retain")
    }

    @Test func closeRequiresReadersToReleaseAndConflictBytesCanBeExported() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let files = try await store(root)
        let file = try await files.write(Data("local".utf8), path: "book")
        let access = try await files.open(file)
        await #expect(throws: FileStoreError.fileInUse) { try await files.close() }
        _ = try await files.remove(file)
        let exported = try await files.exportRetainedCopy(of: file)
        defer { try? FileManager.default.removeItem(at: exported) }
        #expect(try String(contentsOf: exported, encoding: .utf8) == "local")
        await access.close()
        try await files.close()
    }

    private func waitForPausedFetch(_ cloud: TestCloud) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await cloud.isFetchingPaused()) {
            guard ContinuousClock.now < deadline else { throw FileStoreError.timedOut }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func waitUntilLocal(_ file: FileReference, store: SwiftFileStore) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(try await store.status(of: file).isLocal) {
            guard ContinuousClock.now < deadline else { throw FileStoreError.timedOut }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
