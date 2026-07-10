/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Aleo/Leo IR Validation

Type inference and semantic validation for the Aleo/Leo portable IR lowering
path. This is the `aleo-leo` counterpart of `ProofForge.Backend.Psy.IR.Validate`:
it runs before the lowering (`ProofForge.Backend.Aleo.IR`) so that the builder
can fold validated shapes into the Leo AST without re-checking.

Leo-specific rules encoded here:

- Storage is `scalar` (rewritten to a single-slot Leo `mapping`) or `map`.
  `array` / `dynamicArray` storage is rejected (Leo has no fixed-array storage).
  Unlike Psy, **empty state is allowed** — PureMath-style stateless pure functions
  are a first-class Aleo use case.
- Loop indices of `boundedFor` are typed `U64` (matching the Leo `for i: u64 in …`
  emission and the wrapping-`U64` arithmetic the fixtures use), not `U32`.
- `contextRead` and `eventEmit` are rejected: Leo's on-chain context / event
  model differs from the portable vocabulary and is Road 2 work.
-/

import ProofForge.Backend.Aleo.IR.Common
import ProofForge.Target.Registry

namespace ProofForge.Backend.Aleo.IR

open ProofForge.IR
open ProofForge.Target

/-! ### Value-type validation -/

/-- Validate that a `ValueType` is Leo-spellable as a stored/structured type. -/
partial def validateValueType (module : Module) (type : ValueType) : Except LowerError Unit := do
  match type with
  | .unit => .error { message := "Leo IR v0 does not support Unit as a stored or structured value type" }
  | .bool | .u8 | .u32 | .u64 | .u128 | .address | .hash => pure ()  -- RFC 0015: Hash ≡ field
  | .bytes | .string =>
      .error { message := s!"Leo IR v0 does not support `{type.name}` as a stored or structured value type" }
  | .array _ =>
      .error { message := "Leo IR v0 does not support dynamic arrays as a stored or structured value type" }
  | .fixedArray element length =>
      if length == 0 then
        .error { message := "Leo IR v0 fixed arrays must have non-zero length" }
      validateValueType module element
  | .structType name =>
      match findStruct? module name with
      | some _ => pure ()
      | none => .error { message := s!"unknown struct type `{name}`" }

/-- Validate that a `ValueType` is Leo-spellable as an entrypoint ABI type. -/
partial def validateAbiValueType (module : Module) (type : ValueType) (context : String) (allowUnit : Bool) : Except LowerError Unit := do
  match type with
  | .unit =>
      if allowUnit then pure ()
      else
        .error { message := s!"{context} uses Unit; Leo IR v0 entrypoint parameters must use U8/U32/U64/U128/Bool/Address/Hash, fixed arrays, or declared structs" }
  | .bool | .u8 | .u32 | .u64 | .u128 | .address | .hash => pure ()  -- RFC 0015: Hash ≡ field
  | .bytes | .string =>
      .error { message := s!"{context} uses `{type.name}`; Leo IR v0 entrypoint parameters must use U8/U32/U64/U128/Bool/Address/Hash, fixed arrays, or declared structs" }
  | .array _ =>
      .error { message := s!"{context} uses dynamic array; Leo IR v0 entrypoint parameters must use U8/U32/U64/U128/Bool/Address, fixed arrays, or declared structs" }
  | .fixedArray element length =>
      if length == 0 then
        .error { message := s!"{context} uses a zero-length fixed array; Leo IR v0 fixed arrays must have non-zero length" }
      validateAbiValueType module element context false
  | .structType name =>
      match findStruct? module name with
      | some _ => pure ()
      | none => .error { message := s!"{context} references unknown struct type `{name}`" }

/-! ### Local binding environment -/

structure LocalBinding where
  name : String
  type : ValueType
  isMutable : Bool := false
  deriving Repr

abbrev TypeEnv := Array LocalBinding

