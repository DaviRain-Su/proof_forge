/-
  Tests.Materialization.SolanaCpiUnsignedV1 — #119 unsigned companion CPI IR/emitter.

  Ordinary registered suite. Authority path:
  Loader → product compile → preflight capability → Semantic Plan → preflight IR
  → unsigned IR → emitter.

  Pins: companion.invoke/.fail only, single-block gate, siteChecks immediately
  before invoke, sol_invoke_signed_c + sol_set_return_data surface, no 0xec01,
  System/PDA rejection. #125: ordinary resolver admits sync, but product Plan
  fails PF-PLAN-INVARIANT (active catalog companion denied); preactivation lane
  still succeeds (isProductArtifact=false pins unchanged).
-/
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiIRV1
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiProductV1
import ProofForgeV2.Targets.Solana.CpiPreflightIRV1
import ProofForgeV2.Targets.Solana.CpiUnsignedIRV1
import ProofForgeV2.Targets.Solana.EmitCpiUnsignedSbpfV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.Materialization.SolanaCpiUnsignedV1

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

/-- Primary #119 fixture body (mirrors CompanionCpi.lean). -/
private def companionCpiSource : String :=
  wrapProgram "CompanionCpi" <|
    "  state value : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    value := initial\n" ++
    "  entry invokeOnce(account : Principal, delta : UInt64) : UInt64 do\n" ++
    "    value := value + 1\n" ++
    "    call solana.companion.invoke(account, delta)\n" ++
    "    value := value + 2\n" ++
    "    return value\n" ++
    "  entry failOnce(account : Principal, delta : UInt64) : UInt64 do\n" ++
    "    value := value + 1\n" ++
    "    call solana.companion.fail(account, delta)\n" ++
    "    value := value + 2\n" ++
    "    return value\n" ++
    "  view inspect() : UInt64 do\n" ++
    "    return value\n"

