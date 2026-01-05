import Foundation
import SwiftStoreCore

/// Binary encoder/decoder for sync key values
/// Format: [count:UInt8][type1:UInt8][len1:UInt16][data1][type2:UInt8][len2:UInt16][data2]...
public struct SyncKeyEncoder {
    /// Value type markers for binary encoding
    public enum ValueType: UInt8 {
        case uuid = 1      // 16 bytes (fixed)
        case string = 2    // Variable length UTF-8
        case int64 = 3     // 8 bytes (fixed)
        case double = 4    // 8 bytes (fixed)
        case data = 5      // Variable length blob
    }

    /// Encode sync key values to binary Data
    /// - Parameter values: Array of SQLiteValue to encode
    /// - Returns: Binary encoded Data
    public static func encode(_ values: [SQLiteValue]) -> Data {
        var data = Data()
        data.append(UInt8(values.count))

        for value in values {
            switch value {
            case .blob(let bytes):
                // Check if it's a UUIDV7 (16 bytes)
                if bytes.count == 16 {
                    data.append(ValueType.uuid.rawValue)
                    // No length needed for fixed-size UUID
                    data.append(bytes)
                } else {
                    data.append(ValueType.data.rawValue)
                    var length = UInt16(bytes.count)
                    withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
                    data.append(bytes)
                }

            case .text(let str):
                data.append(ValueType.string.rawValue)
                let strData = str.data(using: .utf8) ?? Data()
                var length = UInt16(strData.count)
                withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
                data.append(strData)

            case .integer(let num):
                data.append(ValueType.int64.rawValue)
                // No length needed for fixed-size Int64
                var value = num
                withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }

            case .real(let num):
                data.append(ValueType.double.rawValue)
                // No length needed for fixed-size Double
                var value = num
                withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }

            case .null:
                // Skip null values - sync keys shouldn't have nulls
                break
            }
        }

        return data
    }

    /// Decode binary Data to sync key values
    /// - Parameter data: Binary encoded Data
    /// - Returns: Array of SQLiteValue
    public static func decode(_ data: Data) -> [SQLiteValue] {
        guard !data.isEmpty else { return [] }

        var values: [SQLiteValue] = []
        var offset = 0

        // Read count
        let count = Int(data[offset])
        offset += 1

        for _ in 0..<count {
            guard offset < data.count else { break }

            let typeRaw = data[offset]
            offset += 1

            guard let type = ValueType(rawValue: typeRaw) else { break }

            switch type {
            case .uuid:
                // Fixed 16 bytes
                guard offset + 16 <= data.count else { break }
                let uuidData = data[offset..<offset + 16]
                values.append(.blob(Data(uuidData)))
                offset += 16

            case .string:
                // Variable length
                guard offset + 2 <= data.count else { break }
                let length = data.withUnsafeBytes { ptr in
                    ptr.load(fromByteOffset: offset, as: UInt16.self)
                }
                offset += 2
                guard offset + Int(length) <= data.count else { break }
                let strData = data[offset..<offset + Int(length)]
                let str = String(data: Data(strData), encoding: .utf8) ?? ""
                values.append(.text(str))
                offset += Int(length)

            case .int64:
                // Fixed 8 bytes
                guard offset + 8 <= data.count else { break }
                let value = data.withUnsafeBytes { ptr in
                    ptr.load(fromByteOffset: offset, as: Int64.self)
                }
                values.append(.integer(value))
                offset += 8

            case .double:
                // Fixed 8 bytes
                guard offset + 8 <= data.count else { break }
                let value = data.withUnsafeBytes { ptr in
                    ptr.load(fromByteOffset: offset, as: Double.self)
                }
                values.append(.real(value))
                offset += 8

            case .data:
                // Variable length
                guard offset + 2 <= data.count else { break }
                let length = data.withUnsafeBytes { ptr in
                    ptr.load(fromByteOffset: offset, as: UInt16.self)
                }
                offset += 2
                guard offset + Int(length) <= data.count else { break }
                let blobData = data[offset..<offset + Int(length)]
                values.append(.blob(Data(blobData)))
                offset += Int(length)
            }
        }

        return values
    }
}
