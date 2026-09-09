import SwiftSyntax

/// Helper functions for macro implementations
enum MacroHelpers {

    // MARK: - Indentation Helpers

    /// Indent each line of a multi-line string by the specified number of spaces
    /// - Parameters:
    ///   - text: The text to indent
    ///   - spaces: Number of spaces to add at the beginning of each line
    /// - Returns: Indented text
    static func indent(_ text: String, by spaces: Int) -> String {
        let indentation = String(repeating: " ", count: spaces)
        return
            text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? String($0) : indentation + $0 }
            .joined(separator: "\n")
    }

    /// Join lines with separator and indent each line
    /// - Parameters:
    ///   - lines: Array of lines to join (each element may contain multiple lines)
    ///   - separator: Separator between lines (default: "\n")
    ///   - indent: Number of spaces to indent each line (default: 0)
    /// - Returns: Joined and indented string
    static func joinLines(_ lines: [String], separator: String = "\n", indent spaces: Int = 0)
        -> String
    {
        if spaces == 0 {
            return lines.joined(separator: separator)
        }
        // Handle multiline strings within each element
        return
            lines
            .map { element in
                indent(element, by: spaces)
            }
            .joined(separator: separator)
    }

    /// Join lines for array/list format with comma separator
    /// - Parameters:
    ///   - items: Array of items
    ///   - indent: Number of spaces to indent each item
    /// - Returns: Comma-separated string with each item on new line
    static func joinList(_ items: [String], indent spaces: Int = 0) -> String {
        joinLines(items, separator: ",\n", indent: spaces)
    }

    /// Create indentation string
    /// - Parameter spaces: Number of spaces
    /// - Returns: String of spaces
    static func indentString(_ spaces: Int) -> String {
        String(repeating: " ", count: spaces)
    }

    /// Wrap content in a block with proper indentation
    /// - Parameters:
    ///   - header: Block header (e.g., "do {", "if condition {")
    ///   - content: Content inside the block
    ///   - footer: Block footer (e.g., "}", "} catch {")
    ///   - contentIndent: Indentation for content inside the block
    /// - Returns: Formatted block string
    static func wrapBlock(header: String, content: String, footer: String, contentIndent: Int = 4)
        -> String
    {
        let indentedContent = indent(content, by: contentIndent)
        return "\(header)\n\(indentedContent)\n\(footer)"
    }

    /// Create a do-catch block
    /// - Parameters:
    ///   - tryContent: Content in the do block
    ///   - catchContent: Content in the catch block
    ///   - logField: Optional field name to generate os_log error logging
    ///   - indent: Base indentation for the block content
    /// - Returns: Formatted do-catch block
    static func doCatchBlock(
        try tryContent: String,
        catch catchContent: String,
        logFieldName: String,
        logTypeName: String,
        indent: Int = 4
    ) -> String {
        let tryIndent = indentString(indent)
        let catchIndent = indentString(indent)

        var catchLines: [String] = []

        catchLines.append(
            "SwiftStoreLogger.error(\"Failed to decode '\(logTypeName).\(logFieldName)': \\(error)\")"
        )

        catchLines.append(catchContent)

        let catchCode = catchLines.map { "\(catchIndent)\($0)" }.joined(separator: "\n")

        return """
            do {
            \(tryIndent)\(tryContent)
            } catch {
            \(catchCode)
            }
            """
    }

    /// Format parameters for function/init declaration
    /// - Parameters:
    ///   - params: Array of parameter strings (e.g., ["name: String", "age: Int = 0"])
    ///   - indent: Indentation for each parameter
    ///   - singleLine: If true and params fit, keep on single line
    /// - Returns: Formatted parameters string
    static func formatParams(_ params: [String], indent spaces: Int = 4, singleLine: Bool = false)
        -> String
    {
        if singleLine && params.joined(separator: ", ").count < 80 {
            return params.joined(separator: ", ")
        }
        return joinLines(params, separator: ",\n", indent: spaces)
    }

    /// Format assignments for init body
    /// - Parameters:
    ///   - assignments: Array of assignment strings (e.g., ["self.name = name"])
    ///   - indent: Indentation for each assignment
    /// - Returns: Formatted assignments string
    static func formatAssignments(_ assignments: [String], indent spaces: Int = 4) -> String {
        joinLines(assignments, separator: "\n", indent: spaces)
    }

    // MARK: - String Case Conversion

    /// Convert camelCase to snake_case
    static func camelToSnakeCase(_ input: String) -> String {
        var result = ""
        for (index, char) in input.enumerated() {
            if char.isUppercase {
                if index > 0 {
                    result.append("_")
                }
                result.append(char.lowercased())
            } else {
                result.append(char)
            }
        }
        return result
    }

    /// Convert snake_case to camelCase
    static func snakeToCamelCase(_ input: String) -> String {
        let parts = input.split(separator: "_")
        guard let first = parts.first else { return input }

        var result = String(first)
        for part in parts.dropFirst() {
            result += part.capitalized
        }
        return result
    }

    /// Capitalize first letter
    static func capitalizeFirst(_ input: String) -> String {
        guard let first = input.first else { return input }
        return first.uppercased() + input.dropFirst()
    }

    /// Lowercase first letter
    static func lowercaseFirst(_ input: String) -> String {
        guard let first = input.first else { return input }
        return first.lowercased() + input.dropFirst()
    }

    /// Get pluralized form (simple rules)
    static func pluralize(_ input: String) -> String {
        if input.hasSuffix("y") && !input.hasSuffix("ay") && !input.hasSuffix("ey")
            && !input.hasSuffix("oy") && !input.hasSuffix("uy")
        {
            return String(input.dropLast()) + "ies"
        } else if input.hasSuffix("s") || input.hasSuffix("x") || input.hasSuffix("ch")
            || input.hasSuffix("sh")
        {
            return input + "es"
        } else {
            return input + "s"
        }
    }

    /// Get singular form (simple rules)
    static func singularize(_ input: String) -> String {
        if input.hasSuffix("ies") {
            return String(input.dropLast(3)) + "y"
        } else if input.hasSuffix("es") {
            return String(input.dropLast(2))
        } else if input.hasSuffix("s") {
            return String(input.dropLast())
        }
        return input
    }

    /// Extract property name from KeyPath expression
    static func extractPropertyName(from keyPath: ExprSyntax) -> String? {
        // Handle KeyPathExprSyntax: \Type.property or \.property
        if let keyPathExpr = keyPath.as(KeyPathExprSyntax.self) {
            // Get the last component
            if let lastComponent = keyPathExpr.components.last?.component {
                if let property = lastComponent.as(KeyPathPropertyComponentSyntax.self) {
                    return property.declName.baseName.text
                }
            }
        }

        // Fallback: try to extract from string representation
        let text = keyPath.description.trimmingCharacters(in: .whitespaces)
        if let dotIndex = text.lastIndex(of: ".") {
            return String(text[text.index(after: dotIndex)...])
        }

        return nil
    }

    /// Extract type name from type expression
    static func extractTypeName(from expr: ExprSyntax) -> String? {
        // Handle MemberAccessExprSyntax: Type.self
        if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
            if memberAccess.declName.baseName.text == "self" {
                if let base = memberAccess.base {
                    return base.description.trimmingCharacters(in: .whitespaces)
                }
            }
        }

        // Handle DeclReferenceExprSyntax: Type
        if let declRef = expr.as(DeclReferenceExprSyntax.self) {
            return declRef.baseName.text
        }

        return nil
    }

    /// Get SQLite type from Swift type name
    static func sqliteType(for swiftType: String) -> String {
        let baseType = swiftType.replacingOccurrences(of: "?", with: "")

        switch baseType {
        case "String", "UUID", "URL":
            return "text"
        case "UUIDV7", "Data":
            return "blob"
        case "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32",
            "UInt64", "Bool":
            return "integer"
        case "Double", "Float", "Date":
            return "real"
        default:
            // Assume nested Codable type, store as JSON text
            return "text"
        }
    }

    /// Check if type is optional
    static func isOptional(_ typeString: String) -> Bool {
        typeString.hasSuffix("?") || typeString.hasPrefix("Optional<")
    }

    /// Check if type is a primitive SQLite type
    static func isPrimitive(_ typeString: String) -> Bool {
        let baseType = typeString.replacingOccurrences(of: "?", with: "")
        let primitives = [
            "String", "Int", "Int8", "Int16", "Int32", "Int64",
            "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
            "Double", "Float", "Bool", "Date", "Data", "UUID", "UUIDV7", "URL",
            "CGFloat",
        ]
        return primitives.contains(baseType)
    }

    /// Check if type is a nested struct that needs Embedded constraint validation
    /// Returns false for primitives and collections with primitive elements
    static func isNestedStructType(_ typeString: String) -> Bool {
        let baseType = typeString.replacingOccurrences(of: "?", with: "")

        // Skip primitive types
        if isPrimitive(baseType) {
            return false
        }

        // Check if it's a collection type
        if let collectionKind = CollectionKind.parse(from: baseType) {
            // If the element/value type is primitive, it's not a nested struct type
            // For dictionaries, check the value type
            switch collectionKind {
            case .array(let elementType), .set(let elementType):
                return !isPrimitive(elementType)
            case .dictionary(_, let valueType):
                return !isPrimitive(valueType)
            }
        }

        // Not primitive and not a collection with primitive elements -> nested struct type
        return true
    }

    /// Validate that a field exists in the properties list
    static func validateFieldExists(
        properties: [PropertyInfo],
        fieldName: String,
        structName: String
    ) throws {
        guard properties.contains(where: { $0.name == fieldName }) else {
            throw MacroError.fieldNotFound(structName: structName, fieldName: fieldName)
        }
    }
}

