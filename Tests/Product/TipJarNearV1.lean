/-
  Tests.Product.TipJarNearV1 — ADR-0029 Phase C2 product vertical (NEAR half binding).

  Authority: shipped `Examples/TipJarAsync.lean`.
    * product `check` succeeds (Normalize + exact pf.assets extension triple)
    * product `build --target near` emits proof-forge.output.v1 (wat2wasm)
    * `inspect <out> --json` revalidates exact disk closure
    * pins target=near, profile=near-wasm-raw-u64-v1, WAT host surface
      (attached_deposit + promise_batch_action_transfer)
    * `Examples/TipJar.lean` (sync transfer) on NEAR fails closed at Plan
      (sync transfer is permanently refused; Promise is async) with zero
      published artifacts
    * engineering local artifacts only: non-formal, non-mainnet, no sandbox
      claim (sandbox receipts are the separate runtime gate)
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import Tests.Language.ParserSession

namespace Tests.Product.TipJarNearV1

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

private def shippedPath : FilePath := FilePath.mk "Examples/TipJarAsync.lean"
private def shippedSyncPath : FilePath := FilePath.mk "Examples/TipJar.lean"

private def pfAssetsDigestV1 : String :=
  "sha256:97dfde7f7df228230828db4273086224bc28a4bc88c2f25457eaf0aee22aeeed"

private def readShipped : IO String := do
  unless ← shippedPath.pathExists do
    throw <| IO.userError "Examples/TipJarAsync.lean missing (ADR-0029 C2 continuous vector)"
  IO.FS.readFile shippedPath

private def assertShape (text : String) : IO Unit := do
  expect (containsSubstr text "program TipJarAsync where")
    "must declare program TipJarAsync"
  expect (containsSubstr text "requires extension pf.assets version \"1.0.0\"")
    "must declare exact pf.assets extension triple"
  expect (containsSubstr text pfAssetsDigestV1)
    "must pin frozen pf.assets domain digest"
  expect (containsSubstr text "call pf.assets.native.deposit(amount)")
    "must call pf.assets.native.deposit"
  expect (containsSubstr text "call pf.assets.native.transferAsync(dst, amount)")
    "must call pf.assets.native.transferAsync (async variant, never sync on NEAR)"
  expect (!containsSubstr text "call pf.assets.native.transfer(dst, amount)")
    "must NOT use sync transfer (permanently fail closed on NEAR)"
  expect (containsSubstr text "entry tip(dst : Principal, amount : UInt64)")
    "must declare tip entry with Principal + UInt64 params"

private def cliBin : FilePath := FilePath.mk ".lake/build/bin/proof-forge-next"

private def runCli (args : Array String) : IO (UInt32 × String × String) := do
  unless ← cliBin.pathExists do
    throw <| IO.userError "proof-forge-next missing (build product CLI)"
  let absoluteCli ← IO.FS.realPath cliBin
  let out ← IO.Process.output { cmd := absoluteCli.toString, args }
  pure (out.exitCode, out.stdout, out.stderr)

/-- Product compile of shipped TipJarAsync must succeed (semantic carrier). -/
private unsafe def testProductCompileOk : IO Unit := do
  let text ← readShipped
  assertShape text
  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgramV1 text "Examples/TipJarAsync.lean" "Examples.TipJarAsync" none with
  | .error e =>
      throw <| IO.userError s!"TipJarAsync select must succeed: {e.code}: {e.render}"
  | .ok source =>
      match compileValidatedSourceV1 source with
      | .error e =>
          throw <| IO.userError s!"TipJarAsync product compile must succeed: {e.render}"
      | .ok _ => pure ()

/-- Real CLI check on shipped TipJarAsync (with and without target). -/
private def testCliCheckOk : IO Unit := do
  assertShape (← readShipped)
  let (code, stdout, stderr) ← runCli
    #["check", "Examples/TipJarAsync.lean", "--module", "Examples.TipJarAsync"]
  expect (code == 0)
    s!"TipJarAsync check must succeed, exit={code} stderr={stderr} stdout={stdout}"
  let (codeT, stdoutT, stderrT) ← runCli
    #["check", "Examples/TipJarAsync.lean", "--module", "Examples.TipJarAsync",
      "--target", "near"]
  expect (codeT == 0)
    s!"TipJarAsync check --target near must succeed, exit={codeT} stderr={stderrT} stdout={stdoutT}"
  expect (containsSubstr stdoutT "target=near")
    s!"check --target near must pin target, stdout={stdoutT}"
  expect (containsSubstr stdoutT "profile=near-wasm-raw-u64-v1")
    s!"check --target near must pin profile, stdout={stdoutT}"

