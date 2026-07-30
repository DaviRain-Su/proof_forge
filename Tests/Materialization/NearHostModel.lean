import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Near
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.Materialization.NearHostModel

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1

/-- ProgramV1 Accumulator source for the retained-semantic public UInt64 envelope. -/
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

private def accumulatorModuleNameV1 : String := "Examples.Accumulator"

private abbrev HostStorage := Array (String × ByteArray)
private abbrev U64 := _root_.UInt64

private structure Deposit where
  lowWord : U64
  highWord : U64

private structure Machine where
  storage : HostStorage
  temps : Array (Option U64)
  returned : Option U64 := none

private inductive Outcome where
  | success (storage : HostStorage) (returned : Option U64)
  | trapped (storage : HostStorage) (reason : String)

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def repeatedByte (count : Nat) (value : UInt8) : ByteArray :=
  ByteArray.mk (Array.replicate count value)

private def encodeUInt64LE (value : U64) : ByteArray :=
  ByteArray.mk #[
    value.toUInt8,
    (UInt64.shiftRight value 8).toUInt8,
    (UInt64.shiftRight value 16).toUInt8,
    (UInt64.shiftRight value 24).toUInt8,
    (UInt64.shiftRight value 32).toUInt8,
    (UInt64.shiftRight value 40).toUInt8,
    (UInt64.shiftRight value 48).toUInt8,
    (UInt64.shiftRight value 56).toUInt8
  ]

private def decodeUInt64LEAt (bytes : ByteArray) (offset : Nat) : Option U64 :=
  if offset + 8 > bytes.size then
    none
  else
    some <| Id.run do
      let mut value : U64 := 0
      for index in [0:8] do
        value := value |||
          UInt64.shiftLeft bytes[offset + index]!.toUInt64 (UInt64.ofNat (8 * index))
      return value

private def decodeUInt64LE (bytes : ByteArray) : Option U64 :=
  if bytes.size == 8 then decodeUInt64LEAt bytes 0 else none

private def storageLookup? (storage : HostStorage) (key : String) : Option ByteArray :=
  match storage.find? (fun item => item.1 == key) with
  | some item => some item.2
  | none => none

private def storagePut (storage : HostStorage) (key : String)
    (value : ByteArray) : HostStorage := Id.run do
  let mut result : HostStorage := #[]
  let mut replaced := false
  for item in storage do
    if item.1 == key then
      if !replaced then
        result := result.push (key, value)
      replaced := true
    else
      result := result.push item
  if !replaced then
    result := result.push (key, value)
  return result

private def storageRemove (storage : HostStorage) (key : String) : HostStorage := Id.run do
  let mut result : HostStorage := #[]
  for item in storage do
    unless item.1 == key do
      result := result.push item
  return result

private def modelError (message : String) : Except String α :=
  .error message

private def requireStorage (machine : Machine)
    (region : Targets.Near.KeyRegion) : Except String ByteArray :=
  match storageLookup? machine.storage region.key with
  | some value => .ok value
  | none => modelError s!"missing storage key '{region.key}'"

private def readTemp (machine : Machine) (index : Nat) : Except String U64 :=
  match machine.temps[index]? with
  | some (some value) => .ok value
  | _ => modelError s!"temporary {index} is unavailable"

private def writeTemp (machine : Machine) (index : Nat)
    (value : U64) : Except String Machine :=
  if index < machine.temps.size then
    .ok { machine with temps := machine.temps.set! index (some value) }
  else
    modelError s!"temporary {index} is outside the method frame"

mutual

private partial def step (input : ByteArray) (deposit : Deposit)
    (machine : Machine) : Targets.Near.Operation → Except String Machine
  | .checkInputLen expected =>
      if input.size == expected then .ok machine
      else modelError s!"input length {input.size} does not equal {expected}"
  | .requireZeroAttachedDeposit =>
      if deposit.lowWord == 0 && deposit.highWord == 0 then .ok machine
      else modelError "attached deposit is nonzero"
  | .requireLayoutAbsent marker =>
      if (storageLookup? machine.storage marker.key).isNone then .ok machine
      else modelError "layout marker is already present"
  | .requireLayout marker expected => do
      let encoded ← requireStorage machine marker
      let actual ← match decodeUInt64LE encoded with
        | some value => pure value
        | none => modelError "layout marker is not exactly eight bytes"
      if actual == expected then pure machine
      else modelError "layout marker does not match the Plan"
  | .zeroState field =>
      if (storageLookup? machine.storage field.key).isSome then
        modelError s!"state key '{field.key}' already exists during zero initialization"
      else
        .ok { machine with
          storage := storagePut machine.storage field.key (encodeUInt64LE 0) }
  | .literal destination value =>
      writeTemp machine destination value
  | .loadParam destination inputOffset => do
      let value ← match decodeUInt64LEAt input inputOffset with
        | some value => pure value
        | none => modelError "parameter read is outside the exact input"
      writeTemp machine destination value
  | .loadState destination field => do
      let encoded ← requireStorage machine field
      let value ← match decodeUInt64LE encoded with
        | some value => pure value
        | none => modelError s!"state key '{field.key}' is not exactly eight bytes"
      writeTemp machine destination value
  | .checkedAdd destination lhs rhs => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      let sum := left.toNat + right.toNat
      if sum > 18446744073709551615 then
        modelError "UInt64 addition overflow"
      else
        writeTemp machine destination (UInt64.ofNat sum)
  | .checkedSub destination lhs rhs => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      if left < right then
        modelError "UInt64 subtraction underflow"
      else
        writeTemp machine destination (left - right)
  | .compare destination lhs rhs op => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      let flag : Bool :=
        match op with
        | .eq => left == right
        | .ne => left != right
        | .lt => left < right
        | .le => left ≤ right
        | .gt => left > right
        | .ge => left ≥ right
      writeTemp machine destination (if flag then 1 else 0)
  | .assert condition => do
      let value ← readTemp machine condition
      if value != 0 then
        pure machine
      else
        modelError "assert condition is false"
  | .storeState field source => do
      let previous ← requireStorage machine field
      unless previous.size == 8 do
        modelError s!"evicted state at '{field.key}' is not exactly eight bytes"
      let value ← readTemp machine source
      pure { machine with
        storage := storagePut machine.storage field.key (encodeUInt64LE value) }
  | .setLayout marker value =>
      if (storageLookup? machine.storage marker.key).isSome then
        modelError "layout marker unexpectedly exists before commit"
      else
        .ok { machine with
          storage := storagePut machine.storage marker.key (encodeUInt64LE value) }
  | .setReturnData source => do
      if machine.returned.isSome then
        modelError "return data was already set"
      let value ← readTemp machine source
      pure { machine with returned := some value }
  | .ifRegion condition thenOps elseOps => do
      let value ← readTemp machine condition
      if value != 0 then
        runOperations input deposit thenOps.toList machine
      else
        runOperations input deposit elseOps.toList machine
  | .switchRegion scrutinee cases defaultOps => do
      let scrut ← readTemp machine scrutinee
      let selected := cases.toList.findSome? fun (caseValue, ops) =>
        if caseValue == scrut then some ops else none
      match selected with
      | some ops => runOperations input deposit ops.toList machine
      | none => runOperations input deposit defaultOps.toList machine

