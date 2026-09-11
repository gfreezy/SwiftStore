import Foundation
import CryptoKit
import Darwin

enum FilePaths {
    static func validate(_ path: String, allowEmpty: Bool = false) throws {
        if allowEmpty && path.isEmpty { return }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.contains("\0"), !path.contains("\\"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") }) else {
            throw FileStoreError.invalidPath(path)
        }
    }

    static func url(_ path: String, in root: URL) throws -> URL {
        try validate(path)
        var result = root.standardizedFileURL.resolvingSymlinksInPath()
        for part in path.split(separator: "/") {
            result.appendPathComponent(String(part))
            if let attributes = try? FileManager.default.attributesOfItem(atPath: result.path),
               attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                throw FileStoreError.invalidPath(path)
            }
        }
        return result
    }

    static func relative(_ url: URL, in root: URL) -> String? {
        let base = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let components = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard components.count > base.count, components.starts(with: base) else { return nil }
        let path = components.dropFirst(base.count).joined(separator: "/")
        guard (try? validate(path)) != nil else { return nil }
        return path
    }

    static func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func key(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func removeIfPresent(_ url: URL) throws {
        do { try FileManager.default.removeItem(at: url) }
        catch CocoaError.fileNoSuchFile, CocoaError.fileReadNoSuchFile { }
    }

    static func copy(_ source: URL, to destination: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".copy-\(UUID())")
        defer { try? manager.removeItem(at: temporary) }
        try manager.copyItem(at: source, to: temporary)
        // rename on the same filesystem atomically replaces the directory entry.
        guard rename(temporary.path, destination.path) == 0 else { throw posixError() }
    }

    static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}

/// Reject overlapping cloud namespaces even when their local directories are distinct.
/// Registry serialization makes checking and acquiring a scope one atomic operation.
final class NamespaceLock: @unchecked Sendable {
    private var descriptor: Int32 = -1

    init(base: URL, container: String, rootPath: String) throws {
        let rootPath = rootPath.precomposedStringWithCanonicalMapping.lowercased()
        let directory = base.appendingPathComponent("NamespaceLocks").appendingPathComponent(FilePaths.key(container))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let registry = Darwin.open(directory.appendingPathComponent("registry").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard registry >= 0 else { throw FilePaths.posixError() }
        defer { Darwin.close(registry) }
        guard flock(registry, LOCK_EX) == 0 else { throw FilePaths.posixError() }
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where url.pathExtension == "scope" {
            let fd = Darwin.open(url.path, O_RDWR | O_NOFOLLOW)
            guard fd >= 0 else { throw FilePaths.posixError() }
            defer { Darwin.close(fd) }
            if flock(fd, LOCK_EX | LOCK_NB) != 0 {
                let other = try String(contentsOf: url, encoding: .utf8)
                if other.isEmpty || rootPath.isEmpty || other == rootPath
                    || other.hasPrefix(rootPath + "/") || rootPath.hasPrefix(other + "/") {
                    throw FileStoreError.alreadyOpen
                }
            }
        }
        let file = directory.appendingPathComponent(FilePaths.key(rootPath)).appendingPathExtension("scope")
        descriptor = Darwin.open(file.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw FilePaths.posixError() }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { close(); throw FileStoreError.alreadyOpen }
        do {
            // Write through the locked inode, never atomically replace the lock file.
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: Data(rootPath.utf8))
        } catch { close(); throw error }
    }

    func close() { if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 } }
    deinit { close() }
}

struct StoredFile: Codable, Sendable {
    enum Origin: String, Codable { case local, cloud }
    var origin: Origin
    var digest: String?
    var state: FileSyncState
    var revision: UUID = UUID()
    var deletePending = false
    var issue: FileIssue?
    var cloudVersion: String?
}

struct FileManifest: Codable {
    var version = 1
    var files: [String: StoredFile] = [:]
}

/// Used only on the store actor. The journal is a redo record, not an upload source.
final class LocalStorage: @unchecked Sendable {
    let directory: URL
    let filesRoot: URL
    let staging: URL
    private let manifestURL: URL
    private let transaction: URL
    private var lockFD: Int32 = -1
    var manifest: FileManifest

    struct Install: Codable {
        let path: String
        let entry: StoredFile
    }

    init(base: URL, scope: String, rootPath: String) throws {
        directory = base.appendingPathComponent(scope, isDirectory: true)
        filesRoot = rootPath.isEmpty ? directory.appendingPathComponent("Files")
            : try FilePaths.url(rootPath, in: directory.appendingPathComponent("Files"))
        staging = directory.appendingPathComponent("Staging")
        manifestURL = directory.appendingPathComponent("manifest.json")
        transaction = directory.appendingPathComponent("Transaction")
        manifest = FileManifest()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        lockFD = Darwin.open(directory.appendingPathComponent("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lockFD >= 0 else { throw FilePaths.posixError() }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(lockFD); lockFD = -1
            throw FileStoreError.alreadyOpen
        }
        do {
            if FileManager.default.fileExists(atPath: manifestURL.path) {
                do { manifest = try JSONDecoder().decode(FileManifest.self, from: Data(contentsOf: manifestURL)) }
                catch { throw FileStoreError.corruptState }
                guard manifest.version == 1 else { throw FileStoreError.corruptState }
                for path in manifest.files.keys { try FilePaths.validate(path) }
            }
            try FileManager.default.createDirectory(at: filesRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try recover()
            // Staging never contains committed data; the transaction directory does.
            for file in try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            Darwin.close(lockFD); lockFD = -1
            throw error
        }
    }

    deinit { if lockFD >= 0 { Darwin.close(lockFD) } }

    func close() {
        if lockFD >= 0 { Darwin.close(lockFD); lockFD = -1 }
    }

    func url(_ path: String) throws -> URL { try FilePaths.url(path, in: filesRoot) }
    func exists(_ path: String) -> Bool {
        guard let url = try? url(path) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func set(_ entry: StoredFile, for path: String) throws {
        try set([path: entry])
    }

    func set(_ entries: [String: StoredFile]) throws {
        var next = manifest
        next.files.merge(entries) { _, new in new }
        try JSONEncoder().encode(next).write(to: manifestURL, options: .atomic)
        manifest = next
    }

    /// The payload remains in Transaction until both file installation and manifest commit succeed.
    func install(_ source: URL, path: String, entry: StoredFile) throws {
        _ = try url(path) // Reject invalid destinations before committing a redo record.
        try recover()
        let prepared = staging.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: prepared, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: prepared) }
        try FileManager.default.copyItem(at: source, to: prepared.appendingPathComponent("content"))
        try JSONEncoder().encode(Install(path: path, entry: entry))
            .write(to: prepared.appendingPathComponent("install.json"), options: .atomic)
        try FileManager.default.moveItem(at: prepared, to: transaction)
        try recover()
    }

    func recover() throws {
        guard FileManager.default.fileExists(atPath: transaction.path) else { return }
        let install: Install
        do { install = try JSONDecoder().decode(Install.self, from: Data(contentsOf: transaction.appendingPathComponent("install.json"))) }
        catch { throw FileStoreError.corruptState }
        let content = transaction.appendingPathComponent("content")
        guard try FilePaths.digest(content) == install.entry.digest else { throw FileStoreError.corruptState }
        try FilePaths.copy(content, to: url(install.path))
        try set(install.entry, for: install.path)
        try FileManager.default.removeItem(at: transaction)
    }
}
