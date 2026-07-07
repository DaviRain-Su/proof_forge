import ProofForge.Backend.WasmNear.Plan.Common

namespace ProofForge.Backend.WasmNear.Plan

open ProofForge.IR
open ProofForge.Backend.WasmNear.ExprAnalysis

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
  usesPromiseCreate : Bool := false
  usesPromiseThen : Bool := false
  usesPromiseResults : Bool := false
  usesPromiseResultU64 : Bool := false
  usesPromiseReturn : Bool := false
  usesPromiseReceiverAccount : Bool := false
  usesCrosscallArgs : Bool := false
  usesCrosscallHash : Bool := false
  usesFmtU64 : Bool := false
  usesEventApi : Bool := false
  usesEventNumeric : Bool := false
  usesEventBool : Bool := false
  usesEventHash : Bool := false
  u64IndexedReadTypes : Array ValueType := #[]
  u64IndexedWriteTypes : Array ValueType := #[]
  hashIndexedReadTypes : Array ValueType := #[]
  hashIndexedWriteTypes : Array ValueType := #[]
  usesU64IndexedBuildKey : Bool := false
  usesHashIndexedBuildKey : Bool := false
  usesU64IndexedContains : Bool := false
  usesHashIndexedContains : Bool := false
  usesHashMake : Bool := false
  usesHashPreimage : Bool := false
  usesHashTwoToOne : Bool := false
  usesHashEq : Bool := false
  usesPowU32 : Bool := false
  usesPowU64 : Bool := false
  usesMemcpy : Bool := false
  arrayLitShapes : Array (ValueType × Nat) := #[]
  arrayEqShapes : Array (ValueType × Nat) := #[]
  structLitNames : Array String := #[]
  usesArrAlloc : Bool := false
  usesArrDealloc : Bool := false
  deriving Repr, Inhabited

def pushArrayShapeIfMissing (acc : Array (ValueType × Nat)) (shape : ValueType × Nat) : Array (ValueType × Nat) :=
  if acc.any (fun existing => existing.1 == shape.1 && existing.2 == shape.2) then acc else acc.push shape

def mergeArrayShapes (lhs rhs : Array (ValueType × Nat)) : Array (ValueType × Nat) :=
  rhs.foldl pushArrayShapeIfMissing lhs

def pushStringIfMissing (acc : Array String) (value : String) : Array String :=
  if acc.contains value then acc else acc.push value

def mergeStringSets (lhs rhs : Array String) : Array String :=
  rhs.foldl pushStringIfMissing lhs

