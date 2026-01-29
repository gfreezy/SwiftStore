import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import SwiftStoreMacrosImpl

final class EmbeddedMacroTests: XCTestCase {

    // MARK: - Basic Struct Tests

    func testBasicEmbeddedMacroExpansion() {
        assertMacroExpansion(
            """
            @Embedded
            struct Settings {
                var theme: String = "light"
                var fontSize: Int = 14
                var n: CGFloat
            }
            """,
            expandedSource:
                """
                struct Settings {
                    var theme: String = "light"
                    var fontSize: Int = 14
                    var n: CGFloat
                }

                extension Settings: Embedded {
                }

                extension Settings: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case theme
                        case fontSize
                        case n
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.theme = try container.decode(String.self, forKey: .theme)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'Settings.theme': \\(error)")
                            self.theme = "light"
                        }
                        do {
                            self.fontSize = try container.decode(Int.self, forKey: .fontSize)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'Settings.fontSize': \\(error)")
                            self.fontSize = 14
                        }
                        self.n = try container.decode(CGFloat.self, forKey: .n)
                    }

                }

                extension Settings: Encodable {
                }

                extension Settings: Equatable {
                }

                extension Settings: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    // MARK: - Required Field Tests

    func testDefaultWithRequiredField() {
        assertMacroExpansion(
            """
            @Embedded
            struct UserPrefs {
                var userId: String
                var theme: String = "light"
            }
            """,
            expandedSource: """
                struct UserPrefs {
                    var userId: String
                    var theme: String = "light"
                }

                extension UserPrefs: Embedded {
                }

                extension UserPrefs: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case userId
                        case theme
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.userId = try container.decode(String.self, forKey: .userId)
                        do {
                            self.theme = try container.decode(String.self, forKey: .theme)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'UserPrefs.theme': \\(error)")
                            self.theme = "light"
                        }
                    }

                }

                extension UserPrefs: Encodable {
                }

                extension UserPrefs: Equatable {
                }

                extension UserPrefs: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    // MARK: - Optional Field Tests

