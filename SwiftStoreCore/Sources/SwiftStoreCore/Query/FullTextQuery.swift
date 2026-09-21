import Foundation

public extension Query {
    /// Search for a literal phrase. Quotes and FTS operators in user input are treated as text.
    /// With multiple indexes, supply the name declared by #FullTextIndex.
    /// When enabled, ascending FTS rank takes priority over existing and subsequent ordering.
    /// Those orderings break ties; the most recently enabled rank takes priority.
    func search(_ text: String, index name: String? = nil, orderByRank: Bool = false) throws -> Query<T> {
        let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let index = try fullTextIndex(named: name)
        guard !phrase.isEmpty else { return filter(Predicate(sql: "0")) }
        return fullTextQuery("\"" + phrase.replacingOccurrences(of: "\"", with: "\"\"") + "\"", index: index, orderByRank: orderByRank)
    }

    /// Search with explicit FTS5 syntax (AND/OR, prefixes, phrases and column filters).
    /// Invalid expressions throw when the query is executed. Values are always SQL parameters.
    /// Rank ordering follows the same precedence rules as `search(_:index:orderByRank:)`.
    func matching(_ expression: String, index name: String? = nil, orderByRank: Bool = false) throws -> Query<T> {
        fullTextQuery(expression, index: try fullTextIndex(named: name), orderByRank: orderByRank)
    }

    private func fullTextQuery(_ expression: String, index: FullTextIndexDefinition, orderByRank: Bool) -> Query<T> {
        let query = filter(fullTextPredicate(expression, index: index))
        guard orderByRank else { return query }
        let q = FullTextSchema.quote
        let mapping = q("__swiftstore_fts_\(T.tableName)_map")
        let keyMatch = index.keyColumns.map {
            "\(mapping).\(q($0)) = \(q(T.tableName)).\(q($0))"
        }.joined(separator: " AND ")
        // Evaluate rank inside its MATCH cursor. Resolve the FTS rowid through the
        // unique identity mapping first, so each candidate needs only one FTS lookup.
        // Business rowids (including sparse rowids) have no relationship to FTS IDs.
        let sql = """
            (SELECT \(q(index.name)).rank FROM \(q(index.name))
             WHERE \(q(index.name)) MATCH ? AND \(q(index.name)).rowid = (
                 SELECT \(mapping).fts_id FROM \(mapping)
                 WHERE \(keyMatch)
             ))
            """
        return query.orderByRank(sql: sql, values: [.text(expression)])
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