def findLocal? (env : TypeEnv) (name : String) : Option LocalBinding :=
  env.find? fun binding => binding.name == name

def addLocal (env : TypeEnv) (name : String) (type : ValueType) (isMutable : Bool) : Except LowerError TypeEnv :=
  match findLocal? env name with
  | some _ => .error { message := s!"local `{name}` is already defined" }
  | none => .ok <| env.push { name, type, isMutable }

/-! ### Storage-path resolution (scalar struct fields + map keys) -/

partial def resolvePathSegments (module : Module) : ValueType → List StoragePathSegment → Except LowerError ValueType
  | type, [] => .ok type
  | type, .field fieldName :: rest => do
      match type with
      | .structType typeName =>
          match findStruct? module typeName with
          | some decl =>
              match findStructField? decl fieldName with
              | some field => resolvePathSegments module field.type rest
              | none => .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
          | none => .error { message := s!"unknown struct `{typeName}` in storage path" }
      | other => .error { message := s!"storage path field `{fieldName}` requires struct, got `{other.name}`" }
  | type, .index _ :: rest => do
      match type with
      | .fixedArray element _ => resolvePathSegments module element rest
      | other => .error { message := s!"storage path index requires fixed array, got `{other.name}`" }
  | type, .mapKey _ :: rest => do
      match type with
      | .structType _ => resolvePathSegments module type rest
      | other => .error { message := s!"storage path map key requires struct/map value, got `{other.name}`" }

def resolveStoragePathType (module : Module) (stateId : String) (path : Array StoragePathSegment) : Except LowerError ValueType := do
  if path.isEmpty then .error { message := s!"storage path for state `{stateId}` must contain at least one segment" }
  match findState? module stateId with
  | some { kind := .scalar, type := t, .. } =>
      if path.toList matches .mapKey _ :: _ then
        .error { message := s!"storage path state `{stateId}` is scalar storage, not map storage" }
      else
        resolvePathSegments module t path.toList
  | some { kind := .map _ _, type := t, .. } =>
      match path.toList with
      | .mapKey _ :: rest => resolvePathSegments module t rest
      | _ => .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
  | some { kind := .array _, .. } =>
      .error { message := s!"storage path state `{stateId}` is array storage, which Leo IR v0 does not support" }
  | some { kind := .dynamicArray, .. } =>
      .error { message := s!"storage path state `{stateId}` is dynamic array storage, which Leo IR v0 does not support" }
  | none => .error { message := s!"unknown storage path state `{stateId}`" }

/-! ### Storage state type accessors -/

/-- Scalar state value type (used by both inference and validation). -/
def scalarStateType (module : Module) (stateId : String) : Except LowerError ValueType := do
  let some state := findState? module stateId
    | .error { message := s!"unknown scalar state `{stateId}`" }
  match state.kind with
  | .scalar => .ok state.type
  | .map _ _ => .error { message := s!"state `{stateId}` is a map, not scalar storage" }
  | .array _ => .error { message := s!"state `{stateId}` is an array, not scalar storage" }
  | .dynamicArray => .error { message := s!"state `{stateId}` is a dynamic array, not scalar storage" }

/-- Map state `(keyType, valueType)`. -/
def mapStateTypes (module : Module) (stateId : String) : Except LowerError (ValueType × ValueType) := do
  let some state := findState? module stateId
    | .error { message := s!"unknown map state `{stateId}`" }
  match state.kind with
  | .map keyType _ => .ok (keyType, state.type)
  | .scalar => .error { message := s!"state `{stateId}` is scalar storage, not a map" }
  | .array _ => .error { message := s!"state `{stateId}` is array storage, not a map" }
  | .dynamicArray => .error { message := s!"state `{stateId}` is dynamic array storage, not a map" }

/-! ### Type inference -/

