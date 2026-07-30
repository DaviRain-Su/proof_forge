import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Noir
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession
import Tests.Fixtures.SourcePrograms
import Tests.Materialization.TargetIrFixtures

namespace Tests.Materialization.NoirRelationModel

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open Tests.Fixtures.SourcePrograms

private def counterSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program Counter where\n" ++
  "  state count : UInt64\n\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n\n" ++
  "  entry increment(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n\n" ++
  "end ProofForgeV2.Examples\n"

private def accumulatorSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program Accumulator where\n" ++
  "  state total : UInt64\n\n" ++
  "  init(seed : UInt64) do\n" ++
  "    total := seed\n\n" ++
  "  entry add(amount : UInt64) : UInt64 do\n" ++
  "    total := total + amount\n" ++
  "    return total\n\n" ++
  "  view current() : UInt64 do\n" ++
  "    return total\n\n" ++
  "end ProofForgeV2.Examples\n"

private def privateSumSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program PrivateSum4 where\n" ++
  "  entry sum(private a : UInt64, private b : UInt64, private c : UInt64, private d : UInt64) : UInt64 do\n" ++
  "    return a + b + c + d\n\n" ++
  "end ProofForgeV2.Examples\n"

private abbrev U64 := _root_.UInt64

private inductive ModelValue where
  | u64 (value : U64)
  | bool (value : Bool)
  deriving BEq, Inhabited, Repr

private structure Machine where
  inputs : Array ModelValue
  temps : Array (Option U64)

