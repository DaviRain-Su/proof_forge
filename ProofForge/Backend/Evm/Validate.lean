import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.SharedValidate
import ProofForge.IR.Contract
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
import ProofForge.Backend.Evm.Validate.Common

namespace ProofForge.Backend.Evm.Validate

open ProofForge.IR
open ProofForge.Target

mutual
  partial def inferExprType (module : Module) (env : TypeEnv) : ProofForge.IR.Expr → Except LowerError ValueType
    | .literal (.u32 _) => .ok .u32
    | .literal (.u8 _) => .ok .u8
    | .literal (.u128 _) => .ok .u128
    | .literal (.u64 _) => .ok .u64
    | .literal (.bool _) => .ok .bool
    | .literal (.hash4 ..) => .ok .hash
    | .literal (.address _) => .ok .address
    | .local name =>
        match findLocal? env name with
        | some binding => .ok binding.type
        | none => .error { message := s!"unknown local `{name}`" }
    | .arrayLit elementType values => do
        for value in values do
          ensureType "array literal element" elementType (← inferExprType module env value)
        .ok (.fixedArray elementType values.size)
    | .arrayGet array index => do
        ensureArrayIndexType "fixed array index" (← inferExprType module env index)
        match ← inferExprType module env array with
        | .fixedArray elementType length => do
            match literalArrayIndex? index with
            | some indexValue =>
                ensureFixedArrayIndexInBounds "fixed array index" indexValue length
            | none => pure ()
            .ok elementType
        | other => .error { message := s!"fixed array indexing target expected `Array`, got `{other.name}`" }
    | .memoryArrayNew elementType length => do
        if !isStorageWordType elementType then
          .error { message := s!"memory array element type `{elementType.name}` must be a word-sized type" }
        ensureType "memory array length" .u64 (← inferExprType module env length)
        .ok (.array elementType)
    | .memoryArrayLength array => do
        match ← inferExprType module env array with
        | .array _ => .ok .u64
        | other => .error { message := s!"memory array length expected `Array`, got `{other.name}`" }
    | .memoryArrayGet array index => do
        ensureArrayIndexType "memory array index" (← inferExprType module env index)
        match ← inferExprType module env array with
        | .array elementType =>
            if !isStorageWordType elementType then
              .error { message := s!"memory array element type `{elementType.name}` must be a word-sized type" }
            .ok elementType
        | other => .error { message := s!"memory array get expected `Array`, got `{other.name}`" }
    | .structLit typeName fields => do
        validateStructLiteralFields module typeName fields (inferExprType module env)
        .ok (.structType typeName)
    | .field base fieldName => do
        match ← inferExprType module env base with
        | .structType typeName => do
            let fieldType ← structFieldType module typeName fieldName
            ensureStructLocalFieldType typeName fieldName fieldType
            .ok fieldType
        | other => .error { message := s!"field `{fieldName}` requires struct value, got `{other.name}`" }
    | .add lhs rhs _ => do inferBinaryNumericType "addition" module env lhs rhs
    | .sub lhs rhs _ => do inferBinaryNumericType "subtraction" module env lhs rhs
    | .mul lhs rhs _ => do inferBinaryNumericType "multiplication" module env lhs rhs
    | .div lhs rhs => do inferBinaryNumericType "division" module env lhs rhs
    | .mod lhs rhs => do inferBinaryNumericType "modulo" module env lhs rhs
    | .pow lhs rhs => do inferBinaryNumericType "exponentiation" module env lhs rhs
    | .bitAnd lhs rhs => do inferBinaryNumericType "bitwise and" module env lhs rhs
    | .bitOr lhs rhs => do inferBinaryNumericType "bitwise or" module env lhs rhs
    | .bitXor lhs rhs => do inferBinaryNumericType "bitwise xor" module env lhs rhs
    | .shiftLeft lhs rhs => do inferBinaryNumericType "shift-left" module env lhs rhs
    | .shiftRight lhs rhs => do inferBinaryNumericType "shift-right" module env lhs rhs
    | .cast value targetType => do
        ensureCastType (← inferExprType module env value) targetType
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
        discard <| inferBinaryNumericType "less-than" module env lhs rhs
        .ok .bool
    | .le lhs rhs => do
        discard <| inferBinaryNumericType "less-or-equal" module env lhs rhs
        .ok .bool
    | .gt lhs rhs => do
        discard <| inferBinaryNumericType "greater-than" module env lhs rhs
        .ok .bool
    | .ge lhs rhs => do
        discard <| inferBinaryNumericType "greater-or-equal" module env lhs rhs
        .ok .bool
    | .boolAnd lhs rhs => do
        ensureType "boolean and left operand" .bool (← inferExprType module env lhs)
        ensureType "boolean and right operand" .bool (← inferExprType module env rhs)
        .ok .bool
    | .boolOr lhs rhs => do
        ensureType "boolean or left operand" .bool (← inferExprType module env lhs)
        ensureType "boolean or right operand" .bool (← inferExprType module env rhs)
        .ok .bool
    | .boolNot value => do
        ensureType "boolean not operand" .bool (← inferExprType module env value)
        .ok .bool
    | .hashValue a b c d => do
        ensureType "hash value part 0" .u64 (← inferExprType module env a)
        ensureType "hash value part 1" .u64 (← inferExprType module env b)
        ensureType "hash value part 2" .u64 (← inferExprType module env c)
        ensureType "hash value part 3" .u64 (← inferExprType module env d)
        .ok .hash
    | .hash preimage => do
        ensureType "hash preimage" .hash (← inferExprType module env preimage)
        .ok .hash
    | .hashTwoToOne lhs rhs => do
        ensureType "hash_two_to_one left operand" .hash (← inferExprType module env lhs)
        ensureType "hash_two_to_one right operand" .hash (← inferExprType module env rhs)
        .ok .hash
    | .ecrecover digest v r s => do
        -- digest/r/s are hash-width words; v is a small u64 (27/28).
        discard <| inferExprType module env digest
        ensureType "ecrecover v" .u64 (← inferExprType module env v)
        discard <| inferExprType module env r
        discard <| inferExprType module env s
        .ok .u64
    | .eip712PermitDigest owner spender value nonce deadline domainSep => do
        discard <| inferExprType module env owner
        discard <| inferExprType module env spender
        ensureType "permit value" .u64 (← inferExprType module env value)
        ensureType "permit nonce" .u64 (← inferExprType module env nonce)
        ensureType "permit deadline" .u64 (← inferExprType module env deadline)
        discard <| inferExprType module env domainSep
        .ok .hash
    | .crosscallAbiPacked target _selector _stores _argsSize _outSize _dynOff dynLen?
        dynTgtOffs dynTargets => do
        ensureType "abi-packed call target" .u64 (← inferExprType module env target)
        match dynLen? with
        | none => pure ()
        | some len => ensureType "abi-packed runtime Call[] length" .u64 (← inferExprType module env len)
        if dynTgtOffs.size != dynTargets.size then
          .error { message := "abi-packed dyn target offsets/targets size mismatch" }
        for t in dynTargets do
          ensureType "abi-packed runtime Call target" .u64 (← inferExprType module env t)
        .ok .u64
    | .nativeValue => .ok .u64
    | .crosscallInvoke target methodId args => do
        ensureCrosscallHandleType "crosscall target contract id"
          (← inferExprType module env target)
        ensureCrosscallHandleType "crosscall method id" (← inferExprType module env methodId)
        for arg in args do
          ensureType "crosscall argument" .u64 (← inferExprType module env arg)
        .ok .u64
    | .crosscallInvokeTyped target methodId args returnType => do
        ensureCrosscallHandleType "typed crosscall target contract id"
          (← inferExprType module env target)
        ensureCrosscallHandleType "typed crosscall method id"
          (← inferExprType module env methodId)
        discard <| crosscallReturnWordTypes module "typed crosscall return" returnType
        for arg in args do
          discard <| crosscallArgWordTypes module "typed crosscall argument" (← inferExprType module env arg)
        .ok returnType
    | .crosscallInvokeValueTyped target methodId callValue args returnType => do
        ensureCrosscallHandleType "value crosscall target contract id"
          (← inferExprType module env target)
        ensureCrosscallHandleType "value crosscall method id"
          (← inferExprType module env methodId)
        ensureType "value crosscall call value" .u64 (← inferExprType module env callValue)
        discard <| crosscallReturnWordTypes module "value crosscall return" returnType
        for arg in args do
          discard <| crosscallArgWordTypes module "value crosscall argument" (← inferExprType module env arg)
        .ok returnType
    | .crosscallInvokeStaticTyped target methodId args returnType => do
        ensureCrosscallHandleType "static crosscall target contract id"
          (← inferExprType module env target)
        ensureCrosscallHandleType "static crosscall method id"
          (← inferExprType module env methodId)
        discard <| crosscallReturnWordTypes module "static crosscall return" returnType
        for arg in args do
          discard <| crosscallArgWordTypes module "static crosscall argument" (← inferExprType module env arg)
        .ok returnType
    | .crosscallInvokeDelegateTyped target methodId args returnType => do
        ensureCrosscallHandleType "delegate crosscall target contract id"
          (← inferExprType module env target)
        ensureCrosscallHandleType "delegate crosscall method id"
          (← inferExprType module env methodId)
        discard <| crosscallReturnWordTypes module "delegate crosscall return" returnType
        for arg in args do
          discard <| crosscallArgWordTypes module "delegate crosscall argument" (← inferExprType module env arg)
        .ok returnType
    | .crosscallCreate callValue initCodeHex => do
        ensureType "contract creation call value" .u64 (← inferExprType module env callValue)
        discard <| normalizeInitCodeHex "contract creation" initCodeHex
        .ok .u64
    | .crosscallCreate2 callValue salt initCodeHex => do
        ensureType "contract creation call value" .u64 (← inferExprType module env callValue)
        ensureType "contract creation salt" .hash (← inferExprType module env salt)
        discard <| normalizeInitCodeHex "contract creation" initCodeHex
        .ok .u64
    | .crosscallNamed _ _ args returnType => do
        for arg in args do discard <| inferExprType module env arg
        .ok returnType
    | .nearPromiseThen _ _ _ _
    | .nearCrosscallInvokePool _ _ _ _
    | .nearPromiseResultsCount
    | .nearPromiseResultStatus _
    | .nearPromiseResultU64 _ =>
        .error { message := "NEAR promise API is not supported on EVM" }
    | .effect effect => inferEffectExprType module env effect

  partial def inferBinaryNumericType
      (context : String)
      (module : Module)
      (env : TypeEnv)
      (lhs rhs : ProofForge.IR.Expr) : Except LowerError ValueType := do
    ensureNumericType context (← inferExprType module env lhs) (← inferExprType module env rhs)

  partial def inferStoragePathType
      (module : Module)
      (env : TypeEnv)
      (stateId : String)
      (path : Array StoragePathSegment) : Except LowerError ValueType := do
    let state ← stateDeclOf module stateId "storage path"
    match state.kind, state.type, path.toList with
    | .map keyType _, _, _ => do
        let some keys := storagePathMapKeys? path
          | if path.isEmpty then
              .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
            else
              .error { message := "EVM IR v0 supports map storage paths only as one or more mapKey segments" }
        for key in keys do
          ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
        .ok state.type
    | .scalar, .structType _, [StoragePathSegment.field fieldName] => do
        let (_, field) ← requireStructStateField module stateId fieldName
        .ok field.type
    | .scalar, .structType _, [] =>
        .error { message := s!"storage path state `{stateId}` is struct storage; first segment must be a field" }
    | .scalar, .structType _, _ =>
        .error { message := "EVM IR v0 supports struct scalar storage paths only as a single field segment" }
    | .scalar, _, [] =>
        .ok state.type
    | .scalar, _, [StoragePathSegment.field fieldName] =>
        .error { message := s!"state `{stateId}` has unsupported EVM IR v0 struct storage type `{state.type.name}`; expected struct storage for field `{fieldName}`" }
    | .scalar, _, _ =>
        .error { message := "EVM IR v0 supports storage paths only for single-segment mapKey map access" }
    | .array _, .structType _, [StoragePathSegment.index index, StoragePathSegment.field fieldName] => do
        let (_, _, _, _, field) ← requireStructArrayStateField module stateId fieldName
        ensureArrayIndexType s!"struct array state `{stateId}` index" (← inferExprType module env index)
        .ok field.type
    | .array _, .structType _, [StoragePathSegment.index _] =>
        .error { message := s!"storage path state `{stateId}` is struct array storage; a field segment must follow the index" }
    | .array _, _, [] =>
        .error { message := s!"storage path state `{stateId}` is array storage; first segment must be an index" }
    | .array _, .structType _, _ =>
        .error { message := "EVM IR v0 supports struct-array storage paths only as index followed by field" }
    | .array _, _, [StoragePathSegment.index index] => do
        let (_, _, elementType) ← requireStorageArrayState module stateId
        ensureArrayIndexType s!"array state `{stateId}` index" (← inferExprType module env index)
        .ok elementType
    | .array _, _, _ =>
        .error { message := "EVM IR v0 supports only single-segment index storage paths for arrays" }
    | .dynamicArray, _, [StoragePathSegment.index index] => do
        let (_, elementType) ← lowerPlan <| ProofForge.Backend.Evm.Plan.requireDynamicArrayState module stateId
        ensureArrayIndexType s!"dynamic array state `{stateId}` index" (← inferExprType module env index)
        .ok elementType
    | .dynamicArray, _, [] =>
        .error { message := s!"storage path state `{stateId}` is dynamic array storage; first segment must be an index" }
    | .dynamicArray, _, _ =>
        .error { message := "EVM IR v0 supports only single-segment index storage paths for dynamic arrays" }

  partial def inferEffectExprType (module : Module) (env : TypeEnv) : Effect → Except LowerError ValueType
    | .storageScalarRead stateId =>
        scalarStateType module stateId
    | .storageScalarWrite _ _ =>
        .error { message := "storage.scalar.write is a statement effect, not an expression" }
    | .memoryArraySet _ _ _ =>
        .error { message := "memory.array.set is a statement effect, not an expression" }
    | .storageScalarAssignOp _ _ _ =>
        .error { message := "storage.scalar.assign_op is a statement effect, not an expression" }
    | .storageMapContains stateId key => do
        let (keyType, _) ← mapStateTypes module stateId
        ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
        .ok .bool
    | .storageMapGet stateId key => do
        let (keyType, valueType) ← mapStateTypes module stateId
        ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
        .ok valueType
    | .storageMapInsert stateId key value => do
        let (keyType, valueType) ← mapStateTypes module stateId
        ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
        ensureType s!"map `{stateId}` value" valueType (← inferExprType module env value)
        .ok valueType
    | .storageMapSet stateId key value => do
        let (keyType, valueType) ← mapStateTypes module stateId
        ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
        ensureType s!"map `{stateId}` value" valueType (← inferExprType module env value)
        .ok valueType
    | .storageArrayRead stateId index => do
        let (_, _, elementType) ← requireStorageArrayState module stateId
        ensureArrayIndexType s!"array state `{stateId}` index" (← inferExprType module env index)
        .ok elementType
    | .storageArrayWrite _ _ _ =>
        .error { message := "storage.array.write is a statement effect, not an expression" }
    | .storageArrayStructFieldRead stateId index fieldName => do
        let (_, _, _, _, field) ← requireStructArrayStateField module stateId fieldName
        ensureArrayIndexType s!"struct array state `{stateId}` index" (← inferExprType module env index)
        .ok field.type
    | .storageArrayStructFieldWrite _ _ _ _ =>
        .error { message := "storage.array.struct.field.write is a statement effect, not an expression" }
    | .storageDynamicArrayPush _ _ =>
        .error { message := "storage.dynamic.array.push is a statement effect, not an expression" }
    | .storageDynamicArrayPop _ =>
        .error { message := "storage.dynamic.array.pop is a statement effect, not an expression" }
    | .storageStructFieldRead stateId fieldName => do
        let (_, field) ← requireStructStateField module stateId fieldName
        .ok field.type
    | .storageStructFieldWrite _ _ _ =>
        .error { message := "storage.struct.field.write is a statement effect, not an expression" }
    | .storagePathRead stateId path =>
        inferStoragePathType module env stateId path
    | .storagePathWrite _ _ _ =>
        .error { message := "storage.path.write is a statement effect, not an expression" }
    | .storagePathAssignOp _ _ _ _ =>
        .error { message := "storage.path.assign_op is a statement effect, not an expression" }
    | .contextRead .userIdHash => .ok .hash
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
        .error { message := "checkErc721Received is a statement effect, not an expression" }
    | .checkErc1155Received _ _ _ _ _ =>
        .error { message := "checkErc1155Received is a statement effect, not an expression" }
