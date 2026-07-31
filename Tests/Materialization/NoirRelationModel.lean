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

/-- Equality operands may be UInt64 or Bool public inputs. Bool values are
compared as 0/1, consistent with compare-result temps. -/
private def readComparable (machine : Machine) : Targets.Noir.ValueRef → Except String U64
  | .input index =>
      match machine.inputs[index]? with
      | some (.u64 value) => .ok value
      | some (.bool value) => .ok (if value then 1 else 0)
      | none => modelError s!"input {index} is outside the relation frame"
  | .literal value => .ok value
  | .temp index => readTemp machine index

private def writeTemp (machine : Machine) (index : Nat)
    (value : U64) : Except String Machine :=
  match machine.temps[index]? with
  | some none => .ok { machine with temps := machine.temps.set! index (some value) }
  | some (some _) => modelError s!"temporary {index} was assigned more than once"
  | none => modelError s!"temporary {index} is outside the relation frame"

private def evalComparison (op : Targets.Noir.ComparisonOp)
    (left right : U64) : U64 :=
  let result : Bool := match op with
    | .eq => left == right
    | .ne => left != right
    | .lt => left < right
    | .le => left ≤ right
    | .gt => left > right
    | .ge => left ≥ right
  if result then 1 else 0

mutual
private partial def step (machine : Machine) :
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
  | .checkedMul destination lhs rhs => do
      let left ← readValue machine lhs
      let right ← readValue machine rhs
      let product := left.toNat * right.toNat
      if product > 18446744073709551615 then
        modelError "native checked UInt64 multiplication overflow"
      else
        writeTemp machine destination (UInt64.ofNat product)
  | .checkedDiv destination lhs rhs => do
      let left ← readValue machine lhs
      let right ← readValue machine rhs
      if right == 0 then
        modelError "native checked UInt64 division by zero"
      else
        writeTemp machine destination (left / right)
  | .checkedMod destination lhs rhs => do
      let left ← readValue machine lhs
      let right ← readValue machine rhs
      if right == 0 then
        modelError "native checked UInt64 remainder by zero"
      else
        writeTemp machine destination (left % right)
  | .bitNot destination source => do
      let value ← readValue machine source
      writeTemp machine destination
        (UInt64.ofNat (18446744073709551615 - value.toNat))
  | .boolNot destination source => do
      let value ← readValue machine source
      if value == 0 then
        writeTemp machine destination 1
      else if value == 1 then
        writeTemp machine destination 0
      else
        modelError "native Bool negation received a non-Bool value"
  | .compare op destination lhs rhs => do
      let left ← readValue machine lhs
      let right ← readValue machine rhs
      writeTemp machine destination (evalComparison op left right)
  | .assertEqual lhs rhs => do
      let left ← readComparable machine lhs
      let right ← readComparable machine rhs
      if left == right then .ok machine
      else modelError s!"equality assertion failed: {left.toNat} != {right.toNat}"
  | .assertBool inputIndex expected => do
      let actual ← readInputBool machine inputIndex
      if actual == expected then .ok machine
      else modelError s!"Bool assertion failed at input {inputIndex}"
  | .assertConstraint condition => do
      let value ← readComparable machine condition
      if value != 0 then .ok machine
      else modelError "assert constraint failed: condition is zero"
  | .ifRegion condition thenOps elseOps => do
      let value ← readComparable machine condition
      runOperations (if value != 0 then thenOps.toList else elseOps.toList) machine
  | .switchRegion scrutinee _ cases defaultOps => do
      let value ← readComparable machine scrutinee
      match cases.find? (fun (caseValue, _) => caseValue == value) with
      | some (_, caseOps) => runOperations caseOps.toList machine
      | none => runOperations defaultOps.toList machine
  | .selectRegion destination condition _ thenOps thenValue elseOps elseValue => do
      let value ← readComparable machine condition
      let machine' ← runOperations
        (if value != 0 then thenOps.toList else elseOps.toList) machine
      let result ← readValue machine' (if value != 0 then thenValue else elseValue)
      writeTemp machine' destination result
  | .selectSwitch destination scrutinee _ _ cases defaultOps defaultValue => do
      let value ← readComparable machine scrutinee
      match cases.find? (fun (caseValue, _, _) => caseValue == value) with
      | some (_, caseOps, caseResult) => do
          let machine' ← runOperations caseOps.toList machine
          let result ← readValue machine' caseResult
          writeTemp machine' destination result
      | none => do
          let machine' ← runOperations defaultOps.toList machine
          let result ← readValue machine' defaultValue
          writeTemp machine' destination result

private partial def runOperations :
    List Targets.Noir.Operation → Machine → Except String Machine
  | [], machine => .ok machine
  | operation :: remaining, machine => do
      let next ← step machine operation
      runOperations remaining next
end

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

private def testComparisonModel : IO Unit := do
  let machine : Machine := {
    inputs := #[]
    temps := #[some 7, some 5, none]
  }
  let cases : Array (Targets.Noir.ComparisonOp × U64) := #[
    (.eq, 0), (.ne, 1), (.lt, 0), (.le, 0), (.gt, 1), (.ge, 1)
  ]
  for pair in cases do
    let op := pair.1
    let expected := pair.2
    match step machine (.compare op 2 (.temp 0) (.temp 1)) with
    | .ok next =>
        expect (next.temps[2]? == some (some expected))
          s!"comparison model {repr op}: expected {expected.toNat}, got {repr (next.temps[2]?)}"
    | .error reason =>
        throw <| IO.userError s!"comparison model {repr op}: {reason}"
  -- Equality and ordering boundaries on equal operands.
  let equalMachine : Machine := {
    inputs := #[]
    temps := #[some 9, some 9, none]
  }
  match step equalMachine (.compare .eq 2 (.temp 0) (.temp 1)) with
  | .ok next =>
      expect (next.temps[2]? == some (some 1)) "eq equal operands must yield 1"
  | .error reason => throw <| IO.userError s!"eq equal: {reason}"
  match step equalMachine (.compare .lt 2 (.temp 0) (.temp 1)) with
  | .ok next =>
      expect (next.temps[2]? == some (some 0)) "lt equal operands must yield 0"
  | .error reason => throw <| IO.userError s!"lt equal: {reason}"
  match step equalMachine (.compare .ge 2 (.temp 0) (.temp 1)) with
  | .ok next =>
      expect (next.temps[2]? == some (some 1)) "ge equal operands must yield 1"
  | .error reason => throw <| IO.userError s!"ge equal: {reason}"

private def testAssertConstraintModel : IO Unit := do
  let machine : Machine := {
    inputs := #[]
    temps := #[some 1, some 0]
  }
  match step machine (.assertConstraint (.temp 0)) with
  | .ok _ => pure ()
  | .error reason => throw <| IO.userError s!"assert nonzero must accept: {reason}"
  match step machine (.assertConstraint (.temp 1)) with
  | .error reason =>
      expect (reason.contains "zero")
        s!"assert zero must classify failure, got {reason}"
  | .ok _ => throw <| IO.userError "assert zero unexpectedly accepted"
  match step machine (.assertConstraint (.literal 1)) with
  | .ok _ => pure ()
  | .error reason => throw <| IO.userError s!"assert literal true must accept: {reason}"
  match step machine (.assertConstraint (.literal 0)) with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "assert literal false unexpectedly accepted"