private def modelError (message : String) : Except String α :=
  .error message

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def liftModel (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error reason => throw <| IO.userError s!"{label}: {reason}"

private def readInputU64 (machine : Machine) (index : Nat) : Except String U64 :=
  match machine.inputs[index]? with
  | some (.u64 value) => .ok value
  | some (.bool _) => modelError s!"input {index} is Bool, not UInt64"
  | none => modelError s!"input {index} is outside the relation frame"

private def readInputBool (machine : Machine) (index : Nat) : Except String Bool :=
  match machine.inputs[index]? with
  | some (.bool value) => .ok value
  | some (.u64 _) => modelError s!"input {index} is UInt64, not Bool"
  | none => modelError s!"input {index} is outside the relation frame"

private def readTemp (machine : Machine) (index : Nat) : Except String U64 :=
  match machine.temps[index]? with
  | some (some value) => .ok value
  | some none => modelError s!"temporary {index} has not been assigned"
  | none => modelError s!"temporary {index} is outside the relation frame"

private def readValue (machine : Machine) : Targets.Noir.ValueRef → Except String U64
  | .input index => readInputU64 machine index
  | .literal value => .ok value
  | .temp index => readTemp machine index

private def writeTemp (machine : Machine) (index : Nat)
    (value : U64) : Except String Machine :=
  match machine.temps[index]? with
  | some none => .ok { machine with temps := machine.temps.set! index (some value) }
  | some (some _) => modelError s!"temporary {index} was assigned more than once"
  | none => modelError s!"temporary {index} is outside the relation frame"

private def step (machine : Machine) :
    Targets.Noir.Operation → Except String Machine
  | .checkedAdd destination lhs rhs => do
      let left ← readValue machine lhs
      let right ← readValue machine rhs
      let sum := left.toNat + right.toNat
      if sum > 18446744073709551615 then
        modelError "native checked UInt64 addition overflow"
      else
        writeTemp machine destination (UInt64.ofNat sum)
  | .checkedSub destination lhs rhs => do
      let left ← readValue machine lhs
      let right ← readValue machine rhs
      if left < right then
        modelError "native checked UInt64 subtraction underflow"
      else
        writeTemp machine destination (left - right)
  | .assertEqual lhs rhs => do
      let left ← readValue machine lhs
      let right ← readValue machine rhs
      if left == right then .ok machine
      else modelError s!"UInt64 assertion failed: {left.toNat} != {right.toNat}"
  | .assertBool inputIndex expected => do
      let actual ← readInputBool machine inputIndex
      if actual == expected then .ok machine
      else modelError s!"Bool assertion failed at input {inputIndex}"

private def runOperations :
    List Targets.Noir.Operation → Machine → Except String Machine
  | [], machine => .ok machine
  | operation :: remaining, machine => do
      let next ← step machine operation
      runOperations remaining next

private def validateInputTypes (relation : Targets.Noir.RelationIR)
    (inputs : Array ModelValue) : Except String Unit := do
  if inputs.size != relation.sourceRelation.inputs.size then
    let expected := relation.sourceRelation.inputs.size
    return ← modelError s!"input count {inputs.size} does not equal relation input count {expected}"
  for index in [0:inputs.size] do
    let expected := relation.sourceRelation.inputs[index]!.type
    let actual := inputs[index]!
    match expected, actual with
    | .u64, .u64 _ | .bool, .bool _ => pure ()
    | .u64, .bool _ => return ← modelError s!"input {index} must be UInt64"
    | .bool, .u64 _ => return ← modelError s!"input {index} must be Bool"

/-- Pure deterministic interpreter for target-owned typed relation operations.
It checks a caller-supplied relation witness/public-input assignment only. It
is not Nargo, ACIR execution, proof generation, verification, or settlement. -/
private def execute (relation : Targets.Noir.RelationIR)
    (inputs : Array ModelValue) : Except String Unit := do
  validateInputTypes relation inputs
  let initial : Machine := {
    inputs
    temps := Array.replicate relation.tempCount none
  }
  let _ ← runOperations relation.operations.toList initial
  pure ()

private def expectAccept (label : String)
    (relation : Targets.Noir.RelationIR) (inputs : Array ModelValue) : IO Unit :=
  match execute relation inputs with
  | .ok () => pure ()
  | .error reason => throw <| IO.userError s!"{label} rejected: {reason}"

private def expectReject (label : String)
    (relation : Targets.Noir.RelationIR) (inputs : Array ModelValue) : IO Unit :=
  match execute relation inputs with
  | .error _ => pure ()
  | .ok () => throw <| IO.userError s!"{label} unexpectedly satisfied the relation"

private def testCheckedSubModel : IO Unit := do
  let machine : Machine := {
    inputs := #[]
    temps := #[some 7, some 5, none]
  }
  let success ← match step machine (.checkedSub 2 (.temp 0) (.temp 1)) with
    | .ok value => pure value
    | .error reason => throw <| IO.userError s!"checked-sub model: {reason}"
  expect (success.temps[2]? == some (some 2))
    "checked-sub relation model must write the exact UInt64 difference"
  match step machine (.checkedSub 2 (.temp 1) (.temp 0)) with
  | .error reason =>
      expect (reason.contains "underflow")
        s!"checked-sub relation model must classify underflow, got {reason}"
  | .ok _ => throw <| IO.userError "checked-sub relation model accepted 5 - 7"

def runCheckedSubFast : IO Unit := do
  testCheckedSubModel
  IO.println "Tests.Materialization.NoirRelationModel.checkedSub: ok"

private unsafe def compileIrFromProgramV1 (sourceText moduleName path : String) :
    IO Targets.Noir.IR := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1 sourceText path moduleName none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.noir none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  -- S6 repair: production capability-gated IR inspection (not TargetIrFixtures).
  let _plan ← liftResult <| Targets.Noir.planFromCapability capability
  liftResult <| Targets.Noir.irFromCapability capability

private def findRelation (ir : Targets.Noir.IR)
    (name : String) : IO Targets.Noir.RelationIR :=
  match ir.relations.find? (fun relation => relation.sourceRelation.name == name) with
  | some relation => pure relation
  | none => throw <| IO.userError s!"typed Noir IR is missing relation '{name}'"

private def bindInputs (relation : Targets.Noir.RelationIR)
    (valueFor : Targets.Noir.InputRole → Option ModelValue) :
    Except String (Array ModelValue) := do
  let mut values : Array ModelValue := #[]
  for binding in relation.sourceRelation.inputs do
    let value ← match valueFor binding.role with
      | some value => pure value
      | none => modelError s!"no model value for input '{binding.name}'"
    match binding.type, value with
    | .u64, .u64 _ | .bool, .bool _ => values := values.push value
    | .u64, .bool _ => return ← modelError s!"input '{binding.name}' must be UInt64"
    | .bool, .u64 _ => return ← modelError s!"input '{binding.name}' must be Bool"
  return values

private def statefulInputs (relation : Targets.Noir.RelationIR)
    (preInitialized : Bool) (preState parameter postState : U64)
    (postInitialized : Bool) (result : U64) : Except String (Array ModelValue) :=
  bindInputs relation fun role => match role with
    | .preInitialized => some <| .bool preInitialized
    | .preState _ => some <| .u64 preState
    | .parameter _ => some <| .u64 parameter
    | .postState _ => some <| .u64 postState
    | .postInitialized => some <| .bool postInitialized
    | .result => some <| .u64 result

private def privateSumInputs (relation : Targets.Noir.RelationIR)
    (params : Array U64) (result : U64) : Except String (Array ModelValue) :=
  bindInputs relation fun role => match role with
    | .parameter sourceId => .u64 <$> params[sourceId]?
    | .result => some <| .u64 result
    | _ => none

private structure StatefulCase where
  label : String
  sourceText : String
  moduleName : String
  path : String
  mutateName : String
  viewName : String

private unsafe def checkStatefulLifecycle (test : StatefulCase) : IO Unit := do
  let ir ← compileIrFromProgramV1 test.sourceText test.moduleName test.path
  let initializer ← findRelation ir "init"
  let mutate ← findRelation ir test.mutateName
  let viewRelation ← findRelation ir test.viewName

  let initOk ← liftModel s!"{test.label} init inputs" <|
    statefulInputs initializer false 0 7 7 true 0
  expectAccept s!"{test.label} init false-to-true" initializer initOk

  let initWrongPre ← liftModel s!"{test.label} wrong init pre flag" <|
    statefulInputs initializer true 0 7 7 true 0
  expectReject s!"{test.label} init with pre_initialized=true" initializer initWrongPre
  let initWrongPostFlag ← liftModel s!"{test.label} wrong init post flag" <|
    statefulInputs initializer false 0 7 7 false 0
  expectReject s!"{test.label} init with post_initialized=false"
    initializer initWrongPostFlag
  let initWrongPost ← liftModel s!"{test.label} wrong init post state" <|
    statefulInputs initializer false 0 7 8 true 0
  expectReject s!"{test.label} init with wrong post state" initializer initWrongPost

  let addOk ← liftModel s!"{test.label} add inputs" <|
    statefulInputs mutate true 7 5 12 true 12
  expectAccept s!"{test.label} 7+5=12 true-to-true" mutate addOk

  let addWrongPreFlag ← liftModel s!"{test.label} wrong add pre flag" <|
    statefulInputs mutate false 7 5 12 true 12
  expectReject s!"{test.label} mutate with pre_initialized=false" mutate addWrongPreFlag
  let addWrongPostFlag ← liftModel s!"{test.label} wrong add post flag" <|
    statefulInputs mutate true 7 5 12 false 12
  expectReject s!"{test.label} mutate with post_initialized=false" mutate addWrongPostFlag
  let addWrongPost ← liftModel s!"{test.label} wrong add post state" <|
    statefulInputs mutate true 7 5 11 true 12
  expectReject s!"{test.label} mutate with wrong post state" mutate addWrongPost
  let addWrongResult ← liftModel s!"{test.label} wrong add result" <|
    statefulInputs mutate true 7 5 12 true 11
  expectReject s!"{test.label} mutate with wrong result" mutate addWrongResult

  let maxU64 := UInt64.ofNat 18446744073709551615
  let overflow ← liftModel s!"{test.label} overflow inputs" <|
    statefulInputs mutate true maxU64 1 0 true 0
  expectReject s!"{test.label} max+1 overflow" mutate overflow

  let viewOk ← liftModel s!"{test.label} view inputs" <|
    statefulInputs viewRelation true 12 0 12 true 12
  expectAccept s!"{test.label} view preserves initialized state" viewRelation viewOk
  let viewWrongPreFlag ← liftModel s!"{test.label} wrong view pre flag" <|
    statefulInputs viewRelation false 12 0 12 true 12
  expectReject s!"{test.label} view with pre_initialized=false"
    viewRelation viewWrongPreFlag
  let viewWrongPostFlag ← liftModel s!"{test.label} wrong view post flag" <|
    statefulInputs viewRelation true 12 0 12 false 12
  expectReject s!"{test.label} view with post_initialized=false"
    viewRelation viewWrongPostFlag
  let viewWrongPost ← liftModel s!"{test.label} wrong view post state" <|
    statefulInputs viewRelation true 12 0 13 true 12
  expectReject s!"{test.label} view with changed post state" viewRelation viewWrongPost
  let viewWrongResult ← liftModel s!"{test.label} wrong view result" <|
    statefulInputs viewRelation true 12 0 12 true 13
  expectReject s!"{test.label} view with wrong result" viewRelation viewWrongResult

/-- Isolated residual-only PrivateSum4 host accept/reject via test-local
    RelationIR fixture. The retained-semantic product envelope rejects
    privateWitness; this is **not** product IR/emission evidence (product path is
    `checkPrivateSum4ProductClosed`). -/
private def checkPrivateSum4ResidualRelationModel : IO Unit := do
  let relation := Tests.Materialization.TargetIrFixtures.privateSum4RelationIR
  let parameterBindings := relation.sourceRelation.inputs.filter fun binding =>
    match binding.role with
    | .parameter _ => true
    | _ => false
  let resultBindings := relation.sourceRelation.inputs.filter fun binding =>
    binding.role == .result
  expect (parameterBindings.size == 4 &&
      parameterBindings.all (fun binding => binding.visibility == .witness) &&
      resultBindings.size == 1 && resultBindings[0]!.visibility == .verifier)
    "PrivateSum4 fixture must bind four private witnesses and one verifier-visible result"
  expect (relation.operations == #[
      .checkedAdd 0 (.input 0) (.input 1),
      .checkedAdd 1 (.temp 0) (.input 2),
      .checkedAdd 2 (.temp 1) (.input 3),
      .assertEqual (.input 4) (.temp 2)
    ])
    "PrivateSum4 fixture must preserve every checked addition"
  let valid ← liftModel "PrivateSum4 valid inputs" <|
    privateSumInputs relation #[1, 2, 3, 4] 10
  expectAccept "PrivateSum4 1+2+3+4=10" relation valid
  let wrongResult ← liftModel "PrivateSum4 wrong-result inputs" <|
    privateSumInputs relation #[1, 2, 3, 4] 11
  expectReject "PrivateSum4 wrong public result" relation wrongResult

