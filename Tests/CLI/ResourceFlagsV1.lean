/-
  Tests.CLI.ResourceFlagsV1 — D3-E5 SPEC-CLI resource/evidence/proof-bundle flags
  plus RES-1 pure wall-ms enforce + product CLI PF-RESOURCE-TIME pin.

  Drives shipped pure parse + product preflight (`parseProductCliCommandV1` /
  `parseBuildArgsExcept` / `validateBuildOptionsCliV1` / `parseResourceLimitSpecV1`)
  and shipped `enforceWallMsLimitV1` / `enforceAllWallMsLimitsV1`.
  Not formal SPEC-CLI / NFR-008 host receipt.
-/
import ProofForgeV2.CLI.Emit
import ProofForgeV2.Core.Common

namespace Tests.CLI.ResourceFlagsV1

open System
open ProofForgeV2.CLI
open ProofForgeV2.Core.Common

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def hasSubstr (s sub : String) : Bool :=
  let rec loop (cs : List Char) : Bool :=
    match cs with
    | [] => sub.isEmpty
    | _ :: rest =>
      if sub.toList.isPrefixOf cs then true else loop rest
  loop s.toList

private def expectErr (label : String) (r : Except String α) (needle : String) : IO Unit :=
  match r with
  | .ok _ => throw <| IO.userError s!"{label}: expected error containing '{needle}'"
  | .error msg =>
      expect (hasSubstr msg needle)
        s!"{label}: error must mention '{needle}', got: {msg}"

private def expectOk (label : String) (r : Except String α) : IO α :=
  match r with
  | .ok v => pure v
  | .error msg => throw <| IO.userError s!"{label}: unexpected error: {msg}"

