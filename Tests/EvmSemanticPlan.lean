import ProofForge.Backend.Evm.IR
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.EvmAbiAggregateProbe
import ProofForge.IR.Examples.EvmArrayValueProbe
import ProofForge.IR.Examples.EvmDynamicAbiProbe
import ProofForge.IR.Examples.EvmDynamicArrayProbe
import ProofForge.IR.Examples.EvmCrosscallProbe
import ProofForge.IR.Examples.EvmFallbackProbe
import ProofForge.IR.Examples.EvmHashProbe
import ProofForge.IR.Examples.EvmMapProbe
import ProofForge.IR.Examples.EvmStorageArrayProbe
import ProofForge.IR.Examples.EvmStorageStructProbe
import ProofForge.IR.Examples.EvmStructArrayValueProbe
import ProofForge.IR.Examples.EvmStructValueProbe
import ProofForge.IR.Examples.EventProbe

namespace ProofForge.Tests.EvmSemanticPlan

open ProofForge.IR
open ProofForge.Backend.Evm.IR
open ProofForge.Backend.Evm.Plan

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def requireSome {α : Type} (value : Option α) (message : String) : IO α :=
  match value with
  | some x => pure x
  | none => throw <| IO.userError message

def requireAt {α : Type} (values : Array α) (index : Nat) (message : String) : IO α :=
  match values[index]? with
  | some value => pure value
  | none => throw <| IO.userError message

def requireOk {α : Type} (result : Except LowerError α) (message : String) : IO α :=
  match result with
  | .ok x => pure x
  | .error err => throw <| IO.userError s!"{message}: {err.message}"

def requireValidateOk {α : Type}
    (result : Except ProofForge.Backend.Evm.Validate.LowerError α)
    (message : String) : IO α :=
  match result with
  | .ok x => pure x
  | .error err => throw <| IO.userError s!"{message}: {err.message}"

def requireErrorContains {α : Type}
    (result : Except LowerError α)
    (expected : String)
    (message : String) : IO Unit :=
  match result with
  | .ok _ => throw <| IO.userError s!"{message}: expected error containing `{expected}`"
  | .error err =>
      require (err.message.contains expected)
        s!"{message}: expected `{expected}`, got `{err.message}`"

def requireValidateErrorContains {α : Type}
    (result : Except ProofForge.Backend.Evm.Validate.LowerError α)
    (expected : String)
    (message : String) : IO Unit :=
  match result with
  | .ok _ => throw <| IO.userError s!"{message}: expected error containing `{expected}`"
  | .error err =>
      require (err.message.contains expected)
        s!"{message}: expected `{expected}`, got `{err.message}`"

def statementFunctionName? : Lean.Compiler.Yul.Statement → Option String
  | .funcDef name _ _ _ => some name
  | _ => none

def statementsHaveFunctionNamed (statements : Array Lean.Compiler.Yul.Statement) (name : String) : Bool :=
  statements.any fun stmt => statementFunctionName? stmt == some name

def statementsHaveAssignmentBuiltin (statements : Array Lean.Compiler.Yul.Statement) (name : String) : Bool :=
  statements.any fun stmt =>
    match stmt with
    | Lean.Compiler.Yul.Statement.assignment _ (Lean.Compiler.Yul.Expr.builtin builtinName _) =>
        builtinName == name
    | _ => false

def functionBody? (statements : Array Lean.Compiler.Yul.Statement) (name : String) :
    Option Lean.Compiler.Yul.Block :=
  Id.run do
    let mut found : Option Lean.Compiler.Yul.Block := none
    for stmt in statements do
      if found.isNone then
        match stmt with
        | Lean.Compiler.Yul.Statement.funcDef fnName _ _ body =>
            if fnName == name then
              found := some body
        | _ => pure ()
    found

def exprIsNatLiteral (expr : Lean.Compiler.Yul.Expr) (expected : Nat) : Bool :=
  match expr with
  | Lean.Compiler.Yul.Expr.lit literal => literal.value == toString expected
  | _ => false

mutual
  partial def blockHasMstoreValue (block : Lean.Compiler.Yul.Block) (expected : Nat) : Bool :=
    block.statements.any fun stmt => statementHasMstoreValue stmt expected

  partial def statementHasMstoreValue (stmt : Lean.Compiler.Yul.Statement) (expected : Nat) : Bool :=
    match stmt with
    | Lean.Compiler.Yul.Statement.block block =>
        blockHasMstoreValue block expected
    | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "mstore" args) =>
        match args[1]? with
        | some value => exprIsNatLiteral value expected
        | none => false
    | Lean.Compiler.Yul.Statement.ifStmt _ body =>
        blockHasMstoreValue body expected
    | Lean.Compiler.Yul.Statement.switchStmt _ cases =>
        cases.any fun case => blockHasMstoreValue case.body expected
    | Lean.Compiler.Yul.Statement.funcDef _ _ _ body =>
        blockHasMstoreValue body expected
    | Lean.Compiler.Yul.Statement.forLoop pre _ post body =>
        blockHasMstoreValue pre expected ||
          blockHasMstoreValue post expected ||
          blockHasMstoreValue body expected
    | _ => false
end

def blockHasAssignmentIdent
    (block : Lean.Compiler.Yul.Block)
    (targetName valueName : String) : Bool :=
  block.statements.any fun stmt =>
    match stmt with
    | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.ident name) =>
        names == #[targetName] && name == valueName
    | _ => false

def blockHasAssignmentNat
    (block : Lean.Compiler.Yul.Block)
    (targetName : String)
    (expected : Nat) : Bool :=
  block.statements.any fun stmt =>
    match stmt with
    | Lean.Compiler.Yul.Statement.assignment names expr =>
        names == #[targetName] && exprIsNatLiteral expr expected
    | _ => false

def blockHasAssignmentSloadSlot
    (block : Lean.Compiler.Yul.Block)
    (targetName : String)
    (expectedSlot : Nat) : Bool :=
  block.statements.any fun stmt =>
    match stmt with
    | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.builtin "sload" args) =>
        names == #[targetName] &&
          match args[0]? with
          | some slot => exprIsNatLiteral slot expectedSlot
          | none => false
    | _ => false

def exprsAreNatLiterals
    (args : Array Lean.Compiler.Yul.Expr)
    (expected : Array Nat) : Bool :=
  args.size == expected.size &&
    Id.run do
      let mut ok := true
      for _h : idx in [0:args.size] do
        match expected[idx]? with
        | some value =>
            if ok && !exprIsNatLiteral args[idx]! value then
              ok := false
        | none =>
            ok := false
      ok

def exprsHaveNatPrefix
    (args : Array Lean.Compiler.Yul.Expr)
    (expected : Array Nat) : Bool :=
  expected.size <= args.size &&
    Id.run do
      let mut ok := true
      for _h : idx in [0:expected.size] do
        match expected[idx]? with
        | some value =>
            if ok && !exprIsNatLiteral args[idx]! value then
              ok := false
        | none =>
            ok := false
      ok

def exprsHaveIdentSuffix
    (args : Array Lean.Compiler.Yul.Expr)
    (expected : Array String) : Bool :=
  expected.size <= args.size &&
    Id.run do
      let start := args.size - expected.size
      let mut ok := true
      for _h : idx in [0:expected.size] do
        match expected[idx]? with
        | some value =>
            match args[start + idx]! with
            | Lean.Compiler.Yul.Expr.ident name =>
                if ok && name != value then
                  ok := false
            | _ =>
                ok := false
        | none =>
            ok := false
      ok

def exprIsSloadSlot (expr : Lean.Compiler.Yul.Expr) (expectedSlot : Nat) : Bool :=
  match expr with
  | Lean.Compiler.Yul.Expr.builtin "sload" args =>
      match args[0]? with
      | some slot => exprIsNatLiteral slot expectedSlot
      | none => false
  | _ => false

def exprsHaveSloadSlotSuffix
    (args : Array Lean.Compiler.Yul.Expr)
    (expectedSlots : Array Nat) : Bool :=
  expectedSlots.size <= args.size &&
    Id.run do
      let start := args.size - expectedSlots.size
      let mut ok := true
      for _h : idx in [0:expectedSlots.size] do
        match expectedSlots[idx]? with
        | some slot =>
            if ok && !exprIsSloadSlot args[start + idx]! slot then
              ok := false
        | none =>
            ok := false
      ok

def blockHasAssignmentCallNatArgs
    (block : Lean.Compiler.Yul.Block)
    (targetNames : Array String)
    (functionName : String)
    (expectedArgs : Array Nat) : Bool :=
  block.statements.any fun stmt =>
    match stmt with
    | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) =>
        names == targetNames &&
          name == functionName &&
          exprsAreNatLiterals args expectedArgs
    | _ => false

def blockHasAssignmentCallNatPrefixIdentSuffix
    (block : Lean.Compiler.Yul.Block)
    (targetNames : Array String)
    (functionName : String)
    (expectedNatPrefix : Array Nat)
    (expectedIdentSuffix : Array String) : Bool :=
  block.statements.any fun stmt =>
    match stmt with
    | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) =>
        names == targetNames &&
          name == functionName &&
          args.size == expectedNatPrefix.size + expectedIdentSuffix.size &&
          exprsHaveNatPrefix args expectedNatPrefix &&
          exprsHaveIdentSuffix args expectedIdentSuffix
    | _ => false

def blockHasAssignmentCallNatPrefixSloadSuffix
    (block : Lean.Compiler.Yul.Block)
    (targetNames : Array String)
    (functionName : String)
    (expectedNatPrefix : Array Nat)
    (expectedSlots : Array Nat) : Bool :=
  block.statements.any fun stmt =>
    match stmt with
    | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) =>
        names == targetNames &&
          name == functionName &&
          args.size == expectedNatPrefix.size + expectedSlots.size &&
          exprsHaveNatPrefix args expectedNatPrefix &&
          exprsHaveSloadSlotSuffix args expectedSlots
    | _ => false

mutual
  partial def blockHasSstore (block : Lean.Compiler.Yul.Block) : Bool :=
    block.statements.any statementHasSstore

  partial def statementHasSstore : Lean.Compiler.Yul.Statement → Bool
    | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" _) =>
        true
    | Lean.Compiler.Yul.Statement.block block =>
        blockHasSstore block
    | Lean.Compiler.Yul.Statement.ifStmt _ body =>
        blockHasSstore body
    | Lean.Compiler.Yul.Statement.switchStmt _ cases =>
        cases.any fun c => blockHasSstore c.body
    | Lean.Compiler.Yul.Statement.forLoop pre _ post body =>
        blockHasSstore pre || blockHasSstore post || blockHasSstore body
    | _ => false
end

def requireCallExpr
    (expr : Lean.Compiler.Yul.Expr)
    (expectedName : String)
    (expectedArgCount : Nat)
    (label : String) : IO Unit := do
  match expr with
  | Lean.Compiler.Yul.Expr.call name args => do
      require (name == expectedName) s!"{label} helper name"
      require (args.size == expectedArgCount) s!"{label} arg count"
  | _ => throw <| IO.userError s!"{label} must lower to helper call"

def requireLiteralWordPlan
    (plan : ExprPlan)
    (expectedValue : Nat)
    (label : String) : IO Unit := do
  match plan with
  | .literalWord value =>
      require (value == expectedValue) s!"{label} literal word value"
  | _ => throw <| IO.userError s!"{label} must be a literal word plan"

def requireCrosscallLiteralWordPlan
    (plan : CrosscallArgWordPlan)
    (expectedValue : Nat)
    (label : String) : IO Unit := do
  match plan with
  | .expr exprPlan => requireLiteralWordPlan exprPlan expectedValue label
  | _ => throw <| IO.userError s!"{label} must be a crosscall scalar expression word plan"

def requireScalarStorageTarget
    (target : ScalarStorageTargetPlan)
    (expectedSlot expectedByteOffset expectedByteWidth : Nat)
    (label : String) : IO Unit := do
  match target.slot with
  | .scalarSlot slot =>
      require (slot == expectedSlot) s!"{label} slot"
  | _ => throw <| IO.userError s!"{label} must use scalar slot"
  require (target.byteOffset == expectedByteOffset) s!"{label} byte offset"
  require (target.byteWidth == expectedByteWidth) s!"{label} byte width"

def requireMapWriteTarget
    (target : MapWriteTargetPlan)
    (expectedRootSlot : Nat)
    (label : String) : IO Unit := do
  require (target.rootSlot == expectedRootSlot) s!"{label} root slot"

def requireMapReadTarget
    (target : MapReadTargetPlan)
    (expectedRootSlot : Nat)
    (label : String) : IO Unit := do
  require (target.rootSlot == expectedRootSlot) s!"{label} root slot"

def requireArrayWriteTarget
    (target : ArrayWriteTargetPlan)
    (expectedRootSlot expectedLength : Nat)
    (label : String) : IO Unit := do
  require (target.rootSlot == expectedRootSlot) s!"{label} root slot"
  require (target.length == expectedLength) s!"{label} length"

def requireArrayReadTarget
    (target : ArrayReadTargetPlan)
    (expectedRootSlot expectedLength : Nat)
    (label : String) : IO Unit := do
  require (target.rootSlot == expectedRootSlot) s!"{label} root slot"
  require (target.length == expectedLength) s!"{label} length"

def requireStructFieldWriteTarget
    (target : StructFieldWriteTargetPlan)
    (expectedSlot : Nat)
    (label : String) : IO Unit := do
  match target.slot with
  | .scalarSlot slot =>
      require (slot == expectedSlot) s!"{label} slot"
  | _ => throw <| IO.userError s!"{label} must use scalar slot"

def requireStructFieldReadTarget
    (target : StructFieldReadTargetPlan)
    (expectedSlot : Nat)
    (label : String) : IO Unit := do
  match target.slot with
  | .scalarSlot slot =>
      require (slot == expectedSlot) s!"{label} slot"
  | _ => throw <| IO.userError s!"{label} must use scalar slot"

def requireStructArrayFieldWriteTarget
    (target : StructArrayFieldWriteTargetPlan)
    (expectedRootSlot expectedLength expectedFieldCount expectedFieldOffset : Nat)
    (label : String) : IO Unit := do
  require (target.rootSlot == expectedRootSlot) s!"{label} root slot"
  require (target.length == expectedLength) s!"{label} length"
  require (target.fieldCount == expectedFieldCount) s!"{label} field count"
  require (target.fieldOffset == expectedFieldOffset) s!"{label} field offset"

def requireStructArrayFieldReadTarget
    (target : StructArrayFieldReadTargetPlan)
    (expectedRootSlot expectedLength expectedFieldCount expectedFieldOffset : Nat)
    (label : String) : IO Unit := do
  require (target.rootSlot == expectedRootSlot) s!"{label} root slot"
  require (target.length == expectedLength) s!"{label} length"
  require (target.fieldCount == expectedFieldCount) s!"{label} field count"
  require (target.fieldOffset == expectedFieldOffset) s!"{label} field offset"

def requireIdentExpr
    (expr : Lean.Compiler.Yul.Expr)
    (expectedName : String)
    (label : String) : IO Unit := do
  match expr with
  | Lean.Compiler.Yul.Expr.ident name =>
      require (name == expectedName) s!"{label} local name"
  | _ => throw <| IO.userError s!"{label} must lower to local identifier"

def contextOpsContainField (ops : Array ContextPlan) (field : ContextField) : Bool :=
  ops.any fun op => op.field.name == field.name

def nativeTransferPlanProbe : Module := {
  name := "NativeTransferPlanProbe"
  state := #[]
  entrypoints := #[
    {
      name := "send"
      selector? := some "3e58ca8c"
      params := #[("target", .u64)]
      returns := .u64
      body := #[
        .return (.crosscallInvokeValueTyped
          (.local "target")
          (.literal (.u64 0))
          .nativeValue
          #[]
          .u64)
      ]
    }
  ]
}

def memoryArrayLengthOnlyProbe : Module := {
  name := "MemoryArrayLengthOnlyProbe"
  state := #[]
  entrypoints := #[
    {
      name := "length"
      selector? := some "11111111"
      params := #[("xs", .array .u64)]
      returns := .u64
      body := #[
        .return (.memoryArrayLength (.local "xs"))
      ]
    }
  ]
}

def memoryArrayNewOnlyProbe : Module := {
  name := "MemoryArrayNewOnlyProbe"
  state := #[]
  entrypoints := #[
    {
      name := "fresh_length"
      selector? := some "22222222"
      params := #[]
      returns := .u64
      body := #[
        .letBind "xs" (.array .u64) (.memoryArrayNew .u64 (.literal (.u64 2))),
        .return (.memoryArrayLength (.local "xs"))
      ]
    }
  ]
}

def memoryArrayGetOnlyProbe : Module := {
  name := "MemoryArrayGetOnlyProbe"
  state := #[]
  entrypoints := #[
    {
      name := "first"
      selector? := some "33333333"
      params := #[("xs", .array .u64)]
      returns := .u64
      body := #[
        .return (.memoryArrayGet (.local "xs") (.literal (.u64 0)))
      ]
    }
  ]
}

def hashWordOnlyProbe : Module := {
  name := "HashWordOnlyProbe"
  state := #[]
  entrypoints := #[
    {
      name := "hash_word"
      selector? := some "44444444"
      params := #[("input", .hash)]
      returns := .hash
      body := #[
        .return (.hash (.local "input"))
      ]
    }
  ]
}

def hashPairOnlyProbe : Module := {
  name := "HashPairOnlyProbe"
  state := #[]
  entrypoints := #[
    {
      name := "hash_pair"
      selector? := some "55555555"
      params := #[("left", .hash), ("right", .hash)]
      returns := .hash
      body := #[
        .return (.hashTwoToOne (.local "left") (.local "right"))
      ]
    }
  ]
}

def mapProbeState : StateDecl := {
  id := "balances"
  kind := .map .u64 128
  type := .u64
}

def mapUnusedProbe : Module := {
  name := "MapUnusedProbe"
  state := #[mapProbeState]
  entrypoints := #[
    {
      name := "constant"
      selector? := some "a1000000"
      params := #[]
      returns := .u64
      body := #[
        .return (.literal (.u64 7))
      ]
    }
  ]
}

def mapContainsOnlyProbe : Module := {
  name := "MapContainsOnlyProbe"
  state := #[mapProbeState]
  entrypoints := #[
    {
      name := "contains"
      selector? := some "a2000000"
      params := #[("key", .u64)]
      returns := .bool
      body := #[
        .return (.effect (.storageMapContains "balances" (.local "key")))
      ]
    }
  ]
}

def mapGetOnlyProbe : Module := {
  name := "MapGetOnlyProbe"
  state := #[mapProbeState]
  entrypoints := #[
    {
      name := "get"
      selector? := some "a3000000"
      params := #[("key", .u64)]
      returns := .u64
      body := #[
        .return (.effect (.storageMapGet "balances" (.local "key")))
      ]
    }
  ]
}

def mapWriteOnlyProbe : Module := {
  name := "MapWriteOnlyProbe"
  state := #[mapProbeState]
  entrypoints := #[
    {
      name := "set"
      selector? := some "a4000000"
      params := #[("key", .u64), ("value", .u64)]
      returns := .unit
      body := #[
        .effect (.storageMapSet "balances" (.local "key") (.local "value"))
      ]
    }
  ]
}

def mapSetReturnOnlyProbe : Module := {
  name := "MapSetReturnOnlyProbe"
  state := #[mapProbeState]
  entrypoints := #[
    {
      name := "set_return"
      selector? := some "a5000000"
      params := #[("key", .u64), ("value", .u64)]
      returns := .u64
      body := #[
        .return (.effect (.storageMapSet "balances" (.local "key") (.local "value")))
      ]
    }
  ]
}

def mapAssignOnlyProbe : Module := {
  name := "MapAssignOnlyProbe"
  state := #[mapProbeState]
  entrypoints := #[
    {
      name := "add"
      selector? := some "a6000000"
      params := #[("key", .u64), ("value", .u64)]
      returns := .unit
      body := #[
        .effect (.storagePathAssignOp "balances" #[.mapKey (.local "key")] .add (.local "value"))
      ]
    }
  ]
}

def unusedPointStruct : StructDecl := {
  name := "UnusedPoint"
  fields := #[
    { id := "x", type := .u64 }
  ]
}

def storageArrayUnusedProbe : Module := {
  name := "StorageArrayUnusedProbe"
  state := #[
    { id := "values", kind := .array 3, type := .u64 }
  ]
  entrypoints := #[
    {
      name := "get"
      selector? := some "66666666"
      params := #[]
      returns := .u64
      body := #[
        .return (.literal (.u64 7))
      ]
    }
  ]
}

def dynamicArrayUnusedProbe : Module := {
  name := "DynamicArrayUnusedProbe"
  state := #[
    { id := "values", kind := .dynamicArray, type := .u64 }
  ]
  entrypoints := #[
    {
      name := "get"
      selector? := some "77777777"
      params := #[]
      returns := .u64
      body := #[
        .return (.literal (.u64 7))
      ]
    }
  ]
}

def structArrayUnusedProbe : Module := {
  name := "StructArrayUnusedProbe"
  structs := #[unusedPointStruct]
  state := #[
    { id := "points", kind := .array 2, type := .structType "UnusedPoint" }
  ]
  entrypoints := #[
    {
      name := "get"
      selector? := some "88888888"
      params := #[]
      returns := .u64
      body := #[
        .return (.literal (.u64 7))
      ]
    }
  ]
}

def contextOpsPlanProbe : Module := {
  name := "ContextOpsPlanProbe"
  state := #[]
  entrypoints := #[
    {
      name := "now"
      selector? := some "bbe4fd50"
      params := #[]
      returns := .u64
      body := #[
        .return (.effect (.contextRead .timestamp))
      ]
    },
    {
      name := "block_hash"
      selector? := some "04f3bcec"
      params := #[("block_number", .u64)]
      returns := .hash
      body := #[
        .return (.effect (.contextRead (.blockHash (.local "block_number"))))
      ]
    }
  ]
}

def eip1967PackingProbe : Module := {
  name := "Eip1967PackingProbe"
  state := #[
    {
      id := "$eip1967.implementation"
      type := .address
      kind := .scalar
    }
  ]
  entrypoints := #[]
}

def testCounterSemanticPlanEntrypoints : IO Unit := do
  let plan ← requireOk (buildSemanticPlan ProofForge.IR.Examples.Counter.module) "counter plan"
  require (plan.name == "Counter") "counter plan name"
  require (plan.targetPlan.targetId == "evm") "counter plan target"
  require (plan.entrypoints.size == 3) "counter plan entrypoint count"
  let init := plan.entrypoints[0]!
  require (init.name == "initialize") "counter plan initialize name"
  require (init.selector == "8129fc1c") "counter plan initialize selector"
  require (init.params.size == 0) "counter plan initialize params"
  require (init.returns.returnType == .unit) "counter plan initialize returns unit"
  require (init.body.size == 1) "counter plan initialize body size"
  match ← requireAt init.body 0 "counter plan initialize missing body" with
  | .effect (.storageScalarWriteTarget target (.literalWord value)) => do
      requireScalarStorageTarget target 0 0 8 "counter plan initialize storage write target"
      require (value == 0) "counter plan initialize storage write value"
  | _ => throw <| IO.userError "counter plan initialize body must be storage scalar write"
  let inc := plan.entrypoints[1]!
  require (inc.name == "increment") "counter plan increment name"
  require (inc.body.size == 2) "counter plan increment body size"
  match ← requireAt inc.body 0 "counter plan increment missing first statement" with
  | .letBind name type (.effect (.storageScalarReadTarget target)) => do
      require (name == "n") "counter plan increment let name"
      require (type == .u64) "counter plan increment let type"
      requireScalarStorageTarget target 0 0 8 "counter plan increment read target"
  | _ => throw <| IO.userError "counter plan increment first statement must read count"
  match ← requireAt inc.body 1 "counter plan increment missing second statement" with
  | .effect (.storageScalarWriteTarget target (.checkedArith .add (.local name) (.literalWord value))) => do
      requireScalarStorageTarget target 0 0 8 "counter plan increment storage write target"
      require (name == "n") "counter plan increment add lhs"
      require (value == 1) "counter plan increment add rhs"
  | _ => throw <| IO.userError "counter plan increment second statement must write checked add"

def testCounterSemanticPlanArtifacts : IO Unit := do
  let plan ← requireOk (buildSemanticPlan ProofForge.IR.Examples.Counter.module) "counter plan"
  let get := plan.entrypoints[2]!
  require (get.name == "get") "counter plan get name"
  require (get.selector == "6d4ce63c") "counter plan get selector"
  require (get.returns.returnType == .u64) "counter plan get returns u64"
  require (get.returns.wordTypes == #[.u64]) "counter plan get return words"
  require (get.returns.localNames == #["result"]) "counter plan get return local names"
  let getReturnTypedNames := ProofForge.Backend.Evm.ToYul.returnTypedNames get.returns
  require (getReturnTypedNames.size == 1) "counter plan get typed return count"
  match getReturnTypedNames[0]? with
  | some returnName => require (returnName.name == "result") "counter plan get typed return name"
  | none => throw <| IO.userError "counter plan get missing typed return"
  require (get.body.size == 1) "counter plan get body size"
  match ← requireAt get.body 0 "counter plan get missing body" with
  | .return (.effect (.storageScalarReadTarget target)) =>
      requireScalarStorageTarget target 0 0 8 "counter plan get return read target"
  | _ => throw <| IO.userError "counter plan get body must return storage scalar read"
  let storageCount ← requireSome (plan.storage.find? "count") "counter plan missing count storage"
  require (storageCount.slot == 0) "counter plan count slot"
  require (storageCount.span == 0) "counter plan count span (packed scalar has zero span)"
  require (plan.usesCheckedArithmetic == true) "counter plan checked arithmetic (increment uses add)"
  let checkedHelpers := ProofForge.Backend.Evm.ToYul.checkedArithmeticHelperFunctions
  require (checkedHelpers.size == 3) "checked arithmetic ToYul helper count"
  require
    (statementsHaveFunctionNamed checkedHelpers ProofForge.Backend.Evm.ToYul.checkedAddName)
    "checked arithmetic ToYul helper set includes add"
  require
    (statementsHaveFunctionNamed checkedHelpers ProofForge.Backend.Evm.ToYul.checkedSubName)
    "checked arithmetic ToYul helper set includes sub"
  require
    (statementsHaveFunctionNamed checkedHelpers ProofForge.Backend.Evm.ToYul.checkedMulName)
    "checked arithmetic ToYul helper set includes mul"
  let plannedCheckedHelpers := plannedCheckedArithmeticHelperFunctions plan
  require (plannedCheckedHelpers.size == 3) "planned checked arithmetic helper count"
  require
    (statementsHaveFunctionNamed plannedCheckedHelpers ProofForge.Backend.Evm.ToYul.checkedAddName)
    "planned checked arithmetic helpers include add"
  require (plan.creates.size == 0) "counter plan no creates"
  require (plan.dispatch.entrypoints.size == plan.entrypoints.size) "counter plan dispatch entrypoint count"
  require (plan.dispatch.default == .revert) "counter plan dispatch default"

def testCounterSemanticPlan : IO Unit := do
  testCounterSemanticPlanEntrypoints
  testCounterSemanticPlanArtifacts

def testEventSemanticPlan : IO Unit := do
  let plan ← requireOk (buildSemanticPlan ProofForge.IR.Examples.EventProbe.evmModule) "event plan"
  require (plan.entrypoints.size > 0) "event plan entrypoint count"
  require (plan.events.size > 0) "event plan event count"
  require (plan.hasHelper .arraySlot) "event plan requires array slot helper for storage array event words"
  require (plan.hasHelper .structArraySlot) "event plan requires struct-array slot helper for storage struct-array event words"
  let valueEvent? := plan.events.find? (fun ev => ev.name == "ValueEvent")
  require valueEvent?.isSome "event plan missing ValueEvent"
  let valueEvent := valueEvent?.get!
  require (valueEvent.signature == "ValueEvent(uint64)") "event plan ValueEvent signature"
  let fields := valueEvent.fields
  require (fields.size == 1) "event plan ValueEvent field count"
  require (fields[0]!.name == "value") "event plan ValueEvent field name"
  require (fields[0]!.type == .u64) "event plan ValueEvent field type"
  require (fields[0]!.indexed == false) "event plan ValueEvent field not indexed"
  let valueEntrypoint ← requireSome
    (plan.entrypoints.find? (fun entrypoint => entrypoint.name == "emit_value_event"))
    "event plan missing emit_value_event entrypoint"
  let valueStmt ← requireAt valueEntrypoint.body 0 "event plan emit_value_event missing body"
  match valueStmt with
  | .effect (.eventEmitWords event dataFieldWords) => do
      require (event.name == "ValueEvent") "event plan body eventEmitWords event name"
      require (dataFieldWords.size == 1) "event plan body eventEmitWords field count"
      let valueWords ← requireAt dataFieldWords 0 "event plan body eventEmitWords missing field words"
      require (valueWords.size == 1) "event plan body eventEmitWords word count"
      match valueWords[0]? with
      | some (ExprPlan.local "value") => pure ()
      | _ => throw <| IO.userError "event plan body eventEmitWords must carry value local"
  | _ => throw <| IO.userError "event plan body must already use eventEmitWords"
  let alteredEntrypoints := plan.entrypoints.map fun entrypoint =>
    if entrypoint.name == "emit_value_event" then
      { entrypoint with
        body := #[
          StmtPlan.effect
            (EffectPlan.eventEmitWords valueEvent #[#[ExprPlan.literalWord 99]])
        ]
      }
    else
      entrypoint
  let alteredPlan := { plan with entrypoints := alteredEntrypoints }
  let alteredObject ← requireOk
    (lowerModuleWithPlan ProofForge.IR.Examples.EventProbe.evmModule alteredPlan)
    "event altered entrypoint plan-driven module lowering"
  let alteredEntrypoint ← requireSome
    (alteredPlan.entrypoints.find? (fun entrypoint => entrypoint.name == "emit_value_event"))
    "event altered plan missing emit_value_event entrypoint"
  let alteredFunctionName :=
    ProofForge.Backend.Evm.ToYul.entrypointPlanFunctionName
      ProofForge.IR.Examples.EventProbe.evmModule.name
      alteredEntrypoint
  let alteredBody ← requireSome
    (functionBody? alteredObject.code.statements alteredFunctionName)
    "event altered plan function body missing"
  require (blockHasMstoreValue alteredBody 99)
    "plan-driven entrypoint lowering must consume ModulePlan body event words"
  let storageArrayEvent ← requireSome
    (plan.events.find? (fun ev => ev.name == "StorageArrayEvent"))
    "event plan missing StorageArrayEvent"
  let aggregateEntrypoints := plan.entrypoints.map fun entrypoint =>
    if entrypoint.name == "emit_storage_array_event" then
      { entrypoint with
        body := #[
          StmtPlan.effect
            (EffectPlan.eventEmitWords storageArrayEvent #[#[
              ExprPlan.literalWord 77,
              ExprPlan.literalWord 88
            ]])
        ]
      }
    else
      entrypoint
  let aggregatePlan := { plan with entrypoints := aggregateEntrypoints }
  let aggregateObject ← requireOk
    (lowerModuleWithPlan ProofForge.IR.Examples.EventProbe.evmModule aggregatePlan)
    "event aggregate altered entrypoint plan-driven module lowering"
  let aggregateEntrypoint ← requireSome
    (aggregatePlan.entrypoints.find? (fun entrypoint => entrypoint.name == "emit_storage_array_event"))
    "event aggregate altered plan missing emit_storage_array_event entrypoint"
  let aggregateFunctionName :=
    ProofForge.Backend.Evm.ToYul.entrypointPlanFunctionName
      ProofForge.IR.Examples.EventProbe.evmModule.name
      aggregateEntrypoint
  let aggregateBody ← requireSome
    (functionBody? aggregateObject.code.statements aggregateFunctionName)
    "event aggregate altered plan function body missing"
  require (blockHasMstoreValue aggregateBody 77)
    "plan-driven entrypoint lowering must consume aggregate ModulePlan event word 77"
  require (blockHasMstoreValue aggregateBody 88)
    "plan-driven entrypoint lowering must consume aggregate ModulePlan event word 88"
  let topicStmts := ProofForge.Backend.Evm.ToYul.eventSignatureTopicStatements valueEvent
  require (topicStmts.size > 0) "event plan-to-yul topic statement count"
  match topicStmts[topicStmts.size - 1]? with
  | some (Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.builtin "keccak256" args))) => do
      match vars[0]? with
      | some var => require (var.name == "_topic0") "event plan-to-yul topic var name"
      | none => throw <| IO.userError "event plan-to-yul missing topic var"
      require (args.size == 2) "event plan-to-yul keccak arg count"
  | _ => throw <| IO.userError "event plan-to-yul topic must end with keccak topic0"
  let indexedEvent ← requireSome
    (plan.events.find? (fun ev => ev.name == "IndexedValue"))
    "event plan missing IndexedValue"
  let indexedField ← requireAt indexedEvent.indexedFields 0 "event plan missing IndexedValue indexed field"
  let indexedTopicStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.eventIndexedTopicStatements
      toYulError
      indexedField
      0
      #[Lean.Compiler.Yul.Expr.num 7])
    "event plan-to-yul indexed scalar topic"
  require (indexedTopicStmts.size == 1) "event plan-to-yul indexed scalar topic statement count"
  match indexedTopicStmts[0]! with
  | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.lit lit)) => do
      match vars[0]? with
      | some var => require (var.name == "_indexed_topic0") "event plan-to-yul indexed scalar topic var"
      | none => throw <| IO.userError "event plan-to-yul indexed scalar topic missing var"
      require (lit.value == "7") "event plan-to-yul indexed scalar topic value"
  | _ => throw <| IO.userError "event plan-to-yul indexed scalar topic must be var decl"
  let aggregateTopicStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.eventIndexedTopicStatements
      toYulError
      (EventFieldPlan.mk "values" (.fixedArray .u64 2) true)
      1
      #[Lean.Compiler.Yul.Expr.num 1, Lean.Compiler.Yul.Expr.num 2])
    "event plan-to-yul indexed aggregate topic"
  require (aggregateTopicStmts.size == 3) "event plan-to-yul indexed aggregate topic statement count"
  match aggregateTopicStmts[2]! with
  | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.builtin "keccak256" args)) => do
      match vars[0]? with
      | some var => require (var.name == "_indexed_topic1") "event plan-to-yul indexed aggregate topic var"
      | none => throw <| IO.userError "event plan-to-yul indexed aggregate topic missing var"
      require (args.size == 2) "event plan-to-yul indexed aggregate keccak arg count"
  | _ => throw <| IO.userError "event plan-to-yul indexed aggregate topic must hash stored words"
  let logStmt ← requireOk
    (ProofForge.Backend.Evm.ToYul.eventLogStatement toYulError indexedEvent 1)
    "event plan-to-yul log statement"
  match logStmt with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin name args) => do
      require (name == "log2") "event plan-to-yul indexed log builtin"
      require (args.size == 4) "event plan-to-yul indexed log arg count"
      match args[3]! with
      | Lean.Compiler.Yul.Expr.ident topicName =>
          require (topicName == "_indexed_topic0") "event plan-to-yul indexed topic arg"
      | _ => throw <| IO.userError "event plan-to-yul indexed log topic must be identifier"
  | _ => throw <| IO.userError "event plan-to-yul log must be expr statement"

def testERC20StandardEventSignatureTypes : IO Unit := do
  let module := ProofForge.IR.Examples.Counter.module
  let transferFrom ← requireValidateOk
    (ProofForge.Backend.Evm.Validate.eventSignatureFieldType module "Transfer" "from" .u64)
    "erc20 Transfer.from event ABI type"
  require (transferFrom == "address") "erc20 Transfer.from must stay address"
  let transferValue ← requireValidateOk
    (ProofForge.Backend.Evm.Validate.eventSignatureFieldType module "Transfer" "value" .u64)
    "erc20 Transfer.value event ABI type"
  require
    (transferValue == "uint256")
    "erc20 Transfer.value must stay Solidity/ERC-20 uint256"
  let approvalOwner ← requireValidateOk
    (ProofForge.Backend.Evm.Validate.eventSignatureFieldType module "Approval" "owner" .u64)
    "erc20 Approval.owner event ABI type"
  require (approvalOwner == "address") "erc20 Approval.owner must stay address"
  let approvalValue ← requireValidateOk
    (ProofForge.Backend.Evm.Validate.eventSignatureFieldType module "Approval" "value" .u64)
    "erc20 Approval.value event ABI type"
  require
    (approvalValue == "uint256")
    "erc20 Approval.value must stay Solidity/ERC-20 uint256"
  let defaultValue ← requireValidateOk
    (ProofForge.Backend.Evm.Validate.eventSignatureFieldType module "ValueEvent" "value" .u64)
    "default event ABI type"
  require (defaultValue == "uint64") "non-ERC20 U64 event fields must stay uint64"

def testArtifactMetadata : IO Unit := do
  let artifactMeta ← requireOk (buildPlanArtifactMetadata ProofForge.IR.Examples.Counter.module) "counter artifact metadata"
  require (artifactMeta.moduleName == "Counter") "counter metadata module name"
  require (artifactMeta.targetId == "evm") "counter metadata target"
  require (artifactMeta.entrypoints.size == 3) "counter metadata entrypoint count"
  let init := artifactMeta.entrypoints[0]!
  require (init.name == "initialize") "counter metadata initialize name"
  require (init.selector == "8129fc1c") "counter metadata initialize selector"

def testDeployMetadata : IO Unit := do
  let deployMeta ← requireOk (buildPlanDeployMetadata ProofForge.IR.Examples.Counter.module) "counter deploy metadata"
  require (deployMeta.moduleName == "Counter") "counter deploy metadata module name"
  require (deployMeta.targetId == "evm") "counter deploy metadata target"
  require (deployMeta.entrypointSelectors.size == 3) "counter deploy metadata selectors"
  let initSel := deployMeta.entrypointSelectors[0]!
  require (initSel.fst == "initialize") "counter deploy metadata initialize name"
  require (initSel.snd == "8129fc1c") "counter deploy metadata initialize selector"

def testHashHelperPlanToYul : IO Unit := do
  let hashHelpers := ProofForge.Backend.Evm.ToYul.hashHelperFunctions
  require (hashHelpers.size == 2) "hash ToYul helper count"
  require
    (statementsHaveFunctionNamed hashHelpers (ProofForge.Backend.Evm.Plan.Helper.hashWord).name)
    "hash ToYul helper set includes hash word"
  require
    (statementsHaveFunctionNamed hashHelpers (ProofForge.Backend.Evm.Plan.Helper.hashPair).name)
    "hash ToYul helper set includes hash pair"
  let plan ←
    requireOk
      (buildSemanticPlan ProofForge.IR.Examples.EvmHashProbe.module)
      "hash probe plan"
  require (plan.hasHelper .hashWord) "hash probe plan requires hash word helper"
  require (plan.hasHelper .hashPair) "hash probe plan requires hash pair helper"
  let plannedHashHelpers := plannedHashHelperFunctions plan
  require (plannedHashHelpers.size == 2) "planned hash helper count"
  require
    (statementsHaveFunctionNamed plannedHashHelpers (ProofForge.Backend.Evm.Plan.Helper.hashWord).name)
    "planned hash helpers include hash word"
  require
    (statementsHaveFunctionNamed plannedHashHelpers (ProofForge.Backend.Evm.Plan.Helper.hashPair).name)
    "planned hash helpers include hash pair"

def testArrayHelperPlanToYul : IO Unit := do
  let arrayHelpers := ProofForge.Backend.Evm.ToYul.arrayHelperFunctions
  require (arrayHelpers.size == 1) "array ToYul helper count"
  require
    (statementsHaveFunctionNamed arrayHelpers (Helper.arraySlot).name)
    "array ToYul helper set includes fixed array slot"
  let arrayPlan ←
    requireOk
      (buildSemanticPlan ProofForge.IR.Examples.EvmStorageArrayProbe.module)
      "storage array probe plan"
  require (arrayPlan.hasHelper .arraySlot) "storage array probe plan requires array slot helper"
  let plannedArrayHelpers := plannedArrayHelperFunctions arrayPlan
  require (plannedArrayHelpers.size == 1) "planned array helper count"
  require
    (statementsHaveFunctionNamed plannedArrayHelpers (Helper.arraySlot).name)
    "planned array helpers include fixed array slot"
  let dynamicArrayHelpers := ProofForge.Backend.Evm.ToYul.dynamicArrayHelperFunctions
  require (dynamicArrayHelpers.size == 1) "dynamic array ToYul helper count"
  require
    (statementsHaveFunctionNamed dynamicArrayHelpers (Helper.dynamicArraySlot).name)
    "dynamic array ToYul helper set includes dynamic array slot"
  let dynamicPlan ←
    requireOk
      (buildSemanticPlan ProofForge.IR.Examples.EvmDynamicArrayProbe.module)
      "dynamic array probe plan"
  require (dynamicPlan.hasHelper .dynamicArraySlot) "dynamic array probe plan requires dynamic array slot helper"
  let plannedDynamicHelpers := plannedDynamicArrayHelperFunctions dynamicPlan
  require (plannedDynamicHelpers.size == 1) "planned dynamic array helper count"
  require
    (statementsHaveFunctionNamed plannedDynamicHelpers (Helper.dynamicArraySlot).name)
    "planned dynamic array helpers include dynamic array slot"
  let structArrayHelpers := ProofForge.Backend.Evm.ToYul.structArrayHelperFunctions
  require (structArrayHelpers.size == 1) "struct array ToYul helper count"
  require
    (statementsHaveFunctionNamed structArrayHelpers (Helper.structArraySlot).name)
    "struct array ToYul helper set includes struct array slot"
  let structArrayPlan ←
    requireOk
      (buildSemanticPlan ProofForge.IR.Examples.EvmStorageStructProbe.module)
      "storage struct probe plan"
  require (structArrayPlan.hasHelper .structArraySlot) "storage struct probe plan requires struct array slot helper"
  let plannedStructArrayHelpers := plannedStructArrayHelperFunctions structArrayPlan
  require (plannedStructArrayHelpers.size == 1) "planned struct array helper count"
  require
    (statementsHaveFunctionNamed plannedStructArrayHelpers (Helper.structArraySlot).name)
    "planned struct array helpers include struct array slot"

def testMapHelperPlanToYul : IO Unit := do
  let baseMapHelpers := ProofForge.Backend.Evm.ToYul.mapBaseHelperFunctions
  require (baseMapHelpers.size == 4) "map ToYul base helper count"
  require
    (statementsHaveFunctionNamed baseMapHelpers (Helper.mapSlot).name)
    "map ToYul helper set includes map slot"
  require
    (statementsHaveFunctionNamed baseMapHelpers (Helper.mapPresenceSlot).name)
    "map ToYul helper set includes map presence slot"
  require
    (statementsHaveFunctionNamed baseMapHelpers (Helper.mapWrite).name)
    "map ToYul helper set includes map write"
  require
    (statementsHaveFunctionNamed baseMapHelpers (Helper.mapSetReturn).name)
    "map ToYul helper set includes map set-return"
  let plan ←
    requireOk
      (buildSemanticPlan ProofForge.IR.Examples.EvmMapProbe.module)
      "map probe plan"
  require (plan.hasHelper .mapSlot) "map probe plan requires map slot helper"
  require (plan.hasHelper .mapPresenceSlot) "map probe plan requires map presence slot helper"
  require (plan.hasHelper .mapWrite) "map probe plan requires map write helper"
  require (plan.hasHelper .mapSetReturn) "map probe plan requires map set-return helper"
  require (plan.mapAssignOps.size == 10) "map probe planned map assign op count"
  require
    (plan.mapAssignOps.any fun op => op == .add)
    "map probe planned map assign ops include add"
  let plannedMapHelpers := plannedMapHelperFunctions plan
  require (plannedMapHelpers.size == 4 + plan.mapAssignOps.size) "planned map helper count"
  require
    (statementsHaveFunctionNamed plannedMapHelpers (Helper.mapSlot).name)
    "planned map helpers include map slot"
  require
    (statementsHaveFunctionNamed plannedMapHelpers (Helper.mapPresenceSlot).name)
    "planned map helpers include map presence slot"
  require
    (statementsHaveFunctionNamed plannedMapHelpers (Helper.mapWrite).name)
    "planned map helpers include map write"
  require
    (statementsHaveFunctionNamed plannedMapHelpers (Helper.mapSetReturn).name)
    "planned map helpers include map set-return"
  require
    (statementsHaveFunctionNamed plannedMapHelpers (Helper.mapAssign .add).name)
    "planned map helpers include map assign add"
  require
    (statementsHaveFunctionNamed plannedMapHelpers (Helper.mapAssign .shiftRight).name)
    "planned map helpers include map assign shift-right"

def testPlannedCrosscallHelperDiscoveryToYul : IO Unit := do
  let plan ←
    requireOk
      (buildSemanticPlan ProofForge.IR.Examples.EvmCrosscallProbe.module)
      "crosscall probe plan"
  let lowerPlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan ProofForge.IR.Examples.EvmCrosscallProbe.module)
      "crosscall probe lower full module plan"
  require
    (lowerPlan.crosscalls == plan.crosscalls)
    "crosscall helper discovery must come from Lower.buildFullModulePlan"
  require
    (lowerPlan.creates == plan.creates)
    "create helper discovery must come from Lower.buildFullModulePlan"
  require (plan.crosscalls.size > 0) "crosscall probe planned crosscall helpers"
  require
    (plan.crosscalls.any fun spec =>
      spec.mode == ProofForge.Backend.Evm.Plan.CrosscallMode.staticcall)
    "crosscall probe planned staticcall helper"
  require
    (plan.crosscalls.any fun spec =>
      spec.mode == ProofForge.Backend.Evm.Plan.CrosscallMode.delegatecall)
    "crosscall probe planned delegatecall helper"
  let aggregateReturn ← requireSome
    (plan.crosscalls.find? fun spec =>
      match spec.returnType with
      | .structType "RemotePair" => spec.mode == ProofForge.Backend.Evm.Plan.CrosscallMode.call
      | _ => false)
    "crosscall probe missing planned aggregate return helper"
  require
    (aggregateReturn.wordTypes == #[.bool, .u32])
    "crosscall probe planned aggregate return word layout"
  let aggregateReturnPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.crosscallReturnPlan
      ProofForge.IR.Examples.EvmCrosscallProbe.module
      "typed crosscall return"
      (.structType "RemotePair"))
    "aggregate crosscall return plan"
  require
    (aggregateReturnPlan.wordTypes == #[.bool, .u32])
    "aggregate crosscall return plan word layout"
  require
    (aggregateReturnPlan.localNames == #["__proof_forge_return_0", "__proof_forge_return_1"])
    "aggregate crosscall return plan local names"
  let aggregateAssignmentPlan? ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.aggregateCrosscallReturnAssignmentPlan?
      ProofForge.IR.Examples.EvmCrosscallProbe.module
      (toValidateTypeEnv (entrypointTypeEnv ProofForge.IR.Examples.EvmCrosscallProbe.callRemotePair))
      "call_remote_pair"
      (.structType "RemotePair")
      (.crosscallInvokeTyped
        (.local "target")
        (.local "method")
        #[]
        (.structType "RemotePair")))
    "aggregate crosscall return assignment plan"
  let aggregateAssignmentPlan ← requireSome
    aggregateAssignmentPlan?
    "aggregate crosscall return assignment plan must be present"
  require
    (aggregateAssignmentPlan.mode == ProofForge.Backend.Evm.Plan.CrosscallMode.call)
    "aggregate crosscall return assignment plan mode"
  require
    (aggregateAssignmentPlan.returns.wordTypes == #[.bool, .u32])
    "aggregate crosscall return assignment plan word layout"
  require
    (aggregateAssignmentPlan.returns.localNames == #["__proof_forge_return_0", "__proof_forge_return_1"])
    "aggregate crosscall return assignment plan local names"
  require
    aggregateAssignmentPlan.args.isEmpty
    "aggregate crosscall return assignment plan args"
  match aggregateAssignmentPlan.target with
  | .local "target" => pure ()
  | _ => throw <| IO.userError "aggregate crosscall return assignment plan target"
  match aggregateAssignmentPlan.methodId with
  | .local "method" => pure ()
  | _ => throw <| IO.userError "aggregate crosscall return assignment plan method"
  match aggregateAssignmentPlan.callValue? with
  | none => pure ()
  | some _ => throw <| IO.userError "aggregate crosscall return assignment plan call value"
  let aggregateFunctionName ←
    requireOk
      (ProofForge.Backend.Evm.ToYul.crosscallHelperFunctionName toYulError aggregateReturn)
      "aggregate crosscall helper name"
  require
    (aggregateFunctionName == "__proof_forge_crosscall_0_abi_bool_u32")
    "aggregate crosscall helper name must include planned ABI word layout"
  let aggregateAssignment ←
    requireOk
      (ProofForge.Backend.Evm.ToYul.crosscallAggregateReturnAssignment
        toYulError
        #["ret_flag", "ret_small"]
        ProofForge.Backend.Evm.Plan.CrosscallMode.call
        (Lean.Compiler.Yul.Expr.id "target")
        (Lean.Compiler.Yul.Expr.id "method")
        none
        #[]
        (.structType "RemotePair")
        #[.bool, .u32])
      "aggregate crosscall return assignment helper"
  match aggregateAssignment with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["ret_flag", "ret_small"]) "aggregate crosscall return assignment names"
      require (name == "__proof_forge_crosscall_0_abi_bool_u32") "aggregate crosscall return assignment helper name"
      require (args.size == 2) "aggregate crosscall return assignment arg count"
  | _ => throw <| IO.userError "aggregate crosscall return assignment must assign aggregate helper call"
  let aggregateAssignmentFromPlan ←
    requireOk
      (ProofForge.Backend.Evm.ToYul.crosscallAggregateReturnAssignmentPlanStatement
        toYulError
        (fun
          | .local name => .ok (Lean.Compiler.Yul.Expr.id name)
          | .literalWord value => .ok (Lean.Compiler.Yul.Expr.num value)
          | _ => .error { message := "aggregate crosscall return plan helper test only lowers local/literal scalar plans" })
        (fun name type =>
          if name == "pair" && type == .structType "RemotePair" then
            .ok #[Lean.Compiler.Yul.Expr.id "pair_flag", Lean.Compiler.Yul.Expr.id "pair_small"]
          else
            .error { message := "aggregate crosscall return plan helper test unexpected local source" })
        (fun _stateId _type =>
          .error { message := "aggregate crosscall return plan helper test should not lower storage sources" })
        { aggregateAssignmentPlan with
          args := #[
            CrosscallArgWordPlan.local "pair" (.structType "RemotePair"),
            CrosscallArgWordPlan.expr (.literalWord 7)
          ] })
      "aggregate crosscall return assignment plan helper"
  let aggregateAssignmentFromPlanName ←
    requireOk
      (ProofForge.Backend.Evm.ToYul.crosscallHelperFunctionName
        toYulError
        (ProofForge.Backend.Evm.ToYul.crosscallAggregateHelperSpec
          ProofForge.Backend.Evm.Plan.CrosscallMode.call
          3
          (.structType "RemotePair")
          #[.bool, .u32]))
      "aggregate crosscall return assignment plan helper name"
  match aggregateAssignmentFromPlan with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["__proof_forge_return_0", "__proof_forge_return_1"])
        "aggregate crosscall return assignment plan helper return names"
      require (name == aggregateAssignmentFromPlanName)
        "aggregate crosscall return assignment plan helper function name"
      require (args.size == 5) "aggregate crosscall return assignment plan helper arg count"
      requireIdentExpr args[0]! "target" "aggregate crosscall return assignment plan helper target"
      requireIdentExpr args[1]! "method" "aggregate crosscall return assignment plan helper method"
      requireIdentExpr args[2]! "pair_flag" "aggregate crosscall return assignment plan helper local word 0"
      requireIdentExpr args[3]! "pair_small" "aggregate crosscall return assignment plan helper local word 1"
      match args[4]! with
      | Lean.Compiler.Yul.Expr.lit value =>
          require (value.value == "7") "aggregate crosscall return assignment plan helper literal arg"
      | _ => throw <| IO.userError "aggregate crosscall return assignment plan helper final arg must be literal"
  | _ => throw <| IO.userError "aggregate crosscall return assignment plan helper must assign aggregate helper call"
  let aggregateReturnStmts ←
    requireOk
      (lowerReturnAssignments
        ProofForge.IR.Examples.EvmCrosscallProbe.module
        (entrypointTypeEnv ProofForge.IR.Examples.EvmCrosscallProbe.callRemotePair)
        "call_remote_pair"
        (.structType "RemotePair")
        (.crosscallInvokeTyped
          (.local "target")
          (.local "method")
          #[]
          (.structType "RemotePair")))
      "aggregate crosscall return assignment integration"
  require (aggregateReturnStmts.size == 1) "aggregate crosscall return assignment integration statement count"
  match aggregateReturnStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names.size == 2) "aggregate crosscall return assignment integration names count"
      require (name == "__proof_forge_crosscall_0_abi_bool_u32") "aggregate crosscall return assignment integration helper name"
      require (args.size == 2) "aggregate crosscall return assignment integration arg count"
  | _ => throw <| IO.userError "aggregate crosscall return assignment integration must assign aggregate helper call"
  let plannedAggregateCrosscallExpr ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExprPlan
      ProofForge.IR.Examples.EvmCrosscallProbe.module
      (toValidateTypeEnv (entrypointTypeEnv ProofForge.IR.Examples.EvmCrosscallProbe.callRemotePair))
      (.crosscallInvokeTyped
        (.local "target")
        (.local "method")
        #[]
        (.structType "RemotePair")))
    "planned aggregate crosscall return ExprPlan"
  let plannedAggregateAssignmentPlan? ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.aggregateCrosscallReturnAssignmentPlanFromExprPlan?
      ProofForge.IR.Examples.EvmCrosscallProbe.module
      "call_remote_pair"
      (.structType "RemotePair")
      plannedAggregateCrosscallExpr)
    "planned aggregate crosscall return assignment plan"
  let plannedAggregateAssignmentPlan ← requireSome
    plannedAggregateAssignmentPlan?
    "planned aggregate crosscall return assignment plan must be present"
  require
    (plannedAggregateAssignmentPlan.mode == ProofForge.Backend.Evm.Plan.CrosscallMode.call)
    "planned aggregate crosscall return assignment plan mode"
  require
    (plannedAggregateAssignmentPlan.returns.wordTypes == #[.bool, .u32])
    "planned aggregate crosscall return assignment plan word layout"
  let plannedAggregateReturnStmts ←
    requireOk
      (lowerAggregateReturnStmtPlan
        ProofForge.IR.Examples.EvmCrosscallProbe.module
        (entrypointTypeEnv ProofForge.IR.Examples.EvmCrosscallProbe.callRemotePair)
        "call_remote_pair"
        (.structType "RemotePair")
        plannedAggregateCrosscallExpr
        false)
      "planned aggregate crosscall return plan-to-yul"
  require (plannedAggregateReturnStmts.size == 1)
    "planned aggregate crosscall return plan-to-yul statement count"
  match plannedAggregateReturnStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["__proof_forge_return_0", "__proof_forge_return_1"])
        "planned aggregate crosscall return plan-to-yul return names"
      require (name == "__proof_forge_crosscall_0_abi_bool_u32")
        "planned aggregate crosscall return plan-to-yul helper name"
      require (args.size == 2) "planned aggregate crosscall return plan-to-yul arg count"
  | _ => throw <| IO.userError "planned aggregate crosscall return plan-to-yul must assign aggregate helper call"

def testPlannedCreateAndNativeHelperDiscoveryToYul : IO Unit := do
  let plan ←
    requireOk
      (buildSemanticPlan ProofForge.IR.Examples.EvmCrosscallProbe.module)
      "crosscall probe plan"
  require (plan.creates.size == 2) "crosscall probe planned create helpers"
  let nativePlan ← requireOk (buildSemanticPlan nativeTransferPlanProbe) "native transfer plan"
  let nativeTransfer ← requireSome
    (nativePlan.crosscalls.find? fun spec => spec.plainTransfer)
    "native transfer probe missing planned native transfer helper"
  require
    (nativeTransfer.mode == ProofForge.Backend.Evm.Plan.CrosscallMode.callValue)
    "native transfer helper mode"
  require (nativeTransfer.arity == 0) "native transfer helper arity"
  require (nativeTransfer.returnType == .u64) "native transfer return type"
  require (nativeTransfer.wordTypes == #[.u64]) "native transfer return word layout"
  let nativeFunctionName ←
    requireOk
      (ProofForge.Backend.Evm.ToYul.crosscallHelperFunctionName toYulError nativeTransfer)
      "native transfer helper name"
  require
    (nativeFunctionName == "__proof_forge_native_transfer")
    "native transfer helper name"
  let crosscallHelpers ←
    requireOk
      (plannedCrosscallHelperFunctions nativePlan.crosscalls)
      "planned crosscall helper functions"
  require
    (statementsHaveFunctionNamed crosscallHelpers "__proof_forge_native_transfer")
    "planned crosscall helpers include native transfer"
  let createSpec ← requireSome
    (plan.creates.find? fun spec => spec.mode == ProofForge.Backend.Evm.Plan.CreateMode.create)
    "crosscall probe missing planned create helper"
  require
    (createSpec.initCodeHex == ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex)
    "planned create helper init code"
  let createName ←
    requireOk
      (ProofForge.Backend.Evm.ToYul.createHelperFunctionName
        toYulError
        createSpec.mode
        createSpec.initCodeHex)
      "planned create helper name"
  require
    (createName ==
      "__proof_forge_create_" ++ ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex)
    "planned create helper name must include normalized init code"
  let createFunction ←
    requireOk
      (ProofForge.Backend.Evm.ToYul.createHelperFunction toYulError createSpec)
      "planned create helper function"
  match createFunction with
  | Lean.Compiler.Yul.Statement.funcDef name params returns body => do
      require (name == createName) "planned create helper function name"
      require (params.size == 1) "planned create helper parameter count"
      require (returns.size == 1) "planned create helper return count"
      require (statementsHaveAssignmentBuiltin body.statements "create")
        "planned create helper must call Yul create opcode"
  | _ => throw <| IO.userError "planned create helper must lower to function definition"
  let create2Spec ← requireSome
    (plan.creates.find? fun spec => spec.mode == ProofForge.Backend.Evm.Plan.CreateMode.create2)
    "crosscall probe missing planned create2 helper"
  require
    (create2Spec.initCodeHex == ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex)
    "planned create2 helper init code"
  let create2Name ←
    requireOk
      (ProofForge.Backend.Evm.ToYul.createHelperFunctionName
        toYulError
        create2Spec.mode
        create2Spec.initCodeHex)
      "planned create2 helper name"
  require
    (create2Name ==
      "__proof_forge_create2_" ++ ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex)
    "planned create2 helper name must include normalized init code"
  let create2Function ←
    requireOk
      (ProofForge.Backend.Evm.ToYul.createHelperFunction toYulError create2Spec)
      "planned create2 helper function"
  match create2Function with
  | Lean.Compiler.Yul.Statement.funcDef name params returns body => do
      require (name == create2Name) "planned create2 helper function name"
      require (params.size == 2) "planned create2 helper parameter count"
      require (returns.size == 1) "planned create2 helper return count"
      require (statementsHaveAssignmentBuiltin body.statements "create2")
        "planned create2 helper must call Yul create2 opcode"
  | _ => throw <| IO.userError "planned create2 helper must lower to function definition"
  let createHelpers ←
    requireOk (plannedCreateHelperFunctions plan.creates) "planned create helper functions"
  require (createHelpers.size == 2) "planned create helper count"
  require
    (statementsHaveFunctionNamed createHelpers createName)
    "planned create helpers include create helper"
  require
    (statementsHaveFunctionNamed createHelpers create2Name)
    "planned create helpers include create2 helper"
  let object ←
    requireOk
      (lowerModuleWithPlan nativeTransferPlanProbe nativePlan)
      "native transfer plan-driven module lowering"
  require
    (statementsHaveFunctionNamed object.code.statements "__proof_forge_native_transfer")
    "plan-driven module lowering includes native transfer helper"

def testPlannedHelperDiscoveryToYul : IO Unit := do
  testPlannedCrosscallHelperDiscoveryToYul
  testPlannedCreateAndNativeHelperDiscoveryToYul

def testPlannedCrosscallHelperDiscoveryFromEntrypointPlans : IO Unit := do
  let crosscallPlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan ProofForge.IR.Examples.EvmCrosscallProbe.module)
      "crosscall probe full module plan for planned helper discovery"
  let plannedCrosscalls ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildCrosscallHelperPlansFromEntrypoints
        ProofForge.IR.Examples.EvmCrosscallProbe.module
        crosscallPlan.entrypoints)
      "planned crosscall helper discovery from entrypoint plans"
  require
    (plannedCrosscalls == crosscallPlan.crosscalls)
    "full module crosscall helpers must be discovered from entrypoint plans"
  let counterPlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan ProofForge.IR.Examples.Counter.module)
      "counter full module plan for planned crosscall helper injection"
  let rawCounterCrosscalls ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildCrosscallHelperPlans ProofForge.IR.Examples.Counter.module)
      "counter raw crosscall helper discovery"
  require rawCounterCrosscalls.isEmpty
    "counter raw IR should not contain crosscall helpers"
  let injectedEntrypoints := counterPlan.entrypoints.map fun entrypoint =>
    if entrypoint.name == "get" then
      { entrypoint with
        body := #[
          StmtPlan.return
            (ExprPlan.crosscall
              ProofForge.Backend.Evm.Plan.CrosscallMode.staticcall
              (ExprPlan.literalWord 111)
              (ExprPlan.literalWord 222)
              none
              #[
                CrosscallArgWordPlan.expr (.literalWord 9),
                CrosscallArgWordPlan.expr (.literalWord 10)
              ]
              .u64)
        ]
      }
    else
      entrypoint
  let injectedCrosscalls ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildCrosscallHelperPlansFromEntrypoints
        ProofForge.IR.Examples.Counter.module
        injectedEntrypoints)
      "injected planned crosscall helper discovery"
  let expectedSpec ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.crosscallHelperSpec
        ProofForge.IR.Examples.Counter.module
        "planned crosscall return"
        2
        .u64
        ProofForge.Backend.Evm.Plan.CrosscallMode.staticcall)
      "expected injected planned crosscall helper spec"
  require
    (injectedCrosscalls.any (fun spec => spec == expectedSpec))
    "planned entrypoint body scanner must discover injected staticcall helper"

def testPlannedCreateHelperDiscoveryFromEntrypointPlans : IO Unit := do
  let crosscallPlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan ProofForge.IR.Examples.EvmCrosscallProbe.module)
      "crosscall probe full module plan for planned create helper discovery"
  let plannedCreates :=
    ProofForge.Backend.Evm.Lower.buildCreateHelperPlansFromEntrypoints crosscallPlan.entrypoints
  require
    (plannedCreates == crosscallPlan.creates)
    "full module create helpers must be discovered from entrypoint plans"
  let targetPlanCreates ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlanWithTargetPlan
        ProofForge.IR.Examples.EvmCrosscallProbe.module
        crosscallPlan.targetPlan)
      "crosscall probe target-plan full module plan for planned create helper discovery"
  require
    (targetPlanCreates.creates == crosscallPlan.creates)
    "target-plan full module create helpers must be discovered from entrypoint plans"
  let counterPlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan ProofForge.IR.Examples.Counter.module)
      "counter full module plan for planned create helper injection"
  let rawCounterCreates :=
    ProofForge.Backend.Evm.Lower.buildCreateHelperPlans ProofForge.IR.Examples.Counter.module
  require rawCounterCreates.isEmpty
    "counter raw IR should not contain create helpers"
  let initCodeHex := ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex
  let injectedEntrypoints := counterPlan.entrypoints.map fun entrypoint =>
    if entrypoint.name == "get" then
      { entrypoint with
        body := #[
          StmtPlan.letBind
            "deployed"
            .address
            (ExprPlan.create
              ProofForge.Backend.Evm.Plan.CreateMode.create
              (ExprPlan.literalWord 0)
              none
              initCodeHex),
          StmtPlan.return
            (ExprPlan.create
              ProofForge.Backend.Evm.Plan.CreateMode.create2
              (ExprPlan.literalWord 0)
              (some (ExprPlan.literalWord 42))
              initCodeHex)
        ]
      }
    else
      entrypoint
  let injectedCreates :=
    ProofForge.Backend.Evm.Lower.buildCreateHelperPlansFromEntrypoints injectedEntrypoints
  require
    (injectedCreates.any fun spec =>
      spec == { mode := ProofForge.Backend.Evm.Plan.CreateMode.create, initCodeHex })
    "planned entrypoint body scanner must discover injected create helper"
  require
    (injectedCreates.any fun spec =>
      spec == { mode := ProofForge.Backend.Evm.Plan.CreateMode.create2, initCodeHex })
    "planned entrypoint body scanner must discover injected create2 helper"

def testPlannedMemoryArrayHelperDiscoveryFromEntrypointPlans : IO Unit := do
  let rawLengthPlan ←
    requireOk
      (lowerPlan (ProofForge.Backend.Evm.Plan.buildModulePlan memoryArrayLengthOnlyProbe))
      "memory-array length-only raw module plan"
  require
    (rawLengthPlan.hasHelper .memoryArrayNew)
    "raw memory-array capability helper discovery includes new helper"
  require
    (rawLengthPlan.hasHelper .memoryArrayGet)
    "raw memory-array capability helper discovery includes get helper"
  let lengthPlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan memoryArrayLengthOnlyProbe)
      "memory-array length-only full module plan"
  require
    (!lengthPlan.hasHelper .memoryArrayNew)
    "planned memory-array length-only helper discovery must not require new helper"
  require
    (!lengthPlan.hasHelper .memoryArrayGet)
    "planned memory-array length-only helper discovery must not require get helper"
  require
    (ProofForge.Backend.Evm.Lower.buildMemoryArrayHelpersFromEntrypoints lengthPlan.entrypoints).isEmpty
    "planned memory-array length-only entrypoint scanner must be empty"
  require
    (plannedMemoryArrayHelperFunctions lengthPlan).isEmpty
    "planned memory-array length-only ToYul helper emission must be empty"
  let targetLengthPlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlanWithTargetPlan
        memoryArrayLengthOnlyProbe
        lengthPlan.targetPlan)
      "memory-array length-only target-plan full module plan"
  require
    (targetLengthPlan.helpers == lengthPlan.helpers)
    "target-plan full module memory-array helpers must be discovered from entrypoint plans"
  let newPlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan memoryArrayNewOnlyProbe)
      "memory-array new-only full module plan"
  let newSemanticPlan ←
    requireOk
      (buildSemanticPlan memoryArrayNewOnlyProbe)
      "memory-array new-only semantic plan"
  require
    (newSemanticPlan.helpers == newPlan.helpers)
    "semantic plan must preserve Lower-discovered memory-array new helper"
  require
    (newPlan.hasHelper .memoryArrayNew)
    "planned memory-array new-only helper discovery must require new helper"
  require
    (!newPlan.hasHelper .memoryArrayGet)
    "planned memory-array new-only helper discovery must not require get helper"
  let newHelpers := plannedMemoryArrayHelperFunctions newPlan
  require
    (statementsHaveFunctionNamed newHelpers (Helper.memoryArrayNew).name)
    "planned memory-array new-only ToYul helpers include new helper"
  require
    (!statementsHaveFunctionNamed newHelpers (Helper.memoryArrayGet).name)
    "planned memory-array new-only ToYul helpers must not include get helper"
  let getPlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan memoryArrayGetOnlyProbe)
      "memory-array get-only full module plan"
  let getSemanticPlan ←
    requireOk
      (buildSemanticPlan memoryArrayGetOnlyProbe)
      "memory-array get-only semantic plan"
  require
    (getSemanticPlan.helpers == getPlan.helpers)
    "semantic plan must preserve Lower-discovered memory-array get helper"
  require
    (!getPlan.hasHelper .memoryArrayNew)
    "planned memory-array get-only helper discovery must not require new helper"
  require
    (getPlan.hasHelper .memoryArrayGet)
    "planned memory-array get-only helper discovery must require get helper"
  let getHelpers := plannedMemoryArrayHelperFunctions getPlan
  require
    (!statementsHaveFunctionNamed getHelpers (Helper.memoryArrayNew).name)
    "planned memory-array get-only ToYul helpers must not include new helper"
  require
    (statementsHaveFunctionNamed getHelpers (Helper.memoryArrayGet).name)
    "planned memory-array get-only ToYul helpers include get helper"

def testPlannedHashHelperDiscoveryFromEntrypointPlans : IO Unit := do
  let rawWordPlan ←
    requireOk
      (lowerPlan (ProofForge.Backend.Evm.Plan.buildModulePlan hashWordOnlyProbe))
      "hash-word-only raw module plan"
  require
    (rawWordPlan.hasHelper .hashWord)
    "raw hash capability helper discovery includes hash-word helper"
  require
    (rawWordPlan.hasHelper .hashPair)
    "raw hash capability helper discovery includes hash-pair helper"
  let wordPlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan hashWordOnlyProbe)
      "hash-word-only full module plan"
  require
    (wordPlan.hasHelper .hashWord)
    "planned hash-word-only helper discovery must require hash-word helper"
  require
    (!wordPlan.hasHelper .hashPair)
    "planned hash-word-only helper discovery must not require hash-pair helper"
  let wordSemanticPlan ←
    requireOk
      (buildSemanticPlan hashWordOnlyProbe)
      "hash-word-only semantic plan"
  require
    (wordSemanticPlan.helpers == wordPlan.helpers)
    "semantic plan must preserve Lower-discovered hash-word helper"
  require
    (ProofForge.Backend.Evm.Lower.buildHashHelpersFromEntrypoints wordPlan.entrypoints ==
      #[Helper.hashWord])
    "planned hash-word-only entrypoint scanner must discover only hash-word helper"
  let wordHelpers := plannedHashHelperFunctions wordPlan
  require
    (statementsHaveFunctionNamed wordHelpers (Helper.hashWord).name)
    "planned hash-word-only ToYul helpers include hash-word helper"
  require
    (!statementsHaveFunctionNamed wordHelpers (Helper.hashPair).name)
    "planned hash-word-only ToYul helpers must not include hash-pair helper"
  let targetWordPlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlanWithTargetPlan
        hashWordOnlyProbe
        wordPlan.targetPlan)
      "hash-word-only target-plan full module plan"
  require
    (targetWordPlan.helpers == wordPlan.helpers)
    "target-plan full module hash helpers must be discovered from entrypoint plans"
  let rawPairPlan ←
    requireOk
      (lowerPlan (ProofForge.Backend.Evm.Plan.buildModulePlan hashPairOnlyProbe))
      "hash-pair-only raw module plan"
  require
    (rawPairPlan.hasHelper .hashWord)
    "raw hash-pair capability helper discovery includes hash-word helper"
  require
    (rawPairPlan.hasHelper .hashPair)
    "raw hash-pair capability helper discovery includes hash-pair helper"
  let pairPlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan hashPairOnlyProbe)
      "hash-pair-only full module plan"
  require
    (!pairPlan.hasHelper .hashWord)
    "planned hash-pair-only helper discovery must not require hash-word helper"
  require
    (pairPlan.hasHelper .hashPair)
    "planned hash-pair-only helper discovery must require hash-pair helper"
  let pairSemanticPlan ←
    requireOk
      (buildSemanticPlan hashPairOnlyProbe)
      "hash-pair-only semantic plan"
  require
    (pairSemanticPlan.helpers == pairPlan.helpers)
    "semantic plan must preserve Lower-discovered hash-pair helper"
  require
    (ProofForge.Backend.Evm.Lower.buildHashHelpersFromEntrypoints pairPlan.entrypoints ==
      #[Helper.hashPair])
    "planned hash-pair-only entrypoint scanner must discover only hash-pair helper"
  let pairHelpers := plannedHashHelperFunctions pairPlan
  require
    (!statementsHaveFunctionNamed pairHelpers (Helper.hashWord).name)
    "planned hash-pair-only ToYul helpers must not include hash-word helper"
  require
    (statementsHaveFunctionNamed pairHelpers (Helper.hashPair).name)
    "planned hash-pair-only ToYul helpers include hash-pair helper"

def testPlannedMapHelperDiscoveryFromEntrypointPlans : IO Unit := do
  let rawUnused ←
    requireOk
      (lowerPlan (ProofForge.Backend.Evm.Plan.buildModulePlan mapUnusedProbe))
      "map-unused raw module plan"
  require
    (rawUnused.hasHelper .mapSlot)
    "raw map helper discovery includes map slot helper"
  require
    (rawUnused.hasHelper .mapPresenceSlot)
    "raw map helper discovery includes map presence slot helper"
  require
    (rawUnused.hasHelper .mapWrite)
    "raw map helper discovery includes map write helper"
  require
    (rawUnused.hasHelper .mapSetReturn)
    "raw map helper discovery includes map set-return helper"
  let unused ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan mapUnusedProbe)
      "map-unused full module plan"
  require
    (!unused.hasHelper .mapSlot)
    "planned map-unused helper discovery must not require map slot helper"
  require
    (!unused.hasHelper .mapPresenceSlot)
    "planned map-unused helper discovery must not require map presence slot helper"
  require
    (!unused.hasHelper .mapWrite)
    "planned map-unused helper discovery must not require map write helper"
  require
    (!unused.hasHelper .mapSetReturn)
    "planned map-unused helper discovery must not require map set-return helper"
  require unused.mapAssignOps.isEmpty
    "planned map-unused helper discovery must not retain map assign ops"
  require
    (ProofForge.Backend.Evm.Lower.buildMapHelpersFromEntrypoints unused.entrypoints).isEmpty
    "planned map-unused entrypoint scanner must be empty"
  require
    (plannedMapHelperFunctions unused).isEmpty
    "planned map-unused ToYul helper emission must be empty"
  let unusedSemantic ←
    requireOk
      (buildSemanticPlan mapUnusedProbe)
      "map-unused semantic plan"
  require
    (unusedSemantic.helpers == unused.helpers)
    "semantic plan must preserve Lower-discovered map helper absence"
  let targetUnused ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlanWithTargetPlan
        mapUnusedProbe
        unused.targetPlan)
      "map-unused target-plan full module plan"
  require
    (targetUnused.helpers == unused.helpers)
    "target-plan full module map helpers must be discovered from entrypoint plans"
  let contains ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan mapContainsOnlyProbe)
      "map-contains-only full module plan"
  require
    (!contains.hasHelper .mapSlot)
    "planned map-contains-only helper discovery must not require map slot helper"
  require
    (contains.hasHelper .mapPresenceSlot)
    "planned map-contains-only helper discovery must require map presence slot helper"
  require
    (!contains.hasHelper .mapWrite)
    "planned map-contains-only helper discovery must not require map write helper"
  require
    (!contains.hasHelper .mapSetReturn)
    "planned map-contains-only helper discovery must not require map set-return helper"
  let containsHelpers := plannedMapHelperFunctions contains
  require (containsHelpers.size == 1) "planned map-contains-only ToYul helper count"
  require
    (statementsHaveFunctionNamed containsHelpers (Helper.mapPresenceSlot).name)
    "planned map-contains-only ToYul helpers include map presence slot"
  let get ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan mapGetOnlyProbe)
      "map-get-only full module plan"
  require
    (get.hasHelper .mapSlot)
    "planned map-get-only helper discovery must require map slot helper"
  require
    (!get.hasHelper .mapPresenceSlot)
    "planned map-get-only helper discovery must not require map presence slot helper"
  require
    (!get.hasHelper .mapWrite)
    "planned map-get-only helper discovery must not require map write helper"
  require
    (!get.hasHelper .mapSetReturn)
    "planned map-get-only helper discovery must not require map set-return helper"
  let getHelpers := plannedMapHelperFunctions get
  require (getHelpers.size == 1) "planned map-get-only ToYul helper count"
  require
    (statementsHaveFunctionNamed getHelpers (Helper.mapSlot).name)
    "planned map-get-only ToYul helpers include map slot"
  let write ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan mapWriteOnlyProbe)
      "map-write-only full module plan"
  require
    (write.hasHelper .mapSlot)
    "planned map-write-only helper discovery must require map slot dependency"
  require
    (write.hasHelper .mapPresenceSlot)
    "planned map-write-only helper discovery must require map presence slot dependency"
  require
    (write.hasHelper .mapWrite)
    "planned map-write-only helper discovery must require map write helper"
  require
    (!write.hasHelper .mapSetReturn)
    "planned map-write-only helper discovery must not require map set-return helper"
  require write.mapAssignOps.isEmpty
    "planned map-write-only helper discovery must not retain map assign ops"
  let writeHelpers := plannedMapHelperFunctions write
  require (writeHelpers.size == 3) "planned map-write-only ToYul helper count"
  require
    (!statementsHaveFunctionNamed writeHelpers (Helper.mapSetReturn).name)
    "planned map-write-only ToYul helpers must not include map set-return"
  let setReturn ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan mapSetReturnOnlyProbe)
      "map-set-return-only full module plan"
  require
    (setReturn.hasHelper .mapSlot)
    "planned map-set-return-only helper discovery must require map slot dependency"
  require
    (setReturn.hasHelper .mapPresenceSlot)
    "planned map-set-return-only helper discovery must require map presence slot dependency"
  require
    (!setReturn.hasHelper .mapWrite)
    "planned map-set-return-only helper discovery must not require map write helper"
  require
    (setReturn.hasHelper .mapSetReturn)
    "planned map-set-return-only helper discovery must require map set-return helper"
  let setReturnHelpers := plannedMapHelperFunctions setReturn
  require (setReturnHelpers.size == 3) "planned map-set-return-only ToYul helper count"
  require
    (!statementsHaveFunctionNamed setReturnHelpers (Helper.mapWrite).name)
    "planned map-set-return-only ToYul helpers must not include map write"
  let assign ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan mapAssignOnlyProbe)
      "map-assign-only full module plan"
  require
    (assign.hasHelper .mapSlot)
    "planned map-assign-only helper discovery must require map slot dependency"
  require
    (assign.hasHelper .mapPresenceSlot)
    "planned map-assign-only helper discovery must require map presence slot dependency"
  require
    (!assign.hasHelper .mapWrite)
    "planned map-assign-only helper discovery must not require map write helper"
  require
    (!assign.hasHelper .mapSetReturn)
    "planned map-assign-only helper discovery must not require map set-return helper"
  require
    (assign.hasHelper (Helper.mapAssign .add))
    "planned map-assign-only helper discovery must require map assign add helper"
  require
    (assign.mapAssignOps == #[.add])
    "planned map-assign-only helper discovery must retain only add assign op"
  let assignHelpers := plannedMapHelperFunctions assign
  require (assignHelpers.size == 3) "planned map-assign-only ToYul helper count"
  require
    (statementsHaveFunctionNamed assignHelpers (Helper.mapAssign .add).name)
    "planned map-assign-only ToYul helpers include map assign add"
  require
    (!statementsHaveFunctionNamed assignHelpers (Helper.mapWrite).name)
    "planned map-assign-only ToYul helpers must not include map write"

def testPlannedStorageArrayHelperDiscoveryFromEntrypointPlans : IO Unit := do
  let rawArrayUnused ←
    requireOk
      (lowerPlan (ProofForge.Backend.Evm.Plan.buildModulePlan storageArrayUnusedProbe))
      "storage-array-unused raw module plan"
  require
    (rawArrayUnused.hasHelper .arraySlot)
    "raw storage-array helper discovery includes fixed array slot helper"
  let arrayUnused ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan storageArrayUnusedProbe)
      "storage-array-unused full module plan"
  require
    (!arrayUnused.hasHelper .arraySlot)
    "planned storage-array-unused helper discovery must not require fixed array slot helper"
  let arrayUnusedSemantic ←
    requireOk
      (buildSemanticPlan storageArrayUnusedProbe)
      "storage-array-unused semantic plan"
  require
    (arrayUnusedSemantic.helpers == arrayUnused.helpers)
    "semantic plan must preserve Lower-discovered storage-array helper absence"
  require
    (ProofForge.Backend.Evm.Lower.buildStorageArrayHelpersFromEntrypoints arrayUnused.entrypoints).isEmpty
    "planned storage-array-unused entrypoint scanner must be empty"
  require
    (plannedArrayHelperFunctions arrayUnused).isEmpty
    "planned storage-array-unused ToYul helper emission must be empty"
  let targetArrayUnused ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlanWithTargetPlan
        storageArrayUnusedProbe
        arrayUnused.targetPlan)
      "storage-array-unused target-plan full module plan"
  require
    (targetArrayUnused.helpers == arrayUnused.helpers)
    "target-plan full module fixed-array helpers must be discovered from entrypoint plans"
  let rawDynamicUnused ←
    requireOk
      (lowerPlan (ProofForge.Backend.Evm.Plan.buildModulePlan dynamicArrayUnusedProbe))
      "dynamic-array-unused raw module plan"
  require
    (rawDynamicUnused.hasHelper .dynamicArraySlot)
    "raw dynamic-array helper discovery includes dynamic array slot helper"
  let dynamicUnused ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan dynamicArrayUnusedProbe)
      "dynamic-array-unused full module plan"
  require
    (!dynamicUnused.hasHelper .dynamicArraySlot)
    "planned dynamic-array-unused helper discovery must not require dynamic array slot helper"
  require
    (plannedDynamicArrayHelperFunctions dynamicUnused).isEmpty
    "planned dynamic-array-unused ToYul helper emission must be empty"
  let rawStructUnused ←
    requireOk
      (lowerPlan (ProofForge.Backend.Evm.Plan.buildModulePlan structArrayUnusedProbe))
      "struct-array-unused raw module plan"
  require
    (rawStructUnused.hasHelper .structArraySlot)
    "raw struct-array helper discovery includes struct array slot helper"
  let structUnused ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan structArrayUnusedProbe)
      "struct-array-unused full module plan"
  require
    (!structUnused.hasHelper .structArraySlot)
    "planned struct-array-unused helper discovery must not require struct array slot helper"
  require
    (plannedStructArrayHelperFunctions structUnused).isEmpty
    "planned struct-array-unused ToYul helper emission must be empty"
  let arrayPlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan ProofForge.IR.Examples.EvmStorageArrayProbe.module)
      "storage array probe full module plan"
  require
    (ProofForge.Backend.Evm.Lower.buildStorageArrayHelpersFromEntrypoints arrayPlan.entrypoints |>.contains .arraySlot)
    "planned storage-array scanner must discover fixed array slot helper"
  require
    (arrayPlan.hasHelper .arraySlot)
    "planned storage-array probe helper discovery must require fixed array slot helper"
  let dynamicPlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan ProofForge.IR.Examples.EvmDynamicArrayProbe.module)
      "dynamic array probe full module plan"
  require
    (ProofForge.Backend.Evm.Lower.buildStorageArrayHelpersFromEntrypoints dynamicPlan.entrypoints |>.contains .dynamicArraySlot)
    "planned storage-array scanner must discover dynamic array slot helper"
  require
    (dynamicPlan.hasHelper .dynamicArraySlot)
    "planned dynamic-array probe helper discovery must require dynamic array slot helper"
  let structPlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan ProofForge.IR.Examples.EvmStorageStructProbe.module)
      "storage struct probe full module plan"
  require
    (ProofForge.Backend.Evm.Lower.buildStorageArrayHelpersFromEntrypoints structPlan.entrypoints |>.contains .structArraySlot)
    "planned storage-array scanner must discover struct array slot helper"
  require
    (structPlan.hasHelper .structArraySlot)
    "planned struct-array probe helper discovery must require struct array slot helper"

def testPlannedCheckedArithmeticDiscoveryFromEntrypointPlans : IO Unit := do
  let counterPlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan ProofForge.IR.Examples.Counter.module)
      "counter full module plan for planned checked arithmetic discovery"
  require
    (ProofForge.Backend.Evm.Lower.entrypointsUseCheckedArithmetic counterPlan.entrypoints ==
      counterPlan.usesCheckedArithmetic)
    "full module checked arithmetic requirement must be discovered from entrypoint plans"
  let targetPlanCounter ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlanWithTargetPlan
        ProofForge.IR.Examples.Counter.module
        counterPlan.targetPlan)
      "counter target-plan full module plan for planned checked arithmetic discovery"
  require
    (targetPlanCounter.usesCheckedArithmetic == counterPlan.usesCheckedArithmetic)
    "target-plan full module checked arithmetic requirement must be discovered from entrypoint plans"
  let nativePlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan nativeTransferPlanProbe)
      "native transfer full module plan for planned checked arithmetic injection"
  require
    (!ProofForge.Backend.Evm.Validate.moduleUsesCheckedArithmetic nativeTransferPlanProbe)
    "native transfer raw IR should not require checked arithmetic helpers"
  require
    (!ProofForge.Backend.Evm.Lower.entrypointsUseCheckedArithmetic nativePlan.entrypoints)
    "native transfer planned body should not require checked arithmetic helpers"
  let exprInjectedEntrypoints := nativePlan.entrypoints.map fun entrypoint =>
    if entrypoint.name == "send" then
      { entrypoint with
        body := #[
          StmtPlan.return
            (ExprPlan.checkedArith
              .add
              (ExprPlan.local "target")
              (ExprPlan.literalWord 1))
        ]
      }
    else
      entrypoint
  require
    (ProofForge.Backend.Evm.Lower.entrypointsUseCheckedArithmetic exprInjectedEntrypoints)
    "planned entrypoint body scanner must discover injected checked arithmetic expression"
  let assignOpInjectedEntrypoints := nativePlan.entrypoints.map fun entrypoint =>
    if entrypoint.name == "send" then
      { entrypoint with
        body := #[
          StmtPlan.letMutBind "value" .u64 (ExprPlan.literalWord 1),
          StmtPlan.assignOp
            (ExprPlan.local "value")
            .add
            (ExprPlan.literalWord 1),
          StmtPlan.return (ExprPlan.local "value")
        ]
      }
    else
      entrypoint
  require
    (ProofForge.Backend.Evm.Lower.entrypointsUseCheckedArithmetic assignOpInjectedEntrypoints)
    "planned entrypoint body scanner must discover injected checked assign-op"

def testPlannedContextOpsDiscoveryFromEntrypointPlans : IO Unit := do
  let plan ←
    requireOk
      (buildSemanticPlan contextOpsPlanProbe)
      "context ops probe semantic plan"
  let lowerPlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan contextOpsPlanProbe)
      "context ops probe full module plan"
  require
    (lowerPlan.contextOps == plan.contextOps)
    "semantic plan must preserve Lower-discovered context ops"
  let plannedContextOps :=
    ProofForge.Backend.Evm.Lower.buildContextOpsFromEntrypoints lowerPlan.entrypoints
  require
    (plannedContextOps == lowerPlan.contextOps)
    "full module context ops must be discovered from entrypoint plans"
  require
    (contextOpsContainField lowerPlan.contextOps .timestamp)
    "full module context ops must include timestamp"
  require
    (contextOpsContainField lowerPlan.contextOps (.blockHash (.literal (.u64 0))))
    "full module context ops must include blockHash"
  let targetPlanContext ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlanWithTargetPlan
        contextOpsPlanProbe
        lowerPlan.targetPlan)
      "context ops probe target-plan full module plan"
  require
    (targetPlanContext.contextOps == lowerPlan.contextOps)
    "target-plan full module context ops must be discovered from entrypoint plans"
  let nativePlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan nativeTransferPlanProbe)
      "native transfer full module plan for planned context ops injection"
  require
    (ProofForge.Backend.Evm.Plan.contextOpsFromModule nativeTransferPlanProbe).isEmpty
    "native transfer raw IR should not contain context ops"
  let injectedEntrypoints := nativePlan.entrypoints.map fun entrypoint =>
    if entrypoint.name == "send" then
      { entrypoint with
        body := #[
          StmtPlan.return
            (ExprPlan.context
              (ContextExprPlan.blockHash
                (ExprPlan.context ContextExprPlan.timestamp)))
        ]
      }
    else
      entrypoint
  let injectedContextOps :=
    ProofForge.Backend.Evm.Lower.buildContextOpsFromEntrypoints injectedEntrypoints
  require
    (contextOpsContainField injectedContextOps (.blockHash (.literal (.u64 0))))
    "planned entrypoint body scanner must discover injected blockHash context op"
  require
    (contextOpsContainField injectedContextOps .timestamp)
    "planned entrypoint body scanner must discover nested blockHash argument context op"
  require
    (injectedContextOps.size == 2)
    "planned entrypoint body scanner must de-duplicate context ops by field name"

def testLocalArrayHelperDiscoveryInLowerPlan : IO Unit := do
  let plan ←
    requireOk
      (buildSemanticPlan ProofForge.IR.Examples.EvmArrayValueProbe.module)
      "array value probe plan"
  let lowerPlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan ProofForge.IR.Examples.EvmArrayValueProbe.module)
      "array value probe lower full module plan"
  require
    (lowerPlan.localArrayGetLengths == plan.localArrayGetLengths)
    "local-array helper discovery must come from Lower.buildFullModulePlan"
  require
    (lowerPlan.nestedLocalArrayGetShapes == plan.nestedLocalArrayGetShapes)
    "nested local-array helper discovery must come from Lower.buildFullModulePlan"
  let plannedRequirements :=
    ProofForge.Backend.Evm.Lower.buildLocalArrayHelperRequirementsFromEntrypoints lowerPlan.entrypoints
  require
    (plannedRequirements.fst == lowerPlan.localArrayGetLengths)
    "full module local-array helpers must be discovered from entrypoint plans"
  require
    (plannedRequirements.snd == lowerPlan.nestedLocalArrayGetShapes)
    "full module nested local-array helpers must be discovered from entrypoint plans"
  let targetPlanArray ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlanWithTargetPlan
        ProofForge.IR.Examples.EvmArrayValueProbe.module
        lowerPlan.targetPlan)
      "array value probe target-plan full module plan for planned local-array helper discovery"
  require
    (targetPlanArray.localArrayGetLengths == lowerPlan.localArrayGetLengths)
    "target-plan full module local-array helpers must be discovered from entrypoint plans"
  require
    (targetPlanArray.nestedLocalArrayGetShapes == lowerPlan.nestedLocalArrayGetShapes)
    "target-plan full module nested local-array helpers must be discovered from entrypoint plans"
  let rawLengths ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildLocalArrayGetLengths
        ProofForge.IR.Examples.EvmArrayValueProbe.module)
      "array value probe raw local-array helper discovery"
  let rawShapes ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildNestedLocalArrayGetShapes
        ProofForge.IR.Examples.EvmArrayValueProbe.module)
      "array value probe raw nested local-array helper discovery"
  for length in lowerPlan.localArrayGetLengths do
    require
      (rawLengths.contains length)
      "legacy raw local-array helper scanner must cover planned length"
  for shape in lowerPlan.nestedLocalArrayGetShapes do
    require
      (rawShapes.any (fun rawShape => rawShape == shape))
      "legacy raw nested local-array helper scanner must cover planned shape"
  require
    (rawLengths.contains 2)
    "legacy raw local-array helper scanner over-approximates nested row helper length"
  require
    (!lowerPlan.localArrayGetLengths.contains 2)
    "planned local-array helper discovery must avoid standalone length-2 helper when nested helper covers it"
  require
    (lowerPlan.usesCheckedArithmetic == plan.usesCheckedArithmetic)
    "checked arithmetic discovery must come from Lower.buildFullModulePlan"
  require
    (plan.localArrayGetLengths.contains 3)
    "array value probe must plan length-3 dynamic local-array getter"
  require
    (plan.nestedLocalArrayGetShapes.any (fun shape => shape == #[2, 2]))
    "array value probe must plan nested 2x2 dynamic local-array getter"
  require
    plan.usesCheckedArithmetic
    "array value probe must plan checked arithmetic helpers"
  let localHelpers :=
    ProofForge.Backend.Evm.ToYul.localArrayGetHelperFunctions plan.localArrayGetLengths
  require
    (statementsHaveFunctionNamed localHelpers (ProofForge.Backend.Evm.ToYul.localArrayGetFunctionName 3))
    "local-array ToYul helpers include length-3 getter"
  let nestedHelpers :=
    ProofForge.Backend.Evm.ToYul.nestedLocalArrayGetHelperFunctions plan.nestedLocalArrayGetShapes
  require
    (statementsHaveFunctionNamed nestedHelpers (ProofForge.Backend.Evm.ToYul.nestedLocalArrayGetFunctionName #[2, 2]))
    "nested local-array ToYul helpers include 2x2 getter"
  let object ←
    requireOk
      (lowerModuleWithPlan ProofForge.IR.Examples.EvmArrayValueProbe.module plan)
      "array value probe plan-driven module lowering"
  require
    (statementsHaveFunctionNamed object.code.statements (ProofForge.Backend.Evm.ToYul.localArrayGetFunctionName 3))
    "plan-driven module lowering includes length-3 local-array helper"
  require
    (statementsHaveFunctionNamed object.code.statements (ProofForge.Backend.Evm.ToYul.nestedLocalArrayGetFunctionName #[2, 2]))
    "plan-driven module lowering includes nested local-array helper"
  let nativePlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan nativeTransferPlanProbe)
      "native transfer full module plan for planned local-array helper injection"
  let rawNativeLengths ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildLocalArrayGetLengths nativeTransferPlanProbe)
      "native transfer raw local-array helper discovery"
  let rawNativeShapes ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildNestedLocalArrayGetShapes nativeTransferPlanProbe)
      "native transfer raw nested local-array helper discovery"
  require rawNativeLengths.isEmpty
    "native transfer raw IR should not contain local-array helper requirements"
  require rawNativeShapes.isEmpty
    "native transfer raw IR should not contain nested local-array helper requirements"
  let staticInjectedEntrypoints := nativePlan.entrypoints.map fun entrypoint =>
    if entrypoint.name == "send" then
      { entrypoint with
        body := #[
          StmtPlan.return
            (ExprPlan.localArrayGet "xs" #[ExprPlan.literalWord 1] #[3])
        ]
      }
    else
      entrypoint
  let staticInjectedRequirements :=
    ProofForge.Backend.Evm.Lower.buildLocalArrayHelperRequirementsFromEntrypoints staticInjectedEntrypoints
  require
    (!staticInjectedRequirements.fst.contains 3)
    "planned static local-array get must not require dynamic getter helper"
  require staticInjectedRequirements.snd.isEmpty
    "planned static local-array get must not require nested getter helper"
  let dynamicInjectedEntrypoints := nativePlan.entrypoints.map fun entrypoint =>
    if entrypoint.name == "send" then
      { entrypoint with
        body := #[
          StmtPlan.return
            (ExprPlan.localArrayGet "xs" #[ExprPlan.local "idx"] #[3])
        ]
      }
    else
      entrypoint
  let dynamicInjectedRequirements :=
    ProofForge.Backend.Evm.Lower.buildLocalArrayHelperRequirementsFromEntrypoints dynamicInjectedEntrypoints
  require
    (dynamicInjectedRequirements.fst.contains 3)
    "planned entrypoint body scanner must discover injected dynamic local-array getter"
  require dynamicInjectedRequirements.snd.isEmpty
    "single-dimension local-array get must not require nested helper"
  let nestedInjectedEntrypoints := nativePlan.entrypoints.map fun entrypoint =>
    if entrypoint.name == "send" then
      { entrypoint with
        body := #[
          StmtPlan.return
            (ExprPlan.localArrayGet "matrix" #[ExprPlan.local "row", ExprPlan.literalWord 1] #[2, 2])
        ]
      }
    else
      entrypoint
  let nestedInjectedRequirements :=
    ProofForge.Backend.Evm.Lower.buildLocalArrayHelperRequirementsFromEntrypoints nestedInjectedEntrypoints
  require
    (nestedInjectedRequirements.snd.any (fun shape => shape == #[2, 2]))
    "planned entrypoint body scanner must discover injected nested local-array getter"
  require
    (!nestedInjectedRequirements.fst.contains 2)
    "nested local-array get must require nested helper instead of single-dimension helper"
  let arrayLiteralInjectedEntrypoints := nativePlan.entrypoints.map fun entrypoint =>
    if entrypoint.name == "send" then
      { entrypoint with
        body := #[
          StmtPlan.return
            (ExprPlan.arrayGet
              (ExprPlan.arrayLit .u64 #[ExprPlan.literalWord 10, ExprPlan.literalWord 20])
              (ExprPlan.local "idx"))
        ]
      }
    else
      entrypoint
  let arrayLiteralInjectedRequirements :=
    ProofForge.Backend.Evm.Lower.buildLocalArrayHelperRequirementsFromEntrypoints arrayLiteralInjectedEntrypoints
  require
    (arrayLiteralInjectedRequirements.fst.contains 2)
    "planned entrypoint body scanner must discover injected dynamic array-literal getter"

def testIncompletePlanFallbackCrosscallHelperDiscovery : IO Unit := do
  let crosscallBasePlan ←
    requireOk
      (lowerPlan (ProofForge.Backend.Evm.Plan.buildModulePlan ProofForge.IR.Examples.EvmCrosscallProbe.module))
      "crosscall probe base plan"
  let crosscallFullPlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan ProofForge.IR.Examples.EvmCrosscallProbe.module)
      "crosscall probe full plan"
  let crosscallObject ←
    requireOk
      (lowerModuleWithPlan ProofForge.IR.Examples.EvmCrosscallProbe.module crosscallBasePlan)
      "crosscall probe incomplete-plan fallback lowering"
  for spec in crosscallFullPlan.crosscalls do
    let helperName ←
      requireOk
        (ProofForge.Backend.Evm.ToYul.crosscallHelperFunctionName toYulError spec)
        "fallback crosscall helper name"
    require
      (statementsHaveFunctionNamed crosscallObject.code.statements helperName)
      s!"incomplete-plan fallback includes crosscall helper `{helperName}`"
  for spec in crosscallFullPlan.creates do
    let helperName ←
      requireOk
        (ProofForge.Backend.Evm.ToYul.createHelperFunctionName toYulError spec.mode spec.initCodeHex)
        "fallback create helper name"
    require
      (statementsHaveFunctionNamed crosscallObject.code.statements helperName)
      s!"incomplete-plan fallback includes create helper `{helperName}`"

def testIncompletePlanFallbackLocalArrayHelperDiscovery : IO Unit := do
  let arrayBasePlan ←
    requireOk
      (lowerPlan (ProofForge.Backend.Evm.Plan.buildModulePlan ProofForge.IR.Examples.EvmArrayValueProbe.module))
      "array value probe base plan"
  let arrayFullPlan ←
    requireValidateOk
      (ProofForge.Backend.Evm.Lower.buildFullModulePlan ProofForge.IR.Examples.EvmArrayValueProbe.module)
      "array value probe full plan"
  let arrayObject ←
    requireOk
      (lowerModuleWithPlan ProofForge.IR.Examples.EvmArrayValueProbe.module arrayBasePlan)
      "array value probe incomplete-plan fallback lowering"
  if arrayFullPlan.usesCheckedArithmetic then
    require
      (statementsHaveFunctionNamed arrayObject.code.statements ProofForge.Backend.Evm.ToYul.checkedAddName)
      "incomplete-plan fallback includes checked arithmetic helper"
  for length in arrayFullPlan.localArrayGetLengths do
    let helperName := ProofForge.Backend.Evm.ToYul.localArrayGetFunctionName length
    require
      (statementsHaveFunctionNamed arrayObject.code.statements helperName)
      s!"incomplete-plan fallback includes local-array helper `{helperName}`"
  for shape in arrayFullPlan.nestedLocalArrayGetShapes do
    let helperName := ProofForge.Backend.Evm.ToYul.nestedLocalArrayGetFunctionName shape
    require
      (statementsHaveFunctionNamed arrayObject.code.statements helperName)
      s!"incomplete-plan fallback includes nested local-array helper `{helperName}`"

def testIncompletePlanFallbackHelperDiscovery : IO Unit := do
  testIncompletePlanFallbackCrosscallHelperDiscovery
  testIncompletePlanFallbackLocalArrayHelperDiscovery

def testEntrypointDispatchPlanToYul : IO Unit := do
  let plan ← requireOk (buildSemanticPlan ProofForge.IR.Examples.Counter.module) "counter plan"
  let getEntrypoint ← requireSome
    (plan.entrypoints.find? (fun entrypoint => entrypoint.name == "get"))
    "counter plan missing get entrypoint"
  let getCase ← requireOk
    (ProofForge.Backend.Evm.ToYul.entrypointDispatchCase
      toYulError
      getEntrypoint
      #[revertStmt])
    "entrypoint dispatch case plan-to-yul"
  match getCase.value with
  | some lit =>
      require (lit.value == "0x6d4ce63c") "entrypoint dispatch case selector literal"
  | none => throw <| IO.userError "entrypoint dispatch case must have selector"
  require (getCase.body.statements.size == 1) "entrypoint dispatch case body statement count"
  let directDispatch :=
    ProofForge.Backend.Evm.ToYul.dispatchPlanStatement
      plan.dispatch
      #[getCase]
  match directDispatch with
  | Lean.Compiler.Yul.Statement.switchStmt (Lean.Compiler.Yul.Expr.builtin name args) cases => do
      require (name == "shr") "entrypoint dispatch block helper selector opcode"
      require (args.size == 2) "entrypoint dispatch block helper selector arg count"
      require (cases.size == 2) "entrypoint dispatch block helper case count"
      let defaultCase ← requireAt cases (cases.size - 1) "entrypoint dispatch block helper missing default case"
      require defaultCase.value.isNone "entrypoint dispatch block helper default case value"
      require (defaultCase.body.statements.size == 1) "entrypoint dispatch block helper revert default size"
  | _ => throw <| IO.userError "entrypoint dispatch block helper must lower static params to selector switch"
  let returnStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.staticDispatchReturnStatements
      toYulError
      #[]
      getEntrypoint.returns
      (Lean.Compiler.Yul.call "Counter_get" #[]))
    "entrypoint static dispatch return plan-to-yul"
  require (returnStmts.size == 3) "entrypoint static dispatch return statement count"
  match returnStmts[0]! with
  | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.call name args)) => do
      require (vars.size == 1) "entrypoint static dispatch return result count"
      match vars[0]? with
      | some var => require (var.name == "_r") "entrypoint static dispatch return result name"
      | none => throw <| IO.userError "entrypoint static dispatch return missing result var"
      require (name == "Counter_get") "entrypoint static dispatch return call name"
      require (args.size == 0) "entrypoint static dispatch return call arg count"
  | _ => throw <| IO.userError "entrypoint static dispatch return must bind call result"
  match returnStmts[2]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin name args) => do
      require (name == "return") "entrypoint static dispatch return builtin"
      require (args.size == 2) "entrypoint static dispatch return arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.lit lit => require (lit.value == "32") "entrypoint static dispatch return byte count"
      | _ => throw <| IO.userError "entrypoint static dispatch return byte count must be literal"
  | _ => throw <| IO.userError "entrypoint static dispatch return must end with return"
  let initEntrypoint ← requireSome
    (plan.entrypoints.find? (fun entrypoint => entrypoint.name == "initialize"))
    "counter plan missing initialize entrypoint"
  let unitReturnStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.staticDispatchReturnStatements
      toYulError
      #[]
      initEntrypoint.returns
      (Lean.Compiler.Yul.call "Counter_initialize" #[]))
    "entrypoint unit dispatch return plan-to-yul"
  require (unitReturnStmts.size == 2) "entrypoint unit dispatch return statement count"
  match unitReturnStmts[1]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin name args) => do
      require (name == "return") "entrypoint unit dispatch return builtin"
      require (args.size == 2) "entrypoint unit dispatch return arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.lit lit => require (lit.value == "0") "entrypoint unit dispatch return byte count"
      | _ => throw <| IO.userError "entrypoint unit dispatch return byte count must be literal"
  | _ => throw <| IO.userError "entrypoint unit dispatch return must end with return"
  let dispatch ← requireOk (dispatchBlock ProofForge.IR.Examples.Counter.module) "counter dispatch block"
  match dispatch with
  | Lean.Compiler.Yul.Statement.switchStmt (Lean.Compiler.Yul.Expr.builtin name args) cases => do
      require (name == "shr") "entrypoint dispatch switch selector opcode"
      require (args.size == 2) "entrypoint dispatch switch selector arg count"
      require (cases.size == plan.entrypoints.size + 1) "entrypoint dispatch switch case count"
  | _ => throw <| IO.userError "entrypoint dispatch block must lower to selector switch"
  let dynamicPlan ← requireOk
    (buildSemanticPlan ProofForge.IR.Examples.EvmDynamicAbiProbe.module)
    "dynamic ABI plan"
  let bytesEntrypoint ← requireSome
    (dynamicPlan.entrypoints.find? (fun entrypoint => entrypoint.name == "echo_bytes"))
    "dynamic ABI plan missing echo_bytes entrypoint"
  let bytesParam ← requireAt bytesEntrypoint.params 0 "dynamic ABI echo_bytes missing param"
  require (bytesParam.headWordIndex == 0) "dynamic ABI bytes param head word index"
  require bytesParam.isDynamic "dynamic ABI bytes param is dynamic"
  require
    (bytesParam.localNames == #["data__length", "data__data_ptr"])
    "dynamic ABI bytes param local names"
  let bytesTypedParams := ProofForge.Backend.Evm.ToYul.entrypointParamTypedNames bytesEntrypoint.params
  require (bytesTypedParams.size == 2) "dynamic ABI bytes function param count"
  match bytesTypedParams[1]? with
  | some param => require (param.name == "data__data_ptr") "dynamic ABI bytes function data ptr param"
  | none => throw <| IO.userError "dynamic ABI bytes function missing data ptr param"
  let bytesDecodeStmts :=
    ProofForge.Backend.Evm.ToYul.abiParamValidationAndDecodeStatements bytesEntrypoint.params
  require (bytesDecodeStmts.size == 9) "dynamic ABI bytes decode statement count"
  match bytesDecodeStmts[bytesDecodeStmts.size - 1]! with
  | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.ident ptrName)) => do
      match vars[0]? with
      | some var => require (var.name == "data__data_ptr") "dynamic ABI bytes data ptr local"
      | none => throw <| IO.userError "dynamic ABI bytes decode missing data ptr var"
      require (ptrName == "__pf_dyn_ptr_data") "dynamic ABI bytes decode data ptr source"
  | _ => throw <| IO.userError "dynamic ABI bytes decode must end with data ptr var"
  let alteredDynamicEntrypoints := dynamicPlan.entrypoints.map fun entrypoint =>
    if entrypoint.name == "echo_bytes" then
      { entrypoint with
        body := #[StmtPlan.return (ExprPlan.local "payload")]
      }
    else
      entrypoint
  let alteredDynamicPlan := { dynamicPlan with entrypoints := alteredDynamicEntrypoints }
  let alteredDynamicObject ← requireOk
    (lowerModuleWithPlan ProofForge.IR.Examples.EvmDynamicAbiProbe.module alteredDynamicPlan)
    "dynamic ABI altered entrypoint plan-driven module lowering"
  let alteredBytesEntrypoint ← requireSome
    (alteredDynamicPlan.entrypoints.find? (fun entrypoint => entrypoint.name == "echo_bytes"))
    "dynamic ABI altered plan missing echo_bytes entrypoint"
  let alteredBytesFunctionName :=
    ProofForge.Backend.Evm.ToYul.entrypointPlanFunctionName
      ProofForge.IR.Examples.EvmDynamicAbiProbe.module.name
      alteredBytesEntrypoint
  let alteredBytesBody ← requireSome
    (functionBody? alteredDynamicObject.code.statements alteredBytesFunctionName)
    "dynamic ABI altered plan function body missing"
  require (blockHasAssignmentIdent alteredBytesBody "result" "payload__data_ptr")
    "plan-driven entrypoint lowering must consume dynamic return ModulePlan body"
  let aggregateReturnPlan ← requireOk
    (buildSemanticPlan ProofForge.IR.Examples.EvmAbiAggregateProbe.module)
    "ABI aggregate return plan"
  let alteredAggregateReturnEntrypoints := aggregateReturnPlan.entrypoints.map fun entrypoint =>
    if entrypoint.name == "make_pair" then
      { entrypoint with
        body := #[
          StmtPlan.return
            (ExprPlan.structLit "Pair" #[
              ("left", ExprPlan.literalWord 77),
              ("right", ExprPlan.literalWord 88)
            ])
        ]
      }
    else
      entrypoint
  let alteredAggregateReturnPlan :=
    { aggregateReturnPlan with entrypoints := alteredAggregateReturnEntrypoints }
  let alteredAggregateReturnObject ← requireOk
    (lowerModuleWithPlan
      ProofForge.IR.Examples.EvmAbiAggregateProbe.module
      alteredAggregateReturnPlan)
    "ABI aggregate altered return plan-driven module lowering"
  let alteredMakePairEntrypoint ← requireSome
    (alteredAggregateReturnPlan.entrypoints.find? (fun entrypoint => entrypoint.name == "make_pair"))
    "ABI aggregate altered plan missing make_pair entrypoint"
  let alteredMakePairFunctionName :=
    ProofForge.Backend.Evm.ToYul.entrypointPlanFunctionName
      ProofForge.IR.Examples.EvmAbiAggregateProbe.module.name
      alteredMakePairEntrypoint
  let alteredMakePairBody ← requireSome
    (functionBody? alteredAggregateReturnObject.code.statements alteredMakePairFunctionName)
    "ABI aggregate altered plan function body missing"
  require (blockHasAssignmentNat alteredMakePairBody "__proof_forge_return_0" 77)
    "plan-driven entrypoint lowering must consume aggregate return word 77"
  require (blockHasAssignmentNat alteredMakePairBody "__proof_forge_return_1" 88)
    "plan-driven entrypoint lowering must consume aggregate return word 88"
  let storageStructPlan ← requireOk
    (buildSemanticPlan ProofForge.IR.Examples.EvmStorageStructProbe.module)
    "storage struct return plan"
  let alteredStorageStructEntrypoints := storageStructPlan.entrypoints.map fun entrypoint =>
    if entrypoint.name == "whole_struct_return" then
      { entrypoint with
        body := #[
          StmtPlan.return
            (ExprPlan.effect (EffectPlan.storageScalarRead "current"))
        ]
      }
    else
      entrypoint
  let alteredStorageStructPlan :=
    { storageStructPlan with entrypoints := alteredStorageStructEntrypoints }
  let alteredStorageStructObject ← requireOk
    (lowerModuleWithPlan
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      alteredStorageStructPlan)
    "storage struct altered return plan-driven module lowering"
  let alteredWholeStructEntrypoint ← requireSome
    (alteredStorageStructPlan.entrypoints.find? (fun entrypoint => entrypoint.name == "whole_struct_return"))
    "storage struct altered plan missing whole_struct_return entrypoint"
  let alteredWholeStructFunctionName :=
    ProofForge.Backend.Evm.ToYul.entrypointPlanFunctionName
      ProofForge.IR.Examples.EvmStorageStructProbe.module.name
      alteredWholeStructEntrypoint
  let alteredWholeStructBody ← requireSome
    (functionBody? alteredStorageStructObject.code.statements alteredWholeStructFunctionName)
    "storage struct altered plan function body missing"
  require (blockHasAssignmentSloadSlot alteredWholeStructBody "__proof_forge_return_0" 1)
    "plan-driven entrypoint lowering must consume storage struct return slot 1"
  require (blockHasAssignmentSloadSlot alteredWholeStructBody "__proof_forge_return_1" 2)
    "plan-driven entrypoint lowering must consume storage struct return slot 2"
  require (!blockHasSstore alteredWholeStructBody)
    "plan-driven storage struct return body must not fall back to portable IR storage writes"
  let crosscallPlan ← requireOk
    (buildSemanticPlan ProofForge.IR.Examples.EvmCrosscallProbe.module)
    "crosscall aggregate return plan"
  let alteredCrosscallEntrypoints := crosscallPlan.entrypoints.map fun entrypoint =>
    if entrypoint.name == "call_remote_pair" then
      { entrypoint with
        body := #[
          StmtPlan.return
            (ExprPlan.crosscall
              ProofForge.Backend.Evm.Plan.CrosscallMode.call
              (ExprPlan.literalWord 111)
              (ExprPlan.literalWord 222)
              none
              #[]
              (.structType "RemotePair"))
        ]
      }
    else
      entrypoint
  let alteredCrosscallPlan :=
    { crosscallPlan with entrypoints := alteredCrosscallEntrypoints }
  let alteredCrosscallObject ← requireOk
    (lowerModuleWithPlan
      ProofForge.IR.Examples.EvmCrosscallProbe.module
      alteredCrosscallPlan)
    "crosscall aggregate altered return plan-driven module lowering"
  let alteredCallRemotePairEntrypoint ← requireSome
    (alteredCrosscallPlan.entrypoints.find? (fun entrypoint => entrypoint.name == "call_remote_pair"))
    "crosscall aggregate altered plan missing call_remote_pair entrypoint"
  let alteredCallRemotePairFunctionName :=
    ProofForge.Backend.Evm.ToYul.entrypointPlanFunctionName
      ProofForge.IR.Examples.EvmCrosscallProbe.module.name
      alteredCallRemotePairEntrypoint
  let alteredCallRemotePairBody ← requireSome
    (functionBody? alteredCrosscallObject.code.statements alteredCallRemotePairFunctionName)
    "crosscall aggregate altered plan function body missing"
  require
    (blockHasAssignmentCallNatArgs
      alteredCallRemotePairBody
      #["__proof_forge_return_0", "__proof_forge_return_1"]
      "__proof_forge_crosscall_0_abi_bool_u32"
      #[111, 222])
    "plan-driven entrypoint lowering must consume aggregate crosscall return ModulePlan body"
  let localAggregateCrosscallArgEntrypoint : Entrypoint := {
    name := "planned_pair_arg"
    selector? := some "12345678"
    params := #[
      ("target", .u64),
      ("method", .u64),
      ("pair", .structType "RemotePair")
    ]
    returns := .bool
    body := #[
      .return (.crosscallInvokeTyped
        (.local "target")
        (.local "method")
        #[.local "pair"]
        .bool)
    ]
  }
  let localAggregateCrosscallArgModule :=
    { ProofForge.IR.Examples.EvmCrosscallProbe.module with
      entrypoints :=
        ProofForge.IR.Examples.EvmCrosscallProbe.module.entrypoints.push
          localAggregateCrosscallArgEntrypoint }
  let localAggregateCrosscallArgPlan ← requireOk
    (buildSemanticPlan localAggregateCrosscallArgModule)
    "local aggregate crosscall argument plan"
  let plannedPairArgEntrypoint ← requireSome
    (localAggregateCrosscallArgPlan.entrypoints.find? (fun entrypoint => entrypoint.name == "planned_pair_arg"))
    "local aggregate crosscall argument plan missing entrypoint"
  require
    (stmtPlansSupportPlannedBody plannedPairArgEntrypoint.returns.returnType plannedPairArgEntrypoint.body)
    "local aggregate crosscall argument body must be accepted by planned-body gate"
  match plannedPairArgEntrypoint.body[0]? with
  | some (StmtPlan.return (ExprPlan.crosscall .call _ _ none args .bool)) => do
      require (args.size == 2)
        "local aggregate crosscall argument plan word count"
      let arg0 ← requireAt args 0 "local aggregate crosscall argument plan missing word 0"
      let arg1 ← requireAt args 1 "local aggregate crosscall argument plan missing word 1"
      match arg0, arg1 with
      | CrosscallArgWordPlan.expr (.local word0),
        CrosscallArgWordPlan.expr (.local word1) => do
          require (word0 == "__proof_forge_struct_pair_flag")
            "local aggregate crosscall argument plan word 0"
          require (word1 == "__proof_forge_struct_pair_small")
            "local aggregate crosscall argument plan word 1"
      | _, _ => throw <| IO.userError "local aggregate crosscall argument plan must use planned local word expressions"
  | _ => throw <| IO.userError "local aggregate crosscall argument plan must return crosscall"
  let alteredLocalAggregateCrosscallArgEntrypoints :=
    localAggregateCrosscallArgPlan.entrypoints.map fun entrypoint =>
      if entrypoint.name == "planned_pair_arg" then
        { entrypoint with
          body := #[
            StmtPlan.return
              (ExprPlan.crosscall
                ProofForge.Backend.Evm.Plan.CrosscallMode.call
                (ExprPlan.literalWord 111)
                (ExprPlan.literalWord 222)
                none
                #[
                  CrosscallArgWordPlan.expr (.local "__proof_forge_struct_pair_flag"),
                  CrosscallArgWordPlan.expr (.local "__proof_forge_struct_pair_small")
                ]
                .bool)
          ]
        }
      else
        entrypoint
  let alteredLocalAggregateCrosscallArgPlan :=
    { localAggregateCrosscallArgPlan with entrypoints := alteredLocalAggregateCrosscallArgEntrypoints }
  let alteredLocalAggregateCrosscallArgObject ← requireOk
    (lowerModuleWithPlan
      localAggregateCrosscallArgModule
      alteredLocalAggregateCrosscallArgPlan)
    "local aggregate crosscall argument altered plan-driven module lowering"
  let alteredPlannedPairArgEntrypoint ← requireSome
    (alteredLocalAggregateCrosscallArgPlan.entrypoints.find? (fun entrypoint => entrypoint.name == "planned_pair_arg"))
    "local aggregate crosscall argument altered plan missing entrypoint"
  let alteredPlannedPairArgFunctionName :=
    ProofForge.Backend.Evm.ToYul.entrypointPlanFunctionName
      localAggregateCrosscallArgModule.name
      alteredPlannedPairArgEntrypoint
  let alteredPlannedPairArgBody ← requireSome
    (functionBody? alteredLocalAggregateCrosscallArgObject.code.statements alteredPlannedPairArgFunctionName)
    "local aggregate crosscall argument altered plan function body missing"
  require
    (blockHasAssignmentCallNatPrefixIdentSuffix
      alteredPlannedPairArgBody
      #["result"]
      "__proof_forge_crosscall_2_bool"
      #[111, 222]
      #["__proof_forge_struct_pair_flag", "__proof_forge_struct_pair_small"])
    "plan-driven entrypoint lowering must consume local aggregate crosscall argument ModulePlan body"
  let storageAggregateCrosscallArgEntrypoint : Entrypoint := {
    name := "planned_storage_pair_arg"
    selector? := some "12345679"
    params := #[
      ("target", .u64),
      ("method", .u64)
    ]
    returns := .bool
    body := #[
      .return (.crosscallInvokeTyped
        (.local "target")
        (.local "method")
        #[.effect (.storageScalarRead "current")]
        .bool)
    ]
  }
  let storageAggregateCrosscallArgModule :=
    { ProofForge.IR.Examples.EvmStorageStructProbe.module with
      entrypoints :=
        ProofForge.IR.Examples.EvmStorageStructProbe.module.entrypoints.push
          storageAggregateCrosscallArgEntrypoint }
  let storageAggregateCrosscallArgPlan ← requireOk
    (buildSemanticPlan storageAggregateCrosscallArgModule)
    "storage aggregate crosscall argument plan"
  let plannedStoragePairArgEntrypoint ← requireSome
    (storageAggregateCrosscallArgPlan.entrypoints.find? (fun entrypoint =>
      entrypoint.name == "planned_storage_pair_arg"))
    "storage aggregate crosscall argument plan missing entrypoint"
  require
    (stmtPlansSupportPlannedBody plannedStoragePairArgEntrypoint.returns.returnType plannedStoragePairArgEntrypoint.body)
    "storage aggregate crosscall argument body must be accepted by planned-body gate"
  match plannedStoragePairArgEntrypoint.body[0]? with
  | some (StmtPlan.return (ExprPlan.crosscall .call _ _ none args .bool)) => do
      require (args.size == 2)
        "storage aggregate crosscall argument plan word count"
      let arg0 ← requireAt args 0 "storage aggregate crosscall argument plan missing word 0"
      let arg1 ← requireAt args 1 "storage aggregate crosscall argument plan missing word 1"
      match arg0, arg1 with
      | CrosscallArgWordPlan.expr (.storageLoad (.scalarSlot slot0)),
        CrosscallArgWordPlan.expr (.storageLoad (.scalarSlot slot1)) => do
          require (slot0 == 1)
            "storage aggregate crosscall argument plan storage word 0 slot"
          require (slot1 == 2)
            "storage aggregate crosscall argument plan storage word 1 slot"
      | _, _ => throw <| IO.userError "storage aggregate crosscall argument plan must use planned storage-load words"
  | _ => throw <| IO.userError "storage aggregate crosscall argument plan must return crosscall"
  let alteredStorageAggregateCrosscallArgEntrypoints :=
    storageAggregateCrosscallArgPlan.entrypoints.map fun entrypoint =>
      if entrypoint.name == "planned_storage_pair_arg" then
        { entrypoint with
          body := #[
            StmtPlan.return
              (ExprPlan.crosscall
                ProofForge.Backend.Evm.Plan.CrosscallMode.call
                (ExprPlan.literalWord 333)
                (ExprPlan.literalWord 444)
                none
                #[
                  CrosscallArgWordPlan.expr (.storageLoad (.scalarSlot 1)),
                  CrosscallArgWordPlan.expr (.storageLoad (.scalarSlot 2))
                ]
                .bool)
          ]
        }
      else
        entrypoint
  let alteredStorageAggregateCrosscallArgPlan :=
    { storageAggregateCrosscallArgPlan with entrypoints := alteredStorageAggregateCrosscallArgEntrypoints }
  let alteredStorageAggregateCrosscallArgObject ← requireOk
    (lowerModuleWithPlan
      storageAggregateCrosscallArgModule
      alteredStorageAggregateCrosscallArgPlan)
    "storage aggregate crosscall argument altered plan-driven module lowering"
  let alteredPlannedStoragePairArgEntrypoint ← requireSome
    (alteredStorageAggregateCrosscallArgPlan.entrypoints.find? (fun entrypoint =>
      entrypoint.name == "planned_storage_pair_arg"))
    "storage aggregate crosscall argument altered plan missing entrypoint"
  let alteredPlannedStoragePairArgFunctionName :=
    ProofForge.Backend.Evm.ToYul.entrypointPlanFunctionName
      storageAggregateCrosscallArgModule.name
      alteredPlannedStoragePairArgEntrypoint
  let alteredPlannedStoragePairArgBody ← requireSome
    (functionBody? alteredStorageAggregateCrosscallArgObject.code.statements alteredPlannedStoragePairArgFunctionName)
    "storage aggregate crosscall argument altered plan function body missing"
  require
    (blockHasAssignmentCallNatPrefixSloadSuffix
      alteredPlannedStoragePairArgBody
      #["result"]
      "__proof_forge_crosscall_2_bool"
      #[333, 444]
      #[1, 2])
    "plan-driven entrypoint lowering must consume storage aggregate crosscall argument ModulePlan body"
  let transferEntrypoint ← requireSome
    (dynamicPlan.entrypoints.find? (fun entrypoint => entrypoint.name == "transfer"))
    "dynamic ABI plan missing transfer entrypoint"
  let transferToParam ← requireAt transferEntrypoint.params 0 "transfer missing to param"
  let transferAmountParam ← requireAt transferEntrypoint.params 1 "transfer missing amount param"
  require (transferToParam.headWordIndex == 0) "transfer to param head word index"
  require (transferAmountParam.headWordIndex == 1) "transfer amount param head word index"
  let transferArgs := ProofForge.Backend.Evm.ToYul.entrypointCallArgs transferEntrypoint.params
  require (transferArgs.size == 2) "transfer plan-to-yul call arg count"
  match transferArgs[1]! with
  | Lean.Compiler.Yul.Expr.builtin name args => do
      require (name == "calldataload") "transfer amount call arg load"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.lit lit => require (lit.value == "36") "transfer amount calldata offset"
      | _ => throw <| IO.userError "transfer amount calldata offset must be literal"
  | _ => throw <| IO.userError "transfer amount call arg must be calldata load"
  match ProofForge.Backend.Evm.ToYul.entrypointCallExpr dynamicPlan.name transferEntrypoint with
  | Lean.Compiler.Yul.Expr.call name args => do
      require (name == "f_EvmDynamicAbiProbe_transfer") "transfer plan-to-yul call name"
      require (args.size == 2) "transfer plan-to-yul call arg count"
  | _ => throw <| IO.userError "transfer plan-to-yul call must be a function call"
  let transferFunction :=
    ProofForge.Backend.Evm.ToYul.entrypointFunctionDefinition
      dynamicPlan.name
      transferEntrypoint
      #[revertStmt]
  match transferFunction with
  | Lean.Compiler.Yul.Statement.funcDef name params returns body => do
      require (name == "f_EvmDynamicAbiProbe_transfer") "transfer plan-to-yul function name"
      require (params.size == 2) "transfer plan-to-yul function param count"
      require (returns.size == 1) "transfer plan-to-yul function return count"
      require (body.statements.size == 1) "transfer plan-to-yul function body count"
  | _ => throw <| IO.userError "transfer plan-to-yul function must lower to funcDef"
  let dynamicDirectDispatch :=
    ProofForge.Backend.Evm.ToYul.dispatchPlanStatement
      dynamicPlan.dispatch
      #[getCase]
  match dynamicDirectDispatch with
  | Lean.Compiler.Yul.Statement.block block => do
      require (block.statements.size == 2) "dynamic dispatch block helper statement count"
      match block.statements[0]! with
      | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin name args) => do
          require (name == "mstore") "dynamic dispatch block helper initializes memory"
          require (args.size == 2) "dynamic dispatch block helper memory init arg count"
      | _ => throw <| IO.userError "dynamic dispatch block helper must start with memory init"
      match block.statements[1]! with
      | Lean.Compiler.Yul.Statement.switchStmt (Lean.Compiler.Yul.Expr.builtin name args) _ => do
          require (name == "shr") "dynamic dispatch block helper selector opcode"
          require (args.size == 2) "dynamic dispatch block helper selector arg count"
      | _ => throw <| IO.userError "dynamic dispatch block helper must end with selector switch"
  | _ => throw <| IO.userError "dynamic dispatch block helper must wrap selector switch"
  let dynamicReturnStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.dynamicDispatchReturnStatements
      toYulError
      #[]
      bytesEntrypoint.returns
      (Lean.Compiler.Yul.call "EvmDynamicAbiProbe_echo_bytes" #[Lean.Compiler.Yul.Expr.id "payload"]))
    "entrypoint dynamic dispatch return plan-to-yul"
  require (dynamicReturnStmts.size == 7) "entrypoint dynamic dispatch return statement count"
  match dynamicReturnStmts[0]! with
  | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.call name args)) => do
      match vars[0]? with
      | some var => require (var.name == "_r") "entrypoint dynamic dispatch return result name"
      | none => throw <| IO.userError "entrypoint dynamic dispatch return missing result var"
      require (name == "EvmDynamicAbiProbe_echo_bytes") "entrypoint dynamic dispatch return call name"
      require (args.size == 1) "entrypoint dynamic dispatch return call arg count"
  | _ => throw <| IO.userError "entrypoint dynamic dispatch return must bind call result"
  match dynamicReturnStmts[5]! with
  | Lean.Compiler.Yul.Statement.forLoop _ (Lean.Compiler.Yul.Expr.builtin name args) _ _ => do
      require (name == "lt") "entrypoint dynamic dispatch return copy loop guard"
      require (args.size == 2) "entrypoint dynamic dispatch return copy loop guard arg count"
  | _ => throw <| IO.userError "entrypoint dynamic dispatch return must copy data with loop"
  let dynamicDispatch ← requireOk
    (dispatchBlock ProofForge.IR.Examples.EvmDynamicAbiProbe.module)
    "dynamic ABI dispatch block"
  match dynamicDispatch with
  | Lean.Compiler.Yul.Statement.block block => do
      require (block.statements.size == 2) "dynamic ABI dispatch block statement count"
      match block.statements[1]! with
      | Lean.Compiler.Yul.Statement.switchStmt (Lean.Compiler.Yul.Expr.builtin name args) cases => do
          require (name == "shr") "dynamic ABI dispatch switch selector opcode"
          require (args.size == 2) "dynamic ABI dispatch switch selector arg count"
          require (cases.size == dynamicPlan.entrypoints.size + 1) "dynamic ABI dispatch switch case count"
      | _ => throw <| IO.userError "dynamic ABI dispatch block must contain selector switch"
  | _ => throw <| IO.userError "dynamic ABI dispatch must initialize memory and wrap selector switch"
  let uupsModule := { ProofForge.IR.Examples.Counter.module with evmProxyPattern? := some "uups" }
  let uupsPlan ← requireOk (buildSemanticPlan uupsModule) "UUPS counter plan"
  require (uupsPlan.dispatch.default == .uupsProxy) "UUPS plan dispatch default"
  let uupsDefault := ProofForge.Backend.Evm.ToYul.dispatchDefaultCase uupsPlan.dispatch.default
  require (uupsDefault.value.isNone) "UUPS default case selector"
  require
    (uupsDefault.body.statements.size == ProofForge.Backend.Evm.ToYul.uupsProxyFallbackBody.size)
    "UUPS default case fallback statement count"
  let uupsDispatch ← requireOk (dispatchBlockWithPlan uupsModule uupsPlan.dispatch) "UUPS dispatch block"
  match uupsDispatch with
  | Lean.Compiler.Yul.Statement.switchStmt _ cases => do
      require (cases.size == uupsPlan.dispatch.entrypoints.size + 1) "UUPS dispatch switch case count"
      let defaultCase ← requireAt cases (cases.size - 1) "UUPS dispatch missing default case"
      require
        (defaultCase.body.statements.size == ProofForge.Backend.Evm.ToYul.uupsProxyFallbackBody.size)
        "UUPS dispatch default fallback statement count"
  | _ => throw <| IO.userError "UUPS dispatch block must lower to selector switch"

def testSemanticPlanRender : IO Unit := do
  let rendered ← requireOk (renderSemanticPlan ProofForge.IR.Examples.Counter.module) "counter plan render"
  require (rendered.contains "module: Counter") "counter plan render module"
  require (rendered.contains "target: evm") "counter plan render target"
  require (rendered.contains "entrypoints:") "counter plan render entrypoints"
  require (rendered.contains "initialize") "counter plan render initialize"
  require (rendered.contains "storage:") "counter plan render storage"

def testFallbackReceiveEntrypointPlanLowering : IO Unit := do
  let module := ProofForge.IR.Examples.EvmFallbackProbe.module
  let plan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildFullModulePlan module)
    "fallback probe full module plan"
  require
    (entrypointBodyPlanIsComplete module plan.entrypoints)
    "fallback probe full entrypoint body plan must cover fallback/receive"
  require
    (dispatchEntrypointPlanIsComplete module plan.dispatch.entrypoints)
    "fallback probe dispatch plan must cover only selector entrypoints"
  let rendered ← requireOk (renderModule module) "fallback probe render"
  require
    (rendered.contains "function f_EvmFallbackProbe_increment() {\n      sstore(")
    "fallback probe increment body must not be erased by surface-plan fallback"
  require
    (rendered.contains "function __pf_fallback() {\n      mstore(0, 147028384)")
    "fallback probe fallback body must lower revert payload"
  require
    (rendered.contains "      revert(0, 132)")
    "fallback probe fallback body must revert"
  require
    (rendered.contains "function __pf_receive() {\n      sstore(")
    "fallback probe receive body must not be erased by surface-plan fallback"
  require
    (!rendered.contains "function f_EvmFallbackProbe_increment() { }")
    "fallback probe increment must not lower to empty function"
  require
    (!rendered.contains "function __pf_fallback() { }")
    "fallback probe fallback must not lower to empty function"
  require
    (!rendered.contains "function __pf_receive() { }")
    "fallback probe receive must not lower to empty function"

def testScalarExprPlanToYul : IO Unit := do
  let scalarEnv : TypeEnv := #[
    { name := "target", type := .u64, isMutable := false },
    { name := "amount", type := .u64, isMutable := false },
    { name := "salt", type := .hash, isMutable := false },
    { name := "flag", type := .bool, isMutable := false }
  ]
  let literalPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExpressionExprPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv scalarEnv)
      (.literal (.u64 42)))
    "literal Lower ExprPlan"
  requireLiteralWordPlan literalPlan 42 "literal Lower ExprPlan"
  let directLiteralExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.literal (.u64 42)))
    "direct literal lowers through ExprPlan-to-Yul"
  match directLiteralExpr with
  | Lean.Compiler.Yul.Expr.lit lit =>
      require (lit.value == "42") "direct literal ExprPlan-to-Yul value"
  | _ => throw <| IO.userError "direct literal must lower to Yul literal"
  let boolLiteralPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExpressionExprPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv scalarEnv)
      (.literal (.bool true)))
    "bool literal Lower ExprPlan"
  requireLiteralWordPlan boolLiteralPlan 1 "bool literal Lower ExprPlan"
  let hashLiteralPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExpressionExprPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv scalarEnv)
      (.literal (.hash4 1 2 3 4)))
    "hash literal Lower ExprPlan"
  requireLiteralWordPlan
    hashLiteralPlan
    (← requireValidateOk
      (ProofForge.Backend.Evm.Validate.packedHashLiteral 1 2 3 4)
      "hash literal expected packed value")
    "hash literal Lower ExprPlan"
  let directHashLiteralExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.literal (.hash4 1 2 3 4)))
    "direct hash literal lowers through ExprPlan-to-Yul"
  match directHashLiteralExpr with
  | Lean.Compiler.Yul.Expr.lit lit =>
      require
        (lit.value ==
          toString (← requireValidateOk
            (ProofForge.Backend.Evm.Validate.packedHashLiteral 1 2 3 4)
            "direct hash literal expected packed value"))
        "direct hash literal ExprPlan-to-Yul value"
  | _ => throw <| IO.userError "direct hash literal must lower to Yul literal"
  let localPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExpressionExprPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv scalarEnv)
      (.local "amount"))
    "local Lower ExprPlan"
  match localPlan with
  | .local "amount" => pure ()
  | _ => throw <| IO.userError "local must lower to local ExprPlan"
  let directLocalExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.local "amount"))
    "direct local lowers through ExprPlan-to-Yul"
  match directLocalExpr with
  | Lean.Compiler.Yul.Expr.ident name =>
      require (name == "amount") "direct local ExprPlan-to-Yul name"
  | _ => throw <| IO.userError "direct local must lower to Yul identifier"
  let readExpr ← requireOk
    (lowerExprViaPlan
      ProofForge.IR.Examples.Counter.module
      #[]
      (.effect (.storageScalarRead "count")))
    "counter scalar read plan-to-yul"
  match readExpr with
  | Lean.Compiler.Yul.Expr.builtin name args => do
      -- Packed scalar read: and(shr(shift, sload(slot)), mask)
      require (name == "and") "counter scalar read plan-to-yul opcode (packed read = and)"
      require (args.size == 2) "counter scalar read plan-to-yul arg count (and)"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.lit lit =>
          -- The mask for u64 (8 bytes) is 0xFFFFFFFFFFFFFFFF
          require (lit.value == "18446744073709551615") "counter scalar read plan-to-yul mask"
      | _ => throw <| IO.userError "counter scalar read plan-to-yul mask must be literal"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.builtin shrName shrArgs => do
          require (shrName == "shr") "counter scalar read plan-to-yul inner shr"
          require (shrArgs.size == 2) "counter scalar read plan-to-yul shr arg count"
          match shrArgs[0]! with
          | Lean.Compiler.Yul.Expr.lit lit =>
              require (lit.value == "192") "counter scalar read plan-to-yul shift amount"
          | _ => throw <| IO.userError "counter scalar read plan-to-yul shift must be literal"
          match shrArgs[1]! with
          | Lean.Compiler.Yul.Expr.builtin sloadName sloadArgs => do
              require (sloadName == "sload") "counter scalar read plan-to-yul inner sload"
              require (sloadArgs.size == 1) "counter scalar read plan-to-yul sload arg count"
              match sloadArgs[0]! with
              | Lean.Compiler.Yul.Expr.lit lit =>
                  require (lit.value == "0") "counter scalar read plan-to-yul slot"
              | _ => throw <| IO.userError "counter scalar read plan-to-yul slot must be literal"
          | _ => throw <| IO.userError "counter scalar read plan-to-yul must have sload inside shr"
      | _ => throw <| IO.userError "counter scalar read plan-to-yul must be packed read (and/shr/sload)"
  | _ => throw <| IO.userError "counter scalar read plan-to-yul must be packed read (and/shr/sload)"
  let addExpr ← requireOk
    (lowerExprViaPlan
      ProofForge.IR.Examples.Counter.module
      #[{ name := "n", type := .u64, isMutable := false }]
      (.add (.local "n") (.literal (.u64 1))))
    "counter checked add plan-to-yul"
  match addExpr with
  | Lean.Compiler.Yul.Expr.call name args => do
      require (name == "__pf_checked_add") "counter checked add plan-to-yul helper"
      require (args.size == 2) "counter checked add plan-to-yul arg count"
  | _ => throw <| IO.userError "counter checked add plan-to-yul must be helper call"
  let addPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExpressionExprPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv scalarEnv)
      (.add (.local "amount") (.literal (.u64 1))))
    "add Lower ExprPlan"
  match addPlan with
  | .checkedArith .add (.local "amount") (.literalWord 1) => pure ()
  | _ => throw <| IO.userError "add must lower to checked arithmetic ExprPlan"
  let directAddExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.add (.local "amount") (.literal (.u64 1))))
    "direct add lowers through ExprPlan-to-Yul"
  requireCallExpr
    directAddExpr
    "__pf_checked_add"
    2
    "direct add ExprPlan-to-Yul"
  let directDivExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.div (.local "amount") (.literal (.u64 2))))
    "direct div lowers through ExprPlan-to-Yul"
  match directDivExpr with
  | Lean.Compiler.Yul.Expr.builtin name args => do
      require (name == "div") "direct div ExprPlan-to-Yul opcode"
      require (args.size == 2) "direct div ExprPlan-to-Yul arg count"
  | _ => throw <| IO.userError "direct div must lower to Yul div builtin"
  let powPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExpressionExprPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv scalarEnv)
      (.pow (.local "amount") (.literal (.u64 2))))
    "pow Lower ExprPlan"
  match powPlan with
  | .builtin "exp" args => require (args.size == 2) "pow Lower ExprPlan arg count"
  | _ => throw <| IO.userError "pow must lower to exp builtin ExprPlan"
  let directPowExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.pow (.local "amount") (.literal (.u64 2))))
    "direct pow lowers through ExprPlan-to-Yul"
  match directPowExpr with
  | Lean.Compiler.Yul.Expr.builtin name args => do
      require (name == "exp") "direct pow ExprPlan-to-Yul opcode"
      require (args.size == 2) "direct pow ExprPlan-to-Yul arg count"
  | _ => throw <| IO.userError "direct pow must lower to Yul exp builtin"
  let shiftPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExpressionExprPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv scalarEnv)
      (.shiftLeft (.local "amount") (.literal (.u64 3))))
    "shiftLeft Lower ExprPlan"
  match shiftPlan with
  | .checkedArith .shiftLeft (.local "amount") (.literalWord 3) => pure ()
  | _ => throw <| IO.userError "shiftLeft must lower to checked arithmetic ExprPlan"
  let directShiftExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.shiftLeft (.local "amount") (.literal (.u64 3))))
    "direct shiftLeft lowers through ExprPlan-to-Yul"
  match directShiftExpr with
  | Lean.Compiler.Yul.Expr.builtin name args => do
      require (name == "shl") "direct shiftLeft ExprPlan-to-Yul opcode"
      require (args.size == 2) "direct shiftLeft ExprPlan-to-Yul arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.lit lit =>
          require (lit.value == "3") "direct shiftLeft ExprPlan-to-Yul shift amount"
      | _ => throw <| IO.userError "direct shiftLeft shift amount must be literal"
  | _ => throw <| IO.userError "direct shiftLeft must lower to Yul shl builtin"
  let directBitXorExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.bitXor (.local "amount") (.literal (.u64 255))))
    "direct bitXor lowers through ExprPlan-to-Yul"
  match directBitXorExpr with
  | Lean.Compiler.Yul.Expr.builtin name args => do
      require (name == "xor") "direct bitXor ExprPlan-to-Yul opcode"
      require (args.size == 2) "direct bitXor ExprPlan-to-Yul arg count"
  | _ => throw <| IO.userError "direct bitXor must lower to Yul xor builtin"
  let eqPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExpressionExprPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv scalarEnv)
      (.eq (.local "amount") (.literal (.u64 7))))
    "eq Lower ExprPlan"
  match eqPlan with
  | .builtin "eq" args => require (args.size == 2) "eq Lower ExprPlan arg count"
  | _ => throw <| IO.userError "eq must lower to builtin ExprPlan"
  let directEqExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.eq (.local "amount") (.literal (.u64 7))))
    "direct eq lowers through ExprPlan-to-Yul"
  match directEqExpr with
  | Lean.Compiler.Yul.Expr.builtin name args => do
      require (name == "eq") "direct eq ExprPlan-to-Yul opcode"
      require (args.size == 2) "direct eq ExprPlan-to-Yul arg count"
  | _ => throw <| IO.userError "direct eq must lower to Yul eq builtin"
  let directNeExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.ne (.local "amount") (.literal (.u64 7))))
    "direct ne lowers through ExprPlan-to-Yul"
  match directNeExpr with
  | Lean.Compiler.Yul.Expr.builtin name args => do
      require (name == "iszero") "direct ne ExprPlan-to-Yul outer opcode"
      require (args.size == 1) "direct ne ExprPlan-to-Yul outer arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.builtin innerName innerArgs => do
          require (innerName == "eq") "direct ne ExprPlan-to-Yul inner opcode"
          require (innerArgs.size == 2) "direct ne ExprPlan-to-Yul inner arg count"
      | _ => throw <| IO.userError "direct ne inner expression must be eq builtin"
  | _ => throw <| IO.userError "direct ne must lower to Yul iszero(eq(...))"
  let boolPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExpressionExprPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv scalarEnv)
      (.boolAnd (.local "flag") (.literal (.bool true))))
    "boolAnd Lower ExprPlan"
  match boolPlan with
  | .builtin "and" args => require (args.size == 2) "boolAnd Lower ExprPlan arg count"
  | _ => throw <| IO.userError "boolAnd must lower to builtin ExprPlan"
  let directBoolNotExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.boolNot (.local "flag")))
    "direct boolNot lowers through ExprPlan-to-Yul"
  match directBoolNotExpr with
  | Lean.Compiler.Yul.Expr.builtin name args => do
      require (name == "iszero") "direct boolNot ExprPlan-to-Yul opcode"
      require (args.size == 1) "direct boolNot ExprPlan-to-Yul arg count"
  | _ => throw <| IO.userError "direct boolNot must lower to Yul iszero builtin"
  let castPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExpressionExprPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv scalarEnv)
      (.cast (.local "amount") .u32))
    "cast Lower ExprPlan"
  match castPlan with
  | .cast (.local "amount") .u32 => pure ()
  | _ => throw <| IO.userError "cast must lower to cast ExprPlan"
  let directCastExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.cast (.local "amount") .u32))
    "direct cast lowers through ExprPlan-to-Yul"
  match directCastExpr with
  | Lean.Compiler.Yul.Expr.ident name =>
      require (name == "amount") "direct cast ExprPlan-to-Yul source local"
  | _ => throw <| IO.userError "direct cast must lower to source expression"
  let nativePlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExpressionExprPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv scalarEnv)
      .nativeValue)
    "nativeValue Lower ExprPlan"
  match nativePlan with
  | .nativeValue => pure ()
  | _ => throw <| IO.userError "nativeValue must lower to nativeValue ExprPlan"
  let directNativeExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      .nativeValue)
    "direct nativeValue lowers through ExprPlan-to-Yul"
  match directNativeExpr with
  | Lean.Compiler.Yul.Expr.builtin name args => do
      require (name == "callvalue") "direct nativeValue ExprPlan-to-Yul opcode"
      require (args.isEmpty) "direct nativeValue ExprPlan-to-Yul arg count"
  | _ => throw <| IO.userError "direct nativeValue must lower to Yul callvalue builtin"
  let hashValuePlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExpressionExprPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv scalarEnv)
      (.hashValue
        (.local "amount")
        (.literal (.u64 1))
        (.literal (.u64 2))
        (.literal (.u64 3))))
    "hashValue Lower ExprPlan"
  match hashValuePlan with
  | .hashValue (.local "amount") (.literalWord 1) (.literalWord 2) (.literalWord 3) => pure ()
  | _ => throw <| IO.userError "hashValue must lower to hashValue ExprPlan"
  let directHashValueExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.hashValue
        (.local "amount")
        (.literal (.u64 1))
        (.literal (.u64 2))
        (.literal (.u64 3))))
    "direct hashValue lowers through ExprPlan-to-Yul"
  match directHashValueExpr with
  | Lean.Compiler.Yul.Expr.builtin name args => do
      require (name == "or") "direct hashValue ExprPlan-to-Yul outer opcode"
      require (args.size == 2) "direct hashValue ExprPlan-to-Yul outer arg count"
  | _ => throw <| IO.userError "direct hashValue must lower to packed hash expression"
  let hashPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExpressionExprPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv scalarEnv)
      (.hash (.local "salt")))
    "hash Lower ExprPlan"
  match hashPlan with
  | .hash (.local "salt") => pure ()
  | _ => throw <| IO.userError "hash must lower to hash ExprPlan"
  let directHashExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.hash (.local "salt")))
    "direct hash lowers through ExprPlan-to-Yul"
  requireCallExpr
    directHashExpr
    (ProofForge.Backend.Evm.Plan.Helper.hashWord).name
    1
    "direct hash ExprPlan-to-Yul"
  let hashPairPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExpressionExprPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv scalarEnv)
      (.hashTwoToOne
        (.local "salt")
        (.literal (.hash4 1 2 3 4))))
    "hashTwoToOne Lower ExprPlan"
  match hashPairPlan with
  | .hashTwoToOne (.local "salt") (.literalWord _) => pure ()
  | _ => throw <| IO.userError "hashTwoToOne must lower to hashTwoToOne ExprPlan"
  let directHashPairExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.hashTwoToOne
        (.local "salt")
        (.literal (.hash4 1 2 3 4))))
    "direct hashTwoToOne lowers through ExprPlan-to-Yul"
  requireCallExpr
    directHashPairExpr
    (ProofForge.Backend.Evm.Plan.Helper.hashPair).name
    2
    "direct hashTwoToOne ExprPlan-to-Yul"
  let crosscallPlanExpr ← requireOk
    (lowerExprPlanExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.crosscall
        ProofForge.Backend.Evm.Plan.CrosscallMode.call
        (.local "target")
        (.literalWord 305419896)
        none
        #[CrosscallArgWordPlan.expr (.local "amount")]
        .u32))
    "scalar crosscall ExprPlan-to-Yul"
  requireCallExpr
    crosscallPlanExpr
    "__proof_forge_crosscall_1_u32"
    3
    "scalar crosscall ExprPlan-to-Yul"
  let aggregateArgEnv : TypeEnv := #[
    { name := "target", type := .u64, isMutable := false },
    { name := "p", type := .structType "Point", isMutable := false }
  ]
  let aggregateArgPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExprPlan
      ProofForge.IR.Examples.EvmStructValueProbe.module
      (toValidateTypeEnv aggregateArgEnv)
      (.crosscallInvokeTyped
        (.local "target")
        (.literal (.u64 305419896))
        #[.local "p"]
        .u64))
    "local aggregate crosscall argument Lower ExprPlan"
  match aggregateArgPlan with
  | .crosscall .call _ _ none args .u64 => do
      require (args.size == 2) "local aggregate crosscall argument plan word count"
      let argPlan0 ← requireAt args 0 "local aggregate crosscall argument missing word 0"
      let argPlan1 ← requireAt args 1 "local aggregate crosscall argument missing word 1"
      match argPlan0, argPlan1 with
      | CrosscallArgWordPlan.expr (.local word0),
        CrosscallArgWordPlan.expr (.local word1) => do
          require (word0 == "__proof_forge_struct_p_x") "local aggregate crosscall argument word 0"
          require (word1 == "__proof_forge_struct_p_y") "local aggregate crosscall argument word 1"
      | _, _ => throw <| IO.userError "local aggregate crosscall argument must use planned local word expressions"
  | _ => throw <| IO.userError "local aggregate crosscall argument must lower to call plan"
  let aggregateArgPlanExpr ← requireOk
    (lowerExprPlanExpr
      ProofForge.IR.Examples.EvmStructValueProbe.module
      aggregateArgEnv
      aggregateArgPlan)
    "local aggregate crosscall argument ExprPlan-to-Yul"
  requireCallExpr
    aggregateArgPlanExpr
    "__proof_forge_crosscall_2"
    4
    "local aggregate crosscall argument ExprPlan-to-Yul"
  let storageWordPlans ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.storageCrosscallWordPlans
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      "typed crosscall argument"
      "current"
      (.structType "Point"))
    "storage-backed aggregate crosscall argument Lower word plans"
  require (storageWordPlans.size == 2) "storage-backed aggregate crosscall Lower word plan count"
  let storageXPlan ← requireAt storageWordPlans 0 "storage-backed aggregate crosscall Lower missing x plan"
  match storageXPlan with
  | .storageLoad (.scalarSlot slot) =>
      require (slot == 1) "storage-backed aggregate crosscall Lower x slot"
  | _ => throw <| IO.userError "storage-backed aggregate crosscall Lower x must use storageLoad plan"
  let storageYPlan ← requireAt storageWordPlans 1 "storage-backed aggregate crosscall Lower missing y plan"
  match storageYPlan with
  | .storageLoad (.scalarSlot slot) =>
      require (slot == 2) "storage-backed aggregate crosscall Lower y slot"
  | _ => throw <| IO.userError "storage-backed aggregate crosscall Lower y must use storageLoad plan"
  let aggregateStorageArgPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExprPlan
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      (toValidateTypeEnv #[{ name := "target", type := .u64, isMutable := false }])
      (.crosscallInvokeTyped
        (.local "target")
        (.literal (.u64 305419896))
        #[.effect (.storageScalarRead "current")]
        .u64))
    "storage-backed aggregate crosscall argument Lower ExprPlan"
  match aggregateStorageArgPlan with
  | .crosscall .call _ _ none args .u64 => do
      require (args.size == 2) "storage-backed aggregate crosscall argument plan word count"
      let storageArgPlan0 ← requireAt args 0 "storage-backed aggregate crosscall argument missing word 0"
      let storageArgPlan1 ← requireAt args 1 "storage-backed aggregate crosscall argument missing word 1"
      match storageArgPlan0, storageArgPlan1 with
      | CrosscallArgWordPlan.expr (.storageLoad (.scalarSlot slot0)),
        CrosscallArgWordPlan.expr (.storageLoad (.scalarSlot slot1)) => do
          require (slot0 == 1) "storage-backed aggregate crosscall argument word 0 slot"
          require (slot1 == 2) "storage-backed aggregate crosscall argument word 1 slot"
      | _, _ => throw <| IO.userError "storage-backed aggregate crosscall argument must use planned storage-load words"
  | _ => throw <| IO.userError "storage-backed aggregate crosscall argument must lower to call plan"
  let aggregateStorageArgPlanExpr ← requireOk
    (lowerExprPlanExpr
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      #[{ name := "target", type := .u64, isMutable := false }]
      aggregateStorageArgPlan)
    "storage-backed aggregate crosscall argument ExprPlan-to-Yul"
  requireCallExpr
    aggregateStorageArgPlanExpr
    "__proof_forge_crosscall_2"
    4
    "storage-backed aggregate crosscall argument ExprPlan-to-Yul"
  let aggregateStructLiteralArgPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExprPlan
      ProofForge.IR.Examples.EvmStructValueProbe.module
      (toValidateTypeEnv #[{ name := "target", type := .u64, isMutable := false }])
      (.crosscallInvokeTyped
        (.local "target")
        (.literal (.u64 305419896))
        #[.structLit "Point" #[
          ("x", .literal (.u64 4)),
          ("y", .literal (.u64 6))
        ]]
        .u64))
    "struct literal aggregate crosscall argument Lower ExprPlan"
  match aggregateStructLiteralArgPlan with
  | .crosscall .call _ _ none args .u64 => do
      require (args.size == 2) "struct literal aggregate crosscall argument plan word count"
      requireCrosscallLiteralWordPlan (← requireAt args 0 "struct literal aggregate crosscall argument missing x word") 4
        "struct literal aggregate crosscall argument x word"
      requireCrosscallLiteralWordPlan (← requireAt args 1 "struct literal aggregate crosscall argument missing y word") 6
        "struct literal aggregate crosscall argument y word"
  | _ => throw <| IO.userError "struct literal aggregate crosscall argument must lower to call plan"
  let aggregateStructLiteralArgPlanExpr ← requireOk
    (lowerExprPlanExpr
      ProofForge.IR.Examples.EvmStructValueProbe.module
      #[{ name := "target", type := .u64, isMutable := false }]
      aggregateStructLiteralArgPlan)
    "struct literal aggregate crosscall argument ExprPlan-to-Yul"
  requireCallExpr
    aggregateStructLiteralArgPlanExpr
    "__proof_forge_crosscall_2"
    4
    "struct literal aggregate crosscall argument ExprPlan-to-Yul"
  let aggregateArrayLiteralArgPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExprPlan
      ProofForge.IR.Examples.EvmArrayValueProbe.module
      (toValidateTypeEnv #[{ name := "target", type := .u64, isMutable := false }])
      (.crosscallInvokeTyped
        (.local "target")
        (.literal (.u64 305419896))
        #[.arrayLit .u64 #[
          .literal (.u64 5),
          .literal (.u64 8)
        ]]
        .u64))
    "array literal aggregate crosscall argument Lower ExprPlan"
  match aggregateArrayLiteralArgPlan with
  | .crosscall .call _ _ none args .u64 => do
      require (args.size == 2) "array literal aggregate crosscall argument plan word count"
      requireCrosscallLiteralWordPlan (← requireAt args 0 "array literal aggregate crosscall argument missing element 0 word") 5
        "array literal aggregate crosscall argument element 0 word"
      requireCrosscallLiteralWordPlan (← requireAt args 1 "array literal aggregate crosscall argument missing element 1 word") 8
        "array literal aggregate crosscall argument element 1 word"
  | _ => throw <| IO.userError "array literal aggregate crosscall argument must lower to call plan"
  let aggregateArrayLiteralArgPlanExpr ← requireOk
    (lowerExprPlanExpr
      ProofForge.IR.Examples.EvmArrayValueProbe.module
      #[{ name := "target", type := .u64, isMutable := false }]
      aggregateArrayLiteralArgPlan)
    "array literal aggregate crosscall argument ExprPlan-to-Yul"
  requireCallExpr
    aggregateArrayLiteralArgPlanExpr
    "__proof_forge_crosscall_2"
    4
    "array literal aggregate crosscall argument ExprPlan-to-Yul"
  let aggregateNestedArrayLiteralArgPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExprPlan
      ProofForge.IR.Examples.EvmCrosscallProbe.module
      (toValidateTypeEnv #[{ name := "target", type := .u64, isMutable := false }])
      (.crosscallInvokeTyped
        (.local "target")
        (.literal (.u64 305419896))
        #[ProofForge.IR.Examples.EvmCrosscallProbe.matrix2x2
          (.literal (.u64 1)) (.literal (.u64 2))
          (.literal (.u64 3)) (.literal (.u64 4))]
        .u64))
    "nested array literal aggregate crosscall argument Lower ExprPlan"
  match aggregateNestedArrayLiteralArgPlan with
  | .crosscall .call _ _ none args .u64 => do
      require (args.size == 4) "nested array literal aggregate crosscall argument plan word count"
      requireCrosscallLiteralWordPlan (← requireAt args 0 "nested array literal aggregate crosscall argument missing word 0") 1
        "nested array literal aggregate crosscall argument word 0"
      requireCrosscallLiteralWordPlan (← requireAt args 1 "nested array literal aggregate crosscall argument missing word 1") 2
        "nested array literal aggregate crosscall argument word 1"
      requireCrosscallLiteralWordPlan (← requireAt args 2 "nested array literal aggregate crosscall argument missing word 2") 3
        "nested array literal aggregate crosscall argument word 2"
      requireCrosscallLiteralWordPlan (← requireAt args 3 "nested array literal aggregate crosscall argument missing word 3") 4
        "nested array literal aggregate crosscall argument word 3"
  | _ => throw <| IO.userError "nested array literal aggregate crosscall argument must lower to call plan"
  let aggregateNestedArrayLiteralArgPlanExpr ← requireOk
    (lowerExprPlanExpr
      ProofForge.IR.Examples.EvmCrosscallProbe.module
      #[{ name := "target", type := .u64, isMutable := false }]
      aggregateNestedArrayLiteralArgPlan)
    "nested array literal aggregate crosscall argument ExprPlan-to-Yul"
  requireCallExpr
    aggregateNestedArrayLiteralArgPlanExpr
    "__proof_forge_crosscall_4"
    6
    "nested array literal aggregate crosscall argument ExprPlan-to-Yul"
  let aggregateStructArrayLiteralArgPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExprPlan
      ProofForge.IR.Examples.EvmCrosscallProbe.module
      (toValidateTypeEnv #[{ name := "target", type := .u64, isMutable := false }])
      (.crosscallInvokeTyped
        (.local "target")
        (.literal (.u64 305419896))
        #[.arrayLit (.structType "RemotePair") #[
          ProofForge.IR.Examples.EvmCrosscallProbe.pair (.literal (.bool true)) (.literal (.u32 7)),
          ProofForge.IR.Examples.EvmCrosscallProbe.pair (.literal (.bool false)) (.literal (.u32 9))
        ]]
        .u64))
    "struct-array literal aggregate crosscall argument Lower ExprPlan"
  match aggregateStructArrayLiteralArgPlan with
  | .crosscall .call _ _ none args .u64 => do
      require (args.size == 4) "struct-array literal aggregate crosscall argument plan word count"
      requireCrosscallLiteralWordPlan (← requireAt args 0 "struct-array literal aggregate crosscall argument missing flag 0 word") 1
        "struct-array literal aggregate crosscall argument flag 0 word"
      requireCrosscallLiteralWordPlan (← requireAt args 1 "struct-array literal aggregate crosscall argument missing small 0 word") 7
        "struct-array literal aggregate crosscall argument small 0 word"
      requireCrosscallLiteralWordPlan (← requireAt args 2 "struct-array literal aggregate crosscall argument missing flag 1 word") 0
        "struct-array literal aggregate crosscall argument flag 1 word"
      requireCrosscallLiteralWordPlan (← requireAt args 3 "struct-array literal aggregate crosscall argument missing small 1 word") 9
        "struct-array literal aggregate crosscall argument small 1 word"
  | _ => throw <| IO.userError "struct-array literal aggregate crosscall argument must lower to call plan"
  let aggregateStructArrayLiteralArgPlanExpr ← requireOk
    (lowerExprPlanExpr
      ProofForge.IR.Examples.EvmCrosscallProbe.module
      #[{ name := "target", type := .u64, isMutable := false }]
      aggregateStructArrayLiteralArgPlan)
    "struct-array literal aggregate crosscall argument ExprPlan-to-Yul"
  requireCallExpr
    aggregateStructArrayLiteralArgPlanExpr
    "__proof_forge_crosscall_4"
    6
    "struct-array literal aggregate crosscall argument ExprPlan-to-Yul"
  let nativeTransferPlanExpr ← requireOk
    (lowerExprPlanExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.crosscall
        ProofForge.Backend.Evm.Plan.CrosscallMode.callValue
        (.local "target")
        (.literalWord 0)
        (some .nativeValue)
        #[]
        .u64))
    "native transfer ExprPlan-to-Yul"
  requireCallExpr
    nativeTransferPlanExpr
    "__proof_forge_native_transfer"
    2
    "native transfer ExprPlan-to-Yul"
  let createPlanExpr ← requireOk
    (lowerExprPlanExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.create
        ProofForge.Backend.Evm.Plan.CreateMode.create
        (.literalWord 0)
        none
        ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex))
    "create ExprPlan-to-Yul"
  requireCallExpr
    createPlanExpr
    ("__proof_forge_create_" ++ ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex)
    1
    "create ExprPlan-to-Yul"
  let create2PlanExpr ← requireOk
    (lowerExprPlanExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.create
        ProofForge.Backend.Evm.Plan.CreateMode.create2
        (.literalWord 0)
        (some (.local "salt"))
        ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex))
    "create2 ExprPlan-to-Yul"
  requireCallExpr
    create2PlanExpr
    ("__proof_forge_create2_" ++ ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex)
    2
    "create2 ExprPlan-to-Yul"
  let directCreatePlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExpressionExprPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv scalarEnv)
      (.crosscallCreate
        (.literal (.u64 0))
        ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex))
    "direct create Lower ExprPlan"
  match directCreatePlan with
  | .create .create (.literalWord 0) none initCodeHex => do
      require
        (initCodeHex == ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex)
        "direct create Lower ExprPlan init code"
  | _ => throw <| IO.userError "direct create must lower to create ExprPlan"
  let directCreateExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.crosscallCreate
        (.literal (.u64 0))
        ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex))
    "direct create lowers through ExprPlan-to-Yul"
  requireCallExpr
    directCreateExpr
    ("__proof_forge_create_" ++ ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex)
    1
    "direct create ExprPlan-to-Yul"
  let directCreate2Plan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExpressionExprPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv scalarEnv)
      (.crosscallCreate2
        (.literal (.u64 0))
        (.local "salt")
        ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex))
    "direct create2 Lower ExprPlan"
  match directCreate2Plan with
  | .create .create2 (.literalWord 0) (some (.local "salt")) initCodeHex => do
      require
        (initCodeHex == ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex)
        "direct create2 Lower ExprPlan init code"
  | _ => throw <| IO.userError "direct create2 must lower to create2 ExprPlan"
  let directCreate2Expr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.crosscallCreate2
        (.literal (.u64 0))
        (.local "salt")
        ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex))
    "direct create2 lowers through ExprPlan-to-Yul"
  requireCallExpr
    directCreate2Expr
    ("__proof_forge_create2_" ++ ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex)
    2
    "direct create2 ExprPlan-to-Yul"
  let untypedCrosscallPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExpressionExprPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv scalarEnv)
      (.crosscallInvoke
        (.local "target")
        (.literal (.u64 305419896))
        #[.local "amount"]))
    "untyped scalar crosscall Lower ExprPlan"
  match untypedCrosscallPlan with
  | .crosscall .call _ _ none args .u64 => do
      require (args.size == 1) "untyped scalar crosscall argument count"
      let arg ← requireAt args 0 "untyped scalar crosscall missing argument"
      match arg with
      | CrosscallArgWordPlan.expr (.local "amount") => pure ()
      | _ => throw <| IO.userError "untyped scalar crosscall argument must be scalar expr plan"
  | _ => throw <| IO.userError "untyped scalar crosscall must lower to call ExprPlan"
  let directUntypedCrosscallExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.crosscallInvoke
        (.local "target")
        (.literal (.u64 305419896))
        #[.local "amount"]))
    "direct untyped scalar crosscall lowers through ExprPlan-to-Yul"
  requireCallExpr
    directUntypedCrosscallExpr
    "__proof_forge_crosscall_1"
    3
    "direct untyped scalar crosscall ExprPlan-to-Yul"
  let directCrosscallExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.crosscallInvokeTyped
        (.local "target")
        (.literal (.u64 305419896))
        #[.local "amount"]
        .u32))
    "direct scalar crosscall lowers through ToYul helper-call helper"
  requireCallExpr
    directCrosscallExpr
    "__proof_forge_crosscall_1_u32"
    3
    "direct scalar crosscall ToYul helper-call"
  let aggregateReturnExpr :=
    Expr.crosscallInvokeTyped
      (.local "target")
      (.literal (.u64 305419896))
      #[]
      (.structType "Point")
  requireValidateErrorContains
    (ProofForge.Backend.Evm.Lower.buildExpressionExprPlan
      ProofForge.IR.Examples.EvmStructValueProbe.module
      (toValidateTypeEnv #[{ name := "target", type := .u64, isMutable := false }])
      aggregateReturnExpr)
    "typed aggregate crosscall return `Point` must be consumed by aggregate return lowering in IR EVM v0"
    "Lower expression aggregate typed crosscall return diagnostic"
  requireErrorContains
    (lowerExpr
      ProofForge.IR.Examples.EvmStructValueProbe.module
      #[{ name := "target", type := .u64, isMutable := false }]
      aggregateReturnExpr)
    "typed aggregate crosscall return `Point` must be consumed by aggregate return lowering in IR EVM v0"
    "IR expression aggregate typed crosscall return diagnostic"
  requireValidateErrorContains
    (ProofForge.Backend.Evm.Lower.buildExpressionExprPlan
      ProofForge.IR.Examples.EvmStructValueProbe.module
      (toValidateTypeEnv #[{ name := "target", type := .u64, isMutable := false }])
      (.crosscallInvokeValueTyped
        (.local "target")
        (.literal (.u64 0))
        (.literal (.u64 1))
        #[]
        (.structType "Point")))
    "value aggregate crosscall return `Point` must be consumed by aggregate return lowering in IR EVM v0"
    "Lower expression aggregate value crosscall return diagnostic"
  requireValidateErrorContains
    (ProofForge.Backend.Evm.Lower.buildExpressionExprPlan
      ProofForge.IR.Examples.EvmStructValueProbe.module
      (toValidateTypeEnv #[{ name := "target", type := .u64, isMutable := false }])
      (.crosscallInvokeStaticTyped
        (.local "target")
        (.literal (.u64 305419896))
        #[]
        (.structType "Point")))
    "static aggregate crosscall return `Point` must be consumed by aggregate return lowering in IR EVM v0"
    "Lower expression aggregate static crosscall return diagnostic"
  requireValidateErrorContains
    (ProofForge.Backend.Evm.Lower.buildExpressionExprPlan
      ProofForge.IR.Examples.EvmStructValueProbe.module
      (toValidateTypeEnv #[{ name := "target", type := .u64, isMutable := false }])
      (.crosscallInvokeDelegateTyped
        (.local "target")
        (.literal (.u64 305419896))
        #[]
        (.structType "Point")))
    "delegate aggregate crosscall return `Point` must be consumed by aggregate return lowering in IR EVM v0"
    "Lower expression aggregate delegate crosscall return diagnostic"
  let directNativeTransferExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.crosscallInvokeValueTyped
        (.local "target")
        (.literal (.u64 0))
        .nativeValue
        #[]
        .u64))
    "direct native transfer lowers through ToYul helper-call helper"
  requireCallExpr
    directNativeTransferExpr
    "__proof_forge_native_transfer"
    2
    "direct native transfer ToYul helper-call"
  let arrayEnv : TypeEnv := #[
    { name := "xs", type := .fixedArray .u64 3, isMutable := false },
    { name := "idx", type := .u64, isMutable := false }
  ]
  let staticLocalArrayExpr ← requireOk
    (lowerExprPlanExpr
      ProofForge.IR.Examples.EvmArrayValueProbe.module
      arrayEnv
      (.localArrayGet "xs" #[.literalWord 2] #[3]))
    "static local-array ExprPlan-to-Yul"
  match staticLocalArrayExpr with
  | Lean.Compiler.Yul.Expr.ident name =>
      require (name == "__proof_forge_array_xs_2") "static local-array ExprPlan-to-Yul local name"
  | _ => throw <| IO.userError "static local-array ExprPlan-to-Yul must lower to local identifier"
  let dynamicLocalArrayExpr ← requireOk
    (lowerExprPlanExpr
      ProofForge.IR.Examples.EvmArrayValueProbe.module
      arrayEnv
      (.localArrayGet "xs" #[.local "idx"] #[3]))
    "dynamic local-array ExprPlan-to-Yul"
  requireCallExpr
    dynamicLocalArrayExpr
    "__proof_forge_local_array_get_3"
    4
    "dynamic local-array ExprPlan-to-Yul"
  let directDynamicLocalArrayExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.EvmArrayValueProbe.module
      arrayEnv
      (.arrayGet (.local "xs") (.add (.local "idx") (.literal (.u64 0)))))
    "direct dynamic local-array read lowers through ExprPlan"
  match directDynamicLocalArrayExpr with
  | Lean.Compiler.Yul.Expr.call name args => do
      require (name == "__proof_forge_local_array_get_3") "direct dynamic local-array read helper"
      require (args.size == 4) "direct dynamic local-array read helper arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "direct dynamic local-array read index must lower through ExprPlan"
          require (addArgs.size == 2) "direct dynamic local-array read index helper arg count"
      | _ => throw <| IO.userError "direct dynamic local-array read index must be planned checked add"
  | _ => throw <| IO.userError "direct dynamic local-array read must lower to local-array helper call"
  let staticArrayLiteralExpr ← requireOk
    (lowerExprPlanExpr
      ProofForge.IR.Examples.Counter.module
      arrayEnv
      (.arrayGet
        (.arrayLit .u64 #[.literalWord 5, .literalWord 8])
        (.literalWord 1)))
    "static array-literal ExprPlan-to-Yul"
  match staticArrayLiteralExpr with
  | Lean.Compiler.Yul.Expr.lit lit =>
      require (lit.value == "8") "static array-literal ExprPlan-to-Yul selected value"
  | _ => throw <| IO.userError "static array-literal ExprPlan-to-Yul must select literal value"
  let dynamicArrayLiteralExpr ← requireOk
    (lowerExprPlanExpr
      ProofForge.IR.Examples.Counter.module
      arrayEnv
      (.arrayGet
        (.arrayLit .u64 #[.literalWord 5, .literalWord 8])
        (.local "idx")))
    "dynamic array-literal ExprPlan-to-Yul"
  requireCallExpr
    dynamicArrayLiteralExpr
    "__proof_forge_local_array_get_2"
    3
    "dynamic array-literal ExprPlan-to-Yul"
  let directArrayLiteralExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.Counter.module
      arrayEnv
      (.arrayGet
        (.arrayLit .u64 #[.literal (.u64 5), .literal (.u64 8)])
        (.local "idx")))
    "direct dynamic array-literal read lowers through ToYul"
  requireCallExpr
    directArrayLiteralExpr
    "__proof_forge_local_array_get_2"
    3
    "direct dynamic array-literal read ToYul"
  let structEnv : TypeEnv := #[
    { name := "p", type := .structType "Point", isMutable := false }
  ]
  let structArrayEnv : TypeEnv := #[
    { name := "people", type := .fixedArray (.structType "Person") 2, isMutable := false },
    { name := "idx", type := .u64, isMutable := false }
  ]
  let staticLocalStructFieldExpr ← requireOk
    (lowerExprPlanExpr
      ProofForge.IR.Examples.EvmStructValueProbe.module
      structEnv
      (.structField (.local "p") "x"))
    "static local-struct field ExprPlan-to-Yul"
  match staticLocalStructFieldExpr with
  | Lean.Compiler.Yul.Expr.ident name =>
      require (name == "__proof_forge_struct_p_x") "static local-struct field ExprPlan-to-Yul local name"
  | _ => throw <| IO.userError "static local-struct field ExprPlan-to-Yul must lower to local identifier"
  let structLiteralFieldExpr ← requireOk
    (lowerExprPlanExpr
      ProofForge.IR.Examples.EvmStructValueProbe.module
      structEnv
      (.structField
        (.structLit "Point" #[
          ("x", .literalWord 4),
          ("y", .literalWord 6)
        ])
        "y"))
    "struct-literal field ExprPlan-to-Yul"
  match structLiteralFieldExpr with
  | Lean.Compiler.Yul.Expr.lit lit =>
      require (lit.value == "6") "struct-literal field ExprPlan-to-Yul selected value"
  | _ => throw <| IO.userError "struct-literal field ExprPlan-to-Yul must select literal value"
  let directStructLiteralFieldExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.EvmStructValueProbe.module
      structEnv
      (.field
        (.structLit "Point" #[
          ("x", .literal (.u64 4)),
          ("y", .literal (.u64 6))
        ])
        "x"))
    "direct struct-literal field read lowers through ToYul"
  match directStructLiteralFieldExpr with
  | Lean.Compiler.Yul.Expr.lit lit =>
      require (lit.value == "4") "direct struct-literal field read selected value"
  | _ => throw <| IO.userError "direct struct-literal field read must select literal value"
  let staticStructArrayFieldExpr ← requireOk
    (lowerExprPlanExpr
      ProofForge.IR.Examples.EvmStructArrayValueProbe.module
      structArrayEnv
      (.structField (.localArrayGet "people" #[.literalWord 1] #[2]) "age"))
    "static local struct-array field ExprPlan-to-Yul"
  match staticStructArrayFieldExpr with
  | Lean.Compiler.Yul.Expr.ident name =>
      require (name == "__proof_forge_array_struct_people_1_age") "static local struct-array field ExprPlan-to-Yul local name"
  | _ => throw <| IO.userError "static local struct-array field ExprPlan-to-Yul must lower to local identifier"
  let dynamicStructArrayFieldExpr ← requireOk
    (lowerExprPlanExpr
      ProofForge.IR.Examples.EvmStructArrayValueProbe.module
      structArrayEnv
      (.structField (.localArrayGet "people" #[.local "idx"] #[2]) "score"))
    "dynamic local struct-array field ExprPlan-to-Yul"
  requireCallExpr
    dynamicStructArrayFieldExpr
    "__proof_forge_local_array_get_2"
    3
    "dynamic local struct-array field ExprPlan-to-Yul"
  let directLocalStructFieldExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.EvmStructValueProbe.module
      structEnv
      (.field (.local "p") "y"))
    "direct local struct-field read lowers through ToYul"
  match directLocalStructFieldExpr with
  | Lean.Compiler.Yul.Expr.ident name =>
      require (name == "__proof_forge_struct_p_y") "direct local struct-field read ToYul local name"
  | _ => throw <| IO.userError "direct local struct-field read must lower to local identifier"
  let directLocalStructFieldPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExprPlan
      ProofForge.IR.Examples.EvmStructValueProbe.module
      (toValidateTypeEnv structEnv)
      (.field (.local "p") "y"))
    "direct local struct-field Lower ExprPlan"
  match directLocalStructFieldPlan with
  | .structField (.local name) fieldName => do
      require (name == "p") "direct local struct-field Lower ExprPlan base"
      require (fieldName == "y") "direct local struct-field Lower ExprPlan field"
  | _ => throw <| IO.userError "direct local struct-field Lower ExprPlan must be structField local"
  let directDynamicStructArrayFieldExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.EvmStructArrayValueProbe.module
      structArrayEnv
      (.field (.arrayGet (.local "people") (.add (.local "idx") (.literal (.u64 0)))) "score"))
    "direct dynamic local struct-array field read lowers through ToYul"
  match directDynamicStructArrayFieldExpr with
  | Lean.Compiler.Yul.Expr.call name args => do
      require (name == "__proof_forge_local_array_get_2") "direct dynamic local struct-array field read helper"
      require (args.size == 3) "direct dynamic local struct-array field read helper arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "direct dynamic local struct-array field read index must lower through ExprPlan"
          require (addArgs.size == 2) "direct dynamic local struct-array field read index helper arg count"
      | _ => throw <| IO.userError "direct dynamic local struct-array field read index must be planned checked add"
  | _ => throw <| IO.userError "direct dynamic local struct-array field read must lower to helper call"
  let dynamicPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExprPlan
      ProofForge.IR.Examples.EvmArrayValueProbe.module
      (toValidateTypeEnv arrayEnv)
      (.arrayGet (.local "xs") (.local "idx")))
    "dynamic local-array Lower ExprPlan"
  match dynamicPlan with
  | .localArrayGet name path lengths => do
      require (name == "xs") "dynamic local-array Lower ExprPlan name"
      require (path.size == 1) "dynamic local-array Lower ExprPlan path rank"
      require (lengths == #[3]) "dynamic local-array Lower ExprPlan lengths"
  | _ => throw <| IO.userError "dynamic local-array Lower ExprPlan must be localArrayGet"
  let matrixEnv : TypeEnv := #[
    { name := "matrix", type := .fixedArray (.fixedArray .u64 2) 2, isMutable := false },
    { name := "row", type := .u64, isMutable := false },
    { name := "col", type := .u64, isMutable := false }
  ]
  let nestedDynamicLocalArrayExpr ← requireOk
    (lowerScalarPlanExprOrFallback
      ProofForge.IR.Examples.EvmArrayValueProbe.module
      matrixEnv
      (.arrayGet (.arrayGet (.local "matrix") (.local "row")) (.local "col")))
    "nested dynamic local-array ExprPlan-to-Yul integration"
  requireCallExpr
    nestedDynamicLocalArrayExpr
    "__proof_forge_local_array_get_nested_2_2"
    6
    "nested dynamic local-array ExprPlan-to-Yul integration"

def testLocalAbiWordsToYul : IO Unit := do
  let simpleStructFields (typeName : String) : Except LowerError (Array String) :=
    if typeName == "Point" then
      .ok #["x", "y"]
    else
      .error { message := s!"unknown struct `{typeName}`" }
  let lowerStructFieldIds ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.localAbiStructFieldIds
      ProofForge.IR.Examples.EvmStructValueProbe.module
      "local ABI words"
      "Point")
    "Lower local ABI struct field ids"
  require (lowerStructFieldIds == #["x", "y"]) "Lower local ABI struct field id order"
  let lowerStructFields ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.localAbiStructFields
      ProofForge.IR.Examples.EvmStructValueProbe.module
      "local ABI words"
      "Point")
    "Lower local ABI struct fields"
  require (lowerStructFields == #[("x", .u64), ("y", .u64)])
    "Lower local ABI struct fields"
  let abiStructEnv : TypeEnv := #[
    { name := "p", type := .structType "Point", isMutable := false }
  ]
  discard <| requireValidateOk
    (ProofForge.Backend.Evm.Lower.validateLocalAbiWordPlan
      ProofForge.IR.Examples.EvmStructValueProbe.module
      (toValidateTypeEnv abiStructEnv)
      "local ABI words"
      "p"
      (.structType "Point"))
    "Lower local ABI word validation"
  requireValidateErrorContains
    (ProofForge.Backend.Evm.Lower.validateLocalAbiWordPlan
      ProofForge.IR.Examples.EvmStructValueProbe.module
      (toValidateTypeEnv abiStructEnv)
      "local ABI words"
      "missing"
      (.structType "Point"))
    "unknown local `missing`"
    "Lower local ABI unknown local diagnostic"
  let lowerStructWordPlans ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.localAbiWordPlans
      ProofForge.IR.Examples.EvmStructValueProbe.module
      (toValidateTypeEnv abiStructEnv)
      "local ABI words"
      "p"
      (.structType "Point"))
    "Lower local ABI struct word plans"
  require (lowerStructWordPlans.size == 2) "Lower local ABI struct word plan count"
  match lowerStructWordPlans[0]?, lowerStructWordPlans[1]? with
  | some (ExprPlan.local lhs), some (ExprPlan.local rhs) => do
      require (lhs == "__proof_forge_struct_p_x") "Lower local ABI struct word plan 0"
      require (rhs == "__proof_forge_struct_p_y") "Lower local ABI struct word plan 1"
  | _, _ => throw <| IO.userError "Lower local ABI struct words must be local ExprPlans"
  let directStructWords ← requireOk
    (ProofForge.Backend.Evm.ToYul.localAbiWords
      toYulError
      simpleStructFields
      "local ABI words"
      "p"
      (.structType "Point"))
    "direct local ABI struct words ToYul"
  require (directStructWords.size == 2) "direct local ABI struct words count"
  requireIdentExpr directStructWords[0]! "__proof_forge_struct_p_x" "direct local ABI struct word 0"
  requireIdentExpr directStructWords[1]! "__proof_forge_struct_p_y" "direct local ABI struct word 1"
  let directArrayWords ← requireOk
    (ProofForge.Backend.Evm.ToYul.localAbiWords
      toYulError
      simpleStructFields
      "local ABI words"
      "xs"
      (.fixedArray .u64 2))
    "direct local ABI fixed-array words ToYul"
  require (directArrayWords.size == 2) "direct local ABI fixed-array words count"
  requireIdentExpr directArrayWords[0]! "__proof_forge_array_xs_0" "direct local ABI fixed-array word 0"
  requireIdentExpr directArrayWords[1]! "__proof_forge_array_xs_1" "direct local ABI fixed-array word 1"
  let structEnv : TypeEnv := #[
    { name := "p", type := .structType "Point", isMutable := false }
  ]
  let loweredStructWords ← requireOk
    (lowerLocalAbiWords
      ProofForge.IR.Examples.EvmStructValueProbe.module
      structEnv
      "entrypoint `point` return value"
      "p"
      (.structType "Point"))
    "planned local ABI struct words ToYul"
  require (loweredStructWords.size == 2) "planned local ABI struct words count"
  requireIdentExpr loweredStructWords[0]! "__proof_forge_struct_p_x" "planned local ABI struct word 0"
  requireIdentExpr loweredStructWords[1]! "__proof_forge_struct_p_y" "planned local ABI struct word 1"
  let arrayEnv : TypeEnv := #[
    { name := "xs", type := .fixedArray .u64 3, isMutable := false }
  ]
  let lowerArrayWordPlans ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.localAbiWordPlans
      ProofForge.IR.Examples.EvmStructValueProbe.module
      (toValidateTypeEnv arrayEnv)
      "local ABI words"
      "xs"
      (.fixedArray .u64 3))
    "Lower local ABI fixed-array word plans"
  require (lowerArrayWordPlans.size == 3) "Lower local ABI fixed-array word plan count"
  match lowerArrayWordPlans[2]? with
  | some (ExprPlan.local name) =>
      require (name == "__proof_forge_array_xs_2") "Lower local ABI fixed-array word plan 2"
  | _ => throw <| IO.userError "Lower local ABI fixed-array words must be local ExprPlans"
  let loweredArrayWords ← requireOk
    (lowerLocalAbiWords
      ProofForge.IR.Examples.EvmArrayValueProbe.module
      arrayEnv
      "entrypoint `array` return value"
      "xs"
      (.fixedArray .u64 3))
    "planned local ABI fixed-array words ToYul"
  require (loweredArrayWords.size == 3) "planned local ABI fixed-array words count"
  requireIdentExpr loweredArrayWords[0]! "__proof_forge_array_xs_0" "planned local ABI fixed-array word 0"
  requireIdentExpr loweredArrayWords[1]! "__proof_forge_array_xs_1" "planned local ABI fixed-array word 1"
  requireIdentExpr loweredArrayWords[2]! "__proof_forge_array_xs_2" "planned local ABI fixed-array word 2"
  let dynamicEnv : TypeEnv := #[
    { name := "payload", type := .bytes, isMutable := false }
  ]
  let dynamicWordPlans ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.localAbiWordPlans
      ProofForge.IR.Examples.EvmDynamicAbiProbe.module
      (toValidateTypeEnv dynamicEnv)
      "local dynamic ABI words"
      "payload"
      .bytes)
    "Lower local dynamic ABI word plans"
  require (dynamicWordPlans.size == 1) "Lower local dynamic ABI word plan count"
  match dynamicWordPlans[0]? with
  | some (ExprPlan.local name) =>
      require
        (name == ProofForge.Backend.Evm.Plan.dynamicParamDataPtrName "payload")
        "Lower local dynamic ABI data pointer word plan"
  | _ => throw <| IO.userError "Lower local dynamic ABI word must be local data pointer ExprPlan"
  let loweredDynamicWords ← requireOk
    (lowerLocalAbiWords
      ProofForge.IR.Examples.EvmDynamicAbiProbe.module
      dynamicEnv
      "entrypoint `echo_bytes` return value"
      "payload"
      .bytes)
    "planned local dynamic ABI words ToYul"
  require (loweredDynamicWords.size == 1) "planned local dynamic ABI words count"
  requireIdentExpr
    loweredDynamicWords[0]!
    (ProofForge.Backend.Evm.Plan.dynamicParamDataPtrName "payload")
    "planned local dynamic ABI data pointer word"

def testArrayLiteralDirectExprPlanToYul : IO Unit := do
  let env : TypeEnv := #[
    { name := "idx", type := .u64, isMutable := false }
  ]
  let expr : Expr :=
    .arrayGet
      (.arrayLit .u64 #[.literal (.u64 5), .literal (.u64 8)])
      (.add (.local "idx") (.literal (.u64 0)))
  let plan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExprPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv env)
      expr)
    "direct dynamic array-literal Lower ExprPlan"
  match plan with
  | .arrayGet arrayPlan indexPlan => do
      match arrayPlan with
      | .arrayLit elementType values => do
          require (elementType == .u64) "direct dynamic array-literal Lower ExprPlan element type"
          require (values.size == 2) "direct dynamic array-literal Lower ExprPlan values"
      | _ => throw <| IO.userError "direct dynamic array-literal Lower ExprPlan must use arrayLit base"
      match indexPlan with
      | .checkedArith .add (.local name) (.literalWord 0) =>
          require (name == "idx") "direct dynamic array-literal Lower ExprPlan index"
      | _ => throw <| IO.userError "direct dynamic array-literal Lower ExprPlan index must be checked-add"
  | _ => throw <| IO.userError "direct dynamic array-literal Lower ExprPlan must be arrayGet arrayLit checked-add"
  let lowered ← requireOk
    (lowerExpr ProofForge.IR.Examples.Counter.module env expr)
    "direct dynamic array-literal read lowers through ExprPlan"
  match lowered with
  | Lean.Compiler.Yul.Expr.call name args => do
      require (name == "__proof_forge_local_array_get_2") "direct dynamic array-literal read helper"
      require (args.size == 3) "direct dynamic array-literal read helper arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "direct dynamic array-literal read index must lower through ExprPlan"
          require (addArgs.size == 2) "direct dynamic array-literal read index helper arg count"
      | _ => throw <| IO.userError "direct dynamic array-literal read index must be planned checked add"
  | _ => throw <| IO.userError "direct dynamic array-literal read must lower to local-array helper call"

def requirePlannedBodyAssignmentNat
    (module : Module)
    (entrypointName : String)
    (expected : Nat) : IO Unit := do
  let plan ← requireOk (buildSemanticPlan module) s!"{entrypointName} semantic plan"
  let entrypoint ← requireSome
    (module.entrypoints.find? (fun entrypoint => entrypoint.name == entrypointName))
    s!"missing `{entrypointName}` entrypoint"
  let entrypointPlan ← requireSome
    (plan.entrypoints.find? (fun entrypoint => entrypoint.name == entrypointName))
    s!"missing `{entrypointName}` entrypoint plan"
  require
    (stmtPlansSupportPlannedBody entrypoint.returns entrypointPlan.body)
    s!"`{entrypointName}` body must be accepted by planned-body gate"
  let plannedBody? ← requireOk
    (lowerEntrypointBodyWithPlan? module entrypoint entrypointPlan)
    s!"`{entrypointName}` planned body lowering"
  let plannedBody ← requireSome plannedBody?
    s!"`{entrypointName}` must lower through planned body instead of compatibility fallback"
  require (plannedBody.size == 1) s!"`{entrypointName}` planned body statement count"
  match plannedBody[0]! with
  | Lean.Compiler.Yul.Statement.assignment names expr => do
      require (names == #["result"]) s!"`{entrypointName}` planned body return target"
      require (exprIsNatLiteral expr expected) s!"`{entrypointName}` planned body literal result"
  | _ => throw <| IO.userError s!"`{entrypointName}` planned body must assign result"

def testAggregateLiteralEntrypointPlannedBody : IO Unit := do
  requirePlannedBodyAssignmentNat
    ProofForge.IR.Examples.EvmArrayValueProbe.module
    "direct_literal_index"
    6
  requirePlannedBodyAssignmentNat
    ProofForge.IR.Examples.EvmStructValueProbe.module
    "direct_literal_field"
    6

def testScalarFallbackGateAggregateLiteralPlanToYul : IO Unit := do
  let arrayEnv : TypeEnv := #[
    { name := "idx", type := .u64, isMutable := false }
  ]
  let arrayExpr : Expr :=
    .arrayGet
      (.arrayLit .u64 #[.literal (.u64 5), .literal (.u64 8)])
      (.add (.local "idx") (.literal (.u64 0)))
  require
    (exprSupportsPlanScalarYul arrayExpr)
    "array literal read must be accepted by scalar plan gate"
  let arrayReturnStmts ← requireOk
    (lowerScalarReturnStmtPlanOrFallback
      ProofForge.IR.Examples.Counter.module
      arrayEnv
      "scalar_array_literal_return"
      .u64
      arrayExpr
      false)
    "array literal scalar return plan-to-yul"
  require (arrayReturnStmts.size == 1) "array literal scalar return statement count"
  match arrayReturnStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["result"]) "array literal scalar return target"
      require (name == "__proof_forge_local_array_get_2") "array literal scalar return helper"
      require (args.size == 3) "array literal scalar return helper arg count"
      requireCallExpr args[0]! "__pf_checked_add" 2 "array literal scalar return planned index"
  | _ => throw <| IO.userError "array literal scalar return must use planned helper assignment"
  let structEnv : TypeEnv := #[
    { name := "n", type := .u64, isMutable := false }
  ]
  let structExpr : Expr :=
    .field
      (.structLit "Point" #[
        ("x", .literal (.u64 4)),
        ("y", .add (.local "n") (.literal (.u64 2)))
      ])
      "y"
  require
    (exprSupportsPlanScalarYul structExpr)
    "struct literal field read must be accepted by scalar plan gate"
  let structReturnStmts ← requireOk
    (lowerScalarReturnStmtPlanOrFallback
      ProofForge.IR.Examples.EvmStructValueProbe.module
      structEnv
      "scalar_struct_literal_return"
      .u64
      structExpr
      false)
    "struct literal scalar return plan-to-yul"
  require (structReturnStmts.size == 1) "struct literal scalar return statement count"
  match structReturnStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["result"]) "struct literal scalar return target"
      require (name == "__pf_checked_add") "struct literal scalar return planned field"
      require (args.size == 2) "struct literal scalar return checked add arg count"
  | _ => throw <| IO.userError "struct literal scalar return must use planned field assignment"

def testScalarFallbackGateLocalAggregatePlanToYul : IO Unit := do
  let arrayEnv : TypeEnv := #[
    { name := "xs", type := .fixedArray .u64 3, isMutable := false },
    { name := "idx", type := .u64, isMutable := false }
  ]
  let arrayExpr : Expr :=
    .arrayGet (.local "xs") (.add (.local "idx") (.literal (.u64 0)))
  require
    (exprSupportsPlanScalarYul arrayExpr)
    "local array read must be accepted by scalar plan gate"
  let arrayReturnStmts ← requireOk
    (lowerScalarReturnStmtPlanOrFallback
      ProofForge.IR.Examples.EvmArrayValueProbe.module
      arrayEnv
      "scalar_local_array_return"
      .u64
      arrayExpr
      false)
    "local array scalar return plan-to-yul"
  require (arrayReturnStmts.size == 1) "local array scalar return statement count"
  match arrayReturnStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["result"]) "local array scalar return target"
      require (name == "__proof_forge_local_array_get_3") "local array scalar return helper"
      require (args.size == 4) "local array scalar return helper arg count"
      requireCallExpr args[0]! "__pf_checked_add" 2 "local array scalar return planned index"
  | _ => throw <| IO.userError "local array scalar return must use planned helper assignment"
  let structEnv : TypeEnv := #[
    { name := "p", type := .structType "Point", isMutable := false }
  ]
  let structExpr : Expr := .field (.local "p") "y"
  require
    (exprSupportsPlanScalarYul structExpr)
    "local struct field read must be accepted by scalar plan gate"
  let structBindingStmts ← requireOk
    (lowerScalarBindingStmtPlanOrFallback
      ProofForge.IR.Examples.EvmStructValueProbe.module
      structEnv
      "head"
      .u64
      false
      structExpr)
    "local struct field scalar binding plan-to-yul"
  require (structBindingStmts.size == 1) "local struct field scalar binding statement count"
  match structBindingStmts[0]! with
  | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.ident sourceName)) => do
      let typedName ← requireAt vars 0 "local struct field scalar binding var"
      require (typedName.name == "head") "local struct field scalar binding target"
      require (sourceName == "__proof_forge_struct_p_y") "local struct field scalar binding source"
  | _ => throw <| IO.userError "local struct field scalar binding must use planned local field"
  let structArrayEnv : TypeEnv := #[
    { name := "rows", type := .fixedArray (.structType "Mixed") 2, isMutable := false },
    { name := "idx", type := .u64, isMutable := false }
  ]
  let structArrayExpr : Expr :=
    .field (.arrayGet (.local "rows") (.local "idx")) "enabled"
  require
    (exprSupportsPlanScalarYul structArrayExpr)
    "local struct-array field read must be accepted by scalar plan gate"
  let structArrayAssertStmts ← requireOk
    (lowerScalarAssertStmtPlanOrFallback
      ProofForge.IR.Examples.EvmStructArrayValueProbe.module
      structArrayEnv
      (.assert structArrayExpr "enabled" none))
    "local struct-array field assert plan-to-yul"
  require (structArrayAssertStmts.size == 1) "local struct-array field assert statement count"
  match structArrayAssertStmts[0]! with
  | Lean.Compiler.Yul.Statement.ifStmt (Lean.Compiler.Yul.Expr.builtin "iszero" args) _ => do
      let guard ← requireAt args 0 "local struct-array field assert guard"
      requireCallExpr guard "__proof_forge_local_array_get_2" 3 "local struct-array field assert planned guard"
  | _ => throw <| IO.userError "local struct-array field assert must use planned helper guard"

def testScalarFallbackGateMemoryArrayPlanToYul : IO Unit := do
  let memoryEnv : TypeEnv := #[
    { name := "buf", type := .array .u64, isMutable := false },
    { name := "idx", type := .u64, isMutable := false }
  ]
  require
    (!exprSupportsPlanScalarYul (.memoryArrayNew .u64 (.literal (.u64 2))))
    "standalone memoryArrayNew must not be accepted as scalar plan gate"
  let lengthExpr : Expr :=
    .memoryArrayLength (.memoryArrayNew .u64 (.add (.local "idx") (.literal (.u64 1))))
  require
    (exprSupportsPlanScalarYul lengthExpr)
    "memory array length over new array must be accepted by scalar plan gate"
  let lengthBindingStmts ← requireOk
    (lowerScalarBindingStmtPlanOrFallback
      ProofForge.IR.Examples.Counter.module
      memoryEnv
      "len"
      .u64
      false
      lengthExpr)
    "memory array length scalar binding plan-to-yul"
  require (lengthBindingStmts.size == 1) "memory array length binding statement count"
  match lengthBindingStmts[0]! with
  | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.builtin "mload" args)) => do
      let typedName ← requireAt vars 0 "memory array length binding var"
      require (typedName.name == "len") "memory array length binding target"
      let source ← requireAt args 0 "memory array length binding source"
      requireCallExpr source (Helper.memoryArrayNew).name 1 "memory array length planned new-array source"
  | _ => throw <| IO.userError "memory array length binding must use planned mload"
  let getExpr : Expr :=
    .memoryArrayGet (.local "buf") (.add (.local "idx") (.literal (.u64 0)))
  require
    (exprSupportsPlanScalarYul getExpr)
    "memory array get over local array must be accepted by scalar plan gate"
  let getReturnStmts ← requireOk
    (lowerScalarReturnStmtPlanOrFallback
      ProofForge.IR.Examples.Counter.module
      memoryEnv
      "memory_array_get_return"
      .u64
      getExpr
      false)
    "memory array get scalar return plan-to-yul"
  require (getReturnStmts.size == 1) "memory array get return statement count"
  match getReturnStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["result"]) "memory array get return target"
      require (name == (Helper.memoryArrayGet).name) "memory array get return helper"
      require (args.size == 2) "memory array get return helper arg count"
      requireIdentExpr args[0]! "buf" "memory array get return array source"
      requireCallExpr args[1]! "__pf_checked_add" 2 "memory array get return planned index"
  | _ => throw <| IO.userError "memory array get return must use planned helper assignment"

def testScalarFallbackGateCrosscallCreatePlanToYul : IO Unit := do
  let crosscallEnv : TypeEnv := #[
    { name := "target", type := .u64, isMutable := false },
    { name := "amount", type := .u64, isMutable := false }
  ]
  let scalarCrosscallExpr : Expr :=
    .crosscallInvokeTyped
      (.local "target")
      (.literal (.u64 305419896))
      #[.add (.local "amount") (.literal (.u64 1))]
      .u64
  require
    (exprSupportsPlanScalarYul scalarCrosscallExpr)
    "scalar crosscall return must be accepted by scalar plan gate"
  let crosscallBindingStmts ← requireOk
    (lowerScalarBindingStmtPlanOrFallback
      ProofForge.IR.Examples.EvmCrosscallProbe.module
      crosscallEnv
      "remote"
      .u64
      false
      scalarCrosscallExpr)
    "scalar crosscall binding plan-to-yul"
  require (crosscallBindingStmts.size == 1) "scalar crosscall binding statement count"
  match crosscallBindingStmts[0]! with
  | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.call name args)) => do
      let typedName ← requireAt vars 0 "scalar crosscall binding var"
      require (typedName.name == "remote") "scalar crosscall binding target"
      require (name == "__proof_forge_crosscall_1") "scalar crosscall binding helper"
      require (args.size == 3) "scalar crosscall binding helper arg count"
      requireCallExpr args[2]! "__pf_checked_add" 2 "scalar crosscall binding planned argument"
  | _ => throw <| IO.userError "scalar crosscall binding must use planned helper call"
  let aggregateReturnExpr : Expr :=
    .crosscallInvokeTyped
      (.local "target")
      (.literal (.u64 305419896))
      #[]
      (.structType "RemotePair")
  require
    (!exprSupportsPlanScalarYul aggregateReturnExpr)
    "aggregate crosscall return must stay out of scalar plan gate"
  let aggregateArgExpr : Expr :=
    .crosscallInvokeTyped
      (.local "target")
      (.literal (.u64 305419896))
      #[.structLit "Point" #[
        ("x", .literal (.u64 4)),
        ("y", .add (.local "amount") (.literal (.u64 2)))
      ]]
      .u64
  require
    (exprSupportsPlanScalarYul aggregateArgExpr)
    "aggregate crosscall argument with scalar return must be accepted by scalar plan gate"
  let aggregateArgBindingStmts ← requireOk
    (lowerScalarBindingStmtPlanOrFallback
      ProofForge.IR.Examples.EvmStructValueProbe.module
      crosscallEnv
      "remote_pair"
      .u64
      false
      aggregateArgExpr)
    "aggregate argument scalar crosscall binding plan-to-yul"
  require (aggregateArgBindingStmts.size == 1) "aggregate argument scalar crosscall binding statement count"
  match aggregateArgBindingStmts[0]! with
  | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.call name args)) => do
      let typedName ← requireAt vars 0 "aggregate argument scalar crosscall binding var"
      require (typedName.name == "remote_pair") "aggregate argument scalar crosscall binding target"
      require (name == "__proof_forge_crosscall_2") "aggregate argument scalar crosscall binding helper"
      require (args.size == 4) "aggregate argument scalar crosscall binding helper arg count"
      requireCallExpr args[3]! "__pf_checked_add" 2 "aggregate argument scalar crosscall binding planned field"
  | _ => throw <| IO.userError "aggregate argument scalar crosscall binding must use planned helper call"
  let createEnv : TypeEnv := #[
    { name := "value", type := .u64, isMutable := false },
    { name := "salt", type := .hash, isMutable := false }
  ]
  let createHelperName :=
    "__proof_forge_create_" ++ ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex
  let create2HelperName :=
    "__proof_forge_create2_" ++ ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex
  let createExpr : Expr :=
    .crosscallCreate
      (.add (.local "value") (.literal (.u64 0)))
      ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex
  require
    (exprSupportsPlanScalarYul createExpr)
    "create expression must be accepted by scalar plan gate"
  let createReturnStmts ← requireOk
    (lowerScalarReturnStmtPlanOrFallback
      ProofForge.IR.Examples.EvmCrosscallProbe.module
      createEnv
      "scalar_create_return"
      .u64
      createExpr
      false)
    "create scalar return plan-to-yul"
  require (createReturnStmts.size == 1) "create scalar return statement count"
  match createReturnStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["result"]) "create scalar return target"
      require (name == createHelperName) "create scalar return helper"
      require (args.size == 1) "create scalar return helper arg count"
      requireCallExpr args[0]! "__pf_checked_add" 2 "create scalar return planned call value"
  | _ => throw <| IO.userError "create scalar return must use planned helper assignment"
  let create2Expr : Expr :=
    .crosscallCreate2
      (.local "value")
      (.local "salt")
      ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex
  require
    (exprSupportsPlanScalarYul create2Expr)
    "create2 expression must be accepted by scalar plan gate"
  let create2BindingStmts ← requireOk
    (lowerScalarBindingStmtPlanOrFallback
      ProofForge.IR.Examples.EvmCrosscallProbe.module
      createEnv
      "deployed2"
      .u64
      false
      create2Expr)
    "create2 scalar binding plan-to-yul"
  require (create2BindingStmts.size == 1) "create2 scalar binding statement count"
  match create2BindingStmts[0]! with
  | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.call name args)) => do
      let typedName ← requireAt vars 0 "create2 scalar binding var"
      require (typedName.name == "deployed2") "create2 scalar binding target"
      require (name == create2HelperName) "create2 scalar binding helper"
      require (args.size == 2) "create2 scalar binding helper arg count"
      requireIdentExpr args[0]! "value" "create2 scalar binding call value"
      requireIdentExpr args[1]! "salt" "create2 scalar binding salt"
  | _ => throw <| IO.userError "create2 scalar binding must use planned helper call"

def testLocalCrosscallWordsToYul : IO Unit := do
  let simpleStructFields (typeName : String) : Except LowerError (Array String) :=
    if typeName == "Point" then
      .ok #["x", "y"]
    else
      .error { message := s!"unknown struct `{typeName}`" }
  let lowerStructFields ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.localCrosscallStructFieldIds
      ProofForge.IR.Examples.EvmStructValueProbe.module
      "crosscall argument"
      "Point")
    "Lower local crosscall struct fields"
  require (lowerStructFields == #["x", "y"]) "Lower local crosscall struct field order"
  let directStructWords ← requireOk
    (ProofForge.Backend.Evm.ToYul.localCrosscallWords
      toYulError
      simpleStructFields
      "crosscall argument"
      "p"
      (.structType "Point"))
    "direct local crosscall struct words ToYul"
  require (directStructWords.size == 2) "direct local crosscall struct words count"
  requireIdentExpr directStructWords[0]! "__proof_forge_struct_p_x" "direct local crosscall struct word 0"
  requireIdentExpr directStructWords[1]! "__proof_forge_struct_p_y" "direct local crosscall struct word 1"
  let directArrayWords ← requireOk
    (ProofForge.Backend.Evm.ToYul.localCrosscallWords
      toYulError
      simpleStructFields
      "crosscall argument"
      "xs"
      (.fixedArray .u64 2))
    "direct local crosscall fixed-array words ToYul"
  require (directArrayWords.size == 2) "direct local crosscall fixed-array words count"
  requireIdentExpr directArrayWords[0]! "__proof_forge_array_xs_0" "direct local crosscall fixed-array word 0"
  requireIdentExpr directArrayWords[1]! "__proof_forge_array_xs_1" "direct local crosscall fixed-array word 1"
  let directArgWords ← requireOk
    (ProofForge.Backend.Evm.ToYul.crosscallArgWordPlanExprs
      (fun
        | .literalWord value => .ok (Lean.Compiler.Yul.Expr.num value)
        | _ => .error { message := "direct crosscall arg word plan test only lowers literal scalar plans" })
      (fun name type =>
        ProofForge.Backend.Evm.ToYul.localCrosscallWords
          toYulError
          simpleStructFields
          "crosscall argument"
          name
          type)
      (fun stateId type =>
        if stateId == "current" && type == .structType "Point" then
          .ok #[Lean.Compiler.Yul.Expr.id "current_x", Lean.Compiler.Yul.Expr.id "current_y"]
        else
          .error { message := "direct crosscall arg word plan test unexpected storage plan" })
      #[
        CrosscallArgWordPlan.local "p" (.structType "Point"),
        CrosscallArgWordPlan.expr (.literalWord 9),
        CrosscallArgWordPlan.storage "current" (.structType "Point")
      ])
    "direct crosscall arg word plan ToYul"
  require (directArgWords.size == 5) "direct crosscall arg word plan word count"
  requireIdentExpr directArgWords[0]! "__proof_forge_struct_p_x" "direct crosscall arg word plan local word 0"
  requireIdentExpr directArgWords[1]! "__proof_forge_struct_p_y" "direct crosscall arg word plan local word 1"
  match directArgWords[2]! with
  | Lean.Compiler.Yul.Expr.lit value =>
      require (value.value == "9") "direct crosscall arg word plan scalar word"
  | _ =>
      throw <| IO.userError "direct crosscall arg word plan scalar word must be numeric"
  requireIdentExpr directArgWords[3]! "current_x" "direct crosscall arg word plan storage word 0"
  requireIdentExpr directArgWords[4]! "current_y" "direct crosscall arg word plan storage word 1"
  let directCrosscallExpr ← requireOk
    (ProofForge.Backend.Evm.ToYul.crosscallExprPlanExpr
      toYulError
      (fun
        | .literalWord value => .ok (Lean.Compiler.Yul.Expr.num value)
        | .local name => .ok (Lean.Compiler.Yul.Expr.id name)
        | _ => .error { message := "direct crosscall expression test only lowers literal/local scalar plans" })
      (fun name type =>
        ProofForge.Backend.Evm.ToYul.localCrosscallWords
          toYulError
          simpleStructFields
          "crosscall argument"
          name
          type)
      (fun stateId type =>
        if stateId == "current" && type == .structType "Point" then
          .ok #[Lean.Compiler.Yul.Expr.id "current_x", Lean.Compiler.Yul.Expr.id "current_y"]
        else
          .error { message := "direct crosscall expression test unexpected storage plan" })
      ProofForge.Backend.Evm.Plan.CrosscallMode.call
      (.local "target")
      (.literalWord 305419896)
      none
      #[
        CrosscallArgWordPlan.local "p" (.structType "Point"),
        CrosscallArgWordPlan.expr (.literalWord 9),
        CrosscallArgWordPlan.storage "current" (.structType "Point")
      ]
      .u64)
    "direct provider-backed crosscall ExprPlan-to-Yul"
  requireCallExpr
    directCrosscallExpr
    "__proof_forge_crosscall_5"
    7
    "direct provider-backed crosscall ExprPlan-to-Yul"
  let structEnv : TypeEnv := #[
    { name := "p", type := .structType "Point", isMutable := false }
  ]
  discard <| requireValidateOk
    (ProofForge.Backend.Evm.Lower.validateLocalCrosscallWordPlan
      ProofForge.IR.Examples.EvmStructValueProbe.module
      (toValidateTypeEnv structEnv)
      "typed crosscall argument"
      "p"
      (.structType "Point"))
    "Lower local crosscall word validation"
  requireValidateErrorContains
    (ProofForge.Backend.Evm.Lower.validateLocalCrosscallWordPlan
      ProofForge.IR.Examples.EvmStructValueProbe.module
      (toValidateTypeEnv structEnv)
      "typed crosscall argument"
      "missing"
      (.structType "Point"))
    "unknown local `missing`"
    "Lower local crosscall word unknown local diagnostic"
  let plannedStructArgWords ← requireOk
    (lowerCrosscallArgWordsMany
      ProofForge.IR.Examples.EvmStructValueProbe.module
      structEnv
      "typed crosscall argument"
      #[.local "p"])
    "planned local crosscall struct words via IR facade"
  require (plannedStructArgWords.size == 2) "planned local crosscall struct words count"
  requireIdentExpr plannedStructArgWords[0]! "__proof_forge_struct_p_x" "planned local crosscall struct word 0"
  requireIdentExpr plannedStructArgWords[1]! "__proof_forge_struct_p_y" "planned local crosscall struct word 1"
  let loweredStructWords ← requireOk
    (lowerLocalCrosscallWords
      ProofForge.IR.Examples.EvmStructValueProbe.module
      structEnv
      "crosscall argument"
      "p"
      (.structType "Point"))
    "planned local crosscall struct words ToYul"
  require (loweredStructWords.size == 2) "planned local crosscall struct words count"
  requireIdentExpr loweredStructWords[0]! "__proof_forge_struct_p_x" "planned local crosscall struct word 0"
  requireIdentExpr loweredStructWords[1]! "__proof_forge_struct_p_y" "planned local crosscall struct word 1"
  let providerLocalStructWords ← requireOk
    (lowerCrosscallArgWordPlanExprs
      ProofForge.IR.Examples.EvmStructValueProbe.module
      structEnv
      "crosscall argument"
      #[CrosscallArgWordPlan.local "p" (.structType "Point")])
    "planned provider local crosscall struct words ToYul"
  require (providerLocalStructWords.size == 2) "planned provider local crosscall struct words count"
  requireIdentExpr providerLocalStructWords[0]! "__proof_forge_struct_p_x" "planned provider local crosscall struct word 0"
  requireIdentExpr providerLocalStructWords[1]! "__proof_forge_struct_p_y" "planned provider local crosscall struct word 1"
  let arrayEnv : TypeEnv := #[
    { name := "xs", type := .fixedArray .u64 3, isMutable := false }
  ]
  let loweredArrayWords ← requireOk
    (lowerLocalCrosscallWords
      ProofForge.IR.Examples.EvmArrayValueProbe.module
      arrayEnv
      "crosscall argument"
      "xs"
      (.fixedArray .u64 3))
    "planned local crosscall fixed-array words ToYul"
  require (loweredArrayWords.size == 3) "planned local crosscall fixed-array words count"
  requireIdentExpr loweredArrayWords[0]! "__proof_forge_array_xs_0" "planned local crosscall fixed-array word 0"
  requireIdentExpr loweredArrayWords[1]! "__proof_forge_array_xs_1" "planned local crosscall fixed-array word 1"
  requireIdentExpr loweredArrayWords[2]! "__proof_forge_array_xs_2" "planned local crosscall fixed-array word 2"

def testStorageFixedArrayCrosscallWordPlans : IO Unit := do
  let storageArrayCrosscallValue : Expr := .arrayLit .u64 #[
    .effect (.storageArrayRead "values" (ProofForge.IR.Examples.EvmStorageArrayProbe.u64 0)),
    .effect (.storageArrayRead "values" (ProofForge.IR.Examples.EvmStorageArrayProbe.u64 1)),
    .effect (.storageArrayRead "values" (ProofForge.IR.Examples.EvmStorageArrayProbe.u64 2))
  ]
  let storageArrayCrosscallWordPlans ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.storageCrosscallWordPlans
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      "typed crosscall argument"
      "values"
      (.fixedArray .u64 3))
    "storage-backed fixed-array crosscall argument Lower word plans"
  require (storageArrayCrosscallWordPlans.size == 3)
    "storage-backed fixed-array crosscall Lower word plan count"
  let storageArrayCrosscallWord0 ←
    requireAt storageArrayCrosscallWordPlans 0 "storage-backed fixed-array crosscall missing word 0"
  match storageArrayCrosscallWord0 with
  | .storageLoad (.arraySlot rootSlot length (.irExpr (.literal (.u64 index)))) => do
      require (rootSlot == 1) "storage-backed fixed-array crosscall root slot"
      require (length == 3) "storage-backed fixed-array crosscall length"
      require (index == 0) "storage-backed fixed-array crosscall index"
  | _ => throw <| IO.userError "storage-backed fixed-array crosscall first word must use array storageLoad plan"
  let storageArrayCrosscallArgPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExprPlan
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      (toValidateTypeEnv #[{ name := "target", type := .u64, isMutable := false }])
      (.crosscallInvokeTyped
        (.local "target")
        (.literal (.u64 305419896))
        #[storageArrayCrosscallValue]
        .u64))
    "storage-backed fixed-array crosscall argument Lower ExprPlan"
  match storageArrayCrosscallArgPlan with
  | .crosscall .call _ _ none args .u64 => do
      require (args.size == 3) "storage-backed fixed-array crosscall argument plan word count"
      let arg0 ← requireAt args 0 "storage-backed fixed-array crosscall argument missing word 0"
      let arg2 ← requireAt args 2 "storage-backed fixed-array crosscall argument missing word 2"
      match arg0, arg2 with
      | CrosscallArgWordPlan.expr (.storageLoad (.arraySlot root0 length0 (.irExpr (.literal (.u64 index0))))),
        CrosscallArgWordPlan.expr (.storageLoad (.arraySlot root2 length2 (.irExpr (.literal (.u64 index2))))) => do
          require (root0 == 1) "storage-backed fixed-array crosscall word 0 root slot"
          require (length0 == 3) "storage-backed fixed-array crosscall word 0 length"
          require (index0 == 0) "storage-backed fixed-array crosscall word 0 index"
          require (root2 == 1) "storage-backed fixed-array crosscall word 2 root slot"
          require (length2 == 3) "storage-backed fixed-array crosscall word 2 length"
          require (index2 == 2) "storage-backed fixed-array crosscall word 2 index"
      | _, _ => throw <| IO.userError "storage-backed fixed-array crosscall argument must use planned storage-load words"
  | _ => throw <| IO.userError "storage-backed fixed-array crosscall argument must lower to call plan"
  let storageArrayCrosscallArgPlanExpr ← requireOk
    (lowerExprPlanExpr
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      #[{ name := "target", type := .u64, isMutable := false }]
      storageArrayCrosscallArgPlan)
    "storage-backed fixed-array crosscall argument ExprPlan-to-Yul"
  requireCallExpr
    storageArrayCrosscallArgPlanExpr
    "__proof_forge_crosscall_3"
    5
    "storage-backed fixed-array crosscall argument ExprPlan-to-Yul"
  let storageStructArrayCrosscallValue : Expr := .arrayLit (.structType "Point") #[
    ProofForge.IR.Examples.EvmStorageStructProbe.storagePoint 0,
    ProofForge.IR.Examples.EvmStorageStructProbe.storagePoint 1
  ]
  let storageStructArrayCrosscallWordPlans ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.storageCrosscallWordPlans
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      "typed crosscall argument"
      "points"
      (.fixedArray (.structType "Point") 2))
    "storage-backed struct-array crosscall argument Lower word plans"
  require (storageStructArrayCrosscallWordPlans.size == 4)
    "storage-backed struct-array crosscall Lower word plan count"
  let storageStructArrayCrosscallWord3 ←
    requireAt storageStructArrayCrosscallWordPlans 3 "storage-backed struct-array crosscall missing word 3"
  match storageStructArrayCrosscallWord3 with
  | .storageLoad (.structArrayFieldSlot _ length fieldCount fieldOffset (.irExpr (.literal (.u64 index)))) => do
      require (length == 2) "storage-backed struct-array crosscall length"
      require (fieldCount == 2) "storage-backed struct-array crosscall field count"
      require (fieldOffset == 1) "storage-backed struct-array crosscall field offset"
      require (index == 1) "storage-backed struct-array crosscall index"
  | _ => throw <| IO.userError "storage-backed struct-array crosscall last word must use struct-array storageLoad plan"
  let storageStructArrayCrosscallArgPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildExprPlan
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      (toValidateTypeEnv #[{ name := "target", type := .u64, isMutable := false }])
      (.crosscallInvokeTyped
        (.local "target")
        (.literal (.u64 305419896))
        #[storageStructArrayCrosscallValue]
        .u64))
    "storage-backed struct-array crosscall argument Lower ExprPlan"
  match storageStructArrayCrosscallArgPlan with
  | .crosscall .call _ _ none args .u64 => do
      require (args.size == 4) "storage-backed struct-array crosscall argument plan word count"
      let arg3 ← requireAt args 3 "storage-backed struct-array crosscall argument missing word 3"
      match arg3 with
      | CrosscallArgWordPlan.expr
          (.storageLoad (.structArrayFieldSlot _ length fieldCount fieldOffset (.irExpr (.literal (.u64 index))))) => do
          require (length == 2) "storage-backed struct-array crosscall word length"
          require (fieldCount == 2) "storage-backed struct-array crosscall word field count"
          require (fieldOffset == 1) "storage-backed struct-array crosscall word field offset"
          require (index == 1) "storage-backed struct-array crosscall word index"
      | _ => throw <| IO.userError "storage-backed struct-array crosscall argument must use planned storage-load words"
  | _ => throw <| IO.userError "storage-backed struct-array crosscall argument must lower to call plan"
  let storageStructArrayCrosscallArgPlanExpr ← requireOk
    (lowerExprPlanExpr
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      #[{ name := "target", type := .u64, isMutable := false }]
      storageStructArrayCrosscallArgPlan)
    "storage-backed struct-array crosscall argument ExprPlan-to-Yul"
  requireCallExpr
    storageStructArrayCrosscallArgPlanExpr
    "__proof_forge_crosscall_4"
    6
    "storage-backed struct-array crosscall argument ExprPlan-to-Yul"

def testReturnValueWordPlanToYul : IO Unit := do
  let simpleStructFields (typeName : String) : Except LowerError (Array (String × ValueType)) :=
    if typeName == "Point" then
      .ok #[("x", .u64), ("y", .u64)]
    else
      .error { message := s!"unknown struct `{typeName}`" }
  let noReturnPlanExpr (_ : ExprPlan) : Except LowerError Lean.Compiler.Yul.Expr :=
    .error { message := "direct return value word test should not lower scalar ExprPlan" }
  let noStorageStructWords
      (_context _typeName _stateId : String) : Except LowerError (Array Lean.Compiler.Yul.Expr) :=
    .error { message := "direct return value word test should not lower storage struct words" }
  let noStorageArrayWords
      (_context _stateId : String)
      (_elementType : ValueType)
      (_length : Nat) : Except LowerError (Array Lean.Compiler.Yul.Expr) :=
    .error { message := "direct return value word test should not lower storage array words" }
  let directPlan : ReturnValueWordPlan := {
    returns := {
      returnType := .fixedArray .u64 2
      wordTypes := #[.u64, .u64]
      localNames := #["__proof_forge_return_0", "__proof_forge_return_1"]
    }
    source := AbiValuePlan.local "xs" (.fixedArray .u64 2)
  }
  let directAssignments ← requireOk
    (ProofForge.Backend.Evm.ToYul.returnValueWordPlanAssignments
      toYulError
      noReturnPlanExpr
      simpleStructFields
      noStorageStructWords
      noStorageArrayWords
      "entrypoint `array` return value"
      directPlan)
    "direct return value word plan ToYul"
  require (directAssignments.size == 2) "direct return value word plan assignment count"
  match directAssignments[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.ident valueName) => do
      require (names == #["__proof_forge_return_0"]) "direct return value word plan first target"
      require (valueName == "__proof_forge_array_xs_0") "direct return value word plan first source"
  | _ => throw <| IO.userError "direct return value word plan first statement must assign local ABI word"
  match directAssignments[1]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.ident valueName) => do
      require (names == #["__proof_forge_return_1"]) "direct return value word plan second target"
      require (valueName == "__proof_forge_array_xs_1") "direct return value word plan second source"
  | _ => throw <| IO.userError "direct return value word plan second statement must assign local ABI word"
  let structEnv : TypeEnv := #[
    { name := "p", type := .structType "Point", isMutable := false }
  ]
  let structPlan? ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.returnValueWordPlan?
      ProofForge.IR.Examples.EvmStructValueProbe.module
      (toValidateTypeEnv structEnv)
      "point"
      (.structType "Point")
      (.local "p"))
    "Lower local struct return value word plan"
  let structPlan ← requireSome structPlan? "Lower local struct return value word plan missing"
  match structPlan.source with
  | AbiValuePlan.local name type => do
      require (name == "p") "Lower local struct return source name"
      require (type == .structType "Point") "Lower local struct return source type"
  | _ => throw <| IO.userError "Lower local struct return must use local ABI value source plan"
  require (structPlan.returns.localNames == #["__proof_forge_return_0", "__proof_forge_return_1"])
    "Lower local struct return names"
  let structAssignments ← requireOk
    (lowerReturnValueWordPlan
      ProofForge.IR.Examples.EvmStructValueProbe.module
      structEnv
      "point"
      structPlan)
    "Lower local struct return value word plan ToYul integration"
  require (structAssignments.size == 2) "Lower local struct return assignment count"
  match structAssignments[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.ident valueName) => do
      require (names == #["__proof_forge_return_0"]) "Lower local struct return first target"
      require (valueName == "__proof_forge_struct_p_x") "Lower local struct return first source"
  | _ => throw <| IO.userError "Lower local struct return first statement must assign local ABI word"
  let arrayEnv : TypeEnv := #[
    { name := "xs", type := .fixedArray .u64 3, isMutable := false }
  ]
  let arrayPlan? ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.returnValueWordPlan?
      ProofForge.IR.Examples.EvmArrayValueProbe.module
      (toValidateTypeEnv arrayEnv)
      "array"
      (.fixedArray .u64 3)
      (.local "xs"))
    "Lower local fixed-array return value word plan"
  let arrayPlan ← requireSome arrayPlan? "Lower local fixed-array return value word plan missing"
  match arrayPlan.source with
  | AbiValuePlan.local name type => do
      require (name == "xs") "Lower local fixed-array return source name"
      require (type == .fixedArray .u64 3) "Lower local fixed-array return source type"
  | _ => throw <| IO.userError "Lower local fixed-array return must use local ABI value source plan"
  require (arrayPlan.returns.localNames == #["__proof_forge_return_0", "__proof_forge_return_1", "__proof_forge_return_2"])
    "Lower local fixed-array return names"
  let arrayAssignments ← requireOk
    (lowerReturnValueWordPlan
      ProofForge.IR.Examples.EvmArrayValueProbe.module
      arrayEnv
      "array"
      arrayPlan)
    "Lower local fixed-array return value word plan ToYul integration"
  require (arrayAssignments.size == 3) "Lower local fixed-array return assignment count"
  match arrayAssignments[2]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.ident valueName) => do
      require (names == #["__proof_forge_return_2"]) "Lower local fixed-array return third target"
      require (valueName == "__proof_forge_array_xs_2") "Lower local fixed-array return third source"
  | _ => throw <| IO.userError "Lower local fixed-array return third statement must assign local ABI word"
  let literalStructPlan? ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.returnValueWordPlan?
      ProofForge.IR.Examples.EvmStructValueProbe.module
      (toValidateTypeEnv #[])
      "literal_point"
      (.structType "Point")
      (ProofForge.IR.Examples.EvmStructValueProbe.point 4 6))
    "Lower literal struct return value word plan"
  let literalStructPlan ← requireSome literalStructPlan? "Lower literal struct return value word plan missing"
  match literalStructPlan.source with
  | .structLit typeName fields => do
      require (typeName == "Point") "Lower literal struct return source type"
      require (fields.size == 2) "Lower literal struct return field count"
  | _ => throw <| IO.userError "Lower literal struct return must use structLit source plan"
  let literalStructAssignments ← requireOk
    (lowerReturnValueWordPlan
      ProofForge.IR.Examples.EvmStructValueProbe.module
      #[]
      "literal_point"
      literalStructPlan)
    "Lower literal struct return value word plan ToYul integration"
  require (literalStructAssignments.size == 2) "Lower literal struct return assignment count"
  match literalStructAssignments[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.lit value) => do
      require (names == #["__proof_forge_return_0"]) "Lower literal struct return first target"
      require (value.value == "4") "Lower literal struct return first literal"
  | _ => throw <| IO.userError "Lower literal struct return first statement must assign literal ABI word"
  let plannedStorageStructPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.returnValueWordPlanFromExprPlan
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      (toValidateTypeEnv #[])
      "whole_struct_return"
      (.structType "Point")
      (ExprPlan.effect (EffectPlan.storageScalarRead "current")))
    "Lower planned storage struct return value word plan"
  match plannedStorageStructPlan.source with
  | AbiValuePlan.storage stateId type => do
      require (stateId == "current") "Lower planned storage struct return source state"
      require (type == .structType "Point") "Lower planned storage struct return source type"
  | _ => throw <| IO.userError "Lower planned storage struct return must use storage ABI value source plan"
  let plannedStorageStructAssignments ← requireOk
    (lowerReturnValueWordPlan
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      #[]
      "whole_struct_return"
      plannedStorageStructPlan)
    "Lower planned storage struct return value word plan ToYul integration"
  require (plannedStorageStructAssignments.size == 2)
    "Lower planned storage struct return assignment count"
  match plannedStorageStructAssignments[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.builtin "sload" args) => do
      require (names == #["__proof_forge_return_0"]) "Lower planned storage struct return first target"
      require (args.size == 1) "Lower planned storage struct return first sload arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.lit slot =>
          require (slot.value == "1") "Lower planned storage struct return first slot"
      | _ => throw <| IO.userError "Lower planned storage struct return first source must use literal slot"
  | _ => throw <| IO.userError "Lower planned storage struct return first statement must assign sload ABI word"
  let storageArrayValue : Expr := .arrayLit .u64 #[
    .effect (.storageArrayRead "values" (ProofForge.IR.Examples.EvmStorageArrayProbe.u64 0)),
    .effect (.storageArrayRead "values" (ProofForge.IR.Examples.EvmStorageArrayProbe.u64 1)),
    .effect (.storageArrayRead "values" (ProofForge.IR.Examples.EvmStorageArrayProbe.u64 2))
  ]
  let storageArrayPlan? ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.returnValueWordPlan?
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      (toValidateTypeEnv #[])
      "return_values"
      (.fixedArray .u64 3)
      storageArrayValue)
    "Lower storage fixed-array return value word plan"
  let storageArrayPlan ← requireSome storageArrayPlan? "Lower storage fixed-array return value word plan missing"
  match storageArrayPlan.source with
  | AbiValuePlan.storage stateId type => do
      require (stateId == "values") "Lower storage fixed-array return source state"
      require (type == .fixedArray .u64 3) "Lower storage fixed-array return source type"
  | _ => throw <| IO.userError "Lower storage fixed-array return must use storage ABI value source plan"
  let storageArrayWordPlans ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.storageAbiWordPlans
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      "entrypoint `return_values` return value"
      "values"
      (.fixedArray .u64 3))
    "Lower storage fixed-array ABI word plans"
  require (storageArrayWordPlans.size == 3) "Lower storage fixed-array ABI word plan count"
  let storageArrayFirstWord ← requireAt storageArrayWordPlans 0 "Lower storage fixed-array missing first word"
  match storageArrayFirstWord with
  | .storageLoad (.arraySlot rootSlot length (.irExpr (.literal (.u64 index)))) => do
      require (rootSlot == 1) "Lower storage fixed-array ABI word root slot"
      require (length == 3) "Lower storage fixed-array ABI word length"
      require (index == 0) "Lower storage fixed-array ABI word index"
  | _ => throw <| IO.userError "Lower storage fixed-array ABI first word must use array storageLoad plan"
  let storageArrayFacadeWords ← requireOk
    (lowerStorageArrayAbiWords
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      "entrypoint `return_values` return value"
      "values"
      .u64
      3)
    "planned storage fixed-array ABI words ToYul facade"
  require (storageArrayFacadeWords.size == 3) "planned storage fixed-array ABI facade word count"
  match storageArrayFacadeWords[0]! with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "planned storage fixed-array ABI facade sload arg count"
      requireCallExpr args[0]! "__proof_forge_array_slot" 3
        "planned storage fixed-array ABI facade slot helper"
  | _ => throw <| IO.userError "planned storage fixed-array ABI facade word must be sload"
  let storageArrayAssignments ← requireOk
    (lowerReturnValueWordPlan
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      #[]
      "return_values"
      storageArrayPlan)
    "Lower storage fixed-array return value word plan ToYul integration"
  require (storageArrayAssignments.size == 3) "Lower storage fixed-array return assignment count"
  match storageArrayAssignments[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.builtin "sload" args) => do
      require (names == #["__proof_forge_return_0"]) "Lower storage fixed-array return first target"
      require (args.size == 1) "Lower storage fixed-array return first sload arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call name _ =>
          require (name == "__proof_forge_array_slot") "Lower storage fixed-array return first slot helper"
      | _ => throw <| IO.userError "Lower storage fixed-array return first source must use array slot helper"
  | _ => throw <| IO.userError "Lower storage fixed-array return first statement must assign sload ABI word"
  let storageStructArrayValue : Expr := .arrayLit (.structType "Point") #[
    ProofForge.IR.Examples.EvmStorageStructProbe.storagePoint 0,
    ProofForge.IR.Examples.EvmStorageStructProbe.storagePoint 1
  ]
  let storageStructArrayPlan? ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.returnValueWordPlan?
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      (toValidateTypeEnv #[])
      "return_points"
      (.fixedArray (.structType "Point") 2)
      storageStructArrayValue)
    "Lower storage struct-array return value word plan"
  let storageStructArrayPlan ← requireSome storageStructArrayPlan? "Lower storage struct-array return value word plan missing"
  match storageStructArrayPlan.source with
  | AbiValuePlan.storage stateId type => do
      require (stateId == "points") "Lower storage struct-array return source state"
      require (type == .fixedArray (.structType "Point") 2) "Lower storage struct-array return source type"
  | _ => throw <| IO.userError "Lower storage struct-array return must use storage ABI value source plan"
  let storageStructArrayWordPlans ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.storageAbiWordPlans
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      "entrypoint `return_points` return value"
      "points"
      (.fixedArray (.structType "Point") 2))
    "Lower storage struct-array ABI word plans"
  require (storageStructArrayWordPlans.size == 4) "Lower storage struct-array ABI word plan count"
  let storageStructArrayLastWord ← requireAt storageStructArrayWordPlans 3 "Lower storage struct-array missing last word"
  match storageStructArrayLastWord with
  | .storageLoad (.structArrayFieldSlot _ length fieldCount fieldOffset (.irExpr (.literal (.u64 index)))) => do
      require (length == 2) "Lower storage struct-array ABI word length"
      require (fieldCount == 2) "Lower storage struct-array ABI word field count"
      require (fieldOffset == 1) "Lower storage struct-array ABI word field offset"
      require (index == 1) "Lower storage struct-array ABI word index"
  | _ => throw <| IO.userError "Lower storage struct-array ABI last word must use struct-array storageLoad plan"
  let storageStructArrayFacadeWords ← requireOk
    (lowerStorageArrayAbiWords
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      "entrypoint `return_points` return value"
      "points"
      (.structType "Point")
      2)
    "planned storage struct-array ABI words ToYul facade"
  require (storageStructArrayFacadeWords.size == 4) "planned storage struct-array ABI facade word count"
  match storageStructArrayFacadeWords[3]! with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "planned storage struct-array ABI facade sload arg count"
      requireCallExpr args[0]! "__proof_forge_struct_array_slot" 5
        "planned storage struct-array ABI facade slot helper"
  | _ => throw <| IO.userError "planned storage struct-array ABI facade word must be sload"
  let storageStructArrayAssignments ← requireOk
    (lowerReturnValueWordPlan
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      #[]
      "return_points"
      storageStructArrayPlan)
    "Lower storage struct-array return value word plan ToYul integration"
  require (storageStructArrayAssignments.size == 4) "Lower storage struct-array return assignment count"
  match storageStructArrayAssignments[3]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.builtin "sload" args) => do
      require (names == #["__proof_forge_return_3"]) "Lower storage struct-array return last target"
      require (args.size == 1) "Lower storage struct-array return last sload arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call name _ =>
          require (name == "__proof_forge_struct_array_slot") "Lower storage struct-array return last slot helper"
      | _ => throw <| IO.userError "Lower storage struct-array return last source must use struct-array slot helper"
  | _ => throw <| IO.userError "Lower storage struct-array return last statement must assign sload ABI word"

def testAggregateAssignmentPlanToYul : IO Unit := do
  let fixedStmt :=
    ProofForge.Backend.Evm.ToYul.wholeFixedArrayAssignStmt
      "xs"
      #[
        { index := 0, expr := Lean.Compiler.Yul.Expr.num 11 },
        { index := 1, expr := Lean.Compiler.Yul.Expr.id "__proof_forge_array_ys_1" }
      ]
  match fixedStmt with
  | Lean.Compiler.Yul.Statement.block block => do
      require (block.statements.size == 4) "fixed-array assignment snapshot statement count"
      match block.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.lit lit)) => do
          require (vars.size == 1) "fixed-array assignment first snapshot var count"
          let firstVar ← requireAt vars 0 "fixed-array assignment missing first snapshot var"
          require (firstVar.name == "__proof_forge_assign_array_xs_0") "fixed-array assignment first snapshot var"
          require (lit.value == "11") "fixed-array assignment first snapshot value"
      | _ => throw <| IO.userError "fixed-array assignment first statement must snapshot source"
      match block.statements[3]! with
      | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.ident valueName) => do
          require (names == #["__proof_forge_array_xs_1"]) "fixed-array assignment final target"
          require (valueName == "__proof_forge_assign_array_xs_1") "fixed-array assignment final source"
      | _ => throw <| IO.userError "fixed-array assignment final statement must assign snapshot"
  | _ => throw <| IO.userError "fixed-array assignment ToYul helper must produce block"
  let structStmt :=
    ProofForge.Backend.Evm.ToYul.wholeStructAssignStmt
      "point"
      #[{ fieldName := "x", expr := Lean.Compiler.Yul.Expr.num 7 }]
  match structStmt with
  | Lean.Compiler.Yul.Statement.block block => do
      require (block.statements.size == 2) "struct assignment snapshot statement count"
      match block.statements[1]! with
      | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.ident valueName) => do
          require (names == #["__proof_forge_struct_point_x"]) "struct assignment target"
          require (valueName == "__proof_forge_assign_struct_point_x") "struct assignment snapshot source"
      | _ => throw <| IO.userError "struct assignment final statement must assign snapshot"
  | _ => throw <| IO.userError "struct assignment ToYul helper must produce block"
  let nestedStmt :=
    ProofForge.Backend.Evm.ToYul.wholeNestedFixedArrayAssignStmt
      "matrix"
      #[{
        path := #[1, 0],
        fieldName? := some "x",
        expr := Lean.Compiler.Yul.Expr.num 5
      }]
  match nestedStmt with
  | Lean.Compiler.Yul.Statement.block block => do
      require (block.statements.size == 2) "nested fixed-array assignment snapshot statement count"
      match block.statements[1]! with
      | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.ident valueName) => do
          require (names == #["__proof_forge_array_struct_matrix_1_0_x"]) "nested fixed-array assignment target"
          require (valueName == "__proof_forge_assign_array_struct_matrix_1_0_x") "nested fixed-array assignment snapshot source"
      | _ => throw <| IO.userError "nested fixed-array assignment final statement must assign snapshot"
  | _ => throw <| IO.userError "nested fixed-array assignment ToYul helper must produce block"
  let dynamicStmt :=
    ProofForge.Backend.Evm.ToYul.dynamicLocalValueSwitchBlock
      (Lean.Compiler.Yul.Expr.id "idx")
      (Lean.Compiler.Yul.Expr.num 13)
      2
      (fun idx =>
        #[ProofForge.Backend.Evm.ToYul.dynamicAssignmentStatement
          (ProofForge.Backend.Evm.ToYul.arrayLocalElementName "xs" idx)
          (some .add)])
  match dynamicStmt with
  | Lean.Compiler.Yul.Statement.block block => do
      require (block.statements.size == 3) "dynamic fixed-array assignment frame statement count"
      match block.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.ident indexName)) => do
          let firstVar ← requireAt vars 0 "dynamic fixed-array assignment frame missing index var"
          require (firstVar.name == "__proof_forge_array_index") "dynamic fixed-array assignment frame index var"
          require (indexName == "idx") "dynamic fixed-array assignment frame index source"
      | _ => throw <| IO.userError "dynamic fixed-array assignment frame must snapshot index"
      match block.statements[2]! with
      | Lean.Compiler.Yul.Statement.switchStmt (Lean.Compiler.Yul.Expr.ident switchName) cases => do
          require (switchName == "__proof_forge_array_index") "dynamic fixed-array assignment switch index"
          require (cases.size == 3) "dynamic fixed-array assignment switch case count"
          match cases[1]!.body.statements[0]! with
          | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call helper args) => do
              require (names == #["__proof_forge_array_xs_1"]) "dynamic fixed-array assignment case target"
              require (helper == "__pf_checked_add") "dynamic fixed-array assignment case helper"
              require (args.size == 2) "dynamic fixed-array assignment case helper arg count"
          | _ => throw <| IO.userError "dynamic fixed-array assignment case must assign checked RHS"
      | _ => throw <| IO.userError "dynamic fixed-array assignment frame must switch on index"
  | _ => throw <| IO.userError "dynamic fixed-array assignment ToYul helper must produce block"
  let dynamicPathStmt :=
    ProofForge.Backend.Evm.ToYul.dynamicLocalPathSwitchBlock
      1
      (Lean.Compiler.Yul.Expr.id "col")
      #[
        ProofForge.Backend.Evm.ToYul.dynamicLocalSwitchCase 0 #[
          ProofForge.Backend.Evm.ToYul.dynamicAssignmentStatement
            "__proof_forge_array_matrix_0_0"
            none
        ],
        ProofForge.Backend.Evm.ToYul.dynamicLocalSwitchDefaultCase
      ]
  match dynamicPathStmt with
  | Lean.Compiler.Yul.Statement.block block => do
      match block.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.ident sourceName)) => do
          let firstVar ← requireAt vars 0 "dynamic path assignment frame missing index var"
          require (firstVar.name == "__proof_forge_array_index_1") "dynamic path assignment frame index var"
          require (sourceName == "col") "dynamic path assignment frame index source"
      | _ => throw <| IO.userError "dynamic path assignment frame must snapshot path index"
  | _ => throw <| IO.userError "dynamic path assignment ToYul helper must produce block"
  let env : TypeEnv := #[
    { name := "xs", type := .fixedArray .u64 2, isMutable := true },
    { name := "ys", type := .fixedArray .u64 2, isMutable := false },
    { name := "idx", type := .u64, isMutable := false }
  ]
  let fixedArraySourcePlans ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.fixedArrayAssignmentSourcePlans
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv env)
      "xs"
      .u64
      2
      (.local "ys"))
    "Lower fixed-array assignment source plans"
  require (fixedArraySourcePlans.size == 2) "Lower fixed-array assignment source plan count"
  let fixedArraySourcePlan1 ← requireAt fixedArraySourcePlans 1 "Lower fixed-array assignment source plan missing index 1"
  require (fixedArraySourcePlan1.index == 1) "Lower fixed-array assignment source plan index"
  match fixedArraySourcePlan1.expr with
  | ExprPlan.local name =>
      require (name == "__proof_forge_array_ys_1") "Lower fixed-array assignment source plan local"
  | _ => throw <| IO.userError "Lower fixed-array assignment source plan must use planned local expression"
  let fixedArrayPlanStmt ← requireOk
    (ProofForge.Backend.Evm.ToYul.wholeFixedArrayAssignStmtFromPlan
      (lowerExprPlanExpr ProofForge.IR.Examples.Counter.module env)
      "xs"
      fixedArraySourcePlans)
    "fixed-array assignment source plan ToYul helper"
  match fixedArrayPlanStmt with
  | Lean.Compiler.Yul.Statement.block block => do
      require (block.statements.size == 4) "fixed-array assignment source plan ToYul statement count"
      match block.statements[3]! with
      | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.ident valueName) => do
          require (names == #["__proof_forge_array_xs_1"]) "fixed-array assignment source plan ToYul target"
          require (valueName == "__proof_forge_assign_array_xs_1") "fixed-array assignment source plan ToYul snapshot"
      | _ => throw <| IO.userError "fixed-array assignment source plan ToYul final statement must assign snapshot"
  | _ => throw <| IO.userError "fixed-array assignment source plan ToYul helper must produce block"
  let stmts ← requireOk
    (lowerAssignStmt
      ProofForge.IR.Examples.Counter.module
      env
      (.local "xs")
      (.local "ys"))
    "whole local fixed-array assignment integration"
  require (stmts.size == 1) "whole local fixed-array assignment integration statement count"
  match stmts[0]! with
  | Lean.Compiler.Yul.Statement.block block => do
      require (block.statements.size == 4) "whole local fixed-array assignment integration block count"
      match block.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.ident sourceName)) => do
          let firstVar ← requireAt vars 0 "whole local fixed-array assignment integration missing temp"
          require (firstVar.name == "__proof_forge_assign_array_xs_0") "whole local fixed-array assignment integration temp"
          require (sourceName == "__proof_forge_array_ys_0") "whole local fixed-array assignment integration source"
      | _ => throw <| IO.userError "whole local fixed-array assignment integration must snapshot source first"
  | _ => throw <| IO.userError "whole local fixed-array assignment integration must lower to ToYul block"
  let structAssignEnv : TypeEnv := #[
    { name := "p", type := .structType "Point", isMutable := true },
    { name := "q", type := .structType "Point", isMutable := false },
    { name := "n", type := .u64, isMutable := false }
  ]
  let structSourcePlans ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.structAssignmentSourcePlans
      ProofForge.IR.Examples.EvmStructValueProbe.module
      (toValidateTypeEnv structAssignEnv)
      "p"
      "Point"
      (.local "q"))
    "Lower struct assignment source plans"
  require (structSourcePlans.size == 2) "Lower struct assignment source plan count"
  let structSourcePlan1 ← requireAt structSourcePlans 1 "Lower struct assignment source plan missing field y"
  require (structSourcePlan1.fieldName == "y") "Lower struct assignment source plan field"
  match structSourcePlan1.expr with
  | ExprPlan.local name =>
      require (name == "__proof_forge_struct_q_y") "Lower struct assignment source plan local"
  | _ => throw <| IO.userError "Lower struct assignment source plan must use planned local expression"
  let structLiteralSourcePlans ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.structAssignmentSourcePlans
      ProofForge.IR.Examples.EvmStructValueProbe.module
      (toValidateTypeEnv structAssignEnv)
      "p"
      "Point"
      (.structLit "Point" #[
        ("x", .add (.local "n") (.literal (.u64 1))),
        ("y", .field (.local "q") "x")
      ]))
    "Lower struct literal assignment source plans"
  require (structLiteralSourcePlans.size == 2) "Lower struct literal assignment source plan count"
  let structPlanStmt ← requireOk
    (ProofForge.Backend.Evm.ToYul.wholeStructAssignStmtFromPlan
      (lowerExprPlanExpr ProofForge.IR.Examples.EvmStructValueProbe.module structAssignEnv)
      "p"
      structLiteralSourcePlans)
    "struct assignment source plan ToYul helper"
  match structPlanStmt with
  | Lean.Compiler.Yul.Statement.block block => do
      require (block.statements.size == 4) "struct assignment source plan ToYul statement count"
      match block.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.call name args)) => do
          let firstVar ← requireAt vars 0 "struct assignment source plan ToYul missing first snapshot var"
          require (firstVar.name == "__proof_forge_assign_struct_p_x") "struct assignment source plan ToYul first snapshot"
          require (name == "__pf_checked_add") "struct assignment source plan ToYul planned expression helper"
          require (args.size == 2) "struct assignment source plan ToYul helper arg count"
      | _ => throw <| IO.userError "struct assignment source plan ToYul first statement must snapshot planned expression"
      match block.statements[3]! with
      | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.ident valueName) => do
          require (names == #["__proof_forge_struct_p_y"]) "struct assignment source plan ToYul final target"
          require (valueName == "__proof_forge_assign_struct_p_y") "struct assignment source plan ToYul final snapshot"
      | _ => throw <| IO.userError "struct assignment source plan ToYul final statement must assign snapshot"
  | _ => throw <| IO.userError "struct assignment source plan ToYul helper must produce block"
  let structAssignStmts ← requireOk
    (lowerAssignStmt
      ProofForge.IR.Examples.EvmStructValueProbe.module
      structAssignEnv
      (.local "p")
      (.structLit "Point" #[
        ("x", .add (.local "n") (.literal (.u64 1))),
        ("y", .field (.local "q") "x")
      ]))
    "whole local struct assignment integration"
  require (structAssignStmts.size == 1) "whole local struct assignment integration statement count"
  match structAssignStmts[0]! with
  | Lean.Compiler.Yul.Statement.block block => do
      require (block.statements.size == 4) "whole local struct assignment integration block count"
      match block.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.call name args)) => do
          let firstVar ← requireAt vars 0 "whole local struct assignment integration missing temp"
          require (firstVar.name == "__proof_forge_assign_struct_p_x") "whole local struct assignment integration temp"
          require (name == "__pf_checked_add") "whole local struct assignment integration planned expression helper"
          require (args.size == 2) "whole local struct assignment integration helper arg count"
      | _ => throw <| IO.userError "whole local struct assignment integration must snapshot planned expression first"
  | _ => throw <| IO.userError "whole local struct assignment integration must lower to ToYul block"
  let storageStructAssignEnv : TypeEnv := #[
    { name := "p", type := .structType "Point", isMutable := true }
  ]
  let storageStructSourcePlans ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.structAssignmentSourcePlans
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      (toValidateTypeEnv storageStructAssignEnv)
      "p"
      "Point"
      (.effect (.storageScalarRead "current")))
    "Lower storage-backed struct assignment source plans"
  require (storageStructSourcePlans.size == 2) "Lower storage-backed struct assignment source plan count"
  let storageStructSourcePlan0 ← requireAt storageStructSourcePlans 0 "Lower storage-backed struct assignment source plan missing field x"
  let storageStructSourcePlan1 ← requireAt storageStructSourcePlans 1 "Lower storage-backed struct assignment source plan missing field y"
  match storageStructSourcePlan0.expr, storageStructSourcePlan1.expr with
  | ExprPlan.storageLoad (.scalarSlot slot0), ExprPlan.storageLoad (.scalarSlot slot1) => do
      require (storageStructSourcePlan0.fieldName == "x") "Lower storage-backed struct assignment source plan field x"
      require (storageStructSourcePlan1.fieldName == "y") "Lower storage-backed struct assignment source plan field y"
      require (slot0 == 1) "Lower storage-backed struct assignment source plan slot x"
      require (slot1 == 2) "Lower storage-backed struct assignment source plan slot y"
  | _, _ => throw <| IO.userError "Lower storage-backed struct assignment source plans must use storageLoad plans"
  let storageStructPlanStmt ← requireOk
    (ProofForge.Backend.Evm.ToYul.wholeStructAssignStmtFromPlan
      (lowerExprPlanExpr ProofForge.IR.Examples.EvmStorageStructProbe.module storageStructAssignEnv)
      "p"
      storageStructSourcePlans)
    "storage-backed struct assignment source plan ToYul helper"
  match storageStructPlanStmt with
  | Lean.Compiler.Yul.Statement.block block => do
      require (block.statements.size == 4) "storage-backed struct assignment source plan ToYul statement count"
      match block.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.builtin "sload" args)) => do
          let firstVar ← requireAt vars 0 "storage-backed struct assignment source plan ToYul missing first snapshot var"
          require (firstVar.name == "__proof_forge_assign_struct_p_x") "storage-backed struct assignment source plan ToYul first snapshot"
          let slotExpr ← requireAt args 0 "storage-backed struct assignment source plan ToYul missing first slot"
          match slotExpr with
          | Lean.Compiler.Yul.Expr.lit literal =>
              require (literal.value == "1") "storage-backed struct assignment source plan ToYul first slot"
          | _ => throw <| IO.userError "storage-backed struct assignment source plan ToYul first slot must be numeric"
      | _ => throw <| IO.userError "storage-backed struct assignment source plan ToYul first statement must snapshot sload"
      match block.statements[3]! with
      | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.ident valueName) => do
          require (names == #["__proof_forge_struct_p_y"]) "storage-backed struct assignment source plan ToYul final target"
          require (valueName == "__proof_forge_assign_struct_p_y") "storage-backed struct assignment source plan ToYul final snapshot"
      | _ => throw <| IO.userError "storage-backed struct assignment source plan ToYul final statement must assign snapshot"
  | _ => throw <| IO.userError "storage-backed struct assignment source plan ToYul helper must produce block"
  let storageStructAssignStmts ← requireOk
    (lowerAssignStmt
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      storageStructAssignEnv
      (.local "p")
      (.effect (.storageScalarRead "current")))
    "whole local storage-backed struct assignment integration"
  require (storageStructAssignStmts.size == 1) "whole local storage-backed struct assignment integration statement count"
  match storageStructAssignStmts[0]! with
  | Lean.Compiler.Yul.Statement.block block => do
      require (block.statements.size == 4) "whole local storage-backed struct assignment integration block count"
      match block.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.builtin "sload" args)) => do
          let firstVar ← requireAt vars 0 "whole local storage-backed struct assignment integration missing temp"
          require (firstVar.name == "__proof_forge_assign_struct_p_x") "whole local storage-backed struct assignment integration temp"
          let slotExpr ← requireAt args 0 "whole local storage-backed struct assignment integration missing first slot"
          match slotExpr with
          | Lean.Compiler.Yul.Expr.lit literal =>
              require (literal.value == "1") "whole local storage-backed struct assignment integration first slot"
          | _ => throw <| IO.userError "whole local storage-backed struct assignment integration first slot must be numeric"
      | _ => throw <| IO.userError "whole local storage-backed struct assignment integration must snapshot storage load first"
  | _ => throw <| IO.userError "whole local storage-backed struct assignment integration must lower to ToYul block"
  let dynamicStmts ← requireOk
    (lowerAssignStmt
      ProofForge.IR.Examples.Counter.module
      env
      (.arrayGet (.local "xs") (.add (.local "idx") (.literal (.u64 0))))
      (.add (.local "idx") (.literal (.u64 7))))
    "dynamic local fixed-array assignment integration"
  require (dynamicStmts.size == 1) "dynamic local fixed-array assignment integration statement count"
  match dynamicStmts[0]! with
  | Lean.Compiler.Yul.Statement.block block => do
      require (block.statements.size == 3) "dynamic local fixed-array assignment integration frame count"
      match block.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl _ (some (Lean.Compiler.Yul.Expr.call name args)) => do
          require (name == "__pf_checked_add") "dynamic local fixed-array assignment index must lower through ExprPlan"
          require (args.size == 2) "dynamic local fixed-array assignment index helper arg count"
      | _ => throw <| IO.userError "dynamic local fixed-array assignment index snapshot must be planned checked add"
      match block.statements[1]! with
      | Lean.Compiler.Yul.Statement.varDecl _ (some (Lean.Compiler.Yul.Expr.call name args)) => do
          require (name == "__pf_checked_add") "dynamic local fixed-array assignment value must lower through ExprPlan"
          require (args.size == 2) "dynamic local fixed-array assignment value helper arg count"
      | _ => throw <| IO.userError "dynamic local fixed-array assignment value snapshot must be planned checked add"
      match block.statements[2]! with
      | Lean.Compiler.Yul.Statement.switchStmt (Lean.Compiler.Yul.Expr.ident switchName) cases => do
          require (switchName == "__proof_forge_array_index") "dynamic local fixed-array assignment integration switch index"
          require (cases.size == 3) "dynamic local fixed-array assignment integration case count"
      | _ => throw <| IO.userError "dynamic local fixed-array assignment integration must switch on planned index"
  | _ => throw <| IO.userError "dynamic local fixed-array assignment integration must lower to ToYul frame"
  let dynamicAssignOpStmts ← requireOk
    (lowerAssignOpStmt
      ProofForge.IR.Examples.Counter.module
      env
      (.arrayGet (.local "xs") (.add (.local "idx") (.literal (.u64 0))))
      .add
      (.add (.local "idx") (.literal (.u64 5))))
    "dynamic local fixed-array compound assignment integration"
  require (dynamicAssignOpStmts.size == 1) "dynamic local fixed-array compound assignment integration statement count"
  match dynamicAssignOpStmts[0]! with
  | Lean.Compiler.Yul.Statement.block block => do
      require (block.statements.size == 3) "dynamic local fixed-array compound assignment integration frame count"
      match block.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl _ (some (Lean.Compiler.Yul.Expr.call name args)) => do
          require (name == "__pf_checked_add") "dynamic local fixed-array compound assignment index must lower through ExprPlan"
          require (args.size == 2) "dynamic local fixed-array compound assignment index helper arg count"
      | _ => throw <| IO.userError "dynamic local fixed-array compound assignment index snapshot must be planned checked add"
      match block.statements[1]! with
      | Lean.Compiler.Yul.Statement.varDecl _ (some (Lean.Compiler.Yul.Expr.call name args)) => do
          require (name == "__pf_checked_add") "dynamic local fixed-array compound assignment value must lower through ExprPlan"
          require (args.size == 2) "dynamic local fixed-array compound assignment value helper arg count"
      | _ => throw <| IO.userError "dynamic local fixed-array compound assignment value snapshot must be planned checked add"
      match block.statements[2]! with
      | Lean.Compiler.Yul.Statement.switchStmt (Lean.Compiler.Yul.Expr.ident switchName) cases => do
          require (switchName == "__proof_forge_array_index") "dynamic local fixed-array compound assignment integration switch index"
          require (cases.size == 3) "dynamic local fixed-array compound assignment integration case count"
      | _ => throw <| IO.userError "dynamic local fixed-array compound assignment integration must switch on planned index"
  | _ => throw <| IO.userError "dynamic local fixed-array compound assignment integration must lower to ToYul frame"

def testScalarAssertPlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "n", type := .u64, isMutable := false }]
  let checkGuardBuiltin := fun (stmt : Lean.Compiler.Yul.Statement) (expected : String) (label : String) => do
    match stmt with
    | Lean.Compiler.Yul.Statement.ifStmt (Lean.Compiler.Yul.Expr.builtin name args) _ => do
        require (name == "iszero") s!"{label} guard builtin"
        require (args.size == 1) s!"{label} iszero arg count"
        match args[0]! with
        | Lean.Compiler.Yul.Expr.builtin name _ =>
            require (name == expected) s!"{label} condition builtin"
        | _ => throw <| IO.userError s!"{label} condition must be builtin"
    | _ => throw <| IO.userError s!"{label} must lower to if iszero"
  let directAssertStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.scalarAssertStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.Counter.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.Counter.module env)
      (fun _ => #[revertStmt])
      (ProofForge.Backend.Evm.Plan.StmtPlan.assert
        (.builtin "gt" #[.local "n", .literalWord 0])
        "positive"
        none))
    "scalar assert StmtPlan-to-Yul helper"
  require (directAssertStmts.size == 1) "scalar assert StmtPlan-to-Yul helper statement count"
  checkGuardBuiltin directAssertStmts[0]! "gt" "scalar assert StmtPlan-to-Yul helper"
  let directAssertEqStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.scalarAssertStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.Counter.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.Counter.module env)
      (fun _ => #[revertStmt])
      (ProofForge.Backend.Evm.Plan.StmtPlan.assertEq
        (.local "n")
        (.literalWord 1)
        "one"
        none))
    "scalar assertEq StmtPlan-to-Yul helper"
  require (directAssertEqStmts.size == 1) "scalar assertEq StmtPlan-to-Yul helper statement count"
  checkGuardBuiltin directAssertEqStmts[0]! "eq" "scalar assertEq StmtPlan-to-Yul helper"
  let (assertStmts, _) ← requireOk
    (lowerStatement
      ProofForge.IR.Examples.Counter.module
      "scalar_assert"
      .unit
      env
      false
      (.assert (.gt (.local "n") (.literal (.u64 0))) "positive" none))
    "scalar assert statement plan-to-yul integration"
  require (assertStmts.size == 1) "scalar assert statement plan-to-yul integration statement count"
  match assertStmts[0]! with
  | Lean.Compiler.Yul.Statement.ifStmt (Lean.Compiler.Yul.Expr.builtin name args) _ => do
      require (name == "iszero") "scalar assert statement plan-to-yul integration guard builtin"
      require (args.size == 1) "scalar assert statement plan-to-yul integration iszero arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.builtin name _ =>
          require (name == "gt") "scalar assert statement plan-to-yul integration condition builtin"
      | _ => throw <| IO.userError "scalar assert statement plan-to-yul integration condition must be builtin"
  | _ => throw <| IO.userError "scalar assert statement plan-to-yul integration must lower to if iszero"
  let (assertEqStmts, _) ← requireOk
    (lowerStatement
      ProofForge.IR.Examples.Counter.module
      "scalar_assert_eq"
      .unit
      env
      false
      (.assertEq (.local "n") (.literal (.u64 1)) "one" none))
    "scalar assertEq statement plan-to-yul integration"
  require (assertEqStmts.size == 1) "scalar assertEq statement plan-to-yul integration statement count"
  match assertEqStmts[0]! with
  | Lean.Compiler.Yul.Statement.ifStmt (Lean.Compiler.Yul.Expr.builtin name args) _ => do
      require (name == "iszero") "scalar assertEq statement plan-to-yul integration guard builtin"
      require (args.size == 1) "scalar assertEq statement plan-to-yul integration iszero arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.builtin name _ =>
          require (name == "eq") "scalar assertEq statement plan-to-yul integration condition builtin"
      | _ => throw <| IO.userError "scalar assertEq statement plan-to-yul integration condition must be builtin"
  | _ => throw <| IO.userError "scalar assertEq statement plan-to-yul integration must lower to if iszero"

def testScalarReturnPlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "n", type := .u64, isMutable := false }]
  let dynamicReturnPlan : ReturnPlan := {
    returnType := .bytes
    wordTypes := #[.bytes]
    localNames := #["result"]
  }
  let directDynamicStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.dynamicReturnStmtPlanStatements
      toYulError
      dynamicReturnPlan
      false
      (ProofForge.Backend.Evm.Plan.StmtPlan.return (.local "data")))
    "dynamic return StmtPlan-to-Yul helper"
  require (directDynamicStmts.size == 1) "dynamic return StmtPlan-to-Yul helper statement count"
  match directDynamicStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.ident valueName) => do
      require (names == #["result"]) "dynamic return StmtPlan-to-Yul helper target"
      require (valueName == "data__data_ptr") "dynamic return StmtPlan-to-Yul helper data ptr"
  | _ => throw <| IO.userError "dynamic return StmtPlan-to-Yul helper must assign data pointer"
  let directStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.scalarReturnStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.Counter.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.Counter.module env)
      #["result"]
      false
      (ProofForge.Backend.Evm.Plan.StmtPlan.return
        (.checkedArith .add (.local "n") (.literalWord 1))))
    "scalar return StmtPlan-to-Yul helper"
  require (directStmts.size == 1) "scalar return StmtPlan-to-Yul helper statement count"
  match directStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["result"]) "scalar return StmtPlan-to-Yul helper target"
      require (name == "__pf_checked_add") "scalar return StmtPlan-to-Yul helper checked add"
      require (args.size == 2) "scalar return StmtPlan-to-Yul helper checked add arg count"
  | _ => throw <| IO.userError "scalar return StmtPlan-to-Yul helper must assign helper result"
  let directLeaveStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.scalarReturnStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.Counter.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.Counter.module env)
      #["result"]
      true
      (ProofForge.Backend.Evm.Plan.StmtPlan.return
        (.effect (.storageScalarRead "count"))))
    "scalar return StmtPlan-to-Yul helper leave"
  require (directLeaveStmts.size == 2) "scalar return StmtPlan-to-Yul helper leave statement count"
  match directLeaveStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.builtin name args) => do
      require (names == #["result"]) "scalar return StmtPlan-to-Yul helper leave target"
      -- Packed read: and(shr(shift, sload(slot)), mask)
      require (name == "and") "scalar return StmtPlan-to-Yul helper leave packed read (and)"
      require (args.size == 2) "scalar return StmtPlan-to-Yul helper leave packed read arg count"
  | _ => throw <| IO.userError "scalar return StmtPlan-to-Yul helper leave must assign packed read (and/shr/sload)"
  match directLeaveStmts[1]! with
  | Lean.Compiler.Yul.Statement.leave => pure ()
  | _ => throw <| IO.userError "scalar return StmtPlan-to-Yul helper leave must append leave"
  let returnStmts ← requireOk
    (lowerReturnStmt
      ProofForge.IR.Examples.Counter.module
      env
      "checked_return"
      .u64
      (.add (.local "n") (.literal (.u64 1)))
      false)
    "scalar return plan-to-yul"
  require (returnStmts.size == 1) "scalar return plan-to-yul statement count"
  match returnStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["result"]) "scalar return plan-to-yul target"
      require (name == "__pf_checked_add") "scalar return plan-to-yul helper"
      require (args.size == 2) "scalar return plan-to-yul arg count"
  | _ => throw <| IO.userError "scalar return plan-to-yul must assign helper result"
  let dynamicReturnStmts ← requireOk
    (lowerReturnStmt
      ProofForge.IR.Examples.EvmDynamicAbiProbe.module
      (entrypointTypeEnv ProofForge.IR.Examples.EvmDynamicAbiProbe.echoBytes)
      "echo_bytes"
      .bytes
      (.local "data")
      false)
    "dynamic return plan-to-yul"
  require (dynamicReturnStmts.size == 1) "dynamic return plan-to-yul statement count"
  match dynamicReturnStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.ident valueName) => do
      require (names == #["result"]) "dynamic return plan-to-yul target"
      require (valueName == "data__data_ptr") "dynamic return plan-to-yul data ptr"
  | _ => throw <| IO.userError "dynamic return plan-to-yul must assign data pointer"
  let storageReturnStmts ← requireOk
    (lowerReturnStmt
      ProofForge.IR.Examples.Counter.module
      #[]
      "storage_return"
      .u64
      (.effect (.storageScalarRead "count"))
      false)
    "storage scalar return plan-to-yul"
  require (storageReturnStmts.size == 1) "storage scalar return plan-to-yul statement count"
  match storageReturnStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.builtin name args) => do
      require (names == #["result"]) "storage scalar return plan-to-yul target"
      -- Packed read: and(shr(shift, sload(slot)), mask)
      require (name == "and") "storage scalar return plan-to-yul opcode (packed read = and)"
      require (args.size == 2) "storage scalar return plan-to-yul arg count (and)"
  | _ => throw <| IO.userError "storage scalar return plan-to-yul must assign packed read (and/shr/sload)"

def testScalarBindingStmtPlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "n", type := .u64, isMutable := false }]
  let directStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.scalarBindingStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.Counter.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.Counter.module env)
      (.letBind
        "m"
        .u64
        (.checkedArith .add (.local "n") (.literalWord 1))))
    "scalar let StmtPlan-to-Yul helper"
  require (directStmts.size == 1) "scalar let StmtPlan-to-Yul helper statement count"
  match directStmts[0]! with
  | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.call name args)) => do
      match vars[0]? with
      | some var => require (var.name == "m") "scalar let StmtPlan-to-Yul helper var name"
      | none => throw <| IO.userError "scalar let StmtPlan-to-Yul helper missing var"
      require (name == "__pf_checked_add") "scalar let StmtPlan-to-Yul helper checked add"
      require (args.size == 2) "scalar let StmtPlan-to-Yul helper checked add arg count"
  | _ => throw <| IO.userError "scalar let StmtPlan-to-Yul helper must lower to var decl"
  let (letStmts, _) ← requireOk
    (lowerStatement
      ProofForge.IR.Examples.Counter.module
      "scalar_binding"
      .unit
      env
      false
      (.letBind "m" .u64 (.add (.local "n") (.literal (.u64 1)))))
    "scalar let statement plan-to-yul integration"
  require (letStmts.size == 1) "scalar let statement plan-to-yul integration statement count"
  match letStmts[0]! with
  | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.call name args)) => do
      match vars[0]? with
      | some var => require (var.name == "m") "scalar let statement plan-to-yul integration var name"
      | none => throw <| IO.userError "scalar let statement plan-to-yul integration missing var"
      require (name == "__pf_checked_add") "scalar let statement plan-to-yul integration checked add"
      require (args.size == 2) "scalar let statement plan-to-yul integration checked add arg count"
  | _ => throw <| IO.userError "scalar let statement plan-to-yul integration must lower to var decl"
  let (letMutStmts, _) ← requireOk
    (lowerStatement
      ProofForge.IR.Examples.Counter.module
      "scalar_binding"
      .unit
      #[]
      false
      (.letMutBind "m" .u64 (.effect (.storageScalarRead "count"))))
    "scalar let mut statement plan-to-yul integration"
  require (letMutStmts.size == 1) "scalar let mut statement plan-to-yul integration statement count"
  match letMutStmts[0]! with
  | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.builtin name args)) => do
      match vars[0]? with
      | some var => require (var.name == "m") "scalar let mut statement plan-to-yul integration var name"
      | none => throw <| IO.userError "scalar let mut statement plan-to-yul integration missing var"
      require (name == "and") "scalar let mut statement plan-to-yul integration packed read (and)"
      require (args.size == 2) "scalar let mut statement plan-to-yul integration packed read arg count"
  | _ => throw <| IO.userError "scalar let mut statement plan-to-yul integration must lower to var decl"

def testScalarAssignmentPlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "n", type := .u64, isMutable := true }]
  let arrayEnv : TypeEnv := #[
    { name := "xs", type := .fixedArray .u64 2, isMutable := true },
    { name := "n", type := .u64, isMutable := true }
  ]
  let structEnv : TypeEnv := #[
    { name := "p", type := .structType "Point", isMutable := true },
    { name := "n", type := .u64, isMutable := true }
  ]
  let structArrayEnv : TypeEnv := #[
    { name := "people", type := .fixedArray (.structType "Person") 2, isMutable := true },
    { name := "n", type := .u64, isMutable := true }
  ]
  let directAssignStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.scalarAssignmentStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.Counter.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.Counter.module env)
      (ProofForge.Backend.Evm.Plan.StmtPlan.assign
        (.local "n")
        (.checkedArith .add (.local "n") (.literalWord 1))))
    "scalar assignment StmtPlan-to-Yul helper"
  require (directAssignStmts.size == 1) "scalar assignment StmtPlan-to-Yul helper statement count"
  match directAssignStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["n"]) "scalar assignment StmtPlan-to-Yul helper target"
      require (name == "__pf_checked_add") "scalar assignment StmtPlan-to-Yul helper checked add"
      require (args.size == 2) "scalar assignment StmtPlan-to-Yul helper checked add arg count"
  | _ => throw <| IO.userError "scalar assignment StmtPlan-to-Yul helper must assign helper result"
  let directAssignOpStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.scalarAssignmentStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.Counter.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.Counter.module env)
      (ProofForge.Backend.Evm.Plan.StmtPlan.assignOp
        (.local "n")
        .add
        (.effect (.storageScalarRead "count"))))
    "scalar compound assignment StmtPlan-to-Yul helper"
  require (directAssignOpStmts.size == 1) "scalar compound assignment StmtPlan-to-Yul helper statement count"
  match directAssignOpStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["n"]) "scalar compound assignment StmtPlan-to-Yul helper target"
      require (name == "__pf_checked_add") "scalar compound assignment StmtPlan-to-Yul helper checked add"
      require (args.size == 2) "scalar compound assignment StmtPlan-to-Yul helper checked add arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.builtin name _ =>
          require (name == "and") "scalar compound assignment StmtPlan-to-Yul helper rhs packed read (and)"
      | _ => throw <| IO.userError "scalar compound assignment StmtPlan-to-Yul helper rhs must be sload"
  | _ => throw <| IO.userError "scalar compound assignment StmtPlan-to-Yul helper must assign helper result"
  let directArrayAssignStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.scalarAssignmentStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.Counter.module arrayEnv expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.Counter.module arrayEnv)
      (ProofForge.Backend.Evm.Plan.StmtPlan.assign
        (.localArrayGet "xs" #[.literalWord 1] #[2])
        (.literalWord 9)))
    "static local-array assignment StmtPlan-to-Yul helper"
  require (directArrayAssignStmts.size == 1) "static local-array assignment StmtPlan-to-Yul helper statement count"
  match directArrayAssignStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.lit lit) => do
      require (names == #["__proof_forge_array_xs_1"]) "static local-array assignment StmtPlan-to-Yul target"
      require (lit.value == "9") "static local-array assignment StmtPlan-to-Yul value"
  | _ => throw <| IO.userError "static local-array assignment StmtPlan-to-Yul helper must assign literal"
  let directArrayAssignOpStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.scalarAssignmentStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.Counter.module arrayEnv expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.Counter.module arrayEnv)
      (ProofForge.Backend.Evm.Plan.StmtPlan.assignOp
        (.localArrayGet "xs" #[.literalWord 0] #[2])
        .add
        (.local "n")))
    "static local-array compound assignment StmtPlan-to-Yul helper"
  require (directArrayAssignOpStmts.size == 1) "static local-array compound assignment StmtPlan-to-Yul helper statement count"
  match directArrayAssignOpStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["__proof_forge_array_xs_0"]) "static local-array compound assignment StmtPlan-to-Yul target"
      require (name == "__pf_checked_add") "static local-array compound assignment StmtPlan-to-Yul helper"
      require (args.size == 2) "static local-array compound assignment StmtPlan-to-Yul arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.ident name =>
          require (name == "__proof_forge_array_xs_0") "static local-array compound assignment StmtPlan-to-Yul lhs"
      | _ => throw <| IO.userError "static local-array compound assignment lhs must be target ident"
  | _ => throw <| IO.userError "static local-array compound assignment StmtPlan-to-Yul helper must assign helper result"
  let directStructAssignStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.scalarAssignmentStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStructValueProbe.module structEnv expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStructValueProbe.module structEnv)
      (ProofForge.Backend.Evm.Plan.StmtPlan.assign
        (.structField (.local "p") "x")
        (.literalWord 21)))
    "static local-struct field assignment StmtPlan-to-Yul helper"
  require (directStructAssignStmts.size == 1) "static local-struct field assignment StmtPlan-to-Yul helper statement count"
  match directStructAssignStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.lit lit) => do
      require (names == #["__proof_forge_struct_p_x"]) "static local-struct field assignment StmtPlan-to-Yul target"
      require (lit.value == "21") "static local-struct field assignment StmtPlan-to-Yul value"
  | _ => throw <| IO.userError "static local-struct field assignment StmtPlan-to-Yul helper must assign literal"
  let directStructArrayAssignOpStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.scalarAssignmentStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStructArrayValueProbe.module structArrayEnv expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStructArrayValueProbe.module structArrayEnv)
      (ProofForge.Backend.Evm.Plan.StmtPlan.assignOp
        (.structField (.localArrayGet "people" #[.literalWord 1] #[2]) "score")
        .add
        (.local "n")))
    "static local struct-array field compound assignment StmtPlan-to-Yul helper"
  require (directStructArrayAssignOpStmts.size == 1) "static local struct-array field compound assignment StmtPlan-to-Yul helper statement count"
  match directStructArrayAssignOpStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["__proof_forge_array_struct_people_1_score"]) "static local struct-array field compound assignment StmtPlan-to-Yul target"
      require (name == "__pf_checked_add") "static local struct-array field compound assignment StmtPlan-to-Yul helper"
      require (args.size == 2) "static local struct-array field compound assignment StmtPlan-to-Yul arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.ident name =>
          require (name == "__proof_forge_array_struct_people_1_score") "static local struct-array field compound assignment StmtPlan-to-Yul lhs"
      | _ => throw <| IO.userError "static local struct-array field compound assignment lhs must be target ident"
  | _ => throw <| IO.userError "static local struct-array field compound assignment StmtPlan-to-Yul helper must assign helper result"
  let assignStmts ← requireOk
    (lowerAssignStmt
      ProofForge.IR.Examples.Counter.module
      env
      (.local "n")
      (.add (.local "n") (.literal (.u64 1))))
    "scalar assignment plan-to-yul"
  require (assignStmts.size == 1) "scalar assignment plan-to-yul statement count"
  match assignStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["n"]) "scalar assignment plan-to-yul target"
      require (name == "__pf_checked_add") "scalar assignment plan-to-yul helper"
      require (args.size == 2) "scalar assignment plan-to-yul arg count"
  | _ => throw <| IO.userError "scalar assignment plan-to-yul must assign helper result"
  let assignOpStmts ← requireOk
    (lowerAssignOpStmt
      ProofForge.IR.Examples.Counter.module
      env
      (.local "n")
      .add
      (.effect (.storageScalarRead "count")))
    "scalar compound assignment plan-to-yul"
  require (assignOpStmts.size == 1) "scalar compound assignment plan-to-yul statement count"
  match assignOpStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["n"]) "scalar compound assignment plan-to-yul target"
      require (name == "__pf_checked_add") "scalar compound assignment plan-to-yul helper"
      require (args.size == 2) "scalar compound assignment plan-to-yul arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.builtin name _ =>
          -- Packed read: and(shr(..., sload(...)), mask)
          require (name == "and") "scalar compound assignment plan-to-yul rhs opcode (packed read = and)"
      | _ => throw <| IO.userError "scalar compound assignment plan-to-yul rhs must be packed read (and)"
  | _ => throw <| IO.userError "scalar compound assignment plan-to-yul must assign helper result"
  let arrayAssignStmts ← requireOk
    (lowerAssignStmt
      ProofForge.IR.Examples.Counter.module
      arrayEnv
      (.arrayGet (.local "xs") (.literal (.u64 1)))
      (.add (.local "n") (.literal (.u64 1))))
    "static local-array assignment plan-to-yul integration"
  require (arrayAssignStmts.size == 1) "static local-array assignment plan-to-yul integration statement count"
  match arrayAssignStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["__proof_forge_array_xs_1"]) "static local-array assignment plan-to-yul integration target"
      require (name == "__pf_checked_add") "static local-array assignment plan-to-yul integration helper"
      require (args.size == 2) "static local-array assignment plan-to-yul integration arg count"
  | _ => throw <| IO.userError "static local-array assignment plan-to-yul integration must assign helper result"
  let arrayAssignOpStmts ← requireOk
    (lowerAssignOpStmt
      ProofForge.IR.Examples.Counter.module
      arrayEnv
      (.arrayGet (.local "xs") (.literal (.u64 0)))
      .add
      (.local "n"))
    "static local-array compound assignment plan-to-yul integration"
  require (arrayAssignOpStmts.size == 1) "static local-array compound assignment plan-to-yul integration statement count"
  match arrayAssignOpStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["__proof_forge_array_xs_0"]) "static local-array compound assignment plan-to-yul integration target"
      require (name == "__pf_checked_add") "static local-array compound assignment plan-to-yul integration helper"
      require (args.size == 2) "static local-array compound assignment plan-to-yul integration arg count"
  | _ => throw <| IO.userError "static local-array compound assignment plan-to-yul integration must assign helper result"
  let structAssignStmts ← requireOk
    (lowerAssignStmt
      ProofForge.IR.Examples.EvmStructValueProbe.module
      structEnv
      (.field (.local "p") "x")
      (.add (.local "n") (.literal (.u64 1))))
    "static local-struct field assignment plan-to-yul integration"
  require (structAssignStmts.size == 1) "static local-struct field assignment plan-to-yul integration statement count"
  match structAssignStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["__proof_forge_struct_p_x"]) "static local-struct field assignment plan-to-yul integration target"
      require (name == "__pf_checked_add") "static local-struct field assignment plan-to-yul integration helper"
      require (args.size == 2) "static local-struct field assignment plan-to-yul integration arg count"
  | _ => throw <| IO.userError "static local-struct field assignment plan-to-yul integration must assign helper result"
  let structAssignOpStmts ← requireOk
    (lowerAssignOpStmt
      ProofForge.IR.Examples.EvmStructValueProbe.module
      structEnv
      (.field (.local "p") "y")
      .add
      (.local "n"))
    "static local-struct field compound assignment plan-to-yul integration"
  require (structAssignOpStmts.size == 1) "static local-struct field compound assignment plan-to-yul integration statement count"
  match structAssignOpStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["__proof_forge_struct_p_y"]) "static local-struct field compound assignment plan-to-yul integration target"
      require (name == "__pf_checked_add") "static local-struct field compound assignment plan-to-yul integration helper"
      require (args.size == 2) "static local-struct field compound assignment plan-to-yul integration arg count"
  | _ => throw <| IO.userError "static local-struct field compound assignment plan-to-yul integration must assign helper result"
  let structArrayAssignStmts ← requireOk
    (lowerAssignStmt
      ProofForge.IR.Examples.EvmStructArrayValueProbe.module
      structArrayEnv
      (.field (.arrayGet (.local "people") (.literal (.u64 1))) "age")
      (.add (.local "n") (.literal (.u64 1))))
    "static local struct-array field assignment plan-to-yul integration"
  require (structArrayAssignStmts.size == 1) "static local struct-array field assignment plan-to-yul integration statement count"
  match structArrayAssignStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["__proof_forge_array_struct_people_1_age"]) "static local struct-array field assignment plan-to-yul integration target"
      require (name == "__pf_checked_add") "static local struct-array field assignment plan-to-yul integration helper"
      require (args.size == 2) "static local struct-array field assignment plan-to-yul integration arg count"
  | _ => throw <| IO.userError "static local struct-array field assignment plan-to-yul integration must assign helper result"
  let structArrayAssignOpStmts ← requireOk
    (lowerAssignOpStmt
      ProofForge.IR.Examples.EvmStructArrayValueProbe.module
      structArrayEnv
      (.field (.arrayGet (.local "people") (.literal (.u64 0))) "score")
      .add
      (.local "n"))
    "static local struct-array field compound assignment plan-to-yul integration"
  require (structArrayAssignOpStmts.size == 1) "static local struct-array field compound assignment plan-to-yul integration statement count"
  match structArrayAssignOpStmts[0]! with
  | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
      require (names == #["__proof_forge_array_struct_people_0_score"]) "static local struct-array field compound assignment plan-to-yul integration target"
      require (name == "__pf_checked_add") "static local struct-array field compound assignment plan-to-yul integration helper"
      require (args.size == 2) "static local struct-array field compound assignment plan-to-yul integration arg count"
  | _ => throw <| IO.userError "static local struct-array field compound assignment plan-to-yul integration must assign helper result"
  let dynamicStructArrayAssignStmts ← requireOk
    (lowerAssignStmt
      ProofForge.IR.Examples.EvmStructArrayValueProbe.module
      structArrayEnv
      (.field (.arrayGet (.local "people") (.add (.local "n") (.literal (.u64 0)))) "age")
      (.add (.local "n") (.literal (.u64 1))))
    "dynamic local struct-array field assignment plan-to-yul integration"
  require (dynamicStructArrayAssignStmts.size == 1) "dynamic local struct-array field assignment statement count"
  match dynamicStructArrayAssignStmts[0]! with
  | Lean.Compiler.Yul.Statement.block block => do
      require (block.statements.size == 3) "dynamic local struct-array field assignment frame count"
      match block.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl _ (some (Lean.Compiler.Yul.Expr.call name args)) => do
          require (name == "__pf_checked_add") "dynamic local struct-array field assignment index must lower through ExprPlan"
          require (args.size == 2) "dynamic local struct-array field assignment index helper arg count"
      | _ => throw <| IO.userError "dynamic local struct-array field assignment index snapshot must be planned checked add"
      match block.statements[1]! with
      | Lean.Compiler.Yul.Statement.varDecl _ (some (Lean.Compiler.Yul.Expr.call name args)) => do
          require (name == "__pf_checked_add") "dynamic local struct-array field assignment value must lower through ExprPlan"
          require (args.size == 2) "dynamic local struct-array field assignment value helper arg count"
      | _ => throw <| IO.userError "dynamic local struct-array field assignment value snapshot must be planned checked add"
      match block.statements[2]! with
      | Lean.Compiler.Yul.Statement.switchStmt (Lean.Compiler.Yul.Expr.ident switchName) cases => do
          require (switchName == "__proof_forge_array_index") "dynamic local struct-array field assignment switch index"
          require (cases.size == 3) "dynamic local struct-array field assignment case count"
      | _ => throw <| IO.userError "dynamic local struct-array field assignment must switch on planned index"
  | _ => throw <| IO.userError "dynamic local struct-array field assignment must lower to ToYul frame"
  let dynamicStructArrayAssignOpStmts ← requireOk
    (lowerAssignOpStmt
      ProofForge.IR.Examples.EvmStructArrayValueProbe.module
      structArrayEnv
      (.field (.arrayGet (.local "people") (.add (.local "n") (.literal (.u64 0)))) "score")
      .add
      (.add (.local "n") (.literal (.u64 2))))
    "dynamic local struct-array field compound assignment plan-to-yul integration"
  require (dynamicStructArrayAssignOpStmts.size == 1) "dynamic local struct-array field compound assignment statement count"
  match dynamicStructArrayAssignOpStmts[0]! with
  | Lean.Compiler.Yul.Statement.block block => do
      require (block.statements.size == 3) "dynamic local struct-array field compound assignment frame count"
      match block.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl _ (some (Lean.Compiler.Yul.Expr.call name args)) => do
          require (name == "__pf_checked_add") "dynamic local struct-array field compound assignment index must lower through ExprPlan"
          require (args.size == 2) "dynamic local struct-array field compound assignment index helper arg count"
      | _ => throw <| IO.userError "dynamic local struct-array field compound assignment index snapshot must be planned checked add"
      match block.statements[1]! with
      | Lean.Compiler.Yul.Statement.varDecl _ (some (Lean.Compiler.Yul.Expr.call name args)) => do
          require (name == "__pf_checked_add") "dynamic local struct-array field compound assignment value must lower through ExprPlan"
          require (args.size == 2) "dynamic local struct-array field compound assignment value helper arg count"
      | _ => throw <| IO.userError "dynamic local struct-array field compound assignment value snapshot must be planned checked add"
      match block.statements[2]! with
      | Lean.Compiler.Yul.Statement.switchStmt (Lean.Compiler.Yul.Expr.ident switchName) cases => do
          require (switchName == "__proof_forge_array_index") "dynamic local struct-array field compound assignment switch index"
          require (cases.size == 3) "dynamic local struct-array field compound assignment case count"
      | _ => throw <| IO.userError "dynamic local struct-array field compound assignment must switch on planned index"
  | _ => throw <| IO.userError "dynamic local struct-array field compound assignment must lower to ToYul frame"

def testScalarControlFlowPlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "n", type := .u64, isMutable := true }]
  let (sequenceStmts, finalState) ← requireOk
    (ProofForge.Backend.Evm.ToYul.stmtPlanBodyStatements
      #[
        ProofForge.Backend.Evm.Plan.StmtPlan.letBind "a" .u64 (.literalWord 1),
        ProofForge.Backend.Evm.Plan.StmtPlan.return (.local "a")
      ]
      0
      false
      (fun state leaveAfterReturn _ => do
        let marker := if leaveAfterReturn then s!"step_{state}_leave" else s!"step_{state}_stay"
        .ok (#[Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.id marker)], state + 1)))
    "stmt plan body sequence helper"
  require (finalState == 2) "stmt plan body sequence helper final state"
  require (sequenceStmts.size == 2) "stmt plan body sequence helper statement count"
  match sequenceStmts[0]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.ident name) =>
      require (name == "step_0_leave") "stmt plan body sequence helper first leave flag"
  | _ => throw <| IO.userError "stmt plan body sequence helper first statement"
  match sequenceStmts[1]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.ident name) =>
      require (name == "step_1_stay") "stmt plan body sequence helper second leave flag"
  | _ => throw <| IO.userError "stmt plan body sequence helper second statement"
  let directEmptyRevertStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.revertStmtPlanStatements
      toYulError
      (fun _ => #[Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.id "error_ref_revert")])
      (ProofForge.Backend.Evm.Plan.StmtPlan.revert ""))
    "stmt plan empty revert helper"
  require (directEmptyRevertStmts.size == 1) "stmt plan empty revert helper statement count"
  match directEmptyRevertStmts[0]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin name args) => do
      require (name == "revert") "stmt plan empty revert helper builtin"
      require (args.size == 2) "stmt plan empty revert helper arg count"
  | _ => throw <| IO.userError "stmt plan empty revert helper must lower to revert builtin"
  let directMessageRevertStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.revertStmtPlanStatements
      toYulError
      (fun _ => #[Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.id "error_ref_revert")])
      (ProofForge.Backend.Evm.Plan.StmtPlan.revert "boom"))
    "stmt plan message revert helper"
  require (directMessageRevertStmts.size >= 2) "stmt plan message revert helper statement count"
  match directMessageRevertStmts[0]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin name args) => do
      require (name == "mstore") "stmt plan message revert helper starts with mstore"
      require (args.size == 2) "stmt plan message revert helper mstore arg count"
  | _ => throw <| IO.userError "stmt plan message revert helper must start with mstore"
  let directErrorRefRevertStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.revertStmtPlanStatements
      toYulError
      (fun ref => #[
        Lean.Compiler.Yul.Statement.exprStmt
          (Lean.Compiler.Yul.Expr.id s!"error_ref_{ref.assertionId.toNat}")])
      (ProofForge.Backend.Evm.Plan.StmtPlan.revertWithError
        ({ assertionId := 7, userCode? := some "Counter::Test" } : ProofForge.IR.ErrorRef)))
    "stmt plan error-ref revert helper"
  require (directErrorRefRevertStmts.size == 1) "stmt plan error-ref revert helper statement count"
  match directErrorRefRevertStmts[0]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.ident name) =>
      require (name == "error_ref_7") "stmt plan error-ref revert helper callback"
  | _ => throw <| IO.userError "stmt plan error-ref revert helper must use callback"
  let directIfStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.ifElseStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.Counter.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.Counter.module env)
      #[Lean.Compiler.Yul.Statement.assignment #["n"] (Lean.Compiler.Yul.Expr.num 2)]
      #[Lean.Compiler.Yul.Statement.assignment #["n"] (Lean.Compiler.Yul.Expr.num 1)]
      (ProofForge.Backend.Evm.Plan.StmtPlan.ifElse
        (.builtin "gt" #[.local "n", .literalWord 0])
        #[]
        #[]))
    "scalar ifElse StmtPlan-to-Yul helper"
  require (directIfStmts.size == 1) "scalar ifElse StmtPlan-to-Yul helper statement count"
  match directIfStmts[0]! with
  | Lean.Compiler.Yul.Statement.switchStmt (Lean.Compiler.Yul.Expr.builtin name args) cases => do
      require (name == "gt") "scalar ifElse StmtPlan-to-Yul helper opcode"
      require (args.size == 2) "scalar ifElse StmtPlan-to-Yul helper arg count"
      require (cases.size == 2) "scalar ifElse StmtPlan-to-Yul helper case count"
  | _ => throw <| IO.userError "scalar ifElse StmtPlan-to-Yul helper must lower to switch over builtin"
  let directForStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.boundedForStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.Counter.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.Counter.module env)
      #[Lean.Compiler.Yul.Statement.assignment #["n"] (Lean.Compiler.Yul.Expr.id "i")]
      (ProofForge.Backend.Evm.Plan.StmtPlan.boundedFor
        "i"
        0
        3
        #[]))
    "scalar boundedFor StmtPlan-to-Yul helper"
  require (directForStmts.size == 1) "scalar boundedFor StmtPlan-to-Yul helper statement count"
  match directForStmts[0]! with
  | Lean.Compiler.Yul.Statement.forLoop _ (Lean.Compiler.Yul.Expr.builtin name args) _ body => do
      require (name == "lt") "scalar boundedFor StmtPlan-to-Yul helper opcode"
      require (args.size == 2) "scalar boundedFor StmtPlan-to-Yul helper arg count"
      require (body.statements.size == 1) "scalar boundedFor StmtPlan-to-Yul helper body count"
  | _ => throw <| IO.userError "scalar boundedFor StmtPlan-to-Yul helper must lower to for over builtin"
  let plannedIf :=
    ProofForge.Backend.Evm.Plan.StmtPlan.ifElse
      (.builtin "gt" #[.local "n", .literalWord 0])
      #[
        .letBind "m" .u64 (.checkedArith .add (.local "n") (.literalWord 1)),
        .assign (.local "n") (.local "m")
      ]
      #[
        .effect (.storageScalarWrite "count" (.literalWord 7))
      ]
  let (plannedIfStmts, _) ← requireOk
    (lowerPlannedBodyStatement
      ProofForge.IR.Examples.Counter.module
      "control_flow"
      .unit
      env
      false
      plannedIf)
    "planned scalar ifElse body lowering"
  require (plannedIfStmts.size == 1) "planned scalar ifElse body lowering statement count"
  match plannedIfStmts[0]! with
  | Lean.Compiler.Yul.Statement.switchStmt (Lean.Compiler.Yul.Expr.builtin name args) cases => do
      require (name == "gt") "planned scalar ifElse body lowering opcode"
      require (args.size == 2) "planned scalar ifElse body lowering arg count"
      require (cases.size == 2) "planned scalar ifElse body lowering case count"
      let elseCase ← requireAt cases 0 "planned scalar ifElse body lowering else case"
      let thenCase ← requireAt cases 1 "planned scalar ifElse body lowering then case"
      require (thenCase.body.statements.size == 2) "planned scalar ifElse body lowering then statement count"
      require (elseCase.body.statements.size == 1) "planned scalar ifElse body lowering else statement count"
      match thenCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl names _ => do
          require (names.size == 1) "planned scalar ifElse body lowering let name count"
          let name ← requireAt names 0 "planned scalar ifElse body lowering let name value"
          require (name.name == "m") "planned scalar ifElse body lowering let name"
      | _ => throw <| IO.userError "planned scalar ifElse body lowering must keep planned let body"
      match thenCase.body.statements[1]! with
      | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.ident valueName) => do
          require (names == #["n"]) "planned scalar ifElse body lowering assignment target"
          require (valueName == "m") "planned scalar ifElse body lowering assignment value"
      | _ => throw <| IO.userError "planned scalar ifElse body lowering must keep planned assignment body"
      match elseCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin storageOp storageArgs) => do
          require (storageOp == "sstore") "planned scalar ifElse body lowering storage op"
          require (storageArgs.size == 2) "planned scalar ifElse body lowering storage arg count"
      | _ => throw <| IO.userError "planned scalar ifElse body lowering must keep planned storage body"
  | _ => throw <| IO.userError "planned scalar ifElse body lowering must lower to switch over builtin"
  let plannedFor :=
    ProofForge.Backend.Evm.Plan.StmtPlan.boundedFor
      "i"
      0
      2
      #[
        .assignOp (.local "n") .add (.local "i")
      ]
  let (plannedForStmts, _) ← requireOk
    (lowerPlannedBodyStatement
      ProofForge.IR.Examples.Counter.module
      "control_flow"
      .unit
      env
      false
      plannedFor)
    "planned scalar boundedFor body lowering"
  require (plannedForStmts.size == 1) "planned scalar boundedFor body lowering statement count"
  match plannedForStmts[0]! with
  | Lean.Compiler.Yul.Statement.forLoop _ (Lean.Compiler.Yul.Expr.builtin name args) _ body => do
      require (name == "lt") "planned scalar boundedFor body lowering opcode"
      require (args.size == 2) "planned scalar boundedFor body lowering arg count"
      require (body.statements.size == 1) "planned scalar boundedFor body lowering body count"
      match body.statements[0]! with
      | Lean.Compiler.Yul.Statement.assignment names _ =>
          require (names == #["n"]) "planned scalar boundedFor body lowering assignment target"
      | _ => throw <| IO.userError "planned scalar boundedFor body lowering must keep planned assignment body"
  | _ => throw <| IO.userError "planned scalar boundedFor body lowering must lower to for over builtin"
  let plannedControl? ← requireOk
    (plannedBodyStatement?
      ProofForge.IR.Examples.Counter.module
      "control_flow"
      .unit
      env
      (.ifElse
        (.gt (.local "n") (.literal (.u64 0)))
        #[.assign (.local "n") (.add (.local "n") (.literal (.u64 1)))]
        #[.effect (.storageScalarWrite "count" (.literal (.u64 1)))]))
    "planned scalar control-flow plan construction"
  match plannedControl? with
  | some (.ifElse _ thenBody elseBody) => do
      require (thenBody.size == 1) "planned scalar control-flow plan construction then body"
      require (elseBody.size == 1) "planned scalar control-flow plan construction else body"
  | _ => throw <| IO.userError "planned scalar control-flow plan construction must produce ifElse body plan"
  let aggregateEnv : TypeEnv := #[
    { name := "p", type := .structType "Point", isMutable := true },
    { name := "xs", type := .fixedArray .u64 2, isMutable := true },
    { name := "n", type := .u64, isMutable := true }
  ]
  let plannedAggregateControl? ← requireOk
    (plannedBodyStatement?
      ProofForge.IR.Examples.EvmStructValueProbe.module
      "control_flow"
      .unit
      aggregateEnv
      (.ifElse
        (.gt (.local "n") (.literal (.u64 0)))
        #[
          .assign
            (.field (.local "p") "x")
            (.add (.field (.local "p") "y") (.literal (.u64 1)))
        ]
        #[
          .assign
            (.arrayGet (.local "xs") (.literal (.u64 1)))
            (.field (.local "p") "x")
        ]))
    "planned aggregate scalar control-flow plan construction"
  let plannedAggregateControl ← requireSome plannedAggregateControl?
    "planned aggregate scalar control-flow plan construction missing plan"
  let (aggregateControlStmts, _) ← requireOk
    (lowerPlannedBodyStatement
      ProofForge.IR.Examples.EvmStructValueProbe.module
      "control_flow"
      .unit
      aggregateEnv
      false
      plannedAggregateControl)
    "planned aggregate scalar control-flow body lowering"
  require (aggregateControlStmts.size == 1) "planned aggregate scalar control-flow body lowering statement count"
  match aggregateControlStmts[0]! with
  | Lean.Compiler.Yul.Statement.switchStmt (Lean.Compiler.Yul.Expr.builtin name args) cases => do
      require (name == "gt") "planned aggregate scalar control-flow body lowering opcode"
      require (args.size == 2) "planned aggregate scalar control-flow body lowering arg count"
      require (cases.size == 2) "planned aggregate scalar control-flow body lowering case count"
      let elseCase ← requireAt cases 0 "planned aggregate scalar control-flow body lowering else case"
      let thenCase ← requireAt cases 1 "planned aggregate scalar control-flow body lowering then case"
      require (thenCase.body.statements.size == 1) "planned aggregate scalar control-flow body lowering then count"
      require (elseCase.body.statements.size == 1) "planned aggregate scalar control-flow body lowering else count"
      match thenCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.call name args) => do
          require (names == #["__proof_forge_struct_p_x"]) "planned aggregate scalar control-flow body lowering struct target"
          require (name == "__pf_checked_add") "planned aggregate scalar control-flow body lowering struct helper"
          require (args.size == 2) "planned aggregate scalar control-flow body lowering struct helper args"
      | _ => throw <| IO.userError "planned aggregate scalar control-flow body lowering must assign struct field"
      match elseCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.ident valueName) => do
          require (names == #["__proof_forge_array_xs_1"]) "planned aggregate scalar control-flow body lowering array target"
          require (valueName == "__proof_forge_struct_p_x") "planned aggregate scalar control-flow body lowering array value"
      | _ => throw <| IO.userError "planned aggregate scalar control-flow body lowering must assign local array element"
  | _ => throw <| IO.userError "planned aggregate scalar control-flow body lowering must lower to switch"
  let dynamicLocalArrayEnv : TypeEnv := #[
    { name := "xs", type := .fixedArray .u64 2, isMutable := false },
    { name := "idx", type := .u64, isMutable := false }
  ]
  let plannedDynamicLocalArrayControl? ← requireOk
    (plannedBodyStatement?
      ProofForge.IR.Examples.EvmStructArrayValueProbe.module
      "control_flow"
      .unit
      dynamicLocalArrayEnv
      (.ifElse
        (.gt (.local "idx") (.literal (.u64 0)))
        #[
          .letBind "item" .u64 (.arrayGet (.local "xs") (.local "idx"))
        ]
        #[
          .letBind "first" .u64 (.arrayGet (.local "xs") (.literal (.u64 0)))
        ]))
    "planned dynamic local-array control-flow plan construction"
  let plannedDynamicLocalArrayControl ← requireSome plannedDynamicLocalArrayControl?
    "planned dynamic local-array control-flow plan construction missing plan"
  let (dynamicLocalArrayControlStmts, _) ← requireOk
    (lowerPlannedBodyStatement
      ProofForge.IR.Examples.EvmStructArrayValueProbe.module
      "control_flow"
      .unit
      dynamicLocalArrayEnv
      false
      plannedDynamicLocalArrayControl)
    "planned dynamic local-array control-flow body lowering"
  match dynamicLocalArrayControlStmts[0]? with
  | some (Lean.Compiler.Yul.Statement.switchStmt _ cases) => do
      let elseCase ← requireAt cases 0 "planned dynamic local-array control-flow else case"
      let thenCase ← requireAt cases 1 "planned dynamic local-array control-flow then case"
      require (thenCase.body.statements.size == 1) "planned dynamic local-array control-flow then count"
      require (elseCase.body.statements.size == 1) "planned dynamic local-array control-flow else count"
      match thenCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl names (some (Lean.Compiler.Yul.Expr.call name args)) => do
          require (names.size == 1) "planned dynamic local-array control-flow then var count"
          let typedName ← requireAt names 0 "planned dynamic local-array control-flow then var"
          require (typedName.name == "item") "planned dynamic local-array control-flow then local name"
          require (name == "__proof_forge_local_array_get_2") "planned dynamic local-array control-flow helper"
          require (args.size == 3) "planned dynamic local-array control-flow helper arg count"
      | _ => throw <| IO.userError "planned dynamic local-array control-flow then must lower to helper binding"
      match elseCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl names (some (Lean.Compiler.Yul.Expr.ident valueName)) => do
          require (names.size == 1) "planned static local-array control-flow var count"
          let typedName ← requireAt names 0 "planned static local-array control-flow var"
          require (typedName.name == "first") "planned static local-array control-flow local name"
          require (valueName == "__proof_forge_array_xs_0") "planned static local-array control-flow local source"
      | _ => throw <| IO.userError "planned static local-array control-flow must lower to local binding"
  | _ => throw <| IO.userError "planned dynamic local-array control-flow body lowering must lower to switch"
  let dynamicLocalStructArrayEnv : TypeEnv := #[
    { name := "people", type := .fixedArray (.structType "Person") 2, isMutable := false },
    { name := "idx", type := .u64, isMutable := false }
  ]
  let plannedDynamicLocalStructArrayControl? ← requireOk
    (plannedBodyStatement?
      ProofForge.IR.Examples.EvmStructArrayValueProbe.module
      "control_flow"
      .unit
      dynamicLocalStructArrayEnv
      (.ifElse
        (.gt (.local "idx") (.literal (.u64 0)))
        #[
          .letBind "age" .u64 (.field (.arrayGet (.local "people") (.local "idx")) "age")
        ]
        #[
          .letBind "score" .u64 (.field (.arrayGet (.local "people") (.literal (.u64 0))) "score")
        ]))
    "planned dynamic local struct-array field control-flow plan construction"
  let plannedDynamicLocalStructArrayControl ← requireSome plannedDynamicLocalStructArrayControl?
    "planned dynamic local struct-array field control-flow plan construction missing plan"
  let (dynamicLocalStructArrayControlStmts, _) ← requireOk
    (lowerPlannedBodyStatement
      ProofForge.IR.Examples.EvmStructArrayValueProbe.module
      "control_flow"
      .unit
      dynamicLocalStructArrayEnv
      false
      plannedDynamicLocalStructArrayControl)
    "planned dynamic local struct-array field control-flow body lowering"
  match dynamicLocalStructArrayControlStmts[0]? with
  | some (Lean.Compiler.Yul.Statement.switchStmt _ cases) => do
      let elseCase ← requireAt cases 0 "planned dynamic local struct-array field control-flow else case"
      let thenCase ← requireAt cases 1 "planned dynamic local struct-array field control-flow then case"
      require (thenCase.body.statements.size == 1) "planned dynamic local struct-array field control-flow then count"
      require (elseCase.body.statements.size == 1) "planned dynamic local struct-array field control-flow else count"
      match thenCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl names (some (Lean.Compiler.Yul.Expr.call name args)) => do
          require (names.size == 1) "planned dynamic local struct-array field control-flow then var count"
          let typedName ← requireAt names 0 "planned dynamic local struct-array field control-flow then var"
          require (typedName.name == "age") "planned dynamic local struct-array field control-flow then local name"
          require (name == "__proof_forge_local_array_get_2") "planned dynamic local struct-array field control-flow helper"
          require (args.size == 3) "planned dynamic local struct-array field control-flow helper arg count"
      | _ => throw <| IO.userError "planned dynamic local struct-array field control-flow then must lower to helper binding"
      match elseCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl names (some (Lean.Compiler.Yul.Expr.ident valueName)) => do
          require (names.size == 1) "planned static local struct-array field control-flow var count"
          let typedName ← requireAt names 0 "planned static local struct-array field control-flow var"
          require (typedName.name == "score") "planned static local struct-array field control-flow local name"
          require (valueName == "__proof_forge_array_struct_people_0_score") "planned static local struct-array field control-flow local source"
      | _ => throw <| IO.userError "planned static local struct-array field control-flow must lower to local binding"
  | _ => throw <| IO.userError "planned dynamic local struct-array field control-flow body lowering must lower to switch"
  let immutableAggregatePlan? ← requireOk
    (plannedBodyStatement?
      ProofForge.IR.Examples.EvmStructValueProbe.module
      "control_flow"
      .unit
      #[
        { name := "p", type := .structType "Point", isMutable := false },
        { name := "n", type := .u64, isMutable := true }
      ]
      (.ifElse
        (.gt (.local "n") (.literal (.u64 0)))
        #[.assign (.field (.local "p") "x") (.literal (.u64 1))]
        #[]))
    "planned scalar control-flow validation guard"
  match immutableAggregatePlan? with
  | none => pure ()
  | some _ => throw <| IO.userError "planned scalar control-flow validation guard must reject immutable struct assignment"
  let plannedMapControl? ← requireOk
    (plannedBodyStatement?
      ProofForge.IR.Examples.EvmMapProbe.module
      "control_flow"
      .unit
      env
      (.ifElse
        (.gt (.local "n") (.literal (.u64 0)))
        #[
          .effect (.storageMapSet "balances" (.local "n") (.literal (.u64 9)))
        ]
        #[
          .effect (.storagePathWrite "balances" #[.mapKey (.literal (.u64 2002))] (.local "n"))
        ]))
    "planned map/path storage control-flow plan construction"
  let plannedMapControl ← requireSome plannedMapControl?
    "planned map/path storage control-flow plan construction missing plan"
  let (mapControlStmts, _) ← requireOk
    (lowerPlannedBodyStatement
      ProofForge.IR.Examples.EvmMapProbe.module
      "control_flow"
      .unit
      env
      false
      plannedMapControl)
    "planned map/path storage control-flow body lowering"
  match mapControlStmts[0]? with
  | some (Lean.Compiler.Yul.Statement.switchStmt _ cases) => do
      let elseCase ← requireAt cases 0 "planned map/path storage control-flow else case"
      let thenCase ← requireAt cases 1 "planned map/path storage control-flow then case"
      require (thenCase.body.statements.size == 1) "planned map storage control-flow then count"
      require (elseCase.body.statements.size == 1) "planned map path storage control-flow else count"
      match thenCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.call name args) => do
          require (name == "__proof_forge_map_write") "planned map storage control-flow helper"
          require (args.size == 3) "planned map storage control-flow helper arg count"
      | _ => throw <| IO.userError "planned map storage control-flow must lower to map write helper"
      match elseCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.call name args) => do
          require (name == "__proof_forge_map_write") "planned map path storage control-flow helper"
          require (args.size == 3) "planned map path storage control-flow helper arg count"
      | _ => throw <| IO.userError "planned map path storage control-flow must lower to map write helper"
  | _ => throw <| IO.userError "planned map/path storage control-flow body lowering must lower to switch"
  let plannedMapReadControl? ← requireOk
    (plannedBodyStatement?
      ProofForge.IR.Examples.EvmMapProbe.module
      "control_flow"
      .unit
      env
      (.ifElse
        (.gt (.local "n") (.literal (.u64 0)))
        #[
          .letBind "present" .bool (.effect (.storageMapContains "balances" (.local "n")))
        ]
        #[
          .letBind "value" .u64 (.effect (.storageMapGet "balances" (.local "n")))
        ]))
    "planned map read control-flow plan construction"
  let plannedMapReadControl ← requireSome plannedMapReadControl?
    "planned map read control-flow plan construction missing plan"
  let (mapReadControlStmts, _) ← requireOk
    (lowerPlannedBodyStatement
      ProofForge.IR.Examples.EvmMapProbe.module
      "control_flow"
      .unit
      env
      false
      plannedMapReadControl)
    "planned map read control-flow body lowering"
  match mapReadControlStmts[0]? with
  | some (Lean.Compiler.Yul.Statement.switchStmt _ cases) => do
      let elseCase ← requireAt cases 0 "planned map read control-flow else case"
      let thenCase ← requireAt cases 1 "planned map read control-flow then case"
      require (thenCase.body.statements.size == 1) "planned map contains control-flow then count"
      require (elseCase.body.statements.size == 1) "planned map get control-flow else count"
      match thenCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl names (some (Lean.Compiler.Yul.Expr.builtin name args)) => do
          require (names.size == 1) "planned map contains control-flow var count"
          let typedName ← requireAt names 0 "planned map contains control-flow var"
          require (typedName.name == "present") "planned map contains control-flow local name"
          require (name == "iszero") "planned map contains control-flow outer iszero"
          require (args.size == 1) "planned map contains control-flow outer arg count"
          match args[0]! with
          | Lean.Compiler.Yul.Expr.builtin innerName innerArgs => do
              require (innerName == "iszero") "planned map contains control-flow inner iszero"
              require (innerArgs.size == 1) "planned map contains control-flow inner arg count"
              match innerArgs[0]! with
              | Lean.Compiler.Yul.Expr.builtin loadName loadArgs => do
                  require (loadName == "sload") "planned map contains control-flow sload"
                  require (loadArgs.size == 1) "planned map contains control-flow sload arg count"
                  requireCallExpr loadArgs[0]! (Helper.mapPresenceSlot).name 2
                    "planned map contains control-flow presence slot"
              | _ => throw <| IO.userError "planned map contains control-flow inner must load presence slot"
          | _ => throw <| IO.userError "planned map contains control-flow outer must wrap inner iszero"
      | _ => throw <| IO.userError "planned map contains control-flow must lower to bool binding"
      match elseCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl names (some (Lean.Compiler.Yul.Expr.builtin name args)) => do
          require (names.size == 1) "planned map get control-flow var count"
          let typedName ← requireAt names 0 "planned map get control-flow var"
          require (typedName.name == "value") "planned map get control-flow local name"
          require (name == "sload") "planned map get control-flow sload"
          require (args.size == 1) "planned map get control-flow sload arg count"
          requireCallExpr args[0]! (Helper.mapSlot).name 2
            "planned map get control-flow value slot"
      | _ => throw <| IO.userError "planned map get control-flow must lower to value binding"
  | _ => throw <| IO.userError "planned map read control-flow body lowering must lower to switch"
  let loopIndex := ProofForge.IR.Expr.cast (.local "i") .u64
  let plannedArrayControl? ← requireOk
    (plannedBodyStatement?
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      "control_flow"
      .unit
      env
      (.boundedFor
        "i"
        0
        2
        #[
          .effect (.storageArrayWrite "values" loopIndex (.local "n")),
          .effect (.storagePathAssignOp "values" #[.index loopIndex] .add (.literal (.u64 1)))
        ]))
    "planned array/path storage control-flow plan construction"
  let plannedArrayControl ← requireSome plannedArrayControl?
    "planned array/path storage control-flow plan construction missing plan"
  let (arrayControlStmts, _) ← requireOk
    (lowerPlannedBodyStatement
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      "control_flow"
      .unit
      env
      false
      plannedArrayControl)
    "planned array/path storage control-flow body lowering"
  match arrayControlStmts[0]? with
  | some (Lean.Compiler.Yul.Statement.forLoop _ _ _ body) => do
      require (body.statements.size == 2) "planned array/path storage control-flow body count"
      match body.statements[0]! with
      | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin name args) => do
          require (name == "sstore") "planned array storage control-flow opcode"
          require (args.size == 2) "planned array storage control-flow arg count"
      | _ => throw <| IO.userError "planned array storage control-flow must lower to sstore"
      match body.statements[1]! with
      | Lean.Compiler.Yul.Statement.block block =>
          require (block.statements.size == 2) "planned storage path assign control-flow block count"
      | _ => throw <| IO.userError "planned storage path assign control-flow must lower to block"
  | _ => throw <| IO.userError "planned array/path storage control-flow body lowering must lower to for"
  let plannedArrayReadControl? ← requireOk
    (plannedBodyStatement?
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      "control_flow"
      .unit
      env
      (.ifElse
        (.gt (.local "n") (.literal (.u64 0)))
        #[
          .letBind "item" .u64 (.effect (.storageArrayRead "values" (.local "n")))
        ]
        #[
          .letBind "first" .u64 (.effect (.storageArrayRead "values" (.literal (.u64 0))))
        ]))
    "planned array read control-flow plan construction"
  let plannedArrayReadControl ← requireSome plannedArrayReadControl?
    "planned array read control-flow plan construction missing plan"
  let (arrayReadControlStmts, _) ← requireOk
    (lowerPlannedBodyStatement
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      "control_flow"
      .unit
      env
      false
      plannedArrayReadControl)
    "planned array read control-flow body lowering"
  match arrayReadControlStmts[0]? with
  | some (Lean.Compiler.Yul.Statement.switchStmt _ cases) => do
      let elseCase ← requireAt cases 0 "planned array read control-flow else case"
      let thenCase ← requireAt cases 1 "planned array read control-flow then case"
      require (thenCase.body.statements.size == 1) "planned array read control-flow then count"
      require (elseCase.body.statements.size == 1) "planned array read control-flow else count"
      match thenCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl names (some (Lean.Compiler.Yul.Expr.builtin name args)) => do
          require (names.size == 1) "planned array read control-flow then var count"
          let typedName ← requireAt names 0 "planned array read control-flow then var"
          require (typedName.name == "item") "planned array read control-flow then local name"
          require (name == "sload") "planned array read control-flow then sload"
          require (args.size == 1) "planned array read control-flow then sload arg count"
          requireCallExpr args[0]! (Helper.arraySlot).name 3
            "planned array read control-flow then array slot"
      | _ => throw <| IO.userError "planned array read control-flow then must lower to value binding"
      match elseCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl names (some (Lean.Compiler.Yul.Expr.builtin name args)) => do
          require (names.size == 1) "planned array read control-flow else var count"
          let typedName ← requireAt names 0 "planned array read control-flow else var"
          require (typedName.name == "first") "planned array read control-flow else local name"
          require (name == "sload") "planned array read control-flow else sload"
          require (args.size == 1) "planned array read control-flow else sload arg count"
          requireCallExpr args[0]! (Helper.arraySlot).name 3
            "planned array read control-flow else array slot"
      | _ => throw <| IO.userError "planned array read control-flow else must lower to value binding"
  | _ => throw <| IO.userError "planned array read control-flow body lowering must lower to switch"
  let plannedStructReadControl? ← requireOk
    (plannedBodyStatement?
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      "control_flow"
      .unit
      env
      (.ifElse
        (.gt (.local "n") (.literal (.u64 0)))
        #[
          .letBind "x" .u64 (.effect (.storageStructFieldRead "current" "x"))
        ]
        #[
          .letBind "y" .u64 (.effect (.storageArrayStructFieldRead "points" (.local "n") "y"))
        ]))
    "planned struct read control-flow plan construction"
  let plannedStructReadControl ← requireSome plannedStructReadControl?
    "planned struct read control-flow plan construction missing plan"
  let (structReadControlStmts, _) ← requireOk
    (lowerPlannedBodyStatement
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      "control_flow"
      .unit
      env
      false
      plannedStructReadControl)
    "planned struct read control-flow body lowering"
  match structReadControlStmts[0]? with
  | some (Lean.Compiler.Yul.Statement.switchStmt _ cases) => do
      let elseCase ← requireAt cases 0 "planned struct read control-flow else case"
      let thenCase ← requireAt cases 1 "planned struct read control-flow then case"
      require (thenCase.body.statements.size == 1) "planned struct read control-flow then count"
      require (elseCase.body.statements.size == 1) "planned struct-array read control-flow else count"
      match thenCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl names (some (Lean.Compiler.Yul.Expr.builtin name args)) => do
          require (names.size == 1) "planned struct read control-flow then var count"
          let typedName ← requireAt names 0 "planned struct read control-flow then var"
          require (typedName.name == "x") "planned struct read control-flow then local name"
          require (name == "sload") "planned struct read control-flow then sload"
          require (args.size == 1) "planned struct read control-flow then sload arg count"
      | _ => throw <| IO.userError "planned struct read control-flow then must lower to value binding"
      match elseCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl names (some (Lean.Compiler.Yul.Expr.builtin name args)) => do
          require (names.size == 1) "planned struct-array read control-flow else var count"
          let typedName ← requireAt names 0 "planned struct-array read control-flow else var"
          require (typedName.name == "y") "planned struct-array read control-flow else local name"
          require (name == "sload") "planned struct-array read control-flow else sload"
          require (args.size == 1) "planned struct-array read control-flow else sload arg count"
          requireCallExpr args[0]! (Helper.structArraySlot).name 5
            "planned struct-array read control-flow else slot"
      | _ => throw <| IO.userError "planned struct-array read control-flow else must lower to value binding"
  | _ => throw <| IO.userError "planned struct read control-flow body lowering must lower to switch"
  let plannedPathReadControl? ← requireOk
    (plannedBodyStatement?
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      "control_flow"
      .unit
      env
      (.ifElse
        (.gt (.local "n") (.literal (.u64 0)))
        #[
          .letBind "path_x" .u64 (.effect (.storagePathRead "current" #[.field "x"]))
        ]
        #[
          .letBind "path_y" .u64 (.effect (.storagePathRead "points" #[.index (.local "n"), .field "y"]))
        ]))
    "planned storage path read control-flow plan construction"
  let plannedPathReadControl ← requireSome plannedPathReadControl?
    "planned storage path read control-flow plan construction missing plan"
  let (pathReadControlStmts, _) ← requireOk
    (lowerPlannedBodyStatement
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      "control_flow"
      .unit
      env
      false
      plannedPathReadControl)
    "planned storage path read control-flow body lowering"
  match pathReadControlStmts[0]? with
  | some (Lean.Compiler.Yul.Statement.switchStmt _ cases) => do
      let elseCase ← requireAt cases 0 "planned storage path read control-flow else case"
      let thenCase ← requireAt cases 1 "planned storage path read control-flow then case"
      require (thenCase.body.statements.size == 1) "planned storage path read control-flow then count"
      require (elseCase.body.statements.size == 1) "planned storage path read control-flow else count"
      match thenCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl names (some (Lean.Compiler.Yul.Expr.builtin name args)) => do
          require (names.size == 1) "planned storage path field read control-flow var count"
          let typedName ← requireAt names 0 "planned storage path field read control-flow var"
          require (typedName.name == "path_x") "planned storage path field read control-flow local name"
          require (name == "sload") "planned storage path field read control-flow sload"
          require (args.size == 1) "planned storage path field read control-flow sload arg count"
      | _ => throw <| IO.userError "planned storage path field read control-flow must lower to value binding"
      match elseCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl names (some (Lean.Compiler.Yul.Expr.builtin name args)) => do
          require (names.size == 1) "planned storage path struct-array read control-flow var count"
          let typedName ← requireAt names 0 "planned storage path struct-array read control-flow var"
          require (typedName.name == "path_y") "planned storage path struct-array read control-flow local name"
          require (name == "sload") "planned storage path struct-array read control-flow sload"
          require (args.size == 1) "planned storage path struct-array read control-flow sload arg count"
          requireCallExpr args[0]! (Helper.structArraySlot).name 5
            "planned storage path struct-array read control-flow slot"
      | _ => throw <| IO.userError "planned storage path struct-array read control-flow must lower to value binding"
  | _ => throw <| IO.userError "planned storage path read control-flow body lowering must lower to switch"
  let plannedEventControl? ← requireOk
    (plannedBodyStatement?
      ProofForge.IR.Examples.EventProbe.evmModule
      "control_flow"
      .unit
      env
      (.ifElse
        (.gt (.local "n") (.literal (.u64 0)))
        #[
          .effect (.eventEmit "ValueEvent" #[("value", .local "n")])
        ]
        #[
          .effect (.eventEmitIndexed
            "IndexedValue"
            #[("user", .literal (.u64 1))]
            #[("value", .local "n")])
        ]))
    "planned scalar event control-flow plan construction"
  let plannedEventControl ← requireSome plannedEventControl?
    "planned scalar event control-flow plan construction missing plan"
  let (eventControlStmts, _) ← requireOk
    (lowerPlannedBodyStatement
      ProofForge.IR.Examples.EventProbe.evmModule
      "control_flow"
      .unit
      env
      false
      plannedEventControl)
    "planned scalar event control-flow body lowering"
  match eventControlStmts[0]? with
  | some (Lean.Compiler.Yul.Statement.switchStmt _ cases) => do
      let elseCase ← requireAt cases 0 "planned scalar event control-flow else case"
      let thenCase ← requireAt cases 1 "planned scalar event control-flow then case"
      require (thenCase.body.statements.size == 1) "planned scalar event control-flow then count"
      require (elseCase.body.statements.size == 1) "planned scalar event control-flow else count"
      match thenCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.block block => do
          match block.statements[block.statements.size - 1]! with
          | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin name args) => do
              require (name == "log1") "planned scalar event control-flow data log"
              require (args.size == 3) "planned scalar event control-flow data log arg count"
          | _ => throw <| IO.userError "planned scalar event control-flow then block must end with log"
      | _ => throw <| IO.userError "planned scalar event control-flow then branch must lower to event block"
      match elseCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.block block => do
          match block.statements[block.statements.size - 1]! with
          | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin name args) => do
              require (name == "log2") "planned scalar indexed event control-flow log"
              require (args.size == 4) "planned scalar indexed event control-flow log arg count"
          | _ => throw <| IO.userError "planned scalar indexed event control-flow block must end with log"
      | _ => throw <| IO.userError "planned scalar indexed event control-flow else branch must lower to event block"
  | _ => throw <| IO.userError "planned scalar event control-flow body lowering must lower to switch"
  let crosscallEnv : TypeEnv := #[
    { name := "target", type := .u64, isMutable := false },
    { name := "method", type := .u64, isMutable := false },
    { name := "n", type := .u64, isMutable := true }
  ]
  let plannedCrosscallControl? ← requireOk
    (plannedBodyStatement?
      ProofForge.IR.Examples.EvmCrosscallProbe.module
      "control_flow"
      .unit
      crosscallEnv
      (.ifElse
        (.gt (.local "n") (.literal (.u64 0)))
        #[
          .letBind
            "remote"
            .u64
            (.crosscallInvokeTyped
              (.local "target")
              (.local "method")
              #[.local "n"]
              .u64),
          .assign (.local "n") (.local "remote")
        ]
        #[
          .assign (.local "n") (.literal (.u64 0))
        ]))
    "planned scalar crosscall control-flow plan construction"
  let plannedCrosscallControl ← requireSome plannedCrosscallControl?
    "planned scalar crosscall control-flow plan construction missing plan"
  let (crosscallControlStmts, _) ← requireOk
    (lowerPlannedBodyStatement
      ProofForge.IR.Examples.EvmCrosscallProbe.module
      "control_flow"
      .unit
      crosscallEnv
      false
      plannedCrosscallControl)
    "planned scalar crosscall control-flow body lowering"
  match crosscallControlStmts[0]? with
  | some (Lean.Compiler.Yul.Statement.switchStmt _ cases) => do
      let thenCase ← requireAt cases 1 "planned scalar crosscall control-flow then case"
      require (thenCase.body.statements.size == 2) "planned scalar crosscall control-flow then count"
      match thenCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl names (some (Lean.Compiler.Yul.Expr.call name args)) => do
          require (names.size == 1) "planned scalar crosscall control-flow var count"
          let typedName ← requireAt names 0 "planned scalar crosscall control-flow var"
          require (typedName.name == "remote") "planned scalar crosscall control-flow local name"
          require (name == "__proof_forge_crosscall_1") "planned scalar crosscall control-flow helper"
          require (args.size == 3) "planned scalar crosscall control-flow helper arg count"
      | _ => throw <| IO.userError "planned scalar crosscall control-flow must lower let initializer to helper call"
      match thenCase.body.statements[1]! with
      | Lean.Compiler.Yul.Statement.assignment names (Lean.Compiler.Yul.Expr.ident valueName) => do
          require (names == #["n"]) "planned scalar crosscall control-flow assignment target"
          require (valueName == "remote") "planned scalar crosscall control-flow assignment value"
      | _ => throw <| IO.userError "planned scalar crosscall control-flow must assign helper result"
  | _ => throw <| IO.userError "planned scalar crosscall control-flow body lowering must lower to switch"
  let createEnv : TypeEnv := #[
    { name := "value", type := .u64, isMutable := false },
    { name := "salt", type := .hash, isMutable := false },
    { name := "created", type := .u64, isMutable := true }
  ]
  let createHelperName :=
    "__proof_forge_create_" ++ ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex
  let create2HelperName :=
    "__proof_forge_create2_" ++ ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex
  let plannedCreateControl? ← requireOk
    (plannedBodyStatement?
      ProofForge.IR.Examples.EvmCrosscallProbe.module
      "control_flow"
      .unit
      createEnv
      (.ifElse
        (.eq (.local "value") (.literal (.u64 0)))
        #[
          .letBind
            "deployed"
            .u64
            (.crosscallCreate
              (.local "value")
              ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex),
          .assign (.local "created") (.local "deployed")
        ]
        #[
          .letBind
            "deployed2"
            .u64
            (.crosscallCreate2
              (.local "value")
              (.local "salt")
              ProofForge.IR.Examples.EvmCrosscallProbe.returnFortyTwoInitCodeHex),
          .assign (.local "created") (.local "deployed2")
        ]))
    "planned scalar create control-flow plan construction"
  let plannedCreateControl ← requireSome plannedCreateControl?
    "planned scalar create control-flow plan construction missing plan"
  let (createControlStmts, _) ← requireOk
    (lowerPlannedBodyStatement
      ProofForge.IR.Examples.EvmCrosscallProbe.module
      "control_flow"
      .unit
      createEnv
      false
      plannedCreateControl)
    "planned scalar create control-flow body lowering"
  match createControlStmts[0]? with
  | some (Lean.Compiler.Yul.Statement.switchStmt _ cases) => do
      let thenCase ← requireAt cases 1 "planned scalar create control-flow then case"
      require (thenCase.body.statements.size == 2) "planned scalar create control-flow then count"
      match thenCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl names (some (Lean.Compiler.Yul.Expr.call name args)) => do
          require (names.size == 1) "planned scalar create control-flow var count"
          let typedName ← requireAt names 0 "planned scalar create control-flow var"
          require (typedName.name == "deployed") "planned scalar create control-flow local name"
          require (name == createHelperName) "planned scalar create control-flow helper"
          require (args.size == 1) "planned scalar create control-flow helper arg count"
      | _ => throw <| IO.userError "planned scalar create control-flow must lower let initializer to helper call"
      let elseCase ← requireAt cases 0 "planned scalar create control-flow else case"
      require (elseCase.body.statements.size == 2) "planned scalar create2 control-flow else count"
      match elseCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl names (some (Lean.Compiler.Yul.Expr.call name args)) => do
          require (names.size == 1) "planned scalar create2 control-flow var count"
          let typedName ← requireAt names 0 "planned scalar create2 control-flow var"
          require (typedName.name == "deployed2") "planned scalar create2 control-flow local name"
          require (name == create2HelperName) "planned scalar create2 control-flow helper"
          require (args.size == 2) "planned scalar create2 control-flow helper arg count"
      | _ => throw <| IO.userError "planned scalar create2 control-flow must lower let initializer to helper call"
  | _ => throw <| IO.userError "planned scalar create control-flow body lowering must lower to switch"
  let memoryArrayEnv : TypeEnv := #[
    { name := "buf", type := .array .u64, isMutable := true },
    { name := "n", type := .u64, isMutable := false }
  ]
  let memoryArrayControl :=
    Statement.ifElse
      (.gt (.local "n") (.literal (.u64 0)))
      #[
        .effect (.memoryArraySet (.local "buf") (.literal (.u64 0)) (.local "n"))
      ]
      #[
        .effect (.memoryArraySet (.local "buf") (.literal (.u64 1)) (.literal (.u64 7)))
      ]
  let plannedMemoryArrayControl? ← requireOk
    (plannedBodyStatement?
      ProofForge.IR.Examples.Counter.module
      "control_flow"
      .unit
      memoryArrayEnv
      memoryArrayControl)
    "planned memory-array set control-flow plan construction"
  let plannedMemoryArrayControl ← requireSome plannedMemoryArrayControl?
    "planned memory-array set control-flow plan construction missing plan"
  let (memoryArrayControlStmts, _) ← requireOk
    (lowerPlannedBodyStatement
      ProofForge.IR.Examples.Counter.module
      "control_flow"
      .unit
      memoryArrayEnv
      false
      plannedMemoryArrayControl)
    "planned memory-array set control-flow body lowering"
  match memoryArrayControlStmts[0]? with
  | some (Lean.Compiler.Yul.Statement.switchStmt _ cases) => do
      let elseCase ← requireAt cases 0 "planned memory-array set control-flow else case"
      let thenCase ← requireAt cases 1 "planned memory-array set control-flow then case"
      require (thenCase.body.statements.size == 2) "planned memory-array set control-flow then statement count"
      require (elseCase.body.statements.size == 2) "planned memory-array set control-flow else statement count"
      match thenCase.body.statements[1]! with
      | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin name args) => do
          require (name == "mstore") "planned memory-array set control-flow then mstore"
          require (args.size == 2) "planned memory-array set control-flow then mstore arg count"
      | _ => throw <| IO.userError "planned memory-array set control-flow then branch must lower direct mstore"
      match elseCase.body.statements[1]! with
      | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin name args) => do
          require (name == "mstore") "planned memory-array set control-flow else mstore"
          require (args.size == 2) "planned memory-array set control-flow else mstore arg count"
      | _ => throw <| IO.userError "planned memory-array set control-flow else branch must lower direct mstore"
  | _ => throw <| IO.userError "planned memory-array set control-flow body lowering must lower to switch"
  let (memoryArrayStatementStmts, _) ← requireOk
    (lowerStatement
      ProofForge.IR.Examples.Counter.module
      "control_flow"
      .unit
      memoryArrayEnv
      false
      memoryArrayControl)
    "memory-array set control-flow statement lowering"
  match memoryArrayStatementStmts[0]? with
  | some (Lean.Compiler.Yul.Statement.switchStmt _ cases) => do
      let thenCase ← requireAt cases 1 "memory-array set control-flow statement then case"
      require (thenCase.body.statements.size == 2)
        "memory-array set control-flow statement must use planned body instead of fallback block wrapper"
      match thenCase.body.statements[1]! with
      | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin name args) => do
          require (name == "mstore") "memory-array set control-flow statement mstore"
          require (args.size == 2) "memory-array set control-flow statement mstore arg count"
      | _ => throw <| IO.userError "memory-array set control-flow statement must lower direct planned mstore"
  | _ => throw <| IO.userError "memory-array set control-flow statement lowering must lower to switch"
  let memoryArrayExprControl :=
    Statement.ifElse
      (.gt (.local "n") (.literal (.u64 0)))
      #[
        .letBind "len" .u64 (.memoryArrayLength (.local "buf")),
        .letBind "fresh_len" .u64
          (.memoryArrayLength (.memoryArrayNew .u64 (.literal (.u64 2))))
      ]
      #[
        .letBind "item" .u64 (.memoryArrayGet (.local "buf") (.literal (.u64 0)))
      ]
  let plannedMemoryArrayExprControl? ← requireOk
    (plannedBodyStatement?
      ProofForge.IR.Examples.Counter.module
      "control_flow"
      .unit
      memoryArrayEnv
      memoryArrayExprControl)
    "planned memory-array expression control-flow plan construction"
  let plannedMemoryArrayExprControl ← requireSome plannedMemoryArrayExprControl?
    "planned memory-array expression control-flow plan construction missing plan"
  let (memoryArrayExprControlStmts, _) ← requireOk
    (lowerPlannedBodyStatement
      ProofForge.IR.Examples.Counter.module
      "control_flow"
      .unit
      memoryArrayEnv
      false
      plannedMemoryArrayExprControl)
    "planned memory-array expression control-flow body lowering"
  match memoryArrayExprControlStmts[0]? with
  | some (Lean.Compiler.Yul.Statement.switchStmt _ cases) => do
      let elseCase ← requireAt cases 0 "planned memory-array expression control-flow else case"
      let thenCase ← requireAt cases 1 "planned memory-array expression control-flow then case"
      require (thenCase.body.statements.size == 2) "planned memory-array expression control-flow then statement count"
      require (elseCase.body.statements.size == 1) "planned memory-array expression control-flow else statement count"
      match thenCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl names (some (Lean.Compiler.Yul.Expr.builtin name args)) => do
          require (names.size == 1) "planned memory-array length control-flow var count"
          let typedName ← requireAt names 0 "planned memory-array length control-flow var"
          require (typedName.name == "len") "planned memory-array length control-flow var name"
          require (name == "mload") "planned memory-array length control-flow mload"
          require (args.size == 1) "planned memory-array length control-flow mload arg count"
      | _ => throw <| IO.userError "planned memory-array length control-flow must lower to mload binding"
      match thenCase.body.statements[1]! with
      | Lean.Compiler.Yul.Statement.varDecl names (some (Lean.Compiler.Yul.Expr.builtin name args)) => do
          require (names.size == 1) "planned memory-array new length control-flow var count"
          let typedName ← requireAt names 0 "planned memory-array new length control-flow var"
          require (typedName.name == "fresh_len") "planned memory-array new length control-flow var name"
          require (name == "mload") "planned memory-array new length control-flow mload"
          require (args.size == 1) "planned memory-array new length control-flow mload arg count"
          requireCallExpr args[0]! (Helper.memoryArrayNew).name 1
            "planned memory-array new length control-flow helper"
      | _ => throw <| IO.userError "planned memory-array new length control-flow must lower to helper-backed mload"
      match elseCase.body.statements[0]! with
      | Lean.Compiler.Yul.Statement.varDecl names (some (Lean.Compiler.Yul.Expr.call name args)) => do
          require (names.size == 1) "planned memory-array get control-flow var count"
          let typedName ← requireAt names 0 "planned memory-array get control-flow var"
          require (typedName.name == "item") "planned memory-array get control-flow var name"
          require (name == (Helper.memoryArrayGet).name) "planned memory-array get control-flow helper"
          require (args.size == 2) "planned memory-array get control-flow helper arg count"
      | _ => throw <| IO.userError "planned memory-array get control-flow must lower to helper binding"
  | _ => throw <| IO.userError "planned memory-array expression control-flow body lowering must lower to switch"
  let (ifStmts, _) ← requireOk
    (lowerStatement
      ProofForge.IR.Examples.Counter.module
      "control_flow"
      .unit
      env
      false
      (.ifElse
        (.gt (.local "n") (.literal (.u64 0)))
        #[.assign (.local "n") (.add (.local "n") (.literal (.u64 1)))]
        #[.assign (.local "n") (.literal (.u64 1))]))
    "scalar ifElse condition plan-to-yul"
  require (ifStmts.size == 1) "scalar ifElse condition plan-to-yul statement count"
  match ifStmts[0]! with
  | Lean.Compiler.Yul.Statement.switchStmt (Lean.Compiler.Yul.Expr.builtin name args) _ => do
      require (name == "gt") "scalar ifElse condition plan-to-yul opcode"
      require (args.size == 2) "scalar ifElse condition plan-to-yul arg count"
  | _ => throw <| IO.userError "scalar ifElse condition plan-to-yul must lower to switch over builtin"
  let (forStmts, _) ← requireOk
    (lowerStatement
      ProofForge.IR.Examples.Counter.module
      "control_flow"
      .unit
      env
      false
      (.boundedFor
        "i"
        0
        3
        #[.assign (.local "n") (.add (.local "n") (.local "i"))]))
    "scalar boundedFor condition plan-to-yul"
  require (forStmts.size == 1) "scalar boundedFor condition plan-to-yul statement count"
  match forStmts[0]! with
  | Lean.Compiler.Yul.Statement.forLoop _ (Lean.Compiler.Yul.Expr.builtin name args) _ _ => do
      require (name == "lt") "scalar boundedFor condition plan-to-yul opcode"
      require (args.size == 2) "scalar boundedFor condition plan-to-yul arg count"
  | _ => throw <| IO.userError "scalar boundedFor condition plan-to-yul must lower to for over builtin"

def testScalarEventPlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "n", type := .u64, isMutable := false }]
  let directEvent := ProofForge.Backend.Evm.Plan.EventPlan.mk
    "PlanIndexed"
    "PlanIndexed(uint64,uint64)"
    #[
      ProofForge.Backend.Evm.Plan.EventFieldPlan.mk "key" .u64 true,
      ProofForge.Backend.Evm.Plan.EventFieldPlan.mk "value" .u64 false
    ]
  let directStmt ← requireOk
    (ProofForge.Backend.Evm.ToYul.eventEmitCoreStatement
      toYulError
      directEvent
      #[Lean.Compiler.Yul.Statement.varDecl
        #[{ name := "_indexed_topic0" }]
        (some (Lean.Compiler.Yul.Expr.num 5))]
      #[Lean.Compiler.Yul.Expr.num 9])
    "event EventPlan-to-Yul core helper"
  match directStmt with
  | Lean.Compiler.Yul.Statement.block block => do
      require (block.statements.size >= 4) "event EventPlan-to-Yul core helper statement count"
      match block.statements[block.statements.size - 1]! with
      | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin name args) => do
          require (name == "log2") "event EventPlan-to-Yul core helper log builtin"
          require (args.size == 4) "event EventPlan-to-Yul core helper log arg count"
      | _ => throw <| IO.userError "event EventPlan-to-Yul core helper must end with log statement"
  | _ => throw <| IO.userError "event EventPlan-to-Yul core helper must lower to block"
  let simplePlanExpr : ExprPlan → Except LowerError Lean.Compiler.Yul.Expr := fun plan =>
    match plan with
    | .literalWord value => .ok (Lean.Compiler.Yul.Expr.num value)
    | .local name => .ok (Lean.Compiler.Yul.Expr.id name)
    | _ => .error (toYulError "unexpected event plan test expression")
  let noStructFields (_ : String) : Except LowerError (Array (String × ValueType)) :=
    .error (toYulError "unexpected event plan test struct fields")
  let noStorageWords (_context _typeName _stateId : String) : Except LowerError (Array Lean.Compiler.Yul.Expr) :=
    .error (toYulError "unexpected event plan test storage words")
  let noStorageArrayWords
      (_context _stateId : String)
      (_elementType : ValueType)
      (_length : Nat) : Except LowerError (Array Lean.Compiler.Yul.Expr) :=
    .error (toYulError "unexpected event plan test storage array words")
  let directDataWords ← requireOk
    (ProofForge.Backend.Evm.ToYul.eventFieldsDataWordsFromPlan
      toYulError
      simplePlanExpr
      noStructFields
      noStorageWords
      noStorageArrayWords
      directEvent.name
      directEvent.dataFields
      #[AbiValuePlan.expr (.literalWord 11)])
    "event field plan-to-yul data words"
  require (directDataWords.size == 1) "event field plan-to-yul data word count"
  match directDataWords[0]! with
  | Lean.Compiler.Yul.Expr.lit literal =>
      require (literal.value == "11") "event field plan-to-yul data word value"
  | _ => throw <| IO.userError "event field plan-to-yul data word must be numeric"
  let directIndexedTopics ← requireOk
    (ProofForge.Backend.Evm.ToYul.eventIndexedTopicStatementsFromPlans
      toYulError
      simplePlanExpr
      noStructFields
      noStorageWords
      noStorageArrayWords
      directEvent
      #[AbiValuePlan.expr (.literalWord 7)])
    "event indexed field plan-to-yul topic statements"
  require (directIndexedTopics.size == 1) "event indexed field plan-to-yul topic statement count"
  match directIndexedTopics[0]! with
  | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.lit literal)) => do
      require (literal.value == "7") "event indexed field plan-to-yul topic value"
      match vars[0]? with
      | some var => require (vars.size == 1 && var.name == "_indexed_topic0") "event indexed field plan-to-yul topic var"
      | none => throw <| IO.userError "event indexed field plan-to-yul topic missing var"
  | _ => throw <| IO.userError "event indexed field plan-to-yul topic must be var decl"
  let directWordEffect ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.eventEffectWordPlan
      ProofForge.IR.Examples.EventProbe.evmModule
      (toValidateTypeEnv env)
      (.eventEmitIndexed
        directEvent
        #[AbiValuePlan.expr (.literalWord 7)]
        #[AbiValuePlan.expr (.literalWord 13)]))
    "event effect Lower word plan"
  match directWordEffect with
  | .eventEmitIndexedWords _ indexedWordPlans dataWordPlans => do
      require (indexedWordPlans.size == 1) "event effect Lower indexed word field count"
      require (dataWordPlans.size == 1) "event effect Lower data word field count"
      match indexedWordPlans[0]? with
      | some words =>
          require (words.size == 1) "event effect Lower indexed word count"
          match words[0]? with
          | some (ExprPlan.literalWord 7) => pure ()
          | _ => throw <| IO.userError "event effect Lower indexed word must be literal 7"
      | none => throw <| IO.userError "event effect Lower missing indexed words"
      match dataWordPlans[0]? with
      | some words =>
          require (words.size == 1) "event effect Lower data word count"
          match words[0]? with
          | some (ExprPlan.literalWord 13) => pure ()
          | _ => throw <| IO.userError "event effect Lower data word must be literal 13"
      | none => throw <| IO.userError "event effect Lower missing data words"
  | _ => throw <| IO.userError "event effect Lower must emit eventEmitIndexedWords"
  let directEventEffectStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.eventEffectStmtPlanStatements
      toYulError
      simplePlanExpr
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect
        (.eventEmitIndexedWords
          directEvent
          #[#[.literalWord 7]]
          #[#[.literalWord 13]])))
    "event effect StmtPlan-to-Yul helper"
  require (directEventEffectStmts.size == 1) "event effect StmtPlan-to-Yul helper statement count"
  match directEventEffectStmts[0]! with
  | Lean.Compiler.Yul.Statement.block block => do
      require (block.statements.size >= 4) "event effect StmtPlan-to-Yul helper block statement count"
      let mut foundIndexedTopic := false
      let mut foundDataWord := false
      for stmt in block.statements do
        match stmt with
        | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.lit literal)) => do
            match vars[0]? with
            | some var =>
                if vars.size == 1 && var.name == "_indexed_topic0" && literal.value == "7" then
                  foundIndexedTopic := true
            | none => pure ()
        | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "mstore" args) => do
            match args[1]? with
            | some (Lean.Compiler.Yul.Expr.lit literal) =>
                if literal.value == "13" then
                  foundDataWord := true
            | _ => pure ()
        | _ => pure ()
      require foundIndexedTopic "event effect StmtPlan-to-Yul helper indexed provider word"
      require foundDataWord "event effect StmtPlan-to-Yul helper data provider word"
      match block.statements[block.statements.size - 1]! with
      | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin name args) => do
          require (name == "log2") "event effect StmtPlan-to-Yul helper log builtin"
          require (args.size == 4) "event effect StmtPlan-to-Yul helper log arg count"
      | _ => throw <| IO.userError "event effect StmtPlan-to-Yul helper must end with log"
  | _ => throw <| IO.userError "event effect StmtPlan-to-Yul helper must lower to block"
  let plannedDataEffect ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.EventProbe.evmModule
      (toValidateTypeEnv env)
      (ProofForge.IR.Effect.eventEmit
        "PlanValue"
        #[("value", .add (.local "n") (.literal (.u64 1)))]))
    "event data statement Lower.buildEffectPlan"
  match plannedDataEffect with
  | .eventEmitWords event dataFieldWords => do
      require (event.name == "PlanValue") "event data statement Lower event name"
      require (dataFieldWords.size == 1) "event data statement Lower field count"
      let words ← requireAt dataFieldWords 0 "event data statement Lower missing words"
      require (words.size == 1) "event data statement Lower word count"
      match words[0]? with
      | some (ExprPlan.checkedArith .add (ExprPlan.local "n") (ExprPlan.literalWord 1)) => pure ()
      | _ => throw <| IO.userError "event data statement Lower word must be planned checked add"
  | _ => throw <| IO.userError "event data statement Lower must produce eventEmitWords"
  let plannedIndexedEffect ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.EventProbe.evmModule
      (toValidateTypeEnv env)
      (ProofForge.IR.Effect.eventEmitIndexed
        "PlanIndexed"
        #[("key", .effect (.storageScalarRead "_proof_forge_marker"))]
        #[("value", .add (.local "n") (.literal (.u64 1)))]))
    "indexed event statement Lower.buildEffectPlan"
  match plannedIndexedEffect with
  | .eventEmitIndexedWords event indexedFieldWords dataFieldWords => do
      require (event.name == "PlanIndexed") "indexed event statement Lower event name"
      require (indexedFieldWords.size == 1) "indexed event statement Lower indexed field count"
      require (dataFieldWords.size == 1) "indexed event statement Lower data field count"
      let indexedWords ← requireAt indexedFieldWords 0 "indexed event statement Lower missing indexed words"
      let dataWords ← requireAt dataFieldWords 0 "indexed event statement Lower missing data words"
      require (indexedWords.size == 1) "indexed event statement Lower indexed word count"
      require (dataWords.size == 1) "indexed event statement Lower data word count"
  | _ => throw <| IO.userError "indexed event statement Lower must produce eventEmitIndexedWords"
  let dataStmt ← requireOk
    (lowerEventEmitCoreStmt
      ProofForge.IR.Examples.EventProbe.evmModule
      env
      "PlanValue"
      #[]
      #[("value", .add (.local "n") (.literal (.u64 1)))])
    "scalar event data field plan-to-yul"
  match dataStmt with
  | Lean.Compiler.Yul.Statement.block block => do
      let mut foundCheckedAdd := false
      for stmt in block.statements do
        match stmt with
        | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "mstore" args) => do
            if args.size == 2 then
              match args[1]! with
              | Lean.Compiler.Yul.Expr.call "__pf_checked_add" addArgs =>
                  foundCheckedAdd := foundCheckedAdd || addArgs.size == 2
              | _ => pure ()
        | _ => pure ()
      require foundCheckedAdd "scalar event data field must lower through checked add plan"
  | _ => throw <| IO.userError "scalar event data field plan-to-yul must lower to block"
  let indexedStmt ← requireOk
    (lowerEventEmitCoreStmt
      ProofForge.IR.Examples.EventProbe.evmModule
      env
      "PlanIndexed"
      #[("key", .effect (.storageScalarRead "_proof_forge_marker"))]
      #[("value", .add (.local "n") (.literal (.u64 1)))])
    "scalar indexed event topic plan-to-yul"
  match indexedStmt with
  | Lean.Compiler.Yul.Statement.block block => do
      let mut foundIndexedSload := false
      for stmt in block.statements do
        match stmt with
        | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.builtin andName _)) => do
            -- Packed read: varDecl _indexed_topic0 = and(shr(..., sload(...)), mask)
            match vars[0]? with
            | some var =>
                if vars.size == 1 && var.name == "_indexed_topic0" then
                  require (andName == "and") "scalar indexed event topic must lower to packed read (and)"
                  foundIndexedSload := true
            | none => pure ()
        | _ => pure ()
      require foundIndexedSload "scalar indexed event topic must lower storage read through plan"
  | _ => throw <| IO.userError "scalar indexed event topic plan-to-yul must lower to block"

def plannedLocalAggregateEventDataWords
    (module : ProofForge.IR.Module)
    (env : TypeEnv)
    (eventName : String)
    (fields : Array (String × ProofForge.IR.Expr))
    (label : String) : IO (Array Lean.Compiler.Yul.Expr) := do
  let plan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      module
      (toValidateTypeEnv env)
      (.eventEmit eventName fields))
    s!"{label} Lower EffectPlan"
  let (event, dataFieldWords) ←
    match plan with
    | .eventEmitWords event dataFieldWords => pure (event, dataFieldWords)
    | _ => throw <| IO.userError s!"{label} must lower to eventEmitWords plan"
  require (event.name == eventName) s!"{label} event name"
  require (dataFieldWords.size == fields.size) s!"{label} per-field word plan count"
  let mut wordPlans : Array ExprPlan := #[]
  for h : idx in [0:dataFieldWords.size] do
    wordPlans := wordPlans ++ dataFieldWords[idx]
  let mut words : Array Lean.Compiler.Yul.Expr := #[]
  for h : idx in [0:wordPlans.size] do
    words := words.push
      (← requireOk
        (lowerExprPlanExpr module env wordPlans[idx])
        s!"{label} word plan {idx} to-yul")
  pure words

def testLocalAggregateEventDataWordsPlanToYul : IO Unit := do
  let module := ProofForge.IR.Examples.EventProbe.evmModule
  let pairEnv : TypeEnv := #[
    { name := "pair", type := .structType "Pair", isMutable := false }
  ]
  let pairWords ← plannedLocalAggregateEventDataWords
    module
    pairEnv
    "PairEvent"
    #[("pair", .local "pair")]
    "local struct event data words"
  require (pairWords.size == 2) "local struct event data word count"
  requireIdentExpr (← requireAt pairWords 0 "local struct event missing first word")
    "__proof_forge_struct_pair_left"
    "local struct event first word"
  requireIdentExpr (← requireAt pairWords 1 "local struct event missing second word")
    "__proof_forge_struct_pair_right"
    "local struct event second word"
  let arrayEnv : TypeEnv := #[
    { name := "values", type := .fixedArray .u64 2, isMutable := false }
  ]
  let arrayWords ← plannedLocalAggregateEventDataWords
    module
    arrayEnv
    "ArrayEvent"
    #[("values", .local "values")]
    "local fixed-array event data words"
  require (arrayWords.size == 2) "local fixed-array event data word count"
  requireIdentExpr (← requireAt arrayWords 0 "local fixed-array event missing first word")
    "__proof_forge_array_values_0"
    "local fixed-array event first word"
  requireIdentExpr (← requireAt arrayWords 1 "local fixed-array event missing second word")
    "__proof_forge_array_values_1"
    "local fixed-array event second word"
  let pairArrayEnv : TypeEnv := #[
    { name := "pairs", type := .fixedArray (.structType "Pair") 2, isMutable := false }
  ]
  let pairArrayWords ← plannedLocalAggregateEventDataWords
    module
    pairArrayEnv
    "PairArrayEvent"
    #[("pairs", .local "pairs")]
    "local struct-array event data words"
  require (pairArrayWords.size == 4) "local struct-array event data word count"
  requireIdentExpr (← requireAt pairArrayWords 0 "local struct-array event missing word 0")
    "__proof_forge_array_struct_pairs_0_left"
    "local struct-array event word 0"
  requireIdentExpr (← requireAt pairArrayWords 1 "local struct-array event missing word 1")
    "__proof_forge_array_struct_pairs_0_right"
    "local struct-array event word 1"
  requireIdentExpr (← requireAt pairArrayWords 2 "local struct-array event missing word 2")
    "__proof_forge_array_struct_pairs_1_left"
    "local struct-array event word 2"
  requireIdentExpr (← requireAt pairArrayWords 3 "local struct-array event missing word 3")
    "__proof_forge_array_struct_pairs_1_right"
    "local struct-array event word 3"

def lowerWordPlansToYul
    (module : ProofForge.IR.Module)
    (env : TypeEnv)
    (wordPlans : Array ExprPlan)
    (label : String) : IO (Array Lean.Compiler.Yul.Expr) := do
  let mut words : Array Lean.Compiler.Yul.Expr := #[]
  for h : idx in [0:wordPlans.size] do
    words := words.push
      (← requireOk
        (lowerExprPlanExpr module env wordPlans[idx])
        s!"{label} word plan {idx} to-yul")
  pure words

def testStorageAggregateEventDataWordsPlanToYul : IO Unit := do
  let module := ProofForge.IR.Examples.EventProbe.evmModule
  let plan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      module
      (toValidateTypeEnv #[])
      (.eventEmit "StoragePairEvent" #[("pair", .effect (.storageScalarRead "storedPair"))]))
    "storage aggregate event Lower EffectPlan"
  let (event, dataFieldWords) ←
    match plan with
    | .eventEmitWords event dataFieldWords => pure (event, dataFieldWords)
    | _ => throw <| IO.userError "storage aggregate event must lower to eventEmitWords plan"
  require (event.name == "StoragePairEvent") "storage aggregate event plan name"
  require (event.dataFields.size == 1) "storage aggregate event data field count"
  require (dataFieldWords.size == 1) "storage aggregate event per-field data word count"
  let wordPlans ← requireAt dataFieldWords 0 "storage aggregate event missing data word field"
  require (wordPlans.size == 2) "storage aggregate event data word plan count"
  for h : idx in [0:wordPlans.size] do
    match wordPlans[idx] with
    | .storageLoad (.scalarSlot _) => pure ()
    | _ => throw <| IO.userError s!"storage aggregate event word plan {idx} must be storageLoad"
  let words ← lowerWordPlansToYul module #[] wordPlans "storage aggregate event"
  require (words.size == 2) "storage aggregate event data word count"
  for h : idx in [0:words.size] do
    match words[idx] with
    | Lean.Compiler.Yul.Expr.builtin name args => do
        require (name == "sload") s!"storage aggregate event word {idx} must be sload"
        require (args.size == 1) s!"storage aggregate event word {idx} sload arg count"
    | _ => throw <| IO.userError s!"storage aggregate event word {idx} must lower to sload"
  let facadeStmt ← requireOk
    (lowerEventEmitStmt
      module
      #[]
      "StoragePairEvent"
      #[("pair", .effect (.storageScalarRead "storedPair"))])
    "storage aggregate event facade data words plan-to-yul"
  match facadeStmt with
  | Lean.Compiler.Yul.Statement.block block => do
      let mut sloadDataWordCount := 0
      for stmt in block.statements do
        match stmt with
        | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "mstore" args) => do
            match args[1]? with
            | some (Lean.Compiler.Yul.Expr.builtin "sload" sloadArgs) =>
                if sloadArgs.size == 1 then
                  sloadDataWordCount := sloadDataWordCount + 1
            | _ => pure ()
        | _ => pure ()
      require (sloadDataWordCount == 2)
        "storage aggregate event facade must store two sload-backed data words"
  | _ =>
      throw <| IO.userError "storage aggregate event facade must lower to event emit block"
  let arrayPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      module
      (toValidateTypeEnv #[])
      (.eventEmit "StorageArrayEvent" #[("values", ProofForge.IR.Examples.EventProbe.storedValues)]))
    "storage array aggregate event Lower EffectPlan"
  let (arrayEvent, arrayDataFieldWords) ←
    match arrayPlan with
    | .eventEmitWords event dataFieldWords => pure (event, dataFieldWords)
    | _ => throw <| IO.userError "storage array aggregate event must lower to eventEmitWords plan"
  require (arrayEvent.name == "StorageArrayEvent") "storage array aggregate event plan name"
  require (arrayDataFieldWords.size == 1) "storage array aggregate event per-field data word count"
  let arrayWordPlans ← requireAt arrayDataFieldWords 0
    "storage array aggregate event missing data word field"
  require (arrayWordPlans.size == 2) "storage array aggregate event data word plan count"
  for h : idx in [0:arrayWordPlans.size] do
    match arrayWordPlans[idx] with
    | .storageLoad (.arraySlot ..) => pure ()
    | _ => throw <| IO.userError s!"storage array aggregate event word plan {idx} must be array storageLoad"
  let arrayWords ← lowerWordPlansToYul module #[] arrayWordPlans "storage array aggregate event"
  require (arrayWords.size == 2) "storage array aggregate event data word count"
  for h : idx in [0:arrayWords.size] do
    match arrayWords[idx] with
    | Lean.Compiler.Yul.Expr.builtin "sload" args => do
        require (args.size == 1) s!"storage array aggregate event word {idx} sload arg count"
        match args[0]! with
        | Lean.Compiler.Yul.Expr.call name _ =>
            require (name == "__proof_forge_array_slot") s!"storage array aggregate event word {idx} slot helper"
        | _ => throw <| IO.userError s!"storage array aggregate event word {idx} must call array slot helper"
    | _ => throw <| IO.userError s!"storage array aggregate event word {idx} must lower to sload"
  let structArrayPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      module
      (toValidateTypeEnv #[])
      (.eventEmit "StoragePairArrayEvent" #[("pairs", ProofForge.IR.Examples.EventProbe.storedPairs)]))
    "storage struct-array aggregate event Lower EffectPlan"
  let (structArrayEvent, structArrayDataFieldWords) ←
    match structArrayPlan with
    | .eventEmitWords event dataFieldWords => pure (event, dataFieldWords)
    | _ => throw <| IO.userError "storage struct-array aggregate event must lower to eventEmitWords plan"
  require (structArrayEvent.name == "StoragePairArrayEvent") "storage struct-array aggregate event plan name"
  require (structArrayDataFieldWords.size == 1) "storage struct-array aggregate event per-field data word count"
  let structArrayWordPlans ← requireAt structArrayDataFieldWords 0
    "storage struct-array aggregate event missing data word field"
  require (structArrayWordPlans.size == 4) "storage struct-array aggregate event data word plan count"
  for h : idx in [0:structArrayWordPlans.size] do
    match structArrayWordPlans[idx] with
    | .storageLoad (.structArrayFieldSlot ..) => pure ()
    | _ => throw <| IO.userError s!"storage struct-array aggregate event word plan {idx} must be struct-array storageLoad"
  let structArrayWords ← lowerWordPlansToYul module #[] structArrayWordPlans "storage struct-array aggregate event"
  require (structArrayWords.size == 4) "storage struct-array aggregate event data word count"
  for h : idx in [0:structArrayWords.size] do
    match structArrayWords[idx] with
    | Lean.Compiler.Yul.Expr.builtin "sload" args => do
        require (args.size == 1) s!"storage struct-array aggregate event word {idx} sload arg count"
        match args[0]! with
        | Lean.Compiler.Yul.Expr.call name _ =>
            require (name == "__proof_forge_struct_array_slot") s!"storage struct-array aggregate event word {idx} slot helper"
        | _ => throw <| IO.userError s!"storage struct-array aggregate event word {idx} must call struct-array slot helper"
    | _ => throw <| IO.userError s!"storage struct-array aggregate event word {idx} must lower to sload"

def testStorageAggregateIndexedEventTopicPlanToYul : IO Unit := do
  let module := ProofForge.IR.Examples.EventProbe.evmModule
  let plan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      module
      (toValidateTypeEnv #[{ name := "value", type := .u64, isMutable := false }])
      (.eventEmitIndexed
        "IndexedStoragePair"
        #[("pair", .effect (.storageScalarRead "storedPair"))]
        #[("value", .local "value")]))
    "storage aggregate indexed event Lower EffectPlan"
  let (event, indexedFieldWords) ←
    match plan with
    | .eventEmitIndexedWords event indexedFieldWords _ => pure (event, indexedFieldWords)
    | _ => throw <| IO.userError "storage aggregate indexed event must lower to eventEmitIndexedWords plan"
  require (event.name == "IndexedStoragePair") "storage aggregate indexed event plan name"
  require (event.indexedFields.size == 1) "storage aggregate indexed event indexed field count"
  require (indexedFieldWords.size == 1) "storage aggregate indexed event per-field indexed word count"
  let indexedFieldPlan ← requireAt event.indexedFields 0 "storage aggregate indexed event missing field plan"
  let indexedWordPlans ← requireAt indexedFieldWords 0
    "storage aggregate indexed event missing indexed word field"
  require (indexedWordPlans.size == 2) "storage aggregate indexed event word plan count"
  for h : idx in [0:indexedWordPlans.size] do
    match indexedWordPlans[idx] with
    | .storageLoad (.scalarSlot _) => pure ()
    | _ => throw <| IO.userError s!"storage aggregate indexed event word plan {idx} must be storageLoad"
  let indexedWords ← lowerWordPlansToYul
    module
    #[{ name := "value", type := .u64, isMutable := false }]
    indexedWordPlans
    "storage aggregate indexed event"
  let plannedTopicStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.eventIndexedTopicStatements
      toYulError
      indexedFieldPlan
      0
      indexedWords)
    "storage aggregate indexed event topic plan-to-yul"
  require (plannedTopicStmts.size == 3) "storage aggregate indexed event topic statement count"
  match plannedTopicStmts[2]! with
  | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.builtin "keccak256" args)) => do
      match vars[0]? with
      | some var => require (var.name == "_indexed_topic0") "storage aggregate indexed event topic var"
      | none => throw <| IO.userError "storage aggregate indexed event topic missing var"
      require (args.size == 2) "storage aggregate indexed event topic keccak arg count"
  | _ => throw <| IO.userError "storage aggregate indexed event topic must hash planned words"
  let facadeEventStmt ← requireOk
    (lowerEventEmitCoreStmt
      module
      #[{ name := "value", type := .u64, isMutable := false }]
      "IndexedStoragePair"
      #[("pair", .effect (.storageScalarRead "storedPair"))]
      #[("value", .local "value")])
    "storage aggregate indexed event facade event plan-to-yul"
  match facadeEventStmt with
  | Lean.Compiler.Yul.Statement.block block => do
      let mut foundIndexedTopicHash := false
      for stmt in block.statements do
        match stmt with
        | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.builtin "keccak256" args)) => do
            match vars[0]? with
            | some var =>
                if vars.size == 1 && var.name == "_indexed_topic0" && args.size == 2 then
                  foundIndexedTopicHash := true
            | none => pure ()
        | _ => pure ()
      require foundIndexedTopicHash
        "storage aggregate indexed event facade event must hash planned indexed words"
  | _ =>
      throw <| IO.userError "storage aggregate indexed event facade event must lower to block"

def testScalarStorageEffectPlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "n", type := .u64, isMutable := false }]
  let directWriteStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.scalarStorageEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.Counter.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.Counter.module env)
      (fun _ => .ok (Lean.Compiler.Yul.Expr.num 0))
      (fun _ => .ok (0, 8))
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect
        (.storageScalarWrite
          "count"
          (.checkedArith .add (.local "n") (.literalWord 1)))))
    "scalar storage write StmtPlan-to-Yul helper"
  require (directWriteStmts.size == 1) "scalar storage write StmtPlan-to-Yul helper statement count"
  match directWriteStmts[0]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "scalar storage write StmtPlan-to-Yul helper arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.builtin orName orArgs => do
          require (orName == "or") "scalar storage write StmtPlan-to-Yul helper packed write (or)"
          require (orArgs.size == 2) "scalar storage write StmtPlan-to-Yul helper or arg count"
          match orArgs[1]! with
          | Lean.Compiler.Yul.Expr.builtin shlName shlArgs => do
              require (shlName == "shl") "scalar storage write StmtPlan-to-Yul helper packed shift (shl)"
              match shlArgs[1]! with
              | Lean.Compiler.Yul.Expr.call name addArgs => do
                  require (name == "__pf_checked_add") "scalar storage write StmtPlan-to-Yul helper checked add"
                  require (addArgs.size == 2) "scalar storage write StmtPlan-to-Yul helper checked add arg count"
              | _ => throw <| IO.userError "scalar storage write StmtPlan-to-Yul helper packed value must be helper call"
          | _ => throw <| IO.userError "scalar storage write StmtPlan-to-Yul helper must have shl in packed write"
      | _ => throw <| IO.userError "scalar storage write StmtPlan-to-Yul helper value must be packed write (or/and/shl)"
  | _ => throw <| IO.userError "scalar storage write StmtPlan-to-Yul helper must lower to sstore"
  let directAssignOpStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.scalarStorageEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.Counter.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.Counter.module env)
      (fun _ => .ok (Lean.Compiler.Yul.Expr.num 0))
      (fun _ => .ok (0, 8))
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect
        (.storageScalarAssignOp
          "count"
          .add
          (.effect (.storageScalarRead "count")))))
    "scalar storage assign_op StmtPlan-to-Yul helper"
  require (directAssignOpStmts.size == 1) "scalar storage assign_op StmtPlan-to-Yul helper statement count"
  match directAssignOpStmts[0]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "scalar storage assign_op StmtPlan-to-Yul helper arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.builtin orName orArgs => do
          require (orName == "or") "scalar storage assign_op StmtPlan-to-Yul helper packed write (or)"
          require (orArgs.size == 2) "scalar storage assign_op StmtPlan-to-Yul helper or arg count"
          match orArgs[1]! with
          | Lean.Compiler.Yul.Expr.builtin shlName shlArgs => do
              require (shlName == "shl") "scalar storage assign_op StmtPlan-to-Yul helper packed shift (shl)"
              match shlArgs[1]! with
              | Lean.Compiler.Yul.Expr.call name addArgs => do
                  require (name == "__pf_checked_add") "scalar storage assign_op StmtPlan-to-Yul helper checked add"
                  require (addArgs.size == 2) "scalar storage assign_op StmtPlan-to-Yul helper checked add arg count"
                  match addArgs[0]! with
                  | Lean.Compiler.Yul.Expr.builtin readName _ =>
                      require (readName == "and") "scalar storage assign_op StmtPlan-to-Yul helper packed read (and)"
                  | _ => throw <| IO.userError "scalar storage assign_op StmtPlan-to-Yul helper checked add lhs must be packed read"
              | _ => throw <| IO.userError "scalar storage assign_op StmtPlan-to-Yul helper packed value must be helper call"
          | _ => throw <| IO.userError "scalar storage assign_op StmtPlan-to-Yul helper must have shl in packed write"
      | _ => throw <| IO.userError "scalar storage assign_op StmtPlan-to-Yul helper value must be packed write (or/and/shl)"
  | _ => throw <| IO.userError "scalar storage assign_op StmtPlan-to-Yul helper must lower to sstore"
  let loweredScalarWriteEffect ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv env)
      (.storageScalarWrite "count" (.add (.local "n") (.literal (.u64 1)))))
    "Lower scalar storage write target effect plan"
  match loweredScalarWriteEffect with
  | .storageScalarWriteTarget target (.checkedArith .add (.local name) (.literalWord value)) => do
      requireScalarStorageTarget target 0 0 8 "Lower scalar storage write target"
      require (name == "n") "Lower scalar storage write target value lhs"
      require (value == 1) "Lower scalar storage write target value rhs"
  | _ => throw <| IO.userError "Lower scalar storage write must produce storageScalarWriteTarget"
  let loweredScalarReadEffect ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv env)
      (.storageScalarRead "count"))
    "Lower scalar storage read target effect plan"
  match loweredScalarReadEffect with
  | .storageScalarReadTarget target =>
      requireScalarStorageTarget target 0 0 8 "Lower scalar storage read target"
  | _ => throw <| IO.userError "Lower scalar storage read must produce storageScalarReadTarget"
  let loweredScalarAssignOpEffect ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv env)
      (.storageScalarAssignOp "count" .add (.effect (.storageScalarRead "count"))))
    "Lower scalar storage assign_op target effect plan"
  match loweredScalarAssignOpEffect with
  | .storageScalarAssignOpTarget target op (.effect (.storageScalarReadTarget valueTarget)) => do
      requireScalarStorageTarget target 0 0 8 "Lower scalar storage assign_op target"
      require (op == .add) "Lower scalar storage assign_op target op"
      requireScalarStorageTarget valueTarget 0 0 8 "Lower scalar storage assign_op value target"
  | _ => throw <| IO.userError "Lower scalar storage assign_op must produce storageScalarAssignOpTarget"
  let loweredFixedSlotWriteEffect ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      eip1967PackingProbe
      (toValidateTypeEnv #[{ name := "impl", type := .address, isMutable := false }])
      (.storageScalarWrite "$eip1967.implementation" (.local "impl")))
    "Lower fixed-slot scalar storage write target effect plan"
  match loweredFixedSlotWriteEffect with
  | .storageScalarWriteTarget target (.local valueName) => do
      match target.slot with
      | .fixedSlot slotHex =>
          require
            (slotHex == "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc")
            "Lower fixed-slot scalar storage write target slot"
      | _ => throw <| IO.userError "Lower fixed-slot scalar storage write must use fixed slot target"
      require (target.byteOffset == 0) "Lower fixed-slot scalar storage write byte offset"
      require (target.byteWidth == 32) "Lower fixed-slot scalar storage write byte width"
      require (valueName == "impl") "Lower fixed-slot scalar storage write value"
  | _ => throw <| IO.userError "Lower fixed-slot scalar storage write must produce storageScalarWriteTarget"
  let directPlannedReadExpr ← requireOk
    (ProofForge.Backend.Evm.ToYul.scalarStorageTargetReadExpr
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.Counter.module env expr)
      { slot := .scalarSlot 0, byteOffset := 0, byteWidth := 8 })
    "planned scalar storage read target expr-to-Yul helper"
  match directPlannedReadExpr with
  | Lean.Compiler.Yul.Expr.builtin "and" args =>
      require (args.size == 2) "planned scalar storage read target helper packed arg count"
  | _ => throw <| IO.userError "planned scalar storage read target helper must lower to packed read"
  let legacyPlanReadExpr ← requireOk
    (lowerPlanEffectExpr
      ProofForge.IR.Examples.Counter.module
      env
      (.storageScalarRead "count"))
    "legacy scalar storage read EffectPlan target facade"
  match legacyPlanReadExpr with
  | Lean.Compiler.Yul.Expr.builtin "and" args =>
      require (args.size == 2) "legacy scalar storage read EffectPlan target facade packed arg count"
  | _ => throw <| IO.userError "legacy scalar storage read EffectPlan must lower through target facade"
  let directReadEffectExpr ← requireOk
    (lowerEffectExpr
      ProofForge.IR.Examples.Counter.module
      env
      (.storageScalarRead "count"))
    "scalar storage read effect Lower-to-Yul"
  match directReadEffectExpr with
  | Lean.Compiler.Yul.Expr.builtin "and" args =>
      require (args.size == 2) "scalar storage read effect must use packed target read"
  | _ => throw <| IO.userError "scalar storage read effect must lower through packed target plan"
  let directPlannedWriteStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.scalarStorageTargetEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.Counter.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.Counter.module env)
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect
        (.storageScalarWriteTarget
          { slot := .scalarSlot 0, byteOffset := 0, byteWidth := 8 }
          (.checkedArith .add (.local "n") (.literalWord 1)))))
    "planned scalar storage write target StmtPlan-to-Yul helper"
  require (directPlannedWriteStmts.size == 1) "planned scalar storage write target helper statement count"
  match directPlannedWriteStmts[0]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "planned scalar storage write target helper arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.builtin orName orArgs => do
          require (orName == "or") "planned scalar storage write target helper packed write"
          require (orArgs.size == 2) "planned scalar storage write target helper or arg count"
      | _ => throw <| IO.userError "planned scalar storage write target helper value must be packed write"
  | _ => throw <| IO.userError "planned scalar storage write target helper must lower to sstore"
  let directPlannedAssignOpStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.scalarStorageTargetEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.Counter.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.Counter.module env)
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect
        (.storageScalarAssignOpTarget
          { slot := .scalarSlot 0, byteOffset := 0, byteWidth := 8 }
          .add
          (.effect (.storageScalarRead "count")))))
    "planned scalar storage assign_op target StmtPlan-to-Yul helper"
  require (directPlannedAssignOpStmts.size == 1) "planned scalar storage assign_op target helper statement count"
  match directPlannedAssignOpStmts[0]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "planned scalar storage assign_op target helper arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.builtin orName orArgs => do
          require (orName == "or") "planned scalar storage assign_op target helper packed write"
          require (orArgs.size == 2) "planned scalar storage assign_op target helper or arg count"
      | _ => throw <| IO.userError "planned scalar storage assign_op target helper value must be packed write"
  | _ => throw <| IO.userError "planned scalar storage assign_op target helper must lower to sstore"
  let writeStmt ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.Counter.module
      env
      (.storageScalarWrite "count" (.add (.local "n") (.literal (.u64 1)))))
    "scalar storage write value plan-to-yul"
  match writeStmt with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin ssName args) => do
      require (ssName == "sstore") "scalar storage write plan-to-yul must lower to sstore"
      require (args.size == 2) "scalar storage write plan-to-yul arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.builtin orName orArgs => do
          require (orName == "or") "scalar storage write plan-to-yul must be packed or"
          -- Packed write: or(and(sload(slot), not(mask)), shl(shift, value))
          require (orArgs.size == 2) "scalar storage write plan-to-yul packed or arg count"
          match orArgs[1]! with
          | Lean.Compiler.Yul.Expr.builtin shlName shlArgs => do
              require (shlName == "shl") "scalar storage write plan-to-yul must have shl in packed write"
              match shlArgs[1]! with
              | Lean.Compiler.Yul.Expr.call name addArgs => do
                  require (name == "__pf_checked_add") "scalar storage write plan-to-yul helper"
                  require (addArgs.size == 2) "scalar storage write plan-to-yul helper arg count"
              | _ => throw <| IO.userError "scalar storage write plan-to-yul packed value must be helper call"
          | _ => throw <| IO.userError "scalar storage write plan-to-yul must have shl in packed write"
      | _ => throw <| IO.userError "scalar storage write plan-to-yul value must be packed write (or/and/shl)"
  | _ => throw <| IO.userError "scalar storage write plan-to-yul must lower to sstore"
  let eip1967Write ← requireOk
    (lowerEffectStmt
      eip1967PackingProbe
      #[{ name := "impl", type := .address, isMutable := false }]
      (.storageScalarWrite "$eip1967.implementation" (.local "impl")))
    "EIP-1967 fixed slot scalar write plan-to-yul"
  match eip1967Write with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin ssName args) => do
      require (ssName == "sstore") "EIP-1967 fixed slot write must lower to sstore"
      require (args.size == 2) "EIP-1967 fixed slot write arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.lit literal => do
          match literal.kind with
          | Lean.Compiler.Yul.LiteralKind.hexNumber => pure ()
          | _ => throw <| IO.userError "EIP-1967 fixed slot write slot literal kind"
          require (literal.value == "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc") "EIP-1967 fixed slot write slot"
      | _ => throw <| IO.userError "EIP-1967 fixed slot write must use fixed slot literal"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.ident "impl" => pure ()
      | _ => throw <| IO.userError "EIP-1967 fixed slot write must not pack address value"
  | _ => throw <| IO.userError "EIP-1967 fixed slot write must lower to sstore"
  let assignOpStmt ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.Counter.module
      env
      (.storageScalarAssignOp "count" .add (.effect (.storageScalarRead "count"))))
    "scalar storage assign_op value plan-to-yul"
  match assignOpStmt with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin ssName args) => do
      require (ssName == "sstore") "scalar storage assign_op plan-to-yul must lower to sstore"
      require (args.size == 2) "scalar storage assign_op plan-to-yul arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.builtin orName orArgs => do
          require (orName == "or") "scalar storage assign_op plan-to-yul must be packed or"
          -- Packed write: or(and(sload(slot), not(mask)), shl(shift, helper(packedRead, value)))
          require (orArgs.size == 2) "scalar storage assign_op plan-to-yul packed or arg count"
          match orArgs[1]! with
          | Lean.Compiler.Yul.Expr.builtin shlName shlArgs => do
              require (shlName == "shl") "scalar storage assign_op must have shl in packed write"
              match shlArgs[1]! with
              | Lean.Compiler.Yul.Expr.call name addArgs => do
                  require (name == "__pf_checked_add") "scalar storage assign_op plan-to-yul helper"
                  require (addArgs.size == 2) "scalar storage assign_op plan-to-yul helper arg count"
                  -- The first arg to checked_add is the packed read (and/shr/sload)
                  match addArgs[0]! with
                  | Lean.Compiler.Yul.Expr.builtin andName _ => require (andName == "and") "scalar storage assign_op rhs must be packed read (and)"
                  | _ => throw <| IO.userError "scalar storage assign_op rhs must be packed read (and)"
              | _ => throw <| IO.userError "scalar storage assign_op packed value must be helper call"
          | _ => throw <| IO.userError "scalar storage assign_op must have shl in packed write"
      | _ => throw <| IO.userError "scalar storage assign_op plan-to-yul value must be packed write (or/and/shl)"
  | _ => throw <| IO.userError "scalar storage assign_op plan-to-yul must lower to sstore"

def testMapReadPlanToYul : IO Unit := do
  let env : TypeEnv := #[
    { name := "key", type := .u64, isMutable := false },
    { name := "value", type := .u64, isMutable := false }
  ]
  let loweredContainsEffect ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.EvmMapProbe.module
      (toValidateTypeEnv env)
      (.storageMapContains "balances" (.local "key")))
    "Lower map contains target effect plan"
  match loweredContainsEffect with
  | .storageMapContainsTarget target (.local keyName) => do
      requireMapReadTarget target 1 "Lower map contains target"
      require (keyName == "key") "Lower map contains target key"
  | _ => throw <| IO.userError "Lower map contains must produce storageMapContainsTarget"
  let loweredGetEffect ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.EvmMapProbe.module
      (toValidateTypeEnv env)
      (.storageMapGet "balances" (.local "key")))
    "Lower map get target effect plan"
  match loweredGetEffect with
  | .storageMapGetTarget target (.local keyName) => do
      requireMapReadTarget target 1 "Lower map get target"
      require (keyName == "key") "Lower map get target key"
  | _ => throw <| IO.userError "Lower map get must produce storageMapGetTarget"
  let directContainsExpr ← requireOk
    (ProofForge.Backend.Evm.ToYul.mapContainsTargetExpr
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmMapProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmMapProbe.module env)
      { rootSlot := 1 }
      (.checkedArith .add (.local "key") (.literalWord 1)))
    "planned map contains target expr-to-Yul helper"
  match directContainsExpr with
  | Lean.Compiler.Yul.Expr.builtin "iszero" args => do
      require (args.size == 1) "planned map contains target outer iszero arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.builtin "iszero" innerArgs => do
          require (innerArgs.size == 1) "planned map contains target inner iszero arg count"
          match innerArgs[0]! with
          | Lean.Compiler.Yul.Expr.builtin "sload" loadArgs => do
              require (loadArgs.size == 1) "planned map contains target sload arg count"
              match loadArgs[0]! with
              | Lean.Compiler.Yul.Expr.call slotName slotArgs => do
                  require (slotName == (Helper.mapPresenceSlot).name) "planned map contains target presence slot helper"
                  require (slotArgs.size == 2) "planned map contains target presence slot arg count"
                  match slotArgs[0]! with
                  | Lean.Compiler.Yul.Expr.lit literal =>
                      require (literal.value == "1") "planned map contains target root slot"
                  | _ => throw <| IO.userError "planned map contains target root slot must be literal"
                  match slotArgs[1]! with
                  | Lean.Compiler.Yul.Expr.call addName addArgs => do
                      require (addName == "__pf_checked_add") "planned map contains target key checked add"
                      require (addArgs.size == 2) "planned map contains target key checked add arg count"
                  | _ => throw <| IO.userError "planned map contains target key must be checked add"
              | _ => throw <| IO.userError "planned map contains target slot must use presence helper"
          | _ => throw <| IO.userError "planned map contains target inner must load presence"
      | _ => throw <| IO.userError "planned map contains target must use nested iszero"
  | _ => throw <| IO.userError "planned map contains target must lower to iszero"
  let directRawContainsExpr ← requireOk
    (ProofForge.Backend.Evm.ToYul.mapContainsExpr
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmMapProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmMapProbe.module env)
      1
      (.checkedArith .add (.local "key") (.literalWord 3)))
    "raw map contains expr-to-Yul helper"
  match directRawContainsExpr with
  | Lean.Compiler.Yul.Expr.builtin "iszero" args => do
      require (args.size == 1) "raw map contains outer iszero arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.builtin "iszero" innerArgs => do
          require (innerArgs.size == 1) "raw map contains inner iszero arg count"
          match innerArgs[0]! with
          | Lean.Compiler.Yul.Expr.builtin "sload" loadArgs => do
              require (loadArgs.size == 1) "raw map contains sload arg count"
              requireCallExpr loadArgs[0]! (Helper.mapPresenceSlot).name 2
                "raw map contains presence slot"
          | _ => throw <| IO.userError "raw map contains inner must load presence"
      | _ => throw <| IO.userError "raw map contains must use nested iszero"
  | _ => throw <| IO.userError "raw map contains must lower to iszero"
  let directGetExpr ← requireOk
    (ProofForge.Backend.Evm.ToYul.mapGetTargetExpr
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmMapProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmMapProbe.module env)
      { rootSlot := 1 }
      (.checkedArith .add (.local "key") (.literalWord 2)))
    "planned map get target expr-to-Yul helper"
  match directGetExpr with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "planned map get target sload arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call slotName slotArgs => do
          require (slotName == (Helper.mapSlot).name) "planned map get target value slot helper"
          require (slotArgs.size == 2) "planned map get target value slot arg count"
          match slotArgs[0]! with
          | Lean.Compiler.Yul.Expr.lit literal =>
              require (literal.value == "1") "planned map get target root slot"
          | _ => throw <| IO.userError "planned map get target root slot must be literal"
          match slotArgs[1]! with
          | Lean.Compiler.Yul.Expr.call addName addArgs => do
              require (addName == "__pf_checked_add") "planned map get target key checked add"
              require (addArgs.size == 2) "planned map get target key checked add arg count"
          | _ => throw <| IO.userError "planned map get target key must be checked add"
      | _ => throw <| IO.userError "planned map get target slot must use map helper"
  | _ => throw <| IO.userError "planned map get target must lower to sload"
  let directRawGetExpr ← requireOk
    (ProofForge.Backend.Evm.ToYul.mapGetExpr
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmMapProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmMapProbe.module env)
      1
      (.checkedArith .add (.local "key") (.literalWord 4)))
    "raw map get expr-to-Yul helper"
  match directRawGetExpr with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "raw map get sload arg count"
      requireCallExpr args[0]! (Helper.mapSlot).name 2 "raw map get value slot"
  | _ => throw <| IO.userError "raw map get must lower to sload"
  let legacyPlanGetExpr ← requireOk
    (lowerPlanEffectExpr
      ProofForge.IR.Examples.EvmMapProbe.module
      env
      (.storageMapGet
        "balances"
        (.checkedArith .add (.local "key") (.literalWord 5))))
    "legacy map get EffectPlan target facade"
  match legacyPlanGetExpr with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "legacy map get EffectPlan target facade sload arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call name slotArgs => do
          require (name == (Helper.mapSlot).name) "legacy map get EffectPlan target facade slot helper"
          require (slotArgs.size == 2) "legacy map get EffectPlan target facade slot arg count"
          match slotArgs[1]! with
          | Lean.Compiler.Yul.Expr.call addName addArgs => do
              require (addName == "__pf_checked_add") "legacy map get EffectPlan target facade key"
              require (addArgs.size == 2) "legacy map get EffectPlan target facade key arg count"
          | _ => throw <| IO.userError "legacy map get EffectPlan target facade key must be planned"
      | _ => throw <| IO.userError "legacy map get EffectPlan target facade slot must use map helper"
  | _ => throw <| IO.userError "legacy map get EffectPlan must lower through target facade"
  let containsExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.EvmMapProbe.module
      env
      (.effect (.storageMapContains "balances" (.add (.local "key") (.literal (.u64 1))))))
    "map contains expression plan-to-yul"
  match containsExpr with
  | Lean.Compiler.Yul.Expr.builtin "iszero" args => do
      require (args.size == 1) "map contains expression outer iszero arg count"
  | _ => throw <| IO.userError "map contains expression must lower to iszero"
  let containsEffectExpr ← requireOk
    (lowerEffectExpr
      ProofForge.IR.Examples.EvmMapProbe.module
      env
      (.storageMapContains "balances" (.add (.local "key") (.literal (.u64 1)))))
    "map contains effect Lower-to-Yul"
  match containsEffectExpr with
  | Lean.Compiler.Yul.Expr.builtin "iszero" args => do
      require (args.size == 1) "map contains effect outer iszero arg count"
  | _ => throw <| IO.userError "map contains effect must lower through target plan"
  let getExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.EvmMapProbe.module
      env
      (.effect (.storageMapGet "balances" (.add (.local "key") (.literal (.u64 1))))))
    "map get expression plan-to-yul"
  match getExpr with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "map get expression sload arg count"
      requireCallExpr args[0]! (Helper.mapSlot).name 2 "map get expression value slot helper"
  | _ => throw <| IO.userError "map get expression must lower to sload"

def testMapWritePlanToYul : IO Unit := do
  let env : TypeEnv := #[
    { name := "key", type := .u64, isMutable := false },
    { name := "value", type := .u64, isMutable := false }
  ]
  let directWriteStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.mapWriteEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmMapProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmMapProbe.module env)
      (fun _ => .ok (Lean.Compiler.Yul.Expr.num 0))
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect
        (.storageMapSet
          "balances"
          (.checkedArith .add (.local "key") (.literalWord 1))
          (.effect (.storageScalarRead "before")))))
    "map write StmtPlan-to-Yul helper"
  require (directWriteStmts.size == 1) "map write StmtPlan-to-Yul helper statement count"
  match directWriteStmts[0]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.call name args) => do
      require (name == (Helper.mapWrite).name) "map write StmtPlan-to-Yul helper call"
      require (args.size == 3) "map write StmtPlan-to-Yul helper arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "map write StmtPlan-to-Yul helper key checked add"
          require (addArgs.size == 2) "map write StmtPlan-to-Yul helper key checked add arg count"
      | _ => throw <| IO.userError "map write StmtPlan-to-Yul helper key must be checked add"
      match args[2]! with
      | Lean.Compiler.Yul.Expr.builtin readName readArgs => do
          require (readName == "and") "map write StmtPlan-to-Yul helper value packed read (and)"
          require (readArgs.size == 2) "map write StmtPlan-to-Yul helper value packed read arg count"
      | _ => throw <| IO.userError "map write StmtPlan-to-Yul helper value must be storage read"
  | _ => throw <| IO.userError "map write StmtPlan-to-Yul helper must lower to helper call"
  let directInsertStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.mapWriteEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmMapProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmMapProbe.module env)
      (fun _ => .ok (Lean.Compiler.Yul.Expr.num 0))
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect
        (.storageMapInsert "balances" (.local "key") (.local "value"))))
    "map insert StmtPlan-to-Yul helper"
  require (directInsertStmts.size == 1) "map insert StmtPlan-to-Yul helper statement count"
  match directInsertStmts[0]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.call name args) => do
      require (name == (Helper.mapWrite).name) "map insert StmtPlan-to-Yul helper call"
      require (args.size == 3) "map insert StmtPlan-to-Yul helper arg count"
  | _ => throw <| IO.userError "map insert StmtPlan-to-Yul helper must lower to helper call"
  let loweredMapSetEffect ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.EvmMapProbe.module
      (toValidateTypeEnv env)
      (.storageMapSet "balances" (.local "key") (.local "value")))
    "Lower map set target effect plan"
  match loweredMapSetEffect with
  | .storageMapSetTarget target (.local keyName) (.local valueName) => do
      requireMapWriteTarget target 1 "Lower map set target"
      require (keyName == "key") "Lower map set target key"
      require (valueName == "value") "Lower map set target value"
  | _ => throw <| IO.userError "Lower map set must produce storageMapSetTarget"
  let loweredMapInsertEffect ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.EvmMapProbe.module
      (toValidateTypeEnv env)
      (.storageMapInsert "balances" (.local "key") (.local "value")))
    "Lower map insert target effect plan"
  match loweredMapInsertEffect with
  | .storageMapInsertTarget target (.local keyName) (.local valueName) => do
      requireMapWriteTarget target 1 "Lower map insert target"
      require (keyName == "key") "Lower map insert target key"
      require (valueName == "value") "Lower map insert target value"
  | _ => throw <| IO.userError "Lower map insert must produce storageMapInsertTarget"
  let directPlannedWriteStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.mapWriteTargetEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmMapProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmMapProbe.module env)
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect
        (.storageMapSetTarget
          { rootSlot := 1 }
          (.checkedArith .add (.local "key") (.literalWord 1))
          (.local "value"))))
    "planned map write target StmtPlan-to-Yul helper"
  require (directPlannedWriteStmts.size == 1) "planned map write target helper statement count"
  match directPlannedWriteStmts[0]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.call name args) => do
      require (name == (Helper.mapWrite).name) "planned map write target helper call"
      require (args.size == 3) "planned map write target helper arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.lit literal =>
          require (literal.value == "1") "planned map write target helper root slot"
      | _ => throw <| IO.userError "planned map write target helper root slot must be literal"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "planned map write target helper key checked add"
          require (addArgs.size == 2) "planned map write target helper key checked add arg count"
      | _ => throw <| IO.userError "planned map write target helper key must be checked add"
  | _ => throw <| IO.userError "planned map write target helper must lower to helper call"
  let directPlannedSetReturnExpr ← requireOk
    (ProofForge.Backend.Evm.ToYul.mapSetReturnTargetExpr
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmMapProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmMapProbe.module env)
      { rootSlot := 1 }
      (.local "key")
      (.checkedArith .add (.local "value") (.literalWord 2)))
    "planned map set-return target expr-to-Yul helper"
  match directPlannedSetReturnExpr with
  | Lean.Compiler.Yul.Expr.call name args => do
      require (name == (Helper.mapSetReturn).name) "planned map set-return target helper"
      require (args.size == 3) "planned map set-return target arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.lit literal =>
          require (literal.value == "1") "planned map set-return target root slot"
      | _ => throw <| IO.userError "planned map set-return target root slot must be literal"
      match args[2]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "planned map set-return target value checked add"
          require (addArgs.size == 2) "planned map set-return target value checked add arg count"
      | _ => throw <| IO.userError "planned map set-return target value must be checked add"
  | _ => throw <| IO.userError "planned map set-return target must lower to helper call"
  let writeStmt ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.EvmMapProbe.module
      env
      (.storageMapSet
        "balances"
        (.add (.local "key") (.literal (.u64 1)))
        (.effect (.storageScalarRead "before"))))
    "map write key/value plan-to-yul"
  match writeStmt with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.call name args) => do
      require (name == (Helper.mapWrite).name) "map write plan-to-yul helper"
      require (args.size == 3) "map write plan-to-yul arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "map write key must lower through checked add plan"
          require (addArgs.size == 2) "map write key checked add arg count"
      | _ => throw <| IO.userError "map write key must be plan-lowered checked add"
      match args[2]! with
      | Lean.Compiler.Yul.Expr.builtin readName readArgs => do
          -- Packed read: and(shr(shift, sload(slot)), mask)
          require (readName == "and") "map write value must lower storage read through plan (packed = and)"
          require (readArgs.size == 2) "map write value packed read arg count (and)"
      | _ => throw <| IO.userError "map write value must be plan-lowered packed storage read"
  | _ => throw <| IO.userError "map write plan-to-yul must lower to helper call"
  let setReturnExpr ← requireOk
    (lowerEffectExpr
      ProofForge.IR.Examples.EvmMapProbe.module
      env
      (.storageMapSet
        "balances"
        (.local "key")
        (.add (.local "value") (.literal (.u64 2)))))
    "map set-return effect Lower-to-Yul"
  match setReturnExpr with
  | Lean.Compiler.Yul.Expr.call name args => do
      require (name == (Helper.mapSetReturn).name) "map set-return effect helper"
      require (args.size == 3) "map set-return effect arg count"
      match args[2]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "map set-return effect value checked add"
          require (addArgs.size == 2) "map set-return effect value checked add arg count"
      | _ => throw <| IO.userError "map set-return effect value must be plan-lowered checked add"
  | _ => throw <| IO.userError "map set-return effect must lower through EffectPlan"
  let insertStmt ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.EvmMapProbe.module
      env
      (.storageMapInsert
        "balances"
        (.add (.local "key") (.literal (.u64 1)))
        (.local "value")))
    "map insert statement Lower-to-Yul"
  match insertStmt with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.call name args) => do
      require (name == (Helper.mapWrite).name) "map insert statement helper"
      require (args.size == 3) "map insert statement arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "map insert statement key checked add"
          require (addArgs.size == 2) "map insert statement key checked add arg count"
      | _ => throw <| IO.userError "map insert statement key must be plan-lowered checked add"
      match args[2]! with
      | Lean.Compiler.Yul.Expr.ident valueName =>
          require (valueName == "value") "map insert statement value"
      | _ => throw <| IO.userError "map insert statement value must be plan-lowered local"
  | _ => throw <| IO.userError "map insert statement must lower through EffectPlan"
  let insertReturnExpr ← requireOk
    (lowerEffectExpr
      ProofForge.IR.Examples.EvmMapProbe.module
      env
      (.storageMapInsert
        "balances"
        (.add (.local "key") (.literal (.u64 1)))
        (.local "value")))
    "map insert-return effect Lower-to-Yul"
  match insertReturnExpr with
  | Lean.Compiler.Yul.Expr.call name args => do
      require (name == (Helper.mapSetReturn).name) "map insert-return effect helper"
      require (args.size == 3) "map insert-return effect arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "map insert-return effect key checked add"
          require (addArgs.size == 2) "map insert-return effect key checked add arg count"
      | _ => throw <| IO.userError "map insert-return effect key must be plan-lowered checked add"
  | _ => throw <| IO.userError "map insert-return effect must lower through EffectPlan"

def testArrayReadPlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "value", type := .u64, isMutable := false }]
  let loweredArrayReadEffect ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      (toValidateTypeEnv env)
      (.storageArrayRead "values" (.literal (.u64 1))))
    "Lower array read target effect plan"
  match loweredArrayReadEffect with
  | .storageArrayReadTarget target (.literalWord indexValue) => do
      requireArrayReadTarget target 1 3 "Lower array read target"
      require (indexValue == 1) "Lower array read target index"
  | _ => throw <| IO.userError "Lower array read must produce storageArrayReadTarget"
  let directReadExpr ← requireOk
    (ProofForge.Backend.Evm.ToYul.arrayReadTargetExpr
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module env)
      { rootSlot := 1, length := 3 }
      (.checkedArith .add (.literalWord 1) (.literalWord 1)))
    "planned array read target expr-to-Yul helper"
  match directReadExpr with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "planned array read target sload arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call slotName slotArgs => do
          require (slotName == (Helper.arraySlot).name) "planned array read target slot helper"
          require (slotArgs.size == 3) "planned array read target slot arg count"
          match slotArgs[0]! with
          | Lean.Compiler.Yul.Expr.lit literal =>
              require (literal.value == "1") "planned array read target root slot"
          | _ => throw <| IO.userError "planned array read target root slot must be literal"
          match slotArgs[1]! with
          | Lean.Compiler.Yul.Expr.lit literal =>
              require (literal.value == "3") "planned array read target length"
          | _ => throw <| IO.userError "planned array read target length must be literal"
          match slotArgs[2]! with
          | Lean.Compiler.Yul.Expr.call addName addArgs => do
              require (addName == "__pf_checked_add") "planned array read target index checked add"
              require (addArgs.size == 2) "planned array read target index checked add arg count"
          | _ => throw <| IO.userError "planned array read target index must be checked add"
      | _ => throw <| IO.userError "planned array read target slot must use array helper"
  | _ => throw <| IO.userError "planned array read target must lower to sload"
  let directRawReadExpr ← requireOk
    (ProofForge.Backend.Evm.ToYul.arrayReadExpr
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module env)
      1
      3
      (.checkedArith .add (.literalWord 1) (.literalWord 2)))
    "raw array read expr-to-Yul helper"
  match directRawReadExpr with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "raw array read sload arg count"
      requireCallExpr args[0]! (Helper.arraySlot).name 3 "raw array read slot helper"
  | _ => throw <| IO.userError "raw array read must lower to sload"
  let legacyPlanReadExpr ← requireOk
    (lowerPlanEffectExpr
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      env
      (.storageArrayRead "values" (.checkedArith .add (.literalWord 1) (.literalWord 3))))
    "legacy array read EffectPlan target facade"
  match legacyPlanReadExpr with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "legacy array read EffectPlan target facade sload arg count"
      requireCallExpr args[0]! (Helper.arraySlot).name 3
        "legacy array read EffectPlan target facade slot helper"
  | _ => throw <| IO.userError "legacy array read EffectPlan must lower through target facade"
  let readExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      env
      (.effect (.storageArrayRead "values" (.add (.literal (.u64 1)) (.literal (.u64 1))))))
    "array read expression plan-to-yul"
  match readExpr with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "array read expression sload arg count"
      requireCallExpr args[0]! (Helper.arraySlot).name 3 "array read expression slot helper"
  | _ => throw <| IO.userError "array read expression must lower to sload"
  let readEffectExpr ← requireOk
    (lowerEffectExpr
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      env
      (.storageArrayRead "values" (.add (.literal (.u64 1)) (.literal (.u64 1)))))
    "array read effect Lower-to-Yul"
  match readEffectExpr with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "array read effect sload arg count"
      requireCallExpr args[0]! (Helper.arraySlot).name 3 "array read effect slot helper"
  | _ => throw <| IO.userError "array read effect must lower through target plan"

def testArrayWritePlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "value", type := .u64, isMutable := false }]
  let directWriteStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.arrayWriteEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module env)
      (fun _ index => do
        .ok (Lean.Compiler.Yul.call (Helper.arraySlot).name #[
          Lean.Compiler.Yul.Expr.num 1,
          Lean.Compiler.Yul.Expr.num 3,
          ← ProofForge.Backend.Evm.ToYul.exprPlanExpr
            toYulError
            (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module env expr)
            (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module env)
            index
        ]))
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect
        (.storageArrayWrite
          "values"
          (.checkedArith .add (.literalWord 1) (.literalWord 1))
          (.effect (.storageScalarRead "before")))))
    "array write StmtPlan-to-Yul helper"
  require (directWriteStmts.size == 1) "array write StmtPlan-to-Yul helper statement count"
  match directWriteStmts[0]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "array write StmtPlan-to-Yul helper arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call slotName slotArgs => do
          require (slotName == (Helper.arraySlot).name) "array write StmtPlan-to-Yul helper slot call"
          require (slotArgs.size == 3) "array write StmtPlan-to-Yul helper slot arg count"
          match slotArgs[2]! with
          | Lean.Compiler.Yul.Expr.call addName addArgs => do
              require (addName == "__pf_checked_add") "array write StmtPlan-to-Yul helper index checked add"
              require (addArgs.size == 2) "array write StmtPlan-to-Yul helper index checked add arg count"
          | _ => throw <| IO.userError "array write StmtPlan-to-Yul helper index must be checked add"
      | _ => throw <| IO.userError "array write StmtPlan-to-Yul helper slot must use array helper"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.builtin readName readArgs => do
          require (readName == "and") "array write StmtPlan-to-Yul helper value packed read (and)"
          require (readArgs.size == 2) "array write StmtPlan-to-Yul helper value packed read arg count"
      | _ => throw <| IO.userError "array write StmtPlan-to-Yul helper value must be storage read"
  | _ => throw <| IO.userError "array write StmtPlan-to-Yul helper must lower to sstore"
  let loweredArrayWriteEffect ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      (toValidateTypeEnv env)
      (.storageArrayWrite "values" (.literal (.u64 1)) (.local "value")))
    "Lower array write target effect plan"
  match loweredArrayWriteEffect with
  | .storageArrayWriteTarget target (.literalWord indexValue) (.local valueName) => do
      requireArrayWriteTarget target 1 3 "Lower array write target"
      require (indexValue == 1) "Lower array write target index"
      require (valueName == "value") "Lower array write target value"
  | _ => throw <| IO.userError "Lower array write must produce storageArrayWriteTarget"
  let directPlannedWriteStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.arrayWriteTargetEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module env)
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect
        (.storageArrayWriteTarget
          { rootSlot := 1, length := 3 }
          (.checkedArith .add (.literalWord 1) (.literalWord 1))
          (.checkedArith .add (.local "value") (.literalWord 5)))))
    "planned array write target StmtPlan-to-Yul helper"
  require (directPlannedWriteStmts.size == 1) "planned array write target helper statement count"
  match directPlannedWriteStmts[0]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "planned array write target helper arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call slotName slotArgs => do
          require (slotName == (Helper.arraySlot).name) "planned array write target helper slot call"
          require (slotArgs.size == 3) "planned array write target helper slot arg count"
          match slotArgs[0]! with
          | Lean.Compiler.Yul.Expr.lit literal =>
              require (literal.value == "1") "planned array write target helper root slot"
          | _ => throw <| IO.userError "planned array write target root slot must be literal"
          match slotArgs[1]! with
          | Lean.Compiler.Yul.Expr.lit literal =>
              require (literal.value == "3") "planned array write target helper length"
          | _ => throw <| IO.userError "planned array write target length must be literal"
          match slotArgs[2]! with
          | Lean.Compiler.Yul.Expr.call addName addArgs => do
              require (addName == "__pf_checked_add") "planned array write target helper index checked add"
              require (addArgs.size == 2) "planned array write target helper index checked add arg count"
          | _ => throw <| IO.userError "planned array write target helper index must be checked add"
      | _ => throw <| IO.userError "planned array write target helper slot must use array helper"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "planned array write target helper value checked add"
          require (addArgs.size == 2) "planned array write target helper value checked add arg count"
      | _ => throw <| IO.userError "planned array write target helper value must be checked add"
  | _ => throw <| IO.userError "planned array write target helper must lower to sstore"
  let writeStmt ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      env
      (.storageArrayWrite
        "values"
        (.add (.literal (.u64 1)) (.literal (.u64 1)))
        (.add (.local "value") (.literal (.u64 3)))))
    "array write value plan-to-yul"
  match writeStmt with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "array write plan-to-yul arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call slotName slotArgs => do
          require (slotName == (Helper.arraySlot).name) "array write plan-to-yul slot call"
          require (slotArgs.size == 3) "array write plan-to-yul slot arg count"
          match slotArgs[2]! with
          | Lean.Compiler.Yul.Expr.call addName addArgs => do
              require (addName == "__pf_checked_add") "array write index must lower through checked add plan"
              require (addArgs.size == 2) "array write index checked add arg count"
          | _ => throw <| IO.userError "array write index must be plan-lowered checked add"
      | _ => throw <| IO.userError "array write plan-to-yul slot must use array helper"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "array write value must lower through checked add plan"
          require (addArgs.size == 2) "array write value checked add arg count"
      | _ => throw <| IO.userError "array write value must be plan-lowered checked add"
  | _ => throw <| IO.userError "array write plan-to-yul must lower to sstore"
  let storageValueStmt ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      env
      (.storageArrayWrite
        "values"
        (.literal (.u64 2))
        (.effect (.storageScalarRead "before"))))
    "array write storage-read value plan-to-yul"
  match storageValueStmt with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin ssName args) => do
      require (ssName == "sstore") "array write storage-read value must lower to sstore"
      require (args.size == 2) "array write storage-read value arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.builtin readName readArgs => do
          -- Packed read: and(shr(shift, sload(slot)), mask)
          require (readName == "and") "array write value must lower storage read through plan (packed = and)"
          require (readArgs.size == 2) "array write value packed read arg count (and)"
      | _ => throw <| IO.userError "array write value must be plan-lowered packed storage read"
  | _ => throw <| IO.userError "array write storage-read value must lower to sstore"

def testDynamicArrayPlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "value", type := .u64, isMutable := false }]
  let loweredPushEffect ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.EvmDynamicArrayProbe.module
      (toValidateTypeEnv env)
      (.storageDynamicArrayPush "values" (.add (.local "value") (.literal (.u64 3)))))
    "Lower dynamic-array push effect plan"
  match loweredPushEffect with
  | .storageDynamicArrayPushTarget target (.checkedArith .add (.local valueName) (.literalWord amount)) => do
      require (target.rootSlot == 0) "Lower dynamic-array push target root slot"
      require (valueName == "value") "Lower dynamic-array push value local"
      require (amount == 3) "Lower dynamic-array push checked-add literal"
  | _ => throw <| IO.userError "Lower dynamic-array push must plan target and value expression"
  let directPushStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.dynamicArrayPushTargetEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmDynamicArrayProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmDynamicArrayProbe.module env)
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect loweredPushEffect))
    "dynamic-array push target StmtPlan-to-Yul helper"
  require (directPushStmts.size == 4) "dynamic-array push target helper statement count"
  match directPushStmts[2]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "dynamic-array push target helper sstore arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call slotName slotArgs => do
          require (slotName == (Helper.dynamicArraySlot).name) "dynamic-array push target helper slot"
          require (slotArgs.size == 2) "dynamic-array push target helper slot arg count"
          match slotArgs[0]! with
          | Lean.Compiler.Yul.Expr.lit literal =>
              require (literal.value == "0") "dynamic-array push target helper root slot"
          | _ => throw <| IO.userError "dynamic-array push target helper root slot must be literal"
      | _ => throw <| IO.userError "dynamic-array push target helper first sstore arg must be dynamic slot helper"
      requireCallExpr args[1]! "__pf_checked_add" 2 "dynamic-array push target helper value"
  | _ => throw <| IO.userError "dynamic-array push target helper third statement must be sstore"
  let pushStmt ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.EvmDynamicArrayProbe.module
      env
      (.storageDynamicArrayPush "values" (.add (.local "value") (.literal (.u64 3)))))
    "dynamic-array push Lower-to-Yul"
  match pushStmt with
  | Lean.Compiler.Yul.Statement.block block => do
      require (block.statements.size == 4) "dynamic-array push statement count"
      match block.statements[2]! with
      | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
          require (args.size == 2) "dynamic-array push sstore arg count"
          match args[0]! with
          | Lean.Compiler.Yul.Expr.call slotName slotArgs => do
              require (slotName == (Helper.dynamicArraySlot).name) "dynamic-array push slot helper"
              require (slotArgs.size == 2) "dynamic-array push slot helper arg count"
              match slotArgs[0]! with
              | Lean.Compiler.Yul.Expr.lit literal =>
                  require (literal.value == "0") "dynamic-array push root slot"
              | _ => throw <| IO.userError "dynamic-array push root slot must be literal"
          | _ => throw <| IO.userError "dynamic-array push first sstore arg must be dynamic slot helper"
          match args[1]! with
          | Lean.Compiler.Yul.Expr.call addName addArgs => do
              require (addName == "__pf_checked_add") "dynamic-array push value checked add"
              require (addArgs.size == 2) "dynamic-array push value checked-add arg count"
          | _ => throw <| IO.userError "dynamic-array push value must be plan-lowered checked add"
      | _ => throw <| IO.userError "dynamic-array push third statement must be sstore"
  | _ => throw <| IO.userError "dynamic-array push must lower to block"
  let loweredPopEffect ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.EvmDynamicArrayProbe.module
      (toValidateTypeEnv env)
      (.storageDynamicArrayPop "values"))
    "Lower dynamic-array pop effect plan"
  match loweredPopEffect with
  | .storageDynamicArrayPopTarget target =>
      require (target.rootSlot == 0) "Lower dynamic-array pop target root slot"
  | _ => throw <| IO.userError "Lower dynamic-array pop must produce storageDynamicArrayPopTarget"
  let directPopStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.dynamicArrayPopTargetEffectStmtPlanStatements
      toYulError
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect loweredPopEffect))
    "dynamic-array pop target StmtPlan-to-Yul helper"
  require (directPopStmts.size == 4) "dynamic-array pop target helper statement count"
  match directPopStmts[0]! with
  | Lean.Compiler.Yul.Statement.varDecl _ (some (Lean.Compiler.Yul.Expr.builtin "sload" args)) => do
      require (args.size == 1) "dynamic-array pop target helper load arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.lit literal =>
          require (literal.value == "0") "dynamic-array pop target helper root slot"
      | _ => throw <| IO.userError "dynamic-array pop target helper root slot must be literal"
  | _ => throw <| IO.userError "dynamic-array pop target helper must load root slot"
  let popStmt ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.EvmDynamicArrayProbe.module
      env
      (.storageDynamicArrayPop "values"))
    "dynamic-array pop Lower-to-Yul"
  match popStmt with
  | Lean.Compiler.Yul.Statement.block block => do
      let mut foundLengthLoad := false
      for stmt in block.statements do
        match stmt with
        | Lean.Compiler.Yul.Statement.varDecl _ (some (Lean.Compiler.Yul.Expr.builtin "sload" args)) => do
            if args.size == 1 then
              match args[0]! with
              | Lean.Compiler.Yul.Expr.lit literal =>
                  foundLengthLoad := foundLengthLoad || literal.value == "0"
              | _ => pure ()
        | _ => pure ()
      require foundLengthLoad "dynamic-array pop must load planned root slot"
  | _ => throw <| IO.userError "dynamic-array pop must lower to block"
  requireValidateErrorContains
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      (toValidateTypeEnv env)
      (.storageDynamicArrayPush "values" (.local "value")))
    "EVM storage state 'values' is not a dynamic array"
    "Lower dynamic-array push rejects non-dynamic target before raw fallback"
  requireValidateErrorContains
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      (toValidateTypeEnv env)
      (.storageDynamicArrayPop "values"))
    "EVM storage state 'values' is not a dynamic array"
    "Lower dynamic-array pop rejects non-dynamic target before raw fallback"

def testStructFieldReadPlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "value", type := .u64, isMutable := false }]
  let loweredStructFieldReadEffect ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      (toValidateTypeEnv env)
      (.storageStructFieldRead "current" "x"))
    "Lower struct field read target effect plan"
  match loweredStructFieldReadEffect with
  | .storageStructFieldReadTarget target =>
      requireStructFieldReadTarget target 1 "Lower struct field read target"
  | _ => throw <| IO.userError "Lower struct field read must produce storageStructFieldReadTarget"
  let directReadExpr ← requireOk
    (ProofForge.Backend.Evm.ToYul.structFieldReadTargetExpr
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageStructProbe.module env expr)
      { slot := .scalarSlot 1 })
    "planned struct field read target expr-to-Yul helper"
  match directReadExpr with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "planned struct field read target sload arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.lit literal =>
          require (literal.value == "1") "planned struct field read target slot"
      | _ => throw <| IO.userError "planned struct field read target slot must be literal"
  | _ => throw <| IO.userError "planned struct field read target must lower to sload"
  let directRawReadExpr := ProofForge.Backend.Evm.ToYul.structFieldReadExpr 1
  match directRawReadExpr with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "raw struct field read sload arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.lit literal =>
          require (literal.value == "1") "raw struct field read slot"
      | _ => throw <| IO.userError "raw struct field read slot must be literal"
  | _ => throw <| IO.userError "raw struct field read must lower to sload"
  let legacyPlanReadExpr ← requireOk
    (lowerPlanEffectExpr
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      env
      (.storageStructFieldRead "current" "x"))
    "legacy struct field read EffectPlan target facade"
  match legacyPlanReadExpr with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "legacy struct field read EffectPlan target facade sload arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.lit literal =>
          require (literal.value == "1") "legacy struct field read EffectPlan target facade slot"
      | _ => throw <| IO.userError "legacy struct field read EffectPlan target facade slot must be literal"
  | _ => throw <| IO.userError "legacy struct field read EffectPlan must lower through target facade"
  let readExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      env
      (.effect (.storageStructFieldRead "current" "x")))
    "struct field read expression plan-to-yul"
  match readExpr with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "struct field read expression sload arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.lit literal =>
          require (literal.value == "1") "struct field read expression slot"
      | _ => throw <| IO.userError "struct field read expression slot must be literal"
  | _ => throw <| IO.userError "struct field read expression must lower to sload"

def testStructArrayFieldReadPlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "value", type := .u64, isMutable := false }]
  let loweredStructArrayFieldReadEffect ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      (toValidateTypeEnv env)
      (.storageArrayStructFieldRead "points" (.literal (.u64 1)) "y"))
    "Lower struct-array field read target effect plan"
  match loweredStructArrayFieldReadEffect with
  | .storageArrayStructFieldReadTarget target (.literalWord indexValue) => do
      requireStructArrayFieldReadTarget target 4 2 2 1 "Lower struct-array field read target"
      require (indexValue == 1) "Lower struct-array field read target index"
  | _ => throw <| IO.userError "Lower struct-array field read must produce storageArrayStructFieldReadTarget"
  let directReadExpr ← requireOk
    (ProofForge.Backend.Evm.ToYul.structArrayFieldReadTargetExpr
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageStructProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageStructProbe.module env)
      { rootSlot := 4, length := 2, fieldCount := 2, fieldOffset := 1 }
      (.checkedArith .add (.literalWord 0) (.literalWord 1)))
    "planned struct-array field read target expr-to-Yul helper"
  match directReadExpr with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "planned struct-array field read target sload arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call slotName slotArgs => do
          require (slotName == (Helper.structArraySlot).name) "planned struct-array field read target slot helper"
          require (slotArgs.size == 5) "planned struct-array field read target slot arg count"
          match slotArgs[0]! with
          | Lean.Compiler.Yul.Expr.lit literal =>
              require (literal.value == "4") "planned struct-array field read target root slot"
          | _ => throw <| IO.userError "planned struct-array field read target root slot must be literal"
          match slotArgs[1]! with
          | Lean.Compiler.Yul.Expr.lit literal =>
              require (literal.value == "2") "planned struct-array field read target length"
          | _ => throw <| IO.userError "planned struct-array field read target length must be literal"
          match slotArgs[2]! with
          | Lean.Compiler.Yul.Expr.lit literal =>
              require (literal.value == "2") "planned struct-array field read target field count"
          | _ => throw <| IO.userError "planned struct-array field read target field count must be literal"
          match slotArgs[3]! with
          | Lean.Compiler.Yul.Expr.lit literal =>
              require (literal.value == "1") "planned struct-array field read target field offset"
          | _ => throw <| IO.userError "planned struct-array field read target field offset must be literal"
          match slotArgs[4]! with
          | Lean.Compiler.Yul.Expr.call addName addArgs => do
              require (addName == "__pf_checked_add") "planned struct-array field read target index checked add"
              require (addArgs.size == 2) "planned struct-array field read target index checked add arg count"
          | _ => throw <| IO.userError "planned struct-array field read target index must be checked add"
      | _ => throw <| IO.userError "planned struct-array field read target slot must use struct-array helper"
  | _ => throw <| IO.userError "planned struct-array field read target must lower to sload"
  let directRawReadExpr ← requireOk
    (ProofForge.Backend.Evm.ToYul.structArrayFieldReadExpr
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageStructProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageStructProbe.module env)
      4
      2
      2
      1
      (.literalWord 1))
    "raw struct-array field read expr-to-Yul helper"
  match directRawReadExpr with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "raw struct-array field read sload arg count"
      requireCallExpr args[0]! (Helper.structArraySlot).name 5 "raw struct-array field read slot helper"
  | _ => throw <| IO.userError "raw struct-array field read must lower to sload"
  let legacyPlanReadExpr ← requireOk
    (lowerPlanEffectExpr
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      env
      (.storageArrayStructFieldRead
        "points"
        (.checkedArith .add (.literalWord 0) (.literalWord 1))
        "y"))
    "legacy struct-array field read EffectPlan target facade"
  match legacyPlanReadExpr with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "legacy struct-array field read EffectPlan target facade sload arg count"
      requireCallExpr args[0]! (Helper.structArraySlot).name 5
        "legacy struct-array field read EffectPlan target facade slot helper"
  | _ => throw <| IO.userError "legacy struct-array field read EffectPlan must lower through target facade"
  let readExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      env
      (.effect (.storageArrayStructFieldRead "points" (.add (.literal (.u64 0)) (.literal (.u64 1))) "y")))
    "struct-array field read expression plan-to-yul"
  match readExpr with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "struct-array field read expression sload arg count"
      requireCallExpr args[0]! (Helper.structArraySlot).name 5 "struct-array field read expression slot helper"
  | _ => throw <| IO.userError "struct-array field read expression must lower to sload"
  let readEffectExpr ← requireOk
    (lowerEffectExpr
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      env
      (.storageArrayStructFieldRead "points" (.add (.literal (.u64 0)) (.literal (.u64 1))) "y"))
    "struct-array field read effect Lower-to-Yul"
  match readEffectExpr with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "struct-array field read effect sload arg count"
      requireCallExpr args[0]! (Helper.structArraySlot).name 5 "struct-array field read effect slot helper"
  | _ => throw <| IO.userError "struct-array field read effect must lower through target plan"

def testStructFieldWritePlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "value", type := .u64, isMutable := false }]
  let directFieldStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.structFieldWriteEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageStructProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageStructProbe.module env)
      (fun _ _ => .ok (Lean.Compiler.Yul.Expr.num 2))
      (fun _ index _ => do
        .ok (Lean.Compiler.Yul.call (Helper.structArraySlot).name #[
          Lean.Compiler.Yul.Expr.num 4,
          Lean.Compiler.Yul.Expr.num 2,
          Lean.Compiler.Yul.Expr.num 2,
          Lean.Compiler.Yul.Expr.num 1,
          ← ProofForge.Backend.Evm.ToYul.exprPlanExpr
            toYulError
            (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageStructProbe.module env expr)
            (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageStructProbe.module env)
            index
        ]))
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect
        (.storageStructFieldWrite
          "current"
          "x"
          (.checkedArith .add (.local "value") (.literalWord 5)))))
    "struct field write StmtPlan-to-Yul helper"
  require (directFieldStmts.size == 1) "struct field write StmtPlan-to-Yul helper statement count"
  match directFieldStmts[0]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "struct field write StmtPlan-to-Yul helper arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "struct field write StmtPlan-to-Yul helper checked add"
          require (addArgs.size == 2) "struct field write StmtPlan-to-Yul helper checked add arg count"
      | _ => throw <| IO.userError "struct field write StmtPlan-to-Yul helper value must be checked add"
  | _ => throw <| IO.userError "struct field write StmtPlan-to-Yul helper must lower to sstore"
  let loweredStructFieldWriteEffect ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      (toValidateTypeEnv env)
      (.storageStructFieldWrite "current" "x" (.local "value")))
    "Lower struct field write target effect plan"
  match loweredStructFieldWriteEffect with
  | .storageStructFieldWriteTarget target (.local valueName) => do
      requireStructFieldWriteTarget target 1 "Lower struct field write target"
      require (valueName == "value") "Lower struct field write target value"
  | _ => throw <| IO.userError "Lower struct field write must produce storageStructFieldWriteTarget"
  let directPlannedFieldStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.structFieldWriteTargetEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageStructProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageStructProbe.module env)
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect
        (.storageStructFieldWriteTarget
          { slot := .scalarSlot 1 }
          (.checkedArith .add (.local "value") (.literalWord 5)))))
    "planned struct field write target StmtPlan-to-Yul helper"
  require (directPlannedFieldStmts.size == 1) "planned struct field write target helper statement count"
  match directPlannedFieldStmts[0]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "planned struct field write target helper arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.lit literal =>
          require (literal.value == "1") "planned struct field write target helper slot"
      | _ => throw <| IO.userError "planned struct field write target slot must be literal"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "planned struct field write target helper checked add"
          require (addArgs.size == 2) "planned struct field write target helper checked add arg count"
      | _ => throw <| IO.userError "planned struct field write target helper value must be checked add"
  | _ => throw <| IO.userError "planned struct field write target helper must lower to sstore"
  let directArrayFieldStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.structFieldWriteEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageStructProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageStructProbe.module env)
      (fun _ _ => .ok (Lean.Compiler.Yul.Expr.num 2))
      (fun _ index _ => do
        .ok (Lean.Compiler.Yul.call (Helper.structArraySlot).name #[
          Lean.Compiler.Yul.Expr.num 4,
          Lean.Compiler.Yul.Expr.num 2,
          Lean.Compiler.Yul.Expr.num 2,
          Lean.Compiler.Yul.Expr.num 1,
          ← ProofForge.Backend.Evm.ToYul.exprPlanExpr
            toYulError
            (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageStructProbe.module env expr)
            (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageStructProbe.module env)
            index
        ]))
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect
        (.storageArrayStructFieldWrite
          "points"
          (.checkedArith .add (.literalWord 0) (.literalWord 1))
          "y"
          (.effect (.storageScalarRead "before")))))
    "struct array field write StmtPlan-to-Yul helper"
  require (directArrayFieldStmts.size == 1) "struct array field write StmtPlan-to-Yul helper statement count"
  match directArrayFieldStmts[0]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "struct array field write StmtPlan-to-Yul helper arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call slotName slotArgs => do
          require (slotName == (Helper.structArraySlot).name) "struct array field write StmtPlan-to-Yul helper slot call"
          require (slotArgs.size == 5) "struct array field write StmtPlan-to-Yul helper slot arg count"
          match slotArgs[4]! with
          | Lean.Compiler.Yul.Expr.call addName addArgs => do
              require (addName == "__pf_checked_add") "struct array field write StmtPlan-to-Yul helper index checked add"
              require (addArgs.size == 2) "struct array field write StmtPlan-to-Yul helper index checked add arg count"
          | _ => throw <| IO.userError "struct array field write StmtPlan-to-Yul helper index must be checked add"
      | _ => throw <| IO.userError "struct array field write StmtPlan-to-Yul helper slot must use struct-array helper"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.builtin readName readArgs => do
          require (readName == "and") "struct array field write StmtPlan-to-Yul helper value packed read (and)"
          require (readArgs.size == 2) "struct array field write StmtPlan-to-Yul helper value packed read arg count"
      | _ => throw <| IO.userError "struct array field write StmtPlan-to-Yul helper value must be storage read"
  | _ => throw <| IO.userError "struct array field write StmtPlan-to-Yul helper must lower to sstore"
  let loweredStructArrayFieldWriteEffect ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      (toValidateTypeEnv env)
      (.storageArrayStructFieldWrite "points" (.literal (.u64 1)) "y" (.local "value")))
    "Lower struct-array field write target effect plan"
  match loweredStructArrayFieldWriteEffect with
  | .storageArrayStructFieldWriteTarget target (.literalWord indexValue) (.local valueName) => do
      requireStructArrayFieldWriteTarget target 4 2 2 1 "Lower struct-array field write target"
      require (indexValue == 1) "Lower struct-array field write target index"
      require (valueName == "value") "Lower struct-array field write target value"
  | _ => throw <| IO.userError "Lower struct-array field write must produce storageArrayStructFieldWriteTarget"
  let directPlannedArrayFieldStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.structArrayFieldWriteTargetEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageStructProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageStructProbe.module env)
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect
        (.storageArrayStructFieldWriteTarget
          { rootSlot := 4, length := 2, fieldCount := 2, fieldOffset := 1 }
          (.checkedArith .add (.literalWord 0) (.literalWord 1))
          (.checkedArith .add (.local "value") (.literalWord 7)))))
    "planned struct-array field write target StmtPlan-to-Yul helper"
  require (directPlannedArrayFieldStmts.size == 1) "planned struct-array field write target helper statement count"
  match directPlannedArrayFieldStmts[0]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "planned struct-array field write target helper arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call slotName slotArgs => do
          require (slotName == (Helper.structArraySlot).name) "planned struct-array field write target helper slot call"
          require (slotArgs.size == 5) "planned struct-array field write target helper slot arg count"
          match slotArgs[0]! with
          | Lean.Compiler.Yul.Expr.lit literal =>
              require (literal.value == "4") "planned struct-array field write target root slot"
          | _ => throw <| IO.userError "planned struct-array field write target root slot must be literal"
          match slotArgs[1]! with
          | Lean.Compiler.Yul.Expr.lit literal =>
              require (literal.value == "2") "planned struct-array field write target length"
          | _ => throw <| IO.userError "planned struct-array field write target length must be literal"
          match slotArgs[2]! with
          | Lean.Compiler.Yul.Expr.lit literal =>
              require (literal.value == "2") "planned struct-array field write target field count"
          | _ => throw <| IO.userError "planned struct-array field write target field count must be literal"
          match slotArgs[3]! with
          | Lean.Compiler.Yul.Expr.lit literal =>
              require (literal.value == "1") "planned struct-array field write target field offset"
          | _ => throw <| IO.userError "planned struct-array field write target field offset must be literal"
          match slotArgs[4]! with
          | Lean.Compiler.Yul.Expr.call addName addArgs => do
              require (addName == "__pf_checked_add") "planned struct-array field write target index checked add"
              require (addArgs.size == 2) "planned struct-array field write target index checked add arg count"
          | _ => throw <| IO.userError "planned struct-array field write target index must be checked add"
      | _ => throw <| IO.userError "planned struct-array field write target slot must use struct-array helper"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "planned struct-array field write target value checked add"
          require (addArgs.size == 2) "planned struct-array field write target value checked add arg count"
      | _ => throw <| IO.userError "planned struct-array field write target value must be checked add"
  | _ => throw <| IO.userError "planned struct-array field write target helper must lower to sstore"
  let fieldStmt ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      env
      (.storageStructFieldWrite
        "current"
        "x"
        (.add (.local "value") (.literal (.u64 5)))))
    "struct field write value plan-to-yul"
  match fieldStmt with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "struct field write plan-to-yul arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.lit literal =>
          require (literal.value == "1") "struct field write slot must lower through target plan"
      | _ => throw <| IO.userError "struct field write slot must be planned literal"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "struct field write value must lower through checked add plan"
          require (addArgs.size == 2) "struct field write checked add arg count"
      | _ => throw <| IO.userError "struct field write value must be plan-lowered checked add"
  | _ => throw <| IO.userError "struct field write plan-to-yul must lower to sstore"
  let arrayFieldStmt ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      env
      (.storageArrayStructFieldWrite
        "points"
        (.literal (.u64 1))
        "y"
        (.effect (.storageScalarRead "before"))))
    "struct array field write value plan-to-yul"
  match arrayFieldStmt with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin ssName args) => do
      require (ssName == "sstore") "struct array field write plan-to-yul must lower to sstore"
      require (args.size == 2) "struct array field write plan-to-yul arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call slotName slotArgs => do
          require (slotName == (Helper.structArraySlot).name) "struct array field write plan-to-yul slot call"
          require (slotArgs.size == 5) "struct array field write plan-to-yul slot arg count"
          match slotArgs[0]! with
          | Lean.Compiler.Yul.Expr.lit literal =>
              require (literal.value == "4") "struct array field write root slot must lower through target plan"
          | _ => throw <| IO.userError "struct array field write root slot must be planned literal"
          match slotArgs[1]! with
          | Lean.Compiler.Yul.Expr.lit literal =>
              require (literal.value == "2") "struct array field write length must lower through target plan"
          | _ => throw <| IO.userError "struct array field write length must be planned literal"
          match slotArgs[3]! with
          | Lean.Compiler.Yul.Expr.lit literal =>
              require (literal.value == "1") "struct array field write field offset must lower through target plan"
          | _ => throw <| IO.userError "struct array field write field offset must be planned literal"
      | _ => throw <| IO.userError "struct array field write plan-to-yul slot must use struct-array helper"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.builtin readName readArgs => do
          require (readName == "and") "struct array field write value must lower storage read through plan (packed = and)"
          require (readArgs.size == 2) "struct array field write packed read arg count (and)"
      | _ => throw <| IO.userError "struct array field write value must be plan-lowered packed storage read"
  | _ => throw <| IO.userError "struct array field write plan-to-yul must lower to sstore"

def testWholeStructStorageWritePlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "value", type := .u64, isMutable := false }]
  let directStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.storageStructWriteEffectStmtPlanStatements
      toYulError
      (fun _ _ => .ok #[
        {
          slot := Lean.Compiler.Yul.Expr.num 3
          fieldName := "x"
          value := Lean.Compiler.Yul.call "__pf_checked_add" #[
            Lean.Compiler.Yul.Expr.id "value",
            Lean.Compiler.Yul.Expr.num 7
          ]
        },
        {
          slot := Lean.Compiler.Yul.Expr.num 4
          fieldName := "y"
          value := Lean.Compiler.Yul.builtin "sload" #[Lean.Compiler.Yul.Expr.num 0]
        }
      ])
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect
        (.storageScalarWrite
          "current"
          (.structLit "Point" #[
            ("x", .checkedArith .add (.local "value") (.literalWord 7)),
            ("y", .effect (.storageScalarRead "before"))
          ]))))
    "whole struct storage write StmtPlan-to-Yul helper"
  require (directStmts.size == 1) "whole struct storage write StmtPlan-to-Yul helper statement count"
  match directStmts[0]! with
  | Lean.Compiler.Yul.Statement.block block => do
      let mut foundTempX := false
      let mut foundTempY := false
      let mut foundStoreX := false
      let mut foundStoreY := false
      for stmt in block.statements do
        match stmt with
        | Lean.Compiler.Yul.Statement.varDecl vars (some _) => do
            match vars[0]? with
            | some var =>
                foundTempX := foundTempX || var.name == storageStructAssignTempName "current" "x"
                foundTempY := foundTempY || var.name == storageStructAssignTempName "current" "y"
            | none => pure ()
        | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
            if args.size == 2 then
              match args[1]! with
              | Lean.Compiler.Yul.Expr.ident name =>
                  foundStoreX := foundStoreX || name == storageStructAssignTempName "current" "x"
                  foundStoreY := foundStoreY || name == storageStructAssignTempName "current" "y"
              | _ => pure ()
        | _ => pure ()
      require foundTempX "whole struct storage write StmtPlan-to-Yul helper must snapshot x"
      require foundTempY "whole struct storage write StmtPlan-to-Yul helper must snapshot y"
      require foundStoreX "whole struct storage write StmtPlan-to-Yul helper must store x temp"
      require foundStoreY "whole struct storage write StmtPlan-to-Yul helper must store y temp"
  | _ => throw <| IO.userError "whole struct storage write StmtPlan-to-Yul helper must lower to block"
  let effectPlan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      (toValidateTypeEnv env)
      (.storageScalarWrite
        "current"
        (.structLit "Point" #[
          ("x", .add (.local "value") (.literal (.u64 7))),
          ("y", .effect (.storageScalarRead "before"))
        ])))
    "Lower whole struct storage write effect plan"
  match effectPlan with
  | .storageScalarWrite stateId (.structLit typeName fields) => do
      require (stateId == "current") "Lower whole struct storage write state id"
      require (typeName == "Point") "Lower whole struct storage write struct type"
      let some xField := fields.find? fun field => field.fst == "x"
        | throw <| IO.userError "Lower whole struct storage write must include x field"
      let some yField := fields.find? fun field => field.fst == "y"
        | throw <| IO.userError "Lower whole struct storage write must include y field"
      match xField.snd with
      | .checkedArith .add (.local lhs) (.literalWord rhs) => do
          require (lhs == "value") "Lower whole struct storage write x field lhs"
          require (rhs == 7) "Lower whole struct storage write x field rhs"
      | _ => throw <| IO.userError "Lower whole struct storage write x field must be ExprPlan checked add"
      match yField.snd with
      | .effect (.storageScalarReadTarget target) => do
          require (target.byteOffset == 0) "Lower whole struct storage write y field read byte offset"
          require (target.byteWidth == 8) "Lower whole struct storage write y field read byte width"
      | _ => throw <| IO.userError "Lower whole struct storage write y field must be planned storage read"
  | _ => throw <| IO.userError "Lower whole struct storage write must produce storageScalarWrite"
  let writeStmt ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      env
      (.storageScalarWrite
        "current"
        (.structLit "Point" #[
          ("x", .add (.local "value") (.literal (.u64 7))),
          ("y", .effect (.storageScalarRead "before"))
        ])))
    "whole struct storage write field values plan-to-yul"
  match writeStmt with
  | Lean.Compiler.Yul.Statement.block block => do
      let mut foundCheckedX := false
      let mut foundStorageY := false
      let mut foundStoreX := false
      let mut foundStoreY := false
      for stmt in block.statements do
        match stmt with
        | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.call addName addArgs)) => do
            match vars[0]? with
            | some var =>
                foundCheckedX := foundCheckedX ||
                  (var.name == storageStructAssignTempName "current" "x" &&
                    addName == "__pf_checked_add" &&
                    addArgs.size == 2)
            | none => pure ()
        | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.builtin readName readArgs)) => do
            match vars[0]? with
            | some var =>
                foundStorageY := foundStorageY ||
                  (var.name == storageStructAssignTempName "current" "y" &&
                    readName == "and" &&
                    readArgs.size == 2)
            | none => pure ()
        | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin ssName args) => do
            if ssName == "sstore" && args.size == 2 then
              match args[1]! with
              | Lean.Compiler.Yul.Expr.ident name =>
                  foundStoreX := foundStoreX || name == storageStructAssignTempName "current" "x"
                  foundStoreY := foundStoreY || name == storageStructAssignTempName "current" "y"
              | _ => pure ()
        | _ => pure ()
      require foundCheckedX "whole struct storage write x field must lower through checked add plan"
      require foundStorageY "whole struct storage write y field must lower storage read through plan"
      require foundStoreX "whole struct storage write must store x temp"
      require foundStoreY "whole struct storage write must store y temp"
  | _ => throw <| IO.userError "whole struct storage write plan-to-yul must lower to block"

def testStoragePathReadPlanToYul : IO Unit := do
  let arrayEnv : TypeEnv := #[{ name := "value", type := .u64, isMutable := false }]
  let mapEnv : TypeEnv := #[
    { name := "outer", type := .u64, isMutable := false },
    { name := "inner", type := .u64, isMutable := false }
  ]
  let loweredMapPathRead ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.EvmMapProbe.module
      (toValidateTypeEnv mapEnv)
      (.storagePathRead "balances" #[.mapKey (.add (.local "outer") (.literal (.u64 1)))]))
    "Lower map storage path read target effect plan"
  match loweredMapPathRead with
  | .storagePathReadExprTarget (.mapValueSlot rootSlot keys) => do
      require (rootSlot == 1) "Lower map storage path read target root slot"
      require (keys.size == 1) "Lower map storage path read target key count"
      match keys[0]? with
      | some keyPlan =>
          match keyPlan with
          | .checkedArith .add (.local lhs) (.literalWord rhs) => do
              require (lhs == "outer") "Lower map storage path read key lhs"
              require (rhs == 1) "Lower map storage path read key rhs"
          | _ => throw <| IO.userError "Lower map storage path read key must be ExprPlan checked add"
      | _ => throw <| IO.userError "Lower map storage path read key must be ExprPlan checked add"
  | _ => throw <| IO.userError "Lower map storage path read must produce storagePathReadExprTarget"
  let loweredArrayPathRead ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      (toValidateTypeEnv arrayEnv)
      (.storagePathRead "values" #[.index (.local "value")]))
    "Lower array storage path read target effect plan"
  match loweredArrayPathRead with
  | .storagePathReadExprTarget (.arraySlot rootSlot length indexPlan) => do
      require (rootSlot == 1) "Lower array storage path read target root slot"
      require (length == 3) "Lower array storage path read target length"
      match indexPlan with
      | .local name => require (name == "value") "Lower array storage path read target index"
      | _ => throw <| IO.userError "Lower array storage path read index must be ExprPlan local"
  | _ => throw <| IO.userError "Lower array storage path read must produce storagePathReadExprTarget"
  let typedMapReadPath ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildStoragePathPlan
      ProofForge.IR.Examples.EvmMapProbe.module
      (toValidateTypeEnv mapEnv)
      #[.mapKey (.add (.local "outer") (.literal (.u64 1)))])
    "typed map storage path read plan"
  match typedMapReadPath[0]? with
  | some (ProofForge.Backend.Evm.Plan.StoragePathPlanSegment.mapKey (.checkedArith .add (.local name) (.literalWord value))) => do
      require (name == "outer") "typed map storage path read plan key lhs"
      require (value == 1) "typed map storage path read plan key rhs"
  | _ => throw <| IO.userError "typed map storage path read plan key must be checked add"
  let typedMapReadPlan ← requireOk
    (lowerPlan <|
      ProofForge.Backend.Evm.Plan.storagePathReadExprSlotPlan
        ProofForge.IR.Examples.EvmMapProbe.module
        "balances"
        typedMapReadPath
    )
    "typed map storage path read expr slot plan"
  let typedMapRead ← requireOk
    (ProofForge.Backend.Evm.ToYul.storagePathReadExprFromExprPlan
      toYulError
      (lowerExprPlanExpr ProofForge.IR.Examples.EvmMapProbe.module mapEnv)
      typedMapReadPlan)
    "typed map storage path read expr plan-to-yul"
  match typedMapRead with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "typed map storage path read sload arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call name slotArgs => do
          require (name == (Helper.mapSlot).name) "typed map storage path read slot helper"
          require (slotArgs.size == 2) "typed map storage path read slot arg count"
          requireCallExpr slotArgs[1]! "__pf_checked_add" 2 "typed map storage path read key"
      | _ => throw <| IO.userError "typed map storage path read slot must use map helper"
  | _ => throw <| IO.userError "typed map storage path read must lower to sload"
  let directMapReadPlan ← requireOk
    (lowerPlan <|
      ProofForge.Backend.Evm.Plan.storagePathReadSlotPlan
        ProofForge.IR.Examples.EvmMapProbe.module
        "balances"
        #[.mapKey (.add (.local "outer") (.literal (.u64 1)))]
    )
    "direct map storage path read slot plan"
  let directMapRead ← requireOk
    (ProofForge.Backend.Evm.ToYul.storagePathReadExprFromPlan
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmMapProbe.module mapEnv expr)
      directMapReadPlan)
    "direct map storage path read plan-to-yul"
  match directMapRead with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "direct map storage path read sload arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call name slotArgs => do
          require (name == (Helper.mapSlot).name) "direct map storage path read slot helper"
          require (slotArgs.size == 2) "direct map storage path read slot arg count"
          match slotArgs[1]! with
          | Lean.Compiler.Yul.Expr.call addName addArgs => do
              require (addName == "__pf_checked_add") "direct map storage path read key plan"
              require (addArgs.size == 2) "direct map storage path read key arg count"
          | _ => throw <| IO.userError "direct map storage path read key must be plan-lowered"
      | _ => throw <| IO.userError "direct map storage path read slot must use map helper"
  | _ => throw <| IO.userError "direct map storage path read must lower to sload"
  let arrayReadPlan ← requireOk
    (lowerPlan <|
      ProofForge.Backend.Evm.Plan.storagePathReadSlotPlan
        ProofForge.IR.Examples.EvmStorageArrayProbe.module
        "values"
        #[.index (.local "value")]
    )
    "array storage path read slot plan"
  let arrayRead ← requireOk
    (ProofForge.Backend.Evm.ToYul.storagePathReadExprFromPlan
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module arrayEnv expr)
      arrayReadPlan)
    "array storage path read plan-to-yul"
  match arrayRead with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "array storage path read sload arg count"
      requireCallExpr args[0]! (Helper.arraySlot).name 3 "array storage path read slot"
  | _ => throw <| IO.userError "array storage path read must lower to sload"
  let structReadPlan ← requireOk
    (lowerPlan <|
      ProofForge.Backend.Evm.Plan.storagePathReadSlotPlan
        ProofForge.IR.Examples.EvmStorageStructProbe.module
        "current"
        #[.field "x"]
    )
    "struct storage path read slot plan"
  let structRead ← requireOk
    (ProofForge.Backend.Evm.ToYul.storagePathReadExprFromPlan
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageStructProbe.module #[] expr)
      structReadPlan)
    "struct storage path read plan-to-yul"
  match structRead with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "struct storage path read sload arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.lit literal =>
          require (literal.value == "1") "struct storage path read field slot"
      | _ => throw <| IO.userError "struct storage path read field slot must be literal"
  | _ => throw <| IO.userError "struct storage path read must lower to sload"
  let structArrayReadPlan ← requireOk
    (lowerPlan <|
      ProofForge.Backend.Evm.Plan.storagePathReadSlotPlan
        ProofForge.IR.Examples.EvmStorageStructProbe.module
        "points"
        #[.index (.literal (.u64 1)), .field "y"]
    )
    "struct-array storage path read slot plan"
  let structArrayRead ← requireOk
    (ProofForge.Backend.Evm.ToYul.storagePathReadExprFromPlan
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageStructProbe.module #[] expr)
      structArrayReadPlan)
    "struct-array storage path read plan-to-yul"
  match structArrayRead with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "struct-array storage path read sload arg count"
      requireCallExpr args[0]! (Helper.structArraySlot).name 5 "struct-array storage path read slot"
  | _ => throw <| IO.userError "struct-array storage path read must lower to sload"
  let nestedMapReadPlan ← requireOk
    (lowerPlan <|
      ProofForge.Backend.Evm.Plan.storagePathReadSlotPlan
        ProofForge.IR.Examples.EvmMapProbe.module
        "balances"
        #[.mapKey (.local "outer"), .mapKey (.local "inner")]
    )
    "nested map storage path read slot plan"
  let nestedMapRead ← requireOk
    (ProofForge.Backend.Evm.ToYul.storagePathReadExprFromPlan
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmMapProbe.module mapEnv expr)
      nestedMapReadPlan)
    "nested map storage path read plan-to-yul"
  match nestedMapRead with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "nested map storage path read sload arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call name slotArgs => do
          require (name == (Helper.mapSlot).name) "nested map storage path read outer slot helper"
          require (slotArgs.size == 2) "nested map storage path read outer slot arg count"
          match slotArgs[0]! with
          | Lean.Compiler.Yul.Expr.call parentName parentArgs => do
              require (parentName == (Helper.mapSlot).name) "nested map storage path read parent slot helper"
              require (parentArgs.size == 2) "nested map storage path read parent slot arg count"
          | _ => throw <| IO.userError "nested map storage path read parent slot must use map helper"
      | _ => throw <| IO.userError "nested map storage path read slot must use map helper"
  | _ => throw <| IO.userError "nested map storage path read must lower to sload"
  let rawMapPathRead ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.EvmMapProbe.module
      mapEnv
      (.effect (.storagePathRead "balances" #[.mapKey (.add (.local "outer") (.literal (.u64 1)))])))
    "raw map storage path read expression plan-to-yul"
  match rawMapPathRead with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "raw map storage path read sload arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call name slotArgs => do
          require (name == (Helper.mapSlot).name) "raw map storage path read slot helper"
          require (slotArgs.size == 2) "raw map storage path read slot arg count"
          requireCallExpr slotArgs[1]! "__pf_checked_add" 2 "raw map storage path read key"
      | _ => throw <| IO.userError "raw map storage path read slot must use map helper"
  | _ => throw <| IO.userError "raw map storage path read must lower to sload"
  let rawMapPathReadEffect ← requireOk
    (lowerEffectExpr
      ProofForge.IR.Examples.EvmMapProbe.module
      mapEnv
      (.storagePathRead "balances" #[.mapKey (.add (.local "outer") (.literal (.u64 1)))]))
    "raw map storage path read effect Lower-to-Yul"
  match rawMapPathReadEffect with
  | Lean.Compiler.Yul.Expr.builtin "sload" args => do
      require (args.size == 1) "raw map storage path read effect sload arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call name slotArgs => do
          require (name == (Helper.mapSlot).name) "raw map storage path read effect slot helper"
          require (slotArgs.size == 2) "raw map storage path read effect slot arg count"
          requireCallExpr slotArgs[1]! "__pf_checked_add" 2 "raw map storage path read effect key"
      | _ => throw <| IO.userError "raw map storage path read effect slot must use map helper"
  | _ => throw <| IO.userError "raw map storage path read effect must lower through target plan"

def testStoragePathWritePlanToYul : IO Unit := do
  let arrayEnv : TypeEnv := #[{ name := "value", type := .u64, isMutable := false }]
  let mapEnv : TypeEnv := #[
    { name := "outer", type := .u64, isMutable := false },
    { name := "inner", type := .u64, isMutable := false },
    { name := "value", type := .u64, isMutable := false }
  ]
  let directMapTargetPlan ← requireOk
    (lowerPlan <|
      ProofForge.Backend.Evm.Plan.storagePathWriteTargetPlan
        ProofForge.IR.Examples.EvmMapProbe.module
        "balances"
        #[.mapKey (.add (.local "outer") (.literal (.u64 1)))]
    )
    "direct map storage path target plan"
  let directMapTarget ← requireOk
    (ProofForge.Backend.Evm.ToYul.storagePathWriteTargetFromPlan
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmMapProbe.module mapEnv expr)
      directMapTargetPlan)
    "direct map storage path target plan-to-yul"
  match directMapTarget with
  | ProofForge.Backend.Evm.ToYul.StoragePathWriteTarget.mapWrite rootSlot key => do
      match rootSlot with
      | Lean.Compiler.Yul.Expr.lit literal =>
          require (literal.value == "1") "direct map storage path target root slot"
      | _ => throw <| IO.userError "direct map storage path target root slot must be literal"
      match key with
      | Lean.Compiler.Yul.Expr.call name args => do
          require (name == "__pf_checked_add") "direct map storage path target key plan"
          require (args.size == 2) "direct map storage path target key arg count"
      | _ => throw <| IO.userError "direct map storage path target key must be plan-lowered"
  | _ => throw <| IO.userError "direct map storage path target must lower to mapWrite"
  let typedMapPath ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildStoragePathPlan
      ProofForge.IR.Examples.EvmMapProbe.module
      (toValidateTypeEnv mapEnv)
      #[.mapKey (.add (.local "outer") (.literal (.u64 1)))])
    "typed map storage path plan"
  match typedMapPath[0]? with
  | some (ProofForge.Backend.Evm.Plan.StoragePathPlanSegment.mapKey (.checkedArith .add (.local name) (.literalWord value))) => do
      require (name == "outer") "typed map storage path plan key lhs"
      require (value == 1) "typed map storage path plan key rhs"
  | _ => throw <| IO.userError "typed map storage path plan key must be checked add"
  let typedMapTargetPlan ← requireOk
    (lowerPlan <|
      ProofForge.Backend.Evm.Plan.storagePathWriteExprTargetPlan
        ProofForge.IR.Examples.EvmMapProbe.module
        "balances"
        typedMapPath)
    "typed map storage path expr-target plan"
  let typedMapTarget ← requireOk
    (ProofForge.Backend.Evm.ToYul.storagePathWriteExprTargetFromPlan
      toYulError
      (lowerExprPlanExpr ProofForge.IR.Examples.EvmMapProbe.module mapEnv)
      typedMapTargetPlan)
    "typed map storage path target plan-to-yul"
  match typedMapTarget with
  | ProofForge.Backend.Evm.ToYul.StoragePathWriteTarget.mapWrite _ key => do
      requireCallExpr key "__pf_checked_add" 2 "typed map storage path target key"
  | _ => throw <| IO.userError "typed map storage path target must lower through typed mapWrite"
  let arrayTargetPlan ← requireOk
    (lowerPlan <|
      ProofForge.Backend.Evm.Plan.storagePathWriteTargetPlan
        ProofForge.IR.Examples.EvmStorageArrayProbe.module
        "values"
        #[.index (.local "value")]
    )
    "array storage path target plan"
  let arrayTarget ← requireOk
    (ProofForge.Backend.Evm.ToYul.storagePathWriteTargetFromPlan
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module arrayEnv expr)
      arrayTargetPlan)
    "array storage path target plan-to-yul"
  match arrayTarget with
  | ProofForge.Backend.Evm.ToYul.StoragePathWriteTarget.singleSlot slot =>
      requireCallExpr slot (Helper.arraySlot).name 3 "array storage path target slot"
  | _ => throw <| IO.userError "array storage path target must lower to singleSlot"
  let structTargetPlan ← requireOk
    (lowerPlan <|
      ProofForge.Backend.Evm.Plan.storagePathWriteTargetPlan
        ProofForge.IR.Examples.EvmStorageStructProbe.module
        "current"
        #[.field "x"]
    )
    "struct storage path target plan"
  let structTarget ← requireOk
    (ProofForge.Backend.Evm.ToYul.storagePathWriteTargetFromPlan
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageStructProbe.module #[] expr)
      structTargetPlan)
    "struct storage path target plan-to-yul"
  match structTarget with
  | ProofForge.Backend.Evm.ToYul.StoragePathWriteTarget.singleSlot slot => do
      match slot with
      | Lean.Compiler.Yul.Expr.lit literal =>
          require (literal.value == "1") "struct storage path target field slot"
      | _ => throw <| IO.userError "struct storage path target field slot must be literal"
  | _ => throw <| IO.userError "struct storage path target must lower to singleSlot"
  let structArrayTargetPlan ← requireOk
    (lowerPlan <|
      ProofForge.Backend.Evm.Plan.storagePathWriteTargetPlan
        ProofForge.IR.Examples.EvmStorageStructProbe.module
        "points"
        #[.index (.literal (.u64 1)), .field "y"]
    )
    "struct-array storage path target plan"
  let structArrayTarget ← requireOk
    (ProofForge.Backend.Evm.ToYul.storagePathWriteTargetFromPlan
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageStructProbe.module #[] expr)
      structArrayTargetPlan)
    "struct-array storage path target plan-to-yul"
  match structArrayTarget with
  | ProofForge.Backend.Evm.ToYul.StoragePathWriteTarget.singleSlot slot =>
      requireCallExpr slot (Helper.structArraySlot).name 5 "struct-array storage path target slot"
  | _ => throw <| IO.userError "struct-array storage path target must lower to singleSlot"
  let nestedMapTargetPlan ← requireOk
    (lowerPlan <|
      ProofForge.Backend.Evm.Plan.storagePathWriteTargetPlan
        ProofForge.IR.Examples.EvmMapProbe.module
        "balances"
        #[.mapKey (.local "outer"), .mapKey (.local "inner")]
    )
    "nested map storage path target plan"
  let nestedMapTarget ← requireOk
    (ProofForge.Backend.Evm.ToYul.storagePathWriteTargetFromPlan
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmMapProbe.module mapEnv expr)
      nestedMapTargetPlan)
    "nested map storage path target plan-to-yul"
  match nestedMapTarget with
  | ProofForge.Backend.Evm.ToYul.StoragePathWriteTarget.mapValuePresence valueSlot presenceSlot => do
      requireCallExpr valueSlot (Helper.mapSlot).name 2 "nested map storage path target value slot"
      requireCallExpr presenceSlot (Helper.mapPresenceSlot).name 2 "nested map storage path target presence slot"
  | _ => throw <| IO.userError "nested map storage path target must lower to value/presence slots"
  let loweredArrayWriteEffect ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      (toValidateTypeEnv arrayEnv)
      (.storagePathWrite
        "values"
        #[.index (.local "value")]
        (.add (.local "value") (.literal (.u64 4)))))
    "Lower storage path write target effect plan"
  match loweredArrayWriteEffect with
  | .storagePathWriteExprTarget (.singleSlot (.arraySlot _ length (.local indexName))) valuePlan => do
      require (length == 3) "Lower storage path write target array length"
      require (indexName == "value") "Lower storage path write target index"
      match valuePlan with
      | .checkedArith .add (.local lhs) (.literalWord rhs) => do
          require (lhs == "value") "Lower storage path write target value lhs"
          require (rhs == 4) "Lower storage path write target value rhs"
      | _ => throw <| IO.userError "Lower storage path write target value must be checked add"
  | _ => throw <| IO.userError "Lower storage path write must produce storagePathWriteExprTarget"
  let loweredArrayAssignOpEffect ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      (toValidateTypeEnv arrayEnv)
      (.storagePathAssignOp
        "values"
        #[.index (.local "value")]
        .add
        (.literal (.u64 1))))
    "Lower storage path assign_op target effect plan"
  match loweredArrayAssignOpEffect with
  | .storagePathAssignOpExprTarget (.singleSlot (.arraySlot _ length (.local indexName))) op (.literalWord value) => do
      require (length == 3) "Lower storage path assign_op target array length"
      require (indexName == "value") "Lower storage path assign_op target index"
      require (op == .add) "Lower storage path assign_op target op"
      require (value == 1) "Lower storage path assign_op target value"
  | _ => throw <| IO.userError "Lower storage path assign_op must produce storagePathAssignOpExprTarget"
  let directWriteStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.storagePathWriteExprTargetEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module arrayEnv expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module arrayEnv)
      (lowerExprPlanExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module arrayEnv)
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect
        (.storagePathWriteExprTarget
          (.singleSlot (.arraySlot 0 3 (.local "value")))
          (.checkedArith .add (.local "value") (.literalWord 4)))))
    "storage path write expr-target StmtPlan-to-Yul helper"
  require (directWriteStmts.size == 1) "storage path write expr-target StmtPlan-to-Yul helper statement count"
  match directWriteStmts[0]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "storage path write expr-target StmtPlan-to-Yul helper arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call slotName slotArgs => do
          require (slotName == (Helper.arraySlot).name) "storage path write expr-target helper slot"
          require (slotArgs.size == 3) "storage path write expr-target helper slot arg count"
      | _ => throw <| IO.userError "storage path write expr-target helper slot must use array helper"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "storage path write expr-target StmtPlan-to-Yul helper checked add"
          require (addArgs.size == 2) "storage path write expr-target StmtPlan-to-Yul helper checked add arg count"
      | _ => throw <| IO.userError "storage path write expr-target StmtPlan-to-Yul helper value must be checked add"
  | _ => throw <| IO.userError "storage path write expr-target StmtPlan-to-Yul helper must lower to sstore"
  let directPlannedWriteStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.storagePathWriteTargetEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module arrayEnv expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module arrayEnv)
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect
        (.storagePathWriteTarget
          (.singleSlot (.arraySlot 0 3 (.irExpr (.local "value"))))
          (.checkedArith .add (.local "value") (.literalWord 4)))))
    "planned storage path write target StmtPlan-to-Yul helper"
  require (directPlannedWriteStmts.size == 1) "planned storage path write target helper statement count"
  match directPlannedWriteStmts[0]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "planned storage path write target helper arg count"
      requireCallExpr args[0]! (Helper.arraySlot).name 3 "planned storage path write target helper slot"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "planned storage path write target helper checked add"
          require (addArgs.size == 2) "planned storage path write target helper checked add arg count"
      | _ => throw <| IO.userError "planned storage path write target helper value must be checked add"
  | _ => throw <| IO.userError "planned storage path write target helper must lower to sstore"
  let fallbackArrayWriteStmt ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      arrayEnv
      (.storagePathWrite
        "values"
        #[.index (.literal (.u64 1))]
        (.arrayGet
          (.arrayLit .u64 #[.literal (.u64 2), .literal (.u64 3)])
          (.literal (.u64 1)))))
    "fallback array storage path write value plan-to-yul"
  match fallbackArrayWriteStmt with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "fallback array storage path write sstore arg count"
      requireCallExpr args[0]! (Helper.arraySlot).name 3 "fallback array storage path write slot"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.lit literal =>
          require (literal.value == "3") "fallback array storage path write value"
      | _ => throw <| IO.userError "fallback array storage path write value must be lowered literal"
  | _ => throw <| IO.userError "fallback array storage path write must lower to sstore"
  let arrayWriteStmt ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      arrayEnv
      (.storagePathWrite
        "values"
        #[.index (.literal (.u64 1))]
        (.add (.local "value") (.literal (.u64 4)))))
    "array storage path write value plan-to-yul"
  match arrayWriteStmt with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "array storage path write plan-to-yul arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call slotName slotArgs => do
          require (slotName == (Helper.arraySlot).name) "array storage path write plan-to-yul slot call"
          require (slotArgs.size == 3) "array storage path write plan-to-yul slot arg count"
      | _ => throw <| IO.userError "array storage path write plan-to-yul slot must use array helper"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "array storage path write value must lower through checked add plan"
          require (addArgs.size == 2) "array storage path write value checked add arg count"
      | _ => throw <| IO.userError "array storage path write value must be plan-lowered checked add"
  | _ => throw <| IO.userError "array storage path write plan-to-yul must lower to sstore"
  let nestedWriteStmt ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.EvmMapProbe.module
      mapEnv
      (.storagePathWrite
        "balances"
        #[.mapKey (.local "outer"), .mapKey (.local "inner")]
        (.add (.local "value") (.literal (.u64 9)))))
    "nested storage path write value plan-to-yul"
  match nestedWriteStmt with
  | Lean.Compiler.Yul.Statement.block block => do
      let mut foundCheckedValue := false
      for stmt in block.statements do
        match stmt with
        | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
            if args.size == 2 then
              match args[0]!, args[1]! with
              | Lean.Compiler.Yul.Expr.ident slotName, Lean.Compiler.Yul.Expr.call addName addArgs =>
                  foundCheckedValue := foundCheckedValue ||
                    (slotName == "_slot" && addName == "__pf_checked_add" && addArgs.size == 2)
              | _, _ => pure ()
        | _ => pure ()
      require foundCheckedValue "nested storage path write value must lower through checked add plan"
  | _ => throw <| IO.userError "nested storage path write plan-to-yul must lower to block"
  let directAssignOpStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.storagePathAssignOpExprTargetEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module arrayEnv expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module arrayEnv)
      (lowerExprPlanExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module arrayEnv)
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect
        (.storagePathAssignOpExprTarget
          (.singleSlot (.arraySlot 0 3 (.literalWord 0)))
          .add
          (.effect (.storageScalarRead "before")))))
    "storage path assign_op expr-target StmtPlan-to-Yul helper"
  require (directAssignOpStmts.size == 1) "storage path assign_op expr-target StmtPlan-to-Yul helper statement count"
  match directAssignOpStmts[0]! with
  | Lean.Compiler.Yul.Statement.block block => do
      let mut foundStorageReadValue := false
      let mut foundPlannedSlot := false
      for stmt in block.statements do
        match stmt with
        | Lean.Compiler.Yul.Statement.varDecl names (some slot) => do
            let slotTempName ← requireAt names 0 "storage path assign_op expr-target slot temp name"
            foundPlannedSlot := foundPlannedSlot ||
              (names.size == 1 && slotTempName.name == "_slot" &&
                match slot with
                | Lean.Compiler.Yul.Expr.call slotName slotArgs =>
                    slotName == (Helper.arraySlot).name && slotArgs.size == 3
                | _ => false)
        | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
            if args.size == 2 then
              match args[1]! with
              | Lean.Compiler.Yul.Expr.call addName addArgs =>
                  if addName == "__pf_checked_add" && addArgs.size == 2 then
                    match addArgs[1]! with
                    | Lean.Compiler.Yul.Expr.builtin readName readArgs =>
                        foundStorageReadValue := foundStorageReadValue ||
                          (readName == "and" && readArgs.size == 2)
                    | _ => pure ()
              | _ => pure ()
        | _ => pure ()
      require foundPlannedSlot "storage path assign_op expr-target helper must use planned slot"
      require foundStorageReadValue "storage path assign_op expr-target StmtPlan-to-Yul helper value must lower storage read through plan"
  | _ => throw <| IO.userError "storage path assign_op expr-target StmtPlan-to-Yul helper must lower to block"
  let directPlannedAssignOpStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.storagePathAssignOpTargetEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module arrayEnv expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module arrayEnv)
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect
        (.storagePathAssignOpTarget
          (.singleSlot (.arraySlot 0 3 (.irExpr (.local "value"))))
          .add
          (.literalWord 1))))
    "planned storage path assign_op target StmtPlan-to-Yul helper"
  require (directPlannedAssignOpStmts.size == 1) "planned storage path assign_op target helper statement count"
  match directPlannedAssignOpStmts[0]! with
  | Lean.Compiler.Yul.Statement.block block => do
      let mut foundPlannedAssign := false
      for stmt in block.statements do
        match stmt with
        | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
            if args.size == 2 then
              match args[1]! with
              | Lean.Compiler.Yul.Expr.call addName addArgs =>
                  foundPlannedAssign := foundPlannedAssign ||
                    (addName == "__pf_checked_add" && addArgs.size == 2)
              | _ => pure ()
        | _ => pure ()
      require foundPlannedAssign "planned storage path assign_op target helper must use checked add"
  | _ => throw <| IO.userError "planned storage path assign_op target helper must lower to block"
  let fallbackArrayAssignOpStmt ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      arrayEnv
      (.storagePathAssignOp
        "values"
        #[.index (.literal (.u64 1))]
        .add
        (.arrayGet
          (.arrayLit .u64 #[.literal (.u64 2), .literal (.u64 3)])
          (.literal (.u64 1)))))
    "fallback array storage path assign_op value plan-to-yul"
  match fallbackArrayAssignOpStmt with
  | Lean.Compiler.Yul.Statement.block block => do
      let mut foundSlotDecl := false
      let mut foundCheckedAssign := false
      for stmt in block.statements do
        match stmt with
        | Lean.Compiler.Yul.Statement.varDecl names (some slot) => do
            let slotTempName ← requireAt names 0 "fallback array storage path assign_op slot temp name"
            foundSlotDecl := foundSlotDecl ||
              (names.size == 1 && slotTempName.name == "_slot" &&
                match slot with
                | Lean.Compiler.Yul.Expr.call slotName slotArgs =>
                    slotName == (Helper.arraySlot).name && slotArgs.size == 3
                | _ => false)
        | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
            if args.size == 2 then
              match args[0]!, args[1]! with
              | Lean.Compiler.Yul.Expr.ident slotName, Lean.Compiler.Yul.Expr.call addName addArgs =>
                  foundCheckedAssign := foundCheckedAssign ||
                    (slotName == "_slot" && addName == "__pf_checked_add" && addArgs.size == 2)
              | _, _ => pure ()
        | _ => pure ()
      require foundSlotDecl "fallback array storage path assign_op must declare ToYul slot temp"
      require foundCheckedAssign "fallback array storage path assign_op must use ToYul checked assignment frame"
  | _ => throw <| IO.userError "fallback array storage path assign_op plan-to-yul must lower to block"
  let directMapAssign ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.EvmMapProbe.module
      mapEnv
      (.storagePathAssignOp
        "balances"
        #[.mapKey (.add (.local "outer") (.literal (.u64 1)))]
        .add
        (.effect (.storageScalarRead "before"))))
    "direct map storage path assign_op key/value plan-to-yul"
  match directMapAssign with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.call name args) => do
      require (name == (Helper.mapAssign .add).name) "direct map storage path assign_op helper"
      require (args.size == 3) "direct map storage path assign_op arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "direct map storage path assign_op key must lower through checked add plan"
          require (addArgs.size == 2) "direct map storage path assign_op key checked add arg count"
      | _ => throw <| IO.userError "direct map storage path assign_op key must be plan-lowered checked add"
      match args[2]! with
      | Lean.Compiler.Yul.Expr.builtin readName readArgs => do
          require (readName == "and") "direct map storage path assign_op value must lower storage read through plan (packed = and)"
          require (readArgs.size == 2) "direct map storage path assign_op value packed read arg count (and)"
      | _ => throw <| IO.userError "direct map storage path assign_op value must be plan-lowered packed storage read"
  | _ => throw <| IO.userError "direct map storage path assign_op plan-to-yul must lower to helper call"
  let nestedMapAssign ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.EvmMapProbe.module
      mapEnv
      (.storagePathAssignOp
        "balances"
        #[.mapKey (.local "outer"), .mapKey (.local "inner")]
        .add
        (.effect (.storageScalarRead "before"))))
    "nested map storage path assign_op value plan-to-yul"
  match nestedMapAssign with
  | Lean.Compiler.Yul.Statement.block block => do
      let mut foundStorageReadValue := false
      for stmt in block.statements do
        match stmt with
        | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin ssName args) => do
            if ssName == "sstore" && args.size == 2 then
              match args[0]!, args[1]! with
              | Lean.Compiler.Yul.Expr.ident slotName, Lean.Compiler.Yul.Expr.call addName addArgs =>
                  if slotName == "_slot" && addName == "__pf_checked_add" && addArgs.size == 2 then
                    match addArgs[1]! with
                    | Lean.Compiler.Yul.Expr.builtin readName readArgs =>
                        foundStorageReadValue := foundStorageReadValue ||
                          (readName == "and" && readArgs.size == 2)
                    | _ => pure ()
              | _, _ => pure ()
        | _ => pure ()
      require foundStorageReadValue "nested map storage path assign_op value must lower storage read through plan"
  | _ => throw <| IO.userError "nested map storage path assign_op plan-to-yul must lower to block"
  let arrayAssign ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      #[]
      (.storagePathAssignOp
        "values"
        #[.index (.literal (.u64 1))]
        .add
        (.effect (.storageScalarRead "before"))))
    "array storage path assign_op value plan-to-yul"
  match arrayAssign with
  | Lean.Compiler.Yul.Statement.block block => do
      let mut foundStorageReadValue := false
      for stmt in block.statements do
        match stmt with
        | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin ssName args) => do
            if ssName == "sstore" && args.size == 2 then
              match args[1]! with
              | Lean.Compiler.Yul.Expr.call addName addArgs =>
                  if addName == "__pf_checked_add" && addArgs.size == 2 then
                    match addArgs[1]! with
                    | Lean.Compiler.Yul.Expr.builtin readName readArgs =>
                        foundStorageReadValue := foundStorageReadValue ||
                          (readName == "and" && readArgs.size == 2)
                    | _ => pure ()
              | _ => pure ()
        | _ => pure ()
      require foundStorageReadValue "array storage path assign_op value must lower storage read through plan"
  | _ => throw <| IO.userError "array storage path assign_op plan-to-yul must lower to block"
  let structEnv : TypeEnv := #[{ name := "value", type := .u64, isMutable := false }]
  let fieldAssign ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      structEnv
      (.storagePathAssignOp
        "current"
        #[.field "x"]
        .add
        (.add (.local "value") (.literal (.u64 2)))))
    "struct field storage path assign_op value plan-to-yul"
  match fieldAssign with
  | Lean.Compiler.Yul.Statement.block block => do
      let mut foundCheckedValue := false
      for stmt in block.statements do
        match stmt with
        | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin ssName1 args) => do
            if ssName1 == "sstore" && args.size == 2 then
              match args[1]! with
              | Lean.Compiler.Yul.Expr.call addName addArgs =>
                  if addName == "__pf_checked_add" && addArgs.size == 2 then
                    match addArgs[1]! with
                    | Lean.Compiler.Yul.Expr.call rhsAddName rhsAddArgs =>
                        foundCheckedValue := foundCheckedValue ||
                          (rhsAddName == "__pf_checked_add" && rhsAddArgs.size == 2)
                    | _ => pure ()
              | _ => pure ()
        | _ => pure ()
      require foundCheckedValue "struct field storage path assign_op value must lower through checked add plan"
  | _ => throw <| IO.userError "struct field storage path assign_op plan-to-yul must lower to block"
  let arrayFieldAssign ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      #[]
      (.storagePathAssignOp
        "points"
        #[.index (.literal (.u64 1)), .field "y"]
        .add
        (.effect (.storageScalarRead "before"))))
    "struct-array field storage path assign_op value plan-to-yul"
  match arrayFieldAssign with
  | Lean.Compiler.Yul.Statement.block block => do
      let mut foundStorageReadValue := false
      for stmt in block.statements do
        match stmt with
        | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin ssName2 args) => do
            if ssName2 == "sstore" && args.size == 2 then
              match args[1]! with
              | Lean.Compiler.Yul.Expr.call addName addArgs =>
                  if addName == "__pf_checked_add" && addArgs.size == 2 then
                    match addArgs[1]! with
                    | Lean.Compiler.Yul.Expr.builtin readName readArgs =>
                        foundStorageReadValue := foundStorageReadValue ||
                          (readName == "and" && readArgs.size == 2)
                    | _ => pure ()
              | _ => pure ()
        | _ => pure ()
      require foundStorageReadValue "struct-array field storage path assign_op value must lower storage read through plan"
  | _ => throw <| IO.userError "struct-array field storage path assign_op plan-to-yul must lower to block"

def testContextPlanToYul : IO Unit := do
  let env : TypeEnv := #[
    { name := "block_number", type := .u64, isMutable := false }
  ]
  let plan ← requireValidateOk
    (ProofForge.Backend.Evm.Lower.buildEffectPlan
      ProofForge.IR.Examples.Counter.module
      (toValidateTypeEnv env)
      (.contextRead (.blockHash (.add (.local "block_number") (.literal (.u64 1))))))
    "context blockhash Lower EffectPlan"
  match plan with
  | .contextRead (.blockHash (.checkedArith .add (.local name) (.literalWord value))) => do
      require (name == "block_number") "context blockhash planned local name"
      require (value == 1) "context blockhash planned offset"
  | _ => throw <| IO.userError "context blockhash must lower to planned checked-add argument"
  let lowered ← requireOk
    (lowerPlanEffectExpr ProofForge.IR.Examples.Counter.module env plan)
    "context blockhash plan-to-yul"
  match lowered with
  | Lean.Compiler.Yul.Expr.builtin name args => do
      require (name == "blockhash") "context blockhash plan-to-yul builtin"
      require (args.size == 1) "context blockhash plan-to-yul arg count"
      requireCallExpr args[0]! "__pf_checked_add" 2 "context blockhash planned argument"
  | _ => throw <| IO.userError "context blockhash plan-to-yul must lower to blockhash builtin"
  let directContextExpr ← requireOk
    (lowerEffectExpr
      ProofForge.IR.Examples.Counter.module
      env
      (.contextRead (.blockHash (.add (.local "block_number") (.literal (.u64 1))))))
    "context blockhash effect Lower-to-Yul"
  match directContextExpr with
  | Lean.Compiler.Yul.Expr.builtin name args => do
      require (name == "blockhash") "context blockhash effect Lower-to-Yul builtin"
      require (args.size == 1) "context blockhash effect Lower-to-Yul arg count"
      requireCallExpr args[0]! "__pf_checked_add" 2 "context blockhash effect planned argument"
  | _ => throw <| IO.userError "context blockhash effect must lower through target plan"

def main : IO UInt32 := do
  testCounterSemanticPlan
  testEventSemanticPlan
  testERC20StandardEventSignatureTypes
  testArtifactMetadata
  testDeployMetadata
  testHashHelperPlanToYul
  testArrayHelperPlanToYul
  testMapHelperPlanToYul
  testPlannedHelperDiscoveryToYul
  testPlannedCrosscallHelperDiscoveryFromEntrypointPlans
  testPlannedCreateHelperDiscoveryFromEntrypointPlans
  testPlannedMemoryArrayHelperDiscoveryFromEntrypointPlans
  testPlannedHashHelperDiscoveryFromEntrypointPlans
  testPlannedMapHelperDiscoveryFromEntrypointPlans
  testPlannedStorageArrayHelperDiscoveryFromEntrypointPlans
  testPlannedCheckedArithmeticDiscoveryFromEntrypointPlans
  testPlannedContextOpsDiscoveryFromEntrypointPlans
  testLocalArrayHelperDiscoveryInLowerPlan
  testIncompletePlanFallbackHelperDiscovery
  testEntrypointDispatchPlanToYul
  testSemanticPlanRender
  testFallbackReceiveEntrypointPlanLowering
  testScalarExprPlanToYul
  testStorageFixedArrayCrosscallWordPlans
  testArrayLiteralDirectExprPlanToYul
  testAggregateLiteralEntrypointPlannedBody
  testScalarFallbackGateAggregateLiteralPlanToYul
  testScalarFallbackGateLocalAggregatePlanToYul
  testScalarFallbackGateMemoryArrayPlanToYul
  testScalarFallbackGateCrosscallCreatePlanToYul
  testLocalAbiWordsToYul
  testLocalCrosscallWordsToYul
  testReturnValueWordPlanToYul
  testAggregateAssignmentPlanToYul
  testScalarAssertPlanToYul
  testScalarReturnPlanToYul
  testScalarBindingStmtPlanToYul
  testScalarAssignmentPlanToYul
  testScalarControlFlowPlanToYul
  testScalarEventPlanToYul
  testLocalAggregateEventDataWordsPlanToYul
  testStorageAggregateEventDataWordsPlanToYul
  testStorageAggregateIndexedEventTopicPlanToYul
  testScalarStorageEffectPlanToYul
  testMapReadPlanToYul
  testMapWritePlanToYul
  testArrayReadPlanToYul
  testArrayWritePlanToYul
  testDynamicArrayPlanToYul
  testStructFieldReadPlanToYul
  testStructArrayFieldReadPlanToYul
  testStructFieldWritePlanToYul
  testWholeStructStorageWritePlanToYul
  testStoragePathReadPlanToYul
  testStoragePathWritePlanToYul
  testContextPlanToYul
  IO.println "evm-semantic-plan: ok"
  return 0

end ProofForge.Tests.EvmSemanticPlan

def main : IO UInt32 :=
  ProofForge.Tests.EvmSemanticPlan.main
