/-
  ProofForgeV2.Targets.Solana.ProductSynthesizeV1 — ADR-0032 U1 / P3-c/d/e / M4b.

  Sole product-rail materialize entry for `solana-sbpf-cpi-elf-v1` (plus plan/elf
  shim dispatch):

  * Zero catalog-site full-body: CPI product Plan/IDL + full-body LowerSemantic
    IR → `emitSbpfAsmV1`, framed via `ProductFrameV1` bodyOnly (P3-c).
  * ADR-0053 generic bind with nonempty accounts: append bound account/program
    outer roles, exact runtime identity/privilege join, and pass AccountInfos.
  * hasSites ∧ full-body + sole `solana.system.transfer` + ≥3 outer roles:
    stamp multi-role locals → outer walk + AccountMeta + System 12B invoke
    (`p3e-system-transfer-multi-role`, frameMode `unifiedCpi`).
  * hasSites ∧ full-body + all `pf.assets.token.transfer` + roleCount ∈ [6,32]:
    multi-site multi-role token composite (`m4b-token-transfer-multi-role`,
    frameMode `unifiedCpi`; MiniAmmAssets 4 sites / 21 roles).
  * Other hasSites ∧ full-body (Map/CFG + ExternalCall): empty-meta
    `sol_invoke_signed_c` (P3-d/e foundation partial; Map temp residual may
    still fail emit independently).
  * Straight-line CPI sites (no full-body need): CpiV1 escrow composite.

  Import leaf: sits above EmitSbpfAsm/CpiProduct; does not import Finalize.
  Engineering only — not TipJar/escrow multi-recipe maturity or formal D5.
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
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.ProductFrameV1
import ProofForgeV2.Targets.Solana.ProductCpiRecipesV1
import ProofForgeV2.Targets.CallBindV1

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.Solana.CpiV1
open ProofForgeV2.Targets.Solana.ProductFrameV1
open ProofForgeV2.Targets.Solana.ProductCpiRecipesV1

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

/-- Exact SYS-S5 host syscall QNs. They are not CPI sites, but their
    dedicated Plan/IR/SBPF lowering requires the full-body product route. -/
private def isCryptoHostSyscallCalleeV1 (callee : QualifiedName) : Bool :=
  let comps := callee.components.toArray
  comps == #["pf", "crypto", "sha256"] ||
    comps == #["pf", "crypto", "keccak256"] ||
    comps == #["pf", "crypto", "sha256Bytes"]

/-- Multi-block CFG, aggregate Index*/construct, or a Solana host syscall needs
    the full LowerSemantic body. -/
def semanticNeedsFullBodyV1 (data : SemanticProgramDataV1) : Bool :=
  data.callables.any fun c =>
    c.blocks.size > 1 ||
      c.blocks.any fun b =>
        b.instructions.any fun instr =>
          match instr.op with
          | .indexGet .. | .indexSet .. | .construct .. | .fieldGet ..
          | .fieldSet .. | .variantTag .. | .variantPayload .. => true
          | .externalCall _ callee _ => isCryptoHostSyscallCalleeV1 callee
          | _ => false

def semanticUsesContextCallerV1 (data : SemanticProgramDataV1) : Bool :=
  data.callables.any fun c =>
    c.blocks.any fun b =>
      b.instructions.any fun instr =>
        match instr.op with
        | .contextRead key => key == callerContextKeyV1
        | _ => false

private def isCallBindExemptQnV1 (callee : QualifiedName) : Bool :=
  let qn := String.intercalate "." callee.components.toArray.toList
  qn.startsWith "pf.crypto." || qn.startsWith "pf.assets." ||
    ProductCpiRecipesV1.isSystemTransferCalleeV1 callee.components.toArray

/-- Unique generic synchronous callees in semantic source order. Scheduled
    workflows remain rejected by CPI derive and are not an AccountInfo join. -/
private def collectGenericCallBindCalleesV1
    (data : SemanticProgramDataV1) : Array QualifiedName := Id.run do
  let mut out : Array QualifiedName := #[]
  for callable in data.callables do
    for block in callable.blocks do
      for instruction in block.instructions do
        match instruction.op with
        | .externalCall _ callee _ =>
            unless isCallBindExemptQnV1 callee || out.any (· == callee) do
              out := out.push callee
        | _ => pure ()
  pure out

/-- ADR-0053 Wave 3 activation. Empty rows keep the Wave 2b partial path.
    One full-body outer layout currently carries one generic callee identity;
    multiple distinct nonempty-bound callees fail closed rather than sharing a
    program role that could not satisfy both identities. -/
