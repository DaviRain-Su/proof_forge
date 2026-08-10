/-
  Tests.CLI.DiagnosticsV1 — B8b product CLI diagnostic cutover + C1 surface.

  Spawns the real `proof-forge-next` binary for:
    * multi-error fixture: exit 3, ≥2 human diagnostic lines, no success stdout,
      no output directory, primary lines contain PF-EFFECT-001 and PF-SRC-INVALID
    * usage/config: exit 2 (missing --module, unknown command, unknown --target);
      no diagnostic code invention (no PF-CLI-USAGE / PF-TARGET-UNKNOWN as exception)
    * parser/source boundary: exit 3
    * StateCell `build` success: exit 0 + success stdout, no failure artifacts
    * C1: `check` ok/fail, `inspect` digests, `--json` PF-JCS, `--profile` selection
    * inspect-output: build StateCell → inspect dir (human + --json + --output-dir);
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
    "Examples/StateCell.lean",
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
    "Examples/StateCell.lean",
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
    "build", "Examples/StateCell.lean",
    "--module", "Examples.StateCell",
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

/-- #125 Solana call/schedule diagnostic matrix (no Escrow positive here —
    that product path is covered by SolanaCpiActivationV1):
    * retired plan/elf profiles: selection fails with PF-PROFILE-UNKNOWN,
      before requirement resolution, with zero artifacts
    * exact CPI: unknown Oracle call fails closed (PF-PLAN-INVARIANT after
      ordinary resolve admits sync); schedule still PF-REQ-UNSUPPORTED;
      unknown API path remains fail-closed with zero artifacts
    Diagnostics are not relaxed. -/
