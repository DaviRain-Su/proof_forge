/-
  Tests.Product.TokenJarEvmV1 — ADR-0030 E1a product vertical.

  Authority: shipped `Examples/TokenJar.lean`.
    * product `check --target evm` succeeds (extension.pf-assets advertised)
    * product `build --target evm` emits proof-forge.output.v1 (Yul+ABI; solc
      finalization when locked solc is available on the host)
    * `inspect <out> --json` revalidates exact disk closure
    * pins target=evm, default profile, TokenJar.yul token-transfer structure
      (ERC-20 selector, 68-byte calldata, dynamic callee, return-value predicate)
    * engineering only: non-formal; Anvil differential is main-agent merge
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import Tests.Language.ParserSession

namespace Tests.Product.TokenJarEvmV1

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
  "sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9"

private def readShipped : IO String := do
  unless ← shippedPath.pathExists do
    throw <| IO.userError "Examples/TokenJar.lean missing (ADR-0030 E1a continuous vector)"
  IO.FS.readFile shippedPath

private def assertShape (text : String) : IO Unit := do
  expect (containsSubstr text "program TokenJar where")
    "must declare program TokenJar"
  expect (containsSubstr text "requires extension pf.assets version \"1.1.0\"")
    "must declare exact pf.assets extension triple"
  expect (containsSubstr text pfAssetsDigestV1)
    "must pin frozen pf.assets domain digest"
  expect (containsSubstr text "call pf.assets.token.transfer(mint, dst, amount)")
    "must call pf.assets.token.transfer"
  expect (containsSubstr text "tipToken")
    "must declare tipToken entry"

private def cliBin : FilePath := FilePath.mk ".lake/build/bin/proof-forge-next"

private def runCli (args : Array String) : IO (UInt32 × String × String) := do
  unless ← cliBin.pathExists do
    throw <| IO.userError "proof-forge-next missing (build product CLI)"
  let absoluteCli ← IO.FS.realPath cliBin
  let out ← IO.Process.output { cmd := absoluteCli.toString, args }
  pure (out.exitCode, out.stdout, out.stderr)

private def testCliCheckOk : IO Unit := do
  assertShape (← readShipped)
  let (code, stdout, stderr) ← runCli
    #["check", "Examples/TokenJar.lean", "--module", "Examples.TokenJar",
      "--target", "evm"]
  expect (code == 0)
    s!"TokenJar check --target evm must succeed, exit={code} stderr={stderr} stdout={stdout}"
  expect (containsSubstr stdout "target=evm")
    s!"check --target evm must pin target, stdout={stdout}"
  expect (containsSubstr stdout "profile=evm-yul-solc-0.8.34")
    s!"check --target evm must pin an EVM profile, stdout={stdout}"

