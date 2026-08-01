/-
  Tests.CLI.DiagnosticsV1 — B8b product CLI diagnostic cutover + C1 surface.

  Spawns the real `proof-forge-next` binary for:
    * multi-error fixture: exit 3, ≥2 human diagnostic lines, no success stdout,
      no output directory, primary lines contain PF-EFFECT-001 and PF-SRC-INVALID
    * usage/config: exit 2 (missing --module, unknown command, unknown --target);
      no diagnostic code invention (no PF-CLI-USAGE / PF-TARGET-UNKNOWN as exception)
    * parser/source boundary: exit 3
    * Counter `build` success: exit 0 + success stdout, no failure artifacts
    * C1: `check` ok/fail, `inspect` digests, `--json` PF-JCS, `--profile` selection
    * inspect-output: build Counter → inspect dir (human + --json + --output-dir);
      missing/tampered manifest/evidence fail closed with PF-OUTPUT-MANIFEST exit 6
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.CLI.Emit

namespace Tests.CLI.DiagnosticsV1

open System
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

private def countLinesWith (s linePrefix : String) : Nat :=
  (s.splitOn "\n").filter (fun line => line.startsWith linePrefix) |>.length

private def cliBin : FilePath :=
  FilePath.mk ".lake/build/bin/proof-forge-next"

private def runCliAt
    (cmd : FilePath) (args : Array String) (cwd : Option FilePath := none) :
    IO (UInt32 × String × String) := do
  let out ← IO.Process.output {
    cmd := cmd.toString
    args := args
    cwd := cwd
  }
  pure (out.exitCode, out.stdout, out.stderr)

private def runCli (args : Array String) (cwd : Option FilePath := none) :
    IO (UInt32 × String × String) := do
  let absoluteCli ← IO.FS.realPath cliBin
  runCliAt absoluteCli args cwd

private def runTool (cmd : String) (args : Array String) : IO Unit := do
  let out ← IO.Process.output { cmd, args }
  expect (out.exitCode == 0)
    s!"fixture tool failed: {cmd} {args}; stderr={out.stderr}"

private def writeExecutable (path : FilePath) (body : String) : IO Unit := do
  IO.FS.writeFile path body
  runTool "/bin/chmod" #["755", path.toString]

private def stripTrailingNewlines (s : String) : String :=
  let rec loop (cs : List Char) : List Char :=
    match cs with
    | [] => []
    | c :: rest =>
        if c == '\n' || c == '\r' then loop rest else cs
  String.ofList (loop s.toList.reverse).reverse

private def expectCanonicalJson (label text : String) : IO Unit := do
  let body := stripTrailingNewlines text
  match parsePfJcs body with
  | .ok value =>
      match renderPfJcs value with
      | .ok again =>
          expect (again == body)
            s!"{label}: PF-JCS must re-encode identically"
      | .error e => throw <| IO.userError s!"{label}: re-render failed: {e}"
  | .error e => throw <| IO.userError s!"{label}: not PF-JCS: {e}\n{text}"

private def testMultiErrorProductCli : IO Unit := do
  let outDir := FilePath.mk "build/v2/diagnostic-multi-v1"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let (ec, stdout, stderr) ← runCli #[
    "build",
    "testdata/invalid/DiagnosticMultiV1.lean",
    "--module", "Root",
    "--target", "solana",
    "-o", "build/v2/diagnostic-multi-v1"
  ]
  expect (ec == 3)
    s!"multi-error CLI exit must be 3, got {ec}\nstderr={stderr}\nstdout={stdout}"
  expect (!containsSubstr stdout "built target=")
    "multi-error must not print success stdout"
  expect (!(← outDir.pathExists))
    "multi-error must not create output directory"
  let effectLines := countLinesWith stderr "PF-EFFECT-001:"
  let srcLines := countLinesWith stderr "PF-SRC-INVALID:"
  expect (effectLines ≥ 1)
    s!"stderr must contain PF-EFFECT-001 line, got:\n{stderr}"
  expect (srcLines ≥ 1)
    s!"stderr must contain PF-SRC-INVALID line, got:\n{stderr}"
  expect (effectLines + srcLines ≥ 2)
    "at least two diagnostic lines must survive without [0]? truncation"
  expect (!containsSubstr stderr "PF-CLI-USAGE")
    "must not invent PF-CLI-USAGE"
  expect (!containsSubstr stderr "PF-SEM-UNKNOWN-ENTRY")
    "must not leak PF-SEM-UNKNOWN-ENTRY"
  expect (!containsSubstr stderr "PF-SEM-WRONG-ARITY")
    "must not leak PF-SEM-WRONG-ARITY"
  expect (!containsSubstr stderr "uncaught exception")
    "product diagnostics must not use uncaught exception path"

