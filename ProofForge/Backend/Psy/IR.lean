import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Contract
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
import ProofForge.Backend.Psy.Plan
import ProofForge.Compiler.Psy.AST
import ProofForge.Compiler.Psy.Printer
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
    | .add lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "addition" lhsType rhsType
    | .sub lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "subtraction" lhsType rhsType
    | .mul lhs rhs => do
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
    | .nativeValue => .ok .u64
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

open Lean.Compiler.Psy hiding Module AssignOp Expr Stmt Effect ContextField Literal TypeName StorageTarget StoragePathSegment Method StructDecl StructField StateDecl Test

/-- Map a portable IR `AssignOp` to the Psy AST `AssignOp`. -/
def mapAssignOp : AssignOp → Lean.Compiler.Psy.AssignOp
  | .add => .add
  | .sub => .sub
  | .mul => .mul
  | .div => .div
  | .mod => .mod
  | .bitAnd => .bitAnd
  | .bitOr => .bitOr
  | .bitXor => .bitXor
  | .shiftLeft => .shiftLeft
  | .shiftRight => .shiftRight

/-- Map a portable IR `ContextField` to the Psy AST `ContextField`, rejecting
unsupported context fields. -/
def mapContextField : IR.ContextField → Except LowerError Lean.Compiler.Psy.ContextField
  | .userId => .ok .userId
  | .contractId => .ok .contractId
  | .checkpointId => .ok .checkpointId
  | field => .error { message := s!"Psy IR v0 context read `{field.name}` is not supported; only userId, contractId, and checkpointId are available" }

/-- Map a portable IR `Literal` to the Psy AST `Literal`. -/
def buildLiteral : IR.Literal → Lean.Compiler.Psy.Literal
  | .u32 value => .u32 value
  | .u64 value => .felt value
  | .bool value => .bool value
  | .hash4 a b c d => .hash4 a b c d
  | .u8 value => .u8 value
  | .u128 value => .u128 value
  | .address value => .address (toString value)

/-- Build a `Lean.Compiler.Psy.TypeName` from a portable `ValueType` via `valueTypeName`. -/
def typeName (type : ValueType) : Except LowerError Lean.Compiler.Psy.TypeName :=
  match valueTypeName type with
  | .ok text => .ok { text }
  | .error err => .error err

