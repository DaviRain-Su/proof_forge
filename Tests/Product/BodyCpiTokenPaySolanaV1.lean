/-
  Tests.Product.BodyCpiTokenPaySolanaV1 — ADR-0030 M4b multi-role token product pin.

  Authority: shipped `Examples/BodyCpiTokenPay.lean`.
    * multi-block if + pf.assets.token.transfer on cpi-elf rail
    * pins multi-role outer walk + ATA ensure + transferCheckedPda
    * MiniAmmAssets dual-mint multi-site is M4c (MiniAmmAssetsSolanaV1)
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import ProofForgeV2.Targets.Solana.ProductCpiRecipesV1
import Tests.Language.ParserSession

namespace Tests.Product.BodyCpiTokenPaySolanaV1

open System
open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Targets.Solana.ProductCpiRecipesV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def containsSubstr (s sub : String) : Bool :=
  (s.splitOn sub).length > 1

private def shippedPath : FilePath := FilePath.mk "Examples/BodyCpiTokenPay.lean"

private def readShipped : IO String := do
  unless ← shippedPath.pathExists do
    throw <| IO.userError "Examples/BodyCpiTokenPay.lean missing (M4b multi-role vector)"
  IO.FS.readFile shippedPath

private def assertShape (text : String) : IO Unit := do
  expect (containsSubstr text "program BodyCpiTokenPay where")
    "must declare BodyCpiTokenPay"
  expect (containsSubstr text "pf.assets.token.transfer")
    "must call pf.assets.token.transfer"
  expect (containsSubstr text "requires extension pf.assets")
    "must require pf.assets"
  expect (containsSubstr text "if paid >= amount")
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
    #["check", "Examples/BodyCpiTokenPay.lean",
      "--module", "Examples.BodyCpiTokenPay",
      "--target", "solana",
      "--profile", "solana-sbpf-cpi-elf-v1"]
  expect (cc == 0)
    s!"BodyCpiTokenPay check cpi must succeed, exit={cc} stderr={cerr} stdout={cout}"
  let outDir := FilePath.mk "build/v2/body-cpi-token-pay-solana"
  try IO.FS.removeDirAll outDir catch _ => pure ()
  let (code, stdout, stderr) ← runCli
    #["build", "Examples/BodyCpiTokenPay.lean",
      "--module", "Examples.BodyCpiTokenPay",
      "--target", "solana",
      "--profile", "solana-sbpf-cpi-elf-v1",
      "-o", outDir.toString]
  expect (code == 0)
    s!"BodyCpiTokenPay build cpi must succeed, exit={code} stderr={stderr} stdout={stdout}"
  expect (containsSubstr stdout "deployable=true")
    s!"build must report deployable=true, stdout={stdout}"
  unless ← (outDir / "BodyCpiTokenPay.so").pathExists do
    throw <| IO.userError "must write BodyCpiTokenPay.so"
  unless ← (outDir / "BodyCpiTokenPay.s").pathExists do
    throw <| IO.userError "must write BodyCpiTokenPay.s"
  let ir ← IO.FS.readFile (outDir / "BodyCpiTokenPay.cpi-ir.json")
  expect (containsSubstr ir "m4b-token-transfer-multi-role")
    s!"cpi-ir must mark m4b-token-transfer-multi-role, got={ir}"
  expect (containsSubstr ir "multi-role-token-transfer")
    s!"cpi-ir must mark multi-role token-transfer maturity, got={ir}"
  expect (containsSubstr ir "\"frameMode\":\"unifiedCpi\"")
    s!"cpi-ir must use unifiedCpi frame, got={ir}"
  expect (!containsSubstr ir "empty-meta-partial")
    s!"multi-role path must not mark empty-meta-partial, got={ir}"
  let asm ← IO.FS.readFile (outDir / "BodyCpiTokenPay.s")
  expect (containsSubstr asm "sol_invoke_signed_c")
    "assembly must emit sol_invoke_signed_c"
  expect (containsSubstr asm "mr_parse_role")
    "assembly must walk outer roles (mr_parse_role)"
  expect (containsSubstr asm "product_mr_token")
    "assembly must emit multi-role token.transfer site"
  expect (containsSubstr asm "pf.assets.token.transfer multi-role AccountMeta")
    "assembly must note multi-role AccountMeta maturity"
  expect (containsSubstr asm "TransferChecked")
    "assembly must emit TransferChecked tag"
  expect (containsSubstr asm "createIdempotent")
    "assembly must emit ATA createIdempotent ensure"
  expect (containsSubstr asm "sol_try_find_program_address")
    "assembly must find vault PDA for invoke_signed"
  expect (!containsSubstr asm "empty AccountMeta")
    "multi-role path must not claim empty AccountMeta"
  let evidence ← IO.FS.readFile (outDir / "evidence.json")
  expect (containsSubstr evidence "irDigest=sha256:")
    s!"evidence content-bound irDigest, got={evidence}"
  let bindings ← IO.FS.readFile (outDir / "BodyCpiTokenPay.cpi-bindings.json")
  expect (containsSubstr bindings "m4b-token-transfer-multi-role")
    s!"bindings must pin multi-role synthesize tag, got={bindings}"
  expect (containsSubstr bindings "\"frameMode\":\"unifiedCpi\"")
    s!"bindings must pin unifiedCpi, got={bindings}"
  let (iec, istdout, istderr) ← runCli
    #["inspect", outDir.toString, "--json"]
  expect (iec == 0)
    s!"inspect must succeed, exit={iec} stderr={istderr}"
  expect (containsSubstr istdout "\"target\":\"solana\"")
    s!"inspect json target, got={istdout.take 200}"
  IO.println "  BodyCpiTokenPay solana-sbpf-cpi-elf-v1 multi-role token product pin ok"

unsafe def run : IO Unit := do
  testSolanaCpiBuildAndInspect
  IO.println "Tests.Product.BodyCpiTokenPaySolanaV1: ok"

end Tests.Product.BodyCpiTokenPaySolanaV1