private def resolveCallBindOuterAccountsV1
    (data : SemanticProgramDataV1)
    (bindings : Option CallBindV1.CallBindTableV1) :
    CompileResult (Option (ByteArray × Array CallBindV1.CallBindAccountV1)) := do
  let some table := bindings | pure none
  let callees := collectGenericCallBindCalleesV1 data
  let mut hasNonempty := false
  for callee in callees do
    match CallBindV1.requireSolanaBindingV1 table callee.components.toArray with
    | .ok (_, accounts) =>
        if !accounts.isEmpty then hasNonempty := true
    | .error msg => throw <| .planInvariant .solana msg
  unless hasNonempty do
    return none
  unless callees.size == 1 do
    throw <| .planInvariant .solana
      "call-bind: Solana outer AccountInfo join currently requires one distinct generic callee"
  let some callee := callees[0]? |
    throw <| .planInvariant .solana
      "call-bind: Solana outer AccountInfo join missing generic callee"
  match CallBindV1.requireSolanaOuterAccountJoinV1 table callee.components.toArray with
  | .ok binding => pure (some binding)
  | .error msg => throw <| .planInvariant .solana msg

/-- Shared full-body product files: CPI plan/IDL + LowerSemantic body `.s`.
    `hasSites` selects P3-c (zero-site) vs site-bearing paths. Sole
    system.transfer with ≥3 outer roles stamps multi-role AccountMeta; other
    sites remain empty-meta partial. -/
