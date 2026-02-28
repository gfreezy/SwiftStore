import Foundation

/// A one-shot async signal that multiple waiters can await.
/// Once signaled, all current and future waiters are resolved immediately.
/// Supports an optional watchdog timeout — if the signal is not fired within
/// the given duration after the first `wait()`, all waiters are automatically
/// failed with `SignalError.timeout`.
actor AsyncSignal {
    private var result: Result<Void, Error>?
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private let timeout: Duration?
    private var watchdogTask: Task<Void, Never>?

    enum SignalError: Error, CustomStringConvertible {
        case timeout(Duration)

        var description: String {
            switch self {
            case .timeout(let duration):
                return "AsyncSignal timed out after \(duration)"
            }
        }
    }

    /// Initialize with an optional watchdog timeout.
    /// - Parameter timeout: If set, the signal automatically fires a timeout error
    ///   after this duration (counted from the first `wait()` call) unless `signal()` is called first.
    init(timeout: Duration? = nil) {
        self.timeout = timeout
    }

    /// Wait for the signal. If already signaled, returns (or throws) immediately.
    func wait() async throws {
        if let result {
            try result.get()
            return
        }
        startWatchdogIfNeeded()
        try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Signal completion. Resumes all current waiters; future `wait()` calls return immediately.
    func signal(result: Result<Void, Error> = .success(())) {
        guard self.result == nil else { return }
        self.result = result
        watchdogTask?.cancel()
        watchdogTask = nil
        for w in waiters {
            w.resume(with: result)
        }
        waiters.removeAll()
    }

    private func startWatchdogIfNeeded() {
        guard let timeout, watchdogTask == nil else { return }
        watchdogTask = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self.signal(result: .failure(SignalError.timeout(timeout)))
        }
    }
}
