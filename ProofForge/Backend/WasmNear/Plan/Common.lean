import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Backend.Diagnostic
import ProofForge.IR.Contract
import ProofForge.Backend.WasmNear.ExprAnalysis

namespace ProofForge.Backend.WasmNear.Plan

open ProofForge.IR
open ProofForge.Backend.WasmNear.ExprAnalysis

structure PlanError where
  message : String
  deriving Repr, Inhabited

def err (message : String) : Except PlanError α :=
  .error { message }

instance : ProofForge.Backend.Diagnostic.LoweringError PlanError where
  toDiagnostic := fun e =>
    { message := e.message, backend? := some "wasm-near" }

inductive ContextExprPlan where
  | userId
  | userIdHash
  | contractId
  | checkpointId
  | timestamp
  | epochHeight
  | randomSeed
  | origin
  deriving BEq, DecidableEq, Repr

def ContextExprPlan.field : ContextExprPlan → ContextField
  | .userId => .userId
  | .userIdHash => .userIdHash
  | .contractId => .contractId
  | .checkpointId => .checkpointId
  | .timestamp => .timestamp
  | .epochHeight => .epochHeight
  | .randomSeed => .randomSeed
  | .origin => .origin

def ContextExprPlan.resultType : ContextExprPlan → ValueType
  | .randomSeed | .userIdHash => .hash
  | _ => .u64

def buildContextExprPlan : ContextField → Except PlanError ContextExprPlan
  | .userId => .ok .userId
  | .userIdHash => .ok .userIdHash
  | .contractId => .ok .contractId
  | .checkpointId => .ok .checkpointId
  | .timestamp => .ok .timestamp
  | .epochHeight => .ok .epochHeight
  | .randomSeed => .ok .randomSeed
  | .origin => .ok .origin
  | .chainId =>
      err "wasm-near context read `chainId` is not supported; supported fields are userId, userIdHash, contractId, checkpointId, timestamp, epochHeight, randomSeed, and origin"
  | .gasPrice =>
      err "wasm-near context read `gasPrice` is not supported; supported fields are userId, userIdHash, contractId, checkpointId, timestamp, epochHeight, randomSeed, and origin"
  | .gasLeft =>
      err "wasm-near context read `gasLeft` is not supported; supported fields are userId, userIdHash, contractId, checkpointId, timestamp, epochHeight, randomSeed, and origin"
  | .baseFee =>
      err "wasm-near context read `baseFee` is not supported; supported fields are userId, userIdHash, contractId, checkpointId, timestamp, epochHeight, randomSeed, and origin"
  | .prevRandao =>
      err "wasm-near context read `prevRandao` is not supported; supported fields are userId, userIdHash, contractId, checkpointId, timestamp, epochHeight, randomSeed, and origin"
  | .coinbase =>
      err "wasm-near context read `coinbase` is not supported; supported fields are userId, userIdHash, contractId, checkpointId, timestamp, epochHeight, randomSeed, and origin"
  | .blockHash _ =>
      err "wasm-near context read `blockHash` is not supported; supported fields are userId, userIdHash, contractId, checkpointId, timestamp, epochHeight, randomSeed, and origin"

def mergeContextExprPlans (acc next : Array ContextExprPlan) : Array ContextExprPlan :=
  next.foldl
    (fun merged item =>
      if merged.contains item then merged else merged.push item)
    acc

def pushValueTypeIfMissing (acc : Array ValueType) (type : ValueType) : Array ValueType :=
  if acc.contains type then acc else acc.push type

def mergeValueTypeSets (acc next : Array ValueType) : Array ValueType :=
  next.foldl pushValueTypeIfMissing acc

def stateTypeOf (module : Module) (stateId : String) : Except PlanError ValueType :=
  match module.state.find? (fun state => state.id == stateId) with
  | some state => .ok state.type
  | none => err s!"wasm-near plan references unknown state `{stateId}`"

def scalarHelperType (type : ValueType) : Option ValueType :=
  match type with
  | .u32 | .u64 | .bool | .hash => some type
  | _ => none

