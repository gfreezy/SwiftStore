import Foundation
import SwiftStoreCore
import SwiftStoreMacros
@testable import SwiftStoreSync
import SwiftStoreSyncHTTPTransport

@Entity(tableName: "sync_note")
struct Note {
    var id: UUIDV7 = UUIDV7()
    var title: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

struct Edit: Decodable, Sendable {
    var id: String
    var title: String?
    var timestamp: Double?
}
struct Command: Decodable {
    var directory: String
    var server: URL
    var namespace: String
    var deviceID: UUIDV7
    var edits: [Edit] = []
    var sync: Bool = false
    var rollback: Bool = false
    var offsetMs: Int64 = 0
    var killDuringSync: Bool?
    var duringSync: Edit?
    var requestMarker: String?
}
enum ProbeError: Error { case rollback, timedOut }

@main
@MainActor
struct Worker {
    static func main() async throws {
        let input = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let command = try JSONDecoder().decode(Command.self, from: input)
        try FileManager.default.createDirectory(atPath: command.directory, withIntermediateDirectories: true)
        let db = try SQLiteConnection(path: command.directory + "/data.sqlite")
        try VersionedMigrator(connection: db, migrations: WorkerMigrations.all()).migrate()
        let transport = try HTTPSyncTransport(configuration: HTTPSyncConfiguration(
            serverURL: command.server, namespace: command.namespace, bearerToken: "integration-test",
            stateURL: URL(fileURLWithPath: command.directory + "/transport.json"),
            batchSize: 2, pollInterval: nil, allowInsecureHTTP: true))
        let manager = try SyncManager(connection: db, config: SyncConfig(
            changeLogDbPath: command.directory + "/changes.sqlite", deviceId: command.deviceID,
            registeredEntities: [Note.self], transport: transport, schemaVersion: 1))
        try manager.startTracking()
        func edit(_ edit: Edit) throws {
            let id = UUIDV7(uuidString: edit.id)!
            if let title = edit.title {
                let stamp = edit.timestamp ?? Date().timeIntervalSince1970
                try db.execute("""
                    INSERT INTO sync_note (id,title,created_at,updated_at) VALUES (?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET title=excluded.title,updated_at=excluded.updated_at
                    """, values: [.blob(id.data), .text(title), .real(stamp), .real(stamp)])
            } else {
                try db.execute("DELETE FROM sync_note WHERE id=?", values: [.blob(id.data)])
            }
        }
        do {
            try db.transaction {
                for value in command.edits { try edit(value) }
                if command.rollback { throw ProbeError.rollback }
            }
        } catch ProbeError.rollback {}
        var output: [String: Any] = [:]
        if command.sync {
            let concurrent: Task<Void, Error>?
            if command.duringSync != nil || command.killDuringSync == true {
                concurrent = Task { @MainActor in
                    if let marker = command.requestMarker {
                        var remaining = 1000
                        while !FileManager.default.fileExists(atPath: marker) {
                            try await Task.sleep(for: .milliseconds(10))
                            remaining -= 1
                            guard remaining > 0 else { throw ProbeError.timedOut }
                        }
                    }
                    if command.killDuringSync == true { kill(getpid(), SIGKILL) }
                    if let value = command.duringSync { try edit(value) }
                    if let marker = command.requestMarker {
                        try Data().write(to: URL(fileURLWithPath: marker + ".release"))
                    }
                }
            } else { concurrent = nil }
            do {
                try await NTPClient.$testTimeQuery.withValue({
                    NTPVerificationResult(offsetMs: command.offsetMs, isValid: true,
                                          server: "deterministic-test", rttMs: 1)
                }) {
                    try await manager.startTransport()
                    let result = try await manager.sync()
                    output["pushed"] = result.pushedCount
                    output["pulled"] = result.pulledCount
                    output["conflicts"] = result.conflictCount
                }
            } catch { output["error"] = String(describing: error) }
            if let concurrent { try await concurrent.value }
            await manager.stopTransport()
        }
        output["rows"] = try Note.all(db).map { ["id": $0.id.uuidString, "title": $0.title, "timestamp": $0.updatedAt.timeIntervalSince1970] as [String: Any] }
        output["logCount"] = try manager.allChanges().count
        output["watermark"] = manager.syncState.lastLocalClock
        output["os"] = ProcessInfo.processInfo.operatingSystemVersionString
        output["sqlite"] = try db.queryScalar("SELECT sqlite_version()", type: String.self)
        output["nativeSubsec"] = try db.queryScalar("SELECT typeof(unixepoch('subsec'))", type: String.self)
        print("RESULT " + String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), as: UTF8.self))
    }
}