def run : IO Unit := do
  -- Positive: legal lower-only frontend wall-ms
  let lim ← expectOk "parse wall" (parseResourceLimitSpecV1 "frontend.wall-ms=5000")
  expect (lim.stage == "frontend" && lim.field == "wall-ms" && lim.value == 5000)
    "frontend.wall-ms=5000 must parse"

  -- Hard max reject
  expectErr "over max" (parseResourceLimitSpecV1 "frontend.wall-ms=10001") "exceeds hard maximum"
  -- Zero reject
  expectErr "zero" (parseResourceLimitSpecV1 "frontend.wall-ms=0") "positive"
  -- Unknown stage/field
  expectErr "bad stage" (parseResourceLimitSpecV1 "nope.wall-ms=1") "unknown resource-limit stage"
  expectErr "bad field" (parseResourceLimitSpecV1 "frontend.nope=1") "unknown resource-limit field"
  -- published-bytes hard 0 on frontend
  expectErr "published zero hard"
    (parseResourceLimitSpecV1 "frontend.published-bytes=1") "hard maximum is 0"

  -- Build args: accept resource-limit + minimum-evidence
  let buildOpts ← expectOk "build parse"
    (parseBuildArgsExcept
      ["Examples/Counter.lean", "--module", "Examples.Counter", "--target", "evm",
        "--resource-limit", "compiler-core.wall-ms=1000",
        "--minimum-evidence", "artifact_validated"])
  expect (buildOpts.resourceLimits.size == 1) "one resource limit"
  expect (buildOpts.minimumEvidence == some "artifact_validated") "minimum evidence"

  let buildOk ← expectOk "build validate"
    (validateBuildOptionsCliV1 .build buildOpts)
  expect (buildOk.resourceLimits[0]!.value == 1000) "validated build keeps limit"

  -- Product preflight: check rejects external-tool stage
  expectErr "check external-tool"
    (parseProductCliCommandV1
      ["check", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--resource-limit", "external-tool.wall-ms=1000"])
    "check rejects"

  -- Product preflight: check rejects minimum-evidence
  expectErr "check min-evidence"
    (parseProductCliCommandV1
      ["check", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--minimum-evidence", "specified"])
    "not accepted on check"

  -- Product preflight: bad evidence grade on build
  expectErr "bad grade"
    (parseProductCliCommandV1
      ["build", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--target", "evm", "--minimum-evidence", "not-a-grade"])
    "unknown --minimum-evidence"

  -- Duplicate resource-limit same key
  expectErr "dup limit"
    (parseProductCliCommandV1
      ["check", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--resource-limit", "frontend.wall-ms=100",
        "--resource-limit", "frontend.wall-ms=200"])
    "duplicate --resource-limit"

  -- Proof-bundle unpaired / pair fail closed (product path)
  expectErr "bundle only"
    (parseProductCliCommandV1
      ["check", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--proof-bundle", "/tmp/pb"])
    "--proof-bundle requires"
  expectErr "digest only"
    (parseProductCliCommandV1
      ["check", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--proof-bundle-digest", "sha256:0000000000000000000000000000000000000000000000000000000000000000"])
    "--proof-bundle-digest requires"
  -- INV-1: pair shape is accepted at parse; unused-on-Counter is a product-time
  -- join gate (source has no proof references), not a parse rejection.
  match parseProductCliCommandV1
      ["check", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--proof-bundle", "bundle-dir",
        "--proof-bundle-digest",
        "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"] with
  | .error e => throw <| IO.userError s!"bundle pair parse must succeed (INV-1): {e}"
  | .ok _ => pure ()

  -- Unknown option still fail closed
  expectErr "network"
    (parseProductCliCommandV1
      ["build", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--target", "evm", "--network", "local"])
    "unknown option"

  -- Observable JSON includes resourceLimits (shipped renderer)
  let dig : Digest :=
    { algorithm := .sha256
      bytes := ByteArray.mk (Array.replicate 32 0) }
  match renderCheckOkJsonV1 "Counter" dig dig none none
      #[{ stage := "frontend", field := "wall-ms", value := 5000 }] with
  | .error e => throw <| IO.userError s!"render check json: {e.render}"
  | .ok text =>
      expect (hasSubstr text "resourceLimits") "check json must list resourceLimits"
      expect (hasSubstr text "wall-ms") "check json must include field"
      expect (hasSubstr text "5000") "check json must include value"
      match parsePfJcs text with
      | .error e => throw <| IO.userError s!"check json PF-JCS: {e}"
      | .ok _ => pure ()

  -- RES-1 pure wall enforce (shipped)
  match enforceWallMsLimitV1 "frontend" none 999999 with
  | .error e => throw <| IO.userError s!"no limit must ok: {e}"
  | .ok () => pure ()
  match enforceWallMsLimitV1 "frontend" (some 100) 100 with
  | .error e => throw <| IO.userError s!"exact limit must ok: {e}"
  | .ok () => pure ()
  match enforceWallMsLimitV1 "frontend" (some 100) 101 with
  | .ok () => throw <| IO.userError "over limit must fail"
  | .error msg =>
      expect (hasSubstr msg "PF-RESOURCE-TIME") s!"must cite PF-RESOURCE-TIME, got {msg}"
  match enforceAllWallMsLimitsV1
      #[{ stage := "compiler-core", field := "wall-ms", value := 50 }] 51 with
  | .ok () => throw <| IO.userError "all-wall over must fail"
  | .error msg =>
      expect (hasSubstr msg "compiler-core") s!"stage in message: {msg}"

  -- RES-1 product CLI: Counter check with frontend.wall-ms=1 must fail closed.
  let cliBin := FilePath.mk ".lake/build/bin/proof-forge-next"
  if ← cliBin.pathExists then
    let absoluteCli ← IO.FS.realPath cliBin
    let out ← IO.Process.output {
      cmd := absoluteCli.toString
      args := #["check", "Examples/Counter.lean",
        "--module", "Examples.Counter",
        "--resource-limit", "frontend.wall-ms=1"]
    }
    expect (out.exitCode != 0)
      s!"RES-1: wall-ms=1 check must fail, exit={out.exitCode}"
    let combined := out.stdout ++ "\n" ++ out.stderr
    expect (hasSubstr combined "PF-RESOURCE-TIME")
      s!"RES-1: product must emit PF-RESOURCE-TIME, got:\n{combined}"
  else
    IO.println "Tests.CLI.ResourceFlagsV1: skip product wall CLI (binary absent)"

  IO.println "Tests.CLI.ResourceFlagsV1: ok"

end Tests.CLI.ResourceFlagsV1