def synthesizeFullBodyProductBaseFilesV1
    (capability : ResolvedEngineeringBuildV1)
    (hasSites : Bool)
    (bindings : Option CallBindV1.CallBindTableV1 := none) :
    CompileResult (Array OutputFile) := do
  let compiled := ResolvedEngineeringBuildV1.compiledOf capability
  let data ← match decodeSemanticProgramDataV1
      (CompiledSemanticV1.semanticV1Of compiled).canonicalBytes with
    | .ok d => pure d
    | .error _ =>
        throw <| .planInvariant .solana
          "product synthesize full-body: invalid Semantic carrier"
  let admitCaller := semanticUsesContextCallerV1 data
  let cpiPlan ← productPlanFromCapabilityV1 capability bindings
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
  let bodyIr0 ← fullBodyIrFromProductCapabilityV1 capability admitCaller
  let callBindOuterAccounts? ← resolveCallBindOuterAccountsV1 data bindings
  let siteQns := validated.candidate.cpiSites.map (fun s => s.qn)
  let allSystemXfer :=
    !siteQns.isEmpty && siteQns.all isSystemTransferQnV1
  let allTokenXfer :=
    !siteQns.isEmpty && siteQns.all isPfAssetsTokenTransferQnV1
  let roleCount := validated.candidate.accountRoles.size
  -- Resolve outer role id by key policy (for token multi-role stamping).
  let findRoleId (pred : RoleKeyPolicyV1 → Bool) : Option Nat :=
    validated.candidate.accountRoles.findSome? fun r =>
      if pred r.keyPolicy then some r.roleId else none
  -- P3-e multi-role: sole system.transfer sites + multi-block body → stamp
  -- role locals and emit multi-role walk + AccountMeta invoke.
  -- M4c multi-role: all token.transfer sites + role table fit → stamp each
  -- site (ATA ensure + transferCheckedPda) with per-site vaultAta/dstAta.
  let bodyIr ←
    if let some (programId, accounts) := callBindOuterAccounts? then do
      unless !hasSites do
        throw <| .planInvariant .solana
          "call-bind: generic outer AccountInfo join cannot share a full-body frozen CPI-site layout"
      unless accounts.size + 1 ≤ roleCount do
        throw <| .planInvariant .solana
          "call-bind: validated Plan is missing its bound role suffix"
      let roleBase := roleCount - accounts.size - 1
      for (account, accountIndex) in accounts.zipIdx do
        let some role := validated.candidate.accountRoles[roleBase + accountIndex]? |
          throw <| .planInvariant .solana
            s!"call-bind: validated Plan account role {accountIndex} missing"
        let key ← match SolanaPubkeyV1.ofBytes account.pubkey with
          | .ok value => pure value
          | .error msg => throw <| .planInvariant .solana msg
        unless role.name == account.role &&
            role.keyPolicy == .callBindAccount key account.signer account.writable do
          throw <| .planInvariant .solana
            s!"call-bind: validated Plan account role {accountIndex} diverges from bind row"
      let some programRole := validated.candidate.accountRoles[roleCount - 1]? |
        throw <| .planInvariant .solana
          "call-bind: validated Plan program role missing"
      let expectedProgram ← match SolanaPubkeyV1.ofBytes programId with
        | .ok value => pure value
        | .error msg => throw <| .planInvariant .solana msg
      unless programRole.keyPolicy == .callBindProgram expectedProgram do
        throw <| .planInvariant .solana
          "call-bind: validated Plan program role diverges from bind row"
      unless roleCount ≤ productMaxOuterRolesV1 do
        throw <| .planInvariant .solana
          s!"call-bind: Solana outer role count {roleCount} exceeds {productMaxOuterRolesV1}"
      pure (withProductMultiRoleCallBindV1 bodyIr0 roleBase accounts.size)
    else if hasSites && allSystemXfer && roleCount ≥ 3 then do
      let some site0 := validated.candidate.cpiSites[0]? |
        throw <| .planInvariant .solana
          "product synthesize multi-role system.transfer missing site 0"
      unless site0.metas.size == 2 do
        throw <| .planInvariant .solana
          "product synthesize multi-role system.transfer requires exactly 2 metas"
      let some meta0 := site0.metas[0]? |
        throw <| .planInvariant .solana "multi-role system.transfer meta0 missing"
      let some meta1 := site0.metas[1]? |
        throw <| .planInvariant .solana "multi-role system.transfer meta1 missing"
      pure (withProductMultiRoleSystemTransferV1 bodyIr0 roleCount
        meta0.roleId meta1.roleId site0.programRoleId)
    else if hasSites && allTokenXfer &&
        roleCount ≥ 6 && roleCount ≤ productMaxOuterRolesV1 then do
      let some callerLocal := findRoleId (· == .handlerCaller) |
        throw <| .planInvariant .solana "token multi-role pf_caller role missing"
      let some systemLocal :=
          findRoleId (fun k => match k with
            | .fixedProgram p => p == "system-v1" | _ => false) |
        throw <| .planInvariant .solana "token multi-role system-v1 role missing"
      let some ataLocal :=
          findRoleId (fun k => match k with
            | .fixedProgram p => p == "ata-classic-v1" | _ => false) |
        throw <| .planInvariant .solana "token multi-role ata-classic-v1 role missing"
      let mut sites : Array ProductTokenTransferSiteV1 := #[]
      for site in validated.candidate.cpiSites do
        unless site.metas.size == 4 do
          throw <| .planInvariant .solana
            "product synthesize multi-role token.transfer requires exactly 4 metas"
        let some mVaultAta := site.metas[0]? |
          throw <| .planInvariant .solana "token multi-role meta0 vaultAta missing"
        let some mMint := site.metas[1]? |
          throw <| .planInvariant .solana "token multi-role meta1 mint missing"
        let some mDstAta := site.metas[2]? |
          throw <| .planInvariant .solana "token multi-role meta2 dstAta missing"
        let some mVault := site.metas[3]? |
          throw <| .planInvariant .solana "token multi-role meta3 vaultPda missing"
        -- dst wallet is the Principal param meta binding arg index 1 → role
        -- from site args (mint=0, dst=1). Prefer site arg roleId for dst.
        let some dstWalletLocal :=
            (site.args.findSome? fun a =>
              if a.spec.name == "dst" then a.roleId else none) |
          throw <| .planInvariant .solana "token multi-role dst wallet role missing"
        sites := sites.push {
          vaultAtaLocal := mVaultAta.roleId
          mintLocal := mMint.roleId
          dstAtaLocal := mDstAta.roleId
          vaultPdaLocal := mVault.roleId
          tokenProgramLocal := site.programRoleId
          callerLocal
          dstWalletLocal
          systemLocal
          ataProgramLocal := ataLocal
          accountInfoCount := roleCount
        }
      unless sites.size > 0 do
        throw <| .planInvariant .solana
          "product synthesize multi-role token.transfer requires ≥1 site"
      pure (withProductMultiRoleTokenSitesV1 bodyIr0 roleCount sites)
    else
      pure bodyIr0
  let multiRoleOn := bodyIr.stateAccount.productMultiRoleCount > 0
  let callBindMultiRoleOn := bodyIr.stateAccount.productCallBindMultiRole
  let tokenMultiRoleOn := bodyIr.stateAccount.productTokenMultiRole
  let multiN := bodyIr.stateAccount.productMultiRoleCount
  let asm ← emitSbpfAsmV1 bodyIr bindings
  let frame ←
    if multiRoleOn then do
      unless multiRoleCpiBaseForV1 multiN ≤ productMaxFrameBytesV1 do
        throw <| .planInvariant .solana
          s!"product synthesize multi-role frame: cpiBase {multiRoleCpiBaseForV1 multiN} exceeds max {productMaxFrameBytesV1}"
      match mintUnifiedCpiFrameV1 multiN multiRoleBodyTempBytesV1
          multiRoleCpiScratchBudgetV1 with
      | .ok L => pure L
      | .error e =>
          throw <| .planInvariant .solana s!"product synthesize multi-role frame: {e}"
    else
      match mintBodyOnlyFrameV1 productMaxFrameBytesV1 with
      | .ok L => pure L
      | .error e =>
          throw <| .planInvariant .solana s!"product synthesize frame: {e}"
  requireProductFrameV1 frame
  let frameMode := if multiRoleOn then "unifiedCpi" else "bodyOnly"
  let synthTag :=
    if callBindMultiRoleOn then "call-bind-outer-account-join"
    else if !hasSites then "p3c-zero-site"
    else if multiRoleOn && tokenMultiRoleOn then "m4b-token-transfer-multi-role"
    else if multiRoleOn then "p3e-system-transfer-multi-role"
    else if allTokenXfer then "m4b-token-transfer-empty-meta"
    else if allSystemXfer then "p3e-system-transfer-empty-meta"
    else "p3d-partial-empty-meta"
  let cpiMaturity :=
    if callBindMultiRoleOn then "call-bind-outer-account-join"
    else if !hasSites then "zero-site"
    else if multiRoleOn && tokenMultiRoleOn then "multi-role-token-transfer"
    else if multiRoleOn then "multi-role-system-transfer"
    else if allTokenXfer then "empty-meta-partial-token-transfer"
    else if allSystemXfer then "empty-meta-partial-system-transfer"
    else "empty-meta-partial"
  let honesty :=
    if callBindMultiRoleOn then
      "full-body+generic call-bind compile-time AccountMeta + exact outer AccountInfo identity/privilege join"
    else if !hasSites then
      "body via ProductSynthesizeV1→LowerSemantic+EmitSbpfAsm (P3-c)"
    else if multiRoleOn && tokenMultiRoleOn then
      "full-body+token.transfer multi-role AccountMeta + ATA ensure + transferCheckedPda (M4b)"
    else if multiRoleOn then
      "full-body+system.transfer multi-role AccountMeta + outer role walk (P3-e)"
    else if allTokenXfer then
      "full-body+token.transfer: empty AccountMeta; multi-role deferred (Map/multi-site residual)"
    else if allSystemXfer then
      "full-body+system.transfer: System program id+12B data; empty AccountMeta (P3-e foundation)"
    else
      "full-body+ExternalCall empty-meta sol_invoke; multi-role AccountMeta deferred"
  -- Deterministic marker IR (no self-embedded digest field — P3-g hashes
  -- exact UTF-8 via `fullBodyHybridIrDigestV1`).
  let irText :=
    "{\"schema\":\"" ++ fullBodyHybridIrSchemaV1 ++ "\"," ++
    "\"note\":\"" ++ honesty ++ "\"," ++
    "\"synthesize\":\"" ++ synthTag ++ "\"," ++
    "\"frameMode\":\"" ++ frameMode ++ "\"," ++
    "\"frameBytes\":" ++ toString frame.totalBytes ++ "," ++
    "\"admitCaller\":" ++ (if admitCaller then "true" else "false") ++ "," ++
    "\"admitProductExternalCall\":true," ++
    "\"cpiSites\":" ++ toString validated.candidate.cpiSites.size ++ "," ++
    "\"outerRoleCount\":" ++ toString (if multiRoleOn then multiN else roleCount) ++ "," ++
    "\"cpiMaturity\":\"" ++ cpiMaturity ++ "\"}"
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
  let planDigestWire ← match renderDigest validated.digest with
    | .ok digest => pure digest
    | .error e =>
        throw <| .planInvariant .solana
          s!"product synthesize full-body: planDigest render: {e}"
  let profileDigestWire ← match renderDigest validated.candidate.profileDigest with
    | .ok digest => pure digest
    | .error e =>
        throw <| .planInvariant .solana
          s!"product synthesize full-body: profileDigest render: {e}"
  let catalogDigestWire ← match renderDigest
      validated.candidate.calleeCatalogDigest with
    | .ok digest => pure digest
    | .error e =>
        throw <| .planInvariant .solana
          s!"product synthesize full-body: catalogDigest render: {e}"
  let bindingsText :=
    "{\"schema\":\"proof-forge.solana.cpi-bindings.v1\"," ++
    "\"fullBodyHybrid\":true," ++
    "\"profileId\":\"" ++ validated.candidate.profileId ++ "\"," ++
    "\"profileDigest\":\"" ++ profileDigestWire ++ "\"," ++
    "\"calleeCatalogDigest\":\"" ++ catalogDigestWire ++ "\"," ++
    "\"planDigest\":\"" ++ planDigestWire ++ "\"," ++
    "\"synthesize\":\"" ++ synthTag ++ "\"," ++
    "\"frameMode\":\"" ++ frameMode ++ "\"," ++
    "\"frameBytes\":" ++ toString frame.totalBytes ++ "," ++
    "\"cpiSites\":" ++ toString validated.candidate.cpiSites.size ++ "," ++
    "\"outerRoleCount\":" ++ toString (if multiRoleOn then multiN else roleCount) ++ "," ++
    "\"irDigest\":\"" ++ irDigestWire ++ "\"," ++
    "\"implementationState\":\"" ++
      validated.candidate.computeAssumptions.implementationState ++ "\"," ++
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
    (capability : ResolvedEngineeringBuildV1)
    (bindings : Option CallBindV1.CallBindTableV1 := none) :
    CompileResult (Array OutputFile) :=
  synthesizeFullBodyProductBaseFilesV1 capability false bindings

