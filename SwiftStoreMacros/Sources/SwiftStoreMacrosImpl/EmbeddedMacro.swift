import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxBuilder

/// Embedded macro that generates:
/// - Fault-tolerant Decodable conformance
/// - Embedded protocol conformance
/// - SQLiteValueCodable conformance (via Embedded protocol)
///
/// Use this for types that will be embedded in @Entity structs as JSON.
public struct EmbeddedMacro: MemberMacro, ExtensionMacro {

    // MARK: - MemberMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // For structs, generate full Decodable implementation
        if let structDecl = declaration.as(StructDeclSyntax.self) {
            let properties = structDecl.extractProperties()

            // Generate CodingKeys enum and init(from decoder:)
            let decodableInitDecl = generateDecodableInit(properties: properties)

            // Generate memberwise init with default values
            let memberwiseInitDecl = generateMemberwiseInit(properties: properties)

            return [decodableInitDecl, memberwiseInitDecl]
        }

        // For enums, no additional members needed
        if declaration.is(EnumDeclSyntax.self) {
            return []
        }

        throw MacroError.message("@Embedded can only be applied to structs or enums")
    }

    /// Generate memberwise init method with default values
    private static func generateMemberwiseInit(properties: [PropertyInfo]) -> DeclSyntax {
        var params: [String] = []

        for prop in properties {
            let paramName = prop.name
            let paramType = prop.type

            if let defaultValue = prop.defaultValue {
                params.append("\(paramName): \(paramType) = \(defaultValue)")
            } else if prop.isOptional {
                params.append("\(paramName): \(paramType) = nil")
            } else {
                params.append("\(paramName): \(paramType)")
            }
        }

        let paramsStr = params.joined(separator: ", ")

        // Generate assignments
        var assignments: [String] = []
        for prop in properties {
            assignments.append("self.\(prop.name) = \(prop.name)")
        }
        let assignmentsStr = assignments.joined(separator: "\n    ")

        return """
        public init(\(raw: paramsStr)) {
            \(raw: assignmentsStr)
        }
        """
    }

    // MARK: - ExtensionMacro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Support both structs and enums
        guard declaration.is(StructDeclSyntax.self) || declaration.is(EnumDeclSyntax.self) else {
            return []
        }

        var extensions: [ExtensionDeclSyntax] = []

        // Embedded protocol conformance (includes SQLiteValueCodable via protocol extension)
        let embeddedProtocol: DeclSyntax = """
            extension \(type.trimmed): Embedded {}
            """
        if let ext = embeddedProtocol.as(ExtensionDeclSyntax.self) {
            extensions.append(ext)
        }

        return extensions
    }

    // MARK: - Private Helpers

    /// Generate custom Decodable init(from decoder:) that handles missing keys with default values
    private static func generateDecodableInit(properties: [PropertyInfo]) -> DeclSyntax {
        // Generate CodingKeys enum
        let codingKeysEntries = properties.map { prop in
            "case \(prop.name)"
        }.joined(separator: "\n    ")

        // Generate decoding statements
        var decodingStatements: [String] = []

        for prop in properties {
            let propName = prop.name
            let baseType = prop.type.replacingOccurrences(of: "?", with: "")

            if prop.isOptional {
                // Optional types: use decodeIfPresent, default to nil
                decodingStatements.append("self.\(propName) = try container.decodeIfPresent(\(baseType).self, forKey: .\(propName))")
            } else if let defaultValue = prop.defaultValue {
                // Non-optional with default: use decodeIfPresent with fallback
                // For empty array/set literals, we need explicit type annotation
                let typedDefault: String
                if defaultValue == "[]" || defaultValue == "Set()" {
                    typedDefault = "\(baseType)()"
                } else {
                    typedDefault = defaultValue
                }
                decodingStatements.append("self.\(propName) = try container.decodeIfPresent(\(baseType).self, forKey: .\(propName)) ?? \(typedDefault)")
            } else {
                // Non-optional without default: required field
                decodingStatements.append("self.\(propName) = try container.decode(\(prop.type).self, forKey: .\(propName))")
            }
        }

        let decodingCode = decodingStatements.joined(separator: "\n    ")

        return """
        private enum CodingKeys: String, CodingKey {
            \(raw: codingKeysEntries)
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            \(raw: decodingCode)
        }
        """
    }
}
