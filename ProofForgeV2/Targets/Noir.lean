import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Noir.LowerSemanticV1
import ProofForgeV2.Targets.Noir.ValidatePlanV1
import ProofForgeV2.Targets.Noir.PlanSchemaV1
import ProofForgeV2.Targets.Noir.EmitIRV1
import ProofForgeV2.Targets.Noir.Acir.InventoryV1

/-!
# ProofForgeV2.Targets.Noir — public façade

Plan types and Semantic→Plan lowering live in `LowerSemanticV1`
(`materializePlanFromCapabilityV1` → private `makePlanFromSemanticV1`, with
`semanticV1Of` / `validateSemanticProgramV1` comments on the carrier path).
Plan canonicity lives in `ValidatePlanV1`. IR emission and
`irFromCapability`/`buildFromCapability` live in `EmitIRV1`.
`FinalizeV1` remains a separate submodule.
-/

namespace ProofForgeV2.Targets.Noir

open ProofForgeV2
open ProofForgeV2.Compiler

/-- Capability-gated public plan entry. Plan semantics and identity are both derived from the retained-semantic carrier.
    Authority chain: semanticV1Of → makePlanFromSemanticV1 → validatePlan
    (validateSemanticProgramV1 already ran at capability mint). -/
def planFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  return plan

instance : Materializer .noir where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.Noir