/// Collection type kind
enum CollectionKind: Equatable {
    case array(elementType: String)
    case set(elementType: String)
    case dictionary(keyType: String, valueType: String)

    /// Parse collection kind from type string
    /// - Parameter typeString: The type string (e.g., "[String]", "Set<Int>", "[String: Int]")
    /// - Returns: CollectionKind if the type is a collection, nil otherwise
    static func parse(from typeString: String) -> CollectionKind? {
        // Remove optional wrapper first
        var baseType = typeString
        if baseType.hasSuffix("?") {
            baseType = String(baseType.dropLast())
        } else if baseType.hasPrefix("Optional<") && baseType.hasSuffix(">") {
            baseType = String(baseType.dropFirst(9).dropLast())
        }

        // Check for Array syntax: [ElementType] or Array<ElementType>
        if baseType.hasPrefix("[") && baseType.hasSuffix("]") && !baseType.contains(":") {
            let elementType = String(baseType.dropFirst().dropLast())
            return .array(elementType: elementType.trimmingCharacters(in: .whitespaces))
        }

        if baseType.hasPrefix("Array<") && baseType.hasSuffix(">") {
            let elementType = String(baseType.dropFirst(6).dropLast())
            return .array(elementType: elementType.trimmingCharacters(in: .whitespaces))
        }

        // Check for Set syntax: Set<ElementType>
        if baseType.hasPrefix("Set<") && baseType.hasSuffix(">") {
            let elementType = String(baseType.dropFirst(4).dropLast())
            return .set(elementType: elementType.trimmingCharacters(in: .whitespaces))
        }

        // Check for Dictionary syntax: [KeyType: ValueType] or Dictionary<KeyType, ValueType>
        if baseType.hasPrefix("[") && baseType.hasSuffix("]") && baseType.contains(":") {
            let inner = String(baseType.dropFirst().dropLast())
            if let colonIndex = inner.firstIndex(of: ":") {
                let keyType = String(inner[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let valueType = String(inner[inner.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                return .dictionary(keyType: keyType, valueType: valueType)
            }
        }

        if baseType.hasPrefix("Dictionary<") && baseType.hasSuffix(">") {
            let inner = String(baseType.dropFirst(11).dropLast())
            if let commaIndex = inner.firstIndex(of: ",") {
                let keyType = String(inner[..<commaIndex]).trimmingCharacters(in: .whitespaces)
                let valueType = String(inner[inner.index(after: commaIndex)...]).trimmingCharacters(in: .whitespaces)
                return .dictionary(keyType: keyType, valueType: valueType)
            }
        }

        return nil
    }

    /// The element type for Array and Set, or the value type for Dictionary
    var elementType: String {
        switch self {
        case .array(let elementType), .set(let elementType):
            return elementType
        case .dictionary(_, let valueType):
            return valueType
        }
    }

    /// Whether this is an array
    var isArray: Bool {
        if case .array = self { return true }
        return false
    }

    /// Whether this is a set
    var isSet: Bool {
        if case .set = self { return true }
        return false
    }

    /// Whether this is a dictionary
    var isDictionary: Bool {
        if case .dictionary = self { return true }
        return false
    }
}

/// Property information extracted from struct
struct PropertyInfo {
    let name: String
    let type: String
    let isOptional: Bool
    let isLet: Bool
    /// The default value expression as source code string (e.g., "\"\"", "0", "[]")
    var defaultValue: String?
    /// Collection type information if this is an Array, Set, or Dictionary
    let collectionKind: CollectionKind?

    var columnName: String {
        MacroHelpers.camelToSnakeCase(name)
    }

    var sqliteType: String {
        MacroHelpers.sqliteType(for: type)
    }

    var isPrimitive: Bool {
        MacroHelpers.isPrimitive(type)
    }

    /// Whether this property is a collection type (Array, Set, or Dictionary)
    var isCollection: Bool {
        collectionKind != nil
    }

    /// Whether this property is an Array
    var isArray: Bool {
        collectionKind?.isArray ?? false
    }

    /// Whether this property is a Set
    var isSet: Bool {
        collectionKind?.isSet ?? false
    }

    /// Whether this property is a Dictionary
    var isDictionary: Bool {
        collectionKind?.isDictionary ?? false
    }
}

extension StructDeclSyntax {
    /// Extract all stored properties from a struct (excludes computed properties)
    func extractProperties() -> [PropertyInfo] {
        var properties: [PropertyInfo] = []

        for member in memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                let isLet = varDecl.bindingSpecifier.tokenKind == .keyword(.let)

                for binding in varDecl.bindings {
                    // Skip computed properties (those with accessor blocks like get/set)
                    if binding.accessorBlock != nil {
                        continue
                    }

                    if let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                        let typeAnnotation = binding.typeAnnotation
                    {
                        let name = identifier.identifier.text
                        // Use trimmedDescription to remove trivia (comments, whitespace)
                        let type = typeAnnotation.type.trimmedDescription
                        let isOptional = MacroHelpers.isOptional(type)

                        // Extract default value if present (e.g., var name: String = "")
                        // Also check for @Default attribute on `let` properties
                        var defaultValue: String?
                        if let initializer = binding.initializer {
                            // Use trimmedDescription to remove trivia (comments, whitespace)
                            defaultValue = initializer.value.trimmedDescription
                        } else {
                            // Check for @Default(value) attribute
                            defaultValue = DefaultMarkerParser.extractDefaultValue(from: varDecl.attributes)
                        }

                        // Parse collection kind
                        let collectionKind = CollectionKind.parse(from: type)

                        properties.append(
                            PropertyInfo(
                                name: name,
                                type: type,
                                isOptional: isOptional,
                                isLet: isLet,
                                defaultValue: defaultValue,
                                collectionKind: collectionKind
                            ))
                    }
                }
            }
        }

        return properties
    }

    /// Validate that all stored properties have explicit type annotations
    /// Throws MacroError if any property is missing a type annotation
    func validateAllPropertiesHaveTypes(structName: String) throws {
        for member in memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                // Skip computed properties (those with accessor blocks but no initializer)
                let hasAccessor = varDecl.bindings.contains { binding in
                    binding.accessorBlock != nil
                }
                if hasAccessor {
                    continue
                }

                for binding in varDecl.bindings {
                    if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                        let name = identifier.identifier.text

                        // Check if type annotation is missing
                        if binding.typeAnnotation == nil {
                            throw MacroError.missingTypeAnnotation(
                                structName: structName,
                                fieldName: name
                            )
                        }
                    }
                }
            }
        }
    }
}