end

partial def inferEventFieldExprType (module : Module) (env : TypeEnv) : ProofForge.IR.Expr → Except LowerError ValueType
  | .literal (.u32 _) => .ok .u32
  | .literal (.u64 _) => .ok .u64
  | .literal (.bool _) => .ok .bool
  | .literal (.hash4 ..) => .ok .hash
  | .literal (.address _) => .ok .address
  | .local name =>
      match findLocal? env name with
      | some binding => .ok binding.type
      | none => .error { message := s!"unknown local `{name}`" }
  | .arrayLit elementType values => do
      for value in values do
        ensureType "event field array literal element" elementType (← inferEventFieldExprType module env value)
      .ok (.fixedArray elementType values.size)
  | .arrayGet array index => do
      ensureArrayIndexType "fixed array index" (← inferExprType module env index)
      match ← inferEventFieldExprType module env array with
      | .fixedArray elementType length => do
          match literalArrayIndex? index with
          | some indexValue =>
              ensureFixedArrayIndexInBounds "fixed array index" indexValue length
          | none => pure ()
          .ok elementType
      | other => .error { message := s!"fixed array indexing target expected `Array`, got `{other.name}`" }
  | .structLit typeName fields => do
      if fields.isEmpty then
        .error { message := s!"struct literal `{typeName}` must have at least one field" }
      let some decl := findStruct? module typeName
        | .error { message := s!"unknown struct `{typeName}`" }
      if decl.fields.size != fields.size then
        .error { message := s!"struct literal `{typeName}` expected {decl.fields.size} field(s), got {fields.size}" }
      for field in fields do
        let expected ← structFieldType module typeName field.fst
        let actual ← inferEventFieldExprType module env field.snd
        ensureType s!"struct literal `{typeName}` field `{field.fst}`" expected actual
      for expectedField in decl.fields do
        if !(fields.any fun field => field.fst == expectedField.id) then
          .error { message := s!"struct literal `{typeName}` is missing field `{expectedField.id}`" }
      .ok (.structType typeName)
  | .field base fieldName => do
      match ← inferEventFieldExprType module env base with
      | .structType typeName =>
          structFieldType module typeName fieldName
      | other => .error { message := s!"field `{fieldName}` requires struct value, got `{other.name}`" }
  | .effect effect =>
      inferEffectExprType module env effect
  | other =>
      inferExprType module env other

