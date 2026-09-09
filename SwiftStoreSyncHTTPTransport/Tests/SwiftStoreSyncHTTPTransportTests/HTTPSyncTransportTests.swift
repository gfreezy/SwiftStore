import Foundation
import Testing
@testable import SwiftStoreSync
@testable import SwiftStoreSyncHTTPTransport

private enum NetworkFailure: Error { case lostResponse, unexpectedRequest }

private enum APIReply: Sendable {
    case push([HTTPSyncRejection])
    case pull(HTTPSyncPullResponse)
    case lookup([HTTPSyncRecord])
    case failure(String)
    case raw(String, Data, status: Int, serverID: String?)
}

private func httpResponse(_ request: URLRequest, status: Int = 200, serverID: String? = "s") -> HTTPURLResponse {
    var headers = ["Content-Type": "application/json"]
    if let serverID { headers["X-SwiftStore-Server-ID"] = serverID }
    return HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
}

private actor ScriptedAPI {
    var requests: [URLRequest] = []
    var replies: [APIReply]
    init(_ replies: [APIReply]) { self.replies = replies }

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        guard !replies.isEmpty else { throw NetworkFailure.unexpectedRequest }
        let reply = replies.removeFirst()
        let path: String
        let data: Data
        switch reply {
        case .push(let rejected):
            path = "push"
            data = try JSONEncoder().encode(HTTPSyncPushResponse(rejected: rejected))
        case .pull(let page):
            path = "pull"
            data = try JSONEncoder().encode(page)
        case .lookup(let records):
            path = "records"
            data = try JSONEncoder().encode(HTTPSyncLookupResponse(records: records))
        case .failure(let action):
            #expect(request.url?.lastPathComponent == action)
            throw NetworkFailure.lostResponse
        case .raw(let action, let body, let status, let serverID):
            #expect(request.url?.lastPathComponent == action)
            return (body, httpResponse(request, status: status, serverID: serverID))
        }
        #expect(request.url?.path == "/sync/v1/\(path)")
        #expect(request.httpMethod == (path == "pull" ? "GET" : "POST"))
        if path == "pull" { #expect(request.httpBody == nil) }
        return (data, httpResponse(request))
    }
}

/// Reference server double: stores opaque envelopes and compares only timestamps.
/// It never decodes SyncChange or keeps a modification receipt table.
private actor TimestampOnlyAPI {
    private struct Push: Decodable { let changes: [HTTPSyncRecord] }
    var records: [String: HTTPSyncRecord] = [:]
    var deltas: [HTTPSyncRecord] = []
    var loseFirstPushResponse = true
    var requests: [URLRequest] = []

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        switch request.url!.lastPathComponent {
        case "push":
            let push = try JSONDecoder().decode(Push.self, from: request.httpBody!)
            var rejectedKeys = Set<String>()
            for incoming in push.changes {
                if let current = records[incoming.key], incoming.updatedAt <= current.updatedAt {
                    rejectedKeys.insert(incoming.key)
                } else {
                    let committed = HTTPSyncRecord(key: incoming.key, updatedAt: incoming.updatedAt,
                        payload: incoming.payload, sequence: Int64(deltas.count + 1))
                    records[incoming.key] = committed
                    deltas.append(committed)
                }
            }
            let rejected = rejectedKeys.sorted().map { HTTPSyncRejection(key: $0, sequence: records[$0]!.sequence!) }
            // The transaction committed; only the response is lost.
            if loseFirstPushResponse { loseFirstPushResponse = false; throw NetworkFailure.lostResponse }
            return (try JSONEncoder().encode(HTTPSyncPushResponse(rejected: rejected)), httpResponse(request))
        case "pull":
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let cursor = Int64(query.first { $0.name == "cursor" }!.value!)!
            let rows = deltas.filter { $0.sequence! > cursor }
            return (try JSONEncoder().encode(HTTPSyncPullResponse(changes: rows,
                cursor: rows.last?.sequence ?? cursor, hasMore: false)), httpResponse(request))
        case "records":
            let lookup = try JSONDecoder().decode(HTTPSyncLookupRequest.self, from: request.httpBody!)
            return (try JSONEncoder().encode(HTTPSyncLookupResponse(records: lookup.keys.compactMap { records[$0] })), httpResponse(request))
        default: throw NetworkFailure.unexpectedRequest
        }
    }
}