private def systemTransferSource : String :=
  wrapProgram "UnsignedRejectSystem" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry transfer(payer : Principal, recipient : Principal,\n" ++
    "      lamports : UInt64) : UInt64 do\n" ++
    "    call solana.system.transfer(payer, recipient, lamports)\n" ++
    "    return 0\n"

private def multiBlockSource : String :=
  wrapProgram "UnsignedRejectBranch" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry branchy(account : Principal, delta : UInt64) : UInt64 do\n" ++
    "    if delta == 0 then\n" ++
    "      value := delta\n" ++
    "    else\n" ++
    "      value := 1\n" ++
    "    call solana.companion.invoke(account, delta)\n" ++
    "    return value\n"

private def dualPrincipalSource : String :=
  wrapProgram "UnsignedDualPrincipal" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry invokeBoth(first : Principal, second : Principal,\n" ++
    "      delta : UInt64) : UInt64 do\n" ++
    "    call solana.companion.invoke(first, delta)\n" ++
    "    call solana.companion.invoke(second, delta)\n" ++
    "    return 0\n"

private def literalDeltaSource : String :=
  wrapProgram "UnsignedLiteralDelta" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry invokeLiteral(account : Principal) : UInt64 do\n" ++
    "    let delta : UInt64 := 513\n" ++
    "    call solana.companion.invoke(account, delta)\n" ++
    "    return delta\n"

/-- State + 14 distinct Principal roles + one fixed callee = exact 16-role cap. -/
private def maxRoleSource : String :=
  wrapProgram "UnsignedMaxRoles" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry invokeMany(\n" ++
    "      a0 : Principal, a1 : Principal, a2 : Principal, a3 : Principal,\n" ++
    "      a4 : Principal, a5 : Principal, a6 : Principal, a7 : Principal,\n" ++
    "      a8 : Principal, a9 : Principal, a10 : Principal, a11 : Principal,\n" ++
    "      a12 : Principal, a13 : Principal, delta : UInt64) : UInt64 do\n" ++
    "    call solana.companion.invoke(a0, delta)\n" ++
    "    call solana.companion.invoke(a1, delta)\n" ++
    "    call solana.companion.invoke(a2, delta)\n" ++
    "    call solana.companion.invoke(a3, delta)\n" ++
    "    call solana.companion.invoke(a4, delta)\n" ++
    "    call solana.companion.invoke(a5, delta)\n" ++
    "    call solana.companion.invoke(a6, delta)\n" ++
    "    call solana.companion.invoke(a7, delta)\n" ++
    "    call solana.companion.invoke(a8, delta)\n" ++
    "    call solana.companion.invoke(a9, delta)\n" ++
    "    call solana.companion.invoke(a10, delta)\n" ++
    "    call solana.companion.invoke(a11, delta)\n" ++
    "    call solana.companion.invoke(a12, delta)\n" ++
    "    call solana.companion.invoke(a13, delta)\n" ++
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

private unsafe def fullUnsignedChain
    (session : Language.Loader.ParserSession)
    (source moduleName path : String) :
    IO (ResolvedSolanaCpiUnsignedIRV1 × SolanaCpiUnsignedAssemblyV1) := do
  let compiled ← compileSource session source moduleName path
  let selection ← cpiSelection
  let preflight ← expectPlanOk
    (resolveSolanaCpiPreflightV1 selection compiled) "preflight"
  let plan ← expectPlanOk
    (deriveSolanaCpiPlanFromPreflightV1 preflight) "derive plan"
  let pfIr ← expectPlanOk
    (resolveSolanaCpiPreflightIRV1 plan) "preflight IR"
  let unsigned ← expectPlanOk
    (resolveSolanaCpiUnsignedIRV1 pfIr) "unsigned IR"
  let asm ← expectPlanOk
    (emitCpiUnsignedSbpfV1 unsigned) "emit unsigned"
  pure (unsigned, asm)

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared

  -- Positive chain.
  let (unsigned, asm) ← fullUnsignedChain session companionCpiSource
    "Examples.CompanionCpi" "runtime-tests/solana/fixtures/CompanionCpi.lean"
  let cand := ResolvedSolanaCpiUnsignedIRV1.candidateOf unsigned
  expect (cand.handlers.size == 4) "expected 4 handlers (init/invoke/fail/inspect)"
  expect (cand.handlers.any (fun h => h.name == "invokeOnce")) "invokeOnce handler"
  expect (cand.handlers.any (fun h => h.name == "failOnce")) "failOnce handler"
  for h in cand.handlers do
    -- siteChecks must immediately precede invoke in body IR.
    let ops := h.bodyOps
    for i in [0:ops.size] do
      match ops[i]! with
      | .invokeUnsigned inv =>
          expect (i > 0) s!"{h.name}: invoke without preceding op"
          match ops[i - 1]! with
          | .siteChecks sid _ =>
              expect (sid == inv.siteId) s!"{h.name}: siteChecks/invoke site mismatch"
          | _ =>
              throw <| IO.userError s!"{h.name}: invoke not preceded by siteChecks"
      | _ => pure ()
  let text := SolanaCpiUnsignedAssemblyV1.textOf asm
  expect (hasSubstr text "call sol_invoke_signed_c") "assembly must call sol_invoke_signed_c"
  expect (hasSubstr text "call sol_set_return_data") "assembly must call sol_set_return_data"
  expect (!hasSubstr text "0xec01") "assembly must not contain 0xec01 stub"
  expect (!hasSubstr text "ACC0_") "assembly must not use ACC0 slots"
  expect (hasSubstr text "TEST-PREACTIVATION ONLY") "preactivation banner"
  expect (hasSubstr text "not a product artifact") "product boundary banner"
  expect (hasSubstr text "site-time, not entry-hoisted") "site-time checks comment"
  expect (hasSubstr text "handler_1_invokeOnce_unsigned:") "invokeOnce label"
  expect (hasSubstr text "handler_2_failOnce_unsigned:") "failOnce label"
  expect (!SolanaCpiUnsignedAssemblyV1.isProductArtifact asm) "isProductArtifact=false"
  expect (SolanaCpiUnsignedAssemblyV1.isTestPreactivation asm) "isTestPreactivation=true"
  expect (SolanaCpiUnsignedAssemblyV1.frameBytesOf asm ≤ 4096) "frame ≤ 4096"
  let setReturnCalls := countSubstr text "call sol_set_return_data"
  let checkedSetReturnCalls :=
    countSubstr text "call sol_set_return_data\n  jne r0, 0, cpi_failed"
  expect (setReturnCalls == checkedSetReturnCalls)
    "every sol_set_return_data status must propagate through cpi_failed"

  -- Every companion invoke retains an exact Principal ValueId→param→role→local
  -- join, and meta[0] must use the same role/local handle.
  for h in cand.handlers do
    for op in h.bodyOps do
      match op with
      | .invokeUnsigned inv =>
          expect (inv.principalBindings.size == 1 && inv.metas.size == 1)
            s!"{h.name}: exact one Principal/meta binding"
          let principal := inv.principalBindings[0]!
          let metaBinding := inv.metas[0]!
          expect (principal.argIndex == 0 &&
              principal.roleId == metaBinding.roleId &&
              principal.localIndex == metaBinding.localIndex)
            s!"{h.name}: Principal/meta exact join"
      | _ => pure ()

  -- After cpi_failed label, only exit (no store/event/call).
  let afterFail :=
    match text.splitOn "cpi_failed:" with
    | _ :: rest :: _ => rest
    | _ => ""
  expect (afterFail != "") "cpi_failed label present"
  let failLines := (afterFail.splitOn "\n").take 6
  expect (!failLines.any (fun l => l.contains "stxdw" && l.contains "ROLE_DATA"))
    "no state store after cpi_failed"
  expect (!failLines.any (fun l => l.contains "call sol_invoke"))
    "no further invoke after cpi_failed"
  expect (!failLines.any (fun l => l.contains "call sol_set_return_data"))
    "no success-clear after cpi_failed"

  -- Two Principal parameters used by two sites must remain distinct all the
  -- way through their Semantic ValueIds, declaration ordinals, roles and
  -- dense handler-local positions.
  let (dualUnsigned, _) ← fullUnsignedChain session dualPrincipalSource
    "Examples.UnsignedDualPrincipal"
    "runtime-tests/solana/fixtures/UnsignedDualPrincipal.lean"
  let some dualHandler := (ResolvedSolanaCpiUnsignedIRV1.candidateOf dualUnsigned).handlers.find?
      (fun h => h.name == "invokeBoth") |
    throw <| IO.userError "missing invokeBoth handler"
  let mut dualBindings : Array CpiUnsignedPrincipalBindingV1 := #[]
  for op in dualHandler.bodyOps do
    match op with
    | .invokeUnsigned inv =>
        let binding ← match inv.principalBindings[0]? with
          | some b => pure b
          | none => throw <| IO.userError "dual invoke missing Principal binding"
        dualBindings := dualBindings.push binding
    | _ => pure ()
  expect (dualBindings.size == 2) "dual Principal: two invoke bindings"
  let firstBinding := dualBindings[0]!
  let secondBinding := dualBindings[1]!
  expect (firstBinding.paramOrdinal == 0 && secondBinding.paramOrdinal == 1)
    "dual Principal: exact parameter declaration ordinals"
  expect (firstBinding.semanticValueId != secondBinding.semanticValueId &&
      firstBinding.roleId != secondBinding.roleId &&
      firstBinding.localIndex != secondBinding.localIndex)
    "dual Principal: ValueId/role/local identity must not alias"
  expect (firstBinding.localIndex == 1 && secondBinding.localIndex == 2)
    "dual Principal: state precedes dense account-parameter roles"

  -- Numeric instruction data may use the frozen literal source without
  -- weakening the Principal account binding.
  let (literalUnsigned, _) ← fullUnsignedChain session literalDeltaSource
    "Examples.UnsignedLiteralDelta"
    "runtime-tests/solana/fixtures/UnsignedLiteralDelta.lean"
  let some literalHandler :=
      (ResolvedSolanaCpiUnsignedIRV1.candidateOf literalUnsigned).handlers.find?
        (fun h => h.name == "invokeLiteral") |
    throw <| IO.userError "missing invokeLiteral handler"
  let some literalInvoke := literalHandler.bodyOps.findSome? (fun
      | .invokeUnsigned inv => some inv
      | _ => none) |
    throw <| IO.userError "missing literal invoke"
  match literalInvoke.delta with
  | .literal value => expect (value == 513) "literal delta exact UInt64 value"
  | .param .. => throw <| IO.userError "literal delta incorrectly rebound to param"

  -- At the exact 16-role cap, AccountInfo scratch grows toward the temp region.
  -- CPI_BASE must move down far enough for the full 968-byte region.
  let (maxUnsigned, maxAsm) ← fullUnsignedChain session maxRoleSource
    "Examples.UnsignedMaxRoles"
    "runtime-tests/solana/fixtures/UnsignedMaxRoles.lean"
  let some maxHandler := (ResolvedSolanaCpiUnsignedIRV1.candidateOf maxUnsigned).handlers.find?
      (fun h => h.name == "invokeMany") |
    throw <| IO.userError "missing invokeMany handler"
  expect (maxHandler.localRoleCount == 16) "max role fixture must hit exact cap"
  expect (unsignedMaxSiteScratchV1
      (ResolvedSolanaCpiUnsignedIRV1.candidateOf maxUnsigned) == 968)
    "max role fixture scratch size"
  expect (SolanaCpiUnsignedAssemblyV1.frameBytesOf maxAsm == 3160)
    "max role frame includes relocated base plus reserve"
  expect (hasSubstr (SolanaCpiUnsignedAssemblyV1.textOf maxAsm) ".equ CPI_BASE, 2192")
    "max role CPI base leaves 968 bytes above temp region"

  -- System package rejected at unsigned IR.
  let sysCompiled ← compileSource session systemTransferSource
    "Examples.UnsignedRejectSystem" "runtime-tests/solana/fixtures/UnsignedRejectSystem.lean"
  let selection ← cpiSelection
  let sysPf ← expectPlanOk
    (resolveSolanaCpiPreflightV1 selection sysCompiled) "system preflight"
  let sysPlan ← expectPlanOk
    (deriveSolanaCpiPlanFromPreflightV1 sysPf) "system plan"
  let sysPfIr ← expectPlanOk
    (resolveSolanaCpiPreflightIRV1 sysPlan) "system preflight IR"
  expectPlanRejectContains
    (resolveSolanaCpiUnsignedIRV1 sysPfIr)
    "companion-v1" "system transfer rejected by unsigned IR"

  -- Multi-block rejected.
  let brCompiled ← compileSource session multiBlockSource
    "Examples.UnsignedRejectBranch" "runtime-tests/solana/fixtures/UnsignedRejectBranch.lean"
  let brPf ← expectPlanOk
    (resolveSolanaCpiPreflightV1 selection brCompiled) "branch preflight"
  let brPlan ← expectPlanOk
    (deriveSolanaCpiPlanFromPreflightV1 brPf) "branch plan"
  let brPfIr ← expectPlanOk
    (resolveSolanaCpiPreflightIRV1 brPlan) "branch preflight IR"
  expectPlanRejectContains
    (resolveSolanaCpiUnsignedIRV1 brPfIr)
    "single-block" "multi-block rejected by unsigned IR"

  -- #125: ordinary product resolver admits companion sync; product Plan fails
  -- closed because active catalog denies companion package. Preactivation lane
  -- above remains successful (isProductArtifact=false).
  let resolverCompiled ← compileSource session companionCpiSource
    "Examples.CompanionCpi" "runtime-tests/solana/fixtures/CompanionCpi.lean"
  let capability ← expectPlanOk
    (resolveEngineeringRequirementsV1 selection resolverCompiled)
    "ordinary resolver admits companion unsigned sync"
  expectPlanRejectContains
    (productPlanFromCapabilityV1 capability)
    "companion" "product Plan denies companion catalog package"

  IO.println "Tests.Materialization.SolanaCpiUnsignedV1: ok"

end Tests.Materialization.SolanaCpiUnsignedV1
