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
public enum NTPError: Error {
    case timeout
    case invalidResponse
    case networkError(Error)
    case allServersFailed
}

/// Simple NTP client for time verification
/// Uses SNTP (Simple Network Time Protocol) for basic time synchronization
public final class NTPClient {

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
                ptr.load(fromByteOffset: 40, as: UInt64.self).bigEndian
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

    /// Verify local time against NTP servers
    /// - Parameters:
    ///   - toleranceMs: Maximum acceptable offset in milliseconds (default 5 seconds)
    ///   - servers: NTP servers to query (default Apple, Google, Cloudflare, pool.ntp.org)
    ///   - timeout: Timeout for each server request in seconds
    /// - Returns: Verification result
    public static func verifyTime(
        toleranceMs: Int64 = 5000,
        servers: [String] = defaultServers,
        timeout: TimeInterval = 3.0
    ) async throws -> NTPVerificationResult {
        var lastError: Error = NTPError.allServersFailed

        for server in servers {
            do {
                let result = try await queryServer(server, timeout: timeout, toleranceMs: toleranceMs)
                return result
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError
    }

    /// Query a single NTP server
    private static func queryServer(
        _ server: String,
        timeout: TimeInterval,
        toleranceMs: Int64
    ) async throws -> NTPVerificationResult {
        let socket = try createSocket()
        defer { close(socket) }

        let serverAddress = try resolveAddress(server)

        // Record send time
        let t1 = Date().timeIntervalSince1970

        // Send NTP request
        let request = NTPPacket()
        let requestData = request.toData()
        try sendPacket(socket, data: requestData, to: serverAddress)

        // Set receive timeout
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout.truncatingRemainder(dividingBy: 1)) * 1_000_000))
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Receive response
        let responseData = try receivePacket(socket)

        // Record receive time
        let t4 = Date().timeIntervalSince1970

        guard let response = NTPPacket.fromData(responseData) else {
            throw NTPError.invalidResponse
        }

        // Calculate offset
        // t3 is the NTP server transmit time
        let t3 = ntpToUnix(response.transmitTimestamp)

        // Simplified offset calculation: (t3 - t4)
        // Full calculation would be: ((t2 - t1) + (t3 - t4)) / 2
        // We use simplified because we don't have receive timestamp from server
        let offset = t3 - t4
        let offsetMs = Int64(offset * 1000)

        // RTT is approximately t4 - t1
        let rttMs = Int64((t4 - t1) * 1000)

        return NTPVerificationResult(
            offsetMs: offsetMs,
            isValid: abs(offsetMs) <= toleranceMs,
            server: server,
            rttMs: rttMs
        )
    }

    // MARK: - Socket helpers

    private static func createSocket() throws -> Int32 {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else {
            throw NTPError.networkError(NSError(domain: "NTPClient", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: String(cString: strerror(errno))
            ]))
        }
        return sock
    }

    private static func resolveAddress(_ hostname: String) throws -> sockaddr_in {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(hostname, "123", &hints, &result)

        guard status == 0, let info = result else {
            throw NTPError.networkError(NSError(domain: "NTPClient", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Failed to resolve \(hostname)"
            ]))
        }

        defer { freeaddrinfo(result) }

        let addr = info.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        return addr
    }

    private static func sendPacket(_ socket: Int32, data: Data, to address: sockaddr_in) throws {
        var addr = address
        let sent = data.withUnsafeBytes { ptr in
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    sendto(socket, ptr.baseAddress, data.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        guard sent >= 0 else {
            throw NTPError.networkError(NSError(domain: "NTPClient", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: String(cString: strerror(errno))
            ]))
        }
    }

    private static func receivePacket(_ socket: Int32) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: 48)
        let received = recv(socket, &buffer, buffer.count, 0)

        guard received > 0 else {
            if errno == EAGAIN || errno == EWOULDBLOCK {
                throw NTPError.timeout
            }
            throw NTPError.networkError(NSError(domain: "NTPClient", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: String(cString: strerror(errno))
            ]))
        }

        return Data(buffer[0..<received])
    }
}
