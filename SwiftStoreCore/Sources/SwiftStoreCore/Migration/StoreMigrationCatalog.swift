import Foundation

/// Resolves frozen table deltas in registration order. The first delta describes the initial
/// schema; an omitted delta inherits the preceding schema for a data-only migration.
public struct StoreMigrationCatalog: Sendable {
    public private(set) var migrations: [StoreMigration] = []

    public init() {}

    public mutating func append(
        id: String, delta: SchemaDelta = SchemaDelta(),
        up: @escaping @Sendable (SQLiteConnection) throws -> Void
    ) throws {
        let target = try delta.applying(to: migrations.last?.target ?? .empty)
        migrations.append(StoreMigration(id: id, target: target, up: up))
    }
}