private def testSolanaCallsFailClosed : IO Unit := do
  let fixtureDir := FilePath.mk "build/v2"
  IO.FS.createDirAll fixtureDir
  let callPath := fixtureDir / "diagnostic-solana-call-fail.lean"
  let schedulePath := fixtureDir / "diagnostic-solana-schedule-fail.lean"
  let unknownPath := fixtureDir / "diagnostic-solana-unknown-fail.lean"
  let callSource :=
    "import ProofForgeV2\n" ++
    "namespace Tests.CLI\n" ++
    "open ProofForgeV2.Language\n" ++
    "program SolanaCallFail where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry run() : UInt64 do\n" ++
    "    call Oracle.feed(count)\n" ++
    "    return count\n" ++
    "end Tests.CLI\n"
  let scheduleSource :=
    "import ProofForgeV2\n" ++
    "namespace Tests.CLI\n" ++
    "open ProofForgeV2.Language\n" ++
    "program SolanaScheduleFail where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry run() : UInt64 do\n" ++
    "    schedule Ledger.daily(count)\n" ++
    "    return count\n" ++
    "end Tests.CLI\n"
  let unknownSource :=
    "import ProofForgeV2\n" ++
    "namespace Tests.CLI\n" ++
    "open ProofForgeV2.Language\n" ++
    "program SolanaUnknownFail where\n" ++
    "  requires extension solana.cpi.accounts version \"1.0.0\"\n" ++
    "    digest \"sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020\"\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry run(account : Principal, delta : UInt64) : UInt64 do\n" ++
    "    call solana.unknown.notAnApi(account, delta)\n" ++
    "    return count\n" ++
    "end Tests.CLI\n"
  IO.FS.writeFile callPath callSource
  IO.FS.writeFile schedulePath scheduleSource
  IO.FS.writeFile unknownPath unknownSource
  -- Retired plan/elf profiles fail at selection before requirement resolution.
  let retiredProfiles := #["solana-sbpf-plan-v1", "solana-sbpf-elf-v1"]
  let retiredCases : Array (String × FilePath × String) := #[
    ("call", callPath, "Tests.CLI.SolanaCallFail"),
    ("schedule", schedulePath, "Tests.CLI.SolanaScheduleFail")
  ]
  for (kind, sourcePath, moduleName) in retiredCases do
    for profile in retiredProfiles do
      let outDir := fixtureDir / s!"diagnostic-solana-{kind}-{profile}-output"
      if ← outDir.pathExists then IO.FS.removeDirAll outDir
      let (ec, stdout, stderr) ← runCli #[
        "build", sourcePath.toString,
        "--module", moduleName,
        "--target", "solana",
        "--profile", profile,
        "-o", outDir.toString
      ]
      expect (ec != 0)
        s!"retired Solana {kind}/{profile} must fail, got exit {ec}\n{stdout}\n{stderr}"
      expect (containsSubstr stderr "PF-PROFILE-UNKNOWN" &&
          containsSubstr stderr profile)
        s!"retired Solana {kind}/{profile} diagnostic must reject the profile: {stderr}"
      expect (!containsSubstr stdout "built target=")
        s!"retired Solana {kind}/{profile} must not print build success"
      expect (!(← outDir.pathExists))
        s!"retired Solana {kind}/{profile} must create zero output tree"
  -- Exact CPI: schedule still PF-REQ-UNSUPPORTED (async declined).
  let cpiScheduleOut := fixtureDir / "diagnostic-solana-schedule-solana-sbpf-cpi-elf-v1-output"
  if ← cpiScheduleOut.pathExists then IO.FS.removeDirAll cpiScheduleOut
  let (ecSched, stdoutSched, stderrSched) ← runCli #[
    "build", schedulePath.toString,
    "--module", "Tests.CLI.SolanaScheduleFail",
    "--target", "solana",
    "--profile", "solana-sbpf-cpi-elf-v1",
    "-o", cpiScheduleOut.toString
  ]
  expect (ecSched != 0)
    s!"cpi schedule must fail, got exit {ecSched}\n{stdoutSched}\n{stderrSched}"
  expect (containsSubstr stderrSched "PF-REQ-UNSUPPORTED" &&
      containsSubstr stderrSched "effect.asynchronous-workflow")
    s!"cpi schedule diagnostic must name async: {stderrSched}"
  expect (!containsSubstr stdoutSched "built target=")
    "cpi schedule must not print build success"
  expect (!(← cpiScheduleOut.pathExists))
    "cpi schedule must create zero output tree"
  -- Exact CPI: unknown Oracle call — ordinary resolve admits sync, product Plan
  -- fails closed (no catalog entry). Zero artifacts.
  let cpiCallOut := fixtureDir / "diagnostic-solana-call-solana-sbpf-cpi-elf-v1-output"
  if ← cpiCallOut.pathExists then IO.FS.removeDirAll cpiCallOut
  let (ecCall, stdoutCall, stderrCall) ← runCli #[
    "build", callPath.toString,
    "--module", "Tests.CLI.SolanaCallFail",
    "--target", "solana",
    "--profile", "solana-sbpf-cpi-elf-v1",
    "-o", cpiCallOut.toString
  ]
  expect (ecCall != 0)
    s!"cpi unknown call must fail, got exit {ecCall}\n{stdoutCall}\n{stderrCall}"
  expect (containsSubstr stderrCall "PF-PLAN-INVARIANT" ||
      containsSubstr stderrCall "PF-REQ-UNSUPPORTED" ||
      containsSubstr stderrCall "PF-")
    s!"cpi unknown call must fail closed with product diagnostic: {stderrCall}"
  expect (!containsSubstr stdoutCall "built target=")
    "cpi unknown call must not print build success"
  expect (!(← cpiCallOut.pathExists))
    "cpi unknown call must create zero output tree"
  -- Exact CPI: unknown frozen API with extension still fail-closed, zero artifacts.
  let cpiUnknownOut := fixtureDir / "diagnostic-solana-unknown-solana-sbpf-cpi-elf-v1-output"
  if ← cpiUnknownOut.pathExists then IO.FS.removeDirAll cpiUnknownOut
  let (ecUnk, stdoutUnk, stderrUnk) ← runCli #[
    "build", unknownPath.toString,
    "--module", "Tests.CLI.SolanaUnknownFail",
    "--target", "solana",
    "--profile", "solana-sbpf-cpi-elf-v1",
    "-o", cpiUnknownOut.toString
  ]
  expect (ecUnk != 0)
    s!"cpi unknown API must fail, got exit {ecUnk}\n{stdoutUnk}\n{stderrUnk}"
  expect (containsSubstr stderrUnk "PF-PLAN-INVARIANT" ||
      containsSubstr stderrUnk "PF-REQ-UNSUPPORTED" ||
      containsSubstr stderrUnk "PF-")
    s!"cpi unknown API must fail closed: {stderrUnk}"
  expect (!containsSubstr stdoutUnk "built target=")
    "cpi unknown API must not print build success"
  expect (!(← cpiUnknownOut.pathExists))
    "cpi unknown API must create zero output tree"
  if ← callPath.pathExists then IO.FS.removeFile callPath
  if ← schedulePath.pathExists then IO.FS.removeFile schedulePath
  if ← unknownPath.pathExists then IO.FS.removeFile unknownPath

