/-
  Tests.Product.TokenJarSolanaV1 — ADR-0030 E1b product vertical.

  Authority: shipped `Examples/TokenJar.lean`.
    * `check --target solana --profile solana-sbpf-cpi-elf-v1` accepts pf.assets
      extension + sync-call
    * `build --target solana --profile solana-sbpf-cpi-elf-v1` now succeeds
      (composite ATA-ensure + transferCheckedPda emitter implemented);
      produces ELF `.so` + manifest with exact closure
    * default solana profile (plan-v1) fails closed
    * engineering product path only: non-formal, non-mainnet
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import Tests.Language.ParserSession

namespace Tests.Product.TokenJarSolanaV1

open System
open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def containsSubstr (s sub : String) : Bool :=
  let rec loop (cs : List Char) : Bool :=
    match cs with
    | [] => sub.isEmpty
    | _ :: rest =>
      if sub.toList.isPrefixOf cs then true else loop rest
  loop s.toList

private def shippedPath : FilePath := FilePath.mk "Examples/TokenJar.lean"

private def pfAssetsDigestV1 : String :=
  "sha256:97dfde7f7df228230828db4273086224bc28a4bc88c2f25457eaf0aee22aeeed"

private def readShipped : IO String := do
  unless ← shippedPath.pathExists do
    throw <| IO.userError "Examples/TokenJar.lean missing (ADR-0030 E1b vector)"
  IO.FS.readFile shippedPath

private def assertShape (text : String) : IO Unit := do
  expect (containsSubstr text "program TokenJar where")
    "must declare program TokenJar"
  expect (containsSubstr text "requires extension pf.assets version \"1.0.0\"")
    "must declare exact pf.assets extension triple"
  expect (containsSubstr text pfAssetsDigestV1)
    "must pin frozen pf.assets domain digest"
  expect (containsSubstr text "call pf.assets.token.transfer(mint, dst, amount)")
    "must call pf.assets.token.transfer"
  expect (containsSubstr text "entry tipToken(mint : Principal, dst : Principal, amount : UInt64)")
    "must declare tipToken entry with mint/dst/amount"

private def cliBin : FilePath := FilePath.mk ".lake/build/bin/proof-forge-next"

private def runCli (args : Array String) : IO (UInt32 × String × String) := do
  unless ← cliBin.pathExists do
    throw <| IO.userError "proof-forge-next missing (build product CLI)"
  let absoluteCli ← IO.FS.realPath cliBin
  let out ← IO.Process.output { cmd := absoluteCli.toString, args }
  pure (out.exitCode, out.stdout, out.stderr)

private def testSolanaCpiCheckAndBuild : IO Unit := do
  assertShape (← readShipped)
  -- check must accept pf.assets + sync-call on CPI profile.
  let (cc, cout, cerr) ← runCli
    #["check", "Examples/TokenJar.lean",
      "--module", "Examples.TokenJar",
      "--target", "solana",
      "--profile", "solana-sbpf-cpi-elf-v1"]
  expect (cc == 0)
    s!"TokenJar check --target solana --profile cpi must succeed, exit={cc} stderr={cerr} stdout={cout}"
  expect (containsSubstr cout "solana")
    s!"check must pin solana, stdout={cout}"
  expect (containsSubstr cout "solana-sbpf-cpi-elf-v1")
    s!"check must pin cpi profile, stdout={cout}"
  -- build must now succeed (composite emitter implemented).
  let outDir := FilePath.mk "build/v2/tokenjar-solana"
  try IO.FS.removeDirAll outDir catch _ => pure ()
  let (code, stdout, stderr) ← runCli
    #["build", "Examples/TokenJar.lean",
      "--module", "Examples.TokenJar",
      "--target", "solana",
      "--profile", "solana-sbpf-cpi-elf-v1",
      "-o", outDir.toString]
  expect (code == 0)
    s!"TokenJar build must succeed, exit={code} stdout={stdout} stderr={stderr}"
  -- ELF must exist.
  let elfPath := outDir.join "TokenJar.so"
  expect (← elfPath.pathExists)
    s!"build must produce TokenJar.so"
  -- Manifest must exist and validate.
  let manifestPath := outDir.join "manifest.json"
  expect (← manifestPath.pathExists)
    s!"build must produce manifest.json"
  -- inspect must validate exact closure.
  let (ic, iout, ierr) ← runCli #["inspect", outDir.toString, "--json"]
  expect (ic == 0)
    s!"inspect must succeed, exit={ic} stdout={iout} stderr={ierr}"
  expect (containsSubstr iout "\"deployable\":true")
    s!"inspect must report deployable=true, got={iout}"
  expect (containsSubstr iout "TokenJar.so")
    s!"inspect must list TokenJar.so, got={iout}"

private def testDefaultSolanaStillFailClosed : IO Unit := do
  assertShape (← readShipped)
  let outDir := FilePath.mk "build/v2/tokenjar-solana-default-negative"
  try IO.FS.removeDirAll outDir catch _ => pure ()
  let (code, stdout, stderr) ← runCli
    #["build", "Examples/TokenJar.lean",
      "--module", "Examples.TokenJar",
      "--target", "solana",
      "-o", outDir.toString]
  expect (code != 0)
    s!"TokenJar default solana profile must fail closed, exit={code}"
  let combined := stdout ++ stderr
  expect (containsSubstr combined "PF-REQ-UNSUPPORTED")
    s!"default solana must PF-REQ-UNSUPPORTED, got={combined}"
  expect (!(← outDir.pathExists))
    s!"default solana must leave zero published artifacts"

unsafe def run : IO Unit := do
  testSolanaCpiCheckAndBuild
  testDefaultSolanaStillFailClosed
  IO.println "Tests.Product.TokenJarSolanaV1: ok"

end Tests.Product.TokenJarSolanaV1