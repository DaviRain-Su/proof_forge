import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Soroban.LowerSemanticV1
import ProofForgeV2.Targets.Soroban.ValidatePlanV1
import ProofForgeV2.Targets.Soroban.PlanSchemaV1
import ProofForgeV2.Targets.Soroban.EmitIRV1

/-!
# ProofForgeV2.Targets.Soroban — public façade

Capability-gated source-only Soroban S0 target leaf.

Consumes retained `SemanticProgramV1` via `ResolvedEngineeringBuildV1`
exactly like Quint/Aleo/Psy/Noir. Plan types and Semantic→Plan lowering live in
`LowerSemanticV1`; plan canonicity in `ValidatePlanV1`; structured IR +
`.rs` emission in `EmitIRV1`; zero-tool finalization in `FinalizeV1`.

S0 envelope: public homogeneous UInt64 or Int64 state/params;
Unit/UInt64/Int64/Bool results; single-block callables; pureFn inline
(depth ≤ 64); Array UInt64 N∈1..8 **state** flattens to N instance
`u64` `symbol_short!` keys; Option UInt64 **state** flattens to
`{name}_tag`/`{name}_p0`; Map UInt64 UInt64 **state** flattens to
24 instance keys `{name}_0`..`{name}_23` (cap-8 × occ/key/val).
No invariants/constants/events/call/schedule. Mixing UInt64/Int64,
Int8/16/32, Bytes, Array/Option/Map return/params, nonempty Map
construct, and `symbol_short!` keys longer than 9 bytes fail closed.
-/

namespace ProofForgeV2.Targets.Soroban

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.DescriptorDataV1

def descriptor : TargetDescriptor := DescriptorDataV1.soroban

def planFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  return plan

instance : Materializer .soroban where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.Soroban