mutual
  partial def inferExprType (module : Module) (env : TypeEnv) : Expr → Except LowerError ValueType
    | .literal (.u8 _) => .ok .u8
    | .literal (.u32 _) => .ok .u32
    | .literal (.u64 _) => .ok .u64
    | .literal (.u128 _) => .ok .u128
    | .literal (.bool _) => .ok .bool
    | .literal (.address _) => .ok .address
    | .literal (.hash4 ..) =>
        .error { message := "Leo IR v0 does not support Hash literals" }
    | .local name =>
        match findLocal? env name with
        | some binding => .ok binding.type
        | none => .error { message := s!"unknown local `{name}`" }
    | .arrayLit elementType values => do
        if values.isEmpty then
          .error { message := s!"empty fixed array literals are not supported by Leo IR v0 for `{elementType.name}`" }
        validateValueType module elementType
        for value in values do
          let actual ← inferExprType module env value
          ensureType "array literal element" elementType actual
        .ok (.fixedArray elementType values.size)
    | .arrayGet array index => do
        let indexType ← inferExprType module env index
        discard <| ensureNumericType "array index" indexType
        match ← inferExprType module env array with
        | .fixedArray element length =>
            if length == 0 then
              .error { message := "array index requires a non-empty fixed array" }
            else
              .ok element
        | other =>
            .error { message := s!"array index requires fixed array, got `{other.name}`" }
    | .memoryArrayNew _ _ | .memoryArrayLength _ | .memoryArrayGet _ _ =>
        .error { message := "memory arrays are not supported by Leo IR v0" }
    | .structLit typeName fields => do
        if fields.isEmpty then
          .error { message := s!"struct literal `{typeName}` must have at least one field" }
        let some decl := findStruct? module typeName
          | .error { message := s!"struct literal references unknown struct `{typeName}`" }
        if decl.fields.size != fields.size then
          .error { message := s!"struct literal `{typeName}` expected {decl.fields.size} field(s), got {fields.size}" }
        for field in fields do
          let expected ← structFieldType module typeName field.fst
          let actual ← inferExprType module env field.snd
          ensureType s!"struct literal `{typeName}` field `{field.fst}`" expected actual
        for expectedField in decl.fields do
          if !(fields.any fun field => field.fst == expectedField.id) then
            .error { message := s!"struct literal `{typeName}` is missing field `{expectedField.id}`" }
        .ok (.structType typeName)
    | .field base fieldName => do
        match ← inferExprType module env base with
        | .structType typeName => structFieldType module typeName fieldName
        | other => .error { message := s!"field `{fieldName}` requires struct value, got `{other.name}`" }
    | .add lhs rhs _ | .sub lhs rhs _ | .mul lhs rhs _ => do
        ensureSameNumericType "arithmetic" (← inferExprType module env lhs) (← inferExprType module env rhs)
    | .div lhs rhs | .mod lhs rhs | .pow lhs rhs => do
        ensureSameNumericType "arithmetic" (← inferExprType module env lhs) (← inferExprType module env rhs)
    | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs => do
        ensureSameNumericType "bitwise" (← inferExprType module env lhs) (← inferExprType module env rhs)
    | .cast value targetType => do
        let sourceType ← inferExprType module env value
        ensureCastType sourceType targetType
        .ok targetType
    | .eq lhs rhs | .ne lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureType "equality right operand" lhsType rhsType
        ensureEqType "equality expression" lhsType
        .ok .bool
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs => do
        discard <| ensureSameNumericType "comparison" (← inferExprType module env lhs) (← inferExprType module env rhs)
        .ok .bool
    | .boolAnd lhs rhs | .boolOr lhs rhs => do
        ensureType "boolean left operand" .bool (← inferExprType module env lhs)
        ensureType "boolean right operand" .bool (← inferExprType module env rhs)
        .ok .bool
    | .boolNot value => do
        ensureType "boolean not" .bool (← inferExprType module env value)
        .ok .bool
    | .hashValue a b c d => do
        discard <| inferExprType module env a
        discard <| inferExprType module env b
        discard <| inferExprType module env c
        discard <| inferExprType module env d
        .ok .hash
    | .hash preimage => do
        discard <| inferExprType module env preimage
        .ok .hash
    | .hashTwoToOne l r => do
        discard <| inferExprType module env l
        discard <| inferExprType module env r
        .ok .hash
    | .ecrecover _ _ _ _ | .eip712PermitDigest _ _ _ _ _ _ =>
        .error { message := "ecrecover / EIP-712 is EVM-specific and not supported by Leo IR v0" }
    | .crosscallAbiPacked .. =>
        .error { message := "ABI-packed crosscall (Call[]) is EVM-specific and not supported by Leo IR v0" }
    | .crosscallInvoke _ _ _
    | .crosscallInvokeTyped _ _ _ _
    | .crosscallInvokeValueTyped _ _ _ _ _
    | .crosscallInvokeStaticTyped _ _ _ _
    | .crosscallInvokeDelegateTyped _ _ _ _ =>
        .error { message := "typed crosscall is not supported by Leo IR v0; zk-circuit cross calls are Road 2" }
    | .crosscallCreate _ _ | .crosscallCreate2 _ _ _ =>
        .error { message := "contract creation is not supported by Leo IR v0" }
    | .crosscallNamed _ _ args returnType => do
        -- RFC 0015 D4: named-callee cross-program call (lowered to a static
        -- qualified call `programId::method(args)` + an import).
        for arg in args do discard <| inferExprType module env arg
        validateValueType module returnType
        .ok returnType
    | .nativeValue =>
        .error { message := "native value inspection is not supported by Leo IR v0" }
    | .nearPromiseThen _ _ _ _
    | .nearCrosscallInvokePool _ _ _ _
    | .nearPromiseResultsCount
    | .nearPromiseResultStatus _
    | .nearPromiseResultU64 _ =>
        .error { message := "NEAR promise API is not supported by Leo IR v0" }
    | .effect effect => inferEffectExprType module env effect

  partial def inferEffectExprType (module : Module) (env : TypeEnv) : Effect → Except LowerError ValueType
    | .storageScalarRead stateId => scalarStateType module stateId
    | .storageScalarWrite _ _ =>
        .error { message := "storage.scalar.write is a statement effect, not an expression" }
    | .storageScalarAssignOp _ _ _ =>
        .error { message := "storage.scalar.assign_op is a statement effect, not an expression" }
    | .storageMapContains stateId key => do
      discard <| mapStateTypes module stateId
      discard <| inferExprType module env key
      .ok .bool
    | .storageMapGet stateId key => do
      let (_, valueType) ← mapStateTypes module stateId
      discard <| inferExprType module env key
      .ok valueType
    | .storageMapInsert _ _ _ | .storageMapSet _ _ _ =>
        .error { message := "storage.map.insert/set are statement effects, not expressions" }
    | .storageArrayRead _ _ | .storageArrayWrite _ _ _ =>
        .error { message := "Leo IR v0 does not support array storage" }
    | .storageArrayStructFieldRead _ _ _ | .storageArrayStructFieldWrite _ _ _ _ =>
        .error { message := "Leo IR v0 does not support array storage" }
    | .storageDynamicArrayPush _ _ | .storageDynamicArrayPop _ =>
        .error { message := "Leo IR v0 does not support dynamic array storage" }
    | .memoryArraySet _ _ _ =>
        .error { message := "memory arrays are not supported by Leo IR v0" }
    | .storageStructFieldRead stateId fieldName => do
      let stateType ← scalarStateType module stateId
      match stateType with
      | .structType typeName => structFieldType module typeName fieldName
      | other => .error { message := s!"state `{stateId}` has scalar type `{other.name}`, not struct storage" }
    | .storageStructFieldWrite _ _ _ =>
        .error { message := "storage.struct.field.write is a statement effect, not an expression" }
    | .storagePathRead stateId path => resolveStoragePathType module stateId path
    | .storagePathWrite _ _ _ | .storagePathAssignOp _ _ _ _ =>
        .error { message := "storage.path.write/assign_op are statement effects, not expressions" }
    | .contextRead field => do
        let (t, _) ← mapContextField field
        .ok t
    | .eventEmit _ _ | .eventEmitIndexed _ _ _ =>
        .error { message := "event.emit is a statement effect, not an expression" }
    | .checkErc721Received _ _ _ _ =>
        .error { message := "checkErc721Received is EVM-only (PF-P2-02); not an expression on Leo" }
    | .checkErc1155Received _ _ _ _ _ =>
        .error { message := "checkErc1155Received is EVM-only (PF-P2-02); not an expression on Leo" }
    | .checkErc1155BatchReceived _ _ _ _ _ _ _ =>
        .error { message := "checkErc1155BatchReceived is EVM-only (PF-P2-02); not an expression on host" }

  partial def inferAssignTargetType (module : Module) (env : TypeEnv) : Expr → Except LowerError ValueType
    | .local name =>
        match findLocal? env name with
        | some binding => .ok binding.type
        | none =>
            -- A local that is not in `env` but is a declared scalar state reads as
            -- its scalar value type (storage-backed assignment targets are lowered
            -- separately; this branch only fires for plain locals).
            match findState? module name with
            | some { kind := .scalar, type := t, .. } => .ok t
            | _ => .error { message := s!"unknown assignment target `{name}`" }
    | .field base fieldName => do
        let baseType ← inferAssignTargetType module env base
        match baseType with
        | .structType typeName => structFieldType module typeName fieldName
        | other => .error { message := s!"field assignment `{fieldName}` requires struct, got `{other.name}`" }
    | .arrayGet base index => do
        discard <| inferExprType module env index
        let baseType ← inferAssignTargetType module env base
        match baseType with
        | .fixedArray element _ => .ok element
        | other => .error { message := s!"array assignment requires fixed array, got `{other.name}`" }
    | _ =>
        .error { message := "assignment target must be a local, field, or array index" }