mutual
  /-- Build a `Lean.Compiler.Psy.Expr` from a portable IR `Expr`. Storage/state validation is
  performed by the type-checking pass before this runs; the builder only folds
  the validated shape into the AST. -/
  partial def buildExpr (ctx : BuildContext) : IR.Expr → Except LowerError Lean.Compiler.Psy.Expr
    | .literal value => .ok <| .literal (buildLiteral value)
    | .local name => .ok <| .local name
    | .arrayLit elementType values => do
        if values.isEmpty then
          .error { message := s!"empty fixed array literals are not supported by Psy IR v0 for `{← valueTypeName elementType}`" }
        let elementTypeName ← typeName elementType
        let items ← values.mapM (buildExpr ctx)
        .ok <| .arrayLit elementTypeName items
    | .arrayGet array index => do
        .ok <| .arrayGet (← buildExpr ctx array) (← buildExpr ctx index)
    | .memoryArrayNew _ _ =>
        .error { message := "memory arrays are not supported by Psy IR v0" }
    | .memoryArrayLength _ =>
        .error { message := "memory arrays are not supported by Psy IR v0" }
    | .memoryArrayGet _ _ =>
        .error { message := "memory arrays are not supported by Psy IR v0" }
    | .structLit structName fields => do
        if fields.isEmpty then
          .error { message := s!"struct literal `{structName}` must have at least one field" }
        let items ← fields.mapM fun (n, v) => do
          .ok (n, ← buildExpr ctx v)
        .ok <| .structLit structName items
    | .field base fieldName => do
        .ok <| .field (← buildExpr ctx base) fieldName
    | .add lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .add (← buildExpr ctx rhs)
    | .sub lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .sub (← buildExpr ctx rhs)
    | .mul lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .mul (← buildExpr ctx rhs)
    | .div lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .div (← buildExpr ctx rhs)
    | .mod lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .mod (← buildExpr ctx rhs)
    | .pow lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .pow (← buildExpr ctx rhs)
    | .bitAnd lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .bitAnd (← buildExpr ctx rhs)
    | .bitOr lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .bitOr (← buildExpr ctx rhs)
    | .bitXor lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .bitXor (← buildExpr ctx rhs)
    | .shiftLeft lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .shiftLeft (← buildExpr ctx rhs)
    | .shiftRight lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .shiftRight (← buildExpr ctx rhs)
    | .cast value targetType => do
        let targetTypeName ← typeName targetType
        .ok <| .cast (← buildExpr ctx value) targetTypeName
    | .eq lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .eq (← buildExpr ctx rhs)
    | .ne lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .ne (← buildExpr ctx rhs)
    | .lt lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .lt (← buildExpr ctx rhs)
    | .le lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .le (← buildExpr ctx rhs)
    | .gt lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .gt (← buildExpr ctx rhs)
    | .ge lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .ge (← buildExpr ctx rhs)
    | .boolAnd lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .boolAnd (← buildExpr ctx rhs)
    | .boolOr lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .boolOr (← buildExpr ctx rhs)
    | .boolNot value => do .ok <| .unary .not (← buildExpr ctx value)
    | .hashValue a b c d => do .ok <| .hashValue (← buildExpr ctx a) (← buildExpr ctx b) (← buildExpr ctx c) (← buildExpr ctx d)
    | .hash preimage => do .ok <| .hash (← buildExpr ctx preimage)
    | .hashTwoToOne lhs rhs => do .ok <| .hashTwoToOne (← buildExpr ctx lhs) (← buildExpr ctx rhs)
    | .nativeValue =>
        .error { message := "native value inspection is not supported by Psy IR v0" }
    | .crosscallInvoke target methodId args => do
        .ok <| .crosscallInvoke (← buildExpr ctx target) (← buildExpr ctx methodId) (← args.mapM (buildExpr ctx))
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
    | .nearPromiseThen _ _ _ _
    | .nearCrosscallInvokePool _ _ _ _
    | .nearPromiseResultsCount
    | .nearPromiseResultStatus _
    | .nearPromiseResultU64 _ =>
        .error { message := "NEAR promise API is not supported by Psy IR v0" }
    | .effect effect => buildEffectExpr ctx effect

  /-- Build a `Lean.Compiler.Psy.Expr` from a portable IR `Effect` in expression position. -/
  partial def buildEffectExpr (ctx : BuildContext) : IR.Effect → Except LowerError Lean.Compiler.Psy.Expr
    | .storageScalarRead stateId => do
        requireScalarStateCtx ctx stateId
        .ok <| .storageScalarRead stateId
    | .storageScalarWrite _ _ =>
        .error { message := "storage.scalar.write is a statement effect, not an expression" }
    | .storageScalarAssignOp _ _ _ =>
        .error { message := "storage.scalar.assign_op is a statement effect, not an expression" }
    | .storageMapContains stateId key => do
        requireMapStateCtx ctx stateId
        .ok <| .storageMapContains stateId (← buildExpr ctx key)
    | .storageMapGet stateId key => do
        requireMapStateCtx ctx stateId
        .ok <| .storageMapGet stateId (← buildExpr ctx key)
    | .storageMapInsert stateId key value => do
        requireMapStateCtx ctx stateId
        .ok <| .storageMapInsert stateId (← buildExpr ctx key) (← buildExpr ctx value)
    | .storageMapSet stateId key value => do
        requireMapStateCtx ctx stateId
        .ok <| .storageMapSet stateId (← buildExpr ctx key) (← buildExpr ctx value)
    | .storageArrayRead stateId index => do
        requireArrayStateCtx ctx stateId
        let feltBacked := isFeltBackedU32ArrayCtx ctx stateId
        .ok <| .storageArrayRead stateId (← buildExpr ctx index) feltBacked
    | .storageArrayWrite _ _ _ =>
        .error { message := "storage.array.write is a statement effect, not an expression" }
    | .storageArrayStructFieldRead stateId index fieldName => do
        requireStructArrayStateCtx ctx stateId fieldName
        .ok <| .storageArrayStructFieldRead stateId (← buildExpr ctx index) fieldName
    | .storageArrayStructFieldWrite _ _ _ _ =>
        .error { message := "storage.array.struct.field.write is a statement effect, not an expression" }
    | .storageDynamicArrayPush _ _ =>
        .error { message := "storage.dynamic.array.push is a statement effect, not an expression" }
    | .storageDynamicArrayPop _ =>
        .error { message := "storage.dynamic.array.pop is a statement effect, not an expression" }
    | .memoryArraySet _ _ _ =>
        .error { message := "memory.array.set is a statement effect, not an expression" }
    | .storageStructFieldRead stateId fieldName => do
        requireStructScalarStateCtx ctx stateId fieldName
        .ok <| .storageStructFieldRead stateId fieldName
    | .storageStructFieldWrite _ _ _ =>
        .error { message := "storage.struct.field.write is a statement effect, not an expression" }
    | .storagePathRead stateId path => do
        discard <| resolveStoragePathTypeCtx ctx stateId path
        match lookupState? ctx stateId with
        | some { shape := .map _ _ _, .. } =>
            match path.toList with
            | .mapKey key :: [] => .ok <| .storageMapGet stateId (← buildExpr ctx key)
            | .mapKey _ :: _ => .error { message := s!"storage path state `{stateId}` map values support direct key access only" }
            | _ => .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
        | some _ =>
            let pathType ← resolveStoragePathTypeCtx ctx stateId path
            let feltBacked := storagePathFeltBacked ctx stateId pathType
            .ok <| .storagePathRead stateId (← buildStoragePath ctx path) feltBacked
        | none => .error { message := s!"unknown storage path state `{stateId}`" }
    | .storagePathWrite _ _ _ =>
        .error { message := "storage.path.write is a statement effect, not an expression" }
    | .storagePathAssignOp _ _ _ _ =>
        .error { message := "storage.path.assign_op is a statement effect, not an expression" }
    | .contextRead field => do
        .ok <| .contextRead (← mapContextField field)
    | .eventEmit _ _ =>
        .error { message := "event.emit is a statement effect, not an expression" }
    | .eventEmitIndexed _ _ _ =>
        .error { message := "event.emit.indexed is a statement effect, not an expression" }

  /-- Build `Lean.Compiler.Psy.StoragePathSegment` array from portable IR path segments. -/
  partial def buildStoragePath (ctx : BuildContext) : Array IR.StoragePathSegment → Except LowerError (Array Lean.Compiler.Psy.StoragePathSegment)
    | #[] => .ok #[]
    | arr => arr.mapM fun
      | .field fieldName => .ok <| .field fieldName
      | .index index => do .ok <| .index (← buildExpr ctx index)
      | .mapKey _ => .error { message := "storage path map key lowering is handled at the map state boundary" }

  /-- Check whether an assignment target's root is a storage state (vs a local). -/
  partial def isStorageTargetRoot (ctx : BuildContext) : IR.Expr → Bool
    | .local name => lookupState? ctx name |>.isSome
    | .field base _ => isStorageTargetRoot ctx base
    | .arrayGet base _ => isStorageTargetRoot ctx base
    | _ => false

  /-- Resolve the root storage form of an assignment target expression. -/
  partial def resolveStorageTargetRoot (ctx : BuildContext) : IR.Expr → Except LowerError Lean.Compiler.Psy.StorageTarget
    | .local stateId =>
        match lookupState? ctx stateId with
        | some _ => .ok <| .scalar stateId
        | none => .error { message := s!"unknown storage target `{stateId}`" }
    | .field base fieldName => do
        match ← resolveStorageTargetRoot ctx base with
        | .scalar stateId => .ok <| .structField stateId fieldName
        | .arrayIndex stateId index _ => .ok <| .arrayStructField stateId index fieldName
        | .path stateId segs _ => .ok <| .path stateId (segs.push (.field fieldName)) false
        | .structField stateId baseField =>
            .ok <| .path stateId #[.field baseField, .field fieldName] false
        | .arrayStructField stateId index baseField =>
            .ok <| .path stateId #[.index index, .field baseField, .field fieldName] false
    | .arrayGet base index => do
        match ← resolveStorageTargetRoot ctx base with
        | .scalar stateId =>
            let feltBacked := match lookupState? ctx stateId with
              | some { shape := .array .u32 _ true, .. } => true
              | _ => false
            .ok <| .arrayIndex stateId (← buildExpr ctx index) feltBacked
        | .arrayIndex stateId baseIndex feltBacked =>
            .ok <| .path stateId #[.index baseIndex, .index (← buildExpr ctx index)] feltBacked
        | .path stateId segs feltBacked =>
            .ok <| .path stateId (segs.push (.index (← buildExpr ctx index))) feltBacked
        | .structField _ _ => .error { message := "struct field is not an array assignment target" }
        | .arrayStructField _ _ _ => .error { message := "array struct field is not an array assignment target" }
    | _ => .error { message := "assignment target must be a local, array index, or field path" }
