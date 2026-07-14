import ProofForge.Backend.WasmHost.ModulePlan
import ProofForge.Backend.WasmHost.NearModulePlan

namespace ProofForge.Backend.WasmHost.ModulePlan

/-- Lower a neutral Wasm-host plan through its selected host adapter.
The bridge is taken from the plan's hostBridge. Scalar, map, and import
helpers are bridge-aware; the canonical lowering produces correct Wasm for
any bridge that shares the NEAR key-value storage model. Hash/crosscall/
promise/context helpers are still NEAR-only and produce empty arrays for
contracts that don't use those features. CosmWasm fails closed. -/
def lowerFromPlan (plan : WasmHostModulePlan) :
    Except ProofForge.Backend.WasmHost.Diagnostics.EmitError ProofForge.Compiler.Wasm.Module := do
  unless plan.hostBridge.targetId == plan.targetId do
    ProofForge.Backend.WasmHost.Diagnostics.err "Wasm-host plan target and bridge target disagree"
  match plan.hostBridge.bridge with
  | .near => ProofForge.Backend.WasmHost.NearModulePlan.lowerFromPlan plan
  | .soroban =>
    -- Soroban shares the NEAR key-value storage model; the bridge controls
    -- import selection (_get/_put) and scalar helper dispatch.
    ProofForge.Backend.WasmHost.NearModulePlan.lowerFromPlan
      { plan with targetId := "wasm-near" }
  | .cosmWasm => ProofForge.Backend.WasmHost.Diagnostics.err "CosmWasm plan lowering is not implemented"

end ProofForge.Backend.WasmHost.ModulePlan