def runCompareAssertFast : IO Unit := do
  testComparisonModel
  testAssertConstraintModel
  IO.println "Tests.Materialization.NoirRelationModel.compareAssert: ok"

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
    | .eventSlot _ _ => none

/-- Stateful relation witness with a Bool entry/view result binding. -/
private def statefulInputsBoolResult (relation : Targets.Noir.RelationIR)
    (preInitialized : Bool) (preState parameter postState : U64)
    (postInitialized : Bool) (result : Bool) : Except String (Array ModelValue) :=
  bindInputs relation fun role => match role with
    | .preInitialized => some <| .bool preInitialized
    | .preState _ => some <| .u64 preState
    | .parameter _ => some <| .u64 parameter
    | .postState _ => some <| .u64 postState
    | .postInitialized => some <| .bool postInitialized
    | .result => some <| .bool result
    | .eventSlot _ _ => none

private def privateSumInputs (relation : Targets.Noir.RelationIR)
    (params : Array U64) (result : U64) : Except String (Array ModelValue) :=
  bindInputs relation fun role => match role with
    | .parameter sourceId => .u64 <$> params[sourceId]?
    | .result => some <| .u64 result
    | _ => none

/-- Stateless relation witness with a Bool result binding (0/1 convention). -/
private def privateSumInputsBoolResult (relation : Targets.Noir.RelationIR)
    (params : Array U64) (result : Bool) : Except String (Array ModelValue) :=
  bindInputs relation fun role => match role with
    | .parameter sourceId => .u64 <$> params[sourceId]?
    | .result => some <| .bool result
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

/-- Guarded counter: assert count >= delta before checked subtraction. -/
private def guardedCounterSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program GuardedCounter where\n" ++
  "  state count : UInt64\n\n" ++
  "  init(i : UInt64) do\n" ++
  "    count := i\n\n" ++
  "  entry decrement(delta : UInt64) : UInt64 do\n" ++
  "    assert count >= delta\n" ++
  "    count := count - delta\n" ++
  "    return count\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n\n" ++
  "end ProofForgeV2.Examples\n"

/-- Source covering all six comparison operators via assert conditions. -/
private def allCompareOpsSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program AllCompareOps where\n" ++
  "  entry check(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    assert a == b\n" ++
  "    assert a != b\n" ++
  "    assert a < b\n" ++
  "    assert a <= b\n" ++
  "    assert a > b\n" ++
  "    assert a >= b\n" ++
  "    return a\n\n" ++
  "end ProofForgeV2.Examples\n"

private def boolStateSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program BoolState where\n" ++
  "  state flag : Bool\n\n" ++
  "  init(v : Bool) do\n" ++
  "    flag := v\n\n" ++
  "  view get() : Bool do\n" ++
  "    return flag\n\n" ++
  "end ProofForgeV2.Examples\n"

private def boolParamSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program BoolParam where\n" ++
  "  entry check(flag : Bool) : UInt64 do\n" ++
  "    assert flag\n" ++
  "    return 0\n\n" ++
  "end ProofForgeV2.Examples\n"

private def boolResultSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program BoolResult where\n" ++
  "  entry check(a : UInt64, b : UInt64) : Bool do\n" ++
  "    return a >= b\n\n" ++
  "end ProofForgeV2.Examples\n"

/-- Stateful program with UInt64 entry plus Bool view/entry results. -/
private def boolPredicateSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program BoolPredicate where\n" ++
  "  state count : UInt64\n\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n\n" ++
  "  entry set(v : UInt64) : UInt64 do\n" ++
  "    count := v\n" ++
  "    return count\n\n" ++
  "  view positive() : Bool do\n" ++
  "    return count > 0\n\n" ++
  "  entry equalsCount(d : UInt64) : Bool do\n" ++
  "    return count == d\n\n" ++
  "end ProofForgeV2.Examples\n"

/-- Type-inconsistent: Bool-declared result returning a UInt64 place. -/
private def boolResultReturnsUInt64SourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program BoolResultU64 where\n" ++
  "  entry check(a : UInt64) : Bool do\n" ++
  "    return a\n\n" ++
  "end ProofForgeV2.Examples\n"

/-- Type-inconsistent: UInt64-declared result returning a comparison. -/
private def uint64ResultReturnsCompareSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program U64ResultCompare where\n" ++
  "  entry check(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    return a >= b\n\n" ++
  "end ProofForgeV2.Examples\n"

private def assertElseSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program AssertElse where\n" ++
  "  error E\n\n" ++
  "  entry check(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    assert a >= b else E\n" ++
  "    return a\n\n" ++
  "end ProofForgeV2.Examples\n"

private def findOps (relation : Targets.Noir.RelationIR)
    (pred : Targets.Noir.Operation → Bool) : Array Targets.Noir.Operation :=
  relation.operations.filter pred

private def isAssertConstraint : Targets.Noir.Operation → Bool
  | .assertConstraint _ => true
  | _ => false

