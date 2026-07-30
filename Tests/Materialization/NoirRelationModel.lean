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

private def terminalIfSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program NoirIf where\n" ++
  "  view choose() : UInt64 do\n" ++
  "    if true then\n" ++
  "      return 7\n" ++
  "    else\n" ++
  "      return 9\n\n" ++
  "end ProofForgeV2.Examples\n"

private def terminalSwitchSourceText : String :=
  "import ProofForgeV2\nnamespace ProofForgeV2.Examples\nopen ProofForgeV2.Language\n" ++
  "program NoirMatch where\n  state n : UInt64\n  init(i : UInt64) do\n    n := i\n" ++
  "  view choose() : UInt64 do\n    match n with\n    | 7 => do\n      return 3\n" ++
  "    | _ => do\n      return 4\n" ++
  "end ProofForgeV2.Examples\n"

private def statefulIfSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program NoirStateIf where\n" ++
  "  state count : UInt64\n\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n\n" ++
  "  entry adjust() : UInt64 do\n" ++
  "    if count >= 5 then\n" ++
  "      count := count + 1\n" ++
  "      return count\n" ++
  "    else\n" ++
  "      count := count + 2\n" ++
  "      return count\n\n" ++
  "end ProofForgeV2.Examples\n"

private def joinIfSourceText : String :=
  "import ProofForgeV2\nnamespace ProofForgeV2.Examples\nopen ProofForgeV2.Language\n" ++
  "program NoirJoinIf where\n  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n    count := initial\n" ++
  "  entry adjust() : UInt64 do\n    if count >= 5 then\n      count := count + 1\n" ++
  "    else\n      count := count + 2\n    count := count + 10\n    return count\n" ++
  "end ProofForgeV2.Examples\n"

private def phiJoinIfSourceText : String :=
  "import ProofForgeV2\nnamespace ProofForgeV2.Examples\nopen ProofForgeV2.Language\n" ++
  "program NoirPhiJoinIf where\n  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n    count := initial\n" ++
  "  entry adjust() : UInt64 do\n    let next : UInt64 := 0\n    if count >= 5 then\n      next := count + 1\n" ++
  "    else\n      next := count + 2\n    count := next + 10\n    return count\n" ++
  "end ProofForgeV2.Examples\n"

private def malformedIfSourceText : String :=
  "import ProofForgeV2\nnamespace ProofForgeV2.Examples\nopen ProofForgeV2.Language\n" ++
  "program NoirMalformedIf where\n" ++
  "  entry choose() : UInt64 do\n" ++
  "    if true then\n      return 1\n    else\n      assert true\n" ++
  "end ProofForgeV2.Examples\n"

private def nestedIfSourceText : String :=
  "import ProofForgeV2\nnamespace ProofForgeV2.Examples\nopen ProofForgeV2.Language\n" ++
  "program NoirNestedIf where\n" ++
  "  entry choose() : UInt64 do\n" ++
  "    if true then\n      if false then\n        return 1\n      else\n        return 2\n" ++
  "    else\n      return 3\nend ProofForgeV2.Examples\n"

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
  | .conditional condition thenOps elseOps => do
      let value ← readValue machine condition
      let mut next := machine
      for operation in (if value != 0 then thenOps else elseOps) do
        next ← step next operation
      pure next

