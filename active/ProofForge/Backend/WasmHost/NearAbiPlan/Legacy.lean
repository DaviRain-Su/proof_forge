import ProofForge.Backend.WasmHost.NearAbiPlan
import ProofForge.Backend.WasmHost.StructPlan.Legacy
import ProofForge.IR.Contract

namespace ProofForge.Backend.WasmHost.NearAbiPlan

open ProofForge.IR

def buildJsonObjectSchemaFromIR (structs : Array StructDecl)
    (params : Array (String × ValueType)) : Except String JsonSchemaPlan :=
  buildJsonObjectSchema (structs.map StructPlan.Legacy.ofIR) params

def buildJsonValueSchemaFromIR (structs : Array StructDecl) (type : ValueType) :
    Except String JsonSchemaPlan :=
  buildJsonValueSchema (structs.map StructPlan.Legacy.ofIR) type

def buildEntrypointPlan (structs : Array StructDecl) (entrypoint : Entrypoint) :
    Except String EntrypointPlan :=
  buildSignaturePlan (structs.map StructPlan.Legacy.ofIR)
    entrypoint.name entrypoint.params entrypoint.returns

def buildModulePlans (module : Module) : Except String (Array EntrypointPlan) :=
  module.entrypoints.mapM (buildEntrypointPlan module.structs)

def validateEntrypointPlan (structs : Array StructDecl) (entrypoint : Entrypoint)
    (plan : EntrypointPlan) : Except String Unit := do
  let expected <- buildEntrypointPlan structs entrypoint
  if plan != expected then
    .error s!"NEAR ABI plan for entrypoint `{entrypoint.name}` does not match its signature"
  .ok ()

end ProofForge.Backend.WasmHost.NearAbiPlan
