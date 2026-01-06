import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxBuilder

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
        if let arguments = node.arguments?.as(LabeledExprListSyntax.self),
           let tableNameArg = arguments.first(where: { $0.label?.text == "tableName" }),
           let stringLiteral = tableNameArg.expression.as(StringLiteralExprSyntax.self),
           let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
            tableName = segment.content.text
        } else {
            tableName = MacroHelpers.camelToSnakeCase(structName)
        }

        let properties = structDecl.extractProperties()

        // Parse #SyncKey marker (if any) FIRST - needed for validation
        let syncKeyInfo = SyncKeyMarkerParser.parse(from: structDecl.memberBlock.members)
        let hasSyncKey = syncKeyInfo != nil
        let syncKeyColumns = syncKeyInfo?.columns ?? ["id"]

        // Validate required fields based on whether #SyncKey is used
        try validateRequiredFields(properties: properties, structName: structName, hasSyncKey: hasSyncKey)

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
            let isJSON = !prop.isPrimitive && prop.type != "UUIDV7"
            // Add default value for Date columns (createdAt/updatedAt)
            let isTimestamp = prop.type == "Date" && (prop.name == "createdAt" || prop.name == "updatedAt")

            var def = "ColumnDefinition(name: \"\(prop.columnName)\", type: .\(colType)"
            if nullable {
                def += ", nullable: true"
            }
            if isPrimaryKey {
                def += ", primaryKey: true"
            }
            if isJSON {
                def += ", isJSONEncoded: true"
            }
            if isTimestamp {
                def += ", defaultValue: \"(strftime('%s', 'now'))\""
            }
            def += ")"
            columnDefs.append(def)
        }

        let columnsArray = columnDefs.joined(separator: ",\n        ")

        let tableNameDecl: DeclSyntax = """
            public static var tableName: String { "\(raw: tableName)" }
            """

        // Generate sqliteEncode() method
        let encodeDecl = try generateSqliteEncode(properties: properties)

        // Generate sqliteDecode(from:) method
        let decodeDecl = try generateSqliteDecode(properties: properties, structName: structName, hasSyncKey: hasSyncKey)

        // Parse #Index markers from struct body
        let indexInfos = IndexMarkerParser.parse(from: structDecl.memberBlock.members, tableName: tableName)

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
                let jsonExtract = "json_extract(\(virtualCol.jsonColumn!), '\(virtualCol.jsonPath!)')"
                let def = "ColumnDefinition(name: \"\(virtualCol.columnName)\", type: .text, nullable: true, generatedAs: \"\(jsonExtract)\")"
                virtualColumnDefs.append(def)
            }
        }

        // Append virtual columns to the columns array if any
        var finalColumnsArray = columnsArray
        if !virtualColumnDefs.isEmpty {
            finalColumnsArray += ",\n        " + virtualColumnDefs.joined(separator: ",\n        ")
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

        // Generate init method with default values for id, createdAt, updatedAt
        let initDecl = generateInitMethod(properties: properties)

        // Generate custom Decodable init that handles missing keys with default values
        let decodableInitDecl = generateDecodableInit(properties: properties)

        var result: [DeclSyntax] = [tableNameDecl, columnsDecl, encodeDecl, decodeDecl, syncKeyColumnsDecl, initDecl, decodableInitDecl]

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
            let syncKeyIndexDef = "IndexDefinition(name: \"\(syncKeyIndexName)\", columns: [\(syncKeyColumnsStr)], unique: true)"
            indexDefStrings.append(syncKeyIndexDef)
        }

        // Only add indexes property if there are any indexes
        if !indexDefStrings.isEmpty {
            let indexesArray = indexDefStrings.joined(separator: ",\n        ")
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

    /// Generate custom Decodable init(from decoder:) that handles missing keys with default values
    /// This enables backward compatibility when new fields are added to entities
    private static func generateDecodableInit(properties: [PropertyInfo]) -> DeclSyntax {
        // Generate CodingKeys enum
        let codingKeysEntries = properties.map { prop in
            "case \(prop.name)"
        }.joined(separator: "\n    ")

        // Check if we have any nested struct types that need Embedded validation
        let hasNestedTypes = properties.contains { MacroHelpers.isNestedStructType($0.type) }

        // Generate decoding statements
        var decodingStatements: [String] = []

        for prop in properties {
            let propName = prop.name
            let baseType = prop.type.replacingOccurrences(of: "?", with: "")
            let isNestedType = MacroHelpers.isNestedStructType(prop.type)

            // Use property's own default value (validated to exist for id/createdAt/updatedAt)
            let defaultValue = prop.defaultValue

            if prop.isOptional {
                // Optional types: use decodeIfPresent, default to nil
                if isNestedType {
                    // Use helper function for nested types to enforce Embedded constraint
                    decodingStatements.append("self.\(propName) = try Self._decodeNestedIfPresent(\(baseType).self, from: container, forKey: .\(propName))")
                } else {
                    decodingStatements.append("self.\(propName) = try container.decodeIfPresent(\(baseType).self, forKey: .\(propName))")
                }
            } else if let defaultVal = defaultValue {
                // Non-optional with default: use do-catch to fallback on any error
                if isNestedType {
                    decodingStatements.append("do {\n        self.\(propName) = try Self._decodeNested(\(baseType).self, from: container, forKey: .\(propName))\n    } catch {\n        self.\(propName) = \(defaultVal)\n    }")
                } else {
                    decodingStatements.append("do {\n        self.\(propName) = try container.decode(\(baseType).self, forKey: .\(propName))\n    } catch {\n        self.\(propName) = \(defaultVal)\n    }")
                }
            } else {
                // Non-optional without default: required field
                if isNestedType {
                    // Use helper function for nested types to enforce Embedded constraint
                    decodingStatements.append("self.\(propName) = try Self._decodeNested(\(baseType).self, from: container, forKey: .\(propName))")
                } else {
                    decodingStatements.append("self.\(propName) = try container.decode(\(prop.type).self, forKey: .\(propName))")
                }
            }
        }

        let decodingCode = decodingStatements.joined(separator: "\n    ")

        // Generate helper functions for nested type decoding if needed
        let helperFunctions: String
        if hasNestedTypes {
            helperFunctions = """


                /// Helper to decode nested types with Embedded constraint (compile-time validation)
                @inline(__always)
                private static func _decodeNested<T: Embedded & Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> T {
                    try container.decode(T.self, forKey: key)
                }

                /// Helper to decode optional nested types with Embedded constraint (compile-time validation)
                @inline(__always)
                private static func _decodeNestedIfPresent<T: Embedded & Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> T? {
                    try container.decodeIfPresent(T.self, forKey: key)
                }
            """
        } else {
            helperFunctions = ""
        }

        return """
        private enum CodingKeys: String, CodingKey {
            \(raw: codingKeysEntries)
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            \(raw: decodingCode)
        }\(raw: helperFunctions)
        """
    }

    /// Generate init method with default values from property declarations
    private static func generateInitMethod(properties: [PropertyInfo]) -> DeclSyntax {
        var params: [String] = []

        for prop in properties {
            let paramName = prop.name
            let paramType = prop.type

            // Use property's own default value (validated to exist for id/createdAt/updatedAt)
            if let defaultVal = prop.defaultValue {
                params.append("\(paramName): \(paramType) = \(defaultVal)")
            } else {
                params.append("\(paramName): \(paramType)")
            }
        }

        let paramsStr = params.joined(separator: ",\n    ")

        // Generate assignments
        var assignments: [String] = []
        for prop in properties {
            assignments.append("self.\(prop.name) = \(prop.name)")
        }
        let assignmentsStr = assignments.joined(separator: "\n    ")

        return """
        public init(
            \(raw: paramsStr)
        ) {
            \(raw: assignmentsStr)
        }
        """
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

        let encodingCode = encodings.joined(separator: "\n        ")

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
    private static func generateSqliteDecode(properties: [PropertyInfo], structName: String, hasSyncKey: Bool) throws -> DeclSyntax {
        var decodings: [String] = []
        var constructorArgs: [String] = []

        for (index, prop) in properties.enumerated() {
            let varName = "_\(prop.name)"
            let decoding = generateDecodeExpression(for: prop, varName: varName, index: index)
            decodings.append(decoding)
            constructorArgs.append("\(prop.name): \(varName)")
        }

        let decodingCode = decodings.joined(separator: "\n        ")
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
    private static func generateDecodeExpression(for prop: PropertyInfo, varName: String, index: Int) -> String {
        let baseType = prop.type.replacingOccurrences(of: "?", with: "")
        let sqliteType = prop.sqliteType  // "text", "integer", "real", "blob"

        if prop.isOptional {
            // For optional types, use Optional<T>(from:) which handles .null -> nil
            return "let \(varName) = try Optional<\(baseType)>(from: statement.columnValue(Int32(\(index)), type: .\(sqliteType)))"
        } else if let defaultVal = prop.defaultValue {
            // For non-optional with default value: use var + do-catch block
            return """
var \(varName): \(baseType)
        do {
            \(varName) = try \(baseType)(from: statement.columnValue(Int32(\(index)), type: .\(sqliteType)))
        } catch {
            \(varName) = \(defaultVal)
        }
"""
        } else {
            // For non-optional without default value: just try decode
            return "let \(varName) = try \(baseType)(from: statement.columnValue(Int32(\(index)), type: .\(sqliteType)))"
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
        guard declaration.is(StructDeclSyntax.self) else {
            return []
        }

        var extensions: [ExtensionDeclSyntax] = []

        // EntityProtocol conformance
        let entityProtocol: DeclSyntax = """
            extension \(type.trimmed): EntityProtocol {}
            """
        if let ext = entityProtocol.as(ExtensionDeclSyntax.self) {
            extensions.append(ext)
        }

        // SQLiteCodable conformance (for optimized encode/decode)
        let sqliteCodable: DeclSyntax = """
            extension \(type.trimmed): SQLiteCodable {}
            """
        if let ext = sqliteCodable.as(ExtensionDeclSyntax.self) {
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

        // Embedded protocol conformance (marker protocol for embedded types)
        let embeddedProtocol: DeclSyntax = """
            extension \(type.trimmed): Embedded {}
            """
        if let ext = embeddedProtocol.as(ExtensionDeclSyntax.self) {
            extensions.append(ext)
        }

        return extensions
    }

    /// Generate id computed property for entities using #SyncKey
    /// This enables Identifiable conformance based on sync key fields
    private static func generateSyncKeyIdProperty(syncKeyInfo: SyncKeyMarkerParser.SyncKeyInfo, properties: [PropertyInfo]) -> DeclSyntax {
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

            let fieldsCode = structFields.joined(separator: "\n            ")
            let assignmentsCode = fieldAssignments.joined(separator: ", ")

            return """
                public struct SyncKeyID: Hashable, Sendable {
                    \(raw: fieldsCode)
                }

                public var id: SyncKeyID { SyncKeyID(\(raw: assignmentsCode)) }
                """
        }
    }

    /// Validate that required fields exist with correct types and default values
    /// - hasSyncKey: If true, #SyncKey is used and id field is NOT allowed
    ///               If false, id field is required and #SyncKey is not allowed
    private static func validateRequiredFields(properties: [PropertyInfo], structName: String, hasSyncKey: Bool) throws {
        let hasIdField = properties.contains(where: { $0.name == "id" })

        if hasSyncKey {
            // When #SyncKey is used, id field is NOT allowed
            if hasIdField {
                throw MacroError.syncKeyAndIdMutuallyExclusive(structName: structName)
            }
        } else {
            // When no #SyncKey, id: UUIDV7 is required
            guard let idProp = properties.first(where: { $0.name == "id" }) else {
                throw MacroError.missingRequiredField(
                    structName: structName,
                    fieldName: "id",
                    expectedType: "UUIDV7"
                )
            }

            let idBaseType = idProp.type.replacingOccurrences(of: "?", with: "")
            if idBaseType != "UUIDV7" {
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

            // id field must have a default value
            if idProp.defaultValue == nil {
                throw MacroError.missingDefaultValue(
                    structName: structName,
                    fieldName: "id",
                    expectedDefault: "UUIDV7()"
                )
            }
        }

        // Check for createdAt: Date (always required)
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

        // createdAt must have a default value
        if createdAtProp.defaultValue == nil {
            throw MacroError.missingDefaultValue(
                structName: structName,
                fieldName: "createdAt",
                expectedDefault: "Date()"
            )
        }

        // Check for updatedAt: Date (always required)
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

        // updatedAt must have a default value
        if updatedAtProp.defaultValue == nil {
            throw MacroError.missingDefaultValue(
                structName: structName,
                fieldName: "updatedAt",
                expectedDefault: "Date()"
            )
        }
    }
}

/// Macro errors with detailed messages
public enum MacroError: Error, CustomStringConvertible {
    case message(String)
    case missingRequiredField(structName: String, fieldName: String, expectedType: String)
    case wrongFieldType(structName: String, fieldName: String, expectedType: String, actualType: String)
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
            return "@Entity requires '\(structName)' to have a '\(fieldName): \(expectedType)' field"
        case .wrongFieldType(let structName, let fieldName, let expectedType, let actualType):
            return "@Entity requires '\(structName).\(fieldName)' to be of type '\(expectedType)', but found '\(actualType)'"
        case .fieldMustNotBeOptional(let structName, let fieldName):
            return "@Entity requires '\(structName).\(fieldName)' to be non-optional"
        case .fieldNotFound(let structName, let fieldName):
            return "Field '\(fieldName)' not found in '\(structName)'"
        case .invalidKeyPath(let keyPath):
            return "Invalid KeyPath: '\(keyPath)'"
        case .syncKeyAndIdMutuallyExclusive(let structName):
            return "@Entity '\(structName)': #SyncKey and 'id' field are mutually exclusive. Use either #SyncKey or 'id: UUIDV7', not both."
        case .missingTypeAnnotation(let structName, let fieldName):
            return "@Entity requires '\(structName).\(fieldName)' to have an explicit type annotation. Use 'var \(fieldName): Type = value' instead of 'var \(fieldName) = value'."
        case .missingDefaultValue(let structName, let fieldName, let expectedDefault):
            return "@Entity requires '\(structName).\(fieldName)' to have a default value. Use 'var \(fieldName): ... = \(expectedDefault)'"
        }
    }
}