private def testUsageExit2 : IO Unit := do
  let (ec, stdout, stderr) ← runCli #[
    "build",
    "Examples/Counter.lean",
    "--target", "solana",
    "-o", "build/v2/module-required-diag"
  ]
  expect (ec == 2)
    s!"missing --module must exit 2, got {ec}\nstderr={stderr}"
  expect (containsSubstr stderr "--module is required for canonical ProgramV1 identity")
    s!"usage message missing, stderr={stderr}"
  expect (!containsSubstr stderr "PF-CLI-USAGE")
    "usage must not invent PF-CLI-USAGE"
  expect (!containsSubstr stderr "PF-SRC-INVALID")
    "usage is not a diagnostic"
  expect (stdout == "")
    "usage failure must not print success stdout"

private def testUnknownCommandExit2 : IO Unit := do
  let (ec, _stdout, stderr) ← runCli #["not-a-command"]
  expect (ec == 2)
    s!"unknown command must exit 2, got {ec}"
  expect (containsSubstr stderr "Usage:")
    s!"unknown command must print usage on stderr, got {stderr}"

private def testUnknownTargetExit2 : IO Unit := do
  let (ec, stdout, stderr) ← runCli #[
    "build",
    "Examples/Counter.lean",
    "--module", "Root",
    "--target", "not-a-real-target",
    "-o", "build/v2/unknown-target-diag"
  ]
  expect (ec == 2)
    s!"unknown --target must exit 2 (failUsage), got {ec}\nstderr={stderr}\nstdout={stdout}"
  expect (containsSubstr stderr "unknown target 'not-a-real-target'")
    s!"unknown target message missing, stderr={stderr}"
  expect (!containsSubstr stderr "uncaught exception")
    "unknown target must not use uncaught-exception exit 1 path"
  expect (!containsSubstr stderr "PF-CLI-USAGE")
    "must not invent PF-CLI-USAGE"
  expect (!containsSubstr stderr "PF-TARGET-UNKNOWN")
    "argv unknown target is usage/config, not a product diagnostic wire code"
  expect (stdout == "")
    "unknown target must not print success stdout"

private def testLanguageVersionSelection : IO Unit := do
  let explicitOut := FilePath.mk "build/v2/language-version-explicit"
  let unknownOut := FilePath.mk "build/v2/language-version-unknown"
  if ← explicitOut.pathExists then IO.FS.removeDirAll explicitOut
  if ← unknownOut.pathExists then IO.FS.removeDirAll unknownOut
  let (explicitEc, explicitStdout, explicitStderr) ← runCli #[
    "build", "Examples/Counter.lean",
    "--module", "Examples.Counter",
    "--target", "solana",
    "--language-version", "1.0.0",
    "-o", explicitOut.toString
  ]
  expect (explicitEc == 0)
    s!"explicit 1.0.0 must follow the default product path: {explicitStderr}"
  expect (containsSubstr explicitStdout "built target=solana")
    "explicit 1.0.0 must build the same product"
  expect (← explicitOut.pathExists) "explicit 1.0.0 must publish"
  IO.FS.removeDirAll explicitOut
  let (unknownEc, unknownStdout, unknownStderr) ← runCli #[
    "build", "does-not-exist.lean",
    "--root", "does-not-exist-root",
    "--module", "Root",
    "--target", "solana",
    "--language-version", "latest",
    "-o", unknownOut.toString
  ]
  expect (unknownEc == 3)
    s!"unknown language version must exit 3, got {unknownEc}: {unknownStderr}"
  expect (containsSubstr unknownStderr
      "PF-LANGUAGE-VERSION-UNKNOWN: language version 'latest' is not registered")
    s!"unknown language version diagnostic missing: {unknownStderr}"
  expect (!containsSubstr unknownStderr "source open failed")
    "language selection must fail before source open"
  expect (unknownStdout == "" && !(← unknownOut.pathExists))
    "unknown language version must produce no success output or artifact"

