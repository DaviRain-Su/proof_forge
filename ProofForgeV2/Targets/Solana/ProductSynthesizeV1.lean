/-
  ProofForgeV2.Targets.Solana.ProductSynthesizeV1 — ADR-0032 U1 / P3-c/d.

  Sole product-rail materialize entry for `solana-sbpf-cpi-elf-v1` (plus plan/elf
  shim dispatch):

  * Zero-site full-body: CPI product Plan/IDL + full-body LowerSemantic IR →
    `emitSbpfAsmV1`, framed via `ProductFrameV1` bodyOnly (P3-c).
  * hasSites ∧ full-body (Map/CFG + ExternalCall): same full-body path with
    product ExternalCall markers → empty-meta `sol_invoke_signed_c` (P3-d
    **partial**). CPI product Plan/IDL still carry site metadata; multi-role
    AccountMeta walkers not yet hooked into body emit (honest partial).
  * Straight-line CPI sites (no full-body need): CpiV1 escrow composite.

  Import leaf: sits above EmitSbpfAsm/CpiProduct; does not import Finalize.
  Engineering only — not multi-role CPI maturity or formal D5.
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

/-- Marker schema for product full-body hybrid `*.cpi-ir.json` (P3-c/d/f).
    Not the escrow `proof-forge.solana.cpi-product-ir.v1` carrier. -/
def fullBodyHybridIrSchemaV1 : String :=
  "proof-forge.solana.full-body-hybrid-ir.v1"

/-- Domain tag for content-bound full-body hybrid IR digest (P3-g).
    `SHA-256(UTF8(domain) || 0x00 || exact UTF-8 of cpi-ir.json)`. -/
def fullBodyHybridIrDigestDomainV1 : String :=
  "pf.solana.full-body-hybrid-ir.v1"

/-- Content-bound digest of product full-body hybrid IR UTF-8 bytes. -/
def fullBodyHybridIrDigestV1 (irUtf8 : ByteArray) : Except String Digest :=
  domainSeparatedSha256 fullBodyHybridIrDigestDomainV1 irUtf8

/-- True when IR text is the product full-body hybrid marker schema. -/
def isFullBodyHybridIrTextV1 (irText : String) : Bool :=
  (irText.splitOn ("\"schema\":\"" ++ fullBodyHybridIrSchemaV1 ++ "\"")).length > 1 ||
    (irText.splitOn ("\"schema\": \"" ++ fullBodyHybridIrSchemaV1 ++ "\"")).length > 1

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

/-- Shared full-body product files: CPI plan/IDL + LowerSemantic body `.s`.
    `hasSites` selects P3-c (zero-site) vs P3-d partial (sites present) markers.
    Empty-meta CPI only — multi-role site metas not yet synthesized into body. -/
