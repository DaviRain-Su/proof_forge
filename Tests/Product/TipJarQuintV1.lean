/-
  Tests.Product.TipJarQuintV1 — ADR-0029 Phase A6 product vertical.

  Authority: shipped `Examples/TipJar.lean`.
    * product `check` succeeds (Normalize + exact pf.assets extension triple)
    * product `build --target quint` emits proof-forge.output.v1 (zero-tool)
    * `inspect <out> --json` revalidates exact disk closure
    * pins target=quint, profile=quint-source-u64-model-v1, TipJar.qnt vault model
    * product `build` for evm/solana/near/noir fails closed on extension.pf-assets
      with zero published artifacts
    * engineering model-layer only: non-formal, non-mainnet, deployable=false
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import Tests.Language.ParserSession

namespace Tests.Product.TipJarQuintV1

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
  "sha256:97dfde7f7df228230828db4273086224bc28a4bc88c2f25457eaf0aee22aeeed"

private def readShipped : IO String := do
  unless ← shippedPath.pathExists do
    throw <| IO.userError "Examples/TipJar.lean missing (ADR-0029 A6 continuous vector)"
  IO.FS.readFile shippedPath

private def assertShape (text : String) : IO Unit := do
  expect (containsSubstr text "program TipJar where")
    "must declare program TipJar"
  expect (containsSubstr text "requires extension pf.assets version \"1.0.0\"")
    "must declare exact pf.assets extension triple"
  expect (containsSubstr text pfAssetsDigestV1)
    "must pin frozen pf.assets domain digest"
  expect (containsSubstr text "call pf.assets.native.deposit(amount)")
    "must call pf.assets.native.deposit"
  expect (containsSubstr text "call pf.assets.native.transfer(dst, amount)")
    "must call pf.assets.native.transfer"
  expect (containsSubstr text "state tips : UInt64")
    "must carry public UInt64 tips state"
  expect (containsSubstr text "init(initial : UInt64)")
    "must declare init"
  expect (containsSubstr text "view get() : UInt64")
    "must declare view get"
  expect (containsSubstr text "entry tip(dst : Principal, amount : UInt64)")
    "must declare tip entry with Principal + UInt64 params"

private def cliBin : FilePath := FilePath.mk ".lake/build/bin/proof-forge-next"

private def runCli (args : Array String) : IO (UInt32 × String × String) := do
  unless ← cliBin.pathExists do
    throw <| IO.userError "proof-forge-next missing (build product CLI)"
  let absoluteCli ← IO.FS.realPath cliBin
  let out ← IO.Process.output { cmd := absoluteCli.toString, args }
  pure (out.exitCode, out.stdout, out.stderr)

/-- Product compile of shipped TipJar must succeed (semantic carrier). -/
private unsafe def testProductCompileOk : IO Unit := do
  let text ← readShipped
  assertShape text
  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgramV1 text "Examples/TipJar.lean" "Examples.TipJar" none with
  | .error e =>
      throw <| IO.userError s!"TipJar select must succeed: {e.code}: {e.render}"
  | .ok source =>
      match compileValidatedSourceV1 source with
      | .error e =>
          throw <| IO.userError s!"TipJar product compile must succeed: {e.render}"
      | .ok _ => pure ()

/-- Real CLI check on shipped Examples/TipJar.lean (with and without target). -/
private def testCliCheckOk : IO Unit := do
  assertShape (← readShipped)
  let (code, stdout, stderr) ← runCli
    #["check", "Examples/TipJar.lean", "--module", "Examples.TipJar"]
  expect (code == 0)
    s!"TipJar check must succeed, exit={code} stderr={stderr} stdout={stdout}"
  expect (containsSubstr stdout "program=TipJar" || containsSubstr stdout "TipJar")
    s!"check ok must name TipJar, stdout={stdout}"
  -- With --target quint, resolve must accept extension.pf-assets + sync-call.
  let (codeT, stdoutT, stderrT) ← runCli
    #["check", "Examples/TipJar.lean", "--module", "Examples.TipJar",
      "--target", "quint"]
  expect (codeT == 0)
    s!"TipJar check --target quint must succeed, exit={codeT} stderr={stderrT} stdout={stdoutT}"
  expect (containsSubstr stdoutT "target=quint")
    s!"check --target quint must pin target, stdout={stdoutT}"
  expect (containsSubstr stdoutT "profile=quint-source-u64-model-v1")
    s!"check --target quint must pin profile, stdout={stdoutT}"