private def testBuildStateCellSuccess : IO Unit := do
  let outDir := FilePath.mk "build/v2/diagnostic-build-stateCell-ok"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let (ec, stdout, stderr) ← runCli #[
    "build",
    "Examples/StateCell.lean",
    "--module", "Examples.StateCell",
    "--target", "solana",
    "-o", "build/v2/diagnostic-build-stateCell-ok"
  ]
  expect (ec == 0)
    s!"StateCell build success must exit 0, got {ec}\nstderr={stderr}\nstdout={stdout}"
  expect (containsSubstr stdout "built target=solana profile=")
    s!"StateCell build success stdout missing, stdout={stdout}"
  expect (containsSubstr stdout "deployable=")
    s!"StateCell build must report deployable, stdout={stdout}"
  expect (!containsSubstr stderr "PF-")
    s!"StateCell build success must not print product diagnostic codes on stderr, got:\n{stderr}"
  expect (!containsSubstr stderr "uncaught exception")
    "StateCell build success must not uncaught-exception"
  expect (← outDir.pathExists)
    "StateCell build success must create output directory"

private def testCheckOkAndFail : IO Unit := do
  let (ec, stdout, stderr) ← runCli #[
    "check",
    "Examples/StateCell.lean",
    "--module", "Examples.StateCell"
  ]
  expect (ec == 0)
    s!"check StateCell must exit 0, got {ec}\nstderr={stderr}\nstdout={stdout}"
  expect (containsSubstr stdout "ok\n")
    s!"check ok line missing: {stdout}"
  expect (containsSubstr stdout "program=StateCell")
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
    "Examples/StateCell.lean",
    "--module", "Examples.StateCell",
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
    "Examples/StateCell.lean",
    "--module", "Examples.StateCell",
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
  expect (containsSubstr stdout "profile=evm-yul-solc-0.8.34-hashmap-v1\n")
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
    "check", "Examples/StateCell.lean",
    "--module", "Examples.StateCell", "--json"
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
    "build", "Examples/StateCell.lean",
    "--module", "Examples.StateCell",
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
    "build", "Examples/StateCell.lean",
    "--module", "Examples.StateCell",
    "--target", "solana",
    "--profile", "solana-sbpf-cpi-elf-v1",
    "-o", outDir.toString
  ]
  expect (ec == 0)
    s!"explicit solana plan profile must succeed, got {ec}\n{stderr}"
  expect (containsSubstr stdout "profile=solana-sbpf-cpi-elf-v1")
    s!"build must echo selected profile: {stdout}"
  expect (← outDir.pathExists) "profile build must publish"
  -- Manifest records the selected profile.
  let manifest ← IO.FS.readFile (outDir / "manifest.json")
  expect (containsSubstr manifest "solana-sbpf-cpi-elf-v1")
    s!"manifest must bind selected profile: {manifest}"

  -- ADR-0032 U1 P4: StateCell body-only admits on sole rail cpi-elf (no
  -- extension / sync / caller required). Deployable ELF + hybrid IR.
  let cpiOutDir := FilePath.mk "build/v2/diagnostic-profile-sbpf-cpi-body"
  if ← cpiOutDir.pathExists then IO.FS.removeDirAll cpiOutDir
  let (cpiEc, cpiStdout, cpiStderr) ← runCli #[
    "build", "Examples/StateCell.lean",
    "--module", "Examples.StateCell",
    "--target", "solana",
    "--profile", "solana-sbpf-cpi-elf-v1",
    "-o", cpiOutDir.toString
  ]
  expect (cpiEc == 0)
    s!"StateCell on cpi profile must succeed body-only, got {cpiEc}\n{cpiStderr}\n{cpiStdout}"
  expect (containsSubstr cpiStdout "profile=solana-sbpf-cpi-elf-v1")
    s!"build must echo cpi profile: {cpiStdout}"
  expect (containsSubstr cpiStdout "deployable=true")
    s!"body-only cpi-elf must be deployable: {cpiStdout}"
  unless ← (cpiOutDir / "StateCell.so").pathExists do
    throw <| IO.userError "StateCell cpi body-only must write StateCell.so"
  let cpiIr ← IO.FS.readFile (cpiOutDir / "StateCell.cpi-ir.json")
  expect (containsSubstr cpiIr "p3c-zero-site" || containsSubstr cpiIr "zero-site")
    s!"body-only hybrid ir must mark zero-site, got={cpiIr}"

  let (ec2, _stdout2, stderr2) ← runCli #[
    "check", "Examples/StateCell.lean",
    "--module", "Examples.StateCell",
    "--profile", "solana-sbpf-cpi-elf-v1"
  ]
  expect (ec2 == 2)
    s!"check --profile without --target must exit 2, got {ec2}"
  expect (containsSubstr stderr2 "--profile requires --target")
    s!"profile-requires-target message: {stderr2}"
  -- Deleted commands must fall through to usage.
  let (ec3, _stdout3, stderr3) ← runCli #["build-stateCell", "--target", "solana"]
  expect (ec3 == 2)
    s!"deleted build-stateCell must exit 2, got {ec3}"
  expect (containsSubstr stderr3 "Usage:")
    s!"deleted build-stateCell must print usage: {stderr3}"
  let (ec4, _stdout4, stderr4) ← runCli #["describe-target", "evm"]
  expect (ec4 == 2)
    s!"deleted describe-target must exit 2, got {ec4}"
  expect (containsSubstr stderr4 "Usage:")
    s!"deleted describe-target must print usage: {stderr4}"

