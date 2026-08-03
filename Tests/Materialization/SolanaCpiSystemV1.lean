/-
  Tests.Materialization.SolanaCpiSystemV1 — #121 System CPI IR/emitter.

  Authority path:
  Loader → product compile → preflight capability → Semantic Plan
  → System IR (from SolanaCpiPreflightPlanV1; NOT ResolvedSolanaCpiPreflightIRV1)
  → System emitter.

  Pins: system.transfer / createPdaAccount only, 12/52 codecs, metas/roles,
  space 4096/4097, bump0, canonical signer seam, frame cap, siteArgChecks →
  siteChecks → invoke order, old-lane rejection independence, ordinary
  resolver PF-REQ-UNSUPPORTED.
-/
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiIRV1
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiPreflightIRV1
import ProofForgeV2.Targets.Solana.CpiPdaIRV1
import ProofForgeV2.Targets.Solana.CpiUnsignedIRV1
import ProofForgeV2.Targets.Solana.CpiSystemIRV1
import ProofForgeV2.Targets.Solana.EmitCpiSystemSbpfV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.Materialization.SolanaCpiSystemV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Compiler
open ProofForgeV2.Targets
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Solana.CpiV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectPlanOk {α : Type} (result : CompileResult α)
    (label : String) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def expectPlanRejectContains {α : Type} (result : CompileResult α)
    (needle label : String) : IO Unit :=
  match result with
  | .error error =>
      expect (error.code == "PF-PLAN-INVARIANT" && error.message.contains needle)
        s!"{label}: expected PF-PLAN-INVARIANT containing '{needle}', got {error.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly accepted"

