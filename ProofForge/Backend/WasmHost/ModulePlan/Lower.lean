import ProofForge.Backend.WasmHost.ModulePlan
import ProofForge.Backend.WasmHost.NearModulePlan

namespace ProofForge.Backend.WasmHost.ModulePlan

/-- Lower a neutral Wasm-host plan through its selected host adapter. B1 keeps
only the established NEAR adapter executable; other bridges fail closed. -/
def lowerFromPlan (plan : WasmHostModulePlan) :
    Except ProofForge.Backend.WasmHost.Diagnostics.EmitError ProofForge.Compiler.Wasm.Module := do
  unless plan.hostBridge.targetId == plan.targetId do
    ProofForge.Backend.WasmHost.Diagnostics.err "Wasm-host plan target and bridge target disagree"
  match plan.hostBridge.bridge with
  | .near => ProofForge.Backend.WasmHost.NearModulePlan.lowerFromPlan plan
  | .soroban => ProofForge.Backend.WasmHost.Diagnostics.err "Soroban plan lowering is not implemented (B3)"
  | .cosmWasm => ProofForge.Backend.WasmHost.Diagnostics.err "CosmWasm plan lowering is not implemented"

end ProofForge.Backend.WasmHost.ModulePlan
