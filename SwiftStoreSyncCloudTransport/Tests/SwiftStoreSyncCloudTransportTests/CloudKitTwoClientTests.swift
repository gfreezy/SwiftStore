import CloudKit
import Foundation
import Testing
import SwiftStoreCore
import SwiftStoreSync
@testable import SwiftStoreSyncCloudTransport

/// Models CloudKit conditional saves, not timestamp arbitration. The real
/// operations adapter must handle serverRecordChanged and select the winner.
/// Revision receipts stand in for SDK-managed change tags at the network boundary;
/// this fixture does not validate Apple account, APNs, or real change-tag encoding.
private actor ConditionalCloud {
    private var current: [CKRecord.ID: CKRecord] = [:]
    private var history: [CKRecord] = []
    private var dropNextResponse = false

    func dropResponse() { dropNextResponse = true }
    var count: Int { history.count }

    func save(_ records: [CKRecord], basedOn versions: [CKRecord.ID: UUIDV7]) throws
        -> [CKRecord.ID: Result<CKRecord, Error>] {
        var results: [CKRecord.ID: Result<CKRecord, Error>] = [:]
        for record in records {
            if let old = current[record.recordID], SyncChange(ckRecord: old)?.id != versions[record.recordID] {
                results[record.recordID] = .failure(CKError(.serverRecordChanged,
                    userInfo: [CKRecordChangedErrorServerRecordKey: old]))
            } else {
                current[record.recordID] = record
                history.append(record)
                results[record.recordID] = .success(record)
            }
        }
        if dropNextResponse { dropNextResponse = false; throw CKError(.networkFailure) }
        return results
    }

    func fetch(_ token: Data?) -> CloudKitChangesPage {
        let offset = token.flatMap { Int(String(decoding: $0, as: UTF8.self)) } ?? 0
        let end = min(offset + 2, history.count)
        return CloudKitChangesPage(records: Array(history[offset..<end]),
            token: Data(String(end).utf8), moreComing: end < history.count)
    }
}

private actor ConditionalCloudClient: CloudKitOperationsClient {
    let server: ConditionalCloud
    private var versions: [CKRecord.ID: UUIDV7] = [:]
    init(_ server: ConditionalCloud) { self.server = server }
    func accountID() -> String { "shared-test-account" }
    func prepareZone(create: Bool) {}
    func save(_ records: [CKRecord]) async throws -> [CKRecord.ID: Result<CKRecord, Error>] {
        let results = try await server.save(records, basedOn: versions)
        for (key, result) in results {
            switch result {
            case .success(let record): versions[key] = SyncChange(ckRecord: record)?.id
            case .failure(let error):
                if let record = (error as? CKError)?.serverRecord {
                    versions[key] = SyncChange(ckRecord: record)?.id
                }
            }
        }
        return results
    }
    func fetch(since token: Data?) async throws -> CloudKitChangesPage {
        let page = await server.fetch(token)
        for record in page.records { versions[record.recordID] = SyncChange(ckRecord: record)?.id }
        return page
    }
}

@Suite("Two independent CloudKit adapter journals")
struct CloudKitTwoClientTests {
    private func change(_ time: Int, device: UUIDV7, delete: Bool = false) -> SyncChange {
        SyncChange(id: UUIDV7(), entityType: "note", syncKey: Data([1]), operation: delete ? .delete : .update,
            payload: delete ? nil : "{\"updatedAt\":\(time)}", deviceId: device, logicalClock: Int64(time),
            createdAt: Date(timeIntervalSinceReferenceDate: Double(time)))
    }

    private func adapter(_ client: ConditionalCloudClient, directory: URL) throws -> CloudKitOperationsTransport {
        var settings = CloudKitOperationsSettings(zoneID: CKRecordZone.ID(zoneName: "two-client"),
            recordType: "Change", namespace: "two-client")
        settings.automaticallySync = false
        return CloudKitOperationsTransport(settings: settings, client: client,
            stateStore: try FileCloudKitSyncStateStore(directory: directory), validateTime: { _ in })
    }

    @Test("Offline edits converge in either order, including deletion and newer recreation", arguments: [false, true])
    func offlineConflicts(newestFirst: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = ConditionalCloud()
        let a = try adapter(ConditionalCloudClient(server), directory: root.appendingPathComponent("a"))
        let b = try adapter(ConditionalCloudClient(server), directory: root.appendingPathComponent("b"))
        let deviceA = UUIDV7(), deviceB = UUIDV7()
        try await a.start(deviceId: deviceA)
        try await b.start(deviceId: deviceB)
        let old = change(10, device: deviceA), newer = change(20, device: deviceB)
        try await a.enqueue([old])
        try await b.enqueue([newer])
        if newestFirst { _ = try await b.syncNow(); _ = try await a.syncNow() }
        else { _ = try await a.syncNow(); _ = try await b.syncNow() }
        for transport in [a, b] {
            let result = try await transport.syncNow()
            #expect(result.pulled.map(\.id) == [newer.id])
            try await transport.acknowledge(result)
        }
        let stale = change(25, device: deviceA), deletion = change(30, device: deviceB, delete: true)
        try await a.enqueue([stale])
        try await b.enqueue([deletion])
        _ = try await b.syncNow()
        for transport in [a, b] {
            let result = try await transport.syncNow()
            #expect(result.pulled.map(\.id) == [deletion.id])
            try await transport.acknowledge(result)
        }
        let recreated = change(40, device: deviceA)
        try await a.enqueue([recreated])
        for transport in [a, b] {
            let result = try await transport.syncNow()
            #expect(result.pulled.map(\.id) == [recreated.id])
            try await transport.acknowledge(result)
            #expect(try await transport.syncNow().pulled.isEmpty)
            await transport.stop()
        }
    }

    @Test("Lost commit receipt survives journal restart; equal-time remote edit keeps first commit")
    func restartAndTie() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = ConditionalCloud(), deviceA = UUIDV7(), deviceB = UUIDV7()
        let directoryA = root.appendingPathComponent("a")
        let a = try adapter(ConditionalCloudClient(server), directory: directoryA)
        let b = try adapter(ConditionalCloudClient(server), directory: root.appendingPathComponent("b"))
        let winner = change(10, device: deviceA), tie = change(10, device: deviceB)
        try await a.start(deviceId: deviceA)
        try await a.enqueue([winner])
        await server.dropResponse()
        await #expect(throws: CKError.self) { try await a.syncNow() }
        await a.stop()
        let restarted = try adapter(ConditionalCloudClient(server), directory: directoryA)
        try await restarted.start(deviceId: deviceA)
        let result = try await restarted.syncNow()
        #expect(result.pulled.map(\.id) == [winner.id])
        try await restarted.acknowledge(result)
        try await b.start(deviceId: deviceB)
        try await b.enqueue([tie])
        let other = try await b.syncNow()
        #expect(other.pulled.map(\.id) == [winner.id])
        #expect(await server.count == 1)
        await restarted.stop()
        await b.stop()
    }
}
