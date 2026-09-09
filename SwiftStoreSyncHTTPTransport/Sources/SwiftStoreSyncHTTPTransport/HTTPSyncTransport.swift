import Foundation

/// Durable HTTP outbox/inbox with paged delta downloads. Polling only signals
/// SyncManager; all business writes still use its normal conflict/apply path.
public actor HTTPSyncTransport: SyncTransport {
    typealias SendRequest = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let configuration: HTTPSyncConfiguration
    private let sendRequest: SendRequest
    private let signal = HTTPSyncSignal()
    private var journal: HTTPSyncJournal
    private var tolerance: Int64
    private var generation = UUID()
    private var started = false
    private var cycle: UUID?
    private var polling: Task<Void, Never>?

    public nonisolated var remoteChanges: AsyncStream<Void> { signal.stream }

    deinit { polling?.cancel() }

    public init(configuration: HTTPSyncConfiguration) throws {
        try self.init(configuration: configuration, sendRequest: Self.networkSender())
    }

    init(configuration: HTTPSyncConfiguration, sendRequest: @escaping SendRequest) throws {
        try configuration.validate()
        self.configuration = configuration
        self.sendRequest = sendRequest
        self.tolerance = configuration.ntpToleranceMs
        if FileManager.default.fileExists(atPath: configuration.stateURL.path) {
            journal = try JSONDecoder().decode(HTTPSyncJournal.self, from: Data(contentsOf: configuration.stateURL))
            guard journal.formatVersion == 3, journal.cursor >= 0 else { throw HTTPSyncError.invalidResponse }
        } else {
            journal = HTTPSyncJournal()
        }
    }

    public func configureTimeValidation(toleranceMs: Int64) async throws {
        guard toleranceMs > 0 else { throw NTPError.invalidTolerance }
        tolerance = toleranceMs
    }

    public func start(deviceId: UUIDV7) async throws {
        let endpoint = configuration.serverURL.appendingPathComponent("sync/v1").absoluteString
        guard journal.endpoint == nil || (journal.endpoint == endpoint && journal.namespace == configuration.namespace && journal.deviceID == deviceId) else {
            throw HTTPSyncError.stateIdentityMismatch
        }
        if started { return }
        let current = generation
        try await NTPClient.requireAccurateTime(toleranceMs: tolerance)
        guard current == generation else { throw HTTPSyncError.stopped }
        // Another start may have completed while waiting for time verification.
        if started {
            guard journal.deviceID == deviceId else { throw HTTPSyncError.stateIdentityMismatch }
            return
        }
        var next = journal
        next.endpoint = endpoint
        next.namespace = configuration.namespace
        next.deviceID = deviceId
        try save(next)
        started = true
        signal.start()
        if let interval = configuration.pollInterval {
            polling = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(interval)) } catch { return }
                    await self?.notify(generation: current)
                }
            }
        }
    }

    public func stop() async {
        started = false
        generation = UUID()
        cycle = nil
        polling?.cancel()
        polling = nil
        signal.finish()
    }

    public func enqueue(_ changes: [SyncChange]) async throws {
        guard started else { throw HTTPSyncError.stopped }
        guard changes.allSatisfy({ $0.deviceId == journal.deviceID }) else { throw HTTPSyncError.stateIdentityMismatch }
        var next = journal
        var ids = Set(next.pending.map(\.id))
        for change in changes where ids.insert(change.id).inserted { next.pending.append(change) }
        try save(next)
    }

    public func syncNow() async throws -> SyncCycleResult {
        guard started, journal.deviceID != nil else { throw HTTPSyncError.stopped }
        guard cycle == nil else { throw HTTPSyncError.busy }
        let id = UUID()
        cycle = id
        defer { if cycle == id { cycle = nil } }
        let current = generation
        // Freeze before the first suspension. New edits stay queued for the next cycle.
        let uploads = journal.pending
        for offset in stride(from: 0, to: uploads.count, by: configuration.batchSize) {
            let batch = Array(uploads[offset..<min(offset + configuration.batchSize, uploads.count)])
            try await push(batch, current: current)
        }
        // Every frozen upload has now been confirmed. Pull all pages before lookup.
        var hasMore = true
        while hasMore { hasMore = try await pull(current: current) }
        try await resolveMissing(current: current)
        if !journal.pending.isEmpty { signal.yield() }
        return journal.result
    }

    public func acknowledge(_ result: SyncCycleResult) async throws {
        var next = journal
        next.acknowledge(result)
        try save(next)
    }

    private func push(_ changes: [SyncChange], current: UUID) async throws {
        var request = makeRequest("push", method: "POST")
        request.httpBody = try JSONEncoder().encode(HTTPSyncPushRequest(changes: changes))
        let (response, serverID): (HTTPSyncPushResponse, String) = try await perform(request, current: current)
        let sentIDs = Set(changes.map(\.id))
        let sentByKey = Dictionary(grouping: changes, by: HTTPSyncRecord.key(for:))
        let rejected = Set(response.rejected.map(\.key))
        guard rejected.count == response.rejected.count,
              response.rejected.allSatisfy({ sentByKey[$0.key] != nil && $0.sequence > 0 }) else {
            throw HTTPSyncError.invalidResponse
        }
        var next = journal // Preserve writes enqueued during network I/O.
        next.pending.removeAll { sentIDs.contains($0.id) }
        for rejection in response.rejected {
            // One key may identify several edits in this frozen batch. Associate
            // the correction only with those edits, never with later enqueues.
            for change in sentByKey[rejection.key]! {
                next.rejections.record(change)
                next.rejectionSequences[change.id] = rejection.sequence
                if !next.conflicts.contains(where: { $0.id == change.id }) { next.conflicts.append(change) }
            }
        }
        for change in changes where !rejected.contains(HTTPSyncRecord.key(for: change)) && !next.pushed.contains(change.id) {
            next.pushed.append(change.id)
        }
        next.awaitingPullKeys.formUnion(changes.map(HTTPSyncRecord.key(for:)))
        next.serverID = serverID
        // A later batch failure must never resurrect this confirmed batch.
        try save(next)
    }

    private func pull(current: UUID) async throws -> Bool {
        let cursor = journal.cursor
        let request = makeRequest("pull", method: "GET", query: [
            URLQueryItem(name: "cursor", value: String(cursor)),
            URLQueryItem(name: "limit", value: String(configuration.batchSize))
        ])
        let (response, serverID): (HTTPSyncPullResponse, String) = try await perform(request, current: current)
        guard response.changes.count <= configuration.batchSize,
              !response.hasMore || response.cursor > cursor else { throw HTTPSyncError.invalidResponse }
        var pageCursor = cursor
        for record in response.changes {
            guard let sequence = record.sequence, sequence > pageCursor else { throw HTTPSyncError.invalidResponse }
            _ = try record.decodeChange()
            pageCursor = sequence
        }
        guard pageCursor == response.cursor else { throw HTTPSyncError.invalidResponse }
        var next = journal
        for record in response.changes { try next.receive(record) }
        next.cursor = response.cursor
        next.serverID = serverID
        if !response.hasMore { next.awaitingPullKeys.removeAll() }
        // Each page and cursor form one checkpoint; a failed later page is retryable.
        try save(next)
        return response.hasMore
    }

    private func resolveMissing(current: UUID) async throws {
        let missing = journal.rejections.missing
        guard !missing.isEmpty else { return }
        let keys = Array(Set(missing.map { HTTPSyncRecord.key(for: $0.change) })).sorted()
        for offset in stride(from: 0, to: keys.count, by: configuration.batchSize) {
            let batch = Array(keys[offset..<min(offset + configuration.batchSize, keys.count)])
            var request = makeRequest("records", method: "POST")
            request.httpBody = try JSONEncoder().encode(HTTPSyncLookupRequest(keys: batch))
            let (response, _): (HTTPSyncLookupResponse, String) = try await perform(request, current: current)
            guard response.records.count == batch.count,
                  Set(response.records.map(\.key)) == Set(batch) else { throw HTTPSyncError.invalidResponse }
            for record in response.records {
                let floor = journal.rejections.entries.filter { HTTPSyncRecord.key(for: $0.change) == record.key }
                    .compactMap { journal.rejectionSequences[$0.changeID] }.max() ?? 0
                guard let sequence = record.sequence, sequence > 0,
                      sequence >= max(floor, journal.receivedSequences[record.key] ?? 0) else {
                    throw HTTPSyncError.invalidResponse
                }
                _ = try record.decodeChange()
            }
            var next = journal
            for record in response.records { try next.receive(record) }
            // Lookup never advances the incremental cursor.
            try save(next)
        }
    }

    private func makeRequest(_ action: String, method: String, query: [URLQueryItem] = []) -> URLRequest {
        let url = configuration.serverURL.appendingPathComponent("sync/v1").appendingPathComponent(action)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "namespace", value: configuration.namespace)] + query
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 30
        if method == "POST" { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(configuration.bearerToken)", forHTTPHeaderField: "Authorization")
        if let serverID = journal.serverID { request.setValue(serverID, forHTTPHeaderField: "X-SwiftStore-Server-ID") }
        return request
    }

    private func perform<Response: Decodable>(_ request: URLRequest, current: UUID) async throws -> (Response, String) {
        try await NTPClient.requireAccurateTime(toleranceMs: tolerance)
        guard started, current == generation else { throw HTTPSyncError.stopped }
        try Task.checkCancellation()
        let (data, http) = try await sendRequest(request)
        guard started, current == generation else { throw HTTPSyncError.stopped }
        try Task.checkCancellation()
        guard http.statusCode == 200 else { throw HTTPSyncError.httpStatus(http.statusCode) }
        guard let serverID = http.value(forHTTPHeaderField: "X-SwiftStore-Server-ID"),
              !serverID.isEmpty, serverID.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw HTTPSyncError.invalidResponse
        }
        if let expected = journal.serverID, expected != serverID { throw HTTPSyncError.serverIdentityChanged }
        let response = try JSONDecoder().decode(Response.self, from: data)
        try await NTPClient.requireAccurateTime(toleranceMs: tolerance)
        guard started, current == generation else { throw HTTPSyncError.stopped }
        try Task.checkCancellation()
        return (response, serverID)
    }

    private func save(_ next: HTTPSyncJournal) throws {
        let data = try JSONEncoder().encode(next)
        try FileManager.default.createDirectory(at: configuration.stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: configuration.stateURL, options: .atomic)
        journal = next
    }

    private func notify(generation: UUID) {
        if started, generation == self.generation { signal.yield() }
    }

    private static func networkSender() -> SendRequest {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        let owner = SessionOwner(configuration: config)
        return { request in
            let (data, response) = try await owner.session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw HTTPSyncError.invalidResponse }
            return (data, http)
        }
    }
}

private final class SessionOwner: Sendable {
    let session: URLSession
    init(configuration: URLSessionConfiguration) {
        session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
