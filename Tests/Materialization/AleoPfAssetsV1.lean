/-
  Tests.Materialization.AleoPfAssetsV1 — ADR-0029 Phase D Aleo zero-binding.

  Pins:
    * resolver does **not** advertise `extension.pf-assets`
    * each of the five catalog QNs fails at **resolve** (Aleo declines both
      extension.pf-assets and effect.synchronous-call; product path never
      reaches Plan for call)
    * disposition helpers freeze empty admit set + unbound diagnostic text
    * non-catalog call still declines at resolve (sync-call key) — no
      broadening of Aleo capability

  Plan-level unbound wording in `LowerSemanticV1` is defense-in-depth for a
  future sync-call surface; product fail point today is resolve.
-/
import ProofForgeV2
import ProofForgeV2.Core.RequirementIdsV1
import ProofForgeV2.Targets.Aleo.PfAssetsDispositionV1
import Tests.Language.ParserSession
import Tests.Compiler.ValidatedSourceV1Pipeline

namespace Tests.Materialization.AleoPfAssetsV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Aleo.PfAssetsDispositionV1
open ProofForgeV2.Core.RequirementIdsV1

private def expect (cond : Bool) (message : String) : IO Unit :=
  unless cond do throw <| IO.userError message

private def liftResult {α : Type} : CompileResult α → IO α
  | .ok value => pure value
  | .error e => throw <| IO.userError e.render

private def pfAssetsRequiresBlock : String :=
  "  requires extension pf.assets version \"1.1.0\"\n" ++
  "    digest \"sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9\"\n"

private unsafe def compileSource (label : String) (name : String) (source : String) :
    IO CompiledSemanticV1 := do
  let session ← Tests.Language.ParserSession.shared
  let parsed ← liftResult (← session.selectProgramV1 source label name none)
  liftResult <| Compiler.compileValidatedSourceV1 parsed

private def resolveAleo (compiled : CompiledSemanticV1) :
    CompileResult Targets.ResolvedEngineeringBuildV1 := do
  let selection ← resolveBuildSelectionV1 TargetId.aleo none
  Targets.resolveEngineeringRequirementsV1 selection compiled

/-- Disposition module freezes empty admit set + full catalog membership. -/
def testDispositionHelpers : IO Unit := do
  expect (admittedBindingsV1.isEmpty) "Aleo Phase D admit set must be empty"
  expect (!isAleoAdmittedPfAssetsQnV1 "pf.assets.native.transfer")
    "no QN is Aleo-admitted"
  for qn in pfAssetsCatalogQualifiedNamesV1 do
    expect (isPfAssetsCatalogQnV1 qn) s!"catalog membership must include {qn}"
  let diag := unboundCatalogDiagV1 "pf.assets.native.transfer"
  expect (diag.contains "unbound" && diag.contains "record custody")
    "Aleo unbound diagnostic must cite unbound + record custody"

/-- Extension alone declines at resolve (no Aleo permit row). -/
unsafe def testExtensionDeclinedAtResolve : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program DeclOnly where\n" ++
    pfAssetsRequiresBlock ++
    "  state tips : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    tips := initial\n" ++
    "  entry tip(amount : UInt64) : UInt64 do\n" ++
    "    tips := tips + amount\n" ++
    "    return tips\n" ++
    "  view get() : UInt64 do\n" ++
    "    return tips\n"
  let compiled ← compileSource "<aleo-pf-assets-decl>" "Tests.AleoPfAssetsDecl" source
  match resolveAleo compiled with
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED")
        s!"Aleo must decline extension.pf-assets at resolve, got {e.render}"
  | .ok _ =>
      throw <| IO.userError "Aleo must not advertise extension.pf-assets"

/-- One catalog QN (+ extension) → resolve PF-REQ-UNSUPPORTED. -/
unsafe def expectUnsupportedAtResolve (label qn callLine : String) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    s!"program {label} where\n" ++
    pfAssetsRequiresBlock ++
    "  state tips : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    tips := initial\n" ++
    "  entry tip(dst : Principal, mint : Principal, amount : UInt64) : UInt64 do\n" ++
    s!"    {callLine}\n" ++
    "    return amount\n" ++
    "  view get() : UInt64 do\n" ++
    "    return tips\n"
  let compiled ← compileSource s!"<aleo-pf-assets-{label}>" s!"Tests.Aleo{label}" source
  match resolveAleo compiled with
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED")
        s!"{qn}: must fail at resolve with PF-REQ-UNSUPPORTED, got {e.render}"
  | .ok _ =>
      throw <| IO.userError
        s!"{qn}: Aleo must not resolve a program that requires pf.assets + sync call"

/-- Five catalog QNs: exact resolve failure (zero-binding + no sync-call key). -/
unsafe def testFiveCatalogQnsFailAtResolve : IO Unit := do
  expectUnsupportedAtResolve "Dep" "pf.assets.native.deposit"
    "call pf.assets.native.deposit(amount)"
  expectUnsupportedAtResolve "Xfer" "pf.assets.native.transfer"
    "call pf.assets.native.transfer(dst, amount)"
  expectUnsupportedAtResolve "XferAsync" "pf.assets.native.transferAsync"
    "call pf.assets.native.transferAsync(dst, amount)"
  expectUnsupportedAtResolve "Tok" "pf.assets.token.transfer"
    "call pf.assets.token.transfer(mint, dst, amount)"
  expectUnsupportedAtResolve "TokAsync" "pf.assets.token.transferAsync"
    "call pf.assets.token.transferAsync(mint, dst, amount)"

/-- Non-catalog call still declines (sync-call key) — Phase D must not open call. -/
unsafe def testNonCatalogCallStillDeclined : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Oracle where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(x : UInt64) : UInt64 do\n" ++
    "    call Peer.go(x)\n" ++
    "    return count\n"
  let compiled ← compileSource "<aleo-pf-assets-oracle>" "Tests.AleoPfAssetsOracle" source
  match resolveAleo compiled with
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED")
        s!"non-catalog call must still decline at resolve, got {e.render}"
  | .ok _ =>
      throw <| IO.userError "Aleo must not open sync-call for non-catalog callees"

unsafe def run : IO Unit := do
  testDispositionHelpers
  testExtensionDeclinedAtResolve
  testFiveCatalogQnsFailAtResolve
  testNonCatalogCallStillDeclined
  IO.println "Tests.Materialization.AleoPfAssetsV1: ok"

end Tests.Materialization.AleoPfAssetsV1
