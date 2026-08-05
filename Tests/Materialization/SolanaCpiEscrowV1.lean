/-
  Tests.Materialization.SolanaCpiEscrowV1 — #124 composite escrow CPI IR/emitter.

  Authority path:
  Loader → product compile → preflight capability → Semantic Plan
  → Escrow IR (from SolanaCpiPreflightPlanV1; NOT leaf-only Token/System/ATA IR)
  → Escrow emitter.

  Source authority is the real on-disk fixture:
    runtime-tests/solana/fixtures/EscrowCpi.lean
  (not an inline alternate program string). Dense handlers (source order):
    init, initializeVault, deposit, release, refund,
    initializeThenOverflow, depositThenOverflow, releaseThenOverflow,
    refundThenOverflow, inspect.

  Pins: dual-invoke initializeVault (System createPda + ATA createIdempotent),
  deposit transferChecked, release/refund transferCheckedPda, *ThenOverflow
  rollback order (store → CPI(s) → failing checked add), siteArgChecks→
  siteChecks→invoke adjacency, package identities, test-preactivation
  boundary, #125 ordinary resolver + product Plan/IR success for approved
  composite Escrow closure (preactivation pins and isProductArtifact=false
  unchanged), leaf IR independence.
-/
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiIRV1
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiProductV1
import ProofForgeV2.Targets.Solana.CpiPreflightIRV1
import ProofForgeV2.Targets.Solana.CpiSystemIRV1
import ProofForgeV2.Targets.Solana.CpiTokenIRV1
import ProofForgeV2.Targets.Solana.CpiAtaIRV1
import ProofForgeV2.Targets.Solana.CpiEscrowIRV1
import ProofForgeV2.Targets.Solana.EmitCpiEscrowSbpfV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.Materialization.SolanaCpiEscrowV1

set_option maxRecDepth 4096

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Compiler
open ProofForgeV2.Targets
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Solana.CpiV1

private def fixturePath : String :=
  "runtime-tests/solana/fixtures/EscrowCpi.lean"

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectPlanOk {α : Type} (result : CompileResult α)
    (label : String) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def expectPlanReject {α : Type} (result : CompileResult α)
    (label : String) : IO Unit :=
  match result with
  | .error error =>
      expect (error.code == "PF-PLAN-INVARIANT")
        s!"{label}: expected PF-PLAN-INVARIANT, got {error.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly accepted"

private def hasSubstr (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

private def countSubstr (haystack needle : String) : Nat :=
  (haystack.splitOn needle).length - 1

/-- Load the real runtime fixture from disk (sole source authority). -/
private unsafe def compileSource
    (session : Language.Loader.ParserSession) : IO CompiledSemanticV1 := do
  let sourceText ← IO.FS.readFile fixturePath
  let (source, origins) ← match ← session.selectProgramV1WithOrigins
      sourceText fixturePath "Examples.EscrowCpi" none with
    | .ok pair => pure pair
    | .error error =>
        throw <| IO.userError s!"load Escrow fixture {fixturePath}: {error.render}"
  match Compiler.compileProgramProductV1 source origins with
  | .ok compiled => pure compiled
  | .error _ => throw <| IO.userError "product compile rejected EscrowCpi fixture"

private def cpiSelection : IO ResolvedBuildSelectionV1 :=
  expectPlanOk
    (resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfCpiElfV1))
    "resolve CPI profile"

private unsafe def fullChain
    (session : Language.Loader.ParserSession) :
    IO (CompiledSemanticV1 × SolanaCpiPreflightPlanV1 ×
      ResolvedSolanaCpiEscrowIRV1 × SolanaCpiEscrowAssemblyV1) := do
  let compiled ← compileSource session
  let selection ← cpiSelection
  let preflight ← expectPlanOk
    (resolveSolanaCpiPreflightV1 selection compiled) "preflight"
  let plan ← expectPlanOk
    (deriveSolanaCpiPlanFromPreflightV1 preflight) "derive plan"
  let escrowIr ← expectPlanOk (resolveSolanaCpiEscrowIRV1 plan) "Escrow IR"
  let assembly ← expectPlanOk (emitCpiEscrowSbpfV1 escrowIr) "Escrow emitter"
  pure (compiled, plan, escrowIr, assembly)

private def requireHandler
    (handlers : Array CpiEscrowHandlerIRV1) (name : String) :
    IO CpiEscrowHandlerIRV1 := do
  match handlers.find? (·.name == name) with
  | some h => pure h
  | none => throw <| IO.userError s!"handler '{name}' missing"

/-- Collect every invoke with body index (not find-first). -/
private def collectInvokes
    (h : CpiEscrowHandlerIRV1) : Array (Nat × CpiEscrowInvokeV1) :=
  Id.run do
    let mut out : Array (Nat × CpiEscrowInvokeV1) := #[]
    for (op, i) in h.bodyOps.zipIdx do
      match op with
      | .invokeEscrow inv => out := out.push (i, inv)
      | _ => pure ()
    pure out

