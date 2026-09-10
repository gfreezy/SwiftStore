import Foundation

/// Formats JSON syntax only. Encoded string tokens (including SQL whitespace and escapes)
/// are copied verbatim, rather than parsed and rewritten or processed with replacements.
enum SchemaJSON {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let input = Array(try encoder.encode(value))
        var output = [UInt8]()
        var depth = 0
        var inString = false
        var escaped = false
        func newline() {
            output.append(10)
            output.append(contentsOf: repeatElement(32, count: depth * 2))
        }
        for (index, byte) in input.enumerated() {
            if inString {
                output.append(byte)
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { inString = false }
                continue
            }
            switch byte {
            case 34:
                inString = true
                output.append(byte)
            case 123, 91: // { [
                output.append(byte)
                depth += 1
                if input[index + 1] != (byte == 123 ? 125 : 93) { newline() }
            case 125, 93: // } ]
                depth -= 1
                if input[index - 1] != (byte == 125 ? 123 : 91) { newline() }
                output.append(byte)
            case 44:
                output.append(byte)
                newline()
            case 58:
                output.append(contentsOf: [58, 32])
            default:
                output.append(byte)
            }
        }
        return Data(output)
    }
}