private partial def runOperations (input : ByteArray) (deposit : Deposit) :
    List Targets.Near.Operation → Machine → Except String Machine
  | [], machine => .ok machine
  | operation :: remaining, machine =>
      match step input deposit machine operation with
      | .ok next => runOperations input deposit remaining next
      | .error reason => .error reason

end

/-- Pure deterministic model of the typed recipe. A trap restores the exact
pre-call storage snapshot, modeling NEAR's receipt-local rollback contract.
This is not a NEAR VM, sandbox, gas, or protocol-profile execution. -/
private def execute (method : Targets.Near.MethodIR) (storage : HostStorage)
    (input : ByteArray) (deposit : Deposit) : Outcome :=
  let initial : Machine := {
    storage
    temps := Array.replicate method.tempCount none
  }
  match runOperations input deposit method.operations.toList initial with
  | .ok result => .success result.storage result.returned
  | .error reason => .trapped storage reason

private def requireSuccess (label : String) : Outcome → IO (HostStorage × Option U64)
  | .success storage returned => pure (storage, returned)
  | .trapped _ reason => throw <| IO.userError s!"{label} trapped: {reason}"

private def expectTrap (label : String) (snapshot : HostStorage) : Outcome → IO Unit
  | .trapped storage _ =>
      expect (storage == snapshot) s!"{label} did not restore the pre-call storage snapshot"
  | .success .. => throw <| IO.userError s!"{label} unexpectedly succeeded"

private def findMethod (ir : Targets.Near.IR) (name : String) : IO Targets.Near.MethodIR :=
  match ir.methods.find? (fun method => method.name == name) with
  | some method => pure method
  | none => throw <| IO.userError s!"typed NEAR recipe is missing method '{name}'"

private def storedUInt64? (storage : HostStorage) (key : String) : Option U64 :=
  storageLookup? storage key >>= decodeUInt64LE

private def testCheckedSubModel : IO Unit := do
  let deposit : Deposit := { lowWord := 0, highWord := 0 }
  let machine : Machine := {
    storage := #[]
    temps := #[some 7, some 5, none]
  }
  let success ← match step ByteArray.empty deposit machine (.checkedSub 2 0 1) with
    | .ok value => pure value
    | .error reason => throw <| IO.userError s!"checked-sub model: {reason}"
  expect (success.temps[2]? == some (some 2))
    "checked-sub model must write the exact UInt64 difference"
  match step ByteArray.empty deposit machine (.checkedSub 2 1 0) with
  | .error reason =>
      expect (reason.contains "underflow")
        s!"checked-sub model must classify underflow, got {reason}"
  | .ok _ => throw <| IO.userError "checked-sub model accepted 5 - 7"

