import SwiftSyntaxMacros
@testable import SwiftStoreMacroSupport

nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "Entity": EntityMacro.self,
    "Index": IndexMacro.self,
    "SyncKey": SyncKeyMacro.self,
    "Embedded": EmbeddedMacro.self,
    "Default": DefaultMacro.self,
]