private def testParserBoundaryExit3 : IO Unit := do
  -- Reuse a known parser-rejected invalid fixture under testdata/invalid.
  -- Relative output is resolved under --root, so inspect that exact destination.
  let outDir := FilePath.mk "testdata/invalid/build/v2/diagnostic-parser-boundary"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let (ec, stdout, stderr) ← runCli #[
    "build",
    "program-kind.lean",
    "--root", "testdata/invalid",
    "--module", "Root",
    "--target", "solana",
    "-o", "build/v2/diagnostic-parser-boundary"
  ]
  -- program-kind may fail at Lean parser or decoder; either is exit 3 product diag.
  expect (ec == 3)
    s!"parser/source invalid must exit 3, got {ec}\nstderr={stderr}\nstdout={stdout}"
  expect (!containsSubstr stdout "built target=")
    "parser failure must not print success"
  expect (!(← outDir.pathExists))
    "parser failure must not create output"

private def testBuildCounterSuccess : IO Unit := do
  let outDir := FilePath.mk "build/v2/diagnostic-build-counter-ok"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let (ec, stdout, stderr) ← runCli #[
    "build",
    "Examples/Counter.lean",
    "--module", "Examples.Counter",
    "--target", "solana",
    "-o", "build/v2/diagnostic-build-counter-ok"
  ]
  expect (ec == 0)
    s!"Counter build success must exit 0, got {ec}\nstderr={stderr}\nstdout={stdout}"
  expect (containsSubstr stdout "built target=solana profile=")
    s!"Counter build success stdout missing, stdout={stdout}"
  expect (containsSubstr stdout "deployable=")
    s!"Counter build must report deployable, stdout={stdout}"
  expect (!containsSubstr stderr "PF-")
    s!"Counter build success must not print product diagnostic codes on stderr, got:\n{stderr}"
  expect (!containsSubstr stderr "uncaught exception")
    "Counter build success must not uncaught-exception"
  expect (← outDir.pathExists)
    "Counter build success must create output directory"

private def testCheckOkAndFail : IO Unit := do
  let (ec, stdout, stderr) ← runCli #[
    "check",
    "Examples/Counter.lean",
    "--module", "Examples.Counter"
  ]
  expect (ec == 0)
    s!"check Counter must exit 0, got {ec}\nstderr={stderr}\nstdout={stdout}"
  expect (containsSubstr stdout "ok\n")
    s!"check ok line missing: {stdout}"
  expect (containsSubstr stdout "program=Counter")
    s!"check program missing: {stdout}"
  expect (containsSubstr stdout "semanticDigest=sha256:")
    s!"check semantic digest missing: {stdout}"
  expect (containsSubstr stdout "sourceDigest=sha256:")
    s!"check source digest missing: {stdout}"
  expect (!containsSubstr stdout "target=")
    "check without --target must omit target"
  expect (stderr == "")
    s!"check ok must be silent on stderr, got {stderr}"
  let (ec2, stdout2, stderr2) ← runCli #[
    "check",
    "Examples/Counter.lean",
    "--module", "Examples.Counter",
    "--target", "solana"
  ]
  expect (ec2 == 0)
    s!"check with target must exit 0, got {ec2}\n{stderr2}"
  expect (containsSubstr stdout2 "target=solana")
    s!"check with target must report target: {stdout2}"
  expect (containsSubstr stdout2 "profile=")
    s!"check with target must report profile: {stdout2}"
  let (ec3, stdout3, stderr3) ← runCli #[
    "check",
    "testdata/invalid/DiagnosticMultiV1.lean",
    "--module", "Root",
    "--target", "solana"
  ]
  expect (ec3 == 3)
    s!"check multi-error must exit 3, got {ec3}\nstderr={stderr3}"
  expect (!containsSubstr stdout3 "ok")
    "check fail must not print ok"
  expect (countLinesWith stderr3 "PF-EFFECT-001:" ≥ 1)
    s!"check fail must surface PF-EFFECT-001:\n{stderr3}"
  let (ec4, _stdout4, stderr4) ← runCli #[
    "check",
    "Examples/Counter.lean",
    "--module", "Examples.Counter",
    "-o", "build/v2/check-must-reject-output"
  ]
  expect (ec4 == 2)
    s!"check -o must be usage exit 2, got {ec4}"
  expect (containsSubstr stderr4 "check does not write artifacts")
    s!"check -o message missing: {stderr4}"

