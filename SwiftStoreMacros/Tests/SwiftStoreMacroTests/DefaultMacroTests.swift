import Testing
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import SwiftStoreMacrosImpl

@Suite("Default Macro Tests")
struct DefaultMacroTests {

    // MARK: - Basic Struct Tests

    @Test("@Default generates CodingKeys, init(from:), memberwise init, and marker")
    func testBasicDefaultMacroExpansion() {
        assertMacroExpansion(
            """
            @Default
            struct Settings: Codable {
                var theme: String = "light"
                var fontSize: Int = 14
            }
            """,
            expandedSource: """
            struct Settings: Codable {
                var theme: String = "light"
                var fontSize: Int = 14

                private enum CodingKeys: String, CodingKey {
                    case theme
                    case fontSize
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? "light"
                    self.fontSize = try container.decodeIfPresent(Int.self, forKey: .fontSize) ?? 14
                }

                public init(theme: String = "light", fontSize: Int = 14) {
                    self.theme = theme
                    self.fontSize = fontSize
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension Settings: Default {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Required Field Tests

    @Test("@Default with required field (no default value)")
    func testDefaultWithRequiredField() {
        assertMacroExpansion(
            """
            @Default
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
                    self.theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? "light"
                }

                public init(userId: String, theme: String = "light") {
                    self.userId = userId
                    self.theme = theme
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension UserPrefs: Default {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Optional Field Tests

    @Test("@Default with optional field")
    func testDefaultWithOptionalField() {
        assertMacroExpansion(
            """
            @Default
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
                    self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "default"
                    self.description = try container.decodeIfPresent(String.self, forKey: .description)
                }

                public init(name: String = "default", description: String? = nil) {
                    self.name = name
                    self.description = description
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension Config: Default {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - All Primitive Types Tests

    @Test("@Default with all integer types")
    func testDefaultWithIntegerTypes() {
        assertMacroExpansion(
            """
            @Default
            struct IntegerTypes: Codable {
                var intValue: Int = 0
                var int8Value: Int8 = 8
                var int16Value: Int16 = 16
                var int32Value: Int32 = 32
                var int64Value: Int64 = 64
                var uintValue: UInt = 100
            }
            """,
            expandedSource: """
            struct IntegerTypes: Codable {
                var intValue: Int = 0
                var int8Value: Int8 = 8
                var int16Value: Int16 = 16
                var int32Value: Int32 = 32
                var int64Value: Int64 = 64
                var uintValue: UInt = 100

                private enum CodingKeys: String, CodingKey {
                    case intValue
                    case int8Value
                    case int16Value
                    case int32Value
                    case int64Value
                    case uintValue
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.intValue = try container.decodeIfPresent(Int.self, forKey: .intValue) ?? 0
                    self.int8Value = try container.decodeIfPresent(Int8.self, forKey: .int8Value) ?? 8
                    self.int16Value = try container.decodeIfPresent(Int16.self, forKey: .int16Value) ?? 16
                    self.int32Value = try container.decodeIfPresent(Int32.self, forKey: .int32Value) ?? 32
                    self.int64Value = try container.decodeIfPresent(Int64.self, forKey: .int64Value) ?? 64
                    self.uintValue = try container.decodeIfPresent(UInt.self, forKey: .uintValue) ?? 100
                }

                public init(intValue: Int = 0, int8Value: Int8 = 8, int16Value: Int16 = 16, int32Value: Int32 = 32, int64Value: Int64 = 64, uintValue: UInt = 100) {
                    self.intValue = intValue
                    self.int8Value = int8Value
                    self.int16Value = int16Value
                    self.int32Value = int32Value
                    self.int64Value = int64Value
                    self.uintValue = uintValue
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension IntegerTypes: Default {
            }
            """,
            macros: testMacros
        )
    }

    @Test("@Default with floating point and boolean types")
    func testDefaultWithFloatAndBoolTypes() {
        assertMacroExpansion(
            """
            @Default
            struct FloatBoolTypes: Codable {
                var doubleValue: Double = 3.14
                var floatValue: Float = 2.5
                var boolTrue: Bool = true
                var boolFalse: Bool = false
            }
            """,
            expandedSource: """
            struct FloatBoolTypes: Codable {
                var doubleValue: Double = 3.14
                var floatValue: Float = 2.5
                var boolTrue: Bool = true
                var boolFalse: Bool = false

                private enum CodingKeys: String, CodingKey {
                    case doubleValue
                    case floatValue
                    case boolTrue
                    case boolFalse
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.doubleValue = try container.decodeIfPresent(Double.self, forKey: .doubleValue) ?? 3.14
                    self.floatValue = try container.decodeIfPresent(Float.self, forKey: .floatValue) ?? 2.5
                    self.boolTrue = try container.decodeIfPresent(Bool.self, forKey: .boolTrue) ?? true
                    self.boolFalse = try container.decodeIfPresent(Bool.self, forKey: .boolFalse) ?? false
                }

                public init(doubleValue: Double = 3.14, floatValue: Float = 2.5, boolTrue: Bool = true, boolFalse: Bool = false) {
                    self.doubleValue = doubleValue
                    self.floatValue = floatValue
                    self.boolTrue = boolTrue
                    self.boolFalse = boolFalse
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension FloatBoolTypes: Default {
            }
            """,
            macros: testMacros
        )
    }

    @Test("@Default with string empty and non-empty defaults")
    func testDefaultWithStringDefaults() {
        assertMacroExpansion(
            """
            @Default
            struct StringTypes: Codable {
                var emptyString: String = ""
                var nonEmptyString: String = "hello"
            }
            """,
            expandedSource: """
            struct StringTypes: Codable {
                var emptyString: String = ""
                var nonEmptyString: String = "hello"

                private enum CodingKeys: String, CodingKey {
                    case emptyString
                    case nonEmptyString
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.emptyString = try container.decodeIfPresent(String.self, forKey: .emptyString) ?? ""
                    self.nonEmptyString = try container.decodeIfPresent(String.self, forKey: .nonEmptyString) ?? "hello"
                }

                public init(emptyString: String = "", nonEmptyString: String = "hello") {
                    self.emptyString = emptyString
                    self.nonEmptyString = nonEmptyString
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension StringTypes: Default {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Collection Types Tests

    @Test("@Default with empty array default")
    func testDefaultWithEmptyArrayDefault() {
        assertMacroExpansion(
            """
            @Default
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
                    self.emptyArray = try container.decodeIfPresent([String].self, forKey: .emptyArray) ?? [String]()
                    self.nonEmptyArray = try container.decodeIfPresent([Int].self, forKey: .nonEmptyArray) ?? [1, 2, 3]
                }

                public init(emptyArray: [String] = [], nonEmptyArray: [Int] = [1, 2, 3]) {
                    self.emptyArray = emptyArray
                    self.nonEmptyArray = nonEmptyArray
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension ArrayTypes: Default {
            }
            """,
            macros: testMacros
        )
    }

    @Test("@Default with dictionary defaults")
    func testDefaultWithDictionaryDefaults() {
        assertMacroExpansion(
            """
            @Default
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
                    self.emptyDict = try container.decodeIfPresent([String: Int].self, forKey: .emptyDict) ?? [:]
                    self.nonEmptyDict = try container.decodeIfPresent([String: String].self, forKey: .nonEmptyDict) ?? ["key": "value"]
                }

                public init(emptyDict: [String: Int] = [:], nonEmptyDict: [String: String] = ["key": "value"]) {
                    self.emptyDict = emptyDict
                    self.nonEmptyDict = nonEmptyDict
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension DictTypes: Default {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Nested Struct Tests

    @Test("@Default with nested struct default")
    func testDefaultWithNestedStructDefault() {
        assertMacroExpansion(
            """
            @Default
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
                    self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
                    self.nested = try container.decodeIfPresent(NestedType.self, forKey: .nested) ?? NestedType()
                }

                public init(name: String = "", nested: NestedType = NestedType()) {
                    self.name = name
                    self.nested = nested
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension Container: Default {
            }
            """,
            macros: testMacros
        )
    }

    @Test("@Default with optional nested struct")
    func testDefaultWithOptionalNestedStruct() {
        assertMacroExpansion(
            """
            @Default
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
                    self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
                    self.nested = try container.decodeIfPresent(NestedType.self, forKey: .nested)
                }

                public init(name: String = "", nested: NestedType? = nil) {
                    self.name = name
                    self.nested = nested
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension ContainerOptional: Default {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Enum Tests

    @Test("@Default on enum only generates marker")
    func testDefaultOnEnumGeneratesMarkerOnly() {
        assertMacroExpansion(
            """
            @Default
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

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension Status: Default {
            }
            """,
            macros: testMacros
        )
    }

    @Test("@Default on Int enum")
    func testDefaultOnIntEnum() {
        assertMacroExpansion(
            """
            @Default
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

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension Priority: Default {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Mixed Types Tests

    @Test("@Default with mixed types (primitives, optionals, collections, defaults)")
    func testDefaultWithMixedTypes() {
        assertMacroExpansion(
            """
            @Default
            struct MixedTypes: Codable {
                var required: String
                var withDefault: String = "default"
                var optional: String?
                var array: [Int] = []
                var dict: [String: Bool] = [:]
            }
            """,
            expandedSource: """
            struct MixedTypes: Codable {
                var required: String
                var withDefault: String = "default"
                var optional: String?
                var array: [Int] = []
                var dict: [String: Bool] = [:]

                private enum CodingKeys: String, CodingKey {
                    case required
                    case withDefault
                    case optional
                    case array
                    case dict
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.required = try container.decode(String.self, forKey: .required)
                    self.withDefault = try container.decodeIfPresent(String.self, forKey: .withDefault) ?? "default"
                    self.optional = try container.decodeIfPresent(String.self, forKey: .optional)
                    self.array = try container.decodeIfPresent([Int].self, forKey: .array) ?? [Int]()
                    self.dict = try container.decodeIfPresent([String: Bool].self, forKey: .dict) ?? [:]
                }

                public init(required: String, withDefault: String = "default", optional: String? = nil, array: [Int] = [], dict: [String: Bool] = [:]) {
                    self.required = required
                    self.withDefault = withDefault
                    self.optional = optional
                    self.array = array
                    self.dict = dict
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension MixedTypes: Default {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - All Optional Types Tests

    @Test("@Default with all optional types")
    func testDefaultWithAllOptionalTypes() {
        assertMacroExpansion(
            """
            @Default
            struct AllOptionals: Codable {
                var optString: String?
                var optInt: Int?
                var optBool: Bool?
                var optArray: [String]?
                var optDict: [String: Int]?
            }
            """,
            expandedSource: """
            struct AllOptionals: Codable {
                var optString: String?
                var optInt: Int?
                var optBool: Bool?
                var optArray: [String]?
                var optDict: [String: Int]?

                private enum CodingKeys: String, CodingKey {
                    case optString
                    case optInt
                    case optBool
                    case optArray
                    case optDict
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.optString = try container.decodeIfPresent(String.self, forKey: .optString)
                    self.optInt = try container.decodeIfPresent(Int.self, forKey: .optInt)
                    self.optBool = try container.decodeIfPresent(Bool.self, forKey: .optBool)
                    self.optArray = try container.decodeIfPresent([String].self, forKey: .optArray)
                    self.optDict = try container.decodeIfPresent([String: Int].self, forKey: .optDict)
                }

                public init(optString: String? = nil, optInt: Int? = nil, optBool: Bool? = nil, optArray: [String]? = nil, optDict: [String: Int]? = nil) {
                    self.optString = optString
                    self.optInt = optInt
                    self.optBool = optBool
                    self.optArray = optArray
                    self.optDict = optDict
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension AllOptionals: Default {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Complex Nested Tests

    @Test("@Default with array of nested structs")
    func testDefaultWithArrayOfNestedStructs() {
        assertMacroExpansion(
            """
            @Default
            struct WithNestedArray: Codable {
                var items: [NestedItem] = []
                var optionalItems: [NestedItem]?
            }
            """,
            expandedSource: """
            struct WithNestedArray: Codable {
                var items: [NestedItem] = []
                var optionalItems: [NestedItem]?

                private enum CodingKeys: String, CodingKey {
                    case items
                    case optionalItems
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.items = try container.decodeIfPresent([NestedItem].self, forKey: .items) ?? [NestedItem]()
                    self.optionalItems = try container.decodeIfPresent([NestedItem].self, forKey: .optionalItems)
                }

                public init(items: [NestedItem] = [], optionalItems: [NestedItem]? = nil) {
                    self.items = items
                    self.optionalItems = optionalItems
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension WithNestedArray: Default {
            }
            """,
            macros: testMacros
        )
    }

    @Test("@Default with enum default value")
    func testDefaultWithEnumDefaultValue() {
        assertMacroExpansion(
            """
            @Default
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
                    self.status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .active
                    self.optionalStatus = try container.decodeIfPresent(Status.self, forKey: .optionalStatus)
                }

                public init(status: Status = .active, optionalStatus: Status? = nil) {
                    self.status = status
                    self.optionalStatus = optionalStatus
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension WithEnumDefault: Default {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Array/Dict of Nested Types Tests

    @Test("@Default with array of nested structs with empty default")
    func testDefaultWithArrayOfNestedStructsEmpty() {
        assertMacroExpansion(
            """
            @Default
            struct WithNestedArrayEmpty: Codable {
                var addresses: [Address] = []
                var items: [Item] = []
            }
            """,
            expandedSource: """
            struct WithNestedArrayEmpty: Codable {
                var addresses: [Address] = []
                var items: [Item] = []

                private enum CodingKeys: String, CodingKey {
                    case addresses
                    case items
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.addresses = try container.decodeIfPresent([Address].self, forKey: .addresses) ?? [Address]()
                    self.items = try container.decodeIfPresent([Item].self, forKey: .items) ?? [Item]()
                }

                public init(addresses: [Address] = [], items: [Item] = []) {
                    self.addresses = addresses
                    self.items = items
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension WithNestedArrayEmpty: Default {
            }
            """,
            macros: testMacros
        )
    }

    @Test("@Default with array of nested structs with non-empty default")
    func testDefaultWithArrayOfNestedStructsNonEmpty() {
        assertMacroExpansion(
            """
            @Default
            struct WithNestedArrayNonEmpty: Codable {
                var addresses: [Address] = [Address()]
                var scores: [Score] = [Score(value: 0), Score(value: 100)]
            }
            """,
            expandedSource: """
            struct WithNestedArrayNonEmpty: Codable {
                var addresses: [Address] = [Address()]
                var scores: [Score] = [Score(value: 0), Score(value: 100)]

                private enum CodingKeys: String, CodingKey {
                    case addresses
                    case scores
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.addresses = try container.decodeIfPresent([Address].self, forKey: .addresses) ?? [Address()]
                    self.scores = try container.decodeIfPresent([Score].self, forKey: .scores) ?? [Score(value: 0), Score(value: 100)]
                }

                public init(addresses: [Address] = [Address()], scores: [Score] = [Score(value: 0), Score(value: 100)]) {
                    self.addresses = addresses
                    self.scores = scores
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension WithNestedArrayNonEmpty: Default {
            }
            """,
            macros: testMacros
        )
    }

    @Test("@Default with dictionary of nested structs with empty default")
    func testDefaultWithDictOfNestedStructsEmpty() {
        assertMacroExpansion(
            """
            @Default
            struct WithNestedDictEmpty: Codable {
                var addressBook: [String: Address] = [:]
                var itemMap: [String: Item] = [:]
            }
            """,
            expandedSource: """
            struct WithNestedDictEmpty: Codable {
                var addressBook: [String: Address] = [:]
                var itemMap: [String: Item] = [:]

                private enum CodingKeys: String, CodingKey {
                    case addressBook
                    case itemMap
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.addressBook = try container.decodeIfPresent([String: Address].self, forKey: .addressBook) ?? [:]
                    self.itemMap = try container.decodeIfPresent([String: Item].self, forKey: .itemMap) ?? [:]
                }

                public init(addressBook: [String: Address] = [:], itemMap: [String: Item] = [:]) {
                    self.addressBook = addressBook
                    self.itemMap = itemMap
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension WithNestedDictEmpty: Default {
            }
            """,
            macros: testMacros
        )
    }

    @Test("@Default with dictionary of nested structs with non-empty default")
    func testDefaultWithDictOfNestedStructsNonEmpty() {
        assertMacroExpansion(
            """
            @Default
            struct WithNestedDictNonEmpty: Codable {
                var addressBook: [String: Address] = ["home": Address()]
                var config: [String: Setting] = ["default": Setting(value: 0)]
            }
            """,
            expandedSource: """
            struct WithNestedDictNonEmpty: Codable {
                var addressBook: [String: Address] = ["home": Address()]
                var config: [String: Setting] = ["default": Setting(value: 0)]

                private enum CodingKeys: String, CodingKey {
                    case addressBook
                    case config
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.addressBook = try container.decodeIfPresent([String: Address].self, forKey: .addressBook) ?? ["home": Address()]
                    self.config = try container.decodeIfPresent([String: Setting].self, forKey: .config) ?? ["default": Setting(value: 0)]
                }

                public init(addressBook: [String: Address] = ["home": Address()], config: [String: Setting] = ["default": Setting(value: 0)]) {
                    self.addressBook = addressBook
                    self.config = config
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension WithNestedDictNonEmpty: Default {
            }
            """,
            macros: testMacros
        )
    }

    @Test("@Default with array of enum with empty default")
    func testDefaultWithArrayOfEnumEmpty() {
        assertMacroExpansion(
            """
            @Default
            struct WithEnumArrayEmpty: Codable {
                var statuses: [Status] = []
                var priorities: [Priority] = []
            }
            """,
            expandedSource: """
            struct WithEnumArrayEmpty: Codable {
                var statuses: [Status] = []
                var priorities: [Priority] = []

                private enum CodingKeys: String, CodingKey {
                    case statuses
                    case priorities
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.statuses = try container.decodeIfPresent([Status].self, forKey: .statuses) ?? [Status]()
                    self.priorities = try container.decodeIfPresent([Priority].self, forKey: .priorities) ?? [Priority]()
                }

                public init(statuses: [Status] = [], priorities: [Priority] = []) {
                    self.statuses = statuses
                    self.priorities = priorities
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension WithEnumArrayEmpty: Default {
            }
            """,
            macros: testMacros
        )
    }

    @Test("@Default with array of enum with non-empty default")
    func testDefaultWithArrayOfEnumNonEmpty() {
        assertMacroExpansion(
            """
            @Default
            struct WithEnumArrayNonEmpty: Codable {
                var statuses: [Status] = [.active, .pending]
                var priorities: [Priority] = [.high, .low]
            }
            """,
            expandedSource: """
            struct WithEnumArrayNonEmpty: Codable {
                var statuses: [Status] = [.active, .pending]
                var priorities: [Priority] = [.high, .low]

                private enum CodingKeys: String, CodingKey {
                    case statuses
                    case priorities
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.statuses = try container.decodeIfPresent([Status].self, forKey: .statuses) ?? [.active, .pending]
                    self.priorities = try container.decodeIfPresent([Priority].self, forKey: .priorities) ?? [.high, .low]
                }

                public init(statuses: [Status] = [.active, .pending], priorities: [Priority] = [.high, .low]) {
                    self.statuses = statuses
                    self.priorities = priorities
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension WithEnumArrayNonEmpty: Default {
            }
            """,
            macros: testMacros
        )
    }

    @Test("@Default with dict of enum values")
    func testDefaultWithDictOfEnumValues() {
        assertMacroExpansion(
            """
            @Default
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
                    self.statusMap = try container.decodeIfPresent([String: Status].self, forKey: .statusMap) ?? [:]
                    self.priorityMap = try container.decodeIfPresent([String: Priority].self, forKey: .priorityMap) ?? ["default": .medium]
                }

                public init(statusMap: [String: Status] = [:], priorityMap: [String: Priority] = ["default": .medium]) {
                    self.statusMap = statusMap
                    self.priorityMap = priorityMap
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension WithEnumDict: Default {
            }
            """,
            macros: testMacros
        )
    }

    @Test("@Default with optional array and dict of nested types")
    func testDefaultWithOptionalArrayAndDictOfNestedTypes() {
        assertMacroExpansion(
            """
            @Default
            struct WithOptionalCollections: Codable {
                var addresses: [Address]?
                var itemMap: [String: Item]?
                var statuses: [Status]?
            }
            """,
            expandedSource: """
            struct WithOptionalCollections: Codable {
                var addresses: [Address]?
                var itemMap: [String: Item]?
                var statuses: [Status]?

                private enum CodingKeys: String, CodingKey {
                    case addresses
                    case itemMap
                    case statuses
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.addresses = try container.decodeIfPresent([Address].self, forKey: .addresses)
                    self.itemMap = try container.decodeIfPresent([String: Item].self, forKey: .itemMap)
                    self.statuses = try container.decodeIfPresent([Status].self, forKey: .statuses)
                }

                public init(addresses: [Address]? = nil, itemMap: [String: Item]? = nil, statuses: [Status]? = nil) {
                    self.addresses = addresses
                    self.itemMap = itemMap
                    self.statuses = statuses
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension WithOptionalCollections: Default {
            }
            """,
            macros: testMacros
        )
    }

    @Test("@Default with Set types")
    func testDefaultWithSetTypes() {
        assertMacroExpansion(
            """
            @Default
            struct SetTypes: Codable {
                var emptySet: Set<String> = Set()
                var nonEmptySet: Set<Int> = [1, 2, 3]
            }
            """,
            expandedSource: """
            struct SetTypes: Codable {
                var emptySet: Set<String> = Set()
                var nonEmptySet: Set<Int> = [1, 2, 3]

                private enum CodingKeys: String, CodingKey {
                    case emptySet
                    case nonEmptySet
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.emptySet = try container.decodeIfPresent(Set<String>.self, forKey: .emptySet) ?? Set<String>()
                    self.nonEmptySet = try container.decodeIfPresent(Set<Int>.self, forKey: .nonEmptySet) ?? [1, 2, 3]
                }

                public init(emptySet: Set<String> = Set(), nonEmptySet: Set<Int> = [1, 2, 3]) {
                    self.emptySet = emptySet
                    self.nonEmptySet = nonEmptySet
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker { _makeDefaultMacroMarker() }
            }

            extension SetTypes: Default {
            }
            """,
            macros: testMacros
        )
    }
}
