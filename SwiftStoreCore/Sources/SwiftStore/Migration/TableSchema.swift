import Foundation

// MARK: - Table Schema

/// Represents a database table schema
public struct TableSchema: Sendable, Equatable {
    public let name: String
    public let columns: [ColumnSchema]
    public let indexes: [IndexSchema]
    public let triggers: [TriggerSchema]
    public let foreignKeys: [ForeignKeySchema]

    public init(
        name: String,
        columns: [ColumnSchema],
        indexes: [IndexSchema] = [],
        triggers: [TriggerSchema] = [],
        foreignKeys: [ForeignKeySchema] = []
    ) {
        self.name = name
        self.columns = columns
        self.indexes = indexes
        self.triggers = triggers
        self.foreignKeys = foreignKeys
    }

    public var columnNames: Set<String> {
        Set(columns.map { $0.name })
    }

    public var indexNames: Set<String> {
        Set(indexes.map { $0.name })
    }

    public var triggerNames: Set<String> {
        Set(triggers.map { $0.name })
    }
}

// MARK: - Column Schema

/// Represents a column in a database table
public struct ColumnSchema: Sendable, Equatable, Hashable {
    public let name: String
    public let type: String
    public let isNullable: Bool
    public let isPrimaryKey: Bool
    public let defaultValue: String?
    public let generatedAs: String?

    public init(
        name: String,
        type: String,
        isNullable: Bool = false,
        isPrimaryKey: Bool = false,
        defaultValue: String? = nil,
        generatedAs: String? = nil
    ) {
        self.name = name
        self.type = type
        self.isNullable = isNullable
        self.isPrimaryKey = isPrimaryKey
        self.defaultValue = defaultValue
        self.generatedAs = generatedAs
    }

    public var isGenerated: Bool {
        generatedAs != nil
    }

    /// Generate SQL for column definition
    public func toSQL() -> String {
        if let generated = generatedAs {
            return "\(name) \(type) GENERATED ALWAYS AS (\(generated)) VIRTUAL"
        }

        var sql = "\(name) \(type)"
        if !isNullable {
            sql += " NOT NULL"
        }
        if isPrimaryKey {
            sql += " PRIMARY KEY"
        }
        if let defaultVal = defaultValue {
            sql += " DEFAULT \(defaultVal)"
        }
        return sql
    }
}

// MARK: - Index Schema

/// Represents an index in a database table
public struct IndexSchema: Sendable, Equatable, Hashable {
    public let name: String
    public let columns: [String]
    public let isUnique: Bool
    public let sql: String

    public init(name: String, columns: [String], isUnique: Bool = false, sql: String = "") {
        self.name = name
        self.columns = columns
        self.isUnique = isUnique
        self.sql = sql
    }

    /// Generate SQL for creating this index
    public func toSQL(tableName: String) -> String {
        let unique = isUnique ? "UNIQUE " : ""
        let cols = columns.joined(separator: ", ")
        return "CREATE \(unique)INDEX IF NOT EXISTS \(name) ON \(tableName)(\(cols))"
    }
}

// MARK: - Trigger Schema

/// Represents a trigger in a database table
public struct TriggerSchema: Sendable, Equatable, Hashable {
    public let name: String
    public let event: TriggerEvent
    public let timing: TriggerTiming
    public let condition: String?
    public let body: String
    public let sql: String

    public init(
        name: String,
        event: TriggerEvent,
        timing: TriggerTiming,
        condition: String? = nil,
        body: String,
        sql: String = ""
    ) {
        self.name = name
        self.event = event
        self.timing = timing
        self.condition = condition
        self.body = body
        self.sql = sql
    }

    public enum TriggerEvent: String, Sendable, Equatable, Hashable {
        case insert = "INSERT"
        case update = "UPDATE"
        case delete = "DELETE"
    }

    public enum TriggerTiming: String, Sendable, Equatable, Hashable {
        case before = "BEFORE"
        case after = "AFTER"
        case insteadOf = "INSTEAD OF"
    }
}

// MARK: - Foreign Key Schema

/// Represents a foreign key constraint
public struct ForeignKeySchema: Sendable, Equatable, Hashable {
    public let column: String
    public let referencesTable: String
    public let referencesColumn: String
    public let onDelete: ForeignKeyAction
    public let onUpdate: ForeignKeyAction

    public init(
        column: String,
        referencesTable: String,
        referencesColumn: String,
        onDelete: ForeignKeyAction = .noAction,
        onUpdate: ForeignKeyAction = .noAction
    ) {
        self.column = column
        self.referencesTable = referencesTable
        self.referencesColumn = referencesColumn
        self.onDelete = onDelete
        self.onUpdate = onUpdate
    }

    public enum ForeignKeyAction: String, Sendable, Equatable, Hashable {
        case noAction = "NO ACTION"
        case restrict = "RESTRICT"
        case setNull = "SET NULL"
        case setDefault = "SET DEFAULT"
        case cascade = "CASCADE"
    }

    /// Generate SQL for foreign key constraint
    public func toSQL() -> String {
        var sql = "FOREIGN KEY (\(column)) REFERENCES \(referencesTable)(\(referencesColumn))"
        if onDelete != .noAction {
            sql += " ON DELETE \(onDelete.rawValue)"
        }
        if onUpdate != .noAction {
            sql += " ON UPDATE \(onUpdate.rawValue)"
        }
        return sql
    }
}
