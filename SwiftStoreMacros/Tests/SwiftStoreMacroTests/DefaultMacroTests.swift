import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import SwiftStoreMacrosImpl

final class DefaultMacroTests: XCTestCase {

    // MARK: - Basic @Default Expansion Tests

    func testDefaultMacroExpandsToNothing() {
        // @Default is a peer macro that expands to nothing (marker only)
        assertMacroExpansion(
            """
            @Default("test")
            let name: String
            """,
            expandedSource: """
                let name: String
                """,
            macros: testMacros
        )
    }

    func testDefaultMacroWithIntExpandsToNothing() {
        assertMacroExpansion(
            """
            @Default(42)
            let count: Int
            """,
            expandedSource: """
                let count: Int
                """,
            macros: testMacros
        )
    }

    func testDefaultMacroWithBoolExpandsToNothing() {
        assertMacroExpansion(
            """
            @Default(true)
            let enabled: Bool
            """,
            expandedSource: """
                let enabled: Bool
                """,
            macros: testMacros
        )
    }

    func testDefaultMacroWithNilExpandsToNothing() {
        assertMacroExpansion(
            """
            @Default(nil)
            let optionalName: String?
            """,
            expandedSource: """
                let optionalName: String?
                """,
            macros: testMacros
        )
    }

    func testDefaultMacroWithArrayExpandsToNothing() {
        assertMacroExpansion(
            """
            @Default([])
            let items: [String]
            """,
            expandedSource: """
                let items: [String]
                """,
            macros: testMacros
        )
    }

    func testDefaultMacroWithDictionaryExpandsToNothing() {
        assertMacroExpansion(
            """
            @Default([:])
            let metadata: [String: Int]
            """,
            expandedSource: """
                let metadata: [String: Int]
                """,
            macros: testMacros
        )
    }

    func testDefaultMacroWithNestedTypeExpandsToNothing() {
        assertMacroExpansion(
            """
            @Default(NestedType())
            let nested: NestedType
            """,
            expandedSource: """
                let nested: NestedType
                """,
            macros: testMacros
        )
    }

    func testDefaultMacroWithEnumValueExpandsToNothing() {
        assertMacroExpansion(
            """
            @Default(.active)
            let status: Status
            """,
            expandedSource: """
                let status: Status
                """,
            macros: testMacros
        )
    }

    // MARK: - @Default with @Embedded Integration Tests

