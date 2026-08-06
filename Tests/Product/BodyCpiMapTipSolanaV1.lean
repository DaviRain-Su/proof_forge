/-
  Tests.Product.BodyCpiMapTipSolanaV1 — ADR-0032 U1 P3-f product pin.

  Authority: shipped `Examples/BodyCpiMapTip.lean`.
    * product `check/build --target solana --profile solana-sbpf-cpi-elf-v1`
      (Map + pf.assets transfer → hasSites ∧ needsFullBody → P3-d partial)
    * pins `p3d-partial-empty-meta`, empty-meta `sol_invoke_signed_c`, Map body
    * multi-role AccountMeta maturity **not** claimed
    * engineering only: non-formal, non-mainnet, not Mollusk
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import Tests.Language.ParserSession

namespace Tests.Product.BodyCpiMapTipSolanaV1

open System
open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def containsSubstr (s sub : String) : Bool :=
  (s.splitOn sub).length > 1

private def shippedPath : FilePath := FilePath.mk "Examples/BodyCpiMapTip.lean"

private def readShipped : IO String := do
  unless ← shippedPath.pathExists do
    throw <| IO.userError "Examples/BodyCpiMapTip.lean missing (ADR-0032 P3-f vector)"
  IO.FS.readFile shippedPath

private def assertShape (text : String) : IO Unit := do
  expect (containsSubstr text "program BodyCpiMapTip where")
    "must declare program BodyCpiMapTip"
  expect (containsSubstr text "state tips : Map Principal UInt64")
    "must declare Map Principal UInt64 tips"
  expect (containsSubstr text "state scratch : UInt64")
    "must use scratch across Map StateStore effect boundary"
  expect (containsSubstr text "requires extension pf.assets")
    "must require pf.assets"
  expect (containsSubstr text "call pf.assets.native.transfer")
    "must call pf.assets.native.transfer"
  expect (containsSubstr text "match tips[dst]")
    "must match on Map Principal key"
  expect (containsSubstr text "tips[dst] := scratch")
    "IndexSet RHS must be scratch (not pure binder expression)"

private def cliBin : FilePath := FilePath.mk ".lake/build/bin/proof-forge-next"

private def runCli (args : Array String) : IO (UInt32 × String × String) := do
  unless ← cliBin.pathExists do
    throw <| IO.userError "proof-forge-next missing (build product CLI)"
  let absoluteCli ← IO.FS.realPath cliBin
  let out ← IO.Process.output { cmd := absoluteCli.toString, args }
  pure (out.exitCode, out.stdout, out.stderr)

private def testSolanaCpiBuildAndInspect : IO Unit := do
  assertShape (← readShipped)
  let (cc, cout, cerr) ← runCli
    #["check", "Examples/BodyCpiMapTip.lean",
      "--module", "Examples.BodyCpiMapTip",
      "--target", "solana",
      "--profile", "solana-sbpf-cpi-elf-v1"]
  expect (cc == 0)
    s!"BodyCpiMapTip check cpi must succeed, exit={cc} stderr={cerr} stdout={cout}"
  expect (containsSubstr cout "solana-sbpf-cpi-elf-v1")
    s!"check must pin cpi profile, stdout={cout}"
  let outDir := FilePath.mk "build/v2/body-cpi-map-tip-solana"
  try IO.FS.removeDirAll outDir catch _ => pure ()
  let (code, stdout, stderr) ← runCli
    #["build", "Examples/BodyCpiMapTip.lean",
      "--module", "Examples.BodyCpiMapTip",
      "--target", "solana",
      "--profile", "solana-sbpf-cpi-elf-v1",
      "-o", outDir.toString]
  expect (code == 0)
    s!"BodyCpiMapTip build cpi must succeed, exit={code} stderr={stderr} stdout={stdout}"
  expect (containsSubstr stdout "profile=solana-sbpf-cpi-elf-v1")
    s!"build must pin cpi profile, stdout={stdout}"
  expect (containsSubstr stdout "deployable=true")
    s!"build must report deployable=true, stdout={stdout}"
  unless ← (outDir / "manifest.json").pathExists do
    throw <| IO.userError "must write manifest.json"
  unless ← (outDir / "BodyCpiMapTip.so").pathExists do
    throw <| IO.userError "must write BodyCpiMapTip.so"
  unless ← (outDir / "BodyCpiMapTip.s").pathExists do
    throw <| IO.userError "must write BodyCpiMapTip.s"
  unless ← (outDir / "BodyCpiMapTip.cpi-plan.json").pathExists do
    throw <| IO.userError "must write cpi-plan"
  unless ← (outDir / "BodyCpiMapTip.cpi-ir.json").pathExists do
    throw <| IO.userError "must write cpi-ir"
  let ir ← IO.FS.readFile (outDir / "BodyCpiMapTip.cpi-ir.json")
  expect (containsSubstr ir "p3d-partial-empty-meta")
    s!"cpi-ir must mark p3d-partial-empty-meta, got={ir}"
  expect (containsSubstr ir "empty-meta-partial")
    s!"cpi-ir must mark empty-meta-partial maturity, got={ir}"
  expect (containsSubstr ir "\"admitProductExternalCall\":true")
    s!"cpi-ir must admit product ExternalCall, got={ir}"
  expect (!containsSubstr ir "multi-role-mature")
    "must not claim multi-role maturity"
  let plan ← IO.FS.readFile (outDir / "BodyCpiMapTip.cpi-plan.json")
  expect (containsSubstr plan "pf.assets.native.transfer" ||
      containsSubstr plan "native.transfer")
    s!"cpi-plan must list transfer site, got head={plan.take 400}"
  let asm ← IO.FS.readFile (outDir / "BodyCpiMapTip.s")
  expect (containsSubstr asm "sol_invoke_signed_c")
    "assembly must emit sol_invoke_signed_c (empty-meta partial)"
  expect (containsSubstr asm "empty AccountMeta" ||
      containsSubstr asm "product_external_call")
    "assembly must note empty-meta product ExternalCall path"
  let evidence ← IO.FS.readFile (outDir / "evidence.json")
  expect (containsSubstr evidence "irDigest=full-body-hybrid")
    s!"evidence must pin irDigest=full-body-hybrid, got={evidence}"
  let (iec, istdout, istderr) ← runCli
    #["inspect", outDir.toString, "--json"]
  expect (iec == 0)
    s!"inspect must succeed, exit={iec} stderr={istderr}"
  expect (containsSubstr istdout "\"target\":\"solana\"")
    s!"inspect json target, got={istdout.take 200}"
  IO.println "  BodyCpiMapTip solana-sbpf-cpi-elf-v1 product pin ok"

unsafe def run : IO Unit := do
  testSolanaCpiBuildAndInspect
  IO.println "Tests.Product.BodyCpiMapTipSolanaV1: ok"

end Tests.Product.BodyCpiMapTipSolanaV1
