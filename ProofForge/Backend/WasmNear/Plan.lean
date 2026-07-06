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

inductive IndexedStorageHelperKeyKind where
  | u64
  | hash
  deriving BEq, DecidableEq, Repr

structure IndexedStorageHelperSurface where
  keyKind : IndexedStorageHelperKeyKind
  valueType : ValueType
  deriving BEq, DecidableEq, Repr

def indexedStorageHelperSurfaceOfState (module : Module) (stateId : String) :
    Except PlanError (Option IndexedStorageHelperSurface) :=
  match module.state.find? (fun state => state.id == stateId) with
  | none =>
      err s!"wasm-near plan references unknown state `{stateId}`"
  | some state =>
      match state.kind with
      | .map keyType _ =>
          match keyType with
          | .u64 => .ok (some { keyKind := .u64, valueType := state.type })
          | .hash => .ok (some { keyKind := .hash, valueType := state.type })
          | _ => .ok none
      | .array _ =>
          .ok (some { keyKind := .u64, valueType := state.type })
      | .scalar | .dynamicArray =>
          .ok none

structure ModuleSurface where
  contextOps : Array ContextExprPlan := #[]
  scalarReadTypes : Array ValueType := #[]
  scalarWriteTypes : Array ValueType := #[]
  returnTypes : Array ValueType := #[]
  usesNativeValue : Bool := false
  usesStorageRead : Bool := false
  usesStorageWrite : Bool := false
  usesPromiseApi : Bool := false
  u64IndexedReadTypes : Array ValueType := #[]
  u64IndexedWriteTypes : Array ValueType := #[]
  hashIndexedReadTypes : Array ValueType := #[]
  hashIndexedWriteTypes : Array ValueType := #[]
  usesU64IndexedBuildKey : Bool := false
  usesHashIndexedBuildKey : Bool := false
  usesU64IndexedContains : Bool := false
  usesHashIndexedContains : Bool := false
  deriving Repr

def mergeModuleSurfaces (lhs rhs : ModuleSurface) : ModuleSurface := {
  contextOps := mergeContextExprPlans lhs.contextOps rhs.contextOps
  scalarReadTypes := mergeValueTypeSets lhs.scalarReadTypes rhs.scalarReadTypes
  scalarWriteTypes := mergeValueTypeSets lhs.scalarWriteTypes rhs.scalarWriteTypes
  returnTypes := mergeValueTypeSets lhs.returnTypes rhs.returnTypes
  usesNativeValue := lhs.usesNativeValue || rhs.usesNativeValue
  usesStorageRead := lhs.usesStorageRead || rhs.usesStorageRead
  usesStorageWrite := lhs.usesStorageWrite || rhs.usesStorageWrite
  usesPromiseApi := lhs.usesPromiseApi || rhs.usesPromiseApi
  u64IndexedReadTypes := mergeValueTypeSets lhs.u64IndexedReadTypes rhs.u64IndexedReadTypes
  u64IndexedWriteTypes := mergeValueTypeSets lhs.u64IndexedWriteTypes rhs.u64IndexedWriteTypes
  hashIndexedReadTypes := mergeValueTypeSets lhs.hashIndexedReadTypes rhs.hashIndexedReadTypes
  hashIndexedWriteTypes := mergeValueTypeSets lhs.hashIndexedWriteTypes rhs.hashIndexedWriteTypes
  usesU64IndexedBuildKey := lhs.usesU64IndexedBuildKey || rhs.usesU64IndexedBuildKey
  usesHashIndexedBuildKey := lhs.usesHashIndexedBuildKey || rhs.usesHashIndexedBuildKey
  usesU64IndexedContains := lhs.usesU64IndexedContains || rhs.usesU64IndexedContains
  usesHashIndexedContains := lhs.usesHashIndexedContains || rhs.usesHashIndexedContains
}

namespace ModuleSurface

def empty : ModuleSurface := {}

def withContext (plan : ContextExprPlan) : ModuleSurface := {
  contextOps := #[plan]
}

def withScalarReadType (type : ValueType) : ModuleSurface := {
  scalarReadTypes := #[type]
}