private unsafe def checkGuardedCounterProduct : IO Unit := do
  let ir ← compileIrFromProgramV1 guardedCounterSourceText
    "Examples.GuardedCounter" "<noir-guarded-counter>"
  let initializer ← findRelation ir "init"
  let decrement ← findRelation ir "decrement"
  let viewRelation ← findRelation ir "get"

  -- Pin comparison op kind/order and assert placement on the mutate relation.
  let compares := findOps decrement (fun op => match op with
    | .compare .. => true
    | _ => false)
  expect (compares.size == 1)
    s!"GuardedCounter decrement must emit exactly one compare, got {compares.size}"
  match compares[0]! with
  | .compare .ge _ _ _ => pure ()
  | other => throw <| IO.userError s!"GuardedCounter expected ge compare, got {repr other}"
  let asserts := findOps decrement isAssertConstraint
  expect (asserts.size == 1)
    s!"GuardedCounter decrement must emit exactly one assertConstraint, got {asserts.size}"
  -- Compare must precede its assertConstraint in the operation stream.
  let mut sawCompare := false
  let mut orderOk := false
  for operation in decrement.operations do
    match operation with
    | .compare .ge .. => sawCompare := true
    | .assertConstraint _ =>
        if sawCompare then orderOk := true
    | _ => pure ()
  expect orderOk "GuardedCounter ge compare must precede assertConstraint"

  -- Model accept: count=10, delta=3 → post=7, result=7.
  let ok ← liftModel "GuardedCounter ok inputs" <|
    statefulInputs decrement true 10 3 7 true 7
  expectAccept "GuardedCounter 10-3 under assert" decrement ok

  -- Model reject: count=3, delta=5 fails assert (and would underflow).
  let failAssert ← liftModel "GuardedCounter assert-fail inputs" <|
    statefulInputs decrement true 3 5 0 true 0
  expectReject "GuardedCounter assert fails when count < delta" decrement failAssert

  -- Init / view remain comparison-free and still satisfy the lifecycle model.
  let initOk ← liftModel "GuardedCounter init inputs" <|
    statefulInputs initializer false 0 10 10 true 0
  expectAccept "GuardedCounter init" initializer initOk
  let viewOk ← liftModel "GuardedCounter view inputs" <|
    statefulInputs viewRelation true 7 0 7 true 7
  expectAccept "GuardedCounter view" viewRelation viewOk

  -- `.nr` source must contain the comparison and assert surface.
  let files ← do
    let session ← Tests.Language.ParserSession.shared
    let source ← liftResult (← session.selectProgramV1 guardedCounterSourceText
      "<noir-guarded-emit>" "Examples.GuardedCounter" none)
    let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
    let selection ← liftResult <| resolveBuildSelectionV1 TargetId.noir none
    let capability ← liftResult <|
      Targets.resolveEngineeringRequirementsV1 selection compiled
    liftResult <| Targets.Noir.buildFromCapability capability
  let some mainNr := files.find? (fun file =>
      file.path.endsWith "r1-decrement/src/main.nr") |
    throw <| IO.userError "GuardedCounter missing decrement main.nr"
  expect (mainNr.contents.contains ">=")
    "GuardedCounter .nr must render the >= comparison"
  expect (mainNr.contents.contains "assert(")
    "GuardedCounter .nr must render assert"
  expect (mainNr.contents.contains "bool")
    "GuardedCounter .nr must render bool-typed comparison temp"

  -- Deterministic rebuild: two capability lowerings produce byte-identical IR ops.
  let ir2 ← compileIrFromProgramV1 guardedCounterSourceText
    "Examples.GuardedCounter" "<noir-guarded-counter-2>"
  expect (ir.relations.map (·.operations) == ir2.relations.map (·.operations))
    "GuardedCounter IR operations must be byte-deterministic across rebuilds"
  expect (ir.sourcePlan.planHash == ir2.sourcePlan.planHash)
    "GuardedCounter planHash must be deterministic"

private unsafe def checkAllCompareOpsSource : IO Unit := do
  let ir ← compileIrFromProgramV1 allCompareOpsSourceText
    "Examples.AllCompareOps" "<noir-all-compare>"
  let check ← findRelation ir "check"
  let expectedOps : Array Targets.Noir.ComparisonOp :=
    #[.eq, .ne, .lt, .le, .gt, .ge]
  let compares := findOps check (fun op => match op with
    | .compare .. => true
    | _ => false)
  expect (compares.size == 6)
    s!"AllCompareOps must emit six compares, got {compares.size}"
  for i in [0:expectedOps.size] do
    match compares[i]! with
    | .compare op _ _ _ =>
        expect (op == expectedOps[i]!)
          s!"AllCompareOps compare[{i}] must be {repr (expectedOps[i]!)}, got {repr op}"
    | other => throw <| IO.userError s!"AllCompareOps[{i}] not compare: {repr other}"
  let asserts := findOps check isAssertConstraint
  expect (asserts.size == 6)
    s!"AllCompareOps must emit six assertConstraints, got {asserts.size}"

  let files ← do
    let session ← Tests.Language.ParserSession.shared
    let source ← liftResult (← session.selectProgramV1 allCompareOpsSourceText
      "<noir-all-compare-emit>" "Examples.AllCompareOps" none)
    let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
    let selection ← liftResult <| resolveBuildSelectionV1 TargetId.noir none
    let capability ← liftResult <|
      Targets.resolveEngineeringRequirementsV1 selection compiled
    liftResult <| Targets.Noir.buildFromCapability capability
  let some mainNr := files.find? (fun file =>
      file.path.endsWith "r0-check/src/main.nr") |
    throw <| IO.userError "AllCompareOps missing check main.nr"
  for symbol in #["==", "!=", "<", "<=", ">", ">="] do
    expect (mainNr.contents.contains symbol)
      s!"AllCompareOps .nr must contain comparison symbol {symbol}"
  expect (mainNr.contents.contains "assert(")
    "AllCompareOps .nr must render assert"

  -- Satisfying witness: a == b makes only eq/le/ge succeed; full path needs all six.
  -- Use a=5, b=5: eq, le, ge true; ne, lt, gt false → first failing assert is ne.
  let equal ← liftModel "AllCompareOps equal inputs" <|
    privateSumInputs check #[5, 5] 5
  expectReject "AllCompareOps equal operands fail ne" check equal
  -- a=5, b=3: ne, gt, ge true; eq, lt, le false → fails on eq first.
  let greater ← liftModel "AllCompareOps greater inputs" <|
    privateSumInputs check #[5, 3] 5
  expectReject "AllCompareOps greater operands fail eq" check greater

private unsafe def expectProductClosed (label sourceText moduleName path : String) :
    IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgramV1 sourceText path moduleName none with
  | .error e =>
      expect (e.code.startsWith "PF-")
        s!"{label} selectProgramV1 must fail closed with PF-*, got {e.render}"
  | .ok source =>
      match Compiler.compileValidatedSourceV1 source with
      | .error e =>
          expect (e.code.startsWith "PF-")
            s!"{label} product compile must fail closed with PF-*, got {e.render}"
      | .ok compiled =>
          let selection ← liftResult <| resolveBuildSelectionV1 TargetId.noir none
          match Targets.resolveEngineeringRequirementsV1 selection compiled with
          | .error e =>
              expect (e.code.startsWith "PF-")
                s!"{label} capability mint must fail closed with PF-*, got {e.render}"
          | .ok capability =>
              match Targets.Noir.planFromCapability capability with
              | .error e =>
                  expect (e.code == "PF-PLAN-INVARIANT" || e.code.startsWith "PF-")
                    s!"{label} Noir plan must fail closed, got {e.render}"
              | .ok _ =>
                  throw <| IO.userError s!"{label} must not produce a Noir plan"

/-- Wave-A Bool-result positive: planFromCapability succeeds with a bool-typed
    result binding, model accept/reject, and `.nr` result: pub bool surface. -/