end

/-! ### Effect statement validation -/

def validateEffectStmt (module : Module) (env : TypeEnv) : Effect → Except LowerError Unit
  | .storageScalarRead _ =>
      .error { message := "storage.scalar.read must be used as an expression" }
  | .storageScalarWrite stateId value => do
      let expected ← scalarStateType module stateId
      let actual ← inferExprType module env value
      ensureType s!"state `{stateId}` write" expected actual
  | .storageScalarAssignOp stateId op value => do
      let expected ← scalarStateType module stateId
      let actual ← inferExprType module env value
      discard <| ensureSameNumericType s!"compound assignment {assignOpDiagnosticName op}" expected actual
  | .storageMapContains _ _ | .storageMapGet _ _ =>
      .error { message := "storage.map.contains/get must be used as expressions" }
  | .storageMapInsert stateId key value | .storageMapSet stateId key value => do
      let (keyType, valueType) ← mapStateTypes module stateId
      ensureType s!"map state `{stateId}` key" keyType (← inferExprType module env key)
      ensureType s!"map state `{stateId}` value" valueType (← inferExprType module env value)
  | .storageArrayRead _ _ | .storageArrayWrite _ _ _ =>
      .error { message := "Leo IR v0 does not support array storage" }
  | .storageArrayStructFieldRead _ _ _ | .storageArrayStructFieldWrite _ _ _ _ =>
      .error { message := "Leo IR v0 does not support array storage" }
  | .storageDynamicArrayPush _ _ | .storageDynamicArrayPop _ =>
      .error { message := "Leo IR v0 does not support dynamic array storage" }
  | .memoryArraySet _ _ _ =>
      .error { message := "memory arrays are not supported by Leo IR v0" }
  | .storageStructFieldRead _ _ =>
      .error { message := "storage.struct.field.read must be used as an expression" }
  | .storageStructFieldWrite stateId fieldName value => do
      let expected ←
        match ← scalarStateType module stateId with
        | .structType typeName => structFieldType module typeName fieldName
        | other => .error { message := s!"state `{stateId}` has scalar type `{other.name}`, not struct storage" }
      ensureType s!"state `{stateId}` field `{fieldName}` write" expected (← inferExprType module env value)
  | .storagePathRead _ _ =>
      .error { message := "storage.path.read must be used as an expression" }
  | .storagePathWrite stateId path value => do
      let expected ← resolveStoragePathType module stateId path
      ensureType s!"storage path `{stateId}` write" expected (← inferExprType module env value)
  | .storagePathAssignOp stateId path op value => do
      let expected ← resolveStoragePathType module stateId path
      discard <| ensureSameNumericType s!"compound assignment {assignOpDiagnosticName op}" expected (← inferExprType module env value)
  | .contextRead _ =>
      .error { message := "context.read must be used as an expression" }
  | .eventEmit _ _ | .eventEmitIndexed _ _ _ =>
      .error { message := "Leo IR v0 does not lower event emit (Leo events are Road 2)" }
  | .checkErc721Received _ _ _ _ =>
      .error { message := "checkErc721Received is EVM-only (PF-P2-02); not supported by Leo IR v0" }
  | .checkErc1155Received _ _ _ _ _ =>
      .error { message := "checkErc1155Received is EVM-only (PF-P2-02); not supported by Leo IR v0" }
  | .checkErc1155BatchReceived _ _ _ _ _ _ _ =>
      .error { message := "checkErc1155BatchReceived is EVM-only (PF-P2-02); not supported by Leo IR v0" }

