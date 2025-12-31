// SwiftStoreMacros - Macro declarations for SwiftStore

@_exported import Foundation
@_exported import SwiftStoreProtocols

// MARK: - Entity Macro

/// Entity macro that generates EntityProtocol conformance
/// - Parameter tableName: Optional custom table name. If not provided, uses snake_case of struct name.
/// - Auto-generates init with default values: id = UUIDV4(), createdAt = Date(), updatedAt = Date()
/// - For #SyncKey entities: generates `id` computed property and `SyncKeyID` struct for Identifiable
@attached(member, names: named(tableName), named(columns), named(sqliteEncode), named(sqliteDecode), named(indexes), named(syncKeyColumns), named(init), named(CodingKeys), named(_decodeNested), named(_decodeNestedIfPresent), named(_defaultMacroMarker), named(id), named(SyncKeyID))
@attached(extension, conformances: EntityProtocol, SQLiteCodable, Identifiable, Sendable, Default)
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

// MARK: - SyncKey Macro

/// Freestanding declaration macro for defining sync key inside struct body
/// The sync key is used to uniquely identify entities during synchronization.
/// A unique index is automatically created for the sync key columns.
/// The sync key columns become the primary key when #SyncKey is used.
///
/// Note: #SyncKey and `id` field are mutually exclusive:
/// - Use #SyncKey for sync-based entities (no id field)
/// - Use `id: UUIDV4` for standard entities (no #SyncKey)
///
/// Usage:
///   @Entity
///   struct User {
///       #SyncKey<User>(\.email)                  // Single field sync key
///       var email: String
///       var name: String
///       let createdAt: Date
///       let updatedAt: Date
///   }
///
///   @Entity
///   struct Employee {
///       #SyncKey<Employee>(\.companyId, \.employeeCode)  // Composite key
///       var companyId: UUIDV4
///       var employeeCode: String
///       var name: String
///       let createdAt: Date
///       let updatedAt: Date
///   }
@freestanding(declaration)
public macro SyncKey<T: EntityProtocol>(_ keyPaths: PartialKeyPath<T>...) = #externalMacro(module: "SwiftStoreMacrosImpl", type: "SyncKeyMacro")

// MARK: - Default Macro

/// Default macro that generates fault-tolerant Decodable conformance for Codable structs.
///
/// This macro generates:
/// - `CodingKeys` enum
/// - `init(from decoder: Decoder)` that uses default values for missing fields
///
/// Fields with default values will use `decodeIfPresent` with fallback to the default.
/// Fields without default values will use `decode` and throw if missing.
///
/// Usage:
/// ```swift
/// @Default
/// struct UserSettings: Codable {
///     var theme: String = "light"   // Uses "light" if missing
///     var fontSize: Int = 14        // Uses 14 if missing
///     var userId: String            // Required, throws if missing
/// }
/// ```
@attached(member, names: named(CodingKeys), named(init), named(_defaultMacroMarker))
@attached(extension, conformances: Default)
public macro Default() = #externalMacro(module: "SwiftStoreMacrosImpl", type: "DefaultMacro")