    func testEmbeddedWithSingleDefaultLetProperty() {
        assertMacroExpansion(
            """
            @Embedded
            struct SingleProp {
                @Default("hello")
                let name: String
            }
            """,
            expandedSource: """
                struct SingleProp {
                    let name: String

                    public init(
                        name: String = "hello"
                    ) {
                        self.name = name
                    }
                }

                extension SingleProp: Embedded {
                }

                extension SingleProp: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case name
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.name = try container.decode(String.self, forKey: .name)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'SingleProp.name': \\(error)")
                            self.name = "hello"
                        }
                    }

                }

                extension SingleProp: Encodable {
                }

                extension SingleProp: Equatable {
                }

                extension SingleProp: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    func testEmbeddedWithDefaultNilProperty() {
        assertMacroExpansion(
            """
            @Embedded
            struct NilDefault {
                @Default(nil)
                let optionalName: String?
            }
            """,
            expandedSource: """
                struct NilDefault {
                    let optionalName: String?

                    public init(
                        optionalName: String? = nil
                    ) {
                        self.optionalName = optionalName
                    }
                }

                extension NilDefault: Embedded {
                }

                extension NilDefault: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case optionalName
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.optionalName = try container.decodeIfPresent(String.self, forKey: .optionalName)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'NilDefault.optionalName': \\(error)")
                            self.optionalName = nil
                        }
                    }

                }

                extension NilDefault: Encodable {
                }

                extension NilDefault: Equatable {
                }

                extension NilDefault: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    func testEmbeddedWithTwoDefaultProperties() {
        assertMacroExpansion(
            """
            @Embedded
            struct TwoProps {
                @Default("light")
                let theme: String
                @Default(true)
                let notifications: Bool
            }
            """,
            expandedSource: """
                struct TwoProps {
                    let theme: String
                    let notifications: Bool

                    public init(
                        theme: String = "light",
                        notifications: Bool = true
                    ) {
                        self.theme = theme
                        self.notifications = notifications
                    }
                }

                extension TwoProps: Embedded {
                }

                extension TwoProps: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case theme
                        case notifications
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.theme = try container.decode(String.self, forKey: .theme)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'TwoProps.theme': \\(error)")
                            self.theme = "light"
                        }
                        do {
                            self.notifications = try container.decode(Bool.self, forKey: .notifications)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'TwoProps.notifications': \\(error)")
                            self.notifications = true
                        }
                    }

                }

                extension TwoProps: Encodable {
                }

                extension TwoProps: Equatable {
                }

                extension TwoProps: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    func testEmbeddedWithMixedVarAndDefaultLet() {
        assertMacroExpansion(
            """
            @Embedded
            struct MixedProps {
                var mutableName: String = "default"
                @Default("immutable")
                let immutableName: String
            }
            """,
            expandedSource: """
                struct MixedProps {
                    var mutableName: String = "default"
                    let immutableName: String

                    public init(
                        mutableName: String = "default",
                        immutableName: String = "immutable"
                    ) {
                        self.mutableName = mutableName
                        self.immutableName = immutableName
                    }
                }

                extension MixedProps: Embedded {
                }

                extension MixedProps: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case mutableName
                        case immutableName
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.mutableName = try container.decode(String.self, forKey: .mutableName)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'MixedProps.mutableName': \\(error)")
                            self.mutableName = "default"
                        }
                        do {
                            self.immutableName = try container.decode(String.self, forKey: .immutableName)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'MixedProps.immutableName': \\(error)")
                            self.immutableName = "immutable"
                        }
                    }

                }

                extension MixedProps: Encodable {
                }

                extension MixedProps: Equatable {
                }

                extension MixedProps: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    func testEmbeddedWithDefaultArrayAndDict() {
        assertMacroExpansion(
            """
            @Embedded
            struct Collections {
                @Default([])
                let tags: [String]
                @Default([:])
                let metadata: [String: Int]
            }
            """,
            expandedSource: """
                struct Collections {
                    let tags: [String]
                    let metadata: [String: Int]

                    public init(
                        tags: [String] = [],
                        metadata: [String: Int] = [:]
                    ) {
                        self.tags = tags
                        self.metadata = metadata
                    }
                }

                extension Collections: Embedded {
                }

                extension Collections: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case tags
                        case metadata
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.tags = try container.decode([String].self, forKey: .tags)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'Collections.tags': \\(error)")
                            self.tags = []
                        }
                        do {
                            self.metadata = try container.decode([String: Int].self, forKey: .metadata)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'Collections.metadata': \\(error)")
                            self.metadata = [:]
                        }
                    }

                }

                extension Collections: Encodable {
                }

                extension Collections: Equatable {
                }

                extension Collections: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    func testEmbeddedWithDefaultNestedType() {
        assertMacroExpansion(
            """
            @Embedded
            struct Container {
                @Default(NestedType())
                let nested: NestedType
            }
            """,
            expandedSource: """
                struct Container {
                    let nested: NestedType

                    public init(
                        nested: NestedType = NestedType()
                    ) {
                        self.nested = nested
                    }
                }

                extension Container: Embedded {
                }

                extension Container: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case nested
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.nested = try Self._decodeNested(NestedType.self, from: container, forKey: .nested)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'Container.nested': \\(error)")
                            self.nested = NestedType()
                        }
                    }
                    /// Helper to decode nested types with Embedded constraint (compile-time validation)
                    @inline(__always)
                    private static func _decodeNested<T: Embedded & Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> T {
                        try container.decode(T.self, forKey: key)
                    }

                    /// Helper to decode optional nested types with Embedded constraint (compile-time validation)
                    @inline(__always)
                    private static func _decodeNestedIfPresent<T: Embedded & Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> T? {
                        try container.decodeIfPresent(T.self, forKey: key)
                    }
                }

                extension Container: Encodable {
                }

                extension Container: Equatable {
                }

                extension Container: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    func testEmbeddedWithDefaultEnumValue() {
        assertMacroExpansion(
            """
            @Embedded
            struct StatusConfig {
                @Default(.active)
                let status: Status
            }
            """,
            expandedSource: """
                struct StatusConfig {
                    let status: Status

                    public init(
                        status: Status = .active
                    ) {
                        self.status = status
                    }
                }

                extension StatusConfig: Embedded {
                }

                extension StatusConfig: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case status
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.status = try Self._decodeNested(Status.self, from: container, forKey: .status)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'StatusConfig.status': \\(error)")
                            self.status = .active
                        }
                    }
                    /// Helper to decode nested types with Embedded constraint (compile-time validation)
                    @inline(__always)
                    private static func _decodeNested<T: Embedded & Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> T {
                        try container.decode(T.self, forKey: key)
                    }

                    /// Helper to decode optional nested types with Embedded constraint (compile-time validation)
                    @inline(__always)
                    private static func _decodeNestedIfPresent<T: Embedded & Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> T? {
                        try container.decodeIfPresent(T.self, forKey: key)
                    }
                }

                extension StatusConfig: Encodable {
                }

                extension StatusConfig: Equatable {
                }

                extension StatusConfig: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    func testEmbeddedWithRequiredFieldAndDefault() {
        assertMacroExpansion(
            """
            @Embedded
            struct WithRequired {
                var required: String
                @Default("default")
                let optional: String
            }
            """,
            expandedSource: """
                struct WithRequired {
                    var required: String
                    let optional: String

                    public init(
                        required: String,
                        optional: String = "default"
                    ) {
                        self.required = required
                        self.optional = optional
                    }
                }

                extension WithRequired: Embedded {
                }

                extension WithRequired: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case required
                        case optional
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.required = try container.decode(String.self, forKey: .required)
                        do {
                            self.optional = try container.decode(String.self, forKey: .optional)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'WithRequired.optional': \\(error)")
                            self.optional = "default"
                        }
                    }

                }

                extension WithRequired: Encodable {
                }

                extension WithRequired: Equatable {
                }

                extension WithRequired: Hashable {
                }
                """,
            macros: testMacros
        )
    }
}