private def testCompareAssertModel : IO Unit := do
  let deposit : Deposit := { lowWord := 0, highWord := 0 }
  let machine : Machine := {
    storage := #[]
    temps := #[some 7, some 5, none]
  }
  let ops : Array (Targets.Near.ComparisonOp × (U64 → U64 → Bool)) := #[
    (.eq, fun a b => a == b),
    (.ne, fun a b => a != b),
    (.lt, fun a b => a < b),
    (.le, fun a b => a ≤ b),
    (.gt, fun a b => a > b),
    (.ge, fun a b => a ≥ b)
  ]
  for pair in ops do
    let (op, pred) := pair
    let success ← match step ByteArray.empty deposit machine (.compare 2 0 1 op) with
      | .ok value => pure value
      | .error reason => throw <| IO.userError s!"compare model {repr op}: {reason}"
    let expected : U64 := if pred 7 5 then 1 else 0
    expect (success.temps[2]? == some (some expected))
      s!"compare model {repr op} must write the exact UInt64 0/1 flag"
  let trueMachine ← match step ByteArray.empty deposit machine (.compare 2 0 1 .ge) with
    | .ok value => pure value
    | .error reason => throw <| IO.userError s!"compare model ge: {reason}"
  match step ByteArray.empty deposit trueMachine (.assert 2) with
  | .ok _ => pure ()
  | .error reason => throw <| IO.userError s!"assert model true: {reason}"
  let falseMachine ← match step ByteArray.empty deposit machine (.compare 2 1 0 .ge) with
    | .ok value => pure value
    | .error reason => throw <| IO.userError s!"compare model ge-false: {reason}"
  match step ByteArray.empty deposit falseMachine (.assert 2) with
  | .error reason =>
      expect (reason.contains "assert")
        s!"assert model must classify false condition, got {reason}"
  | .ok _ => throw <| IO.userError "assert model accepted a zero condition"

def runCheckedSubFast : IO Unit := do
  testCheckedSubModel
  testCompareAssertModel
  IO.println "Tests.Materialization.NearHostModel.checkedSub: ok"

def runCompareAssertFast : IO Unit := do
  testCompareAssertModel
  IO.println "Tests.Materialization.NearHostModel.compareAssert: ok"

/-- Guarded counter: assert count >= delta before checked subtraction. -/
private def guardedCounterSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program Guarded where\n" ++
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

private def guardedCounterModuleNameV1 : String := "Examples.Guarded"

private def operationKinds (operations : Array Targets.Near.Operation) :
    Array String :=
  operations.map fun op =>
    match op with
    | .checkInputLen _ => "checkInputLen"
    | .requireZeroAttachedDeposit => "requireZeroAttachedDeposit"
    | .requireLayoutAbsent _ => "requireLayoutAbsent"
    | .requireLayout _ _ => "requireLayout"
    | .zeroState _ => "zeroState"
    | .literal _ _ => "literal"
    | .loadParam _ _ => "loadParam"
    | .loadState _ _ => "loadState"
    | .checkedAdd _ _ _ => "checkedAdd"
    | .checkedSub _ _ _ => "checkedSub"
    | .storeState _ _ => "storeState"
    | .setLayout _ _ => "setLayout"
    | .setReturnData _ => "setReturnData"
    | .compare _ _ _ op =>
        match op with
        | .eq => "compare.eq"
        | .ne => "compare.ne"
        | .lt => "compare.lt"
        | .le => "compare.le"
        | .gt => "compare.gt"
        | .ge => "compare.ge"
    | .assert _ => "assert"
    | .ifRegion .. => "ifRegion"
    | .switchRegion .. => "switchRegion"

private def expectContains (haystack needle label : String) : IO Unit :=
  expect (haystack.contains needle) s!"{label}: missing WAT substring {needle}"

/-- If/else multi-block program for the NEAR region lanes. -/
private def ifFlowSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program IfFlow where\n" ++
  "  state count : UInt64\n\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    if count > 0 then\n" ++
  "      count := count + delta\n" ++
  "    else\n" ++
  "      count := delta\n" ++
  "    return count\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n\n" ++
  "end ProofForgeV2.Examples\n"

private unsafe def testIfFlowProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source ← liftResult (← session.selectProgramV1
    ifFlowSourceText "<near-if-flow>"
    "Examples.IfFlow" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  let bump := plan.entries[0]!
  expect (bump.body == #[
      .ifThenElse (.compare .gt (.stateLoad 0) (.literal 0))
        #[.store { fieldIndex := 0, value := .checkedAdd (.stateLoad 0) (.param 0) }]
        #[.store { fieldIndex := 0, value := .param 0 }],
      .returnValue (.stateLoad 0)])
    "IfFlow bump must lower the branch diamond then join return"
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let ir2 ← liftResult <| Targets.Near.irFromCapability capability
  expect (ir == ir2) "IfFlow IR rebuild must be structure-identical"
  let bumpIR ← findMethod ir "bump"
  let regionOps := bumpIR.operations.filter fun op =>
    match op with | .ifRegion .. => true | _ => false
  expect (regionOps.size == 1)
    s!"IfFlow IR must contain exactly one if-region, got {regionOps.size}"
  -- Host-model execution: init(0) → bump(3) takes else (state 3), bump(2) takes then (5).
  let initializer ← findMethod ir "init"
  let get ← findMethod ir "get"
  let field := ir.keys[1]!
  let empty : HostStorage := #[]
  let (storage0, _) ← requireSuccess "if-flow init"
    (execute initializer empty (encodeUInt64LE 0) { lowWord := 0, highWord := 0 })
  let (storage1, ret1) ← requireSuccess "if-flow else"
    (execute bumpIR storage0 (encodeUInt64LE 3) { lowWord := 0, highWord := 0 })
  expect (ret1 == some 3 && storedUInt64? storage1 field.key == some 3)
    "if-flow else branch must store delta (3)"
  let (storage2, ret2) ← requireSuccess "if-flow then"
    (execute bumpIR storage1 (encodeUInt64LE 2) { lowWord := 0, highWord := 0 })
  expect (ret2 == some 5 && storedUInt64? storage2 field.key == some 5)
    "if-flow then branch must store count+delta (5)"
  let (_, retGet) ← requireSuccess "if-flow get"
    (execute get storage2 ByteArray.empty { lowWord := 0, highWord := 0 })
  expect (retGet == some 5) "if-flow view must return 5"
  -- WAT: nested if with i64 condition.
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some wat := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "if-flow: missing .wat artifact"
  expectContains wat.contents "(if (local.get $t" "if-flow WAT if condition"
  expectContains wat.contents "(else" "if-flow WAT else"
  expectContains wat.contents "(i64.gt_u" "if-flow WAT gt comparison"
  expectContains wat.contents "(i64.add" "if-flow WAT then add"