private struct Fixture {
    let root: URL
    let configuration: HTTPSyncConfiguration
    let api: ScriptedAPI
    let transport: HTTPSyncTransport
}

private actor PausedAPI {
    nonisolated let arrived = AsyncStream<Void>.makeStream()
    var requests: [URLRequest] = []
    var waiting: CheckedContinuation<Void, Never>?
    var uploaded: [SyncChange] = []
    let rejectUploads: Bool
    init(rejectUploads: Bool = false) { self.rejectUploads = rejectUploads }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if request.url?.lastPathComponent == "push" {
            let body = try JSONDecoder().decode(HTTPSyncPushRequest.self, from: request.httpBody!)
            await withCheckedContinuation { waiting = $0; arrived.continuation.yield(()) }
            uploaded.append(contentsOf: body.changes)
            let keys = Set(body.changes.map(HTTPSyncRecord.key(for:)))
            let rejected = rejectUploads ? keys.sorted().map { key in
                HTTPSyncRejection(key: key, sequence: Int64(uploaded.lastIndex { HTTPSyncRecord.key(for: $0) == key }! + 1))
            } : []
            return (try JSONEncoder().encode(HTTPSyncPushResponse(rejected: rejected)), httpResponse(request))
        }
        let records = try uploaded.enumerated().map { try HTTPSyncRecord(change: $0.element, sequence: Int64($0.offset + 1)) }
        return (try JSONEncoder().encode(HTTPSyncPullResponse(changes: records,
            cursor: records.last?.sequence ?? 0, hasMore: false)), httpResponse(request))
    }
    func release() { waiting?.resume(); waiting = nil }
}

@Suite("HTTP synchronization")
struct HTTPSyncTransportTests {
    private func config(_ root: URL, batchSize: Int = 100, namespace: String = "test") -> HTTPSyncConfiguration {
        HTTPSyncConfiguration(serverURL: URL(string: "https://sync.example.com")!, namespace: namespace,
            bearerToken: "test-token", stateURL: root.appendingPathComponent("journal.json"),
            batchSize: batchSize, pollInterval: nil)
    }

    private func change(_ device: UUIDV7, key: UInt8 = 1, time: Double = 810000000.125) -> SyncChange {
        SyncChange(id: UUIDV7(), entityType: "note", syncKey: Data([key]), operation: .insert,
            payload: "{\"title\":\"note\",\"updatedAt\":\(time)}", deviceId: device,
            logicalClock: 1, createdAt: Date(timeIntervalSinceReferenceDate: time))
    }

    private func fixture(_ replies: [APIReply], device: UUIDV7 = UUIDV7(), batchSize: Int = 100,
                         body: (Fixture) async throws -> Void) async throws {
        try await NTPClient.$testTimeQuery.withValue({ .init(offsetMs: 0, isValid: true, server: "test", rttMs: 1) }) {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let configuration = config(root, batchSize: batchSize)
            let api = ScriptedAPI(replies)
            let transport = try HTTPSyncTransport(configuration: configuration, sendRequest: { try await api.send($0) })
            try await transport.start(deviceId: device)
            do { try await body(Fixture(root: root, configuration: configuration, api: api, transport: transport)) }
            catch { await transport.stop(); throw error }
            await transport.stop()
        }
    }

    private func journal(_ fixture: Fixture) throws -> HTTPSyncJournal {
        try JSONDecoder().decode(HTTPSyncJournal.self, from: Data(contentsOf: fixture.configuration.stateURL))
    }

    private func page(_ records: [HTTPSyncRecord] = [], cursor: Int64 = 0, more: Bool = false) -> APIReply {
        .pull(.init(changes: records, cursor: cursor, hasMore: more))
    }

