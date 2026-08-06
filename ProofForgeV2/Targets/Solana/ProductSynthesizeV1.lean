/-
  ProofForgeV2.Targets.Solana.ProductSynthesizeV1 — ADR-0032 U1 / P3-c skeleton.

  Sole product-rail materialize entry for `solana-sbpf-cpi-elf-v1` (plus plan/elf
  shim dispatch). Zero-site full-body path: CPI product Plan/IDL + full-body
  LowerSemantic IR → `emitSbpfAsmV1`, framed via `ProductFrameV1` bodyOnly.

  Non-zero CPI sites still delegate to `CpiV1.productBaseFilesFromCapabilityV1`
  (escrow composite). Site hooks = P3-d; true unified product IR digest = later.

  Import leaf: sits above EmitSbpfAsm/CpiProduct; does not import Finalize.
  Engineering only.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.Solana.LowerSemanticV1
import ProofForgeV2.Targets.Solana.EmitIRV1
import ProofForgeV2.Targets.Solana.EmitSbpfAsmV1
import ProofForgeV2.Targets.Solana.CpiProductV1
import ProofForgeV2.Targets.Solana.CpiIdlV1
import ProofForgeV2.Targets.Solana.ProductFrameV1

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.Solana.CpiV1
open ProofForgeV2.Targets.Solana.ProductFrameV1

/-- Multi-block CFG or aggregate Index*/construct needs full LowerSemantic body. -/
def semanticNeedsFullBodyV1 (data : SemanticProgramDataV1) : Bool :=
  data.callables.any fun c =>
    c.blocks.size > 1 ||
      c.blocks.any fun b =>
        b.instructions.any fun instr =>
          match instr.op with
          | .indexGet .. | .indexSet .. | .construct .. | .fieldGet ..
          | .fieldSet .. | .variantTag .. | .variantPayload .. => true
          | _ => false

def semanticUsesContextCallerV1 (data : SemanticProgramDataV1) : Bool :=
  data.callables.any fun c =>
    c.blocks.any fun b =>
      b.instructions.any fun instr =>
        match instr.op with
        | .contextRead key => key == callerContextKeyV1
        | _ => false

/-- Zero-site full-body product base files (P3-c skeleton ≡ former hybrid path,
    with ProductFrame bodyOnly gate).
    `emitSbpfAsmV1` already enforces per-handler `(cursor+1)*8 ≤ 4096`; the
    frame mint records that body-only mode occupies at most the full stack. -/