/-- Match on UInt64 literals: host-model switch execution per case. -/
private unsafe def testMatchProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MatchUint where\n" ++
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry apply(delta : UInt64) : UInt64 do\n" ++
    "    match delta with\n" ++
    "    | 0 => do\n" ++
    "      return count\n" ++
    "    | 1 => do\n" ++
    "      count := count + 1\n" ++
    "    | _ => do\n" ++
    "      count := delta\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    text "<near-match>" "Examples.MatchUint" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let applyIR ← findMethod ir "apply"
  let switchOps := applyIR.operations.filter fun op =>
    match op with | .switchRegion .. => true | _ => false
  expect (switchOps.size == 1)
    s!"MatchUint IR must contain exactly one switch-region, got {switchOps.size}"
  let initializer ← findMethod ir "init"
  let field := ir.keys[1]!
  let (storage0, _) ← requireSuccess "match init"
    (execute initializer #[] (encodeUInt64LE 7) { lowWord := 0, highWord := 0 })
  let (storage1, ret1) ← requireSuccess "match case0"
    (execute applyIR storage0 (encodeUInt64LE 0) { lowWord := 0, highWord := 0 })
  expect (ret1 == some 7 && storedUInt64? storage1 field.key == some 7)
    "match case 0 must return count without writing"
  let (storage2, ret2) ← requireSuccess "match case1"
    (execute applyIR storage1 (encodeUInt64LE 1) { lowWord := 0, highWord := 0 })
  expect (ret2 == some 8 && storedUInt64? storage2 field.key == some 8)
    "match case 1 must increment"
  let (storage3, ret3) ← requireSuccess "match default"
    (execute applyIR storage2 (encodeUInt64LE 5) { lowWord := 0, highWord := 0 })
  expect (ret3 == some 5 && storedUInt64? storage3 field.key == some 5)
    "match default must store the scrutinee"
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some wat := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "match: missing .wat artifact"
  expectContains wat.contents "(if (i64.eq" "match WAT case comparison"
  expectContains wat.contents "(else" "match WAT else chain"

/-- Assert inside a branch traps only when that branch is taken. -/
private unsafe def testBranchAssertTrap
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BranchAssert where\n" ++
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry withdraw(delta : UInt64) : UInt64 do\n" ++
    "    if delta > 0 then\n" ++
    "      assert count >= delta\n" ++
    "      count := count - delta\n" ++
    "    else\n" ++
    "      count := 0\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    text "<near-branch-assert>" "Examples.BranchAssert" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let withdraw ← findMethod ir "withdraw"
  let initializer ← findMethod ir "init"
  let field := ir.keys[1]!
  let (storage0, _) ← requireSuccess "branch-assert init"
    (execute initializer #[] (encodeUInt64LE 5) { lowWord := 0, highWord := 0 })
  -- delta=3 → then branch, assert passes, state 2.
  let (storage1, ret1) ← requireSuccess "branch-assert pass"
    (execute withdraw storage0 (encodeUInt64LE 3) { lowWord := 0, highWord := 0 })
  expect (ret1 == some 2 && storedUInt64? storage1 field.key == some 2)
    "branch-assert: taken branch must apply the subtraction"
  -- delta=9 → then branch, assert fails → trap, storage rolled back.
  match execute withdraw storage0 (encodeUInt64LE 9) { lowWord := 0, highWord := 0 } with
  | .trapped restored reason =>
      expect (storedUInt64? restored field.key == some 5)
        s!"branch-assert: trap must roll back to pre-call storage, got {reason}"
  | .success _ _ =>
      throw <| IO.userError "branch-assert: underflowing branch must trap"
  -- delta=0 → else branch, no assert fires, state 0.
  let (storage3, ret3) ← requireSuccess "branch-assert else"
    (execute withdraw storage0 (encodeUInt64LE 0) { lowWord := 0, highWord := 0 })
  expect (ret3 == some 0 && storedUInt64? storage3 field.key == some 0)
    "branch-assert: else branch must not fire the assert"

private unsafe def testGuardedCounterProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source ← liftResult (← session.selectProgramV1
    guardedCounterSourceText "<near-host-guarded>"
    guardedCounterModuleNameV1 none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let ir2 ← liftResult <| Targets.Near.irFromCapability capability
  expect (ir == ir2) "guarded: irFromCapability must be byte-identical on rebuild"
  let initializer ← findMethod ir "init"
  let decrement ← findMethod ir "decrement"
  let get ← findMethod ir "get"
  let field := ir.keys[1]!
  let empty : HostStorage := #[]
  let zeroDeposit : Deposit := { lowWord := 0, highWord := 0 }

  -- Pin method operations: compare.ge then assert before checkedSub.
  let kinds := operationKinds decrement.operations
  expect (kinds.contains "compare.ge")
    s!"guarded: decrement must lower comparison, got {kinds}"
  expect (kinds.contains "assert")
    s!"guarded: decrement must lower assert, got {kinds}"
  expect (kinds.contains "checkedSub")
    s!"guarded: decrement must lower checkedSub, got {kinds}"
  let some geIdx := kinds.findIdx? (· == "compare.ge") |
    throw <| IO.userError "guarded: missing compare.ge index"
  let some assertIdx := kinds.findIdx? (· == "assert") |
    throw <| IO.userError "guarded: missing assert index"
  let some subIdx := kinds.findIdx? (· == "checkedSub") |
    throw <| IO.userError "guarded: missing checkedSub index"
  expect (geIdx < assertIdx && assertIdx < subIdx)
    s!"guarded: expected compare→assert→sub order, got {geIdx}/{assertIdx}/{subIdx}"
  match decrement.operations[geIdx]? with
  | some (.compare destination lhs rhs .ge) =>
      expect (destination + 1 > destination)
        s!"guarded: compare destination must be a local slot, got {destination}/{lhs}/{rhs}"
  | other =>
      throw <| IO.userError s!"guarded: expected compare.ge at {geIdx}, got {repr other}"
  match decrement.operations[assertIdx]? with
  | some (.assert condition) =>
      match decrement.operations[geIdx]? with
      | some (.compare destination _ _ .ge) =>
          expect (condition == destination)
            s!"guarded: assert must consume compare destination, got {condition} vs {destination}"
      | _ => pure ()
  | other =>
      throw <| IO.userError s!"guarded: expected assert at {assertIdx}, got {repr other}"

  let (initialized, initReturn) ← requireSuccess "guarded init" <|
    execute initializer empty (encodeUInt64LE 10) zeroDeposit
  expect (initReturn.isNone) "guarded init must not set return data"
  expect (storedUInt64? initialized field.key == some 10)
    "guarded init must store seed 10"

  let (afterOk, decReturn) ← requireSuccess "guarded decrement success" <|
    execute decrement initialized (encodeUInt64LE 3) zeroDeposit
  expect (decReturn == some 7 && storedUInt64? afterOk field.key == some 7)
    "guarded: 10 - 3 must yield 7 under assert"

  let (_, getReturn) ← requireSuccess "guarded view" <|
    execute get afterOk ByteArray.empty zeroDeposit
  expect (getReturn == some 7) "guarded view must observe committed 7"

  -- Underflowing decrement is trapped by the assert (not checkedSub).
  match execute decrement afterOk (encodeUInt64LE 8) zeroDeposit with
  | .trapped storage reason =>
      expect (storage == afterOk)
        "guarded underflow trap must restore pre-call storage"
      expect (reason.contains "assert")
        s!"guarded underflow must classify as assert trap, got {reason}"
  | .success .. =>
      throw <| IO.userError "guarded underflow unexpectedly succeeded"

  -- WAT text substrings for comparison op and assert trap.
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some watFile := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "guarded: missing .wat artifact"
  expectContains watFile.contents "i64.ge_u" "guarded WAT ge"
  expectContains watFile.contents "i64.extend_i32_u" "guarded WAT extend"
  expectContains watFile.contents "(if (i64.eqz" "guarded WAT assert trap"
  expectContains watFile.contents "unreachable" "guarded WAT unreachable"
  -- Deterministic rebuild of files.
  let files2 ← liftResult <| Targets.Near.buildFromCapability capability
  expect (files.map (·.contents) == files2.map (·.contents))
    "guarded: buildFromCapability must be byte-identical on rebuild"
  -- Keep plan identity stable for comparison-free consumers.
  expect (plan.programName == "Guarded") "guarded plan program name"

private unsafe def testAllComparisonOpsWat
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- NEAR requires KV state + initializer; comparisons themselves are UInt64-only.
  let sourceText :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program Compares where\n" ++
    "  state seed : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    seed := i\n\n" ++
    "  entry check(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    assert a == b\n" ++
    "    assert a != b\n" ++
    "    assert a < b\n" ++
    "    assert a <= b\n" ++
    "    assert a > b\n" ++
    "    assert a >= b\n" ++
    "    return a\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    sourceText "<near-host-compares>" "Examples.Compares" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let check ← findMethod ir "check"
  let kinds := operationKinds check.operations
  for expected in (#[
      "compare.eq", "compare.ne", "compare.lt",
      "compare.le", "compare.gt", "compare.ge"] : Array String) do
    expect (kinds.contains expected)
      s!"compares: missing {expected} in {kinds}"
  let assertCount := kinds.foldl (fun n k => if k == "assert" then n + 1 else n) 0
  expect (assertCount == 6)
    s!"compares: expected 6 asserts, got {assertCount}"
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some watFile := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "compares: missing .wat artifact"
  for insn in (#[
      "i64.eq", "i64.ne", "i64.lt_u", "i64.le_u", "i64.gt_u", "i64.ge_u"] : Array String) do
    expectContains watFile.contents insn s!"compares WAT {insn}"

private unsafe def testAssertElseRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Assert-else is rejected at Normalize (before target). Confirm product path
  -- still fails closed and does not produce NEAR artifacts.
  let sourceText :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program AssertElse where\n" ++
    "  entry f(x : UInt64) : UInt64 do\n" ++
    "    assert x > 0 else bad\n" ++
    "    return x\n" ++
    "  error bad()\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    sourceText "<near-host-assert-else>" "Examples.AssertElse" none)
  match Compiler.compileValidatedSourceV1 source with
  | .error _ => pure ()
  | .ok _ =>
      throw <| IO.userError "assert-else must fail product compile before NEAR materialization"

/-- Bool state/param remain outside the NEAR pilot; Bool results are accepted. -/
private unsafe def testBoolStateParamRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let cases : Array (String × String × String) := #[
    ("bool-state", "Examples.BoolState",
      "program BoolState where\n" ++
      "  state flag : Bool\n" ++
      "  entry ping(x : UInt64) : UInt64 do\n" ++
      "    return x\n"),
    ("bool-param", "Examples.BoolParam",
      "program BoolParam where\n" ++
      "  state count : UInt64\n" ++
      "  entry ping(flag : Bool) : UInt64 do\n" ++
      "    return count\n")
  ]
  for item in cases do
    let (label, moduleName, body) := item
    let sourceText :=
      "import ProofForgeV2\n\n" ++
      "namespace ProofForgeV2.Examples\n\n" ++
      "open ProofForgeV2.Language\n\n" ++
      body ++ "\nend ProofForgeV2.Examples\n"
    let source ← liftResult (← session.selectProgramV1
      sourceText s!"<near-host-{label}>" moduleName none)
    match Compiler.compileValidatedSourceV1 source with
    | .error _ => pure ()
    | .ok compiled =>
        -- If Normalize ever admits these, the NEAR type/signature gates must still fail closed.
        let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
        match Targets.resolveEngineeringRequirementsV1 selection compiled with
        | .error _ => pure ()
        | .ok capability =>
            match Targets.Near.planFromCapability capability with
            | .error _ => pure ()
            | .ok _ =>
                throw <| IO.userError
                  s!"{label}: Bool state/param must fail closed for NEAR"