private unsafe def checkBoolResultPositive : IO Unit := do
  let ir ← compileIrFromProgramV1 boolResultSourceText
    "Examples.BoolResult" "<noir-bool-result>"
  let check ← findRelation ir "check"
  let resultBindings := check.sourceRelation.inputs.filter fun binding =>
    binding.role == .result
  expect (resultBindings.size == 1 && resultBindings[0]!.type == .bool)
    "BoolResult check must bind a single Bool-typed result public input"
  let compares := findOps check (fun op => match op with
    | .compare .. => true
    | _ => false)
  expect (compares.size == 1)
    s!"BoolResult check must emit exactly one compare, got {compares.size}"
  match compares[0]! with
  | .compare .ge _ _ _ => pure ()
  | other => throw <| IO.userError s!"BoolResult expected ge compare, got {repr other}"
  -- Model accept: a=5, b=3 ⇒ 5 >= 3 is true.
  let ok ← liftModel "BoolResult ok inputs" <|
    privateSumInputsBoolResult check #[5, 3] true
  expectAccept "BoolResult 5 >= 3 accepts true" check ok
  -- Model reject: wrong claimed result.
  let wrong ← liftModel "BoolResult wrong-result inputs" <|
    privateSumInputsBoolResult check #[5, 3] false
  expectReject "BoolResult 5 >= 3 rejects false" check wrong
  -- False path: a=2, b=5 ⇒ false.
  let falseOk ← liftModel "BoolResult false-path inputs" <|
    privateSumInputsBoolResult check #[2, 5] false
  expectAccept "BoolResult 2 >= 5 accepts false" check falseOk
  let falseWrong ← liftModel "BoolResult false-path wrong inputs" <|
    privateSumInputsBoolResult check #[2, 5] true
  expectReject "BoolResult 2 >= 5 rejects true" check falseWrong

  let files ← do
    let session ← Tests.Language.ParserSession.shared
    let source ← liftResult (← session.selectProgramV1 boolResultSourceText
      "<noir-bool-result-emit>" "Examples.BoolResult" none)
    let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
    let selection ← liftResult <| resolveBuildSelectionV1 TargetId.noir none
    let capability ← liftResult <|
      Targets.resolveEngineeringRequirementsV1 selection compiled
    liftResult <| Targets.Noir.buildFromCapability capability
  let some mainNr := files.find? (fun file =>
      file.path.endsWith "r0-check/src/main.nr") |
    throw <| IO.userError "BoolResult missing check main.nr"
  expect (mainNr.contents.contains "result: pub bool")
    "BoolResult .nr must declare result: pub bool"
  expect (mainNr.contents.contains "assert(result ==")
    "BoolResult .nr must bind result with assert(result =="
  expect (mainNr.contents.contains "let t")
    "BoolResult .nr must render a typed comparison temp"
  expect (mainNr.contents.contains ">=")
    "BoolResult .nr must render the >= comparison"
  let some interface := files.find? (fun file =>
      file.path.endsWith ".noir-relations.json") |
    throw <| IO.userError "BoolResult missing relations JSON"
  expect (interface.contents.contains "\"type\":\"bool\"")
    "BoolResult ABI metadata must carry bool result type"

  let ir2 ← compileIrFromProgramV1 boolResultSourceText
    "Examples.BoolResult" "<noir-bool-result-2>"
  expect (ir.sourcePlan.planHash == ir2.sourcePlan.planHash)
    "BoolResult planHash must be deterministic"
  expect (ir.relations.map (·.operations) == ir2.relations.map (·.operations))
    "BoolResult IR ops must be byte-identical across rebuilds"

/-- End-to-end BoolPredicate: UInt64 entry + Bool view/entry results. -/
private unsafe def checkBoolPredicateProduct : IO Unit := do
  let ir ← compileIrFromProgramV1 boolPredicateSourceText
    "Examples.BoolPredicate" "<noir-bool-predicate>"
  let initializer ← findRelation ir "init"
  let setEntry ← findRelation ir "set"
  let positive ← findRelation ir "positive"
  let equalsCount ← findRelation ir "equalsCount"

  -- Relation result types.
  let setResult := setEntry.sourceRelation.inputs.filter (·.role == .result)
  expect (setResult.size == 1 && setResult[0]!.type == .u64)
    "BoolPredicate set must keep UInt64 result"
  let positiveResult := positive.sourceRelation.inputs.filter (·.role == .result)
  expect (positiveResult.size == 1 && positiveResult[0]!.type == .bool)
    "BoolPredicate positive must bind Bool result"
  let equalsResult := equalsCount.sourceRelation.inputs.filter (·.role == .result)
  expect (equalsResult.size == 1 && equalsResult[0]!.type == .bool)
    "BoolPredicate equalsCount must bind Bool result"

  -- Model: init + UInt64 set still work.
  let initOk ← liftModel "BoolPredicate init inputs" <|
    statefulInputs initializer false 0 10 10 true 0
  expectAccept "BoolPredicate init" initializer initOk
  let setOk ← liftModel "BoolPredicate set inputs" <|
    statefulInputs setEntry true 10 7 7 true 7
  expectAccept "BoolPredicate set 10→7" setEntry setOk

  -- positive view: count > 0.
  let posTrue ← liftModel "BoolPredicate positive true inputs" <|
    statefulInputsBoolResult positive true 7 0 7 true true
  expectAccept "BoolPredicate positive(count=7) true" positive posTrue
  let posFalse ← liftModel "BoolPredicate positive false inputs" <|
    statefulInputsBoolResult positive true 0 0 0 true false
  expectAccept "BoolPredicate positive(count=0) false" positive posFalse
  let posWrong ← liftModel "BoolPredicate positive wrong inputs" <|
    statefulInputsBoolResult positive true 0 0 0 true true
  expectReject "BoolPredicate positive(count=0) rejects true" positive posWrong

  -- equalsCount: count == d.
  let eqTrue ← liftModel "BoolPredicate equals true inputs" <|
    statefulInputsBoolResult equalsCount true 7 7 7 true true
  expectAccept "BoolPredicate equalsCount(7,7) true" equalsCount eqTrue
  let eqFalse ← liftModel "BoolPredicate equals false inputs" <|
    statefulInputsBoolResult equalsCount true 7 3 7 true false
  expectAccept "BoolPredicate equalsCount(7,3) false" equalsCount eqFalse
  let eqWrong ← liftModel "BoolPredicate equals wrong inputs" <|
    statefulInputsBoolResult equalsCount true 7 3 7 true true
  expectReject "BoolPredicate equalsCount(7,3) rejects true" equalsCount eqWrong

  -- `.nr` surface for Bool relations.
  let files ← do
    let session ← Tests.Language.ParserSession.shared
    let source ← liftResult (← session.selectProgramV1 boolPredicateSourceText
      "<noir-bool-predicate-emit>" "Examples.BoolPredicate" none)
    let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
    let selection ← liftResult <| resolveBuildSelectionV1 TargetId.noir none
    let capability ← liftResult <|
      Targets.resolveEngineeringRequirementsV1 selection compiled
    liftResult <| Targets.Noir.buildFromCapability capability
  let some positiveNr := files.find? (fun file =>
      file.path.endsWith "r2-positive/src/main.nr") |
    throw <| IO.userError "BoolPredicate missing positive main.nr"
  expect (positiveNr.contents.contains "result: pub bool")
    "BoolPredicate positive .nr must declare result: pub bool"
  expect (positiveNr.contents.contains "assert(result ==")
    "BoolPredicate positive .nr must bind result with assert(result =="
  let some equalsNr := files.find? (fun file =>
      file.path.endsWith "r3-equalsCount/src/main.nr") |
    throw <| IO.userError "BoolPredicate missing equalsCount main.nr"
  expect (equalsNr.contents.contains "result: pub bool")
    "BoolPredicate equalsCount .nr must declare result: pub bool"
  expect (equalsNr.contents.contains "assert(result ==")
    "BoolPredicate equalsCount .nr must bind result with assert(result =="
  expect (equalsNr.contents.contains "==")
    "BoolPredicate equalsCount .nr must render equality comparison"

  -- Deterministic rebuild.
  let ir2 ← compileIrFromProgramV1 boolPredicateSourceText
    "Examples.BoolPredicate" "<noir-bool-predicate-2>"
  expect (ir.sourcePlan.planHash == ir2.sourcePlan.planHash)
    "BoolPredicate planHash must be deterministic"
  expect (ir.relations.map (·.operations) == ir2.relations.map (·.operations))
    "BoolPredicate IR ops must be byte-identical across rebuilds"

