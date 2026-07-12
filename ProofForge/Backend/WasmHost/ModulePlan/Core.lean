import ProofForge.Backend.WasmHost.ModulePlan
import ProofForge.Backend.WasmHost.NearModulePlan.Core

namespace ProofForge.Backend.WasmHost.ModulePlan.Core

/-- Build the target-neutral Wasm-host plan. B1 intentionally enables only
NEAR; later target promotion must provide its own strict builder. -/
def buildFromCore (checked : ProofForge.IR.Canonical.CheckedCanonicalContract)
    (capPlan : ProofForge.Target.CapabilityPlan) :
    Except ProofForge.Backend.WasmHost.Plan.PlanError WasmHostModulePlan := do
  let hostBridge <- match bridgeForTarget capPlan.targetId with
    | .ok bridge => pure bridge
    | .error message => throw { message }
  unless hostBridge.bridge == .near do
    throw { message := s!"Wasm-host canonical builder is not implemented for `{capPlan.targetId}`" }
  let plan <- ProofForge.Backend.WasmHost.NearModulePlan.Core.buildFromCore checked capPlan
  pure { plan with hostBridge }

end ProofForge.Backend.WasmHost.ModulePlan.Core
