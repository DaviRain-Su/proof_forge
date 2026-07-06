import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Contract

namespace ProofForge.Backend.WasmNear.Plan

open ProofForge.IR

structure PlanError where
  message : String
  deriving Repr, Inhabited

def err (message : String) : Except PlanError α :=
  .error { message }

inductive ContextExprPlan where
  | userId
  | contractId
  | checkpointId
  | timestamp
  | epochHeight
  | randomSeed
  | origin
  deriving BEq, DecidableEq, Repr

def ContextExprPlan.field : ContextExprPlan → ContextField
  | .userId => .userId
  | .contractId => .contractId
  | .checkpointId => .checkpointId
  | .timestamp => .timestamp
  | .epochHeight => .epochHeight
  | .randomSeed => .randomSeed
  | .origin => .origin

def ContextExprPlan.resultType : ContextExprPlan → ValueType
  | .randomSeed => .hash
  | _ => .u64

def buildContextExprPlan : ContextField → Except PlanError ContextExprPlan
  | .userId => .ok .userId
  | .contractId => .ok .contractId
  | .checkpointId => .ok .checkpointId
  | .timestamp => .ok .timestamp
  | .epochHeight => .ok .epochHeight
  | .randomSeed => .ok .randomSeed
  | .origin => .ok .origin
  | .chainId =>
      err "wasm-near context read `chainId` is not supported; supported fields are userId, contractId, checkpointId, timestamp, epochHeight, randomSeed, and origin"
  | .gasPrice =>
      err "wasm-near context read `gasPrice` is not supported; supported fields are userId, contractId, checkpointId, timestamp, epochHeight, randomSeed, and origin"
  | .gasLeft =>
      err "wasm-near context read `gasLeft` is not supported; supported fields are userId, contractId, checkpointId, timestamp, epochHeight, randomSeed, and origin"
  | .baseFee =>
      err "wasm-near context read `baseFee` is not supported; supported fields are userId, contractId, checkpointId, timestamp, epochHeight, randomSeed, and origin"
  | .prevRandao =>
      err "wasm-near context read `prevRandao` is not supported; supported fields are userId, contractId, checkpointId, timestamp, epochHeight, randomSeed, and origin"
  | .coinbase =>
      err "wasm-near context read `coinbase` is not supported; supported fields are userId, contractId, checkpointId, timestamp, epochHeight, randomSeed, and origin"
  | .blockHash _ =>
      err "wasm-near context read `blockHash` is not supported; supported fields are userId, contractId, checkpointId, timestamp, epochHeight, randomSeed, and origin"

def mergeContextExprPlans (acc next : Array ContextExprPlan) : Array ContextExprPlan :=
  next.foldl
    (fun merged item =>
      if merged.contains item then merged else merged.push item)
    acc