/-! ### Statement validation -/

mutual
  partial def validateStatement (module : Module) (entrypoint : Entrypoint) (env : TypeEnv) : Statement → Except LowerError TypeEnv
    | .letBind name type value => do
        validateValueType module type
        let actual ← inferExprType module env value
        ensureType s!"let binding `{name}`" type actual
        addLocal env name type false
    | .letMutBind name type value => do
        validateValueType module type
        let actual ← inferExprType module env value
        ensureType s!"mutable let binding `{name}`" type actual
        addLocal env name type true
    | .assign target value => do
        let expected ← inferAssignTargetType module env target
        let actual ← inferExprType module env value
        ensureType "assignment value" expected actual
        .ok env
    | .assignOp target op value => do
        let expected ← inferAssignTargetType module env target
        let actual ← inferExprType module env value
        discard <| ensureSameNumericType s!"compound assignment {assignOpDiagnosticName op}" expected actual
        .ok env
    | .effect effect => do
        validateEffectStmt module env effect
        .ok env
    | .assert condition _ _ => do
        ensureType "assert condition" .bool (← inferExprType module env condition)
        .ok env
    | .assertEq lhs rhs _ _ => do
        ensureType "assert_eq right operand" (← inferExprType module env lhs) (← inferExprType module env rhs)
        .ok env
    | .release _ =>
        .error { message := "release statements are not supported by Leo IR v0" }
    | .revert _ | .revertWithError _ => .ok env
    | .ifElse condition thenBody elseBody => do
        ensureType "if condition" .bool (← inferExprType module env condition)
        discard <| validateBody module entrypoint env thenBody
        discard <| validateBody module entrypoint env elseBody
        .ok env
    | .boundedFor indexName start stopExclusive body => do
        if stopExclusive <= start then
          .error { message := s!"bounded loop `{indexName}` must have stop greater than start" }
        -- Leo emits `for i: u64 in startu64..stopu64`, so the loop index is U64.
        let loopEnv ← addLocal env indexName .u64 false
        discard <| validateBody module entrypoint loopEnv body
        .ok env
    | .whileLoop _ _ =>
        .error { message := "while loops are not supported by Leo IR v0" }
    | .return value => do
        let actual ← inferExprType module env value
        ensureType s!"entrypoint `{entrypoint.name}` return" entrypoint.returns actual
        .ok env

  partial def validateBody (module : Module) (entrypoint : Entrypoint) (env : TypeEnv) (body : Array Statement) : Except LowerError TypeEnv :=
    body.foldlM (init := env) fun acc stmt =>
      validateStatement module entrypoint acc stmt
