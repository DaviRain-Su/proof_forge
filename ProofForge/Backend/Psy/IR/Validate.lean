/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Psy IR Validation

Type inference and semantic validation for the Psy portable IR lowering path.
-/

import ProofForge.Backend.Psy.IR.Common

namespace ProofForge.Backend.Psy.IR

open ProofForge.IR
open ProofForge.Target

mutual
  partial def inferExprType (module : Module) (env : TypeEnv) : Expr → Except LowerError ValueType
    | .literal (.u32 _) => .ok .u32
    | .literal (.u64 _) => .ok .u64
    | .literal (.u128 _) => .error { message := "Psy IR v0 does not support U128 literals" }
    | .literal (.bool _) => .ok .bool
    | .literal (.hash4 ..) => .ok .hash
    | .literal (.u8 _) => .ok .u8
    | .literal (.address _) => .ok .address
    | .local name =>
        match findLocal? env name with
        | some binding => .ok binding.type
        | none => .error { message := s!"unknown local `{name}`" }
    | .arrayLit elementType values => do
        if values.isEmpty then
          .error { message := s!"empty fixed array literals are not supported by Psy IR v0 for `{← valueTypeName elementType}`" }
        validateValueType module elementType
        for value in values do
          let actual ← inferExprType module env value
          ensureType "array literal element" elementType actual
        .ok (.fixedArray elementType values.size)
    | .arrayGet array index => do
        let indexType ← inferExprType module env index
        ensureIndexType "array index" indexType
        match ← inferExprType module env array with
        | .fixedArray element length =>
            if length == 0 then
              .error { message := "array index requires a non-empty fixed array" }
            else
              .ok element
        | other =>
            .error { message := s!"array index requires fixed array, got `{other.name}`" }
    | .memoryArrayNew _ _ =>
        .error { message := "memory arrays are not supported by Psy IR v0" }
    | .memoryArrayLength _ =>
        .error { message := "memory arrays are not supported by Psy IR v0" }
    | .memoryArrayGet _ _ =>
        .error { message := "memory arrays are not supported by Psy IR v0" }
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
        | .structType typeName =>
            structFieldType module typeName fieldName
        | other =>
            .error { message := s!"field `{fieldName}` requires struct value, got `{other.name}`" }
    | .add lhs rhs _ => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "addition" lhsType rhsType
    | .sub lhs rhs _ => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "subtraction" lhsType rhsType
    | .mul lhs rhs _ => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "multiplication" lhsType rhsType
    | .div lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "division" lhsType rhsType
    | .mod lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "modulo" lhsType rhsType
    | .pow lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "exponentiation" lhsType rhsType
    | .bitAnd lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "bitwise and" lhsType rhsType
    | .bitOr lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "bitwise or" lhsType rhsType
    | .bitXor lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "bitwise xor" lhsType rhsType
    | .shiftLeft lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "shift-left" lhsType rhsType
    | .shiftRight lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "shift-right" lhsType rhsType
    | .cast value targetType => do
        let sourceType ← inferExprType module env value
        ensureCastType sourceType targetType
        .ok targetType
    | .eq lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureType "equality right operand" lhsType rhsType
        ensureEqType "equality expression" lhsType
        .ok .bool
    | .ne lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureType "inequality right operand" lhsType rhsType
        ensureEqType "inequality expression" lhsType
        .ok .bool
    | .lt lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        discard <| ensureSameNumericType "less-than" lhsType rhsType
        .ok .bool
    | .le lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        discard <| ensureSameNumericType "less-or-equal" lhsType rhsType
        .ok .bool
    | .gt lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        discard <| ensureSameNumericType "greater-than" lhsType rhsType
        .ok .bool
    | .ge lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        discard <| ensureSameNumericType "greater-or-equal" lhsType rhsType
        .ok .bool
    | .boolAnd lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureType "boolean and left operand" .bool lhsType
        ensureType "boolean and right operand" .bool rhsType
        .ok .bool
    | .boolOr lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureType "boolean or left operand" .bool lhsType
        ensureType "boolean or right operand" .bool rhsType
        .ok .bool
    | .boolNot value => do
        let valueType ← inferExprType module env value
        ensureType "boolean not operand" .bool valueType
        .ok .bool
    | .hashValue a b c d => do
        ensureHashValuePart "0" (← inferExprType module env a)
        ensureHashValuePart "1" (← inferExprType module env b)
        ensureHashValuePart "2" (← inferExprType module env c)
        ensureHashValuePart "3" (← inferExprType module env d)
        .ok .hash
    | .hash preimage => do
        let preimageType ← inferExprType module env preimage
        ensureType "hash preimage" .hash preimageType
        .ok .hash
    | .hashTwoToOne lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureType "hash_two_to_one left operand" .hash lhsType
        ensureType "hash_two_to_one right operand" .hash rhsType
        .ok .hash
    | .ecrecover _ _ _ _ | .eip712PermitDigest _ _ _ _ _ _ =>
        .error { message := "ecrecover / EIP-712 permit require crypto.ecrecover (EVM-only); not supported by Psy IR v0" }
    | .crosscallAbiPacked _ _ _ _ _ _ _ _ _ =>
        .error { message := "crosscallAbiPacked (compile-time ABI Call[]) is EVM-only; not supported by Psy IR v0" }
    | .nativeValue =>
        .error { message := "native value inspection is not supported by Psy IR v0" }
    | .crosscallInvoke target methodId args => do
        let targetType ← inferExprType module env target
        ensureType "crosscall target contract id" .u64 targetType
        let methodIdType ← inferExprType module env methodId
        ensureType "crosscall method id" .u64 methodIdType
        let argTypes ← args.mapM (inferExprType module env)
        for argType in argTypes do
          ensureType "crosscall argument" .u64 argType
        .ok .u64
    | .crosscallInvokeTyped _ _ _ returnType =>
        .error { message := s!"typed crosscall return `{returnType.name}` is not supported by Psy IR v0; use untyped U64 crosscallInvoke for Psy targets" }
    | .crosscallInvokeValueTyped _ _ _ _ returnType =>
        .error { message := s!"value-bearing typed crosscall return `{returnType.name}` is not supported by Psy IR v0; use untyped U64 crosscallInvoke for Psy targets" }
    | .crosscallInvokeStaticTyped _ _ _ returnType =>
        .error { message := s!"static typed crosscall return `{returnType.name}` is not supported by Psy IR v0; use untyped U64 crosscallInvoke for Psy targets" }
    | .crosscallInvokeDelegateTyped _ _ _ returnType =>
        .error { message := s!"delegate typed crosscall return `{returnType.name}` is not supported by Psy IR v0; use untyped U64 crosscallInvoke for Psy targets" }
    | .crosscallCreate _ _ =>
        .error { message := "EVM contract creation is not supported by Psy IR v0" }
    | .crosscallCreate2 _ _ _ =>
        .error { message := "EVM deterministic contract creation is not supported by Psy IR v0" }
    | .crosscallNamed _ _ _ _ =>
        .error { message := "named-callee cross-program calls (crosscallNamed) are not supported by Psy IR v0; Psy uses runtime-address crosscallInvoke" }
    | .nearPromiseThen _ _ _ _
    | .nearCrosscallInvokePool _ _ _ _
    | .nearPromiseResultsCount
    | .nearPromiseResultStatus _
    | .nearPromiseResultU64 _ =>
        .error { message := "NEAR promise API is not supported by Psy IR v0" }
    | .effect effect =>
        inferEffectExprType module env effect

  partial def validateStoragePathExprs (module : Module) (env : TypeEnv) (stateId : String) (path : Array StoragePathSegment) : Except LowerError Unit := do
    if path.isEmpty then
      pure ()
    match findState? module stateId with
    | some state =>
        match state.kind with
        | .map keyType _ =>
            match path.toList with
            | .mapKey key :: rest => do
                let actualKey ← inferExprType module env key
                ensureType s!"map `{stateId}` key" keyType actualKey
                for segment in rest do
                  match segment with
                  | .field _ => pure ()
                  | .index index => do
                      let actualIndex ← inferExprType module env index
                      ensureIndexType s!"storage path `{stateId}` index" actualIndex
                  | .mapKey _ =>
                      .error { message := s!"storage path `{stateId}` can use a map key only as its first segment" }
            | _ => pure ()
        | .scalar | .array _ | .dynamicArray =>
            for segment in path do
              match segment with
              | .field _ => pure ()
              | .index index => do
                  let actualIndex ← inferExprType module env index
                  ensureIndexType s!"storage path `{stateId}` index" actualIndex
              | .mapKey _ =>
                  pure ()
    | none => pure ()

  partial def inferEffectExprType (module : Module) (env : TypeEnv) : Effect → Except LowerError ValueType
    | .storageScalarRead stateId =>
        scalarStateType module stateId
    | .storageScalarWrite _ _ =>
        .error { message := "storage.scalar.write is a statement effect, not an expression" }
    | .storageScalarAssignOp _ _ _ =>
        .error { message := "storage.scalar.assign_op is a statement effect, not an expression" }
    | .storageMapContains stateId key => do
        let (keyType, _) ← mapStateTypes module stateId
        let actualKey ← inferExprType module env key
        ensureType s!"map `{stateId}` key" keyType actualKey
        .ok .bool
    | .storageMapGet stateId key => do
        let (keyType, valueType) ← mapStateTypes module stateId
        let actualKey ← inferExprType module env key
        ensureType s!"map `{stateId}` key" keyType actualKey
        .ok valueType
    | .storageMapInsert stateId key value => do
        let (keyType, valueType) ← mapStateTypes module stateId
        let actualKey ← inferExprType module env key
        ensureType s!"map `{stateId}` key" keyType actualKey
        let actualValue ← inferExprType module env value
        ensureType s!"map `{stateId}` value" valueType actualValue
        .ok valueType
    | .storageMapSet stateId key value => do
        let (keyType, valueType) ← mapStateTypes module stateId
        let actualKey ← inferExprType module env key
        ensureType s!"map `{stateId}` key" keyType actualKey
        let actualValue ← inferExprType module env value
        ensureType s!"map `{stateId}` value" valueType actualValue
        .ok valueType
    | .storageArrayRead stateId index => do
        let elementType ← arrayStateElementType module stateId
        let actualIndex ← inferExprType module env index
        ensureIndexType s!"array state `{stateId}` index" actualIndex
        .ok elementType
    | .storageArrayWrite _ _ _ =>
        .error { message := "storage.array.write is a statement effect, not an expression" }
    | .storageArrayStructFieldRead stateId index fieldName => do
        let elementType ← arrayStateElementType module stateId
        let actualIndex ← inferExprType module env index
        ensureIndexType s!"array state `{stateId}` index" actualIndex
        match elementType with
        | .structType typeName => structFieldType module typeName fieldName
        | other => .error { message := s!"array state `{stateId}` has element type `{other.name}`, not struct storage" }
    | .storageArrayStructFieldWrite _ _ _ _ =>
        .error { message := "storage.array.struct.field.write is a statement effect, not an expression" }
    | .storageDynamicArrayPush _ _ =>
        .error { message := "storage.dynamic.array.push is a statement effect, not an expression" }
    | .storageDynamicArrayPop _ =>
        .error { message := "storage.dynamic.array.pop is a statement effect, not an expression" }
    | .memoryArraySet _ _ _ =>
        .error { message := "memory.array.set is a statement effect, not an expression" }
    | .storageStructFieldRead stateId fieldName => do
        match ← scalarStateType module stateId with
        | .structType typeName => structFieldType module typeName fieldName
        | other => .error { message := s!"state `{stateId}` has scalar type `{other.name}`, not struct storage" }
    | .storageStructFieldWrite _ _ _ =>
        .error { message := "storage.struct.field.write is a statement effect, not an expression" }
    | .storagePathRead stateId path => do
        validateStoragePathExprs module env stateId path
        resolveStoragePathType module stateId path
    | .storagePathWrite _ _ _ =>
        .error { message := "storage.path.write is a statement effect, not an expression" }
    | .storagePathAssignOp _ _ _ _ =>
        .error { message := "storage.path.assign_op is a statement effect, not an expression" }
    | .contextRead .origin => .ok .hash
    | .contextRead .randomSeed => .ok .hash
    | .contextRead .coinbase => .ok .hash
    | .contextRead (.blockHash _) => .ok .hash
    | .contextRead _ =>
        .ok .u64
    | .eventEmit _ _ =>
        .error { message := "event.emit is a statement effect, not an expression" }
    | .eventEmitIndexed _ _ _ =>
        .error { message := "event.emit.indexed is a statement effect, not an expression" }
    | .checkErc721Received _ _ _ _ =>
        .error { message := "checkErc721Received is EVM-only (PF-P2-02); not an expression on Psy" }
    | .checkErc1155Received _ _ _ _ _ =>
        .error { message := "checkErc1155Received is EVM-only (PF-P2-02); not an expression on Psy" }
