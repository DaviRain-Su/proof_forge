import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Psy.LowerSemanticV1
import ProofForgeV2.Targets.Psy.ValidatePlanV1
import ProofForgeV2.Targets.Psy.EmitIRV1
import ProofForgeV2.Targets.Psy.Dpn.SchemaV1
import ProofForgeV2.Targets.Psy.Dpn.JsonCodecV1
import ProofForgeV2.Targets.Psy.Dpn.LowerPlanV1

/-!
# ProofForgeV2.Targets.Psy

Capability-gated Psy target leaf. The sole product path is retained
`SemanticProgramV1` → target-owned Plan → versioned DPN IR/package JSON.
There is no Psy source AST, renderer, compiler lane, or source fallback.
Product finalization is zero-tool and remains non-deployable.
-/

namespace ProofForgeV2.Targets.Psy

open ProofForgeV2.Targets.DescriptorDataV1

/-- Shared descriptor data (single source: DescriptorDataV1). -/
def descriptor : TargetDescriptor := DescriptorDataV1.psy

open ProofForgeV2
open ProofForgeV2.Compiler

/-- Capability-gated public Plan entry (Psy target leaf). Support is already
    decided by the capability; the Plan body consumes only retained
    SemanticProgramV1. Authority chain: semanticV1Of → makePlanFromSemanticV1
    → validatePlan. -/
def planFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  return plan

instance : Materializer .psy where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.Psy
