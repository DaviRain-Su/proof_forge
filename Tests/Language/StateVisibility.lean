import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.TypedV1
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.WireV1
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
    CheckV1/disclosure stays clean while product compile retains visibility. -/
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

  -- Public / default remain S1-compileable through the single semantic carrier.
  let compiledDefault ← match Compiler.compileValidatedSourceV1 defaultVis with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let compiledPublic ← match Compiler.compileValidatedSourceV1 pubVis with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let semanticDefault ← match ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
      (Compiler.CompiledSemanticV1.semanticV1Of compiledDefault) with
    | .ok data => pure data
    | .error error => throw <| IO.userError s!"default semantic: {repr error}"
  let semanticPublic ← match ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
      (Compiler.CompiledSemanticV1.semanticV1Of compiledPublic) with
    | .ok data => pure data
    | .error error => throw <| IO.userError s!"public semantic: {repr error}"

  expect (semanticDefault.logicalState.map (·.visibility) ==
        #[ProofForgeV2.Semantic.WireV1.VisibilityV1.public_] &&
      semanticPublic.logicalState.map (·.visibility) ==
        #[ProofForgeV2.Semantic.WireV1.VisibilityV1.public_])
    "public Semantic state declarations must retain public visibility"
  expect (semanticPublic.requirements.items.map (·.id) == #["state.persistent"] &&
      semanticDefault.requirements.items.map (·.id) == #["state.persistent"])
    "public/default state must freeze only state.persistent"

  -- Private / commitment: AST + CheckV1 + RequirementsInfer retained; N1 product
  -- compile succeeds and Semantic state rows keep visibility (disclosure keys
  -- are freeze-skipped; only state.persistent is frozen).
  match Typed.checkV1 privVis with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"private CheckV1: {e.render}"
  match Typed.checkV1 commVis with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"commitment CheckV1: {e.render}"

  let privIds := (inferRequirementContributionsFromSourceV1 privVis).map
    RequirementContributionV1.idOf
  let commIds := (inferRequirementContributionsFromSourceV1 commVis).map
    RequirementContributionV1.idOf
  expect (privIds == #["state.persistent", "disclosure.private-state"])
    "private state must contribute state-specific disclosure"
  expect (commIds == #["state.persistent", "disclosure.commitment-state"])
    "commitment state must contribute state-specific disclosure"

  let compiledPriv ← match Compiler.compileValidatedSourceV1 privVis with
    | .ok value => pure value
    | .error e => throw <| IO.userError s!"private compile must succeed (N1): {e.render}"
  let compiledComm ← match Compiler.compileValidatedSourceV1 commVis with
    | .ok value => pure value
    | .error e => throw <| IO.userError s!"commitment compile must succeed (N1): {e.render}"
  let semanticPriv ← match ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
      (Compiler.CompiledSemanticV1.semanticV1Of compiledPriv) with
    | .ok data => pure data
    | .error error => throw <| IO.userError s!"private semantic: {repr error}"
  let semanticComm ← match ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
      (Compiler.CompiledSemanticV1.semanticV1Of compiledComm) with
    | .ok data => pure data
    | .error error => throw <| IO.userError s!"commitment semantic: {repr error}"
  expect (semanticPriv.logicalState.map (·.visibility) ==
        #[ProofForgeV2.Semantic.WireV1.VisibilityV1.private_])
    "private Semantic state declarations must retain private visibility"
  expect (semanticComm.logicalState.map (·.visibility) ==
        #[ProofForgeV2.Semantic.WireV1.VisibilityV1.commitment])
    "commitment Semantic state declarations must retain commitment visibility"
  expect (semanticPriv.requirements.items.map (·.id) == #["state.persistent"] &&
      semanticComm.requirements.items.map (·.id) == #["state.persistent"])
    "private/commitment state freezes only state.persistent (disclosure keys skipped)"

  let parserEnv ← parserEnvironment
  expectParserReject "escaped visibility keyword" <|
    Lean.Parser.runParserCategory parserEnv `ProofForgeV2.Language.pfItem
      "state «public» value : UInt64"
  expectParserReject "unknown visibility keyword" <|
    Lean.Parser.runParserCategory parserEnv `ProofForgeV2.Language.pfItem
      "state secret value : UInt64"

end Tests.Language.StateVisibility
