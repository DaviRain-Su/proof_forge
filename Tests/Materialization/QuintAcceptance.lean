/-
  Host-optional Quint 0.32 acceptance for generated `.qnt` source.

  This suite is deliberately outside product finalization: the shipped profile
  remains zero-tool and non-deployable. When the exact host CLI is available,
  it typechecks StateCell, arithmetic, declared-revert, and Bool/pureFn/invariant models, then
  performs a tiny TypeScript-evaluator smoke. The emitted nondeterministic
  domain remains full-width UInt64, but this sampled smoke does not exhaust
  that domain and is not a Reference differential. Absence or a different
  version skips cleanly; no Tool Lock/formal evidence is claimed.
-/
import ProofForgeV2
import ProofForgeV2.Targets.Quint
import Tests.Language.ParserSession

namespace Tests.Materialization.QuintAcceptance

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets
open ProofForgeV2.Targets.BuildSelectionV1
open System

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def exactQuint032Available : IO Bool := do
  try
    let output ← IO.Process.output {
      cmd := "quint"
      args := #["--version"]
      stdin := .null
      stdout := .piped
      stderr := .piped
      inheritEnv := true
    }
    pure (output.exitCode == 0 && output.stdout.trimAscii.copy == "0.32.0")
  catch _ =>
    pure false

private unsafe def materializeQuint
    (session : Language.Loader.ParserSession)
    (label sourceText moduleName expectedPath : String) : IO OutputFile := do
  let source ← liftResult s!"parse {label}" (← session.selectProgramV1
    sourceText s!"<quint-accept-{label}>" moduleName none)
  let compiled ← liftResult s!"compile {label}" <|
    Compiler.compileValidatedSourceV1 source
  let selection ← liftResult s!"select {label}" <|
    resolveBuildSelectionV1 TargetId.quint none
  let capability ← liftResult s!"resolve {label}" <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let artifacts ← liftResult s!"materialize {label}" <|
    Targets.materializeResult capability
  let files := MaterializedArtifactsV1.filesOf artifacts
  let some file := files.find? (·.path == expectedPath) |
    throw <| IO.userError s!"{label}: missing {expectedPath}; got {files.map (·.path)}"
  expect (file.mediaType == "text/x-quint") s!"{label}: wrong media type"
  pure file

private def runQuint
    (args : Array String) (label : String) : IO Unit := do
  let output ← IO.Process.output {
    cmd := "quint"
    args
    stdin := .null
    stdout := .piped
    stderr := .piped
    inheritEnv := true
  }
  unless output.exitCode == 0 do
    throw <| IO.userError
      (label ++ ": Quint 0.32 failed (exit " ++ toString output.exitCode ++
        ")\nstdout:\n" ++ output.stdout ++ "\nstderr:\n" ++ output.stderr)

private def stateCellSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program StateCell where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  entry increment(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n"

private def logicSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program Logic where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  fn isPositive(x : UInt64) : Bool do\n" ++
  "    return x > 0\n" ++
  "  entry check(delta : UInt64) : Bool do\n" ++
  "    return isPositive(delta) && count >= 0\n" ++
  "  invariant nonNeg : count >= 0\n"

private def revertSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program Stopper where\n" ++
  "  error Stop()\n" ++
  "  entry stop() : UInt64 do\n" ++
  "    revert Stop\n"

private def arithmeticSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program Arithmetic where\n" ++
  "  entry sum(x : UInt64, y : UInt64) : UInt64 do\n" ++
  "    return x + y\n" ++
  "  entry difference(x : UInt64, y : UInt64) : UInt64 do\n" ++
  "    return x - y\n" ++
  "  entry product(x : UInt64, y : UInt64) : UInt64 do\n" ++
  "    return x * y\n" ++
  "  entry quotient(x : UInt64, y : UInt64, z : UInt64) : UInt64 do\n" ++
  "    return (x - y) / z\n" ++
  "  entry remainder(x : UInt64, y : UInt64) : UInt64 do\n" ++
  "    return x % y\n" ++
  "  entry ensure(x : UInt64) : UInt64 do\n" ++
  "    assert x > 0\n" ++
  "    return x\n"

unsafe def run : IO Unit := do
  IO.println "Tests.Materialization.QuintAcceptance: start"
  unless ← exactQuint032Available do
    IO.println "skipped: exact host Quint 0.32.0 unavailable"
    IO.println "Tests.Materialization.QuintAcceptance: ok (skipped)"
    return
  let session ← Tests.Language.ParserSession.shared
  let stateCell ← materializeQuint session "StateCell" stateCellSource
    "Tests.QuintAccept.StateCell" "StateCell.qnt"
  let logic ← materializeQuint session "Logic" logicSource
    "Tests.QuintAccept.Logic" "Logic.qnt"
  let arithmetic ← materializeQuint session "Arithmetic" arithmeticSource
    "Tests.QuintAccept.Arithmetic" "Arithmetic.qnt"
  let stopper ← materializeQuint session "Stopper" revertSource
    "Tests.QuintAccept.Stopper" "Stopper.qnt"
  let staging := FilePath.mk "build/v2/quint-acceptance"
  if ← staging.pathExists then IO.FS.removeDirAll staging
  IO.FS.createDirAll staging
  try
    let stateCellPath := staging / stateCell.path
    let logicPath := staging / logic.path
    let arithmeticPath := staging / arithmetic.path
    let stopperPath := staging / stopper.path
    IO.FS.writeFile stateCellPath stateCell.contents
    IO.FS.writeFile logicPath logic.contents
    IO.FS.writeFile arithmeticPath arithmetic.contents
    IO.FS.writeFile stopperPath stopper.contents
    runQuint #["typecheck", stateCellPath.toString] "StateCell typecheck"
    runQuint #["typecheck", logicPath.toString] "Logic typecheck"
    runQuint #["typecheck", arithmeticPath.toString] "Arithmetic typecheck"
    runQuint #["typecheck", stopperPath.toString] "Stopper typecheck"
    runQuint #["run", logicPath.toString, "--backend", "typescript",
      "--max-samples", "1", "--max-steps", "2", "--seed", "2",
      "--invariants", "pf_invariant_nonNeg", "--verbosity", "1"]
      "Logic invariant smoke"
    IO.println "Tests.Materialization.QuintAcceptance: ok"
  finally
    if ← staging.pathExists then IO.FS.removeDirAll staging

end Tests.Materialization.QuintAcceptance
