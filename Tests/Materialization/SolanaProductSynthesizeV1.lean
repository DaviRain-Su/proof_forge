/-
  Tests.Materialization.SolanaProductSynthesizeV1 — ADR-0032 U1 P3-c/d pins.

  * P3-d partial: Map/CFG body + CPI sites → full-body + empty-meta sol_invoke
  * Escrow path (TipJar-class) still builds under synthesize dispatch
  * Engineering only — not multi-role AccountMeta maturity
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

/-- Multi-block if + pf.assets transfer: needs full body AND cpiSites (P3-d partial).
    (Map Principal match+IndexSet in a single block still hits a pre-existing
    effect-boundary lower limitation; MiniAmm-shaped multi-block Map works, but
    BodyCpiIfPay is the minimal P3-d pin.) -/
private def bodyCpiIfPaySource : String :=
  "import ProofForgeV2\n\nnamespace Examples\n\nopen ProofForgeV2.Language\n\n" ++
  "program BodyCpiIfPay where\n" ++
  "  requires extension pf.assets version \"1.1.0\"\n" ++
  "    digest \"" ++ pfAssetsDigest ++ "\"\n\n" ++
  "  state paid : UInt64\n\n" ++
  "  init() do\n" ++
  "    paid := 0\n\n" ++
  "  entry pay(dst : Principal, amount : UInt64) : UInt64 do\n" ++
  "    if amount > 0 then\n" ++
  "      call pf.assets.native.transfer(dst, amount)\n" ++
  "      paid := paid + amount\n" ++
  "      return paid\n" ++
  "    else\n" ++
  "      return paid\n\n" ++
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

/-- P3-d partial: multi-block CFG + CPI sites → one ELF with body + empty-meta. -/
private unsafe def testP3dPartialBodyCpiIfPay : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let compiled ← compileSourceText session bodyCpiIfPaySource
    "Examples/BodyCpiIfPay.lean" "Examples.BodyCpiIfPay"
  let capability ← resolveSolanaCpi compiled
  let files ← expectOk (buildFromCapability capability)
    "BodyCpiIfPay P3-d partial buildFromCapability"
  expect (files.any fun f => f.path == "BodyCpiIfPay.s")
    "BodyCpiIfPay must emit BodyCpiIfPay.s"
  expect (files.any fun f => f.path == "BodyCpiIfPay.cpi-plan.json")
    "BodyCpiIfPay must emit cpi-plan (sites metadata)"
  expect (files.any fun f => f.path == "BodyCpiIfPay.cpi-ir.json")
    "BodyCpiIfPay must emit cpi-ir"
  let some asm := files.find? (·.path == "BodyCpiIfPay.s") |
    throw <| IO.userError "missing BodyCpiIfPay.s"
  expect (containsSubstr asm.contents "sol_invoke_signed_c")
    "BodyCpiIfPay body must emit empty-meta sol_invoke_signed_c"
  expect (containsSubstr asm.contents "product_external_call" ||
      containsSubstr asm.contents "empty AccountMeta")
    s!"BodyCpiIfPay asm must note product ExternalCall empty-meta path"
  let some ir := files.find? (·.path == "BodyCpiIfPay.cpi-ir.json") |
    throw <| IO.userError "missing BodyCpiIfPay.cpi-ir.json"
  expect (containsSubstr ir.contents "p3d-partial-empty-meta")
    s!"cpi-ir must mark p3d-partial-empty-meta, got={ir.contents}"
  expect (containsSubstr ir.contents "empty-meta-partial")
    s!"cpi-ir must mark cpiMaturity empty-meta-partial, got={ir.contents}"
  expect (containsSubstr ir.contents "\"admitProductExternalCall\":true")
    "cpi-ir must admit product ExternalCall"
  -- Honesty: must NOT claim multi-role AccountMeta maturity.
  expect (!containsSubstr ir.contents "multi-role-mature")
    "must not claim multi-role maturity"
  IO.println "  P3-d partial (BodyCpiIfPay empty-meta) ok"

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

/-- P3-f: shipped Map+CPI demo builds via synthesize (scratch discipline). -/
private unsafe def testP3fBodyCpiMapTipShipped : IO Unit := do
  let path := FilePath.mk "Examples/BodyCpiMapTip.lean"
  unless ← path.pathExists do
    throw <| IO.userError "Examples/BodyCpiMapTip.lean missing"
  let text ← IO.FS.readFile path
  let session ← Tests.Language.ParserSession.shared
  let compiled ← compileSourceText session text
    "Examples/BodyCpiMapTip.lean" "Examples.BodyCpiMapTip"
  let capability ← resolveSolanaCpi compiled
  let files ← expectOk (buildFromCapability capability)
    "BodyCpiMapTip buildFromCapability"
  expect (files.any fun f => f.path == "BodyCpiMapTip.s")
    "BodyCpiMapTip must emit .s"
  let some ir := files.find? (·.path == "BodyCpiMapTip.cpi-ir.json") |
    throw <| IO.userError "missing BodyCpiMapTip.cpi-ir.json"
  expect (containsSubstr ir.contents "p3d-partial-empty-meta")
    s!"MapTip cpi-ir must be p3d-partial, got={ir.contents}"
  let some asm := files.find? (·.path == "BodyCpiMapTip.s") |
    throw <| IO.userError "missing BodyCpiMapTip.s"
  expect (containsSubstr asm.contents "sol_invoke_signed_c")
    "MapTip body must emit empty-meta sol_invoke_signed_c"
  IO.println "  P3-f BodyCpiMapTip synthesize ok"

unsafe def run : IO Unit := do
  testEscrowFramePinsCompatible
  testP3dPartialBodyCpiIfPay
  testP3fBodyCpiMapTipShipped
  testTipJarStillBuildsViaSynthesizeDispatch
  IO.println "Tests.Materialization.SolanaProductSynthesizeV1: ok"

end Tests.Materialization.SolanaProductSynthesizeV1
