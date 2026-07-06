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

partial def localCrosscallWordPlansAt
    (module : Module)
    (context name : String)
    (path : Array Nat) : ValueType → Except LowerError (Array ExprPlan)
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address =>
      if path.isEmpty then
        .ok #[.local name]
      else
        .ok #[.local (arrayLocalPathName name path)]
  | .fixedArray elementType length => do
      if length == 0 then
        .error {
          message := s!"{context} uses Array<{elementType.name},0>; IR EVM v0 crosscall fixed arrays must have non-zero length"
        }
      let mut plans : Array ExprPlan := #[]
      for _h : idx in [0:length] do
        plans := plans ++ (← localCrosscallWordPlansAt module context name (path.push idx) elementType)
      .ok plans
  | .structType typeName => do
      let fieldIds ← localCrosscallStructFieldIds module context typeName
      let mut plans : Array ExprPlan := #[]
      for fieldId in fieldIds do
        let fieldName :=
          if path.isEmpty then
            structLocalFieldName name fieldId
          else
            arrayStructLocalPathFieldName name path fieldId
        plans := plans.push (.local fieldName)
      .ok plans
  | .unit | .bytes | .string | .array _ =>
      .error {
        message := s!"{context} uses a dynamic type; IR EVM v0 crosscall values must use U32, U64, Bool, Hash, Address, fixed arrays, or structs"
      }