private partial def runOperations :
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
  let relation : Targets.Noir.RelationIR := {
    sourceRelation := {
      index := 0, name := "branch", artifactStem := "r0-branch", mode := .view
      params := #[], inputs := #[], body := #[]
    }
    tempCount := 1
    operations := #[.conditional (.literal 1)
      #[.checkedAdd 0 (.literal 2) (.literal 3), .assertEqual (.temp 0) (.literal 5)]
      #[.assertConstraint (.literal 0)]]
  }
  expectAccept "structured conditional true arm" relation #[]
  let mutated := { relation with operations := #[.conditional (.literal 0)
    #[.assertConstraint (.literal 1)] #[.assertConstraint (.literal 0)]] }
  expectReject "structured conditional condition mutation" mutated #[]
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

private unsafe def checkTerminalIfProduct : IO Unit := do
  let ir ← compileIrFromProgramV1 terminalIfSourceText
    "Examples.NoirIf" "<noir-terminal-if>"
  let choose ← findRelation ir "choose"
  match choose.operations with
  | #[.conditional (.literal 1) thenOps elseOps] =>
      expect (!thenOps.isEmpty && !elseOps.isEmpty)
        "Noir terminal-if must retain both structured arms"
  | operations =>
      throw <| IO.userError s!"unexpected Noir terminal-if IR: {repr operations}"
  let sourceRelation := choose.sourceRelation
  let expectConditionalMutationRejected (label : String)
      (mutated : Targets.Noir.Relation) : IO Unit := do
    let unsignedPlan := { ir.sourcePlan with relations := ir.sourcePlan.relations.map fun
      (relation : Targets.Noir.Relation) =>
      if relation.name == "choose" then mutated else relation }
    let mutatedPlan := { unsignedPlan with
      planHash := Targets.Noir.canonicalPlanHash unsignedPlan }
    match Targets.Noir.validatePlan mutatedPlan with
    | .error _ => pure ()
    | .ok _ => throw <| IO.userError s!"Noir Plan accepted {label}"
  let parameterizedConditional := {
    sourceRelation with
    params := #[({ sourceId := 0, name := "value", inputIndex := 0, visibility := .verifier } : Targets.Noir.Param)]
  }
  expectConditionalMutationRejected "a parameterized singleton conditional" parameterizedConditional
  expectConditionalMutationRejected "a prefix plus conditional"
    { sourceRelation with body := #[.assert (.literal 1), sourceRelation.body[0]!] }
  expectConditionalMutationRejected "a nested conditional"
    { sourceRelation with body := #[.conditional (.literal 1)
        #[.conditional (.literal 1) #[.returnValue (.literal 1)]
          #[.returnValue (.literal 2)]]
        #[.returnValue (.literal 3)]] }
  expectConditionalMutationRejected "a non-Bool conditional condition"
    { sourceRelation with body := #[.conditional (.checkedAdd (.literal 1) (.literal 1))
        #[.returnValue (.literal 1)] #[.returnValue (.literal 2)]] }
  expectConditionalMutationRejected "a non-Bool conditional-arm assert"
    { sourceRelation with body := #[.conditional (.literal 1)
        #[.assert (.literal 7), .returnValue (.literal 1)]
        #[.returnValue (.literal 2)]] }
  expectConditionalMutationRejected "a Bool conditional-arm return"
    { sourceRelation with body := #[.conditional (.literal 1)
        #[.returnValue (.compare .eq (.literal 1) (.literal 1))]
        #[.returnValue (.literal 2)]] }
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1 terminalIfSourceText
    "<noir-terminal-if-render>" "Examples.NoirIf" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.noir none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let files ← liftResult <| Targets.Noir.buildFromCapability capability
  let some mainNr := files.find? (fun file => file.path.endsWith "r0-choose/src/main.nr") |
    throw <| IO.userError "NoirIf missing choose main.nr"
  expect (mainNr.contents.contains "if " && mainNr.contents.contains "} else {")
    "Noir terminal-if source must render deterministic structured control flow"

private unsafe def checkTerminalSwitchProduct : IO Unit := do
  let ir ← compileIrFromProgramV1 terminalSwitchSourceText "Examples.NoirMatch" "<noir-match>"
  let choose ← findRelation ir "choose"
  expect (choose.sourceRelation.body == #[.conditional (.compare .eq (.stateLoad 0) (.literal 7))
    #[.returnValue (.literal 3)] #[.returnValue (.literal 4)]]) "Noir exact switch Plan"
  let hit ← liftModel "Noir switch hit" <| statefulInputs choose true 7 0 7 true 3
  expectAccept "Noir switch case" choose hit
  let fallback ← liftModel "Noir switch default" <| statefulInputs choose true 8 0 8 true 4
  expectAccept "Noir switch default" choose fallback
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1 terminalSwitchSourceText
    "<noir-match-render>" "Examples.NoirMatch" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.noir none
  let capability ← liftResult <| Targets.resolveEngineeringRequirementsV1 selection compiled
  let files ← liftResult <| Targets.Noir.buildFromCapability capability
  let main := (files.find? (fun f => f.path.endsWith "r1-choose/src/main.nr")).get!.contents
  expect (main.contains "== 7" && main.contains "3" && main.contains "4")
    "Noir render must retain switch equality and both arms"

private unsafe def checkStatefulIfProduct : IO Unit := do
  let ir ← compileIrFromProgramV1 statefulIfSourceText
    "Examples.NoirStateIf" "<noir-state-if>"
  let adjust ← findRelation ir "adjust"
  match adjust.operations.find? (fun op => match op with | .conditional .. => true | _ => false) with
  | some (.conditional (.temp _) thenOps elseOps) =>
      expect (thenOps.any (fun op => match op with | .checkedAdd .. => true | _ => false) &&
          elseOps.any (fun op => match op with | .checkedAdd .. => true | _ => false))
        "stateful conditional arms must retain arithmetic"
  | other => throw <| IO.userError s!"stateful conditional must use computed condition: {repr other}"
  let thenOk ← liftModel "stateful-if then inputs" <|
    statefulInputs adjust true 5 0 6 true 6
  expectAccept "stateful-if selected then arm" adjust thenOk
  let thenWrongState ← liftModel "stateful-if then wrong state" <|
    statefulInputs adjust true 5 0 5 true 6
  expectReject "stateful-if constrains then post-state" adjust thenWrongState
  let elseOk ← liftModel "stateful-if else inputs" <|
    statefulInputs adjust true 3 0 5 true 5
  expectAccept "stateful-if selected else arm" adjust elseOk
  let elseWrongResult ← liftModel "stateful-if else wrong result" <|
    statefulInputs adjust true 3 0 5 true 4
  expectReject "stateful-if constrains else result" adjust elseWrongResult

private unsafe def checkJoinIfProduct : IO Unit := do
  let ir ← compileIrFromProgramV1 joinIfSourceText
    "Examples.NoirJoinIf" "<noir-join-if>"
  let adjust ← findRelation ir "adjust"
  match adjust.sourceRelation.body with
  | #[.conditional _ thenBody elseBody] =>
      expect (thenBody.size >= 3 && elseBody.size >= 3)
        "state-mediated join must duplicate the complete continuation into both arms"
      expect (match thenBody[thenBody.size - 2]?, thenBody.back? with
        | some (.store _), some (.returnValue _) => true | _, _ => false)
        "state-mediated then arm must end in continuation store and return"
      expect (match elseBody[elseBody.size - 2]?, elseBody.back? with
        | some (.store _), some (.returnValue _) => true | _, _ => false)
        "state-mediated else arm must end in continuation store and return"
  | body => throw <| IO.userError s!"unexpected Noir join Plan: {repr body}"
  let thenOk ← liftModel "join-if then inputs" <|
    statefulInputs adjust true 5 0 16 true 16
  expectAccept "join-if true arm feeds continuation" adjust thenOk
  let elseOk ← liftModel "join-if else inputs" <|
    statefulInputs adjust true 3 0 15 true 15
  expectAccept "join-if false arm feeds continuation" adjust elseOk
  let wrong ← liftModel "join-if wrong continuation result" <|
    statefulInputs adjust true 5 0 6 true 6
  expectReject "join-if constrains post-state/result inside the selected arm" adjust wrong
private unsafe def checkPhiJoinIfProduct : IO Unit := do
  let ir ← compileIrFromProgramV1 phiJoinIfSourceText
    "Examples.NoirPhiJoinIf" "<noir-phi-join-if>"
  let adjust ← findRelation ir "adjust"
  match adjust.sourceRelation.body with
  | #[.conditional _ thenBody elseBody] =>
      expect (match thenBody.back?, elseBody.back? with
        | some (.returnValue _), some (.returnValue _) => true | _, _ => false)
        "phi join must duplicate its continuation into both arms"
  | body => throw <| IO.userError s!"unexpected Noir phi join Plan: {repr body}"
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1 phiJoinIfSourceText
    "<noir-phi-join-if-render>" "Examples.NoirPhiJoinIf" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.noir none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let files ← liftResult <| Targets.Noir.buildFromCapability capability
  let some mainNr := files.find? (fun file => file.path.endsWith "r1-adjust/src/main.nr") |
    throw <| IO.userError "NoirPhiJoinIf missing adjust main.nr"
  let armMarker := " + 10;"
  expect ((mainNr.contents.splitOn armMarker).length == 3)
    "join .nr must render continuation arithmetic inside both lexical arms"
  expect ((mainNr.contents.splitOn "} else {").length == 2)
    "join .nr must render one conditional with exactly two lexical arms"
  let afterConditional := (mainNr.contents.splitOn "    }\n").getLast!
  expect (afterConditional == "}\n")
    s!"join .nr must not reference a branch temp after the closing conditional: {afterConditional}"

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
  expectProductClosed "malformed terminal if" malformedIfSourceText
    "Examples.NoirMalformedIf" "<noir-malformed-if>"
  expectProductClosed "nested terminal if" nestedIfSourceText
    "Examples.NoirNestedIf" "<noir-nested-if>"

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

unsafe def run : IO Unit := do
  runCheckedSubFast
  runCompareAssertFast
  checkJoinIfProduct
  checkPhiJoinIfProduct
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
  checkTerminalIfProduct
  checkTerminalSwitchProduct
  checkStatefulIfProduct
  checkCompareAssertNegatives
  checkCounterPlanHashUnchanged
  checkPrivateSum4ResidualRelationModel
  checkPrivateSum4ProductClosed

end Tests.Materialization.NoirRelationModel
