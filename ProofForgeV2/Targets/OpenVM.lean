import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.OpenVM.LowerSemanticV1
import ProofForgeV2.Targets.OpenVM.ValidatePlanV1
import ProofForgeV2.Targets.OpenVM.PlanSchemaV1
import ProofForgeV2.Targets.OpenVM.EmitIRV1

/-!
# ProofForgeV2.Targets.OpenVM — public façade

Capability-gated source-only OpenVM guest-source target leaf (O0, ADR-0045).

Consumes retained `SemanticProgramV1` via `ResolvedEngineeringBuildV1` exactly
like Aleo/Psy/Quint. Plan types and Semantic→Plan lowering live in
`LowerSemanticV1`; plan canonicity in `ValidatePlanV1`; structured Rust guest
IR + `.rs`/`.toml`/`.json` emission in `EmitIRV1`; zero-tool finalization in
`FinalizeV1`.

O0 envelope: anonymous UInt64/Int64/Bool/Unit; public homogeneous UInt64
**or** Int64 state/params (mixing fail closed); public Unit/UInt64/Int64/Bool
results; anonymous `Array UInt64 N` or `Array Int64 N` (N=1..8) **state**
flatten to N guest `u64`/`i64` fields `{name}_0`..`{name}_{N-1}` (element
follows signedNumeric; no `[u64; N]` / Vec); anonymous `Option UInt64` or
`Option Int64` **state** flatten to two guest `u64`/`i64` fields
`{name}_tag` + `{name}_p0` (tag 0=none / 1=some; none zeros payload;
payload follows signedNumeric; no Rust `Option`); anonymous
`Map UInt64 UInt64` or `Map Int64 Int64` **state** flatten to 24 guest
`u64`/`i64` fields `{name}_0`..`{name}_{23}` (cap-8 × occ/key/val;
`Map.empty` + IndexSet upsert; IndexGet → Option tag+payload via `ite`;
no `HashMap` / `std::collections` / Vec); single-block callables; pureFn
inline (depth ≤ 64); checked `+`/`-`/`*`/`/`/`%` (signed uses Rust
`i64::checked_*`); bare assert; zero-payload declared revert; empty
events/constants; no call/schedule/ContextRead/Commit/Bytes/nested
Array/Array-or-Option-or-Map param-return/narrow-Int/invariants/Principal/
pf.assets. Mixed UInt64↔Int64 containers, N∉1..8, and container
return/params stay fail closed.
Everything else fails closed. Zero-tool finalize — no guest
build/transpile/keygen/execute/prove/verify.
-/

namespace ProofForgeV2.Targets.OpenVM

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.DescriptorDataV1

/-- Shared descriptor data (wired by main-agent DescriptorDataV1.openvm). -/
def descriptor : TargetDescriptor := DescriptorDataV1.openvm

/-- Capability-gated public Plan entry (OpenVM target leaf).
    Authority chain: semanticV1Of → makePlanFromSemanticV1 → validatePlan
    (validateSemanticProgramV1 already ran at capability mint). -/
def planFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  return plan

instance : Materializer .openvm where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.OpenVM