    @Test("All frozen upload batches finish before paged pull begins")
    func batchesBeforePull() async throws {
        let device = UUIDV7()
        let first = change(device), second = change(device, key: 2), third = change(device, key: 3)
        let records = try [first, second, third].enumerated().map { try HTTPSyncRecord(change: $0.element, sequence: Int64($0.offset + 1)) }
        try await fixture([.push([]), .push([]), page(Array(records.prefix(2)), cursor: 2, more: true),
                           page([records[2]], cursor: 3)], device: device, batchSize: 2) { f in
            try await f.transport.enqueue([first, second, third])
            let result = try await f.transport.syncNow()
            #expect(result.pushed == [first.id, second.id, third.id])
            #expect(Set(result.pulled.map(\.id)) == Set(result.pushed))
            let requests = await f.api.requests
            #expect(requests.map { $0.url!.lastPathComponent } == ["push", "push", "pull", "pull"])
            #expect(try JSONDecoder().decode(HTTPSyncPushRequest.self, from: requests[0].httpBody!).changes.count == 2)
            #expect(try JSONDecoder().decode(HTTPSyncPushRequest.self, from: requests[1].httpBody!).changes.map(\.id) == [third.id])
            #expect(requests[0].value(forHTTPHeaderField: "X-SwiftStore-Server-ID") == nil)
            #expect(requests.dropFirst().allSatisfy { $0.value(forHTTPHeaderField: "X-SwiftStore-Server-ID") == "s" })
            #expect(URLComponents(url: requests[3].url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "cursor", value: "2")) == true)
            try await f.transport.acknowledge(result)
            #expect(try journal(f).pending.isEmpty)
        }
    }

    @Test("Failed later upload batches do not repeat confirmed batches or start pull early")
    func batchFailureAndRestart() async throws {
        let device = UUIDV7(), first = change(device), second = change(device, key: 2)
        let records = try [first, second].enumerated().map { try HTTPSyncRecord(change: $0.element, sequence: Int64($0.offset + 1)) }
        try await fixture([.push([]), .failure("push"), .push([]), page([records[0]], cursor: 1, more: true),
                           page([records[1]], cursor: 2)], device: device, batchSize: 1) { f in
            try await f.transport.enqueue([first, second])
            await #expect(throws: NetworkFailure.self) { try await f.transport.syncNow() }
            #expect(try journal(f).pending.map(\.id) == [second.id])
            #expect(await f.api.requests.map { $0.url!.lastPathComponent } == ["push", "push"])
            await f.transport.stop()
            let restored = try HTTPSyncTransport(configuration: f.configuration, sendRequest: { try await f.api.send($0) })
            try await restored.start(deviceId: device)
            let result = try await restored.syncNow()
            #expect(result.pushed == [first.id, second.id])
            let requests = await f.api.requests
            let failed = try JSONDecoder().decode(HTTPSyncPushRequest.self, from: requests[1].httpBody!)
            let retried = try JSONDecoder().decode(HTTPSyncPushRequest.self, from: requests[2].httpBody!)
            #expect(failed.changes.map(\.id) == retried.changes.map(\.id))
            #expect(try HTTPSyncRecord(change: failed.changes[0]).payload == HTTPSyncRecord(change: retried.changes[0]).payload)
            await restored.stop()
        }
    }

    @Test("Pull failure preserves completed uploads and page checkpoints across restart")
    func pullFailureAndRestart() async throws {
        let device = UUIDV7(), local = change(device), old = change(UUIDV7(), time: 810000000)
        let before = try HTTPSyncRecord(change: old, sequence: 1), final = try HTTPSyncRecord(change: local, sequence: 2)
        try await fixture([.push([]), page([before], cursor: 1, more: true), .failure("pull"), page([final], cursor: 2)], device: device) { f in
            try await f.transport.enqueue([local])
            await #expect(throws: NetworkFailure.self) { try await f.transport.syncNow() }
            #expect(try journal(f).cursor == 1)
            #expect(try journal(f).result.pulled.isEmpty) // Historical page cannot overwrite the accepted local edit.
            await f.transport.stop()
            let restored = try HTTPSyncTransport(configuration: f.configuration, sendRequest: { try await f.api.send($0) })
            try await restored.start(deviceId: device)
            #expect(try await restored.syncNow().pulled.map(\.id) == [local.id])
            #expect(await f.api.requests.map { $0.url!.lastPathComponent } == ["push", "pull", "pull", "pull"])
            await restored.stop()
        }
    }

