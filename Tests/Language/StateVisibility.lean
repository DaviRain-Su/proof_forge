import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession
import ProofForgeV2.Targets.Registry

namespace Tests.Language.StateVisibility

open ProofForgeV2
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.ValidatedSourceV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def source (progName statePrefix : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.StateVisibilityFixture\n\n" ++
  "program " ++ progName ++ " where\n" ++
  "  state " ++ statePrefix ++ "value : UInt64\n\n" ++
  "  entry ping() : UInt64 do\n" ++
  "    return 0\n\n" ++
  "end Tests.Language.StateVisibilityFixture\n"

private def moduleName : String := "Tests.Language.StateVisibilityFixture"

private unsafe def load (session : Language.Loader.ParserSession)
    (progName statePrefix : String) : IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 (source progName statePrefix)
      ("<state-visibility-" ++ progName ++ ">") moduleName none with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def stateVisibility (prog : ValidatedSourceV1) : Option VisibilityV1 :=
  prog.program.items.findSome? fun item =>
    match item with
    | .state decl => some decl.visibility
    | _ => none

private def expectParserReject (label : String)
    (result : Except String Lean.Syntax) : IO Unit := do
  match result with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError s!"{label}: parser unexpectedly accepted invalid visibility"

private unsafe def parserEnvironment : IO Lean.Environment := do
  Lean.enableInitializersExecution
  Lean.initSearchPath (← Lean.findSysroot "lean")
  Lean.importModules #[{ module := `ProofForgeV2.Language.Syntax }] {} 0
    (loadExts := true)

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared

  let defaultVis ← load session "DefaultStateVisibility" ""
  let pubVis ← load session "PublicStateVisibility" "public "
  let privVis ← load session "PrivateStateVisibility" "private "
  let commVis ← load session "CommitmentStateVisibility" "commitment "

  expect (stateVisibility defaultVis == some .public_)
    "default state visibility must decode as public_"
  expect (stateVisibility pubVis == some .public_)
    "explicit public state visibility must decode as public_"
  expect (stateVisibility privVis == some .private_)
    "private state visibility must decode as private_"
  expect (stateVisibility commVis == some .commitment)
    "commitment state visibility must decode as commitment"

  expect (defaultVis.program != privVis.program && pubVis.program != privVis.program &&
      privVis.program != commVis.program)
    "distinct visibility declarations must produce distinct ProgramV1 ASTs"

  let semanticDefault ← match Compiler.compileValidatedSourceV1 defaultVis with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let semanticPublic ← match Compiler.compileValidatedSourceV1 pubVis with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let semanticPrivate ← match Compiler.compileValidatedSourceV1 privVis with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let semanticCommitment ← match Compiler.compileValidatedSourceV1 commVis with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render

  expect (semanticDefault.state.map (·.visibility) == #[Semantic.Visibility.verifierVisible] &&
      semanticPublic.state.map (·.visibility) == #[Semantic.Visibility.verifierVisible] &&
      semanticPrivate.state.map (·.visibility) == #[Semantic.Visibility.proverWitness] &&
      semanticCommitment.state.map (·.visibility) == #[Semantic.Visibility.commitmentOnly])
    "Semantic state declarations must retain target-neutral visibility"

  expect (semanticPublic.requirements == #[.persistentState])
    "public state must require persistence without a private disclosure claim"
  expect (semanticPrivate.requirements == #[.persistentState, .privateState])
    "private state must have a state-specific disclosure requirement"
  expect (semanticCommitment.requirements == #[.persistentState, .commitmentState])
    "commitment state must have a state-specific disclosure requirement"

  for target in Targets.phase1 do
    match Targets.checkSupport target semanticPrivate with
    | .error (.unsupportedRequirement .privateState rejectedTarget) =>
        expect (rejectedTarget == target)
          s!"{target}: private-state rejection must retain the selected target"
    | _ => throw <| IO.userError s!"{target} must reject private state before target-owned planning"
    match Targets.checkSupport target semanticCommitment with
    | .error (.unsupportedRequirement .commitmentState rejectedTarget) =>
        expect (rejectedTarget == target)
          s!"{target}: commitment-state rejection must retain the selected target"
    | _ => throw <| IO.userError (s!"{target} must reject commitment state before target-owned planning")

  let parserEnv ← parserEnvironment
  expectParserReject "escaped visibility keyword" <|
    Lean.Parser.runParserCategory parserEnv `ProofForgeV2.Language.pfItem
      "state «public» value : UInt64"
  expectParserReject "unknown visibility keyword" <|
    Lean.Parser.runParserCategory parserEnv `ProofForgeV2.Language.pfItem
      "state secret value : UInt64"

end Tests.Language.StateVisibility