def synthesizeZeroSiteFullBodyBaseFilesV1
    (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  let compiled := ResolvedEngineeringBuildV1.compiledOf capability
  let data ← match decodeSemanticProgramDataV1
      (CompiledSemanticV1.semanticV1Of compiled).canonicalBytes with
    | .ok d => pure d
    | .error _ =>
        throw <| .planInvariant .solana
          "product synthesize zero-site: invalid Semantic carrier"
  let admitCaller := semanticUsesContextCallerV1 data
  let cpiPlan ← productPlanFromCapabilityV1 capability
  let validated := SolanaCpiProductPlanV1.planOf cpiPlan
  unless validated.candidate.cpiSites.isEmpty do
    throw <| .planInvariant .solana
      "product synthesize zero-site: cpiSites must be empty (use escrow path)"
  let idl ← deriveSolanaCpiIdlV1 validated
  let name := validated.candidate.programName
  let planText ← match String.fromUTF8?
      (SolanaCpiProductPlanV1.canonicalBytesOf cpiPlan) with
    | some s => pure s
    | none =>
        throw <| .planInvariant .solana
          "product synthesize zero-site: plan UTF-8 decode failed"
  let bodyIr ← fullBodyIrFromProductCapabilityV1 capability admitCaller
  let asm ← emitSbpfAsmV1 bodyIr
  -- Post-emit: body region may use up to the full 4096 stack (emit-gated).
  let frame ← match mintBodyOnlyFrameV1 productMaxFrameBytesV1 with
    | .ok L => pure L
    | .error e =>
        throw <| .planInvariant .solana s!"product synthesize frame: {e}"
  requireProductFrameV1 frame
  -- Keep hybrid IR schema for product pin / Finalize irDigest compatibility
  -- (P3-g will replace with recomputeable product IR).
  let irText :=
    "{\"schema\":\"proof-forge.solana.full-body-hybrid-ir.v1\"," ++
    "\"note\":\"body via ProductSynthesizeV1→LowerSemantic+EmitSbpfAsm (P3-c)\"," ++
    "\"synthesize\":\"p3c-zero-site\"," ++
    "\"frameMode\":\"bodyOnly\"," ++
    "\"frameBytes\":" ++ toString frame.totalBytes ++ "," ++
    "\"admitCaller\":" ++ (if admitCaller then "true" else "false") ++ "}"
  let bindingsText :=
    "{\"schema\":\"proof-forge.solana.cpi-bindings.v1\"," ++
    "\"fullBodyHybrid\":true," ++
    "\"synthesize\":\"p3c-zero-site\"," ++
    "\"frameMode\":\"bodyOnly\"," ++
    "\"frameBytes\":" ++ toString frame.totalBytes ++ "," ++
    "\"programName\":\"" ++ name ++ "\"}"
  pure #[
    { path := s!"{name}.cpi-plan.json"
      mediaType := "application/json"
      contents := planText },
    { path := s!"{name}.cpi-ir.json"
      mediaType := "application/json"
      contents := irText },
    { path := s!"{name}.idl.json"
      mediaType := "application/json"
      contents := idl.canonicalText },
    { path := s!"{name}.s"
      mediaType := "text/x-asm"
      contents := asm },
    { path := s!"{name}.cpi-bindings.json"
      mediaType := "application/json"
      contents := bindingsText }
  ]

private def buildUnknownProfileFail (profile : CodegenProfileId) :
    CompileResult (Array OutputFile) :=
  throw <| .planInvariant .solana
    s!"unknown Solana codegen profile '{profile}' (exhaustive plan/elf/cpi only)"

/-- Capability-gated public materialize entry (S6 / #125 + ADR-0032 U1 P3-c).

    Exhaustive profile dispatch:
    * `solana-sbpf-plan-v1` → single-account plan+IDL only
    * `solana-sbpf-elf-v1` → single-account plan+IDL+`.s`
    * `solana-sbpf-cpi-elf-v1` → product base files:
        - zero CPI sites ∧ full-body shape → ProductSynthesize zero-site
        - else → CpiV1 escrow product base files
    * unknown → fail closed
-/
def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .solana do
    throw <| .planInvariant .solana "engineering capability kind is not Solana"
  let profile := ResolvedEngineeringBuildV1.codegenProfileOf capability
  if profile == CodegenProfileId.solanaSbpfPlanV1 then
    let ir ← legacyIrFromCapabilityV1 capability
    emitPlanAndIdlFromIR capability ir
  else if profile == CodegenProfileId.solanaSbpfElfV1 then
    let ir ← legacyIrFromCapabilityV1 capability
    emitElfFromIR capability ir
  else if profile == CodegenProfileId.solanaSbpfCpiElfV1 then
    let plan ← productPlanFromCapabilityV1 capability
    let cand := SolanaCpiProductPlanV1.candidateOf plan
    let hasSites := !cand.cpiSites.isEmpty
    let compiled := ResolvedEngineeringBuildV1.compiledOf capability
    let data ← match decodeSemanticProgramDataV1
        (CompiledSemanticV1.semanticV1Of compiled).canonicalBytes with
      | .ok d => pure d
      | .error _ =>
          throw <| .planInvariant .solana "invalid SemanticProgramV1 carrier"
    if !hasSites && semanticNeedsFullBodyV1 data then
      synthesizeZeroSiteFullBodyBaseFilesV1 capability
    else
      productBaseFilesFromCapabilityV1 capability
  else
    buildUnknownProfileFail profile

end ProofForgeV2.Targets.Solana
