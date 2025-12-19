import Foundation

/// SQLite column types
public enum SQLiteType: String, Sendable {
    case text = "TEXT"
    case integer = "INTEGER"
    case real = "REAL"
    case blob = "BLOB"
}

/// Column definition for database schema
public struct ColumnDefinition: Sendable {
    public let name: String
    public let type: SQLiteType
    public let nullable: Bool
    public let primaryKey: Bool
    public let unique: Bool
    public let defaultValue: String?
    public let generatedAs: String?  // For virtual columns
    public let isJSONEncoded: Bool   // For nested Codable types stored as JSON

    public init(
        name: String,
        type: SQLiteType,
        nullable: Bool = false,
        primaryKey: Bool = false,
        unique: Bool = false,
        defaultValue: String? = nil,
        generatedAs: String? = nil,
        isJSONEncoded: Bool = false
    ) {
        self.name = name
        self.type = type
        self.nullable = nullable
        self.primaryKey = primaryKey
        self.unique = unique
        self.defaultValue = defaultValue
        self.generatedAs = generatedAs
        self.isJSONEncoded = isJSONEncoded
    }

    /// Generate SQL for column definition
    public func toSQL() -> String {
        var sql = "\(name) \(type.rawValue)"

        if let generated = generatedAs {
            sql += " GENERATED ALWAYS AS (\(generated)) VIRTUAL"
        } else {
            if !nullable {
                sql += " NOT NULL"
            }
            if primaryKey {
                sql += " PRIMARY KEY"
            }
            if unique && !primaryKey {
                sql += " UNIQUE"
            }
            if let defaultVal = defaultValue {
                sql += " DEFAULT \(defaultVal)"
            }
        }

        return sql
    }
}

/// Index definition
public struct IndexDefinition: Sendable {
    public let name: String
    public let columns: [String]
    public let unique: Bool

    public init(name: String, columns: [String], unique: Bool = false) {
        self.name = name
        self.columns = columns
        self.unique = unique
    }

    /// Generate SQL for index creation
    public func toSQL(tableName: String) -> String {
        let uniqueStr = unique ? "UNIQUE " : ""
        let columnsStr = columns.joined(separator: ", ")
        return "CREATE \(uniqueStr)INDEX IF NOT EXISTS \(name) ON \(tableName)(\(columnsStr))"
    }
}

/// Foreign key definition
public struct ForeignKeyDefinition: Sendable {
    public let column: String
    public let referencesTable: String
    public let referencesColumn: String
    public let onDelete: ForeignKeyAction
    public let onUpdate: ForeignKeyAction

    public enum ForeignKeyAction: String, Sendable {
        case noAction = "NO ACTION"
        case restrict = "RESTRICT"
        case setNull = "SET NULL"
        case setDefault = "SET DEFAULT"
        case cascade = "CASCADE"
    }

    public init(
        column: String,
        referencesTable: String,
        referencesColumn: String,
        onDelete: ForeignKeyAction = .cascade,
        onUpdate: ForeignKeyAction = .noAction
    ) {
        self.column = column
        self.referencesTable = referencesTable
        self.referencesColumn = referencesColumn
        self.onDelete = onDelete
        self.onUpdate = onUpdate
    }

    /// Generate SQL for foreign key constraint
    public func toSQL() -> String {
        return "FOREIGN KEY (\(column)) REFERENCES \(referencesTable)(\(referencesColumn)) ON DELETE \(onDelete.rawValue) ON UPDATE \(onUpdate.rawValue)"
    }
}
