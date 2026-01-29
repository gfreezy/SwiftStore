import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Entity macro that generates EntityProtocol conformance
public struct EntityMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.message("@Entity can only be applied to structs")
        }

        let structName = structDecl.name.text

        // Validate all properties have explicit type annotations
        try structDecl.validateAllPropertiesHaveTypes(structName: structName)

        // Parse optional tableName argument
        let tableName: String
        // Parse readonly parameter (default: false)
        let isReadonly: Bool

        if let arguments = node.arguments?.as(LabeledExprListSyntax.self) {
            // Parse tableName
            if let tableNameArg = arguments.first(where: { $0.label?.text == "tableName" }),
                let stringLiteral = tableNameArg.expression.as(StringLiteralExprSyntax.self),
                let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self)
            {
                tableName = segment.content.text
            } else {
                tableName = MacroHelpers.camelToSnakeCase(structName)
            }

            // Parse readonly parameter
            if let readonlyArg = arguments.first(where: { $0.label?.text == "readonly" }),
                let boolLiteral = readonlyArg.expression.as(BooleanLiteralExprSyntax.self)
            {
                isReadonly = boolLiteral.literal.text == "true"
            } else {
                isReadonly = false
            }
        } else {
            tableName = MacroHelpers.camelToSnakeCase(structName)
            isReadonly = false
        }

        // syncEnabled is the inverse of readonly
        let syncEnabled = !isReadonly

        let properties = structDecl.extractProperties()

        // Parse #SyncKey marker (if any) FIRST - needed for validation
        let syncKeyInfo = SyncKeyMarkerParser.parse(from: structDecl.memberBlock.members)
        let hasSyncKey = syncKeyInfo != nil
        let syncKeyColumns = syncKeyInfo?.columns ?? ["id"]

        // Validate required fields based on whether #SyncKey is used and sync is enabled
        try validateRequiredFields(
            properties: properties, structName: structName, hasSyncKey: hasSyncKey, syncEnabled: syncEnabled
        )

        // Generate column definitions
        var columnDefs: [String] = []
        for prop in properties {
            let nullable = prop.isOptional
            // Primary key: either "id" (when no #SyncKey) or first sync key column (when #SyncKey is used)
            let isPrimaryKey: Bool
            if hasSyncKey {
                // When using #SyncKey, the first sync key column is the primary key for single-column sync key
                // For composite sync key, we don't set primaryKey on columns (use unique index instead)
                isPrimaryKey = syncKeyColumns.count == 1 && prop.columnName == syncKeyColumns[0]
            } else {
                isPrimaryKey = prop.name == "id"
            }
            let colType = prop.sqliteType
            let isJSON = !prop.isPrimitive

            var def = "ColumnDefinition(name: \"\(prop.columnName)\", type: .\(colType)"
            if nullable {
                def += ", nullable: true"
            }
            if isPrimaryKey {
                def += ", primaryKey: true"
            }
            // Generate SQL DEFAULT from Swift default value (must be before isJSONEncoded)
            if let sqlDefault = convertToSQLDefault(prop: prop) {
                def += ", defaultValue: \"\(sqlDefault)\""
            }
            if isJSON {
                def += ", isJSONEncoded: true"
            }
            def += ")"
            columnDefs.append(def)
        }

        let columnsArray = MacroHelpers.joinList(columnDefs, indent: 8)

        let tableNameDecl: DeclSyntax = """
            public static var tableName: String { "\(raw: tableName)" }
            """

        // Generate sqliteEncode() method
        let encodeDecl = try generateSqliteEncode(properties: properties)

        // Generate sqliteDecode(from:) method
        let decodeDecl = try generateSqliteDecode(
            properties: properties, structName: structName, hasSyncKey: hasSyncKey)

        // Parse #Index markers from struct body
        let indexInfos = IndexMarkerParser.parse(
            from: structDecl.memberBlock.members, tableName: tableName)

        // Collect all virtual columns needed for nested property indexes
        var virtualColumnDefs: [String] = []
        var seenVirtualColumns: Set<String> = []
        for idx in indexInfos {
            for virtualCol in idx.virtualColumns {
                // Avoid duplicates
                guard !seenVirtualColumns.contains(virtualCol.columnName) else { continue }
                seenVirtualColumns.insert(virtualCol.columnName)

                // Generate virtual column definition
                // json_extract returns TEXT by default for string values
                let jsonExtract =
                    "json_extract(\(virtualCol.jsonColumn!), '\(virtualCol.jsonPath!)')"
                let def =
                    "ColumnDefinition(name: \"\(virtualCol.columnName)\", type: .text, nullable: true, generatedAs: \"\(jsonExtract)\")"
                virtualColumnDefs.append(def)
            }
        }

        // Append virtual columns to the columns array if any
        var finalColumnsArray = columnsArray
        if !virtualColumnDefs.isEmpty {
            finalColumnsArray += ",\n" + MacroHelpers.joinList(virtualColumnDefs, indent: 8)
        }

        let columnsDecl: DeclSyntax = """
            public static var columns: [ColumnDefinition] {
                [
            \(raw: finalColumnsArray)
                ]
            }
            """

        // Generate syncKeyColumns property
        let syncKeyColumnsStr = syncKeyColumns.map { "\"\($0)\"" }.joined(separator: ", ")
        let syncKeyColumnsDecl: DeclSyntax = """
            public static var syncKeyColumns: [String] { [\(raw: syncKeyColumnsStr)] }
            """

        // Generate isReadonly property
        let isReadonlyDecl: DeclSyntax = """
            public static var isReadonly: Bool { \(raw: isReadonly ? "true" : "false") }
            """

        // Generate memberwise init with default values
        let memberwiseInitDecl = EmbeddedMacro.generateMemberWiseInit(properties: properties)

        var result: [DeclSyntax] = [
            tableNameDecl, columnsDecl, encodeDecl, decodeDecl, syncKeyColumnsDecl, isReadonlyDecl,
            memberwiseInitDecl,
        ]

        // Generate id computed property for #SyncKey entities (for Identifiable conformance)
        if let syncKeyInfo = syncKeyInfo {
            let idDecl = generateSyncKeyIdProperty(syncKeyInfo: syncKeyInfo, properties: properties)
            result.append(idDecl)
        }

        // Generate indexes (including auto-generated unique index for sync key)
        var indexDefStrings: [String] = []

        // Add user-defined indexes
        for idx in indexInfos {
            let columnsStr = idx.columnNames.map { "\"\($0)\"" }.joined(separator: ", ")
            // Use custom name if provided, otherwise generate from table and columns
            let indexName = idx.name ?? "idx_\(tableName)_\(idx.columnNames.joined(separator: "_"))"
            var def = "IndexDefinition(name: \"\(indexName)\", columns: [\(columnsStr)]"
            if idx.unique {
                def += ", unique: true"
            }
            def += ")"
            indexDefStrings.append(def)
        }

        // Auto-generate unique index for sync key (unless it's just "id" which is already primary key)
        if syncKeyColumns != ["id"] {
            let syncKeyIndexName = "idx_\(tableName)_sync_key"
            let syncKeyIndexDef =
                "IndexDefinition(name: \"\(syncKeyIndexName)\", columns: [\(syncKeyColumnsStr)], unique: true)"
            indexDefStrings.append(syncKeyIndexDef)
        }

        // Only add indexes property if there are any indexes
        if !indexDefStrings.isEmpty {
            let indexesArray = MacroHelpers.joinList(indexDefStrings, indent: 8)
            let indexesDecl: DeclSyntax = """
                public static var indexes: [IndexDefinition] {
                    [
                \(raw: indexesArray)
                    ]
                }
                """
            result.append(indexesDecl)
        }

        // Note: Nested types (non-primitive Codable types) should conform to Embedded protocol
        // for proper fault-tolerant decoding. Add @Embedded to your nested structs.

        return result
    }

    /// Generate the sqliteEncode() method
    /// Uses SQLiteValueEncodable.sqliteEncode() for all types
    private static func generateSqliteEncode(properties: [PropertyInfo]) throws -> DeclSyntax {
        var encodings: [String] = []

        for prop in properties {
            let columnName = prop.columnName
            // All types (including Optional) conform to SQLiteValueEncodable
            // Optional's sqliteEncode() returns .null for nil values
            encodings.append("result[\"\(columnName)\"] = try self.\(prop.name).sqliteEncode()")
        }

        let encodingCode = MacroHelpers.joinLines(encodings, indent: 4)

        return """
            public func sqliteEncode() throws -> [String: SQLiteValue] {
                var result: [String: SQLiteValue] = [:]
            \(raw: encodingCode)
                return result
            }
            """
    }

    /// Generate the sqliteDecode(from:) method
    /// Uses SQLiteValueDecodable.init(from:) for all types
    /// For properties with default values, uses do-catch to fallback to default on error
    private static func generateSqliteDecode(
        properties: [PropertyInfo], structName: String, hasSyncKey: Bool
    ) throws -> DeclSyntax {
        var decodings: [String] = []
        var constructorArgs: [String] = []

        for (index, prop) in properties.enumerated() {
            let varName = "_\(prop.name)"
            let decoding = generateDecodeExpression(for: prop, varName: varName, index: index, typeName: structName)
            decodings.append(decoding)
            constructorArgs.append("\(prop.name): \(varName)")
        }

        let decodingCode = MacroHelpers.joinLines(decodings, indent: 4)
        let constructorCode = constructorArgs.joined(separator: ", ")

        return """
            public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
            \(raw: decodingCode)
                return Self(\(raw: constructorCode))
            }
            """
    }

    /// Generate decode expression for a property
    /// Uses SQLiteValueDecodable.init(from:) with do-catch for default values
    private static func generateDecodeExpression(
        for prop: PropertyInfo, varName: String, index: Int, typeName: String
    ) -> String {
        let baseType = prop.type.replacingOccurrences(of: "?", with: "")
        let sqliteType = prop.sqliteType  // "text", "integer", "real", "blob"
        let decodeExpr =
            "\(baseType)(from: statement.columnValue(Int32(\(index)), type: .\(sqliteType)))"
        let decodeOptionalExpr =
            "Optional<\(baseType)>(from: statement.columnValue(Int32(\(index)), type: .\(sqliteType)))"

        if let defaultVal = prop.defaultValue {
            var tryExpr: String
            var declExpr: String
            if prop.isOptional {
                declExpr = "var \(varName): Optional<\(baseType)>"
                tryExpr = "\(varName) = try \(decodeOptionalExpr)"
            } else {
                declExpr = "var \(varName): \(baseType)"
                tryExpr = "\(varName) = try \(decodeExpr)"
            }
            
            let catchExpr = "\(varName) = \(defaultVal)"
            let doCatch = MacroHelpers.doCatchBlock(
                try: tryExpr, catch: catchExpr, logFieldName: prop.name, logTypeName: typeName)
            return "\(declExpr)\n\(doCatch)"
        } else if prop.isOptional {
            // For optional types, use Optional<T>(from:) which handles .null -> nil
            return
                "let \(varName) = try \(decodeOptionalExpr)"
        } else {
            // For non-optional without default value: just try decode
            return "let \(varName) = try \(decodeExpr)"
        }
    }

    // MARK: - ExtensionMacro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            return []
        }

        let structName = structDecl.name.text

        // Parse readonly parameter to determine syncEnabled
        let isReadonly: Bool
        if let arguments = node.arguments?.as(LabeledExprListSyntax.self),
            let readonlyArg = arguments.first(where: { $0.label?.text == "readonly" }),
            let boolLiteral = readonlyArg.expression.as(BooleanLiteralExprSyntax.self)
        {
            isReadonly = boolLiteral.literal.text == "true"
        } else {
            isReadonly = false
        }
        let syncEnabled = !isReadonly

        // Get properties (same logic as MemberMacro)
        let properties = structDecl.extractProperties()
        let syncKeyInfo = SyncKeyMarkerParser.parse(from: structDecl.memberBlock.members)
        let hasSyncKey = syncKeyInfo != nil

        try validateRequiredFields(
            properties: properties, structName: structName, hasSyncKey: hasSyncKey, syncEnabled: syncEnabled
        )

        var extensions: [ExtensionDeclSyntax] = []

        // EntityProtocol conformance (includes SQLiteCodable via protocol inheritance)
        let entityProtocol: DeclSyntax = """
            extension \(type.trimmed): EntityProtocol {}
            """
        if let ext = entityProtocol.as(ExtensionDeclSyntax.self) {
            extensions.append(ext)
        }

        // Decodable extension with init(from decoder:) - in extension to preserve memberwise init
        let decodableExt = EmbeddedMacro.generateDecodableExtension(for: type, properties: properties, typeName: structName)
        if let ext = decodableExt.as(ExtensionDeclSyntax.self) {
            extensions.append(ext)
        }

        // Encodable conformance (Swift auto-synthesizes encode method)
        let encodable: DeclSyntax = """
            extension \(type.trimmed): Encodable {}
            """
        if let ext = encodable.as(ExtensionDeclSyntax.self) {
            extensions.append(ext)
        }

        // Identifiable conformance (always - either via id field or #SyncKey generated id)
        let identifiable: DeclSyntax = """
            extension \(type.trimmed): Identifiable {}
            """
        if let ext = identifiable.as(ExtensionDeclSyntax.self) {
            extensions.append(ext)
        }

        // Sendable conformance
        let sendable: DeclSyntax = """
            extension \(type.trimmed): Sendable {}
            """
        if let ext = sendable.as(ExtensionDeclSyntax.self) {
            extensions.append(ext)
        }

        // Equatable conformance (auto-synthesized by compiler)
        let equatable: DeclSyntax = """
            extension \(type.trimmed): Equatable {}
            """
        if let ext = equatable.as(ExtensionDeclSyntax.self) {
            extensions.append(ext)
        }

        // Hashable conformance (auto-synthesized by compiler)
        let hashable: DeclSyntax = """
            extension \(type.trimmed): Hashable {}
            """
        if let ext = hashable.as(ExtensionDeclSyntax.self) {
            extensions.append(ext)
        }

        return extensions
    }

    /// Generate id computed property for entities using #SyncKey
    /// This enables Identifiable conformance based on sync key fields
    private static func generateSyncKeyIdProperty(
        syncKeyInfo: SyncKeyMarkerParser.SyncKeyInfo, properties: [PropertyInfo]
    ) -> DeclSyntax {
        let propertyNames = syncKeyInfo.propertyNames

        if propertyNames.count == 1 {
            // Single sync key: id is the value directly
            let propName = propertyNames[0]
            // Find the property type
            if let prop = properties.first(where: { $0.name == propName }) {
                return """
                    public var id: \(raw: prop.type) { \(raw: propName) }
                    """
            }
            // Fallback if property not found
            return """
                public var id: String { String(describing: \(raw: propName)) }
                """
        } else {
            // Composite sync key: create a struct to hold all key values
            // Generate a nested SyncKeyID struct
            var structFields: [String] = []
            var fieldAssignments: [String] = []

            for propName in propertyNames {
                if let prop = properties.first(where: { $0.name == propName }) {
                    structFields.append("public let \(propName): \(prop.type)")
                    fieldAssignments.append("\(propName): self.\(propName)")
                }
            }

            let fieldsCode = MacroHelpers.joinLines(structFields, indent: 4)
            let assignmentsCode = fieldAssignments.joined(separator: ", ")

            return """
                public struct SyncKeyID: Hashable, Sendable {
                \(raw: fieldsCode)
                }

                public var id: SyncKeyID { SyncKeyID(\(raw: assignmentsCode)) }
                """
        }
    }

    /// Validate that required fields exist with correct types
    /// - hasSyncKey: If true, #SyncKey is used and id field is NOT allowed
    ///               If false, id field is required (UUIDV7 only when syncEnabled)
    /// - syncEnabled: If true, enforce UUIDV7 id and require createdAt/updatedAt
    ///                If false, allow any id type and createdAt/updatedAt are optional
    private static func validateRequiredFields(
        properties: [PropertyInfo], structName: String, hasSyncKey: Bool, syncEnabled: Bool
    ) throws {
        let hasIdField = properties.contains(where: { $0.name == "id" })

        if hasSyncKey {
            // When #SyncKey is used, id field is NOT allowed
            if hasIdField {
                throw MacroError.syncKeyAndIdMutuallyExclusive(structName: structName)
            }
        } else {
            // id field is required
            guard let idProp = properties.first(where: { $0.name == "id" }) else {
                if syncEnabled {
                    throw MacroError.missingRequiredField(
                        structName: structName,
                        fieldName: "id",
                        expectedType: "UUIDV7"
                    )
                } else {
                    throw MacroError.missingRequiredField(
                        structName: structName,
                        fieldName: "id",
                        expectedType: "any type"
                    )
                }
            }

            let idBaseType = idProp.type.replacingOccurrences(of: "?", with: "")

            // When sync is enabled, id must be UUIDV7
            if syncEnabled && idBaseType != "UUIDV7" {
                throw MacroError.wrongFieldType(
                    structName: structName,
                    fieldName: "id",
                    expectedType: "UUIDV7",
                    actualType: idProp.type
                )
            }

            if idProp.isOptional {
                throw MacroError.fieldMustNotBeOptional(
                    structName: structName,
                    fieldName: "id"
                )
            }
        }

        // createdAt and updatedAt are only required when sync is enabled
        if syncEnabled {
            // Check for createdAt: Date
            guard let createdAtProp = properties.first(where: { $0.name == "createdAt" }) else {
                throw MacroError.missingRequiredField(
                    structName: structName,
                    fieldName: "createdAt",
                    expectedType: "Date"
                )
            }

            let createdAtBaseType = createdAtProp.type.replacingOccurrences(of: "?", with: "")
            if createdAtBaseType != "Date" {
                throw MacroError.wrongFieldType(
                    structName: structName,
                    fieldName: "createdAt",
                    expectedType: "Date",
                    actualType: createdAtProp.type
                )
            }

            if createdAtProp.isOptional {
                throw MacroError.fieldMustNotBeOptional(
                    structName: structName,
                    fieldName: "createdAt"
                )
            }

            // Check for updatedAt: Date
            guard let updatedAtProp = properties.first(where: { $0.name == "updatedAt" }) else {
                throw MacroError.missingRequiredField(
                    structName: structName,
                    fieldName: "updatedAt",
                    expectedType: "Date"
                )
            }

            let updatedAtBaseType = updatedAtProp.type.replacingOccurrences(of: "?", with: "")
            if updatedAtBaseType != "Date" {
                throw MacroError.wrongFieldType(
                    structName: structName,
                    fieldName: "updatedAt",
                    expectedType: "Date",
                    actualType: updatedAtProp.type
                )
            }

            if updatedAtProp.isOptional {
                throw MacroError.fieldMustNotBeOptional(
                    structName: structName,
                    fieldName: "updatedAt"
                )
            }
        }
    }
}

