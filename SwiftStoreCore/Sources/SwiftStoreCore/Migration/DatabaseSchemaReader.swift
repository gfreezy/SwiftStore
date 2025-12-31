import Foundation

/// Reads table schema from SQLite database
public struct DatabaseSchemaReader {
    private let connection: SQLiteConnection

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    /// Read all table schemas from database
    public func readAllSchemas() throws -> [String: TableSchema] {
        var schemas: [String: TableSchema] = [:]
        for tableName in try allTableNames() {
            if let schema = try readSchema(for: tableName) {
                schemas[tableName] = schema
            }
        }
        return schemas
    }

    // MARK: - Private

    /// Read schema for a specific table
    private func readSchema(for tableName: String) throws -> TableSchema? {
        guard try connection.tableExists(tableName) else {
            return nil
        }

        let columns = try readColumns(for: tableName)
        let indexes = try readIndexes(for: tableName)
        let triggers = try readTriggers(for: tableName)

        return TableSchema(name: tableName, columns: columns, indexes: indexes, triggers: triggers)
    }

    /// Read all table names in database (excluding sqlite system tables)
    private func allTableNames() throws -> [String] {
        let stmt = try connection.prepare(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        )

        var names: [String] = []
        while try stmt.step() {
            if let name = stmt.columnString(0) {
                names.append(name)
            }
        }
        return names
    }

    private func readColumns(for tableName: String) throws -> [ColumnSchema] {
        let tableInfo = try connection.tableInfo(tableName)

        return tableInfo.compactMap { row -> ColumnSchema? in
            guard let name = row["name"] as? String,
                  let type = row["type"] as? String else {
                return nil
            }

            let notNull = row["notnull"] as? Bool ?? false
            let isPrimaryKey = row["pk"] as? Bool ?? false
            let defaultValue = row["dflt_value"] as? String

            return ColumnSchema(
                name: name,
                type: type,
                isNullable: !notNull,
                isPrimaryKey: isPrimaryKey,
                defaultValue: defaultValue
            )
        }
    }

    private func readIndexes(for tableName: String) throws -> [IndexSchema] {
        let listStmt = try connection.prepare("PRAGMA index_list('\(tableName)')")
        var indexes: [IndexSchema] = []

        while try listStmt.step() {
            guard let name = listStmt.columnString(1) else { continue }

            // Skip auto-created indexes
            if name.hasPrefix("sqlite_autoindex_") { continue }

            let isUnique = listStmt.columnInt64(2) == 1

            // Get columns for this index
            let infoStmt = try connection.prepare("PRAGMA index_info('\(name)')")
            var columns: [String] = []
            while try infoStmt.step() {
                if let colName = infoStmt.columnString(2) {
                    columns.append(colName)
                }
            }

            // Get original SQL
            let sqlStmt = try connection.prepare("SELECT sql FROM sqlite_master WHERE type='index' AND name=?")
            try sqlStmt.bind(1, name)
            var sql = ""
            if try sqlStmt.step() {
                sql = sqlStmt.columnString(0) ?? ""
            }

            indexes.append(IndexSchema(
                name: name,
                columns: columns,
                isUnique: isUnique,
                sql: sql
            ))
        }

        return indexes
    }

    private func readTriggers(for tableName: String) throws -> [TriggerSchema] {
        let stmt = try connection.prepare("SELECT name, sql FROM sqlite_master WHERE type='trigger' AND tbl_name=?")
        try stmt.bind(1, tableName)

        var triggers: [TriggerSchema] = []
        while try stmt.step() {
            guard let name = stmt.columnString(0),
                  let sql = stmt.columnString(1) else { continue }

            let parsed = parseTriggerSQL(sql)
            triggers.append(TriggerSchema(
                name: name,
                event: parsed.event,
                timing: parsed.timing,
                condition: parsed.condition,
                body: parsed.body,
                sql: sql
            ))
        }
        return triggers
    }

    private func parseTriggerSQL(_ sql: String) -> (
        event: TriggerSchema.TriggerEvent,
        timing: TriggerSchema.TriggerTiming,
        condition: String?,
        body: String
    ) {
        let uppercased = sql.uppercased()

        // Parse timing
        let timing: TriggerSchema.TriggerTiming
        if uppercased.contains("BEFORE") {
            timing = .before
        } else if uppercased.contains("INSTEAD OF") {
            timing = .insteadOf
        } else {
            timing = .after
        }

        // Parse event
        let event: TriggerSchema.TriggerEvent
        if uppercased.contains("INSERT") {
            event = .insert
        } else if uppercased.contains("DELETE") {
            event = .delete
        } else {
            event = .update
        }

        // Parse WHEN condition
        var condition: String? = nil
        if let whenRange = sql.range(of: "WHEN ", options: .caseInsensitive),
           let beginRange = sql.range(of: "BEGIN", options: .caseInsensitive),
           whenRange.upperBound < beginRange.lowerBound {
            condition = String(sql[whenRange.upperBound..<beginRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Parse body (between BEGIN and END)
        var body = ""
        if let beginRange = sql.range(of: "BEGIN", options: .caseInsensitive),
           let endRange = sql.range(of: "END", options: [.caseInsensitive, .backwards]) {
            body = String(sql[beginRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return (event, timing, condition, body)
    }
}