/-- P3-d partial: full-body shape + non-empty cpiSites → one ELF with body
    Map/CFG + empty-meta ExternalCall invoke. Not multi-role CPI maturity. -/
def synthesizeFullBodyWithSitesBaseFilesV1
    (capability : ResolvedEngineeringBuildV1)
    (bindings : Option CallBindV1.CallBindTableV1 := none) :
    CompileResult (Array OutputFile) :=
  synthesizeFullBodyProductBaseFilesV1 capability true bindings

private def buildUnknownProfileFail (profile : CodegenProfileId) :
    CompileResult (Array OutputFile) :=
  throw <| .planInvariant .solana
    s!"unknown Solana codegen profile '{profile}' (exhaustive plan/elf/cpi only)"

/-- Capability-gated public materialize entry (S6 / ADR-0032 U1 sole rail).

    Sole profile: `solana-sbpf-cpi-elf-v1`
    * full-body shape ∧ CPI sites → full-body + multi-role/empty-meta
    * zero sites → full-body hybrid
    * straight-line non-empty sites → CpiV1 escrow product base files
    * any other profile (including retired plan/elf shims) → fail closed
-/
def buildFromCapability (capability : ResolvedEngineeringBuildV1)
    (bindings : Option CallBindV1.CallBindTableV1 := none) :
    CompileResult (Array OutputFile) := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .solana do
    throw <| .planInvariant .solana "engineering capability kind is not Solana"
  let profile := ResolvedEngineeringBuildV1.codegenProfileOf capability
  if profile == CodegenProfileId.solanaSbpfCpiElfV1 then
    let plan ← productPlanFromCapabilityV1 capability bindings
    let cand := SolanaCpiProductPlanV1.candidateOf plan
    let hasSites := !cand.cpiSites.isEmpty
    let compiled := ResolvedEngineeringBuildV1.compiledOf capability
    let data ← match decodeSemanticProgramDataV1
        (CompiledSemanticV1.semanticV1Of compiled).canonicalBytes with
      | .ok d => pure d
      | .error _ =>
          throw <| .planInvariant .solana "invalid SemanticProgramV1 carrier"
    let needsBody := semanticNeedsFullBodyV1 data
    -- Empty logical state (view-only programs such as CallerIsMe): full-body
    -- LowerSemantic Plan requires nonempty state + initializer, so stay on the
    -- CPI product Plan/IDL/ELF path (stateSchemas=[], pf_caller-only roles).
    -- Nonempty state + zero CPI sites → full-body synthesize. Host syscalls
    -- also force full-body when real CPI sites coexist; escrow composite is
    -- only for straight-line non-empty sites without full-body operations.
    if data.logicalState.isEmpty then
      productBaseFilesFromCapabilityV1 capability bindings
    else if !hasSites || needsBody then
      synthesizeFullBodyProductBaseFilesV1 capability hasSites bindings
    else
      let files ← productBaseFilesFromCapabilityV1 capability bindings
      let bodyTempBytes :=
        productEscrowTempRegionEndV1 - productEscrowTempBaseV1
      let cpiScratchBytes :=
        productMaxFrameBytesV1 - productEscrowTempRegionEndV1
      match mintEscrowCompatibleUnifiedCpiFrameV1 bodyTempBytes cpiScratchBytes with
      | .ok frame => do
          requireProductFrameV1 frame
          pure files
      | .error e =>
          throw <| .planInvariant .solana
            s!"product synthesize escrow frame: {e}"
  else
    buildUnknownProfileFail profile

end ProofForgeV2.Targets.Solana
