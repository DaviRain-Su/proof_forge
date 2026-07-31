import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Aleo.LowerSemanticV1
import ProofForgeV2.Targets.Aleo.ValidatePlanV1
import ProofForgeV2.Targets.Aleo.EmitIRV1

/-!
# ProofForgeV2.Targets.Aleo — public façade

Capability-gated Aleo (Leo 4.0.2) target leaf.

Port of the hackathon/aleo-2026-08 lane onto the current product spine:
consumes retained `SemanticProgramV1` via the `ResolvedEngineeringBuildV1`
capability exactly like EVM/Solana/NEAR/Noir. No V1-direct second semantic
path: the target-owned Plan/IR are built from the same structure-valid
semantic carrier the other four targets consume.

Leo 4.0.2 execution model (verified by the hackathon spike + devnet runs):
  * mappings are the only state; mapping reads/writes are legal only in
    finalization context, so state-touching callables materialize as
    `fn ... -> Final { return final { ... } }`
  * `Final` functions cannot return a value: a non-Unit entry whose body
    touches state records `resultDropped` (explicit Plan metadata, never a
    silent omission); the value is observable post-transaction via
    `leo query`. Each dropped return expression is still evaluated inside
    the final block so its failure semantics (halt on panic = revert) are
    preserved.
  * native u64 arithmetic is checked (halt on overflow — spike-verified);
    `div`/`mod` by zero and `assert(false)` halt the transaction, which
    reverts atomically (no state change) — the DSL revert analogue.

Honest fail-closed decisions (documented, SPEC-TARGET-ALEO-001):
  * `emit` — Leo 4.0.2 has no on-chain event log → fail closed.
  * `revert` with error args — the payload cannot be represented →
    fail closed; bare `revert` lowers to `assert(false)` (halt = revert).
  * `trap` lowers to `assert(false)` (unreachable halt).
  * views: bare public-state reads materialize as off-chain query
    descriptors (`leo query` — the EVM `eth_call` analogue); computed
    state-reading views fail closed; pure computed views are plain fns.
  * shift counts: UInt32 wire values render as u64 with an explicit
    `assert(count < 64u64)` guard (invalidShift); result overflow relies
    on Leo native checked shift semantics (the Noir precedent).
  * u32 count arithmetic is promoted to u64 (the documented four-target
    superset: a u32 overflow can only reach the count guard and reverts
    there).
  * bounded `for`: Leo loops need constant bounds, so the loop lowers to
    `for c in 0u64..N { if c < (end - start) { body } }` guarded by
    `if start < end { assert(end - start <= N) }` (boundExceeded halts
    before any body runs; observably identical to the reference's
    N-bodies-then-revert since a halt discards all provisional state).

Plan types and Semantic→Plan lowering live in `LowerSemanticV1`
(`materializePlanFromCapabilityV1` → private `makePlanFromSemanticV1`).
Plan canonicity lives in `ValidatePlanV1`. Leo IR emission and
`irFromCapability`/`buildFromCapability` live in `EmitIRV1`.
`FinalizeV1` remains a separate submodule.
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