/-- NEAR product vertical: build + inspect exact closure + WAT host pins. -/
private def testNearBuildAndInspect : IO Unit := do
  assertShape (← readShipped)
  let (tec, tstdout, tstderr) ← runCli #["inspect", "near"]
  expect (tec == 0)
    s!"inspect near must succeed, exit={tec} stderr={tstderr}"
  expect (containsSubstr tstdout "extension.pf-assets")
    s!"inspect near must advertise extension.pf-assets, got={tstdout}"
  expect (containsSubstr tstdout "effect.synchronous-call")
    s!"inspect near must advertise effect.synchronous-call (pf.assets catalog scope), got={tstdout}"
  let claimLine :=
    (tstdout.splitOn "\n").find? (·.startsWith "supportClaimDigest=sha256:")
  let some claimWire := claimLine |
    throw <| IO.userError s!"inspect near missing supportClaimDigest, got={tstdout}"
  let claimBare := (claimWire.splitOn "sha256:")[1]!
  let outDir := FilePath.mk "build/v2/tipjarasync-near"
  try IO.FS.removeDirAll outDir catch _ => pure ()
  let (code, stdout, stderr) ← runCli
    #["build", "Examples/TipJarAsync.lean",
      "--module", "Examples.TipJarAsync",
      "--target", "near",
      "-o", outDir.toString]
  expect (code == 0)
    s!"TipJarAsync build --target near must succeed, exit={code} stderr={stderr} stdout={stdout}"
  expect (containsSubstr stdout "target=near")
    s!"build stdout must pin target=near, stdout={stdout}"
  expect (containsSubstr stdout "profile=near-wasm-raw-u64-v1")
    s!"build stdout must pin near-wasm-raw-u64-v1, stdout={stdout}"
  unless ← (outDir / "manifest.json").pathExists do
    throw <| IO.userError "TipJarAsync NEAR must write manifest.json"
  unless ← (outDir / "evidence.json").pathExists do
    throw <| IO.userError "TipJarAsync NEAR must write evidence.json"
  unless ← (outDir / "TipJarAsync.wasm").pathExists do
    throw <| IO.userError "TipJarAsync NEAR must write TipJarAsync.wasm"
  unless ← (outDir / "TipJarAsync.wat").pathExists do
    throw <| IO.userError "TipJarAsync NEAR must write TipJarAsync.wat"
  let manifest ← IO.FS.readFile (outDir / "manifest.json")
  expect (containsSubstr manifest "\"target\": \"near\"")
    s!"manifest target must be near, got={manifest}"
  expect (containsSubstr manifest "\"codegenProfile\": \"near-wasm-raw-u64-v1\"")
    s!"manifest profile must be near-wasm-raw-u64-v1, got={manifest}"
  expect (containsSubstr manifest "\"artifactProgramName\": \"TipJarAsync\"")
    s!"manifest artifact name must be TipJarAsync, got={manifest}"
  expect (containsSubstr manifest s!"\"supportClaimDigest\": \"{claimBare}\"")
    s!"manifest supportClaimDigest must match inspect near, got={manifest}"
  let wat ← IO.FS.readFile (outDir / "TipJarAsync.wat")
  expect (containsSubstr wat "attached_deposit")
    "TipJarAsync.wat must use attached_deposit (deposit exact check)"
  expect (containsSubstr wat "promise_batch_action_transfer")
    "TipJarAsync.wat must emit promise_batch_action_transfer (transferAsync)"
  expect (!containsSubstr wat "promise_batch_action_function_call")
    "TipJarAsync.wat must not emit function-call actions (no schedule in demo)"
  let (iec, istdout, istderr) ← runCli
    #["inspect", outDir.toString, "--json"]
  expect (iec == 0)
    s!"inspect tipjarasync-near --json must succeed, exit={iec} stderr={istderr} stdout={istdout}"
  expect (containsSubstr istdout "\"target\":\"near\"")
    s!"inspect json target, got={istdout}"
  expect (containsSubstr istdout "\"codegenProfile\":\"near-wasm-raw-u64-v1\"")
    s!"inspect json profile, got={istdout}"
  expect (containsSubstr istdout
      "\"validation\":\"structure+evidence+artifact-content+exact-disk-closure+outputSetDigest-recompute\"")
    s!"inspect must revalidate exact disk closure, got={istdout}"
  expect (istderr == "")
    s!"inspect ok must be silent on stderr, got={istderr}"

/-- The sync TipJar demo must fail closed on NEAR at Plan (sync transfer is
    permanently refused; Promise is async) with zero published artifacts. -/
private def testSyncTipJarFailClosedOnNear : IO Unit := do
  unless ← shippedSyncPath.pathExists do
    throw <| IO.userError "Examples/TipJar.lean missing (Phase A demo)"
  let outDir := FilePath.mk "build/v2/tipjar-near-syncfc"
  try IO.FS.removeDirAll outDir catch _ => pure ()
  let (code, stdout, stderr) ← runCli
    #["build", "Examples/TipJar.lean",
      "--module", "Examples.TipJar",
      "--target", "near",
      "-o", outDir.toString]
  expect (code != 0)
    s!"TipJar (sync transfer) build --target near must fail closed, exit={code}"
  let combined := stdout ++ stderr
  expect (containsSubstr combined "permanently fail closed on NEAR")
    s!"sync transfer must cite permanent fail closed, got={combined}"
  expect (!(← outDir.pathExists))
    s!"TipJar on near must leave zero published artifacts at {outDir}"
  expect (!containsSubstr stdout "built target=")
    s!"TipJar on near must not print success stdout, got={stdout}"

unsafe def run : IO Unit := do
  testProductCompileOk
  testCliCheckOk
  testNearBuildAndInspect
  testSyncTipJarFailClosedOnNear
  IO.println "Tests.Product.TipJarNearV1: ok"

end Tests.Product.TipJarNearV1