/-- Quint product vertical: build + inspect exact closure + key field pins. -/
private def testQuintBuildAndInspect : IO Unit := do
  assertShape (← readShipped)
  -- Target-level inspect pins the exact support row (incl. extension.pf-assets).
  let (tec, tstdout, tstderr) ← runCli #["inspect", "quint"]
  expect (tec == 0)
    s!"inspect quint must succeed, exit={tec} stderr={tstderr}"
  expect (containsSubstr tstdout
      "requirements=#[effect.synchronous-call, extension.pf-assets, failure.atomic-rollback, state.persistent, value.bool, value.checked-arithmetic]")
    s!"inspect quint must advertise exact pf-assets support row, got={tstdout}"
  -- Extract bare supportClaimDigest hex for OutputSet join below.
  let claimLine :=
    (tstdout.splitOn "\n").find? (·.startsWith "supportClaimDigest=sha256:")
  let some claimWire := claimLine |
    throw <| IO.userError s!"inspect quint missing supportClaimDigest, got={tstdout}"
  let claimParts := claimWire.splitOn "sha256:"
  expect (claimParts.length == 2)
    s!"supportClaimDigest wire shape, got={claimWire}"
  let claimBare := claimParts[1]!
  expect (claimBare.length == 64)
    s!"supportClaimDigest bare hex length, got={claimBare}"
  let outDir := FilePath.mk "build/v2/tipjar-quint"
  try IO.FS.removeDirAll outDir catch _ => pure ()
  let (code, stdout, stderr) ← runCli
    #["build", "Examples/TipJar.lean",
      "--module", "Examples.TipJar",
      "--target", "quint",
      "-o", outDir.toString]
  expect (code == 0)
    s!"TipJar build --target quint must succeed, exit={code} stderr={stderr} stdout={stdout}"
  expect (containsSubstr stdout "target=quint")
    s!"build stdout must pin target=quint, stdout={stdout}"
  expect (containsSubstr stdout "profile=quint-source-u64-model-v1")
    s!"build stdout must pin quint-source-u64-model-v1, stdout={stdout}"
  expect (containsSubstr stdout "deployable=false")
    s!"Quint model target must report deployable=false, stdout={stdout}"
  unless ← (outDir / "manifest.json").pathExists do
    throw <| IO.userError "TipJar Quint must write manifest.json"
  unless ← (outDir / "evidence.json").pathExists do
    throw <| IO.userError "TipJar Quint must write evidence.json"
  unless ← (outDir / "TipJar.qnt").pathExists do
    throw <| IO.userError "TipJar Quint must write TipJar.qnt"
  let manifest ← IO.FS.readFile (outDir / "manifest.json")
  expect (containsSubstr manifest "\"schemaVersion\": \"proof-forge.output.v1\"")
    s!"manifest schemaVersion must be proof-forge.output.v1, got={manifest}"
  expect (containsSubstr manifest "\"target\": \"quint\"")
    s!"manifest target must be quint, got={manifest}"
  expect (containsSubstr manifest "\"codegenProfile\": \"quint-source-u64-model-v1\"")
    s!"manifest profile must be quint-source-u64-model-v1, got={manifest}"
  expect (containsSubstr manifest "\"artifactProgramName\": \"TipJar\"")
    s!"manifest artifact name must be TipJar, got={manifest}"
  expect (containsSubstr manifest "\"deployable\": false")
    s!"manifest deployable must be false, got={manifest}"
  expect (containsSubstr manifest "TipJar.qnt")
    s!"manifest files must list TipJar.qnt, got={manifest}"
  expect (containsSubstr manifest "\"contentSha256\":")
    s!"manifest must carry content-bound file descriptors, got={manifest}"
  expect (containsSubstr manifest "\"evidenceSha256\":")
    s!"manifest must bind evidenceSha256, got={manifest}"
  -- OutputSet supportClaimDigest must join the target support row that includes
  -- exact extension.pf-assets (same bare hex as inspect quint).
  expect (containsSubstr manifest s!"\"supportClaimDigest\": \"{claimBare}\"")
    s!"manifest supportClaimDigest must match inspect quint (pf-assets row), got={manifest}"
  let evidence ← IO.FS.readFile (outDir / "evidence.json")
  expect (containsSubstr evidence "\"target\": \"quint\"")
    s!"evidence target must be quint, got={evidence}"
  expect (containsSubstr evidence "\"deployable\": false")
    s!"evidence deployable must be false, got={evidence}"
  let qnt ← IO.FS.readFile (outDir / "TipJar.qnt")
  expect (containsSubstr qnt "module PFModel_TipJar {")
    s!"TipJar.qnt must declare model module, got head"
  expect (containsSubstr qnt "var pf_vault_native: int")
    "TipJar.qnt must model self vault pf_vault_native"
  expect (containsSubstr qnt "var pf_state_tips: int")
    "TipJar.qnt must declare tips state"
  expect (containsSubstr qnt "nondet pf_ext_ok_")
    "TipJar.qnt must nondet external outcomes for pf.assets ops"
  -- inspect re-walks exact disk closure (structure+evidence+content+closure).
  let (iec, istdout, istderr) ← runCli
    #["inspect", outDir.toString, "--json"]
  expect (iec == 0)
    s!"inspect tipjar-quint --json must succeed, exit={iec} stderr={istderr} stdout={istdout}"
  expect (containsSubstr istdout "\"schema\":\"proof-forge.cli.inspect-output.v1\"")
    s!"inspect json schema, got={istdout}"
  expect (containsSubstr istdout "\"target\":\"quint\"")
    s!"inspect json target, got={istdout}"
  expect (containsSubstr istdout "\"codegenProfile\":\"quint-source-u64-model-v1\"")
    s!"inspect json profile, got={istdout}"
  expect (containsSubstr istdout "\"artifactProgramName\":\"TipJar\"")
    s!"inspect json artifact, got={istdout}"
  expect (containsSubstr istdout
      "\"validation\":\"structure+evidence+artifact-content+exact-disk-closure+outputSetDigest-recompute\"")
    s!"inspect must revalidate exact disk closure, got={istdout}"
  expect (containsSubstr istdout "\"contentSha256\":\"sha256:")
    s!"inspect must report content-bound descriptors, got={istdout}"
  expect (containsSubstr istdout "\"evidenceSha256\":\"sha256:")
    s!"inspect must report evidenceSha256, got={istdout}"
  expect (containsSubstr istdout s!"\"supportClaimDigest\":\"sha256:{claimBare}\"")
    s!"inspect json supportClaimDigest must join pf-assets row, got={istdout}"
  expect (istderr == "")
    s!"inspect ok must be silent on stderr, got={istderr}"
  -- Human inspect also pins target/profile/validation.
  let (hec, hstdout, hstderr) ← runCli #["inspect", outDir.toString]
  expect (hec == 0)
    s!"inspect tipjar-quint human must succeed, exit={hec} stderr={hstderr}"
  expect (containsSubstr hstdout "target=quint\n")
    s!"human inspect target, got={hstdout}"
  expect (containsSubstr hstdout "codegenProfile=quint-source-u64-model-v1\n")
    s!"human inspect profile, got={hstdout}"
  expect (containsSubstr hstdout
      "validation=structure+evidence+artifact-content+exact-disk-closure+outputSetDigest-recompute")
    s!"human inspect validation, got={hstdout}"
  -- Leave tree for manual review; suite is idempotent on next run (rm first).