/-- S6 product path: privateWitness / private params fail closed before emit.
    Shipped path: CheckV1 disclosure rejects private→public return as
    `PF-VIS-001` (via Normalize typed gate). Alternate closed phases:
    `PF-SRC-INVALID` (unsupported shape) or later capability
    `PF-REQ-UNSUPPORTED` / `PF-REGISTRY-INVALID`. Never vacuous pure (). -/
private unsafe def checkPrivateSum4ProductClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgramV1 privateSumSourceText "<noir-private-sum>"
      "Examples.PrivateSum4" none with
  | .error e =>
      expect (e.code == "PF-SRC-INVALID" || e.code.startsWith "PF-")
        s!"PrivateSum4 selectProgramV1 must fail closed with PF-*, got {e.render}"
  | .ok source =>
      match Compiler.compileValidatedSourceV1 source with
      | .error e =>
          expect (e.code == "PF-VIS-001" || e.code == "PF-SRC-INVALID")
            s!"PrivateSum4 product compile must fail closed (PF-VIS-001 or PF-SRC-INVALID), got {e.render}"
      | .ok compiled =>
          let selection ← liftResult <| resolveBuildSelectionV1 TargetId.noir none
          match Targets.resolveEngineeringRequirementsV1 selection compiled with
          | .error e =>
              expect (e.code == "PF-REQ-UNSUPPORTED" || e.code == "PF-REGISTRY-INVALID")
                s!"PrivateSum4 capability mint must fail closed, got {e.render}"
          | .ok _ =>
              throw <| IO.userError
                "PrivateSum4 must not mint engineering capability (privateWitness outside S2)"

unsafe def run : IO Unit := do
  runCheckedSubFast
  checkStatefulLifecycle {
    label := "Counter"
    sourceText := counterSourceText
    moduleName := "Examples.Counter"
    path := "<noir-rel-counter>"
    mutateName := "increment"
    viewName := "get"
  }
  checkStatefulLifecycle {
    label := "Accumulator"
    sourceText := accumulatorSourceText
    moduleName := "Examples.Accumulator"
    path := "<noir-rel-accumulator>"
    mutateName := "add"
    viewName := "current"
  }
  checkPrivateSum4ResidualRelationModel
  checkPrivateSum4ProductClosed

end Tests.Materialization.NoirRelationModel