private def collectAdds (h : CpiEscrowHandlerIRV1) : Array Nat :=
  Id.run do
    let mut out : Array Nat := #[]
    for (op, i) in h.bodyOps.zipIdx do
      match op with
      | .checkedAddU64 .. => out := out.push i
      | _ => pure ()
    pure out

private def collectStores (h : CpiEscrowHandlerIRV1) : Array Nat :=
  Id.run do
    let mut out : Array Nat := #[]
    for (op, i) in h.bodyOps.zipIdx do
      match op with
      | .stateStoreU64 .. => out := out.push i
      | _ => pure ()
    pure out

/-- Every invoke must be immediately preceded by siteArgChecks→siteChecks
    with matching site ids. -/
private def assertAdjacentChecks (h : CpiEscrowHandlerIRV1) : IO Unit := do
  for i in [0:h.bodyOps.size] do
    match h.bodyOps[i]! with
    | .invokeEscrow inv =>
        expect (i ≥ 2) s!"{h.name}: invoke at {i} lacks preceding ops"
        match h.bodyOps[i - 2]!, h.bodyOps[i - 1]! with
        | .siteArgChecks sid0 _, .siteChecks sid1 _ =>
            expect (sid0 == inv.siteId && sid1 == inv.siteId)
              s!"{h.name}: site id mismatch around invoke site={inv.siteId}"
        | _, _ =>
            throw <| IO.userError
              s!"{h.name}: invoke site={inv.siteId} not preceded by siteArgChecks→siteChecks"
    | _ => pure ()

