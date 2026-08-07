/-
  Tests.Product.MiniAmmProofSurfaceV1 — RESEARCH-023 L0 product pin.

  Authority: shipped `Examples/MiniAmmProofSurface.lean`.
    * platform simple-closure L0 sample (not MiniAmm-only machinery)
    * product `check` → proofStatus=certified
    * does NOT claim L1 business preservation or formal TASK-D2-07
    * build --target solana with nonempty invariant remains materializer FC
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import Tests.Language.ParserSession

namespace Tests.Product.MiniAmmProofSurfaceV1

open System
open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def containsSubstr (s sub : String) : Bool :=
  (s.splitOn sub).length > 1

private def shippedPath : FilePath := FilePath.mk "Examples/MiniAmmProofSurface.lean"

private def readShipped : IO String := do
  unless ← shippedPath.pathExists do
    throw <| IO.userError "Examples/MiniAmmProofSurface.lean missing (L0 formalization surface)"
  IO.FS.readFile shippedPath

private def assertShape (text : String) : IO Unit := do
  expect (containsSubstr text "program MiniAmmProofSurface where")
    "must declare MiniAmmProofSurface"
  expect (containsSubstr text "invariant l0Surface : true")
    "must declare neutral L0 invariant (not a business safety claim)"
  expect (containsSubstr text "proof l0Surface using")
    "must bind proof reference"
  expect (containsSubstr text "generatedL0SurfaceV1")
    "author theorem must exact generated L0 helper"
  expect (containsSubstr text "RESEARCH-023")
    "must point at formalization ladder"
  expect (!containsSubstr text "state reserve0")
    "L0 surface must not embed full MiniAmm state (simple-closure family only)"

private def cliBin : FilePath := FilePath.mk ".lake/build/bin/proof-forge-next"

private def runCli (args : Array String) : IO (UInt32 × String × String) := do
  unless ← cliBin.pathExists do
    throw <| IO.userError "proof-forge-next missing (build product CLI)"
  let absoluteCli ← IO.FS.realPath cliBin
  let out ← IO.Process.output { cmd := absoluteCli.toString, args }
  pure (out.exitCode, out.stdout, out.stderr)

private def testCheckCertified : IO Unit := do
  assertShape (← readShipped)
  let (code, stdout, stderr) ← runCli
    #["check", "Examples/MiniAmmProofSurface.lean",
      "--module", "Examples.MiniAmmProofSurface"]
  expect (code == 0)
    s!"L0 check must succeed, exit={code} stderr={stderr} stdout={stdout}"
  expect (containsSubstr stdout "proofStatus=certified")
    s!"must report proofStatus=certified, stdout={stdout}"
  expect (
      containsSubstr stdout "proofTheoremCount=1" ||
      containsSubstr stdout "proofCount=1")
    s!"must report one certified theorem, stdout={stdout}"

private def testSolanaBuildFailClosedOnInvariant : IO Unit := do
  let outDir := FilePath.mk "build/v2/miniamm-proof-surface-solana-fc"
  try IO.FS.removeDirAll outDir catch _ => pure ()
  let (code, stdout, stderr) ← runCli
    #["build", "Examples/MiniAmmProofSurface.lean",
      "--module", "Examples.MiniAmmProofSurface",
      "--target", "solana",
      "--profile", "solana-sbpf-cpi-elf-v1",
      "-o", outDir.toString]
  expect (code != 0)
    s!"nonempty invariant materialize must fail closed, got exit={code} stdout={stdout}"
  expect (
      containsSubstr stderr "invariant" ||
      containsSubstr stderr "unsupported" ||
      containsSubstr stdout "invariant" ||
      containsSubstr stderr "fail")
    s!"FC diagnostics should mention invariant/unsupported:\n{stderr}\n{stdout}"

unsafe def run : IO Unit := do
  testCheckCertified
  testSolanaBuildFailClosedOnInvariant
  IO.println "Tests.Product.MiniAmmProofSurfaceV1: ok"

end Tests.Product.MiniAmmProofSurfaceV1