    @Test("Normal pull resolves rejected keys only after reaching the decision sequence")
    func rejectionResolvedByPull() async throws {
        let device = UUIDV7(), local = change(device)
        let old = try HTTPSyncRecord(change: change(UUIDV7()), sequence: 10)
        let winner = try HTTPSyncRecord(change: change(UUIDV7(), time: 810000001), sequence: 100)
        try await fixture([.push([.init(key: HTTPSyncRecord.key(for: local), sequence: 100)]), page([old], cursor: 10, more: true),
                           page([winner], cursor: 100)], device: device) { f in
            try await f.transport.enqueue([local])
            let result = try await f.transport.syncNow()
            #expect(result.pulled.map(\.id) == [try winner.decodeChange().id])
            #expect(result.conflicts.map(\.id) == [local.id])
            #expect(await f.api.requests.count == 3) // No lookup.
            try await f.transport.acknowledge(.init(pulled: [], pushed: [], conflicts: result.conflicts))
            #expect(try journal(f).rejections.entries.count == 1)
            try await f.transport.acknowledge(result)
            #expect(try journal(f).rejections.entries.isEmpty)
        }
    }

    @Test("Already downloaded winners use lookup; lookup failure never resubmits the confirmed upload")
    func lookupRecovery() async throws {
        let device = UUIDV7(), local = change(device)
        let winner = try HTTPSyncRecord(change: change(UUIDV7(), time: 810000001), sequence: 10)
        try await fixture([page([winner], cursor: 10), .push([.init(key: HTTPSyncRecord.key(for: local), sequence: 10)]),
                           page(cursor: 10), .failure("records"), page(cursor: 10), .lookup([winner])], device: device) { f in
            let initial = try await f.transport.syncNow()
            try await f.transport.acknowledge(initial)
            try await f.transport.enqueue([local])
            await #expect(throws: NetworkFailure.self) { try await f.transport.syncNow() }
            #expect(try journal(f).pending.isEmpty)
            #expect(try journal(f).rejections.missing.count == 1)
            await f.transport.stop()
            let restored = try HTTPSyncTransport(configuration: f.configuration, sendRequest: { try await f.api.send($0) })
            try await restored.start(deviceId: device)
            let result = try await restored.syncNow()
            #expect(result.pulled.map(\.id) == [try winner.decodeChange().id])
            #expect(await f.api.requests.filter { $0.url!.lastPathComponent == "push" }.count == 1)
            #expect(try journal(f).cursor == 10)
            try await restored.acknowledge(result)
            #expect(try journal(f).rejections.entries.isEmpty)
            await restored.stop()
        }
    }

    @Test("Lookup fetches only keys omitted from pull and cannot return an older version")
    func lookupValidation() async throws {
        let device = UUIDV7(), a = change(device), b = change(device, key: 2)
        let ra = try HTTPSyncRecord(change: change(UUIDV7()), sequence: 10)
        let rb = try HTTPSyncRecord(change: change(UUIDV7(), key: 2), sequence: 5)
        try await fixture([page([rb], cursor: 5), .push([.init(key: HTTPSyncRecord.key(for: a), sequence: 10), .init(key: HTTPSyncRecord.key(for: b), sequence: 5)]),
                           page([ra], cursor: 10), .lookup([rb])], device: device) { f in
            let initial = try await f.transport.syncNow()
            try await f.transport.acknowledge(initial)
            try await f.transport.enqueue([a, b])
            let result = try await f.transport.syncNow()
            #expect(Set(result.pulled.map(\.id)) == [try ra.decodeChange().id, try rb.decodeChange().id])
            let last = try #require(await f.api.requests.last)
            #expect(try JSONDecoder().decode(HTTPSyncLookupRequest.self, from: last.httpBody!).keys == [rb.key])
        }
        try await fixture([page([ra], cursor: 10), .push([.init(key: HTTPSyncRecord.key(for: a), sequence: 10)]), page(cursor: 10),
                           .lookup([try HTTPSyncRecord(change: change(UUIDV7()), sequence: 2)])], device: device) { f in
            let initial = try await f.transport.syncNow()
            try await f.transport.acknowledge(initial)
            try await f.transport.enqueue([a])
            await #expect(throws: HTTPSyncError.self) { try await f.transport.syncNow() }
            #expect(try journal(f).rejections.missing.map(\.changeID) == [a.id])
        }
    }