/-- Result-kind mismatches fail closed (Typed/Normalize, or NEAR return-kind gate). -/
private unsafe def testBoolResultKindMismatchRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let cases : Array (String × String × String) := #[
    ("bool-method-returns-uint64", "Examples.BoolReturnU64",
      "program BoolReturnU64 where\n" ++
      "  state count : UInt64\n\n" ++
      "  init(i : UInt64) do\n" ++
      "    count := i\n\n" ++
      "  view positive() : Bool do\n" ++
      "    return count\n"),
    ("uint64-method-returns-bool", "Examples.U64ReturnBool",
      "program U64ReturnBool where\n" ++
      "  state count : UInt64\n\n" ++
      "  init(i : UInt64) do\n" ++
      "    count := i\n\n" ++
      "  view get() : UInt64 do\n" ++
      "    return count > 0\n")
  ]
  for item in cases do
    let (label, moduleName, body) := item
    let sourceText :=
      "import ProofForgeV2\n\n" ++
      "namespace ProofForgeV2.Examples\n\n" ++
      "open ProofForgeV2.Language\n\n" ++
      body ++ "\nend ProofForgeV2.Examples\n"
    let source ← liftResult (← session.selectProgramV1
      sourceText s!"<near-host-{label}>" moduleName none)
    match Compiler.compileValidatedSourceV1 source with
    | .error _ => pure ()
    | .ok compiled =>
        let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
        match Targets.resolveEngineeringRequirementsV1 selection compiled with
        | .error _ => pure ()
        | .ok capability =>
            match Targets.Near.planFromCapability capability with
            | .error _ => pure ()
            | .ok _ =>
                throw <| IO.userError
                  s!"{label}: result-kind mismatch must fail closed for NEAR"

