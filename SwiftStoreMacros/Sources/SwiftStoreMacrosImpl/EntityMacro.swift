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
            let isJSON = !prop.isPrimitive && prop.type != "UUIDV4"
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

        let columnsArray = columnDefs.joined(separator: ",\n            ")

        let tableNameDecl: DeclSyntax = """
            public static var tableName: String { "\(raw: tableName)" }
            """

        // Generate sqliteEncode() method
        let encodeDecl = try generateSqliteEncode(properties: properties)

        // Generate sqliteDecode(from:) method
        let decodeDecl = try generateSqliteDecode(properties: properties, structName: structName)

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
            finalColumnsArray += ",\n            " + virtualColumnDefs.joined(separator: ",\n            ")
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
        let initDecl = generateInitMethod(properties: properties, hasSyncKey: hasSyncKey)

        // Generate custom Decodable init that handles missing keys with default values
        let decodableInitDecl = generateDecodableInit(properties: properties, hasSyncKey: hasSyncKey)

        // Generate Default protocol marker (prevents manual conformance)
        let defaultMarkerDecl: DeclSyntax = """
            @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            """

        var result: [DeclSyntax] = [tableNameDecl, columnsDecl, encodeDecl, decodeDecl, syncKeyColumnsDecl, initDecl, decodableInitDecl, defaultMarkerDecl]

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
            let indexesArray = indexDefStrings.joined(separator: ",\n            ")
            let indexesDecl: DeclSyntax = """
                public static var indexes: [IndexDefinition] {
                    [
                        \(raw: indexesArray)
                    ]
                }
                """
            result.append(indexesDecl)
        }

        // Note: Nested types (non-primitive Codable types) should conform to Default protocol
        // for proper fault-tolerant decoding. Add @Default to your nested structs.

        return result
    }

    /// Generate custom Decodable init(from decoder:) that handles missing keys with default values
    /// This enables backward compatibility when new fields are added to entities
    private static func generateDecodableInit(properties: [PropertyInfo], hasSyncKey: Bool) -> DeclSyntax {
        // Generate CodingKeys enum
        let codingKeysEntries = properties.map { prop in
            "case \(prop.name)"
        }.joined(separator: "\n            ")

        // Check if we have any nested struct types that need Default validation
        let hasNestedTypes = properties.contains { MacroHelpers.isNestedStructType($0.type) }

        // Generate decoding statements
        var decodingStatements: [String] = []

        for prop in properties {
            let propName = prop.name
            let baseType = prop.type.replacingOccurrences(of: "?", with: "")
            let isNestedType = MacroHelpers.isNestedStructType(prop.type)

            // Determine the default value for this property
            let defaultValue: String?
            if let propDefault = prop.defaultValue {
                defaultValue = propDefault
            } else if propName == "id" && !hasSyncKey {
                defaultValue = "UUIDV4()"
            } else if propName == "createdAt" || propName == "updatedAt" {
                defaultValue = "Date()"
            } else {
                defaultValue = nil
            }

            if prop.isOptional {
                // Optional types: use decodeIfPresent, default to nil
                if isNestedType {
                    // Use helper function for nested types to enforce Default constraint
                    decodingStatements.append("self.\(propName) = try Self._decodeNestedIfPresent(\(baseType).self, from: container, forKey: .\(propName))")
                } else {
                    decodingStatements.append("self.\(propName) = try container.decodeIfPresent(\(baseType).self, forKey: .\(propName))")
                }
            } else if let defaultVal = defaultValue {
                // Non-optional with default: use decodeIfPresent with fallback
                // For empty array literals, we need explicit type annotation
                let typedDefault: String
                if defaultVal == "[]" {
                    typedDefault = "\(baseType)()"
                } else {
                    typedDefault = defaultVal
                }
                if isNestedType {
                    // Use helper function for nested types to enforce Default constraint
                    decodingStatements.append("self.\(propName) = try Self._decodeNestedIfPresent(\(baseType).self, from: container, forKey: .\(propName)) ?? \(typedDefault)")
                } else {
                    decodingStatements.append("self.\(propName) = try container.decodeIfPresent(\(baseType).self, forKey: .\(propName)) ?? \(typedDefault)")
                }
            } else {
                // Non-optional without default: required field
                if isNestedType {
                    // Use helper function for nested types to enforce Default constraint
                    decodingStatements.append("self.\(propName) = try Self._decodeNested(\(baseType).self, from: container, forKey: .\(propName))")
                } else {
                    decodingStatements.append("self.\(propName) = try container.decode(\(prop.type).self, forKey: .\(propName))")
                }
            }
        }

        let decodingCode = decodingStatements.joined(separator: "\n        ")

        // Generate helper functions for nested type decoding if needed
        let helperFunctions: String
        if hasNestedTypes {
            helperFunctions = """


                /// Helper to decode nested types with Default constraint (compile-time validation)
                @inline(__always)
                private static func _decodeNested<T: Default & Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> T {
                    try container.decode(T.self, forKey: key)
                }

                /// Helper to decode optional nested types with Default constraint (compile-time validation)
                @inline(__always)
                private static func _decodeNestedIfPresent<T: Default & Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> T? {
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

    /// Generate init method with default values
    /// Priority: 1. Property's own default value (from source)
    ///           2. Built-in defaults for id (UUIDV4()), createdAt/updatedAt (Date())
    private static func generateInitMethod(properties: [PropertyInfo], hasSyncKey: Bool) -> DeclSyntax {
        var params: [String] = []

        for prop in properties {
            let paramName = prop.name
            let paramType = prop.type

            // Determine if this parameter should have a default value
            // Priority: property's own default > built-in defaults
            let defaultValue: String?
            if let propDefault = prop.defaultValue {
                // Use the property's own default value from source
                defaultValue = propDefault
            } else if paramName == "id" && !hasSyncKey {
                // id has default value UUIDV4() for non-sync-key entities
                defaultValue = "UUIDV4()"
            } else if paramName == "createdAt" || paramName == "updatedAt" {
                // createdAt and updatedAt have default value Date()
                defaultValue = "Date()"
            } else {
                defaultValue = nil
            }

            if let defaultVal = defaultValue {
                params.append("\(paramName): \(paramType) = \(defaultVal)")
            } else {
                params.append("\(paramName): \(paramType)")
            }
        }

        let paramsStr = params.joined(separator: ",\n        ")

        // Generate assignments
        var assignments: [String] = []
        for prop in properties {
            assignments.append("self.\(prop.name) = \(prop.name)")
        }
        let assignmentsStr = assignments.joined(separator: "\n        ")

        return """
            public init(
                \(raw: paramsStr)
            ) {
                \(raw: assignmentsStr)
            }
            """
    }

    /// Generate the sqliteEncode() method
    private static func generateSqliteEncode(properties: [PropertyInfo]) throws -> DeclSyntax {
        var encodings: [String] = []

        for prop in properties {
            let columnName = prop.columnName
            let encoding = generateEncodeExpression(for: prop)
            encodings.append("result[\"\(columnName)\"] = \(encoding)")
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

    /// Generate encode expression for a property
    private static func generateEncodeExpression(for prop: PropertyInfo) -> String {
        let propName = prop.name
        let baseType = prop.type.replacingOccurrences(of: "?", with: "")

        // Check if encoding needs try (JSON encoded types - all non-primitive types except UUIDV4)
        let needsTry = !prop.isPrimitive && baseType != "UUIDV4"

        if prop.isOptional {
            // For optional types, the outer closure needs try if inner code throws
            let outerTry = needsTry ? "try " : ""
            // Inner return also needs try if it's a throwing expression
            let innerTry = needsTry ? "try " : ""
            return """
                \(outerTry){
                        if let value = self.\(propName) {
                            return \(innerTry)\(encodeValue(name: "value", type: baseType))
                        } else {
                            return .null
                        }
                    }()
                """
        } else {
            if needsTry {
                return "try \(encodeValue(name: "self.\(propName)", type: baseType))"
            }
            return encodeValue(name: "self.\(propName)", type: baseType)
        }
    }

    /// Generate the value encoding expression for a given type
    private static func encodeValue(name: String, type: String) -> String {
        switch type {
        case "String":
            return ".text(\(name))"
        case "Int":
            return ".integer(Int64(\(name)))"
        case "Int64":
            return ".integer(\(name))"
        case "Int32":
            return ".integer(Int64(\(name)))"
        case "Int16":
            return ".integer(Int64(\(name)))"
        case "Int8":
            return ".integer(Int64(\(name)))"
        case "UInt":
            return ".integer(Int64(\(name)))"
        case "UInt64":
            return ".integer(Int64(\(name)))"
        case "UInt32":
            return ".integer(Int64(\(name)))"
        case "UInt16":
            return ".integer(Int64(\(name)))"
        case "UInt8":
            return ".integer(Int64(\(name)))"
        case "Bool":
            return ".integer(\(name) ? 1 : 0)"
        case "Double":
            return ".real(\(name))"
        case "Float":
            return ".real(Double(\(name)))"
        case "Date":
            return ".real(\(name).timeIntervalSince1970)"
        case "UUID":
            return ".text(\(name).uuidString)"
        case "UUIDV4":
            return ".blob(\(name).data)"
        case "Data":
            return ".blob(\(name))"
        default:
            // Nested Codable type - encode as JSON
            return """
                {
                        let jsonData = try JSONEncoder().encode(\(name))
                        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                            throw StoreError.encodingFailed("Failed to encode \\(\(name)) to JSON")
                        }
                        return .text(jsonString)
                    }()
                """
        }
    }

    /// Generate the sqliteDecode(from:) method
    private static func generateSqliteDecode(properties: [PropertyInfo], structName: String) throws -> DeclSyntax {
        var decodings: [String] = []
        var constructorArgs: [String] = []

        for (index, prop) in properties.enumerated() {
            let varName = "_\(prop.name)"
            let decoding = generateDecodeExpression(for: prop, index: index)
            decodings.append("let \(varName) = \(decoding)")
            constructorArgs.append("\(prop.name): \(varName)")
        }

        let decodingCode = decodings.joined(separator: "\n        ")
        let constructorCode = constructorArgs.joined(separator: ",\n            ")

        return """
            public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                \(raw: decodingCode)
                return Self(
                    \(raw: constructorCode)
                )
            }
            """
    }

    /// Generate decode expression for a property
    private static func generateDecodeExpression(for prop: PropertyInfo, index: Int) -> String {
        let baseType = prop.type.replacingOccurrences(of: "?", with: "")

        // Check if decoding needs try (JSON types - all non-primitive types except UUIDV4)
        let needsTry = !prop.isPrimitive && baseType != "UUIDV4"

        if prop.isOptional {
            // For optional types:
            // - The inner closure call needs try if it throws
            // - The outer closure call also needs try because it contains a throwing call
            let innerTry = needsTry ? "try " : ""
            let outerTry = needsTry ? "try " : ""
            return """
                \(outerTry){
                        if statement.isNull(Int32(\(index))) {
                            return Optional<\(baseType)>.none
                        }
                        return \(innerTry)\(decodeValue(type: baseType, index: index, defaultValue: nil))
                    }()
                """
        } else {
            // For non-optional types with default value, use closure to handle NULL
            if let defaultValue = prop.defaultValue {
                let innerTry = needsTry ? "try " : ""
                let outerTry = needsTry ? "try " : ""
                // For empty array literals, use explicit type annotation to avoid [Any] inference
                let typedDefault: String
                if defaultValue == "[]" {
                    typedDefault = "\(baseType)()"
                } else {
                    typedDefault = defaultValue
                }
                return """
                    \(outerTry){
                            if statement.isNull(Int32(\(index))) {
                                return \(typedDefault)
                            }
                            return \(innerTry)\(decodeValue(type: baseType, index: index, defaultValue: defaultValue))
                        }()
                    """
            }
            // For non-optional types without default value
            if needsTry {
                return "try \(decodeValue(type: baseType, index: index, defaultValue: nil))"
            }
            return decodeValue(type: baseType, index: index, defaultValue: nil)
        }
    }

    /// Generate the value decoding expression for a given type
    /// - Parameters:
    ///   - type: The Swift type name
    ///   - index: The column index
    ///   - defaultValue: Optional default value to use when NULL (for non-optional types)
    private static func decodeValue(type: String, index: Int, defaultValue: String?) -> String {
        // For types that need a fallback, use the default value if provided
        let stringFallback = defaultValue ?? "\"\""
        let dataFallback = defaultValue ?? "Data()"

        switch type {
        case "String":
            return "statement.columnString(Int32(\(index))) ?? \(stringFallback)"
        case "Int":
            return "Int(statement.columnInt64(Int32(\(index))))"
        case "Int64":
            return "statement.columnInt64(Int32(\(index)))"
        case "Int32":
            return "Int32(statement.columnInt64(Int32(\(index))))"
        case "Int16":
            return "Int16(statement.columnInt64(Int32(\(index))))"
        case "Int8":
            return "Int8(statement.columnInt64(Int32(\(index))))"
        case "UInt":
            return "UInt(statement.columnInt64(Int32(\(index))))"
        case "UInt64":
            return "UInt64(statement.columnInt64(Int32(\(index))))"
        case "UInt32":
            return "UInt32(statement.columnInt64(Int32(\(index))))"
        case "UInt16":
            return "UInt16(statement.columnInt64(Int32(\(index))))"
        case "UInt8":
            return "UInt8(statement.columnInt64(Int32(\(index))))"
        case "Bool":
            return "statement.columnInt64(Int32(\(index))) != 0"
        case "Double":
            return "statement.columnDouble(Int32(\(index)))"
        case "Float":
            return "Float(statement.columnDouble(Int32(\(index))))"
        case "Date":
            return "Date(timeIntervalSince1970: statement.columnDouble(Int32(\(index))))"
        case "UUID":
            return "UUID(uuidString: statement.columnString(Int32(\(index))) ?? \"\") ?? UUID()"
        case "UUIDV4":
            return "UUIDV4(data: statement.columnData(Int32(\(index))) ?? Data()) ?? UUIDV4()"
        case "Data":
            return "statement.columnData(Int32(\(index))) ?? \(dataFallback)"
        default:
            // Nested Codable type - decode from JSON
            // If there's a default value and column is NULL, we already handle it in generateDecodeExpression
            return """
                {
                        guard let jsonString = statement.columnString(Int32(\(index))),
                              let jsonData = jsonString.data(using: .utf8) else {
                            throw StoreError.decodingFailed("Failed to decode \(type) from column \(index)")
                        }
                        return try JSONDecoder().decode(\(type).self, from: jsonData)
                    }()
                """
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

        let properties = structDecl.extractProperties()
        let hasIdField = properties.contains(where: { $0.name == "id" })

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

        // Identifiable conformance only if entity has id field
        if hasIdField {
            let identifiable: DeclSyntax = """
                extension \(type.trimmed): Identifiable {}
                """
            if let ext = identifiable.as(ExtensionDeclSyntax.self) {
                extensions.append(ext)
            }
        }

        // Default protocol conformance (marker protocol for fault-tolerant decoding)
        let defaultProtocol: DeclSyntax = """
            extension \(type.trimmed): Default {}
            """
        if let ext = defaultProtocol.as(ExtensionDeclSyntax.self) {
            extensions.append(ext)
        }

        return extensions
    }

    /// Validate that required fields exist with correct types
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
            // When no #SyncKey, id: UUIDV4 is required
            guard let idProp = properties.first(where: { $0.name == "id" }) else {
                throw MacroError.missingRequiredField(
                    structName: structName,
                    fieldName: "id",
                    expectedType: "UUIDV4"
                )
            }

            let idBaseType = idProp.type.replacingOccurrences(of: "?", with: "")
            if idBaseType != "UUIDV4" {
                throw MacroError.wrongFieldType(
                    structName: structName,
                    fieldName: "id",
                    expectedType: "UUIDV4",
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
            return "@Entity '\(structName)': #SyncKey and 'id' field are mutually exclusive. Use either #SyncKey or 'id: UUIDV4', not both."
        case .missingTypeAnnotation(let structName, let fieldName):
            return "@Entity requires '\(structName).\(fieldName)' to have an explicit type annotation. Use 'var \(fieldName): Type = value' instead of 'var \(fieldName) = value'."
        }
    }
}
