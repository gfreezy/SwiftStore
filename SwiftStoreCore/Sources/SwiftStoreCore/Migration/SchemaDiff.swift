import Foundation

// MARK: - Table Schema Diff (Internal)

/// Computes difference between current and target table schema
struct SchemaDiff: Sendable {
    let current: TableSchema?
    let target: TableSchema

    init(current: TableSchema?, target: TableSchema) {
        self.current = current
        self.target = target
    }

    var tableName: String {
        target.name
    }

    var needsCreate: Bool {
        current == nil
    }

    var columnsToAdd: [ColumnSchema] {
        guard let current = current else { return [] }
        let existingNames = current.columnNames

        return target.columns.filter { column in
            !existingNames.contains(column.name) && !column.isGenerated
        }
    }

    /// Columns with type mismatch between current and target schema
    var columnsWithTypeMismatch: [(name: String, currentType: String, targetType: String)] {
        guard let current = current else { return [] }

        var mismatches: [(name: String, currentType: String, targetType: String)] = []

        for targetColumn in target.columns where !targetColumn.isGenerated {
            if let currentColumn = current.columns.first(where: { $0.name == targetColumn.name }) {
                // Compare types (case-insensitive)
                if currentColumn.type.uppercased() != targetColumn.type.uppercased() {
                    mismatches.append((
                        name: targetColumn.name,
                        currentType: currentColumn.type,
                        targetType: targetColumn.type
                    ))
                }
            }
        }

        return mismatches
    }

    var indexesToAdd: [IndexSchema] {
        guard let current = current else { return target.indexes }
        return target.indexes.filter { !current.indexNames.contains($0.name) }
    }

    var triggersToAdd: [TriggerSchema] {
        guard let current = current else { return target.triggers }
        return target.triggers.filter { !current.triggerNames.contains($0.name) }
    }

    var hasChanges: Bool {
        needsCreate || !columnsToAdd.isEmpty || !indexesToAdd.isEmpty || !triggersToAdd.isEmpty
    }
}

// MARK: - Database Diff (Public)

/// Represents schema diff for a database
public struct DatabaseDiff: Sendable {
    let tableDiffs: [SchemaDiff]

    init(tableDiffs: [SchemaDiff]) {
        self.tableDiffs = tableDiffs
    }

    /// Whether there are any changes needed
    public var hasChanges: Bool {
        tableDiffs.contains { $0.hasChanges }
    }

    /// Number of tables that need to be created
    public var tablesToCreateCount: Int {
        tableDiffs.filter { $0.needsCreate }.count
    }

    /// Number of columns that need to be added
    public var columnsToAddCount: Int {
        tableDiffs.reduce(0) { $0 + $1.columnsToAdd.count }
    }

    /// Number of indexes that need to be added
    public var indexesToAddCount: Int {
        tableDiffs.reduce(0) { $0 + $1.indexesToAdd.count }
    }

    /// Number of triggers that need to be added
    public var triggersToAddCount: Int {
        tableDiffs.reduce(0) { $0 + $1.triggersToAdd.count }
    }
}