/-- Build solana StateCell fixture for inspect-output tests. -/
private def buildInspectOutputFixture (outDir : FilePath) : IO Unit := do
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let (buildEc, buildStdout, buildStderr) ← runCli #[
    "build", "Examples/StateCell.lean",
    "--module", "Examples.StateCell",
    "--target", "solana",
    "--profile", "solana-sbpf-cpi-elf-v1",
    "-o", outDir.toString
  ]
  expect (buildEc == 0)
    s!"inspect-output fixture build must exit 0, got {buildEc}\n{buildStderr}\n{buildStdout}"
  expect (← (outDir / "manifest.json").pathExists) "fixture must write manifest.json"
  expect (← (outDir / "evidence.json").pathExists) "fixture must write evidence.json"

/-- C1 inspect-output positive path: fields, determinism, json, --output-dir. -/
private def testInspectOutputDirPositive : IO Unit := do
  let outDir := FilePath.mk "build/v2/diagnostic-inspect-output-ok"
  buildInspectOutputFixture outDir
  let (ec, stdout, stderr) ← runCli #["inspect", outDir.toString]
  expect (ec == 0)
    s!"inspect output-dir must exit 0, got {ec}\n{stderr}\n{stdout}"
  expect (containsSubstr stdout s!"outputDir={outDir}")
    s!"inspect-output outputDir: {stdout}"
  expect (containsSubstr stdout "schemaVersion=proof-forge.output.v1\n")
    s!"inspect-output schemaVersion: {stdout}"
  expect (containsSubstr stdout "target=solana\n")
    s!"inspect-output target: {stdout}"
  expect (containsSubstr stdout "codegenProfile=solana-sbpf-cpi-elf-v1\n")
    s!"inspect-output profile: {stdout}"
  expect (containsSubstr stdout "artifactProgramName=StateCell\n")
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
  expect (containsSubstr stdout "evidenceSha256=sha256:")
    s!"inspect-output evidenceSha256: {stdout}"
  expect (containsSubstr stdout "deployable=")
    s!"inspect-output deployable: {stdout}"
  expect (containsSubstr stdout "files=#[")
    s!"inspect-output files: {stdout}"
  expect (containsSubstr stdout
      "validation=structure+evidence+artifact-content+exact-disk-closure+outputSetDigest-recompute")
    s!"inspect-output validation tag: {stdout}"
  expect (stderr == "")
    s!"inspect-output ok must be silent on stderr, got {stderr}"
  let (ec2, stdout2, _) ← runCli #["inspect", outDir.toString]
  expect (ec2 == 0 && stdout2 == stdout)
    "inspect-output must be deterministic"
  let (ec3, stdout3, stderr3) ← runCli #["inspect", "--output-dir", outDir.toString]
  expect (ec3 == 0)
    s!"inspect --output-dir must exit 0, got {ec3}\n{stderr3}"
  expect (stdout3 == stdout)
    "inspect --output-dir must match positional form"
  let (ec4, stdout4, stderr4) ← runCli #["inspect", outDir.toString, "--json"]
  expect (ec4 == 0)
    s!"inspect-output --json exit, got {ec4}\n{stderr4}"
  expectCanonicalJson "inspect-output" stdout4
  expect (containsSubstr stdout4 "\"schema\":\"proof-forge.cli.inspect-output.v1\"")
    s!"inspect-output schema: {stdout4}"
  expect (containsSubstr stdout4 "\"target\":\"solana\"")
    s!"inspect-output json target: {stdout4}"
  expect (containsSubstr stdout4 "\"codegenProfile\":\"solana-sbpf-cpi-elf-v1\"")
    s!"inspect-output json profile: {stdout4}"
  expect (containsSubstr stdout4 "\"artifactProgramName\":\"StateCell\"")
    s!"inspect-output json artifact: {stdout4}"
  expect (containsSubstr stdout4 "\"sourceHash\":\"sha256:")
    s!"inspect-output json sourceHash: {stdout4}"
  expect (containsSubstr stdout4 "\"outputSetDigest\":\"sha256:")
    s!"inspect-output json outputSetDigest: {stdout4}"
  expect (containsSubstr stdout4 "\"evidenceSha256\":\"sha256:")
    s!"inspect-output json evidenceSha256: {stdout4}"
  expect (containsSubstr stdout4 "\"contentSha256\":\"sha256:")
    s!"inspect-output json file contentSha256: {stdout4}"
  expect (containsSubstr stdout4
      "\"validation\":\"structure+evidence+artifact-content+exact-disk-closure+outputSetDigest-recompute\"")
    s!"inspect-output json validation: {stdout4}"
  let (ec5, stdout5, _) ← runCli #["inspect", "--json", "--output-dir", outDir.toString]
  expect (ec5 == 0 && stdout5 == stdout4)
    "inspect --json --output-dir must match"
  let (ecTarget, stdoutTarget, _) ← runCli #["inspect", "solana"]
  expect (ecTarget == 0)
    "inspect solana must remain target inspect"
  expect (containsSubstr stdoutTarget "target=solana\n")
    s!"target inspect still works: {stdoutTarget}"
  expect (!containsSubstr stdoutTarget "outputDir=")
    "registered target must not switch to output-dir mode"
  expect (containsSubstr stdoutTarget "registryRootDigest=sha256:")
    s!"target inspect still reports registry root: {stdoutTarget}"

