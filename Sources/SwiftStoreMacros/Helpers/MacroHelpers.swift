import SwiftSyntax

/// Helper functions for macro implementations
enum MacroHelpers {
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
        if input.hasSuffix("y") && !input.hasSuffix("ay") && !input.hasSuffix("ey") && !input.hasSuffix("oy") && !input.hasSuffix("uy") {
            return String(input.dropLast()) + "ies"
        } else if input.hasSuffix("s") || input.hasSuffix("x") || input.hasSuffix("ch") || input.hasSuffix("sh") {
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
        case "String", "UUID":
            return "text"
        case "UUIDV4", "Data":
            return "blob"
        case "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Bool":
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
        let primitives = ["String", "Int", "Int8", "Int16", "Int32", "Int64",
                         "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
                         "Double", "Float", "Bool", "Date", "Data", "UUID", "UUIDV4"]
        return primitives.contains(baseType)
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

/// Raw value storage type for RawRepresentable enums
enum RawType {
    case string
    case integer
    case none  // Not a RawRepresentable
}

/// Property information extracted from struct
struct PropertyInfo {
    let name: String
    let type: String
    let isOptional: Bool
    let isLet: Bool
    let rawType: RawType

    var columnName: String {
        MacroHelpers.camelToSnakeCase(name)
    }

    var sqliteType: String {
        // If marked as RawValue, use appropriate type
        switch rawType {
        case .string:
            return "text"
        case .integer:
            return "integer"
        case .none:
            return MacroHelpers.sqliteType(for: type)
        }
    }

    var isPrimitive: Bool {
        MacroHelpers.isPrimitive(type)
    }

    var isRawRepresentable: Bool {
        rawType != .none
    }
}

extension StructDeclSyntax {
    /// Extract all stored properties from a struct
    func extractProperties() -> [PropertyInfo] {
        var properties: [PropertyInfo] = []

        for member in memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                let isLet = varDecl.bindingSpecifier.tokenKind == .keyword(.let)

                // Check for @RawValue attribute
                let rawType = extractRawValueType(from: varDecl.attributes)

                for binding in varDecl.bindings {
                    if let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                       let typeAnnotation = binding.typeAnnotation {
                        let name = identifier.identifier.text
                        let type = typeAnnotation.type.description.trimmingCharacters(in: .whitespaces)
                        let isOptional = MacroHelpers.isOptional(type)

                        properties.append(PropertyInfo(
                            name: name,
                            type: type,
                            isOptional: isOptional,
                            isLet: isLet,
                            rawType: rawType
                        ))
                    }
                }
            }
        }

        return properties
    }

    /// Extract RawValueType from @RawValue attribute
    private func extractRawValueType(from attributes: AttributeListSyntax) -> RawType {
        for attribute in attributes {
            guard case .attribute(let attr) = attribute else { continue }

            let attrName = attr.attributeName.description.trimmingCharacters(in: .whitespaces)
            if attrName == "RawValue" {
                // Check for rawType parameter
                if let arguments = attr.arguments,
                   case .argumentList(let argList) = arguments {
                    for arg in argList {
                        if let memberAccess = arg.expression.as(MemberAccessExprSyntax.self) {
                            let rawTypeName = memberAccess.declName.baseName.text
                            if rawTypeName == "integer" {
                                return .integer
                            } else if rawTypeName == "string" {
                                return .string
                            }
                        }
                    }
                }
                // Default to string if no rawType specified
                return .string
            }
        }
        return .none
    }
}