mutual
  partial def contextOpsFromExpr (expr : Expr) : Except PlanError (Array ContextExprPlan) :=
    match expr with
    | .literal _ | .local _ | .nativeValue => .ok #[]
    | .arrayLit _ values =>
        values.foldlM (init := #[]) fun acc value =>
          return mergeContextExprPlans acc (← contextOpsFromExpr value)
    | .arrayGet array index =>
        return mergeContextExprPlans (← contextOpsFromExpr array) (← contextOpsFromExpr index)
    | .memoryArrayNew _ length =>
        contextOpsFromExpr length
    | .memoryArrayLength array =>
        contextOpsFromExpr array
    | .memoryArrayGet array index =>
        return mergeContextExprPlans (← contextOpsFromExpr array) (← contextOpsFromExpr index)
    | .structLit _ fields =>
        fields.foldlM (init := #[]) fun acc field =>
          return mergeContextExprPlans acc (← contextOpsFromExpr field.snd)
    | .field base _ =>
        contextOpsFromExpr base
    | .add lhs rhs | .sub lhs rhs | .mul lhs rhs | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs =>
        return mergeContextExprPlans (← contextOpsFromExpr lhs) (← contextOpsFromExpr rhs)
    | .cast value _ | .boolNot value | .hash value =>
        contextOpsFromExpr value
    | .hashValue a b c d =>
        return mergeContextExprPlans
          (mergeContextExprPlans (← contextOpsFromExpr a) (← contextOpsFromExpr b))
          (mergeContextExprPlans (← contextOpsFromExpr c) (← contextOpsFromExpr d))
    | .crosscallInvoke target methodId args
    | .crosscallInvokeTyped target methodId args _
    | .crosscallInvokeStaticTyped target methodId args _
    | .crosscallInvokeDelegateTyped target methodId args _ => do
        let base :=
          mergeContextExprPlans (← contextOpsFromExpr target) (← contextOpsFromExpr methodId)
        args.foldlM (init := base) fun acc arg =>
          return mergeContextExprPlans acc (← contextOpsFromExpr arg)
    | .crosscallInvokeValueTyped target methodId callValue args _ => do
        let base :=
          mergeContextExprPlans
            (mergeContextExprPlans (← contextOpsFromExpr target) (← contextOpsFromExpr methodId))
            (← contextOpsFromExpr callValue)
        args.foldlM (init := base) fun acc arg =>
          return mergeContextExprPlans acc (← contextOpsFromExpr arg)
    | .crosscallCreate callValue _ =>
        contextOpsFromExpr callValue
    | .crosscallCreate2 callValue salt _ =>
        return mergeContextExprPlans (← contextOpsFromExpr callValue) (← contextOpsFromExpr salt)
    | .effect effect =>
        contextOpsFromEffect effect

  partial def contextOpsFromEffect (effect : Effect) : Except PlanError (Array ContextExprPlan) :=
    match effect with
    | .storageScalarRead _ => .ok #[]
    | .storageScalarWrite _ value | .storageScalarAssignOp _ _ value =>
        contextOpsFromExpr value
    | .storageMapContains _ key | .storageMapGet _ key =>
        contextOpsFromExpr key
    | .storageMapInsert _ key value | .storageMapSet _ key value =>
        return mergeContextExprPlans (← contextOpsFromExpr key) (← contextOpsFromExpr value)
    | .storageArrayRead _ index | .storageArrayStructFieldRead _ index _ =>
        contextOpsFromExpr index
    | .storageArrayWrite _ index value =>
        return mergeContextExprPlans (← contextOpsFromExpr index) (← contextOpsFromExpr value)
    | .storageArrayStructFieldWrite _ index _ value =>
        return mergeContextExprPlans (← contextOpsFromExpr index) (← contextOpsFromExpr value)
    | .storageDynamicArrayPush _ value =>
        contextOpsFromExpr value
    | .storageDynamicArrayPop _ =>
        .ok #[]
    | .memoryArraySet array index value =>
        return mergeContextExprPlans
          (mergeContextExprPlans (← contextOpsFromExpr array) (← contextOpsFromExpr index))
          (← contextOpsFromExpr value)
    | .storageStructFieldRead _ _ => .ok #[]
    | .storageStructFieldWrite _ _ value =>
        contextOpsFromExpr value
    | .storagePathRead _ path =>
        contextOpsFromPath path
    | .storagePathWrite _ path value | .storagePathAssignOp _ path _ value =>
        return mergeContextExprPlans (← contextOpsFromPath path) (← contextOpsFromExpr value)
    | .contextRead field =>
        return #[← buildContextExprPlan field]
    | .eventEmit _ fields =>
        fields.foldlM (init := #[]) fun acc field =>
          return mergeContextExprPlans acc (← contextOpsFromExpr field.snd)
    | .eventEmitIndexed _ indexedFields dataFields => do
        let indexed ← indexedFields.foldlM (init := #[]) fun acc field =>
          return mergeContextExprPlans acc (← contextOpsFromExpr field.snd)
        dataFields.foldlM (init := indexed) fun acc field =>
          return mergeContextExprPlans acc (← contextOpsFromExpr field.snd)

  partial def contextOpsFromPath (path : Array StoragePathSegment) :
      Except PlanError (Array ContextExprPlan) :=
    path.foldlM (init := #[]) fun acc segment =>
      match segment with
      | .field _ => pure acc
      | .index index | .mapKey index =>
          return mergeContextExprPlans acc (← contextOpsFromExpr index)

  partial def contextOpsFromStatement (statement : Statement) :
      Except PlanError (Array ContextExprPlan) :=
    match statement with
    | .letBind _ _ value | .letMutBind _ _ value =>
        contextOpsFromExpr value
    | .assign target value | .assignOp target _ value =>
        return mergeContextExprPlans (← contextOpsFromExpr target) (← contextOpsFromExpr value)
    | .effect effect =>
        contextOpsFromEffect effect
    | .assert condition _ _ =>
        contextOpsFromExpr condition
    | .assertEq lhs rhs _ _ =>
        return mergeContextExprPlans (← contextOpsFromExpr lhs) (← contextOpsFromExpr rhs)
    | .revert _ | .revertWithError _ | .release _ =>
        .ok #[]
    | .ifElse condition thenBody elseBody =>
        return mergeContextExprPlans
          (mergeContextExprPlans (← contextOpsFromExpr condition) (← contextOpsFromStatements thenBody))
          (← contextOpsFromStatements elseBody)
    | .boundedFor _ _ _ body =>
        contextOpsFromStatements body
    | .whileLoop condition body =>
        return mergeContextExprPlans (← contextOpsFromExpr condition) (← contextOpsFromStatements body)
    | .return value =>
        contextOpsFromExpr value

  partial def contextOpsFromStatements (statements : Array Statement) :
      Except PlanError (Array ContextExprPlan) :=
    statements.foldlM (init := #[]) fun acc statement =>
      return mergeContextExprPlans acc (← contextOpsFromStatement statement)
end

def contextOpsFromModule (module : Module) : Except PlanError (Array ContextExprPlan) :=
  module.entrypoints.foldlM (init := #[]) fun acc entrypoint =>
    return mergeContextExprPlans acc (← contextOpsFromStatements entrypoint.body)

structure ModulePlan where
  contextOps : Array ContextExprPlan
  deriving Repr

def buildModulePlan (module : Module) : Except PlanError ModulePlan := do
  .ok { contextOps := ← contextOpsFromModule module }

end ProofForge.Backend.WasmNear.Plan
