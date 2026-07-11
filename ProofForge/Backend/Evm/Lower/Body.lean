import ProofForge.Backend.Evm.AbiType
import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.Lower.Requirements
import ProofForge.Backend.Evm.Validate
import ProofForge.IR.Contract
import ProofForge.Target.Adapter
import ProofForge.Target.ProtocolMaterialize
import ProofForge.Target.Registry

/-! # EVM entrypoint body plan lowering

This module contains the ABI/event word planning plus expression, effect, and
statement planning used to build `EntrypointPlan` bodies. `Lower.lean` imports
this layer and keeps the higher-level assignment-source, helper discovery, and
module assembly passes.
-/

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
    (headWordIndex : Nat)
    (abiWord? : Option String := none) : Except LowerError AbiParamPlan := do
  let wordTypes ← abiValueWordTypes module s!"{context} parameter `{name}`" type
  let localNames ←
    if abiTypeIsDynamic type then
      .ok #[dynamicParamLengthName name, dynamicParamDataPtrName name]
    else
      abiValueParamNames module s!"{context} parameter `{name}`" name type
  .ok { name, type, abiWord?, wordTypes, headWordIndex, localNames }

def entrypointParamPlans (module : Module) (entrypoint : Entrypoint) :
    Except LowerError (Array AbiParamPlan) := do
  if entrypoint.paramAbiWords.size > entrypoint.params.size then
    .error {
      message :=
        s!"entrypoint `{entrypoint.name}` has {entrypoint.paramAbiWords.size} ABI override entries for {entrypoint.params.size} parameter(s)"
    }
  let (_, params) ← entrypoint.params.foldlM (init := (0, #[])) fun acc param => do
    let (headWordIndex, params) := acc
    let paramIndex := params.size
    validateUserIdentifier s!"entrypoint `{entrypoint.name}` parameter" param.fst
    let abiWord? :=
      if h : paramIndex < entrypoint.paramAbiWords.size then
        entrypoint.paramAbiWords[paramIndex]
      else
        none
    match ProofForge.Backend.Evm.AbiType.validateAbiWordOverride
        s!"entrypoint `{entrypoint.name}` parameter `{param.fst}`" param.snd abiWord? with
    | .ok _ => pure ()
    | .error message => .error { message }
    let paramPlan ← abiParamPlan module s!"entrypoint `{entrypoint.name}`" param.fst param.snd
      headWordIndex abiWord?
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
  | .bytes _ => .error { message := "EVM literalPlan: bytes literal not yet supported (use memoryArrayNew + store)" }
  | .string _ => .error { message := "EVM literalPlan: string literal not yet supported (use memoryArrayNew + store)" }

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

def assignExprPlan
    (op : AssignOp)
    (lhs rhs : ExprPlan)
    (overflowChecked : Bool := true)
    (resultByteWidth? : Option Nat := none) : ExprPlan :=
  .checkedArith op lhs rhs overflowChecked resultByteWidth?

def inferredArithmeticByteWidth?
    (module : Module)
    (env : TypeEnv)
    (expr : Expr) : Option Nat :=
  match inferExprType module env expr with
  | .ok type =>
      let byteWidth := type.byteWidth
      if byteWidth == 0 then none else some byteWidth
  | .error _ => none

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
        match base with
        | .effect (.storageScalarRead stateId) => do
            let slotPlan ← lowerPlan <|
              ProofForge.Backend.Evm.Plan.structFieldSlotPlan module stateId fieldName
            .ok (.storageLoad slotPlan)
        | _ =>
            match ← localArrayStructFieldExprPlan? module env base fieldName with
            | some plan => .ok plan
            | none => .ok (.structField (← buildExprPlan module env base) fieldName)
    | .add lhs rhs oc => do
        .ok (assignExprPlan .add
          (← buildExprPlan module env lhs)
          (← buildExprPlan module env rhs)
          oc
          (inferredArithmeticByteWidth? module env (.add lhs rhs oc)))
    | .sub lhs rhs oc => do
        .ok (assignExprPlan .sub
          (← buildExprPlan module env lhs)
          (← buildExprPlan module env rhs)
          oc
          (inferredArithmeticByteWidth? module env (.sub lhs rhs oc)))
    | .mul lhs rhs oc => do
        .ok (assignExprPlan .mul
          (← buildExprPlan module env lhs)
          (← buildExprPlan module env rhs)
          oc
          (inferredArithmeticByteWidth? module env (.mul lhs rhs oc)))
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
    | .ecrecover digest v r s => do
        .ok (.ecrecover
          (← buildExprPlan module env digest)
          (← buildExprPlan module env v)
          (← buildExprPlan module env r)
          (← buildExprPlan module env s))
    | .eip712PermitDigest owner spender value nonce deadline domainSep => do
        .ok (.eip712PermitDigest
          (← buildExprPlan module env owner)
          (← buildExprPlan module env spender)
          (← buildExprPlan module env value)
          (← buildExprPlan module env nonce)
          (← buildExprPlan module env deadline)
          (← buildExprPlan module env domainSep))
    | .crosscallAbiPacked target selector stores argsSize outSize dynLenOffset? dynLen?
        dynTargetOffsets dynTargets => do
        let dynPlan ←
          match dynLen? with
          | none => pure none
          | some len => .ok (some (← buildExprPlan module env len))
        let tgtPlans ← dynTargets.mapM (buildExprPlan module env)
        .ok (.crosscallAbiPacked
          (← buildExprPlan module env target) selector stores argsSize outSize
          dynLenOffset? dynPlan dynTargetOffsets tgtPlans)
    | .nativeValue =>
        .ok .nativeValue
    | .crosscallInvoke target methodId args => do
        .ok (.crosscall .call
          (← buildExprPlan module env
            (ProtocolMaterialize.resolveEvmTargetExpr module.nearCrosscallStrings target))
          (← buildExprPlan module env
            (ProtocolMaterialize.resolveEvmMethodExpr module.nearCrosscallStrings methodId))
          none
          (wrapCrosscallExprWordPlans (← args.mapM (buildExprPlan module env)))
          .u64)
    | .crosscallInvokeTyped target methodId args returnType => do
        .ok (.crosscall .call
          (← buildExprPlan module env
            (ProtocolMaterialize.resolveEvmTargetExpr module.nearCrosscallStrings target))
          (← buildExprPlan module env
            (ProtocolMaterialize.resolveEvmMethodExpr module.nearCrosscallStrings methodId))
          none
          (← buildCrosscallArgWordPlansMany module env "typed crosscall argument" args)
          returnType)
    | .crosscallInvokeValueTyped target methodId callValue args returnType => do
        .ok (.crosscall .callValue
          (← buildExprPlan module env
            (ProtocolMaterialize.resolveEvmTargetExpr module.nearCrosscallStrings target))
          (← buildExprPlan module env
            (ProtocolMaterialize.resolveEvmMethodExpr module.nearCrosscallStrings methodId))
          (some (← buildExprPlan module env callValue))
          (← buildCrosscallArgWordPlansMany module env "value crosscall argument" args)
          returnType)
    | .crosscallInvokeStaticTyped target methodId args returnType => do
        .ok (.crosscall .staticcall
          (← buildExprPlan module env
            (ProtocolMaterialize.resolveEvmTargetExpr module.nearCrosscallStrings target))
          (← buildExprPlan module env
            (ProtocolMaterialize.resolveEvmMethodExpr module.nearCrosscallStrings methodId))
          none
          (← buildCrosscallArgWordPlansMany module env "static crosscall argument" args)
          returnType)
    | .crosscallInvokeDelegateTyped target methodId args returnType => do
        .ok (.crosscall .delegatecall
          (← buildExprPlan module env
            (ProtocolMaterialize.resolveEvmTargetExpr module.nearCrosscallStrings target))
          (← buildExprPlan module env
            (ProtocolMaterialize.resolveEvmMethodExpr module.nearCrosscallStrings methodId))
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
    | .crosscallNamed _ _ _ _ =>
        .error { message := "crosscallNamed (named-callee cross-program call) is a ZK-lane construct (RFC 0015); not lowered on EVM — use crosscallInvoke* for EVM cross-program calls" }
    | .nearPromiseThen _ _ _ _
    | .nearPromiseResultsCount
    | .nearPromiseResultStatus _
    | .nearPromiseResultU64 _
    | .nearCrosscallInvokePool _ _ _ _ =>
        .error { message := "NEAR promise API is not supported on EVM" }
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
    -- Identity-width caller: `hashWord(caller)` → keccak256 of 32-byte padded address.
    | .userIdHash => .ok .userIdHash
    | .contractId => .ok .contractId
    | .checkpointId => .ok .checkpointId
    | .timestamp => .ok .timestamp
    | .epochHeight => .error { message := "EVM context read `epochHeight` is not supported; EVM has no epoch-height opcode" }
    | .chainId => .ok .chainId
    | .gasPrice => .ok .gasPrice
    | .gasLeft => .ok .gasLeft
    | .prepaidGas => .error { message := "EVM context read `prepaidGas` is not supported; prepaid_gas is NEAR-only (use gasLeft for EVM gas)" }
    | .usedGas => .error { message := "EVM context read `usedGas` is not supported; used_gas is NEAR-only (use gasLeft for EVM gas)" }
    | .baseFee => .ok .baseFee
    | .prevRandao => .ok .prevRandao
    | .randomSeed => .error { message := "EVM context read `randomSeed` is not supported; use prevRandao for the EVM prevrandao opcode" }
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
        | some target => do
            let target := {
              target with
                writeSemantics := scalarStorageWriteSemantics module valuePlan
            }
            .ok (.storageScalarWriteTarget target valuePlan)
        | none => .ok (.storageScalarWrite stateId valuePlan)
    | .storageScalarAssignOp stateId op value => do
        if stateId == "$eip1967.implementation" then
          .error {
            message := "compound assignment is not allowed for the EIP-1967 implementation state"
          }
        else
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
    | .storageMapDelete stateId key => do
        let keyPlan ← buildExprPlan module env key
        match mapWriteTargetPlan? module stateId with
        | some target => .ok (.storageMapDeleteTarget target keyPlan)
        | none => .ok (.storageMapDelete stateId keyPlan)
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
    | .checkErc721Received operator fromAddr toAddr tokenId => do
        .ok (.checkErc721Received
          (← buildExprPlan module env operator)
          (← buildExprPlan module env fromAddr)
          (← buildExprPlan module env toAddr)
          (← buildExprPlan module env tokenId))
    | .checkErc1155Received operator fromAddr toAddr id amount => do
        .ok (.checkErc1155Received
          (← buildExprPlan module env operator)
          (← buildExprPlan module env fromAddr)
          (← buildExprPlan module env toAddr)
          (← buildExprPlan module env id)
          (← buildExprPlan module env amount))

    | .checkErc1155BatchReceived operator fromAddr toAddr ids amounts => do
        .ok (.checkErc1155BatchReceived
          (← buildExprPlan module env operator)
          (← buildExprPlan module env fromAddr)
          (← buildExprPlan module env toAddr)
          (← buildExprPlan module env ids)
          (← buildExprPlan module env amounts))

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

end ProofForge.Backend.Evm.Lower