end

/-- Build a `Lean.Compiler.Psy.Stmt` from a portable IR `Effect` in statement position. -/
def buildEffectStmt (ctx : BuildContext) : IR.Effect → Except LowerError Lean.Compiler.Psy.Stmt
  | .storageScalarRead _ => .error { message := "storage.scalar.read must be used as an expression" }
  | .storageScalarWrite stateId value => do
      requireScalarStateCtx ctx stateId
      .ok <| .effect (.storageScalarWrite stateId (← buildExpr ctx value))
  | .storageScalarAssignOp stateId op value => do
      requireScalarStateCtx ctx stateId
      .ok <| .effect (.storageScalarAssignOp stateId (mapAssignOp op) (← buildExpr ctx value))
  | .storageMapContains _ _ => .error { message := "storage.map.contains must be used as an expression" }
  | .storageMapGet _ _ => .error { message := "storage.map.get must be used as an expression" }
  | .storageMapInsert stateId key value => do
      requireMapStateCtx ctx stateId
      .ok <| .effect (.storageMapInsert stateId (← buildExpr ctx key) (← buildExpr ctx value))
  | .storageMapSet stateId key value => do
      requireMapStateCtx ctx stateId
      .ok <| .effect (.storageMapSet stateId (← buildExpr ctx key) (← buildExpr ctx value))
  | .storageArrayRead _ _ => .error { message := "storage.array.read must be used as an expression" }
  | .storageArrayWrite stateId index value => do
      requireArrayStateCtx ctx stateId
      let feltBacked := match lookupState? ctx stateId with
        | some { shape := .array .u32 _ true, .. } => true
        | _ => false
      .ok <| .effect (.storageArrayWrite stateId (← buildExpr ctx index) (← buildExpr ctx value) feltBacked)
  | .storageArrayStructFieldRead _ _ _ => .error { message := "storage.array.struct.field.read must be used as an expression" }
  | .storageArrayStructFieldWrite stateId index fieldName value => do
      requireStructArrayStateCtx ctx stateId fieldName
      .ok <| .effect (.storageArrayStructFieldWrite stateId (← buildExpr ctx index) fieldName (← buildExpr ctx value))
  | .storageDynamicArrayPush _ _ => .error { message := "storage.dynamic.array.push is not supported by Psy IR v0" }
  | .storageDynamicArrayPop _ => .error { message := "storage.dynamic.array.pop is not supported by Psy IR v0" }
  | .memoryArraySet _ _ _ =>
      .error { message := "memory arrays are not supported by Psy IR v0" }
  | .storageStructFieldRead _ _ => .error { message := "storage.struct.field.read must be used as an expression" }
  | .storageStructFieldWrite stateId fieldName value => do
      requireStructScalarStateCtx ctx stateId fieldName
      .ok <| .effect (.storageStructFieldWrite stateId fieldName (← buildExpr ctx value))
  | .storagePathRead _ _ => .error { message := "storage.path.read must be used as an expression" }
  | .storagePathWrite stateId path value => do
      discard <| resolveStoragePathTypeCtx ctx stateId path
      match lookupState? ctx stateId with
      | some { shape := .map _ _ _, .. } =>
          match path.toList with
          | .mapKey key :: [] => do .ok <| .effect (.storageMapSet stateId (← buildExpr ctx key) (← buildExpr ctx value))
          | .mapKey _ :: _ => .error { message := s!"storage path state `{stateId}` map values support direct key access only" }
          | _ => .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
      | some _ =>
          let pathType ← resolveStoragePathTypeCtx ctx stateId path
          let feltBacked := storagePathFeltBacked ctx stateId pathType
          .ok <| .effect (.storagePathWrite stateId (← buildStoragePath ctx path) (← buildExpr ctx value) feltBacked)
      | none => .error { message := s!"unknown storage path state `{stateId}`" }
  | .storagePathAssignOp stateId path op value => do
      discard <| resolveStoragePathTypeCtx ctx stateId path
      let pathType ← resolveStoragePathTypeCtx ctx stateId path
      match lookupState? ctx stateId with
      | some { shape := .map _ _ _, .. } => .error { message := s!"storage path state `{stateId}` map values do not support compound assignment" }
      | some { shape := .array .u32 _ _, .. } =>
          if storagePathFeltBacked ctx stateId pathType then
            let segs ← buildStoragePath ctx path
            let target := Lean.Compiler.Psy.StorageTarget.path stateId segs false
            let read := Lean.Compiler.Psy.Expr.storagePathRead stateId segs true
            let rhs := Lean.Compiler.Psy.Expr.cast
              (Lean.Compiler.Psy.Expr.binary read ((mapAssignOp op).toBinaryOp) (← buildExpr ctx value))
              { text := psyFeltTypeName }
            .ok <| .assign target rhs
          else
            .ok <| .effect (.storagePathAssignOp stateId (← buildStoragePath ctx path) (mapAssignOp op) (← buildExpr ctx value))
      | some _ => do .ok <| .effect (.storagePathAssignOp stateId (← buildStoragePath ctx path) (mapAssignOp op) (← buildExpr ctx value))
      | none => .error { message := s!"unknown storage path state `{stateId}`" }
  | .contextRead _ => .error { message := "context.read must be used as an expression" }
  | .eventEmit name fields => do
      let fieldExprs ← fields.mapM fun (n, v) => do .ok (n, ← buildExpr ctx v)
      .ok <| .effect (.eventEmit name fieldExprs)
  | .eventEmitIndexed name _ _ => .error { message := s!"event `{name}` uses indexed fields, which are not supported by Psy IR v0" }