def mergeModuleSurfaces (lhs rhs : ModuleSurface) : ModuleSurface := {
  contextOps := mergeContextExprPlans lhs.contextOps rhs.contextOps
  scalarReadTypes := mergeValueTypeSets lhs.scalarReadTypes rhs.scalarReadTypes
  scalarWriteTypes := mergeValueTypeSets lhs.scalarWriteTypes rhs.scalarWriteTypes
  returnTypes := mergeValueTypeSets lhs.returnTypes rhs.returnTypes
  usesNativeValue := lhs.usesNativeValue || rhs.usesNativeValue
  usesStorageRead := lhs.usesStorageRead || rhs.usesStorageRead
  usesStorageWrite := lhs.usesStorageWrite || rhs.usesStorageWrite
  usesPromiseApi := lhs.usesPromiseApi || rhs.usesPromiseApi
  usesPromiseCreate := lhs.usesPromiseCreate || rhs.usesPromiseCreate
  usesPromiseThen := lhs.usesPromiseThen || rhs.usesPromiseThen
  usesPromiseResults := lhs.usesPromiseResults || rhs.usesPromiseResults
  usesPromiseResultU64 := lhs.usesPromiseResultU64 || rhs.usesPromiseResultU64
  usesPromiseReturn := lhs.usesPromiseReturn || rhs.usesPromiseReturn
  usesPromiseReceiverAccount := lhs.usesPromiseReceiverAccount || rhs.usesPromiseReceiverAccount
  usesCrosscallArgs := lhs.usesCrosscallArgs || rhs.usesCrosscallArgs
  usesCrosscallHash := lhs.usesCrosscallHash || rhs.usesCrosscallHash
  usesFmtU64 := lhs.usesFmtU64 || rhs.usesFmtU64
  usesEventApi := lhs.usesEventApi || rhs.usesEventApi
  usesEventNumeric := lhs.usesEventNumeric || rhs.usesEventNumeric
  usesEventBool := lhs.usesEventBool || rhs.usesEventBool
  usesEventHash := lhs.usesEventHash || rhs.usesEventHash
  u64IndexedReadTypes := mergeValueTypeSets lhs.u64IndexedReadTypes rhs.u64IndexedReadTypes
  u64IndexedWriteTypes := mergeValueTypeSets lhs.u64IndexedWriteTypes rhs.u64IndexedWriteTypes
  hashIndexedReadTypes := mergeValueTypeSets lhs.hashIndexedReadTypes rhs.hashIndexedReadTypes
  hashIndexedWriteTypes := mergeValueTypeSets lhs.hashIndexedWriteTypes rhs.hashIndexedWriteTypes
  usesU64IndexedBuildKey := lhs.usesU64IndexedBuildKey || rhs.usesU64IndexedBuildKey
  usesHashIndexedBuildKey := lhs.usesHashIndexedBuildKey || rhs.usesHashIndexedBuildKey
  usesU64IndexedContains := lhs.usesU64IndexedContains || rhs.usesU64IndexedContains
  usesHashIndexedContains := lhs.usesHashIndexedContains || rhs.usesHashIndexedContains
  usesHashMake := lhs.usesHashMake || rhs.usesHashMake
  usesHashPreimage := lhs.usesHashPreimage || rhs.usesHashPreimage
  usesHashTwoToOne := lhs.usesHashTwoToOne || rhs.usesHashTwoToOne
  usesHashEq := lhs.usesHashEq || rhs.usesHashEq
  usesPowU32 := lhs.usesPowU32 || rhs.usesPowU32
  usesPowU64 := lhs.usesPowU64 || rhs.usesPowU64
  usesMemcpy := lhs.usesMemcpy || rhs.usesMemcpy
  arrayLitShapes := mergeArrayShapes lhs.arrayLitShapes rhs.arrayLitShapes
  arrayEqShapes := mergeArrayShapes lhs.arrayEqShapes rhs.arrayEqShapes
  structLitNames := mergeStringSets lhs.structLitNames rhs.structLitNames
  usesArrAlloc := lhs.usesArrAlloc || rhs.usesArrAlloc
  usesArrDealloc := lhs.usesArrDealloc || rhs.usesArrDealloc
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

/-- NEAR Promise-based crosscall lowering via `promise_create`. -/
def withCrosscallPromise : ModuleSurface := {
  usesPromiseApi := true
  usesPromiseCreate := true
}

def withPromiseReturn : ModuleSurface := {
  usesPromiseReturn := true
}

/-- NEAR `promise_then` on the current contract account. -/
def withPromiseThen : ModuleSurface := {
  usesPromiseApi := true
  usesPromiseThen := true
  usesPromiseReceiverAccount := true
}

/-- NEAR callback result introspection (`promise_results_count` / `promise_result`). -/
def withPromiseResults : ModuleSurface := {
  usesPromiseApi := true
  usesPromiseResults := true
}

/-- NEAR callback result payload decode (`promise_result` + Borsh U64 from register). -/
def withPromiseResultU64 : ModuleSurface := {
  usesPromiseApi := true
  usesPromiseResults := true
  usesPromiseResultU64 := true
}

def withCrosscallArgs : ModuleSurface := {
  usesCrosscallArgs := true
  usesMemcpy := true
}

def withCrosscallHash : ModuleSurface := {
  usesCrosscallArgs := true
  usesCrosscallHash := true
  usesMemcpy := true
}

/-- Decimal u64 formatter shared by event and crosscall JSON builders (no `log_utf8`). -/
def withFmtU64 : ModuleSurface := {
  usesFmtU64 := true
}

def withEventApi : ModuleSurface := {
  usesEventApi := true
  usesMemcpy := true
}

def withEventNumeric : ModuleSurface := {
  usesEventApi := true
  usesEventNumeric := true
  usesMemcpy := true
}

def withEventBool : ModuleSurface := {
  usesEventApi := true
  usesEventBool := true
  usesMemcpy := true
}

def withEventHash : ModuleSurface := {
  usesEventApi := true
  usesEventHash := true
  usesMemcpy := true
}

def withU64IndexedBuildKey : ModuleSurface := {
  usesU64IndexedBuildKey := true
}

def withHashIndexedBuildKey : ModuleSurface := {
  usesHashIndexedBuildKey := true
  usesMemcpy := true
}

def withU64IndexedReadType (type : ValueType) : ModuleSurface := {
  usesU64IndexedBuildKey := true
  u64IndexedReadTypes := #[type]
}

def withU64IndexedWriteType (type : ValueType) : ModuleSurface := {
  usesU64IndexedBuildKey := true
  u64IndexedWriteTypes := #[type]
  usesMemcpy := type == .hash
}

def withHashIndexedReadType (type : ValueType) : ModuleSurface := {
  usesHashIndexedBuildKey := true
  hashIndexedReadTypes := #[type]
}

def withHashIndexedWriteType (type : ValueType) : ModuleSurface := {
  usesHashIndexedBuildKey := true
  hashIndexedWriteTypes := #[type]
  usesMemcpy := type == .hash
}

def withU64IndexedContains : ModuleSurface := {
  usesU64IndexedBuildKey := true
  usesU64IndexedContains := true
}

def withHashIndexedContains : ModuleSurface := {
  usesHashIndexedBuildKey := true
  usesHashIndexedContains := true
}

def withHashMake : ModuleSurface := {
  usesHashMake := true
}

def withHashPreimage : ModuleSurface := {
  usesHashPreimage := true
}

def withHashTwoToOne : ModuleSurface := {
  usesHashTwoToOne := true
  usesMemcpy := true
}

def withHashEq : ModuleSurface := {
  usesHashEq := true
}

def withPowU32 : ModuleSurface := {
  usesPowU32 := true
}

def withPowU64 : ModuleSurface := {
  usesPowU64 := true
}

def withMemcpy : ModuleSurface := {
  usesMemcpy := true
}

def withArrayLitShape (elemType : ValueType) (len : Nat) : ModuleSurface := {
  arrayLitShapes := #[(elemType, len)]
  usesArrAlloc := true
}

def withArrayEqShape (elemType : ValueType) (len : Nat) : ModuleSurface := {
  arrayEqShapes := #[(elemType, len)]
}

def withStructLitName (name : String) : ModuleSurface := {
  structLitNames := #[name]
  usesArrAlloc := true
}

def withArrAlloc : ModuleSurface := {
  usesArrAlloc := true
}

def withArrDealloc : ModuleSurface := {
  usesArrDealloc := true
}

def comparisonSurfaceForType (type : ValueType) : ModuleSurface :=
  match type with
  | .fixedArray elemType len => ModuleSurface.withArrayEqShape elemType len
  | .hash => ModuleSurface.withHashEq
  | _ => ModuleSurface.empty

end ModuleSurface

def crosscallArgSurfaceForType (type : ValueType) : ModuleSurface :=
  match type with
  | .u64 | .u32 => mergeModuleSurfaces ModuleSurface.withCrosscallArgs ModuleSurface.withFmtU64
  | .bool => ModuleSurface.withCrosscallArgs
  | .hash => ModuleSurface.withCrosscallHash
  | _ => ModuleSurface.withCrosscallArgs

def eventFieldSurfaceForType (type : ValueType) : ModuleSurface :=
  match type with
  | .u64 | .u32 => ModuleSurface.withEventNumeric
  | .bool => ModuleSurface.withEventBool
  | .hash => ModuleSurface.withEventHash
  | _ => ModuleSurface.withEventApi

partial def collectLocalTypesFrom (env : LocalTypeEnv) (statement : Statement) : Except PlanError LocalTypeEnv := do
  match statement with
  | .letBind name type _ | .letMutBind name type _ =>
      .ok (env.push (name, type))
  | .ifElse _ thenBody elseBody => do
      let env ← thenBody.foldlM (init := env) collectLocalTypesFrom
      elseBody.foldlM (init := env) collectLocalTypesFrom
  | .boundedFor indexName _ _ body => do
      let env := env.push (indexName, .u64)
      body.foldlM (init := env) collectLocalTypesFrom
  | _ =>
      .ok env

def collectEntrypointLocalTypes (entrypoint : Entrypoint) : Except PlanError LocalTypeEnv := do
  let initial := entrypoint.params.map (fun param => (param.fst, param.snd))
  entrypoint.body.foldlM (init := initial) collectLocalTypesFrom

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
    | .nearCrosscallInvokePool accountIndex methodId args deposit => do
        let base :=
          mergeContextExprPlans
            (mergeContextExprPlans (← contextOpsFromExpr accountIndex) (← contextOpsFromExpr methodId))
            (← contextOpsFromExpr deposit)
        args.foldlM (init := base) fun acc arg =>
          return mergeContextExprPlans acc (← contextOpsFromExpr arg)
    | .nearPromiseThen parentPromise callbackMethod args deposit => do
        let base :=
          mergeContextExprPlans
            (mergeContextExprPlans (← contextOpsFromExpr parentPromise) (← contextOpsFromExpr callbackMethod))
            (← contextOpsFromExpr deposit)
        args.foldlM (init := base) fun acc arg =>
          return mergeContextExprPlans acc (← contextOpsFromExpr arg)
    | .nearPromiseResultsCount => .ok #[]
    | .nearPromiseResultStatus index => contextOpsFromExpr index
    | .nearPromiseResultU64 index => contextOpsFromExpr index
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

partial def surfaceFromValueType (module : Module) (type : ValueType) : ModuleSurface :=
  match type with
  | .hash => ModuleSurface.withMemcpy
  | .fixedArray elemType _ =>
      mergeModuleSurfaces ModuleSurface.withArrAlloc
        (if elemType == .hash then ModuleSurface.withMemcpy else surfaceFromValueType module elemType)
  | .structType structName =>
      let fieldSurface :=
        match findStruct? module structName with
        | some structDecl =>
            structDecl.fields.foldl (fun acc field =>
              mergeModuleSurfaces acc (surfaceFromValueType module field.type)) ModuleSurface.empty
        | none => ModuleSurface.empty
      mergeModuleSurfaces ModuleSurface.withArrAlloc fieldSurface
  | _ => ModuleSurface.empty

def surfaceFromEntrypointParams (module : Module) (params : Array (String × ValueType)) : ModuleSurface :=
  params.foldl (fun acc (_, type) =>
    mergeModuleSurfaces acc (surfaceFromValueType module type)) ModuleSurface.empty

mutual
  partial def surfaceFromCrosscallArgs (module : Module) (env : LocalTypeEnv) (args : Array Expr) :
      Except PlanError ModuleSurface :=
    if args.isEmpty then
      .ok ModuleSurface.empty
    else
      args.foldlM (init := ModuleSurface.empty) fun acc arg => do
        let argSurface ← surfaceFromExpr module env arg
        let argType ← inferExprType module env arg
        return mergeModuleSurfaces acc (mergeModuleSurfaces argSurface (crosscallArgSurfaceForType argType))

  partial def surfaceFromExpr (module : Module) (env : LocalTypeEnv) (expr : Expr) : Except PlanError ModuleSurface :=
    match expr with
    | .literal (.hash4 ..) =>
        .ok ModuleSurface.withHashMake
    | .literal _ | .local _ =>
        .ok ModuleSurface.empty
    | .nativeValue =>
        .ok ModuleSurface.withNativeValue
    | .arrayLit elementType values => do
        let valueSurface ← values.foldlM (init := ModuleSurface.empty) fun acc value =>
          return mergeModuleSurfaces acc (← surfaceFromExpr module env value)
        .ok (mergeModuleSurfaces valueSurface (ModuleSurface.withArrayLitShape elementType values.size))
    | .structLit typeName fields => do
        let valueSurface ← fields.foldlM (init := ModuleSurface.empty) fun acc field =>
          return mergeModuleSurfaces acc (← surfaceFromExpr module env field.snd)
        .ok (mergeModuleSurfaces valueSurface (ModuleSurface.withStructLitName typeName))
    | .arrayGet array index =>
        return mergeModuleSurfaces (← surfaceFromExpr module env array) (← surfaceFromExpr module env index)
    | .memoryArrayNew _ length =>
        surfaceFromExpr module env length
    | .memoryArrayLength array =>
        surfaceFromExpr module env array
    | .memoryArrayGet array index =>
        return mergeModuleSurfaces (← surfaceFromExpr module env array) (← surfaceFromExpr module env index)
    | .field base _ =>
        surfaceFromExpr module env base
    | .add lhs rhs | .sub lhs rhs | .mul lhs rhs | .div lhs rhs | .mod lhs rhs
    | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs =>
        return mergeModuleSurfaces (← surfaceFromExpr module env lhs) (← surfaceFromExpr module env rhs)
    | .pow lhs rhs => do
        let lhsSurface ← surfaceFromExpr module env lhs
        let rhsSurface ← surfaceFromExpr module env rhs
        let lhsType ← inferExprType module env lhs
        let powSurface :=
          if lhsType == .u32 then ModuleSurface.withPowU32
          else if lhsType == .u64 then ModuleSurface.withPowU64
          else ModuleSurface.empty
        .ok (mergeModuleSurfaces (mergeModuleSurfaces lhsSurface rhsSurface) powSurface)
    | .eq lhs rhs | .ne lhs rhs => do
        let lhsSurface ← surfaceFromExpr module env lhs
        let rhsSurface ← surfaceFromExpr module env rhs
        let lhsType ← inferExprType module env lhs
        .ok (mergeModuleSurfaces (mergeModuleSurfaces lhsSurface rhsSurface) (ModuleSurface.comparisonSurfaceForType lhsType))
    | .hashTwoToOne lhs rhs => do
        let merged :=
          mergeModuleSurfaces (← surfaceFromExpr module env lhs) (← surfaceFromExpr module env rhs)
        .ok (mergeModuleSurfaces merged ModuleSurface.withHashTwoToOne)
    | .cast value _ | .boolNot value =>
        surfaceFromExpr module env value
    | .hash preimage => do
        let preimageSurface ← surfaceFromExpr module env preimage
        .ok (mergeModuleSurfaces preimageSurface ModuleSurface.withHashPreimage)
    | .hashValue a b c d => do
        let merged :=
          mergeModuleSurfaces
            (mergeModuleSurfaces (← surfaceFromExpr module env a) (← surfaceFromExpr module env b))
            (mergeModuleSurfaces (← surfaceFromExpr module env c) (← surfaceFromExpr module env d))
        .ok (mergeModuleSurfaces merged ModuleSurface.withHashMake)
    | .crosscallInvoke target methodId args
    | .crosscallInvokeTyped target methodId args _
    | .crosscallInvokeStaticTyped target methodId args _
    | .crosscallInvokeDelegateTyped target methodId args _ => do
        let base :=
          mergeModuleSurfaces
            (mergeModuleSurfaces (← surfaceFromExpr module env target) (← surfaceFromExpr module env methodId))
            ModuleSurface.withCrosscallPromise
        let argSurface ← surfaceFromCrosscallArgs module env args
        return mergeModuleSurfaces base argSurface
    | .crosscallInvokeValueTyped target methodId callValue args _ => do
        let base :=
          mergeModuleSurfaces
            (mergeModuleSurfaces
              (mergeModuleSurfaces (← surfaceFromExpr module env target) (← surfaceFromExpr module env methodId))
              (← surfaceFromExpr module env callValue))
            ModuleSurface.withCrosscallPromise
        let argSurface ← surfaceFromCrosscallArgs module env args
        return mergeModuleSurfaces base argSurface
    | .crosscallCreate callValue _ => do
        return mergeModuleSurfaces (← surfaceFromExpr module env callValue) ModuleSurface.withCrosscallPromise
    | .crosscallCreate2 callValue salt _ =>
        return mergeModuleSurfaces
          (mergeModuleSurfaces (← surfaceFromExpr module env callValue) (← surfaceFromExpr module env salt))
          ModuleSurface.withCrosscallPromise
    | .nearCrosscallInvokePool accountIndex methodId args deposit => do
        let base :=
          mergeModuleSurfaces
            (mergeModuleSurfaces (← surfaceFromExpr module env accountIndex) (← surfaceFromExpr module env methodId))
            (← surfaceFromExpr module env deposit)
        let argSurface ← surfaceFromCrosscallArgs module env args
        return mergeModuleSurfaces (mergeModuleSurfaces base argSurface) ModuleSurface.withCrosscallPromise
    | .nearPromiseThen parentPromise callbackMethod args deposit => do
        let base :=
          mergeModuleSurfaces
            (mergeModuleSurfaces
              (mergeModuleSurfaces (← surfaceFromExpr module env parentPromise) (← surfaceFromExpr module env callbackMethod))
              (← surfaceFromExpr module env deposit))
            ModuleSurface.withPromiseThen
        let argSurface ← surfaceFromCrosscallArgs module env args
        return mergeModuleSurfaces base argSurface
    | .nearPromiseResultsCount => .ok ModuleSurface.withPromiseResults
    | .nearPromiseResultStatus index =>
        return mergeModuleSurfaces (← surfaceFromExpr module env index) ModuleSurface.withPromiseResults
    | .nearPromiseResultU64 index =>
        return mergeModuleSurfaces (← surfaceFromExpr module env index) ModuleSurface.withPromiseResultU64
    | .effect effect =>
        surfaceFromEffect module env effect

  partial def surfaceFromEffect (module : Module) (env : LocalTypeEnv) (effect : Effect) : Except PlanError ModuleSurface :=
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
        let valueSurface ← surfaceFromExpr module env value
        let base := mergeModuleSurfaces valueSurface ModuleSurface.withStorageWrite
        match scalarHelperType type with
        | some scalarType =>
            .ok <| mergeModuleSurfaces base (ModuleSurface.withScalarWriteType scalarType)
        | none =>
            .ok base
    | .storageScalarAssignOp stateId _ value => do
        let type ← stateTypeOf module stateId
        let valueSurface ← surfaceFromExpr module env value
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
          (mergeModuleSurfaces (← surfaceFromExpr module env key) (← indexedStorageContainsSurfaceSummary module stateId))
          ModuleSurface.empty
    | .storageMapGet stateId key => do
        return mergeModuleSurfaces
          (mergeModuleSurfaces (← surfaceFromExpr module env key) (← indexedStorageReadSurfaceSummary module stateId))
          ModuleSurface.withStorageRead
    | .storageMapInsert stateId key value | .storageMapSet stateId key value => do
        return mergeModuleSurfaces
          (mergeModuleSurfaces
            (mergeModuleSurfaces (← surfaceFromExpr module env key) (← surfaceFromExpr module env value))
            (← indexedStorageWriteSurfaceSummary module stateId))
          (mergeModuleSurfaces ModuleSurface.withStorageRead ModuleSurface.withStorageWrite)
    | .storageArrayRead stateId index
    | .storageArrayStructFieldRead stateId index _ => do
        return mergeModuleSurfaces
          (mergeModuleSurfaces (← surfaceFromExpr module env index) (← indexedStorageReadSurfaceSummary module stateId))
          ModuleSurface.withStorageRead
    | .storageArrayWrite stateId index value
    | .storageArrayStructFieldWrite stateId index _ value => do
        return mergeModuleSurfaces
          (mergeModuleSurfaces
            (mergeModuleSurfaces (← surfaceFromExpr module env index) (← surfaceFromExpr module env value))
            (← indexedStorageWriteSurfaceSummary module stateId))
          (mergeModuleSurfaces ModuleSurface.withStorageRead ModuleSurface.withStorageWrite)
    | .storageDynamicArrayPush _ value =>
        surfaceFromExpr module env value
    | .storageDynamicArrayPop _ =>
        .ok ModuleSurface.empty
    | .memoryArraySet array index value =>
        return mergeModuleSurfaces
          (mergeModuleSurfaces (← surfaceFromExpr module env array) (← surfaceFromExpr module env index))
          (← surfaceFromExpr module env value)
    | .storageStructFieldRead _ _ =>
        .ok ModuleSurface.withStorageRead
    | .storageStructFieldWrite _ _ value =>
        return mergeModuleSurfaces
          (← surfaceFromExpr module env value)
          (mergeModuleSurfaces ModuleSurface.withStorageRead ModuleSurface.withStorageWrite)
    | .storagePathRead stateId path =>
        return mergeModuleSurfaces
          (mergeModuleSurfaces (← surfaceFromPath module env path) (← indexedStorageReadSurfaceSummary module stateId))
          ModuleSurface.withStorageRead
    | .storagePathWrite stateId path value
    | .storagePathAssignOp stateId path _ value =>
        return mergeModuleSurfaces
          (mergeModuleSurfaces
            (mergeModuleSurfaces (← surfaceFromPath module env path) (← surfaceFromExpr module env value))
            (← indexedStorageWriteSurfaceSummary module stateId))
          (mergeModuleSurfaces ModuleSurface.withStorageRead ModuleSurface.withStorageWrite)
    | .contextRead field => do
        .ok <| ModuleSurface.withContext (← buildContextExprPlan field)
    | .eventEmit _ fields =>
        fields.foldlM (init := ModuleSurface.withEventApi) fun acc field =>
          return mergeModuleSurfaces acc (← surfaceFromExpr module env field.snd)
    | .eventEmitIndexed _ indexedFields dataFields => do
        let indexed ← indexedFields.foldlM (init := ModuleSurface.withEventApi) fun acc field =>
          return mergeModuleSurfaces acc (← surfaceFromExpr module env field.snd)
        dataFields.foldlM (init := indexed) fun acc field =>
          return mergeModuleSurfaces acc (← surfaceFromExpr module env field.snd)

  partial def surfaceFromPath (module : Module) (env : LocalTypeEnv) (path : Array StoragePathSegment) :
      Except PlanError ModuleSurface :=
    path.foldlM (init := ModuleSurface.empty) fun acc segment =>
      match segment with
      | .field _ => pure acc
      | .index index | .mapKey index =>
          return mergeModuleSurfaces acc (← surfaceFromExpr module env index)

  partial def surfaceFromStatement (module : Module) (env : LocalTypeEnv) (returnType : ValueType) (statement : Statement) :
      Except PlanError ModuleSurface :=
    match statement with
    | .letBind _ _ value | .letMutBind _ _ value =>
        surfaceFromExpr module env value
    | .assign target value | .assignOp target _ value =>
        return mergeModuleSurfaces (← surfaceFromExpr module env target) (← surfaceFromExpr module env value)
    | .effect effect =>
        match effect with
        | .eventEmit _ fields =>
            fields.foldlM (init := ModuleSurface.withEventApi) fun acc field => do
              let valueSurface ← surfaceFromExpr module env field.snd
              let valueType ← inferExprType module env field.snd
              return mergeModuleSurfaces acc (mergeModuleSurfaces valueSurface (eventFieldSurfaceForType valueType))
        | .eventEmitIndexed _ indexedFields dataFields => do
            let indexed ← indexedFields.foldlM (init := ModuleSurface.withEventApi) fun acc field => do
              let valueSurface ← surfaceFromExpr module env field.snd
              let valueType ← inferExprType module env field.snd
              return mergeModuleSurfaces acc (mergeModuleSurfaces valueSurface (eventFieldSurfaceForType valueType))
            dataFields.foldlM (init := indexed) fun acc field => do
              let valueSurface ← surfaceFromExpr module env field.snd
              let valueType ← inferExprType module env field.snd
              return mergeModuleSurfaces acc (mergeModuleSurfaces valueSurface (eventFieldSurfaceForType valueType))
        | _ =>
            surfaceFromEffect module env effect
    | .assert condition _ _ =>
        surfaceFromExpr module env condition
    | .assertEq lhs rhs _ _ => do
        let lhsSurface ← surfaceFromExpr module env lhs
        let rhsSurface ← surfaceFromExpr module env rhs
        let lhsType ← inferExprType module env lhs
        .ok (mergeModuleSurfaces (mergeModuleSurfaces lhsSurface rhsSurface) (ModuleSurface.comparisonSurfaceForType lhsType))
    | .release _ =>
        .ok ModuleSurface.withArrDealloc
    | .revert _ | .revertWithError _ =>
        .ok ModuleSurface.empty
    | .ifElse condition thenBody elseBody =>
        return mergeModuleSurfaces
          (mergeModuleSurfaces (← surfaceFromExpr module env condition) (← surfaceFromStatements module env returnType thenBody))
          (← surfaceFromStatements module env returnType elseBody)
    | .boundedFor _ _ _ body =>
        surfaceFromStatements module env returnType body
    | .whileLoop condition body =>
        return mergeModuleSurfaces (← surfaceFromExpr module env condition) (← surfaceFromStatements module env returnType body)
    | .return value => do
        let valueSurface ← surfaceFromExpr module env value
        let promiseReturn :=
          if exprReturnsNearPromise value then ModuleSurface.withPromiseReturn else ModuleSurface.empty
        return mergeModuleSurfaces
          (mergeModuleSurfaces valueSurface promiseReturn) (ModuleSurface.withReturnType returnType)

  partial def surfaceFromStatements (module : Module) (env : LocalTypeEnv) (returnType : ValueType) (statements : Array Statement) :
      Except PlanError ModuleSurface :=
    statements.foldlM (init := ModuleSurface.empty) fun acc statement =>
      return mergeModuleSurfaces acc (← surfaceFromStatement module env returnType statement)
end

def surfaceFromModule (module : Module) : Except PlanError ModuleSurface :=
  module.entrypoints.foldlM (init := ModuleSurface.empty) fun acc entrypoint => do
    let env ← collectEntrypointLocalTypes entrypoint
    let paramSurface := surfaceFromEntrypointParams module entrypoint.params
    let bodySurface ← surfaceFromStatements module env entrypoint.returns entrypoint.body
    return mergeModuleSurfaces acc (mergeModuleSurfaces paramSurface bodySurface)

end ProofForge.Backend.WasmNear.Plan
