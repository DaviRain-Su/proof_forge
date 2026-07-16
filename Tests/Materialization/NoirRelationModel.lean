import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Accumulator
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Examples.PrivateSum4
import ProofForgeV2.Targets.Noir

namespace Tests.Materialization.NoirRelationModel

open ProofForgeV2

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

private def compileIr (sourceProgram : Source.Program) : IO Targets.Noir.IR := do
  let semantic ← liftResult <| Compiler.compile sourceProgram
  let resolved ← liftResult <| Targets.resolve Targets.Noir.descriptor semantic
  let plan ← liftResult <| Targets.Noir.makePlan resolved
  liftResult <| Targets.Noir.lower plan

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
  sourceProgram : Source.Program
  mutateName : String
  viewName : String

private def checkStatefulLifecycle (test : StatefulCase) : IO Unit := do
  let ir ← compileIr test.sourceProgram
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

private def checkPrivateSum4 : IO Unit := do
  let ir ← compileIr Examples.privateSum4
  let relation ← findRelation ir "sum"
  let parameterBindings := relation.sourceRelation.inputs.filter fun binding =>
    match binding.role with
    | .parameter _ => true
    | _ => false
  let resultBindings := relation.sourceRelation.inputs.filter fun binding =>
    binding.role == .result
  expect (parameterBindings.size == 4 &&
      parameterBindings.all (fun binding => binding.visibility == .witness) &&
      resultBindings.size == 1 && resultBindings[0]!.visibility == .verifier)
    "PrivateSum4 must bind four private witnesses and one verifier-visible result"

  let valid ← liftModel "PrivateSum4 valid inputs" <|
    privateSumInputs relation #[1, 2, 3, 4] 10
  expectAccept "PrivateSum4 1+2+3+4=10" relation valid
  let wrongResult ← liftModel "PrivateSum4 wrong-result inputs" <|
    privateSumInputs relation #[1, 2, 3, 4] 11
  expectReject "PrivateSum4 wrong public result" relation wrongResult

def run : IO Unit := do
  checkStatefulLifecycle {
    label := "Counter"
    sourceProgram := Examples.counter
    mutateName := "increment"
    viewName := "get"
  }
  checkStatefulLifecycle {
    label := "Accumulator"
    sourceProgram := Examples.accumulator
    mutateName := "add"
    viewName := "current"
  }
  checkPrivateSum4

end Tests.Materialization.NoirRelationModel