// MARK: - Swift to SQL Default Value Conversion

/// Convert Swift default value to SQL DEFAULT clause value
/// Returns nil if no SQL default should be generated (e.g., for primary keys)
private func convertToSQLDefault(prop: PropertyInfo) -> String? {
    // Skip primary key fields (id, UUIDV7)
    if prop.name == "id" {
        return nil
    }

    // Get base type (remove Optional wrapper if present)
    let baseType = prop.type.replacingOccurrences(of: "?", with: "")

    // Skip UUIDV7 fields
    if baseType == "UUIDV7" {
        return nil
    }

    guard let swiftDefault = prop.defaultValue else {
        return nil
    }

    // For optional types, skip if default is nil
    if prop.isOptional && swiftDefault == "nil" {
        return nil
    }

    // Handle Date type - use SQL function for current timestamp
    if baseType == "Date" {
        return "(strftime('%s', 'now'))"
    }

    // Handle Bool type
    if baseType == "Bool" {
        if swiftDefault == "true" {
            return "1"
        } else if swiftDefault == "false" {
            return "0"
        }
    }

    // Handle numeric types (Int, Double, Float, etc.)
    if prop.sqliteType == "integer" || prop.sqliteType == "real" {
        // Check if it's a valid number literal
        let trimmed = swiftDefault.trimmingCharacters(in: .whitespaces)
        if let _ = Double(trimmed) {
            return trimmed
        }
        // Default to 0 for numeric types with non-literal defaults
        return prop.sqliteType == "integer" ? "0" : "0.0"
    }

    // Handle String type
    if baseType == "String" {
        // Swift string literal: "value" or ""
        let trimmed = swiftDefault.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") {
            // Extract content and convert to SQL string literal
            let content = String(trimmed.dropFirst().dropLast())
            // Escape single quotes for SQL
            let escaped = content.replacingOccurrences(of: "'", with: "''")
            return "'\(escaped)'"
        }
        // Default to empty string
        return "''"
    }

    // Handle JSON-encoded types (nested structs, arrays, dictionaries)
    if !prop.isPrimitive {
        let trimmed = swiftDefault.trimmingCharacters(in: .whitespaces)
        // Empty array literal
        if trimmed == "[]" {
            return "'[]'"
        }
        // Empty dictionary literal
        if trimmed == "[:]" {
            return "'{}'"
        }
        // Struct initializer (e.g., "MyStruct()" or "MyStruct(field: value)")
        // Default to empty JSON object
        return "'{}'"
    }

    return nil
}