/-- Wave-A bool-result defensive negative flipped to a positive plan accept. -/
private unsafe def testBoolResultAccepted
    (session : Language.Loader.ParserSession) : IO Unit := do
  let sourceText :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BoolResult where\n" ++
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  view positive() : Bool do\n" ++
    "    return count > 0\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    sourceText "<near-host-bool-result>" "Examples.BoolResult" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  let positive ← match plan.entries.find? (·.name == "positive") with
    | some method => pure method
    | none => throw <| IO.userError "bool-result: missing positive method"
  expect (positive.resultKind == .bool && positive.mode == .view)
    "bool-result: positive must be a Bool view"
  expect (positive.body.any fun s => match s with
      | .returnValue (.compare .gt (.stateLoad 0) (.literal 0)) => true
      | _ => false)
    "bool-result: positive body must return the count > 0 compare"

/-- Full BoolPredicate product path: mixed UInt64 + Bool entry/view results. -/
private def boolPredicateSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program BoolPredicate where\n" ++
  "  state count : UInt64\n\n" ++
  "  init(i : UInt64) do\n" ++
  "    count := i\n\n" ++
  "  entry add(amount : UInt64) : UInt64 do\n" ++
  "    count := count + amount\n" ++
  "    return count\n\n" ++
  "  view positive() : Bool do\n" ++
  "    return count > 0\n\n" ++
  "  entry equalsCount(d : UInt64) : Bool do\n" ++
  "    return count == d\n\n" ++
  "end ProofForgeV2.Examples\n"

private def boolPredicateModuleNameV1 : String := "Examples.BoolPredicate"

private def findPlanMethod (plan : Targets.Near.Plan) (name : String) :
    IO Targets.Near.Method :=
  match plan.entries.find? (fun method => method.name == name) with
  | some method => pure method
  | none =>
      if plan.initializer.name == name then pure plan.initializer
      else throw <| IO.userError s!"plan is missing method '{name}'"