end

/-! ### Identifier validation over bodies -/

mutual
  partial def validateStatementIdentifiers (entrypointName : String) : Statement → Except LowerError Unit
    | .letBind name _ _ | .letMutBind name _ _ =>
        validateLeoIdentifier s!"local name in entrypoint `{entrypointName}`" name
    | .ifElse _ thenBody elseBody => do
        validateBodyIdentifiers entrypointName thenBody
        validateBodyIdentifiers entrypointName elseBody
    | .boundedFor indexName _ _ body => do
        validateLeoIdentifier s!"loop index in entrypoint `{entrypointName}`" indexName
        validateBodyIdentifiers entrypointName body
    | .whileLoop _ body => validateBodyIdentifiers entrypointName body
    | .assign _ _ | .assignOp _ _ _ | .effect _ | .assert _ _ _ | .assertEq _ _ _ _
    | .release _ | .revert _ | .revertWithError _ | .return _ =>
        pure ()

  partial def validateBodyIdentifiers (entrypointName : String) (body : Array Statement) : Except LowerError Unit := do
    for stmt in body do
      validateStatementIdentifiers entrypointName stmt
end

/-! ### Top-level validation passes -/

def validateIdentifiers (module : Module) : Except LowerError Unit := do
  validateLeoIdentifier "module name" module.name
  validateDistinctNames "struct name" (module.structs.map fun decl => decl.name)
  validateDistinctNames "state id" (module.state.map fun state => state.id)
  validateDistinctNames "entrypoint name" (module.entrypoints.map fun entrypoint => entrypoint.name)
  for decl in module.structs do
    validateLeoIdentifier "struct name" decl.name
    validateDistinctNames s!"struct `{decl.name}` field id" (decl.fields.map fun field => field.id)
    for field in decl.fields do
      validateLeoIdentifier s!"field id in struct `{decl.name}`" field.id
  for state in module.state do
    validateLeoIdentifier "state id" state.id
  for entrypoint in module.entrypoints do
    validateLeoIdentifier "entrypoint name" entrypoint.name
    validateDistinctNames s!"entrypoint `{entrypoint.name}` parameter name" (entrypoint.params.map fun param => param.fst)
    for param in entrypoint.params do
      validateLeoIdentifier s!"parameter name in entrypoint `{entrypoint.name}`" param.fst
    validateBodyIdentifiers entrypoint.name entrypoint.body
    for ref in (analyzeBody entrypoint.body).namedCrosscalls do
      validateLeoProgramId s!"crosscall in entrypoint `{entrypoint.name}`" ref.programId
      validateLeoIdentifier s!"crosscall method in entrypoint `{entrypoint.name}`" ref.method

