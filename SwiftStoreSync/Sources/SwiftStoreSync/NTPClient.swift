import Foundation

/// NTP time verification result
public struct NTPVerificationResult: Sendable {
    /// Offset between local time and NTP time in milliseconds
    public let offsetMs: Int64
    /// Whether the offset is within acceptable tolerance
    public let isValid: Bool
    /// NTP server used
    public let server: String
    /// Round trip time in milliseconds
    public let rttMs: Int64

    public var offsetSeconds: Double {
        Double(offsetMs) / 1000.0
    }
}

/// NTP time verification error
public enum NTPError: Error, LocalizedError {
    case invalidTolerance
    case timeout
    case invalidResponse
    case networkError(Error)
    case allServersFailed
    case timeOutOfSync(offsetMs: Int64, toleranceMs: Int64)

    public var errorDescription: String? {
        switch self {
        case .invalidTolerance:
            return "Sync time tolerance must be positive; time verification cannot be disabled."
        case .timeout:
            return "NTP request timed out"
        case .invalidResponse:
            return "Invalid NTP response"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .allServersFailed:
            return "All NTP servers failed"
        case .timeOutOfSync(let offsetMs, let toleranceMs):
            return "Device time is out of sync by \(offsetMs)ms (tolerance: \(toleranceMs)ms)"
        }
    }
}

/// Simple NTP client for time verification
/// Uses SNTP (Simple Network Time Protocol) for basic time synchronization
public final class NTPClient {
    private static let startupCheck = NTPStartupCheck {
        try await verifyTime()
    }

    // Tests get a fresh process-lifetime cache without affecting other tests.
    @TaskLocal static var testStartupCheck: NTPStartupCheck?

    /// Checks network time at the first sync in this process, with a total
    /// deadline of three seconds. Concurrent callers share the check; later
    /// calls reuse its result, including network failure/timeout (fail open).
    /// A measured offset outside the caller's tolerance still rejects sync.
    public static func requireAccurateTime(toleranceMs: Int64 = 5000) async throws {
        guard toleranceMs > 0 else { throw NTPError.invalidTolerance }
        try Task.checkCancellation()
        let outcome = await (testStartupCheck ?? startupCheck).result()
        try Task.checkCancellation()
        if case .measured(let result) = outcome {
            // Avoid abs(Int64.min), and apply each caller's configured tolerance.
            guard result.offsetMs >= -toleranceMs, result.offsetMs <= toleranceMs else {
                throw NTPError.timeOutOfSync(offsetMs: result.offsetMs, toleranceMs: toleranceMs)
            }
        }
    }

    /// Default NTP servers
    public static let defaultServers = [
        "time.apple.com",
        "pool.ntp.org",
        "time.google.com",
        "time.cloudflare.com"
    ]

    /// NTP packet structure (48 bytes)
    private struct NTPPacket {
        var flags: UInt8           // LI, VN, Mode
        var stratum: UInt8
        var poll: UInt8
        var precision: Int8
        var rootDelay: UInt32
        var rootDispersion: UInt32
        var referenceId: UInt32
        var referenceTimestamp: UInt64
        var originateTimestamp: UInt64
        var receiveTimestamp: UInt64
        var transmitTimestamp: UInt64

        static let size = 48

        init() {
            // Version 3, Mode 3 (Client)
            flags = 0x1B
            stratum = 0
            poll = 0
            precision = 0
            rootDelay = 0
            rootDispersion = 0
            referenceId = 0
            referenceTimestamp = 0
            originateTimestamp = 0
            receiveTimestamp = 0
            transmitTimestamp = 0
        }

        func toData() -> Data {
            var data = Data(count: NTPPacket.size)
            data[0] = flags
            data[1] = stratum
            data[2] = poll
            data[3] = UInt8(bitPattern: precision)
            // Rest is zeros for client request
            return data
        }

        static func fromData(_ data: Data) -> NTPPacket? {
            guard data.count >= size else { return nil }

            var packet = NTPPacket()
            packet.flags = data[0]
            packet.stratum = data[1]
            packet.poll = data[2]
            packet.precision = Int8(bitPattern: data[3])

            // Parse transmit timestamp (bytes 40-47)
            packet.transmitTimestamp = data.withUnsafeBytes { ptr in
                ptr.loadUnaligned(fromByteOffset: 40, as: UInt64.self).bigEndian
            }

            return packet
        }
    }

    /// NTP epoch is January 1, 1900
    private static let ntpEpochOffset: TimeInterval = 2208988800

    /// Convert NTP timestamp to Unix timestamp (seconds since 1970)
    private static func ntpToUnix(_ ntp: UInt64) -> TimeInterval {
        let seconds = Double(ntp >> 32)
        let fraction = Double(ntp & 0xFFFFFFFF) / Double(UInt32.max)
        return seconds + fraction - ntpEpochOffset
    }

    /// Perform an uncached network measurement. Sync uses `requireAccurateTime` instead.
    /// - Parameters:
    ///   - toleranceMs: Maximum acceptable offset in milliseconds (default 5 seconds)
    ///   - servers: NTP servers to query (default Apple, Google, Cloudflare, pool.ntp.org)
    ///   - timeout: Total time budget in seconds, including DNS and server fallback
    /// - Returns: Verification result
    public static func verifyTime(
        toleranceMs: Int64 = 5000,
        servers: [String] = defaultServers,
        timeout: TimeInterval = 3.0
    ) async throws -> NTPVerificationResult {
        guard toleranceMs > 0 else { throw NTPError.invalidTolerance }
        guard timeout.isFinite, timeout > 0 else { throw NTPError.timeout }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        var lastError: Error = NTPError.allServersFailed

        for (index, server) in servers.enumerated() {
            try Task.checkCancellation()
            let remaining = clock.now.duration(to: deadline)
            guard remaining > .zero else { throw NTPError.timeout }
            // Reserve time for fallbacks so a silent first server cannot consume
            // the entire startup budget. Each request's deadline includes DNS.
            let attemptTimeout = remaining / (servers.count - index)
            do {
                return try await queryServer(server, timeout: attemptTimeout, toleranceMs: toleranceMs)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Query a single NTP server
    private static func queryServer(
        _ server: String,
        timeout: Duration,
        toleranceMs: Int64
    ) async throws -> NTPVerificationResult {
        let reply = try await NTPRequest(server: server, packet: NTPPacket().toData(), timeout: timeout).response()
        guard let response = NTPPacket.fromData(reply.data) else {
            throw NTPError.invalidResponse
        }
        let t3 = ntpToUnix(response.transmitTimestamp)
        let offsetMs = Int64((t3 - reply.receivedAt.timeIntervalSince1970) * 1000)
        let rttMs = Int64(reply.receivedAt.timeIntervalSince(reply.sentAt) * 1000)
        return NTPVerificationResult(
            offsetMs: offsetMs,
            isValid: offsetMs >= -toleranceMs && offsetMs <= toleranceMs,
            server: server,
            rttMs: rttMs
        )
    }
}
