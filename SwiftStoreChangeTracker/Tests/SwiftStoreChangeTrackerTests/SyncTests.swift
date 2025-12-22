import Testing
import Foundation
@testable import SwiftStoreChangeTracker

@Suite("Hybrid Clock Tests")
struct HybridClockTests {
    @Test("Hybrid clock ticks increment")
    func testHybridClock() {
        var clock = HybridClock()

        let tick1 = clock.tick()
        let tick2 = clock.tick()

        #expect(tick2 > tick1)

        let logicalTime = HybridClock.logicalTime(from: tick1)
        #expect(logicalTime > 0)
    }
}
