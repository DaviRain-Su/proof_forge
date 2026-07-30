/-
  Tests.CLI.DiagnosticsV1 — B8b product CLI diagnostic cutover.

  Spawns the real `proof-forge-next` binary for:
    * multi-error fixture: exit 3, ≥2 human diagnostic lines, no success stdout,
      no output directory, primary lines contain PF-EFFECT-001 and PF-SRC-INVALID
    * usage/config: exit 2 (missing --module, unknown command, unknown --target);
      no diagnostic code invention (no PF-CLI-USAGE / PF-TARGET-UNKNOWN as exception)
    * parser/source boundary: exit 3
    * supervised source authority: in-root leaf symlink is rejected with exit 3
    * build-counter package source is independent of caller cwd
    * compiler symlink launch cannot redirect pinned sibling workers
    * Counter `build-counter` success: exit 0 + success stdout, no failure artifacts
    * non-Darwin: both product build commands fail closed with the stable frontend
      protocol diagnostic and zero output (no in-process Loader fallback)
-/
import ProofForgeV2.Core.Common

namespace Tests.CLI.DiagnosticsV1

open System

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

private def testSupervisedSourceRejectsLeafSymlink : IO Unit := do
  let root := FilePath.mk "build/v2/cli-supervised-source"
  if ← root.pathExists then IO.FS.removeDirAll root
  IO.FS.createDirAll root
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Counter where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  IO.FS.writeFile (root / "real.lean") source
  let linkResult ← IO.Process.output {
    cmd := "/bin/ln"
    args := #["-s", "real.lean", (root / "link.lean").toString]
  }
  expect (linkResult.exitCode == 0)
    s!"could not create source symlink: {linkResult.stderr}"
  let outDir := root / "out"
  let (ec, stdout, stderr) ← runCli #[
    "build", "link.lean",
    "--root", root.toString,
    "--module", "Root",
    "--target", "solana",
    "-o", "out"
  ]
  expect (ec == 3)
    s!"supervised leaf symlink must exit 3, got {ec}\nstderr={stderr}\nstdout={stdout}"
  expect (containsSubstr stderr "PF-SRC-INVALID: source open failed")
    s!"leaf symlink must map to stable source-open diagnostic, stderr={stderr}"
  expect (!containsSubstr stdout "built target=")
    "leaf symlink failure must not print success"
  expect (!(← outDir.pathExists))
    "leaf symlink failure must not create output"

private def testBuildCounterUsesPackageSource : IO Unit := do
  let foreignRoot := FilePath.mk "build/v2/cli-build-counter-foreign-cwd"
  if ← foreignRoot.pathExists then IO.FS.removeDirAll foreignRoot
  IO.FS.createDirAll (foreignRoot / "Examples")
  IO.FS.writeFile (foreignRoot / "Examples" / "Counter.lean")
    "this caller-controlled Counter source must never be read\n"
  let foreignRoot ← IO.FS.realPath foreignRoot
  let outDir := foreignRoot / "out"
  let (ec, stdout, stderr) ← runCli #[
    "build-counter", "--target", "solana", "-o", outDir.toString
  ] (some foreignRoot)
  expect (ec == 0)
    s!"build-counter must use package source, got {ec}\nstderr={stderr}\nstdout={stdout}"
  expect (containsSubstr stdout "built Counter target=solana")
    s!"package-source build-counter stdout missing: {stdout}"
  expect (← outDir.pathExists)
    "package-source build-counter must create output"

private def testSymlinkLaunchCannotRedirectWorkers : IO Unit := do
  let fixture := FilePath.mk "build/v2/cli-symlink-launch"
  if ← fixture.pathExists then IO.FS.removeDirAll fixture
  IO.FS.createDirAll fixture
  let fixture ← IO.FS.realPath fixture
  let realCli ← IO.FS.realPath cliBin
  let linkedCli := fixture / "proof-forge-next"
  runTool "/bin/ln" #["-s", realCli.toString, linkedCli.toString]
  let safeMarker := fixture / "forged-safe-open-ran.flag"
  let frontendMarker := fixture / "forged-frontend-ran.flag"
  writeExecutable (fixture / "proof-forge-frontend-safe-open-worker-v1") <|
    "#!/bin/sh\n" ++ s!": > '{safeMarker}'\n" ++ "exit 7\n"
  writeExecutable (fixture / "proof-forge-frontend-worker-v1") <|
    "#!/bin/sh\n" ++ s!": > '{frontendMarker}'\n" ++ "exit 7\n"
  let outDir := fixture / "out"
  let (ec, stdout, stderr) ← runCliAt linkedCli #[
    "build-counter", "--target", "solana", "-o", outDir.toString
  ]
  expect (!(← safeMarker.pathExists) && !(← frontendMarker.pathExists))
    "symlink launch must never execute forged sibling workers"
  if ec == 0 then
    expect (containsSubstr stdout "built Counter target=solana")
      s!"physical app-path launch lost success output: {stdout}"
    expect (← outDir.pathExists)
      "physical app-path launch must create output"
  else
    expect (ec == 2 && containsSubstr stderr "symbolic link")
      s!"symlink launch must resolve physically or fail closed, got {ec}: {stderr}"
    expect (!(← outDir.pathExists))
      "rejected symlink launch must not create output"

