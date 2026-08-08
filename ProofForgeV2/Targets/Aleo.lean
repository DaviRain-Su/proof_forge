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
# ProofForgeV2.Targets.Aleo — public façade

Capability-gated Aleo target leaf. **ALEO-IR-6 product authority** =
**Aleo Instructions** register IR (not long-term sole Leo 4 source).

Port of the hackathon/aleo-2026-08 lane onto the current product spine:
consumes retained `SemanticProgramV1` via the `ResolvedEngineeringBuildV1`
capability exactly like EVM/Solana/NEAR/Noir. No V1-direct second semantic
path: the target-owned Plan/IR are built from the same structure-valid
semantic carrier consumed by the other implemented targets.

Official pipeline: Leo source → **Aleo Instructions** → AVM. ProofForge
product materialize primary is Plan→Instructions text (`{id}.aleo`) when
lower succeeds; transitional Leo 4 source is debug/compare-only
(`PROOF_FORGE_ALEO_EMIT_LEO=1` / `emitLeoDebug`, or compile-profile dual-write).

Leo 4.0.2 execution model (verified by the hackathon spike + devnet runs;
still used by residual Leo path + debug dual-write + compile compare):
  * mappings are the only state; mapping reads/writes are legal only in
    finalization context, so state-touching callables materialize as
    Final / finalize blocks (Leo printer) or Instructions `function` +
    `finalize` (primary path).
  * `Final` / finalize cannot return a value: a non-Unit entry whose body
    touches state records `resultDropped` (explicit Plan metadata, never a
    silent omission); the value is observable post-transaction via
    network-state query. Each dropped return expression is still evaluated
    so failure semantics (halt on panic = revert) are preserved.
  * native u64 arithmetic is checked (halt on overflow — spike-verified);
    `div`/`mod` by zero and `assert(false)` halt the transaction, which
    reverts atomically (no state change) — the DSL revert analogue.

Honest fail-closed decisions (documented, SPEC-TARGET-ALEO-001 + AleoCoverage):
  * `emit` — no on-chain event log → fail closed (`ALEO-IR-5:`).
  * `externalCall` / `schedule` — no address-bearing type / workflow model
    → fail closed (resolver declines both requirement keys).
  * `revert` with error args — the payload cannot be represented →
    fail closed; bare `revert` lowers to `assert.eq true false` / `assert(false)`.
  * `trap` lowers to halt assert.
  * **Field (bn254 Fr)** — Aleo native `field` is BLS12-377 Fr (Edwards BLS
    scalar), **not** catalog bn254 Fr → fail closed (PsyFelt-style pin).
  * **named aggregates / Array/Map/Bytes/Option** — Plan is scalar mapping
    leaves; multi-leaf flatten is admitted; nested Map residual FC.
  * **ContextRead** — no host clock ABI → fail closed; **Commit** is
    label-only identity passthrough (same N5 policy as EVM/Solana/NEAR).
  * views: bare public-state reads materialize as off-chain query
    descriptors; computed state-reading views fail closed.
  * G5-HARD: Int64 / Field BLS12-377 / pureFn inline lower to Instructions;
    residual allowlist empty — Instructions lower failure is
    `ALEO-IR-G5-HARD` (no silent Leo-only primary).

Plan types and Semantic→Plan lowering live in `LowerSemanticV1`
(`materializePlanFromCapabilityV1` → private `makePlanFromSemanticV1`).
Plan canonicity lives in `ValidatePlanV1`. Product emit + optional Leo
dual-write live in `EmitIRV1`; Instructions lower in
`Instructions/LowerPlanV1`. `FinalizeV1` remains a separate submodule.
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
