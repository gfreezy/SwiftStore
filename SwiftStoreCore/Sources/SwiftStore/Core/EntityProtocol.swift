import Foundation
import SwiftStoreProtocols

// Re-export core types from SwiftStoreProtocols
// (These are also @_exported via SwiftStore.swift)

// MARK: - Query Extensions for EntityProtocol

public extension EntityProtocol {
    /// Create a new Query for this entity type
    static func query() -> Query<Self> {
        Query(Self.self)
    }

    /// Add a WHERE predicate
    static func filter(_ predicate: Predicate<Self>) -> Query<Self> {
        Query(Self.self).filter(predicate)
    }

    /// Add a WHERE predicate using closure with dynamic member lookup
    /// Usage: `TestUser.filter { $0.age >= 25 }`
    static func filter(_ buildPredicate: (Columns<Self>) -> Predicate<Self>) -> Query<Self> {
        Query(Self.self).filter(buildPredicate)
    }

    /// Filter by primary key
    static func filter(id: UUIDV4) -> Query<Self> {
        Query(Self.self).filter(id: id)
    }

    /// Filter by multiple primary keys
    static func filter(ids: [UUIDV4]) -> Query<Self> {
        Query(Self.self).filter(ids: ids)
    }

    /// Add ORDER BY clause
    static func order<V>(by keyPath: KeyPath<Self, V>, ascending: Bool = true) -> Query<Self> {
        Query(Self.self).order(by: keyPath, ascending: ascending)
    }

    /// Order by descending
    static func orderDesc<V>(by keyPath: KeyPath<Self, V>) -> Query<Self> {
        Query(Self.self).orderDesc(by: keyPath)
    }

    /// Add LIMIT clause
    static func limit(_ count: Int) -> Query<Self> {
        Query(Self.self).limit(count)
    }

    /// Add DISTINCT to the query
    static func distinct() -> Query<Self> {
        Query(Self.self).distinct()
    }

    /// Select specific columns
    static func select(_ columns: String...) -> Query<Self> {
        var query = Query(Self.self)
        for column in columns {
            query = query.select(column)
        }
        return query
    }
}