def validateStructs (module : Module) : Except LowerError Unit := do
  for decl in module.structs do
    if decl.fields.isEmpty then
      .error { message := s!"struct `{decl.name}` must declare at least one field" }
    for field in decl.fields do
      validateValueType module field.type
    if decl.semantics == .value && decl.fields.any (fun field => field.id == "owner") then
      .error {
        message := s!"value struct `{decl.name}` cannot declare field `owner`: Leo 4.0.2 reserves `owner` for record ownership"
      }
    else if decl.semantics == .linearRecord then
      let owners := decl.fields.filter fun field => field.id == "owner"
      match owners.toList with
      | [owner] =>
          if owner.type != .address then
            .error { message := s!"record `{decl.name}` must declare exactly one `owner: address` field" }
      | _ => .error { message := s!"record `{decl.name}` must declare exactly one `owner: address` field" }

def validateEntrypoints (module : Module) : Except LowerError Unit := do
  for entrypoint in module.entrypoints do
    for param in entrypoint.params do
      validateAbiValueType module param.snd s!"entrypoint `{entrypoint.name}` parameter `{param.fst}`" false
    validateAbiValueType module entrypoint.returns s!"entrypoint `{entrypoint.name}` return type" true
    discard <| planFunction entrypoint

def initialTypeEnv (entrypoint : Entrypoint) : Except LowerError TypeEnv :=
  entrypoint.params.foldlM (init := #[]) fun env param =>
    addLocal env param.fst param.snd false

partial def bodyEndsWithReturn (body : Array Statement) : Bool :=
  match body.toList.reverse with
  | Statement.return _ :: _ => true
  | Statement.ifElse _ thenBody elseBody :: _ => bodyEndsWithReturn thenBody && bodyEndsWithReturn elseBody
  | _ => false

def validateEntrypointBodies (module : Module) : Except LowerError Unit := do
  for entrypoint in module.entrypoints do
    let env ← initialTypeEnv entrypoint
    discard <| validateBody module entrypoint env entrypoint.body
    if entrypoint.returns != .unit && !bodyEndsWithReturn entrypoint.body then
      .error { message := s!"entrypoint `{entrypoint.name}` returns `{entrypoint.returns.name}` but does not end with a return statement" }

/-- Validate Aleo/Leo state shapes.

Unlike Psy, **empty state is allowed** (PureMath-style stateless functions).
Scalar states rewrite to a single-slot Leo `mapping`; map states lower to a Leo
`mapping`. Array / dynamic-array storage is rejected. -/
partial def containsLinearRecord (module : Module) (type : ValueType)
    (visiting : Array String := #[]) : Bool :=
  match type with
  | .fixedArray element _ | .array element => containsLinearRecord module element visiting
  | .structType name =>
      if visiting.contains name then false
      else
        match findStruct? module name with
        | none => false
        | some decl =>
            decl.semantics == .linearRecord ||
              decl.fields.any fun field => containsLinearRecord module field.type (visiting.push name)
  | _ => false

def validateState (module : Module) : Except LowerError Unit := do
  for state in module.state do
    match state.kind with
    | .map keyType _ =>
        if containsLinearRecord module keyType then
          .error { message := s!"state `{state.id}` map key transitively contains a linear record" }
    | _ => pure ()
    if containsLinearRecord module state.type then
      .error { message := s!"state `{state.id}` value transitively contains a linear record" }
    match state.kind, state.type with
    | .scalar, .bool | .scalar, .u8 | .scalar, .u32 | .scalar, .u64
    | .scalar, .u128 | .scalar, .address | .scalar, .hash =>
        pure ()
    | .scalar, .structType typeName =>
        match findStruct? module typeName with
        | some _ => pure ()
        | none => .error { message := s!"state `{state.id}` references unknown struct `{typeName}`" }
    | .scalar, other =>
        .error { message := s!"state `{state.id}` has unsupported Leo scalar type `{other.name}`" }
    | .map keyType _, valueType => do
        validateValueType module keyType
        validateValueType module valueType
    | .array _, _ =>
        .error { message := s!"state `{state.id}` is array storage; Leo IR v0 does not lower fixed-array storage" }
    | .dynamicArray, _ =>
        .error { message := s!"state `{state.id}` is dynamic array storage; Leo IR v0 does not lower dynamic-array storage" }

/-- Validate that every capability the module requires is present in the
`aleo-leo` target profile. -/
def validateCapabilities (module : Module) : Except LowerError Unit :=
  match resolveModule Target.aleoLeo module with
  | .ok _ => .ok ()
  | .error err => .error (diagnosticError err)

/-- Run every validation pass in order. -/
def validateModule (module : Module) : Except LowerError Unit := do
  validateCapabilities module
  validateIdentifiers module
  validateStructs module
  validateState module
  validateEntrypoints module
  validateEntrypointBodies module

end ProofForge.Backend.Aleo.IR
