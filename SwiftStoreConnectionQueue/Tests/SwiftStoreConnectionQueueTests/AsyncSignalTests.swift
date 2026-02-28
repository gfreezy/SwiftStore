import Testing

@testable import SwiftStoreConnectionQueue

@Suite("AsyncSignal")
struct AsyncSignalTests {
    @Test("wait returns immediately after signal")
    func waitAfterSignal() async throws {
        let signal = AsyncSignal()
        await signal.signal()
        try await signal.wait()
    }

    @Test("wait suspends until signal is called")
    func waitBeforeSignal() async throws {
        let signal = AsyncSignal()
        let started = Lock(false)
        let finished = Lock(false)

        Task {
            started.setValue(true)
            try await signal.wait()
            finished.setValue(true)
        }

        // Give the task time to start and suspend
        try await Task.sleep(for: .milliseconds(50))
        #expect(started.value() == true)
        #expect(finished.value() == false)

        await signal.signal()
        try await Task.sleep(for: .milliseconds(50))
        #expect(finished.value() == true)
    }

    @Test("multiple waiters all resume on signal")
    func multipleWaiters() async throws {
        let signal = AsyncSignal()
        let count = Lock(0)

        for _ in 0..<5 {
            Task {
                try await signal.wait()
                count.withLock { $0 += 1 }
            }
        }

        try await Task.sleep(for: .milliseconds(50))
        #expect(count.value() == 0)

        await signal.signal()
        try await Task.sleep(for: .milliseconds(50))
        #expect(count.value() == 5)
    }

    @Test("signal with error propagates to waiters")
    func signalWithError() async throws {
        let signal = AsyncSignal()
        struct TestError: Error {}

        Task { await signal.signal(result: .failure(TestError())) }

        try await Task.sleep(for: .milliseconds(50))
        await #expect(throws: TestError.self) {
            try await signal.wait()
        }
    }

    @Test("signal is idempotent — second signal is ignored")
    func signalIdempotent() async throws {
        let signal = AsyncSignal()
        struct TestError: Error {}

        await signal.signal()
        await signal.signal(result: .failure(TestError()))

        // Should succeed because only the first signal counts
        try await signal.wait()
    }

    @Test("watchdog fires timeout when signal is not called")
    func watchdogTimeout() async throws {
        let signal = AsyncSignal(timeout: .milliseconds(100))

        await #expect(throws: AsyncSignal.SignalError.self) {
            try await signal.wait()
        }
    }

    @Test("watchdog is cancelled when signal fires before timeout")
    func watchdogCancelledBySignal() async throws {
        let signal = AsyncSignal(timeout: .milliseconds(200))

        Task {
            try await Task.sleep(for: .milliseconds(50))
            await signal.signal()
        }

        try await signal.wait()
    }

    @Test("wait after timeout also throws")
    func waitAfterTimeout() async throws {
        let signal = AsyncSignal(timeout: .milliseconds(50))

        // Trigger watchdog by calling wait
        await #expect(throws: AsyncSignal.SignalError.self) {
            try await signal.wait()
        }

        // Subsequent wait should also throw the cached timeout error
        await #expect(throws: AsyncSignal.SignalError.self) {
            try await signal.wait()
        }
    }
}