abbrev LocalTypeEnv := Array (String × ValueType)

def lookupLocalType? (env : LocalTypeEnv) (name : String) : Option ValueType :=
  env.foldr (fun binding acc => if binding.fst == name then some binding.snd else acc) none

def findStruct? (module : Module) (name : String) : Option StructDecl :=
  module.structs.find? (fun struct_ => struct_.name == name)

def structFieldTypeOf (module : Module) (structName fieldName : String) : Except PlanError ValueType :=
  match findStruct? module structName with
  | none => err s!"wasm-near plan references unknown struct `{structName}`"
  | some struct_ =>
      match struct_.fields.find? (fun field => field.id == fieldName) with
      | none => err s!"wasm-near plan references unknown struct field `{structName}.{fieldName}`"
      | some field => .ok field.type

mutual
  partial def inferStoragePathType
      (module : Module)
      (env : LocalTypeEnv)
      (stateId : String)
      (path : Array StoragePathSegment) : Except PlanError ValueType := do
    match path.toList with
    | [.mapKey key] => do
        discard <| inferExprType module env key
        stateTypeOf module stateId
    | [.index index] => do
        discard <| inferExprType module env index
        stateTypeOf module stateId
    | [.field fieldName] => do
        match ← stateTypeOf module stateId with
        | .structType structName => structFieldTypeOf module structName fieldName
        | type => err s!"wasm-near plan expected struct storage for `{stateId}`, got `{type.name}`"
    | [.index index, .field fieldName] => do
        discard <| inferExprType module env index
        match ← stateTypeOf module stateId with
        | .structType structName => structFieldTypeOf module structName fieldName
        | type => err s!"wasm-near plan expected struct-valued array storage for `{stateId}`, got `{type.name}`"
    | [.mapKey key1, .mapKey key2] => do
        discard <| inferExprType module env key1
        discard <| inferExprType module env key2
        stateTypeOf module stateId
    | _ =>
        err "wasm-near plan storagePathRead supports mapKey, index, field, index+field, or nested mapKey+mapKey paths"

  partial def inferEffectExprType
      (module : Module)
      (env : LocalTypeEnv)
      (effect : Effect) : Except PlanError ValueType := do
    match effect with
    | .storageScalarRead stateId => stateTypeOf module stateId
    | .storageMapContains stateId key => do
        discard <| inferExprType module env key
        discard <| stateTypeOf module stateId
        .ok .bool
    | .storageMapGet stateId key => do
        discard <| inferExprType module env key
        stateTypeOf module stateId
    | .storageMapInsert stateId key value
    | .storageMapSet stateId key value => do
        discard <| inferExprType module env key
        discard <| inferExprType module env value
        stateTypeOf module stateId
    | .storageArrayRead stateId index => do
        discard <| inferExprType module env index
        stateTypeOf module stateId
    | .storageArrayStructFieldRead stateId index fieldName => do
        discard <| inferExprType module env index
        match ← stateTypeOf module stateId with
        | .structType structName => structFieldTypeOf module structName fieldName
        | type => err s!"wasm-near plan expected struct-valued array storage for `{stateId}`, got `{type.name}`"
    | .storageStructFieldRead stateId fieldName => do
        match ← stateTypeOf module stateId with
        | .structType structName => structFieldTypeOf module structName fieldName
        | type => err s!"wasm-near plan expected struct storage for `{stateId}`, got `{type.name}`"
    | .storagePathRead stateId path =>
        inferStoragePathType module env stateId path
    | .contextRead field =>
        .ok (ContextExprPlan.resultType (← buildContextExprPlan field))
    | .storageScalarWrite _ _
    | .storageScalarAssignOp _ _ _
    | .storageArrayWrite _ _ _
    | .storageArrayStructFieldWrite _ _ _ _
    | .storageDynamicArrayPush _ _
    | .storageDynamicArrayPop _
    | .memoryArraySet _ _ _
    | .storageStructFieldWrite _ _ _
    | .storagePathWrite _ _ _
    | .storagePathAssignOp _ _ _ _
    | .eventEmit _ _
    | .eventEmitIndexed _ _ _ =>
        err "wasm-near plan cannot treat statement-only effects as expression values"

  partial def inferExprType
      (module : Module)
      (env : LocalTypeEnv)
      (expr : Expr) : Except PlanError ValueType := do
    match expr with
    | .literal (.u8 _) => .ok .u8
    | .literal (.u32 _) => .ok .u32
    | .literal (.u64 _) => .ok .u64
    | .literal (.u128 _) => .ok .u128
    | .literal (.address _) => .ok .address
    | .literal (.bool _) => .ok .bool
    | .literal (.hash4 ..) => .ok .hash
    | .local name =>
        match lookupLocalType? env name with
        | some type => .ok type
        | none => err s!"wasm-near plan references unknown local `{name}`"
    | .arrayLit elementType values => do
        for value in values do
          discard <| inferExprType module env value
        .ok (.fixedArray elementType values.size)
    | .arrayGet array index => do
        discard <| inferExprType module env index
        match ← inferExprType module env array with
        | .fixedArray elementType _ => .ok elementType
        | .array elementType => .ok elementType
        | type => err s!"wasm-near plan expected array value, got `{type.name}`"
    | .memoryArrayNew elementType _ => .ok (.array elementType)
    | .memoryArrayLength _ => .ok .u64
    | .memoryArrayGet array index => do
        discard <| inferExprType module env index
        match ← inferExprType module env array with
        | .fixedArray elementType _ => .ok elementType
        | .array elementType => .ok elementType
        | type => err s!"wasm-near plan expected memory array value, got `{type.name}`"
    | .structLit typeName _ => .ok (.structType typeName)
    | .field base fieldName => do
        match ← inferExprType module env base with
        | .structType structName => structFieldTypeOf module structName fieldName
        | type => err s!"wasm-near plan expected struct value, got `{type.name}`"
    | .add lhs rhs _ | .sub lhs rhs _ | .mul lhs rhs _ | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        if lhsType == rhsType then .ok lhsType
        else err s!"wasm-near plan expected matching numeric operands, got `{lhsType.name}`/`{rhsType.name}`"
    | .eq lhs rhs | .ne lhs rhs | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        if lhsType == rhsType then .ok .bool
        else err s!"wasm-near plan expected comparable operands with matching types, got `{lhsType.name}`/`{rhsType.name}`"
    | .boolAnd lhs rhs | .boolOr lhs rhs => do
        discard <| inferExprType module env lhs
        discard <| inferExprType module env rhs
        .ok .bool
    | .boolNot value => do
        discard <| inferExprType module env value
        .ok .bool
    | .cast _ targetType => .ok targetType
    | .hashValue a b c d => do
        discard <| inferExprType module env a
        discard <| inferExprType module env b
        discard <| inferExprType module env c
        discard <| inferExprType module env d
        .ok .hash
    | .hash preimage => do
        discard <| inferExprType module env preimage
        .ok .hash
    | .hashTwoToOne lhs rhs => do
        discard <| inferExprType module env lhs
        discard <| inferExprType module env rhs
        .ok .hash
    | .nativeValue => .ok .u64
    | .crosscallInvoke _ _ _ => .ok .u64
    | .crosscallInvokeTyped _ _ _ returnType => .ok returnType
    | .crosscallInvokeValueTyped _ _ _ _ returnType => .ok returnType
    | .crosscallInvokeStaticTyped _ _ _ returnType => .ok returnType
    | .crosscallInvokeDelegateTyped _ _ _ returnType => .ok returnType
    | .crosscallCreate _ _ => .ok .u64
    | .crosscallCreate2 _ _ _ => .ok .u64
    | .nearCrosscallInvokePool _ _ _ _ => .ok .u64
    | .nearPromiseThen _ _ _ _ => .ok .u64
    | .nearPromiseResultsCount => .ok .u64
    | .nearPromiseResultStatus _ => .ok .u64
    | .nearPromiseResultU64 _ => .ok .u64
    | .effect effect =>
        inferEffectExprType module env effect
end


end ProofForge.Backend.WasmNear.Plan