private unsafe def checkCompareAssertNegatives : IO Unit := do
  expectProductClosed "Bool state" boolStateSourceText
    "Examples.BoolState" "<noir-bool-state>"
  expectProductClosed "Bool param" boolParamSourceText
    "Examples.BoolParam" "<noir-bool-param>"
  expectProductClosed "Bool result returning UInt64" boolResultReturnsUInt64SourceText
    "Examples.BoolResultU64" "<noir-bool-result-u64>"
  expectProductClosed "UInt64 result returning comparison" uint64ResultReturnsCompareSourceText
    "Examples.U64ResultCompare" "<noir-u64-result-compare>"
  expectProductClosed "assert-else" assertElseSourceText
    "Examples.AssertElse" "<noir-assert-else>"

/-- Existing Counter planHash golden stays green and comparison-free. -/
private unsafe def checkCounterPlanHashUnchanged : IO Unit := do
  let ir ← compileIrFromProgramV1 counterSourceText
    "Examples.Counter" "<noir-counter-hash>"
  -- Comparison-free: no compare / assertConstraint ops on any relation.
  for relation in ir.relations do
    expect (findOps relation (fun op => match op with
        | .compare .. | .assertConstraint _ => true
        | _ => false)).isEmpty
      s!"Counter relation '{relation.sourceRelation.name}' must remain comparison-free"
  -- Deterministic rebuild identity (existing Counter surface).
  let ir2 ← compileIrFromProgramV1 counterSourceText
    "Examples.Counter" "<noir-counter-hash-2>"
  expect (ir.sourcePlan.planHash == ir2.sourcePlan.planHash)
    "Counter planHash must be stable across rebuilds"
  expect (ir.relations.map (·.operations) == ir2.relations.map (·.operations))
    "Counter IR ops must be byte-identical across rebuilds"
  -- Result public inputs remain UInt64 (no accidental Bool result cutover).
  for relation in ir.relations do
    for binding in relation.sourceRelation.inputs do
      if binding.role == .result then
        expect (binding.type == .u64)
          s!"Counter relation '{relation.sourceRelation.name}' result must stay u64"

/-- Wave C branching: if/else diamond, both-return if, early-return with a
    trailing join (previously fail-closed case), match with a bind catch-all,
    and an assert inside a branch arm (constrains only that path). -/
private def branchCounterSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program BranchCounter where\n" ++
  "  state count : UInt64\n\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    if count >= delta then\n" ++
  "      count := count - delta\n" ++
  "    else\n" ++
  "      count := count + delta\n" ++
  "    return count\n\n" ++
  "  entry clamp(limit : UInt64) : UInt64 do\n" ++
  "    if count > limit then\n" ++
  "      return limit\n" ++
  "    else\n" ++
  "      return count\n\n" ++
  "  entry cap(limit : UInt64) : UInt64 do\n" ++
  "    if count > limit then\n" ++
  "      return limit\n" ++
  "    else\n" ++
  "      count := count + 1\n" ++
  "    return count\n\n" ++
  "  entry pick(choice : UInt64) : UInt64 do\n" ++
  "    match choice with\n" ++
  "    | 0 => do\n" ++
  "      count := count + 10\n" ++
  "    | 1 => do\n" ++
  "      count := count + 20\n" ++
  "    | other => do\n" ++
  "      count := other\n" ++
  "    return count\n\n" ++
  "  entry withdraw(amount : UInt64) : UInt64 do\n" ++
  "    if amount > 0 then\n" ++
  "      assert count >= amount\n" ++
  "      count := count - amount\n" ++
  "    return count\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n\n" ++
  "end ProofForgeV2.Examples\n"

