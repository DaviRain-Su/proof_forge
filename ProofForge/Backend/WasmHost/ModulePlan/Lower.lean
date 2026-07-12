import ProofForge.Backend.WasmHost.ModulePlan
import ProofForge.Backend.WasmHost.NearModulePlan

namespace ProofForge.Backend.WasmHost.ModulePlan

/-- Lower a neutral Wasm-host plan through its selected host adapter.
NEAR lowering is fully canonical (plan-driven). Soroban Counter MVP plan
building is supported, but canonical lowering is deferred — the canonical
storage helpers (Scalar.readFuncNear etc.) hard-code NEAR host calls
(storage_read/storage_write) and need bridge-aware variants. CLI artifact
emission uses EmitWat.lowerModule which already handles the .soroban bridge
correctly. CosmWasm still fails closed. -/
def lowerFromPlan (plan : WasmHostModulePlan) :
    Except ProofForge.Backend.WasmHost.Diagnostics.EmitError ProofForge.Compiler.Wasm.Module := do
  unless plan.hostBridge.targetId == plan.targetId do
    ProofForge.Backend.WasmHost.Diagnostics.err "Wasm-host plan target and bridge target disagree"
  match plan.hostBridge.bridge with
  | .near => ProofForge.Backend.WasmHost.NearModulePlan.lowerFromPlan plan
  | .soroban => ProofForge.Backend.WasmHost.Diagnostics.err "Soroban canonical lowering is deferred (storage helpers hard-code NEAR host calls; CLI uses EmitWat.lowerModule with .soroban bridge)"
  | .cosmWasm => ProofForge.Backend.WasmHost.Diagnostics.err "CosmWasm plan lowering is not implemented"

end ProofForge.Backend.WasmHost.ModulePlan
