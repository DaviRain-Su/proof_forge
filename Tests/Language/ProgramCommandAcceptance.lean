import Tests.Language.ParserSession
import ProofForgeV2.Language.Syntax

namespace Tests.Language.ProgramCommandAcceptance.Fixture
open ProofForgeV2.Language

program Counter where
  view get() : UInt64 do
    return 0

end Tests.Language.ProgramCommandAcceptance.Fixture

namespace Tests.Language.ProgramCommandAcceptance
open ProofForgeV2 System
open Tests.Language.ProgramCommandAcceptance.Fixture

private def expect (c : Bool) (m : String) : IO Unit :=
  unless c do throw <| IO.userError m

private def withCapturedStdout (act : IO α) : IO (α × String) := do
  let (stdout, result) ← IO.FS.withIsolatedStreams act (isolateStderr := false)
  pure (result, stdout)

private def counterSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "namespace Tests.Language.ProgramCommandAcceptance.Fixture\n" ++
  "program Counter where\n" ++
  "  view get() : UInt64 do\n" ++
  "    return 0\n" ++
  "end Tests.Language.ProgramCommandAcceptance.Fixture\n"

private def kindSource : String :=
  "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
  "program Invalid : contract where\n  view get() : UInt64 do\n    return 0\n"

private def runCmdSource : String :=
  "import ProofForgeV2\nrun_cmd IO.println \"PF-PA88-MUST-NOT-EXECUTE\"\n"

private def marker : String := "PF-PA88-MUST-NOT-EXECUTE"

private def exactKindErr : String :=
  "PF-SRC-INVALID: Lean parser rejected source: failed to parse file"

private def exactRunCmdErr : String :=
  "PF-SRC-INVALID: Lean command 'Lean.runCmd' is outside the portable program DSL"

/-- TST-SRC-003 packaging: program command identity + illegal top-level only. -/
unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  match ← session.parsePrograms counterSource "<pa88-counter>" with
  | .error e => throw <| IO.userError s!"positive parse failed: {e.render}"
  | .ok programs => do
      expect (programs.size == 1) s!"expected one program, got {programs.size}"
      let some p := programs[0]? | throw <| IO.userError "missing program"
      expect (p.name == "Counter") "short name"
      expect (p.qualifiedName ==
        "Tests.Language.ProgramCommandAcceptance.Fixture.Counter") "FQN"
      expect (p == Counter) "full Source.Program BEq"
      expect (p.sourceHash == Counter.sourceHash) "sourceHash"
  let (kindRes, _) ← withCapturedStdout (session.parsePrograms kindSource "<pa88-kind>")
  match kindRes with
  | .ok _ => throw <| IO.userError "kind suffix must fail"
  | .error e => expect (e.render == exactKindErr) s!"kind: {e.render}"
  let (cmdRes, cmdOut) ← withCapturedStdout (session.parsePrograms runCmdSource "<pa88-runcmd>")
  match cmdRes with
  | .ok _ => throw <| IO.userError "run_cmd must fail"
  | .error e => expect (e.render == exactRunCmdErr) s!"run_cmd: {e.render}"
  expect (!cmdOut.contains marker) "marker must not execute"

end Tests.Language.ProgramCommandAcceptance
