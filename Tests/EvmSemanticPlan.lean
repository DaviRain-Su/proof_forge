import ProofForge.Backend.Evm.IR
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.EvmMapProbe
import ProofForge.IR.Examples.EvmStorageArrayProbe
import ProofForge.IR.Examples.EvmStorageStructProbe
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
      require (name == "sload") "scalar let mut statement plan-to-yul integration storage read"
      require (args.size == 1) "scalar let mut statement plan-to-yul integration sload arg count"
  | _ => throw <| IO.userError "scalar let mut statement plan-to-yul integration must lower to var decl"

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

def testScalarStorageEffectPlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "n", type := .u64, isMutable := false }]
  let writeStmt ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.Counter.module
      env
      (.storageScalarWrite "count" (.add (.local "n") (.literal (.u64 1)))))
    "scalar storage write value plan-to-yul"
  match writeStmt with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "scalar storage write plan-to-yul arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call name addArgs => do
          require (name == "__pf_checked_add") "scalar storage write plan-to-yul helper"
          require (addArgs.size == 2) "scalar storage write plan-to-yul helper arg count"
      | _ => throw <| IO.userError "scalar storage write plan-to-yul value must be helper call"
  | _ => throw <| IO.userError "scalar storage write plan-to-yul must lower to sstore"
  let assignOpStmt ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.Counter.module
      env
      (.storageScalarAssignOp "count" .add (.effect (.storageScalarRead "count"))))
    "scalar storage assign_op value plan-to-yul"
  match assignOpStmt with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "scalar storage assign_op plan-to-yul arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call name addArgs => do
          require (name == "__pf_checked_add") "scalar storage assign_op plan-to-yul helper"
          require (addArgs.size == 2) "scalar storage assign_op plan-to-yul helper arg count"
          match addArgs[1]! with
          | Lean.Compiler.Yul.Expr.builtin readName _ =>
              require (readName == "sload") "scalar storage assign_op rhs must be plan-lowered sload"
          | _ => throw <| IO.userError "scalar storage assign_op rhs must be sload"
      | _ => throw <| IO.userError "scalar storage assign_op plan-to-yul value must be helper call"
  | _ => throw <| IO.userError "scalar storage assign_op plan-to-yul must lower to sstore"

def testMapWritePlanToYul : IO Unit := do
  let env : TypeEnv := #[
    { name := "key", type := .u64, isMutable := false },
    { name := "value", type := .u64, isMutable := false }
  ]
  let writeStmt ← requireOk
    (lowerMapWriteStmt
      ProofForge.IR.Examples.EvmMapProbe.module
      env
      "balances"
      (.add (.local "key") (.literal (.u64 1)))
      (.effect (.storageScalarRead "before")))
    "map write key/value plan-to-yul"
  match writeStmt with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.call name args) => do
      require (name == mapWriteFunctionName) "map write plan-to-yul helper"
      require (args.size == 3) "map write plan-to-yul arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "map write key must lower through checked add plan"
          require (addArgs.size == 2) "map write key checked add arg count"
      | _ => throw <| IO.userError "map write key must be plan-lowered checked add"
      match args[2]! with
      | Lean.Compiler.Yul.Expr.builtin readName readArgs => do
          require (readName == "sload") "map write value must lower storage read through plan"
          require (readArgs.size == 1) "map write value sload arg count"
      | _ => throw <| IO.userError "map write value must be plan-lowered storage read"
  | _ => throw <| IO.userError "map write plan-to-yul must lower to helper call"
  let setReturnExpr ← requireOk
    (lowerMapSetReturnExpr
      ProofForge.IR.Examples.EvmMapProbe.module
      env
      "balances"
      (.local "key")
      (.add (.local "value") (.literal (.u64 2))))
    "map set-return value plan-to-yul"
  match setReturnExpr with
  | Lean.Compiler.Yul.Expr.call name args => do
      require (name == mapSetReturnFunctionName) "map set-return plan-to-yul helper"
      require (args.size == 3) "map set-return plan-to-yul arg count"
      match args[2]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "map set-return value must lower through checked add plan"
          require (addArgs.size == 2) "map set-return value checked add arg count"
      | _ => throw <| IO.userError "map set-return value must be plan-lowered checked add"
  | _ => throw <| IO.userError "map set-return plan-to-yul must lower to helper call"

def testArrayWritePlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "value", type := .u64, isMutable := false }]
  let writeStmt ← requireOk
    (lowerArrayWriteStmt
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      env
      "values"
      (.literal (.u64 1))
      (.add (.local "value") (.literal (.u64 3))))
    "array write value plan-to-yul"
  match writeStmt with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "array write plan-to-yul arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "array write value must lower through checked add plan"
          require (addArgs.size == 2) "array write value checked add arg count"
      | _ => throw <| IO.userError "array write value must be plan-lowered checked add"
  | _ => throw <| IO.userError "array write plan-to-yul must lower to sstore"
  let storageValueStmt ← requireOk
    (lowerArrayWriteStmt
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      env
      "values"
      (.literal (.u64 2))
      (.effect (.storageScalarRead "before")))
    "array write storage-read value plan-to-yul"
  match storageValueStmt with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "array write storage-read value arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.builtin readName readArgs => do
          require (readName == "sload") "array write value must lower storage read through plan"
          require (readArgs.size == 1) "array write value sload arg count"
      | _ => throw <| IO.userError "array write value must be plan-lowered storage read"
  | _ => throw <| IO.userError "array write storage-read value must lower to sstore"

def testStructFieldWritePlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "value", type := .u64, isMutable := false }]
  let fieldStmt ← requireOk
    (lowerStructFieldWriteStmt
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      env
      "current"
      "x"
      (.add (.local "value") (.literal (.u64 5))))
    "struct field write value plan-to-yul"
  match fieldStmt with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "struct field write plan-to-yul arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "struct field write value must lower through checked add plan"
          require (addArgs.size == 2) "struct field write checked add arg count"
      | _ => throw <| IO.userError "struct field write value must be plan-lowered checked add"
  | _ => throw <| IO.userError "struct field write plan-to-yul must lower to sstore"
  let arrayFieldStmt ← requireOk
    (lowerStructArrayFieldWriteStmt
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      env
      "points"
      (.literal (.u64 1))
      "y"
      (.effect (.storageScalarRead "before")))
    "struct array field write value plan-to-yul"
  match arrayFieldStmt with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "struct array field write plan-to-yul arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.builtin readName readArgs => do
          require (readName == "sload") "struct array field write value must lower storage read through plan"
          require (readArgs.size == 1) "struct array field write sload arg count"
      | _ => throw <| IO.userError "struct array field write value must be plan-lowered storage read"
  | _ => throw <| IO.userError "struct array field write plan-to-yul must lower to sstore"

def testWholeStructStorageWritePlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "value", type := .u64, isMutable := false }]
  let writeStmt ← requireOk
    (lowerStorageStructWriteStmt
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      env
      "current"
      (.structLit "Point" #[
        ("x", .add (.local "value") (.literal (.u64 7))),
        ("y", .effect (.storageScalarRead "before"))
      ]))
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
                    readName == "sload" &&
                    readArgs.size == 1)
            | none => pure ()
        | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
            if args.size == 2 then
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

