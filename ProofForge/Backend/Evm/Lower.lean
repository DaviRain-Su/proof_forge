import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.Validate
import ProofForge.IR.Contract
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

/-! # EVM semantic plan lowering (IR -> ModulePlan)

This module is the `Lower` pass from RFC 0004. It consumes a portable IR
`Module` together with the pure validation/type-inference from `Validate.lean`
and produces a fully populated `Plan.ModulePlan` with:

- `EntrypointPlan` nodes (selector, ABI params, return plan, body)
- `EventPlan` nodes (signature, indexed/data field layout)
- `CrosscallHelperSpec` and `CreateHelperSpec` discovered from the IR
- Local-array-get and nested-local-array-get helper requirements
- The checked-arithmetic flag
- A `MetadataPlan` summarizing the module for artifact/deploy metadata

The plan is then consumed by `ToYul.lean` (helper emission) and `IR.lean`
(Yul AST construction). Keeping plan construction separate from Yul AST
construction is the core architectural goal of RFC 0004. -/

namespace ProofForge.Backend.Evm.Lower

open ProofForge.IR
open ProofForge.Target
open ProofForge.Backend.Evm.Plan
open ProofForge.Backend.Evm.Validate

/-! ## Entrypoint plan construction -/

def scalarStorageTargetPlan? (module : Module) (stateId : String) : Option ScalarStorageTargetPlan :=
  match scalarStorageTargetPlan module stateId with
  | .ok target => some target
  | .error _ => none

def mapWriteTargetPlan? (module : Module) (stateId : String) : Option MapWriteTargetPlan :=
  match mapWriteTargetPlan module stateId with
  | .ok target => some target
  | .error _ => none

def mapReadTargetPlan? (module : Module) (stateId : String) : Option MapReadTargetPlan :=
  match mapReadTargetPlan module stateId with
  | .ok target => some target
  | .error _ => none

def arrayWriteTargetPlan? (module : Module) (stateId : String) : Option ArrayWriteTargetPlan :=
  match arrayWriteTargetPlan module stateId with
  | .ok target => some target
  | .error _ => none

def arrayReadTargetPlan? (module : Module) (stateId : String) : Option ArrayReadTargetPlan :=
  match arrayReadTargetPlan module stateId with
  | .ok target => some target
  | .error _ => none

def structFieldWriteTargetPlan?
    (module : Module)
    (stateId fieldName : String) : Option StructFieldWriteTargetPlan :=
  match structFieldWriteTargetPlan module stateId fieldName with
  | .ok target => some target
  | .error _ => none

def structFieldReadTargetPlan?
    (module : Module)
    (stateId fieldName : String) : Option StructFieldReadTargetPlan :=
  match structFieldReadTargetPlan module stateId fieldName with
  | .ok target => some target
  | .error _ => none

def structArrayFieldWriteTargetPlan?
    (module : Module)
    (stateId fieldName : String) : Option StructArrayFieldWriteTargetPlan :=
  match structArrayFieldWriteTargetPlan module stateId fieldName with
  | .ok target => some target
  | .error _ => none

def structArrayFieldReadTargetPlan?
    (module : Module)
    (stateId fieldName : String) : Option StructArrayFieldReadTargetPlan :=
  match structArrayFieldReadTargetPlan module stateId fieldName with
  | .ok target => some target
  | .error _ => none

def abiParamPlan
    (module : Module)
    (context : String)
    (name : String)
    (type : ValueType)
    (headWordIndex : Nat) : Except LowerError AbiParamPlan := do
  let wordTypes ← abiValueWordTypes module s!"{context} parameter `{name}`" type
  let localNames ←
    if abiTypeIsDynamic type then
      .ok #[dynamicParamLengthName name, dynamicParamDataPtrName name]
    else
      abiValueParamNames module s!"{context} parameter `{name}`" name type
  .ok { name, type, wordTypes, headWordIndex, localNames }

