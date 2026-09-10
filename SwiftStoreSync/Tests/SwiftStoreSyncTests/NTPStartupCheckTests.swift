import Foundation
import Testing
import os
@testable import SwiftStoreSync

private actor SuspendedTimeQuery {
    var calls = 0
    private var reply: CheckedContinuation<NTPVerificationResult, Error>?
    private var started: [CheckedContinuation<Void, Never>] = []

    func query() async throws -> NTPVerificationResult {
        calls += 1
        return try await withCheckedThrowingContinuation { continuation in
            reply = continuation
            for waiter in started { waiter.resume() }
            started.removeAll()
        }
    }

    func waitUntilStarted() async {
        if calls > 0 { return }
        await withCheckedContinuation { started.append($0) }
    }

    // Deliberately ignores cancellation, like a resolver that returns late.
    func complete(offset: Int64 = 0) {
        reply?.resume(returning: .init(offsetMs: offset, isValid: true, server: "test", rttMs: 1))
        reply = nil
    }
}

@Suite("Process startup NTP check")
struct NTPStartupCheckTests {
    @Test("Concurrent and subsequent callers share a single measurement and log")
    func coalescesAndCaches() async throws {
        let query = SuspendedTimeQuery()
        let logs = OSAllocatedUnfairLock(initialState: [String]())
        let check = NTPStartupCheck(query: { try await query.query() }, log: { line in
            logs.withLock { $0.append(line) }
        })
        try await NTPClient.$testStartupCheck.withValue(check) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<32 { group.addTask { try await NTPClient.requireAccurateTime() } }
                await query.waitUntilStarted()
                await query.complete()
                try await group.waitForAll()
            }
            for _ in 0..<10 { try await NTPClient.requireAccurateTime() }
        }
        #expect(await query.calls == 1)
        #expect(logs.withLock { $0.count } == 1)
    }

    @Test("Network failures and timeouts allow every later call without retrying",
          arguments: [NTPError.timeout, .allServersFailed, .invalidResponse,
                      .networkError(URLError(.notConnectedToInternet))])
    func cachesFailure(error: NTPError) async throws {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let logs = OSAllocatedUnfairLock(initialState: [String]())
        let check = NTPStartupCheck(query: {
            calls.withLock { $0 += 1 }
            throw error
        }, log: { line in logs.withLock { $0.append(line) } })
        try await NTPClient.$testStartupCheck.withValue(check) {
            for _ in 0..<5 { try await NTPClient.requireAccurateTime() }
        }
        #expect(calls.withLock { $0 } == 1)
        #expect(logs.withLock { $0.count } == 1)
        #expect(logs.withLock { $0.first?.contains("Allowing sync") } == true)
    }

    @Test("Total deadline releases callers even if DNS ignores cancellation; late results cannot replace fail-open")
    func boundedWaitAndLateReply() async throws {
        let query = SuspendedTimeQuery()
        let logs = OSAllocatedUnfairLock(initialState: [String]())
        let check = NTPStartupCheck(timeout: .milliseconds(50), query: { try await query.query() },
                                    log: { line in logs.withLock { $0.append(line) } })
        try await NTPClient.$testStartupCheck.withValue(check) {
            let clock = ContinuousClock()
            let start = clock.now
            try await NTPClient.requireAccurateTime()
            #expect(start.duration(to: clock.now) < .seconds(1))
            // A contradictory late measurement must not change this launch's decision.
            await query.complete(offset: 60_000)
            try await NTPClient.requireAccurateTime()
        }
        #expect(await query.calls == 1)
        #expect(logs.withLock { $0.count } == 1)
    }

    @Test("Cancelling one caller does not cancel or poison the shared check")
    func callerCancellation() async throws {
        let query = SuspendedTimeQuery()
        let check = NTPStartupCheck(query: { try await query.query() })
        try await NTPClient.$testStartupCheck.withValue(check) {
            let cancelled = Task { try await NTPClient.requireAccurateTime() }
            await query.waitUntilStarted()
            let other = Task { try await NTPClient.requireAccurateTime() }
            cancelled.cancel()
            await query.complete()
            await #expect(throws: CancellationError.self) { try await cancelled.value }
            try await other.value
            try await NTPClient.requireAccurateTime()
        }
        #expect(await query.calls == 1)
    }

    @Test("Different stores apply their own tolerance to the same cached offset")
    func perCallerTolerance() async throws {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let check = NTPStartupCheck(query: {
            calls.withLock { $0 += 1 }
            return .init(offsetMs: 6000, isValid: false, server: "test", rttMs: 1)
        })
        try await NTPClient.$testStartupCheck.withValue(check) {
            await #expect(throws: NTPError.self) { try await NTPClient.requireAccurateTime() }
            try await NTPClient.requireAccurateTime(toleranceMs: 10_000)
            await #expect(throws: NTPError.self) { try await NTPClient.requireAccurateTime() }
        }
        #expect(calls.withLock { $0 } == 1)
    }

    @Test("A fresh process cache measures again after the previous launch failed")
    func freshLaunch() async throws {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        for _ in 0..<2 {
            let check = NTPStartupCheck(query: {
                calls.withLock { $0 += 1 }
                throw NTPError.timeout
            })
            try await NTPClient.$testStartupCheck.withValue(check) {
                try await NTPClient.requireAccurateTime()
                try await NTPClient.requireAccurateTime()
            }
        }
        #expect(calls.withLock { $0 } == 2)
    }
}