def localCrosscallWordPlans
    (module : Module)
    (env : TypeEnv)
    (context name : String)
    (expectedType : ValueType) : Except LowerError (Array ExprPlan) := do
  validateLocalCrosscallWordPlan module env context name expectedType
  localCrosscallWordPlansAt module context name #[] expectedType

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
  | .fixedArray elementType length => do
      discard <| crosscallValueWordTypes module context (.fixedArray elementType length)
      storageArrayAbiWordPlans module context stateId elementType length
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address | .unit
  | .bytes | .string | .array _ =>
      .error {
        message := s!"{context} storage-backed crosscall word expansion supports struct scalar storage or fixed storage arrays only, got `{expectedType.name}`"
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
        .ok <| wrapCrosscallExprWordPlans
          (← localCrosscallWordPlans module env context name (.structType typeName))
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
        .ok <| wrapCrosscallExprWordPlans
          (← storageCrosscallWordPlans module context stateId (.structType typeName))
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
        .ok <| wrapCrosscallExprWordPlans
          (← localCrosscallWordPlans module env context name (.fixedArray (.structType typeName) length))
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
    match ← storageArrayAbiWordsPlan? module (.fixedArray elementType length) arg with
    | some (.storage stateId storageType) =>
        .ok <| wrapCrosscallExprWordPlans
          (← storageCrosscallWordPlans module context stateId storageType)
    | _ =>
        match elementType with
        | .structType typeName =>
            buildCrosscallStructArrayArgWordPlans module env context typeName length arg
        | .fixedArray nestedElementType nestedLength =>
            match arg with
            | .local name =>
                .ok <| wrapCrosscallExprWordPlans
                  (← localCrosscallWordPlans module env context name (.fixedArray elementType length))
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
                .ok <| wrapCrosscallExprWordPlans
                  (← localCrosscallWordPlans module env context name (.fixedArray elementType length))
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
            .ok <| wrapCrosscallExprWordPlans
              (← localCrosscallWordPlans module env context name type)
        | _ =>
            buildCrosscallFixedArrayArgWordPlans module env context elementType length arg
    | .structType typeName =>
        match arg with
        | .local name =>
            .ok <| wrapCrosscallExprWordPlans
              (← localCrosscallWordPlans module env context name type)
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
        let valuePlan ← buildExprPlan module env value
        let target ← lowerPlan <| dynamicArrayTargetPlan module stateId
        .ok (.storageDynamicArrayPushTarget target valuePlan)
    | .storageDynamicArrayPop stateId => do
        let target ← lowerPlan <| dynamicArrayTargetPlan module stateId
        .ok (.storageDynamicArrayPopTarget target)
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

def fixedArrayAssignmentSourcePlans
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (elementType : ValueType)
    (length : Nat)
    (value : Expr) : Except LowerError (Array FixedArrayAssignmentSourcePlan) := do
  match value with
  | .local sourceName => do
      let (sourceElementType, sourceLength) ← requireLocalFixedArray "assignment value" env sourceName
      ensureType s!"assignment target `{name}` fixed-array element type" elementType sourceElementType
      if sourceLength != length then
        .error { message := s!"assignment target `{name}` expected fixed array length {length}, got {sourceLength}" }
      let mut sources : Array FixedArrayAssignmentSourcePlan := #[]
      for _h : idx in [0:length] do
        sources := sources.push {
          index := idx
          expr := .local (arrayLocalElementName sourceName idx)
        }
      .ok sources
  | .arrayLit literalElementType literalValues => do
      ensureType s!"assignment target `{name}` fixed-array element type" elementType literalElementType
      if literalValues.size != length then
        .error { message := s!"assignment target `{name}` expected fixed array length {length}, got {literalValues.size}" }
      let mut sources : Array FixedArrayAssignmentSourcePlan := #[]
      for h : idx in [0:literalValues.size] do
        sources := sources.push {
          index := idx
          expr := ← buildExprPlan module env literalValues[idx]
        }
      .ok sources
  | _ =>
      .error { message := s!"assignment target `{name}` fixed-array whole assignment supports local fixed-array values or array literals in IR EVM v0" }

def structAssignmentSourcePlans
    (module : Module)
    (env : TypeEnv)
    (name typeName : String)
    (value : Expr) : Except LowerError (Array StructAssignmentSourcePlan) := do
  let decl ← ensureLocalFlatStructType module s!"assignment target `{name}` struct type" typeName
  match value with
  | .local sourceName => do
      let some binding := findLocal? env sourceName
        | .error { message := s!"unknown local `{sourceName}`" }
      ensureType s!"assignment target `{name}` struct type" (.structType typeName) binding.type
      let mut sources : Array StructAssignmentSourcePlan := #[]
      for fieldDecl in decl.fields do
        sources := sources.push {
          fieldName := fieldDecl.id
          expr := .local (structLocalFieldName sourceName fieldDecl.id)
        }
      .ok sources
  | .structLit literalTypeName fields => do
      if literalTypeName != typeName then
        .error { message := s!"assignment target `{name}` expected struct `{typeName}`, got `{literalTypeName}`" }
      let mut sources : Array StructAssignmentSourcePlan := #[]
      for fieldDecl in decl.fields do
        let some field := fields.find? fun field => field.fst == fieldDecl.id
          | .error { message := s!"struct literal `{typeName}` is missing field `{fieldDecl.id}`" }
        sources := sources.push {
          fieldName := fieldDecl.id
          expr := ← buildExprPlan module env field.snd
        }
      .ok sources
  | .effect (.storageScalarRead stateId) => do
      let (slot, stateTypeName, _) ← lowerPlan <| ProofForge.Backend.Evm.Plan.requireStructState module stateId
      ensureType s!"assignment target `{name}` struct type" (.structType typeName) (.structType stateTypeName)
      let mut sources : Array StructAssignmentSourcePlan := #[]
      for h : idx in [0:decl.fields.size] do
        let fieldDecl := decl.fields[idx]
        ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
        sources := sources.push {
          fieldName := fieldDecl.id
          expr := .storageLoad (.scalarSlot (slot + idx))
        }
      .ok sources
  | _ =>
      .error { message := s!"assignment target `{name}` struct whole assignment supports local struct values, struct literals, or storage scalar struct reads in IR EVM v0" }

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

def plainValueTransferMethodIdPlan? : ExprPlan → Bool
  | .literalWord 0 => true
  | _ => false

def plainValueTransferCallPlan? (methodId : ExprPlan) (args : Array CrosscallArgWordPlan) : Bool :=
  plainValueTransferMethodIdPlan? methodId && args.isEmpty

mutual
  partial def crosscallHelperSpecsFromContextExprPlan
      (module : Module) : ContextExprPlan → Except LowerError (Array CrosscallHelperSpec)
    | .blockHash blockNumber =>
        crosscallHelperSpecsFromExprPlan module blockNumber
    | .userId | .contractId | .checkpointId | .timestamp | .chainId
    | .gasPrice | .gasLeft | .baseFee | .prevRandao | .origin | .coinbase =>
        .ok #[]

  partial def crosscallHelperSpecsFromStorageSlotExprPlan
      (module : Module) : StorageSlotExprPlan → Except LowerError (Array CrosscallHelperSpec)
    | .scalarSlot _ | .fixedSlot _ => .ok #[]
    | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
        keys.foldlM (init := #[]) fun acc key => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExprPlan module key))
    | .arraySlot _ _ index
    | .structArrayFieldSlot _ _ _ _ index
    | .dynamicArraySlot _ index =>
        crosscallHelperSpecsFromExprPlan module index

  partial def crosscallHelperSpecsFromStoragePathWriteExprTargetPlan
      (module : Module) : StoragePathWriteExprTargetPlan → Except LowerError (Array CrosscallHelperSpec)
    | .mapWrite _ key =>
        crosscallHelperSpecsFromExprPlan module key
    | .singleSlot slot =>
        crosscallHelperSpecsFromStorageSlotExprPlan module slot
    | .mapValuePresence valueSlot presenceSlot => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromStorageSlotExprPlan module valueSlot)
          (← crosscallHelperSpecsFromStorageSlotExprPlan module presenceSlot))

  partial def crosscallHelperSpecsFromAbiValuePlan
      (module : Module) : AbiValuePlan → Except LowerError (Array CrosscallHelperSpec)
    | .expr value =>
        crosscallHelperSpecsFromExprPlan module value
    | .local .. | .storage .. =>
        .ok #[]
    | .arrayLit _ values =>
        values.foldlM (init := #[]) fun acc value => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromAbiValuePlan module value))
    | .structLit _ fields =>
        fields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromAbiValuePlan module field.snd))

  partial def crosscallHelperSpecsFromCrosscallArgWordPlan
      (module : Module) : CrosscallArgWordPlan → Except LowerError (Array CrosscallHelperSpec)
    | .expr value =>
        crosscallHelperSpecsFromExprPlan module value
    | .local .. | .storage .. =>
        .ok #[]

  partial def crosscallHelperSpecsFromExprPlan
      (module : Module) : ExprPlan → Except LowerError (Array CrosscallHelperSpec)
    | .literalWord _ | .local _ | .calldataWord _ | .nativeValue =>
        .ok #[]
    | .storageLoad slot =>
        match slot with
        | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
            keys.foldlM (init := #[]) fun acc valuePlan => do
              match valuePlan with
              | .irExpr _ => .ok acc
        | .arraySlot .. | .structArrayFieldSlot .. | .dynamicArraySlot ..
        | .scalarSlot _ | .fixedSlot _ =>
            .ok #[]
    | .builtin _ args | .helperCall _ args | .arrayLit _ args =>
        args.foldlM (init := #[]) fun acc arg => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExprPlan module arg))
    | .checkedArith _ lhs rhs
    | .arrayGet lhs rhs
    | .hashTwoToOne lhs rhs => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module lhs)
          (← crosscallHelperSpecsFromExprPlan module rhs))
    | .hashPack a b c d | .hashValue a b c d => do
        let ab := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module a)
          (← crosscallHelperSpecsFromExprPlan module b)
        let cd := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module c)
          (← crosscallHelperSpecsFromExprPlan module d)
        .ok (mergeCrosscallHelperSpecs ab cd)
    | .context field =>
        crosscallHelperSpecsFromContextExprPlan module field
    | .crosscall mode target methodId callValue? args returnType => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module target)
          (← crosscallHelperSpecsFromExprPlan module methodId)
        match callValue? with
        | some callValue =>
            nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromExprPlan module callValue)
        | none => pure ()
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromCrosscallArgWordPlan module arg)
        let plainTransfer :=
          match mode with
          | .callValue => plainValueTransferCallPlan? methodId args && isCrosscallWordType returnType
          | .call | .staticcall | .delegatecall => false
        let spec ← crosscallHelperSpec
          module
          "planned crosscall return"
          args.size
          returnType
          mode
          plainTransfer
        .ok (pushCrosscallHelperSpecIfMissing nested spec)
    | .create _ callValue salt? _ => do
        let callValueSpecs ← crosscallHelperSpecsFromExprPlan module callValue
        match salt? with
        | some salt =>
            .ok (mergeCrosscallHelperSpecs callValueSpecs (← crosscallHelperSpecsFromExprPlan module salt))
        | none =>
            .ok callValueSpecs
    | .cast source _
    | .structField source _
    | .memoryArrayLength source
    | .hash source =>
        crosscallHelperSpecsFromExprPlan module source
    | .localArrayGet _ path _ =>
        path.foldlM (init := #[]) fun acc index => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExprPlan module index))
    | .memoryArrayNew _ length =>
        crosscallHelperSpecsFromExprPlan module length
    | .memoryArrayGet array index => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module array)
          (← crosscallHelperSpecsFromExprPlan module index))
    | .structLit _ fields =>
        fields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExprPlan module field.snd))
    | .effect effect =>
        crosscallHelperSpecsFromEffectPlan module effect

  partial def crosscallHelperSpecsFromEffectPlan
      (module : Module) : EffectPlan → Except LowerError (Array CrosscallHelperSpec)
    | .storageScalarRead _ | .storageScalarReadTarget _
    | .storageStructFieldRead _ _ | .storageStructFieldReadTarget _
    | .storageDynamicArrayPop _ | .storageDynamicArrayPopTarget _ =>
        .ok #[]
    | .storageScalarWrite _ value
    | .storageScalarWriteTarget _ value
    | .storageScalarAssignOp _ _ value
    | .storageScalarAssignOpTarget _ _ value
    | .storageStructFieldWrite _ _ value
    | .storageStructFieldWriteTarget _ value
    | .storageDynamicArrayPush _ value
    | .storageDynamicArrayPushTarget _ value =>
        crosscallHelperSpecsFromExprPlan module value
    | .storageMapContains _ key
    | .storageMapContainsTarget _ key
    | .storageMapGet _ key
    | .storageMapGetTarget _ key
    | .storageArrayRead _ key
    | .storageArrayReadTarget _ key
    | .storageArrayStructFieldRead _ key _
    | .storageArrayStructFieldReadTarget _ key =>
        crosscallHelperSpecsFromExprPlan module key
    | .storageMapInsert _ key value
    | .storageMapInsertTarget _ key value
    | .storageMapSet _ key value
    | .storageMapSetTarget _ key value
    | .storageArrayWrite _ key value
    | .storageArrayWriteTarget _ key value
    | .storageArrayStructFieldWrite _ key _ value
    | .storageArrayStructFieldWriteTarget _ key value => do
        let keySpecs ← crosscallHelperSpecsFromExprPlan module key
        let valueSpecs ← crosscallHelperSpecsFromExprPlan module value
        .ok (mergeCrosscallHelperSpecs keySpecs valueSpecs)
    | .memoryArraySet array index value => do
        let arraySpecs ← crosscallHelperSpecsFromExprPlan module array
        let indexSpecs ← crosscallHelperSpecsFromExprPlan module index
        let valueSpecs ← crosscallHelperSpecsFromExprPlan module value
        .ok (mergeCrosscallHelperSpecs (mergeCrosscallHelperSpecs arraySpecs indexSpecs) valueSpecs)
    | .storagePathRead _ _ =>
        .ok #[]
    | .storagePathReadTarget slot =>
        match slot with
        | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
            keys.foldlM (init := #[]) fun acc valuePlan => do
              match valuePlan with
              | .irExpr _ => .ok acc
        | .arraySlot .. | .structArrayFieldSlot .. | .dynamicArraySlot ..
        | .scalarSlot _ | .fixedSlot _ =>
            .ok #[]
    | .storagePathReadExprTarget slot =>
        crosscallHelperSpecsFromStorageSlotExprPlan module slot
    | .storagePathWrite _ _ value | .storagePathAssignOp _ _ _ value =>
        crosscallHelperSpecsFromExprPlan module value
    | .storagePathWriteTarget target value
    | .storagePathAssignOpTarget target _ value => do
        let targetSpecs ←
          match target with
          | .mapWrite _ (.irExpr _) => .ok #[]
          | .singleSlot _ => .ok #[]
          | .mapValuePresence _ _ => .ok #[]
        .ok (mergeCrosscallHelperSpecs targetSpecs (← crosscallHelperSpecsFromExprPlan module value))
    | .storagePathWriteExprTarget target value
    | .storagePathAssignOpExprTarget target _ value => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromStoragePathWriteExprTargetPlan module target)
          (← crosscallHelperSpecsFromExprPlan module value))
    | .contextRead field =>
        crosscallHelperSpecsFromContextExprPlan module field
    | .eventEmit _ dataFields =>
        dataFields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromAbiValuePlan module field))
    | .eventEmitIndexed _ indexedFields dataFields => do
        let indexedSpecs ← indexedFields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromAbiValuePlan module field))
        dataFields.foldlM (init := indexedSpecs) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromAbiValuePlan module field))
    | .eventEmitWords _ dataFieldWords =>
        dataFieldWords.foldlM (init := #[]) fun acc words => do
          words.foldlM (init := acc) fun wordAcc word => do
            .ok (mergeCrosscallHelperSpecs wordAcc (← crosscallHelperSpecsFromExprPlan module word))
    | .eventEmitIndexedWords _ indexedFieldWords dataFieldWords => do
        let indexedSpecs ← indexedFieldWords.foldlM (init := #[]) fun acc words => do
          words.foldlM (init := acc) fun wordAcc word => do
            .ok (mergeCrosscallHelperSpecs wordAcc (← crosscallHelperSpecsFromExprPlan module word))
        dataFieldWords.foldlM (init := indexedSpecs) fun acc words => do
          words.foldlM (init := acc) fun wordAcc word => do
            .ok (mergeCrosscallHelperSpecs wordAcc (← crosscallHelperSpecsFromExprPlan module word))

  partial def crosscallHelperSpecsFromStmtPlan
      (module : Module) : StmtPlan → Except LowerError (Array CrosscallHelperSpec)
    | .letBind _ _ value
    | .letMutBind _ _ value
    | .assert value _ _
    | .return value =>
        crosscallHelperSpecsFromExprPlan module value
    | .assign target value
    | .assignOp target _ value => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module target)
          (← crosscallHelperSpecsFromExprPlan module value))
    | .effect effect =>
        crosscallHelperSpecsFromEffectPlan module effect
    | .assertEq lhs rhs _ _ => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module lhs)
          (← crosscallHelperSpecsFromExprPlan module rhs))
    | .release _ | .revert _ | .revertWithError _ =>
        .ok #[]
    | .ifElse condition thenBody elseBody => do
        let conditionSpecs ← crosscallHelperSpecsFromExprPlan module condition
        let thenSpecs ← crosscallHelperSpecsFromStmtPlans module thenBody
        let elseSpecs ← crosscallHelperSpecsFromStmtPlans module elseBody
        .ok (mergeCrosscallHelperSpecs conditionSpecs (mergeCrosscallHelperSpecs thenSpecs elseSpecs))
    | .boundedFor _ _ _ body =>
        crosscallHelperSpecsFromStmtPlans module body

  partial def crosscallHelperSpecsFromStmtPlans
      (module : Module)
      (statements : Array StmtPlan) : Except LowerError (Array CrosscallHelperSpec) :=
    statements.foldlM (init := #[]) fun acc stmt => do
      .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromStmtPlan module stmt))
end

def buildCrosscallHelperPlansFromEntrypoints
    (module : Module)
    (entrypoints : Array EntrypointPlan) : Except LowerError (Array CrosscallHelperSpec) :=
  entrypoints.foldlM (init := #[]) fun acc entrypoint => do
    .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromStmtPlans module entrypoint.body))

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

