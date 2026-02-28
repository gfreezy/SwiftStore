/// A one-shot async signal that multiple waiters can await.
/// Once signaled, all current and future waiters are resolved immediately.
actor AsyncSignal {
    private var result: Result<Void, Error>?
    private var waiters: [CheckedContinuation<Void, Error>] = []

    /// Wait for the signal. If already signaled, returns (or throws) immediately.
    func wait() async throws {
        if let result {
            try result.get()
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Signal success. Resumes all current waiters; future `wait()` calls return immediately.
    func signal(result: Result<Void, Error> = .success(())) {
        guard self.result == nil else { return }
        self.result = result
        for w in waiters {
            w.resume(with: result)
        }
        waiters.removeAll()
    }
}