    @Test("Malformed batch responses and missing identity retain uploads; database replacement blocks pull")
    func invalidResponses() async throws {
        let device = UUIDV7(), local = change(device)
        try await fixture([.push([.init(key: "unknown-key", sequence: 1)]),
                           .raw("push", Data("{\"rejected\":[]}".utf8), status: 200, serverID: nil),
                           .push([]), .raw("pull", Data("{\"changes\":[],\"cursor\":0,\"hasMore\":false}".utf8), status: 200, serverID: "replacement")], device: device) { f in
            try await f.transport.enqueue([local])
            await #expect(throws: HTTPSyncError.self) { try await f.transport.syncNow() }
            #expect(try journal(f).pending.map(\.id) == [local.id])
            await #expect(throws: HTTPSyncError.self) { try await f.transport.syncNow() }
            #expect(try journal(f).pending.map(\.id) == [local.id])
            await #expect(throws: HTTPSyncError.self) { try await f.transport.syncNow() }
            #expect(try journal(f).pending.isEmpty)
            #expect(try journal(f).serverID == "s")
            #expect(try journal(f).cursor == 0)
        }
    }

    @Test("Writes during upload belong to the next cycle; a key-level rejection cannot reject later edits", arguments: [false, true])
    func frozenSnapshotAndStop(rejectUploads: Bool) async throws {
        try await NTPClient.$testTimeQuery.withValue({ .init(offsetMs: 0, isValid: true, server: "test", rttMs: 1) }) {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let device = UUIDV7(), first = change(device), second = change(device, time: 810000001)
            let api = PausedAPI(rejectUploads: rejectUploads)
            var arrived = api.arrived.stream.makeAsyncIterator()
            let transport = try HTTPSyncTransport(configuration: config(root), sendRequest: { try await api.send($0) })
            try await transport.start(deviceId: device)
            try await transport.enqueue([first])
            let task = Task { try await transport.syncNow() }
            _ = await arrived.next()
            try await transport.enqueue([second])
            await api.release()
            let result = try await task.value
            #expect(result.pushed == (rejectUploads ? [] : [first.id]))
            #expect(result.conflicts.map(\.id) == (rejectUploads ? [first.id] : []))
            #expect(result.rejectedKeys.allSatisfy { $0.changeID != second.id })
            #expect(result.pendingChanges.map(\.id) == [second.id])
            #expect(await api.requests.map { $0.url!.lastPathComponent } == ["push", "pull"])
            let later = Task { try await transport.syncNow() }
            _ = await arrived.next()
            await transport.stop()
            try await transport.start(deviceId: device)
            await api.release()
            await #expect(throws: HTTPSyncError.self) { try await later.value }
            let saved = try JSONDecoder().decode(HTTPSyncJournal.self, from: Data(contentsOf: config(root).stateURL))
            #expect(saved.pending.map(\.id) == [second.id])
            await transport.stop()
        }
    }

    @Test("One key-level rejection repairs every same-key edit in that batch")
    func repeatedKeyInBatch() async throws {
        let device = UUIDV7(), a = change(device), b = change(device, time: 810000001)
        let winner = try HTTPSyncRecord(change: change(UUIDV7(), time: 810000002), sequence: 10)
        try await fixture([.push([.init(key: winner.key, sequence: 10)]), page([winner], cursor: 10)], device: device) { f in
            try await f.transport.enqueue([a, b])
            let result = try await f.transport.syncNow()
            #expect(result.pendingChanges.isEmpty && result.pushed.isEmpty)
            #expect(Set(result.rejectedKeys.map(\.changeID)) == [a.id, b.id])
            #expect(result.pulled.map(\.id) == [try winner.decodeChange().id])
            try await f.transport.acknowledge(result)
            #expect(try journal(f).rejections.entries.isEmpty)
        }
    }

