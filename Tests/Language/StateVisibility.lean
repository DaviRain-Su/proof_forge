import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.TypedV1
import ProofForgeV2.Typed.RequirementsInferV1
import Tests.Language.ParserSession

namespace Tests.Language.StateVisibility

open ProofForgeV2
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.RequirementsInferV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Public/default: S1-compatible bare place return of state. -/
private def publicSource (progName statePrefix : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.StateVisibilityFixture\n\n" ++
  "program " ++ progName ++ " where\n" ++
  "  state " ++ statePrefix ++ "value : UInt64\n\n" ++
  "  entry ping() : UInt64 do\n" ++
  "    return value\n\n" ++
  "end Tests.Language.StateVisibilityFixture\n"

/-- Private/commitment: unused non-public state + public param return so
    CheckV1/disclosure stays clean while product compile fails at Normalize. -/
private def nonPublicSource (progName statePrefix : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.StateVisibilityFixture\n\n" ++
  "program " ++ progName ++ " where\n" ++
  "  state " ++ statePrefix ++ "value : UInt64\n\n" ++
  "  entry ping(seed : UInt64) : UInt64 do\n" ++
  "    return seed\n\n" ++
  "end Tests.Language.StateVisibilityFixture\n"

private def moduleName : String := "Tests.Language.StateVisibilityFixture"

private unsafe def load (session : Language.Loader.ParserSession)
    (progName : String) (input : String) : IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 input
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

  let defaultVis ← load session "DefaultStateVisibility"
    (publicSource "DefaultStateVisibility" "")
  let pubVis ← load session "PublicStateVisibility"
    (publicSource "PublicStateVisibility" "public ")
  let privVis ← load session "PrivateStateVisibility"
    (nonPublicSource "PrivateStateVisibility" "private ")
  let commVis ← load session "CommitmentStateVisibility"
    (nonPublicSource "CommitmentStateVisibility" "commitment ")

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

  -- Public / default remain S1-compileable (Normalize gate + residual alpha).
  let semanticDefault ← match Compiler.compileValidatedSourceV1 defaultVis with
    | .ok value => pure (Compiler.CompiledProgramV1.alphaResidualOf value)
    | .error error => throw <| IO.userError error.render
  let semanticPublic ← match Compiler.compileValidatedSourceV1 pubVis with
    | .ok value => pure (Compiler.CompiledProgramV1.alphaResidualOf value)
    | .error error => throw <| IO.userError error.render

  expect (semanticDefault.state.map (·.visibility) == #[Semantic.Visibility.verifierVisible] &&
      semanticPublic.state.map (·.visibility) == #[Semantic.Visibility.verifierVisible])
    "public Semantic state declarations must retain verifierVisible"
  expect (semanticPublic.requirements == #[.persistentState])
    "public state must require persistence without a private disclosure claim"
  expect (semanticDefault.requirements == #[.persistentState])
    "default-public state must require persistence only"

  -- Private / commitment: AST + CheckV1 + RequirementsInfer retained; full
  -- product compile fails closed at Normalize S1 (no alpha-only path).
  match Typed.checkV1 privVis with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"private CheckV1: {e.render}"
  match Typed.checkV1 commVis with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"commitment CheckV1: {e.render}"

  let privInfer := inferRequirementsV1 privVis
  let commInfer := inferRequirementsV1 commVis
  expect (privInfer.requirements == #[.persistentState, .privateState])
    "private state must have a state-specific disclosure requirement (infer)"
  expect (commInfer.requirements == #[.persistentState, .commitmentState])
    "commitment state must have a state-specific disclosure requirement (infer)"

  match Compiler.compileValidatedSourceV1 privVis with
  | .error (.invalidProgram msg) =>
      expect (msg == "S1 normalizer supports only public state, got non-public 'value'")
        s!"private compile must fail at Normalize gate, got {msg}"
  | .error e => throw <| IO.userError s!"private compile wrong error: {e.render}"
  | .ok _ => throw <| IO.userError "private state must not full-compile past Normalize S1"

  match Compiler.compileValidatedSourceV1 commVis with
  | .error (.invalidProgram msg) =>
      expect (msg == "S1 normalizer supports only public state, got non-public 'value'")
        s!"commitment compile must fail at Normalize gate, got {msg}"
  | .error e => throw <| IO.userError s!"commitment compile wrong error: {e.render}"
  | .ok _ => throw <| IO.userError "commitment state must not full-compile past Normalize S1"

  let parserEnv ← parserEnvironment
  expectParserReject "escaped visibility keyword" <|
    Lean.Parser.runParserCategory parserEnv `ProofForgeV2.Language.pfItem
      "state «public» value : UInt64"
  expectParserReject "unknown visibility keyword" <|
    Lean.Parser.runParserCategory parserEnv `ProofForgeV2.Language.pfItem
      "state secret value : UInt64"

end Tests.Language.StateVisibility
