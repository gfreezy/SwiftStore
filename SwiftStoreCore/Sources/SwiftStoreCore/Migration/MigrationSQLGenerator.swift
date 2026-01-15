import Foundation

/// Generates SQL statements from schema diffs
public struct MigrationSQLGenerator {
    /// Generate migration plan from database diff
    public func generatePlan(from diff: DatabaseDiff) -> MigrationPlan {
        var statements: [String] = []

        // Generate statements for each table diff
        for tableDiff in diff.tableDiffs {
            statements.append(contentsOf: generateStatements(for: tableDiff))
        }

        return MigrationPlan(statements: statements)
    }

    // MARK: - Private

    private func generateStatements(for diff: SchemaDiff) -> [String] {
        var statements: [String] = []

        if diff.needsCreate {
            // Create table
            statements.append(generateCreateTableSQL(for: diff.target))

            // Create indexes
            for index in diff.target.indexes {
                statements.append(index.toSQL(tableName: diff.tableName))
            }
        } else {
            // Add new columns
            for column in diff.columnsToAdd {
                statements.append(contentsOf: generateAlterTableSQL(tableName: diff.tableName, column: column))
            }

            // Drop unused columns (SQLite 3.35.0+)
            for columnName in diff.columnsToDrop {
                statements.append("ALTER TABLE \(diff.tableName) DROP COLUMN \(columnName)")
            }

            // Add new indexes
            for index in diff.indexesToAdd {
                statements.append(index.toSQL(tableName: diff.tableName))
            }
        }

        // Add triggers from diff
        for trigger in diff.triggersToAdd {
            statements.append(trigger.sql)
        }

        return statements
    }

    // MARK: - SQL Generation

    private func generateCreateTableSQL(for schema: TableSchema) -> String {
        var parts: [String] = []

        // Add columns
        for column in schema.columns {
            parts.append(column.toSQL())
        }

        // Add foreign keys
        for fk in schema.foreignKeys {
            parts.append(fk.toSQL())
        }

        return "CREATE TABLE \(schema.name) (\n    \(parts.joined(separator: ",\n    "))\n)"
    }

    private func generateAlterTableSQL(tableName: String, column: ColumnSchema) -> [String] {
        var statements: [String] = []
        var sql = "ALTER TABLE \(tableName) ADD COLUMN \(column.name) \(column.type)"

        if !column.isNullable {
            let defaultVal = column.defaultValue ?? defaultValueForType(column.type)

            // SQLite ALTER TABLE ADD COLUMN doesn't allow expressions (anything in parentheses)
            // or CURRENT_TIME, CURRENT_DATE, CURRENT_TIMESTAMP as default values.
            // We need to use a literal default and then UPDATE existing rows.
            if isExpressionDefault(defaultVal) {
                // Use a literal value for ALTER TABLE
                let literalDefault = defaultValueForType(column.type)
                sql += " NOT NULL DEFAULT \(literalDefault)"
                statements.append(sql)

                // Generate UPDATE to set the expression value for existing rows
                statements.append("UPDATE \(tableName) SET \(column.name) = \(defaultVal)")
            } else {
                sql += " NOT NULL DEFAULT \(defaultVal)"
                statements.append(sql)
            }
        } else {
            statements.append(sql)
        }

        return statements
    }

    /// Check if a default value is an expression (not allowed in ALTER TABLE ADD COLUMN)
    private func isExpressionDefault(_ defaultValue: String) -> Bool {
        let trimmed = defaultValue.trimmingCharacters(in: .whitespaces)
        // Expressions are wrapped in parentheses
        if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") {
            return true
        }
        // CURRENT_TIME, CURRENT_DATE, CURRENT_TIMESTAMP are also not allowed
        let upper = trimmed.uppercased()
        return upper == "CURRENT_TIME" || upper == "CURRENT_DATE" || upper == "CURRENT_TIMESTAMP"
    }

    private func defaultValueForType(_ type: String) -> String {
        let upperType = type.uppercased()
        if upperType.contains("TEXT") {
            return "''"
        } else if upperType.contains("INTEGER") || upperType.contains("INT") {
            return "0"
        } else if upperType.contains("REAL") || upperType.contains("FLOAT") || upperType.contains("DOUBLE") {
            return "0.0"
        } else if upperType.contains("BLOB") {
            return "X''"
        }
        return "''"
    }
}