end

partial def inferAssignTargetType (module : Module) (env : TypeEnv) : Expr → Except LowerError ValueType
  | .local name =>
      match findLocal? env name with
      | some binding =>
          if binding.isMutable then
            .ok binding.type
          else
            .error { message := s!"assignment target local `{name}` is not mutable" }
      | none => .error { message := s!"unknown local `{name}`" }
  | .arrayGet array index => do
      let indexType ← inferExprType module env index
      ensureIndexType "assignment array index" indexType
      match ← inferAssignTargetType module env array with
      | .fixedArray element length =>
          if length == 0 then
            .error { message := "assignment array target requires a non-empty fixed array" }
          else
            .ok element
      | other =>
          .error { message := s!"assignment array target requires fixed array, got `{other.name}`" }
  | .memoryArrayNew _ _ =>
      .error { message := "memory arrays are not supported by Psy IR v0" }
  | .memoryArrayLength _ =>
      .error { message := "memory arrays are not supported by Psy IR v0" }
  | .memoryArrayGet _ _ =>
      .error { message := "memory arrays are not supported by Psy IR v0" }
  | .field base fieldName => do
      match ← inferAssignTargetType module env base with
      | .structType typeName =>
          structFieldType module typeName fieldName
      | other =>
          .error { message := s!"assignment field `{fieldName}` requires struct value, got `{other.name}`" }
  | _ =>
      .error { message := "assignment target must be a local, array index, or field path" }

