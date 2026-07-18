import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import Tests.Language.ParserSession
import ProofForgeV2.Targets.Registry

namespace Tests.Language.StateVisibilityFixture

open ProofForgeV2.Language

program DefaultStateVisibility where
  state value : UInt64

  entry ping() : UInt64 do
    return 0

program PublicStateVisibility where
  state public value : UInt64

  entry ping() : UInt64 do
    return 0

program PrivateStateVisibility where
  state private value : UInt64

  entry ping() : UInt64 do
    return 0

program CommitmentStateVisibility where
  state commitment value : UInt64

  entry ping() : UInt64 do
    return 0

end Tests.Language.StateVisibilityFixture

namespace Tests.Language.StateVisibility

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def source (programName statePrefix : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.StateVisibilityFixture\n\n" ++
  "program " ++ programName ++ " where\n" ++
  "  state " ++ statePrefix ++ "value : UInt64\n\n" ++
  "  entry ping() : UInt64 do\n" ++
  "    return 0\n\n" ++
  "end Tests.Language.StateVisibilityFixture\n"

private def sameIdentitySource (statePrefix : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program CanonicalStateVisibility where\n" ++
  "  state " ++ statePrefix ++ "value : UInt64\n\n" ++
  "  entry ping() : UInt64 do\n" ++
  "    return 0\n"

private def expectParserReject (label : String) (result : Except String Lean.Syntax) : IO Unit := do
  match result with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError s!"{label}: parser unexpectedly accepted invalid visibility"

private unsafe def parserEnvironment : IO Lean.Environment := do
  Lean.enableInitializersExecution
  Lean.initSearchPath (← Lean.findSysroot "lean")
  Lean.importModules #[{ module := `ProofForgeV2.Language.Syntax }] {} 0
    (loadExts := true)

private unsafe def select (session : Language.Loader.ParserSession)
    (input path : String) : IO Source.Program := do
  match ← session.selectProgram input path none with
  | .ok sourceProgram => pure sourceProgram
  | .error error => throw <| IO.userError error.render

private def checkElaborated (label : String) (expected : Source.Visibility)
    (sourceProgram : Source.Program) : IO Unit := do
  match sourceProgram.state with
  | #[stateDecl] =>
      expect (stateDecl.visibility == expected)
        s!"{label} state visibility must survive Lean command elaboration"
  | _ => throw <| IO.userError s!"{label} must declare exactly one state cell"

private unsafe def checkParity (session : Language.Loader.ParserSession)
    (programName statePrefix : String)
    (elaborated : Source.Program) : IO Unit := do
  let decoded ← select session (source programName statePrefix) s!"<state-visibility-{programName}>"
  expect (decoded == elaborated)
    s!"{programName}: Loader and Lean command must produce the same Source.Program"
  expect (decoded.sourceHash == elaborated.sourceHash)
    s!"{programName}: Loader and Lean command must produce the same source hash"

unsafe def run : IO Unit := do
  let defaultState := Tests.Language.StateVisibilityFixture.DefaultStateVisibility
  let publicState := Tests.Language.StateVisibilityFixture.PublicStateVisibility
  let privateState := Tests.Language.StateVisibilityFixture.PrivateStateVisibility
  let commitmentState := Tests.Language.StateVisibilityFixture.CommitmentStateVisibility

  checkElaborated "default" .verifierVisible defaultState
  checkElaborated "explicit public" .verifierVisible publicState
  checkElaborated "private" .proverWitness privateState
  checkElaborated "commitment" .commitmentOnly commitmentState

  let session ← Tests.Language.ParserSession.shared
  checkParity session "DefaultStateVisibility" "" defaultState
  checkParity session "PublicStateVisibility" "public " publicState
  checkParity session "PrivateStateVisibility" "private " privateState
  checkParity session "CommitmentStateVisibility" "commitment " commitmentState

  let canonicalDefault ← select session (sameIdentitySource "") "<state-visibility-default>"
  let canonicalPublic ← select session (sameIdentitySource "public ") "<state-visibility-public>"
  let canonicalPrivate ← select session (sameIdentitySource "private ") "<state-visibility-private>"
  let canonicalCommitment ← select session (sameIdentitySource "commitment ")
    "<state-visibility-commitment>"
  expect (canonicalDefault == canonicalPublic &&
      canonicalDefault.sourceHash == canonicalPublic.sourceHash)
    "omitted and explicit public state visibility must canonicalize identically"
  expect (canonicalPrivate != canonicalPublic && canonicalCommitment != canonicalPublic &&
      canonicalPrivate != canonicalCommitment)
    "private and commitment state visibility must remain distinct Source AST values"
  expect (canonicalPrivate.sourceHash != canonicalPublic.sourceHash &&
      canonicalCommitment.sourceHash != canonicalPublic.sourceHash &&
      canonicalPrivate.sourceHash != canonicalCommitment.sourceHash)
    "state visibility must contribute to the canonical source binding"

  let parserEnv ← parserEnvironment
  expectParserReject "escaped visibility keyword" <|
    Lean.Parser.runParserCategory parserEnv `ProofForgeV2.Language.pfItem
      "state «public» value : UInt64"
  expectParserReject "unknown visibility keyword" <|
    Lean.Parser.runParserCategory parserEnv `ProofForgeV2.Language.pfItem
      "state secret value : UInt64"

  let typedPrivate ← match Typed.check privateState with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  expect (typedPrivate.state.map (·.visibility) == #[Source.Visibility.proverWitness])
    "Typed state declarations must retain private visibility"

  let semanticPublic ← match Compiler.compile publicState with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let semanticPrivate ← match Compiler.compile privateState with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let semanticCommitment ← match Compiler.compile commitmentState with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  expect (semanticPublic.state.map (·.visibility) == #[Semantic.Visibility.verifierVisible] &&
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

  let privateCounterSource : Source.Program := {
    Examples.counter with
    «state» := Examples.counter.state.map fun sourceState =>
      { sourceState with visibility := .proverWitness }
  }
  let privateCounter ← match Compiler.compile privateCounterSource with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let forgedNoir : ResolvedProgram .noir := {
    source := privateCounter
    descriptor := Targets.Noir.descriptor
    targetMatches := rfl
  }
  match Targets.Noir.makePlan forgedNoir with
  | .error (.unsupportedRequirement .privateState .noir) => pure ()
  | .error other => throw <| IO.userError (s!"forged Noir resolution returned the wrong error: {other.render}")
  | .ok _ => throw <| IO.userError "forged Noir resolution must not erase private state into public relation inputs"

end Tests.Language.StateVisibility