def testStoragePathWritePlanToYul : IO Unit := do
  let mapEnv : TypeEnv := #[
    { name := "outer", type := .u64, isMutable := false },
    { name := "inner", type := .u64, isMutable := false },
    { name := "value", type := .u64, isMutable := false }
  ]
  let nestedWriteStmt ← requireOk
    (lowerMapPathWriteStmt
      ProofForge.IR.Examples.EvmMapProbe.module
      mapEnv
      "balances"
      #[.local "outer", .local "inner"]
      (.add (.local "value") (.literal (.u64 9))))
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
  let directMapAssign ← requireOk
    (lowerStoragePathAssignOpStmt
      ProofForge.IR.Examples.EvmMapProbe.module
      mapEnv
      "balances"
      #[.mapKey (.add (.local "outer") (.literal (.u64 1)))]
      .add
      (.effect (.storageScalarRead "before")))
    "direct map storage path assign_op key/value plan-to-yul"
  match directMapAssign with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.call name args) => do
      require (name == mapAssignFunctionName .add) "direct map storage path assign_op helper"
      require (args.size == 3) "direct map storage path assign_op arg count"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "direct map storage path assign_op key must lower through checked add plan"
          require (addArgs.size == 2) "direct map storage path assign_op key checked add arg count"
      | _ => throw <| IO.userError "direct map storage path assign_op key must be plan-lowered checked add"
      match args[2]! with
      | Lean.Compiler.Yul.Expr.builtin readName readArgs => do
          require (readName == "sload") "direct map storage path assign_op value must lower storage read through plan"
          require (readArgs.size == 1) "direct map storage path assign_op value sload arg count"
      | _ => throw <| IO.userError "direct map storage path assign_op value must be plan-lowered storage read"
  | _ => throw <| IO.userError "direct map storage path assign_op plan-to-yul must lower to helper call"
  let nestedMapAssign ← requireOk
    (lowerStoragePathAssignOpStmt
      ProofForge.IR.Examples.EvmMapProbe.module
      mapEnv
      "balances"
      #[.mapKey (.local "outer"), .mapKey (.local "inner")]
      .add
      (.effect (.storageScalarRead "before")))
    "nested map storage path assign_op value plan-to-yul"
  match nestedMapAssign with
  | Lean.Compiler.Yul.Statement.block block => do
      let mut foundStorageReadValue := false
      for stmt in block.statements do
        match stmt with
        | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
            if args.size == 2 then
              match args[0]!, args[1]! with
              | Lean.Compiler.Yul.Expr.ident slotName, Lean.Compiler.Yul.Expr.call addName addArgs =>
                  if slotName == "_slot" && addName == "__pf_checked_add" && addArgs.size == 2 then
                    match addArgs[1]! with
                    | Lean.Compiler.Yul.Expr.builtin readName readArgs =>
                        foundStorageReadValue := foundStorageReadValue ||
                          (readName == "sload" && readArgs.size == 1)
                    | _ => pure ()
              | _, _ => pure ()
        | _ => pure ()
      require foundStorageReadValue "nested map storage path assign_op value must lower storage read through plan"
  | _ => throw <| IO.userError "nested map storage path assign_op plan-to-yul must lower to block"
  let arrayAssign ← requireOk
    (lowerStoragePathAssignOpStmt
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      #[]
      "values"
      #[.index (.literal (.u64 1))]
      .add
      (.effect (.storageScalarRead "before")))
    "array storage path assign_op value plan-to-yul"
  match arrayAssign with
  | Lean.Compiler.Yul.Statement.block block => do
      let mut foundStorageReadValue := false
      for stmt in block.statements do
        match stmt with
        | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
            if args.size == 2 then
              match args[1]! with
              | Lean.Compiler.Yul.Expr.call addName addArgs =>
                  if addName == "__pf_checked_add" && addArgs.size == 2 then
                    match addArgs[1]! with
                    | Lean.Compiler.Yul.Expr.builtin readName readArgs =>
                        foundStorageReadValue := foundStorageReadValue ||
                          (readName == "sload" && readArgs.size == 1)
                    | _ => pure ()
              | _ => pure ()
        | _ => pure ()
      require foundStorageReadValue "array storage path assign_op value must lower storage read through plan"
  | _ => throw <| IO.userError "array storage path assign_op plan-to-yul must lower to block"
  let structEnv : TypeEnv := #[{ name := "value", type := .u64, isMutable := false }]
  let fieldAssign ← requireOk
    (lowerStoragePathAssignOpStmt
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      structEnv
      "current"
      #[.field "x"]
      .add
      (.add (.local "value") (.literal (.u64 2))))
    "struct field storage path assign_op value plan-to-yul"
  match fieldAssign with
  | Lean.Compiler.Yul.Statement.block block => do
      let mut foundCheckedValue := false
      for stmt in block.statements do
        match stmt with
        | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
            if args.size == 2 then
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
    (lowerStoragePathAssignOpStmt
      ProofForge.IR.Examples.EvmStorageStructProbe.module
      #[]
      "points"
      #[.index (.literal (.u64 1)), .field "y"]
      .add
      (.effect (.storageScalarRead "before")))
    "struct-array field storage path assign_op value plan-to-yul"
  match arrayFieldAssign with
  | Lean.Compiler.Yul.Statement.block block => do
      let mut foundStorageReadValue := false
      for stmt in block.statements do
        match stmt with
        | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
            if args.size == 2 then
              match args[1]! with
              | Lean.Compiler.Yul.Expr.call addName addArgs =>
                  if addName == "__pf_checked_add" && addArgs.size == 2 then
                    match addArgs[1]! with
                    | Lean.Compiler.Yul.Expr.builtin readName readArgs =>
                        foundStorageReadValue := foundStorageReadValue ||
                          (readName == "sload" && readArgs.size == 1)
                    | _ => pure ()
              | _ => pure ()
        | _ => pure ()
      require foundStorageReadValue "struct-array field storage path assign_op value must lower storage read through plan"
  | _ => throw <| IO.userError "struct-array field storage path assign_op plan-to-yul must lower to block"

def main : IO UInt32 := do
  testCounterSemanticPlan
  testEventSemanticPlan
  testERC20StandardEventSignatureTypes
  testArtifactMetadata
  testDeployMetadata
  testSemanticPlanRender
  testScalarExprPlanToYul
  testScalarAssertPlanToYul
  testScalarReturnPlanToYul
  testScalarBindingStmtPlanToYul
  testScalarAssignmentPlanToYul
  testScalarControlFlowPlanToYul
  testScalarEventPlanToYul
  testScalarStorageEffectPlanToYul
  testMapWritePlanToYul
  testArrayWritePlanToYul
  testStructFieldWritePlanToYul
  testWholeStructStorageWritePlanToYul
  testStoragePathWritePlanToYul
  IO.println "evm-semantic-plan: ok"
  return 0

end ProofForge.Tests.EvmSemanticPlan

def main : IO UInt32 :=
  ProofForge.Tests.EvmSemanticPlan.main