def validateEffectStmt (module : Module) (env : TypeEnv) : Effect → Except LowerError Unit
  | .storageScalarRead _ =>
      .error { message := "storage.scalar.read must be used as an expression" }
  | .storageScalarWrite stateId value => do
      let expected ← scalarStateType module stateId
      let actual ← inferExprType module env value
      ensureType s!"scalar state `{stateId}` write" expected actual
  | .storageScalarAssignOp stateId op value => do
      let expected ← scalarStateType module stateId
      let actual ← inferExprType module env value
      ensureAssignOpTypes op expected actual
  | .storageMapContains _ _ =>
      .error { message := "storage.map.contains must be used as an expression" }
  | .storageMapGet _ _ =>
      .error { message := "storage.map.get must be used as an expression" }
  | .storageMapInsert stateId key value => do
      let (keyType, valueType) ← mapStateTypes module stateId
      let actualKey ← inferExprType module env key
      ensureType s!"map `{stateId}` key" keyType actualKey
      let actualValue ← inferExprType module env value
      ensureType s!"map `{stateId}` value" valueType actualValue
  | .storageMapSet stateId key value => do
      let (keyType, valueType) ← mapStateTypes module stateId
      let actualKey ← inferExprType module env key
      ensureType s!"map `{stateId}` key" keyType actualKey
      let actualValue ← inferExprType module env value
      ensureType s!"map `{stateId}` value" valueType actualValue
  | .storageArrayRead _ _ =>
      .error { message := "storage.array.read must be used as an expression" }
  | .storageArrayWrite stateId index value => do
      let elementType ← arrayStateElementType module stateId
      let actualIndex ← inferExprType module env index
      ensureIndexType s!"array state `{stateId}` index" actualIndex
      let actualValue ← inferExprType module env value
      ensureType s!"array state `{stateId}` write" elementType actualValue
  | .storageArrayStructFieldRead _ _ _ =>
      .error { message := "storage.array.struct.field.read must be used as an expression" }
  | .storageArrayStructFieldWrite stateId index fieldName value => do
      let elementType ← arrayStateElementType module stateId
      let actualIndex ← inferExprType module env index
      ensureIndexType s!"array state `{stateId}` index" actualIndex
      let expected ←
        match elementType with
        | .structType typeName => structFieldType module typeName fieldName
        | other => .error { message := s!"array state `{stateId}` has element type `{other.name}`, not struct storage" }
      let actualValue ← inferExprType module env value
      ensureType s!"array state `{stateId}` field `{fieldName}` write" expected actualValue
  | .storageDynamicArrayPush _ _ =>
      .error { message := "storage.dynamic.array.push is not supported by Psy IR v0" }
  | .storageDynamicArrayPop _ =>
      .error { message := "storage.dynamic.array.pop is not supported by Psy IR v0" }
  | .memoryArraySet _ _ _ =>
      .error { message := "memory arrays are not supported by Psy IR v0" }
  | .storageStructFieldRead _ _ =>
      .error { message := "storage.struct.field.read must be used as an expression" }
  | .storageStructFieldWrite stateId fieldName value => do
      let expected ←
        match ← scalarStateType module stateId with
        | .structType typeName => structFieldType module typeName fieldName
        | other => .error { message := s!"state `{stateId}` has scalar type `{other.name}`, not struct storage" }
      let actualValue ← inferExprType module env value
      ensureType s!"state `{stateId}` field `{fieldName}` write" expected actualValue
  | .storagePathRead _ _ =>
      .error { message := "storage.path.read must be used as an expression" }
  | .storagePathWrite stateId path value => do
      validateStoragePathExprs module env stateId path
      let expected ← resolveStoragePathType module stateId path
      let actualValue ← inferExprType module env value
      ensureType s!"storage path `{stateId}` write" expected actualValue
  | .storagePathAssignOp stateId path op value => do
      validateStoragePathExprs module env stateId path
      let expected ← resolveStoragePathType module stateId path
      let actualValue ← inferExprType module env value
      ensureAssignOpTypes op expected actualValue
  | .contextRead _ =>
      .error { message := "context.read must be used as an expression" }
  | .eventEmit name fields => do
      validatePsyIdentifier "event name" name
      if fields.isEmpty then
        .error { message := s!"event `{name}` must have at least one field" }
      validateDistinctNames s!"event `{name}` field name" (fields.map fun field => field.fst)
      for field in fields do
        validatePsyIdentifier s!"event `{name}` field name" field.fst
        let actual ← inferExprType module env field.snd
        ensureType s!"event `{name}` field `{field.fst}`" .u64 actual
  | .eventEmitIndexed name _ _ =>
      .error { message := s!"event `{name}` uses indexed fields, which are not supported by Psy IR v0" }
  | .checkErc721Received _ _ _ _ =>
      .error { message := "checkErc721Received is EVM-only (PF-P2-02); not supported by Psy IR v0" }
  | .checkErc1155Received _ _ _ _ _ =>
      .error { message := "checkErc1155Received is EVM-only (PF-P2-02); not supported by Psy IR v0" }

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
        ensureAssignOpTypes op expected actual
        .ok env
    | .effect effect => do
        validateEffectStmt module env effect
        .ok env
    | .assert condition _ _ => do
        let conditionType ← inferExprType module env condition
        ensureType "assert condition" .bool conditionType
        .ok env
    | .assertEq lhs rhs _ _ => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureType "assert_eq right operand" lhsType rhsType
        .ok env
    | .release _ =>
        .error { message := "release statements are not supported by Psy IR v0" }
    | .revert _ => .ok env
    | .revertWithError _ => .ok env
    | .ifElse condition thenBody elseBody => do
        let conditionType ← inferExprType module env condition
        ensureType "if condition" .bool conditionType
        discard <| validateBody module entrypoint env thenBody
        discard <| validateBody module entrypoint env elseBody
        .ok env
    | .boundedFor indexName start stopExclusive body => do
        if stopExclusive <= start then
          .error { message := s!"bounded loop `{indexName}` must have stop greater than start" }
        let loopEnv ← addLocal env indexName .u32 false
        discard <| validateBody module entrypoint loopEnv body
        .ok env
    | .whileLoop _ _ =>
        .error { message := "while loops are not supported by Psy IR v0" }
    | .return value => do
        let actual ← inferExprType module env value
        ensureType s!"entrypoint `{entrypoint.name}` return" entrypoint.returns actual
        .ok env

  partial def validateBody (module : Module) (entrypoint : Entrypoint) (env : TypeEnv) (body : Array Statement) : Except LowerError TypeEnv :=
    body.foldlM (init := env) fun acc stmt =>
      validateStatement module entrypoint acc stmt
