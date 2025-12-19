// SwiftStore - A lightweight SQLite persistence framework for Swift
// Based on similar concepts to SwiftData but with macro-based code generation

@_exported import Foundation

// MARK: - Macro Declarations

/// Entity macro that generates EntityProtocol conformance
@attached(member, names: named(tableName), named(columns))
@attached(extension, conformances: EntityProtocol)
public macro Entity() = #externalMacro(module: "SwiftStoreMacros", type: "EntityMacro")

/// RawValue marker to indicate a property is a RawRepresentable enum
/// Use this on enum properties with String or Int raw values
/// Example:
///   @RawValue var status: Status
///   @RawValue(rawType: .integer) var priority: Priority
@attached(peer)
public macro RawValue(rawType: RawValueType = .string) = #externalMacro(module: "SwiftStoreMacros", type: "RawValueMacro")

/// Raw value storage type for enums
public enum RawValueType {
    case string
    case integer
}

/// Index macro for creating database indexes
@attached(member)
public macro Index(_ keyPaths: Any..., unique: Bool = false) = #externalMacro(module: "SwiftStoreMacros", type: "IndexMacro")

// MARK: - Relation Macros (without 'from' - on Entity directly)

/// OneToOne relation macro (without from)
@attached(member)
@attached(peer, names: arbitrary)
public macro OneToOne<Current, To, FromField, ToField>(
    fromField: KeyPath<Current, FromField>,
    to: To.Type,
    toField: KeyPath<To, ToField>
) = #externalMacro(module: "SwiftStoreMacros", type: "OneToOneMacro")

/// ManyToOne relation macro (without from)
@attached(member)
@attached(peer, names: arbitrary)
public macro ManyToOne<Current, To, FromField, ToField>(
    fromField: KeyPath<Current, FromField>,
    to: To.Type,
    toField: KeyPath<To, ToField>
) = #externalMacro(module: "SwiftStoreMacros", type: "ManyToOneMacro")

// MARK: - Relation Macros (with 'from' - separate relation Entity)

/// OneToOne relation macro (with from)
@attached(member)
@attached(peer, names: arbitrary)
public macro OneToOne<From, To, Current, FromField, FromKey, ToField, ToKey>(
    from: From.Type,
    fromField: KeyPath<From, FromField>,
    fromKey: KeyPath<Current, FromKey>,
    to: To.Type,
    toField: KeyPath<To, ToField>,
    toKey: KeyPath<Current, ToKey>
) = #externalMacro(module: "SwiftStoreMacros", type: "OneToOneMacro")

/// OneToMany relation macro (requires from)
@attached(member)
@attached(peer, names: arbitrary)
public macro OneToMany<From, To, Current, FromField, FromKey, ToField, ToKey>(
    from: From.Type,
    fromField: KeyPath<From, FromField>,
    fromKey: KeyPath<Current, FromKey>,
    to: To.Type,
    toField: KeyPath<To, ToField>,
    toKey: KeyPath<Current, ToKey>
) = #externalMacro(module: "SwiftStoreMacros", type: "OneToManyMacro")

/// ManyToOne relation macro (with from)
@attached(member)
@attached(peer, names: arbitrary)
public macro ManyToOne<From, To, Current, FromField, FromKey, ToField, ToKey>(
    from: From.Type,
    fromField: KeyPath<From, FromField>,
    fromKey: KeyPath<Current, FromKey>,
    to: To.Type,
    toField: KeyPath<To, ToField>,
    toKey: KeyPath<Current, ToKey>
) = #externalMacro(module: "SwiftStoreMacros", type: "ManyToOneMacro")

/// ManyToMany relation macro
@attached(member)
@attached(peer, names: arbitrary)
public macro ManyToMany<From, To, Current, FromField, FromKey, ToField, ToKey>(
    from: From.Type,
    fromField: KeyPath<From, FromField>,
    fromKey: KeyPath<Current, FromKey>,
    to: To.Type,
    toField: KeyPath<To, ToField>,
    toKey: KeyPath<Current, ToKey>
) = #externalMacro(module: "SwiftStoreMacros", type: "ManyToManyMacro")

/// ManyToMany relation macro for self-referencing relations
@attached(member)
@attached(peer, names: arbitrary)
public macro ManyToMany<From, To, Current, FromField, FromKey, ToField, ToKey>(
    from: From.Type,
    fromField: KeyPath<From, FromField>,
    fromKey: KeyPath<Current, FromKey>,
    to: To.Type,
    toField: KeyPath<To, ToField>,
    toKey: KeyPath<Current, ToKey>,
    fromName: String,
    toName: String
) = #externalMacro(module: "SwiftStoreMacros", type: "ManyToManyMacro")
