import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiftStoreMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        EntityMacro.self,
        IndexMacro.self,
        SyncKeyMacro.self,
        EmbeddedMacro.self,
        DefaultMacro.self,
    ]
}
