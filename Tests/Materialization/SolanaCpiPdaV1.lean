/-
  Tests.Materialization.SolanaCpiPdaV1 — #120 PDA-signed companion CPI IR/emitter.

  Authority path:
  Loader → product compile → preflight capability → Semantic Plan
  → PDA IR (from SolanaCpiPreflightPlanV1; NOT ResolvedSolanaCpiPreflightIRV1)
  → PDA emitter.

  Pins: companion.invokeSigned only, single-block gate, siteChecks immediately
  before invoke, three Principal bindings/meta/outer-only/signer group,
  sol_try_find_program_address + sol_invoke_signed_c surface, bump-zero reject,
  #118/#119 rejection independence, ordinary resolver PF-REQ-UNSUPPORTED.
-/
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiIRV1
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiPreflightIRV1
import ProofForgeV2.Targets.Solana.CpiPdaIRV1
import ProofForgeV2.Targets.Solana.EmitCpiPdaSbpfV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.Materialization.SolanaCpiPdaV1

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

private def extensionHeader : String :=
  "  requires extension solana.cpi.accounts version \"1.0.0\"\n" ++
  "    digest \"sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020\"\n"

private def wrapProgram (name body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  s!"program {name} where\n" ++
  extensionHeader ++
  body

/-- Primary #120 fixture body (CompanionPdaCpi shape). -/
private def companionPdaCpiSource : String :=
  wrapProgram "CompanionPdaCpi" <|
    "  state value : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    value := initial\n" ++
    "  entry invokeOnce(account : Principal, authorityPda : Principal,\n" ++
    "      seedAuthority : Principal, seedTag : UInt64, bump : UInt8,\n" ++
    "      delta : UInt64) : UInt64 do\n" ++
    "    value := value + 1\n" ++
    "    call solana.companion.invokeSigned(account, authorityPda,\n" ++
    "      seedAuthority, seedTag, bump, delta)\n" ++
    "    value := value + 2\n" ++
    "    return value\n" ++
    "  view inspect() : UInt64 do\n" ++
    "    return value\n"

/-- Typed-let literals for seedTag/bump/delta. -/
private def literalSourcesSource : String :=
  wrapProgram "PdaLiteralSources" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry invokeLiteral(account : Principal, authorityPda : Principal,\n" ++
    "      seedAuthority : Principal) : UInt64 do\n" ++
    "    let seedTag : UInt64 := 42\n" ++
    "    let bump : UInt8 := 255\n" ++
    "    let delta : UInt64 := 7\n" ++
    "    call solana.companion.invokeSigned(account, authorityPda,\n" ++
    "      seedAuthority, seedTag, bump, delta)\n" ++
    "    return delta\n"

/-- Bump literal 0 must be rejected at IR mint. -/
private def bumpZeroLiteralSource : String :=
  wrapProgram "PdaBumpZero" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry invokeZero(account : Principal, authorityPda : Principal,\n" ++
    "      seedAuthority : Principal, seedTag : UInt64, delta : UInt64) : UInt64 do\n" ++
    "    let bump : UInt8 := 0\n" ++
    "    call solana.companion.invokeSigned(account, authorityPda,\n" ++
    "      seedAuthority, seedTag, bump, delta)\n" ++
    "    return 0\n"

private def unsignedCompanionSource : String :=
  wrapProgram "UnsignedForPdaReject" <|
    "  state value : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    value := initial\n" ++
    "  entry invokeOnce(account : Principal, delta : UInt64) : UInt64 do\n" ++
    "    call solana.companion.invoke(account, delta)\n" ++
    "    return value\n"

private def systemTransferSource : String :=
  wrapProgram "PdaRejectSystem" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry transfer(payer : Principal, recipient : Principal,\n" ++
    "      lamports : UInt64) : UInt64 do\n" ++
    "    call solana.system.transfer(payer, recipient, lamports)\n" ++
    "    return 0\n"

private def multiBlockSource : String :=
  wrapProgram "PdaRejectBranch" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry branchy(account : Principal, authorityPda : Principal,\n" ++
    "      seedAuthority : Principal, seedTag : UInt64, bump : UInt8,\n" ++
    "      delta : UInt64) : UInt64 do\n" ++
    "    if delta == 0 then\n" ++
    "      value := delta\n" ++
    "    else\n" ++
    "      value := 1\n" ++
    "    call solana.companion.invokeSigned(account, authorityPda,\n" ++
    "      seedAuthority, seedTag, bump, delta)\n" ++
    "    return value\n"

/-- Exact 16-role cap: state + companion + shared authorityPda/seedAuthority
    + 12 distinct account Principals used across sites. -/
private def maxRoleSource : String :=
  wrapProgram "PdaMaxRoles" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry invokeMany(\n" ++
    "      a0 : Principal, a1 : Principal, a2 : Principal, a3 : Principal,\n" ++
    "      a4 : Principal, a5 : Principal, a6 : Principal, a7 : Principal,\n" ++
    "      a8 : Principal, a9 : Principal, a10 : Principal, a11 : Principal,\n" ++
    "      authorityPda : Principal, seedAuthority : Principal,\n" ++
    "      seedTag : UInt64, bump : UInt8, delta : UInt64) : UInt64 do\n" ++
    "    call solana.companion.invokeSigned(a0, authorityPda,\n" ++
    "      seedAuthority, seedTag, bump, delta)\n" ++
    "    call solana.companion.invokeSigned(a1, authorityPda,\n" ++
    "      seedAuthority, seedTag, bump, delta)\n" ++
    "    call solana.companion.invokeSigned(a2, authorityPda,\n" ++
    "      seedAuthority, seedTag, bump, delta)\n" ++
    "    call solana.companion.invokeSigned(a3, authorityPda,\n" ++
    "      seedAuthority, seedTag, bump, delta)\n" ++
    "    call solana.companion.invokeSigned(a4, authorityPda,\n" ++
    "      seedAuthority, seedTag, bump, delta)\n" ++
    "    call solana.companion.invokeSigned(a5, authorityPda,\n" ++
    "      seedAuthority, seedTag, bump, delta)\n" ++
    "    call solana.companion.invokeSigned(a6, authorityPda,\n" ++
    "      seedAuthority, seedTag, bump, delta)\n" ++
    "    call solana.companion.invokeSigned(a7, authorityPda,\n" ++
    "      seedAuthority, seedTag, bump, delta)\n" ++
    "    call solana.companion.invokeSigned(a8, authorityPda,\n" ++
    "      seedAuthority, seedTag, bump, delta)\n" ++
    "    call solana.companion.invokeSigned(a9, authorityPda,\n" ++
    "      seedAuthority, seedTag, bump, delta)\n" ++
    "    call solana.companion.invokeSigned(a10, authorityPda,\n" ++
    "      seedAuthority, seedTag, bump, delta)\n" ++
    "    call solana.companion.invokeSigned(a11, authorityPda,\n" ++
    "      seedAuthority, seedTag, bump, delta)\n" ++
    "    return 0\n"

private def countSubstr (haystack needle : String) : Nat :=
  (haystack.splitOn needle).length - 1

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

private unsafe def fullPdaChain
    (session : Language.Loader.ParserSession)
    (source moduleName path : String) :
    IO (ResolvedSolanaCpiPdaIRV1 × SolanaCpiPdaAssemblyV1) := do
  let compiled ← compileSource session source moduleName path
  let selection ← cpiSelection
  let preflight ← expectPlanOk
    (resolveSolanaCpiPreflightV1 selection compiled) "preflight"
  let plan ← expectPlanOk
    (deriveSolanaCpiPlanFromPreflightV1 preflight) "derive plan"
  let pda ← expectPlanOk
    (resolveSolanaCpiPdaIRV1 plan) "pda IR"
  let asm ← expectPlanOk
    (emitCpiPdaSbpfV1 pda) "emit pda"
  pure (pda, asm)

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

  -- Positive chain (normal param sources).
  let (pda, asm) ← fullPdaChain session companionPdaCpiSource
    "Examples.CompanionPdaCpi"
    "runtime-tests/solana/fixtures/CompanionPdaCpi.lean"
  let cand := ResolvedSolanaCpiPdaIRV1.candidateOf pda
  expect (cand.schema == pdaIrSchemaV1) "schema proof-forge.solana.cpi-pda-ir.v1"
  expect (cand.handlers.size == 3) "expected 3 handlers (init/invokeOnce/inspect)"
  expect (cand.handlers.any (fun h => h.name == "invokeOnce")) "invokeOnce handler"
  for h in cand.handlers do
    let ops := h.bodyOps
    for i in [0:ops.size] do
      match ops[i]! with
      | .invokeSigned inv =>
          expect (i > 0) s!"{h.name}: invoke without preceding op"
          match ops[i - 1]! with
          | .siteChecks sid _ =>
              expect (sid == inv.siteId) s!"{h.name}: siteChecks/invoke site mismatch"
          | _ =>
              throw <| IO.userError s!"{h.name}: invoke not preceded by siteChecks"
      | _ => pure ()

  -- Exact three Principal bindings / meta / outer-only / signer group.
  let some invokeHandler := cand.handlers.find? (fun h => h.name == "invokeOnce") |
    throw <| IO.userError "missing invokeOnce"
  expect (invokeHandler.probeIxDataLen == 25)
    "signed probe must pack handlerId8 + seedTag8 + bump1 + delta8"
  let some inv := invokeHandler.bodyOps.findSome? (fun
      | .invokeSigned i => some i
      | _ => none) |
    throw <| IO.userError "missing invokeSigned op"
  expect (inv.account.argIndex == 0 && inv.authorityPda.argIndex == 1 &&
      inv.seedAuthority.argIndex == 2) "Principal arg indices 0/1/2"
  expect (inv.account.paramOrdinal == 0 && inv.authorityPda.paramOrdinal == 1 &&
      inv.seedAuthority.paramOrdinal == 2) "Principal param ordinals"
  expect (inv.account.semanticValueId != inv.authorityPda.semanticValueId &&
      inv.authorityPda.semanticValueId != inv.seedAuthority.semanticValueId &&
      inv.account.roleId != inv.authorityPda.roleId &&
      inv.authorityPda.roleId != inv.seedAuthority.roleId &&
      inv.account.localIndex != inv.authorityPda.localIndex &&
      inv.authorityPda.localIndex != inv.seedAuthority.localIndex)
    "Principal ValueId/role/local must not alias"
  expect (inv.metas.size == 2) "two metas"
  expect (inv.metas[0]!.roleId == inv.account.roleId &&
      inv.metas[0]!.localIndex == inv.account.localIndex &&
      inv.metas[0]!.cpiWritable == true && inv.metas[0]!.cpiSigner == false)
    "meta[0] account writable non-signer"
  expect (inv.metas[1]!.roleId == inv.authorityPda.roleId &&
      inv.metas[1]!.localIndex == inv.authorityPda.localIndex &&
      inv.metas[1]!.cpiWritable == false && inv.metas[1]!.cpiSigner == true &&
      inv.metas[1]!.signerGroupId == some 0)
    "meta[1] authorityPda readonly CPI signer group 0"
  expect (inv.outerOnly.size == 1 &&
      inv.outerOnly[0]!.roleId == inv.seedAuthority.roleId &&
      inv.outerOnly[0]!.localIndex == inv.seedAuthority.localIndex &&
      inv.outerOnly[0]!.outerSigner == true &&
      inv.outerOnly[0]!.outerWritable == false)
    "outer-only seedAuthority business signer"
  expect (inv.signerGroupId == 0 && inv.pdaRule == "current-program-tagged-v1" &&
      inv.tag == 2 && inv.dataLen == 9)
    "frozen PDA rule / tag / dataLen"

  let text := SolanaCpiPdaAssemblyV1.textOf asm
  expect (hasSubstr text "call sol_try_find_program_address")
    "assembly must call sol_try_find_program_address"
  expect (hasSubstr text "call sol_invoke_signed_c")
    "assembly must call sol_invoke_signed_c"
  expect (hasSubstr text "call sol_set_return_data")
    "assembly must call sol_set_return_data"
  expect (hasSubstr text "0x6f662d666f6f7270") "seed0 limb0"
  expect (hasSubstr text "SEED0_LEN") "seed0 length equ"
  expect (!hasSubstr text "0xec01") "assembly must not contain 0xec01 stub"
  expect (!hasSubstr text "ACC0_") "assembly must not use ACC0 slots"
  expect (hasSubstr text "TEST-PREACTIVATION ONLY") "preactivation banner"
  expect (hasSubstr text "not a product artifact") "product boundary banner"
  expect (hasSubstr text "site-time, not entry-hoisted") "site-time checks comment"
  expect (hasSubstr text "handler_1_invokeOnce_pda:") "invokeOnce label"
  expect (!SolanaCpiPdaAssemblyV1.isProductArtifact asm) "isProductArtifact=false"
  expect (SolanaCpiPdaAssemblyV1.isTestPreactivation asm) "isTestPreactivation=true"
  expect (SolanaCpiPdaAssemblyV1.frameBytesOf asm ≤ 4096) "frame ≤ 4096"
  let setReturnCalls := countSubstr text "call sol_set_return_data"
  let checkedSetReturnCalls :=
    countSubstr text "call sol_set_return_data\n  jne r0, 0, cpi_failed"
  expect (setReturnCalls == checkedSetReturnCalls)
    "every sol_set_return_data status must propagate through cpi_failed"
  expect (hasSubstr text "call sol_try_find_program_address\n  jne r0, 0, cpi_failed")
    "find_program_address status must propagate"
  expect (hasSubstr text "call sol_invoke_signed_c\n  jne r0, 0, cpi_failed")
    "invoke_signed status must propagate"
  expect (hasSubstr text "jeq r4, 0, err_shape") "runtime bump-zero reject"

  -- Typed-let literals for seedTag/bump/delta.
  let (litPda, _) ← fullPdaChain session literalSourcesSource
    "Examples.PdaLiteralSources"
    "runtime-tests/solana/fixtures/PdaLiteralSources.lean"
  let some litHandler :=
      (ResolvedSolanaCpiPdaIRV1.candidateOf litPda).handlers.find?
        (fun h => h.name == "invokeLiteral") |
    throw <| IO.userError "missing invokeLiteral"
  let some litInv := litHandler.bodyOps.findSome? (fun
      | .invokeSigned i => some i
      | _ => none) |
    throw <| IO.userError "missing literal invoke"
  match litInv.seedTag with
  | .literal v => expect (v == 42) "literal seedTag 42"
  | .param .. => throw <| IO.userError "seedTag incorrectly rebound to param"
  match litInv.bump with
  | .literal v => expect (v == 255) "literal bump 255"
  | .param .. => throw <| IO.userError "bump incorrectly rebound to param"
  match litInv.delta with
  | .literal v => expect (v == 7) "literal delta 7"
  | .param .. => throw <| IO.userError "delta incorrectly rebound to param"

  -- Bump literal 0 rejected at IR.
  let zeroPlan ← planOnly session bumpZeroLiteralSource
    "Examples.PdaBumpZero" "runtime-tests/solana/fixtures/PdaBumpZero.lean"
  expectPlanRejectContains
    (resolveSolanaCpiPdaIRV1 zeroPlan)
    "bump literal 0" "bump zero literal rejected by PDA IR"

  -- System package rejected.
  let sysPlan ← planOnly session systemTransferSource
    "Examples.PdaRejectSystem" "runtime-tests/solana/fixtures/PdaRejectSystem.lean"
  expectPlanRejectContains
    (resolveSolanaCpiPdaIRV1 sysPlan)
    "invokeSigned" "system transfer rejected by PDA IR"

  -- Multi-block rejected.
  let brPlan ← planOnly session multiBlockSource
    "Examples.PdaRejectBranch" "runtime-tests/solana/fixtures/PdaRejectBranch.lean"
  expectPlanRejectContains
    (resolveSolanaCpiPdaIRV1 brPlan)
    "single-block" "multi-block rejected by PDA IR"

  -- #119 unsigned companion rejected by #120 PDA IR.
  let unsignedPlan ← planOnly session unsignedCompanionSource
    "Examples.UnsignedForPdaReject"
    "runtime-tests/solana/fixtures/UnsignedForPdaReject.lean"
  expectPlanRejectContains
    (resolveSolanaCpiPdaIRV1 unsignedPlan)
    "invokeSigned" "unsigned companion.invoke rejected by PDA IR"

  -- #118/#119 rejection independence: PDA program rejected by preflight IR
  -- (unsigned IR is unreachable past that gate; both refuse PDA/signer groups).
  let pdaPlan ← planOnly session companionPdaCpiSource
    "Examples.CompanionPdaCpi"
    "runtime-tests/solana/fixtures/CompanionPdaCpi.lean"
  expectPlanRejectContains
    (resolveSolanaCpiPreflightIRV1 pdaPlan)
    "PDA" "#118 preflight IR rejects PDA program"

  -- Ordinary product resolver still rejects sync.
  let resolverCompiled ← compileSource session companionPdaCpiSource
    "Examples.CompanionPdaCpi"
    "runtime-tests/solana/fixtures/CompanionPdaCpi.lean"
  let selection ← cpiSelection
  match resolveEngineeringRequirementsV1 selection resolverCompiled with
  | .error error =>
      expect (error.code == "PF-REQ-UNSUPPORTED")
        s!"ordinary resolver must PF-REQ-UNSUPPORTED, got {error.render}"
  | .ok _ =>
      throw <| IO.userError "ordinary resolver unexpectedly accepted sync program"

  -- Max-role boundary (state + 14 principals + companion can exceed 16; fixture
  -- uses 11 filler + 3 principals + state + companion = 16).
  let (maxPda, maxAsm) ← fullPdaChain session maxRoleSource
    "Examples.PdaMaxRoles"
    "runtime-tests/solana/fixtures/PdaMaxRoles.lean"
  let some maxHandler := (ResolvedSolanaCpiPdaIRV1.candidateOf maxPda).handlers.find?
      (fun h => h.name == "invokeMany") |
    throw <| IO.userError "missing invokeMany"
  expect (maxHandler.localRoleCount == 16) "max role fixture must hit exact cap"
  expect (pdaMaxSiteScratchV1 (ResolvedSolanaCpiPdaIRV1.candidateOf maxPda) == 1152)
    "max role fixture scratch size 256+56*16"
  expect (SolanaCpiPdaAssemblyV1.frameBytesOf maxAsm == 3528)
    "max role frame 2376+1152"
  expect (hasSubstr (SolanaCpiPdaAssemblyV1.textOf maxAsm) ".equ CPI_BASE, 2376")
    "max role CPI base"

  IO.println "Tests.Materialization.SolanaCpiPdaV1: ok"

end Tests.Materialization.SolanaCpiPdaV1