private def testEvmBuildAndInspect : IO Unit := do
  assertShape (← readShipped)
  let (tec, tstdout, tstderr) ← runCli #["inspect", "evm"]
  expect (tec == 0)
    s!"inspect evm must succeed, exit={tec} stderr={tstderr}"
  expect (containsSubstr tstdout "extension.pf-assets")
    s!"inspect evm must advertise extension.pf-assets, got={tstdout}"
  expect (containsSubstr tstdout "effect.synchronous-call")
    s!"inspect evm must advertise effect.synchronous-call, got={tstdout}"
  let claimLine :=
    (tstdout.splitOn "\n").find? (·.startsWith "supportClaimDigest=sha256:")
  let some claimWire := claimLine |
    throw <| IO.userError s!"inspect evm missing supportClaimDigest, got={tstdout}"
  let claimParts := claimWire.splitOn "sha256:"
  expect (claimParts.length == 2)
    s!"supportClaimDigest wire shape, got={claimWire}"
  let claimBare := claimParts[1]!
  expect (claimBare.length == 64)
    s!"supportClaimDigest bare hex length, got={claimBare}"
  let outDir := FilePath.mk "build/v2/tokenjar-evm"
  try IO.FS.removeDirAll outDir catch _ => pure ()
  let (code, stdout, stderr) ← runCli
    #["build", "Examples/TokenJar.lean",
      "--module", "Examples.TokenJar",
      "--target", "evm",
      "-o", outDir.toString]
  expect (code == 0)
    s!"TokenJar build --target evm must succeed, exit={code} stderr={stderr} stdout={stdout}"
  expect (containsSubstr stdout "target=evm")
    s!"build stdout must pin target=evm, stdout={stdout}"
  unless ← (outDir / "manifest.json").pathExists do
    throw <| IO.userError "TokenJar EVM must write manifest.json"
  unless ← (outDir / "evidence.json").pathExists do
    throw <| IO.userError "TokenJar EVM must write evidence.json"
  unless ← (outDir / "TokenJar.yul").pathExists do
    throw <| IO.userError "TokenJar EVM must write TokenJar.yul"
  let manifest ← IO.FS.readFile (outDir / "manifest.json")
  expect (containsSubstr manifest "\"schemaVersion\": \"proof-forge.output.v1\"")
    s!"manifest schemaVersion must be proof-forge.output.v1, got={manifest}"
  expect (containsSubstr manifest "\"target\": \"evm\"")
    s!"manifest target must be evm, got={manifest}"
  expect (containsSubstr manifest "\"artifactProgramName\": \"TokenJar\"")
    s!"manifest artifact name must be TokenJar, got={manifest}"
  expect (containsSubstr manifest "TokenJar.yul")
    s!"manifest files must list TokenJar.yul, got={manifest}"
  expect (containsSubstr manifest "\"contentSha256\":")
    s!"manifest must carry content-bound file descriptors, got={manifest}"
  expect (containsSubstr manifest "\"evidenceSha256\":")
    s!"manifest must bind evidenceSha256, got={manifest}"
  expect (containsSubstr manifest s!"\"supportClaimDigest\": \"{claimBare}\"")
    s!"manifest supportClaimDigest must match inspect evm (pf-assets row), got={manifest}"
  let yul ← IO.FS.readFile (outDir / "TokenJar.yul")
  expect (containsSubstr yul "object \"TokenJar\"")
    "TokenJar.yul must declare object TokenJar"
  -- E1a: ERC-20 transfer selector 0xa9059cbb.
  expect (containsSubstr yul "0xa9059cbb")
    "TokenJar.yul must emit ERC-20 transfer selector"
  -- E1a: 68-byte calldata (4B selector + 32B address + 32B amount).
  expect (containsSubstr yul "0, 68, 0, 32)")
    "TokenJar.yul CALL must use 68-byte calldata + 32-byte return buffer"
  -- E1a: dynamic callee address from mint Principal.
  expect (containsSubstr yul "tokenAddr")
    "TokenJar.yul must bind token contract address from mint Principal"
  -- E1a: wire-shape gates (len==20).
  expect (containsSubstr yul ", 20)")
    "TokenJar.yul must require Principal len == 20"
  -- E1a: return-value predicate (returndatasize switch).
  expect (containsSubstr yul "returndatasize()")
    "TokenJar.yul must read returndatasize for return-value predicate"
  -- E1a: token transfer is non-deposit → entry is nonpayable (no ETH value).
  expect (containsSubstr yul "if callvalue() { revert(0, 0) }")
    "TokenJar.yul nonpayable tipToken must enforce callvalue==0"
  unless ← (outDir / "TokenJar.abi.json").pathExists do
    throw <| IO.userError "TokenJar EVM must write TokenJar.abi.json"
  let abi ← IO.FS.readFile (outDir / "TokenJar.abi.json")
  expect (containsSubstr abi "\"stateMutability\":\"nonpayable\"")
    "TokenJar.abi tipToken must be nonpayable (token transfer carries no ETH)"
  -- inspect re-walks exact disk closure.
  let (iec, istdout, istderr) ← runCli
    #["inspect", outDir.toString, "--json"]
  expect (iec == 0)
    s!"inspect tokenjar-evm --json must succeed, exit={iec} stderr={istderr} stdout={istdout}"
  expect (containsSubstr istdout "\"schema\":\"proof-forge.cli.inspect-output.v1\"")
    s!"inspect json schema, got={istdout}"
  expect (containsSubstr istdout "\"target\":\"evm\"")
    s!"inspect json target, got={istdout}"
  expect (containsSubstr istdout "\"artifactProgramName\":\"TokenJar\"")
    s!"inspect json artifact, got={istdout}"
  expect (containsSubstr istdout
      "\"validation\":\"structure+evidence+artifact-content+exact-disk-closure+outputSetDigest-recompute\"")
    s!"inspect must revalidate exact disk closure, got={istdout}"
  expect (containsSubstr istdout s!"\"supportClaimDigest\":\"sha256:{claimBare}\"")
    s!"inspect json supportClaimDigest must join pf-assets row, got={istdout}"
  expect (istderr == "")
    s!"inspect ok must be silent on stderr, got={istderr}"

unsafe def run : IO Unit := do
  testCliCheckOk
  testEvmBuildAndInspect
  IO.println "Tests.Product.TokenJarEvmV1: ok"

end Tests.Product.TokenJarEvmV1