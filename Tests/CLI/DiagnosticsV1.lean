/-
  Tests.CLI.DiagnosticsV1 — B8b product CLI diagnostic cutover.

  Spawns the real `proof-forge-next` binary for:
    * multi-error fixture: exit 3, ≥2 human diagnostic lines, no success stdout,
      no output directory, primary lines contain PF-EFFECT-001 and PF-SRC-INVALID
    * usage/config: exit 2 (missing --module, unknown command, unknown --target);
      no diagnostic code invention (no PF-CLI-USAGE / PF-TARGET-UNKNOWN as exception)
    * parser/source boundary: exit 3
    * Counter `build-counter` success: exit 0 + success stdout, no failure artifacts
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

private def runCli (args : Array String) (cwd : Option FilePath := none) :
    IO (UInt32 × String × String) := do
  let out ← IO.Process.output {
    cmd := cliBin.toString
    args := args
    cwd := cwd
  }
  pure (out.exitCode, out.stdout, out.stderr)

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

unsafe def run : IO Unit := do
  unless ← cliBin.pathExists do
    throw <| IO.userError
      s!"CLI binary missing at {cliBin}; build proof_forge_next first"
  testUsageExit2
  testUnknownCommandExit2
  testUnknownTargetExit2
  testMultiErrorProductCli
  testParserBoundaryExit3
  testBuildCounterSuccess
  IO.println "Tests.CLI.DiagnosticsV1: ok"

end Tests.CLI.DiagnosticsV1