def synthesizeFullBodyProductBaseFilesV1
    (capability : ResolvedEngineeringBuildV1)
    (hasSites : Bool) :
    CompileResult (Array OutputFile) := do
  let compiled := ResolvedEngineeringBuildV1.compiledOf capability
  let data ← match decodeSemanticProgramDataV1
      (CompiledSemanticV1.semanticV1Of compiled).canonicalBytes with
    | .ok d => pure d
    | .error _ =>
        throw <| .planInvariant .solana
          "product synthesize full-body: invalid Semantic carrier"
  let admitCaller := semanticUsesContextCallerV1 data
  let cpiPlan ← productPlanFromCapabilityV1 capability
  let validated := SolanaCpiProductPlanV1.planOf cpiPlan
  unless hasSites == !validated.candidate.cpiSites.isEmpty do
    throw <| .planInvariant .solana
      "product synthesize full-body: hasSites flag diverges from cpiSites"
  let idl ← deriveSolanaCpiIdlV1 validated
  let name := validated.candidate.programName
  let planText ← match String.fromUTF8?
      (SolanaCpiProductPlanV1.canonicalBytesOf cpiPlan) with
    | some s => pure s
    | none =>
        throw <| .planInvariant .solana
          "product synthesize full-body: plan UTF-8 decode failed"
  let bodyIr ← fullBodyIrFromProductCapabilityV1 capability admitCaller
  let asm ← emitSbpfAsmV1 bodyIr
  -- Body-only frame: empty-meta CPI uses body temp region (not multi-role
  -- walker scratch). Multi-role unified frame lands with real site hooks.
  let frame ← match mintBodyOnlyFrameV1 productMaxFrameBytesV1 with
    | .ok L => pure L
    | .error e =>
        throw <| .planInvariant .solana s!"product synthesize frame: {e}"
  requireProductFrameV1 frame
  let synthTag := if hasSites then "p3d-partial-empty-meta" else "p3c-zero-site"
  let honesty :=
    if hasSites then
      "full-body+ExternalCall empty-meta sol_invoke; multi-role AccountMeta deferred"
    else
      "body via ProductSynthesizeV1→LowerSemantic+EmitSbpfAsm (P3-c)"
  -- Deterministic marker IR (no self-embedded digest field — P3-g hashes
  -- exact UTF-8 via `fullBodyHybridIrDigestV1`).
  let irText :=
    "{\"schema\":\"" ++ fullBodyHybridIrSchemaV1 ++ "\"," ++
    "\"note\":\"" ++ honesty ++ "\"," ++
    "\"synthesize\":\"" ++ synthTag ++ "\"," ++
    "\"frameMode\":\"bodyOnly\"," ++
    "\"frameBytes\":" ++ toString frame.totalBytes ++ "," ++
    "\"admitCaller\":" ++ (if admitCaller then "true" else "false") ++ "," ++
    "\"admitProductExternalCall\":true," ++
    "\"cpiSites\":" ++ toString validated.candidate.cpiSites.size ++ "," ++
    "\"cpiMaturity\":\"" ++
      (if hasSites then "empty-meta-partial" else "zero-site") ++ "\"}"
  let irDigestWire ← match fullBodyHybridIrDigestV1 irText.toUTF8 with
    | .ok d =>
        match renderDigest d with
        | .ok s => pure s
        | .error e =>
            throw <| .planInvariant .solana
              s!"product synthesize full-body: irDigest render: {e}"
    | .error e =>
        throw <| .planInvariant .solana
          s!"product synthesize full-body: irDigest: {e}"
  let bindingsText :=
    "{\"schema\":\"proof-forge.solana.cpi-bindings.v1\"," ++
    "\"fullBodyHybrid\":true," ++
    "\"synthesize\":\"" ++ synthTag ++ "\"," ++
    "\"frameMode\":\"bodyOnly\"," ++
    "\"frameBytes\":" ++ toString frame.totalBytes ++ "," ++
    "\"cpiSites\":" ++ toString validated.candidate.cpiSites.size ++ "," ++
    "\"irDigest\":\"" ++ irDigestWire ++ "\"," ++
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

/-- Zero-site full-body product base files (P3-c). -/
def synthesizeZeroSiteFullBodyBaseFilesV1
    (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) :=
  synthesizeFullBodyProductBaseFilesV1 capability false

/-- P3-d partial: full-body shape + non-empty cpiSites → one ELF with body
    Map/CFG + empty-meta ExternalCall invoke. Not multi-role CPI maturity. -/
def synthesizeFullBodyWithSitesBaseFilesV1
    (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) :=
  synthesizeFullBodyProductBaseFilesV1 capability true

private def buildUnknownProfileFail (profile : CodegenProfileId) :
    CompileResult (Array OutputFile) :=
  throw <| .planInvariant .solana
    s!"unknown Solana codegen profile '{profile}' (exhaustive plan/elf/cpi only)"

/-- Capability-gated public materialize entry (S6 / #125 + ADR-0032 U1 P3-c/d).

    Exhaustive profile dispatch:
    * `solana-sbpf-plan-v1` → single-account plan+IDL only
    * `solana-sbpf-elf-v1` → single-account plan+IDL+`.s`
    * `solana-sbpf-cpi-elf-v1` → product base files:
        - full-body shape ∧ CPI sites → P3-d partial (empty-meta)
        - full-body shape ∧ zero sites → P3-c zero-site full body
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
    let needsBody := semanticNeedsFullBodyV1 data
    if needsBody then
      -- P3-c zero-site full body, or P3-d partial (sites + empty-meta CPI).
      synthesizeFullBodyProductBaseFilesV1 capability hasSites
    else
      -- Straight-line CPI product (TipJar/TokenJar) or narrow zero-site body:
      -- escrow composite path + unified frame contract pin (P3-b/c).
      let files ← productBaseFilesFromCapabilityV1 capability
      let bodyTempBytes :=
        productEscrowTempRegionEndV1 - productEscrowTempBaseV1
      let cpiScratchBytes :=
        productMaxFrameBytesV1 - productEscrowTempRegionEndV1
      match mintUnifiedCpiFrameV1 bodyTempBytes cpiScratchBytes with
      | .ok frame => do
          requireProductFrameV1 frame
          pure files
      | .error e =>
          throw <| .planInvariant .solana
            s!"product synthesize escrow frame: {e}"
  else
    buildUnknownProfileFail profile

end ProofForgeV2.Targets.Solana
