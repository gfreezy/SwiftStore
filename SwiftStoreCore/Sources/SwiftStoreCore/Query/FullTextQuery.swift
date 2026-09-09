import Foundation

public extension Query {
    /// Search for a literal phrase. Quotes and FTS operators in user input are treated as text.
    /// With multiple indexes, supply the name declared by #FullTextIndex.
    func search(_ text: String, index name: String? = nil) throws -> Query<T> {
        let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let index = try fullTextIndex(named: name)
        guard !phrase.isEmpty else { return filter(Predicate(sql: "0")) }
        return filter(fullTextPredicate("\"" + phrase.replacingOccurrences(of: "\"", with: "\"\"") + "\"", index: index))
    }

    /// Search with explicit FTS5 syntax (AND/OR, prefixes, phrases and column filters).
    /// Invalid expressions throw when the query is executed. Values are always SQL parameters.
    func matching(_ expression: String, index name: String? = nil) throws -> Query<T> {
        filter(fullTextPredicate(expression, index: try fullTextIndex(named: name)))
    }

    private func fullTextIndex(named name: String?) throws -> FullTextIndexDefinition {
        if let name, let index = T.fullTextIndexes.first(where: { $0.name == name }) { return index }
        if name == nil, T.fullTextIndexes.count == 1 { return T.fullTextIndexes[0] }
        throw StoreError.queryFailed("Choose a declared full-text index for \(T.tableName); available: \(T.fullTextIndexes.map(\.name).joined(separator: ", "))")
    }

    private func fullTextPredicate(_ expression: String, index: FullTextIndexDefinition) -> Predicate<T> {
        let q = FullTextSchema.quote
        let keys = index.keyColumns.map(q).joined(separator: ", ")
        let selected = index.keyColumns.map { "m.\(q($0))" }.joined(separator: ", ")
        let sql = """
            (\(keys)) IN (
                SELECT \(selected) FROM \(q("__swiftstore_fts_\(T.tableName)_map")) AS m
                JOIN \(q(index.name)) ON \(q(index.name)).rowid = m.fts_id
                WHERE \(q(index.name)) MATCH ?
            )
            """
        return Predicate(sql: sql, values: [.text(expression)])
    }
}
