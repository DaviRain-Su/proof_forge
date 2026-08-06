/-
  ProofForgeV2.Targets.Solana.MaterializationV1 — #125 + ADR-0032 U1.

  Transitional tagged sum over single-account Plan/IR ("legacy" shim) and
  product CPI carriers, with exhaustive profile dispatch for
  `planFromCapability` / `irFromCapability`.

  **ADR-0032 direction (U1):** sole product rail is `solana-sbpf-cpi-elf-v1`.
  Full Semantic body surface is being absorbed into that rail (product IR/emit).
  `solana-sbpf-plan-v1` / `solana-sbpf-elf-v1` are temporary single-account shims
  — do not add new body capability only on the shim. New arith (sub/mul/div/mod)
  already lands on product body (P2 first cut).

  Product core sole authority (`CpiProductV1` / `CpiDeriveV1` / product IR):
    productPlanFromCapabilityV1  → SolanaCpiProductPlanV1
    productIrFromCapabilityV1    → ResolvedSolanaCpiProductIRV1
    productPlanDigestFromCapabilityV1
    productBaseFilesFromCapabilityV1
  This module never re-implements CPI Plan/IR/emitter core.

  Single TargetKind `.solana` / single Materializer instance: no second
  dispatch key. Unknown profiles fail closed (no silent else fallback).
  ExternalCall/Schedule remain unreachable on single-account shim.
-/
import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Targets.Solana.LowerSemanticV1
import ProofForgeV2.Targets.Solana.ValidatePlanV1
import ProofForgeV2.Targets.Solana.PlanSchemaV1
import ProofForgeV2.Targets.Solana.EmitIRV1
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiEscrowIRV1
import ProofForgeV2.Targets.Solana.CpiProductCapabilityV1
import ProofForgeV2.Targets.Solana.CpiProductV1

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Targets.Solana.CpiV1

/-! ## Tagged materialization carriers (single TargetKind / Materializer) -/

/-- Capability-gated Solana Plan carrier: legacy typed Plan or product CPI Plan.
    Materializer `.solana` Plan type. Design alias: `SolanaMaterializationPlanV1`. -/
inductive SolanaPlanFromCapabilityV1 where
  | legacy (plan : Plan)
  | cpi (plan : SolanaCpiProductPlanV1)

/-- Capability-gated Solana IR carrier: legacy typed IR or product CPI IR.
    Materializer `.solana` TargetIR type. Design alias: `SolanaMaterializationIRV1`. -/
inductive SolanaIRFromCapabilityV1 where
  | legacy (ir : IR)
  | cpi (ir : ResolvedSolanaCpiProductIRV1)

/-- Design-name alias for the materializer Plan tagged sum. -/
abbrev SolanaMaterializationPlanV1 := SolanaPlanFromCapabilityV1

/-- Design-name alias for the materializer IR tagged sum. -/
abbrev SolanaMaterializationIRV1 := SolanaIRFromCapabilityV1

private def unknownProfileFail (profile : CodegenProfileId) : CompileResult α :=
  throw <| .planInvariant .solana
    s!"unknown Solana codegen profile '{profile}' (exhaustive plan/elf/cpi only)"

/-- Capability-gated public plan entry with exhaustive profile dispatch.
    * `solana-sbpf-plan-v1` / `solana-sbpf-elf-v1` → legacy Plan (existing path)
    * `solana-sbpf-cpi-elf-v1` → product CPI Plan (never legacy Plan gate)
    * any other profile → fail closed
-/
def planFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult SolanaPlanFromCapabilityV1 := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .solana do
    throw <| .planInvariant .solana "engineering capability kind is not Solana"
  let profile := ResolvedEngineeringBuildV1.codegenProfileOf capability
  if profile == CodegenProfileId.solanaSbpfPlanV1 ||
      profile == CodegenProfileId.solanaSbpfElfV1 then
    let plan ← materializePlanFromCapabilityV1 capability
    validatePlan plan
    pure (.legacy plan)
  else if profile == CodegenProfileId.solanaSbpfCpiElfV1 then
    -- Product path only: must not enter legacy materializePlanFromCapabilityV1
    -- (that residual gate still FC's the CPI profile for safety).
    let plan ← productPlanFromCapabilityV1 capability
    pure (.cpi plan)
  else
    unknownProfileFail profile

/-- Capability-gated public IR inspection with exhaustive profile dispatch.
    Legacy uses `legacyIrFromCapabilityV1` (EmitIRV1); CPI uses product IR. -/
def irFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult SolanaIRFromCapabilityV1 := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .solana do
    throw <| .planInvariant .solana "engineering capability kind is not Solana"
  let profile := ResolvedEngineeringBuildV1.codegenProfileOf capability
  if profile == CodegenProfileId.solanaSbpfPlanV1 ||
      profile == CodegenProfileId.solanaSbpfElfV1 then
    let ir ← legacyIrFromCapabilityV1 capability
    pure (.legacy ir)
  else if profile == CodegenProfileId.solanaSbpfCpiElfV1 then
    let ir ← productIrFromCapabilityV1 capability
    pure (.cpi ir)
  else
    unknownProfileFail profile

/-- Engineering plan digest for BuildIdentity / materialize.
    Legacy → `engineeringSolanaPlanDigestV1`; CPI → product Plan carrier digest.
    CPI never re-enters the legacy plan schema encoder. -/
def engineeringSolanaMaterializationPlanDigestV1
    (plan : SolanaPlanFromCapabilityV1) : Except String Core.Common.Digest :=
  match plan with
  | .legacy p => engineeringSolanaPlanDigestV1 p
  | .cpi p => pure (SolanaCpiProductPlanV1.digestOf p)

/-- Convenience: recompute plan digest from capability (profile-exhaustive). -/
def planDigestFromCapabilityV1
    (capability : ResolvedEngineeringBuildV1) :
    CompileResult Core.Common.Digest := do
  let profile := ResolvedEngineeringBuildV1.codegenProfileOf capability
  if profile == CodegenProfileId.solanaSbpfCpiElfV1 then
    productPlanDigestFromCapabilityV1 capability
  else if profile == CodegenProfileId.solanaSbpfPlanV1 ||
      profile == CodegenProfileId.solanaSbpfElfV1 then
    let plan ← materializePlanFromCapabilityV1 capability
    validatePlan plan
    match engineeringSolanaPlanDigestV1 plan with
    | .ok d => pure d
    | .error e =>
        throw <| .invalidProgram s!"Solana plan digest failed: {e}"
  else
    unknownProfileFail profile

end ProofForgeV2.Targets.Solana
