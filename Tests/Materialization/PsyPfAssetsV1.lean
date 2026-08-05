/-
  Tests.Materialization.PsyPfAssetsV1 — ADR-0029 Phase D Psy zero-binding.

  Pins:
    * resolver does **not** advertise `extension.pf-assets`
    * each of the five catalog QNs with extension declaration fails at
      **resolve** (`PF-REQ-UNSUPPORTED`)
    * `pf.assets.native.deposit` without extension reaches Plan and fails with
      explicit **unbound** diagnostic (must not alias `__invoke_sync` as vault)
    * non-catalog L0 sync call still lowers (Phase D must not broaden FC)

  Note: transfer* QNs need Principal args; Psy type-closure declines Principal,
  so without extension those programs fail closed at Principal before the
  unbound body gate. Resolve-with-extension is the product pin for all five.
-/
import ProofForgeV2
import ProofForgeV2.Core.RequirementIdsV1
import ProofForgeV2.Targets.Psy
import ProofForgeV2.Targets.Psy.PfAssetsDispositionV1
import Tests.Language.ParserSession
import Tests.Compiler.ValidatedSourceV1Pipeline

namespace Tests.Materialization.PsyPfAssetsV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Psy.PfAssetsDispositionV1
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

private def resolvePsy (compiled : CompiledSemanticV1) :
    CompileResult Targets.ResolvedEngineeringBuildV1 := do
  let selection ← resolveBuildSelectionV1 TargetId.psy none
  Targets.resolveEngineeringRequirementsV1 selection compiled

private def planPsyOf (compiled : CompiledSemanticV1) : CompileResult Targets.Psy.Plan := do
  let capability ← resolvePsy compiled
  Targets.Psy.planFromCapability capability

/-- Disposition module freezes empty admit set + full catalog membership. -/
def testDispositionHelpers : IO Unit := do
  expect (admittedBindingsV1.isEmpty) "Psy Phase D admit set must be empty"
  expect (!isPsyAdmittedPfAssetsQnV1 "pf.assets.native.deposit")
    "no QN is Psy-admitted"
  for qn in pfAssetsCatalogQualifiedNamesV1 do
    expect (isPfAssetsCatalogQnV1 qn) s!"catalog membership must include {qn}"
  expect (!isPfAssetsCatalogQnV1 "Peer.go") "non-catalog must not match"
  expect ((unboundCatalogDiagV1 "pf.assets.native.deposit").contains "unbound")
    "unbound diagnostic must cite unbound"

/-- One catalog QN (+ extension) → resolve PF-REQ-UNSUPPORTED. -/
unsafe def expectUnsupportedAtResolve (label qn callLine extraParams : String) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    s!"program {label} where\n" ++
    pfAssetsRequiresBlock ++
    "  state tips : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    tips := initial\n" ++
    s!"  entry tip({extraParams}) : UInt64 do\n" ++
    s!"    {callLine}\n" ++
    "    return amount\n" ++
    "  view get() : UInt64 do\n" ++
    "    return tips\n"
  let compiled ← compileSource s!"<psy-pf-assets-{label}>" s!"Tests.Psy{label}" source
  match resolvePsy compiled with
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED")
        s!"{qn}: must fail at resolve with PF-REQ-UNSUPPORTED, got {e.render}"
  | .ok _ =>
      throw <| IO.userError
        s!"{qn}: Psy must not resolve a program that requires extension.pf-assets"

/-- Five catalog QNs: exact resolve failure (zero-binding — no Psy permit). -/
unsafe def testFiveCatalogQnsFailAtResolve : IO Unit := do
  expectUnsupportedAtResolve "Dep" "pf.assets.native.deposit"
    "call pf.assets.native.deposit(amount)" "amount : UInt64"
  expectUnsupportedAtResolve "Xfer" "pf.assets.native.transfer"
    "call pf.assets.native.transfer(dst, amount)"
    "dst : Principal, amount : UInt64"
  expectUnsupportedAtResolve "XferAsync" "pf.assets.native.transferAsync"
    "call pf.assets.native.transferAsync(dst, amount)"
    "dst : Principal, amount : UInt64"
  expectUnsupportedAtResolve "Tok" "pf.assets.token.transfer"
    "call pf.assets.token.transfer(mint, dst, amount)"
    "mint : Principal, dst : Principal, amount : UInt64"
  expectUnsupportedAtResolve "TokAsync" "pf.assets.token.transferAsync"
    "call pf.assets.token.transferAsync(mint, dst, amount)"
    "mint : Principal, dst : Principal, amount : UInt64"

/-- Deposit without extension: resolve OK (sync-call only), Plan unbound FC.
    This is the Plan-level pin that `__invoke_sync` must not fake vault deposit. -/
unsafe def testDepositUnboundAtPlan : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program DepNoExt where\n" ++
    "  state tips : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    tips := initial\n" ++
    "  entry tip(amount : UInt64) : UInt64 do\n" ++
    "    call pf.assets.native.deposit(amount)\n" ++
    "    return amount\n" ++
    "  view get() : UInt64 do\n" ++
    "    return tips\n"
  let compiled ← compileSource "<psy-pf-assets-dep-noext>" "Tests.PsyDepNoExt" source
  -- Resolve must succeed (Psy advertises sync-call; no extension row required).
  let _capability ← liftResult <| resolvePsy compiled
  match planPsyOf compiled with
  | .error (.planInvariant .psy msg) =>
      expect (msg.contains "unbound" && msg.contains "pf.assets.native.deposit")
        s!"deposit Plan must cite unbound+QN, got: {msg}"
      expect (!msg.contains "must have at least two components")
        "unbound path must be distinct from callee arity gate"
  | .error e =>
      throw <| IO.userError s!"expected planInvariant .psy, got {e.render}"
  | .ok _ =>
      throw <| IO.userError
        "deposit catalog QN must fail closed at Psy Plan (unbound; no fake vault)"

/-- Non-catalog L0 call still materializes (Phase D must not broaden FC). -/
unsafe def testNonCatalogCallStillLowers : IO Unit := do
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
  let compiled ← compileSource "<psy-pf-assets-oracle>" "Tests.PsyPfAssetsOracle" source
  let plan ← liftResult <| planPsyOf compiled
  liftResult <| Targets.Psy.validatePlan plan

unsafe def run : IO Unit := do
  testDispositionHelpers
  testFiveCatalogQnsFailAtResolve
  testDepositUnboundAtPlan
  testNonCatalogCallStillLowers
  IO.println "Tests.Materialization.PsyPfAssetsV1: ok"

end Tests.Materialization.PsyPfAssetsV1