end

mutual
  partial def validateStatementIdentifiers (entrypointName : String) : Statement → Except LowerError Unit
    | .letBind name _ _ =>
        validatePsyIdentifier s!"local name in entrypoint `{entrypointName}`" name
    | .letMutBind name _ _ =>
        validatePsyIdentifier s!"local name in entrypoint `{entrypointName}`" name
    | .ifElse _ thenBody elseBody => do
        validateBodyIdentifiers entrypointName thenBody
        validateBodyIdentifiers entrypointName elseBody
    | .boundedFor indexName _ _ body => do
        validatePsyIdentifier s!"loop index in entrypoint `{entrypointName}`" indexName
        validateBodyIdentifiers entrypointName body
    | .whileLoop _ body => validateBodyIdentifiers entrypointName body
    | .assign _ _
    | .assignOp _ _ _
    | .effect _
    | .assert _ _ _
    | .assertEq _ _ _ _
    | .release _
    | .revert _
    | .revertWithError _
    | .return _ =>
        pure ()

  partial def validateBodyIdentifiers (entrypointName : String) (body : Array Statement) : Except LowerError Unit := do
    for stmt in body do
      validateStatementIdentifiers entrypointName stmt
end

def validateIdentifiers (module : Module) : Except LowerError Unit := do
  validatePsyIdentifier "module name" module.name
  validateDistinctNames "struct name" (module.structs.map fun decl => decl.name)
  validateDistinctNames "state id" (module.state.map fun state => state.id)
  validateDistinctNames "entrypoint name" (module.entrypoints.map fun entrypoint => entrypoint.name)
  for decl in module.structs do
    validatePsyIdentifier "struct name" decl.name
    validateDistinctNames s!"struct `{decl.name}` field id" (decl.fields.map fun field => field.id)
    for field in decl.fields do
      validatePsyIdentifier s!"field id in struct `{decl.name}`" field.id
  for state in module.state do
    validatePsyIdentifier "state id" state.id
  for entrypoint in module.entrypoints do
    validatePsyIdentifier "entrypoint name" entrypoint.name
    validateDistinctNames s!"entrypoint `{entrypoint.name}` parameter name" (entrypoint.params.map fun param => param.fst)
    for param in entrypoint.params do
      validatePsyIdentifier s!"parameter name in entrypoint `{entrypoint.name}`" param.fst
    validateBodyIdentifiers entrypoint.name entrypoint.body