private unsafe def checkBranchingProduct : IO Unit := do
  let ir ← compileIrFromProgramV1 branchCounterSourceText
    "Examples.BranchCounter" "<noir-branch-counter>"
  let initializer ← findRelation ir "init"
  let bump ← findRelation ir "bump"
  let clamp ← findRelation ir "clamp"
  let cap ← findRelation ir "cap"
  let pick ← findRelation ir "pick"
  let withdraw ← findRelation ir "withdraw"

  -- Region structure: every mutating entry carries exactly one region op.
  let regionCount : Targets.Noir.RelationIR → Nat := fun relation =>
    relation.operations.foldl (fun total op => total + match op with
      | .ifRegion .. | .switchRegion .. => 1
      | _ => 0) 0
  expect (regionCount bump == 1 && regionCount clamp == 1 &&
      regionCount cap == 1 && regionCount pick == 1 &&
      regionCount withdraw == 1 && regionCount initializer == 0)
    "BranchCounter relations must each carry exactly one region op (init: none)"
  match pick.operations.find? (fun op => match op with
    | .switchRegion .. => true | _ => false) with
  | some (.switchRegion _ _ cases _) =>
      expect (cases.size == 2)
        s!"pick switch must carry two literal cases plus the bind default, got {cases.size}"
  | _ => throw <| IO.userError "pick relation must lower match to a switchRegion"
  match bump.operations.find? (fun op => match op with
    | .ifRegion .. => true | _ => false) with
  | some (.ifRegion _ thenOps elseOps) =>
      expect (!thenOps.isEmpty && !elseOps.isEmpty)
        "bump if-region arms must both be non-empty complete paths"
  | _ => throw <| IO.userError "bump relation must lower the diamond to an ifRegion"

  let initOk ← liftModel "BranchCounter init inputs" <|
    statefulInputs initializer false 0 10 10 true 0
  expectAccept "BranchCounter init" initializer initOk

  -- bump: both diamond paths, state and result per path.
  let bumpSub ← liftModel "BranchCounter bump sub inputs" <|
    statefulInputs bump true 10 3 7 true 7
  expectAccept "BranchCounter bump 10>=3 subtracts" bump bumpSub
  let bumpAdd ← liftModel "BranchCounter bump add inputs" <|
    statefulInputs bump true 3 5 8 true 8
  expectAccept "BranchCounter bump 3<5 adds" bump bumpAdd
  let bumpWrongPost ← liftModel "BranchCounter bump wrong post inputs" <|
    statefulInputs bump true 10 3 8 true 7
  expectReject "BranchCounter bump post-state from the wrong arm" bump bumpWrongPost

  -- clamp: both arms return; state untouched on both paths.
  let clampHigh ← liftModel "BranchCounter clamp high inputs" <|
    statefulInputs clamp true 10 5 10 true 5
  expectAccept "BranchCounter clamp 10>5 returns limit" clamp clampHigh
  let clampLow ← liftModel "BranchCounter clamp low inputs" <|
    statefulInputs clamp true 3 7 3 true 3
  expectAccept "BranchCounter clamp 3<=7 returns count" clamp clampLow
  let clampWrongResult ← liftModel "BranchCounter clamp wrong result inputs" <|
    statefulInputs clamp true 10 5 10 true 10
  expectReject "BranchCounter clamp wrong result on the taken arm" clamp clampWrongResult

  -- cap: early return in the then arm with a trailing join (formerly
  -- fail-closed asymmetric shape); else path stores and falls through.
  let capEarly ← liftModel "BranchCounter cap early inputs" <|
    statefulInputs cap true 10 5 10 true 5
  expectAccept "BranchCounter cap 10>5 early-returns limit" cap capEarly
  let capThrough ← liftModel "BranchCounter cap through inputs" <|
    statefulInputs cap true 3 7 4 true 4
  expectAccept "BranchCounter cap 3<=7 increments through the join" cap capThrough
  let capWrongEarly ← liftModel "BranchCounter cap wrong early inputs" <|
    statefulInputs cap true 10 5 11 true 11
  expectReject "BranchCounter cap early path must not run the join" cap capWrongEarly

  -- pick: literal cases and the bind default arm.
  let pickZero ← liftModel "BranchCounter pick 0 inputs" <|
    statefulInputs pick true 5 0 15 true 15
  expectAccept "BranchCounter pick choice=0 adds 10" pick pickZero
  let pickOne ← liftModel "BranchCounter pick 1 inputs" <|
    statefulInputs pick true 5 1 25 true 25
  expectAccept "BranchCounter pick choice=1 adds 20" pick pickOne
  let pickOther ← liftModel "BranchCounter pick other inputs" <|
    statefulInputs pick true 5 7 7 true 7
  expectAccept "BranchCounter pick choice=7 binds the default arm" pick pickOther
  let pickWrongArm ← liftModel "BranchCounter pick wrong-arm inputs" <|
    statefulInputs pick true 5 2 25 true 25
  expectReject "BranchCounter pick default arm must not take a literal case" pick pickWrongArm

  -- withdraw: the assert inside the arm constrains only that path.
  let withdrawOk ← liftModel "BranchCounter withdraw ok inputs" <|
    statefulInputs withdraw true 10 3 7 true 7
  expectAccept "BranchCounter withdraw 10-3 under branch assert" withdraw withdrawOk
  let withdrawSkip ← liftModel "BranchCounter withdraw skip inputs" <|
    statefulInputs withdraw true 10 0 10 true 10
  expectAccept "BranchCounter withdraw amount=0 skips the assert" withdraw withdrawSkip
  let withdrawTrap ← liftModel "BranchCounter withdraw trap inputs" <|
    statefulInputs withdraw true 3 5 0 true 0
  expectReject "BranchCounter withdraw 3<5 fails the branch assert" withdraw withdrawTrap

  -- `.nr` surface: if/else and else-if chains with per-path asserts.
  let files ← do
    let session ← Tests.Language.ParserSession.shared
    let source ← liftResult (← session.selectProgramV1 branchCounterSourceText
      "<noir-branch-emit>" "Examples.BranchCounter" none)
    let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
    let selection ← liftResult <| resolveBuildSelectionV1 TargetId.noir none
    let capability ← liftResult <|
      Targets.resolveEngineeringRequirementsV1 selection compiled
    liftResult <| Targets.Noir.buildFromCapability capability
  let some bumpNr := files.find? (fun file =>
    file.path.endsWith "r1-bump/src/main.nr") |
    throw <| IO.userError "BranchCounter missing bump main.nr"
  expect (bumpNr.contents.contains "if t")
    "BranchCounter bump .nr must render the branch condition temp"
  expect (bumpNr.contents.contains "} else {")
    "BranchCounter bump .nr must render the else arm"
  expect ((bumpNr.contents.splitOn "assert(post_s0 ==").length == 3)
    "BranchCounter bump .nr must bind post-state inside both path leaves"
  let some pickNr := files.find? (fun file =>
    file.path.endsWith "r4-pick/src/main.nr") |
    throw <| IO.userError "BranchCounter missing pick main.nr"
  expect (pickNr.contents.contains "else if")
    "BranchCounter pick .nr must render the switch as an else-if chain"
  expect ((pickNr.contents.contains "== 0") && (pickNr.contents.contains "== 1"))
    "BranchCounter pick .nr must render literal case comparisons"

  -- Deterministic rebuild.
  let ir2 ← compileIrFromProgramV1 branchCounterSourceText
    "Examples.BranchCounter" "<noir-branch-counter-2>"
  expect (ir.sourcePlan.planHash == ir2.sourcePlan.planHash)
    "BranchCounter planHash must be deterministic"
  expect (ir.relations.map (·.operations) == ir2.relations.map (·.operations))
    "BranchCounter IR ops must be byte-identical across rebuilds"

/-- Declared event/error: emit binds verifier-visible event slots per path
    (zero on non-executing paths); revert marks its path inadmissible. -/
private def emitRevertSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program EventFlow where\n" ++
  "  state count : UInt64\n\n" ++
  "  event Moved(src : UInt64, dst : UInt64)\n" ++
  "  error Cap(limit : UInt64)\n\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    emit Moved(count, delta)\n" ++
  "    if count > delta then\n" ++
  "      revert Cap(delta)\n" ++
  "    else\n" ++
  "      count := count + delta\n" ++
  "    return count\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n\n" ++
  "end ProofForgeV2.Examples\n"

/-- Stateful relation witness extended with event-slot values (keyed by
    (emit index, arg index)). -/
private def statefulInputsWithSlots (relation : Targets.Noir.RelationIR)
    (preInitialized : Bool) (preState parameter postState : U64)
    (postInitialized : Bool) (result : U64)
    (slots : Array (Nat × Nat × U64)) : Except String (Array ModelValue) :=
  bindInputs relation fun role => match role with
    | .preInitialized => some <| .bool preInitialized
    | .preState _ => some <| .u64 preState
    | .parameter _ => some <| .u64 parameter
    | .postState _ => some <| .u64 postState
    | .postInitialized => some <| .bool postInitialized
    | .result => some <| .u64 result
    | .eventSlot emitIndex argIndex =>
        (slots.find? fun (e, a, _) => e == emitIndex && a == argIndex).map
          fun (_, _, value) => ModelValue.u64 value

