/-
  Tests.Typed.RequirementsInferV1 — D2-05 requirements inference engineering
  subset suite.

  Covers Counter-like public state + arithmetic, private/commitment state
  disclosure, private entry param (privateWitness), AST-direct emit/call/
  schedule, Bool type carrier, idempotent id list, optional parity vs
  Semantic.deriveRequirements on compileValidatedSourceV1-accepted programs,
  and exact ProgramRequirement.id human wire strings.
  Independent of CheckV1 / Typed.checkV1 product path.
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Core.SemanticIR
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.RequirementsInferV1
import Tests.Language.ParserSession

namespace Tests.Typed.RequirementsInferV1

open ProofForgeV2
open ProofForgeV2.Core
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.RequirementsInferV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def moduleName : String := "Tests.RequirementsInferV1"

private def reqIds (reqs : Array ProgramRequirement) : Array String :=
  reqs.map ProgramRequirement.id

private def containsReq (reqs : Array ProgramRequirement) (r : ProgramRequirement) : Bool :=
  reqs.contains r

private unsafe def loadSource
    (session : Language.Loader.ParserSession) (label source : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 source ("<req-infer-" ++ label ++ ">") moduleName none with
  | .ok validated => pure validated
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private unsafe def inferSource
    (session : Language.Loader.ParserSession) (label source : String) :
    IO RequirementsInferResultV1 := do
  let validated ← loadSource session label source
  pure (inferRequirementsV1 validated)

private def wrap (name body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++ body

/-- 1. Counter-like public state + init + increment/get. -/
private unsafe def testCounterLike
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ReqCounter" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let result ← inferSource session "counter" source
  expect result.ok "counter: ok"
  expect result.analysisComplete "counter: complete"
  let reqs := result.requirements
  expect (containsReq reqs .persistentState) "counter: persistentState"
  expect (containsReq reqs .checkedArithmetic) "counter: checkedArithmetic"
  expect (containsReq reqs .transactionalRollback) "counter: transactionalRollback"
  expect (!containsReq reqs .privateState) "counter: no privateState"
  expect (!containsReq reqs .privateWitness) "counter: no privateWitness"
  expect (!containsReq reqs .callerContext) "counter: no callerContext"
  -- First-seen order: persistent then arithmetic then rollback (from +)
  expect (reqs == #[.persistentState, .checkedArithmetic, .transactionalRollback])
    s!"counter: exact order, got {reqIds reqs}"

/-- 2. private state only. -/
private unsafe def testPrivateState
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ReqPrivateState" <|
    "  state private value : UInt64\n" ++
    "  entry ping() : UInt64 do\n" ++
    "    return 0\n"
  let result ← inferSource session "private-state" source
  expect (result.requirements == #[.persistentState, .privateState])
    s!"private-state: expected [persistent, privateState], got {reqIds result.requirements}"

/-- 3. commitment state. -/
private unsafe def testCommitmentState
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ReqCommitmentState" <|
    "  state commitment value : UInt64\n" ++
    "  entry ping() : UInt64 do\n" ++
    "    return 0\n"
  let result ← inferSource session "commitment-state" source
  expect (result.requirements == #[.persistentState, .commitmentState])
    s!"commitment-state: expected [persistent, commitmentState], got {reqIds result.requirements}"

/-- 4. private entry param ⇒ privateWitness; public param no disclosure. -/
private unsafe def testPrivateParam
    (session : Language.Loader.ParserSession) : IO Unit := do
  let privateSrc := wrap "ReqPrivateParam" <|
    "  entry run(private secret : UInt64) : UInt64 do\n" ++
    "    return 0\n"
  let publicSrc := wrap "ReqPublicParam" <|
    "  entry run(public x : UInt64) : UInt64 do\n" ++
    "    return 0\n"
  let priv ← inferSource session "private-param" privateSrc
  let pub ← inferSource session "public-param" publicSrc
  expect (containsReq priv.requirements .privateWitness)
    "private-param: privateWitness"
  expect (!containsReq priv.requirements .privateState)
    "private-param: not privateState"
  expect (!containsReq pub.requirements .privateWitness)
    "public-param: no privateWitness"
  expect (!containsReq pub.requirements .commitmentDisclosure)
    "public-param: no commitmentDisclosure"
  expect (priv.requirements == #[.privateWitness])
    s!"private-param exact: {reqIds priv.requirements}"
  expect (pub.requirements == #[])
    s!"public-param exact empty: {reqIds pub.requirements}"

/-- 5. AST-direct emit ⇒ eventEmission. -/
private unsafe def testEmit
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ReqEmit" <|
    "  event Ev()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    emit Ev()\n" ++
    "    return 0\n"
  let result ← inferSource session "emit" source
  expect (containsReq result.requirements .eventEmission) "emit: eventEmission"
  expect (result.requirements == #[.eventEmission])
    s!"emit exact: {reqIds result.requirements}"

/-- 6. AST-direct external call ⇒ synchronousCall + transactionalRollback. -/
private unsafe def testExternalCall
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ReqCall" <|
    "  entry run() : UInt64 do\n" ++
    "    call External.Use()\n" ++
    "    return 0\n"
  let result ← inferSource session "call" source
  expect (containsReq result.requirements .synchronousCall) "call: synchronousCall"
  expect (containsReq result.requirements .transactionalRollback)
    "call: transactionalRollback"
  expect (result.requirements == #[.synchronousCall, .transactionalRollback])
    s!"call exact: {reqIds result.requirements}"

/-- 7. AST-direct schedule ⇒ asynchronousWorkflow only. -/
private unsafe def testSchedule
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ReqSchedule" <|
    "  entry run() : UInt64 do\n" ++
    "    schedule External.Later()\n" ++
    "    return 0\n"
  let result ← inferSource session "schedule" source
  expect (containsReq result.requirements .asynchronousWorkflow)
    "schedule: asynchronousWorkflow"
  expect (!containsReq result.requirements .transactionalRollback)
    "schedule: no invented transactionalRollback"
  expect (result.requirements == #[.asynchronousWorkflow])
    s!"schedule exact: {reqIds result.requirements}"

/-- 8. Bool result/param ⇒ boolValues. -/
private unsafe def testBoolValues
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ReqBool" <|
    "  entry run(flag : Bool) : Bool do\n" ++
    "    return flag\n"
  let result ← inferSource session "bool" source
  expect (containsReq result.requirements .boolValues) "bool: boolValues"
  -- param Bool then result Bool; stableUnique keeps one
  expect (result.requirements == #[.boolValues])
    s!"bool exact: {reqIds result.requirements}"

/-- 9. Idempotent: twice same AST ⇒ byte-identical requirement id list. -/
private unsafe def testIdempotent
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ReqIdem" <|
    "  state count : UInt64\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n"
  let a ← inferSource session "idem-a" source
  let b ← inferSource session "idem-b" source
  expect (reqIds a.requirements == reqIds b.requirements)
    s!"idempotent ids: {reqIds a.requirements} vs {reqIds b.requirements}"
  expect (a.requirements == b.requirements) "idempotent arrays"

/-- 10. Parity with Semantic.deriveRequirements on S1 Counter; direct inference
    for out-of-S1 private/commitment/call (full compile no longer required). -/
private unsafe def testParity
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Counter product source text (S1 — compile + deriveRequirements parity)
  let counterSrc := Examples.counterSourceText
  match ← session.selectProgramV1 counterSrc "<req-infer-parity-counter>"
      Examples.counterModuleNameV1 none with
  | .error e => throw <| IO.userError s!"parity-counter load: {e.render}"
  | .ok validated =>
      let inferred := inferRequirementsV1 validated
      match Compiler.compileValidatedSourceV1 validated with
      | .error e => throw <| IO.userError s!"parity-counter compile: {e.render}"
      | .ok semantic =>
          expect (inferred.requirements == semantic.requirements)
            s!"parity-counter: infer {reqIds inferred.requirements} != semantic {reqIds semantic.requirements}"
          expect (inferred.requirements == Semantic.deriveRequirements semantic)
            "parity-counter: match deriveRequirements"

  -- Public S1-compatible state (bare place return) — compile parity.
  let publicSrc :=
    "import ProofForgeV2\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "namespace Tests.RequirementsInferParity\n\n" ++
    "program ParityPublic where\n" ++
    "  state public value : UInt64\n\n" ++
    "  entry ping() : UInt64 do\n" ++
    "    return value\n\n" ++
    "end Tests.RequirementsInferParity\n"
  match ← session.selectProgramV1 publicSrc "<ParityPublic>"
      "Tests.RequirementsInferParity" none with
  | .error e => throw <| IO.userError s!"ParityPublic load: {e.render}"
  | .ok validated =>
      let inferred := inferRequirementsV1 validated
      expect (inferred.requirements == #[.persistentState])
        s!"ParityPublic: infer got {reqIds inferred.requirements}"
      match Compiler.compileValidatedSourceV1 validated with
      | .error e => throw <| IO.userError s!"ParityPublic compile: {e.render}"
      | .ok semantic =>
          expect (inferred.requirements == semantic.requirements)
            s!"ParityPublic: parity infer {reqIds inferred.requirements} != semantic {reqIds semantic.requirements}"

  -- Private / commitment / call: direct inference only (out of S1 Normalize surface).
  let nonS1 : Array (String × String × Array ProgramRequirement) := #[
    ("ParityPrivate",
      "  state private value : UInt64\n" ++
      "  entry ping() : UInt64 do\n" ++
      "    return value\n",
      #[.persistentState, .privateState]),
    ("ParityCommitment",
      "  state commitment value : UInt64\n" ++
      "  entry ping() : UInt64 do\n" ++
      "    return value\n",
      #[.persistentState, .commitmentState]),
    ("ParityCall",
      "  entry run() : UInt64 do\n" ++
      "    call External.Use()\n" ++
      "    return 0\n",
      #[.synchronousCall, .transactionalRollback])]
  for c in nonS1 do
    let progName := c.1
    let body := c.2.1
    let expected := c.2.2
    let source := wrap progName body
    match ← session.selectProgramV1 source ("<" ++ progName ++ ">")
        moduleName none with
    | .error e => throw <| IO.userError s!"{progName} load: {e.render}"
    | .ok validated =>
        let inferred := inferRequirementsV1 validated
        expect (inferred.requirements == expected)
          s!"{progName}: infer got {reqIds inferred.requirements}"

/-- 11. Human wire ids exact. -/
private def testWireIds : IO Unit := do
  expect (ProgramRequirement.id .persistentState == "state.persistent")
    "wire persistent"
  expect (ProgramRequirement.id .checkedArithmetic == "value.checked-arithmetic")
    "wire checked-arithmetic"
  expect (ProgramRequirement.id .transactionalRollback == "failure.atomic-rollback")
    "wire atomic-rollback"
  expect (ProgramRequirement.id .synchronousCall == "effect.synchronous-call")
    "wire synchronous-call"
  expect (ProgramRequirement.id .asynchronousWorkflow == "effect.asynchronous-workflow")
    "wire asynchronous-workflow"
  expect (ProgramRequirement.id .privateWitness == "disclosure.private-witness")
    "wire private-witness"
  expect (ProgramRequirement.id .eventEmission == "effect.event")
    "wire event"
  expect (ProgramRequirement.id .callerContext == "context.caller")
    "wire caller"
  expect (ProgramRequirement.id .boolValues == "value.bool")
    "wire bool"
  expect (ProgramRequirement.id .commitmentDisclosure == "disclosure.commitment")
    "wire commitment disclosure"
  expect (ProgramRequirement.id .fieldBn254 == "value.field.bn254-fr")
    "wire field"
  expect (ProgramRequirement.id .privateState == "disclosure.private-state")
    "wire private-state"
  expect (ProgramRequirement.id .commitmentState == "disclosure.commitment-state")
    "wire commitment-state"

/-- Extra: Field bn254_fr type carrier; assert/revert transactionalRollback. -/
private unsafe def testFieldAndFailure
    (session : Language.Loader.ParserSession) : IO Unit := do
  let fieldSrc := wrap "ReqField" <|
    "  entry run(x : Field bn254_fr) : Field bn254_fr do\n" ++
    "    return x\n"
  let field ← inferSource session "field" fieldSrc
  expect (field.requirements == #[.fieldBn254])
    s!"field: {reqIds field.requirements}"

  let assertSrc := wrap "ReqAssert" <|
    "  entry run(x : Bool) : UInt64 do\n" ++
    "    assert x\n" ++
    "    return 0\n"
  let asrt ← inferSource session "assert" assertSrc
  expect (containsReq asrt.requirements .boolValues) "assert: bool from param"
  expect (containsReq asrt.requirements .transactionalRollback)
    "assert: transactionalRollback"

  let revertSrc := wrap "ReqRevert" <|
    "  error Boom()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    revert Boom()\n" ++
    "    return 0\n"
  let rev ← inferSource session "revert" revertSrc
  expect (rev.requirements == #[.transactionalRollback])
    s!"revert: {reqIds rev.requirements}"

  let commitmentParam := wrap "ReqCommitParam" <|
    "  entry run(commitment c : UInt64) : UInt64 do\n" ++
    "    return 0\n"
  let cp ← inferSource session "commit-param" commitmentParam
  expect (cp.requirements == #[.commitmentDisclosure])
    s!"commit-param: {reqIds cp.requirements}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testCounterLike session
  testPrivateState session
  testCommitmentState session
  testPrivateParam session
  testEmit session
  testExternalCall session
  testSchedule session
  testBoolValues session
  testIdempotent session
  testParity session
  testWireIds
  testFieldAndFailure session
  IO.println "Tests.Typed.RequirementsInferV1: ok"

end Tests.Typed.RequirementsInferV1