def validateStructs (module : Module) : Except LowerError Unit := do
  for decl in module.structs do
    if decl.fields.isEmpty then
      .error { message := s!"struct `{decl.name}` must declare at least one field" }
    for field in decl.fields do
      if field.isRef then
        if !decl.deriveStorage then
          .error { message := s!"field `{field.id}` in struct `{decl.name}` is marked ref, but the struct is not marked deriveStorage" }
        match field.type with
        | .structType typeName =>
            match findStruct? module typeName with
            | some targetDecl =>
                if !targetDecl.deriveStorage then
                  .error { message := s!"field `{field.id}` in struct `{decl.name}` references struct `{typeName}`, but the referenced struct is not marked deriveStorage" }
            | none =>
                .error { message := s!"field `{field.id}` in struct `{decl.name}` references unknown struct `{typeName}`" }
        | other =>
            .error { message := s!"field `{field.id}` in struct `{decl.name}` is marked ref, but has non-struct type `{other.name}`" }
      validateValueType module field.type

def validateEntrypoints (module : Module) : Except LowerError Unit := do
  for entrypoint in module.entrypoints do
    -- EVM-style selectors are target-specific ABI metadata. Psy/DPN entrypoints
    -- are addressed by contract method name, so selectors are ignored during
    -- source generation. They may still be recorded in artifact metadata for
    -- cross-target traceability.
    match entrypoint.selector? with
    | some _ => pure ()
    | none => pure ()
    for param in entrypoint.params do
      validateAbiValueType module param.snd s!"entrypoint `{entrypoint.name}` parameter `{param.fst}`" false
    validateAbiValueType module entrypoint.returns s!"entrypoint `{entrypoint.name}` return type" true

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

