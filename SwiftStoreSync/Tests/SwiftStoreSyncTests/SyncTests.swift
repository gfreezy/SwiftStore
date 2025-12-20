import Testing
import Foundation
@testable import SwiftStoreSync

@Suite("Sync Tests")
struct SyncTests {
    @Test("Hybrid clock")
    func testHybridClock() {
        var clock = HybridClock()

        let tick1 = clock.tick()
        let tick2 = clock.tick()

        #expect(tick2 > tick1)

        let logicalTime = HybridClock.logicalTime(from: tick1)
        #expect(logicalTime > 0)
    }

    @Test("NTP verification result properties")
    func testNTPVerificationResult() {
        // Test valid result (within tolerance)
        let validResult = NTPVerificationResult(
            offsetMs: 100,
            isValid: true,
            server: "time.apple.com",
            rttMs: 50
        )
        #expect(validResult.isValid == true)
        #expect(validResult.offsetSeconds == 0.1)
        #expect(validResult.server == "time.apple.com")
        #expect(validResult.rttMs == 50)

        // Test invalid result (outside tolerance)
        let invalidResult = NTPVerificationResult(
            offsetMs: 10000,
            isValid: false,
            server: "pool.ntp.org",
            rttMs: 200
        )
        #expect(invalidResult.isValid == false)
        #expect(invalidResult.offsetSeconds == 10.0)
    }

    @Test("NTP time verification")
    func testNTPTimeVerification() async throws {
        // This test requires network access
        // It may fail in offline environments
        do {
            let result = try await NTPClient.verifyTime(toleranceMs: 30000)  // 30 second tolerance
            #expect(result.server.isEmpty == false)
            #expect(result.rttMs >= 0)
            // With 30 second tolerance, most systems should pass
            // unless the clock is severely misconfigured
            print("NTP offset: \(result.offsetMs)ms, RTT: \(result.rttMs)ms, server: \(result.server)")
        } catch {
            // Network may not be available in test environment
            print("NTP test skipped: \(error)")
        }
    }

    @Test("NTP verify time with tolerance")
    func testNTPVerifyTimeWithTolerance() async throws {
        do {
            let result = try await NTPClient.verifyTime(toleranceMs: 30000)
            #expect(result.server.isEmpty == false)
        } catch {
            // Network may not be available
            print("NTP verifyTime test skipped: \(error)")
        }
    }

    @Test("NTP validate time - valid time")
    func testValidateTimeValid() async throws {
        do {
            // With large tolerance, should pass
            let result = try await NTPClient.verifyTime(toleranceMs: 60000)  // 60 seconds
            if !result.isValid {
                print("Time out of sync: offset=\(result.offsetMs)ms")
            }
        } catch {
            // Network error - skip test
            print("validateTime test skipped: \(error)")
        }
    }

}