mutual
  partial def createHelperSpecsFromContextExprPlan : ContextExprPlan → Array CreateHelperSpec
    | .blockHash blockNumber =>
        createHelperSpecsFromExprPlan blockNumber
    | .userId | .contractId | .checkpointId | .timestamp | .chainId
    | .gasPrice | .gasLeft | .baseFee | .prevRandao | .origin | .coinbase =>
        #[]

  partial def createHelperSpecsFromStorageSlotExprPlan : StorageSlotExprPlan → Array CreateHelperSpec
    | .scalarSlot _ | .fixedSlot _ => #[]
    | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
        keys.foldl (init := #[]) fun acc key =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExprPlan key)
    | .arraySlot _ _ index
    | .structArrayFieldSlot _ _ _ _ index
    | .dynamicArraySlot _ index =>
        createHelperSpecsFromExprPlan index

  partial def createHelperSpecsFromStoragePathWriteExprTargetPlan :
      StoragePathWriteExprTargetPlan → Array CreateHelperSpec
    | .mapWrite _ key =>
        createHelperSpecsFromExprPlan key
    | .singleSlot slot =>
        createHelperSpecsFromStorageSlotExprPlan slot
    | .mapValuePresence valueSlot presenceSlot =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromStorageSlotExprPlan valueSlot)
          (createHelperSpecsFromStorageSlotExprPlan presenceSlot)

  partial def createHelperSpecsFromAbiValuePlan : AbiValuePlan → Array CreateHelperSpec
    | .expr value =>
        createHelperSpecsFromExprPlan value
    | .local .. | .storage .. =>
        #[]
    | .arrayLit _ values =>
        values.foldl (init := #[]) fun acc value =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromAbiValuePlan value)
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromAbiValuePlan field.snd)

  partial def createHelperSpecsFromCrosscallArgWordPlan :
      CrosscallArgWordPlan → Array CreateHelperSpec
    | .expr value =>
        createHelperSpecsFromExprPlan value
    | .local .. | .storage .. =>
        #[]

  partial def createHelperSpecsFromExprPlan : ExprPlan → Array CreateHelperSpec
    | .literalWord _ | .local _ | .calldataWord _ | .nativeValue =>
        #[]
    | .storageLoad slot =>
        match slot with
        | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
            keys.foldl (init := #[]) fun acc valuePlan =>
              match valuePlan with
              | .irExpr _ => acc
        | .arraySlot .. | .structArrayFieldSlot .. | .dynamicArraySlot ..
        | .scalarSlot _ | .fixedSlot _ =>
            #[]
    | .builtin _ args | .helperCall _ args | .arrayLit _ args =>
        args.foldl (init := #[]) fun acc arg =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExprPlan arg)
    | .checkedArith _ lhs rhs
    | .arrayGet lhs rhs
    | .hashTwoToOne lhs rhs =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan lhs)
          (createHelperSpecsFromExprPlan rhs)
    | .hashPack a b c d | .hashValue a b c d =>
        let ab := mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan a)
          (createHelperSpecsFromExprPlan b)
        let cd := mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan c)
          (createHelperSpecsFromExprPlan d)
        mergeCreateHelperSpecs ab cd
    | .context field =>
        createHelperSpecsFromContextExprPlan field
    | .crosscall _ target methodId callValue? args _ =>
        let nested := mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan target)
          (createHelperSpecsFromExprPlan methodId)
        let nested :=
          match callValue? with
          | some callValue => mergeCreateHelperSpecs nested (createHelperSpecsFromExprPlan callValue)
          | none => nested
        args.foldl (init := nested) fun acc arg =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromCrosscallArgWordPlan arg)
    | .create mode callValue salt? initCodeHex =>
        let nested :=
          match salt? with
          | some salt =>
              mergeCreateHelperSpecs
                (createHelperSpecsFromExprPlan callValue)
                (createHelperSpecsFromExprPlan salt)
          | none =>
              createHelperSpecsFromExprPlan callValue
        pushCreateHelperSpecIfMissing nested { mode, initCodeHex }
    | .cast source _
    | .structField source _
    | .memoryArrayLength source
    | .hash source =>
        createHelperSpecsFromExprPlan source
    | .localArrayGet _ path _ =>
        path.foldl (init := #[]) fun acc index =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExprPlan index)
    | .memoryArrayNew _ length =>
        createHelperSpecsFromExprPlan length
    | .memoryArrayGet array index =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan array)
          (createHelperSpecsFromExprPlan index)
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExprPlan field.snd)
    | .effect effect =>
        createHelperSpecsFromEffectPlan effect

  partial def createHelperSpecsFromEffectPlan : EffectPlan → Array CreateHelperSpec
    | .storageScalarRead _ | .storageScalarReadTarget _
    | .storageStructFieldRead _ _ | .storageStructFieldReadTarget _
    | .storageDynamicArrayPop _ | .storageDynamicArrayPopTarget _ =>
        #[]
    | .storageScalarWrite _ value
    | .storageScalarWriteTarget _ value
    | .storageScalarAssignOp _ _ value
    | .storageScalarAssignOpTarget _ _ value
    | .storageStructFieldWrite _ _ value
    | .storageStructFieldWriteTarget _ value
    | .storageDynamicArrayPush _ value
    | .storageDynamicArrayPushTarget _ value =>
        createHelperSpecsFromExprPlan value
    | .storageMapContains _ key
    | .storageMapContainsTarget _ key
    | .storageMapGet _ key
    | .storageMapGetTarget _ key
    | .storageArrayRead _ key
    | .storageArrayReadTarget _ key
    | .storageArrayStructFieldRead _ key _
    | .storageArrayStructFieldReadTarget _ key =>
        createHelperSpecsFromExprPlan key
    | .storageMapInsert _ key value
    | .storageMapInsertTarget _ key value
    | .storageMapSet _ key value
    | .storageMapSetTarget _ key value
    | .storageArrayWrite _ key value
    | .storageArrayWriteTarget _ key value
    | .storageArrayStructFieldWrite _ key _ value
    | .storageArrayStructFieldWriteTarget _ key value =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan key)
          (createHelperSpecsFromExprPlan value)
    | .memoryArraySet array index value =>
        mergeCreateHelperSpecs
          (mergeCreateHelperSpecs
            (createHelperSpecsFromExprPlan array)
            (createHelperSpecsFromExprPlan index))
          (createHelperSpecsFromExprPlan value)
    | .storagePathRead _ _ =>
        #[]
    | .storagePathReadTarget slot =>
        match slot with
        | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
            keys.foldl (init := #[]) fun acc valuePlan =>
              match valuePlan with
              | .irExpr _ => acc
        | .arraySlot .. | .structArrayFieldSlot .. | .dynamicArraySlot ..
        | .scalarSlot _ | .fixedSlot _ =>
            #[]
    | .storagePathReadExprTarget slot =>
        createHelperSpecsFromStorageSlotExprPlan slot
    | .storagePathWrite _ _ value | .storagePathAssignOp _ _ _ value =>
        createHelperSpecsFromExprPlan value
    | .storagePathWriteTarget target value
    | .storagePathAssignOpTarget target _ value =>
        let targetSpecs :=
          match target with
          | .mapWrite _ (.irExpr _) => #[]
          | .singleSlot _ => #[]
          | .mapValuePresence _ _ => #[]
        mergeCreateHelperSpecs targetSpecs (createHelperSpecsFromExprPlan value)
    | .storagePathWriteExprTarget target value
    | .storagePathAssignOpExprTarget target _ value =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromStoragePathWriteExprTargetPlan target)
          (createHelperSpecsFromExprPlan value)
    | .contextRead field =>
        createHelperSpecsFromContextExprPlan field
    | .eventEmit _ dataFields =>
        dataFields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromAbiValuePlan field)
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexedSpecs := indexedFields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromAbiValuePlan field)
        dataFields.foldl (init := indexedSpecs) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromAbiValuePlan field)
    | .eventEmitWords _ dataFieldWords =>
        dataFieldWords.foldl (init := #[]) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeCreateHelperSpecs wordAcc (createHelperSpecsFromExprPlan word)
    | .eventEmitIndexedWords _ indexedFieldWords dataFieldWords =>
        let indexedSpecs := indexedFieldWords.foldl (init := #[]) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeCreateHelperSpecs wordAcc (createHelperSpecsFromExprPlan word)
        dataFieldWords.foldl (init := indexedSpecs) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeCreateHelperSpecs wordAcc (createHelperSpecsFromExprPlan word)

  partial def createHelperSpecsFromStmtPlan : StmtPlan → Array CreateHelperSpec
    | .letBind _ _ value
    | .letMutBind _ _ value
    | .assert value _ _
    | .return value =>
        createHelperSpecsFromExprPlan value
    | .assign target value
    | .assignOp target _ value =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan target)
          (createHelperSpecsFromExprPlan value)
    | .effect effect =>
        createHelperSpecsFromEffectPlan effect
    | .assertEq lhs rhs _ _ =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan lhs)
          (createHelperSpecsFromExprPlan rhs)
    | .release _ | .revert _ | .revertWithError _ =>
        #[]
    | .ifElse condition thenBody elseBody =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan condition)
          (mergeCreateHelperSpecs (createHelperSpecsFromStmtPlans thenBody) (createHelperSpecsFromStmtPlans elseBody))
    | .boundedFor _ _ _ body =>
        createHelperSpecsFromStmtPlans body

  partial def createHelperSpecsFromStmtPlans (statements : Array StmtPlan) : Array CreateHelperSpec :=
    statements.foldl (init := #[]) fun acc stmt =>
      mergeCreateHelperSpecs acc (createHelperSpecsFromStmtPlan stmt)
end

def buildCreateHelperPlansFromEntrypoints
    (entrypoints : Array EntrypointPlan) : Array CreateHelperSpec :=
  entrypoints.foldl (init := #[]) fun acc entrypoint =>
    mergeCreateHelperSpecs acc (createHelperSpecsFromStmtPlans entrypoint.body)

def valuePlanUsesCheckedArithmetic : ValuePlan → Bool
  | .irExpr expr => ProofForge.Backend.Evm.Validate.exprUsesCheckedArithmetic expr

def storagePathSegmentUsesCheckedArithmetic : StoragePathSegment → Bool
  | .field _ => false
  | .index index => ProofForge.Backend.Evm.Validate.exprUsesCheckedArithmetic index
  | .mapKey key => ProofForge.Backend.Evm.Validate.exprUsesCheckedArithmetic key

def storageSlotPlanUsesCheckedArithmetic : StorageSlotPlan → Bool
  | .scalarSlot _ | .fixedSlot _ => false
  | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
      keys.any valuePlanUsesCheckedArithmetic
  | .arraySlot _ _ index
  | .structArrayFieldSlot _ _ _ _ index
  | .dynamicArraySlot _ index =>
      valuePlanUsesCheckedArithmetic index

def storagePathWriteTargetPlanUsesCheckedArithmetic : StoragePathWriteTargetPlan → Bool
  | .mapWrite _ key =>
      valuePlanUsesCheckedArithmetic key
  | .singleSlot slot =>
      storageSlotPlanUsesCheckedArithmetic slot
  | .mapValuePresence valueSlot presenceSlot =>
      storageSlotPlanUsesCheckedArithmetic valueSlot ||
        storageSlotPlanUsesCheckedArithmetic presenceSlot

mutual
  partial def contextExprPlanUsesCheckedArithmetic : ContextExprPlan → Bool
    | .blockHash blockNumber =>
        exprPlanUsesCheckedArithmetic blockNumber
    | .userId | .contractId | .checkpointId | .timestamp | .chainId
    | .gasPrice | .gasLeft | .baseFee | .prevRandao | .origin | .coinbase =>
        false

  partial def storageSlotExprPlanUsesCheckedArithmetic : StorageSlotExprPlan → Bool
    | .scalarSlot _ | .fixedSlot _ => false
    | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
        keys.any exprPlanUsesCheckedArithmetic
    | .arraySlot _ _ index
    | .structArrayFieldSlot _ _ _ _ index
    | .dynamicArraySlot _ index =>
        exprPlanUsesCheckedArithmetic index

  partial def storagePathWriteExprTargetPlanUsesCheckedArithmetic :
      StoragePathWriteExprTargetPlan → Bool
    | .mapWrite _ key =>
        exprPlanUsesCheckedArithmetic key
    | .singleSlot slot =>
        storageSlotExprPlanUsesCheckedArithmetic slot
    | .mapValuePresence valueSlot presenceSlot =>
        storageSlotExprPlanUsesCheckedArithmetic valueSlot ||
          storageSlotExprPlanUsesCheckedArithmetic presenceSlot

  partial def abiValuePlanUsesCheckedArithmetic : AbiValuePlan → Bool
    | .expr value =>
        exprPlanUsesCheckedArithmetic value
    | .local .. | .storage .. =>
        false
    | .arrayLit _ values =>
        values.any abiValuePlanUsesCheckedArithmetic
    | .structLit _ fields =>
        fields.any (fun field => abiValuePlanUsesCheckedArithmetic field.snd)

  partial def crosscallArgWordPlanUsesCheckedArithmetic : CrosscallArgWordPlan → Bool
    | .expr value =>
        exprPlanUsesCheckedArithmetic value
    | .local .. | .storage .. =>
        false

  partial def exprPlanUsesCheckedArithmetic : ExprPlan → Bool
    | .literalWord _ | .local _ | .calldataWord _ | .nativeValue =>
        false
    | .storageLoad slot =>
        storageSlotPlanUsesCheckedArithmetic slot
    | .builtin _ args | .helperCall _ args | .arrayLit _ args =>
        args.any exprPlanUsesCheckedArithmetic
    | .checkedArith op lhs rhs =>
        needsCheckedArithmetic op ||
          exprPlanUsesCheckedArithmetic lhs ||
          exprPlanUsesCheckedArithmetic rhs
    | .arrayGet lhs rhs
    | .hashTwoToOne lhs rhs =>
        exprPlanUsesCheckedArithmetic lhs || exprPlanUsesCheckedArithmetic rhs
    | .hashPack a b c d | .hashValue a b c d =>
        exprPlanUsesCheckedArithmetic a ||
          exprPlanUsesCheckedArithmetic b ||
          exprPlanUsesCheckedArithmetic c ||
          exprPlanUsesCheckedArithmetic d
    | .context field =>
        contextExprPlanUsesCheckedArithmetic field
    | .crosscall _ target methodId callValue? args _ =>
        exprPlanUsesCheckedArithmetic target ||
          exprPlanUsesCheckedArithmetic methodId ||
          (match callValue? with
          | some callValue => exprPlanUsesCheckedArithmetic callValue
          | none => false) ||
          args.any crosscallArgWordPlanUsesCheckedArithmetic
    | .create _ callValue salt? _ =>
        exprPlanUsesCheckedArithmetic callValue ||
          (match salt? with
          | some salt => exprPlanUsesCheckedArithmetic salt
          | none => false)
    | .cast source _
    | .structField source _
    | .memoryArrayLength source
    | .hash source =>
        exprPlanUsesCheckedArithmetic source
    | .localArrayGet _ path _ =>
        path.any exprPlanUsesCheckedArithmetic
    | .memoryArrayNew _ length =>
        exprPlanUsesCheckedArithmetic length
    | .memoryArrayGet array index =>
        exprPlanUsesCheckedArithmetic array || exprPlanUsesCheckedArithmetic index
    | .structLit _ fields =>
        fields.any (fun field => exprPlanUsesCheckedArithmetic field.snd)
    | .effect effect =>
        effectPlanUsesCheckedArithmetic effect

  partial def effectPlanUsesCheckedArithmetic : EffectPlan → Bool
    | .storageScalarRead _ | .storageStructFieldRead _ _
    | .storageDynamicArrayPop _ | .storageDynamicArrayPopTarget _ =>
        false
    | .storageScalarReadTarget target =>
        storageSlotPlanUsesCheckedArithmetic target.slot
    | .storageStructFieldReadTarget target =>
        storageSlotPlanUsesCheckedArithmetic target.slot
    | .storageScalarWrite _ value
    | .storageScalarWriteTarget _ value
    | .storageStructFieldWrite _ _ value
    | .storageStructFieldWriteTarget _ value
    | .storageDynamicArrayPush _ value
    | .storageDynamicArrayPushTarget _ value =>
        exprPlanUsesCheckedArithmetic value
    | .storageScalarAssignOp _ op value
    | .storageScalarAssignOpTarget _ op value =>
        needsCheckedArithmetic op || exprPlanUsesCheckedArithmetic value
    | .storageMapContains _ key
    | .storageMapContainsTarget _ key
    | .storageMapGet _ key
    | .storageMapGetTarget _ key
    | .storageArrayRead _ key
    | .storageArrayReadTarget _ key
    | .storageArrayStructFieldRead _ key _
    | .storageArrayStructFieldReadTarget _ key =>
        exprPlanUsesCheckedArithmetic key
    | .storageMapInsert _ key value
    | .storageMapInsertTarget _ key value
    | .storageMapSet _ key value
    | .storageMapSetTarget _ key value
    | .storageArrayWrite _ key value
    | .storageArrayWriteTarget _ key value
    | .storageArrayStructFieldWrite _ key _ value
    | .storageArrayStructFieldWriteTarget _ key value =>
        exprPlanUsesCheckedArithmetic key || exprPlanUsesCheckedArithmetic value
    | .memoryArraySet array index value =>
        exprPlanUsesCheckedArithmetic array ||
          exprPlanUsesCheckedArithmetic index ||
          exprPlanUsesCheckedArithmetic value
    | .storagePathRead _ path =>
        path.any storagePathSegmentUsesCheckedArithmetic
    | .storagePathReadTarget slot =>
        storageSlotPlanUsesCheckedArithmetic slot
    | .storagePathReadExprTarget slot =>
        storageSlotExprPlanUsesCheckedArithmetic slot
    | .storagePathWrite _ path value =>
        path.any storagePathSegmentUsesCheckedArithmetic ||
          exprPlanUsesCheckedArithmetic value
    | .storagePathAssignOp _ path op value =>
        path.any storagePathSegmentUsesCheckedArithmetic ||
          needsCheckedArithmetic op ||
          exprPlanUsesCheckedArithmetic value
    | .storagePathWriteTarget target value =>
        storagePathWriteTargetPlanUsesCheckedArithmetic target ||
          exprPlanUsesCheckedArithmetic value
    | .storagePathAssignOpTarget target op value =>
        storagePathWriteTargetPlanUsesCheckedArithmetic target ||
          needsCheckedArithmetic op ||
          exprPlanUsesCheckedArithmetic value
    | .storagePathWriteExprTarget target value =>
        storagePathWriteExprTargetPlanUsesCheckedArithmetic target ||
          exprPlanUsesCheckedArithmetic value
    | .storagePathAssignOpExprTarget target op value =>
        storagePathWriteExprTargetPlanUsesCheckedArithmetic target ||
          needsCheckedArithmetic op ||
          exprPlanUsesCheckedArithmetic value
    | .contextRead field =>
        contextExprPlanUsesCheckedArithmetic field
    | .eventEmit _ dataFields =>
        dataFields.any abiValuePlanUsesCheckedArithmetic
    | .eventEmitIndexed _ indexedFields dataFields =>
        indexedFields.any abiValuePlanUsesCheckedArithmetic ||
          dataFields.any abiValuePlanUsesCheckedArithmetic
    | .eventEmitWords _ dataFieldWords =>
        dataFieldWords.any (fun words => words.any exprPlanUsesCheckedArithmetic)
    | .eventEmitIndexedWords _ indexedFieldWords dataFieldWords =>
        indexedFieldWords.any (fun words => words.any exprPlanUsesCheckedArithmetic) ||
          dataFieldWords.any (fun words => words.any exprPlanUsesCheckedArithmetic)

  partial def stmtPlanUsesCheckedArithmetic : StmtPlan → Bool
    | .letBind _ _ value
    | .letMutBind _ _ value
    | .assert value _ _
    | .return value =>
        exprPlanUsesCheckedArithmetic value
    | .assign target value =>
        exprPlanUsesCheckedArithmetic target || exprPlanUsesCheckedArithmetic value
    | .assignOp target op value =>
        exprPlanUsesCheckedArithmetic target ||
          needsCheckedArithmetic op ||
          exprPlanUsesCheckedArithmetic value
    | .effect effect =>
        effectPlanUsesCheckedArithmetic effect
    | .assertEq lhs rhs _ _ =>
        exprPlanUsesCheckedArithmetic lhs || exprPlanUsesCheckedArithmetic rhs
    | .release _ | .revert _ | .revertWithError _ =>
        false
    | .ifElse condition thenBody elseBody =>
        exprPlanUsesCheckedArithmetic condition ||
          thenBody.any stmtPlanUsesCheckedArithmetic ||
          elseBody.any stmtPlanUsesCheckedArithmetic
    | .boundedFor _ _ _ body =>
        body.any stmtPlanUsesCheckedArithmetic
end

def entrypointsUseCheckedArithmetic (entrypoints : Array EntrypointPlan) : Bool :=
  entrypoints.any fun entrypoint => entrypoint.body.any stmtPlanUsesCheckedArithmetic

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

abbrev LocalArrayHelperRequirements := Array Nat × Array (Array Nat)

def emptyLocalArrayHelperRequirements : LocalArrayHelperRequirements :=
  (#[], #[])

def mergeLocalArrayHelperRequirements
    (lhs rhs : LocalArrayHelperRequirements) : LocalArrayHelperRequirements :=
  (mergeNatSets lhs.fst rhs.fst, mergeNatArraySets lhs.snd rhs.snd)

def addLocalArrayGetLength
    (requirements : LocalArrayHelperRequirements)
    (length : Nat) : LocalArrayHelperRequirements :=
  (pushNatIfMissing requirements.fst length, requirements.snd)

def addNestedLocalArrayGetShape
    (requirements : LocalArrayHelperRequirements)
    (shape : Array Nat) : LocalArrayHelperRequirements :=
  (requirements.fst, pushNatArrayIfMissing requirements.snd shape)

def exprPlanLiteralWord? : ExprPlan → Option Nat
  | .literalWord value => some value
  | _ => none

def exprPlanPathIsStatic (path : Array ExprPlan) : Bool :=
  path.all fun index => exprPlanLiteralWord? index |>.isSome

def localArrayGetRequirementsFromPath
    (path : Array ExprPlan)
    (lengths : Array Nat) : LocalArrayHelperRequirements :=
  if path.size == lengths.size && !exprPlanPathIsStatic path then
    match lengths.toList with
    | [] => emptyLocalArrayHelperRequirements
    | [length] => addLocalArrayGetLength emptyLocalArrayHelperRequirements length
    | _ => addNestedLocalArrayGetShape emptyLocalArrayHelperRequirements lengths
  else
    emptyLocalArrayHelperRequirements

mutual
  partial def localArrayHelperRequirementsFromStorageSlotExprPlan :
      StorageSlotExprPlan → LocalArrayHelperRequirements
    | .scalarSlot _ | .fixedSlot _ => emptyLocalArrayHelperRequirements
    | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
        keys.foldl (init := emptyLocalArrayHelperRequirements) fun acc key =>
          mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromExprPlan key)
    | .arraySlot _ _ index
    | .structArrayFieldSlot _ _ _ _ index
    | .dynamicArraySlot _ index =>
        localArrayHelperRequirementsFromExprPlan index

  partial def localArrayHelperRequirementsFromStoragePathWriteExprTargetPlan :
      StoragePathWriteExprTargetPlan → LocalArrayHelperRequirements
    | .mapWrite _ key =>
        localArrayHelperRequirementsFromExprPlan key
    | .singleSlot slot =>
        localArrayHelperRequirementsFromStorageSlotExprPlan slot
    | .mapValuePresence valueSlot presenceSlot =>
        mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromStorageSlotExprPlan valueSlot)
          (localArrayHelperRequirementsFromStorageSlotExprPlan presenceSlot)

  partial def localArrayHelperRequirementsFromContextExprPlan :
      ContextExprPlan → LocalArrayHelperRequirements
    | .blockHash blockNumber =>
        localArrayHelperRequirementsFromExprPlan blockNumber
    | .userId | .contractId | .checkpointId | .timestamp | .chainId
    | .gasPrice | .gasLeft | .baseFee | .prevRandao | .origin | .coinbase =>
        emptyLocalArrayHelperRequirements

  partial def localArrayHelperRequirementsFromAbiValuePlan :
      AbiValuePlan → LocalArrayHelperRequirements
    | .expr value =>
        localArrayHelperRequirementsFromExprPlan value
    | .local .. | .storage .. =>
        emptyLocalArrayHelperRequirements
    | .arrayLit _ values =>
        values.foldl (init := emptyLocalArrayHelperRequirements) fun acc value =>
          mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromAbiValuePlan value)
    | .structLit _ fields =>
        fields.foldl (init := emptyLocalArrayHelperRequirements) fun acc field =>
          mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromAbiValuePlan field.snd)

  partial def localArrayHelperRequirementsFromCrosscallArgWordPlan :
      CrosscallArgWordPlan → LocalArrayHelperRequirements
    | .expr value =>
        localArrayHelperRequirementsFromExprPlan value
    | .local .. | .storage .. =>
        emptyLocalArrayHelperRequirements

  partial def localArrayHelperRequirementsFromExprPlan :
      ExprPlan → LocalArrayHelperRequirements
    | .literalWord _ | .local _ | .calldataWord _ | .nativeValue =>
        emptyLocalArrayHelperRequirements
    | .storageLoad _ =>
        emptyLocalArrayHelperRequirements
    | .builtin _ args | .helperCall _ args | .arrayLit _ args =>
        args.foldl (init := emptyLocalArrayHelperRequirements) fun acc arg =>
          mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromExprPlan arg)
    | .checkedArith _ lhs rhs
    | .hashTwoToOne lhs rhs =>
        mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan lhs)
          (localArrayHelperRequirementsFromExprPlan rhs)
    | .hashPack a b c d | .hashValue a b c d =>
        let ab := mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan a)
          (localArrayHelperRequirementsFromExprPlan b)
        let cd := mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan c)
          (localArrayHelperRequirementsFromExprPlan d)
        mergeLocalArrayHelperRequirements ab cd
    | .context field =>
        localArrayHelperRequirementsFromContextExprPlan field
    | .crosscall _ target methodId callValue? args _ =>
        let nested := mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan target)
          (localArrayHelperRequirementsFromExprPlan methodId)
        let nested :=
          match callValue? with
          | some callValue =>
              mergeLocalArrayHelperRequirements nested (localArrayHelperRequirementsFromExprPlan callValue)
          | none => nested
        args.foldl (init := nested) fun acc arg =>
          mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromCrosscallArgWordPlan arg)
    | .create _ callValue salt? _ =>
        match salt? with
        | some salt =>
            mergeLocalArrayHelperRequirements
              (localArrayHelperRequirementsFromExprPlan callValue)
              (localArrayHelperRequirementsFromExprPlan salt)
        | none =>
            localArrayHelperRequirementsFromExprPlan callValue
    | .cast source _
    | .structField source _
    | .memoryArrayLength source
    | .hash source =>
        localArrayHelperRequirementsFromExprPlan source
    | .arrayGet array index =>
        let nested := mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan array)
          (localArrayHelperRequirementsFromExprPlan index)
        match array with
        | .arrayLit _ values =>
            if values.isEmpty || (exprPlanLiteralWord? index).isSome then
              nested
            else
              addLocalArrayGetLength nested values.size
        | _ =>
            nested
    | .localArrayGet _ path lengths =>
        let nested := path.foldl (init := emptyLocalArrayHelperRequirements) fun acc index =>
          mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromExprPlan index)
        mergeLocalArrayHelperRequirements nested (localArrayGetRequirementsFromPath path lengths)
    | .memoryArrayNew _ length =>
        localArrayHelperRequirementsFromExprPlan length
    | .memoryArrayGet array index =>
        mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan array)
          (localArrayHelperRequirementsFromExprPlan index)
    | .structLit _ fields =>
        fields.foldl (init := emptyLocalArrayHelperRequirements) fun acc field =>
          mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromExprPlan field.snd)
    | .effect effect =>
        localArrayHelperRequirementsFromEffectPlan effect

  partial def localArrayHelperRequirementsFromEffectPlan :
      EffectPlan → LocalArrayHelperRequirements
    | .storageScalarRead _ | .storageScalarReadTarget _
    | .storageStructFieldRead _ _ | .storageStructFieldReadTarget _
    | .storageDynamicArrayPop _ | .storageDynamicArrayPopTarget _ =>
        emptyLocalArrayHelperRequirements
    | .storageScalarWrite _ value
    | .storageScalarWriteTarget _ value
    | .storageScalarAssignOp _ _ value
    | .storageScalarAssignOpTarget _ _ value
    | .storageStructFieldWrite _ _ value
    | .storageStructFieldWriteTarget _ value
    | .storageDynamicArrayPush _ value
    | .storageDynamicArrayPushTarget _ value =>
        localArrayHelperRequirementsFromExprPlan value
    | .storageMapContains _ key
    | .storageMapContainsTarget _ key
    | .storageMapGet _ key
    | .storageMapGetTarget _ key
    | .storageArrayRead _ key
    | .storageArrayReadTarget _ key
    | .storageArrayStructFieldRead _ key _
    | .storageArrayStructFieldReadTarget _ key =>
        localArrayHelperRequirementsFromExprPlan key
    | .storageMapInsert _ key value
    | .storageMapInsertTarget _ key value
    | .storageMapSet _ key value
    | .storageMapSetTarget _ key value
    | .storageArrayWrite _ key value
    | .storageArrayWriteTarget _ key value
    | .storageArrayStructFieldWrite _ key _ value
    | .storageArrayStructFieldWriteTarget _ key value =>
        mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan key)
          (localArrayHelperRequirementsFromExprPlan value)
    | .memoryArraySet array index value =>
        mergeLocalArrayHelperRequirements
          (mergeLocalArrayHelperRequirements
            (localArrayHelperRequirementsFromExprPlan array)
            (localArrayHelperRequirementsFromExprPlan index))
          (localArrayHelperRequirementsFromExprPlan value)
    | .storagePathRead _ _ | .storagePathReadTarget _ =>
        emptyLocalArrayHelperRequirements
    | .storagePathReadExprTarget slot =>
        localArrayHelperRequirementsFromStorageSlotExprPlan slot
    | .storagePathWrite _ _ value | .storagePathAssignOp _ _ _ value =>
        localArrayHelperRequirementsFromExprPlan value
    | .storagePathWriteTarget _ value | .storagePathAssignOpTarget _ _ value =>
        localArrayHelperRequirementsFromExprPlan value
    | .storagePathWriteExprTarget target value
    | .storagePathAssignOpExprTarget target _ value =>
        mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromStoragePathWriteExprTargetPlan target)
          (localArrayHelperRequirementsFromExprPlan value)
    | .contextRead field =>
        localArrayHelperRequirementsFromContextExprPlan field
    | .eventEmit _ dataFields =>
        dataFields.foldl (init := emptyLocalArrayHelperRequirements) fun acc field =>
          mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromAbiValuePlan field)
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexed := indexedFields.foldl (init := emptyLocalArrayHelperRequirements) fun acc field =>
          mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromAbiValuePlan field)
        dataFields.foldl (init := indexed) fun acc field =>
          mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromAbiValuePlan field)
    | .eventEmitWords _ dataFieldWords =>
        dataFieldWords.foldl (init := emptyLocalArrayHelperRequirements) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeLocalArrayHelperRequirements wordAcc (localArrayHelperRequirementsFromExprPlan word)
    | .eventEmitIndexedWords _ indexedFieldWords dataFieldWords =>
        let indexed := indexedFieldWords.foldl (init := emptyLocalArrayHelperRequirements) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeLocalArrayHelperRequirements wordAcc (localArrayHelperRequirementsFromExprPlan word)
        dataFieldWords.foldl (init := indexed) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeLocalArrayHelperRequirements wordAcc (localArrayHelperRequirementsFromExprPlan word)

  partial def localArrayHelperRequirementsFromStmtPlan :
      StmtPlan → LocalArrayHelperRequirements
    | .letBind _ _ value
    | .letMutBind _ _ value
    | .assert value _ _
    | .return value =>
        localArrayHelperRequirementsFromExprPlan value
    | .assign target value
    | .assignOp target _ value =>
        mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan target)
          (localArrayHelperRequirementsFromExprPlan value)
    | .effect effect =>
        localArrayHelperRequirementsFromEffectPlan effect
    | .assertEq lhs rhs _ _ =>
        mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan lhs)
          (localArrayHelperRequirementsFromExprPlan rhs)
    | .release _ | .revert _ | .revertWithError _ =>
        emptyLocalArrayHelperRequirements
    | .ifElse condition thenBody elseBody =>
        mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan condition)
          (mergeLocalArrayHelperRequirements
            (localArrayHelperRequirementsFromStmtPlans thenBody)
            (localArrayHelperRequirementsFromStmtPlans elseBody))
    | .boundedFor _ _ _ body =>
        localArrayHelperRequirementsFromStmtPlans body

  partial def localArrayHelperRequirementsFromStmtPlans
      (statements : Array StmtPlan) : LocalArrayHelperRequirements :=
    statements.foldl (init := emptyLocalArrayHelperRequirements) fun acc stmt =>
      mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromStmtPlan stmt)
