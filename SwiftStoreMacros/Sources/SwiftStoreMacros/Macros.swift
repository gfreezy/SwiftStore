// SwiftStoreMacros - Macro declarations for SwiftStore

@_exported import Foundation
@_exported import SwiftStoreProtocols

// MARK: - Entity Macro

/// Entity macro that generates EntityProtocol conformance
/// - Parameter tableName: Optional custom table name. If not provided, uses snake_case of struct name.
@attached(member, names: named(tableName), named(columns), named(sqliteEncode), named(sqliteDecode), named(indexes))
@attached(extension, conformances: EntityProtocol, SQLiteCodable)
public macro Entity(tableName: String? = nil) = #externalMacro(module: "SwiftStoreMacrosImpl", type: "EntityMacro")

// MARK: - Index Macro

/// Freestanding declaration macro for defining indexes inside struct body
/// Usage:
///   @Entity
///   struct User {
///       #Index(\.email, unique: true)
///       #Index(\.firstName, \.lastName, name: "custom_name")
///       var email: String
///       ...
///   }
@freestanding(declaration)
public macro Index<T: EntityProtocol>(_ keyPaths: PartialKeyPath<T>..., unique: Bool = false, name: String? = nil) = #externalMacro(module: "SwiftStoreMacrosImpl", type: "IndexMacro")

// MARK: - Relation Macros (without 'from' - on Entity directly)

/// OneToOne relation macro (without from)
@attached(member)
@attached(peer, names: arbitrary)
public macro OneToOne<Current, To, FromField, ToField>(
    fromField: KeyPath<Current, FromField>,
    to: To.Type,
    toField: KeyPath<To, ToField>
) = #externalMacro(module: "SwiftStoreMacrosImpl", type: "OneToOneMacro")

/// ManyToOne relation macro (without from)
@attached(member)
@attached(peer, names: arbitrary)
public macro ManyToOne<Current, To, FromField, ToField>(
    fromField: KeyPath<Current, FromField>,
    to: To.Type,
    toField: KeyPath<To, ToField>
) = #externalMacro(module: "SwiftStoreMacrosImpl", type: "ManyToOneMacro")

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
) = #externalMacro(module: "SwiftStoreMacrosImpl", type: "OneToOneMacro")

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
) = #externalMacro(module: "SwiftStoreMacrosImpl", type: "OneToManyMacro")

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
) = #externalMacro(module: "SwiftStoreMacrosImpl", type: "ManyToOneMacro")

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
) = #externalMacro(module: "SwiftStoreMacrosImpl", type: "ManyToManyMacro")

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
) = #externalMacro(module: "SwiftStoreMacrosImpl", type: "ManyToManyMacro")
