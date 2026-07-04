import ProofForge.Backend.Evm.IR
import ProofForge.IR.Examples.Counter
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

def testCounterSemanticPlan : IO Unit := do
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
  | .effect (.storageScalarWrite stateId (.literalWord value)) => do
      require (stateId == "count") "counter plan initialize storage write state"
      require (value == 0) "counter plan initialize storage write value"
  | _ => throw <| IO.userError "counter plan initialize body must be storage scalar write"
  let inc := plan.entrypoints[1]!
  require (inc.name == "increment") "counter plan increment name"
  require (inc.body.size == 2) "counter plan increment body size"
  match ← requireAt inc.body 0 "counter plan increment missing first statement" with
  | .letBind name type (.effect (.storageScalarRead stateId)) => do
      require (name == "n") "counter plan increment let name"
      require (type == .u64) "counter plan increment let type"
      require (stateId == "count") "counter plan increment read state"
  | _ => throw <| IO.userError "counter plan increment first statement must read count"
  match ← requireAt inc.body 1 "counter plan increment missing second statement" with
  | .effect (.storageScalarWrite stateId (.checkedArith .add (.local name) (.literalWord value))) => do
      require (stateId == "count") "counter plan increment write state"
      require (name == "n") "counter plan increment add lhs"
      require (value == 1) "counter plan increment add rhs"
  | _ => throw <| IO.userError "counter plan increment second statement must write checked add"
  let get := plan.entrypoints[2]!
  require (get.name == "get") "counter plan get name"
  require (get.selector == "6d4ce63c") "counter plan get selector"
  require (get.returns.returnType == .u64) "counter plan get returns u64"
  require (get.returns.wordTypes == #[.u64]) "counter plan get return words"
  require (get.body.size == 1) "counter plan get body size"
  match ← requireAt get.body 0 "counter plan get missing body" with
  | .return (.effect (.storageScalarRead stateId)) =>
      require (stateId == "count") "counter plan get return read state"
  | _ => throw <| IO.userError "counter plan get body must return storage scalar read"
  let storageCount ← requireSome (plan.storage.find? "count") "counter plan missing count storage"
  require (storageCount.slot == 0) "counter plan count slot"
  require (storageCount.span == 1) "counter plan count span"
  require (plan.usesCheckedArithmetic == true) "counter plan checked arithmetic (increment uses add)"
  require (plan.creates.size == 0) "counter plan no creates"

def testEventSemanticPlan : IO Unit := do
  let plan ← requireOk (buildSemanticPlan ProofForge.IR.Examples.EventProbe.evmModule) "event plan"
  require (plan.entrypoints.size > 0) "event plan entrypoint count"
  require (plan.events.size > 0) "event plan event count"
  let valueEvent? := plan.events.find? (fun ev => ev.name == "ValueEvent")
  require valueEvent?.isSome "event plan missing ValueEvent"
  let valueEvent := valueEvent?.get!
  require (valueEvent.signature == "ValueEvent(uint64)") "event plan ValueEvent signature"
  let fields := valueEvent.fields
  require (fields.size == 1) "event plan ValueEvent field count"
  require (fields[0]!.name == "value") "event plan ValueEvent field name"
  require (fields[0]!.type == .u64) "event plan ValueEvent field type"
  require (fields[0]!.indexed == false) "event plan ValueEvent field not indexed"
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

def testSemanticPlanRender : IO Unit := do
  let rendered ← requireOk (renderSemanticPlan ProofForge.IR.Examples.Counter.module) "counter plan render"
  require (rendered.contains "module: Counter") "counter plan render module"
  require (rendered.contains "target: evm") "counter plan render target"
  require (rendered.contains "entrypoints:") "counter plan render entrypoints"
  require (rendered.contains "initialize") "counter plan render initialize"
  require (rendered.contains "storage:") "counter plan render storage"

def testScalarExprPlanToYul : IO Unit := do
  let readExpr ← requireOk
    (lowerExprViaPlan
      ProofForge.IR.Examples.Counter.module
      #[]
      (.effect (.storageScalarRead "count")))
    "counter scalar read plan-to-yul"
  match readExpr with
  | Lean.Compiler.Yul.Expr.builtin name args => do
      require (name == "sload") "counter scalar read plan-to-yul opcode"
      require (args.size == 1) "counter scalar read plan-to-yul arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.lit lit =>
          require (lit.value == "0") "counter scalar read plan-to-yul slot"
      | _ => throw <| IO.userError "counter scalar read plan-to-yul slot must be literal"
  | _ => throw <| IO.userError "counter scalar read plan-to-yul must be sload"
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

def testScalarAssertPlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "n", type := .u64, isMutable := false }]
  let assertCond ← requireOk
    (lowerScalarPlanExprOrFallback
      ProofForge.IR.Examples.Counter.module
      env
      (.gt (.local "n") (.literal (.u64 0))))
    "scalar assert condition plan-to-yul"
  let assertStmt := lowerAssertStmt assertCond none
  match assertStmt with
  | Lean.Compiler.Yul.Statement.ifStmt (Lean.Compiler.Yul.Expr.builtin name args) _ => do
      require (name == "iszero") "scalar assert plan-to-yul guard builtin"
      require (args.size == 1) "scalar assert plan-to-yul iszero arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.builtin name _ =>
          require (name == "gt") "scalar assert plan-to-yul condition builtin"
      | _ => throw <| IO.userError "scalar assert plan-to-yul condition must be builtin"
  | _ => throw <| IO.userError "scalar assert plan-to-yul must lower to if iszero"
  let lhs ← requireOk
    (lowerScalarPlanExprOrFallback
      ProofForge.IR.Examples.Counter.module
      env
      (.local "n"))
    "scalar assertEq lhs plan-to-yul"
  let rhs ← requireOk
    (lowerScalarPlanExprOrFallback
      ProofForge.IR.Examples.Counter.module
      env
      (.literal (.u64 1)))
    "scalar assertEq rhs plan-to-yul"
  let assertEqStmt := lowerAssertStmt (Lean.Compiler.Yul.builtin "eq" #[lhs, rhs]) none
  match assertEqStmt with
  | Lean.Compiler.Yul.Statement.ifStmt (Lean.Compiler.Yul.Expr.builtin name args) _ => do
      require (name == "iszero") "scalar assertEq plan-to-yul guard builtin"
      require (args.size == 1) "scalar assertEq plan-to-yul iszero arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.builtin name _ =>
          require (name == "eq") "scalar assertEq plan-to-yul condition builtin"
      | _ => throw <| IO.userError "scalar assertEq plan-to-yul condition must be builtin"
  | _ => throw <| IO.userError "scalar assertEq plan-to-yul must lower to if iszero"

def testScalarReturnPlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "n", type := .u64, isMutable := false }]
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
      require (name == "sload") "storage scalar return plan-to-yul opcode"
      require (args.size == 1) "storage scalar return plan-to-yul arg count"
  | _ => throw <| IO.userError "storage scalar return plan-to-yul must assign sload"

def testScalarAssignmentPlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "n", type := .u64, isMutable := true }]
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
          require (name == "sload") "scalar compound assignment plan-to-yul rhs opcode"
      | _ => throw <| IO.userError "scalar compound assignment plan-to-yul rhs must be sload"
  | _ => throw <| IO.userError "scalar compound assignment plan-to-yul must assign helper result"

def testScalarControlFlowPlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "n", type := .u64, isMutable := true }]
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
        | Lean.Compiler.Yul.Statement.varDecl vars (some (Lean.Compiler.Yul.Expr.builtin "sload" args)) => do
            match vars[0]? with
            | some var =>
                if vars.size == 1 && var.name == "_indexed_topic0" then
                  foundIndexedSload := foundIndexedSload || args.size == 1
            | none => pure ()
        | _ => pure ()
      require foundIndexedSload "scalar indexed event topic must lower storage read through plan"
  | _ => throw <| IO.userError "scalar indexed event topic plan-to-yul must lower to block"

def main : IO UInt32 := do
  testCounterSemanticPlan
  testEventSemanticPlan
  testArtifactMetadata
  testDeployMetadata
  testSemanticPlanRender
  testScalarExprPlanToYul
  testScalarAssertPlanToYul
  testScalarReturnPlanToYul
  testScalarAssignmentPlanToYul
  testScalarControlFlowPlanToYul
  testScalarEventPlanToYul
  IO.println "evm-semantic-plan: ok"
  return 0

end ProofForge.Tests.EvmSemanticPlan

def main : IO UInt32 :=
  ProofForge.Tests.EvmSemanticPlan.main