private def hasSubstr (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

private def countSubstr (haystack needle : String) : Nat :=
  (haystack.splitOn needle).length - 1

private def extensionHeader : String :=
  "  requires extension solana.cpi.accounts version \"1.0.0\"\n" ++
  "    digest \"sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020\"\n"

private def wrapProgram (name body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  s!"program {name} where\n" ++
  extensionHeader ++
  body

/-- Combined transfer + createPda fixture with state mutation. -/
private def systemCpiSource : String :=
  wrapProgram "SystemCpi" <|
    "  state value : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    value := initial\n" ++
    "  entry transferOnce(payer : Principal, recipient : Principal,\n" ++
    "      lamports : UInt64) : UInt64 do\n" ++
    "    value := value + 1\n" ++
    "    call solana.system.transfer(payer, recipient, lamports)\n" ++
    "    value := value + 2\n" ++
    "    return value\n" ++
    "  entry createOnce(payer : Principal, pda : Principal,\n" ++
    "      seedAuthority : Principal, seedTag : UInt64, bump : UInt8,\n" ++
    "      lamports : UInt64, space : UInt64) : UInt64 do\n" ++
    "    value := value + 1\n" ++
    "    call solana.system.createPdaAccount(payer, pda, seedAuthority,\n" ++
    "      seedTag, bump, lamports, space)\n" ++
    "    value := value + 2\n" ++
    "    return value\n" ++
    "  view inspect() : UInt64 do\n" ++
    "    return value\n"

private def transferOnlySource : String :=
  wrapProgram "SystemTransferOnly" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry transfer(payer : Principal, recipient : Principal,\n" ++
    "      lamports : UInt64) : UInt64 do\n" ++
    "    call solana.system.transfer(payer, recipient, lamports)\n" ++
    "    return 0\n"

private def createSpace4096Source : String :=
  wrapProgram "SystemCreateSpaceOk" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry create(payer : Principal, pda : Principal,\n" ++
    "      seedAuthority : Principal, seedTag : UInt64, bump : UInt8,\n" ++
    "      lamports : UInt64) : UInt64 do\n" ++
    "    let space : UInt64 := 4096\n" ++
    "    call solana.system.createPdaAccount(payer, pda, seedAuthority,\n" ++
    "      seedTag, bump, lamports, space)\n" ++
    "    return 0\n"

private def createSpace4097Source : String :=
  wrapProgram "SystemCreateSpaceOver" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry create(payer : Principal, pda : Principal,\n" ++
    "      seedAuthority : Principal, seedTag : UInt64, bump : UInt8,\n" ++
    "      lamports : UInt64) : UInt64 do\n" ++
    "    let space : UInt64 := 4097\n" ++
    "    call solana.system.createPdaAccount(payer, pda, seedAuthority,\n" ++
    "      seedTag, bump, lamports, space)\n" ++
    "    return 0\n"

private def bumpZeroSource : String :=
  wrapProgram "SystemBumpZero" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry create(payer : Principal, pda : Principal,\n" ++
    "      seedAuthority : Principal, seedTag : UInt64, lamports : UInt64,\n" ++
    "      space : UInt64) : UInt64 do\n" ++
    "    let bump : UInt8 := 0\n" ++
    "    call solana.system.createPdaAccount(payer, pda, seedAuthority,\n" ++
    "      seedTag, bump, lamports, space)\n" ++
    "    return 0\n"

private def companionSource : String :=
  wrapProgram "SystemRejectCompanion" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry invokeOnce(account : Principal, delta : UInt64) : UInt64 do\n" ++
    "    call solana.companion.invoke(account, delta)\n" ++
    "    return value\n"

private def multiBlockSource : String :=
  wrapProgram "SystemRejectBranch" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry branchy(payer : Principal, recipient : Principal,\n" ++
    "      lamports : UInt64) : UInt64 do\n" ++
    "    if lamports == 0 then\n" ++
    "      value := lamports\n" ++
    "    else\n" ++
    "      value := 1\n" ++
    "    call solana.system.transfer(payer, recipient, lamports)\n" ++
    "    return value\n"

private unsafe def compileSource
    (session : Language.Loader.ParserSession)
    (source moduleName path : String) : IO CompiledSemanticV1 := do
  let (src, origins) ← match ← session.selectProgramV1WithOrigins
      source path moduleName none with
    | .ok pair => pure pair
    | .error error =>
        throw <| IO.userError s!"load {moduleName}: {error.render}"
  match Compiler.compileProgramProductV1 src origins with
  | .ok compiled => pure compiled
  | .error _bundle =>
      throw <| IO.userError s!"compile {moduleName}: product compile failed"

private def cpiSelection : IO ResolvedBuildSelectionV1 :=
  expectPlanOk
    (resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfCpiElfV1))
    "resolve CPI profile"

private unsafe def fullSystemChain
    (session : Language.Loader.ParserSession)
    (source moduleName path : String) :
    IO (ResolvedSolanaCpiSystemIRV1 × SolanaCpiSystemAssemblyV1) := do
  let compiled ← compileSource session source moduleName path
  let selection ← cpiSelection
  let preflight ← expectPlanOk
    (resolveSolanaCpiPreflightV1 selection compiled) "preflight"
  let plan ← expectPlanOk
    (deriveSolanaCpiPlanFromPreflightV1 preflight) "derive plan"
  let sys ← expectPlanOk
    (resolveSolanaCpiSystemIRV1 plan) "system IR"
  let asm ← expectPlanOk
    (emitCpiSystemSbpfV1 sys) "emit system"
  pure (sys, asm)

private unsafe def planOnly
    (session : Language.Loader.ParserSession)
    (source moduleName path : String) : IO SolanaCpiPreflightPlanV1 := do
  let compiled ← compileSource session source moduleName path
  let selection ← cpiSelection
  let preflight ← expectPlanOk
    (resolveSolanaCpiPreflightV1 selection compiled) "preflight"
  expectPlanOk (deriveSolanaCpiPlanFromPreflightV1 preflight) "derive plan"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared

  -- Positive combined chain.
  let (sys, asm) ← fullSystemChain session systemCpiSource
    "Examples.SystemCpi" "runtime-tests/solana/fixtures/SystemCpi.lean"
  let cand := ResolvedSolanaCpiSystemIRV1.candidateOf sys
  expect (cand.schema == systemIrSchemaV1) "schema proof-forge.solana.cpi-system-ir.v1"
  expect (cand.handlers.size == 4)
    "expected 4 handlers (init/transferOnce/createOnce/inspect)"

  -- Strict siteArgChecks → siteChecks → invoke order on every invoke.
  for h in cand.handlers do
    let ops := h.bodyOps
    for i in [0:ops.size] do
      match ops[i]! with
      | .invokeSystem inv =>
          expect (i ≥ 2) s!"{h.name}: invoke without preceding ops"
          match ops[i - 2]!, ops[i - 1]! with
          | .siteArgChecks sidA _, .siteChecks sidC _ =>
              expect (sidA == inv.siteId && sidC == inv.siteId)
                s!"{h.name}: siteArgChecks/siteChecks/invoke site mismatch"
          | _, _ =>
              throw <| IO.userError
                s!"{h.name}: invoke not preceded by siteArgChecks→siteChecks"
      | _ => pure ()

  -- transferOnce exact Plan join / 12B codec / metas.
  let some transferHandler := cand.handlers.find? (fun h => h.name == "transferOnce") |
    throw <| IO.userError "missing transferOnce"
  expect (transferHandler.probeIxDataLen == 16)
    "transfer probe packs handlerId8 + lamports8"
  let some tInv := transferHandler.bodyOps.findSome? (fun
      | .invokeSystem i => some i
      | _ => none) |
    throw <| IO.userError "missing transfer invoke"
  expect (tInv.kind == .transfer && tInv.qn == "solana.system.transfer" &&
      tInv.packageId == "system-v1" && tInv.dataLen == 12)
    "transfer frozen qn/package/dataLen"
  expect (tInv.payer.argIndex == 0 &&
      (match tInv.recipient with | some r => r.argIndex == 1 | none => false))
    "transfer Principal arg indices 0/1"
  expect (tInv.metas.size == 2 && tInv.outerOnly.isEmpty &&
      tInv.signerGroupId.isNone)
    "transfer two metas, zero outer-only, zero signer groups"
  expect (tInv.metas[0]!.roleId == tInv.payer.roleId &&
      tInv.metas[0]!.localIndex == tInv.payer.localIndex &&
      tInv.metas[0]!.cpiWritable == true && tInv.metas[0]!.cpiSigner == true)
    "meta[0] payer writable CPI signer"
  let some recip := tInv.recipient | throw <| IO.userError "recipient missing"
  expect (tInv.metas[1]!.roleId == recip.roleId &&
      tInv.metas[1]!.localIndex == recip.localIndex &&
      tInv.metas[1]!.cpiWritable == true && tInv.metas[1]!.cpiSigner == false)
    "meta[1] recipient writable non-signer"

  -- createOnce exact 52B / PDA signer seam / seedAuthority outer non-signer.
  let some createHandler := cand.handlers.find? (fun h => h.name == "createOnce") |
    throw <| IO.userError "missing createOnce"
  expect (createHandler.probeIxDataLen == 33)
    "create probe packs handlerId8+seedTag8+bump1+lamports8+space8"
  let some cInv := createHandler.bodyOps.findSome? (fun
      | .invokeSystem i => some i
      | _ => none) |
    throw <| IO.userError "missing create invoke"
  expect (cInv.kind == .createPdaAccount &&
      cInv.qn == "solana.system.createPdaAccount" &&
      cInv.packageId == "system-v1" && cInv.dataLen == 52)
    "create frozen qn/package/dataLen"
  expect (cInv.signerGroupId == some 0 &&
      cInv.pdaRule == some "current-program-tagged-v1")
    "create signer group / PDA rule"
  expect (cInv.metas.size == 2 && cInv.outerOnly.size == 1)
    "create two metas + one outer-only"
  let some pdaB := cInv.pda | throw <| IO.userError "pda binding missing"
  let some seedAuth := cInv.seedAuthority |
    throw <| IO.userError "seedAuthority binding missing"
  -- Exact create payer meta flags (CPI; outer writable/signer fixed at project join).
  expect (cInv.metas[0]!.metaIndex == 0 &&
      cInv.metas[0]!.roleId == cInv.payer.roleId &&
      cInv.metas[0]!.localIndex == cInv.payer.localIndex &&
      cInv.metas[0]!.cpiWritable == true &&
      cInv.metas[0]!.cpiSigner == true &&
      cInv.metas[0]!.signerGroupId.isNone)
    "create meta[0] payer: CPI writable+signer, no group, join payer principal"
  -- Exact create PDA meta flags.
  expect (cInv.metas[1]!.metaIndex == 1 &&
      cInv.metas[1]!.roleId == pdaB.roleId &&
      cInv.metas[1]!.localIndex == pdaB.localIndex &&
      cInv.metas[1]!.cpiWritable == true &&
      cInv.metas[1]!.cpiSigner == true &&
      cInv.metas[1]!.signerGroupId == some 0)
    "create meta[1] pda: CPI writable+signer group 0, join pda principal"
  -- Exact seedAuthority outer-only flags (readonly non-signer).
  expect (cInv.outerOnly[0]!.outerOnlyIndex == 0 &&
      cInv.outerOnly[0]!.roleId == seedAuth.roleId &&
      cInv.outerOnly[0]!.localIndex == seedAuth.localIndex &&
      cInv.outerOnly[0]!.outerSigner == false &&
      cInv.outerOnly[0]!.outerWritable == false)
    "create outer-only seedAuthority: readonly non-signer exact"
  -- Create site sequence: siteArgChecks → siteChecks → invoke (same siteId).
  let createOps := createHandler.bodyOps
  let some createInvokeIdx := Id.run (do
      for i in [0:createOps.size] do
        match createOps[i]! with
        | .invokeSystem inv =>
            if inv.siteId == cInv.siteId then return some i
        | _ => pure ()
      return none) |
    throw <| IO.userError "create invoke index missing"
  expect (createInvokeIdx ≥ 2) "create invoke needs two preceding ops"
  match createOps[createInvokeIdx - 2]!, createOps[createInvokeIdx - 1]!,
      createOps[createInvokeIdx]! with
  | .siteArgChecks sidA checks, .siteChecks sidC _, .invokeSystem inv =>
      expect (sidA == cInv.siteId && sidC == cInv.siteId && inv.siteId == cInv.siteId)
        "create siteArgChecks→siteChecks→invoke same siteId"
      expect (checks.size == 1) "create siteArgChecks has one space predicate"
      match checks[0]! with
      | .uint64AtMost name _ maxV =>
          expect (name == "space" && maxV == 4096) "space cap 4096 in siteArgChecks"
  | _, _, _ =>
      throw <| IO.userError "create sequence is not siteArgChecks→siteChecks→invoke"

  let text := SolanaCpiSystemAssemblyV1.textOf asm
  expect (hasSubstr text "call sol_invoke_signed_c")
    "assembly must call sol_invoke_signed_c"
  expect (hasSubstr text "call sol_set_return_data")
    "assembly must call sol_set_return_data"
  expect (hasSubstr text "call sol_try_find_program_address")
    "combined fixture must call find_program_address for create"
  expect (hasSubstr text "0x6f662d666f6f7270") "seed0 limb0"
  expect (hasSubstr text "SEED0_LEN") "seed0 length equ"
  expect (hasSubstr text "MAX_PDA_SPACE") "space cap equ"
  expect (!hasSubstr text "0xec01") "assembly must not contain 0xec01 stub"
  expect (!hasSubstr text "ACC0_") "assembly must not use ACC0 slots"
  expect (!hasSubstr text "callx") "assembly must not use callx"
  expect (hasSubstr text "TEST-PREACTIVATION ONLY") "preactivation banner"
  expect (hasSubstr text "not a product artifact") "product boundary banner"
  expect (hasSubstr text "site-time, not entry-hoisted") "site-time checks comment"
  expect (hasSubstr text "handler_1_transferOnce_system:") "transferOnce label"
  expect (hasSubstr text "handler_2_createOnce_system:") "createOnce label"
  expect (!SolanaCpiSystemAssemblyV1.isProductArtifact asm) "isProductArtifact=false"
  expect (SolanaCpiSystemAssemblyV1.isTestPreactivation asm) "isTestPreactivation=true"
  expect (SolanaCpiSystemAssemblyV1.frameBytesOf asm ≤ 4096) "frame ≤ 4096"
  expect (hasSubstr text "call sol_try_find_program_address\n  jne r0, 0, cpi_failed")
    "find status must propagate"
  expect (hasSubstr text "call sol_invoke_signed_c\n  jne r0, 0, cpi_failed")
    "invoke status must propagate"
  expect (hasSubstr text "jeq r4, 0, err_shape") "runtime bump-zero reject"
  let setReturnCalls := countSubstr text "call sol_set_return_data"
  let checkedSetReturnCalls :=
    countSubstr text "call sol_set_return_data\n  jne r0, 0, cpi_failed"
  expect (setReturnCalls == checkedSetReturnCalls)
    "every sol_set_return_data status must propagate through cpi_failed"
  -- transfer data disc 2
  expect (hasSubstr text "SystemInstruction::Transfer") "transfer disc comment"
  expect (hasSubstr text "SystemInstruction::CreateAccount") "create disc comment"

  -- Transfer-only path: no find_program_address required when no create.
  let (tOnly, tAsm) ← fullSystemChain session transferOnlySource
    "Examples.SystemTransferOnly"
    "runtime-tests/solana/fixtures/SystemTransferOnly.lean"
  let tText := SolanaCpiSystemAssemblyV1.textOf tAsm
  expect (hasSubstr tText "call sol_invoke_signed_c") "transfer-only invoke"
  expect (!hasSubstr tText "call sol_try_find_program_address")
    "transfer-only must not call find_program_address"
  let some tOnlyInv :=
      (ResolvedSolanaCpiSystemIRV1.candidateOf tOnly).handlers.findSome? (fun h =>
        h.bodyOps.findSome? (fun | .invokeSystem i => some i | _ => none)) |
    throw <| IO.userError "transfer-only invoke missing"
  expect (tOnlyInv.dataLen == 12 && tOnlyInv.signerGroupId.isNone)
    "transfer-only zero signer groups / 12B"

  -- space literal 4096 accepted.
  let (okSpace, _) ← fullSystemChain session createSpace4096Source
    "Examples.SystemCreateSpaceOk"
    "runtime-tests/solana/fixtures/SystemCreateSpaceOk.lean"
  let some okInv :=
      (ResolvedSolanaCpiSystemIRV1.candidateOf okSpace).handlers.findSome? (fun h =>
        h.bodyOps.findSome? (fun | .invokeSystem i => some i | _ => none)) |
    throw <| IO.userError "space4096 invoke missing"
  match okInv.space with
  | some (.literal v) => expect (v == 4096) "literal space 4096"
  | _ => throw <| IO.userError "space not literal 4096"

  -- space literal 4097 rejected at IR mint.
  let overPlan ← planOnly session createSpace4097Source
    "Examples.SystemCreateSpaceOver"
    "runtime-tests/solana/fixtures/SystemCreateSpaceOver.lean"
  expectPlanRejectContains
    (resolveSolanaCpiSystemIRV1 overPlan)
    "space" "space 4097 rejected by System IR"

  -- bump literal 0 rejected.
  let zeroPlan ← planOnly session bumpZeroSource
    "Examples.SystemBumpZero" "runtime-tests/solana/fixtures/SystemBumpZero.lean"
  expectPlanRejectContains
    (resolveSolanaCpiSystemIRV1 zeroPlan)
    "bump literal 0" "bump zero literal rejected by System IR"

  -- companion rejected by System IR.
  let companionPlan ← planOnly session companionSource
    "Examples.SystemRejectCompanion"
    "runtime-tests/solana/fixtures/SystemRejectCompanion.lean"
  expectPlanRejectContains
    (resolveSolanaCpiSystemIRV1 companionPlan)
    "system" "companion rejected by System IR"

  -- multi-block rejected.
  let brPlan ← planOnly session multiBlockSource
    "Examples.SystemRejectBranch"
    "runtime-tests/solana/fixtures/SystemRejectBranch.lean"
  expectPlanRejectContains
    (resolveSolanaCpiSystemIRV1 brPlan)
    "single-block" "multi-block rejected by System IR"

  -- Old-lane independence: create path rejected by preflight IR (PDA/systemCreate).
  let createPlan ← planOnly session createSpace4096Source
    "Examples.SystemCreateSpaceOk"
    "runtime-tests/solana/fixtures/SystemCreateSpaceOk.lean"
  expectPlanRejectContains
    (resolveSolanaCpiPreflightIRV1 createPlan)
    "PDA" "#118 preflight IR rejects createPda PDA/systemCreate path"

  -- PDA IR rejects system transfer.
  let transferPlan ← planOnly session transferOnlySource
    "Examples.SystemTransferOnly"
    "runtime-tests/solana/fixtures/SystemTransferOnly.lean"
  expectPlanRejectContains
    (resolveSolanaCpiPdaIRV1 transferPlan)
    "invokeSigned" "system transfer rejected by PDA IR"

  -- Ordinary product resolver still rejects sync.
  let resolverCompiled ← compileSource session systemCpiSource
    "Examples.SystemCpi" "runtime-tests/solana/fixtures/SystemCpi.lean"
  let selection ← cpiSelection
  match resolveEngineeringRequirementsV1 selection resolverCompiled with
  | .error error =>
      expect (error.code == "PF-REQ-UNSUPPORTED")
        s!"ordinary resolver must PF-REQ-UNSUPPORTED, got {error.render}"
  | .ok _ =>
      throw <| IO.userError "ordinary resolver unexpectedly accepted sync program"

  -- Frame / scratch non-overlap via public helpers (no fragile opcode strings).
  -- Emitter: reserve = max(maxScratch, 240);
  --   cpiBase = max(systemCpiBaseMinV1, systemTempRegionEndV1 + reserve);
  --   frame = cpiBase + reserve. CPI region starts at r10-CPI_BASE and must not
  -- overlap the temp region ending at systemTempRegionEndV1.
  let maxScratch := systemMaxSiteScratchV1 cand
  let createScratch := systemCpiScratchCreateV1 cInv.accountInfoCount
  expect (maxScratch == createScratch)
    "combined fixture max scratch dominated by createPda layout"
  expect (maxScratch == 296 + cInv.accountInfoCount * 56)
    "create scratch exact 296+56*N formula"
  let reserve := Nat.max maxScratch 240
  let expectedCpiBase :=
    Nat.max systemCpiBaseMinV1 (systemTempRegionEndV1 + reserve)
  let expectedFrame := expectedCpiBase + reserve
  expect (expectedCpiBase ≥ systemTempRegionEndV1 + reserve)
    "CPI_BASE places scratch at/after temp-region end (no overlap)"
  expect (SolanaCpiSystemAssemblyV1.frameBytesOf asm == expectedFrame)
    s!"frameBytes exact {expectedFrame} from public helpers"
  expect (expectedFrame ≤ systemMaxFrameBytesV1) "frame ≤ 4096 public cap"
  expect (hasSubstr text s!".equ CPI_BASE, {expectedCpiBase}")
    s!"emitted CPI_BASE equ matches computed {expectedCpiBase}"

  IO.println "Tests.Materialization.SolanaCpiSystemV1: ok"

end Tests.Materialization.SolanaCpiSystemV1