def eventSignature
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (fields : Array (String × ProofForge.IR.Expr)) : Except LowerError String := do
  validateEventName name
  let _ ← fields.foldlM (init := #[]) fun seen field =>
    validateDistinctEventFieldName name seen field.fst
  let mut typeNames := #[]
  for field in fields do
    let actual ← inferEventFieldExprType module env field.snd
    typeNames := typeNames.push (← eventSignatureFieldType module name field.fst actual)
  .ok (name ++ "(" ++ String.intercalate "," typeNames.toList ++ ")")

def validateEffectStmtTypes (module : Module) (env : TypeEnv) : Effect → Except LowerError Unit
  | .storageScalarRead _ =>
      .error { message := "storage.scalar.read must be used as an expression" }
  | .storageScalarWrite stateId value => do
      ensureType s!"scalar state `{stateId}` write" (← scalarStateType module stateId) (← inferExprType module env value)
  | .storageScalarAssignOp stateId op value => do
      ensureAssignOpTypes op (← scalarStateType module stateId) (← inferExprType module env value)
  | .storageMapContains _ _ =>
      .error { message := "storage.map.contains must be used as an expression" }
  | .storageMapGet _ _ =>
      .error { message := "storage.map.get must be used as an expression" }
  | .storageMapInsert stateId key value => do
      let (keyType, valueType) ← mapStateTypes module stateId
      ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
      ensureType s!"map `{stateId}` value" valueType (← inferExprType module env value)
  | .storageMapSet stateId key value => do
      let (keyType, valueType) ← mapStateTypes module stateId
      ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
      ensureType s!"map `{stateId}` value" valueType (← inferExprType module env value)
  | .storageArrayRead _ _ =>
      .error { message := "storage.array.read must be used as an expression" }
  | .storageArrayWrite stateId index value => do
      let (_, _, elementType) ← requireStorageArrayState module stateId
      ensureArrayIndexType s!"array state `{stateId}` index" (← inferExprType module env index)
      ensureType s!"array state `{stateId}` write" elementType (← inferExprType module env value)
  | .storageArrayStructFieldRead _ _ _ =>
      .error { message := "storage.array.struct.field.read must be used as an expression" }
  | .storageArrayStructFieldWrite stateId index fieldName value => do
      let (_, _, _, _, field) ← requireStructArrayStateField module stateId fieldName
      ensureArrayIndexType s!"struct array state `{stateId}` index" (← inferExprType module env index)
      ensureType s!"struct array state `{stateId}` field `{fieldName}` write" field.type (← inferExprType module env value)
    | .storageDynamicArrayPush stateId value => do
      let (_, elementType) ← lowerPlan <| ProofForge.Backend.Evm.Plan.requireDynamicArrayState module stateId
      ensureType s!"dynamic array state `{stateId}` push" elementType (← inferExprType module env value)
    | .storageDynamicArrayPop stateId => do
      let _ ← lowerPlan <| ProofForge.Backend.Evm.Plan.requireDynamicArrayState module stateId
      .ok ()
    | .memoryArraySet array index value => do
      match ← inferExprType module env array with
      | .array elementType => do
          if !isStorageWordType elementType then
            .error { message := s!"memory array element type `{elementType.name}` must be a word-sized type" }
          ensureArrayIndexType "memory array set index" (← inferExprType module env index)
          ensureType "memory array set value" elementType (← inferExprType module env value)
          .ok ()
      | other => .error { message := s!"memory array set expected `Array`, got `{other.name}`" }
    | .storageStructFieldRead _ _ =>
      .error { message := "storage.struct.field.read must be used as an expression" }
  | .storageStructFieldWrite stateId fieldName value => do
      let (_, field) ← requireStructStateField module stateId fieldName
      ensureType s!"struct state `{stateId}` field `{fieldName}` write" field.type (← inferExprType module env value)
  | .storagePathRead _ _ =>
      .error { message := "storage.path.read must be used as an expression" }
  | .storagePathWrite stateId path value => do
      ensureType s!"storage path `{stateId}` write" (← inferStoragePathType module env stateId path) (← inferExprType module env value)
  | .storagePathAssignOp stateId path op value => do
      ensureAssignOpTypes op (← inferStoragePathType module env stateId path) (← inferExprType module env value)
  | .contextRead _ =>
      .error { message := "context reads must be used as expressions" }
  | .eventEmit name fields => do
      discard <| eventSignature module env name fields
  | .eventEmitIndexed name indexedFields dataFields => do
      validateIndexedEventFieldCount name indexedFields.size
      for field in indexedFields do
        ensureIndexedEventFieldType module name field.fst (← inferEventFieldExprType module env field.snd)
      discard <| eventSignature module env name (indexedFields ++ dataFields)
  | .checkErc721Received operator fromAddr toAddr tokenId => do
      discard <| inferExprType module env operator
      discard <| inferExprType module env fromAddr
      discard <| inferExprType module env toAddr
      discard <| inferExprType module env tokenId
  | .checkErc1155Received operator fromAddr toAddr id amount => do
      discard <| inferExprType module env operator
      discard <| inferExprType module env fromAddr
      discard <| inferExprType module env toAddr
      discard <| inferExprType module env id
      discard <| inferExprType module env amount

def requireMutableLocal (env : TypeEnv) (context name : String) : Except LowerError LocalBinding := do
  let some binding := findLocal? env name
    | .error { message := s!"unknown local `{name}`" }
  if !binding.isMutable then
    .error { message := s!"{context} local `{name}` is not mutable" }
  .ok binding

partial def validateFixedArrayIndexPathTarget
    (module : Module)
    (env : TypeEnv)
    (context : String)
    (type : ValueType)
    (path : Array ProofForge.IR.Expr) : Except LowerError ValueType := do
  match path.toList with
  | [] => .ok type
  | index :: rest =>
      match type with
      | .fixedArray elementType length => do
          ensureArrayIndexType s!"{context} fixed-array index" (← inferExprType module env index)
          match literalArrayIndex? index with
          | some indexValue => ensureFixedArrayIndexInBounds s!"{context} fixed-array index" indexValue length
          | none => pure ()
          validateFixedArrayIndexPathTarget module env context elementType rest.toArray
      | .array _ =>
          .error { message := s!"{context} target expected fixed `Array`, got dynamic `Array`" }
      | other =>
          .error { message := s!"{context} target expected `Array`, got `{other.name}`" }

def validateLocalFixedArrayTarget
    (module : Module)
    (env : TypeEnv)
    (context name : String)
    (index value : ProofForge.IR.Expr) : Except LowerError ValueType := do
  let binding ← requireMutableLocal env context name
  match binding.type with
  | .fixedArray elementType length => do
      ensureArrayIndexType s!"{context} fixed-array index" (← inferExprType module env index)
      match literalArrayIndex? index with
      | some indexValue =>
          ensureFixedArrayIndexInBounds s!"{context} fixed-array index" indexValue length
      | none => pure ()
      ensureType s!"{context} value" elementType (← inferExprType module env value)
      match elementType with
      | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => pure ()
      | .structType _ =>
          .error {
            message := s!"{context} local `{name}` returns struct values; IR EVM v0 requires field assignment such as array[index].field"
          }
      | .unit | .fixedArray _ _ | .bytes | .string | .array _ =>
          .error {
            message := s!"{context} local `{name}` has unsupported EVM IR v0 element target type `{elementType.name}`; local fixed-array element targets must resolve to U32, U64, Bool, Hash, or Address leaves"
          }
      .ok elementType
  | other =>
      .error { message := s!"{context} local `{name}` expected fixed-array target, got `{other.name}`" }

def validateLocalFixedArrayStaticPathTarget
    (module : Module)
    (env : TypeEnv)
    (context name : String)
    (path : Array ProofForge.IR.Expr)
    (value : ProofForge.IR.Expr) : Except LowerError ValueType := do
  let binding ← requireMutableLocal env context name
  let targetType ← validateFixedArrayIndexPathTarget module env context binding.type path
  ensureType s!"{context} value" targetType (← inferExprType module env value)
  match targetType with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => .ok targetType
  | .structType _ =>
      .error {
        message := s!"{context} local `{name}` returns struct values; IR EVM v0 requires field assignment such as array[index].field"
      }
  | .unit | .fixedArray _ _ | .bytes | .string | .array _ =>
      .error {
        message := s!"{context} local `{name}` has unsupported EVM IR v0 element target type `{targetType.name}`; local fixed-array element targets must resolve to U32, U64, Bool, Hash, or Address leaves"
      }

def validateLocalStructTarget
    (module : Module)
    (env : TypeEnv)
    (context name fieldName : String)
    (value : ProofForge.IR.Expr) : Except LowerError ValueType := do
  let binding ← requireMutableLocal env context name
  match binding.type with
  | .structType typeName => do
      let fieldType ← structFieldType module typeName fieldName
      ensureStructLocalFieldType typeName fieldName fieldType
      ensureType s!"{context} value" fieldType (← inferExprType module env value)
      .ok fieldType
  | other =>
      .error { message := s!"{context} local `{name}` expected struct target, got `{other.name}`" }

def validateLocalStructArrayFieldTarget
    (module : Module)
    (env : TypeEnv)
    (context name : String)
    (index : ProofForge.IR.Expr)
    (fieldName : String)
    (value : ProofForge.IR.Expr) : Except LowerError ValueType := do
  discard <| requireMutableLocal env context name
  let (_, length, fieldType) ← requireLocalFixedStructArrayField module env context name fieldName
  ensureArrayIndexType s!"{context} fixed-array index" (← inferExprType module env index)
  match literalArrayIndex? index with
  | some indexValue =>
      ensureFixedArrayIndexInBounds s!"{context} fixed-array index" indexValue length
  | none => pure ()
  ensureType s!"{context} value" fieldType (← inferExprType module env value)
  .ok fieldType

def validateLocalFixedArrayPathFieldTarget
    (module : Module)
    (env : TypeEnv)
    (context name : String)
    (path : Array ProofForge.IR.Expr)
    (fieldName : String)
    (value : ProofForge.IR.Expr) : Except LowerError ValueType := do
  let binding ← requireMutableLocal env context name
  let targetType ← validateFixedArrayIndexPathTarget module env context binding.type path
  match targetType with
  | .structType typeName => do
      discard <| ensureLocalFlatStructType module s!"{context} local `{name}` fixed-array leaf" typeName
      let fieldType ← structFieldType module typeName fieldName
      ensureStructLocalFieldType typeName fieldName fieldType
      ensureType s!"{context} value" fieldType (← inferExprType module env value)
      .ok fieldType
  | other =>
      .error {
        message := s!"{context} local `{name}` field target expected flat struct leaf, got `{other.name}`"
      }

def validateAssignTarget
    (module : Module)
    (env : TypeEnv)
    (target value : ProofForge.IR.Expr) : Except LowerError Unit := do
  let validateDefault : Except LowerError Unit := do
    match target with
    | .local name => do
        let binding ← requireMutableLocal env "assignment target" name
        match binding.type with
        | .fixedArray elementType _ => do
            match elementType with
            | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => pure ()
            | .fixedArray _ _ =>
                ensureLocalNestedFixedArrayValueType module "assignment target" name elementType
            | .structType typeName =>
                discard <| ensureLocalFlatStructType module s!"assignment target `{name}` fixed-array element" typeName
            | .unit | .bytes | .string | .array _ =>
                .error {
                  message := s!"assignment target `{name}` has unsupported EVM IR v0 fixed-array element type `{elementType.name}`; local fixed arrays support U32, U64, Bool, Hash, Address, flat struct elements, or nested fixed arrays with scalar or flat struct leaves"
                }
            ensureType "assignment value" binding.type (← inferExprType module env value)
        | .structType typeName => do
            let some decl := findStruct? module typeName
              | .error { message := s!"unknown struct `{typeName}`" }
            for field in decl.fields do
              ensureStructLocalFieldType typeName field.id field.type
            ensureType "assignment value" binding.type (← inferExprType module env value)
        | _ =>
            ensureType "assignment value" binding.type (← inferExprType module env value)
    | .arrayGet (.local name) index => do
        discard <| validateLocalFixedArrayTarget module env "assignment target" name index value
    | .field (.arrayGet (.local name) index) fieldName => do
        discard <| validateLocalStructArrayFieldTarget module env "assignment target" name index fieldName value
    | .field (.local name) fieldName => do
        discard <| validateLocalStructTarget module env "assignment target" name fieldName value
    | _ =>
        .error { message := "assignment target must be a mutable local, mutable local fixed-array element, mutable local struct field, or mutable local struct-array field in IR EVM v0" }
  match collectLocalArrayFieldGetPath target with
  | some (name, path, fieldName) =>
      if path.size > 1 then
        discard <| validateLocalFixedArrayPathFieldTarget module env "assignment target" name path fieldName value
      else
        validateDefault
  | none =>
      match collectLocalArrayGetPath target with
      | some (name, path) =>
          if path.size > 1 then
            discard <| validateLocalFixedArrayStaticPathTarget module env "assignment target" name path value
          else
            validateDefault
      | none =>
          validateDefault

def validateAssignOpTarget
    (module : Module)
    (env : TypeEnv)
    (target : ProofForge.IR.Expr)
    (op : AssignOp)
    (value : ProofForge.IR.Expr) : Except LowerError Unit := do
  let validateDefault : Except LowerError Unit := do
    match target with
    | .local name => do
        let binding ← requireMutableLocal env "compound assignment target" name
        ensureAssignOpTypes op binding.type (← inferExprType module env value)
    | .arrayGet (.local name) index => do
        let targetType ← validateLocalFixedArrayTarget module env "compound assignment target" name index value
        ensureAssignOpTypes op targetType (← inferExprType module env value)
    | .field (.arrayGet (.local name) index) fieldName => do
        let targetType ← validateLocalStructArrayFieldTarget module env "compound assignment target" name index fieldName value
        ensureAssignOpTypes op targetType (← inferExprType module env value)
    | .field (.local name) fieldName => do
        let targetType ← validateLocalStructTarget module env "compound assignment target" name fieldName value
        ensureAssignOpTypes op targetType (← inferExprType module env value)
    | _ =>
        .error { message := "compound assignment target must be a mutable local, mutable local fixed-array element, mutable local struct field, or mutable local struct-array field in IR EVM v0" }
  match collectLocalArrayFieldGetPath target with
  | some (name, path, fieldName) =>
      if path.size > 1 then
        let targetType ← validateLocalFixedArrayPathFieldTarget module env "compound assignment target" name path fieldName value
        ensureAssignOpTypes op targetType (← inferExprType module env value)
      else
        validateDefault
  | none =>
      match collectLocalArrayGetPath target with
      | some (name, path) =>
          if path.size > 1 then
            let targetType ← validateLocalFixedArrayStaticPathTarget module env "compound assignment target" name path value
            ensureAssignOpTypes op targetType (← inferExprType module env value)
          else
            validateDefault
      | none =>
          validateDefault

mutual
  partial def validateStatements (module : Module) (entrypoint : Entrypoint) (env : TypeEnv) (statements : Array Statement) : Except LowerError TypeEnv :=
    statements.foldlM (init := env) fun env stmt =>
      validateStatementTypes module entrypoint env stmt

  partial def validateStatementTypes (module : Module) (entrypoint : Entrypoint) (env : TypeEnv) : Statement → Except LowerError TypeEnv
    | .letBind name type value => do
        ensureType s!"let binding `{name}`" type (← inferExprType module env value)
        addLocal env name type false
    | .letMutBind name type value => do
        ensureType s!"mutable let binding `{name}`" type (← inferExprType module env value)
        addLocal env name type true
    | .assign target value => do
        validateAssignTarget module env target value
        .ok env
    | .assignOp target op value => do
        validateAssignOpTarget module env target op value
        .ok env
    | .effect effect => do
        validateEffectStmtTypes module env effect
        .ok env
    | .assert condition _ _ => do
        ensureType "assert condition" .bool (← inferExprType module env condition)
        .ok env
    | .assertEq lhs rhs _ _ => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureType "assert_eq right operand" lhsType rhsType
        ensureEqType "assert_eq" lhsType
        .ok env
    | .release _ =>
        .error { message := "release statements are not supported by IR EVM v0" }
    | .revert _ => .ok env
    | .revertWithError _ => .ok env
    | .ifElse condition thenBody elseBody => do
        ensureType "if condition" .bool (← inferExprType module env condition)
        discard <| validateStatements module entrypoint env thenBody
        discard <| validateStatements module entrypoint env elseBody
        .ok env
    | .boundedFor indexName start stopExclusive body => do
        if stopExclusive <= start then
          .error { message := s!"bounded loop `{indexName}` must have stop greater than start" }
        let loopEnv ← addLocal env indexName .u32 false
        discard <| validateStatements module entrypoint loopEnv body
        .ok env
    | .whileLoop _ _ =>
        .error { message := "while loops are not supported by EVM IR v0; use boundedFor" }
    | .return value => do
        ensureType "return value" entrypoint.returns (← inferExprType module env value)
        .ok env
end

def entrypointTypeEnv (entrypoint : Entrypoint) : TypeEnv :=
  (ProofForge.Backend.SharedValidate.sharedParamBindings entrypoint).map fun binding =>
    { name := binding.name, type := binding.type, isMutable := binding.isMutable : LocalBinding }

def validateEntrypointTypes (module : Module) (entrypoint : Entrypoint) : Except LowerError Unit := do
  discard <| validateStatements module entrypoint (entrypointTypeEnv entrypoint) entrypoint.body

/-- Control-flow return-path predicate, delegating to the shared
`SharedValidate.statementAlwaysReturns`. Kept as a wrapper so existing EVM
call sites (`lowerEntrypoint` in `Evm/IR.lean`) keep their names. -/
def statementAlwaysReturns (stmt : Statement) : Bool :=
  ProofForge.Backend.SharedValidate.statementAlwaysReturns stmt

def statementsAlwaysReturn (statements : Array Statement) : Bool :=
  ProofForge.Backend.SharedValidate.statementsAlwaysReturn statements

def validateDistinctStructName (seen : Array String) (name : String) : Except LowerError (Array String) :=
  if name.isEmpty then
    .error { message := "struct name must be non-empty for IR EVM v0" }
  else if seen.contains name then
    .error { message := s!"duplicate struct `{name}`" }
  else
    .ok (seen.push name)

def validateDistinctStructFieldName (structName : String) (seen : Array String) (fieldName : String) : Except LowerError (Array String) :=
  if fieldName.isEmpty then
    .error { message := s!"struct `{structName}` field name must be non-empty" }
  else if seen.contains fieldName then
    .error { message := s!"duplicate field `{fieldName}` in struct `{structName}`" }
  else
    .ok (seen.push fieldName)

def validateStructs (module : Module) : Except LowerError Unit := do
  let _ ← module.structs.foldlM (init := #[]) fun seen decl =>
    validateDistinctStructName seen decl.name
  for decl in module.structs do
    if decl.fields.isEmpty then
      .error { message := s!"struct `{decl.name}` must declare at least one field" }
    let _ ← decl.fields.foldlM (init := #[]) fun seen field =>
      validateDistinctStructFieldName decl.name seen field.id
    for field in decl.fields do
      ensureStructLocalFieldType decl.name field.id field.type

def validateStorageStructState (context typeName : String) (module : Module) : Except LowerError Unit := do
  let some decl := findStruct? module typeName
    | .error { message := s!"{context} uses unknown struct `{typeName}`" }
  if decl.fields.isEmpty then
    .error { message := s!"{context} uses empty struct `{typeName}`; EVM IR v0 storage structs must have at least one field" }
  for field in decl.fields do
    ensureStructLocalFieldType decl.name field.id field.type

def validateState (module : Module) : Except LowerError Unit := do
  for state in module.state do
    match state.kind, state.type with
    | .scalar, .u8 => pure ()
    | .scalar, .u32 => pure ()
    | .scalar, .u64 => pure ()
    | .scalar, .u128 => pure ()
    | .scalar, .bool => pure ()
    | .scalar, .hash => pure ()
    | .scalar, .address => pure ()
    | .scalar, .structType typeName =>
        validateStorageStructState s!"state `{state.id}`" typeName module
    | .scalar, other =>
        .error { message := s!"state `{state.id}` has unsupported EVM IR v0 type `{other.name}`" }
    | .map keyType capacity, valueType =>
        if isStorageWordType keyType && isStorageWordType valueType then
          pure ()
        else
          .error {
            message := s!"map state `{state.id}` has unsupported EVM IR v0 type `{mapShapeName keyType valueType capacity}`; storage maps support key/value word types U32, U64, Bool, or Hash"
          }
    | .array 0, _ =>
        .error { message := s!"array state `{state.id}` must have non-zero length" }
    | .array _, .u8 => pure ()
    | .array _, .u32 => pure ()
    | .array _, .u64 => pure ()
    | .array _, .u128 => pure ()
    | .array _, .bool => pure ()
    | .array _, .hash => pure ()
    | .array _, .address => pure ()
    | .array _, .structType typeName =>
        validateStorageStructState s!"array state `{state.id}`" typeName module
    | .array _, other =>
        .error { message := s!"array state `{state.id}` has unsupported EVM IR v0 element type `{other.name}`; storage arrays support U32, U64, Bool, Hash, or flat struct arrays" }
    | .dynamicArray, _ =>
        .error { message := s!"state `{state.id}` is dynamic array storage; IR EVM v0 does not yet support dynamic array storage" }

def validateCapabilities (module : Module) : Except LowerError Unit :=
  match resolveModule Target.evm module with
  | .ok _ => .ok ()
  | .error err => .error (diagnosticError err)

/-! Detect whether a module uses any `.add`/`.sub`/`.mul` `Expr` or compound
    assignment op that would route to the checked-arithmetic helpers. Used to
    avoid emitting the helpers when a module only uses div/mod/bitwise/shift. -/
mutual
  partial def effectUsesCheckedArithmetic : Effect → Bool
    | .storageScalarWrite _ v => exprUsesCheckedArithmetic v
    | .storageScalarAssignOp _ op v => needsCheckedArithmetic op || exprUsesCheckedArithmetic v
    | .storageMapInsert _ _ v => exprUsesCheckedArithmetic v
    | .storageMapSet _ _ v => exprUsesCheckedArithmetic v
    | .storageArrayWrite _ _ v => exprUsesCheckedArithmetic v
    | .storageArrayStructFieldWrite _ _ _ v => exprUsesCheckedArithmetic v
    | .storageDynamicArrayPush _ v => exprUsesCheckedArithmetic v
    | .storageDynamicArrayPop _ => false
    | .memoryArraySet _ i v => exprUsesCheckedArithmetic i || exprUsesCheckedArithmetic v
    | .storageStructFieldWrite _ _ v => exprUsesCheckedArithmetic v
    | .storagePathWrite _ _ v => exprUsesCheckedArithmetic v
    | .storagePathAssignOp _ _ op v => needsCheckedArithmetic op || exprUsesCheckedArithmetic v
    | .storageScalarRead _ | .storageMapContains _ _ | .storageMapGet _ _
    | .storageArrayRead _ _ | .storageArrayStructFieldRead _ _ _
    | .storageStructFieldRead _ _ | .storagePathRead _ _
    | .contextRead _ | .eventEmit _ _ | .eventEmitIndexed _ _ _ => false
    | .checkErc721Received a b c d =>
        exprUsesCheckedArithmetic a || exprUsesCheckedArithmetic b ||
          exprUsesCheckedArithmetic c || exprUsesCheckedArithmetic d
    | .checkErc1155Received a b c d e =>
        exprUsesCheckedArithmetic a || exprUsesCheckedArithmetic b ||
          exprUsesCheckedArithmetic c || exprUsesCheckedArithmetic d || exprUsesCheckedArithmetic e

  partial def exprUsesCheckedArithmetic : Expr → Bool
    | .add _ _ _ | .sub _ _ _ | .mul _ _ _ => true
    | .literal _ | .local _ | .nativeValue => false
    | .arrayLit _ xs => xs.any exprUsesCheckedArithmetic
    | .arrayGet a i => exprUsesCheckedArithmetic a || exprUsesCheckedArithmetic i
    | .memoryArrayNew _ l => exprUsesCheckedArithmetic l
    | .memoryArrayLength a => exprUsesCheckedArithmetic a
    | .memoryArrayGet a i => exprUsesCheckedArithmetic a || exprUsesCheckedArithmetic i
    | .structLit _ fs => fs.any (fun (_, v) => exprUsesCheckedArithmetic v)
    | .field b _ => exprUsesCheckedArithmetic b
    | .div l r | .mod l r | .pow l r
    | .bitAnd l r | .bitOr l r | .bitXor l r
    | .shiftLeft l r | .shiftRight l r => exprUsesCheckedArithmetic l || exprUsesCheckedArithmetic r
    | .cast v _ => exprUsesCheckedArithmetic v
    | .eq l r | .ne l r | .lt l r | .le l r | .gt l r | .ge l r
    | .boolAnd l r | .boolOr l r => exprUsesCheckedArithmetic l || exprUsesCheckedArithmetic r
    | .boolNot v => exprUsesCheckedArithmetic v
    | .hashValue a b c d => exprUsesCheckedArithmetic a || exprUsesCheckedArithmetic b
        || exprUsesCheckedArithmetic c || exprUsesCheckedArithmetic d
    | .hash p => exprUsesCheckedArithmetic p
    | .hashTwoToOne l r => exprUsesCheckedArithmetic l || exprUsesCheckedArithmetic r
    | .ecrecover a b c d =>
        exprUsesCheckedArithmetic a || exprUsesCheckedArithmetic b ||
          exprUsesCheckedArithmetic c || exprUsesCheckedArithmetic d
    | .eip712PermitDigest a b c d e f =>
        exprUsesCheckedArithmetic a || exprUsesCheckedArithmetic b ||
          exprUsesCheckedArithmetic c || exprUsesCheckedArithmetic d ||
          exprUsesCheckedArithmetic e || exprUsesCheckedArithmetic f
    | .crosscallAbiPacked target _ _ _ _ _ _ _ _ =>
        exprUsesCheckedArithmetic target
    | .crosscallInvoke t m args | .crosscallInvokeTyped t m args _
    | .crosscallInvokeValueTyped t m _ args _
    | .crosscallInvokeStaticTyped t m args _ | .crosscallInvokeDelegateTyped t m args _ =>
        exprUsesCheckedArithmetic t || exprUsesCheckedArithmetic m || args.any exprUsesCheckedArithmetic
    | .crosscallCreate v _ => exprUsesCheckedArithmetic v
    | .crosscallCreate2 v s _ => exprUsesCheckedArithmetic v || exprUsesCheckedArithmetic s
    | .crosscallNamed _ _ args _ => args.any exprUsesCheckedArithmetic
    | .nearPromiseThen p m args d =>
        exprUsesCheckedArithmetic p || exprUsesCheckedArithmetic m || exprUsesCheckedArithmetic d ||
          args.any exprUsesCheckedArithmetic
    | .nearCrosscallInvokePool accountIndex methodId args deposit =>
        exprUsesCheckedArithmetic accountIndex || exprUsesCheckedArithmetic methodId ||
          exprUsesCheckedArithmetic deposit || args.any exprUsesCheckedArithmetic
    | .nearPromiseResultsCount => false
    | .nearPromiseResultStatus i => exprUsesCheckedArithmetic i
    | .nearPromiseResultU64 i => exprUsesCheckedArithmetic i
    | .effect e => effectUsesCheckedArithmetic e

  partial def stmtUsesCheckedArithmetic : Statement → Bool
    | .letBind _ _ v | .letMutBind _ _ v | .assign _ v | .assignOp _ _ v | .return v =>
        exprUsesCheckedArithmetic v
    | .assert _ _ _ | .assertEq _ _ _ _ | .release _ | .revert _ | .revertWithError _ => false
    | .effect e => effectUsesCheckedArithmetic e
    | .ifElse c thenBody elseBody =>
        exprUsesCheckedArithmetic c || thenBody.any stmtUsesCheckedArithmetic
          || elseBody.any stmtUsesCheckedArithmetic
    | .boundedFor _ _ _ body => body.any stmtUsesCheckedArithmetic
    | .whileLoop c body => exprUsesCheckedArithmetic c || body.any stmtUsesCheckedArithmetic
end

def moduleUsesCheckedArithmetic (module : Module) : Bool :=
  module.entrypoints.any (fun ep => ep.body.any stmtUsesCheckedArithmetic)

end ProofForge.Backend.Evm.Validate
