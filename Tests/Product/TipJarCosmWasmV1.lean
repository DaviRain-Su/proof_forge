/-
  Tests.Product.TipJarCosmWasmV1 — ADR-0029 Phase C1 product vertical (CosmWasm).

  Authority: shipped `Examples/TipJar.lean`.
    * product `check` succeeds (Normalize + exact pf.assets extension triple)
    * product `build --target cosmwasm` emits proof-forge.output.v1
      (locked wat2wasm + cosmwasm-check when the tool is present)
    * `inspect <out> --json` revalidates exact disk closure
    * pins target=cosmwasm, profile=cosmwasm-wasm-u64-v1, WAT pf.assets surface
      (funds helpers + bank send SubMsg emission)
    * engineering artifacts only: non-formal, non-mainnet; wasmd rung-1 and
      cosmwasm-vm mock are separate runtime gates
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import Tests.Language.ParserSession

namespace Tests.Product.TipJarCosmWasmV1

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

private def cliBin : FilePath := FilePath.mk ".lake/build/bin/proof-forge-next"

private def runCli (args : Array String) : IO (UInt32 × String × String) := do
  unless ← cliBin.pathExists do
    throw <| IO.userError "proof-forge-next missing (build product CLI)"
  let absoluteCli ← IO.FS.realPath cliBin
  let out ← IO.Process.output { cmd := absoluteCli.toString, args }
  pure (out.exitCode, out.stdout, out.stderr)

/-- Real CLI check on shipped TipJar with --target cosmwasm. -/
private def testCliCheckOk : IO Unit := do
  let text ← readShipped
  expect (containsSubstr text pfAssetsDigestV1)
    "TipJar must pin frozen pf.assets domain digest"
  let (codeT, stdoutT, stderrT) ← runCli
    #["check", "Examples/TipJar.lean", "--module", "Examples.TipJar",
      "--target", "cosmwasm"]
  expect (codeT == 0)
    s!"TipJar check --target cosmwasm must succeed, exit={codeT} stderr={stderrT} stdout={stdoutT}"
  expect (containsSubstr stdoutT "target=cosmwasm")
    s!"check --target cosmwasm must pin target, stdout={stdoutT}"
  expect (containsSubstr stdoutT "profile=cosmwasm-wasm-u64-v1")
    s!"check --target cosmwasm must pin profile, stdout={stdoutT}"

/-- CosmWasm product vertical: build + inspect exact closure + WAT pins. -/
private def testCosmWasmBuildAndInspect : IO Unit := do
  let (tec, tstdout, tstderr) ← runCli #["inspect", "cosmwasm"]
  expect (tec == 0)
    s!"inspect cosmwasm must succeed, exit={tec} stderr={tstderr}"
  expect (containsSubstr tstdout "extension.pf-assets")
    s!"inspect cosmwasm must advertise extension.pf-assets, got={tstdout}"
  let claimLine :=
    (tstdout.splitOn "\n").find? (·.startsWith "supportClaimDigest=sha256:")
  let some claimWire := claimLine |
    throw <| IO.userError s!"inspect cosmwasm missing supportClaimDigest, got={tstdout}"
  let claimBare := (claimWire.splitOn "sha256:")[1]!
  let outDir := FilePath.mk "build/v2/tipjar-cw"
  try IO.FS.removeDirAll outDir catch _ => pure ()
  let (code, stdout, stderr) ← runCli
    #["build", "Examples/TipJar.lean",
      "--module", "Examples.TipJar",
      "--target", "cosmwasm",
      "-o", outDir.toString]
  expect (code == 0)
    s!"TipJar build --target cosmwasm must succeed, exit={code} stderr={stderr} stdout={stdout}"
  expect (containsSubstr stdout "target=cosmwasm")
    s!"build stdout must pin target=cosmwasm, stdout={stdout}"
  expect (containsSubstr stdout "profile=cosmwasm-wasm-u64-v1")
    s!"build stdout must pin cosmwasm-wasm-u64-v1, stdout={stdout}"
  unless ← (outDir / "manifest.json").pathExists do
    throw <| IO.userError "TipJar CW must write manifest.json"
  unless ← (outDir / "evidence.json").pathExists do
    throw <| IO.userError "TipJar CW must write evidence.json"
  unless ← (outDir / "TipJar.wasm").pathExists do
    throw <| IO.userError "TipJar CW must write TipJar.wasm"
  unless ← (outDir / "TipJar.wat").pathExists do
    throw <| IO.userError "TipJar CW must write TipJar.wat"
  let manifest ← IO.FS.readFile (outDir / "manifest.json")
  expect (containsSubstr manifest "\"target\": \"cosmwasm\"")
    s!"manifest target must be cosmwasm, got={manifest}"
  expect (containsSubstr manifest "\"codegenProfile\": \"cosmwasm-wasm-u64-v1\"")
    s!"manifest profile must be cosmwasm-wasm-u64-v1, got={manifest}"
  expect (containsSubstr manifest "\"artifactProgramName\": \"TipJar\"")
    s!"manifest artifact name must be TipJar, got={manifest}"
  expect (containsSubstr manifest s!"\"supportClaimDigest\": \"{claimBare}\"")
    s!"manifest supportClaimDigest must match inspect cosmwasm, got={manifest}"
  let wat ← IO.FS.readFile (outDir / "TipJar.wat")
  expect (containsSubstr wat "$pf_funds_exact")
    "TipJar.wat must carry the exact-one-coin funds helper"
  expect (containsSubstr wat "$pf_funds_empty")
    "TipJar.wat must carry the empty-funds helper"
  expect (containsSubstr wat "$pf_dst_check")
    "TipJar.wat must carry the dst padding validator"
  -- Bank send SubMsg envelope byte constants: `\"bank\":{\"send\":{\"to_address\":`
  -- is emitted byte-by-byte; pin a few decisive opcode comments/fragments.
  expect (containsSubstr wat "pf.assets.native.transfer")
    "TipJar.wat must annotate the bank send site"
  expect (containsSubstr wat "reply_on")
    "TipJar.wat must carry reply_on=never SubMsg envelope bytes"
  let (iec, istdout, istderr) ← runCli
    #["inspect", outDir.toString, "--json"]
  expect (iec == 0)
    s!"inspect tipjar-cw --json must succeed, exit={iec} stderr={istderr} stdout={istdout}"
  expect (containsSubstr istdout "\"target\":\"cosmwasm\"")
    s!"inspect json target, got={istdout}"
  expect (containsSubstr istdout "\"codegenProfile\":\"cosmwasm-wasm-u64-v1\"")
    s!"inspect json profile, got={istdout}"
  expect (containsSubstr istdout
      "\"validation\":\"structure+evidence+artifact-content+exact-disk-closure+outputSetDigest-recompute\"")
    s!"inspect must revalidate exact disk closure, got={istdout}"
  expect (istderr == "")
    s!"inspect ok must be silent on stderr, got={istderr}"

unsafe def run : IO Unit := do
  testCliCheckOk
  testCosmWasmBuildAndInspect
  IO.println "Tests.Product.TipJarCosmWasmV1: ok"

end Tests.Product.TipJarCosmWasmV1
