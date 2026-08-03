import Tests.Language.ParserSession
import ProofForgeV2.Language.ProgramElaborationV1
import ProofForgeV2.Language.ProgramExport
import Lean

namespace Tests.Language.ProgramCommandAcceptance.Fixture
open ProofForgeV2.Language

program Counter where
  view get() : UInt64 do
    return 0

end Tests.Language.ProgramCommandAcceptance.Fixture

namespace Tests.Language.ProgramCommandAcceptance
open ProofForgeV2 System
open ProofForgeV2.Core.Common
open ProofForgeV2.Language.ProgramExport
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
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
  "PF-SRC-INVALID: Lean command is outside the portable program DSL"

/-- TST-SRC-003 packaging: program command identity + illegal top-level only. -/
unsafe def run : IO Unit := do
  let env ← Lean.importModules
    (imports := #[{ module := `Tests.Language.ProgramCommandAcceptance }])
    (opts := {})
    (trustLevel := 0)
  match programPayloadV2 env `Tests.Language.ProgramCommandAcceptance.Fixture.Counter with
  | .error e => throw <| IO.userError s!"positive payload reconstruction failed: {e}"
  | .ok source =>
      let identity := (NonEmptyArray.toArray source.programIdentity.components).map (·.raw)
      expect (identity == #["Tests", "Language", "ProgramCommandAcceptance", "Fixture", "Counter"])
        "command must produce v2 payload with moduleName ++ declaration identity"
      expect (source.program.items.size == 1)
        "Counter ProgramV1 must contain one view entry"

  let session ← Tests.Language.ParserSession.shared
  match ← session.parseProgramsV1 counterSource "<pa88-counter>"
      "Tests.Language.ProgramCommandAcceptance" with
  | .error e => throw <| IO.userError s!"positive parse failed: {e.render}"
  | .ok programs => do
      expect (programs.size == 1) s!"expected one program, got {programs.size}"
      let some p := programs[0]? | throw <| IO.userError "missing program"
      expect (p.program.name.raw == "Counter") "short name"
      expect ((NonEmptyArray.toArray p.programIdentity.components).map (·.raw) ==
        #["Tests", "Language", "ProgramCommandAcceptance", "Fixture", "Counter"]) "FQN"
  let (kindRes, _) ← withCapturedStdout
      (session.parseProgramsV1 kindSource "<pa88-kind>" "InvalidModule")
  match kindRes with
  | .ok _ => throw <| IO.userError "kind suffix must fail"
  | .error e => expect (e.render == exactKindErr) s!"kind: {e.render}"
  let (cmdRes, cmdOut) ← withCapturedStdout
      (session.parseProgramsV1 runCmdSource "<pa88-runcmd>" "RunCmd")
  match cmdRes with
  | .ok _ => throw <| IO.userError "run_cmd must fail"
  | .error e => expect (e.render == exactRunCmdErr) s!"run_cmd: {e.render}"
  expect (!cmdOut.contains marker) "marker must not execute"

end Tests.Language.ProgramCommandAcceptance
