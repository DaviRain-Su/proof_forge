/-
  Tests.Materialization.SolanaProductSynthesizeV1 — ADR-0032 U1 P3-c/d pins.

  * P3-d explicit gate: Map/CFG body + CPI sites → stable planInvariant
  * Escrow path (TipJar-class) still builds under synthesize dispatch
  * Engineering only
-/
import ProofForgeV2.Targets.Solana
import ProofForgeV2.Targets.Solana.ProductSynthesizeV1
import ProofForgeV2.Targets.Solana.ProductFrameV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.DiagnosticBundleV1
import Tests.Language.ParserSession

namespace Tests.Materialization.SolanaProductSynthesizeV1

open System
open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Targets
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Solana
open ProofForgeV2.Targets.Solana.ProductFrameV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def containsSubstr (s sub : String) : Bool :=
  (s.splitOn sub).length > 1

private def expectOk {α : Type} (result : CompileResult α) (label : String) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def pfAssetsDigest : String :=
  "sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9"

/-- Map + pf.assets transfer: needs full body AND cpiSites (P3-d hole). -/
private def mapTipCallSource : String :=
  "import ProofForgeV2\n\nnamespace Examples\n\nopen ProofForgeV2.Language\n\n" ++
  "program MapTipCall where\n" ++
  "  requires extension pf.assets version \"1.1.0\"\n" ++
  "    digest \"" ++ pfAssetsDigest ++ "\"\n\n" ++
  "  state tips : Map Principal UInt64\n\n" ++
  "  init() do\n" ++
  "    tips := Map.empty()\n\n" ++
  "  entry tip(dst : Principal, amount : UInt64) : UInt64 do\n" ++
  "    assert amount > 0\n" ++
  "    call pf.assets.native.transfer(dst, amount)\n" ++
  "    match tips[dst] with\n" ++
  "    | Option.some(v) => do\n" ++
  "      tips[dst] := v + amount\n" ++
  "      return v + amount\n" ++
  "    | _ => do\n" ++
  "      tips[dst] := amount\n" ++
  "      return amount\n\n" ++
  "end Examples\n"

private unsafe def compileSourceText
    (session : Language.Loader.ParserSession)
    (sourceText path moduleName : String) : IO CompiledSemanticV1 := do
  let (source, origins) ← match ← session.selectProgramV1WithOrigins
      sourceText path moduleName none with
    | .ok pair => pure pair
    | .error error =>
        throw <| IO.userError s!"load {moduleName}: {error.render}"
  match compileProgramProductV1 source origins with
  | .ok compiled => pure compiled
  | .error bundle =>
      throw <| IO.userError
        s!"product compile rejected {moduleName}: {DiagnosticBundleV1.renderHuman bundle}"

private def resolveSolanaCpi (compiled : CompiledSemanticV1) :
    IO ResolvedEngineeringBuildV1 := do
  let sel ← expectOk
    (resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfCpiElfV1))
    "resolve CPI selection"
  expectOk (resolveEngineeringRequirementsV1 sel compiled)
    "resolve engineering"

private unsafe def testP3dGateMapPlusCpi : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let compiled ← compileSourceText session mapTipCallSource
    "Examples/MapTipCall.lean" "Examples.MapTipCall"
  let capability ← resolveSolanaCpi compiled
  match buildFromCapability capability with
  | .ok _ =>
      throw <| IO.userError
        "MapTipCall must fail closed until P3-d site+full-body synthesis lands"
  | .error e => do
      expect (e.code == "PF-PLAN-INVARIANT")
        s!"expected PF-PLAN-INVARIANT, got {e.render}"
      expect (containsSubstr e.render "P3-d incomplete")
        s!"expected P3-d incomplete message, got {e.render}"
      expect (containsSubstr e.render "cpiSites")
        s!"expected cpiSites mention, got {e.render}"
  IO.println "  P3-d gate (Map+CPI) ok"

private def testEscrowFramePinsCompatible : IO Unit := do
  let bodyTempBytes := productEscrowTempRegionEndV1 - productEscrowTempBaseV1
  let cpiScratchBytes := productMaxFrameBytesV1 - productEscrowTempRegionEndV1
  match mintUnifiedCpiFrameV1 bodyTempBytes cpiScratchBytes with
  | .error e => throw <| IO.userError s!"escrow-compatible frame must mint: {e}"
  | .ok L => do
      expect (L.totalBytes == productMaxFrameBytesV1)
        s!"escrow-compatible unified frame should fill stack, got {L.totalBytes}"
      expect (L.bodyTempStart == productEscrowTempBaseV1) "body at 1096"
  IO.println "  escrow-compatible unified frame pin ok"

private unsafe def testTipJarStillBuildsViaSynthesizeDispatch : IO Unit := do
  let path := FilePath.mk "Examples/TipJar.lean"
  unless ← path.pathExists do
    throw <| IO.userError "Examples/TipJar.lean missing"
  let text ← IO.FS.readFile path
  let session ← Tests.Language.ParserSession.shared
  let compiled ← compileSourceText session text
    "Examples/TipJar.lean" "Examples.TipJar"
  let capability ← resolveSolanaCpi compiled
  let files ← expectOk (buildFromCapability capability)
    "TipJar buildFromCapability"
  expect (files.any fun f => f.path == "TipJar.s")
    "TipJar must emit TipJar.s via synthesize dispatch → escrow"
  expect (files.any fun f => f.path == "TipJar.cpi-plan.json")
    "TipJar must emit cpi-plan"
  let some asm := files.find? (·.path == "TipJar.s") |
    throw <| IO.userError "missing TipJar.s"
  expect (containsSubstr asm.contents "sol_invoke_signed_c")
    "TipJar assembly must still invoke signed"
  IO.println "  TipJar synthesize→escrow path ok"

unsafe def run : IO Unit := do
  testEscrowFramePinsCompatible
  testP3dGateMapPlusCpi
  testTipJarStillBuildsViaSynthesizeDispatch
  IO.println "Tests.Materialization.SolanaProductSynthesizeV1: ok"

end Tests.Materialization.SolanaProductSynthesizeV1