    func testDefaultWithOptionalField() {
        assertMacroExpansion(
            """
            @Embedded
            struct Config {
                var name: String = "default"
                var description: String?
            }
            """,
            expandedSource: """
                struct Config {
                    var name: String = "default"
                    var description: String?
                }

                extension Config: Embedded {
                }

                extension Config: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case name
                        case description
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.name = try container.decode(String.self, forKey: .name)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'Config.name': \\(error)")
                            self.name = "default"
                        }
                        self.description = try container.decodeIfPresent(String.self, forKey: .description)
                    }

                }

                extension Config: Encodable {
                }

                extension Config: Equatable {
                }

                extension Config: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    // MARK: - Collection Types Tests

    func testDefaultWithEmptyArrayDefault() {
        assertMacroExpansion(
            """
            @Embedded
            struct ArrayTypes {
                var emptyArray: [String] = []
                var nonEmptyArray: [Int] = [1, 2, 3]
            }
            """,
            expandedSource: """
                struct ArrayTypes {
                    var emptyArray: [String] = []
                    var nonEmptyArray: [Int] = [1, 2, 3]
                }

                extension ArrayTypes: Embedded {
                }

                extension ArrayTypes: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case emptyArray
                        case nonEmptyArray
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.emptyArray = try container.decode([String].self, forKey: .emptyArray)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'ArrayTypes.emptyArray': \\(error)")
                            self.emptyArray = []
                        }
                        do {
                            self.nonEmptyArray = try container.decode([Int].self, forKey: .nonEmptyArray)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'ArrayTypes.nonEmptyArray': \\(error)")
                            self.nonEmptyArray = [1, 2, 3]
                        }
                    }

                }

                extension ArrayTypes: Encodable {
                }

                extension ArrayTypes: Equatable {
                }

                extension ArrayTypes: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    func testDefaultWithDictionaryDefaults() {
        assertMacroExpansion(
            """
            @Embedded
            struct DictTypes {
                var emptyDict: [String: Int] = [:]
                var nonEmptyDict: [String: String] = ["key": "value"]
            }
            """,
            expandedSource: """
                struct DictTypes {
                    var emptyDict: [String: Int] = [:]
                    var nonEmptyDict: [String: String] = ["key": "value"]
                }

                extension DictTypes: Embedded {
                }

                extension DictTypes: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case emptyDict
                        case nonEmptyDict
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.emptyDict = try container.decode([String: Int].self, forKey: .emptyDict)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'DictTypes.emptyDict': \\(error)")
                            self.emptyDict = [:]
                        }
                        do {
                            self.nonEmptyDict = try container.decode([String: String].self, forKey: .nonEmptyDict)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'DictTypes.nonEmptyDict': \\(error)")
                            self.nonEmptyDict = ["key": "value"]
                        }
                    }

                }

                extension DictTypes: Encodable {
                }

                extension DictTypes: Equatable {
                }

                extension DictTypes: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    // MARK: - Nested Struct Tests

    func testDefaultWithNestedStructDefault() {
        assertMacroExpansion(
            """
            @Embedded
            struct Container {
                var name: String = ""
                var nested: NestedType = NestedType()
            }
            """,
            expandedSource: """
                struct Container {
                    var name: String = ""
                    var nested: NestedType = NestedType()
                }

                extension Container: Embedded {
                }

                extension Container: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case name
                        case nested
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.name = try container.decode(String.self, forKey: .name)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'Container.name': \\(error)")
                            self.name = ""
                        }
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

    func testDefaultWithOptionalNestedStruct() {
        assertMacroExpansion(
            """
            @Embedded
            struct ContainerOptional {
                var name: String = ""
                var nested: NestedType?
            }
            """,
            expandedSource: """
                struct ContainerOptional {
                    var name: String = ""
                    var nested: NestedType?
                }

                extension ContainerOptional: Embedded {
                }

                extension ContainerOptional: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case name
                        case nested
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.name = try container.decode(String.self, forKey: .name)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'ContainerOptional.name': \\(error)")
                            self.name = ""
                        }
                        self.nested = try Self._decodeNestedIfPresent(NestedType.self, from: container, forKey: .nested)
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

                extension ContainerOptional: Encodable {
                }

                extension ContainerOptional: Equatable {
                }

                extension ContainerOptional: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    // MARK: - Enum Tests

    func testDefaultOnEnumGeneratesMarkerOnly() {
        assertMacroExpansion(
            """
            @Embedded
            enum Status: String {
                case active
                case inactive
                case pending
            }
            """,
            expandedSource: """
                enum Status: String {
                    case active
                    case inactive
                    case pending
                }

                extension Status: Embedded {
                }

                extension Status: Codable {
                }

                extension Status: Equatable {
                }

                extension Status: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    func testDefaultOnIntEnum() {
        assertMacroExpansion(
            """
            @Embedded
            enum Priority: Int {
                case low = 0
                case medium = 1
                case high = 2
            }
            """,
            expandedSource: """
                enum Priority: Int {
                    case low = 0
                    case medium = 1
                    case high = 2
                }

                extension Priority: Embedded {
                }

                extension Priority: Codable {
                }

                extension Priority: Equatable {
                }

                extension Priority: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    // MARK: - Mixed Types Tests

        func testDefaultWithMixedTypes() {
        assertMacroExpansion(
            """
            @Embedded
            struct MixedTypes {
                var required: String
                var withDefault: String = "default"
                var optional: String? = "hello"
                var array: [Int] = []
            }
            """,
            expandedSource: """
                struct MixedTypes {
                    var required: String
                    var withDefault: String = "default"
                    var optional: String? = "hello"
                    var array: [Int] = []
                }

                extension MixedTypes: Embedded {
                }

                extension MixedTypes: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case required
                        case withDefault
                        case optional
                        case array
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.required = try container.decode(String.self, forKey: .required)
                        do {
                            self.withDefault = try container.decode(String.self, forKey: .withDefault)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'MixedTypes.withDefault': \\(error)")
                            self.withDefault = "default"
                        }
                        do {
                            self.optional = try container.decodeIfPresent(String.self, forKey: .optional)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'MixedTypes.optional': \\(error)")
                            self.optional = "hello"
                        }
                        do {
                            self.array = try container.decode([Int].self, forKey: .array)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'MixedTypes.array': \\(error)")
                            self.array = []
                        }
                    }

                }

                extension MixedTypes: Encodable {
                }

                extension MixedTypes: Equatable {
                }

                extension MixedTypes: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    // MARK: - All Optional Types Tests

    func testDefaultWithAllOptionalTypes() {
        assertMacroExpansion(
            """
            @Embedded
            struct AllOptionals {
                var optString: String?
                var optInt: Int?
                var optBool: Bool?
            }
            """,
            expandedSource: """
                struct AllOptionals {
                    var optString: String?
                    var optInt: Int?
                    var optBool: Bool?
                }

                extension AllOptionals: Embedded {
                }

                extension AllOptionals: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case optString
                        case optInt
                        case optBool
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.optString = try container.decodeIfPresent(String.self, forKey: .optString)
                        self.optInt = try container.decodeIfPresent(Int.self, forKey: .optInt)
                        self.optBool = try container.decodeIfPresent(Bool.self, forKey: .optBool)
                    }

                }

                extension AllOptionals: Encodable {
                }

                extension AllOptionals: Equatable {
                }

                extension AllOptionals: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    // MARK: - Enum Default Value Tests

    func testDefaultWithEnumDefaultValue() {
        assertMacroExpansion(
            """
            @Embedded
            struct WithEnumDefault {
                var status: Status = .active
                var optionalStatus: Status?
            }
            """,
            expandedSource: """
                struct WithEnumDefault {
                    var status: Status = .active
                    var optionalStatus: Status?
                }

                extension WithEnumDefault: Embedded {
                }

                extension WithEnumDefault: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case status
                        case optionalStatus
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.status = try Self._decodeNested(Status.self, from: container, forKey: .status)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'WithEnumDefault.status': \\(error)")
                            self.status = .active
                        }
                        self.optionalStatus = try Self._decodeNestedIfPresent(Status.self, from: container, forKey: .optionalStatus)
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

                extension WithEnumDefault: Encodable {
                }

                extension WithEnumDefault: Equatable {
                }

                extension WithEnumDefault: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    // MARK: - Array of Nested Types Tests

    func testDefaultWithArrayOfNestedStructsEmpty() {
        assertMacroExpansion(
            """
            @Embedded
            struct WithNestedArrayEmpty {
                var addresses: [Address] = []
            }
            """,
            expandedSource: """
                struct WithNestedArrayEmpty {
                    var addresses: [Address] = []
                }

                extension WithNestedArrayEmpty: Embedded {
                }

                extension WithNestedArrayEmpty: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case addresses
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.addresses = try Self._decodeNested([Address].self, from: container, forKey: .addresses)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'WithNestedArrayEmpty.addresses': \\(error)")
                            self.addresses = []
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

                extension WithNestedArrayEmpty: Encodable {
                }

                extension WithNestedArrayEmpty: Equatable {
                }

                extension WithNestedArrayEmpty: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    func testDefaultWithArrayOfNestedStructsNonEmpty() {
        assertMacroExpansion(
            """
            @Embedded
            struct WithNestedArrayNonEmpty {
                var addresses: [Address] = [Address()]
            }
            """,
            expandedSource: """
                struct WithNestedArrayNonEmpty {
                    var addresses: [Address] = [Address()]
                }

                extension WithNestedArrayNonEmpty: Embedded {
                }

                extension WithNestedArrayNonEmpty: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case addresses
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.addresses = try Self._decodeNested([Address].self, from: container, forKey: .addresses)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'WithNestedArrayNonEmpty.addresses': \\(error)")
                            self.addresses = [Address()]
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

                extension WithNestedArrayNonEmpty: Encodable {
                }

                extension WithNestedArrayNonEmpty: Equatable {
                }

                extension WithNestedArrayNonEmpty: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    // MARK: - Dict of Nested Types Tests

    func testDefaultWithDictOfNestedStructsEmpty() {
        assertMacroExpansion(
            """
            @Embedded
            struct WithNestedDictEmpty {
                var addressBook: [String: Address] = [:]
            }
            """,
            expandedSource: """
                struct WithNestedDictEmpty {
                    var addressBook: [String: Address] = [:]
                }

                extension WithNestedDictEmpty: Embedded {
                }

                extension WithNestedDictEmpty: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case addressBook
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.addressBook = try Self._decodeNested([String: Address].self, from: container, forKey: .addressBook)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'WithNestedDictEmpty.addressBook': \\(error)")
                            self.addressBook = [:]
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

                extension WithNestedDictEmpty: Encodable {
                }

                extension WithNestedDictEmpty: Equatable {
                }

                extension WithNestedDictEmpty: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    func testDefaultWithDictOfNestedStructsNonEmpty() {
        assertMacroExpansion(
            """
            @Embedded
            struct WithNestedDictNonEmpty {
                var addressBook: [String: Address] = ["home": Address()]
            }
            """,
            expandedSource: """
                struct WithNestedDictNonEmpty {
                    var addressBook: [String: Address] = ["home": Address()]
                }

                extension WithNestedDictNonEmpty: Embedded {
                }

                extension WithNestedDictNonEmpty: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case addressBook
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.addressBook = try Self._decodeNested([String: Address].self, from: container, forKey: .addressBook)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'WithNestedDictNonEmpty.addressBook': \\(error)")
                            self.addressBook = ["home": Address()]
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

                extension WithNestedDictNonEmpty: Encodable {
                }

                extension WithNestedDictNonEmpty: Equatable {
                }

                extension WithNestedDictNonEmpty: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    // MARK: - Array of Enum Tests

    func testDefaultWithArrayOfEnumEmpty() {
        assertMacroExpansion(
            """
            @Embedded
            struct WithEnumArrayEmpty {
                var statuses: [Status] = []
            }
            """,
            expandedSource: """
                struct WithEnumArrayEmpty {
                    var statuses: [Status] = []
                }

                extension WithEnumArrayEmpty: Embedded {
                }

                extension WithEnumArrayEmpty: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case statuses
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.statuses = try Self._decodeNested([Status].self, from: container, forKey: .statuses)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'WithEnumArrayEmpty.statuses': \\(error)")
                            self.statuses = []
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

                extension WithEnumArrayEmpty: Encodable {
                }

                extension WithEnumArrayEmpty: Equatable {
                }

                extension WithEnumArrayEmpty: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    func testDefaultWithArrayOfEnumNonEmpty() {
        assertMacroExpansion(
            """
            @Embedded
            struct WithEnumArrayNonEmpty {
                var statuses: [Status] = [.active, .pending]
            }
            """,
            expandedSource: """
                struct WithEnumArrayNonEmpty {
                    var statuses: [Status] = [.active, .pending]
                }

                extension WithEnumArrayNonEmpty: Embedded {
                }

                extension WithEnumArrayNonEmpty: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case statuses
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.statuses = try Self._decodeNested([Status].self, from: container, forKey: .statuses)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'WithEnumArrayNonEmpty.statuses': \\(error)")
                            self.statuses = [.active, .pending]
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

                extension WithEnumArrayNonEmpty: Encodable {
                }

                extension WithEnumArrayNonEmpty: Equatable {
                }

                extension WithEnumArrayNonEmpty: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    // MARK: - Dict of Enum Values Tests

    func testDefaultWithDictOfEnumValues() {
        assertMacroExpansion(
            """
            @Embedded
            struct WithEnumDict {
                var statusMap: [String: Status] = [:]
                var priorityMap: [String: Priority] = ["default": .medium]
            }
            """,
            expandedSource: """
                struct WithEnumDict {
                    var statusMap: [String: Status] = [:]
                    var priorityMap: [String: Priority] = ["default": .medium]
                }

                extension WithEnumDict: Embedded {
                }

                extension WithEnumDict: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case statusMap
                        case priorityMap
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.statusMap = try Self._decodeNested([String: Status].self, from: container, forKey: .statusMap)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'WithEnumDict.statusMap': \\(error)")
                            self.statusMap = [:]
                        }
                        do {
                            self.priorityMap = try Self._decodeNested([String: Priority].self, from: container, forKey: .priorityMap)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'WithEnumDict.priorityMap': \\(error)")
                            self.priorityMap = ["default": .medium]
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

                extension WithEnumDict: Encodable {
                }

                extension WithEnumDict: Equatable {
                }

                extension WithEnumDict: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    // MARK: - Optional Collection of Nested Types Tests

    func testDefaultWithOptionalArrayAndDictOfNestedTypes() {
        assertMacroExpansion(
            """
            @Embedded
            struct WithOptionalCollections {
                var addresses: [Address]?
                var itemMap: [String: Item]?
            }
            """,
            expandedSource: """
                struct WithOptionalCollections {
                    var addresses: [Address]?
                    var itemMap: [String: Item]?
                }

                extension WithOptionalCollections: Embedded {
                }

                extension WithOptionalCollections: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case addresses
                        case itemMap
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.addresses = try Self._decodeNestedIfPresent([Address].self, from: container, forKey: .addresses)
                        self.itemMap = try Self._decodeNestedIfPresent([String: Item].self, from: container, forKey: .itemMap)
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

                extension WithOptionalCollections: Encodable {
                }

                extension WithOptionalCollections: Equatable {
                }

                extension WithOptionalCollections: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    // MARK: - Integer Types Tests

    func testDefaultWithIntegerTypes() {
        assertMacroExpansion(
            """
            @Embedded
            struct IntegerTypes {
                var intValue: Int = 0
                var int64Value: Int64 = 64
            }
            """,
            expandedSource: """
                struct IntegerTypes {
                    var intValue: Int = 0
                    var int64Value: Int64 = 64
                }

                extension IntegerTypes: Embedded {
                }

                extension IntegerTypes: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case intValue
                        case int64Value
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.intValue = try container.decode(Int.self, forKey: .intValue)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'IntegerTypes.intValue': \\(error)")
                            self.intValue = 0
                        }
                        do {
                            self.int64Value = try container.decode(Int64.self, forKey: .int64Value)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'IntegerTypes.int64Value': \\(error)")
                            self.int64Value = 64
                        }
                    }

                }

                extension IntegerTypes: Encodable {
                }

                extension IntegerTypes: Equatable {
                }

                extension IntegerTypes: Hashable {
                }
                """,
            macros: testMacros
        )
    }

    // MARK: - Float and Bool Types Tests

    func testDefaultWithFloatAndBoolTypes() {
        assertMacroExpansion(
            """
            @Embedded
            struct FloatBoolTypes {
                var doubleValue: Double = 3.14
                var boolTrue: Bool = true
            }
            """,
            expandedSource: """
                struct FloatBoolTypes {
                    var doubleValue: Double = 3.14
                    var boolTrue: Bool = true
                }

                extension FloatBoolTypes: Embedded {
                }

                extension FloatBoolTypes: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case doubleValue
                        case boolTrue
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.doubleValue = try container.decode(Double.self, forKey: .doubleValue)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'FloatBoolTypes.doubleValue': \\(error)")
                            self.doubleValue = 3.14
                        }
                        do {
                            self.boolTrue = try container.decode(Bool.self, forKey: .boolTrue)
                        } catch {
                            SwiftStoreLogger.error("Failed to decode 'FloatBoolTypes.boolTrue': \\(error)")
                            self.boolTrue = true
                        }
                    }

                }

                extension FloatBoolTypes: Encodable {
                }

                extension FloatBoolTypes: Equatable {
                }

                extension FloatBoolTypes: Hashable {
                }
                """,
            macros: testMacros
        )
    }
}
