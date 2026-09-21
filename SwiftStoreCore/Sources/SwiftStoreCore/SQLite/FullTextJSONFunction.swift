import Foundation
import SQLite3
import SwiftStoreProtocols

/// Pure JSON projection used by array FTS views and their maintenance triggers.
/// Keep this function's v1 semantics stable: its name is persisted in migration SQL.
enum FullTextJSONFunction {
    static let name = "swiftstore_fts_text_v1"

    static func register(on database: OpaquePointer) throws {
        let status = sqlite3_create_function_v2(database, name, 2,
            SQLITE_UTF8 | SQLITE_DETERMINISTIC | SQLITE_INNOCUOUS, nil, { context, count, values in
                guard let context, count == 2, let values else { return }
                guard let ruleData = FullTextJSONFunction.data(values[1]),
                      let paths = try? JSONDecoder().decode([String].self, from: ruleData),
                      paths.count >= 2,
                      let components = FullTextJSONFunction.components(paths) else {
                    sqlite3_result_error(context, "Invalid SwiftStore full-text array projection", -1)
                    return
                }
                // Missing or malformed JSON contributes no text, matching missing arrays.
                let text: String
                if let input = FullTextJSONFunction.data(values[0]),
                   let json = try? JSONSerialization.jsonObject(with: input, options: [.fragmentsAllowed]) {
                    text = FullTextJSONFunction.extract(json, paths: components)
                } else {
                    text = ""
                }
                guard text.utf8.count <= Int(Int32.max) else {
                    sqlite3_result_error_toobig(context)
                    return
                }
                text.withCString { pointer in
                    sqlite3_result_text(context, pointer, Int32(text.utf8.count),
                        unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            }, nil, nil, nil)
        guard status == SQLITE_OK else {
            throw StoreError.queryFailed("Cannot register SwiftStore full-text JSON function: \(status)")
        }
    }

    private static func data(_ value: OpaquePointer?) -> Data? {
        guard sqlite3_value_type(value) == SQLITE_TEXT,
              let pointer = sqlite3_value_text(value) else { return nil }
        return Data(bytes: pointer, count: Int(sqlite3_value_bytes(value)))
    }

    /// Arrays use property-only paths emitted by the macro, not arbitrary SQLite JSON paths.
    static func components(_ paths: [String]) -> [[String]]? {
        var result: [[String]] = []
        for path in paths {
            if path == "$" { result.append([]); continue }
            guard path.hasPrefix("$."), !path.contains("\0") else { return nil }
            let keys = path.dropFirst(2).split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard keys.allSatisfy({ !$0.isEmpty && !$0.contains(where: { "[]\"\\".contains($0) }) }) else { return nil }
            result.append(keys)
        }
        return result
    }

    private static func value(_ root: Any, at path: [String]) -> Any? {
        var current = root
        for key in path {
            guard let object = current as? [String: Any], let next = object[key] else { return nil }
            current = next
        }
        return current
    }

    private static func extract(_ json: Any, paths: [[String]]) -> String {
        var elements: [Any] = [json]
        for path in paths.dropLast() {
            elements = elements.flatMap { value($0, at: path) as? [Any] ?? [] }
        }
        let leaf = paths[paths.count - 1]
        return elements.compactMap { value($0, at: leaf) as? String }.joined(separator: "\n")
    }
}
