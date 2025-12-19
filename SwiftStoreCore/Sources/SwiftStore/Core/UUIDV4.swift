import Foundation

/// A type-safe wrapper for UUID v4
/// Used to enforce that entity IDs are valid UUID v4 values
public struct UUIDV4: Hashable, Sendable, Codable, CustomStringConvertible {
    public let uuid: UUID

    /// Create a new random UUID v4
    public init() {
        self.uuid = UUID()
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

extension UUIDV4: Identifiable {
    public var id: UUIDV4 { self }
}

// MARK: - ExpressibleByStringLiteral (for convenience in tests)

extension UUIDV4: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        guard let uuid = UUID(uuidString: value) else {
            fatalError("Invalid UUID string literal: \(value)")
        }
        self.uuid = uuid
    }
}

// MARK: - SQLite Support

extension UUIDV4: SQLiteComparable {
    public var sqliteValue: SQLiteValue {
        .blob(data)
    }
}
