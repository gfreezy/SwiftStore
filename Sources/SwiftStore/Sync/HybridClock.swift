import Foundation

/// Hybrid Logical Clock for distributed sync
public struct HybridClock: Sendable {
    private var logical: Int64 = 0
    private var counter: Int32 = 0

    public init() {}

    /// Generate next clock value
    public mutating func tick() -> Int64 {
        let physical = Int64(Date().timeIntervalSince1970 * 1000)

        if physical > logical {
            logical = physical
            counter = 0
        } else {
            counter += 1
        }

        // High 48 bits are logical time, low 16 bits are counter
        return (logical << 16) | Int64(counter & 0xFFFF)
    }

    /// Update clock when receiving remote message
    public mutating func update(received: Int64) {
        let receivedLogical = received >> 16
        let physical = Int64(Date().timeIntervalSince1970 * 1000)
        logical = max(logical, max(receivedLogical, physical))
    }

    /// Current clock value without incrementing
    public var current: Int64 {
        (logical << 16) | Int64(counter & 0xFFFF)
    }

    /// Extract logical time from clock value
    public static func logicalTime(from clock: Int64) -> Int64 {
        clock >> 16
    }

    /// Extract counter from clock value
    public static func counter(from clock: Int64) -> Int32 {
        Int32(clock & 0xFFFF)
    }
}
