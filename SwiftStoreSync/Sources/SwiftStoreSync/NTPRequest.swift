import Foundation
import Network

/// DNS and UDP run through Network.framework so cancellation also ends a
/// request stuck resolving a hostname, rather than blocking a Swift executor.
actor NTPRequest {
    struct Reply: Sendable {
        let data: Data
        let sentAt: Date
        let receivedAt: Date
    }

    private let connection: NWConnection
    private let packet: Data
    private let timeout: Duration
    private var continuation: CheckedContinuation<Reply, Error>?
    private var deadline: Task<Void, Never>?
    private var sentAt: Date?
    private var finished = false

    init(server: String, port: UInt16 = 123, packet: Data, timeout: Duration) {
        connection = NWConnection(host: NWEndpoint.Host(server), port: NWEndpoint.Port(rawValue: port)!, using: .udp)
        self.packet = packet
        self.timeout = timeout
    }

    func response() async throws -> Reply {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                guard !finished else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                deadline = Task {
                    do { try await Task.sleep(for: timeout) }
                    catch { return }
                    finish(.failure(NTPError.timeout))
                }
                connection.stateUpdateHandler = { state in
                    Task { await self.stateChanged(state) }
                }
                connection.start(queue: .global(qos: .utility))
            }
        } onCancel: {
            Task { await self.finish(.failure(CancellationError())) }
        }
    }

    private func stateChanged(_ state: NWConnection.State) {
        guard !finished else { return }
        switch state {
        case .ready:
            guard sentAt == nil else { return }
            sentAt = Date()
            connection.send(content: packet, completion: .contentProcessed { error in
                Task { await self.didSend(error) }
            })
        case .failed(let error), .waiting(let error):
            finish(.failure(NTPError.networkError(error)))
        case .cancelled:
            finish(.failure(CancellationError()))
        default:
            break
        }
    }

    private func didSend(_ error: NWError?) {
        guard !finished else { return }
        if let error {
            finish(.failure(NTPError.networkError(error)))
            return
        }
        guard let sentAt else { return }
        connection.receiveMessage { data, _, _, error in
            let receivedAt = Date()
            let result: Result<Reply, Error>
            if let error { result = .failure(NTPError.networkError(error)) }
            else if let data { result = .success(Reply(data: data, sentAt: sentAt, receivedAt: receivedAt)) }
            else { result = .failure(NTPError.invalidResponse) }
            Task { await self.finish(result) }
        }
    }

    private func finish(_ result: Result<Reply, Error>) {
        guard !finished else { return }
        finished = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        deadline?.cancel()
        deadline = nil
        continuation?.resume(with: result)
        continuation = nil
    }
}