/-- Ensure fixture exists; return (outDir, originalManifest, originalEvidence). -/
private def ensureInspectFixture :
    IO (FilePath × String × String) := do
  let outDir := FilePath.mk "build/v2/diagnostic-inspect-output-ok"
  unless (← (outDir / "manifest.json").pathExists) do
    buildInspectOutputFixture outDir
  let originalManifest ← IO.FS.readFile (outDir / "manifest.json")
  let originalEvidence ← IO.FS.readFile (outDir / "evidence.json")
  pure (outDir, originalManifest, originalEvidence)

/-- Negatives A: missing dir, outputSetDigest, evidence, content, extra leaf. -/
private def testInspectOutputDirNegativesA : IO Unit := do
  let (outDir, originalManifest, originalEvidence) ← ensureInspectFixture
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
  IO.FS.writeFile (outDir / "manifest.json") originalManifest
  let badEvidence :=
    String.intercalate "\"target\": \"near\""
      (originalEvidence.splitOn "\"target\": \"solana\"")
  IO.FS.writeFile (outDir / "evidence.json") badEvidence
  let (ecEv, stdoutEv, stderrEv) ← runCli #["inspect", "--output-dir", outDir.toString]
  expect (ecEv == 6)
    s!"evidence target mismatch must exit 6, got {ecEv}\n{stderrEv}"
  expect (containsSubstr stderrEv "PF-OUTPUT-MANIFEST:")
    s!"evidence mismatch prefix: {stderrEv}"
  expect (containsSubstr stderrEv "evidence" || containsSubstr stderrEv "evidenceSha256")
    s!"evidence mismatch message: {stderrEv}"
  expect (stdoutEv == "")
    "evidence mismatch must not print success"
  IO.FS.writeFile (outDir / "evidence.json") originalEvidence
  let noteTampered :=
    if (originalEvidence.splitOn "\"note\": \"").length ≥ 2 then
      let p := originalEvidence.splitOn "\"note\": \""
      p[0]! ++ "\"note\": \"x" ++ String.intercalate "\"note\": \"" (p.drop 1)
    else
      originalEvidence ++ " "
  IO.FS.writeFile (outDir / "evidence.json") noteTampered
  let (ecNote, stdoutNote, stderrNote) ← runCli #["inspect", outDir.toString]
  expect (ecNote == 6)
    s!"evidence note-only tamper must exit 6, got {ecNote}\n{stderrNote}"
  expect (containsSubstr stderrNote "PF-OUTPUT-MANIFEST:")
    s!"note tamper prefix: {stderrNote}"
  expect (containsSubstr stderrNote "evidence")
    s!"note tamper must mention evidence: {stderrNote}"
  expect (stdoutNote == "")
    "note tamper must not print success"
  IO.FS.writeFile (outDir / "evidence.json") originalEvidence
  let artifactPath := outDir / "StateCell.cpi-plan.json"
  expect (← artifactPath.pathExists) "fixture must have StateCell.cpi-plan.json"
  let originalArtifact ← IO.FS.readFile artifactPath
  IO.FS.writeFile artifactPath (originalArtifact ++ "\n//tamper")
  let (ecArt, stdoutArt, stderrArt) ← runCli #["inspect", outDir.toString]
  expect (ecArt == 6)
    s!"artifact content tamper must exit 6, got {ecArt}\n{stderrArt}"
  expect (containsSubstr stderrArt "PF-OUTPUT-MANIFEST:")
    s!"artifact tamper prefix: {stderrArt}"
  expect (containsSubstr stderrArt "artifact content" ||
      containsSubstr stderrArt "diverges")
    s!"artifact tamper message: {stderrArt}"
  expect (stdoutArt == "")
    "artifact tamper must not print success"
  IO.FS.writeFile artifactPath originalArtifact
  IO.FS.writeFile (outDir / "extra-rogue.txt") "rogue"
  let (ecExtra, stdoutExtra, stderrExtra) ← runCli #["inspect", outDir.toString]
  expect (ecExtra == 6)
    s!"extra leaf must exit 6, got {ecExtra}\n{stderrExtra}"
  expect (containsSubstr stderrExtra "PF-OUTPUT-MANIFEST:")
    s!"extra leaf prefix: {stderrExtra}"
  expect (containsSubstr stderrExtra "unexpected" || containsSubstr stderrExtra "extra")
    s!"extra leaf message: {stderrExtra}"
  expect (stdoutExtra == "")
    "extra leaf must not print success"
  IO.FS.removeFile (outDir / "extra-rogue.txt")

