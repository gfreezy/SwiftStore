import Foundation

/// Time-ordered UUID (similar to UUID v7, RFC 9562)
///
/// Format (128 bits):
/// ```
/// 0                   1                   2                   3
/// 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                          timestamp_ms (32 bits)               |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |           timestamp_ms (16 bits)      |  ver  | rand (12 bits)|
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |var|                    rand (62 bits)                         |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                          rand (32 bits)                       |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// ```
///
/// - First 48 bits: Unix timestamp in milliseconds
/// - Version: 7 (bits 48-51)
/// - Variant: RFC 4122 (bits 64-65)
/// - Remaining: Random data
///
/// Benefits:
/// - Time-ordered: UUIDs created later sort after earlier ones
/// - Better database index performance (sequential inserts)
/// - Timestamp can be extracted from UUID
public struct UUIDV7: Hashable, Sendable, Codable, CustomStringConvertible, Comparable {
    public let uuid: UUID

    /// Create a new time-ordered UUID
    public init() {
        self.uuid = Self.generateTimeOrdered()
    }

    /// Create from an existing UUID
    /// - Parameter uuid: The UUID to wrap
    public init(_ uuid: UUID) {
        self.uuid = uuid
    }

    /// Create from a UUID string
    /// - Parameter uuidString: The string representation of a UUID
    /// - Returns: nil if the string is not a valid UUID
    public init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else {
            return nil
        }
        self.uuid = uuid
    }

    public var uuidString: String {
        uuid.uuidString
    }

    public var description: String {
        uuid.uuidString
    }

    // MARK: - Time Extraction

    /// Extract the timestamp from a time-ordered UUID
    /// - Returns: The Date when this UUID was created, or nil if not a v7 UUID
    public var timestamp: Date? {
        let bytes = uuid.uuid
        // Check version (should be 7)
        let version = (bytes.6 >> 4) & 0x0F
        guard version == 7 else { return nil }

        // Extract 48-bit timestamp (milliseconds since Unix epoch)
        let ms: UInt64 =
            (UInt64(bytes.0) << 40) |
            (UInt64(bytes.1) << 32) |
            (UInt64(bytes.2) << 24) |
            (UInt64(bytes.3) << 16) |
            (UInt64(bytes.4) << 8) |
            UInt64(bytes.5)

        return Date(timeIntervalSince1970: Double(ms) / 1000.0)
    }

    // MARK: - Binary Data Support

    /// Returns the UUID as 16-byte binary data
    public var data: Data {
        withUnsafeBytes(of: uuid.uuid) { Data($0) }
    }

    /// Create from 16-byte binary data
    /// - Parameter data: 16 bytes representing the UUID
    /// - Returns: nil if data is not exactly 16 bytes
    public init?(data: Data) {
        guard data.count == 16 else { return nil }
        let uuid = data.withUnsafeBytes { ptr -> UUID in
            UUID(uuid: ptr.load(as: uuid_t.self))
        }
        self.uuid = uuid
    }

    // MARK: - Comparable

    public static func < (lhs: UUIDV7, rhs: UUIDV7) -> Bool {
        // Compare as big-endian bytes for correct time ordering
        let lhsBytes = lhs.uuid.uuid
        let rhsBytes = rhs.uuid.uuid

        // Compare byte by byte
        if lhsBytes.0 != rhsBytes.0 { return lhsBytes.0 < rhsBytes.0 }
        if lhsBytes.1 != rhsBytes.1 { return lhsBytes.1 < rhsBytes.1 }
        if lhsBytes.2 != rhsBytes.2 { return lhsBytes.2 < rhsBytes.2 }
        if lhsBytes.3 != rhsBytes.3 { return lhsBytes.3 < rhsBytes.3 }
        if lhsBytes.4 != rhsBytes.4 { return lhsBytes.4 < rhsBytes.4 }
        if lhsBytes.5 != rhsBytes.5 { return lhsBytes.5 < rhsBytes.5 }
        if lhsBytes.6 != rhsBytes.6 { return lhsBytes.6 < rhsBytes.6 }
        if lhsBytes.7 != rhsBytes.7 { return lhsBytes.7 < rhsBytes.7 }
        if lhsBytes.8 != rhsBytes.8 { return lhsBytes.8 < rhsBytes.8 }
        if lhsBytes.9 != rhsBytes.9 { return lhsBytes.9 < rhsBytes.9 }
        if lhsBytes.10 != rhsBytes.10 { return lhsBytes.10 < rhsBytes.10 }
        if lhsBytes.11 != rhsBytes.11 { return lhsBytes.11 < rhsBytes.11 }
        if lhsBytes.12 != rhsBytes.12 { return lhsBytes.12 < rhsBytes.12 }
        if lhsBytes.13 != rhsBytes.13 { return lhsBytes.13 < rhsBytes.13 }
        if lhsBytes.14 != rhsBytes.14 { return lhsBytes.14 < rhsBytes.14 }
        return lhsBytes.15 < rhsBytes.15
    }

    // MARK: - Private

    /// Generate a time-ordered UUID (v7 format)
    private static func generateTimeOrdered() -> UUID {
        // Get current timestamp in milliseconds
        let now = Date()
        let ms = UInt64(now.timeIntervalSince1970 * 1000)

        // Generate random bytes
        var randomBytes = [UInt8](repeating: 0, count: 10)
        _ = SecRandomCopyBytes(kSecRandomDefault, 10, &randomBytes)

        // Build UUID bytes
        let bytes: [UInt8] = [
            // Timestamp (48 bits, big-endian)
            UInt8((ms >> 40) & 0xFF),
            UInt8((ms >> 32) & 0xFF),
            UInt8((ms >> 24) & 0xFF),
            UInt8((ms >> 16) & 0xFF),
            UInt8((ms >> 8) & 0xFF),
            UInt8(ms & 0xFF),
            // Version 7 + random (4 bits version + 12 bits random)
            (0x70 | (randomBytes[0] & 0x0F)),
            randomBytes[1],
            // Variant (2 bits) + random (6 bits)
            (0x80 | (randomBytes[2] & 0x3F)),
            // Random (56 bits)
            randomBytes[3],
            randomBytes[4],
            randomBytes[5],
            randomBytes[6],
            randomBytes[7],
            randomBytes[8],
            randomBytes[9]
        ]

        // Create uuid_t tuple
        let uuidTuple: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )

        return UUID(uuid: uuidTuple)
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let uuid = UUID(uuidString: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid UUID string: \(string)"
            )
        }
        self.uuid = uuid
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(uuid.uuidString)
    }
}

// MARK: - Identifiable

extension UUIDV7: Identifiable {
    public var id: UUIDV7 { self }
}

// MARK: - ExpressibleByStringLiteral (for convenience in tests)

extension UUIDV7: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        guard let uuid = UUID(uuidString: value) else {
            fatalError("Invalid UUID string literal: \(value)")
        }
        self.uuid = uuid
    }
}
