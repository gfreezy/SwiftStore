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
            struct Settings: Codable {
                var theme: String = "light"
                var fontSize: Int = 14
                var n: CGFloat
            }
            """,
            expandedSource:
                """
                struct Settings: Codable {
                    var theme: String = "light"
                    var fontSize: Int = 14
                    var n: CGFloat

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
                            os_log(.error, "SwiftStore: Failed to decode 'Settings.theme': %{public}@", String(describing: error))
                            self.theme = "light"
                        }
                        do {
                            self.fontSize = try container.decode(Int.self, forKey: .fontSize)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'Settings.fontSize': %{public}@", String(describing: error))
                            self.fontSize = 14
                        }
                        self.n = try container.decode(CGFloat.self, forKey: .n)
                    }

                    public init(
                        theme: String = "light",
                        fontSize: Int = 14,
                        n: CGFloat
                    ) {
                        self.theme = theme
                        self.fontSize = fontSize
                        self.n = n
                    }
                }
                
                extension Settings: Embedded {
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
            struct UserPrefs: Codable {
                var userId: String
                var theme: String = "light"
            }
            """,
            expandedSource: """
                struct UserPrefs: Codable {
                    var userId: String
                    var theme: String = "light"

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
                            os_log(.error, "SwiftStore: Failed to decode 'UserPrefs.theme': %{public}@", String(describing: error))
                            self.theme = "light"
                        }
                    }

                    public init(
                        userId: String,
                        theme: String = "light"
                    ) {
                        self.userId = userId
                        self.theme = theme
                    }
                }

                extension UserPrefs: Embedded {
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
            struct Config: Codable {
                var name: String = "default"
                var description: String?
            }
            """,
            expandedSource: """
                struct Config: Codable {
                    var name: String = "default"
                    var description: String?

                    private enum CodingKeys: String, CodingKey {
                        case name
                        case description
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.name = try container.decode(String.self, forKey: .name)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'Config.name': %{public}@", String(describing: error))
                            self.name = "default"
                        }
                        self.description = try container.decodeIfPresent(String.self, forKey: .description)
                    }

                    public init(
                        name: String = "default",
                        description: String?
                    ) {
                        self.name = name
                        self.description = description
                    }
                }

                extension Config: Embedded {
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
            struct ArrayTypes: Codable {
                var emptyArray: [String] = []
                var nonEmptyArray: [Int] = [1, 2, 3]
            }
            """,
            expandedSource: """
                struct ArrayTypes: Codable {
                    var emptyArray: [String] = []
                    var nonEmptyArray: [Int] = [1, 2, 3]

                    private enum CodingKeys: String, CodingKey {
                        case emptyArray
                        case nonEmptyArray
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.emptyArray = try container.decode([String].self, forKey: .emptyArray)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'ArrayTypes.emptyArray': %{public}@", String(describing: error))
                            self.emptyArray = []
                        }
                        do {
                            self.nonEmptyArray = try container.decode([Int].self, forKey: .nonEmptyArray)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'ArrayTypes.nonEmptyArray': %{public}@", String(describing: error))
                            self.nonEmptyArray = [1, 2, 3]
                        }
                    }

                    public init(
                        emptyArray: [String] = [],
                        nonEmptyArray: [Int] = [1, 2, 3]
                    ) {
                        self.emptyArray = emptyArray
                        self.nonEmptyArray = nonEmptyArray
                    }
                }

                extension ArrayTypes: Embedded {
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
            struct DictTypes: Codable {
                var emptyDict: [String: Int] = [:]
                var nonEmptyDict: [String: String] = ["key": "value"]
            }
            """,
            expandedSource: """
                struct DictTypes: Codable {
                    var emptyDict: [String: Int] = [:]
                    var nonEmptyDict: [String: String] = ["key": "value"]

                    private enum CodingKeys: String, CodingKey {
                        case emptyDict
                        case nonEmptyDict
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.emptyDict = try container.decode([String: Int].self, forKey: .emptyDict)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'DictTypes.emptyDict': %{public}@", String(describing: error))
                            self.emptyDict = [:]
                        }
                        do {
                            self.nonEmptyDict = try container.decode([String: String].self, forKey: .nonEmptyDict)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'DictTypes.nonEmptyDict': %{public}@", String(describing: error))
                            self.nonEmptyDict = ["key": "value"]
                        }
                    }

                    public init(
                        emptyDict: [String: Int] = [:],
                        nonEmptyDict: [String: String] = ["key": "value"]
                    ) {
                        self.emptyDict = emptyDict
                        self.nonEmptyDict = nonEmptyDict
                    }
                }

                extension DictTypes: Embedded {
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
            struct Container: Codable {
                var name: String = ""
                var nested: NestedType = NestedType()
            }
            """,
            expandedSource: """
                struct Container: Codable {
                    var name: String = ""
                    var nested: NestedType = NestedType()

                    private enum CodingKeys: String, CodingKey {
                        case name
                        case nested
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.name = try container.decode(String.self, forKey: .name)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'Container.name': %{public}@", String(describing: error))
                            self.name = ""
                        }
                        do {
                            self.nested = try Self._decodeNested(NestedType.self, from: container, forKey: .nested)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'Container.nested': %{public}@", String(describing: error))
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

                    public init(
                        name: String = "",
                        nested: NestedType = NestedType()
                    ) {
                        self.name = name
                        self.nested = nested
                    }
                }

                extension Container: Embedded {
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
            struct ContainerOptional: Codable {
                var name: String = ""
                var nested: NestedType?
            }
            """,
            expandedSource: """
                struct ContainerOptional: Codable {
                    var name: String = ""
                    var nested: NestedType?

                    private enum CodingKeys: String, CodingKey {
                        case name
                        case nested
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.name = try container.decode(String.self, forKey: .name)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'ContainerOptional.name': %{public}@", String(describing: error))
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

                    public init(
                        name: String = "",
                        nested: NestedType?
                    ) {
                        self.name = name
                        self.nested = nested
                    }
                }

                extension ContainerOptional: Embedded {
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
            enum Status: String, Codable {
                case active
                case inactive
                case pending
            }
            """,
            expandedSource: """
                enum Status: String, Codable {
                    case active
                    case inactive
                    case pending
                }

                extension Status: Embedded {
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
            enum Priority: Int, Codable {
                case low = 0
                case medium = 1
                case high = 2
            }
            """,
            expandedSource: """
                enum Priority: Int, Codable {
                    case low = 0
                    case medium = 1
                    case high = 2
                }

                extension Priority: Embedded {
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
            struct MixedTypes: Codable {
                var required: String
                var withDefault: String = "default"
                var optional: String? = "hello"
                var array: [Int] = []
            }
            """,
            expandedSource: """
                struct MixedTypes: Codable {
                    var required: String
                    var withDefault: String = "default"
                    var optional: String? = "hello"
                    var array: [Int] = []

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
                            os_log(.error, "SwiftStore: Failed to decode 'MixedTypes.withDefault': %{public}@", String(describing: error))
                            self.withDefault = "default"
                        }
                        do {
                            self.optional = try container.decodeIfPresent(String.self, forKey: .optional)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'MixedTypes.optional': %{public}@", String(describing: error))
                            self.optional = "hello"
                        }
                        do {
                            self.array = try container.decode([Int].self, forKey: .array)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'MixedTypes.array': %{public}@", String(describing: error))
                            self.array = []
                        }
                    }

                    public init(
                        required: String,
                        withDefault: String = "default",
                        optional: String? = "hello",
                        array: [Int] = []
                    ) {
                        self.required = required
                        self.withDefault = withDefault
                        self.optional = optional
                        self.array = array
                    }
                }

                extension MixedTypes: Embedded {
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
            struct AllOptionals: Codable {
                var optString: String?
                var optInt: Int?
                var optBool: Bool?
            }
            """,
            expandedSource: """
                struct AllOptionals: Codable {
                    var optString: String?
                    var optInt: Int?
                    var optBool: Bool?

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

                    public init(
                        optString: String?,
                        optInt: Int?,
                        optBool: Bool?
                    ) {
                        self.optString = optString
                        self.optInt = optInt
                        self.optBool = optBool
                    }
                }

                extension AllOptionals: Embedded {
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
            struct WithEnumDefault: Codable {
                var status: Status = .active
                var optionalStatus: Status?
            }
            """,
            expandedSource: """
                struct WithEnumDefault: Codable {
                    var status: Status = .active
                    var optionalStatus: Status?

                    private enum CodingKeys: String, CodingKey {
                        case status
                        case optionalStatus
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.status = try Self._decodeNested(Status.self, from: container, forKey: .status)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'WithEnumDefault.status': %{public}@", String(describing: error))
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

                    public init(
                        status: Status = .active,
                        optionalStatus: Status?
                    ) {
                        self.status = status
                        self.optionalStatus = optionalStatus
                    }
                }

                extension WithEnumDefault: Embedded {
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
            struct WithNestedArrayEmpty: Codable {
                var addresses: [Address] = []
            }
            """,
            expandedSource: """
                struct WithNestedArrayEmpty: Codable {
                    var addresses: [Address] = []

                    private enum CodingKeys: String, CodingKey {
                        case addresses
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.addresses = try container.decode([Address].self, forKey: .addresses)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'WithNestedArrayEmpty.addresses': %{public}@", String(describing: error))
                            self.addresses = []
                        }
                    }

                    public init(
                        addresses: [Address] = []
                    ) {
                        self.addresses = addresses
                    }
                }

                extension WithNestedArrayEmpty: Embedded {
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
            struct WithNestedArrayNonEmpty: Codable {
                var addresses: [Address] = [Address()]
            }
            """,
            expandedSource: """
                struct WithNestedArrayNonEmpty: Codable {
                    var addresses: [Address] = [Address()]

                    private enum CodingKeys: String, CodingKey {
                        case addresses
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.addresses = try container.decode([Address].self, forKey: .addresses)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'WithNestedArrayNonEmpty.addresses': %{public}@", String(describing: error))
                            self.addresses = [Address()]
                        }
                    }

                    public init(
                        addresses: [Address] = [Address()]
                    ) {
                        self.addresses = addresses
                    }
                }

                extension WithNestedArrayNonEmpty: Embedded {
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
            struct WithNestedDictEmpty: Codable {
                var addressBook: [String: Address] = [:]
            }
            """,
            expandedSource: """
                struct WithNestedDictEmpty: Codable {
                    var addressBook: [String: Address] = [:]

                    private enum CodingKeys: String, CodingKey {
                        case addressBook
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.addressBook = try container.decode([String: Address].self, forKey: .addressBook)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'WithNestedDictEmpty.addressBook': %{public}@", String(describing: error))
                            self.addressBook = [:]
                        }
                    }

                    public init(
                        addressBook: [String: Address] = [:]
                    ) {
                        self.addressBook = addressBook
                    }
                }

                extension WithNestedDictEmpty: Embedded {
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
            struct WithNestedDictNonEmpty: Codable {
                var addressBook: [String: Address] = ["home": Address()]
            }
            """,
            expandedSource: """
                struct WithNestedDictNonEmpty: Codable {
                    var addressBook: [String: Address] = ["home": Address()]

                    private enum CodingKeys: String, CodingKey {
                        case addressBook
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.addressBook = try container.decode([String: Address].self, forKey: .addressBook)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'WithNestedDictNonEmpty.addressBook': %{public}@", String(describing: error))
                            self.addressBook = ["home": Address()]
                        }
                    }

                    public init(
                        addressBook: [String: Address] = ["home": Address()]
                    ) {
                        self.addressBook = addressBook
                    }
                }

                extension WithNestedDictNonEmpty: Embedded {
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
            struct WithEnumArrayEmpty: Codable {
                var statuses: [Status] = []
            }
            """,
            expandedSource: """
                struct WithEnumArrayEmpty: Codable {
                    var statuses: [Status] = []

                    private enum CodingKeys: String, CodingKey {
                        case statuses
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.statuses = try container.decode([Status].self, forKey: .statuses)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'WithEnumArrayEmpty.statuses': %{public}@", String(describing: error))
                            self.statuses = []
                        }
                    }

                    public init(
                        statuses: [Status] = []
                    ) {
                        self.statuses = statuses
                    }
                }

                extension WithEnumArrayEmpty: Embedded {
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
            struct WithEnumArrayNonEmpty: Codable {
                var statuses: [Status] = [.active, .pending]
            }
            """,
            expandedSource: """
                struct WithEnumArrayNonEmpty: Codable {
                    var statuses: [Status] = [.active, .pending]

                    private enum CodingKeys: String, CodingKey {
                        case statuses
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.statuses = try container.decode([Status].self, forKey: .statuses)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'WithEnumArrayNonEmpty.statuses': %{public}@", String(describing: error))
                            self.statuses = [.active, .pending]
                        }
                    }

                    public init(
                        statuses: [Status] = [.active, .pending]
                    ) {
                        self.statuses = statuses
                    }
                }

                extension WithEnumArrayNonEmpty: Embedded {
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
            struct WithEnumDict: Codable {
                var statusMap: [String: Status] = [:]
                var priorityMap: [String: Priority] = ["default": .medium]
            }
            """,
            expandedSource: """
                struct WithEnumDict: Codable {
                    var statusMap: [String: Status] = [:]
                    var priorityMap: [String: Priority] = ["default": .medium]

                    private enum CodingKeys: String, CodingKey {
                        case statusMap
                        case priorityMap
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.statusMap = try container.decode([String: Status].self, forKey: .statusMap)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'WithEnumDict.statusMap': %{public}@", String(describing: error))
                            self.statusMap = [:]
                        }
                        do {
                            self.priorityMap = try container.decode([String: Priority].self, forKey: .priorityMap)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'WithEnumDict.priorityMap': %{public}@", String(describing: error))
                            self.priorityMap = ["default": .medium]
                        }
                    }

                    public init(
                        statusMap: [String: Status] = [:],
                        priorityMap: [String: Priority] = ["default": .medium]
                    ) {
                        self.statusMap = statusMap
                        self.priorityMap = priorityMap
                    }
                }

                extension WithEnumDict: Embedded {
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
            struct WithOptionalCollections: Codable {
                var addresses: [Address]?
                var itemMap: [String: Item]?
            }
            """,
            expandedSource: """
                struct WithOptionalCollections: Codable {
                    var addresses: [Address]?
                    var itemMap: [String: Item]?

                    private enum CodingKeys: String, CodingKey {
                        case addresses
                        case itemMap
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.addresses = try container.decodeIfPresent([Address].self, forKey: .addresses)
                        self.itemMap = try container.decodeIfPresent([String: Item].self, forKey: .itemMap)
                    }

                    public init(
                        addresses: [Address]?,
                        itemMap: [String: Item]?
                    ) {
                        self.addresses = addresses
                        self.itemMap = itemMap
                    }
                }

                extension WithOptionalCollections: Embedded {
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
            struct IntegerTypes: Codable {
                var intValue: Int = 0
                var int64Value: Int64 = 64
            }
            """,
            expandedSource: """
                struct IntegerTypes: Codable {
                    var intValue: Int = 0
                    var int64Value: Int64 = 64

                    private enum CodingKeys: String, CodingKey {
                        case intValue
                        case int64Value
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.intValue = try container.decode(Int.self, forKey: .intValue)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'IntegerTypes.intValue': %{public}@", String(describing: error))
                            self.intValue = 0
                        }
                        do {
                            self.int64Value = try container.decode(Int64.self, forKey: .int64Value)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'IntegerTypes.int64Value': %{public}@", String(describing: error))
                            self.int64Value = 64
                        }
                    }

                    public init(
                        intValue: Int = 0,
                        int64Value: Int64 = 64
                    ) {
                        self.intValue = intValue
                        self.int64Value = int64Value
                    }
                }

                extension IntegerTypes: Embedded {
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
            struct FloatBoolTypes: Codable {
                var doubleValue: Double = 3.14
                var boolTrue: Bool = true
            }
            """,
            expandedSource: """
                struct FloatBoolTypes: Codable {
                    var doubleValue: Double = 3.14
                    var boolTrue: Bool = true

                    private enum CodingKeys: String, CodingKey {
                        case doubleValue
                        case boolTrue
                    }

                    public init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        do {
                            self.doubleValue = try container.decode(Double.self, forKey: .doubleValue)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'FloatBoolTypes.doubleValue': %{public}@", String(describing: error))
                            self.doubleValue = 3.14
                        }
                        do {
                            self.boolTrue = try container.decode(Bool.self, forKey: .boolTrue)
                        } catch {
                            os_log(.error, "SwiftStore: Failed to decode 'FloatBoolTypes.boolTrue': %{public}@", String(describing: error))
                            self.boolTrue = true
                        }
                    }

                    public init(
                        doubleValue: Double = 3.14,
                        boolTrue: Bool = true
                    ) {
                        self.doubleValue = doubleValue
                        self.boolTrue = boolTrue
                    }
                }

                extension FloatBoolTypes: Embedded {
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