/-- Negatives B: missing evidence/artifact, descriptor role/path/size/hash, legacy. -/
private def testInspectOutputDirNegativesB : IO Unit := do
  let (outDir, originalManifest, originalEvidence) ← ensureInspectFixture
  IO.FS.writeFile (outDir / "manifest.json") originalManifest
  IO.FS.writeFile (outDir / "evidence.json") originalEvidence
  IO.FS.removeFile (outDir / "evidence.json")
  let (ecNoEv, stdoutNoEv, stderrNoEv) ← runCli #["inspect", outDir.toString]
  expect (ecNoEv == 6)
    s!"missing evidence must exit 6, got {ecNoEv}\n{stderrNoEv}"
  expect (containsSubstr stderrNoEv "evidence.json")
    s!"missing evidence message: {stderrNoEv}"
  expect (stdoutNoEv == "")
    "missing evidence must not print success"
  IO.FS.writeFile (outDir / "evidence.json") originalEvidence
  let idlPath := outDir / "StateCell.idl.json"
  expect (← idlPath.pathExists) "fixture must have StateCell.idl.json"
  let idlBytes ← IO.FS.readFile idlPath
  IO.FS.removeFile idlPath
  let (ecMissArt, stdoutMissArt, stderrMissArt) ← runCli #["inspect", outDir.toString]
  expect (ecMissArt == 6)
    s!"missing listed artifact must exit 6, got {ecMissArt}\n{stderrMissArt}"
  expect (containsSubstr stderrMissArt "PF-OUTPUT-MANIFEST:")
    s!"missing artifact prefix: {stderrMissArt}"
  expect (containsSubstr stderrMissArt "StateCell.idl.json" ||
      containsSubstr stderrMissArt "missing")
    s!"missing artifact message: {stderrMissArt}"
  expect (stdoutMissArt == "")
    "missing artifact must not print success"
  IO.FS.writeFile idlPath idlBytes
  let contentMarker := "\"contentSha256\": \""
  let cParts := originalManifest.splitOn contentMarker
  expect (cParts.length ≥ 2)
    s!"manifest must contain contentSha256:\n{originalManifest}"
  let cBefore := cParts[0]!
  let cAfter := String.intercalate contentMarker (cParts.drop 1)
  let cChars := cAfter.toList
  expect (!cChars.isEmpty) "contentSha256 value nonempty"
  let cFirst := cChars.head!
  let cFlipped : Char := if cFirst == '0' then '1' else '0'
  let contentTampered :=
    cBefore ++ contentMarker ++ String.singleton cFlipped ++ String.ofList cChars.tail!
  IO.FS.writeFile (outDir / "manifest.json") contentTampered
  let (ecHash, stdoutHash, stderrHash) ← runCli #["inspect", outDir.toString]
  expect (ecHash == 6)
    s!"descriptor contentSha256 tamper must exit 6, got {ecHash}\n{stderrHash}"
  expect (containsSubstr stderrHash "PF-OUTPUT-MANIFEST:")
    s!"hash tamper prefix: {stderrHash}"
  expect (stdoutHash == "")
    "hash tamper must not print success"
  IO.FS.writeFile (outDir / "manifest.json") originalManifest
  let roleTampered :=
    String.intercalate "\"role\": \"finalized-extra\""
      (originalManifest.splitOn "\"role\": \"materialized-base\"")
  expect (roleTampered != originalManifest)
    "role tamper must change text"
  IO.FS.writeFile (outDir / "manifest.json") roleTampered
  let (ecRole, stdoutRole, stderrRole) ← runCli #["inspect", outDir.toString]
  expect (ecRole == 6)
    s!"descriptor role tamper must exit 6, got {ecRole}\n{stderrRole}"
  expect (containsSubstr stderrRole "PF-OUTPUT-MANIFEST:")
    s!"role tamper prefix: {stderrRole}"
  expect (stdoutRole == "")
    "role tamper must not print success"
  IO.FS.writeFile (outDir / "manifest.json") originalManifest
  let sizeMarker := "\"size\": "
  let sParts := originalManifest.splitOn sizeMarker
  expect (sParts.length ≥ 2)
    s!"manifest must contain size field:\n{originalManifest}"
  let sBefore := sParts[0]!
  let sRest := String.intercalate sizeMarker (sParts.drop 1)
  let sizeTampered := sBefore ++ sizeMarker ++ "9" ++ sRest
  IO.FS.writeFile (outDir / "manifest.json") sizeTampered
  let (ecSize, stdoutSize, stderrSize) ← runCli #["inspect", outDir.toString]
  expect (ecSize == 6)
    s!"descriptor size tamper must exit 6, got {ecSize}\n{stderrSize}"
  expect (containsSubstr stderrSize "PF-OUTPUT-MANIFEST:")
    s!"size tamper prefix: {stderrSize}"
  expect (stdoutSize == "")
    "size tamper must not print success"
  IO.FS.writeFile (outDir / "manifest.json") originalManifest
  let pathTampered :=
    String.intercalate "\"path\": \"StateCell.rogue\""
      (originalManifest.splitOn "\"path\": \"StateCell.idl.json\"")
  expect (pathTampered != originalManifest)
    "path tamper must change text"
  IO.FS.writeFile (outDir / "manifest.json") pathTampered
  let (ecPath, stdoutPath, stderrPath) ← runCli #["inspect", outDir.toString]
  expect (ecPath == 6)
    s!"descriptor path tamper must exit 6, got {ecPath}\n{stderrPath}"
  expect (containsSubstr stderrPath "PF-OUTPUT-MANIFEST:")
    s!"path tamper prefix: {stderrPath}"
  expect (stdoutPath == "")
    "path tamper must not print success"
  let legacyManifest :=
    "{\n" ++
    "  \"schemaVersion\": \"proof-forge.output.v1\",\n" ++
    "  \"target\": \"solana\",\n" ++
    "  \"codegenProfile\": \"solana-sbpf-cpi-elf-v1\",\n" ++
    "  \"artifactProgramName\": \"StateCell\",\n" ++
    "  \"sourceHash\": \"0000000000000000000000000000000000000000000000000000000000000000\",\n" ++
    "  \"semanticHash\": \"0000000000000000000000000000000000000000000000000000000000000000\",\n" ++
    "  \"buildIdentityDigest\": \"0000000000000000000000000000000000000000000000000000000000000000\",\n" ++
    "  \"planDigest\": \"0000000000000000000000000000000000000000000000000000000000000000\",\n" ++
    "  \"supportClaimDigest\": \"0000000000000000000000000000000000000000000000000000000000000000\",\n" ++
    "  \"engineeringRegistryRootDigest\": \"0000000000000000000000000000000000000000000000000000000000000000\",\n" ++
    "  \"outputSetDigest\": \"0000000000000000000000000000000000000000000000000000000000000000\",\n" ++
    "  \"evidenceSha256\": \"0000000000000000000000000000000000000000000000000000000000000000\",\n" ++
    "  \"deployable\": false,\n" ++
    "  \"files\": [\"StateCell.cpi-plan.json\",\"StateCell.idl.json\"]\n" ++
    "}\n"
  IO.FS.writeFile (outDir / "manifest.json") legacyManifest
  let (ecLegacy, stdoutLegacy, stderrLegacy) ← runCli #["inspect", outDir.toString]
  expect (ecLegacy == 6)
    s!"legacy path-only manifest must exit 6, got {ecLegacy}\n{stderrLegacy}"
  expect (containsSubstr stderrLegacy "PF-OUTPUT-MANIFEST:")
    s!"legacy prefix: {stderrLegacy}"
  expect (containsSubstr stderrLegacy "path-only" ||
      containsSubstr stderrLegacy "must be objects")
    s!"legacy message: {stderrLegacy}"
  expect (stdoutLegacy == "")
    "legacy must not print success"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir

private def testInspectOutputDir : IO Unit := do
  testInspectOutputDirPositive
  testInspectOutputDirNegativesA
  testInspectOutputDirNegativesB

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
  testSolanaCallsFailClosed
  testBuildStateCellSuccess
  testCheckOkAndFail
  testInspectDigests
  testJsonSurface
  testProfileSelection
  testInspectOutputDir
  IO.println "Tests.CLI.DiagnosticsV1: ok"

end Tests.CLI.DiagnosticsV1
