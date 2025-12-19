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

        // Validate required fields
        try validateRequiredFields(properties: properties, structName: structName)

        // Generate column definitions
        var columnDefs: [String] = []
        for prop in properties {
            let nullable = prop.isOptional
            let primaryKey = prop.name == "id"
            let colType = prop.sqliteType
            let isJSON = !prop.isPrimitive && prop.type != "UUIDV4"

            var def = "ColumnDefinition(name: \"\(prop.columnName)\", type: .\(colType)"
            if nullable {
                def += ", nullable: true"
            }
            if primaryKey {
                def += ", primaryKey: true"
            }
            if isJSON {
                def += ", isJSONEncoded: true"
            }
            def += ")"
            columnDefs.append(def)
        }

        let columnsArray = columnDefs.joined(separator: ",\n            ")

        let tableNameDecl: DeclSyntax = """
            public static var tableName: String { "\(raw: tableName)" }
            """

        let columnsDecl: DeclSyntax = """
            public static var columns: [ColumnDefinition] {
                [
                    \(raw: columnsArray)
                ]
            }
            """

        // Generate sqliteEncode() method
        let encodeDecl = try generateSqliteEncode(properties: properties)

        // Generate sqliteDecode(from:) method
        let decodeDecl = try generateSqliteDecode(properties: properties, structName: structName)

        return [tableNameDecl, columnsDecl, encodeDecl, decodeDecl]
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
                        return \(innerTry)\(decodeValue(type: baseType, index: index))
                    }()
                """
        } else {
            // For non-optional types, we need try directly
            if needsTry {
                return "try \(decodeValue(type: baseType, index: index))"
            }
            return decodeValue(type: baseType, index: index)
        }
    }

    /// Generate the value decoding expression for a given type
    private static func decodeValue(type: String, index: Int) -> String {
        switch type {
        case "String":
            return "statement.columnString(Int32(\(index))) ?? \"\""
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
            return "statement.columnData(Int32(\(index))) ?? Data()"
        default:
            // Nested Codable type - decode from JSON
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
        // EntityProtocol conformance
        let entityProtocol: DeclSyntax = """
            extension \(type.trimmed): EntityProtocol {}
            """

        // SQLiteCodable conformance (for optimized encode/decode)
        let sqliteCodable: DeclSyntax = """
            extension \(type.trimmed): SQLiteCodable {}
            """

        var extensions: [ExtensionDeclSyntax] = []

        if let ext = entityProtocol.as(ExtensionDeclSyntax.self) {
            extensions.append(ext)
        }

        if let ext = sqliteCodable.as(ExtensionDeclSyntax.self) {
            extensions.append(ext)
        }

        return extensions
    }

    /// Validate that required fields exist with correct types
    private static func validateRequiredFields(properties: [PropertyInfo], structName: String) throws {
        // Check for id: UUIDV4
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

/// Macro errors with detailed messages
public enum MacroError: Error, CustomStringConvertible {
    case message(String)
    case missingRequiredField(structName: String, fieldName: String, expectedType: String)
    case wrongFieldType(structName: String, fieldName: String, expectedType: String, actualType: String)
    case fieldMustNotBeOptional(structName: String, fieldName: String)
    case fieldNotFound(structName: String, fieldName: String)
    case invalidKeyPath(keyPath: String)

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
        }
    }
}
