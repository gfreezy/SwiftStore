import Foundation

/// Changes only DEFAULT expressions in the original CREATE TABLE text, preserving
/// constraints, generated columns, extra columns, quoting, and table options.
enum TimestampDefaultMigration {
    static func isLegacyDefault(_ value: String) -> Bool {
        let parts = tokens(value).map { range in
            let token = String(value[range])
            return token.hasPrefix("'") ? token : token.lowercased()
        }
        let normalized = parts.filter { $0 != "(" && $0 != ")" }.joined()
        return ["strftime'%s','now'", "unixepoch'subsec'"].contains(normalized)
    }

    static func rewrite(_ sql: String, columns: [ColumnSchema], addedColumns: Set<String> = []) throws -> String {
        let spans = tokens(sql)
        let words = spans.map { String(sql[$0]) }
        var depth = 0
        var column: String?
        var atColumnStart = false
        var replacements: [(Range<String.Index>, String)] = []
        for i in words.indices {
            let word = words[i]
            if atColumnStart {
                column = unquote(word)
                atColumnStart = false
            }
            if word == "(" {
                depth += 1
                if depth == 1 { atColumnStart = true }
            } else if word == ")" {
                depth -= 1
            } else if word == ",", depth == 1 {
                atColumnStart = true
            } else if word.uppercased() == "DEFAULT", depth == 1,
                      let target = columns.first(where: { $0.name == column }),
                      let value = target.defaultValue, i + 1 < words.count {
                var end = i + 1
                if words[end] == "(" {
                    var nesting = 1
                    while nesting > 0, end + 1 < words.count {
                        end += 1
                        if words[end] == "(" { nesting += 1 }
                        if words[end] == ")" { nesting -= 1 }
                    }
                    guard nesting == 0 else { throw Failure.invalidDefinition }
                }
                let range = spans[i + 1].lowerBound..<spans[end].upperBound
                let old = String(sql[range])
                guard isLegacyDefault(old) || (addedColumns.contains(target.name) && Double(old) == 0) else {
                    throw Failure.invalidDefinition
                }
                replacements.append((range, value))
            }
        }
        guard replacements.count == columns.count else { throw Failure.invalidDefinition }
        var result = sql
        for (range, value) in replacements.reversed() { result.replaceSubrange(range, with: value) }
        return result
    }

    enum Failure: Error {
        case invalidDefinition
        case stalePlan
    }

    private static func unquote(_ word: String) -> String {
        guard let first = word.first, let last = word.last else { return word }
        if first == "[", last == "]" { return String(word.dropFirst().dropLast()) }
        if ["\"", "`", "'"].contains(first), last == first {
            return String(word.dropFirst().dropLast())
                .replacingOccurrences(of: String(repeating: String(first), count: 2), with: String(first))
        }
        return word
    }

    /// Keep quoted literals/identifiers intact and omit comments. In particular,
    /// a DEFAULT-looking string literal or comment must never be rewritten.
    private static func tokens(_ sql: String) -> [Range<String.Index>] {
        let pattern = #"--[^\n]*|/\*[\s\S]*?\*/|'(?:''|[^'])*'|"(?:""|[^"])*"|`(?:``|[^`])*`|\[[^\]]*\]|\d+(?:\.\d*)?(?:[eE][+-]?\d+)?|[\p{L}\p{N}_]+|[^\s]"#
        let regex = try! NSRegularExpression(pattern: pattern)
        return regex.matches(in: sql, range: NSRange(sql.startIndex..., in: sql)).compactMap { match in
            guard let range = Range(match.range, in: sql) else { return nil }
            let token = sql[range]
            return token.hasPrefix("--") || token.hasPrefix("/*") ? nil : range
        }
    }

    static func literal(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }
}
