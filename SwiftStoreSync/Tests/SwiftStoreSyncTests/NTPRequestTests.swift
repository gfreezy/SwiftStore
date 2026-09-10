import Darwin
import Foundation
import Testing
@testable import SwiftStoreSync

private final class LoopbackNTPServer: Sendable {
    let descriptor: Int32
    let port: UInt16

    init() throws {
        let socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socket >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket, $0, &length) }
        }
        guard bound == 0, named == 0 else { close(socket); throw POSIXError(.EIO) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        descriptor = socket
        port = UInt16(bigEndian: address.sin_port)
    }

    deinit { close(descriptor) }

    func replyOnce(_ reply: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global().async {
                var buffer = [UInt8](repeating: 0, count: 512)
                var peer = sockaddr_in()
                var length = socklen_t(MemoryLayout<sockaddr_in>.size)
                let received = withUnsafeMutablePointer(to: &peer) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(self.descriptor, &buffer, buffer.count, 0, $0, &length)
                    }
                }
                guard received > 0 else { continuation.resume(throwing: POSIXError(.EIO)); return }
                let sent = reply.withUnsafeBytes { bytes in
                    withUnsafePointer(to: &peer) { pointer in
                        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            sendto(self.descriptor, bytes.baseAddress, reply.count, 0, $0, length)
                        }
                    }
                }
                if sent == reply.count { continuation.resume() }
                else { continuation.resume(throwing: POSIXError(.EIO)) }
            }
        }
    }
}

@Suite("Asynchronous NTP requests")
struct NTPRequestTests {
    @Test("UDP response reaches the caller with send and receive times")
    func reply() async throws {
        let server = try LoopbackNTPServer()
        let packet = Data(repeating: 0, count: 48)
        let request = NTPRequest(server: "127.0.0.1", port: server.port, packet: packet, timeout: .seconds(1))
        let responder = Task { try await server.replyOnce(packet) }
        let result = try await request.response()
        try await responder.value
        #expect(result.data == packet)
        #expect(result.receivedAt >= result.sentAt)
    }

    @Test("A silent UDP peer cannot outlive its request deadline")
    func timeout() async throws {
        let server = try LoopbackNTPServer()
        let request = NTPRequest(server: "127.0.0.1", port: server.port,
                                 packet: Data(repeating: 0, count: 48), timeout: .milliseconds(50))
        let clock = ContinuousClock(), start = ContinuousClock.now
        do {
            _ = try await request.response()
            Issue.record("Expected a request timeout")
        } catch NTPError.timeout { }

        #expect(start.duration(to: clock.now) < .seconds(1))
    }

    @Test("Cancellation releases an in-flight request and a request cancelled before startup")
    func cancellation() async throws {
        let server = try LoopbackNTPServer()
        let request = NTPRequest(server: "127.0.0.1", port: server.port,
                                 packet: Data(repeating: 0, count: 48), timeout: .seconds(10))
        let task = Task { try await request.response() }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        let early = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await NTPRequest(server: "unused.invalid", packet: Data(), timeout: .seconds(10)).response()
        }
        await #expect(throws: CancellationError.self) { try await early.value }
    }
}
