import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiftStoreMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        EntityMacro.self,
        IndexMacro.self,
        OneToOneMacro.self,
        OneToManyMacro.self,
        ManyToOneMacro.self,
        ManyToManyMacro.self,
        RawValueMacro.self,
    ]
}