private def testInspectDigests : IO Unit := do
  let (ec, stdout, stderr) ← runCli #["inspect", "evm"]
  expect (ec == 0)
    s!"inspect evm must exit 0, got {ec}\n{stderr}"
  expect (containsSubstr stdout "target=evm\n")
    s!"inspect target line: {stdout}"
  expect (containsSubstr stdout "profile=evm-yul-solc-0.8.34-v1\n")
    s!"inspect profile: {stdout}"
  expect (containsSubstr stdout "requirements=#[")
    s!"inspect requirements: {stdout}"
  expect (containsSubstr stdout "registryRootDigest=sha256:")
    s!"inspect registry root: {stdout}"
  expect (containsSubstr stdout "supportClaimDigest=sha256:")
    s!"inspect support claim: {stdout}"
  expect (containsSubstr stdout "buildIdentityDomain=pf.build-identity.engineering.v1")
    s!"inspect build identity domain: {stdout}"
  let (ec2, stdout2, _) ← runCli #["inspect", "evm"]
  expect (ec2 == 0 && stdout2 == stdout)
    "inspect must be deterministic"
  let (ec3, stdout3, stderr3) ← runCli #["inspect", "openvm"]
  expect (ec3 == 0)
    s!"inspect openvm must exit 0, got {ec3}\n{stderr3}"
  expect (containsSubstr stdout3 "status=research-only")
    s!"inspect design-only status: {stdout3}"
  expect (!containsSubstr stdout3 "supportClaimDigest=")
    "design-only inspect must omit support claim"

private def testJsonSurface : IO Unit := do
  let (ec, stdout, stderr) ← runCli #["list-targets", "--json"]
  expect (ec == 0)
    s!"list-targets --json exit, got {ec}\n{stderr}"
  expectCanonicalJson "list-targets" stdout
  expect (containsSubstr stdout "\"schema\":\"proof-forge.cli.list-targets.v1\"")
    s!"list-targets schema: {stdout}"
  expect (containsSubstr stdout "\"id\":\"evm\"")
    s!"list-targets must include evm: {stdout}"
  let (ec2, stdout2, stderr2) ← runCli #["inspect", "evm", "--json"]
  expect (ec2 == 0)
    s!"inspect --json exit, got {ec2}\n{stderr2}"
  expectCanonicalJson "inspect" stdout2
  expect (containsSubstr stdout2 "\"schema\":\"proof-forge.cli.inspect.v1\"")
    s!"inspect schema: {stdout2}"
  expect (containsSubstr stdout2 "\"registryRootDigest\":\"sha256:")
    s!"inspect json digest: {stdout2}"
  let (ec3, stdout3, stderr3) ← runCli #[
    "check", "Examples/Counter.lean",
    "--module", "Examples.Counter", "--json"
  ]
  expect (ec3 == 0)
    s!"check --json exit, got {ec3}\n{stderr3}"
  expectCanonicalJson "check" stdout3
  expect (containsSubstr stdout3 "\"schema\":\"proof-forge.cli.check.v1\"")
    s!"check schema: {stdout3}"
  expect (containsSubstr stdout3 "\"ok\":true")
    s!"check ok flag: {stdout3}"
  let outDir := FilePath.mk "build/v2/diagnostic-build-json-ok"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let (ec4, stdout4, stderr4) ← runCli #[
    "build", "Examples/Counter.lean",
    "--module", "Examples.Counter",
    "--target", "solana",
    "-o", outDir.toString,
    "--json"
  ]
  expect (ec4 == 0)
    s!"build --json exit, got {ec4}\n{stderr4}"
  expectCanonicalJson "build" stdout4
  expect (containsSubstr stdout4 "\"schema\":\"proof-forge.cli.build.v1\"")
    s!"build schema: {stdout4}"
  expect (containsSubstr stdout4 "\"target\":\"solana\"")
    s!"build target: {stdout4}"
  expect (containsSubstr stdout4 "\"codegenProfile\":")
    s!"build profile field: {stdout4}"

