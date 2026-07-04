import ProofForge.Backend.Evm.IR
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.EvmArrayValueProbe
import ProofForge.IR.Examples.EvmDynamicAbiProbe
import ProofForge.IR.Examples.EvmCrosscallProbe
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

def requireIdentExpr
    (expr : Lean.Compiler.Yul.Expr)
    (expectedName : String)
    (label : String) : IO Unit := do
  match expr with
  | Lean.Compiler.Yul.Expr.ident name =>
      require (name == expectedName) s!"{label} local name"
  | _ => throw <| IO.userError s!"{label} must lower to local identifier"

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
  require (get.returns.localNames == #["result"]) "counter plan get return local names"
  let getReturnTypedNames := ProofForge.Backend.Evm.ToYul.returnTypedNames get.returns
  require (getReturnTypedNames.size == 1) "counter plan get typed return count"
  match getReturnTypedNames[0]? with
  | some returnName => require (returnName.name == "result") "counter plan get typed return name"
  | none => throw <| IO.userError "counter plan get missing typed return"
  require (get.body.size == 1) "counter plan get body size"
  match ← requireAt get.body 0 "counter plan get missing body" with
  | .return (.effect (.storageScalarRead stateId)) =>
      require (stateId == "count") "counter plan get return read state"
  | _ => throw <| IO.userError "counter plan get body must return storage scalar read"
  let storageCount ← requireSome (plan.storage.find? "count") "counter plan missing count storage"
  require (storageCount.slot == 0) "counter plan count slot"
  require (storageCount.span == 0) "counter plan count span (packed scalar has zero span)"
  require (plan.usesCheckedArithmetic == true) "counter plan checked arithmetic (increment uses add)"
  require (plan.creates.size == 0) "counter plan no creates"
  require (plan.dispatch.entrypoints.size == plan.entrypoints.size) "counter plan dispatch entrypoint count"
  require (plan.dispatch.default == .revert) "counter plan dispatch default"

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

def testPlannedHelperDiscoveryToYul : IO Unit := do
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
  require
    (lowerPlan.usesCheckedArithmetic == plan.usesCheckedArithmetic)
    "checked arithmetic discovery must come from Lower.buildFullModulePlan"
  require
    (plan.localArrayGetLengths.contains 3)
    "array value probe must plan length-3 dynamic local-array getter"
  require
    (plan.localArrayGetLengths.contains 2)
    "array value probe must plan length-2 dynamic local-array getter"
  require
    (plan.nestedLocalArrayGetShapes.any (fun shape => shape == #[2, 2]))
    "array value probe must plan nested 2x2 dynamic local-array getter"
  require
    plan.usesCheckedArithmetic
    "array value probe must plan checked arithmetic helpers"

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

def testScalarExprPlanToYul : IO Unit := do
  let scalarEnv : TypeEnv := #[
    { name := "target", type := .u64, isMutable := false },
    { name := "amount", type := .u64, isMutable := false },
    { name := "salt", type := .hash, isMutable := false }
  ]
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
  let crosscallPlanExpr ← requireOk
    (lowerExprPlanExpr
      ProofForge.IR.Examples.Counter.module
      scalarEnv
      (.crosscall
        ProofForge.Backend.Evm.Plan.CrosscallMode.call
        (.local "target")
        (.literalWord 305419896)
        none
        #[.local "amount"]
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
      require (args.size == 1) "local aggregate crosscall argument plan word group count"
      let argPlan ← requireAt args 0 "local aggregate crosscall argument missing plan"
      match argPlan with
      | .localCrosscallWords name type => do
          require (name == "p") "local aggregate crosscall argument plan local name"
          require (type == .structType "Point") "local aggregate crosscall argument plan type"
      | _ => throw <| IO.userError "local aggregate crosscall argument must use localCrosscallWords plan"
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
      require (args.size == 1) "storage-backed aggregate crosscall argument plan word group count"
      let argPlan ← requireAt args 0 "storage-backed aggregate crosscall argument missing plan"
      match argPlan with
      | .storageCrosscallWords stateId type => do
          require (stateId == "current") "storage-backed aggregate crosscall argument plan state id"
          require (type == .structType "Point") "storage-backed aggregate crosscall argument plan type"
      | _ => throw <| IO.userError "storage-backed aggregate crosscall argument must use storageCrosscallWords plan"
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
      requireLiteralWordPlan (← requireAt args 0 "struct literal aggregate crosscall argument missing x word") 4
        "struct literal aggregate crosscall argument x word"
      requireLiteralWordPlan (← requireAt args 1 "struct literal aggregate crosscall argument missing y word") 6
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
      requireLiteralWordPlan (← requireAt args 0 "array literal aggregate crosscall argument missing element 0 word") 5
        "array literal aggregate crosscall argument element 0 word"
      requireLiteralWordPlan (← requireAt args 1 "array literal aggregate crosscall argument missing element 1 word") 8
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
      requireLiteralWordPlan (← requireAt args 0 "nested array literal aggregate crosscall argument missing word 0") 1
        "nested array literal aggregate crosscall argument word 0"
      requireLiteralWordPlan (← requireAt args 1 "nested array literal aggregate crosscall argument missing word 1") 2
        "nested array literal aggregate crosscall argument word 1"
      requireLiteralWordPlan (← requireAt args 2 "nested array literal aggregate crosscall argument missing word 2") 3
        "nested array literal aggregate crosscall argument word 2"
      requireLiteralWordPlan (← requireAt args 3 "nested array literal aggregate crosscall argument missing word 3") 4
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
      requireLiteralWordPlan (← requireAt args 0 "struct-array literal aggregate crosscall argument missing flag 0 word") 1
        "struct-array literal aggregate crosscall argument flag 0 word"
      requireLiteralWordPlan (← requireAt args 1 "struct-array literal aggregate crosscall argument missing small 0 word") 7
        "struct-array literal aggregate crosscall argument small 0 word"
      requireLiteralWordPlan (← requireAt args 2 "struct-array literal aggregate crosscall argument missing flag 1 word") 0
        "struct-array literal aggregate crosscall argument flag 1 word"
      requireLiteralWordPlan (← requireAt args 3 "struct-array literal aggregate crosscall argument missing small 1 word") 9
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
  let directDynamicStructArrayFieldExpr ← requireOk
    (lowerExpr
      ProofForge.IR.Examples.EvmStructArrayValueProbe.module
      structArrayEnv
      (.field (.arrayGet (.local "people") (.local "idx")) "score"))
    "direct dynamic local struct-array field read lowers through ToYul"
  requireCallExpr
    directDynamicStructArrayFieldExpr
    "__proof_forge_local_array_get_2"
    3
    "direct dynamic local struct-array field read ToYul"
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
    "compat local ABI struct words ToYul"
  require (loweredStructWords.size == 2) "compat local ABI struct words count"
  requireIdentExpr loweredStructWords[0]! "__proof_forge_struct_p_x" "compat local ABI struct word 0"
  requireIdentExpr loweredStructWords[1]! "__proof_forge_struct_p_y" "compat local ABI struct word 1"
  let arrayEnv : TypeEnv := #[
    { name := "xs", type := .fixedArray .u64 3, isMutable := false }
  ]
  let loweredArrayWords ← requireOk
    (lowerLocalAbiWords
      ProofForge.IR.Examples.EvmArrayValueProbe.module
      arrayEnv
      "entrypoint `array` return value"
      "xs"
      (.fixedArray .u64 3))
    "compat local ABI fixed-array words ToYul"
  require (loweredArrayWords.size == 3) "compat local ABI fixed-array words count"
  requireIdentExpr loweredArrayWords[0]! "__proof_forge_array_xs_0" "compat local ABI fixed-array word 0"
  requireIdentExpr loweredArrayWords[1]! "__proof_forge_array_xs_1" "compat local ABI fixed-array word 1"
  requireIdentExpr loweredArrayWords[2]! "__proof_forge_array_xs_2" "compat local ABI fixed-array word 2"

def testLocalCrosscallWordsToYul : IO Unit := do
  let simpleStructFields (typeName : String) : Except LowerError (Array String) :=
    if typeName == "Point" then
      .ok #["x", "y"]
    else
      .error { message := s!"unknown struct `{typeName}`" }
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
  let structEnv : TypeEnv := #[
    { name := "p", type := .structType "Point", isMutable := false }
  ]
  let loweredStructWords ← requireOk
    (lowerLocalCrosscallWords
      ProofForge.IR.Examples.EvmStructValueProbe.module
      structEnv
      "crosscall argument"
      "p"
      (.structType "Point"))
    "compat local crosscall struct words ToYul"
  require (loweredStructWords.size == 2) "compat local crosscall struct words count"
  requireIdentExpr loweredStructWords[0]! "__proof_forge_struct_p_x" "compat local crosscall struct word 0"
  requireIdentExpr loweredStructWords[1]! "__proof_forge_struct_p_y" "compat local crosscall struct word 1"
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
    "compat local crosscall fixed-array words ToYul"
  require (loweredArrayWords.size == 3) "compat local crosscall fixed-array words count"
  requireIdentExpr loweredArrayWords[0]! "__proof_forge_array_xs_0" "compat local crosscall fixed-array word 0"
  requireIdentExpr loweredArrayWords[1]! "__proof_forge_array_xs_1" "compat local crosscall fixed-array word 1"
  requireIdentExpr loweredArrayWords[2]! "__proof_forge_array_xs_2" "compat local crosscall fixed-array word 2"

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
  let dynamicStmts ← requireOk
    (lowerAssignStmt
      ProofForge.IR.Examples.Counter.module
      env
      (.arrayGet (.local "xs") (.local "idx"))
      (.literal (.u64 7)))
    "dynamic local fixed-array assignment integration"
  require (dynamicStmts.size == 1) "dynamic local fixed-array assignment integration statement count"
  match dynamicStmts[0]! with
  | Lean.Compiler.Yul.Statement.block block => do
      require (block.statements.size == 3) "dynamic local fixed-array assignment integration frame count"
      match block.statements[2]! with
      | Lean.Compiler.Yul.Statement.switchStmt (Lean.Compiler.Yul.Expr.ident switchName) cases => do
          require (switchName == "__proof_forge_array_index") "dynamic local fixed-array assignment integration switch index"
          require (cases.size == 3) "dynamic local fixed-array assignment integration case count"
      | _ => throw <| IO.userError "dynamic local fixed-array assignment integration must switch on planned index"
  | _ => throw <| IO.userError "dynamic local fixed-array assignment integration must lower to ToYul frame"

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

def testScalarControlFlowPlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "n", type := .u64, isMutable := true }]
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
      require (name == mapWriteFunctionName) "map write StmtPlan-to-Yul helper call"
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
      require (name == mapWriteFunctionName) "map insert StmtPlan-to-Yul helper call"
      require (args.size == 3) "map insert StmtPlan-to-Yul helper arg count"
  | _ => throw <| IO.userError "map insert StmtPlan-to-Yul helper must lower to helper call"
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
      require (name == mapWriteFunctionName) "map write plan-to-yul helper"
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
  let directWriteStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.arrayWriteEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module env)
      (fun _ index => do
        .ok (Lean.Compiler.Yul.call arraySlotFunctionName #[
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
          require (slotName == arraySlotFunctionName) "array write StmtPlan-to-Yul helper slot call"
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
  let writeStmt ← requireOk
    (lowerEffectStmt
      ProofForge.IR.Examples.EvmStorageArrayProbe.module
      env
      (.storageArrayWrite
        "values"
        (.literal (.u64 1))
        (.add (.local "value") (.literal (.u64 3)))))
    "array write value plan-to-yul"
  match writeStmt with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "array write plan-to-yul arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.call slotName slotArgs => do
          require (slotName == arraySlotFunctionName) "array write plan-to-yul slot call"
          require (slotArgs.size == 3) "array write plan-to-yul slot arg count"
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

def testStructFieldWritePlanToYul : IO Unit := do
  let env : TypeEnv := #[{ name := "value", type := .u64, isMutable := false }]
  let directFieldStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.structFieldWriteEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageStructProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageStructProbe.module env)
      (fun _ _ => .ok (Lean.Compiler.Yul.Expr.num 2))
      (fun _ index _ => do
        .ok (Lean.Compiler.Yul.call structArraySlotFunctionName #[
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
  let directArrayFieldStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.structFieldWriteEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageStructProbe.module env expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageStructProbe.module env)
      (fun _ _ => .ok (Lean.Compiler.Yul.Expr.num 2))
      (fun _ index _ => do
        .ok (Lean.Compiler.Yul.call structArraySlotFunctionName #[
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
          require (slotName == structArraySlotFunctionName) "struct array field write StmtPlan-to-Yul helper slot call"
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
          require (slotName == structArraySlotFunctionName) "struct array field write plan-to-yul slot call"
          require (slotArgs.size == 5) "struct array field write plan-to-yul slot arg count"
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

def testStoragePathWritePlanToYul : IO Unit := do
  let arrayEnv : TypeEnv := #[{ name := "value", type := .u64, isMutable := false }]
  let directWriteStmts ← requireOk
    (ProofForge.Backend.Evm.ToYul.storagePathWriteEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module arrayEnv expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module arrayEnv)
      (fun _ _ => .ok (.singleSlot (Lean.Compiler.Yul.Expr.num 9)))
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect
        (.storagePathWrite
          "values"
          #[.index (.literal (.u64 0))]
          (.checkedArith .add (.local "value") (.literalWord 4)))))
    "storage path write StmtPlan-to-Yul helper"
  require (directWriteStmts.size == 1) "storage path write StmtPlan-to-Yul helper statement count"
  match directWriteStmts[0]! with
  | Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.Expr.builtin "sstore" args) => do
      require (args.size == 2) "storage path write StmtPlan-to-Yul helper arg count"
      match args[0]! with
      | Lean.Compiler.Yul.Expr.lit lit =>
          require (lit.value == "9") "storage path write StmtPlan-to-Yul helper slot"
      | _ => throw <| IO.userError "storage path write StmtPlan-to-Yul helper slot must be literal"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "storage path write StmtPlan-to-Yul helper checked add"
          require (addArgs.size == 2) "storage path write StmtPlan-to-Yul helper checked add arg count"
      | _ => throw <| IO.userError "storage path write StmtPlan-to-Yul helper value must be checked add"
  | _ => throw <| IO.userError "storage path write StmtPlan-to-Yul helper must lower to sstore"
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
          require (slotName == arraySlotFunctionName) "array storage path write plan-to-yul slot call"
          require (slotArgs.size == 3) "array storage path write plan-to-yul slot arg count"
      | _ => throw <| IO.userError "array storage path write plan-to-yul slot must use array helper"
      match args[1]! with
      | Lean.Compiler.Yul.Expr.call addName addArgs => do
          require (addName == "__pf_checked_add") "array storage path write value must lower through checked add plan"
          require (addArgs.size == 2) "array storage path write value checked add arg count"
      | _ => throw <| IO.userError "array storage path write value must be plan-lowered checked add"
  | _ => throw <| IO.userError "array storage path write plan-to-yul must lower to sstore"
  let mapEnv : TypeEnv := #[
    { name := "outer", type := .u64, isMutable := false },
    { name := "inner", type := .u64, isMutable := false },
    { name := "value", type := .u64, isMutable := false }
  ]
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
    (ProofForge.Backend.Evm.ToYul.storagePathAssignOpEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module arrayEnv expr)
      (lowerPlanEffectExpr ProofForge.IR.Examples.EvmStorageArrayProbe.module arrayEnv)
      (fun _ _ => .ok (.singleSlot (Lean.Compiler.Yul.Expr.num 9)))
      (ProofForge.Backend.Evm.Plan.StmtPlan.effect
        (.storagePathAssignOp
          "values"
          #[.index (.literal (.u64 0))]
          .add
          (.effect (.storageScalarRead "before")))))
    "storage path assign_op StmtPlan-to-Yul helper"
  require (directAssignOpStmts.size == 1) "storage path assign_op StmtPlan-to-Yul helper statement count"
  match directAssignOpStmts[0]! with
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
                          (readName == "and" && readArgs.size == 2)
                    | _ => pure ()
              | _ => pure ()
        | _ => pure ()
      require foundStorageReadValue "storage path assign_op StmtPlan-to-Yul helper value must lower storage read through plan"
  | _ => throw <| IO.userError "storage path assign_op StmtPlan-to-Yul helper must lower to block"
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
      require (name == mapAssignFunctionName .add) "direct map storage path assign_op helper"
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

def main : IO UInt32 := do
  testCounterSemanticPlan
  testEventSemanticPlan
  testERC20StandardEventSignatureTypes
  testArtifactMetadata
  testDeployMetadata
  testPlannedHelperDiscoveryToYul
  testLocalArrayHelperDiscoveryInLowerPlan
  testEntrypointDispatchPlanToYul
  testSemanticPlanRender
  testScalarExprPlanToYul
  testLocalAbiWordsToYul
  testLocalCrosscallWordsToYul
  testAggregateAssignmentPlanToYul
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
