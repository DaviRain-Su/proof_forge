import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Quint.LowerSemanticV1
import ProofForgeV2.Targets.Quint.ValidatePlanV1
import ProofForgeV2.Targets.Quint.PlanSchemaV1
import ProofForgeV2.Targets.Quint.EmitIRV1

/-!
# ProofForgeV2.Targets.Quint — public façade

Capability-gated source-only Quint 0.32 target leaf (Q0).

Consumes retained `SemanticProgramV1` via `ResolvedEngineeringBuildV1`
exactly like Aleo/Psy/Noir. Plan types and Semantic→Plan lowering live in
`LowerSemanticV1`; plan canonicity in `ValidatePlanV1`; structured IR +
`.qnt` emission in `EmitIRV1`; zero-tool finalization in `FinalizeV1`.

Q0 envelope: public homogeneous UInt64 **or** Int64 state/params
(mixing fail closed); Unit/UInt64/Int64/Bool results; `Array UInt64 N` or
`Array Int64 N` (N=1..8) state flattens to N leaves (element follows
signedNumeric; no native List); `Option UInt64` or `Option Int64` state
flattens to `{name}_tag`/`{name}_p0` (payload follows signedNumeric);
`Map UInt64 UInt64` or `Map Int64 Int64` state flattens to 24 occ/key/val
leaves (cap-8); single-block callables; pureFn inline (depth ≤ 64);
zero-param Bool invariants; empty constants/events and zero-payload
declared errors only. Everything else fails closed.
-/

namespace ProofForgeV2.Targets.Quint

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.DescriptorDataV1

/-- Shared descriptor data (wired by main-agent DescriptorDataV1.quint). -/
def descriptor : TargetDescriptor := DescriptorDataV1.quint

/-- Capability-gated public Plan entry (Quint target leaf).
    Authority chain: semanticV1Of → makePlanFromSemanticV1 → validatePlan
    (validateSemanticProgramV1 already ran at capability mint). -/
def planFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  return plan

instance : Materializer .quint where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.Quint
