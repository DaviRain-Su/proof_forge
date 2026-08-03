/-
  Tests.Materialization.SolanaCpiUnsignedV1 — #119 unsigned companion CPI IR/emitter.

  Ordinary registered suite. Authority path:
  Loader → product compile → preflight capability → Semantic Plan → preflight IR
  → unsigned IR → emitter.

  Pins: companion.invoke/.fail only, single-block gate, siteChecks immediately
  before invoke, sol_invoke_signed_c + sol_set_return_data surface, no 0xec01,
  System/PDA rejection, ordinary resolver still rejects sync.
-/
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiIRV1
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
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

  -- Ordinary product resolver still rejects sync on the call program.
  let resolverCompiled ← compileSource session companionCpiSource
    "Examples.CompanionCpi" "runtime-tests/solana/fixtures/CompanionCpi.lean"
  match resolveEngineeringRequirementsV1 selection resolverCompiled with
  | .error error =>
      expect (error.code == "PF-REQ-UNSUPPORTED")
        s!"ordinary resolver must PF-REQ-UNSUPPORTED, got {error.render}"
  | .ok _ =>
      throw <| IO.userError "ordinary resolver unexpectedly accepted sync program"

  IO.println "Tests.Materialization.SolanaCpiUnsignedV1: ok"

end Tests.Materialization.SolanaCpiUnsignedV1
