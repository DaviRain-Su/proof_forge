import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Icp.LowerSemanticV1
import ProofForgeV2.Targets.Icp.ValidatePlanV1
import ProofForgeV2.Targets.Icp.PlanSchemaV1
import ProofForgeV2.Targets.Icp.EmitIRV1

/-!
# ProofForgeV2.Targets.Icp — public façade

Capability-gated Counter/StateCell-narrow ICP target leaf (ICP-2, ADR-0047).

Consumes retained `SemanticProgramV1` via `ResolvedEngineeringBuildV1` exactly
like Quint/Aleo/Psy/Noir. Plan types and Semantic→Plan lowering live in
`LowerSemanticV1`; plan canonicity in `ValidatePlanV1`; structured IR + `.wat`
+ `.did` emission in `EmitIRV1`; wat2wasm finalization in `FinalizeV1`
(PocketIC remains a separate host-optional runtime lane).

ICP-2 envelope: public UInt64 **or** public Int64 state (homogeneous
numeric domain: every integer state/param/result is UInt64, or every
one is Int64; mixing fails closed); Array UInt64 N or Array Int64 N∈1..8
state flattens to N i64 Wasm globals (element follows signedNumeric; no
Candid `vec`); Option UInt64 2-leaf and named Struct/Enum flatten to extra
i64 globals (no Candid `opt`/`record`/`variant`); Map stays fail closed;
`init`/entry(mutate)/view;
single-block callable bodies; checked `+`/`-`/`*`/`/`/`%` and comparisons
(literal/param/stateLoad/store/return; Bool results). View-only Array
UInt64 N / Option UInt64 / named Struct·Enum returns flatten to a Candid
positional tuple `(nat64, …)` (consecutive LE i64 reply; no `record`/`opt`/`vec`).
`Op.ContextRead` admits only `context.unixTimeSeconds`.
Everything else — pureFn, invariants, events, errors, emit,
sync call, schedule, residual ContextRead keys, `Op.Commit`, Map,
entry aggregate return, Principal/Bytes return, Int8/16/32, UInt8/16/128/256,
Field — fails closed. ICP-1's async advertisement (`effect.asynchronous-workflow`)
stays a resolver-level advertisement only; no ICP-2 Plan shape realizes
it.
-/

namespace ProofForgeV2.Targets.Icp

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.DescriptorDataV1

/-- Shared descriptor data (wired by main-agent DescriptorDataV1.icp). -/
def descriptor : TargetDescriptor := DescriptorDataV1.icp

/-- Capability-gated public Plan entry (ICP target leaf).
    Authority chain: semanticV1Of → makePlanFromSemanticV1 → validatePlan
    (validateSemanticProgramV1 already ran at capability mint). -/
def planFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  return plan

instance : Materializer .icp where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.Icp