end

def buildLocalArrayHelperRequirementsFromEntrypoints
    (entrypoints : Array EntrypointPlan) : LocalArrayHelperRequirements :=
  entrypoints.foldl (init := emptyLocalArrayHelperRequirements) fun acc entrypoint =>
    mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromStmtPlans entrypoint.body)

def pushHelperIfMissing (helpers : HelperSet) (helper : Helper) : HelperSet :=
  HelperSet.insert helpers helper

def mergeHelperSets (lhs rhs : HelperSet) : HelperSet :=
  rhs.foldl pushHelperIfMissing lhs

def removeMemoryArrayHelpers (helpers : HelperSet) : HelperSet :=
  helpers.filter fun helper =>
    !(helper == Helper.memoryArrayNew) && !(helper == Helper.memoryArrayGet)

def replaceMemoryArrayHelpers (helpers memoryHelpers : HelperSet) : HelperSet :=
  mergeHelperSets (removeMemoryArrayHelpers helpers) memoryHelpers

def isMemoryArrayHelper : Helper → Bool
  | .memoryArrayNew | .memoryArrayGet => true
  | _ => false

def isHashHelper : Helper → Bool
  | .hashWord | .hashPair => true
  | _ => false

def isStorageArrayHelper : Helper → Bool
  | .arraySlot | .structArraySlot | .dynamicArraySlot => true
  | _ => false