/// Macro errors with detailed messages
public enum MacroError: Error, CustomStringConvertible {
    case message(String)
    case missingRequiredField(structName: String, fieldName: String, expectedType: String)
    case wrongFieldType(
        structName: String, fieldName: String, expectedType: String, actualType: String)
    case fieldMustNotBeOptional(structName: String, fieldName: String)
    case fieldNotFound(structName: String, fieldName: String)
    case invalidKeyPath(keyPath: String)
    case syncKeyAndIdMutuallyExclusive(structName: String)
    case missingTypeAnnotation(structName: String, fieldName: String)
    case missingDefaultValue(structName: String, fieldName: String, expectedDefault: String)

    public var description: String {
        switch self {
        case .message(let msg):
            return msg
        case .missingRequiredField(let structName, let fieldName, let expectedType):
            return
                "@Entity requires '\(structName)' to have a '\(fieldName): \(expectedType)' field"
        case .wrongFieldType(let structName, let fieldName, let expectedType, let actualType):
            return
                "@Entity requires '\(structName).\(fieldName)' to be of type '\(expectedType)', but found '\(actualType)'"
        case .fieldMustNotBeOptional(let structName, let fieldName):
            return "@Entity requires '\(structName).\(fieldName)' to be non-optional"
        case .fieldNotFound(let structName, let fieldName):
            return "Field '\(fieldName)' not found in '\(structName)'"
        case .invalidKeyPath(let keyPath):
            return "Invalid KeyPath: '\(keyPath)'"
        case .syncKeyAndIdMutuallyExclusive(let structName):
            return
                "@Entity '\(structName)': #SyncKey and 'id' field are mutually exclusive. Use either #SyncKey or 'id: UUIDV7', not both."
        case .missingTypeAnnotation(let structName, let fieldName):
            return
                "@Entity requires '\(structName).\(fieldName)' to have an explicit type annotation. Use 'var \(fieldName): Type = value' instead of 'var \(fieldName) = value'."
        case .missingDefaultValue(let structName, let fieldName, let expectedDefault):
            return
                "@Entity requires '\(structName).\(fieldName)' to have a default value. Use 'var \(fieldName): ... = \(expectedDefault)'"
        }
    }
}