private unsafe def checkEmitRevertProduct : IO Unit := do
  let ir ← compileIrFromProgramV1 emitRevertSourceText
    "Examples.EventFlow" "<noir-event-flow>"
  let bump ← findRelation ir "bump"
  let eventSlots := bump.sourceRelation.inputs.filter fun binding =>
    match binding.role with | .eventSlot .. => true | _ => false
  expect (eventSlots.size == 2 &&
      eventSlots.all (·.visibility == .verifier) &&
      eventSlots.all (·.type == .u64))
    "EventFlow bump must bind two verifier-visible u64 event slots"
  expect (eventSlots.map (·.name) == #["ev_e0_a0", "ev_e0_a1"])
    "EventFlow event slots must use canonical effect-arg names"
  let hasRevert := bump.operations.any fun op =>
    match op with
    | .ifRegion _ thenOps _ =>
        thenOps.any fun inner =>
          match inner with | .assertConstraint (.literal 0) => true | _ => false
    | _ => false
  expect hasRevert "EventFlow revert path must be marked inadmissible in the then arm"

  -- Else path: delta=7 > count=5 → post=12, result=12, slots=(5,7).
  let elseOk ← liftModel "EventFlow else inputs" <|
    statefulInputsWithSlots bump true 5 7 12 true 12 #[(0, 0, 5), (0, 1, 7)]
  expectAccept "EventFlow else path binds event slots" bump elseOk
  let elseWrongSlot ← liftModel "EventFlow wrong slot inputs" <|
    statefulInputsWithSlots bump true 5 7 12 true 12 #[(0, 0, 5), (0, 1, 8)]
  expectReject "EventFlow rejects a wrong event slot" bump elseWrongSlot
  -- Then path: delta=3 < count=5 → revert: no admissible witness exists.
  let revertAny ← liftModel "EventFlow revert inputs" <|
    statefulInputsWithSlots bump true 5 3 5 true 3 #[(0, 0, 0), (0, 1, 0)]
  expectReject "EventFlow revert path is inadmissible" bump revertAny
  let revertSlots ← liftModel "EventFlow revert slot inputs" <|
    statefulInputsWithSlots bump true 5 3 8 true 3 #[(0, 0, 5), (0, 1, 3)]
  expectReject "EventFlow revert path stays inadmissible for any slots" bump revertSlots

  -- `.nr` surface: slot inputs and the inadmissible assert.
  let files ← do
    let session ← Tests.Language.ParserSession.shared
    let source ← liftResult (← session.selectProgramV1 emitRevertSourceText
      "<noir-event-flow-emit>" "Examples.EventFlow" none)
    let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
    let selection ← liftResult <| resolveBuildSelectionV1 TargetId.noir none
    let capability ← liftResult <|
      Targets.resolveEngineeringRequirementsV1 selection compiled
    liftResult <| Targets.Noir.buildFromCapability capability
  let some bumpNr := files.find? (fun file =>
      file.path.endsWith "r1-bump/src/main.nr") |
    throw <| IO.userError "EventFlow missing bump main.nr"
  expect (bumpNr.contents.contains "ev_e0_a0: pub u64" &&
      bumpNr.contents.contains "ev_e0_a1: pub u64")
    "EventFlow .nr must declare the event slot public inputs"
  expect (bumpNr.contents.contains "assert(false)")
    "EventFlow .nr must render the revert path as assert(false)"
  expect (bumpNr.contents.contains "assert(ev_e0_a0 ==")
    "EventFlow .nr must bind the event slot on executing paths"

/-- Pure-fn inlining: nested fn→fn calls and an fn revert path. The check fn
    inlines into the bump relation with a result-selecting if expression;
    the revert arm is inadmissible. -/
private def fnFlowSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program FnFlow where\n" ++
  "  state count : UInt64\n\n" ++
  "  error Cap(limit : UInt64)\n\n" ++
  "  fn double(x : UInt64) : UInt64 do\n" ++
  "    return x + x\n\n" ++
  "  fn check(x : UInt64, lim : UInt64) : UInt64 do\n" ++
  "    if x > lim then\n" ++
  "      revert Cap(lim)\n" ++
  "    else\n" ++
  "      return double(x)\n\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    count := check(delta, 10) + double(count)\n" ++
  "    return count\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n\n" ++
  "end ProofForgeV2.Examples\n"

private unsafe def checkFnLocalCallProduct : IO Unit := do
  let ir ← compileIrFromProgramV1 fnFlowSourceText
    "Examples.FnFlow" "<noir-fn-flow>"
  let bump ← findRelation ir "bump"
  let selects := bump.operations.filter fun op =>
    match op with | .selectRegion .. => true | _ => false
  expect (selects.size == 1)
    s!"FnFlow bump must inline check as one select region, got {selects.size}"
  match selects[0]! with
  | .selectRegion _ _ resultIsBool thenOps _ elseOps _ =>
      expect (!resultIsBool) "FnFlow select must be u64-typed"
      let hasRevert := thenOps.any fun op =>
        match op with | .assertConstraint (.literal 0) => true | _ => false
      expect hasRevert "FnFlow revert arm must be inadmissible"
      let hasNestedAdd := elseOps.any fun op =>
        match op with | .checkedAdd .. => true | _ => false
      expect hasNestedAdd "FnFlow else arm must inline double's add"
  | _ => throw <| IO.userError "FnFlow: expected a selectRegion"
  -- delta=4 ≤ 10: check → double(4)=8; double(count)=6; post=14, result=14.
  let ok ← liftModel "FnFlow ok inputs" <|
    statefulInputs bump true 3 4 14 true 14
  expectAccept "FnFlow delta=4 accepts" bump ok
  let wrong ← liftModel "FnFlow wrong inputs" <|
    statefulInputs bump true 3 4 14 true 13
  expectReject "FnFlow wrong result rejects" bump wrong
  -- delta=20 > 10: check reverts Cap(10) → inadmissible for any witness.
  let reverting ← liftModel "FnFlow revert inputs" <|
    statefulInputs bump true 3 20 3 true 20
  expectReject "FnFlow revert path is inadmissible" bump reverting
  let reverting2 ← liftModel "FnFlow revert inputs 2" <|
    statefulInputs bump true 3 20 43 true 43
  expectReject "FnFlow revert path stays inadmissible" bump reverting2

  let files ← do
    let session ← Tests.Language.ParserSession.shared
    let source ← liftResult (← session.selectProgramV1 fnFlowSourceText
      "<noir-fn-flow-emit>" "Examples.FnFlow" none)
    let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
    let selection ← liftResult <| resolveBuildSelectionV1 TargetId.noir none
    let capability ← liftResult <|
      Targets.resolveEngineeringRequirementsV1 selection compiled
    liftResult <| Targets.Noir.buildFromCapability capability
  let some bumpNr := files.find? (fun file =>
      file.path.endsWith "r1-bump/src/main.nr") |
    throw <| IO.userError "FnFlow missing bump main.nr"
  expect (bumpNr.contents.contains "let t" && bumpNr.contents.contains ": u64 = if")
    "FnFlow .nr must render the select as a block-valued if expression"
  expect (bumpNr.contents.contains "assert(false)")
    "FnFlow .nr must render the fn revert arm as assert(false)"

/-- Mul/div/mod/unary lowering: checked multiplication overflow, division and
    remainder zero guards, bitwise NOT, and Bool NOT in a view result. -/
private def arithFlowSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program ArithFlow where\n" ++
  "  state count : UInt64\n\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n\n" ++
  "  entry scale(factor : UInt64) : UInt64 do\n" ++
  "    count := count * factor / 3 + count % 3\n" ++
  "    return count\n\n" ++
  "  entry clip(divisor : UInt64) : UInt64 do\n" ++
  "    count := count / divisor + count % divisor\n" ++
  "    return count\n\n" ++
  "  entry mask(value : UInt64) : UInt64 do\n" ++
  "    count := ~value\n" ++
  "    return count\n\n" ++
  "  view parity() : Bool do\n" ++
  "    return !(count % 2 == 0)\n\n" ++
  "end ProofForgeV2.Examples\n"

private unsafe def checkArithOpsProduct : IO Unit := do
  let ir ← compileIrFromProgramV1 arithFlowSourceText
    "Examples.ArithFlow" "<noir-arith-flow>"
  let scale ← findRelation ir "scale"
  let clip ← findRelation ir "clip"
  let mask ← findRelation ir "mask"
  let parity ← findRelation ir "parity"

  -- scale: mul → div → mod → add op order on `count * factor / 3 + count % 3`.
  let arithOps := scale.operations.filter fun op =>
    match op with
    | .checkedMul .. | .checkedDiv .. | .checkedMod .. | .checkedAdd .. => true
    | _ => false
  expect (arithOps.size == 4)
    s!"ArithFlow scale must emit four arithmetic ops, got {arithOps.size}"
  match arithOps[0]!, arithOps[1]!, arithOps[2]!, arithOps[3]! with
  | .checkedMul .., .checkedDiv .., .checkedMod .., .checkedAdd .. => pure ()
  | _, _, _, _ =>
      throw <| IO.userError "ArithFlow scale op order must be mul/div/mod/add"
  -- scale accept: 6*4=24, 24/3=8, 6%3=0 → post=8, result=8.
  let scaleOk ← liftModel "ArithFlow scale ok inputs" <|
    statefulInputs scale true 6 4 8 true 8
  expectAccept "ArithFlow scale 6,4 accepts" scale scaleOk
  let scaleWrong ← liftModel "ArithFlow scale wrong inputs" <|
    statefulInputs scale true 6 4 8 true 9
  expectReject "ArithFlow scale wrong result rejects" scale scaleWrong
  -- scale mul overflow: 2^63 * 4 exceeds UInt64 for any witness.
  let scaleOverflow ← liftModel "ArithFlow scale overflow inputs" <|
    statefulInputs scale true 9223372036854775808 4 0 true 0
  expectReject "ArithFlow scale mul overflow is inadmissible" scale scaleOverflow

  -- clip accept: 17/5=3, 17%5=2 → post=5, result=5.
  let clipOk ← liftModel "ArithFlow clip ok inputs" <|
    statefulInputs clip true 17 5 5 true 5
  expectAccept "ArithFlow clip 17,5 accepts" clip clipOk
  -- clip divisor=0: division guard rejects any witness.
  let clipZero ← liftModel "ArithFlow clip zero inputs" <|
    statefulInputs clip true 17 0 0 true 0
  expectReject "ArithFlow clip division by zero is inadmissible" clip clipZero

  -- mask accept: ~5 = 2^64 - 6.
  let maskOk ← liftModel "ArithFlow mask ok inputs" <|
    statefulInputs mask true 0 5 18446744073709551610 true 18446744073709551610
  expectAccept "ArithFlow mask ~5 accepts" mask maskOk
  let maskWrong ← liftModel "ArithFlow mask wrong inputs" <|
    statefulInputs mask true 0 5 18446744073709551611 true 18446744073709551611
  expectReject "ArithFlow mask wrong complement rejects" mask maskWrong

  -- parity: !(count % 2 == 0); odd state is true, even state is false.
  let parityOdd ← liftModel "ArithFlow parity odd inputs" <|
    statefulInputsBoolResult parity true 7 0 7 true true
  expectAccept "ArithFlow parity(count=7) true" parity parityOdd
  let parityEven ← liftModel "ArithFlow parity even inputs" <|
    statefulInputsBoolResult parity true 8 0 8 true false
  expectAccept "ArithFlow parity(count=8) false" parity parityEven
  let parityWrong ← liftModel "ArithFlow parity wrong inputs" <|
    statefulInputsBoolResult parity true 7 0 7 true false
  expectReject "ArithFlow parity(count=7) rejects false" parity parityWrong

  -- `.nr` surface: guards and unary forms.
  let files ← do
    let session ← Tests.Language.ParserSession.shared
    let source ← liftResult (← session.selectProgramV1 arithFlowSourceText
      "<noir-arith-emit>" "Examples.ArithFlow" none)
    let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
    let selection ← liftResult <| resolveBuildSelectionV1 TargetId.noir none
    let capability ← liftResult <|
      Targets.resolveEngineeringRequirementsV1 selection compiled
    liftResult <| Targets.Noir.buildFromCapability capability
  let some scaleNr := files.find? (fun file =>
      file.path.endsWith "r1-scale/src/main.nr") |
    throw <| IO.userError "ArithFlow missing scale main.nr"
  expect (scaleNr.contents.contains " * " && scaleNr.contents.contains " / " &&
      scaleNr.contents.contains " % ")
    "ArithFlow scale .nr must render mul/div/mod operators"
  let some clipNr := files.find? (fun file =>
      file.path.endsWith "r2-clip/src/main.nr") |
    throw <| IO.userError "ArithFlow missing clip main.nr"
  expect (clipNr.contents.contains "assert(arg_p0 != 0);")
    "ArithFlow clip .nr must guard the divisor against zero"
  let some maskNr := files.find? (fun file =>
      file.path.endsWith "r3-mask/src/main.nr") |
    throw <| IO.userError "ArithFlow missing mask main.nr"
  expect (maskNr.contents.contains ": u64 = !")
    "ArithFlow mask .nr must render bitwise NOT on u64"
  let some parityNr := files.find? (fun file =>
      file.path.endsWith "r4-parity/src/main.nr") |
    throw <| IO.userError "ArithFlow missing parity main.nr"
  expect (parityNr.contents.contains ": bool = !")
    "ArithFlow parity .nr must render Bool NOT"

unsafe def run : IO Unit := do
  runCheckedSubFast
  runCompareAssertFast
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
  checkGuardedCounterProduct
  checkAllCompareOpsSource
  checkBoolResultPositive
  checkBoolPredicateProduct
  checkCompareAssertNegatives
  checkCounterPlanHashUnchanged
  checkPrivateSum4ResidualRelationModel
  checkPrivateSum4ProductClosed
  checkBranchingProduct
  checkEmitRevertProduct
  checkFnLocalCallProduct
  checkArithOpsProduct

end Tests.Materialization.NoirRelationModel