def isMapHelper : Helper → Bool
  | .mapSlot | .mapPresenceSlot | .mapWrite | .mapSetReturn | .mapAssign _ => true
  | _ => false

def removeHashHelpers (helpers : HelperSet) : HelperSet :=
  helpers.filter fun helper =>
    !(helper == Helper.hashWord) && !(helper == Helper.hashPair)

def replaceHashHelpers (helpers hashHelpers : HelperSet) : HelperSet :=
  mergeHelperSets (removeHashHelpers helpers) hashHelpers

def removeStorageArrayHelpers (helpers : HelperSet) : HelperSet :=
  helpers.filter fun helper =>
    !(helper == Helper.arraySlot) &&
      !(helper == Helper.structArraySlot) &&
      !(helper == Helper.dynamicArraySlot)

def replaceStorageArrayHelpers (helpers storageArrayHelpers : HelperSet) : HelperSet :=
  mergeHelperSets (removeStorageArrayHelpers helpers) storageArrayHelpers

def removeMapHelpers (helpers : HelperSet) : HelperSet :=
  helpers.filter fun helper => !isMapHelper helper

def insertMapHelperDependencies (helpers : HelperSet) : Helper → HelperSet
  | .mapWrite =>
      HelperSet.insert
        (HelperSet.insert
          (HelperSet.insert helpers .mapSlot)
          .mapPresenceSlot)
        .mapWrite
  | .mapSetReturn =>
      HelperSet.insert
        (HelperSet.insert
          (HelperSet.insert helpers .mapSlot)
          .mapPresenceSlot)
        .mapSetReturn
  | .mapAssign op =>
      HelperSet.insert
        (HelperSet.insert
          (HelperSet.insert helpers .mapSlot)
          .mapPresenceSlot)
        (.mapAssign op)
  | helper =>
      HelperSet.insert helpers helper

