import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxBuilder

/// Default macro that generates fault-tolerant Decodable conformance
/// and Default protocol conformance for Codable structs
public struct DefaultMacro: MemberMacro, ExtensionMacro {

    // MARK: - MemberMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.message("@Default can only be applied to structs")
        }

        let properties = structDecl.extractProperties()

        // Generate CodingKeys enum and init(from decoder:)
        let decodableInitDecl = generateDecodableInit(properties: properties)

        return [decodableInitDecl]
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

        // Default protocol conformance
        let defaultProtocol: DeclSyntax = """
            extension \(type.trimmed): Default {}
            """
        if let ext = defaultProtocol.as(ExtensionDeclSyntax.self) {
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
        }.joined(separator: "\n            ")

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
                // For empty array literals, we need explicit type annotation
                let typedDefault: String
                if defaultValue == "[]" {
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

        let decodingCode = decodingStatements.joined(separator: "\n        ")

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