private def testProfileSelection : IO Unit := do
  let outDir := FilePath.mk "build/v2/diagnostic-profile-sbpf-elf"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let (ec, stdout, stderr) ← runCli #[
    "build", "Examples/Counter.lean",
    "--module", "Examples.Counter",
    "--target", "solana",
    "--profile", "solana-sbpf-plan-v1",
    "-o", outDir.toString
  ]
  expect (ec == 0)
    s!"explicit solana plan profile must succeed, got {ec}\n{stderr}"
  expect (containsSubstr stdout "profile=solana-sbpf-plan-v1")
    s!"build must echo selected profile: {stdout}"
  expect (← outDir.pathExists) "profile build must publish"
  -- Manifest records the selected profile.
  let manifest ← IO.FS.readFile (outDir / "manifest.json")
  expect (containsSubstr manifest "solana-sbpf-plan-v1")
    s!"manifest must bind selected profile: {manifest}"
  let (ec2, _stdout2, stderr2) ← runCli #[
    "check", "Examples/Counter.lean",
    "--module", "Examples.Counter",
    "--profile", "solana-sbpf-plan-v1"
  ]
  expect (ec2 == 2)
    s!"check --profile without --target must exit 2, got {ec2}"
  expect (containsSubstr stderr2 "--profile requires --target")
    s!"profile-requires-target message: {stderr2}"
  -- Deleted commands must fall through to usage.
  let (ec3, _stdout3, stderr3) ← runCli #["build-counter", "--target", "solana"]
  expect (ec3 == 2)
    s!"deleted build-counter must exit 2, got {ec3}"
  expect (containsSubstr stderr3 "Usage:")
    s!"deleted build-counter must print usage: {stderr3}"
  let (ec4, _stdout4, stderr4) ← runCli #["describe-target", "evm"]
  expect (ec4 == 2)
    s!"deleted describe-target must exit 2, got {ec4}"
  expect (containsSubstr stderr4 "Usage:")
    s!"deleted describe-target must print usage: {stderr4}"

/-- C1 inspect-output: build Counter → inspect dir → assert fields; tamper fails;
    `--json` golden schema; `--output-dir` form; registered target still preferred. -/
