/-
  Tests.Product.BodyCpiSysPaySolanaV1 — ADR-0032 U1 P3-e foundation product pin.

  Authority: shipped `Examples/BodyCpiSysPay.lean`.
    * multi-block if + solana.system.transfer on cpi-elf rail
    * pins System program id (zeros) + 12B Transfer data packing
    * multi-role AccountMeta still deferred
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import ProofForgeV2.Targets.Solana.ProductCpiRecipesV1
import Tests.Language.ParserSession

namespace Tests.Product.BodyCpiSysPaySolanaV1

open System
open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Targets.Solana.ProductCpiRecipesV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def containsSubstr (s sub : String) : Bool :=
  (s.splitOn sub).length > 1

private def shippedPath : FilePath := FilePath.mk "Examples/BodyCpiSysPay.lean"

private def readShipped : IO String := do
  unless ← shippedPath.pathExists do
    throw <| IO.userError "Examples/BodyCpiSysPay.lean missing (P3-e foundation vector)"
  IO.FS.readFile shippedPath

private def assertShape (text : String) : IO Unit := do
  expect (containsSubstr text "program BodyCpiSysPay where")
    "must declare BodyCpiSysPay"
  expect (containsSubstr text "solana.system.transfer")
    "must call solana.system.transfer"
  expect (containsSubstr text "requires extension solana.cpi.accounts")
    "must require solana.cpi.accounts"
  expect (containsSubstr text "if bal >= amount")
    "must use multi-block if (needsFullBody)"

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
    #["check", "Examples/BodyCpiSysPay.lean",
      "--module", "Examples.BodyCpiSysPay",
      "--target", "solana",
      "--profile", "solana-sbpf-cpi-elf-v1"]
  expect (cc == 0)
    s!"BodyCpiSysPay check cpi must succeed, exit={cc} stderr={cerr} stdout={cout}"
  let outDir := FilePath.mk "build/v2/body-cpi-sys-pay-solana"
  try IO.FS.removeDirAll outDir catch _ => pure ()
  let (code, stdout, stderr) ← runCli
    #["build", "Examples/BodyCpiSysPay.lean",
      "--module", "Examples.BodyCpiSysPay",
      "--target", "solana",
      "--profile", "solana-sbpf-cpi-elf-v1",
      "-o", outDir.toString]
  expect (code == 0)
    s!"BodyCpiSysPay build cpi must succeed, exit={code} stderr={stderr} stdout={stdout}"
  expect (containsSubstr stdout "deployable=true")
    s!"build must report deployable=true, stdout={stdout}"
  unless ← (outDir / "BodyCpiSysPay.so").pathExists do
    throw <| IO.userError "must write BodyCpiSysPay.so"
  unless ← (outDir / "BodyCpiSysPay.s").pathExists do
    throw <| IO.userError "must write BodyCpiSysPay.s"
  let ir ← IO.FS.readFile (outDir / "BodyCpiSysPay.cpi-ir.json")
  expect (containsSubstr ir "p3e-system-transfer-empty-meta")
    s!"cpi-ir must mark p3e-system-transfer-empty-meta, got={ir}"
  expect (containsSubstr ir "empty-meta-partial-system-transfer")
    s!"cpi-ir must mark system-transfer maturity, got={ir}"
  expect (containsSubstr ir "\"outerRoleCount\":")
    s!"cpi-ir must record outerRoleCount, got={ir}"
  let asm ← IO.FS.readFile (outDir / "BodyCpiSysPay.s")
  expect (containsSubstr asm "sol_invoke_signed_c")
    "assembly must emit sol_invoke_signed_c"
  expect (containsSubstr asm ("program_id=0x" ++ systemProgramIdHexV1))
    "assembly must use native System program id (32 zeros)"
  expect (containsSubstr asm "SystemInstruction::Transfer" ||
      containsSubstr asm "system.transfer data layout")
    "assembly must note System transfer data packing"
  expect (containsSubstr asm "stxw")
    "assembly must stxw Transfer discriminant"
  expect (!containsSubstr asm "multi-role-mature")
    "must not claim multi-role maturity"
  let evidence ← IO.FS.readFile (outDir / "evidence.json")
  expect (containsSubstr evidence "irDigest=sha256:")
    s!"evidence content-bound irDigest, got={evidence}"
  let (iec, istdout, istderr) ← runCli
    #["inspect", outDir.toString, "--json"]
  expect (iec == 0)
    s!"inspect must succeed, exit={iec} stderr={istderr}"
  expect (containsSubstr istdout "\"target\":\"solana\"")
    s!"inspect json target, got={istdout.take 200}"
  IO.println "  BodyCpiSysPay solana-sbpf-cpi-elf-v1 product pin ok"

unsafe def run : IO Unit := do
  testSolanaCpiBuildAndInspect
  IO.println "Tests.Product.BodyCpiSysPaySolanaV1: ok"

end Tests.Product.BodyCpiSysPaySolanaV1