def closeMapHelpers (helpers : HelperSet) : HelperSet :=
  helpers.foldl insertMapHelperDependencies #[]

def replaceMapHelpers (helpers mapHelpers : HelperSet) : HelperSet :=
  mergeHelperSets (removeMapHelpers helpers) (closeMapHelpers mapHelpers)

mutual
  partial def plannedHelpersFromStorageSlotExprPlan : StorageSlotExprPlan → HelperSet
    | .scalarSlot _ | .fixedSlot _ => #[]
    | .mapValueSlot _ keys =>
        let nested := keys.foldl (init := #[]) fun acc key =>
          mergeHelperSets acc (plannedHelpersFromExprPlan key)
        HelperSet.insert nested .mapSlot
    | .mapPresenceSlot _ keys =>
        let nested := keys.foldl (init := #[]) fun acc key =>
          mergeHelperSets acc (plannedHelpersFromExprPlan key)
        let helpers := HelperSet.insert nested .mapPresenceSlot
        if keys.size > 1 then HelperSet.insert helpers .mapSlot else helpers
    | .arraySlot _ _ index =>
        HelperSet.insert (plannedHelpersFromExprPlan index) .arraySlot
    | .structArrayFieldSlot _ _ _ _ index =>
        HelperSet.insert (plannedHelpersFromExprPlan index) .structArraySlot
    | .dynamicArraySlot _ index =>
        HelperSet.insert (plannedHelpersFromExprPlan index) .dynamicArraySlot

  partial def plannedHelpersFromStoragePathWriteExprTargetPlan :
      StoragePathWriteExprTargetPlan → HelperSet
    | .mapWrite _ key =>
        HelperSet.insert (plannedHelpersFromExprPlan key) .mapWrite
    | .singleSlot slot =>
        plannedHelpersFromStorageSlotExprPlan slot
    | .mapValuePresence valueSlot presenceSlot =>
        mergeHelperSets
          (plannedHelpersFromStorageSlotExprPlan valueSlot)
          (plannedHelpersFromStorageSlotExprPlan presenceSlot)

  partial def plannedHelpersFromContextExprPlan : ContextExprPlan → HelperSet
    | .blockHash blockNumber =>
        plannedHelpersFromExprPlan blockNumber
    | .userId | .contractId | .checkpointId | .timestamp | .chainId
    | .gasPrice | .gasLeft | .baseFee | .prevRandao | .origin | .coinbase =>
        #[]

  partial def plannedHelpersFromAbiValuePlan : AbiValuePlan → HelperSet
    | .expr value =>
        plannedHelpersFromExprPlan value
    | .local .. | .storage .. =>
        #[]
    | .arrayLit _ values =>
        values.foldl (init := #[]) fun acc value =>
          mergeHelperSets acc (plannedHelpersFromAbiValuePlan value)
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeHelperSets acc (plannedHelpersFromAbiValuePlan field.snd)

  partial def plannedHelpersFromCrosscallArgWordPlan : CrosscallArgWordPlan → HelperSet
    | .expr value =>
        plannedHelpersFromExprPlan value
    | .local .. | .storage .. =>
        #[]

  partial def plannedHelpersFromExprPlan : ExprPlan → HelperSet
    | .literalWord _ | .local _ | .calldataWord _ | .nativeValue =>
        #[]
    | .storageLoad slot =>
        slot.requiredHelpers
    | .builtin _ args | .arrayLit _ args =>
        args.foldl (init := #[]) fun acc arg =>
          mergeHelperSets acc (plannedHelpersFromExprPlan arg)
    | .helperCall helper args =>
        let nested := args.foldl (init := #[]) fun acc arg =>
          mergeHelperSets acc (plannedHelpersFromExprPlan arg)
        HelperSet.insert nested helper
    | .checkedArith _ lhs rhs
    | .arrayGet lhs rhs =>
        mergeHelperSets
          (plannedHelpersFromExprPlan lhs)
          (plannedHelpersFromExprPlan rhs)
    | .hashTwoToOne lhs rhs =>
        HelperSet.insert
          (mergeHelperSets
            (plannedHelpersFromExprPlan lhs)
            (plannedHelpersFromExprPlan rhs))
          .hashPair
    | .hashPack a b c d | .hashValue a b c d =>
        let ab := mergeHelperSets
          (plannedHelpersFromExprPlan a)
          (plannedHelpersFromExprPlan b)
        let cd := mergeHelperSets
          (plannedHelpersFromExprPlan c)
          (plannedHelpersFromExprPlan d)
        mergeHelperSets ab cd
    | .context field =>
        plannedHelpersFromContextExprPlan field
    | .crosscall _ target methodId callValue? args _ =>
        let nested := mergeHelperSets
          (plannedHelpersFromExprPlan target)
          (plannedHelpersFromExprPlan methodId)
        let nested :=
          match callValue? with
          | some callValue =>
              mergeHelperSets nested (plannedHelpersFromExprPlan callValue)
          | none => nested
        args.foldl (init := nested) fun acc arg =>
          mergeHelperSets acc (plannedHelpersFromCrosscallArgWordPlan arg)
    | .create _ callValue salt? _ =>
        match salt? with
        | some salt =>
            mergeHelperSets
              (plannedHelpersFromExprPlan callValue)
              (plannedHelpersFromExprPlan salt)
        | none =>
            plannedHelpersFromExprPlan callValue
    | .cast source _
    | .structField source _
    | .memoryArrayLength source =>
        plannedHelpersFromExprPlan source
    | .hash source =>
        HelperSet.insert (plannedHelpersFromExprPlan source) .hashWord
    | .localArrayGet _ path _ =>
        path.foldl (init := #[]) fun acc index =>
          mergeHelperSets acc (plannedHelpersFromExprPlan index)
    | .memoryArrayNew _ length =>
        HelperSet.insert (plannedHelpersFromExprPlan length) .memoryArrayNew
    | .memoryArrayGet array index =>
        HelperSet.insert
          (mergeHelperSets
            (plannedHelpersFromExprPlan array)
            (plannedHelpersFromExprPlan index))
          .memoryArrayGet
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeHelperSets acc (plannedHelpersFromExprPlan field.snd)
    | .effect effect =>
        plannedHelpersFromEffectPlan .mapSetReturn effect

  partial def plannedHelpersFromEffectPlan (mapWriteHelper : Helper) : EffectPlan → HelperSet
    | .storageScalarRead _ | .storageScalarReadTarget _
    | .storageStructFieldRead _ _ | .storageStructFieldReadTarget _
    | .storageDynamicArrayPop _ | .storageDynamicArrayPopTarget _ =>
        #[]
    | .storageScalarWrite _ value
    | .storageScalarWriteTarget _ value
    | .storageScalarAssignOp _ _ value
    | .storageScalarAssignOpTarget _ _ value
    | .storageStructFieldWrite _ _ value
    | .storageStructFieldWriteTarget _ value
    | .storageDynamicArrayPush _ value
    | .storageDynamicArrayPushTarget _ value =>
        plannedHelpersFromExprPlan value
    | .storageMapContains _ key
    | .storageMapContainsTarget _ key =>
        HelperSet.insert (plannedHelpersFromExprPlan key) .mapPresenceSlot
    | .storageMapGet _ key
    | .storageMapGetTarget _ key =>
        HelperSet.insert (plannedHelpersFromExprPlan key) .mapSlot
    | .storageArrayRead _ key
    | .storageArrayReadTarget _ key
    | .storageArrayStructFieldRead _ key _
    | .storageArrayStructFieldReadTarget _ key =>
        plannedHelpersFromExprPlan key
    | .storageMapInsert _ key value
    | .storageMapInsertTarget _ key value
    | .storageMapSet _ key value
    | .storageMapSetTarget _ key value =>
        HelperSet.insert
          (mergeHelperSets
            (plannedHelpersFromExprPlan key)
            (plannedHelpersFromExprPlan value))
          mapWriteHelper
    | .storageArrayWrite _ key value
    | .storageArrayWriteTarget _ key value
    | .storageArrayStructFieldWrite _ key _ value
    | .storageArrayStructFieldWriteTarget _ key value =>
        mergeHelperSets
          (plannedHelpersFromExprPlan key)
          (plannedHelpersFromExprPlan value)
    | .memoryArraySet array index value =>
        mergeHelperSets
          (mergeHelperSets
            (plannedHelpersFromExprPlan array)
            (plannedHelpersFromExprPlan index))
          (plannedHelpersFromExprPlan value)
    | .storagePathRead _ _ | .storagePathReadTarget _ =>
        #[]
    | .storagePathReadExprTarget slot =>
        plannedHelpersFromStorageSlotExprPlan slot
    | .storagePathWrite _ _ value | .storagePathAssignOp _ _ _ value =>
        plannedHelpersFromExprPlan value
    | .storagePathWriteTarget _ value | .storagePathAssignOpTarget _ _ value =>
        plannedHelpersFromExprPlan value
    | .storagePathWriteExprTarget target value =>
        mergeHelperSets
          (plannedHelpersFromStoragePathWriteExprTargetPlan target)
          (plannedHelpersFromExprPlan value)
    | .storagePathAssignOpExprTarget target op value =>
        let targetHelpers :=
          match target with
          | .mapWrite _ key =>
              HelperSet.insert (plannedHelpersFromExprPlan key) (.mapAssign op)
          | .singleSlot slot =>
              plannedHelpersFromStorageSlotExprPlan slot
          | .mapValuePresence valueSlot presenceSlot =>
              mergeHelperSets
                (plannedHelpersFromStorageSlotExprPlan valueSlot)
                (plannedHelpersFromStorageSlotExprPlan presenceSlot)
        mergeHelperSets targetHelpers (plannedHelpersFromExprPlan value)
    | .contextRead field =>
        plannedHelpersFromContextExprPlan field
    | .eventEmit _ dataFields =>
        dataFields.foldl (init := #[]) fun acc field =>
          mergeHelperSets acc (plannedHelpersFromAbiValuePlan field)
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexed := indexedFields.foldl (init := #[]) fun acc field =>
          mergeHelperSets acc (plannedHelpersFromAbiValuePlan field)
        dataFields.foldl (init := indexed) fun acc field =>
          mergeHelperSets acc (plannedHelpersFromAbiValuePlan field)
    | .eventEmitWords _ dataFieldWords =>
        dataFieldWords.foldl (init := #[]) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeHelperSets wordAcc (plannedHelpersFromExprPlan word)
    | .eventEmitIndexedWords _ indexedFieldWords dataFieldWords =>
        let indexed := indexedFieldWords.foldl (init := #[]) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeHelperSets wordAcc (plannedHelpersFromExprPlan word)
        dataFieldWords.foldl (init := indexed) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeHelperSets wordAcc (plannedHelpersFromExprPlan word)

  partial def plannedHelpersFromStmtPlan : StmtPlan → HelperSet
    | .letBind _ _ value
    | .letMutBind _ _ value
    | .assert value _ _
    | .return value =>
        plannedHelpersFromExprPlan value
    | .assign target value
    | .assignOp target _ value =>
        mergeHelperSets
          (plannedHelpersFromExprPlan target)
          (plannedHelpersFromExprPlan value)
    | .effect effect =>
        plannedHelpersFromEffectPlan .mapWrite effect
    | .assertEq lhs rhs _ _ =>
        mergeHelperSets
          (plannedHelpersFromExprPlan lhs)
          (plannedHelpersFromExprPlan rhs)
    | .release _ | .revert _ | .revertWithError _ =>
        #[]
    | .ifElse condition thenBody elseBody =>
        mergeHelperSets
          (plannedHelpersFromExprPlan condition)
          (mergeHelperSets
            (plannedHelpersFromStmtPlans thenBody)
            (plannedHelpersFromStmtPlans elseBody))
    | .boundedFor _ _ _ body =>
        plannedHelpersFromStmtPlans body

  partial def plannedHelpersFromStmtPlans (statements : Array StmtPlan) : HelperSet :=
    statements.foldl (init := #[]) fun acc stmt =>
      mergeHelperSets acc (plannedHelpersFromStmtPlan stmt)
end

def buildPlannedHelpersFromEntrypoints (entrypoints : Array EntrypointPlan) : HelperSet :=
  entrypoints.foldl (init := #[]) fun acc entrypoint =>
    mergeHelperSets acc (plannedHelpersFromStmtPlans entrypoint.body)

def buildMemoryArrayHelpersFromEntrypoints (entrypoints : Array EntrypointPlan) : HelperSet :=
  (buildPlannedHelpersFromEntrypoints entrypoints).filter isMemoryArrayHelper

def buildHashHelpersFromEntrypoints (entrypoints : Array EntrypointPlan) : HelperSet :=
  (buildPlannedHelpersFromEntrypoints entrypoints).filter isHashHelper

def buildStorageArrayHelpersFromEntrypoints (entrypoints : Array EntrypointPlan) : HelperSet :=
  (buildPlannedHelpersFromEntrypoints entrypoints).filter isStorageArrayHelper

def buildMapHelpersFromEntrypoints (entrypoints : Array EntrypointPlan) : HelperSet :=
  (buildPlannedHelpersFromEntrypoints entrypoints).filter isMapHelper
    |> closeMapHelpers

def contextFieldFromContextExprPlan : ContextExprPlan → ContextField
  | .userId => .userId
  | .contractId => .contractId
  | .checkpointId => .checkpointId
  | .timestamp => .timestamp
  | .chainId => .chainId
  | .gasPrice => .gasPrice
  | .gasLeft => .gasLeft
  | .baseFee => .baseFee
  | .prevRandao => .prevRandao
  | .origin => .origin
  | .coinbase => .coinbase
  | .blockHash _ => .blockHash (.literal (.u64 0))

def pushContextPlanIfMissing (ops : Array ContextPlan) (op : ContextPlan) : Array ContextPlan :=
  if ops.any (fun existing => existing.field.name == op.field.name) then ops else ops.push op

def mergeContextPlans (lhs rhs : Array ContextPlan) : Array ContextPlan :=
  rhs.foldl pushContextPlanIfMissing lhs

mutual
  partial def contextOpsFromStorageSlotExprPlan :
      StorageSlotExprPlan → Array ContextPlan
    | .scalarSlot _ | .fixedSlot _ => #[]
    | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
        keys.foldl (init := #[]) fun acc key =>
          mergeContextPlans acc (contextOpsFromExprPlan key)
    | .arraySlot _ _ index
    | .structArrayFieldSlot _ _ _ _ index
    | .dynamicArraySlot _ index =>
        contextOpsFromExprPlan index

  partial def contextOpsFromStoragePathWriteExprTargetPlan :
      StoragePathWriteExprTargetPlan → Array ContextPlan
    | .mapWrite _ key =>
        contextOpsFromExprPlan key
    | .singleSlot slot =>
        contextOpsFromStorageSlotExprPlan slot
    | .mapValuePresence valueSlot presenceSlot =>
        mergeContextPlans
          (contextOpsFromStorageSlotExprPlan valueSlot)
          (contextOpsFromStorageSlotExprPlan presenceSlot)

  partial def contextOpsFromContextExprPlan : ContextExprPlan → Array ContextPlan
    | .blockHash blockNumber =>
        mergeContextPlans
          #[{ field := contextFieldFromContextExprPlan (.blockHash blockNumber) }]
          (contextOpsFromExprPlan blockNumber)
    | field =>
        #[{ field := contextFieldFromContextExprPlan field }]

  partial def contextOpsFromAbiValuePlan : AbiValuePlan → Array ContextPlan
    | .expr value =>
        contextOpsFromExprPlan value
    | .local .. | .storage .. =>
        #[]
    | .arrayLit _ values =>
        values.foldl (init := #[]) fun acc value =>
          mergeContextPlans acc (contextOpsFromAbiValuePlan value)
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeContextPlans acc (contextOpsFromAbiValuePlan field.snd)

  partial def contextOpsFromCrosscallArgWordPlan : CrosscallArgWordPlan → Array ContextPlan
    | .expr value =>
        contextOpsFromExprPlan value
    | .local .. | .storage .. =>
        #[]

  partial def contextOpsFromExprPlan : ExprPlan → Array ContextPlan
    | .literalWord _ | .local _ | .calldataWord _ | .nativeValue =>
        #[]
    | .storageLoad _ =>
        #[]
    | .builtin _ args | .helperCall _ args | .arrayLit _ args =>
        args.foldl (init := #[]) fun acc arg =>
          mergeContextPlans acc (contextOpsFromExprPlan arg)
    | .checkedArith _ lhs rhs
    | .hashTwoToOne lhs rhs =>
        mergeContextPlans
          (contextOpsFromExprPlan lhs)
          (contextOpsFromExprPlan rhs)
    | .hashPack a b c d | .hashValue a b c d =>
        let ab := mergeContextPlans
          (contextOpsFromExprPlan a)
          (contextOpsFromExprPlan b)
        let cd := mergeContextPlans
          (contextOpsFromExprPlan c)
          (contextOpsFromExprPlan d)
        mergeContextPlans ab cd
    | .context field =>
        contextOpsFromContextExprPlan field
    | .crosscall _ target methodId callValue? args _ =>
        let nested := mergeContextPlans
          (contextOpsFromExprPlan target)
          (contextOpsFromExprPlan methodId)
        let nested :=
          match callValue? with
          | some callValue =>
              mergeContextPlans nested (contextOpsFromExprPlan callValue)
          | none => nested
        args.foldl (init := nested) fun acc arg =>
          mergeContextPlans acc (contextOpsFromCrosscallArgWordPlan arg)
    | .create _ callValue salt? _ =>
        match salt? with
        | some salt =>
            mergeContextPlans
              (contextOpsFromExprPlan callValue)
              (contextOpsFromExprPlan salt)
        | none =>
            contextOpsFromExprPlan callValue
    | .cast source _
    | .structField source _
    | .memoryArrayLength source
    | .hash source =>
        contextOpsFromExprPlan source
    | .arrayGet array index
    | .memoryArrayGet array index =>
        mergeContextPlans
          (contextOpsFromExprPlan array)
          (contextOpsFromExprPlan index)
    | .localArrayGet _ path _ =>
        path.foldl (init := #[]) fun acc index =>
          mergeContextPlans acc (contextOpsFromExprPlan index)
    | .memoryArrayNew _ length =>
        contextOpsFromExprPlan length
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeContextPlans acc (contextOpsFromExprPlan field.snd)
    | .effect effect =>
        contextOpsFromEffectPlan effect

  partial def contextOpsFromEffectPlan : EffectPlan → Array ContextPlan
    | .storageScalarRead _ | .storageScalarReadTarget _
    | .storageStructFieldRead _ _ | .storageStructFieldReadTarget _
    | .storageDynamicArrayPop _ | .storageDynamicArrayPopTarget _ =>
        #[]
    | .storageScalarWrite _ value
    | .storageScalarWriteTarget _ value
    | .storageScalarAssignOp _ _ value
    | .storageScalarAssignOpTarget _ _ value
    | .storageStructFieldWrite _ _ value
    | .storageStructFieldWriteTarget _ value
    | .storageDynamicArrayPush _ value
    | .storageDynamicArrayPushTarget _ value =>
        contextOpsFromExprPlan value
    | .storageMapContains _ key
    | .storageMapContainsTarget _ key
    | .storageMapGet _ key
    | .storageMapGetTarget _ key
    | .storageArrayRead _ key
    | .storageArrayReadTarget _ key
    | .storageArrayStructFieldRead _ key _
    | .storageArrayStructFieldReadTarget _ key =>
        contextOpsFromExprPlan key
    | .storageMapInsert _ key value
    | .storageMapInsertTarget _ key value
    | .storageMapSet _ key value
    | .storageMapSetTarget _ key value
    | .storageArrayWrite _ key value
    | .storageArrayWriteTarget _ key value
    | .storageArrayStructFieldWrite _ key _ value
    | .storageArrayStructFieldWriteTarget _ key value =>
        mergeContextPlans
          (contextOpsFromExprPlan key)
          (contextOpsFromExprPlan value)
    | .memoryArraySet array index value =>
        mergeContextPlans
          (mergeContextPlans
            (contextOpsFromExprPlan array)
            (contextOpsFromExprPlan index))
          (contextOpsFromExprPlan value)
    | .storagePathRead _ _ | .storagePathReadTarget _ =>
        #[]
    | .storagePathReadExprTarget slot =>
        contextOpsFromStorageSlotExprPlan slot
    | .storagePathWrite _ _ value | .storagePathAssignOp _ _ _ value =>
        contextOpsFromExprPlan value
    | .storagePathWriteTarget _ value | .storagePathAssignOpTarget _ _ value =>
        contextOpsFromExprPlan value
    | .storagePathWriteExprTarget target value
    | .storagePathAssignOpExprTarget target _ value =>
        mergeContextPlans
          (contextOpsFromStoragePathWriteExprTargetPlan target)
          (contextOpsFromExprPlan value)
    | .contextRead field =>
        contextOpsFromContextExprPlan field
    | .eventEmit _ dataFields =>
        dataFields.foldl (init := #[]) fun acc field =>
          mergeContextPlans acc (contextOpsFromAbiValuePlan field)
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexed := indexedFields.foldl (init := #[]) fun acc field =>
          mergeContextPlans acc (contextOpsFromAbiValuePlan field)
        dataFields.foldl (init := indexed) fun acc field =>
          mergeContextPlans acc (contextOpsFromAbiValuePlan field)
    | .eventEmitWords _ dataFieldWords =>
        dataFieldWords.foldl (init := #[]) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeContextPlans wordAcc (contextOpsFromExprPlan word)
    | .eventEmitIndexedWords _ indexedFieldWords dataFieldWords =>
        let indexed := indexedFieldWords.foldl (init := #[]) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeContextPlans wordAcc (contextOpsFromExprPlan word)
        dataFieldWords.foldl (init := indexed) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeContextPlans wordAcc (contextOpsFromExprPlan word)

  partial def contextOpsFromStmtPlan : StmtPlan → Array ContextPlan
    | .letBind _ _ value
    | .letMutBind _ _ value
    | .assert value _ _
    | .return value =>
        contextOpsFromExprPlan value
    | .assign target value
    | .assignOp target _ value =>
        mergeContextPlans
          (contextOpsFromExprPlan target)
          (contextOpsFromExprPlan value)
    | .effect effect =>
        contextOpsFromEffectPlan effect
    | .assertEq lhs rhs _ _ =>
        mergeContextPlans
          (contextOpsFromExprPlan lhs)
          (contextOpsFromExprPlan rhs)
    | .release _ | .revert _ | .revertWithError _ =>
        #[]
    | .ifElse condition thenBody elseBody =>
        mergeContextPlans
          (contextOpsFromExprPlan condition)
          (mergeContextPlans
            (contextOpsFromStmtPlans thenBody)
            (contextOpsFromStmtPlans elseBody))
    | .boundedFor _ _ _ body =>
        contextOpsFromStmtPlans body

  partial def contextOpsFromStmtPlans (statements : Array StmtPlan) : Array ContextPlan :=
    statements.foldl (init := #[]) fun acc stmt =>
      mergeContextPlans acc (contextOpsFromStmtPlan stmt)
end

def buildContextOpsFromEntrypoints (entrypoints : Array EntrypointPlan) : Array ContextPlan :=
  entrypoints.foldl (init := #[]) fun acc entrypoint =>
    mergeContextPlans acc (contextOpsFromStmtPlans entrypoint.body)

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
  let crosscallPlans ← buildCrosscallHelperPlansFromEntrypoints module entrypointPlans
  let createPlans := buildCreateHelperPlansFromEntrypoints entrypointPlans
  let localArrayRequirements := buildLocalArrayHelperRequirementsFromEntrypoints entrypointPlans
  let localArrayGetLengths := localArrayRequirements.fst
  let nestedLocalArrayGetShapes := localArrayRequirements.snd
  let usesCheckedArithmetic := entrypointsUseCheckedArithmetic entrypointPlans
  let contextOps := buildContextOpsFromEntrypoints entrypointPlans
  let memoryArrayHelpers := buildMemoryArrayHelpersFromEntrypoints entrypointPlans
  let hashHelpers := buildHashHelpersFromEntrypoints entrypointPlans
  let storageArrayHelpers := buildStorageArrayHelpersFromEntrypoints entrypointPlans
  let mapHelpers := buildMapHelpersFromEntrypoints entrypointPlans
  let helpers := replaceHashHelpers
    (replaceMemoryArrayHelpers
      (replaceStorageArrayHelpers
        (replaceMapHelpers basePlan.helpers mapHelpers)
        storageArrayHelpers)
      memoryArrayHelpers)
    hashHelpers
  let mapAssignOps := helperMapAssignOps helpers
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
    contextOps := contextOps
    helpers := helpers
    mapAssignOps := mapAssignOps
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
  let crosscallPlans ← buildCrosscallHelperPlansFromEntrypoints module entrypointPlans
  let createPlans := buildCreateHelperPlansFromEntrypoints entrypointPlans
  let localArrayRequirements := buildLocalArrayHelperRequirementsFromEntrypoints entrypointPlans
  let localArrayGetLengths := localArrayRequirements.fst
  let nestedLocalArrayGetShapes := localArrayRequirements.snd
  let usesCheckedArithmetic := entrypointsUseCheckedArithmetic entrypointPlans
  let contextOps := buildContextOpsFromEntrypoints entrypointPlans
  let memoryArrayHelpers := buildMemoryArrayHelpersFromEntrypoints entrypointPlans
  let hashHelpers := buildHashHelpersFromEntrypoints entrypointPlans
  let storageArrayHelpers := buildStorageArrayHelpersFromEntrypoints entrypointPlans
  let mapHelpers := buildMapHelpersFromEntrypoints entrypointPlans
  let helpers := replaceHashHelpers
    (replaceMemoryArrayHelpers
      (replaceStorageArrayHelpers
        (replaceMapHelpers basePlan.helpers mapHelpers)
        storageArrayHelpers)
      memoryArrayHelpers)
    hashHelpers
  let mapAssignOps := helperMapAssignOps helpers
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
    contextOps := contextOps
    helpers := helpers
    mapAssignOps := mapAssignOps
    metadata := metadata
  }

end ProofForge.Backend.Evm.Lower
