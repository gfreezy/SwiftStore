import SwiftSyntax

/// Relation type enumeration for macro parsing
enum RelationTypeEnum {
    case oneToOne
    case oneToMany
    case manyToOne
    case manyToMany
}

/// Parsed configuration from relation macro arguments
struct RelationConfig {
    let relationType: RelationTypeEnum

    // 'from' parameter (optional - if missing, relation is on the entity itself)
    let fromType: String?
    let fromField: String?
    let fromKey: String?

    // 'to' parameter (always required)
    let toType: String
    let toField: String
    let toKey: String?

    // Self-reference names (only for ManyToMany self-reference)
    let fromName: String?
    let toName: String?

    var hasFrom: Bool {
        fromType != nil
    }

    var isSelfReference: Bool {
        fromType == toType && fromType != nil
    }

    /// Parse relation configuration from macro arguments
    static func parse(from arguments: LabeledExprListSyntax, relationType: RelationTypeEnum) throws -> RelationConfig {
        var fromType: String?
        var fromField: String?
        var fromKey: String?
        var toType: String?
        var toField: String?
        var toKey: String?
        var fromName: String?
        var toName: String?

        for arg in arguments {
            let label = arg.label?.text ?? ""
            let expr = arg.expression

            switch label {
            case "from":
                fromType = MacroHelpers.extractTypeName(from: expr)
            case "fromField":
                fromField = MacroHelpers.extractPropertyName(from: expr)
            case "fromKey":
                fromKey = MacroHelpers.extractPropertyName(from: expr)
            case "to":
                toType = MacroHelpers.extractTypeName(from: expr)
            case "toField":
                toField = MacroHelpers.extractPropertyName(from: expr)
            case "toKey":
                toKey = MacroHelpers.extractPropertyName(from: expr)
            case "fromName":
                if let stringLiteral = expr.as(StringLiteralExprSyntax.self),
                   let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                    fromName = segment.content.text
                }
            case "toName":
                if let stringLiteral = expr.as(StringLiteralExprSyntax.self),
                   let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                    toName = segment.content.text
                }
            default:
                break
            }
        }

        // Validate required parameters
        guard let toType = toType else {
            throw MacroError.message("Relation macro requires 'to' parameter")
        }

        guard let toField = toField else {
            throw MacroError.message("Relation macro requires 'toField' parameter")
        }

        // If 'from' is specified, fromField, fromKey, and toKey are required
        if fromType != nil {
            guard let _ = fromField else {
                throw MacroError.message("When 'from' is specified, 'fromField' is required")
            }
            guard let _ = fromKey else {
                throw MacroError.message("When 'from' is specified, 'fromKey' is required")
            }
            guard let _ = toKey else {
                throw MacroError.message("When 'from' is specified, 'toKey' is required")
            }
        }

        return RelationConfig(
            relationType: relationType,
            fromType: fromType,
            fromField: fromField,
            fromKey: fromKey,
            toType: toType,
            toField: toField,
            toKey: toKey,
            fromName: fromName,
            toName: toName
        )
    }
}