/-- Same demo must fail closed on targets that do not advertise pf.assets. -/
private def testOtherTargetsFailClosed : IO Unit := do
  assertShape (← readShipped)
  let targets := #["evm", "solana", "near", "noir"]
  for tid in targets do
    let outDir := FilePath.mk s!"build/v2/tipjar-{tid}-negative"
    try IO.FS.removeDirAll outDir catch _ => pure ()
    let (code, stdout, stderr) ← runCli
      #["build", "Examples/TipJar.lean",
        "--module", "Examples.TipJar",
        "--target", tid,
        "-o", outDir.toString]
    expect (code != 0)
      s!"TipJar build --target {tid} must fail closed, exit={code} stdout={stdout} stderr={stderr}"
    let combined := stdout ++ stderr
    expect (containsSubstr combined "PF-REQ-UNSUPPORTED")
      s!"TipJar on {tid} must surface PF-REQ-UNSUPPORTED, got={combined}"
    -- TipJar freezes both effect.synchronous-call (from call sites) and
    -- extension.pf-assets. Resolve reports the first unsupported id in wire
    -- order: EVM/Noir typically hit extension.pf-assets (they advertise sync
    -- call); Solana/NEAR default profiles hit effect.synchronous-call first.
    -- Either is correct fail-closed evidence that the demo is Quint-only.
    expect (containsSubstr combined "extension.pf-assets" ||
        containsSubstr combined "pf-assets" ||
        containsSubstr combined "pf.assets" ||
        containsSubstr combined "effect.synchronous-call")
      s!"TipJar on {tid} must cite pf.assets or sync-call requirement, got={combined}"
    expect (!(← outDir.pathExists))
      s!"TipJar on {tid} must leave zero published artifacts at {outDir}"
    expect (!containsSubstr stdout "built target=")
      s!"TipJar on {tid} must not print success stdout, got={stdout}"

unsafe def run : IO Unit := do
  testProductCompileOk
  testCliCheckOk
  testQuintBuildAndInspect
  testOtherTargetsFailClosed
  IO.println "Tests.Product.TipJarQuintV1: ok"

end Tests.Product.TipJarQuintV1