def entrypointParamPlans (module : Module) (entrypoint : Entrypoint) :
    Except LowerError (Array AbiParamPlan) := do
  let (_, params) ← entrypoint.params.foldlM (init := (0, #[])) fun acc param => do
    let (headWordIndex, params) := acc
    let paramPlan ← abiParamPlan module s!"entrypoint `{entrypoint.name}`" param.fst param.snd headWordIndex
    .ok (headWordIndex + paramPlan.headWordCount, params.push paramPlan)
  .ok params

def returnPlan (module : Module) (context : String) (returnType : ValueType) :
    Except LowerError ReturnPlan := do
  let wordTypes ←
    match returnType with
    | .unit => .ok #[]
    | _ => abiValueWordTypes module s!"{context} return value" returnType
  .ok { returnType, wordTypes, localNames := returnLocalNames returnType wordTypes }

def localAbiStructFieldIds
    (module : Module)
    (context typeName : String) : Except LowerError (Array String) := do
  discard <| abiValueWordTypes module context (.structType typeName)
  let some decl := ProofForge.Backend.Evm.Validate.findStruct? module typeName
    | .error { message := s!"{context} uses unknown struct `{typeName}`" }
  let mut fieldIds : Array String := #[]
  for fieldDecl in decl.fields do
    ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
    fieldIds := fieldIds.push fieldDecl.id
  .ok fieldIds

def localAbiStructFields
    (module : Module)
    (context typeName : String) : Except LowerError (Array (String × ValueType)) := do
  discard <| abiValueWordTypes module context (.structType typeName)
  let some decl := ProofForge.Backend.Evm.Validate.findStruct? module typeName
    | .error { message := s!"{context} uses unknown struct `{typeName}`" }
  let mut fields : Array (String × ValueType) := #[]
  for fieldDecl in decl.fields do
    ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
    fields := fields.push (fieldDecl.id, fieldDecl.type)
  .ok fields

def validateLocalAbiWordPlan
    (module : Module)
    (env : TypeEnv)
    (context name : String)
    (expectedType : ValueType) : Except LowerError Unit := do
  let some binding := findLocal? env name
    | .error { message := s!"unknown local `{name}`" }
  ensureType context expectedType binding.type
  discard <| abiValueWordTypes module context expectedType

def crosscallReturnPlan (module : Module) (context : String) (returnType : ValueType) :
    Except LowerError ReturnPlan := do
  let wordTypes ← crosscallReturnWordTypes module context returnType
  .ok { returnType, wordTypes, localNames := returnLocalNames returnType wordTypes }

def localCrosscallStructFieldIds
    (module : Module)
    (context typeName : String) : Except LowerError (Array String) := do
  discard <| crosscallValueWordTypes module context (.structType typeName)
  let some decl := ProofForge.Backend.Evm.Validate.findStruct? module typeName
    | .error { message := s!"{context} uses unknown struct `{typeName}`" }
  let mut fieldIds : Array String := #[]
  for fieldDecl in decl.fields do
    ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
    fieldIds := fieldIds.push fieldDecl.id
  .ok fieldIds

def validateLocalCrosscallWordPlan
    (module : Module)
    (env : TypeEnv)
    (context name : String)
    (expectedType : ValueType) : Except LowerError Unit := do
  let some binding := findLocal? env name
    | .error { message := s!"unknown local `{name}`" }
  ensureType context expectedType binding.type
  match expectedType with
  | .fixedArray _ _ | .structType _ =>
      discard <| crosscallValueWordTypes module context expectedType
  | _ => pure ()

def storageCrosscallWordPlans
    (module : Module)
    (context stateId : String)
    (expectedType : ValueType) : Except LowerError (Array ExprPlan) := do
  match expectedType with
  | .structType typeName => do
      discard <| crosscallValueWordTypes module context (.structType typeName)
      let (slot, stateTypeName, decl) ← lowerPlan <| ProofForge.Backend.Evm.Plan.requireStructState module stateId
      ensureType context (.structType typeName) (.structType stateTypeName)
      let mut plans : Array ExprPlan := #[]
      for h : idx in [0:decl.fields.size] do
        let field := decl.fields[idx]
        ensureStructLocalFieldType typeName field.id field.type
        plans := plans.push (.storageLoad (.scalarSlot (slot + idx)))
      .ok plans
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address | .unit
  | .fixedArray _ _ | .bytes | .string | .array _ =>
      .error {
        message := s!"{context} storage-backed crosscall word expansion supports struct scalar storage only, got `{expectedType.name}`"
      }

def wrapCrosscallExprWordPlans (plans : Array ExprPlan) : Array CrosscallArgWordPlan :=
  plans.map CrosscallArgWordPlan.expr

def storageArrayAbiWordPlans
    (module : Module)
    (context stateId : String)
    (elementType : ValueType)
    (length : Nat) : Except LowerError (Array ExprPlan) := do
  match elementType with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => do
      let (slot, stateLength, stateElementType) ← lowerPlan <| ProofForge.Backend.Evm.Plan.requireArrayState module stateId
      if stateLength != length then
        .error { message := s!"{context} storage array `{stateId}` expected length {length}, got {stateLength}" }
      ensureType s!"{context} storage array `{stateId}` element type" elementType stateElementType
      let mut plans : Array ExprPlan := #[]
      for _h : idx in [0:length] do
        plans := plans.push (.storageLoad (.arraySlot slot stateLength (.irExpr (.literal (.u64 idx)))))
      .ok plans
  | .structType typeName => do
      let some decl := ProofForge.Backend.Evm.Validate.findStruct? module typeName
        | .error { message := s!"{context} storage array `{stateId}` uses unknown struct `{typeName}`" }
      match ProofForge.Backend.Evm.Validate.stateInfo? module stateId with
      | some (_, { kind := .array stateLength, type := .structType stateTypeName, .. }) => do
          if stateLength != length then
            .error { message := s!"{context} storage struct array `{stateId}` expected length {length}, got {stateLength}" }
          if stateTypeName != typeName then
            .error { message := s!"{context} storage struct array `{stateId}` expected struct `{typeName}`, got `{stateTypeName}`" }
      | some (_, state) =>
          .error { message := s!"{context} storage struct array `{stateId}` expected fixed array of struct `{typeName}`, got `{state.type.name}`" }
      | none =>
          .error { message := s!"unknown struct array state `{stateId}`" }
      let mut plans : Array ExprPlan := #[]
      for _h : idx in [0:length] do
        for fieldDecl in decl.fields do
          let (slot, stateLength, fieldCount, fieldOffset, field) ←
            lowerPlan <| ProofForge.Backend.Evm.Plan.requireStructArrayStateField module stateId fieldDecl.id
          ensureType s!"{context} storage struct array `{stateId}` field `{fieldDecl.id}`" fieldDecl.type field.type
          plans := plans.push
            (.storageLoad
              (.structArrayFieldSlot
                slot
                stateLength
                fieldCount
                fieldOffset
                (.irExpr (.literal (.u64 idx)))))
      .ok plans
  | .unit | .fixedArray _ _ | .bytes | .string | .array _ =>
      .error {
        message := s!"{context} storage-backed ABI word expansion has unsupported fixed-array element type `{elementType.name}`"
      }

def storageAbiWordPlans
    (module : Module)
    (context stateId : String)
    (expectedType : ValueType) : Except LowerError (Array ExprPlan) := do
  match expectedType with
  | .structType typeName => do
      let (slot, stateTypeName, decl) ← lowerPlan <| ProofForge.Backend.Evm.Plan.requireStructState module stateId
      ensureType context (.structType typeName) (.structType stateTypeName)
      let mut plans : Array ExprPlan := #[]
      for h : idx in [0:decl.fields.size] do
        let field := decl.fields[idx]
        ensureStructLocalFieldType typeName field.id field.type
        plans := plans.push (.storageLoad (.scalarSlot (slot + idx)))
      .ok plans
  | .fixedArray elementType length =>
      storageArrayAbiWordPlans module context stateId elementType length
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address | .unit
  | .bytes | .string | .array _ =>
      .error {
        message := s!"{context} storage-backed ABI word expansion supports struct scalar storage or fixed storage arrays only, got `{expectedType.name}`"
      }

partial def localAbiWordPlansAt
    (module : Module)
    (context name : String)
    (path : Array Nat) : ValueType → Except LowerError (Array ExprPlan)
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address =>
      if path.isEmpty then
        .ok #[.local name]
      else
        .ok #[.local (arrayLocalPathName name path)]
  | .unit =>
      .error {
        message := s!"{context} uses Unit; IR EVM v0 ABI values must use U32, U64, Bool, Hash, Address, Bytes, String, fixed arrays, or structs"
      }
  | .bytes | .string | .array _ =>
      if path.isEmpty then
        .ok #[.local (dynamicParamDataPtrName name)]
      else
        .error { message := s!"{context} dynamic type cannot be nested in fixed arrays" }
  | .fixedArray elementType length => do
      if length == 0 then
        .error {
          message := s!"{context} uses Array<{elementType.name},0>; IR EVM v0 ABI fixed arrays must have non-zero length"
        }
      let mut plans : Array ExprPlan := #[]
      for _h : idx in [0:length] do
        plans := plans ++ (← localAbiWordPlansAt module context name (path.push idx) elementType)
      .ok plans
  | .structType typeName => do
      let fields ← localAbiStructFields module context typeName
      let mut plans : Array ExprPlan := #[]
      for field in fields do
        let fieldName :=
          if path.isEmpty then
            structLocalFieldName name field.fst
          else
            arrayStructLocalPathFieldName name path field.fst
        plans := plans.push (.local fieldName)
      .ok plans

def localAbiWordPlans
    (module : Module)
    (env : TypeEnv)
    (context name : String)
    (expectedType : ValueType) : Except LowerError (Array ExprPlan) := do
  validateLocalAbiWordPlan module env context name expectedType
  localAbiWordPlansAt module context name #[] expectedType

partial def abiValueWordPlans
    (module : Module)
    (env : TypeEnv)
    (context : String)
    (type : ValueType)
    (value : AbiValuePlan) : Except LowerError (Array ExprPlan) := do
  match type with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address =>
      match value with
      | .expr plan => .ok #[plan]
      | _ =>
          .error { message := s!"{context} scalar ABI value requires an expression plan" }
  | .fixedArray elementType length =>
      match value with
      | .local name plannedType =>
          if plannedType == type then
            localAbiWordPlans module env context name type
          else
            .error {
              message := s!"{context} local ABI word plan type mismatch: expected `{type.name}`, got `{plannedType.name}`"
            }
      | .storage stateId plannedType =>
          if plannedType == type then
            storageAbiWordPlans module context stateId type
          else
            .error {
              message := s!"{context} storage ABI word plan type mismatch: expected `{type.name}`, got `{plannedType.name}`"
            }
      | .arrayLit literalElementType values => do
          if literalElementType != elementType then
            .error {
              message := s!"{context} fixed-array literal element type mismatch: expected `{elementType.name}`, got `{literalElementType.name}`"
            }
          if values.size != length then
            .error { message := s!"{context} fixed-array expected length {length}, got {values.size}" }
          let mut plans : Array ExprPlan := #[]
          for h : idx in [0:values.size] do
            plans := plans ++
              (← abiValueWordPlans
                module
                env
                s!"{context} fixed-array element {idx}"
                elementType
                values[idx])
          .ok plans
      | _ =>
          .error { message := s!"{context} aggregate field requires an ABI word expansion plan" }
  | .structType typeName =>
      match value with
      | .local name plannedType =>
          if plannedType == type then
            localAbiWordPlans module env context name type
          else
            .error {
              message := s!"{context} local ABI word plan type mismatch: expected `{type.name}`, got `{plannedType.name}`"
            }
      | .storage stateId plannedType =>
          if plannedType == type then
            storageAbiWordPlans module context stateId type
          else
            .error {
              message := s!"{context} storage ABI word plan type mismatch: expected `{type.name}`, got `{plannedType.name}`"
            }
      | .structLit literalTypeName fields => do
          if literalTypeName != typeName then
            .error { message := s!"{context} expected struct `{typeName}`, got `{literalTypeName}`" }
          let fieldDecls ← localAbiStructFields module context typeName
          let mut plans : Array ExprPlan := #[]
          for fieldDecl in fieldDecls do
            let some field := fields.find? fun field => field.fst == fieldDecl.fst
              | .error {
                  message := s!"{context} struct literal `{typeName}` is missing field `{fieldDecl.fst}`"
                }
            plans := plans ++
              (← abiValueWordPlans
                module
                env
                s!"{context} struct field `{fieldDecl.fst}`"
                fieldDecl.snd
                field.snd)
          .ok plans
      | _ =>
          .error { message := s!"{context} aggregate field requires an ABI word expansion plan" }
  | .unit | .bytes | .string | .array _ =>
      .error { message := s!"{context} has unsupported ABI word type `{type.name}`" }

def returnValueWordPlans
    (module : Module)
    (env : TypeEnv)
    (context : String)
    (plan : ReturnValueWordPlan) : Except LowerError (Array ExprPlan) :=
  abiValueWordPlans module env context plan.returns.returnType plan.source

partial def abiValuePlanFromExprPlan
    (module : Module)
    (env : TypeEnv)
    (context : String)
    (expectedType : ValueType)
    (value : ExprPlan) : Except LowerError AbiValuePlan := do
  match expectedType with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address =>
      ensureAbiWordType context expectedType
      .ok (.expr value)
  | .fixedArray elementType length =>
      match value with
      | .local name => do
          validateLocalAbiWordPlan module env context name expectedType
          .ok (.local name expectedType)
      | .arrayLit literalElementType values => do
          if literalElementType != elementType then
            .error {
              message := s!"{context} fixed-array literal element type mismatch: expected `{elementType.name}`, got `{literalElementType.name}`"
            }
          if values.size != length then
            .error { message := s!"{context} fixed-array expected length {length}, got {values.size}" }
          let mut plannedValues : Array AbiValuePlan := #[]
          for h : idx in [0:values.size] do
            plannedValues := plannedValues.push
              (← abiValuePlanFromExprPlan
                module
                env
                s!"{context} fixed-array element {idx}"
                elementType
                values[idx])
          .ok (.arrayLit elementType plannedValues)
      | _ =>
          .error { message := s!"{context} aggregate return requires an ABI word expansion plan" }
  | .structType typeName =>
      match value with
      | .local name => do
          validateLocalAbiWordPlan module env context name expectedType
          .ok (.local name expectedType)
      | .effect (.storageScalarRead stateId) => do
          ensureType s!"{context} storage value" (.structType typeName) (← scalarStateType module stateId)
          .ok (.storage stateId expectedType)
      | .structLit literalTypeName fields => do
          if literalTypeName != typeName then
            .error { message := s!"{context} expected struct `{typeName}`, got `{literalTypeName}`" }
          let fieldDecls ← localAbiStructFields module context typeName
          let mut plannedFields : Array (String × AbiValuePlan) := #[]
          for fieldDecl in fieldDecls do
            let some field := fields.find? fun field => field.fst == fieldDecl.fst
              | .error {
                  message := s!"{context} struct literal `{typeName}` is missing field `{fieldDecl.fst}`"
                }
            plannedFields := plannedFields.push
              (fieldDecl.fst,
                ← abiValuePlanFromExprPlan
                  module
                  env
                  s!"{context} struct field `{fieldDecl.fst}`"
                  fieldDecl.snd
                  field.snd)
          .ok (.structLit typeName plannedFields)
      | _ =>
          .error { message := s!"{context} aggregate return requires an ABI word expansion plan" }
  | .unit | .bytes | .string | .array _ =>
      .error { message := s!"{context} has unsupported ABI return type `{expectedType.name}`" }

def returnValueWordPlanFromExprPlan
    (module : Module)
    (env : TypeEnv)
    (entrypointName : String)
    (returnType : ValueType)
    (value : ExprPlan) : Except LowerError ReturnValueWordPlan := do
  match returnType with
  | .fixedArray _ _ | .structType _ =>
      let context := s!"entrypoint `{entrypointName}` return value"
      let returns ← returnPlan module s!"entrypoint `{entrypointName}`" returnType
      .ok {
        returns
        source := ← abiValuePlanFromExprPlan module env context returnType value
      }
  | _ =>
      .error {
        message := s!"entrypoint `{entrypointName}` return type `{returnType.name}` does not require aggregate return word planning"
      }

def eventFieldDataWordPlans
    (module : Module)
    (env : TypeEnv)
    (eventName : String)
    (field : EventFieldPlan)
    (value : AbiValuePlan) : Except LowerError (Array ExprPlan) :=
  abiValueWordPlans
    module
    env
    s!"planned event `{eventName}` field `{field.name}`"
    field.type
    value

def eventFieldsDataWordPlans
    (module : Module)
    (env : TypeEnv)
    (eventName : String)
    (fields : Array EventFieldPlan)
    (values : Array AbiValuePlan) : Except LowerError (Array ExprPlan) := do
  if fields.size != values.size then
    .error { message := s!"planned scalar control-flow event `{eventName}` field/value count mismatch" }
  let mut plans : Array ExprPlan := #[]
  for h : idx in [0:fields.size] do
    let some value := values[idx]?
      | .error { message := s!"planned scalar control-flow event `{eventName}` missing field value at index {idx}" }
    plans := plans ++ (← eventFieldDataWordPlans module env eventName fields[idx] value)
  .ok plans

def eventFieldWordPlans
    (module : Module)
    (env : TypeEnv)
    (eventName : String)
    (field : EventFieldPlan)
    (value : AbiValuePlan) : Except LowerError (Array ExprPlan) :=
  eventFieldDataWordPlans module env eventName field value

def eventFieldsWordPlans
    (module : Module)
    (env : TypeEnv)
    (event : EventPlan)
    (fields : Array EventFieldPlan)
    (values : Array AbiValuePlan) :
    Except LowerError (Array (Array ExprPlan)) := do
  if fields.size != values.size then
    .error {
      message := s!"planned scalar control-flow event `{event.name}` field/value count mismatch"
    }
  let mut fieldWords : Array (Array ExprPlan) := #[]
  for h : idx in [0:fields.size] do
    let some value := values[idx]?
      | .error {
          message := s!"planned scalar control-flow event `{event.name}` missing field value at index {idx}"
        }
    fieldWords := fieldWords.push (← eventFieldWordPlans module env event.name fields[idx] value)
  .ok fieldWords

def eventEffectWordPlan
    (module : Module)
    (env : TypeEnv) :
    EffectPlan → Except LowerError EffectPlan
  | .eventEmit event dataFields => do
      let dataFieldWords ← eventFieldsWordPlans module env event event.dataFields dataFields
      .ok (.eventEmitWords event dataFieldWords)
  | .eventEmitIndexed event indexedFields dataFields => do
      let indexedFieldWords ← eventFieldsWordPlans module env event event.indexedFields indexedFields
      let dataFieldWords ← eventFieldsWordPlans module env event event.dataFields dataFields
      .ok (.eventEmitIndexedWords event indexedFieldWords dataFieldWords)
  | .eventEmitWords event dataFieldWords =>
      .ok (.eventEmitWords event dataFieldWords)
  | .eventEmitIndexedWords event indexedFieldWords dataFieldWords =>
      .ok (.eventEmitIndexedWords event indexedFieldWords dataFieldWords)
  | _ =>
      .error { message := "planned event lowering expected event emit effect" }

def entrypointSelector (entrypoint : Entrypoint) : Except LowerError String :=
  match entrypoint.selector? with
  | some selector => .ok selector
  | none =>
    if entrypoint.kind == .fallback || entrypoint.kind == .receive then
      .ok ""  -- Fallback/receive don't have selectors
    else
      .error { message := s!"entrypoint `{entrypoint.name}` has no EVM selector metadata" }

/-! Entrypoint body plans carry structural `StmtPlan` / `ExprPlan` nodes.

`IR.lean` remains the compatibility facade that assembles final Yul today, but
the semantic plan now owns a target-validated statement/expression view of each
entrypoint body. Later migration slices can consume these plan nodes directly
instead of re-walking the portable IR at Yul assembly time. -/

def literalPlan : Literal → Except LowerError ExprPlan
  | .u32 value => .ok (.literalWord value)
  | .u64 value => .ok (.literalWord value)
  | .u8 value => .ok (.literalWord value)
  | .u128 value => .ok (.literalWord value)
  | .bool value => .ok (.literalWord (if value then 1 else 0))
  | .hash4 a b c d => do
      .ok (.literalWord (← packedHashLiteral a b c d))
  | .address value => .ok (.literalWord value)

def eventPlanForFields
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (indexedFields dataFields : Array (String × Expr)) :
    Except LowerError EventPlan := do
  validateIndexedEventFieldCount name indexedFields.size
  let fields := indexedFields ++ dataFields
  let signature ← eventSignature module env name fields
  let mut fieldPlans : Array EventFieldPlan := #[]
  for field in indexedFields do
    let fieldType ← inferEventFieldExprType module env field.snd
    fieldPlans := fieldPlans.push (EventFieldPlan.mk field.fst fieldType true)
  for field in dataFields do
    let fieldType ← inferEventFieldExprType module env field.snd
    fieldPlans := fieldPlans.push (EventFieldPlan.mk field.fst fieldType false)
  .ok (EventPlan.mk name signature fieldPlans)

def assignExprPlan (op : AssignOp) (lhs rhs : ExprPlan) : ExprPlan :=
  .checkedArith op lhs rhs

def fixedArrayScalarLeafType? : ValueType → Bool
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => true
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ => false

def storageArrayReadStateAt? (index : Nat) : Expr → Option String
  | .effect (.storageArrayRead stateId indexExpr) =>
      match literalArrayIndex? indexExpr with
      | some value => if value == index then some stateId else none
      | none => none
  | _ => none

def storageArrayReadState? (values : Array Expr) : Option String := Id.run do
  let mut state? : Option String := none
  let mut ok := true
  for h : idx in [0:values.size] do
    match storageArrayReadStateAt? idx values[idx] with
    | some stateId =>
        match state? with
        | none => state? := some stateId
        | some existing =>
            if existing != stateId then
              ok := false
    | none =>
        ok := false
  if ok then
    state?
  else
    none

def storageStructArrayFieldReadStateAt? (index : Nat) (fieldName : String) : Expr → Option String
  | .effect (.storageArrayStructFieldRead stateId indexExpr readFieldName) =>
      match literalArrayIndex? indexExpr with
      | some value =>
          if value == index && readFieldName == fieldName then some stateId else none
      | none => none
  | _ => none

def storageStructArrayElementReadState? (decl : StructDecl) (index : Nat) : Expr → Option String
  | .structLit typeName fields =>
      if typeName != decl.name || fields.size != decl.fields.size then
        none
      else Id.run do
        let mut state? : Option String := none
        let mut ok := true
        for fieldDecl in decl.fields do
          match fields.find? fun field => field.fst == fieldDecl.id with
          | some field =>
            match storageStructArrayFieldReadStateAt? index fieldDecl.id field.snd with
            | some stateId =>
                match state? with
                | none => state? := some stateId
                | some existing =>
                    if existing != stateId then
                      ok := false
            | none =>
                ok := false
          | none =>
              ok := false
        if ok then
          state?
        else
          none
  | _ => none

def storageStructArrayReadState? (decl : StructDecl) (values : Array Expr) : Option String := Id.run do
  let mut state? : Option String := none
  let mut ok := true
  for h : idx in [0:values.size] do
    match storageStructArrayElementReadState? decl idx values[idx] with
    | some stateId =>
        match state? with
        | none => state? := some stateId
        | some existing =>
            if existing != stateId then
              ok := false
    | none =>
        ok := false
  if ok then
    state?
  else
    none

def storageArrayAbiWordsPlan?
    (module : Module)
    (fieldType : ValueType)
    (value : Expr) : Except LowerError (Option AbiValuePlan) := do
  match fieldType, value with
  | .fixedArray (.structType typeName) length, .arrayLit (.structType literalTypeName) values => do
      if literalTypeName != typeName || values.size != length then
        .ok none
      else
        let some decl := ProofForge.Backend.Evm.Validate.findStruct? module typeName
          | .error { message := s!"event storage array ABI word plan uses unknown struct `{typeName}`" }
        match storageStructArrayReadState? decl values with
        | none => .ok none
        | some stateId =>
            match ProofForge.Backend.Evm.Validate.stateInfo? module stateId with
            | some (_, { kind := .array stateLength, type := .structType stateTypeName, .. }) =>
                if stateLength == length && stateTypeName == typeName then
                  .ok (some (.storage stateId fieldType))
                else
                  .ok none
            | _ => .ok none
  | .fixedArray elementType length, .arrayLit literalElementType values => do
      if literalElementType != elementType || values.size != length then
        .ok none
      else
        match storageArrayReadState? values with
        | none => .ok none
        | some stateId => do
            let (_, stateLength, stateElementType) ← lowerPlan <| requireArrayState module stateId
            if stateLength == length && stateElementType == elementType then
              .ok (some (.storage stateId fieldType))
            else
              .ok none
  | _, _ =>
      .ok none

def ensureExpressionCrosscallReturnWord
    (modeLabel : String)
    (returnType : ValueType) : Except LowerError Unit :=
  if isCrosscallWordType returnType then
    .ok ()
  else
    .error {
      message := s!"{modeLabel} aggregate crosscall return `{returnType.name}` must be consumed by aggregate return lowering in IR EVM v0"
    }

mutual
  partial def localArrayGetExprPlan?
      (module : Module)
      (env : TypeEnv)
      (array index : Expr) : Except LowerError (Option ExprPlan) := do
    let fullExpr := Expr.arrayGet array index
    match collectLocalArrayGetPath fullExpr with
    | some (name, path) => do
        let some binding := findLocal? env name
          | .error { message := s!"unknown local `{name}`" }
        let (lengths, leafType) ← fixedArrayPathShape "fixed array index" binding.type path
        if fixedArrayScalarLeafType? leafType then
          .ok (some (.localArrayGet name (← path.mapM (buildExprPlan module env)) lengths))
        else
          .ok none
    | none =>
        .ok none

  partial def localArrayStructFieldExprPlan?
      (module : Module)
      (env : TypeEnv)
      (base : Expr)
      (fieldName : String) : Except LowerError (Option ExprPlan) := do
    match collectLocalArrayGetPath base with
    | some (name, path) => do
        let some binding := findLocal? env name
          | .error { message := s!"unknown local `{name}`" }
        let (lengths, leafType) ← fixedArrayPathShape "struct field fixed-array index" binding.type path
        match leafType with
        | .structType typeName => do
            discard <| ensureLocalFlatStructType module s!"struct field access local `{name}` fixed-array leaf" typeName
            let fieldType ← structFieldType module typeName fieldName
            ensureStructLocalFieldType typeName fieldName fieldType
            .ok (some <|
              .structField
                (.localArrayGet name (← path.mapM (buildExprPlan module env)) lengths)
                fieldName)
        | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address
        | .unit | .fixedArray _ _ | .array _ | .bytes | .string =>
            .ok none
    | none =>
        .ok none

  partial def buildCrosscallStructArgWordPlans
      (module : Module)
      (env : TypeEnv)
      (context typeName : String)
      (arg : Expr) : Except LowerError (Array CrosscallArgWordPlan) := do
    discard <| crosscallArgWordTypes module context (.structType typeName)
    let some decl := ProofForge.Backend.Evm.Validate.findStruct? module typeName
      | .error { message := s!"{context} uses unknown struct `{typeName}`" }
    match arg with
    | .local name =>
        ensureType context (.structType typeName) (← inferExprType module env arg)
        .ok #[.local name (.structType typeName)]
    | .structLit literalTypeName fields => do
        if literalTypeName != typeName then
          .error { message := s!"{context} expected struct `{typeName}`, got `{literalTypeName}`" }
        let mut plans : Array CrosscallArgWordPlan := #[]
        for fieldDecl in decl.fields do
          ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
          let some field := fields.find? fun field => field.fst == fieldDecl.id
            | .error { message := s!"struct literal `{typeName}` is missing field `{fieldDecl.id}`" }
          plans := plans.push (.expr (← buildExprPlan module env field.snd))
        .ok plans
    | .effect (.storageScalarRead stateId) => do
        discard <| storageCrosscallWordPlans module context stateId (.structType typeName)
        .ok #[.storage stateId (.structType typeName)]
    | _ =>
        .error {
          message := s!"{context} struct values in IR EVM v0 support local struct values, struct literals, or storage scalar struct reads only"
        }

  partial def buildCrosscallStructArrayArgWordPlans
      (module : Module)
      (env : TypeEnv)
      (context typeName : String)
      (length : Nat)
      (arg : Expr) : Except LowerError (Array CrosscallArgWordPlan) := do
    discard <| crosscallArgWordTypes module context (.fixedArray (.structType typeName) length)
    match arg with
    | .local name =>
        ensureType context (.fixedArray (.structType typeName) length) (← inferExprType module env arg)
        .ok #[.local name (.fixedArray (.structType typeName) length)]
    | .arrayLit literalElementType values => do
        ensureType s!"{context} fixed-array element type" (.structType typeName) literalElementType
        if values.size != length then
          .error { message := s!"{context} fixed-array expected length {length}, got {values.size}" }
        let mut plans : Array CrosscallArgWordPlan := #[]
        for h : idx in [0:values.size] do
          match values[idx] with
          | .structLit .. =>
              plans := plans ++ (← buildCrosscallStructArgWordPlans module env context typeName values[idx])
          | other =>
              let actualType ← inferExprType module env other
              .error {
                message := s!"{context} fixed-array element {idx} expected struct literal `{typeName}`, got `{actualType.name}`"
              }
        .ok plans
    | _ =>
        .error {
          message := s!"{context} fixed-array struct values in IR EVM v0 support local fixed-array values or array literals only"
        }

  partial def buildCrosscallFixedArrayArgWordPlans
      (module : Module)
      (env : TypeEnv)
      (context : String)
      (elementType : ValueType)
      (length : Nat)
      (arg : Expr) : Except LowerError (Array CrosscallArgWordPlan) := do
    discard <| crosscallArgWordTypes module context (.fixedArray elementType length)
    match elementType with
    | .structType typeName =>
        buildCrosscallStructArrayArgWordPlans module env context typeName length arg
    | .fixedArray nestedElementType nestedLength =>
        match arg with
        | .local name =>
            ensureType context (.fixedArray elementType length) (← inferExprType module env arg)
            .ok #[.local name (.fixedArray elementType length)]
        | .arrayLit literalElementType values => do
            ensureType s!"{context} fixed-array element type" elementType literalElementType
            if values.size != length then
              .error { message := s!"{context} fixed-array expected length {length}, got {values.size}" }
            let mut plans : Array CrosscallArgWordPlan := #[]
            for h : idx in [0:values.size] do
              plans := plans ++ (← buildCrosscallFixedArrayArgWordPlans module env context nestedElementType nestedLength values[idx])
            .ok plans
        | _ =>
            .error {
              message := s!"{context} nested fixed-array values in IR EVM v0 support local fixed-array values or array literals only"
            }
    | _ =>
        match arg with
        | .local name =>
            ensureType context (.fixedArray elementType length) (← inferExprType module env arg)
            .ok #[.local name (.fixedArray elementType length)]
        | .arrayLit literalElementType values => do
            ensureType s!"{context} fixed-array element type" elementType literalElementType
            if values.size != length then
              .error { message := s!"{context} fixed-array expected length {length}, got {values.size}" }
            let mut plans : Array CrosscallArgWordPlan := #[]
            for h : idx in [0:values.size] do
              plans := plans.push (.expr (← buildExprPlan module env values[idx]))
            .ok plans
        | _ =>
            .error {
              message := s!"{context} fixed-array values in IR EVM v0 support local fixed-array values or array literals only"
            }

  partial def buildCrosscallArgWordPlans
      (module : Module)
      (env : TypeEnv)
      (context : String)
      (arg : Expr) : Except LowerError (Array CrosscallArgWordPlan) := do
    let type ← inferExprType module env arg
    discard <| crosscallArgWordTypes module context type
    match type with
    | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address =>
        .ok #[.expr (← buildExprPlan module env arg)]
    | .fixedArray elementType length =>
        match arg with
        | .local name =>
            .ok #[.local name type]
        | _ =>
            buildCrosscallFixedArrayArgWordPlans module env context elementType length arg
    | .structType typeName =>
        match arg with
        | .local name =>
            .ok #[.local name type]
        | _ =>
            buildCrosscallStructArgWordPlans module env context typeName arg
    | .array _ =>
        .error { message := s!"{context} uses dynamic array; IR EVM v0 crosscall arguments do not yet support dynamic arrays" }
    | .unit | .bytes | .string =>
        .error { message := s!"{context} uses Unit; IR EVM v0 crosscall arguments must use U32, U64, Bool, Hash, fixed arrays, or structs" }

  partial def buildCrosscallArgWordPlansMany
      (module : Module)
      (env : TypeEnv)
      (context : String)
      (args : Array Expr) : Except LowerError (Array CrosscallArgWordPlan) := do
    let mut plans : Array CrosscallArgWordPlan := #[]
    for arg in args do
      plans := plans ++ (← buildCrosscallArgWordPlans module env context arg)
    .ok plans

  partial def buildExprPlan (module : Module) (env : TypeEnv) : Expr → Except LowerError ExprPlan
    | .literal value => literalPlan value
    | .local name => .ok (.local name)
    | .arrayLit elementType values => do
        let planned ← values.mapM (buildExprPlan module env)
        .ok (.arrayLit elementType planned)
    | .arrayGet array index => do
        match ← localArrayGetExprPlan? module env array index with
        | some plan => .ok plan
        | none => .ok (.arrayGet (← buildExprPlan module env array) (← buildExprPlan module env index))
    | .memoryArrayNew elementType length => do
        .ok (.memoryArrayNew elementType (← buildExprPlan module env length))
    | .memoryArrayLength array => do
        .ok (.memoryArrayLength (← buildExprPlan module env array))
    | .memoryArrayGet array index => do
        .ok (.memoryArrayGet (← buildExprPlan module env array) (← buildExprPlan module env index))
    | .structLit typeName fields => do
        let mut planned : Array (String × ExprPlan) := #[]
        for field in fields do
          planned := planned.push (field.fst, ← buildExprPlan module env field.snd)
        .ok (.structLit typeName planned)
    | .field base fieldName => do
        match ← localArrayStructFieldExprPlan? module env base fieldName with
        | some plan => .ok plan
        | none => .ok (.structField (← buildExprPlan module env base) fieldName)
    | .add lhs rhs => do
        .ok (assignExprPlan .add (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .sub lhs rhs => do
        .ok (assignExprPlan .sub (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .mul lhs rhs => do
        .ok (assignExprPlan .mul (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .div lhs rhs => do
        .ok (assignExprPlan .div (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .mod lhs rhs => do
        .ok (assignExprPlan .mod (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .pow lhs rhs => do
        .ok (.builtin "exp" #[← buildExprPlan module env lhs, ← buildExprPlan module env rhs])
    | .bitAnd lhs rhs => do
        .ok (assignExprPlan .bitAnd (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .bitOr lhs rhs => do
        .ok (assignExprPlan .bitOr (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .bitXor lhs rhs => do
        .ok (assignExprPlan .bitXor (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .shiftLeft lhs rhs => do
        .ok (assignExprPlan .shiftLeft (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .shiftRight lhs rhs => do
        .ok (assignExprPlan .shiftRight (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .cast value targetType => do
        .ok (.cast (← buildExprPlan module env value) targetType)
    | .eq lhs rhs => do
        .ok (.builtin "eq" #[← buildExprPlan module env lhs, ← buildExprPlan module env rhs])
    | .ne lhs rhs => do
        .ok (.builtin "iszero" #[.builtin "eq" #[← buildExprPlan module env lhs, ← buildExprPlan module env rhs]])
    | .lt lhs rhs => do
        .ok (.builtin "lt" #[← buildExprPlan module env lhs, ← buildExprPlan module env rhs])
    | .le lhs rhs => do
        .ok (.builtin "iszero" #[.builtin "gt" #[← buildExprPlan module env lhs, ← buildExprPlan module env rhs]])
    | .gt lhs rhs => do
        .ok (.builtin "gt" #[← buildExprPlan module env lhs, ← buildExprPlan module env rhs])
    | .ge lhs rhs => do
        .ok (.builtin "iszero" #[.builtin "lt" #[← buildExprPlan module env lhs, ← buildExprPlan module env rhs]])
    | .boolAnd lhs rhs => do
        .ok (.builtin "and" #[← buildExprPlan module env lhs, ← buildExprPlan module env rhs])
    | .boolOr lhs rhs => do
        .ok (.builtin "or" #[← buildExprPlan module env lhs, ← buildExprPlan module env rhs])
    | .boolNot value => do
        .ok (.builtin "iszero" #[← buildExprPlan module env value])
    | .hashValue a b c d => do
        .ok (.hashValue
          (← buildExprPlan module env a)
          (← buildExprPlan module env b)
          (← buildExprPlan module env c)
          (← buildExprPlan module env d))
    | .hash preimage => do
        .ok (.hash (← buildExprPlan module env preimage))
    | .hashTwoToOne lhs rhs => do
        .ok (.hashTwoToOne (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .nativeValue =>
        .ok .nativeValue
    | .crosscallInvoke target methodId args => do
        .ok (.crosscall .call
          (← buildExprPlan module env target)
          (← buildExprPlan module env methodId)
          none
          (wrapCrosscallExprWordPlans (← args.mapM (buildExprPlan module env)))
          .u64)
    | .crosscallInvokeTyped target methodId args returnType => do
        .ok (.crosscall .call
          (← buildExprPlan module env target)
          (← buildExprPlan module env methodId)
          none
          (← buildCrosscallArgWordPlansMany module env "typed crosscall argument" args)
          returnType)
    | .crosscallInvokeValueTyped target methodId callValue args returnType => do
        .ok (.crosscall .callValue
          (← buildExprPlan module env target)
          (← buildExprPlan module env methodId)
          (some (← buildExprPlan module env callValue))
          (← buildCrosscallArgWordPlansMany module env "value crosscall argument" args)
          returnType)
    | .crosscallInvokeStaticTyped target methodId args returnType => do
        .ok (.crosscall .staticcall
          (← buildExprPlan module env target)
          (← buildExprPlan module env methodId)
          none
          (← buildCrosscallArgWordPlansMany module env "static crosscall argument" args)
          returnType)
    | .crosscallInvokeDelegateTyped target methodId args returnType => do
        .ok (.crosscall .delegatecall
          (← buildExprPlan module env target)
          (← buildExprPlan module env methodId)
          none
          (← buildCrosscallArgWordPlansMany module env "delegate crosscall argument" args)
          returnType)
    | .crosscallCreate callValue initCodeHex => do
        .ok (.create .create (← buildExprPlan module env callValue) none initCodeHex)
    | .crosscallCreate2 callValue salt initCodeHex => do
        .ok (.create .create2
          (← buildExprPlan module env callValue)
          (some (← buildExprPlan module env salt))
          initCodeHex)
    | .effect effect => do
        .ok (.effect (← buildEffectPlan module env effect))

  partial def buildAbiValuePlan
      (module : Module)
      (env : TypeEnv)
      (context : String)
      (expectedType : ValueType)
      (value : Expr) : Except LowerError AbiValuePlan := do
    ensureType context expectedType (← inferExprType module env value)
    match expectedType, value with
    | .fixedArray _ _, .local name
    | .structType _, .local name => do
        let some binding := findLocal? env name
          | .error { message := s!"unknown local `{name}`" }
        ensureType s!"{context} local value" expectedType binding.type
        .ok (.local name expectedType)
    | .structType typeName, .effect (.storageScalarRead stateId) => do
        ensureType s!"{context} storage value" (.structType typeName) (← scalarStateType module stateId)
        .ok (.storage stateId expectedType)
    | .fixedArray elementType length, .arrayLit literalElementType values => do
        match ← storageArrayAbiWordsPlan? module expectedType value with
        | some plan => .ok plan
        | none => do
            if literalElementType != elementType then
              .error {
                message := s!"{context} fixed-array literal element type mismatch: expected `{elementType.name}`, got `{literalElementType.name}`"
              }
            if values.size != length then
              .error { message := s!"{context} fixed-array expected length {length}, got {values.size}" }
            let mut plannedValues : Array AbiValuePlan := #[]
            for h : idx in [0:values.size] do
              plannedValues := plannedValues.push
                (← buildAbiValuePlan
                  module
                  env
                  s!"{context} fixed-array element {idx}"
                  elementType
                  values[idx])
            .ok (.arrayLit elementType plannedValues)
    | .fixedArray _ _, _ => do
        match ← storageArrayAbiWordsPlan? module expectedType value with
        | some plan => .ok plan
        | none => .ok (.expr (← buildExprPlan module env value))
    | .structType typeName, .structLit literalTypeName fields => do
        if literalTypeName != typeName then
          .error { message := s!"{context} expected struct `{typeName}`, got `{literalTypeName}`" }
        let fieldDecls ← localAbiStructFields module context typeName
        let mut plannedFields : Array (String × AbiValuePlan) := #[]
        for fieldDecl in fieldDecls do
          let some field := fields.find? fun field => field.fst == fieldDecl.fst
            | .error {
                message := s!"{context} struct literal `{typeName}` is missing field `{fieldDecl.fst}`"
              }
          plannedFields := plannedFields.push
            (fieldDecl.fst,
              ← buildAbiValuePlan
                module
                env
                s!"{context} struct field `{fieldDecl.fst}`"
                fieldDecl.snd
                field.snd)
        .ok (.structLit typeName plannedFields)
    | _, _ =>
        .ok (.expr (← buildExprPlan module env value))

  partial def buildStoragePathSegmentPlan
      (module : Module)
      (env : TypeEnv) :
      StoragePathSegment → Except LowerError StoragePathPlanSegment
    | .mapKey key => do
        .ok (.mapKey (← buildExprPlan module env key))
    | .index index => do
        .ok (.index (← buildExprPlan module env index))
    | .field fieldName => .ok (.field fieldName)

  partial def buildStoragePathPlan
      (module : Module)
      (env : TypeEnv)
      (path : Array StoragePathSegment) :
      Except LowerError (Array StoragePathPlanSegment) :=
    path.mapM (buildStoragePathSegmentPlan module env)

  partial def buildContextExprPlan
      (module : Module)
      (env : TypeEnv) :
      ContextField → Except LowerError ContextExprPlan
    | .userId => .ok .userId
    | .contractId => .ok .contractId
    | .checkpointId => .ok .checkpointId
    | .timestamp => .ok .timestamp
    | .chainId => .ok .chainId
    | .gasPrice => .ok .gasPrice
    | .gasLeft => .ok .gasLeft
    | .baseFee => .ok .baseFee
    | .prevRandao => .ok .prevRandao
    | .origin => .ok .origin
    | .coinbase => .ok .coinbase
    | .blockHash blockNumber => do
        .ok (.blockHash (← buildExprPlan module env blockNumber))

  partial def buildEventFieldValuePlan
      (module : Module)
      (env : TypeEnv)
      (eventName fieldName : String)
      (fieldType : ValueType)
      (value : Expr) : Except LowerError AbiValuePlan := do
    let context := s!"event `{eventName}` field `{fieldName}`"
    ensureType context fieldType (← inferEventFieldExprType module env value)
    buildAbiValuePlan module env context fieldType value

  partial def buildEffectPlan (module : Module) (env : TypeEnv) : Effect → Except LowerError EffectPlan
    | .storageScalarRead stateId =>
        match scalarStorageTargetPlan? module stateId with
        | some target => .ok (.storageScalarReadTarget target)
        | none => .ok (.storageScalarRead stateId)
    | .storageScalarWrite stateId value => do
        let valuePlan ← buildExprPlan module env value
        match scalarStorageTargetPlan? module stateId with
        | some target => .ok (.storageScalarWriteTarget target valuePlan)
        | none => .ok (.storageScalarWrite stateId valuePlan)
    | .storageScalarAssignOp stateId op value => do
        let valuePlan ← buildExprPlan module env value
        match scalarStorageTargetPlan? module stateId with
        | some target => .ok (.storageScalarAssignOpTarget target op valuePlan)
        | none => .ok (.storageScalarAssignOp stateId op valuePlan)
    | .storageMapContains stateId key => do
        let keyPlan ← buildExprPlan module env key
        match mapReadTargetPlan? module stateId with
        | some target => .ok (.storageMapContainsTarget target keyPlan)
        | none => .ok (.storageMapContains stateId keyPlan)
    | .storageMapGet stateId key => do
        let keyPlan ← buildExprPlan module env key
        match mapReadTargetPlan? module stateId with
        | some target => .ok (.storageMapGetTarget target keyPlan)
        | none => .ok (.storageMapGet stateId keyPlan)
    | .storageMapInsert stateId key value => do
        let keyPlan ← buildExprPlan module env key
        let valuePlan ← buildExprPlan module env value
        match mapWriteTargetPlan? module stateId with
        | some target => .ok (.storageMapInsertTarget target keyPlan valuePlan)
        | none => .ok (.storageMapInsert stateId keyPlan valuePlan)
    | .storageMapSet stateId key value => do
        let keyPlan ← buildExprPlan module env key
        let valuePlan ← buildExprPlan module env value
        match mapWriteTargetPlan? module stateId with
        | some target => .ok (.storageMapSetTarget target keyPlan valuePlan)
        | none => .ok (.storageMapSet stateId keyPlan valuePlan)
    | .storageArrayRead stateId index => do
        let indexPlan ← buildExprPlan module env index
        match arrayReadTargetPlan? module stateId with
        | some target => .ok (.storageArrayReadTarget target indexPlan)
        | none => .ok (.storageArrayRead stateId indexPlan)
    | .storageArrayWrite stateId index value => do
        let indexPlan ← buildExprPlan module env index
        let valuePlan ← buildExprPlan module env value
        match arrayWriteTargetPlan? module stateId with
        | some target => .ok (.storageArrayWriteTarget target indexPlan valuePlan)
        | none => .ok (.storageArrayWrite stateId indexPlan valuePlan)
    | .storageArrayStructFieldRead stateId index fieldName => do
        let indexPlan ← buildExprPlan module env index
        match structArrayFieldReadTargetPlan? module stateId fieldName with
        | some target => .ok (.storageArrayStructFieldReadTarget target indexPlan)
        | none => .ok (.storageArrayStructFieldRead stateId indexPlan fieldName)
    | .storageArrayStructFieldWrite stateId index fieldName value => do
        let indexPlan ← buildExprPlan module env index
        let valuePlan ← buildExprPlan module env value
        match structArrayFieldWriteTargetPlan? module stateId fieldName with
        | some target => .ok (.storageArrayStructFieldWriteTarget target indexPlan valuePlan)
        | none => .ok (.storageArrayStructFieldWrite stateId indexPlan fieldName valuePlan)
    | .storageDynamicArrayPush stateId value => do
        .ok (.storageDynamicArrayPush stateId (← buildExprPlan module env value))
    | .storageDynamicArrayPop stateId =>
        .ok (.storageDynamicArrayPop stateId)
    | .memoryArraySet array index value => do
        let arrayPlan ← buildExprPlan module env array
        let indexPlan ← buildExprPlan module env index
        let valuePlan ← buildExprPlan module env value
        .ok (.memoryArraySet arrayPlan indexPlan valuePlan)
    | .storageStructFieldRead stateId fieldName => do
        match structFieldReadTargetPlan? module stateId fieldName with
        | some target => .ok (.storageStructFieldReadTarget target)
        | none => .ok (.storageStructFieldRead stateId fieldName)
    | .storageStructFieldWrite stateId fieldName value => do
        let valuePlan ← buildExprPlan module env value
        match structFieldWriteTargetPlan? module stateId fieldName with
        | some target => .ok (.storageStructFieldWriteTarget target valuePlan)
        | none => .ok (.storageStructFieldWrite stateId fieldName valuePlan)
    | .storagePathRead stateId path => do
        let plannedPath ← buildStoragePathPlan module env path
        let slot ← lowerPlan <| storagePathReadExprSlotPlan module stateId plannedPath
        .ok (.storagePathReadExprTarget slot)
    | .storagePathWrite stateId path value => do
        let plannedPath ← buildStoragePathPlan module env path
        let target ← lowerPlan <| storagePathWriteExprTargetPlan module stateId plannedPath
        .ok (.storagePathWriteExprTarget target (← buildExprPlan module env value))
    | .storagePathAssignOp stateId path op value => do
        let plannedPath ← buildStoragePathPlan module env path
        let target ← lowerPlan <| storagePathWriteExprTargetPlan module stateId plannedPath
        .ok (.storagePathAssignOpExprTarget target op (← buildExprPlan module env value))
    | .contextRead field => do
        .ok (.contextRead (← buildContextExprPlan module env field))
    | .eventEmit name fields => do
        let eventPlan ← eventPlanForFields module env name #[] fields
        let dataFields := eventPlan.dataFields
        let plannedFields ← fields.mapIdxM fun idx field => do
          let some fieldPlan := dataFields[idx]?
            | .error { message := s!"event `{name}` missing data field plan at index {idx}" }
          buildEventFieldValuePlan module env name field.fst fieldPlan.type field.snd
        eventEffectWordPlan module env (.eventEmit eventPlan plannedFields)
    | .eventEmitIndexed name indexedFields dataFields => do
        let eventPlan ← eventPlanForFields module env name indexedFields dataFields
        let indexedPlans := eventPlan.indexedFields
        let dataPlans := eventPlan.dataFields
        let plannedIndexed ← indexedFields.mapIdxM fun idx field => do
          let some fieldPlan := indexedPlans[idx]?
            | .error { message := s!"event `{name}` missing indexed field plan at index {idx}" }
          buildEventFieldValuePlan module env name field.fst fieldPlan.type field.snd
        let plannedData ← dataFields.mapIdxM fun idx field => do
          let some fieldPlan := dataPlans[idx]?
            | .error { message := s!"event `{name}` missing data field plan at index {idx}" }
          buildEventFieldValuePlan module env name field.fst fieldPlan.type field.snd
        eventEffectWordPlan module env (.eventEmitIndexed eventPlan plannedIndexed plannedData)

  partial def buildStatementPlan
      (module : Module)
      (entrypoint : Entrypoint)
      (env : TypeEnv) :
      Statement → Except LowerError (StmtPlan × TypeEnv)
    | .letBind name type value => do
        ensureType s!"let binding `{name}`" type (← inferExprType module env value)
        let valuePlan ← buildExprPlan module env value
        let nextEnv ← addLocal env name type false
        .ok (.letBind name type valuePlan, nextEnv)
    | .letMutBind name type value => do
        ensureType s!"mutable let binding `{name}`" type (← inferExprType module env value)
        let valuePlan ← buildExprPlan module env value
        let nextEnv ← addLocal env name type true
        .ok (.letMutBind name type valuePlan, nextEnv)
    | .assign target value => do
        let targetPlan ← buildExprPlan module env target
        let valuePlan ← buildExprPlan module env value
        .ok (.assign targetPlan valuePlan, env)
    | .assignOp target op value => do
        let targetPlan ← buildExprPlan module env target
        let valuePlan ← buildExprPlan module env value
        .ok (.assignOp targetPlan op valuePlan, env)
    | .effect effect => do
        .ok (.effect (← buildEffectPlan module env effect), env)
    | .assert condition message errorRef? => do
        ensureType "assert condition" .bool (← inferExprType module env condition)
        .ok (.assert (← buildExprPlan module env condition) message errorRef?, env)
    | .assertEq lhs rhs message errorRef? => do
        let lhsType ← inferExprType module env lhs
        ensureType "assert_eq right operand" lhsType (← inferExprType module env rhs)
        ensureEqType "assert_eq" lhsType
        .ok (.assertEq (← buildExprPlan module env lhs) (← buildExprPlan module env rhs) message errorRef?, env)
    | .release name =>
        .ok (.release name, env)
    | .revert message => .ok (.revert message, env)
    | .revertWithError errorRef => .ok (.revertWithError errorRef, env)
    | .ifElse condition thenBody elseBody => do
        ensureType "if condition" .bool (← inferExprType module env condition)
        let (thenPlans, _) ← buildStatementPlans module entrypoint env thenBody
        let (elsePlans, _) ← buildStatementPlans module entrypoint env elseBody
        .ok (.ifElse (← buildExprPlan module env condition) thenPlans elsePlans, env)
    | .boundedFor indexName start stopExclusive body => do
        if stopExclusive <= start then
          .error { message := s!"bounded loop `{indexName}` must have stop greater than start" }
        let loopEnv ← addLocal env indexName .u32 false
        let (bodyPlans, _) ← buildStatementPlans module entrypoint loopEnv body
        .ok (.boundedFor indexName start stopExclusive bodyPlans, env)
    | .whileLoop _ _ =>
        .error { message := "while loops are not supported by EVM IR v0; use boundedFor" }
    | .return value => do
        ensureType "return value" entrypoint.returns (← inferExprType module env value)
        .ok (.return (← buildExprPlan module env value), env)

  partial def buildStatementPlans
      (module : Module)
      (entrypoint : Entrypoint)
      (env : TypeEnv)
      (statements : Array Statement) :
      Except LowerError (Array StmtPlan × TypeEnv) := do
    statements.foldlM (init := (#[], env)) fun acc stmt => do
      let (plans, currentEnv) := acc
      let (stmtPlan, nextEnv) ← buildStatementPlan module entrypoint currentEnv stmt
      .ok (plans.push stmtPlan, nextEnv)
end

def buildExpressionExprPlan
    (module : Module)
    (env : TypeEnv)
    (expr : Expr) : Except LowerError ExprPlan := do
  match expr with
  | .crosscallInvokeTyped _ _ _ returnType =>
      ensureExpressionCrosscallReturnWord "typed" returnType
  | .crosscallInvokeValueTyped _ _ _ _ returnType =>
      ensureExpressionCrosscallReturnWord "value" returnType
  | .crosscallInvokeStaticTyped _ _ _ returnType =>
      ensureExpressionCrosscallReturnWord "static" returnType
  | .crosscallInvokeDelegateTyped _ _ _ returnType =>
      ensureExpressionCrosscallReturnWord "delegate" returnType
  | _ => pure ()
  buildExprPlan module env expr

def crosscallModeArgContext : CrosscallMode → String
  | .call => "typed crosscall argument"
  | .callValue => "value crosscall argument"
  | .staticcall => "static crosscall argument"
  | .delegatecall => "delegate crosscall argument"

def buildCrosscallReturnAssignmentPlan
    (module : Module)
    (env : TypeEnv)
    (entrypointName : String)
    (returnType : ValueType)
    (mode : CrosscallMode)
    (target methodId : Expr)
    (callValue? : Option Expr)
    (args : Array Expr)
    (callReturnType : ValueType) :
    Except LowerError CrosscallReturnAssignmentPlan := do
  ensureType s!"entrypoint `{entrypointName}` aggregate crosscall return type" returnType callReturnType
  let returns ← crosscallReturnPlan module s!"entrypoint `{entrypointName}` return value" returnType
  .ok {
    returns
    mode
    target := ← buildExprPlan module env target
    methodId := ← buildExprPlan module env methodId
    callValue? := ← callValue?.mapM (buildExprPlan module env)
    args := ← buildCrosscallArgWordPlansMany module env (crosscallModeArgContext mode) args
  }

def aggregateCrosscallReturnAssignmentPlan?
    (module : Module)
    (env : TypeEnv)
    (entrypointName : String)
    (returnType : ValueType)
    (value : Expr) :
    Except LowerError (Option CrosscallReturnAssignmentPlan) := do
  if isCrosscallWordType returnType then
    .ok none
  else
    match value with
    | .crosscallInvokeTyped target methodId args callReturnType => do
        let plan ← buildCrosscallReturnAssignmentPlan
          module env entrypointName returnType .call target methodId none args callReturnType
        .ok (some plan)
    | .crosscallInvokeValueTyped target methodId callValue args callReturnType => do
        let plan ← buildCrosscallReturnAssignmentPlan
          module env entrypointName returnType .callValue target methodId (some callValue) args callReturnType
        .ok (some plan)
    | .crosscallInvokeStaticTyped target methodId args callReturnType => do
        let plan ← buildCrosscallReturnAssignmentPlan
          module env entrypointName returnType .staticcall target methodId none args callReturnType
        .ok (some plan)
    | .crosscallInvokeDelegateTyped target methodId args callReturnType => do
        let plan ← buildCrosscallReturnAssignmentPlan
          module env entrypointName returnType .delegatecall target methodId none args callReturnType
        .ok (some plan)
    | _ => .ok none

def aggregateCrosscallReturnAssignmentPlanFromExprPlan?
    (module : Module)
    (entrypointName : String)
    (returnType : ValueType)
    (value : ExprPlan) :
    Except LowerError (Option CrosscallReturnAssignmentPlan) := do
  match returnType with
  | .fixedArray _ _ | .structType _ =>
      match value with
      | .crosscall mode target methodId callValue? args callReturnType => do
          ensureType s!"entrypoint `{entrypointName}` aggregate crosscall return type"
            returnType
            callReturnType
          let returns ← crosscallReturnPlan module s!"entrypoint `{entrypointName}` return value" returnType
          .ok (some {
            returns
            mode
            target
            methodId
            callValue?
            args
          })
      | _ => .ok none
  | .unit | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address | .bytes | .string | .array _ =>
      .ok none

def returnValueWordPlan?
    (module : Module)
    (env : TypeEnv)
    (entrypointName : String)
    (returnType : ValueType)
    (value : Expr) :
    Except LowerError (Option ReturnValueWordPlan) := do
  let context := s!"entrypoint `{entrypointName}` return value"
  let returns ← returnPlan module s!"entrypoint `{entrypointName}`" returnType
  match returnType, value with
  | .fixedArray _ _, _
  | .structType _, _ => do
      .ok (some {
        returns
        source := ← buildAbiValuePlan module env context returnType value
      })
  | _, _ =>
      .ok none

def buildEntrypointBodyPlan (module : Module) (entrypoint : Entrypoint) :
    Except LowerError (Array StmtPlan) := do
  validateEntrypointTypes module entrypoint
  let (body, _) ← buildStatementPlans module entrypoint (entrypointTypeEnv entrypoint) entrypoint.body
  .ok body

def buildEntrypointPlan (module : Module) (entrypoint : Entrypoint) :
    Except LowerError EntrypointPlan := do
  let selector ← entrypointSelector entrypoint
  let params ← entrypointParamPlans module entrypoint
  let returns ← returnPlan module s!"entrypoint `{entrypoint.name}`" entrypoint.returns
  let body ← buildEntrypointBodyPlan module entrypoint
  .ok { name := entrypoint.name, selector, params, returns, body }

def buildEntrypointSurfacePlan (module : Module) (entrypoint : Entrypoint) :
    Except LowerError EntrypointPlan := do
  let selector ← entrypointSelector entrypoint
  let params ← entrypointParamPlans module entrypoint
  let returns ← returnPlan module s!"entrypoint `{entrypoint.name}`" entrypoint.returns
  .ok { name := entrypoint.name, selector, params, returns, body := #[] }

def buildEntrypointPlans (module : Module) : Except LowerError (Array EntrypointPlan) :=
  module.entrypoints.foldlM (init := #[]) fun acc entrypoint => do
    .ok (acc.push (← buildEntrypointPlan module entrypoint))

/-! ## Event plan construction

Event plans are built by walking each entrypoint's body with a growing type
environment (params + let-bound locals), matching the same pattern used by
`Cli.lean` for event ABI extraction. This ensures event field expressions can
reference locals bound earlier in the same entrypoint. -/

structure EventCollector where
  plans : Array EventPlan := #[]
  deriving Repr

def EventCollector.find (collector : EventCollector) (name : String) : Option EventPlan :=
  collector.plans.find? (fun plan => plan.name == name)

def EventCollector.add (collector : EventCollector) (plan : EventPlan) : EventCollector :=
  match collector.find plan.name with
  | some _ => collector
  | none => { plans := collector.plans.push plan }

mutual
  partial def collectEventPlansFromExpr
      (module : Module)
      (env : TypeEnv)
      (collector : EventCollector) :
      Expr → Except LowerError EventCollector
    | .literal _ | .local _ | .nativeValue => pure collector
    | .arrayLit _ values =>
        values.foldlM (init := collector) (collectEventPlansFromExpr module env)
    | .arrayGet array index => do
        let collector ← collectEventPlansFromExpr module env collector array
        collectEventPlansFromExpr module env collector index
    | .memoryArrayNew _ length =>
        collectEventPlansFromExpr module env collector length
    | .memoryArrayLength array =>
        collectEventPlansFromExpr module env collector array
    | .memoryArrayGet array index => do
        let collector ← collectEventPlansFromExpr module env collector array
        collectEventPlansFromExpr module env collector index
    | .structLit _ fields =>
        fields.foldlM (init := collector) fun acc field =>
          collectEventPlansFromExpr module env acc field.snd
    | .field base _ => collectEventPlansFromExpr module env collector base
    | .add lhs rhs | .sub lhs rhs | .mul lhs rhs | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs => do
        let collector ← collectEventPlansFromExpr module env collector lhs
        collectEventPlansFromExpr module env collector rhs
    | .cast value _ | .boolNot value | .hash value =>
        collectEventPlansFromExpr module env collector value
    | .hashValue a b c d => do
        let collector ← collectEventPlansFromExpr module env collector a
        let collector ← collectEventPlansFromExpr module env collector b
        let collector ← collectEventPlansFromExpr module env collector c
        collectEventPlansFromExpr module env collector d
    | .crosscallInvoke _ _ _ | .crosscallInvokeTyped _ _ _ _ | .crosscallInvokeValueTyped _ _ _ _ _
    | .crosscallInvokeStaticTyped _ _ _ _ | .crosscallInvokeDelegateTyped _ _ _ _ => pure collector
    | .crosscallCreate _ _ | .crosscallCreate2 _ _ _ => pure collector
    | .effect effect => collectEventPlansFromEffect module env collector effect

  partial def collectEventPlansFromEffect
      (module : Module)
      (env : TypeEnv)
      (collector : EventCollector) :
      Effect → Except LowerError EventCollector
    | .storageScalarRead _ => pure collector
    | .storageScalarWrite _ value | .storageScalarAssignOp _ _ value =>
        collectEventPlansFromExpr module env collector value
    | .storageMapContains _ key | .storageMapGet _ key =>
        collectEventPlansFromExpr module env collector key
    | .storageMapInsert _ key value | .storageMapSet _ key value => do
        let collector ← collectEventPlansFromExpr module env collector key
        collectEventPlansFromExpr module env collector value
    | .storageArrayRead _ index => collectEventPlansFromExpr module env collector index
    | .storageArrayWrite _ index value | .storageArrayStructFieldWrite _ index _ value => do
        let collector ← collectEventPlansFromExpr module env collector index
        collectEventPlansFromExpr module env collector value
    | .storageArrayStructFieldRead _ index _ => collectEventPlansFromExpr module env collector index
    | .storageDynamicArrayPush _ value => collectEventPlansFromExpr module env collector value
    | .storageDynamicArrayPop _ => pure collector
    | .memoryArraySet array index value => do
        let collector ← collectEventPlansFromExpr module env collector array
        let collector ← collectEventPlansFromExpr module env collector index
        collectEventPlansFromExpr module env collector value
    | .storageStructFieldRead _ _ => pure collector
    | .storageStructFieldWrite _ _ value => collectEventPlansFromExpr module env collector value
    | .storagePathRead _ path =>
        path.foldlM (init := collector) fun acc segment =>
          match segment with
          | .mapKey key => collectEventPlansFromExpr module env acc key
          | .index index => collectEventPlansFromExpr module env acc index
          | .field _ => pure acc
    | .storagePathWrite _ path value | .storagePathAssignOp _ path _ value => do
        let collector ← path.foldlM (init := collector) fun acc segment =>
          match segment with
          | .mapKey key => collectEventPlansFromExpr module env acc key
          | .index index => collectEventPlansFromExpr module env acc index
          | .field _ => pure acc
        collectEventPlansFromExpr module env collector value
    | .contextRead _ => pure collector
    | .eventEmit name fields => do
        let signature ← eventSignature module env name fields
        let mut fieldPlans : Array EventFieldPlan := #[]
        for field in fields do
          let fieldType ← inferEventFieldExprType module env field.snd
          fieldPlans := fieldPlans.push (EventFieldPlan.mk field.fst fieldType false)
        pure (collector.add (EventPlan.mk name signature fieldPlans))
    | .eventEmitIndexed name indexedFields dataFields => do
        validateIndexedEventFieldCount name indexedFields.size
        let mut fieldPlans : Array EventFieldPlan := #[]
        for field in indexedFields do
          let fieldType ← inferEventFieldExprType module env field.snd
          fieldPlans := fieldPlans.push (EventFieldPlan.mk field.fst fieldType true)
        for field in dataFields do
          let fieldType ← inferEventFieldExprType module env field.snd
          fieldPlans := fieldPlans.push (EventFieldPlan.mk field.fst fieldType false)
        let signature ← eventSignature module env name (indexedFields ++ dataFields)
        pure (collector.add (EventPlan.mk name signature fieldPlans))

  partial def collectEventPlansFromStatements
      (module : Module)
      (env : TypeEnv)
      (collector : EventCollector) :
      Array Statement → Except LowerError EventCollector
    | #[] => pure collector
    | statements => do
      let mut current := env
      let mut acc := collector
      for stmt in statements do
        match stmt with
        | .letBind name type value => do
            ensureType s!"let binding `{name}`" type (← inferExprType module current value)
            current ← addLocal current name type false
            acc ← collectEventPlansFromExpr module current acc value
        | .letMutBind name type value => do
            ensureType s!"mutable let binding `{name}`" type (← inferExprType module current value)
            current ← addLocal current name type true
            acc ← collectEventPlansFromExpr module current acc value
        | .assign target value | .assignOp target _ value => do
            acc ← collectEventPlansFromExpr module current acc target
            acc ← collectEventPlansFromExpr module current acc value
        | .effect effect => do
            acc ← collectEventPlansFromEffect module current acc effect
        | .assert condition _ _ => do
            acc ← collectEventPlansFromExpr module current acc condition
        | .assertEq lhs rhs _ _ => do
            acc ← collectEventPlansFromExpr module current acc lhs
            acc ← collectEventPlansFromExpr module current acc rhs
        | .release _ | .revert _ | .revertWithError _ => pure ()
        | .ifElse condition thenBody elseBody => do
            acc ← collectEventPlansFromExpr module current acc condition
            acc ← collectEventPlansFromStatements module current acc thenBody
            acc ← collectEventPlansFromStatements module current acc elseBody
        | .boundedFor indexName _ _ body => do
            let loopEnv ← addLocal current indexName .u32 false
            acc ← collectEventPlansFromStatements module loopEnv acc body
        | .whileLoop _ _ => pure ()
        | .return value => do
            acc ← collectEventPlansFromExpr module current acc value
      pure acc
end

def buildEventPlans (module : Module) : Except LowerError (Array EventPlan) := do
  let mut collector : EventCollector := {}
  for entrypoint in module.entrypoints do
    collector ← collectEventPlansFromStatements module (entrypointTypeEnv entrypoint) collector entrypoint.body
  .ok collector.plans

/-! ## Helper plan discovery -/

def plainValueTransferMethodId? : Expr → Bool
  | .literal (.u64 0) => true
  | _ => false

def plainValueTransferCall? (methodId : Expr) (args : Array Expr) : Bool :=
  plainValueTransferMethodId? methodId && args.isEmpty

def pushCrosscallHelperSpecIfMissing
    (acc : Array CrosscallHelperSpec)
    (value : CrosscallHelperSpec) : Array CrosscallHelperSpec :=
  if acc.any (fun existing => existing == value) then acc else acc.push value

def mergeCrosscallHelperSpecs
    (lhs rhs : Array CrosscallHelperSpec) : Array CrosscallHelperSpec :=
  rhs.foldl pushCrosscallHelperSpecIfMissing lhs

def crosscallArgWordCountForExpr
    (module : Module)
    (env : TypeEnv)
    (context : String)
    (arg : Expr) : Except LowerError Nat := do
  let type ← inferExprType module env arg
  let words ← crosscallArgWordTypes module context type
  .ok words.size

def crosscallArgWordCountForArgs
    (module : Module)
    (env : TypeEnv)
    (context : String)
    (args : Array Expr) : Except LowerError Nat := do
  let mut count := 0
  for arg in args do
    count := count + (← crosscallArgWordCountForExpr module env context arg)
  .ok count

def crosscallHelperSpec
    (module : Module)
    (context : String)
    (arity : Nat)
    (returnType : ValueType)
    (mode : CrosscallMode)
    (plainTransfer : Bool := false) : Except LowerError CrosscallHelperSpec := do
  let wordTypes ← crosscallReturnWordTypes module context returnType
  .ok { arity, returnType, wordTypes, mode, plainTransfer }

mutual
  partial def crosscallHelperSpecsFromExpr
      (module : Module)
      (env : TypeEnv) : Expr → Except LowerError (Array CrosscallHelperSpec)
    | .literal _ | .local _ | .nativeValue => .ok #[]
    | .arrayLit _ values =>
        values.foldlM (init := #[]) fun acc value => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExpr module env value))
    | .arrayGet array index => do
        let arraySpecs ← crosscallHelperSpecsFromExpr module env array
        let indexSpecs ← crosscallHelperSpecsFromExpr module env index
        .ok (mergeCrosscallHelperSpecs arraySpecs indexSpecs)
    | .memoryArrayNew _ length =>
        crosscallHelperSpecsFromExpr module env length
    | .memoryArrayLength array =>
        crosscallHelperSpecsFromExpr module env array
    | .memoryArrayGet array index => do
        let arraySpecs ← crosscallHelperSpecsFromExpr module env array
        let indexSpecs ← crosscallHelperSpecsFromExpr module env index
        .ok (mergeCrosscallHelperSpecs arraySpecs indexSpecs)
    | .structLit _ fields =>
        fields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExpr module env field.snd))
    | .field base _ =>
        crosscallHelperSpecsFromExpr module env base
    | .add lhs rhs | .sub lhs rhs | .mul lhs rhs | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs => do
        let lhsSpecs ← crosscallHelperSpecsFromExpr module env lhs
        let rhsSpecs ← crosscallHelperSpecsFromExpr module env rhs
        .ok (mergeCrosscallHelperSpecs lhsSpecs rhsSpecs)
    | .cast value _ | .boolNot value | .hash value =>
        crosscallHelperSpecsFromExpr module env value
    | .hashValue a b c d => do
        let ab := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env a)
          (← crosscallHelperSpecsFromExpr module env b)
        let cd := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env c)
          (← crosscallHelperSpecsFromExpr module env d)
        .ok (mergeCrosscallHelperSpecs ab cd)
    | .crosscallInvoke target methodId args => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env target)
          (← crosscallHelperSpecsFromExpr module env methodId)
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromExpr module env arg)
        let spec ← crosscallHelperSpec module "crosscall return" args.size .u64 .call
        .ok (pushCrosscallHelperSpecIfMissing nested spec)
    | .crosscallInvokeTyped target methodId args returnType => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env target)
          (← crosscallHelperSpecsFromExpr module env methodId)
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromExpr module env arg)
        let argWordCount ← crosscallArgWordCountForArgs module env "typed crosscall argument" args
        let spec ← crosscallHelperSpec module "typed crosscall return" argWordCount returnType .call
        .ok (pushCrosscallHelperSpecIfMissing nested spec)
    | .crosscallInvokeValueTyped target methodId callValue args returnType => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env target)
          (← crosscallHelperSpecsFromExpr module env methodId)
        nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromExpr module env callValue)
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromExpr module env arg)
        let argWordCount ← crosscallArgWordCountForArgs module env "value crosscall argument" args
        let plainTransfer := plainValueTransferCall? methodId args && isCrosscallWordType returnType
        let spec ← crosscallHelperSpec
          module
          "value crosscall return"
          argWordCount
          returnType
          .callValue
          plainTransfer
        .ok (pushCrosscallHelperSpecIfMissing nested spec)
    | .crosscallInvokeStaticTyped target methodId args returnType => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env target)
          (← crosscallHelperSpecsFromExpr module env methodId)
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromExpr module env arg)
        let argWordCount ← crosscallArgWordCountForArgs module env "static crosscall argument" args
        let spec ← crosscallHelperSpec module "static crosscall return" argWordCount returnType .staticcall
        .ok (pushCrosscallHelperSpecIfMissing nested spec)
    | .crosscallInvokeDelegateTyped target methodId args returnType => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env target)
          (← crosscallHelperSpecsFromExpr module env methodId)
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromExpr module env arg)
        let argWordCount ← crosscallArgWordCountForArgs module env "delegate crosscall argument" args
        let spec ← crosscallHelperSpec module "delegate crosscall return" argWordCount returnType .delegatecall
        .ok (pushCrosscallHelperSpecIfMissing nested spec)
    | .crosscallCreate callValue _ =>
        crosscallHelperSpecsFromExpr module env callValue
    | .crosscallCreate2 callValue salt _ => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env callValue)
          (← crosscallHelperSpecsFromExpr module env salt))
    | .effect effect =>
        crosscallHelperSpecsFromEffect module env effect

  partial def crosscallHelperSpecsFromEffect
      (module : Module)
      (env : TypeEnv) : Effect → Except LowerError (Array CrosscallHelperSpec)
    | .storageScalarRead _ | .storageStructFieldRead _ _ | .contextRead _ => .ok #[]
    | .storageScalarWrite _ value
    | .storageScalarAssignOp _ _ value
    | .storageStructFieldWrite _ _ value =>
        crosscallHelperSpecsFromExpr module env value
    | .storageMapContains _ key
    | .storageMapGet _ key
    | .storageArrayRead _ key
    | .storageArrayStructFieldRead _ key _ =>
        crosscallHelperSpecsFromExpr module env key
    | .storageMapInsert _ key value
    | .storageMapSet _ key value
    | .storageArrayWrite _ key value
    | .storageArrayStructFieldWrite _ key _ value => do
        let keySpecs ← crosscallHelperSpecsFromExpr module env key
        let valueSpecs ← crosscallHelperSpecsFromExpr module env value
        .ok (mergeCrosscallHelperSpecs keySpecs valueSpecs)
    | .storageDynamicArrayPush _ value =>
        crosscallHelperSpecsFromExpr module env value
    | .storageDynamicArrayPop _ =>
        .ok #[]
    | .memoryArraySet array index value => do
        let arraySpecs ← crosscallHelperSpecsFromExpr module env array
        let indexSpecs ← crosscallHelperSpecsFromExpr module env index
        let valueSpecs ← crosscallHelperSpecsFromExpr module env value
        .ok (mergeCrosscallHelperSpecs (mergeCrosscallHelperSpecs arraySpecs indexSpecs) valueSpecs)
    | .storagePathRead _ path =>
        path.foldlM (init := #[]) fun acc segment => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromStoragePathSegment module env segment))
    | .storagePathWrite _ path value | .storagePathAssignOp _ path _ value => do
        let pathSpecs ← path.foldlM (init := #[]) fun acc segment => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromStoragePathSegment module env segment))
        .ok (mergeCrosscallHelperSpecs pathSpecs (← crosscallHelperSpecsFromExpr module env value))
    | .eventEmit _ fields =>
        fields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExpr module env field.snd))
    | .eventEmitIndexed _ indexedFields dataFields => do
        let indexedSpecs ← indexedFields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExpr module env field.snd))
        dataFields.foldlM (init := indexedSpecs) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExpr module env field.snd))

  partial def crosscallHelperSpecsFromStoragePathSegment
      (module : Module)
      (env : TypeEnv) : StoragePathSegment → Except LowerError (Array CrosscallHelperSpec)
    | .field _ => .ok #[]
    | .index index => crosscallHelperSpecsFromExpr module env index
    | .mapKey key => crosscallHelperSpecsFromExpr module env key

  partial def crosscallHelperSpecsFromStatement
      (module : Module)
      (env : TypeEnv) : Statement → Except LowerError (Array CrosscallHelperSpec × TypeEnv)
    | .letBind name type value => do
        let specs ← crosscallHelperSpecsFromExpr module env value
        let nextEnv ← addLocal env name type false
        .ok (specs, nextEnv)
    | .letMutBind name type value => do
        let specs ← crosscallHelperSpecsFromExpr module env value
        let nextEnv ← addLocal env name type true
        .ok (specs, nextEnv)
    | .assign target value | .assignOp target _ value => do
        let targetSpecs ← crosscallHelperSpecsFromExpr module env target
        let valueSpecs ← crosscallHelperSpecsFromExpr module env value
        .ok (mergeCrosscallHelperSpecs targetSpecs valueSpecs, env)
    | .effect effect => do
        .ok (← crosscallHelperSpecsFromEffect module env effect, env)
    | .assert condition _ _ => do
        .ok (← crosscallHelperSpecsFromExpr module env condition, env)
    | .assertEq lhs rhs _ _ => do
        let lhsSpecs ← crosscallHelperSpecsFromExpr module env lhs
        let rhsSpecs ← crosscallHelperSpecsFromExpr module env rhs
        .ok (mergeCrosscallHelperSpecs lhsSpecs rhsSpecs, env)
    | .release _ =>
        .ok (#[], env)
    | .revert _ => .ok (#[], env)
    | .revertWithError _ => .ok (#[], env)
    | .ifElse condition thenBody elseBody => do
        let conditionSpecs ← crosscallHelperSpecsFromExpr module env condition
        let (thenSpecs, _) ← crosscallHelperSpecsFromStatements module env thenBody
        let (elseSpecs, _) ← crosscallHelperSpecsFromStatements module env elseBody
        .ok (mergeCrosscallHelperSpecs conditionSpecs (mergeCrosscallHelperSpecs thenSpecs elseSpecs), env)
    | .boundedFor indexName _ _ body => do
        let loopEnv ← addLocal env indexName .u32 false
        let (bodySpecs, _) ← crosscallHelperSpecsFromStatements module loopEnv body
        .ok (bodySpecs, env)
    | .whileLoop _ _ => .ok (#[], env)
    | .return value => do
        .ok (← crosscallHelperSpecsFromExpr module env value, env)

  partial def crosscallHelperSpecsFromStatements
      (module : Module)
      (env : TypeEnv)
      (statements : Array Statement) : Except LowerError (Array CrosscallHelperSpec × TypeEnv) :=
    statements.foldlM (init := (#[], env)) fun acc stmt => do
      let (specs, currentEnv) := acc
      let (stmtSpecs, nextEnv) ← crosscallHelperSpecsFromStatement module currentEnv stmt
      .ok (mergeCrosscallHelperSpecs specs stmtSpecs, nextEnv)
end

def buildCrosscallHelperPlans (module : Module) : Except LowerError (Array CrosscallHelperSpec) := do
  let mut specs : Array CrosscallHelperSpec := #[]
  for entrypoint in module.entrypoints do
    let (entrypointSpecs, _) ←
      crosscallHelperSpecsFromStatements module (entrypointTypeEnv entrypoint) entrypoint.body
    specs := mergeCrosscallHelperSpecs specs entrypointSpecs
  .ok specs

def pushCreateHelperSpecIfMissing
    (acc : Array CreateHelperSpec)
    (value : CreateHelperSpec) : Array CreateHelperSpec :=
  if acc.any (fun existing => existing == value) then acc else acc.push value

def mergeCreateHelperSpecs
    (lhs rhs : Array CreateHelperSpec) : Array CreateHelperSpec :=
  rhs.foldl pushCreateHelperSpecIfMissing lhs

mutual
  partial def createHelperSpecsFromExpr : Expr → Array CreateHelperSpec
    | .literal _ | .local _ | .nativeValue => #[]
    | .arrayLit _ values =>
        values.foldl (init := #[]) fun acc value =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExpr value)
    | .arrayGet array index =>
        mergeCreateHelperSpecs (createHelperSpecsFromExpr array) (createHelperSpecsFromExpr index)
    | .memoryArrayNew _ length =>
        createHelperSpecsFromExpr length
    | .memoryArrayLength array =>
        createHelperSpecsFromExpr array
    | .memoryArrayGet array index =>
        mergeCreateHelperSpecs (createHelperSpecsFromExpr array) (createHelperSpecsFromExpr index)
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExpr field.snd)
    | .field base _ =>
        createHelperSpecsFromExpr base
    | .add lhs rhs | .sub lhs rhs | .mul lhs rhs | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs =>
        mergeCreateHelperSpecs (createHelperSpecsFromExpr lhs) (createHelperSpecsFromExpr rhs)
    | .cast value _ | .boolNot value | .hash value =>
        createHelperSpecsFromExpr value
    | .hashValue a b c d =>
        mergeCreateHelperSpecs
          (mergeCreateHelperSpecs (createHelperSpecsFromExpr a) (createHelperSpecsFromExpr b))
          (mergeCreateHelperSpecs (createHelperSpecsFromExpr c) (createHelperSpecsFromExpr d))
    | .crosscallInvoke target methodId args
    | .crosscallInvokeTyped target methodId args _
    | .crosscallInvokeStaticTyped target methodId args _
    | .crosscallInvokeDelegateTyped target methodId args _ =>
        let nested := mergeCreateHelperSpecs (createHelperSpecsFromExpr target) (createHelperSpecsFromExpr methodId)
        args.foldl (init := nested) fun acc arg =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExpr arg)
    | .crosscallInvokeValueTyped target methodId callValue args _ =>
        let nested := mergeCreateHelperSpecs (createHelperSpecsFromExpr target) (createHelperSpecsFromExpr methodId)
        let nested := mergeCreateHelperSpecs nested (createHelperSpecsFromExpr callValue)
        args.foldl (init := nested) fun acc arg =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExpr arg)
    | .crosscallCreate callValue initCodeHex =>
        pushCreateHelperSpecIfMissing (createHelperSpecsFromExpr callValue) { mode := .create, initCodeHex }
    | .crosscallCreate2 callValue salt initCodeHex =>
        let nested := mergeCreateHelperSpecs (createHelperSpecsFromExpr callValue) (createHelperSpecsFromExpr salt)
        pushCreateHelperSpecIfMissing nested { mode := .create2, initCodeHex }
    | .effect effect =>
        createHelperSpecsFromEffect effect

  partial def createHelperSpecsFromEffect : Effect → Array CreateHelperSpec
    | .storageScalarRead _ | .storageStructFieldRead _ _ | .contextRead _ => #[]
    | .storageScalarWrite _ value
    | .storageScalarAssignOp _ _ value
    | .storageStructFieldWrite _ _ value =>
        createHelperSpecsFromExpr value
    | .storageMapContains _ key
    | .storageMapGet _ key
    | .storageArrayRead _ key
    | .storageArrayStructFieldRead _ key _ =>
        createHelperSpecsFromExpr key
    | .storageMapInsert _ key value
    | .storageMapSet _ key value
    | .storageArrayWrite _ key value
    | .storageArrayStructFieldWrite _ key _ value =>
        mergeCreateHelperSpecs (createHelperSpecsFromExpr key) (createHelperSpecsFromExpr value)
    | .storageDynamicArrayPush _ value =>
        createHelperSpecsFromExpr value
    | .storageDynamicArrayPop _ =>
        #[]
    | .memoryArraySet array index value =>
        mergeCreateHelperSpecs
          (mergeCreateHelperSpecs (createHelperSpecsFromExpr array) (createHelperSpecsFromExpr index))
          (createHelperSpecsFromExpr value)
    | .storagePathRead _ path =>
        path.foldl (init := #[]) fun acc segment =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromStoragePathSegment segment)
    | .storagePathWrite _ path value | .storagePathAssignOp _ path _ value =>
        let pathSpecs := path.foldl (init := #[]) fun acc segment =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromStoragePathSegment segment)
        mergeCreateHelperSpecs pathSpecs (createHelperSpecsFromExpr value)
    | .eventEmit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExpr field.snd)
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexedSpecs := indexedFields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExpr field.snd)
        dataFields.foldl (init := indexedSpecs) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExpr field.snd)

  partial def createHelperSpecsFromStoragePathSegment : StoragePathSegment → Array CreateHelperSpec
    | .field _ => #[]
    | .index index => createHelperSpecsFromExpr index
    | .mapKey key => createHelperSpecsFromExpr key

  partial def createHelperSpecsFromStatement : Statement → Array CreateHelperSpec
    | .letBind _ _ value | .letMutBind _ _ value =>
        createHelperSpecsFromExpr value
    | .assign target value | .assignOp target _ value =>
        mergeCreateHelperSpecs (createHelperSpecsFromExpr target) (createHelperSpecsFromExpr value)
    | .effect effect =>
        createHelperSpecsFromEffect effect
    | .assert condition _ _ =>
        createHelperSpecsFromExpr condition
    | .assertEq lhs rhs _ _ =>
        mergeCreateHelperSpecs (createHelperSpecsFromExpr lhs) (createHelperSpecsFromExpr rhs)
    | .release _ =>
        #[]
    | .revert _ => #[]
    | .revertWithError _ => #[]
    | .ifElse condition thenBody elseBody =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromExpr condition)
          (mergeCreateHelperSpecs (createHelperSpecsFromStatements thenBody) (createHelperSpecsFromStatements elseBody))
    | .boundedFor _ _ _ body =>
        createHelperSpecsFromStatements body
    | .whileLoop _ _ => #[]
    | .return value =>
        createHelperSpecsFromExpr value

  partial def createHelperSpecsFromStatements (statements : Array Statement) : Array CreateHelperSpec :=
    statements.foldl (init := #[]) fun acc stmt =>
      mergeCreateHelperSpecs acc (createHelperSpecsFromStatement stmt)
end

def buildCreateHelperPlans (module : Module) : Array CreateHelperSpec :=
  module.entrypoints.foldl (init := #[]) fun acc entrypoint =>
    mergeCreateHelperSpecs acc (createHelperSpecsFromStatements entrypoint.body)

def pushNatIfMissing (acc : Array Nat) (value : Nat) : Array Nat :=
  if acc.contains value then acc else acc.push value

def mergeNatSets (lhs rhs : Array Nat) : Array Nat :=
  rhs.foldl pushNatIfMissing lhs

def pushNatArrayIfMissing
    (acc : Array (Array Nat))
    (value : Array Nat) : Array (Array Nat) :=
  if acc.any (fun existing => existing == value) then acc else acc.push value

def mergeNatArraySets (lhs rhs : Array (Array Nat)) : Array (Array Nat) :=
  rhs.foldl pushNatArrayIfMissing lhs

def localArrayGetLengthsForDynamicExprTarget
    (env : TypeEnv)
    (array index : Expr) : Array Nat :=
  match literalArrayIndex? index with
  | some _ => #[]
  | none =>
      match array with
      | .local name =>
          match findLocal? env name with
          | some { type := .fixedArray _ length, .. } => #[length]
          | _ => #[]
      | .arrayLit _ values => #[values.size]
      | _ => #[]

def nestedLocalArrayGetShapesForDynamicExprTarget
    (env : TypeEnv)
    (array index : Expr) : Array (Array Nat) :=
  let fullExpr := Expr.arrayGet array index
  match collectLocalArrayGetPath fullExpr with
  | some (name, path) =>
      if path.size > 1 && arrayIndexPathHasDynamic path then
        match findLocal? env name with
        | some binding =>
            match fixedArrayPathShape "fixed array index" binding.type path with
            | .ok (lengths, leafType) =>
                match leafType with
                | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address | .structType _ => #[lengths]
                | .unit | .fixedArray _ _ | .bytes | .string | .array _ => #[]
            | .error _ => #[]
        | none => #[]
      else
        #[]
  | none => #[]

mutual
  partial def localArrayGetLengthsExpr (env : TypeEnv) : Expr → Array Nat
    | .literal _ | .local _ | .nativeValue => #[]
    | .arrayLit _ values =>
        values.foldl (init := #[]) fun acc value =>
          mergeNatSets acc (localArrayGetLengthsExpr env value)
    | .arrayGet array index =>
        let nested := mergeNatSets (localArrayGetLengthsExpr env array) (localArrayGetLengthsExpr env index)
        mergeNatSets nested (localArrayGetLengthsForDynamicExprTarget env array index)
    | .memoryArrayNew _ length =>
        localArrayGetLengthsExpr env length
    | .memoryArrayLength array =>
        localArrayGetLengthsExpr env array
    | .memoryArrayGet array index =>
        mergeNatSets (localArrayGetLengthsExpr env array) (localArrayGetLengthsExpr env index)
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeNatSets acc (localArrayGetLengthsExpr env field.snd)
    | .field base _ =>
        localArrayGetLengthsExpr env base
    | .add lhs rhs | .sub lhs rhs | .mul lhs rhs | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs =>
        mergeNatSets (localArrayGetLengthsExpr env lhs) (localArrayGetLengthsExpr env rhs)
    | .cast value _ | .boolNot value | .hash value =>
        localArrayGetLengthsExpr env value
    | .hashValue a b c d =>
        mergeNatSets
          (mergeNatSets (localArrayGetLengthsExpr env a) (localArrayGetLengthsExpr env b))
          (mergeNatSets (localArrayGetLengthsExpr env c) (localArrayGetLengthsExpr env d))
    | .crosscallInvoke target methodId args
    | .crosscallInvokeTyped target methodId args _
    | .crosscallInvokeStaticTyped target methodId args _
    | .crosscallInvokeDelegateTyped target methodId args _ =>
        let nested := mergeNatSets (localArrayGetLengthsExpr env target) (localArrayGetLengthsExpr env methodId)
        args.foldl (init := nested) fun acc arg =>
          mergeNatSets acc (localArrayGetLengthsExpr env arg)
    | .crosscallInvokeValueTyped target methodId callValue args _ =>
        let nested := mergeNatSets (localArrayGetLengthsExpr env target) (localArrayGetLengthsExpr env methodId)
        let nested := mergeNatSets nested (localArrayGetLengthsExpr env callValue)
        args.foldl (init := nested) fun acc arg =>
          mergeNatSets acc (localArrayGetLengthsExpr env arg)
    | .crosscallCreate callValue _ =>
        localArrayGetLengthsExpr env callValue
    | .crosscallCreate2 callValue salt _ =>
        mergeNatSets (localArrayGetLengthsExpr env callValue) (localArrayGetLengthsExpr env salt)
    | .effect effect =>
        localArrayGetLengthsEffect env effect

  partial def localArrayGetLengthsEffect (env : TypeEnv) : Effect → Array Nat
    | .storageScalarRead _ | .storageStructFieldRead _ _ | .contextRead _ => #[]
    | .storageScalarWrite _ value
    | .storageScalarAssignOp _ _ value
    | .storageStructFieldWrite _ _ value =>
        localArrayGetLengthsExpr env value
    | .storageMapContains _ key
    | .storageMapGet _ key
    | .storageArrayRead _ key
    | .storageArrayStructFieldRead _ key _ =>
        localArrayGetLengthsExpr env key
    | .storageMapInsert _ key value
    | .storageMapSet _ key value
    | .storageArrayWrite _ key value
    | .storageArrayStructFieldWrite _ key _ value =>
        mergeNatSets (localArrayGetLengthsExpr env key) (localArrayGetLengthsExpr env value)
    | .storageDynamicArrayPush _ value =>
        localArrayGetLengthsExpr env value
    | .storageDynamicArrayPop _ =>
        #[]
    | .memoryArraySet array index value =>
        mergeNatSets
          (mergeNatSets (localArrayGetLengthsExpr env array) (localArrayGetLengthsExpr env index))
          (localArrayGetLengthsExpr env value)
    | .storagePathRead _ path =>
        path.foldl (init := #[]) fun acc segment =>
          mergeNatSets acc (localArrayGetLengthsStoragePathSegment env segment)
    | .storagePathWrite _ path value | .storagePathAssignOp _ path _ value =>
        let pathLengths := path.foldl (init := #[]) fun acc segment =>
          mergeNatSets acc (localArrayGetLengthsStoragePathSegment env segment)
        mergeNatSets pathLengths (localArrayGetLengthsExpr env value)
    | .eventEmit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeNatSets acc (localArrayGetLengthsExpr env field.snd)
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexedLengths := indexedFields.foldl (init := #[]) fun acc field =>
          mergeNatSets acc (localArrayGetLengthsExpr env field.snd)
        dataFields.foldl (init := indexedLengths) fun acc field =>
          mergeNatSets acc (localArrayGetLengthsExpr env field.snd)

  partial def localArrayGetLengthsStoragePathSegment (env : TypeEnv) : StoragePathSegment → Array Nat
    | .field _ => #[]
    | .index index => localArrayGetLengthsExpr env index
    | .mapKey key => localArrayGetLengthsExpr env key

  partial def localArrayGetLengthsAssignTarget (env : TypeEnv) : Expr → Array Nat
    | .arrayGet (.local _) index =>
        localArrayGetLengthsExpr env index
    | .field (.local _) _ =>
        #[]
    | target =>
        localArrayGetLengthsExpr env target

  partial def localArrayGetLengthsStatement
      (env : TypeEnv) : Statement → Except LowerError (Array Nat × TypeEnv)
    | .letBind name type value => do
        let nextEnv ← addLocal env name type false
        .ok (localArrayGetLengthsExpr env value, nextEnv)
    | .letMutBind name type value => do
        let nextEnv ← addLocal env name type true
        .ok (localArrayGetLengthsExpr env value, nextEnv)
    | .assign target value | .assignOp target _ value =>
        .ok (mergeNatSets (localArrayGetLengthsAssignTarget env target) (localArrayGetLengthsExpr env value), env)
    | .effect effect =>
        .ok (localArrayGetLengthsEffect env effect, env)
    | .assert condition _ _ =>
        .ok (localArrayGetLengthsExpr env condition, env)
    | .assertEq lhs rhs _ _ =>
        .ok (mergeNatSets (localArrayGetLengthsExpr env lhs) (localArrayGetLengthsExpr env rhs), env)
    | .release _ =>
        .ok (#[], env)
    | .revert _ => .ok (#[], env)
    | .revertWithError _ => .ok (#[], env)
    | .ifElse condition thenBody elseBody => do
        let (thenLengths, _) ← localArrayGetLengthsStatements env thenBody
        let (elseLengths, _) ← localArrayGetLengthsStatements env elseBody
        let bodyLengths := mergeNatSets thenLengths elseLengths
        .ok (mergeNatSets (localArrayGetLengthsExpr env condition) bodyLengths, env)
    | .boundedFor indexName _ _ body => do
        let loopEnv ← addLocal env indexName .u32 false
        let (bodyLengths, _) ← localArrayGetLengthsStatements loopEnv body
        .ok (bodyLengths, env)
    | .whileLoop _ _ => .ok (#[], env)
    | .return value =>
        .ok (localArrayGetLengthsExpr env value, env)

  partial def localArrayGetLengthsStatements
      (env : TypeEnv)
      (statements : Array Statement) : Except LowerError (Array Nat × TypeEnv) :=
    statements.foldlM (init := (#[], env)) fun acc stmt => do
      let (lengths, currentEnv) := acc
      let (stmtLengths, nextEnv) ← localArrayGetLengthsStatement currentEnv stmt
      .ok (mergeNatSets lengths stmtLengths, nextEnv)
end

def buildLocalArrayGetLengths (module : Module) : Except LowerError (Array Nat) := do
  let mut lengths : Array Nat := #[]
  for entrypoint in module.entrypoints do
    let (entrypointLengths, _) ← localArrayGetLengthsStatements (entrypointTypeEnv entrypoint) entrypoint.body
    lengths := mergeNatSets lengths entrypointLengths
  .ok lengths

mutual
  partial def nestedLocalArrayGetShapesExpr (env : TypeEnv) : Expr → Array (Array Nat)
    | .literal _ | .local _ | .nativeValue => #[]
    | .arrayLit _ values =>
        values.foldl (init := #[]) fun acc value =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env value)
    | .arrayGet array index =>
        let nested :=
          mergeNatArraySets (nestedLocalArrayGetShapesExpr env array) (nestedLocalArrayGetShapesExpr env index)
        mergeNatArraySets nested (nestedLocalArrayGetShapesForDynamicExprTarget env array index)
    | .memoryArrayNew _ length =>
        nestedLocalArrayGetShapesExpr env length
    | .memoryArrayLength array =>
        nestedLocalArrayGetShapesExpr env array
    | .memoryArrayGet array index =>
        mergeNatArraySets (nestedLocalArrayGetShapesExpr env array) (nestedLocalArrayGetShapesExpr env index)
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env field.snd)
    | .field base _ =>
        nestedLocalArrayGetShapesExpr env base
    | .add lhs rhs | .sub lhs rhs | .mul lhs rhs | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs =>
        mergeNatArraySets (nestedLocalArrayGetShapesExpr env lhs) (nestedLocalArrayGetShapesExpr env rhs)
    | .cast value _ | .boolNot value | .hash value =>
        nestedLocalArrayGetShapesExpr env value
    | .hashValue a b c d =>
        mergeNatArraySets
          (mergeNatArraySets (nestedLocalArrayGetShapesExpr env a) (nestedLocalArrayGetShapesExpr env b))
          (mergeNatArraySets (nestedLocalArrayGetShapesExpr env c) (nestedLocalArrayGetShapesExpr env d))
    | .crosscallInvoke target methodId args
    | .crosscallInvokeTyped target methodId args _
    | .crosscallInvokeStaticTyped target methodId args _
    | .crosscallInvokeDelegateTyped target methodId args _ =>
        let nested :=
          mergeNatArraySets (nestedLocalArrayGetShapesExpr env target) (nestedLocalArrayGetShapesExpr env methodId)
        args.foldl (init := nested) fun acc arg =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env arg)
    | .crosscallInvokeValueTyped target methodId callValue args _ =>
        let nested :=
          mergeNatArraySets (nestedLocalArrayGetShapesExpr env target) (nestedLocalArrayGetShapesExpr env methodId)
        let nested := mergeNatArraySets nested (nestedLocalArrayGetShapesExpr env callValue)
        args.foldl (init := nested) fun acc arg =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env arg)
    | .crosscallCreate callValue _ =>
        nestedLocalArrayGetShapesExpr env callValue
    | .crosscallCreate2 callValue salt _ =>
        mergeNatArraySets (nestedLocalArrayGetShapesExpr env callValue) (nestedLocalArrayGetShapesExpr env salt)
    | .effect effect =>
        nestedLocalArrayGetShapesEffect env effect

  partial def nestedLocalArrayGetShapesEffect (env : TypeEnv) : Effect → Array (Array Nat)
    | .storageScalarRead _ | .storageStructFieldRead _ _ | .contextRead _ => #[]
    | .storageScalarWrite _ value
    | .storageScalarAssignOp _ _ value
    | .storageStructFieldWrite _ _ value =>
        nestedLocalArrayGetShapesExpr env value
    | .storageMapContains _ key
    | .storageMapGet _ key
    | .storageArrayRead _ key
    | .storageArrayStructFieldRead _ key _ =>
        nestedLocalArrayGetShapesExpr env key
    | .storageMapInsert _ key value
    | .storageMapSet _ key value
    | .storageArrayWrite _ key value
    | .storageArrayStructFieldWrite _ key _ value =>
        mergeNatArraySets (nestedLocalArrayGetShapesExpr env key) (nestedLocalArrayGetShapesExpr env value)
    | .storageDynamicArrayPush _ value =>
        nestedLocalArrayGetShapesExpr env value
    | .storageDynamicArrayPop _ =>
        #[]
    | .memoryArraySet array index value =>
        mergeNatArraySets
          (mergeNatArraySets (nestedLocalArrayGetShapesExpr env array) (nestedLocalArrayGetShapesExpr env index))
          (nestedLocalArrayGetShapesExpr env value)
    | .storagePathRead _ path =>
        path.foldl (init := #[]) fun acc segment =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesStoragePathSegment env segment)
    | .storagePathWrite _ path value | .storagePathAssignOp _ path _ value =>
        let pathShapes := path.foldl (init := #[]) fun acc segment =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesStoragePathSegment env segment)
        mergeNatArraySets pathShapes (nestedLocalArrayGetShapesExpr env value)
    | .eventEmit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env field.snd)
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexedShapes := indexedFields.foldl (init := #[]) fun acc field =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env field.snd)
        dataFields.foldl (init := indexedShapes) fun acc field =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env field.snd)

  partial def nestedLocalArrayGetShapesStoragePathSegment (env : TypeEnv) :
      StoragePathSegment → Array (Array Nat)
    | .field _ => #[]
    | .index index => nestedLocalArrayGetShapesExpr env index
    | .mapKey key => nestedLocalArrayGetShapesExpr env key

  partial def nestedLocalArrayGetShapesAssignTarget (env : TypeEnv) : Expr → Array (Array Nat)
    | .arrayGet array index =>
        let nested :=
          mergeNatArraySets (nestedLocalArrayGetShapesExpr env array) (nestedLocalArrayGetShapesExpr env index)
        mergeNatArraySets nested (nestedLocalArrayGetShapesForDynamicExprTarget env array index)
    | .field target _ =>
        nestedLocalArrayGetShapesExpr env target
    | _ => #[]

  partial def nestedLocalArrayGetShapesStatement
      (env : TypeEnv) : Statement → Except LowerError (Array (Array Nat) × TypeEnv)
    | .letBind name type value => do
        let nextEnv ← addLocal env name type false
        .ok (nestedLocalArrayGetShapesExpr env value, nextEnv)
    | .letMutBind name type value => do
        let nextEnv ← addLocal env name type true
        .ok (nestedLocalArrayGetShapesExpr env value, nextEnv)
    | .assign target value | .assignOp target _ value =>
        .ok (
          mergeNatArraySets
            (nestedLocalArrayGetShapesAssignTarget env target)
            (nestedLocalArrayGetShapesExpr env value),
          env
        )
    | .effect effect =>
        .ok (nestedLocalArrayGetShapesEffect env effect, env)
    | .assert condition _ _ =>
        .ok (nestedLocalArrayGetShapesExpr env condition, env)
    | .assertEq lhs rhs _ _ =>
        .ok (mergeNatArraySets (nestedLocalArrayGetShapesExpr env lhs) (nestedLocalArrayGetShapesExpr env rhs), env)
    | .release _ =>
        .ok (#[], env)
    | .revert _ => .ok (#[], env)
    | .revertWithError _ => .ok (#[], env)
    | .ifElse condition thenBody elseBody => do
        let (thenShapes, _) ← nestedLocalArrayGetShapesStatements env thenBody
        let (elseShapes, _) ← nestedLocalArrayGetShapesStatements env elseBody
        .ok (
          mergeNatArraySets
            (nestedLocalArrayGetShapesExpr env condition)
            (mergeNatArraySets thenShapes elseShapes),
          env
        )
    | .boundedFor indexName _ _ body => do
        let loopEnv ← addLocal env indexName .u32 false
        let (bodyShapes, _) ← nestedLocalArrayGetShapesStatements loopEnv body
        .ok (bodyShapes, env)
    | .whileLoop _ _ => .ok (#[], env)
    | .return value =>
        .ok (nestedLocalArrayGetShapesExpr env value, env)

  partial def nestedLocalArrayGetShapesStatements
      (env : TypeEnv)
      (statements : Array Statement) : Except LowerError (Array (Array Nat) × TypeEnv) :=
    statements.foldlM (init := (#[], env)) fun acc stmt => do
      let (shapes, currentEnv) := acc
      let (stmtShapes, nextEnv) ← nestedLocalArrayGetShapesStatement currentEnv stmt
      .ok (mergeNatArraySets shapes stmtShapes, nextEnv)
end

def buildNestedLocalArrayGetShapes (module : Module) : Except LowerError (Array (Array Nat)) := do
  let mut shapes : Array (Array Nat) := #[]
  for entrypoint in module.entrypoints do
    let (entrypointShapes, _) ← nestedLocalArrayGetShapesStatements (entrypointTypeEnv entrypoint) entrypoint.body
    shapes := mergeNatArraySets shapes entrypointShapes
  .ok shapes

/-! ## Module plan assembly -/

def buildFullModulePlan (module : Module) : Except LowerError ModulePlan := do
  let basePlan ←
    match buildModulePlan module with
    | .ok plan => .ok plan
    | .error err => .error (planError err)
  let entrypointPlans ← buildEntrypointPlans module
  let dispatchEntrypointPlans := entrypointPlans.filterMap fun plan =>
    match module.entrypoints.find? (fun ep => ep.name == plan.name) with
    | some ep => if ep.kind == .fallback || ep.kind == .receive then none else some plan
    | none => some plan
  let dispatchPlan := moduleDispatchPlan module dispatchEntrypointPlans
  let eventPlans ← buildEventPlans module
  let crosscallPlans ← buildCrosscallHelperPlans module
  let createPlans := buildCreateHelperPlans module
  let localArrayGetLengths ← buildLocalArrayGetLengths module
  let nestedLocalArrayGetShapes ← buildNestedLocalArrayGetShapes module
  let usesCheckedArithmetic := moduleUsesCheckedArithmetic module
  let metadata := {
    moduleName := module.name
    entrypoints := entrypointPlans
    events := eventPlans
    capabilities := basePlan.targetPlan.capabilities
  }
  .ok { basePlan with
    entrypoints := entrypointPlans
    dispatch := dispatchPlan
    events := eventPlans
    crosscalls := crosscallPlans
    creates := createPlans
    localArrayGetLengths := localArrayGetLengths
    nestedLocalArrayGetShapes := nestedLocalArrayGetShapes
    usesCheckedArithmetic := usesCheckedArithmetic
    metadata := metadata
  }

def buildFullModulePlanWithTargetPlan
    (module : Module)
    (targetPlan : CapabilityPlan) :
    Except LowerError ModulePlan := do
  let basePlan ←
    match buildModulePlanWithTargetPlan module targetPlan with
    | .ok plan => .ok plan
    | .error err => .error (planError err)
  let entrypointPlans ← buildEntrypointPlans module
  let dispatchEntrypointPlans := entrypointPlans.filterMap fun plan =>
    match module.entrypoints.find? (fun ep => ep.name == plan.name) with
    | some ep => if ep.kind == .fallback || ep.kind == .receive then none else some plan
    | none => some plan
  let dispatchPlan := moduleDispatchPlan module dispatchEntrypointPlans
  let eventPlans ← buildEventPlans module
  let crosscallPlans ← buildCrosscallHelperPlans module
  let createPlans := buildCreateHelperPlans module
  let localArrayGetLengths ← buildLocalArrayGetLengths module
  let nestedLocalArrayGetShapes ← buildNestedLocalArrayGetShapes module
  let usesCheckedArithmetic := moduleUsesCheckedArithmetic module
  let metadata := {
    moduleName := module.name
    entrypoints := entrypointPlans
    events := eventPlans
    capabilities := basePlan.targetPlan.capabilities
  }
  .ok { basePlan with
    entrypoints := entrypointPlans
    dispatch := dispatchPlan
    events := eventPlans
    crosscalls := crosscallPlans
    creates := createPlans
    localArrayGetLengths := localArrayGetLengths
    nestedLocalArrayGetShapes := nestedLocalArrayGetShapes
    usesCheckedArithmetic := usesCheckedArithmetic
    metadata := metadata
  }

end ProofForge.Backend.Evm.Lower
