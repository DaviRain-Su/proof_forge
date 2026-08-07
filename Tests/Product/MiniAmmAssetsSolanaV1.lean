/-
  Tests.Product.MiniAmmAssetsSolanaV1 — ADR-0030 M4c multi-role dual-mint product pin.

  Authority: shipped `Examples/MiniAmmAssets.lean`.
    * Map Principal LP + multi-site pf.assets.token.transfer on cpi-elf rail
    * pins m4b-token-transfer-multi-role / outerRoleCount=21 / 4 token sites
    * denseMapPrincipal specialized ops keep handler temps under multi-role frame
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import Tests.Language.ParserSession

namespace Tests.Product.MiniAmmAssetsSolanaV1

open System
open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def containsSubstr (s sub : String) : Bool :=
  (s.splitOn sub).length > 1

private def shippedPath : FilePath := FilePath.mk "Examples/MiniAmmAssets.lean"

private def readShipped : IO String := do
  unless ← shippedPath.pathExists do
    throw <| IO.userError "Examples/MiniAmmAssets.lean missing (M4c dual-mint vector)"
  IO.FS.readFile shippedPath

private def assertShape (text : String) : IO Unit := do
  expect (containsSubstr text "program MiniAmmAssets where")
    "must declare MiniAmmAssets"
  expect (containsSubstr text "pf.assets.token.transfer")
    "must call pf.assets.token.transfer"
  expect (containsSubstr text "Map Principal UInt64")
    "must use Map Principal LP balances"
  expect (containsSubstr text "removeLiquidity")
    "must declare removeLiquidity dual transfer"

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
    #["check", "Examples/MiniAmmAssets.lean",
      "--module", "Examples.MiniAmmAssets",
      "--target", "solana",
      "--profile", "solana-sbpf-cpi-elf-v1"]
  expect (cc == 0)
    s!"MiniAmmAssets check cpi must succeed, exit={cc} stderr={cerr} stdout={cout}"
  let outDir := FilePath.mk "build/v2/miniamm-assets-solana"
  try IO.FS.removeDirAll outDir catch _ => pure ()
  let (code, stdout, stderr) ← runCli
    #["build", "Examples/MiniAmmAssets.lean",
      "--module", "Examples.MiniAmmAssets",
      "--target", "solana",
      "--profile", "solana-sbpf-cpi-elf-v1",
      "-o", outDir.toString]
  expect (code == 0)
    s!"MiniAmmAssets build cpi must succeed, exit={code} stderr={stderr} stdout={stdout}"
  expect (containsSubstr stdout "deployable=true")
    s!"build must report deployable=true, stdout={stdout}"
  unless ← (outDir / "MiniAmmAssets.so").pathExists do
    throw <| IO.userError "must write MiniAmmAssets.so"
  unless ← (outDir / "MiniAmmAssets.s").pathExists do
    throw <| IO.userError "must write MiniAmmAssets.s"
  let ir ← IO.FS.readFile (outDir / "MiniAmmAssets.cpi-ir.json")
  expect (containsSubstr ir "m4b-token-transfer-multi-role")
    s!"cpi-ir must mark m4b-token-transfer-multi-role, got={ir}"
  expect (containsSubstr ir "multi-role-token-transfer")
    s!"cpi-ir must mark multi-role token maturity, got={ir}"
  expect (containsSubstr ir "\"frameMode\":\"unifiedCpi\"")
    s!"cpi-ir must use unifiedCpi frame, got={ir}"
  expect (containsSubstr ir "\"outerRoleCount\":21")
    s!"cpi-ir must pin outerRoleCount=21, got={ir}"
  expect (containsSubstr ir "\"cpiSites\":4")
    s!"cpi-ir must pin cpiSites=4 dual-mint, got={ir}"
  expect (!containsSubstr ir "empty-meta")
    s!"multi-role path must not mark empty-meta, got={ir}"
  let asm ← IO.FS.readFile (outDir / "MiniAmmAssets.s")
  expect (containsSubstr asm "sol_invoke_signed_c")
    "assembly must emit sol_invoke_signed_c"
  expect (containsSubstr asm "mr_parse_role")
    "assembly must walk outer roles"
  expect (containsSubstr asm "product_mr_token_0")
    "assembly must emit multi-site token site 0"
  expect (containsSubstr asm "product_mr_token_1")
    "assembly must emit multi-site token site 1"
  expect (containsSubstr asm "product_mr_token_2")
    "assembly must emit multi-site token site 2"
  expect (containsSubstr asm "product_mr_token_3")
    "assembly must emit multi-site token site 3"
  expect (containsSubstr asm "TransferChecked")
    "assembly must emit TransferChecked"
  expect (containsSubstr asm "createIdempotent")
    "assembly must emit ATA createIdempotent"
  expect (containsSubstr asm ".equ ROLE_BASE, 0x540")
    "assembly ROLE_BASE must be 21×64=1344 (0x540)"
  expect (!containsSubstr asm "empty AccountMeta")
    "multi-role path must not claim empty AccountMeta"
  -- Map Principal specialized ops keep multi-role frame budget honest.
  expect (containsSubstr asm "handler addLiquidity (temps=102)")
    "addLiquidity temps must stay specialized-map bound (102)"
  expect (containsSubstr asm "handler removeLiquidity (temps=102)")
    "removeLiquidity temps must stay specialized-map bound (102)"
  expect (containsSubstr asm "handler balanceOf (temps=55)")
    "balanceOf temps must stay specialized-map lookup bound (55)"
  let evidence ← IO.FS.readFile (outDir / "evidence.json")
  expect (containsSubstr evidence "irDigest=sha256:")
    s!"evidence content-bound irDigest, got={evidence}"
  let bindings ← IO.FS.readFile (outDir / "MiniAmmAssets.cpi-bindings.json")
  expect (containsSubstr bindings "m4b-token-transfer-multi-role")
    s!"bindings must pin multi-role synthesize tag, got={bindings}"
  let (iec, istdout, istderr) ← runCli
    #["inspect", outDir.toString, "--json"]
  expect (iec == 0)
    s!"inspect must succeed, exit={iec} stderr={istderr}"
  expect (containsSubstr istdout "\"target\":\"solana\"")
    s!"inspect json target, got={istdout.take 200}"
  IO.println "  MiniAmmAssets solana-sbpf-cpi-elf-v1 multi-role dual-mint product pin ok"

unsafe def run : IO Unit := do
  testSolanaCpiBuildAndInspect
  IO.println "Tests.Product.MiniAmmAssetsSolanaV1: ok"

end Tests.Product.MiniAmmAssetsSolanaV1
