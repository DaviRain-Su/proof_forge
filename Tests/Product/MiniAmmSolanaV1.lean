/-
  Tests.Product.MiniAmmSolanaV1 — ADR-0030 E4 + ADR-0032 U1 product pin.

  Authority: shipped `Examples/MiniAmm.lean`.
    * product `check/build --target solana --profile solana-sbpf-cpi-elf-v1`
      emits proof-forge.output.v1 + full-body hybrid assembly/ELF
      (zero CPI sites + multi-block/Map → LowerSemantic body, admitCaller)
    * `inspect <out> --json` revalidates exact disk closure
    * pins profile, MiniAmm artifact name, hybrid IR/bindings markers
    * default / single-account Solana profiles fail closed (context.caller)
    * engineering product path only: non-formal, non-mainnet, not Mollusk
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import Tests.Language.ParserSession

namespace Tests.Product.MiniAmmSolanaV1

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

private def shippedPath : FilePath := FilePath.mk "Examples/MiniAmm.lean"

private def readShipped : IO String := do
  unless ← shippedPath.pathExists do
    throw <| IO.userError "Examples/MiniAmm.lean missing (ADR-0030 E4 / ADR-0032 U1 vector)"
  IO.FS.readFile shippedPath

private def assertShape (text : String) : IO Unit := do
  expect (containsSubstr text "program MiniAmm where")
    "must declare program MiniAmm"
  expect (containsSubstr text "state balances : Map Principal UInt64")
    "must declare Map Principal UInt64 LP balances"
  expect (containsSubstr text "context.caller")
    "must key LP mint by context.caller"
  expect (containsSubstr text "entry addLiquidity")
    "must declare addLiquidity"
  expect (containsSubstr text "entry swap0to1")
    "must declare swap0to1"
  expect (containsSubstr text "state scratch : UInt64")
    "must use scratch UInt64 across Map effect boundary"
  -- Zero CPI sites: hybrid full-body pin, not pf.assets escrow path.
  expect (!containsSubstr text "requires extension pf.assets")
    "MiniAmm must not require pf.assets (zero-site hybrid body)"
  expect (!containsSubstr text "call pf.assets")
    "MiniAmm must not call pf.assets (zero-site hybrid body)"

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
    #["check", "Examples/MiniAmm.lean",
      "--module", "Examples.MiniAmm",
      "--target", "solana",
      "--profile", "solana-sbpf-cpi-elf-v1"]
  expect (cc == 0)
    s!"MiniAmm check --target solana --profile cpi must succeed, exit={cc} stderr={cerr} stdout={cout}"
  expect (containsSubstr cout "target=solana" || containsSubstr cout "solana")
    s!"check must pin solana, stdout={cout}"
  expect (containsSubstr cout "solana-sbpf-cpi-elf-v1")
    s!"check must pin cpi profile, stdout={cout}"
  let outDir := FilePath.mk "build/v2/miniamm-solana-cpi"
  try IO.FS.removeDirAll outDir catch _ => pure ()
  let (code, stdout, stderr) ← runCli
    #["build", "Examples/MiniAmm.lean",
      "--module", "Examples.MiniAmm",
      "--target", "solana",
      "--profile", "solana-sbpf-cpi-elf-v1",
      "-o", outDir.toString]
  expect (code == 0)
    s!"MiniAmm build --target solana --profile solana-sbpf-cpi-elf-v1 must succeed, exit={code} stderr={stderr} stdout={stdout}"
  expect (containsSubstr stdout "target=solana")
    s!"build stdout must pin target=solana, stdout={stdout}"
  expect (containsSubstr stdout "profile=solana-sbpf-cpi-elf-v1")
    s!"build stdout must pin cpi profile, stdout={stdout}"
  expect (containsSubstr stdout "deployable=true")
    s!"build must report deployable=true, stdout={stdout}"
  unless ← (outDir / "manifest.json").pathExists do
    throw <| IO.userError "MiniAmm Solana must write manifest.json"
  unless ← (outDir / "evidence.json").pathExists do
    throw <| IO.userError "MiniAmm Solana must write evidence.json"
  let hasSo ← (outDir / "MiniAmm.so").pathExists
  let hasS ← (outDir / "MiniAmm.s").pathExists
  expect (hasSo && hasS)
    "MiniAmm Solana must write both assembly and finalized ELF"
  unless ← (outDir / "MiniAmm.cpi-plan.json").pathExists do
    throw <| IO.userError "MiniAmm Solana must write MiniAmm.cpi-plan.json"
  unless ← (outDir / "MiniAmm.cpi-ir.json").pathExists do
    throw <| IO.userError "MiniAmm Solana must write MiniAmm.cpi-ir.json"
  unless ← (outDir / "MiniAmm.cpi-bindings.json").pathExists do
    throw <| IO.userError "MiniAmm Solana must write MiniAmm.cpi-bindings.json"
  unless ← (outDir / "MiniAmm.idl.json").pathExists do
    throw <| IO.userError "MiniAmm Solana must write MiniAmm.idl.json"
  let manifest ← IO.FS.readFile (outDir / "manifest.json")
  expect (containsSubstr manifest "\"schemaVersion\": \"proof-forge.output.v1\"")
    s!"manifest schemaVersion, got={manifest}"
  expect (containsSubstr manifest "\"target\": \"solana\"")
    s!"manifest target, got={manifest}"
  expect (containsSubstr manifest "\"codegenProfile\": \"solana-sbpf-cpi-elf-v1\"")
    s!"manifest profile, got={manifest}"
  expect (containsSubstr manifest "\"artifactProgramName\": \"MiniAmm\"")
    s!"manifest artifact, got={manifest}"
  expect (containsSubstr manifest "\"supportClaimDigest\":")
    s!"manifest must bind supportClaimDigest, got={manifest}"
  expect (containsSubstr manifest "\"contentSha256\":")
    s!"manifest content-bound, got={manifest}"
  expect (containsSubstr manifest "\"path\": \"MiniAmm.so\"")
    s!"manifest must list MiniAmm.so, got={manifest}"
  let ir ← IO.FS.readFile (outDir / "MiniAmm.cpi-ir.json")
  expect (containsSubstr ir "proof-forge.solana.full-body-hybrid-ir.v1")
    s!"cpi-ir must mark full-body hybrid, got={ir}"
  expect (containsSubstr ir "\"admitCaller\":true")
    s!"cpi-ir must admitCaller for context.caller, got={ir}"
  let bindings ← IO.FS.readFile (outDir / "MiniAmm.cpi-bindings.json")
  expect (containsSubstr bindings "\"fullBodyHybrid\":true")
    s!"bindings must mark fullBodyHybrid, got={bindings}"
  expect (containsSubstr bindings "\"programName\":\"MiniAmm\"")
    s!"bindings programName MiniAmm, got={bindings}"
  let plan ← IO.FS.readFile (outDir / "MiniAmm.cpi-plan.json")
  expect (containsSubstr plan "\"programName\":\"MiniAmm\"" ||
      containsSubstr plan "\"programName\": \"MiniAmm\"")
    s!"cpi-plan must name MiniAmm, got={plan}"
  expect (containsSubstr plan "\"name\":\"pf_caller\"" ||
      containsSubstr plan "\"name\": \"pf_caller\"")
    s!"cpi-plan must include pf_caller role for context.caller, got={plan}"
  expect (containsSubstr plan "addLiquidity")
    "cpi-plan/handlers must list addLiquidity"
  expect (containsSubstr plan "swap0to1")
    "cpi-plan/handlers must list swap0to1"
  let evidence ← IO.FS.readFile (outDir / "evidence.json")
  expect (containsSubstr evidence "irDigest=full-body-hybrid")
    s!"evidence must pin irDigest=full-body-hybrid, got={evidence}"
  expect (containsSubstr evidence "solana-sbpf-cpi-elf-v1")
    s!"evidence must pin cpi profile, got={evidence}"
  if hasS then
    let asm ← IO.FS.readFile (outDir / "MiniAmm.s")
    expect (containsSubstr asm ".globl entrypoint")
      "assembly must export entrypoint"
    expect (containsSubstr asm "caller_principal_leaf")
      "assembly must load caller principal from account[1]"
    -- Zero CPI sites: hybrid body must not emit sol_invoke*.
    expect (!containsSubstr asm "sol_invoke")
      "full-body hybrid MiniAmm must not emit sol_invoke (zero CPI sites)"
  let (iec, istdout, istderr) ← runCli
    #["inspect", outDir.toString, "--json"]
  expect (iec == 0)
    s!"inspect miniamm-solana --json must succeed, exit={iec} stderr={istderr}"
  expect (containsSubstr istdout "\"target\":\"solana\"")
    s!"inspect json target, got={istdout}"
  expect (containsSubstr istdout "\"codegenProfile\":\"solana-sbpf-cpi-elf-v1\"")
    s!"inspect json profile, got={istdout}"
  expect (containsSubstr istdout "\"artifactProgramName\":\"MiniAmm\"")
    s!"inspect artifact name, got={istdout}"
  expect (containsSubstr istdout "\"deployable\":true")
    s!"inspect deployable, got={istdout}"
  expect (containsSubstr istdout "MiniAmm.so")
    s!"inspect must list MiniAmm.so, got={istdout}"
  expect (containsSubstr istdout
      "\"validation\":\"structure+evidence+artifact-content+exact-disk-closure+outputSetDigest-recompute\"")
    s!"inspect exact closure, got={istdout}"
  expect (containsSubstr istdout "\"supportClaimDigest\":\"sha256:")
    s!"inspect supportClaimDigest present, got={istdout}"
  expect (istderr == "") "inspect ok silent stderr"

private def testDefaultSolanaStillFailClosed : IO Unit := do
  assertShape (← readShipped)
  let outDir := FilePath.mk "build/v2/miniamm-solana-default-negative"
  try IO.FS.removeDirAll outDir catch _ => pure ()
  let (code, stdout, stderr) ← runCli
    #["build", "Examples/MiniAmm.lean",
      "--module", "Examples.MiniAmm",
      "--target", "solana",
      "-o", outDir.toString]
  expect (code != 0)
    s!"MiniAmm default solana profile must fail closed, exit={code}"
  let combined := stdout ++ stderr
  -- Single-account rails reject context.caller; message steers to cpi-elf hybrid.
  expect (containsSubstr combined "PF-PLAN-INVARIANT" ||
      containsSubstr combined "ContextRead" ||
      containsSubstr combined "context.caller")
    s!"default solana must reject context.caller / single-account shape, got={combined}"
  expect (!(← outDir.pathExists))
    s!"default solana must leave zero published artifacts"

unsafe def run : IO Unit := do
  testSolanaCpiBuildAndInspect
  testDefaultSolanaStillFailClosed
  IO.println "Tests.Product.MiniAmmSolanaV1: ok"

end Tests.Product.MiniAmmSolanaV1