    @Test("A timestamp-only server safely handles lost responses and equal-time different payloads")
    func retryWithoutServerModificationIDs() async throws {
        try await NTPClient.$testTimeQuery.withValue({ .init(offsetMs: 0, isValid: true, server: "test", rttMs: 1) }) {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let device = UUIDV7(), original = change(device), sameTime = change(device)
            let api = TimestampOnlyAPI()
            let transport = try HTTPSyncTransport(configuration: config(root), sendRequest: { try await api.send($0) })
            try await transport.start(deviceId: device)
            try await transport.enqueue([original])
            await #expect(throws: NetworkFailure.self) { try await transport.syncNow() }
            #expect(await api.deltas.count == 1)
            let retried = try await transport.syncNow()
            #expect(await api.deltas.count == 1)
            #expect(retried.pulled.map(\.id) == [original.id])
            #expect(retried.conflicts.map(\.id) == [original.id])
            try await transport.acknowledge(retried)
            // The payload differs (including its client-owned ID), but time is equal.
            try await transport.enqueue([sameTime])
            let tied = try await transport.syncNow()
            #expect(await api.deltas.count == 1)
            #expect(tied.pulled.map(\.id) == [original.id])
            #expect(tied.conflicts.map(\.id) == [sameTime.id])
            #expect(await api.requests.last?.url?.lastPathComponent == "records")
            try await transport.acknowledge(tied)
            let saved = try JSONDecoder().decode(HTTPSyncJournal.self, from: Data(contentsOf: config(root).stateURL))
            #expect(saved.pending.isEmpty && saved.rejections.entries.isEmpty)
            await transport.stop()
        }
    }

    @Test("Namespace and device state stay bound; time validation cannot be disabled")
    func identityAndTime() async throws {
        let device = UUIDV7()
        try await fixture([], device: device) { f in
            await f.transport.stop()
            let other = try HTTPSyncTransport(configuration: config(f.root, namespace: "other"), sendRequest: { try await f.api.send($0) })
            await #expect(throws: HTTPSyncError.self) { try await other.start(deviceId: device) }
            await #expect(throws: HTTPSyncError.self) { try await f.transport.start(deviceId: UUIDV7()) }
            await NTPClient.$testTimeQuery.withValue({ .init(offsetMs: 5001, isValid: false, server: "test", rttMs: 1) }) {
                await #expect(throws: NTPError.self) { try await f.transport.start(deviceId: device) }
            }
            #expect(await f.api.requests.isEmpty)
        }
    }

    @Test("Bodies contain only stage-specific fields, and opaque envelopes retain identity validation")
    func simplifiedWire() throws {
        let change = change(UUIDV7())
        let data = try JSONEncoder().encode(HTTPSyncPushRequest(changes: [change]))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["changes"])
        let rows = try #require(object["changes"] as? [[String: Any]])
        #expect(Set(rows[0].keys) == ["key", "updatedAt", "payload"])
        let response = try JSONEncoder().encode(HTTPSyncPushResponse(rejected: [.init(key: HTTPSyncRecord.key(for: change), sequence: 1)]))
        let body = try #require(try JSONSerialization.jsonObject(with: response) as? [String: Any])
        let rejected = try #require(body["rejected"] as? [[String: Any]])
        #expect(Set(body.keys) == ["rejected"] && Set(rejected[0].keys) == ["key", "sequence"])
        let record = try HTTPSyncRecord(change: change)
        let shared = try SyncRecordEnvelope(change: change)
        #expect(record.key == shared.key && record.payload == shared.payload && record.updatedAt == shared.updatedAt)
        #expect(record.updatedAt == 1788307200125)
        let tampered = HTTPSyncRecord(key: record.key, updatedAt: record.updatedAt + 1, payload: record.payload)
        #expect(throws: HTTPSyncError.self) { try tampered.decodeChange() }
    }

    @Test("Published examples decode with the actual push, pull, lookup and tombstone models")
    func documentationExamples() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let document = try String(contentsOf: root.appendingPathComponent("docs/http-sync-server-api.md"), encoding: .utf8)
        let examples = document.components(separatedBy: "```json\n").dropFirst().map { Data($0.components(separatedBy: "```")[0].utf8) }
        let upload = try JSONDecoder().decode(HTTPSyncPushRequest.self, from: examples[0])
        _ = try JSONDecoder().decode(HTTPSyncPushResponse.self, from: examples[1])
        let pull = try JSONDecoder().decode(HTTPSyncPullResponse.self, from: examples[2])
        let lookup = try JSONDecoder().decode(HTTPSyncLookupRequest.self, from: examples[3])
        let records = try JSONDecoder().decode(HTTPSyncLookupResponse.self, from: examples[4])
        let deletion = try JSONDecoder().decode(HTTPSyncRecord.self, from: examples[5]).decodeChange()
        #expect(upload.changes[0].id == (try pull.changes[0].decodeChange().id))
        #expect(lookup.keys == records.records.map(\.key))
        #expect(deletion.operation == .delete)
    }
}