def validateState (module : Module) : Except LowerError Unit := do
  if module.state.isEmpty then
    .error { message := "Psy IR v0 requires at least one state field because Dargo v0.1.0 rejects empty #[derive(Storage)] contracts; add a marker state field for stateless fixtures" }
  for state in module.state do
    match state.kind, state.type with
    | .scalar, .u32 => pure ()
    | .scalar, .bool => pure ()
    | .scalar, .hash => pure ()
    | .scalar, .u64 => pure ()
    | .scalar, .structType typeName =>
        match findStruct? module typeName with
        | some decl =>
            if decl.deriveStorage then
              pure ()
            else
              .error { message := s!"state `{state.id}` uses struct `{typeName}`, but the struct is not marked deriveStorage" }
        | none =>
            .error { message := s!"state `{state.id}` references unknown struct `{typeName}`" }
    | .scalar, other =>
        .error { message := s!"state `{state.id}` uses scalar storage of type `{other.name}`; Psy IR v0 scalar storage only supports U32, Bool, Hash, U64, and deriveStorage structs (U8 and Address are valid Psy types but not yet wired as storage scalars)" }
    | .map .hash capacity, .hash =>
        if capacity == 0 then
            .error { message := s!"map state `{state.id}` must have non-zero capacity" }
        else
            pure ()
    | .map keyType _, valueType =>
        .error { message := s!"state `{state.id}` has unsupported Psy IR v0 map type Map<{keyType.name}, {valueType.name}>; only Map<Hash, Hash, N> is supported as storage" }
    | .array length, .bool =>
        if length == 0 then
          .error { message := s!"array state `{state.id}` must have non-zero length" }
        else
          pure ()
    | .array length, .u32 =>
        if length == 0 then
          .error { message := s!"array state `{state.id}` must have non-zero length" }
        else
          pure ()
    | .array length, .u64 =>
        if length == 0 then
          .error { message := s!"array state `{state.id}` must have non-zero length" }
        else
          pure ()
    | .array length, .hash =>
        if length == 0 then
          .error { message := s!"array state `{state.id}` must have non-zero length" }
        else
          pure ()
    | .array length, .structType typeName =>
        if length == 0 then
          .error { message := s!"array state `{state.id}` must have non-zero length" }
        match findStruct? module typeName with
        | some decl =>
            if decl.deriveStorage then
              pure ()
            else
              .error { message := s!"array state `{state.id}` uses struct `{typeName}`, but the struct is not marked deriveStorage" }
        | none =>
            .error { message := s!"array state `{state.id}` references unknown struct `{typeName}`" }
    | .array _, valueType =>
        .error { message := s!"array state `{state.id}` has unsupported Psy IR v0 element type `{valueType.name}`; only Felt, Bool, U32, Hash, and deriveStorage structs are supported" }
    | .dynamicArray, _ =>
        .error { message := s!"state `{state.id}` is storage.dynamicArray; Psy IR v0 does not lower portable dynamic array storage" }

def validateCapabilities (module : Module) : Except LowerError Unit :=
  match resolveModule Target.psyDpn module with
  | .ok _ => .ok ()
  | .error err => .error (diagnosticError err)

end ProofForge.Backend.Psy.IR
