import ProofForge.Backend.WasmHost.ModulePlan
import ProofForge.Backend.WasmHost.NearModulePlan.Core

namespace ProofForge.Backend.WasmHost.ModulePlan.Core

/-- Build the target-neutral Wasm-host plan. B1 enabled only NEAR; B3 adds
Soroban Counter MVP support. Both targets share the same key-value storage
layout model (scalars as UTF-8 keys, maps as prefixed keys), so the NEAR
layout builder is reused. The bridge discriminator distinguishes host imports
and lowering dispatch. CosmWasm and other bridges fail closed until promoted. -/
def buildFromCore (checked : ProofForge.IR.Canonical.CheckedCanonicalContract)
    (capPlan : ProofForge.Target.CapabilityPlan) :
    Except ProofForge.Backend.WasmHost.Plan.PlanError WasmHostModulePlan := do
  let hostBridge <- match bridgeForTarget capPlan.targetId with
    | .ok bridge => pure bridge
    | .error message => throw { message }
  match hostBridge.bridge with
  | .near =>
    let plan <- ProofForge.Backend.WasmHost.NearModulePlan.Core.buildFromCore checked capPlan
    pure { plan with hostBridge }
  | .soroban =>
    -- Soroban Counter MVP: reuse the NEAR layout builder (same key-value
    -- storage semantics) and set the Soroban bridge. EmitWat lowering for
    -- Soroban uses _put/_get host imports instead of storage_read/write.
    let nearCapPlan := { capPlan with targetId := "wasm-near" }
    let plan <- ProofForge.Backend.WasmHost.NearModulePlan.Core.buildFromCore checked nearCapPlan
    pure { plan with targetId := capPlan.targetId, hostBridge }
  | .cosmWasm =>
    throw { message := s!"Wasm-host canonical builder is not implemented for `{capPlan.targetId}`" }

end ProofForge.Backend.WasmHost.ModulePlan.Core