mutual
  /-- Collect else-if chain from a nested if/else body.

  Given the `elseBody` of an IR `.ifElse`, if the body is a single
  `.ifElse` statement, lift it into an `elseIfs` entry and recurse into its
  else body. This lets the printer emit `} else if cond {` instead of
  `} else { if cond { ... } else { ... } }`. -/
  partial def collectElseIfs (ctx : BuildContext) : Array IR.Statement → Except LowerError (Array (Lean.Compiler.Psy.Expr × Array Lean.Compiler.Psy.Stmt) × Array Lean.Compiler.Psy.Stmt)
    | #[.ifElse cond thenBody nestedElseBody] => do
        let condExpr ← buildExpr ctx cond
        let thenStmts ← buildBody ctx thenBody
        let (nestedElseIfs, finalElse) ← collectElseIfs ctx nestedElseBody
        .ok (#[(condExpr, thenStmts)] ++ nestedElseIfs, finalElse)
    | other => do
        let elseStmts ← buildBody ctx other
        .ok (#[], elseStmts)

  /-- Build a `Lean.Compiler.Psy.Stmt` from a portable IR `Statement`. -/
  partial def buildStmt (ctx : BuildContext) : IR.Statement → Except LowerError Lean.Compiler.Psy.Stmt
    | .letBind name type value => do
        .ok <| .letBind name (← typeName type) (← buildExpr ctx value)
    | .letMutBind name type value => do
        .ok <| .letMutBind name (← typeName type) (← buildExpr ctx value)
    | .assign target value => do
        if isStorageTargetRoot ctx target then
          do .ok <| .assign (← resolveStorageTargetRoot ctx target) (← buildExpr ctx value)
        else
          do .ok <| .localAssign (← buildExpr ctx target) (← buildExpr ctx value)
    | .assignOp target op value => do
        if isStorageTargetRoot ctx target then
          do .ok <| .assignOp (← resolveStorageTargetRoot ctx target) (mapAssignOp op) (← buildExpr ctx value)
        else
          do .ok <| .localAssignOp (← buildExpr ctx target) (mapAssignOp op) (← buildExpr ctx value)
    | .effect effect => buildEffectStmt ctx effect
    | .assert condition message _ => do .ok <| .assert (← buildExpr ctx condition) message
    | .assertEq lhs rhs message _ => do .ok <| .assertEq (← buildExpr ctx lhs) (← buildExpr ctx rhs) message
    | .release _ => .error { message := "release statements are not supported by Psy IR v0" }
    | .revert message => .ok <| .revert message
    | .revertWithError _ => .ok <| .revert "revertWithError"
    | .ifElse condition thenBody elseBody => do
        let condExpr ← buildExpr ctx condition
        let thenStmts ← buildBody ctx thenBody
        let (elseIfs, finalElse) ← collectElseIfs ctx elseBody
        .ok <| .ifElse condExpr thenStmts elseIfs finalElse
    | .boundedFor indexName start stopExclusive body => do
        if stopExclusive <= start then
          .error { message := s!"bounded loop `{indexName}` must have stop greater than start" }
        .ok <| .boundedFor indexName start stopExclusive (← buildBody ctx body)
    | .whileLoop _ _ =>
        .error { message := "while loops are not supported by Psy IR v0" }
    | .return value => do .ok <| .returnExpr (← buildExpr ctx value)

  /-- Build an array of `Lean.Compiler.Psy.Stmt` from a portable IR body. -/
  partial def buildBody (ctx : BuildContext) : Array IR.Statement → Except LowerError (Array Lean.Compiler.Psy.Stmt)
    | #[] => .ok #[]
    | arr => arr.mapM (buildStmt ctx)
end

/-- Build a `Lean.Compiler.Psy.Method` from a portable IR `Entrypoint`. -/
def buildMethod (ctx : BuildContext) (entrypoint : Entrypoint) : Except LowerError Lean.Compiler.Psy.Method := do
  let params ← entrypoint.params.mapM fun (n, t) => do
    let tn ← typeName t
    .ok (n, tn)
  let returns ← match entrypoint.returns with
    | .unit => .ok none
    | other => do .ok (some (← typeName other))
  let body ← buildBody ctx entrypoint.body
  .ok { name := entrypoint.name, params, returns, body }

/-- Build a `Lean.Compiler.Psy.StructDecl` from a portable IR struct declaration. -/
def buildStructDecl (decl : IR.StructDecl) : Except LowerError Lean.Compiler.Psy.StructDecl := do
  let fields ← decl.fields.mapM fun field => do
    let tn ← typeName field.type
    .ok { id := field.id, type := tn, isPublic := field.isPublic, isRef := field.isRef }
  .ok { name := decl.name, isPublic := decl.isPublic, deriveStorage := decl.deriveStorage, fields }

/-- Build a `Lean.Compiler.Psy.StateDecl` from a portable IR state declaration. -/
def buildStateDecl (state : IR.StateDecl) : Except LowerError Lean.Compiler.Psy.StateDecl := do
  match state.kind with
  | .scalar =>
      match state.type with
      | .structType _ => do .ok <| .structRef state.id (← typeName state.type)
      | _ => do .ok <| .scalar state.id (← typeName state.type)
  | .map keyType capacity => do .ok <| .map state.id (← typeName keyType) (← typeName state.type) capacity
  | .array length =>
      let feltBacked := state.type == .u32
      .ok <| .array state.id (← typeName state.type) length feltBacked
  | .dynamicArray =>
      .error { message := s!"state `{state.id}` is storage.dynamicArray; Psy IR v0 does not lower portable dynamic array storage" }


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
        .error { message := s!"state `{state.id}` has unsupported Psy IR v0 type `{other.name}`" }
    | .map .hash capacity, .hash =>
        if capacity == 0 then
          .error { message := s!"map state `{state.id}` must have non-zero capacity" }
        else
          pure ()
    | .map keyType _, valueType =>
        .error { message := s!"map state `{state.id}` has unsupported Psy IR v0 type Map<{keyType.name}, {valueType.name}>; only Map<Hash, Hash, N> is supported" }
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

/-- Build a `Lean.Compiler.Psy.Module` from a portable IR `Module` and its
semantic plan. The plan carries the test body, storage layout, and other
resolved shapes; the builder only folds IR into the AST. -/

def buildModuleWithPlan (module : Module) (plan : ProofForge.Backend.Psy.Plan.PsyModulePlan) : Except LowerError Lean.Compiler.Psy.Module := do
  let ctx := { module, layout := plan.storage }
  let structs ← module.structs.mapM buildStructDecl
  let state ← module.state.mapM buildStateDecl
  let methods ← module.entrypoints.mapM (buildMethod ctx)
  let headerComment := s!"// Generated by ProofForge from the portable {module.name} IR.\n// This is Psy source intended for the official Dargo/Psy compiler toolchain."
  .ok {
    name := module.name,
    headerComment,
    structs,
    contractName := module.name,
    state,
    refName := ProofForge.Backend.Psy.Plan.capitalizedRefName module,
    methods,
    test := { name := plan.test.functionName, body := plan.test.bodyLines }
  }

/-- Build a `Lean.Compiler.Psy.Module` from a portable IR `Module`. -/
def buildModule (module : Module) : Except LowerError Lean.Compiler.Psy.Module := do
  match ProofForge.Backend.Psy.Plan.buildModulePlan module with
  | .ok plan => buildModuleWithPlan module plan
  | .error err => .error { message := err.message }

/-- Render a portable IR `Module` to `.psy` source text.

This is the public entrypoint. It validates the module, builds the semantic
plan, lowers the IR + plan to a `Lean.Compiler.Psy.Module` AST, and renders
the AST to source text via `Lean.Compiler.Psy.Printer.module`. -/
def renderModule (module : Module) : Except LowerError String := do
  validateCapabilities module
  validateIdentifiers module
  validateStructs module
  validateEntrypoints module
  validateState module
  validateEntrypointBodies module
  let plan ← match ProofForge.Backend.Psy.Plan.buildModulePlan module with
    | .ok plan => .ok plan
    | .error err => .error { message := err.message }
  let ast ← buildModuleWithPlan module plan
  .ok (Lean.Compiler.Psy.Printer.module ast)

end ProofForge.Backend.Psy.IR
