import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Aleo.LowerSemanticV1
import ProofForgeV2.Targets.Aleo.ValidatePlanV1
import ProofForgeV2.Targets.Aleo.PlanSchemaV1
import ProofForgeV2.Targets.Aleo.EmitIRV1
import ProofForgeV2.Targets.Aleo.Instructions.SchemaV1
import ProofForgeV2.Targets.Aleo.Instructions.TextCodecV1
import ProofForgeV2.Targets.Aleo.Instructions.LowerPlanV1

/-!
# ProofForgeV2.Targets.Aleo

Capability-gated Aleo target leaf. The sole product path is retained
`SemanticProgramV1` → target-owned Plan → Aleo Instructions IR → canonical
`{id}.aleo` plus the network-state query descriptor. No alternate source,
compiler, dual-write, or target-language fallback exists.
-/

namespace ProofForgeV2.Targets.Aleo

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.DescriptorDataV1

/-- Capability-gated public Plan entry (Aleo target leaf). Support is already
    decided by the capability; the Plan body consumes only retained
    SemanticProgramV1, never residual alpha.
    Authority chain: semanticV1Of → makePlanFromSemanticV1 → validatePlan
    (validateSemanticProgramV1 already ran at capability mint). -/
def planFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  return plan

instance : Materializer .aleo where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.Aleo