private def testInspectOutputDir : IO Unit := do
  let outDir := FilePath.mk "build/v2/diagnostic-inspect-output-ok"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let (buildEc, buildStdout, buildStderr) ← runCli #[
    "build", "Examples/Counter.lean",
    "--module", "Examples.Counter",
    "--target", "solana",
    "--profile", "solana-sbpf-plan-v1",
    "-o", outDir.toString
  ]
  expect (buildEc == 0)
    s!"inspect-output fixture build must exit 0, got {buildEc}\n{buildStderr}\n{buildStdout}"
  expect (← (outDir / "manifest.json").pathExists) "fixture must write manifest.json"
  expect (← (outDir / "evidence.json").pathExists) "fixture must write evidence.json"
  -- Positional path form.
  let (ec, stdout, stderr) ← runCli #["inspect", outDir.toString]
  expect (ec == 0)
    s!"inspect output-dir must exit 0, got {ec}\n{stderr}\n{stdout}"
  expect (containsSubstr stdout s!"outputDir={outDir}")
    s!"inspect-output outputDir: {stdout}"
  expect (containsSubstr stdout "schemaVersion=proof-forge.output.v1\n")
    s!"inspect-output schemaVersion: {stdout}"
  expect (containsSubstr stdout "target=solana\n")
    s!"inspect-output target: {stdout}"
  expect (containsSubstr stdout "codegenProfile=solana-sbpf-plan-v1\n")
    s!"inspect-output profile: {stdout}"
  expect (containsSubstr stdout "artifactProgramName=Counter\n")
    s!"inspect-output artifact name: {stdout}"
  expect (containsSubstr stdout "sourceHash=sha256:")
    s!"inspect-output sourceHash: {stdout}"
  expect (containsSubstr stdout "semanticHash=sha256:")
    s!"inspect-output semanticHash: {stdout}"
  expect (containsSubstr stdout "buildIdentityDigest=sha256:")
    s!"inspect-output buildIdentity: {stdout}"
  expect (containsSubstr stdout "supportClaimDigest=sha256:")
    s!"inspect-output supportClaim: {stdout}"
  expect (containsSubstr stdout "engineeringRegistryRootDigest=sha256:")
    s!"inspect-output registry root: {stdout}"
  expect (containsSubstr stdout "outputSetDigest=sha256:")
    s!"inspect-output outputSetDigest: {stdout}"
  expect (containsSubstr stdout "deployable=")
    s!"inspect-output deployable: {stdout}"
  expect (containsSubstr stdout "files=#[")
    s!"inspect-output files: {stdout}"
  expect (containsSubstr stdout
      "validation=structure+evidence+digest-format+outputSetDigest-recompute")
    s!"inspect-output validation tag: {stdout}"
  expect (stderr == "")
    s!"inspect-output ok must be silent on stderr, got {stderr}"
  -- Determinism.
  let (ec2, stdout2, _) ← runCli #["inspect", outDir.toString]
  expect (ec2 == 0 && stdout2 == stdout)
    "inspect-output must be deterministic"
  -- Explicit --output-dir form.
  let (ec3, stdout3, stderr3) ← runCli #["inspect", "--output-dir", outDir.toString]
  expect (ec3 == 0)
    s!"inspect --output-dir must exit 0, got {ec3}\n{stderr3}"
  expect (stdout3 == stdout)
    "inspect --output-dir must match positional form"
  -- --json PF-JCS golden shape.
  let (ec4, stdout4, stderr4) ← runCli #["inspect", outDir.toString, "--json"]
  expect (ec4 == 0)
    s!"inspect-output --json exit, got {ec4}\n{stderr4}"
  expectCanonicalJson "inspect-output" stdout4
  expect (containsSubstr stdout4 "\"schema\":\"proof-forge.cli.inspect-output.v1\"")
    s!"inspect-output schema: {stdout4}"
  expect (containsSubstr stdout4 "\"target\":\"solana\"")
    s!"inspect-output json target: {stdout4}"
  expect (containsSubstr stdout4 "\"codegenProfile\":\"solana-sbpf-plan-v1\"")
    s!"inspect-output json profile: {stdout4}"
  expect (containsSubstr stdout4 "\"artifactProgramName\":\"Counter\"")
    s!"inspect-output json artifact: {stdout4}"
  expect (containsSubstr stdout4 "\"sourceHash\":\"sha256:")
    s!"inspect-output json sourceHash: {stdout4}"
  expect (containsSubstr stdout4 "\"outputSetDigest\":\"sha256:")
    s!"inspect-output json outputSetDigest: {stdout4}"
  expect (containsSubstr stdout4
      "\"validation\":\"structure+evidence+digest-format+outputSetDigest-recompute\"")
    s!"inspect-output json validation: {stdout4}"
  -- Explicit --output-dir --json either order.
  let (ec5, stdout5, _) ← runCli #["inspect", "--json", "--output-dir", outDir.toString]
  expect (ec5 == 0 && stdout5 == stdout4)
    "inspect --json --output-dir must match"
  -- Registered target still preferred over a same-named directory (disambiguation).
  let (ecTarget, stdoutTarget, _) ← runCli #["inspect", "solana"]
  expect (ecTarget == 0)
    "inspect solana must remain target inspect"
  expect (containsSubstr stdoutTarget "target=solana\n")
    s!"target inspect still works: {stdoutTarget}"
  expect (!containsSubstr stdoutTarget "outputDir=")
    "registered target must not switch to output-dir mode"
  expect (containsSubstr stdoutTarget "registryRootDigest=sha256:")
    s!"target inspect still reports registry root: {stdoutTarget}"
  -- Missing directory.
  let missingDir := "build/v2/diagnostic-inspect-output-missing"
  if ← (FilePath.mk missingDir).pathExists then
    IO.FS.removeDirAll (FilePath.mk missingDir)
  let (ecMiss, stdoutMiss, stderrMiss) ← runCli #["inspect", missingDir]
  expect (ecMiss == 6)
    s!"missing output-dir must exit 6, got {ecMiss}\n{stderrMiss}"
  expect (containsSubstr stderrMiss "PF-OUTPUT-MANIFEST:")
    s!"missing dir must use PF-OUTPUT-MANIFEST: {stderrMiss}"
  expect (stdoutMiss == "")
    "missing dir must not print success stdout"
  -- Tamper: flip the first hex nibble of outputSetDigest (format still valid,
  -- public recompute must fail closed).
  let originalManifest ← IO.FS.readFile (outDir / "manifest.json")
  let digestMarker := "\"outputSetDigest\": \""
  let parts := originalManifest.splitOn digestMarker
  expect (parts.length ≥ 2)
    s!"manifest must contain outputSetDigest field:\n{originalManifest}"
  let before := parts[0]!
  let after := String.intercalate digestMarker (parts.drop 1)
  let afterChars := after.toList
  expect (!afterChars.isEmpty)
    "outputSetDigest value must be nonempty"
  let first := afterChars.head!
  let flipped : Char := if first == '0' then '1' else '0'
  let tampered :=
    before ++ digestMarker ++ String.singleton flipped ++ String.ofList afterChars.tail!
  expect (tampered != originalManifest)
    "tamper must change manifest text"
  IO.FS.writeFile (outDir / "manifest.json") tampered
  let (ecTamper, stdoutTamper, stderrTamper) ← runCli #["inspect", outDir.toString]
  expect (ecTamper == 6)
    s!"tampered outputSetDigest must exit 6, got {ecTamper}\n{stderrTamper}"
  expect (containsSubstr stderrTamper "PF-OUTPUT-MANIFEST:")
    s!"tamper must use PF-OUTPUT-MANIFEST: {stderrTamper}"
  expect (containsSubstr stderrTamper "outputSetDigest")
    s!"tamper must mention outputSetDigest: {stderrTamper}"
  expect (stdoutTamper == "")
    "tamper must not print success stdout"
  -- Restore then break evidence identity join.
  IO.FS.writeFile (outDir / "manifest.json") originalManifest
  let originalEvidence ← IO.FS.readFile (outDir / "evidence.json")
  let badEvidence :=
    String.intercalate "\"target\": \"near\""
      (originalEvidence.splitOn "\"target\": \"solana\"")
  expect (badEvidence != originalEvidence)
    "evidence tamper must change text"
  IO.FS.writeFile (outDir / "evidence.json") badEvidence
  let (ecEv, stdoutEv, stderrEv) ← runCli #["inspect", "--output-dir", outDir.toString]
  expect (ecEv == 6)
    s!"evidence target mismatch must exit 6, got {ecEv}\n{stderrEv}"
  expect (containsSubstr stderrEv "PF-OUTPUT-MANIFEST:")
    s!"evidence mismatch prefix: {stderrEv}"
  expect (containsSubstr stderrEv "evidence target")
    s!"evidence mismatch message: {stderrEv}"
  expect (stdoutEv == "")
    "evidence mismatch must not print success"
  -- Missing evidence.
  IO.FS.writeFile (outDir / "evidence.json") originalEvidence
  IO.FS.removeFile (outDir / "evidence.json")
  let (ecNoEv, stdoutNoEv, stderrNoEv) ← runCli #["inspect", outDir.toString]
  expect (ecNoEv == 6)
    s!"missing evidence must exit 6, got {ecNoEv}\n{stderrNoEv}"
  expect (containsSubstr stderrNoEv "missing evidence.json")
    s!"missing evidence message: {stderrNoEv}"
  expect (stdoutNoEv == "")
    "missing evidence must not print success"
  -- Cleanup fixture for subsequent runs / disk hygiene.
  if ← outDir.pathExists then IO.FS.removeDirAll outDir

unsafe def run : IO Unit := do
  unless ← cliBin.pathExists do
    throw <| IO.userError
      s!"CLI binary missing at {cliBin}; build proof_forge_next first"
  testUsageExit2
  testUnknownCommandExit2
  testUnknownTargetExit2
  testLanguageVersionSelection
  testMultiErrorProductCli
  testParserBoundaryExit3
  testBuildCounterSuccess
  testCheckOkAndFail
  testInspectDigests
  testJsonSurface
  testProfileSelection
  testInspectOutputDir
  IO.println "Tests.CLI.DiagnosticsV1: ok"

end Tests.CLI.DiagnosticsV1
