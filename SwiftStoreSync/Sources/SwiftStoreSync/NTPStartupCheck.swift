import Foundation
import SwiftStoreCore

/// One measurement per process, including a cached fail-open decision. Each
/// caller still applies its own tolerance to a successful measurement.
actor NTPStartupCheck {
    enum Outcome: Sendable {
        case measured(NTPVerificationResult)
        case unavailable(String)
    }

    private let timeout: Duration
    private let query: @Sendable () async throws -> NTPVerificationResult
    private let log: @Sendable (String) -> Void
    private var outcome: Outcome?
    private var waiters: [CheckedContinuation<Outcome, Never>] = []
    private var request: Task<Void, Never>?
    private var deadline: Task<Void, Never>?

    init(timeout: Duration = .seconds(3),
         query: @escaping @Sendable () async throws -> NTPVerificationResult,
         log: @escaping @Sendable (String) -> Void = { SwiftStoreLogger.info($0) }) {
        self.timeout = timeout
        self.query = query
        self.log = log
    }

    func result() async -> Outcome {
        if let outcome { return outcome }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
            guard request == nil else { return }
            let query = query
            request = Task {
                do { finish(.measured(try await query())) }
                catch { finish(.unavailable(error.localizedDescription)) }
            }
            deadline = Task {
                do { try await Task.sleep(for: timeout) }
                catch { return }
                finish(.unavailable(NTPError.timeout.localizedDescription))
            }
        }
    }

    private func finish(_ value: Outcome) {
        // A cancelled request can finish late; it must never replace the
        // decision already shared with callers or emit a second log entry.
        guard outcome == nil else { return }
        outcome = value
        request?.cancel()
        deadline?.cancel()
        request = nil
        deadline = nil
        switch value {
        case .measured(let result):
            log("Startup NTP check: \(result.server), offset \(result.offsetMs)ms; reusing this measurement for the process lifetime.")
        case .unavailable(let reason):
            log("Startup NTP check unavailable: \(reason). Allowing sync without time verification; no retry until the next process launch.")
        }
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume(returning: value) }
    }
}
