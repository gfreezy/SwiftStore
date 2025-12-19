import SwiftSyntaxMacros
@testable import SwiftStoreMacros

nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "Entity": EntityMacro.self,
    "Index": IndexMacro.self,
    "OneToOne": OneToOneMacro.self,
    "OneToMany": OneToManyMacro.self,
    "ManyToOne": ManyToOneMacro.self,
    "ManyToMany": ManyToManyMacro.self,
    "RawValue": RawValueMacro.self,
]
