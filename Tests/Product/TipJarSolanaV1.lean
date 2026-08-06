/-
  Tests.Product.TipJarSolanaV1 — ADR-0029 Phase B1 product vertical.

  Authority: shipped `Examples/TipJar.lean`.
    * product `build --target solana --profile solana-sbpf-cpi-elf-v1`
      emits proof-forge.output.v1 + ELF + CPI bases
    * `inspect <out> --json` revalidates exact disk closure
    * pins profile, TipJar artifact name, extension.pf-assets support claim
    * ADR-0032 P4: default Solana profile is sole rail cpi-elf
    * plan shim still fails closed (no sync/CPI support claim)
    * engineering product path only: non-formal, non-mainnet
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import Tests.Language.ParserSession

namespace Tests.Product.TipJarSolanaV1

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

private def shippedPath : FilePath := FilePath.mk "Examples/TipJar.lean"

private def pfAssetsDigestV1 : String :=
  "sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9"

private def readShipped : IO String := do
  unless ← shippedPath.pathExists do
    throw <| IO.userError "Examples/TipJar.lean missing (ADR-0029 B1 continuous vector)"
  IO.FS.readFile shippedPath

private def assertShape (text : String) : IO Unit := do
  expect (containsSubstr text "program TipJar where")
    "must declare program TipJar"
  expect (containsSubstr text "requires extension pf.assets version \"1.1.0\"")
    "must declare exact pf.assets extension triple"
  expect (containsSubstr text pfAssetsDigestV1)
    "must pin frozen pf.assets domain digest"
  expect (containsSubstr text "call pf.assets.native.deposit(amount)")
    "must call pf.assets.native.deposit"
  expect (containsSubstr text "call pf.assets.native.transfer(dst, amount)")
    "must call pf.assets.native.transfer"

private def cliBin : FilePath := FilePath.mk ".lake/build/bin/proof-forge-next"

private def runCli (args : Array String) : IO (UInt32 × String × String) := do
  unless ← cliBin.pathExists do
    throw <| IO.userError "proof-forge-next missing (build product CLI)"
  let absoluteCli ← IO.FS.realPath cliBin
  let out ← IO.Process.output { cmd := absoluteCli.toString, args }
  pure (out.exitCode, out.stdout, out.stderr)

