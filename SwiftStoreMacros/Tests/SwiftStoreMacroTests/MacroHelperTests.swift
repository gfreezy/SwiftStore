import Testing
@testable import SwiftStoreMacrosImpl

@Suite("Macro Helper Tests")
struct MacroHelperTests {
    @Test("camelToSnakeCase conversion")
    func testCamelToSnakeCase() {
        #expect(MacroHelpers.camelToSnakeCase("userId") == "user_id")
        #expect(MacroHelpers.camelToSnakeCase("createdAt") == "created_at")
        #expect(MacroHelpers.camelToSnakeCase("UserProfile") == "user_profile")
        #expect(MacroHelpers.camelToSnakeCase("id") == "id")
        #expect(MacroHelpers.camelToSnakeCase("XMLParser") == "x_m_l_parser")
    }

    @Test("snakeToCamelCase conversion")
    func testSnakeToCamelCase() {
        #expect(MacroHelpers.snakeToCamelCase("user_id") == "userId")
        #expect(MacroHelpers.snakeToCamelCase("created_at") == "createdAt")
        #expect(MacroHelpers.snakeToCamelCase("user_profile") == "userProfile")
        #expect(MacroHelpers.snakeToCamelCase("id") == "id")
    }

    @Test("capitalizeFirst")
    func testCapitalizeFirst() {
        #expect(MacroHelpers.capitalizeFirst("user") == "User")
        #expect(MacroHelpers.capitalizeFirst("userId") == "UserId")
        #expect(MacroHelpers.capitalizeFirst("") == "")
    }

    @Test("lowercaseFirst")
    func testLowercaseFirst() {
        #expect(MacroHelpers.lowercaseFirst("User") == "user")
        #expect(MacroHelpers.lowercaseFirst("UserId") == "userId")
        #expect(MacroHelpers.lowercaseFirst("") == "")
    }

    @Test("pluralize")
    func testPluralize() {
        #expect(MacroHelpers.pluralize("user") == "users")
        #expect(MacroHelpers.pluralize("tag") == "tags")
        #expect(MacroHelpers.pluralize("category") == "categories")
        #expect(MacroHelpers.pluralize("box") == "boxes")
        #expect(MacroHelpers.pluralize("church") == "churches")
    }

    @Test("singularize")
    func testSingularize() {
        #expect(MacroHelpers.singularize("users") == "user")
        #expect(MacroHelpers.singularize("tags") == "tag")
        #expect(MacroHelpers.singularize("categories") == "category")
        #expect(MacroHelpers.singularize("boxes") == "box")
    }

    @Test("sqliteType mapping")
    func testSqliteType() {
        #expect(MacroHelpers.sqliteType(for: "String") == "text")
        #expect(MacroHelpers.sqliteType(for: "UUID") == "text")
        #expect(MacroHelpers.sqliteType(for: "UUIDV4") == "blob")
        #expect(MacroHelpers.sqliteType(for: "Int") == "integer")
        #expect(MacroHelpers.sqliteType(for: "Int64") == "integer")
        #expect(MacroHelpers.sqliteType(for: "Bool") == "integer")
        #expect(MacroHelpers.sqliteType(for: "Double") == "real")
        #expect(MacroHelpers.sqliteType(for: "Date") == "real")
        #expect(MacroHelpers.sqliteType(for: "Data") == "blob")
        #expect(MacroHelpers.sqliteType(for: "Address") == "text")  // nested Codable
        #expect(MacroHelpers.sqliteType(for: "Int?") == "integer")
    }

    @Test("isOptional check")
    func testIsOptional() {
        #expect(MacroHelpers.isOptional("Int?") == true)
        #expect(MacroHelpers.isOptional("String?") == true)
        #expect(MacroHelpers.isOptional("Optional<Int>") == true)
        #expect(MacroHelpers.isOptional("Int") == false)
        #expect(MacroHelpers.isOptional("String") == false)
    }

    @Test("isPrimitive check")
    func testIsPrimitive() {
        #expect(MacroHelpers.isPrimitive("String") == true)
        #expect(MacroHelpers.isPrimitive("Int") == true)
        #expect(MacroHelpers.isPrimitive("UUID") == true)
        #expect(MacroHelpers.isPrimitive("UUIDV4") == true)
        #expect(MacroHelpers.isPrimitive("Date") == true)
        #expect(MacroHelpers.isPrimitive("Address") == false)
        #expect(MacroHelpers.isPrimitive("UserSettings") == false)
    }
}
