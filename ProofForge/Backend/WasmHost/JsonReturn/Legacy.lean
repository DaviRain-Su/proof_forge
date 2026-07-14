import ProofForge.Backend.WasmHost.JsonReturn
import ProofForge.Backend.WasmHost.StructPlan.Legacy

namespace ProofForge.Backend.WasmHost.JsonReturn

open ProofForge.IR

def buildReturnFuncFromIR (entrypoint : String) (structs : Array StructDecl)
    (schema : AbiPlan.JsonSchemaPlan) (type : ValueType) :
    Except String ProofForge.Compiler.Wasm.Func :=
  buildReturnFunc entrypoint (structs.map StructPlan.Legacy.ofIR) schema type

end ProofForge.Backend.WasmHost.JsonReturn