private def testBuildCounterSuccess : IO Unit := do
  let outDir := FilePath.mk "build/v2/diagnostic-build-counter-ok"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let (ec, stdout, stderr) ← runCli #[
    "build-counter",
    "--target", "solana",
    "-o", "build/v2/diagnostic-build-counter-ok"
  ]
  expect (ec == 0)
    s!"build-counter success must exit 0, got {ec}\nstderr={stderr}\nstdout={stdout}"
  expect (containsSubstr stdout "built Counter target=solana")
    s!"build-counter success stdout missing, stdout={stdout}"
  expect (!containsSubstr stderr "PF-")
    s!"build-counter success must not print product diagnostic codes on stderr, got:\n{stderr}"
  expect (!containsSubstr stderr "uncaught exception")
    "build-counter success must not uncaught-exception"
  expect (← outDir.pathExists)
    "build-counter success must create output directory"

private def testUnsupportedPlatformFailsClosed : IO Unit := do
  let sourceOut := FilePath.mk "build/v2/diagnostic-non-darwin-source"
  let counterOut := FilePath.mk "build/v2/diagnostic-non-darwin-counter"
  if ← sourceOut.pathExists then IO.FS.removeDirAll sourceOut
  if ← counterOut.pathExists then IO.FS.removeDirAll counterOut
  let (sourceEc, sourceStdout, sourceStderr) ← runCli #[
    "build", "Examples/Counter.lean",
    "--module", "Examples.Counter",
    "--target", "solana",
    "-o", sourceOut.toString
  ]
  expect (sourceEc == 3)
    s!"non-Darwin build must fail closed with exit 3, got {sourceEc}: {sourceStderr}"
  expect (containsSubstr sourceStderr
      "PF-FRONTEND-PROTOCOL: frontend supervisor unavailable")
    s!"non-Darwin build must report the closed supervisor diagnostic: {sourceStderr}"
  expect (sourceStdout == "" && !(← sourceOut.pathExists))
    "non-Darwin build must not print success or publish output"

  let (counterEc, counterStdout, counterStderr) ← runCli #[
    "build-counter", "--target", "solana", "-o", counterOut.toString
  ]
  expect (counterEc == 3)
    s!"non-Darwin build-counter must fail closed with exit 3, got {counterEc}: {counterStderr}"
  expect (containsSubstr counterStderr
      "PF-FRONTEND-PROTOCOL: frontend supervisor unavailable")
    s!"non-Darwin build-counter must report the closed supervisor diagnostic: {counterStderr}"
  expect (counterStdout == "" && !(← counterOut.pathExists))
    "non-Darwin build-counter must not print success or publish output"

unsafe def run : IO Unit := do
  unless ← cliBin.pathExists do
    throw <| IO.userError
      s!"CLI binary missing at {cliBin}; build proof_forge_next first"
  testUsageExit2
  testUnknownCommandExit2
  testUnknownTargetExit2
  if !System.Platform.isOSX then
    testUnsupportedPlatformFailsClosed
    IO.println "Tests.CLI.DiagnosticsV1: ok (unsupported host fails closed)"
  else
    testMultiErrorProductCli
    testParserBoundaryExit3
    testSupervisedSourceRejectsLeafSymlink
    testBuildCounterUsesPackageSource
    testSymlinkLaunchCannotRedirectWorkers
    testBuildCounterSuccess
    IO.println "Tests.CLI.DiagnosticsV1: ok"

end Tests.CLI.DiagnosticsV1
