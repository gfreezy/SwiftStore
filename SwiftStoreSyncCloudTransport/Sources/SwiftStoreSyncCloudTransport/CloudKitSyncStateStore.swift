import Foundation

/// Durable CloudKit state. Atomically store the whole journal: engine cursor,
/// pending payloads, inbox, receipts, and record tags. Corrupt state must throw.
public protocol CloudKitSyncStateStore: Sendable {
    func loadJournal() async throws -> CloudKitSyncJournal?
    func saveJournal(_ journal: CloudKitSyncJournal) async throws
}

/// Default file-based store. Atomically replaces journal.plist.
/// Implement CloudKitSyncStateStore to use your own persistence layer.
public actor FileCloudKitSyncStateStore: CloudKitSyncStateStore {
    private let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }

    public func loadJournal() async throws -> CloudKitSyncJournal? {
        let url = directory.appendingPathComponent("journal.plist")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try PropertyListDecoder().decode(CloudKitSyncJournal.self, from: Data(contentsOf: url))
        } catch {
            // Unlike a disposable cursor, pending uploads/downloads cannot be discarded.
            throw CloudKitTransportError.stateCorrupt(error.localizedDescription)
        }
    }

    public func saveJournal(_ journal: CloudKitSyncJournal) async throws {
        let data = try PropertyListEncoder().encode(journal)
        try data.write(to: directory.appendingPathComponent("journal.plist"), options: .atomic)
    }
}