private unsafe def testBoolPredicateProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source ← liftResult (← session.selectProgramV1
    boolPredicateSourceText "<near-host-bool-predicate>"
    boolPredicateModuleNameV1 none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let ir2 ← liftResult <| Targets.Near.irFromCapability capability
  expect (ir == ir2) "bool-predicate: irFromCapability must be byte-identical on rebuild"

  expect (plan.initializer.resultKind == .unit)
    "bool-predicate: init result kind must be unit"
  let addMethod ← findPlanMethod plan "add"
  let positiveMethod ← findPlanMethod plan "positive"
  let equalsMethod ← findPlanMethod plan "equalsCount"
  expect (addMethod.resultKind == .uint64 && addMethod.mode == .mutate)
    "bool-predicate: add must be UInt64 mutate"
  expect (positiveMethod.resultKind == .bool && positiveMethod.mode == .view)
    "bool-predicate: positive must be Bool view"
  expect (equalsMethod.resultKind == .bool && equalsMethod.mode == .mutate)
    "bool-predicate: equalsCount must be Bool entry"

  let initializer ← findMethod ir "init"
  let add ← findMethod ir "add"
  let positive ← findMethod ir "positive"
  let equalsCount ← findMethod ir "equalsCount"
  let field := ir.keys[1]!
  let empty : HostStorage := #[]
  let zeroDeposit : Deposit := { lowWord := 0, highWord := 0 }

  -- Pin Bool method ops: compare temp feeds setReturnData (no assert).
  let positiveKinds := operationKinds positive.operations
  expect (positiveKinds.contains "compare.gt")
    s!"bool-predicate: positive must lower gt compare, got {positiveKinds}"
  expect (positiveKinds.contains "setReturnData")
    s!"bool-predicate: positive must set return data, got {positiveKinds}"
  expect (!positiveKinds.contains "assert")
    s!"bool-predicate: positive must not assert, got {positiveKinds}"
  let equalsKinds := operationKinds equalsCount.operations
  expect (equalsKinds.contains "compare.eq")
    s!"bool-predicate: equalsCount must lower eq compare, got {equalsKinds}"
  expect (equalsKinds.contains "setReturnData")
    s!"bool-predicate: equalsCount must set return data, got {equalsKinds}"

  let (initialized, initReturn) ← requireSuccess "bool-predicate init" <|
    execute initializer empty (encodeUInt64LE 0) zeroDeposit
  expect (initReturn.isNone) "bool-predicate init must not set return data"
  expect (storedUInt64? initialized field.key == some 0)
    "bool-predicate init must store seed 0"

  let (_, posFalse) ← requireSuccess "bool-predicate positive false" <|
    execute positive initialized ByteArray.empty zeroDeposit
  expect (posFalse == some 0)
    "bool-predicate: positive on count=0 must return Bool false as i64 0"

  let (afterAdd, addReturn) ← requireSuccess "bool-predicate add" <|
    execute add initialized (encodeUInt64LE 7) zeroDeposit
  expect (addReturn == some 7 && storedUInt64? afterAdd field.key == some 7)
    "bool-predicate: add must return UInt64 7 and store it"

  let (_, posTrue) ← requireSuccess "bool-predicate positive true" <|
    execute positive afterAdd ByteArray.empty zeroDeposit
  expect (posTrue == some 1)
    "bool-predicate: positive on count=7 must return Bool true as i64 1"

  let (_, eqTrue) ← requireSuccess "bool-predicate equals true" <|
    execute equalsCount afterAdd (encodeUInt64LE 7) zeroDeposit
  expect (eqTrue == some 1)
    "bool-predicate: equalsCount(7) on count=7 must return true"

  let (_, eqFalse) ← requireSuccess "bool-predicate equals false" <|
    execute equalsCount afterAdd (encodeUInt64LE 3) zeroDeposit
  expect (eqFalse == some 0)
    "bool-predicate: equalsCount(3) on count=7 must return false"

  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some watFile := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "bool-predicate: missing .wat artifact"
  let some abiFile := files.find? (fun f => f.path.endsWith ".near-abi.json") |
    throw <| IO.userError "bool-predicate: missing .near-abi.json artifact"
  expectContains watFile.contents "i64.gt_u" "bool-predicate WAT gt"
  expectContains watFile.contents "i64.eq" "bool-predicate WAT eq"
  expectContains watFile.contents "i64.extend_i32_u" "bool-predicate WAT extend"
  expectContains watFile.contents "export \"positive\"" "bool-predicate WAT positive export"
  expectContains watFile.contents "export \"equalsCount\"" "bool-predicate WAT equalsCount export"
  expectContains watFile.contents "pf_value_return" "bool-predicate WAT value_return"
  -- Bool methods return the compare temp via the same 8-byte LE convention.
  expectContains watFile.contents "(call $pf_value_return (i64.const 8)"
    "bool-predicate WAT return length"
  expectContains abiFile.contents "\"returns\":\"bool\""
    "bool-predicate ABI must mark Bool method results"
  expectContains abiFile.contents "\"returns\":\"u64-le\""
    "bool-predicate ABI must retain UInt64 method results"
  expectContains abiFile.contents "\"name\":\"positive\""
    "bool-predicate ABI must list positive"
  expectContains abiFile.contents "\"name\":\"add\""
    "bool-predicate ABI must list add"
  -- Deterministic rebuild of files.
  let files2 ← liftResult <| Targets.Near.buildFromCapability capability
  expect (files.map (·.contents) == files2.map (·.contents))
    "bool-predicate: buildFromCapability must be byte-identical on rebuild"
  expect (plan.programName == "BoolPredicate") "bool-predicate plan program name"

unsafe def run : IO Unit := do
  runCheckedSubFast
  runCompareAssertFast
  let session ← Tests.Language.ParserSession.shared
  testIfFlowProductPath session
  testMatchProductPath session
  testBranchAssertTrap session
  let source ← liftResult (← session.selectProgramV1
    accumulatorSourceText "<near-host-accumulator>"
    accumulatorModuleNameV1 none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  -- S6 repair: production capability-gated IR inspection (not TargetIrFixtures).
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let initializer ← findMethod ir "init"
  let add ← findMethod ir "add"
  let current ← findMethod ir "current"
  let marker := ir.keys[0]!
  let field := ir.keys[1]!
  let empty : HostStorage := #[]
  let zeroDeposit : Deposit := { lowWord := 0, highWord := 0 }
  let lowDeposit : Deposit := { lowWord := 1, highWord := 0 }
  let highDeposit : Deposit := { lowWord := 0, highWord := 1 }

  expectTrap "entry before init" empty <|
    execute add empty (encodeUInt64LE 5) zeroDeposit
  expectTrap "seven-byte init input" empty <|
    execute initializer empty (repeatedByte 7 0) zeroDeposit
  expectTrap "nine-byte init input" empty <|
    execute initializer empty (repeatedByte 9 0) zeroDeposit
  expectTrap "init with low attached deposit" empty <|
    execute initializer empty (encodeUInt64LE 7) lowDeposit
  expectTrap "init with high attached deposit" empty <|
    execute initializer empty (encodeUInt64LE 7) highDeposit

  let (initialized, initReturn) ← requireSuccess "eight-byte init input" <|
    execute initializer empty (encodeUInt64LE 7) zeroDeposit
  expect (initReturn.isNone) "initializer must not set return data"
  expect (storedUInt64? initialized field.key == some 7)
    "initializer must materialize the seed in target-owned KV state"
  expect (storedUInt64? initialized marker.key == some plan.storage.markerValue)
    "initializer must commit the layout marker after state initialization"

  expectTrap "init twice" initialized <|
    execute initializer initialized (encodeUInt64LE 9) zeroDeposit
  expectTrap "mutate with low attached deposit" initialized <|
    execute add initialized (encodeUInt64LE 5) lowDeposit
  expectTrap "mutate with high attached deposit" initialized <|
    execute add initialized (encodeUInt64LE 5) highDeposit
  expectTrap "seven-byte mutate input" initialized <|
    execute add initialized (repeatedByte 7 0) zeroDeposit
  expectTrap "nine-byte mutate input" initialized <|
    execute add initialized (repeatedByte 9 0) zeroDeposit
  expectTrap "zero-parameter view with trailing input" initialized <|
    execute current initialized (repeatedByte 1 0) zeroDeposit

  let (_, initialViewReturn) ← requireSuccess "zero-parameter view" <|
    execute current initialized ByteArray.empty zeroDeposit
  expect (initialViewReturn == some 7)
    "zero-parameter view must read the initialized UInt64 value"

  let missingMarker := storageRemove initialized marker.key
  expectTrap "missing layout marker" missingMarker <|
    execute current missingMarker ByteArray.empty zeroDeposit
  let missingField := storageRemove initialized field.key
  expectTrap "missing state value" missingField <|
    execute current missingField ByteArray.empty zeroDeposit
  for size in (#[(0 : Nat), 7, 9] : Array Nat) do
    let corruptMarker := storagePut initialized marker.key (repeatedByte size 0)
    expectTrap s!"{size}-byte layout marker" corruptMarker <|
      execute current corruptMarker ByteArray.empty zeroDeposit
    let corruptField := storagePut initialized field.key (repeatedByte size 0)
    expectTrap s!"{size}-byte state value" corruptField <|
      execute current corruptField ByteArray.empty zeroDeposit
  let wrongMarkerValue := if plan.storage.markerValue == 1 then 2 else 1
  let oldLayout := storagePut initialized marker.key (encodeUInt64LE wrongMarkerValue)
  expectTrap "eight-byte mismatched layout marker" oldLayout <|
    execute current oldLayout ByteArray.empty zeroDeposit

  let (added, addReturn) ← requireSuccess "7 + 5 mutate" <|
    execute add initialized (encodeUInt64LE 5) zeroDeposit
  expect (addReturn == some 12 && storedUInt64? added field.key == some 12)
    "mutate must store 12 and its post-store state read must return 12"
  let (_, currentReturn) ← requireSuccess "view after mutate" <|
    execute current added ByteArray.empty zeroDeposit
  expect (currentReturn == some 12) "view must observe the committed mutate state"

  let maximum := UInt64.ofNat 18446744073709551615
  let (maximumState, _) ← requireSuccess "maximum UInt64 init" <|
    execute initializer empty (encodeUInt64LE maximum) zeroDeposit
  expectTrap "maximum UInt64 plus one" maximumState <|
    execute add maximumState (encodeUInt64LE 1) zeroDeposit

  -- Comparison + assert envelope product paths.
  testGuardedCounterProductPath session
  testAllComparisonOpsWat session
  testAssertElseRejected session
  testBoolStateParamRejected session
  testBoolResultKindMismatchRejected session
  testBoolResultAccepted session
  testBoolPredicateProductPath session
  IO.println "Tests.Materialization.NearHostModel: ok"

end Tests.Materialization.NearHostModel