private def testSolanaCpiBuildAndInspect : IO Unit := do
  assertShape (← readShipped)
  -- check --target solana --profile CPI must accept pf.assets + sync-call.
  let (cc, cout, cerr) ← runCli
    #["check", "Examples/TipJar.lean",
      "--module", "Examples.TipJar",
      "--target", "solana",
      "--profile", "solana-sbpf-cpi-elf-v1"]
  expect (cc == 0)
    s!"TipJar check --target solana --profile cpi must succeed, exit={cc} stderr={cerr} stdout={cout}"
  expect (containsSubstr cout "target=solana" || containsSubstr cout "solana")
    s!"check must pin solana, stdout={cout}"
  expect (containsSubstr cout "solana-sbpf-cpi-elf-v1")
    s!"check must pin cpi profile, stdout={cout}"
  let outDir := FilePath.mk "build/v2/tipjar-solana-cpi"
  try IO.FS.removeDirAll outDir catch _ => pure ()
  let (code, stdout, stderr) ← runCli
    #["build", "Examples/TipJar.lean",
      "--module", "Examples.TipJar",
      "--target", "solana",
      "--profile", "solana-sbpf-cpi-elf-v1",
      "-o", outDir.toString]
  expect (code == 0)
    s!"TipJar build --target solana --profile solana-sbpf-cpi-elf-v1 must succeed, exit={code} stderr={stderr} stdout={stdout}"
  expect (containsSubstr stdout "target=solana")
    s!"build stdout must pin target=solana, stdout={stdout}"
  expect (containsSubstr stdout "profile=solana-sbpf-cpi-elf-v1")
    s!"build stdout must pin cpi profile, stdout={stdout}"
  unless ← (outDir / "manifest.json").pathExists do
    throw <| IO.userError "TipJar Solana must write manifest.json"
  unless ← (outDir / "evidence.json").pathExists do
    throw <| IO.userError "TipJar Solana must write evidence.json"
  -- CPI product bases + finalized ELF.
  let hasSo ← (outDir / "TipJar.so").pathExists
  let hasS ← (outDir / "TipJar.s").pathExists
  expect (hasSo || hasS)
    "TipJar Solana must write assembly and/or ELF"
  unless ← (outDir / "TipJar.cpi-plan.json").pathExists do
    throw <| IO.userError "TipJar Solana must write TipJar.cpi-plan.json"
  unless ← (outDir / "TipJar.cpi-ir.json").pathExists do
    throw <| IO.userError "TipJar Solana must write TipJar.cpi-ir.json"
  let manifest ← IO.FS.readFile (outDir / "manifest.json")
  expect (containsSubstr manifest "\"schemaVersion\": \"proof-forge.output.v1\"")
    s!"manifest schemaVersion, got={manifest}"
  expect (containsSubstr manifest "\"target\": \"solana\"")
    s!"manifest target, got={manifest}"
  expect (containsSubstr manifest "\"codegenProfile\": \"solana-sbpf-cpi-elf-v1\"")
    s!"manifest profile, got={manifest}"
  expect (containsSubstr manifest "\"artifactProgramName\": \"TipJar\"")
    s!"manifest artifact, got={manifest}"
  expect (containsSubstr manifest "\"supportClaimDigest\":")
    s!"manifest must bind supportClaimDigest (CPI row incl pf-assets), got={manifest}"
  expect (containsSubstr manifest "\"contentSha256\":")
    s!"manifest content-bound, got={manifest}"
  let plan ← IO.FS.readFile (outDir / "TipJar.cpi-plan.json")
  expect (containsSubstr plan "pf.assets.native.deposit")
    "cpi-plan must list deposit site"
  expect (containsSubstr plan "pf.assets.native.transfer")
    "cpi-plan must list transfer site"
  expect (containsSubstr plan "proof-forge:vault:v1" ||
      containsSubstr plan "vaultPda")
    "cpi-plan must mention vault PDA"
  if hasS then
    let asm ← IO.FS.readFile (outDir / "TipJar.s")
    expect (containsSubstr asm "sol_invoke_signed_c")
      "assembly must invoke signed"
    expect (containsSubstr asm "proof-forge:vault:v1")
      "assembly must pin vault seed"
  let (iec, istdout, istderr) ← runCli
    #["inspect", outDir.toString, "--json"]
  expect (iec == 0)
    s!"inspect tipjar-solana --json must succeed, exit={iec} stderr={istderr}"
  expect (containsSubstr istdout "\"target\":\"solana\"")
    s!"inspect json target, got={istdout}"
  expect (containsSubstr istdout "\"codegenProfile\":\"solana-sbpf-cpi-elf-v1\"")
    s!"inspect json profile, got={istdout}"
  expect (containsSubstr istdout
      "\"validation\":\"structure+evidence+artifact-content+exact-disk-closure+outputSetDigest-recompute\"")
    s!"inspect exact closure, got={istdout}"
  expect (containsSubstr istdout "\"supportClaimDigest\":\"sha256:")
    s!"inspect supportClaimDigest present, got={istdout}"
  expect (istderr == "") "inspect ok silent stderr"

/-- ADR-0032 P4: bare `--target solana` selects sole rail cpi-elf. -/
private def testDefaultSolanaSoleRail : IO Unit := do
  assertShape (← readShipped)
  let outDir := FilePath.mk "build/v2/tipjar-solana-default-sole"
  try IO.FS.removeDirAll outDir catch _ => pure ()
  let (code, stdout, stderr) ← runCli
    #["build", "Examples/TipJar.lean",
      "--module", "Examples.TipJar",
      "--target", "solana",
      "-o", outDir.toString]
  expect (code == 0)
    s!"TipJar default solana sole rail must succeed, exit={code} stderr={stderr} stdout={stdout}"
  expect (containsSubstr stdout "profile=solana-sbpf-cpi-elf-v1")
    s!"default must select cpi-elf, got={stdout}"
  expect (containsSubstr stdout "deployable=true")
    s!"default sole rail deployable, got={stdout}"
  unless ← (outDir / "TipJar.so").pathExists do
    throw <| IO.userError "default sole rail must write TipJar.so"
  -- plan shim still FC (legacy declines sync/pf.assets)
  let planOut := FilePath.mk "build/v2/tipjar-solana-plan-shim-negative"
  try IO.FS.removeDirAll planOut catch _ => pure ()
  let (pc, pstdout, pstderr) ← runCli
    #["build", "Examples/TipJar.lean",
      "--module", "Examples.TipJar",
      "--target", "solana",
      "--profile", "solana-sbpf-plan-v1",
      "-o", planOut.toString]
  expect (pc != 0)
    s!"TipJar plan shim must fail closed, exit={pc}"
  let combined := pstdout ++ pstderr
  expect (containsSubstr combined "PF-REQ-UNSUPPORTED")
    s!"plan shim must PF-REQ-UNSUPPORTED, got={combined}"

unsafe def run : IO Unit := do
  testSolanaCpiBuildAndInspect
  testDefaultSolanaSoleRail
  IO.println "Tests.Product.TipJarSolanaV1: ok"

end Tests.Product.TipJarSolanaV1