/-- Assert single-CPI overflow order: add→store→invoke→add→store. -/
private def assertSingleCpiOverflowOrder
    (h : CpiEscrowHandlerIRV1) (label : String) : IO Unit := do
  let adds := collectAdds h
  let stores := collectStores h
  let invs := collectInvokes h
  expect (adds.size == 2 && stores.size == 2 && invs.size == 1)
    s!"{label}: expected 2 adds/2 stores/1 invoke, got {adds.size}/{stores.size}/{invs.size}"
  let some (invPos, _) := invs[0]? |
    throw <| IO.userError s!"{label}: invoke missing"
  let some a0 := adds[0]? | throw <| IO.userError s!"{label}: add0"
  let some a1 := adds[1]? | throw <| IO.userError s!"{label}: add1"
  let some s0 := stores[0]? | throw <| IO.userError s!"{label}: store0"
  let some s1 := stores[1]? | throw <| IO.userError s!"{label}: store1"
  expect (a0 < s0 && s0 < invPos && invPos < a1 && a1 < s1)
    s!"{label}: must execute CPI between first commit and failing checked add"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let (compiled, plan, resolved, assembly) ← fullChain session
  let candidate := ResolvedSolanaCpiEscrowIRV1.candidateOf resolved
  expect (candidate.schema == escrowIrSchemaV1) "Escrow IR schema"

  -- Dense 10 handlers exact source order (fixture comment authority).
  let expectedNames : Array String := #[
    "init", "initializeVault", "deposit", "release", "refund",
    "initializeThenOverflow", "depositThenOverflow", "releaseThenOverflow",
    "refundThenOverflow", "inspect"
  ]
  expect (candidate.handlers.size == 10)
    s!"expected 10 handlers, got {candidate.handlers.size}"
  for i in [0:expectedNames.size] do
    let some h := candidate.handlers[i]? |
      throw <| IO.userError s!"handler index {i} missing"
    let some want := expectedNames[i]? |
      throw <| IO.userError s!"expectedNames index {i} missing"
    expect (h.name == want && h.handlerId == i)
      s!"handler[{i}] expected id={i} name={want}, got id={h.handlerId} name={h.name}"

  -- Caller program id pin (runtime Mollusk key; assembly reads ABIv1 program id).
  expect (escrowCallerProgramIdBytesV1.size == 32 &&
      escrowCallerProgramIdBytesV1.all (· == UInt8.ofNat 0x59))
    "caller program id pin is [0x59; 32]"

  for h in candidate.handlers do
    assertAdjacentChecks h

  ------------------------------------------------------------------
  -- initializeVault: exact two invokes System then ATA
  ------------------------------------------------------------------
  let vaultH ← requireHandler candidate.handlers "initializeVault"
  expect (vaultH.localRoleCount == 9)
    s!"initializeVault localRoleCount must be 9, got {vaultH.localRoleCount}"
  let vaultInvs := collectInvokes vaultH
  expect (vaultInvs.size == 2)
    s!"initializeVault must have exactly 2 invokes, got {vaultInvs.size}"
  let some (sysPos, sysInv) := vaultInvs[0]? |
    throw <| IO.userError "initializeVault missing System invoke"
  let some (ataPos, ataInv) := vaultInvs[1]? |
    throw <| IO.userError "initializeVault missing ATA invoke"
  expect (sysPos < ataPos) "initializeVault System invoke before ATA invoke"
  expect (sysInv.kind == CpiEscrowKindV1.createPdaAccount &&
      sysInv.qn == "solana.system.createPdaAccount" &&
      sysInv.packageId == "system-v1" && sysInv.dataLen == 52 &&
      sysInv.metas.size == 2 && sysInv.outerOnly.size == 1 &&
      sysInv.signerGroupId == some 0 &&
      sysInv.pdaRule == some "current-program-tagged-v1")
    "initializeVault first invoke exact System createPdaAccount contract"
  expect (ataInv.kind == CpiEscrowKindV1.createIdempotent &&
      ataInv.qn == "solana.ata.createIdempotent" &&
      ataInv.packageId == "ata-classic-v1" && ataInv.dataLen == 1 &&
      ataInv.metas.size == 6 && ataInv.outerOnly.isEmpty &&
      ataInv.signerGroupId.isNone &&
      ataInv.pdaRule == some "ata-classic-v1")
    "initializeVault second invoke exact ATA createIdempotent contract"
  -- Independent adjacent checks per invoke; site ids strict increasing.
  expect (sysInv.siteId < ataInv.siteId)
    s!"initializeVault site ids must increase: {sysInv.siteId} < {ataInv.siteId}"
  -- Match Plan cpiSiteIds order for this handler.
  let planCand := SolanaCpiPreflightPlanV1.candidateOf plan
  let some planVault := planCand.handlers.find? (·.name == "initializeVault") |
    throw <| IO.userError "plan initializeVault missing"
  expect (planVault.cpiSiteIds.size == 2)
    s!"plan initializeVault cpiSiteIds size, got {planVault.cpiSiteIds.size}"
  let some planSid0 := planVault.cpiSiteIds[0]? |
    throw <| IO.userError "plan cpiSiteIds[0] missing"
  let some planSid1 := planVault.cpiSiteIds[1]? |
    throw <| IO.userError "plan cpiSiteIds[1] missing"
  expect (planSid0 == sysInv.siteId && planSid1 == ataInv.siteId)
    s!"initializeVault body site ids must equal Plan cpiSiteIds {planVault.cpiSiteIds}"

  -- Cross-site Principal joins: System payer == ATA payer; System PDA == ATA wallet.
  let some sysPayer := sysInv.payer |
    throw <| IO.userError "System createPda missing payer"
  let some sysPda := sysInv.pda |
    throw <| IO.userError "System createPda missing pda"
  let some ataPayer := ataInv.payer |
    throw <| IO.userError "ATA createIdempotent missing payer"
  let some ataWallet := ataInv.wallet |
    throw <| IO.userError "ATA createIdempotent missing wallet"
  let some ataTarget := ataInv.ata |
    throw <| IO.userError "ATA createIdempotent missing ata"
  let some ataMint := ataInv.mint |
    throw <| IO.userError "ATA createIdempotent missing mint"
  let some ataSysLocal := ataInv.systemProgramLocalIndex |
    throw <| IO.userError "ATA missing systemProgramLocalIndex"
  let some ataTokLocal := ataInv.tokenProgramLocalIndex |
    throw <| IO.userError "ATA missing tokenProgramLocalIndex"
  expect (sysPayer.roleId == ataPayer.roleId &&
      sysPayer.localIndex == ataPayer.localIndex)
    "initializeVault System payer joins ATA payer (roleId/localIndex)"
  expect (sysPda.roleId == ataWallet.roleId &&
      sysPda.localIndex == ataWallet.localIndex)
    "initializeVault System PDA joins ATA wallet (authorityPda)"
  -- ATA target / mint / fixed programs exact shape.
  expect (ataTarget.localIndex < vaultH.localRoleCount &&
      ataMint.localIndex < vaultH.localRoleCount &&
      ataInv.programLocalIndex < vaultH.localRoleCount &&
      ataSysLocal < vaultH.localRoleCount &&
      ataTokLocal < vaultH.localRoleCount)
    "ATA target/mint/fixed locals in range"
  let some ataProgRole := vaultH.localRoleOrder[ataInv.programLocalIndex]? |
    throw <| IO.userError "ATA program role missing"
  let some sysRole := vaultH.localRoleOrder[ataSysLocal]? |
    throw <| IO.userError "System fixed role missing"
  let some tokRole := vaultH.localRoleOrder[ataTokLocal]? |
    throw <| IO.userError "Token fixed role missing"
  match ataProgRole.keyPolicy, sysRole.keyPolicy, tokRole.keyPolicy with
  | .fixedProgram "ata-classic-v1", .fixedProgram "system-v1",
      .fixedProgram "token-classic-v1" => pure ()
  | _, _, _ =>
      throw <| IO.userError
        "ATA fixed-program roles must be ata-classic-v1/system-v1/token-classic-v1"

  -- Happy initialize: first store before both CPIs; second store after both.
  let vaultAdds := collectAdds vaultH
  let vaultStores := collectStores vaultH
  expect (vaultAdds.size == 2 && vaultStores.size == 2)
    "initializeVault exact 2 adds / 2 stores"
  let some a0 := vaultAdds[0]? | throw <| IO.userError "vault add0"
  let some a1 := vaultAdds[1]? | throw <| IO.userError "vault add1"
  let some s0 := vaultStores[0]? | throw <| IO.userError "vault store0"
  let some s1 := vaultStores[1]? | throw <| IO.userError "vault store1"
  expect (a0 < s0 && s0 < sysPos && sysPos < ataPos && ataPos < a1 && a1 < s1)
    "initializeVault: first commit, System+ATA CPI, then post-CPI second store"

  ------------------------------------------------------------------
  -- deposit / release / refund contracts + role counts
  ------------------------------------------------------------------
  let depH ← requireHandler candidate.handlers "deposit"
  expect (depH.localRoleCount == 6)
    s!"deposit localRoleCount must be 6, got {depH.localRoleCount}"
  let depInvs := collectInvokes depH
  expect (depInvs.size == 1) "deposit exactly one invoke"
  let some (_, depInv) := depInvs[0]? |
    throw <| IO.userError "deposit invoke missing"
  expect (depInv.kind == CpiEscrowKindV1.transferChecked &&
      depInv.qn == "solana.token.transferChecked" &&
      depInv.packageId == "token-classic-v1" && depInv.dataLen == 10 &&
      depInv.metas.size == 4 && depInv.signerGroupId.isNone)
    "deposit exact transferChecked contract"
  let some m0 := depInv.metas[0]? | throw <| IO.userError "deposit meta0"
  let some m3 := depInv.metas[3]? | throw <| IO.userError "deposit meta3"
  expect (m0.cpiWritable == true && m0.cpiSigner == false &&
      m3.cpiWritable == false && m3.cpiSigner == true)
    "deposit meta writable/signer flags"

  let relH ← requireHandler candidate.handlers "release"
  expect (relH.localRoleCount == 7)
    s!"release localRoleCount must be 7, got {relH.localRoleCount}"
  let relInvs := collectInvokes relH
  expect (relInvs.size == 1) "release exactly one invoke"
  let some (_, relInv) := relInvs[0]? |
    throw <| IO.userError "release invoke missing"
  expect (relInv.kind == CpiEscrowKindV1.transferCheckedPda &&
      relInv.qn == "solana.token.transferCheckedPda" &&
      relInv.packageId == "token-classic-v1" && relInv.dataLen == 10 &&
      relInv.signerGroupId == some 0 &&
      relInv.pdaRule == some "current-program-tagged-v1" &&
      relInv.outerOnly.size == 1)
    "release exact transferCheckedPda contract"

  let refH ← requireHandler candidate.handlers "refund"
  expect (refH.localRoleCount == 7)
    s!"refund localRoleCount must be 7, got {refH.localRoleCount}"
  let refInvs := collectInvokes refH
  expect (refInvs.size == 1) "refund exactly one invoke"
  let some (_, refInv) := refInvs[0]? |
    throw <| IO.userError "refund invoke missing"
  expect (refInv.kind == CpiEscrowKindV1.transferCheckedPda &&
      refInv.qn == "solana.token.transferCheckedPda" &&
      refInv.packageId == "token-classic-v1" && refInv.dataLen == 10 &&
      refInv.signerGroupId == some 0 &&
      refInv.pdaRule == some "current-program-tagged-v1")
    "refund exact transferCheckedPda contract"

  ------------------------------------------------------------------
  -- *ThenOverflow rollback order static forcing
  ------------------------------------------------------------------
  let initOv ← requireHandler candidate.handlers "initializeThenOverflow"
  let initOvAdds := collectAdds initOv
  let initOvStores := collectStores initOv
  let initOvInvs := collectInvokes initOv
  expect (initOvAdds.size == 2 && initOvStores.size == 2 && initOvInvs.size == 2)
    s!"initializeThenOverflow: expected 2 adds/2 stores/2 invokes, got {initOvAdds.size}/{initOvStores.size}/{initOvInvs.size}"
  let some (initOvSysPos, initOvSysInv) := initOvInvs[0]? |
    throw <| IO.userError "initializeThenOverflow System invoke missing"
  let some (initOvAtaPos, initOvAtaInv) := initOvInvs[1]? |
    throw <| IO.userError "initializeThenOverflow ATA invoke missing"
  expect (initOvSysInv.kind == CpiEscrowKindV1.createPdaAccount &&
      initOvAtaInv.kind == CpiEscrowKindV1.createIdempotent)
    "initializeThenOverflow invoke kinds [createPdaAccount, createIdempotent]"
  let some oa0 := initOvAdds[0]? | throw <| IO.userError "initOv add0"
  let some oa1 := initOvAdds[1]? | throw <| IO.userError "initOv add1"
  let some os0 := initOvStores[0]? | throw <| IO.userError "initOv store0"
  let some os1 := initOvStores[1]? | throw <| IO.userError "initOv store1"
  expect (oa0 < os0 && os0 < initOvSysPos &&
      initOvSysPos < initOvAtaPos &&
      initOvAtaPos < oa1 && oa1 < os1)
    "initializeThenOverflow: add→store→System→ATA→add→store"

  let depOv ← requireHandler candidate.handlers "depositThenOverflow"
  assertSingleCpiOverflowOrder depOv "depositThenOverflow"
  let some (_, depOvInv) := (collectInvokes depOv)[0]? |
    throw <| IO.userError "depositThenOverflow invoke"
  expect (depOvInv.kind == CpiEscrowKindV1.transferChecked)
    "depositThenOverflow invoke kind"
  let relOv ← requireHandler candidate.handlers "releaseThenOverflow"
  assertSingleCpiOverflowOrder relOv "releaseThenOverflow"
  let some (_, relOvInv) := (collectInvokes relOv)[0]? |
    throw <| IO.userError "releaseThenOverflow invoke"
  expect (relOvInv.kind == CpiEscrowKindV1.transferCheckedPda)
    "releaseThenOverflow invoke kind"
  let refOv ← requireHandler candidate.handlers "refundThenOverflow"
  assertSingleCpiOverflowOrder refOv "refundThenOverflow"
  let some (_, refOvInv) := (collectInvokes refOv)[0]? |
    throw <| IO.userError "refundThenOverflow invoke"
  expect (refOvInv.kind == CpiEscrowKindV1.transferCheckedPda)
    "refundThenOverflow invoke kind"

  ------------------------------------------------------------------
  -- Assembly surface + boundary
  ------------------------------------------------------------------
  let text := SolanaCpiEscrowAssemblyV1.textOf assembly
  expect (hasSubstr text "proof-forge solana composite escrow CPI SBPF (#124)")
    "escrow #124 assembly header (not Token #122)"
  expect (!hasSubstr text "cpi token SBPF (#122)")
    "must not retain Token #122 header"
  expect (hasSubstr text "call sol_invoke_signed_c") "assembly invoke"
  expect (hasSubstr text "call sol_set_return_data") "assembly return data"
  expect (hasSubstr text "call sol_try_find_program_address") "assembly find PDA"
  expect (hasSubstr text "0x0c") "TransferChecked tag"
  expect (hasSubstr text "stxb [r9 + 0], r4                  ; CreateIdempotent")
    "ATA data byte 01"
  expect (hasSubstr text "SystemInstruction::CreateAccount") "System create disc"
  expect (hasSubstr text "ataAddressCanonical seeds=[wallet,classicToken,mint]")
    "ATA seed banner"
  expect (hasSubstr text "ataAccountPrestateClosed") "ATA prestate"
  expect (hasSubstr text "tokenAccountStateInitialized") "Token field checks"
  expect (hasSubstr text "TEST-PREACTIVATION ONLY") "preactivation banner"
  expect (hasSubstr text "not a product artifact") "product boundary banner"
  expect (!hasSubstr text "0xec01" && !hasSubstr text "ACC0_" &&
      !hasSubstr text "callx") "no legacy/indirect call surface"
  expect (!SolanaCpiEscrowAssemblyV1.isProductArtifact assembly &&
      SolanaCpiEscrowAssemblyV1.isTestPreactivation assembly)
    "test-preactivation assembly boundary"
  expect (SolanaCpiEscrowAssemblyV1.frameBytesOf assembly ≤ 4096) "frame ≤ 4096"
  let setCalls := countSubstr text "call sol_set_return_data"
  let checkedSetCalls := countSubstr text
    "call sol_set_return_data\n  jne r0, 0, cpi_failed"
  expect (setCalls == checkedSetCalls) "every return-data clear propagates status"
  expect (hasSubstr text "call sol_invoke_signed_c\n  jne r0, 0, cpi_failed")
    "invoke status must propagate"
  expect (hasSubstr text "jeq r4, 0, err_shape") "runtime bump-zero reject"

  -- Frame / scratch: exclusive-end maxScratch may be non-8-aligned (createPda
  -- 289+56N). Emitter aligns reserve and CPI_BASE to 8 so invoke pointers are
  -- aligned. Formula must match EmitCpiEscrowSbpfV1 exactly.
  let alignUp8 (n : Nat) : Nat := ((n + 7) / 8) * 8
  let createPdaScratch :=
    escrowCpiScratchCreatePdaAccountV1 sysInv.accountInfoCount
  expect (createPdaScratch == 289 + sysInv.accountInfoCount * 56)
    s!"createPda scratch exclusive end must be 289+56N, got {createPdaScratch}"
  -- bumpOut offset + 1 is covered by the exclusive-end formula (and by reserve).
  let bumpOutOff := 288 + sysInv.accountInfoCount * 56
  expect (bumpOutOff + 1 == createPdaScratch)
    "createPda bumpOut offset+1 must equal scratch exclusive end"
  let maxScratch := escrowMaxSiteScratchV1 candidate
  let expectedMax :=
    Nat.max createPdaScratch
      (Nat.max (escrowCpiScratchCreateIdempotentV1 ataInv.accountInfoCount)
        (Nat.max (escrowCpiScratchTransferCheckedV1 depInv.accountInfoCount)
          (escrowCpiScratchTransferCheckedPdaV1 relInv.accountInfoCount)))
  expect (maxScratch == expectedMax)
    s!"max scratch {maxScratch} must equal computed family max {expectedMax}"
  -- Real fixture N=9 → maxScratch 793 → reserve 800 → CPI_BASE 2024 → frame 2824.
  expect (maxScratch == 793)
    s!"real fixture maxScratch expected 793 (createPda 289+56*9), got {maxScratch}"
  expect (createPdaScratch ≤ maxScratch)
    "createPda exclusive end covered by maxScratch/reserve"
  let reserve := alignUp8 (Nat.max maxScratch 240)
  let cpiBase :=
    alignUp8 (Nat.max escrowCpiBaseMinV1 (escrowTempRegionEndV1 + reserve))
  expect (reserve % 8 == 0 && cpiBase % 8 == 0)
    s!"scratchReserve/CPI_BASE must be 8-aligned, got {reserve}/{cpiBase}"
  expect (createPdaScratch ≤ reserve)
    s!"bumpOut exclusive end {createPdaScratch} must fit in aligned reserve {reserve}"
  expect (cpiBase ≥ escrowTempRegionEndV1 + reserve)
    "CPI_BASE places scratch after temp region (no overlap)"
  let expectedFrame := cpiBase + reserve
  expect (reserve == 800 && cpiBase == 2024 && expectedFrame == 2824)
    s!"aligned frame triple reserve/base/frame expected 800/2024/2824, got {reserve}/{cpiBase}/{expectedFrame}"
  expect (SolanaCpiEscrowAssemblyV1.frameBytesOf assembly == expectedFrame &&
      SolanaCpiEscrowAssemblyV1.frameBytesOf assembly ≤ escrowMaxFrameBytesV1)
    s!"Escrow frame exact {expectedFrame} and within 4096"
  expect (hasSubstr text s!".equ CPI_BASE, {cpiBase}")
    s!"emitted CPI_BASE equ matches computed {cpiBase}"
  expect (hasSubstr text s!"; Handlers: 10; frameBytes={expectedFrame}")
    s!"header frameBytes={expectedFrame}"

  -- Package identities remain exact deny-state dependencies.
  for (id, key, cls) in #[
      ("ata-classic-v1", ataClassicProgramIdV1, ExecutionClass.loaderV3Sbpf),
      ("token-classic-v1", tokenClassicProgramIdV1, ExecutionClass.loaderV3Sbpf),
      ("system-v1", systemProgramIdV1, ExecutionClass.nativeSystem)] do
    let some package := findCalleePackage? id |
      throw <| IO.userError s!"missing package {id}"
    expect (package.programId == key && package.executionClass == cls &&
        package.admittedForMaterialization == false)
      s!"package {id} exact identity + denied admission"

  -- Leaf IR lanes reject the composite multi-family plan.
  let selection ← cpiSelection
  expectPlanReject (resolveSolanaCpiTokenIRV1 plan)
    "Token IR rejects multi-family escrow"
  expectPlanReject (resolveSolanaCpiSystemIRV1 plan)
    "System IR rejects multi-family escrow"
  expectPlanReject (resolveSolanaCpiAtaIRV1 plan)
    "ATA IR rejects multi-family escrow"
  expectPlanReject (resolveSolanaCpiPreflightIRV1 plan)
    "generic preflight IR rejects composite escrow data"

  -- #125: ordinary product capability admits sync; approved composite Escrow
  -- closure further mints product Plan/IR. Preactivation lane above remains
  -- independent (isProductArtifact=false / assembly sha pins retained).
  let capability ← expectPlanOk
    (resolveEngineeringRequirementsV1 selection compiled)
    "ordinary resolver admits EscrowCpi sync"
  let _ ← expectPlanOk (productPlanFromCapabilityV1 capability)
    "product Plan succeeds for EscrowCpi"
  let _ ← expectPlanOk (productIrFromCapabilityV1 capability)
    "product IR succeeds for EscrowCpi"

  match validateSolanaCpiEscrowIRCandidateV1 candidate with
  | .ok () => pure ()
  | .error error =>
      throw <| IO.userError s!"pristine escrow candidate: {error.render}"

  -- Public candidate mutation: drop ATA address-check → validator reject.
  let dropAddressChecks (body : Array CpiEscrowBodyOpV1) :
      Array CpiEscrowBodyOpV1 :=
    body.map fun op =>
      match op with
      | .siteChecks sid checks =>
          .siteChecks sid (checks.filter fun
            | .ataAddressCanonical .. => false
            | .ataAccountPrestateClosed .. => true
            | .tokenAccountStateInitialized _ => true
            | .tokenAccountMintEqualsRole .. => true
            | .tokenAccountOwnerEqualsRole .. => true
            | .tokenAccountDelegateNone _ => true
            | .tokenMintInitialized _ => true
            | .tokenMintDecimalsEquals .. => true
            | .generic _ => true)
      | .siteArgChecks sid c => .siteArgChecks sid c
      | .invokeEscrow inv => .invokeEscrow inv
      | .loadParamU64 t o => .loadParamU64 t o
      | .loadParamU8 t o => .loadParamU8 t o
      | .loadLiteralU64 t v => .loadLiteralU64 t v
      | .loadLiteralU8 t v => .loadLiteralU8 t v
      | .stateLoadU64 t li o => .stateLoadU64 t li o
      | .checkedAddU64 d l r => .checkedAddU64 d l r
      | .stateStoreU64 li o s wm m => .stateStoreU64 li o s wm m
      | .envReadVaultBalance t k v va m s tk a =>
          .envReadVaultBalance t k v va m s tk a
      | .returnU64 t => .returnU64 t
      | .returnNone => .returnNone
  let vaultH' : CpiEscrowHandlerIRV1 := {
    handlerId := vaultH.handlerId
    callableId := vaultH.callableId
    name := vaultH.name
    mode := vaultH.mode
    localRoleCount := vaultH.localRoleCount
    localRoleOrder := vaultH.localRoleOrder
    accountParameterBindings := vaultH.accountParameterBindings
    probeIxDataLen := vaultH.probeIxDataLen
    entryGlobalOps := vaultH.entryGlobalOps
    bodyOps := dropAddressChecks vaultH.bodyOps
    tempCount := vaultH.tempCount
  }
  let candMut : SolanaCpiEscrowIRCandidateV1 := {
    schema := candidate.schema
    sourcePlanDigest := candidate.sourcePlanDigest
    sourceIrDigest := candidate.sourceIrDigest
    profileId := candidate.profileId
    profileDigest := candidate.profileDigest
    catalogDigest := candidate.catalogDigest
    abiLayout := candidate.abiLayout
    maxOuterRoles := candidate.maxOuterRoles
    maxFrameBytes := candidate.maxFrameBytes
    handlers := candidate.handlers.map fun h =>
      if h.handlerId == vaultH.handlerId then vaultH' else h
  }
  expectPlanReject (validateSolanaCpiEscrowIRCandidateV1 candMut)
    "missing ATA address-check must fail validateSolanaCpiEscrowIRCandidateV1"

  -- Public candidate mutation: corrupt createIdempotent dataLen.
  let bumpAtaDataLen (body : Array CpiEscrowBodyOpV1) :
      Array CpiEscrowBodyOpV1 :=
    body.map fun op =>
      match op with
      | .invokeEscrow inv =>
          if inv.kind == CpiEscrowKindV1.createIdempotent then
            .invokeEscrow {
              siteId := inv.siteId
              kind := inv.kind
              qn := inv.qn
              packageId := inv.packageId
              programLocalIndex := inv.programLocalIndex
              dataLen := 2
              source := inv.source
              mint := inv.mint
              destination := inv.destination
              authority := inv.authority
              authorityPda := inv.authorityPda
              seedAuthority := inv.seedAuthority
              payer := inv.payer
              pda := inv.pda
              ata := inv.ata
              wallet := inv.wallet
              seedTag := inv.seedTag
              bump := inv.bump
              amount := inv.amount
              decimals := inv.decimals
              lamports := inv.lamports
              space := inv.space
              systemProgramLocalIndex := inv.systemProgramLocalIndex
              tokenProgramLocalIndex := inv.tokenProgramLocalIndex
              metas := inv.metas
              outerOnly := inv.outerOnly
              signerGroupId := inv.signerGroupId
              pdaRule := inv.pdaRule
              accountInfoCount := inv.accountInfoCount
            }
          else .invokeEscrow inv
      | .siteArgChecks sid c => .siteArgChecks sid c
      | .siteChecks sid c => .siteChecks sid c
      | .loadParamU64 t o => .loadParamU64 t o
      | .loadParamU8 t o => .loadParamU8 t o
      | .loadLiteralU64 t v => .loadLiteralU64 t v
      | .loadLiteralU8 t v => .loadLiteralU8 t v
      | .stateLoadU64 t li o => .stateLoadU64 t li o
      | .checkedAddU64 d l r => .checkedAddU64 d l r
      | .stateStoreU64 li o s wm m => .stateStoreU64 li o s wm m
      | .envReadVaultBalance t k v va m s tk a =>
          .envReadVaultBalance t k v va m s tk a
      | .returnU64 t => .returnU64 t
      | .returnNone => .returnNone
  let vaultH2 : CpiEscrowHandlerIRV1 := {
    handlerId := vaultH.handlerId
    callableId := vaultH.callableId
    name := vaultH.name
    mode := vaultH.mode
    localRoleCount := vaultH.localRoleCount
    localRoleOrder := vaultH.localRoleOrder
    accountParameterBindings := vaultH.accountParameterBindings
    probeIxDataLen := vaultH.probeIxDataLen
    entryGlobalOps := vaultH.entryGlobalOps
    bodyOps := bumpAtaDataLen vaultH.bodyOps
    tempCount := vaultH.tempCount
  }
  let candMut2 : SolanaCpiEscrowIRCandidateV1 := {
    schema := candidate.schema
    sourcePlanDigest := candidate.sourcePlanDigest
    sourceIrDigest := candidate.sourceIrDigest
    profileId := candidate.profileId
    profileDigest := candidate.profileDigest
    catalogDigest := candidate.catalogDigest
    abiLayout := candidate.abiLayout
    maxOuterRoles := candidate.maxOuterRoles
    maxFrameBytes := candidate.maxFrameBytes
    handlers := candidate.handlers.map fun h =>
      if h.handlerId == vaultH.handlerId then vaultH2 else h
  }
  expectPlanReject (validateSolanaCpiEscrowIRCandidateV1 candMut2)
    "mutated ATA dataLen must fail validateSolanaCpiEscrowIRCandidateV1"

  ------------------------------------------------------------------
  -- UInt8 checked-add must fail closed at Escrow IR (not typecheck/parser).
  -- Include a real Token CPI so preflight/Plan accept effect.synchronous-call;
  -- body still materialises anonymous UInt8 add before the ExternalCall.
  ------------------------------------------------------------------
  let u8Source : String :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program EscrowU8Add where\n" ++
    "  requires extension solana.cpi.accounts version \"1.0.0\"\n" ++
    "    digest \"sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020\"\n" ++
    "  state value : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    value := initial\n" ++
    "  entry u8AddThenDeposit(\n" ++
    "      a : UInt8,\n" ++
    "      b : UInt8,\n" ++
    "      source : Principal,\n" ++
    "      mint : Principal,\n" ++
    "      destination : Principal,\n" ++
    "      authority : Principal,\n" ++
    "      amount : UInt64,\n" ++
    "      decimals : UInt8\n" ++
    "  ) : UInt8 do\n" ++
    "    let s : UInt8 := a + b\n" ++
    "    call solana.token.transferChecked(\n" ++
    "      source, mint, destination, authority, amount, decimals)\n" ++
    "    return s\n" ++
    "  view inspect() : UInt64 do\n" ++
    "    return value\n"
  let (u8src, u8origins) ← match ← session.selectProgramV1WithOrigins
      u8Source "runtime-tests/solana/fixtures/EscrowU8Add.lean"
      "Examples.EscrowU8Add" none with
    | .ok pair => pure pair
    | .error error =>
        throw <| IO.userError s!"load UInt8-add source: {error.render}"
  let u8compiled ← match Compiler.compileProgramProductV1 u8src u8origins with
    | .ok c => pure c
    | .error _ =>
        throw <| IO.userError
          "product compile must accept UInt8 add + deposit entry (gate is Escrow IR)"
  let u8selection ← cpiSelection
  let u8preflight ← expectPlanOk
    (resolveSolanaCpiPreflightV1 u8selection u8compiled)
    "UInt8-add preflight must succeed"
  let u8plan ← expectPlanOk
    (deriveSolanaCpiPlanFromPreflightV1 u8preflight)
    "UInt8-add plan must succeed"
  expectPlanReject (resolveSolanaCpiEscrowIRV1 u8plan)
    "UInt8 checked-add must PF-PLAN-INVARIANT at Escrow IR mint"

  IO.println "Tests.Materialization.SolanaCpiEscrowV1: ok"

end Tests.Materialization.SolanaCpiEscrowV1