def withScalarWriteType (type : ValueType) : ModuleSurface := {
  scalarWriteTypes := #[type]
}

def withReturnType (type : ValueType) : ModuleSurface :=
  match type with
  | .u32 | .u64 | .bool | .hash => { returnTypes := #[type] }
  | _ => empty

def withNativeValue : ModuleSurface := {
  usesNativeValue := true
}

def withStorageRead : ModuleSurface := {
  usesStorageRead := true
}

def withStorageWrite : ModuleSurface := {
  usesStorageWrite := true
}

def withPromiseApi : ModuleSurface := {
  usesPromiseApi := true
}

def withU64IndexedBuildKey : ModuleSurface := {
  usesU64IndexedBuildKey := true
}

def withHashIndexedBuildKey : ModuleSurface := {
  usesHashIndexedBuildKey := true
}

def withU64IndexedReadType (type : ValueType) : ModuleSurface := {
  usesU64IndexedBuildKey := true
  u64IndexedReadTypes := #[type]
}

def withU64IndexedWriteType (type : ValueType) : ModuleSurface := {
  usesU64IndexedBuildKey := true
  u64IndexedWriteTypes := #[type]
}

def withHashIndexedReadType (type : ValueType) : ModuleSurface := {
  usesHashIndexedBuildKey := true
  hashIndexedReadTypes := #[type]
}

def withHashIndexedWriteType (type : ValueType) : ModuleSurface := {
  usesHashIndexedBuildKey := true
  hashIndexedWriteTypes := #[type]
}

def withU64IndexedContains : ModuleSurface := {
  usesU64IndexedBuildKey := true
  usesU64IndexedContains := true
}

def withHashIndexedContains : ModuleSurface := {
  usesHashIndexedBuildKey := true
  usesHashIndexedContains := true
}

end ModuleSurface

def indexedStorageReadSurfaceSummary
    (module : Module)
    (stateId : String) : Except PlanError ModuleSurface := do
  match ← indexedStorageHelperSurfaceOfState module stateId with
  | some surface =>
      match surface.keyKind, scalarHelperType surface.valueType with
      | .u64, some type => .ok (ModuleSurface.withU64IndexedReadType type)
      | .u64, none => .ok ModuleSurface.withU64IndexedBuildKey
      | .hash, some type => .ok (ModuleSurface.withHashIndexedReadType type)
      | .hash, none => .ok ModuleSurface.withHashIndexedBuildKey
  | none => .ok ModuleSurface.empty

def indexedStorageWriteSurfaceSummary
    (module : Module)
    (stateId : String) : Except PlanError ModuleSurface := do
  match ← indexedStorageHelperSurfaceOfState module stateId with
  | some surface =>
      match surface.keyKind, scalarHelperType surface.valueType with
      | .u64, some type => .ok (ModuleSurface.withU64IndexedWriteType type)
      | .u64, none => .ok ModuleSurface.withU64IndexedBuildKey
      | .hash, some type => .ok (ModuleSurface.withHashIndexedWriteType type)
      | .hash, none => .ok ModuleSurface.withHashIndexedBuildKey
  | none => .ok ModuleSurface.empty

def indexedStorageContainsSurfaceSummary
    (module : Module)
    (stateId : String) : Except PlanError ModuleSurface := do
  match ← indexedStorageHelperSurfaceOfState module stateId with
  | some surface =>
      match surface.keyKind with
      | .u64 => .ok ModuleSurface.withU64IndexedContains
      | .hash => .ok ModuleSurface.withHashIndexedContains
  | none => .ok ModuleSurface.empty

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

mutual
  partial def surfaceFromExpr (module : Module) (expr : Expr) : Except PlanError ModuleSurface :=
    match expr with
    | .literal _ | .local _ =>
        .ok ModuleSurface.empty
    | .nativeValue =>
        .ok ModuleSurface.withNativeValue
    | .arrayLit _ values =>
        values.foldlM (init := ModuleSurface.empty) fun acc value =>
          return mergeModuleSurfaces acc (← surfaceFromExpr module value)
    | .arrayGet array index =>
        return mergeModuleSurfaces (← surfaceFromExpr module array) (← surfaceFromExpr module index)
    | .memoryArrayNew _ length =>
        surfaceFromExpr module length
    | .memoryArrayLength array =>
        surfaceFromExpr module array
    | .memoryArrayGet array index =>
        return mergeModuleSurfaces (← surfaceFromExpr module array) (← surfaceFromExpr module index)
    | .structLit _ fields =>
        fields.foldlM (init := ModuleSurface.empty) fun acc field =>
          return mergeModuleSurfaces acc (← surfaceFromExpr module field.snd)
    | .field base _ =>
        surfaceFromExpr module base
    | .add lhs rhs | .sub lhs rhs | .mul lhs rhs | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs =>
        return mergeModuleSurfaces (← surfaceFromExpr module lhs) (← surfaceFromExpr module rhs)
    | .cast value _ | .boolNot value | .hash value =>
        surfaceFromExpr module value
    | .hashValue a b c d =>
        return mergeModuleSurfaces
          (mergeModuleSurfaces (← surfaceFromExpr module a) (← surfaceFromExpr module b))
          (mergeModuleSurfaces (← surfaceFromExpr module c) (← surfaceFromExpr module d))
    | .crosscallInvoke target methodId args
    | .crosscallInvokeTyped target methodId args _
    | .crosscallInvokeStaticTyped target methodId args _
    | .crosscallInvokeDelegateTyped target methodId args _ => do
        let base :=
          mergeModuleSurfaces
            (mergeModuleSurfaces (← surfaceFromExpr module target) (← surfaceFromExpr module methodId))
            ModuleSurface.withPromiseApi
        args.foldlM (init := base) fun acc arg =>
          return mergeModuleSurfaces acc (← surfaceFromExpr module arg)
    | .crosscallInvokeValueTyped target methodId callValue args _ => do
        let base :=
          mergeModuleSurfaces
            (mergeModuleSurfaces
              (mergeModuleSurfaces (← surfaceFromExpr module target) (← surfaceFromExpr module methodId))
              (← surfaceFromExpr module callValue))
            ModuleSurface.withPromiseApi
        args.foldlM (init := base) fun acc arg =>
          return mergeModuleSurfaces acc (← surfaceFromExpr module arg)
    | .crosscallCreate callValue _ => do
        return mergeModuleSurfaces (← surfaceFromExpr module callValue) ModuleSurface.withPromiseApi
    | .crosscallCreate2 callValue salt _ =>
        return mergeModuleSurfaces
          (mergeModuleSurfaces (← surfaceFromExpr module callValue) (← surfaceFromExpr module salt))
          ModuleSurface.withPromiseApi
    | .effect effect =>
        surfaceFromEffect module effect

  partial def surfaceFromEffect (module : Module) (effect : Effect) : Except PlanError ModuleSurface :=
    match effect with
    | .storageScalarRead stateId => do
        let type ← stateTypeOf module stateId
        let base := ModuleSurface.withStorageRead
        match scalarHelperType type with
        | some scalarType =>
            .ok <| mergeModuleSurfaces base (ModuleSurface.withScalarReadType scalarType)
        | none =>
            .ok base
    | .storageScalarWrite stateId value => do
        let type ← stateTypeOf module stateId
        let valueSurface ← surfaceFromExpr module value
        let base := mergeModuleSurfaces valueSurface ModuleSurface.withStorageWrite
        match scalarHelperType type with
        | some scalarType =>
            .ok <| mergeModuleSurfaces base (ModuleSurface.withScalarWriteType scalarType)
        | none =>
            .ok base
    | .storageScalarAssignOp stateId _ value => do
        let type ← stateTypeOf module stateId
        let valueSurface ← surfaceFromExpr module value
        let base :=
          mergeModuleSurfaces
            (mergeModuleSurfaces valueSurface ModuleSurface.withStorageRead)
            ModuleSurface.withStorageWrite
        match scalarHelperType type with
        | some scalarType =>
            .ok <| mergeModuleSurfaces
              (mergeModuleSurfaces base (ModuleSurface.withScalarReadType scalarType))
              (ModuleSurface.withScalarWriteType scalarType)
        | none =>
            .ok base
    | .storageMapContains stateId key => do
        return mergeModuleSurfaces
          (mergeModuleSurfaces (← surfaceFromExpr module key) (← indexedStorageContainsSurfaceSummary module stateId))
          ModuleSurface.empty
    | .storageMapGet stateId key => do
        return mergeModuleSurfaces
          (mergeModuleSurfaces (← surfaceFromExpr module key) (← indexedStorageReadSurfaceSummary module stateId))
          ModuleSurface.withStorageRead
    | .storageMapInsert stateId key value | .storageMapSet stateId key value => do
        return mergeModuleSurfaces
          (mergeModuleSurfaces
            (mergeModuleSurfaces (← surfaceFromExpr module key) (← surfaceFromExpr module value))
            (← indexedStorageWriteSurfaceSummary module stateId))
          (mergeModuleSurfaces ModuleSurface.withStorageRead ModuleSurface.withStorageWrite)
    | .storageArrayRead stateId index
    | .storageArrayStructFieldRead stateId index _ => do
        return mergeModuleSurfaces
          (mergeModuleSurfaces (← surfaceFromExpr module index) (← indexedStorageReadSurfaceSummary module stateId))
          ModuleSurface.withStorageRead
    | .storageArrayWrite stateId index value
    | .storageArrayStructFieldWrite stateId index _ value => do
        return mergeModuleSurfaces
          (mergeModuleSurfaces
            (mergeModuleSurfaces (← surfaceFromExpr module index) (← surfaceFromExpr module value))
            (← indexedStorageWriteSurfaceSummary module stateId))
          (mergeModuleSurfaces ModuleSurface.withStorageRead ModuleSurface.withStorageWrite)
    | .storageDynamicArrayPush _ value =>
        surfaceFromExpr module value
    | .storageDynamicArrayPop _ =>
        .ok ModuleSurface.empty
    | .memoryArraySet array index value =>
        return mergeModuleSurfaces
          (mergeModuleSurfaces (← surfaceFromExpr module array) (← surfaceFromExpr module index))
          (← surfaceFromExpr module value)
    | .storageStructFieldRead _ _ =>
        .ok ModuleSurface.withStorageRead
    | .storageStructFieldWrite _ _ value =>
        return mergeModuleSurfaces
          (← surfaceFromExpr module value)
          (mergeModuleSurfaces ModuleSurface.withStorageRead ModuleSurface.withStorageWrite)
    | .storagePathRead stateId path =>
        return mergeModuleSurfaces
          (mergeModuleSurfaces (← surfaceFromPath module path) (← indexedStorageReadSurfaceSummary module stateId))
          ModuleSurface.withStorageRead
    | .storagePathWrite stateId path value
    | .storagePathAssignOp stateId path _ value =>
        return mergeModuleSurfaces
          (mergeModuleSurfaces
            (mergeModuleSurfaces (← surfaceFromPath module path) (← surfaceFromExpr module value))
            (← indexedStorageWriteSurfaceSummary module stateId))
          (mergeModuleSurfaces ModuleSurface.withStorageRead ModuleSurface.withStorageWrite)
    | .contextRead field => do
        .ok <| ModuleSurface.withContext (← buildContextExprPlan field)
    | .eventEmit _ fields =>
        fields.foldlM (init := ModuleSurface.empty) fun acc field =>
          return mergeModuleSurfaces acc (← surfaceFromExpr module field.snd)
    | .eventEmitIndexed _ indexedFields dataFields => do
        let indexed ← indexedFields.foldlM (init := ModuleSurface.empty) fun acc field =>
          return mergeModuleSurfaces acc (← surfaceFromExpr module field.snd)
        dataFields.foldlM (init := indexed) fun acc field =>
          return mergeModuleSurfaces acc (← surfaceFromExpr module field.snd)

  partial def surfaceFromPath (module : Module) (path : Array StoragePathSegment) :
      Except PlanError ModuleSurface :=
    path.foldlM (init := ModuleSurface.empty) fun acc segment =>
      match segment with
      | .field _ => pure acc
      | .index index | .mapKey index =>
          return mergeModuleSurfaces acc (← surfaceFromExpr module index)

  partial def surfaceFromStatement (module : Module) (returnType : ValueType) (statement : Statement) :
      Except PlanError ModuleSurface :=
    match statement with
    | .letBind _ _ value | .letMutBind _ _ value =>
        surfaceFromExpr module value
    | .assign target value | .assignOp target _ value =>
        return mergeModuleSurfaces (← surfaceFromExpr module target) (← surfaceFromExpr module value)
    | .effect effect =>
        surfaceFromEffect module effect
    | .assert condition _ _ =>
        surfaceFromExpr module condition
    | .assertEq lhs rhs _ _ =>
        return mergeModuleSurfaces (← surfaceFromExpr module lhs) (← surfaceFromExpr module rhs)
    | .revert _ | .revertWithError _ | .release _ =>
        .ok ModuleSurface.empty
    | .ifElse condition thenBody elseBody =>
        return mergeModuleSurfaces
          (mergeModuleSurfaces (← surfaceFromExpr module condition) (← surfaceFromStatements module returnType thenBody))
          (← surfaceFromStatements module returnType elseBody)
    | .boundedFor _ _ _ body =>
        surfaceFromStatements module returnType body
    | .whileLoop condition body =>
        return mergeModuleSurfaces (← surfaceFromExpr module condition) (← surfaceFromStatements module returnType body)
    | .return value =>
        return mergeModuleSurfaces (← surfaceFromExpr module value) (ModuleSurface.withReturnType returnType)

  partial def surfaceFromStatements (module : Module) (returnType : ValueType) (statements : Array Statement) :
      Except PlanError ModuleSurface :=
    statements.foldlM (init := ModuleSurface.empty) fun acc statement =>
      return mergeModuleSurfaces acc (← surfaceFromStatement module returnType statement)
end

def surfaceFromModule (module : Module) : Except PlanError ModuleSurface :=
  module.entrypoints.foldlM (init := ModuleSurface.empty) fun acc entrypoint =>
    return mergeModuleSurfaces acc (← surfaceFromStatements module entrypoint.returns entrypoint.body)

structure ModulePlan where
  contextOps : Array ContextExprPlan
  scalarReadTypes : Array ValueType
  scalarWriteTypes : Array ValueType
  returnTypes : Array ValueType
  usesNativeValue : Bool
  usesStorageRead : Bool
  usesStorageWrite : Bool
  usesPromiseApi : Bool
  u64IndexedReadTypes : Array ValueType
  u64IndexedWriteTypes : Array ValueType
  hashIndexedReadTypes : Array ValueType
  hashIndexedWriteTypes : Array ValueType
  usesU64IndexedBuildKey : Bool
  usesHashIndexedBuildKey : Bool
  usesU64IndexedContains : Bool
  usesHashIndexedContains : Bool
  deriving Repr

def buildModulePlan (module : Module) : Except PlanError ModulePlan := do
  let surface ← surfaceFromModule module
  .ok {
    contextOps := surface.contextOps
    scalarReadTypes := surface.scalarReadTypes
    scalarWriteTypes := surface.scalarWriteTypes
    returnTypes := surface.returnTypes
    usesNativeValue := surface.usesNativeValue
    usesStorageRead := surface.usesStorageRead
    usesStorageWrite := surface.usesStorageWrite
    usesPromiseApi := surface.usesPromiseApi
    u64IndexedReadTypes := surface.u64IndexedReadTypes
    u64IndexedWriteTypes := surface.u64IndexedWriteTypes
    hashIndexedReadTypes := surface.hashIndexedReadTypes
    hashIndexedWriteTypes := surface.hashIndexedWriteTypes
    usesU64IndexedBuildKey := surface.usesU64IndexedBuildKey
    usesHashIndexedBuildKey := surface.usesHashIndexedBuildKey
    usesU64IndexedContains := surface.usesU64IndexedContains
    usesHashIndexedContains := surface.usesHashIndexedContains
  }

end ProofForge.Backend.WasmNear.Plan
