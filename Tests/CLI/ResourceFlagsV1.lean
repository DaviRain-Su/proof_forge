/-
  Tests.CLI.ResourceFlagsV1 — D3-E5 SPEC-CLI resource/evidence flags plus RES-1
  pure wall-ms enforce/product CLI PF-RESOURCE-TIME and RES-1B artifact-output
  published-bytes enforcement/PF-RESOURCE-OUTPUT pins.

  Drives shipped pure parse + product preflight (`parseProductCliCommandV1` /
  `parseBuildArgsExcept` / `validateBuildOptionsCliV1` / `parseResourceLimitSpecV1`),
  wall gates, and the pre-publish artifacts+sidecars byte gate.
  Structural `--proof-bundle` / `--proof-bundle-digest` are unknown options
  (product bypass removed; inline certifier owns product proof gating).
  Not formal SPEC-CLI / NFR-008 host receipt or memory containment.
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
  -- published-bytes hard 0 on frontend; artifact-output accepts lower-only.
  expectErr "published zero hard"
    (parseResourceLimitSpecV1 "frontend.published-bytes=1") "hard maximum is 0"
  let publishedLimit ← expectOk "parse output published"
    (parseResourceLimitSpecV1 "artifact-output.published-bytes=123")
  expect (publishedLimit.value == 123) "published override value"
  expect
    (effectivePublishedBytesLimitV1 #[publishedLimit] == 123)
    "published override must become the effective limit"
  expect
    (effectivePublishedBytesLimitV1 #[] == hardOutputProfile.maxPublishedBytes)
    "omitted published override must use the hard output maximum"

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

  -- Structural proof-bundle product flags are deleted; both spellings are
  -- unknown options (no parse pair acceptance / no product bypass).
  expectErr "bundle only"
    (parseProductCliCommandV1
      ["check", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--proof-bundle", "/tmp/pb"])
    "unknown option"
  expectErr "digest only"
    (parseProductCliCommandV1
      ["check", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--proof-bundle-digest", "sha256:0000000000000000000000000000000000000000000000000000000000000000"])
    "unknown option"
  expectErr "bundle pair"
    (parseProductCliCommandV1
      ["check", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--proof-bundle", "bundle-dir",
        "--proof-bundle-digest",
        "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"])
    "unknown option"

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

  -- RES-1B pure published total: artifact bytes plus exact UTF-8 sidecars.
  -- `é` is two UTF-8 bytes, so 100 + 20 + 2 + 1 = 123.
  let publishedTotal := engineeringPublishedBytesV1 #[100, 20] "é" "x"
  expect (publishedTotal == 123) s!"published total must include UTF-8 sidecars: {publishedTotal}"
  match enforcePublishedBytesLimitV1 123 publishedTotal with
  | .error e => throw <| IO.userError s!"published exact limit must pass: {e}"
  | .ok () => pure ()
  expectErr "published over" (enforcePublishedBytesLimitV1 122 publishedTotal)
    "PF-RESOURCE-OUTPUT"

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

    -- RES-1B product build: a lower-only published cap must fire before
    -- atomic rename, classify as exit 6, and leave no destination/staging.
    let publishedOut := FilePath.mk "build/v2/res1b-published-limit"
    if ← publishedOut.pathExists then IO.FS.removeDirAll publishedOut
    let published ← IO.Process.output {
      cmd := absoluteCli.toString
      args := #["build", "Examples/Counter.lean",
        "--module", "Examples.Counter", "--target", "solana",
        "--output", publishedOut.toString,
        "--resource-limit", "artifact-output.published-bytes=1"]
    }
    expect (published.exitCode == 6)
      s!"RES-1B: published-bytes=1 build must exit 6, got {published.exitCode}"
    let publishedCombined := published.stdout ++ "\n" ++ published.stderr
    expect (hasSubstr publishedCombined "PF-RESOURCE-OUTPUT")
      s!"RES-1B: product must emit PF-RESOURCE-OUTPUT, got:\n{publishedCombined}"
    expect (!hasSubstr publishedCombined "PF-OUTPUT-LIMIT")
      s!"RES-1B: lower-only override must not use PF-OUTPUT-LIMIT, got:\n{publishedCombined}"
    expect (!(← publishedOut.pathExists))
      "RES-1B: output limit must not publish a destination"
    let parentEntries ← (FilePath.mk "build/v2").readDir
    let stagingLeft := parentEntries.filter fun e =>
      e.fileName.startsWith ".res1b-published-limit.staging-"
    expect stagingLeft.isEmpty
      "RES-1B: output limit must clean the sibling staging directory"

    -- RES-1 wall zero-publish: wall-ms over during product build must exit 6
    -- with PF-RESOURCE-TIME and must not leave a published destination (or
    -- sibling staging). Pin before rename, not after atomic publish.
    let wallOut := FilePath.mk "build/v2/res1-wall-zero-publish"
    if ← wallOut.pathExists then IO.FS.removeDirAll wallOut
    let wall ← IO.Process.output {
      cmd := absoluteCli.toString
      args := #["build", "Examples/Counter.lean",
        "--module", "Examples.Counter", "--target", "solana",
        "--output", wallOut.toString,
        "--resource-limit", "artifact-output.wall-ms=1"]
    }
    expect (wall.exitCode == 6)
      s!"RES-1 wall zero-publish: wall-ms=1 build must exit 6, got {wall.exitCode}"
    let wallCombined := wall.stdout ++ "\n" ++ wall.stderr
    expect (hasSubstr wallCombined "PF-RESOURCE-TIME")
      s!"RES-1 wall zero-publish: must emit PF-RESOURCE-TIME, got:\n{wallCombined}"
    expect (!(← wallOut.pathExists))
      "RES-1 wall zero-publish: wall limit must not publish a destination"
    let wallParentEntries ← (FilePath.mk "build/v2").readDir
    let wallStagingLeft := wallParentEntries.filter fun e =>
      e.fileName.startsWith ".res1-wall-zero-publish.staging-"
    expect wallStagingLeft.isEmpty
      "RES-1 wall zero-publish: wall limit must clean sibling staging"
  else
    IO.println "Tests.CLI.ResourceFlagsV1: skip product resource CLI (binary absent)"

  IO.println "Tests.CLI.ResourceFlagsV1: ok"

end Tests.CLI.ResourceFlagsV1
