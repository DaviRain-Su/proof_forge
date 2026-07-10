import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.ToYul
import ProofForge.Backend.Evm.Validate
import ProofForge.Backend.Evm.IR.Validate
import ProofForge.Backend.Evm.Lower
import ProofForge.IR.Contract
import ProofForge.Compiler.Yul.AST
import ProofForge.Compiler.Yul.Printer

/-! # EVM IR expression and effect lowering

Expression, effect-expression, and single effect-statement lowering from
ProofForge IR plans into Yul AST nodes. Statement and module assembly remain in
`ProofForge.Backend.Evm.IR`. -/

namespace ProofForge.Backend.Evm.IR

open ProofForge.Backend.Evm.Plan
open ProofForge.Backend.Evm.Validate (needsCheckedArithmetic exprUsesCheckedArithmetic)
open ProofForge.IR
open ProofForge.Backend.Evm.Validate
open ProofForge.Backend.Evm.ToYul
open ProofForge.Backend.Evm.Lower
open ProofForge.Backend.Evm.Plan

mutual
  partial def lowerStorageSlotPlanExpr
      (module : Module)
      (env : TypeEnv)
      (plan : ProofForge.Backend.Evm.Plan.StorageSlotPlan) :
      Except LowerError Lean.Compiler.Yul.Expr :=
    ProofForge.Backend.Evm.ToYul.storageSlotExpr
      toYulError
      (fun expr => lowerExpr module env expr)
      plan

  partial def lowerScalarStorageSlotExpr
      (module : Module)
      (env : TypeEnv)
      (stateId : String) : Except LowerError Lean.Compiler.Yul.Expr := do
    let plan ← lowerPlan <| ProofForge.Backend.Evm.Plan.scalarSlotPlan module stateId
    lowerStorageSlotPlanExpr module env plan

  partial def lowerScalarStorageReadExpr
      (module : Module)
      (env : TypeEnv)
      (stateId : String) : Except LowerError Lean.Compiler.Yul.Expr := do
    let storageSlot ← lowerScalarStorageSlotExpr module env stateId
    let (byteOffset, byteWidth) ← scalarStatePacking module stateId
    if byteWidth >= 32 || byteOffset == 0 && byteWidth == 32 then
      .ok (Lean.Compiler.Yul.builtin "sload" #[storageSlot])
    else
      let shiftBits := byteOffset * 8
      let mask := (2^(byteWidth * 8 : Nat)) - 1
      .ok (Lean.Compiler.Yul.builtin "and" #[
        Lean.Compiler.Yul.builtin "shr" #[
          Lean.Compiler.Yul.Expr.num shiftBits,
          Lean.Compiler.Yul.builtin "sload" #[storageSlot]
        ],
        Lean.Compiler.Yul.Expr.num mask
      ])

  partial def lowerMapPathValueSlotExpr
      (module : Module)
      (env : TypeEnv)
      (stateId : String)
      (keys : Array ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr := do
    discard <| requireStorageMapState module stateId
    if keys.isEmpty then
      .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
    let plan ← lowerPlan <| ProofForge.Backend.Evm.Plan.mapValueSlotPlan module stateId keys
    lowerStorageSlotPlanExpr module env plan

  partial def lowerMapPathPresenceSlotExpr
      (module : Module)
      (env : TypeEnv)
      (stateId : String)
      (keys : Array ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr := do
    discard <| requireStorageMapState module stateId
    if keys.isEmpty then
      .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
    let plan ← lowerPlan <| ProofForge.Backend.Evm.Plan.mapPresenceSlotPlan module stateId keys
    lowerStorageSlotPlanExpr module env plan

  partial def lowerDynamicArraySlotExpr
      (module : Module)
      (env : TypeEnv)
      (stateId : String)
      (index : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr := do
    discard <| lowerPlan <| ProofForge.Backend.Evm.Plan.requireDynamicArrayState module stateId
    let plan ← lowerPlan <| ProofForge.Backend.Evm.Plan.dynamicArraySlotPlan module stateId index
    lowerStorageSlotPlanExpr module env plan

  partial def lowerStructFieldSlotExpr
      (module : Module)
      (stateId fieldName : String) : Except LowerError Lean.Compiler.Yul.Expr := do
    let (slot, _) ← requireStructStateField module stateId fieldName
    .ok (slotExpr slot)

  partial def lowerStructFieldReadExpr
      (module : Module)
      (stateId fieldName : String) : Except LowerError Lean.Compiler.Yul.Expr := do
    let target ← lowerPlan <|
      ProofForge.Backend.Evm.Plan.structFieldReadTargetPlan module stateId fieldName
    ProofForge.Backend.Evm.ToYul.structFieldReadTargetExpr
      toYulError
      (fun expr => lowerExpr module #[] expr)
      target

  partial def lowerStoragePathReadExprTarget
      (module : Module)
      (env : TypeEnv)
      (stateId : String)
      (path : Array StoragePathSegment) : Except LowerError Lean.Compiler.Yul.Expr := do
    let plannedPath ←
      match ProofForge.Backend.Evm.Lower.buildStoragePathPlan module (toValidateTypeEnv env) path with
      | .ok plan => .ok plan
      | .error err => .error { message := err.message }
    let slot ← lowerPlan <|
      ProofForge.Backend.Evm.Plan.storagePathReadExprSlotPlan module stateId plannedPath
    ProofForge.Backend.Evm.ToYul.storagePathReadExprFromExprPlan
      toYulError
      (lowerExprPlanExpr module env)
      slot

  partial def validateFixedArrayIndexExprPath
      (module : Module)
      (env : TypeEnv)
      (context : String)
      (type : ValueType)
      (path : Array ProofForge.IR.Expr) : Except LowerError (Array Nat × ValueType) := do
    match path.toList with
    | [] => .ok (#[], type)
    | index :: rest =>
        match type with
        | .fixedArray elementType length => do
            ensureArrayIndexType context (← inferExprType module env index)
            match literalArrayIndex? index with
            | some indexValue => ensureFixedArrayIndexInBounds context indexValue length
            | none => pure ()
            let (nestedLengths, leafType) ← validateFixedArrayIndexExprPath module env context elementType rest.toArray
            .ok (#[length] ++ nestedLengths, leafType)
        | other =>
            .error { message := s!"{context} target expected `Array`, got `{other.name}`" }

  partial def lowerDynamicNestedLocalFixedArrayGetExpr
      (module : Module)
      (env : TypeEnv)
      (name : String)
      (binding : LocalBinding)
      (path : Array ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr := do
    let (lengths, leafType) ← validateFixedArrayIndexExprPath module env "fixed array index" binding.type path
    match leafType with
    | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => pure ()
    | .structType _ =>
        .error {
          message := s!"fixed array indexing local `{name}` returns struct values; IR EVM v0 requires field access such as array[index].field"
        }
    | .unit | .fixedArray _ _ | .bytes | .string | .array _ =>
        .error {
          message := s!"fixed array indexing local `{name}` has unsupported EVM IR v0 element type `{leafType.name}`"
        }
    let leafPaths := nestedLocalArrayLeafPaths lengths
    let mut args : Array Lean.Compiler.Yul.Expr := #[]
    for index in path do
      args := args.push (← lowerExpr module env index)
    for leafPath in leafPaths do
      args := args.push (Lean.Compiler.Yul.Expr.id (arrayLocalPathName name leafPath))
    .ok (Lean.Compiler.Yul.call (nestedLocalArrayGetFunctionName lengths) args)

  partial def lowerLocalFixedArrayGetExpr
      (module : Module)
      (env : TypeEnv)
      (array index : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr := do
    let fullExpr := ProofForge.IR.Expr.arrayGet array index
    let planned ←
      match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) fullExpr with
      | .ok plan => .ok plan
      | .error err => .error { message := err.message }
    match planned with
    | .localArrayGet .. =>
        lowerExprPlanExpr module env planned
    | .arrayGet (.arrayLit ..) _ =>
        lowerExprPlanExpr module env planned
    | _ =>
        match collectLocalArrayGetPath fullExpr with
        | some (name, path) =>
            if path.size > 1 && arrayIndexPathHasDynamic path then
              let some binding := findLocal? env name
                | .error { message := s!"unknown local `{name}`" }
              lowerDynamicNestedLocalFixedArrayGetExpr module env name binding path
            else
              match collectStaticLocalArrayGetPath fullExpr with
              | some (name, path) => do
                  let some binding := findLocal? env name
                    | .error { message := s!"unknown local `{name}`" }
                  let elementType ← fixedArrayPathType "fixed array index" binding.type path
                  match elementType with
                  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address =>
                      .ok (Lean.Compiler.Yul.Expr.id (arrayLocalPathName name path))
                  | .structType _ =>
                      .error {
                        message := s!"fixed array indexing local `{name}` returns struct values; IR EVM v0 requires field access such as array[index].field"
                      }
                  | .unit | .fixedArray _ _ | .bytes | .string | .array _ =>
                      .error {
                        message := s!"fixed array indexing local `{name}` has unsupported EVM IR v0 element type `{elementType.name}`"
                      }
              | none =>
                  lowerLocalFixedArrayGetExprFallback module env array index
        | none =>
            lowerLocalFixedArrayGetExprFallback module env array index

  partial def lowerLocalFixedArrayGetExprFallback
      (module : Module)
      (env : TypeEnv)
      (array index : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr :=
    match array with
    | .local name => do
        let (elementType, length) ← requireLocalFixedArray "fixed array indexing" env name
        match elementType with
        | .structType _ =>
            .error {
              message := s!"fixed array indexing local `{name}` returns struct values; IR EVM v0 requires field access such as array[index].field"
            }
        | .unit | .fixedArray _ _ | .bytes | .string | .array _ =>
            .error {
              message := s!"fixed array indexing local `{name}` has unsupported EVM IR v0 element type `{elementType.name}`"
            }
        | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => pure ()
        match literalArrayIndex? index with
        | some indexValue => do
            ensureFixedArrayIndexInBounds "fixed array index" indexValue length
            .ok (Lean.Compiler.Yul.Expr.id (arrayLocalElementName name indexValue))
        | none => do
            let mut values : Array Lean.Compiler.Yul.Expr := #[]
            for _h : idx in [0:length] do
              values := values.push (Lean.Compiler.Yul.Expr.id (arrayLocalElementName name idx))
            .ok (Lean.Compiler.Yul.call (localArrayGetFunctionName length) (#[← lowerExpr module env index] ++ values))
    | .arrayLit _ _ => do
        let arrayPlan ←
          match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) array with
          | .ok plan => .ok plan
          | .error err => .error { message := err.message }
        let indexPlan ←
          match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) index with
          | .ok plan => .ok plan
          | .error err => .error { message := err.message }
        lowerExprPlanExpr module env (.arrayGet arrayPlan indexPlan)
    | _ =>
        .error {
          message := "fixed array indexing in IR EVM v0 supports local fixed-array values or array literals only"
        }

  partial def lowerNestedLocalStructFieldGetExpr
      (module : Module)
      (env : TypeEnv)
      (name : String)
      (binding : LocalBinding)
      (path : Array ProofForge.IR.Expr)
      (fieldName : String) : Except LowerError Lean.Compiler.Yul.Expr := do
    let (lengths, leafType) ← validateFixedArrayIndexExprPath module env "struct field fixed-array index" binding.type path
    match leafType with
    | .structType typeName => do
        discard <| ensureLocalFlatStructType module s!"struct field access local `{name}` fixed-array leaf" typeName
        let fieldType ← structFieldType module typeName fieldName
        ensureStructLocalFieldType typeName fieldName fieldType
    | other =>
        .error {
          message := s!"struct field access local `{name}` fixed-array leaf expected flat struct, got `{other.name}`"
        }
    lowerExprPlanExpr module env <|
      .structField
        (.localArrayGet name
          (← path.mapM fun index =>
            match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) index with
            | .ok plan => .ok plan
            | .error err => .error { message := err.message })
          lengths)
        fieldName

  partial def lowerLocalStructFieldExpr
      (module : Module)
      (env : TypeEnv)
      (base : ProofForge.IR.Expr)
      (fieldName : String) : Except LowerError Lean.Compiler.Yul.Expr := do
    let fullExpr := ProofForge.IR.Expr.field base fieldName
    let planned ←
      match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) fullExpr with
      | .ok plan => .ok plan
      | .error err => .error { message := err.message }
    match planned with
    | .structField (.local _) _ | .structField (.structLit ..) _
    | .structField (.localArrayGet ..) _ =>
        lowerExprPlanExpr module env planned
    | _ =>
        match base with
        | .effect (.storageScalarRead stateId) =>
            lowerStructFieldReadExpr module stateId fieldName
        | _ =>
            match collectLocalArrayGetPath base with
            | some (name, path) =>
                if path.size > 1 then do
                  let some binding := findLocal? env name
                    | .error { message := s!"unknown local `{name}`" }
                  lowerNestedLocalStructFieldGetExpr module env name binding path fieldName
                else
                  .error {
                    message := "struct field access in IR EVM v0 supports local struct values, local struct-array values, nested local fixed-array struct leaves, or struct literals only"
                  }
            | none =>
                .error {
                  message := "struct field access in IR EVM v0 supports local struct values, local struct-array values, nested local fixed-array struct leaves, or struct literals only"
                }

  partial def localAbiStructFieldIds
      (module : Module)
      (context typeName : String) : Except LowerError (Array String) := do
    lowerValidate <|
      ProofForge.Backend.Evm.Lower.localAbiStructFieldIds module context typeName

  partial def localAbiStructFields
      (module : Module)
      (context typeName : String) : Except LowerError (Array (String × ValueType)) := do
    lowerValidate <|
      ProofForge.Backend.Evm.Lower.localAbiStructFields module context typeName

  partial def lowerLocalAbiWords
      (module : Module)
      (env : TypeEnv)
      (context name : String)
      (expectedType : ValueType) : Except LowerError (Array Lean.Compiler.Yul.Expr) := do
    let plans ←
      lowerValidate <|
        ProofForge.Backend.Evm.Lower.localAbiWordPlans
          module
          (toValidateTypeEnv env)
          context
          name
          expectedType
    plans.mapM (lowerExprPlanExpr module env)

  partial def lowerStorageArrayAbiWords
      (module : Module)
      (context stateId : String)
      (elementType : ValueType)
      (length : Nat) : Except LowerError (Array Lean.Compiler.Yul.Expr) := do
    let plans ←
      lowerValidate <|
        ProofForge.Backend.Evm.Lower.storageAbiWordPlans
          module
          context
          stateId
          (.fixedArray elementType length)
    plans.mapM (lowerExprPlanExpr module #[])

  partial def lowerExprThroughPlan
      (module : Module)
      (env : TypeEnv)
      (expr : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr := do
    let plan ←
      match ProofForge.Backend.Evm.Lower.buildExpressionExprPlan module (toValidateTypeEnv env) expr with
      | .ok plan => .ok plan
      | .error err => .error { message := err.message }
    lowerExprPlanExpr module env plan

  partial def lowerExpr (module : Module) (env : TypeEnv) : ProofForge.IR.Expr → Except LowerError Lean.Compiler.Yul.Expr
    | .literal value => do
        lowerExprThroughPlan module env (.literal value)
    | .local name => do
        lowerExprThroughPlan module env (.local name)
    | .arrayLit _ _ =>
        .error { message := "fixed array literals must be consumed by a fixed array local binding or literal index in IR EVM v0" }
    | .arrayGet array index =>
        lowerLocalFixedArrayGetExpr module env array index
    | .memoryArrayNew elementType length => do
        let lengthPlan ←
          match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) (.memoryArrayNew elementType length) with
          | .ok plan => .ok plan
          | .error err => .error { message := err.message }
        lowerExprPlanExpr module env lengthPlan
    | .memoryArrayLength array => do
        let arrayPlan ←
          match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) (.memoryArrayLength array) with
          | .ok plan => .ok plan
          | .error err => .error { message := err.message }
        lowerExprPlanExpr module env arrayPlan
    | .memoryArrayGet array index => do
        let getPlan ←
          match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) (.memoryArrayGet array index) with
          | .ok plan => .ok plan
          | .error err => .error { message := err.message }
        lowerExprPlanExpr module env getPlan
    | .structLit _ _ =>
        .error { message := "struct literals must be consumed by a struct local binding or field access in IR EVM v0" }
    | .field base fieldName =>
        lowerLocalStructFieldExpr module env base fieldName
    | .add lhs rhs oc => do
        lowerExprThroughPlan module env (.add lhs rhs oc)
    | .sub lhs rhs oc => do
        lowerExprThroughPlan module env (.sub lhs rhs oc)
    | .mul lhs rhs oc => do
        lowerExprThroughPlan module env (.mul lhs rhs oc)
    | .div lhs rhs => do
        lowerExprThroughPlan module env (.div lhs rhs)
    | .mod lhs rhs => do
        lowerExprThroughPlan module env (.mod lhs rhs)
    | .pow lhs rhs => do
        lowerExprThroughPlan module env (.pow lhs rhs)
    | .bitAnd lhs rhs => do
        lowerExprThroughPlan module env (.bitAnd lhs rhs)
    | .bitOr lhs rhs => do
        lowerExprThroughPlan module env (.bitOr lhs rhs)
    | .bitXor lhs rhs => do
        lowerExprThroughPlan module env (.bitXor lhs rhs)
    | .shiftLeft lhs rhs => do
        lowerExprThroughPlan module env (.shiftLeft lhs rhs)
    | .shiftRight lhs rhs => do
        lowerExprThroughPlan module env (.shiftRight lhs rhs)
    | .cast value targetType => do
        lowerExprThroughPlan module env (.cast value targetType)
    | .eq lhs rhs => do
        lowerExprThroughPlan module env (.eq lhs rhs)
    | .ne lhs rhs => do
        lowerExprThroughPlan module env (.ne lhs rhs)
    | .lt lhs rhs => do
        lowerExprThroughPlan module env (.lt lhs rhs)
    | .le lhs rhs => do
        lowerExprThroughPlan module env (.le lhs rhs)
    | .gt lhs rhs => do
        lowerExprThroughPlan module env (.gt lhs rhs)
    | .ge lhs rhs => do
        lowerExprThroughPlan module env (.ge lhs rhs)
    | .boolAnd lhs rhs => do
        lowerExprThroughPlan module env (.boolAnd lhs rhs)
    | .boolOr lhs rhs => do
        lowerExprThroughPlan module env (.boolOr lhs rhs)
    | .boolNot value => do
        lowerExprThroughPlan module env (.boolNot value)
    | .hashValue a b c d => do
        lowerExprThroughPlan module env (.hashValue a b c d)
    | .hash preimage => do
        lowerExprThroughPlan module env (.hash preimage)
    | .hashTwoToOne lhs rhs => do
        lowerExprThroughPlan module env (.hashTwoToOne lhs rhs)
    | .ecrecover a b c d => do
        lowerExprThroughPlan module env (.ecrecover a b c d)
    | .eip712PermitDigest a b c d e f => do
        lowerExprThroughPlan module env (.eip712PermitDigest a b c d e f)
    | .crosscallAbiPacked target sel stores argsSize outSize dynLenOffset? dynLen?
        dynTargetOffsets dynTargets => do
        lowerExprThroughPlan module env
          (.crosscallAbiPacked target sel stores argsSize outSize dynLenOffset? dynLen?
            dynTargetOffsets dynTargets)
    | .nativeValue =>
        lowerExprThroughPlan module env .nativeValue
    | .crosscallInvoke target methodId args => do
        lowerExprThroughPlan module env (.crosscallInvoke target methodId args)
    | .crosscallInvokeTyped target methodId args returnType => do
        lowerExprThroughPlan module env (.crosscallInvokeTyped target methodId args returnType)
    | .crosscallInvokeValueTyped target methodId callValue args returnType => do
        lowerExprThroughPlan module env (.crosscallInvokeValueTyped target methodId callValue args returnType)
    | .crosscallInvokeStaticTyped target methodId args returnType => do
        lowerExprThroughPlan module env (.crosscallInvokeStaticTyped target methodId args returnType)
    | .crosscallInvokeDelegateTyped target methodId args returnType => do
        lowerExprThroughPlan module env (.crosscallInvokeDelegateTyped target methodId args returnType)
    | .crosscallCreate callValue initCodeHex => do
        lowerExprThroughPlan module env (.crosscallCreate callValue initCodeHex)
    | .crosscallCreate2 callValue salt initCodeHex => do
        lowerExprThroughPlan module env (.crosscallCreate2 callValue salt initCodeHex)
    | .crosscallNamed _ _ _ _
    | .nearPromiseThen _ _ _ _
    | .nearCrosscallInvokePool _ _ _ _
    | .nearPromiseResultsCount
    | .nearPromiseResultStatus _
    | .nearPromiseResultU64 _ =>
        .error { message := "NEAR promise API is not supported on EVM" }
    | .effect effect => lowerEffectExpr module env effect

  partial def lowerEffectExprThroughPlan
      (module : Module)
      (env : TypeEnv)
      (effect : Effect) : Except LowerError Lean.Compiler.Yul.Expr := do
    let plan ←
      match ProofForge.Backend.Evm.Lower.buildEffectPlan module (toValidateTypeEnv env) effect with
      | .ok plan => .ok plan
      | .error err => .error { message := err.message }
    lowerPlanEffectExpr module env plan

  partial def lowerEffectExpr (module : Module) (env : TypeEnv) : Effect → Except LowerError Lean.Compiler.Yul.Expr
    | .storageScalarRead stateId => do
        lowerEffectExprThroughPlan module env (.storageScalarRead stateId)
    | .storageScalarWrite _ _ =>
        .error { message := "storage.scalar.write is a statement effect, not an expression" }
    | .storageScalarAssignOp _ _ _ =>
        .error { message := "storage.scalar.assign_op is a statement effect, not an expression" }
    | .storageMapContains stateId key =>
        lowerEffectExprThroughPlan module env (.storageMapContains stateId key)
    | .storageMapGet stateId key =>
        lowerEffectExprThroughPlan module env (.storageMapGet stateId key)
    | .storageMapInsert stateId key value =>
        lowerEffectExprThroughPlan module env (.storageMapInsert stateId key value)
    | .storageMapSet stateId key value =>
        lowerEffectExprThroughPlan module env (.storageMapSet stateId key value)
    | .storageArrayRead stateId index =>
        lowerEffectExprThroughPlan module env (.storageArrayRead stateId index)
    | .storageArrayWrite _ _ _ =>
        .error { message := "storage.array.write is a statement effect, not an expression" }
    | .memoryArraySet _ _ _ =>
        .error { message := "memory.array.set is a statement effect, not an expression" }
    | .storageArrayStructFieldRead stateId index fieldName =>
        lowerEffectExprThroughPlan module env (.storageArrayStructFieldRead stateId index fieldName)
    | .storageArrayStructFieldWrite _ _ _ _ =>
        .error { message := "storage.array.struct.field.write is a statement effect, not an expression" }
    | .storageDynamicArrayPush _ _ =>
        .error { message := "storage.dynamic.array.push is a statement effect, not an expression" }
    | .storageDynamicArrayPop _ =>
        .error { message := "storage.dynamic.array.pop is a statement effect, not an expression" }
    | .storageStructFieldRead stateId fieldName =>
        lowerEffectExprThroughPlan module env (.storageStructFieldRead stateId fieldName)
    | .storageStructFieldWrite _ _ _ =>
        .error { message := "storage.struct.field.write is a statement effect, not an expression" }
    | .storagePathRead stateId path =>
        lowerEffectExprThroughPlan module env (.storagePathRead stateId path)
    | .storagePathWrite _ _ _ =>
        .error { message := "storage.path.write is a statement effect, not an expression" }
    | .storagePathAssignOp _ _ _ _ =>
        .error { message := "storage.path.assign_op is a statement effect, not an expression" }
    | .contextRead field =>
        lowerEffectExprThroughPlan module env (.contextRead field)
    | .eventEmit _ _ =>
        .error { message := "event.emit is a statement effect, not an expression" }
    | .eventEmitIndexed _ _ _ =>
        .error { message := "event.emit.indexed is a statement effect, not an expression" }
    | .checkErc721Received _ _ _ _ =>
        .error { message := "checkErc721Received is a statement effect, not an expression" }
    | .checkErc1155Received _ _ _ _ _ =>
        .error { message := "checkErc1155Received is a statement effect, not an expression" }
    | .checkErc1155BatchReceived _ _ _ _ _ _ _ =>
        .error { message := "checkErc1155BatchReceived is EVM-only (PF-P2-02); not an expression on host" }

  partial def lowerPlanEffectExpr
      (module : Module)
      (env : TypeEnv) :
      ProofForge.Backend.Evm.Plan.EffectPlan → Except LowerError Lean.Compiler.Yul.Expr
    | .storageScalarRead stateId => do
        match ← scalarStateType module stateId with
        | .structType _ =>
            .error {
              message := s!"storage.scalar.read for struct state `{stateId}` must be consumed by a struct local binding, struct field access, or struct return in IR EVM v0"
            }
        | _ => pure ()
        match ProofForge.Backend.Evm.Lower.scalarStorageTargetPlan? module stateId with
        | some target =>
            ProofForge.Backend.Evm.ToYul.scalarStorageTargetReadExpr
              toYulError
              (fun expr => lowerExpr module env expr)
              target
        | none =>
            lowerScalarStorageReadExpr module env stateId
    | .storageScalarReadTarget target =>
        ProofForge.Backend.Evm.ToYul.scalarStorageTargetReadExpr
          toYulError
          (fun expr => lowerExpr module env expr)
          target
    | .storageScalarWriteTarget _ _ =>
        .error { message := "storage.scalar.write is a statement effect, not an expression" }
    | .storageScalarAssignOpTarget _ _ _ =>
        .error { message := "storage.scalar.assign_op is a statement effect, not an expression" }
    | .contextRead field =>
        ProofForge.Backend.Evm.ToYul.contextExprPlan
          (fun exprPlan => lowerExprPlanExpr module env exprPlan)
          field
    | .storageMapContains stateId key => do
        match ProofForge.Backend.Evm.Lower.mapReadTargetPlan? module stateId with
        | some target =>
            ProofForge.Backend.Evm.ToYul.mapContainsTargetExpr
              toYulError
              (fun expr => lowerExpr module env expr)
              (lowerPlanEffectExpr module env)
              target
              key
        | none =>
            let (rootSlot, _, _) ← requireStorageMapState module stateId
            ProofForge.Backend.Evm.ToYul.mapContainsExpr
              toYulError
              (fun expr => lowerExpr module env expr)
              (lowerPlanEffectExpr module env)
              rootSlot
              key
    | .storageMapContainsTarget target key =>
        ProofForge.Backend.Evm.ToYul.mapContainsTargetExpr
          toYulError
          (fun expr => lowerExpr module env expr)
          (lowerPlanEffectExpr module env)
          target
          key
    | .storageMapGet stateId key => do
        match ProofForge.Backend.Evm.Lower.mapReadTargetPlan? module stateId with
        | some target =>
            ProofForge.Backend.Evm.ToYul.mapGetTargetExpr
              toYulError
              (fun expr => lowerExpr module env expr)
              (lowerPlanEffectExpr module env)
              target
              key
        | none =>
            let (rootSlot, _, _) ← requireStorageMapState module stateId
            ProofForge.Backend.Evm.ToYul.mapGetExpr
              toYulError
              (fun expr => lowerExpr module env expr)
              (lowerPlanEffectExpr module env)
              rootSlot
              key
    | .storageMapGetTarget target key =>
        ProofForge.Backend.Evm.ToYul.mapGetTargetExpr
          toYulError
          (fun expr => lowerExpr module env expr)
          (lowerPlanEffectExpr module env)
          target
          key
    | .storageMapInsertTarget target key value
    | .storageMapSetTarget target key value =>
        ProofForge.Backend.Evm.ToYul.mapSetReturnTargetExpr
          toYulError
          (fun expr => lowerExpr module env expr)
          (lowerPlanEffectExpr module env)
          target
          key
          value
    | .storageArrayRead stateId index => do
        match ProofForge.Backend.Evm.Lower.arrayReadTargetPlan? module stateId with
        | some target =>
            ProofForge.Backend.Evm.ToYul.arrayReadTargetExpr
              toYulError
              (fun expr => lowerExpr module env expr)
              (lowerPlanEffectExpr module env)
              target
              index
        | none =>
            let (rootSlot, length, _) ← requireStorageArrayState module stateId
            ProofForge.Backend.Evm.ToYul.arrayReadExpr
              toYulError
              (fun expr => lowerExpr module env expr)
              (lowerPlanEffectExpr module env)
              rootSlot
              length
              index
    | .storageArrayReadTarget target index =>
        ProofForge.Backend.Evm.ToYul.arrayReadTargetExpr
          toYulError
          (fun expr => lowerExpr module env expr)
          (lowerPlanEffectExpr module env)
          target
          index
    | .storageStructFieldRead stateId fieldName => do
        match ProofForge.Backend.Evm.Lower.structFieldReadTargetPlan? module stateId fieldName with
        | some target =>
            ProofForge.Backend.Evm.ToYul.structFieldReadTargetExpr
              toYulError
              (fun expr => lowerExpr module env expr)
              target
        | none =>
            let (slot, _) ← requireStructStateField module stateId fieldName
            .ok (ProofForge.Backend.Evm.ToYul.structFieldReadExpr slot)
    | .storageStructFieldReadTarget target =>
        ProofForge.Backend.Evm.ToYul.structFieldReadTargetExpr
          toYulError
          (fun expr => lowerExpr module env expr)
          target
    | .storageArrayStructFieldRead stateId index fieldName => do
        match ProofForge.Backend.Evm.Lower.structArrayFieldReadTargetPlan? module stateId fieldName with
        | some target =>
            ProofForge.Backend.Evm.ToYul.structArrayFieldReadTargetExpr
              toYulError
              (fun expr => lowerExpr module env expr)
              (lowerPlanEffectExpr module env)
              target
              index
        | none =>
            let (rootSlot, length, fieldCount, fieldOffset, _) ← requireStructArrayStateField module stateId fieldName
            ProofForge.Backend.Evm.ToYul.structArrayFieldReadExpr
              toYulError
              (fun expr => lowerExpr module env expr)
              (lowerPlanEffectExpr module env)
              rootSlot
              length
              fieldCount
              fieldOffset
              index
    | .storageArrayStructFieldReadTarget target index =>
        ProofForge.Backend.Evm.ToYul.structArrayFieldReadTargetExpr
          toYulError
          (fun expr => lowerExpr module env expr)
          (lowerPlanEffectExpr module env)
          target
          index
    | .storagePathRead stateId path =>
        lowerStoragePathReadExprTarget module env stateId path
    | .storagePathReadTarget slot =>
        ProofForge.Backend.Evm.ToYul.storagePathReadExprFromPlan
          toYulError
          (fun expr => lowerExpr module env expr)
          slot
    | .storagePathReadExprTarget slot =>
        ProofForge.Backend.Evm.ToYul.storagePathReadExprFromExprPlan
          toYulError
          (lowerExprPlanExpr module env)
          slot
    | _ =>
        .error { message := "EVM ExprPlan-to-Yul scalar lowering does not support this effect plan yet" }

  partial def lowerExprPlanExpr
      (module : Module)
      (env : TypeEnv)
      (plan : ProofForge.Backend.Evm.Plan.ExprPlan) :
      Except LowerError Lean.Compiler.Yul.Expr := do
    match plan with
    | .crosscall mode target methodId callValue? args returnType => do
        ProofForge.Backend.Evm.ToYul.crosscallExpandedExprPlanExpr
          toYulError
          (lowerExprPlanExpr module env)
          mode
          target
          methodId
          callValue?
          args
          returnType
    | _ =>
        ProofForge.Backend.Evm.ToYul.exprPlanExpr
          toYulError
          (fun expr => lowerExpr module env expr)
          (lowerPlanEffectExpr module env)
          plan
end

def lowerCrosscallReturnAssignmentPlan
    (module : Module)
    (env : TypeEnv)
    (plan : ProofForge.Backend.Evm.Plan.CrosscallReturnAssignmentPlan) :
    Except LowerError Lean.Compiler.Yul.Statement := do
  ProofForge.Backend.Evm.ToYul.crosscallAggregateReturnAssignmentExpandedPlanStatement
    toYulError
    (lowerExprPlanExpr module env)
    plan

def lowerAbiWordPlanExprs
    (module : Module)
    (env : TypeEnv)
    (plans : Array ProofForge.Backend.Evm.Plan.ExprPlan) :
    Except LowerError (Array Lean.Compiler.Yul.Expr) :=
  plans.mapM (lowerExprPlanExpr module env)

def lowerReturnValueWordPlan
    (module : Module)
    (env : TypeEnv)
    (entrypointName : String)
    (plan : ProofForge.Backend.Evm.Plan.ReturnValueWordPlan) :
    Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  let context := s!"entrypoint `{entrypointName}` return value"
  let wordPlans ←
    lowerValidate <|
      ProofForge.Backend.Evm.Lower.returnValueWordPlans
        module
        (toValidateTypeEnv env)
        context
        plan
  let words ← lowerAbiWordPlanExprs module env wordPlans
  ProofForge.Backend.Evm.ToYul.returnValueWordAssignments
    toYulError
    context
    plan.returns
    words

mutual
partial def exprSupportsPlanScalarYul : ProofForge.IR.Expr → Bool
  | .literal _ => true
  | .local _ => true
  | .add lhs rhs _
  | .sub lhs rhs _
  | .mul lhs rhs _
  | .div lhs rhs
  | .mod lhs rhs
  | .pow lhs rhs
  | .bitAnd lhs rhs
  | .bitOr lhs rhs
  | .bitXor lhs rhs
  | .shiftLeft lhs rhs
  | .shiftRight lhs rhs
  | .eq lhs rhs
  | .ne lhs rhs
  | .lt lhs rhs
  | .le lhs rhs
  | .gt lhs rhs
  | .ge lhs rhs
  | .boolAnd lhs rhs
  | .boolOr lhs rhs
  | .hashTwoToOne lhs rhs =>
      exprSupportsPlanScalarYul lhs && exprSupportsPlanScalarYul rhs
  | .ecrecover a b c d =>
      exprSupportsPlanScalarYul a && exprSupportsPlanScalarYul b &&
        exprSupportsPlanScalarYul c && exprSupportsPlanScalarYul d
  | .eip712PermitDigest a b c d e f =>
      exprSupportsPlanScalarYul a && exprSupportsPlanScalarYul b &&
        exprSupportsPlanScalarYul c && exprSupportsPlanScalarYul d &&
        exprSupportsPlanScalarYul e && exprSupportsPlanScalarYul f
  | .crosscallAbiPacked target _ _ _ _ _ _ _ _ =>
      exprSupportsPlanScalarYul target
  | .cast value _ => exprSupportsPlanScalarYul value
  | .boolNot value
  | .hash value => exprSupportsPlanScalarYul value
  | .hashValue a b c d =>
      exprSupportsPlanScalarYul a &&
      exprSupportsPlanScalarYul b &&
      exprSupportsPlanScalarYul c &&
      exprSupportsPlanScalarYul d
  | .nativeValue => true
  | .effect (.storageScalarRead _) => true
  | .effect (.contextRead _) => true
  | .arrayGet (.arrayLit _ values) index =>
      !values.isEmpty &&
        values.all exprSupportsPlanScalarYul &&
        exprSupportsPlanScalarYul index
  | .arrayGet (.local _) index =>
      exprSupportsPlanScalarYul index
  | .arrayGet (.arrayGet array index) nextIndex =>
      exprSupportsPlanScalarYul (.arrayGet array index) &&
        exprSupportsPlanScalarYul nextIndex
  | .field (.structLit _ fields) _ =>
      fields.all fun field => exprSupportsPlanScalarYul field.snd
  | .field (.local _) _ => true
  | .field (.arrayGet array index) _ =>
      exprSupportsPlanScalarYul (.arrayGet array index)
  | .memoryArrayLength (.local _) => true
  | .memoryArrayLength (.memoryArrayNew _ length) =>
      exprSupportsPlanScalarYul length
  | .memoryArrayGet (.local _) index =>
      exprSupportsPlanScalarYul index
  | .memoryArrayGet (.memoryArrayNew _ length) index =>
      exprSupportsPlanScalarYul length &&
        exprSupportsPlanScalarYul index
  | .crosscallInvoke target methodId args =>
      exprSupportsPlanScalarYul target &&
        exprSupportsPlanScalarYul methodId &&
        args.all exprSupportsPlanScalarYul
  | .crosscallInvokeTyped target methodId args returnType =>
      isCrosscallWordType returnType &&
        exprSupportsPlanScalarYul target &&
        exprSupportsPlanScalarYul methodId &&
        args.all exprSupportsPlanCrosscallArgYul
  | .crosscallInvokeValueTyped target methodId callValue args returnType =>
      isCrosscallWordType returnType &&
        exprSupportsPlanScalarYul target &&
        exprSupportsPlanScalarYul methodId &&
        exprSupportsPlanScalarYul callValue &&
        args.all exprSupportsPlanCrosscallArgYul
  | .crosscallInvokeStaticTyped target methodId args returnType =>
      isCrosscallWordType returnType &&
        exprSupportsPlanScalarYul target &&
        exprSupportsPlanScalarYul methodId &&
        args.all exprSupportsPlanCrosscallArgYul
  | .crosscallInvokeDelegateTyped target methodId args returnType =>
      isCrosscallWordType returnType &&
        exprSupportsPlanScalarYul target &&
        exprSupportsPlanScalarYul methodId &&
        args.all exprSupportsPlanCrosscallArgYul
  | .crosscallCreate callValue _ =>
      exprSupportsPlanScalarYul callValue
  | .crosscallCreate2 callValue salt _ =>
      exprSupportsPlanScalarYul callValue &&
        exprSupportsPlanScalarYul salt
  | .crosscallNamed _ _ _ _ => false
  | .arrayLit _ _
  | .arrayGet _ _
  | .memoryArrayNew _ _
  | .memoryArrayLength _
  | .memoryArrayGet _ _
  | .structLit _ _
  | .field _ _
  | .nearPromiseThen _ _ _ _
  | .nearCrosscallInvokePool _ _ _ _
  | .nearPromiseResultsCount
  | .nearPromiseResultStatus _
  | .nearPromiseResultU64 _
  | .effect _ => false

partial def exprSupportsPlanCrosscallArgYul : ProofForge.IR.Expr → Bool
  | .arrayLit _ values =>
      !values.isEmpty &&
        values.all exprSupportsPlanCrosscallArgYul
  | .structLit _ fields =>
      !fields.isEmpty &&
        fields.all fun field => exprSupportsPlanCrosscallArgYul field.snd
  | expr => exprSupportsPlanScalarYul expr
end

partial def lowerExprViaPlan
    (module : Module)
    (env : TypeEnv)
    (expr : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr :=
  lowerExprThroughPlan module env expr

def lowerAssignmentValueExpr
    (module : Module)
    (env : TypeEnv)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr := do
  let valuePlan ←
    match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) value with
    | .ok plan => .ok plan
    | .error err => .error { message := err.message }
  lowerExprPlanExpr module env valuePlan

def lowerScalarLocalAssignmentStmt
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (op? : Option AssignOp)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  let valuePlan ←
    match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) value with
    | .ok plan => .ok plan
    | .error err => .error { message := err.message }
  let stmtPlan :=
    match op? with
    | none => ProofForge.Backend.Evm.Plan.StmtPlan.assign (.local name) valuePlan
    | some op => ProofForge.Backend.Evm.Plan.StmtPlan.assignOp (.local name) op valuePlan
  ProofForge.Backend.Evm.ToYul.scalarAssignmentStmtPlanStatements
    module.overflowChecked
    toYulError
    (fun expr => lowerExpr module env expr)
    (lowerPlanEffectExpr module env)
    stmtPlan

partial def lowerScalarBindingStmtPlan
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (type : ValueType)
    (isMutable : Bool)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  let valuePlan ←
    match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) value with
    | .ok plan => .ok plan
    | .error err => .error { message := err.message }
  let stmtPlan :=
    if isMutable then
      ProofForge.Backend.Evm.Plan.StmtPlan.letMutBind name type valuePlan
    else
      ProofForge.Backend.Evm.Plan.StmtPlan.letBind name type valuePlan
  ProofForge.Backend.Evm.ToYul.scalarBindingStmtPlanStatements
    toYulError
    (fun expr => lowerExpr module env expr)
    (lowerPlanEffectExpr module env)
    stmtPlan

partial def lowerScalarAssertStmtPlan
    (module : Module)
    (env : TypeEnv) :
    ProofForge.IR.Statement → Except LowerError (Array Lean.Compiler.Yul.Statement)
  | .assert condition message errorRef? => do
      let conditionPlan ←
        match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) condition with
        | .ok plan => .ok plan
        | .error err => .error { message := err.message }
      ProofForge.Backend.Evm.ToYul.scalarAssertStmtPlanStatements
        toYulError
        (fun expr => lowerExpr module env expr)
        (lowerPlanEffectExpr module env)
        (fun
          | none => .ok #[revertStmt]
          | some ref => errorRefRevertStmtsRuntime toYulError (fun expr => lowerExpr module env expr) ref)
        (.assert conditionPlan message errorRef?)
  | .assertEq lhs rhs message errorRef? => do
      let lhsPlan ←
        match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) lhs with
        | .ok plan => .ok plan
        | .error err => .error { message := err.message }
      let rhsPlan ←
        match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) rhs with
        | .ok plan => .ok plan
        | .error err => .error { message := err.message }
      ProofForge.Backend.Evm.ToYul.scalarAssertStmtPlanStatements
        toYulError
        (fun expr => lowerExpr module env expr)
        (lowerPlanEffectExpr module env)
        (fun
          | none => .ok #[revertStmt]
          | some ref => errorRefRevertStmtsRuntime toYulError (fun expr => lowerExpr module env expr) ref)
        (.assertEq lhsPlan rhsPlan message errorRef?)
  | _ =>
      .error { message := "EVM StmtPlan-to-Yul scalar assertion lowering expected assert/assertEq" }

def lowerEventEffectWordPlan
    (module : Module)
    (env : TypeEnv) :
    ProofForge.Backend.Evm.Plan.EffectPlan →
      Except LowerError ProofForge.Backend.Evm.Plan.EffectPlan :=
  fun effect =>
    lowerValidate <|
      ProofForge.Backend.Evm.Lower.eventEffectWordPlan
        module
        (toValidateTypeEnv env)
        effect

def lowerEventEmitCoreStmt
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (indexedFields dataFields : Array (String × ProofForge.IR.Expr)) : Except LowerError Lean.Compiler.Yul.Statement := do
  let effect : ProofForge.IR.Effect :=
    if indexedFields.isEmpty then
      ProofForge.IR.Effect.eventEmit name dataFields
    else
      ProofForge.IR.Effect.eventEmitIndexed name indexedFields dataFields
  let effect ←
    match ProofForge.Backend.Evm.Lower.buildEffectPlan module (toValidateTypeEnv env) effect with
    | .ok (.eventEmitWords event dataFieldWords) =>
        .ok (ProofForge.Backend.Evm.Plan.EffectPlan.eventEmitWords event dataFieldWords)
    | .ok (.eventEmitIndexedWords event indexedFieldWords dataFieldWords) =>
        .ok (ProofForge.Backend.Evm.Plan.EffectPlan.eventEmitIndexedWords event indexedFieldWords dataFieldWords)
    | .ok _ =>
        .error { message := s!"EVM Lower.buildEffectPlan event `{name}` did not produce word-planned event effect" }
    | .error err =>
        .error { message := err.message }
  let statements ←
    ProofForge.Backend.Evm.ToYul.eventEffectStmtPlanStatements
      toYulError
      (lowerExprPlanExpr module env)
      (.effect effect)
  match statements[0]? with
  | some statement =>
      if statements.size == 1 then
        .ok statement
      else
        .error { message := s!"event `{name}` lowering produced {statements.size} statements, expected 1" }
  | none =>
      .error { message := s!"event `{name}` lowering produced no statements" }

def lowerEventEmitStmt
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (fields : Array (String × ProofForge.IR.Expr)) : Except LowerError Lean.Compiler.Yul.Statement :=
  lowerEventEmitCoreStmt module env name #[] fields

def lowerEventEmitIndexedStmt
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (indexedFields dataFields : Array (String × ProofForge.IR.Expr)) : Except LowerError Lean.Compiler.Yul.Statement :=
  lowerEventEmitCoreStmt module env name indexedFields dataFields

partial def lowerMapWriteStmtPlan
    (module : Module)
    (env : TypeEnv)
    (stateId : String)
    (mkEffect : String → ProofForge.IR.Expr → ProofForge.IR.Expr → Effect)
    (key value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let effectPlan ←
    match ProofForge.Backend.Evm.Lower.buildEffectPlan module (toValidateTypeEnv env)
        (mkEffect stateId key value) with
    | .ok plan => .ok plan
    | .error err => .error { message := err.message }
  let statements ←
    match effectPlan with
    | .storageMapInsertTarget .. | .storageMapSetTarget .. =>
        ProofForge.Backend.Evm.ToYul.mapWriteTargetEffectStmtPlanStatements
          toYulError
          (fun expr => lowerExpr module env expr)
          (lowerPlanEffectExpr module env)
          (.effect effectPlan)
    | _ =>
        .error { message := "EVM Lower.buildEffectPlan map write did not produce storageMapInsertTarget/storageMapSetTarget" }
  match statements[0]? with
  | some statement =>
      if statements.size == 1 then
        .ok statement
      else
        .error { message := s!"EVM StmtPlan-to-Yul map write lowering produced {statements.size} statements, expected 1" }
  | none =>
      .error { message := "EVM StmtPlan-to-Yul map write lowering produced no statements" }

partial def lowerArrayWriteStmtPlan
    (module : Module)
    (env : TypeEnv)
    (stateId : String)
    (index value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let effectPlan ←
    match ProofForge.Backend.Evm.Lower.buildEffectPlan module (toValidateTypeEnv env)
        (.storageArrayWrite stateId index value) with
    | .ok plan => .ok plan
    | .error err => .error { message := err.message }
  let statements ←
    match effectPlan with
    | .storageArrayWriteTarget .. =>
        ProofForge.Backend.Evm.ToYul.arrayWriteTargetEffectStmtPlanStatements
          toYulError
          (fun expr => lowerExpr module env expr)
          (lowerPlanEffectExpr module env)
          (.effect effectPlan)
    | _ =>
        .error { message := "EVM Lower.buildEffectPlan array write did not produce storageArrayWriteTarget" }
  match statements[0]? with
  | some statement =>
      if statements.size == 1 then
        .ok statement
      else
        .error { message := s!"EVM StmtPlan-to-Yul array write lowering produced {statements.size} statements, expected 1" }
  | none =>
      .error { message := "EVM StmtPlan-to-Yul array write lowering produced no statements" }

partial def lowerStructFieldWriteStmtPlan
    (module : Module)
    (env : TypeEnv)
    (stateId fieldName : String)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let effectPlan ←
    match ProofForge.Backend.Evm.Lower.buildEffectPlan module (toValidateTypeEnv env)
        (.storageStructFieldWrite stateId fieldName value) with
    | .ok plan => .ok plan
    | .error err => .error { message := err.message }
  let statements ←
    match effectPlan with
    | .storageStructFieldWriteTarget .. =>
        ProofForge.Backend.Evm.ToYul.structFieldWriteTargetEffectStmtPlanStatements
          toYulError
          (fun expr => lowerExpr module env expr)
          (lowerPlanEffectExpr module env)
          (.effect effectPlan)
    | _ =>
        .error { message := "EVM Lower.buildEffectPlan struct field write did not produce storageStructFieldWriteTarget" }
  match statements[0]? with
  | some statement =>
      if statements.size == 1 then
        .ok statement
      else
        .error { message := s!"EVM StmtPlan-to-Yul struct field write lowering produced {statements.size} statements, expected 1" }
  | none =>
      .error { message := "EVM StmtPlan-to-Yul struct field write lowering produced no statements" }

def storageStructAssignTempName (stateId fieldName : String) : String :=
  ProofForge.Backend.Evm.ToYul.storageStructAssignTempName stateId fieldName

partial def lowerStorageStructWriteStmtPlan
    (module : Module)
    (env : TypeEnv)
    (stateId : String)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let effectPlan ←
    match ProofForge.Backend.Evm.Lower.buildEffectPlan module (toValidateTypeEnv env)
        (.storageScalarWrite stateId value) with
    | .ok plan => .ok plan
    | .error err => .error { message := err.message }
  let statements ←
    match effectPlan with
    | .storageScalarWrite stateId valuePlan =>
        let fields ←
          lowerValidate <|
            ProofForge.Backend.Evm.Lower.storageStructWriteFieldPlans
              module
              (toValidateTypeEnv env)
              stateId
              valuePlan
        ProofForge.Backend.Evm.ToYul.storageStructWriteFieldPlanStatements
          toYulError
          (fun expr => lowerExpr module env expr)
          (lowerPlanEffectExpr module env)
          stateId
          fields
    | _ =>
        .error { message := "EVM Lower.buildEffectPlan storage struct write did not produce storageScalarWrite" }
  match statements[0]? with
  | some statement =>
      if statements.size == 1 then
        .ok statement
      else
        .error { message := s!"EVM StmtPlan-to-Yul storage struct write lowering produced {statements.size} statements, expected 1" }
  | none =>
      .error { message := "EVM StmtPlan-to-Yul storage struct write lowering produced no statements" }

partial def lowerStructArrayFieldWriteStmtPlan
    (module : Module)
    (env : TypeEnv)
    (stateId : String)
    (index : ProofForge.IR.Expr)
    (fieldName : String)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let effectPlan ←
    match ProofForge.Backend.Evm.Lower.buildEffectPlan module (toValidateTypeEnv env)
        (.storageArrayStructFieldWrite stateId index fieldName value) with
    | .ok plan => .ok plan
    | .error err => .error { message := err.message }
  let statements ←
    match effectPlan with
    | .storageArrayStructFieldWriteTarget .. =>
        ProofForge.Backend.Evm.ToYul.structArrayFieldWriteTargetEffectStmtPlanStatements
          toYulError
          (fun expr => lowerExpr module env expr)
          (lowerPlanEffectExpr module env)
          (.effect effectPlan)
    | _ =>
        .error { message := "EVM Lower.buildEffectPlan struct-array field write did not produce storageArrayStructFieldWriteTarget" }
  match statements[0]? with
  | some statement =>
      if statements.size == 1 then
        .ok statement
      else
        .error { message := s!"EVM StmtPlan-to-Yul struct-array field write lowering produced {statements.size} statements, expected 1" }
  | none =>
      .error { message := "EVM StmtPlan-to-Yul struct-array field write lowering produced no statements" }

partial def lowerDynamicArrayPushStmtPlan
    (module : Module)
    (env : TypeEnv)
    (stateId : String)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let effectPlan ←
    match ProofForge.Backend.Evm.Lower.buildEffectPlan module (toValidateTypeEnv env)
        (.storageDynamicArrayPush stateId value) with
    | .ok plan => .ok plan
    | .error err => .error { message := err.message }
  let statements ←
    match effectPlan with
    | .storageDynamicArrayPushTarget .. =>
        ProofForge.Backend.Evm.ToYul.dynamicArrayPushTargetEffectStmtPlanStatements
          toYulError
          (fun expr => lowerExpr module env expr)
          (lowerPlanEffectExpr module env)
          (.effect effectPlan)
    | _ =>
        .error { message := "EVM Lower.buildEffectPlan dynamic-array push did not produce storageDynamicArrayPushTarget" }
  if statements.isEmpty then
    .error { message := "EVM StmtPlan-to-Yul dynamic-array push lowering produced no statements" }
  else if statements.size == 1 then
    .ok statements[0]!
  else
    .ok (.block { statements := statements })

partial def lowerDynamicArrayPopStmtPlan
    (module : Module)
    (env : TypeEnv)
    (stateId : String) : Except LowerError Lean.Compiler.Yul.Statement := do
  let effectPlan ←
    match ProofForge.Backend.Evm.Lower.buildEffectPlan module (toValidateTypeEnv env)
        (.storageDynamicArrayPop stateId) with
    | .ok plan => .ok plan
    | .error err => .error { message := err.message }
  let statements ←
    match effectPlan with
    | .storageDynamicArrayPopTarget .. =>
        ProofForge.Backend.Evm.ToYul.dynamicArrayPopTargetEffectStmtPlanStatements
          toYulError
          (.effect effectPlan)
    | _ =>
        .error { message := "EVM Lower.buildEffectPlan dynamic-array pop did not produce storageDynamicArrayPopTarget" }
  if statements.isEmpty then
    .error { message := "EVM StmtPlan-to-Yul dynamic-array pop lowering produced no statements" }
  else if statements.size == 1 then
    .ok statements[0]!
  else
    .ok (.block { statements := statements })

partial def lowerStoragePathWriteStmtPlan
    (module : Module)
    (env : TypeEnv)
    (stateId : String)
    (path : Array StoragePathSegment)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let effectPlan ←
    match ProofForge.Backend.Evm.Lower.buildEffectPlan module (toValidateTypeEnv env)
        (.storagePathWrite stateId path value) with
    | .ok plan => .ok plan
    | .error err => .error { message := err.message }
  let statements ←
    match effectPlan with
    | .storagePathWriteExprTarget .. =>
        ProofForge.Backend.Evm.ToYul.storagePathWriteExprTargetEffectStmtPlanStatements
          toYulError
          (fun expr => lowerExpr module env expr)
          (lowerPlanEffectExpr module env)
          (lowerExprPlanExpr module env)
          (.effect effectPlan)
    | .storagePathWriteTarget .. =>
        ProofForge.Backend.Evm.ToYul.storagePathWriteTargetEffectStmtPlanStatements
          toYulError
          (fun expr => lowerExpr module env expr)
          (lowerPlanEffectExpr module env)
          (.effect effectPlan)
    | _ =>
        .error { message := "EVM Lower.buildEffectPlan storage path write did not produce storagePathWriteExprTarget/storagePathWriteTarget" }
  match statements[0]? with
  | some statement =>
      if statements.size == 1 then
        .ok statement
      else
        .error { message := s!"EVM StmtPlan-to-Yul storage path write lowering produced {statements.size} statements, expected 1" }
  | none =>
      .error { message := "EVM StmtPlan-to-Yul storage path write lowering produced no statements" }

partial def lowerStoragePathAssignOpStmtPlan
    (module : Module)
    (env : TypeEnv)
    (stateId : String)
    (path : Array StoragePathSegment)
    (op : AssignOp)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let effectPlan ←
    match ProofForge.Backend.Evm.Lower.buildEffectPlan module (toValidateTypeEnv env)
        (.storagePathAssignOp stateId path op value) with
    | .ok plan => .ok plan
    | .error err => .error { message := err.message }
  let statements ←
    match effectPlan with
    | .storagePathAssignOpExprTarget .. =>
        ProofForge.Backend.Evm.ToYul.storagePathAssignOpExprTargetEffectStmtPlanStatements
          module.overflowChecked
          toYulError
          (fun expr => lowerExpr module env expr)
          (lowerPlanEffectExpr module env)
          (lowerExprPlanExpr module env)
          (.effect effectPlan)
    | .storagePathAssignOpTarget .. =>
        ProofForge.Backend.Evm.ToYul.storagePathAssignOpTargetEffectStmtPlanStatements
          module.overflowChecked
          toYulError
          (fun expr => lowerExpr module env expr)
          (lowerPlanEffectExpr module env)
          (.effect effectPlan)
    | _ =>
        .error { message := "EVM Lower.buildEffectPlan storage path assign_op did not produce storagePathAssignOpExprTarget/storagePathAssignOpTarget" }
  match statements[0]? with
  | some statement =>
      if statements.size == 1 then
        .ok statement
      else
        .error { message := s!"EVM StmtPlan-to-Yul storage path assign_op lowering produced {statements.size} statements, expected 1" }
  | none =>
      .error { message := "EVM StmtPlan-to-Yul storage path assign_op lowering produced no statements" }

partial def lowerMemoryArraySetStmtPlan
    (module : Module)
    (env : TypeEnv)
    (array index value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let effectPlan ←
    match ProofForge.Backend.Evm.Lower.buildEffectPlan module (toValidateTypeEnv env)
        (.memoryArraySet array index value) with
    | .ok plan => .ok plan
    | .error err => .error { message := err.message }
  let statements ←
    ProofForge.Backend.Evm.ToYul.memoryArraySetEffectStmtPlanStatements
      toYulError
      (fun expr => lowerExpr module env expr)
      (lowerPlanEffectExpr module env)
      (.effect effectPlan)
  if statements.isEmpty then
    .error { message := "EVM StmtPlan-to-Yul memory array set lowering produced no statements" }
  else
    .ok (.block { statements := statements })

partial def lowerScalarStorageEffectStmtPlan
    (module : Module)
    (env : TypeEnv) :
    Effect → Except LowerError Lean.Compiler.Yul.Statement
  | .storageScalarWrite stateId value => do
      match ← scalarStateType module stateId with
      | .structType _ =>
          lowerStorageStructWriteStmtPlan module env stateId value
      | _ =>
          let effectPlan ←
            match ProofForge.Backend.Evm.Lower.buildEffectPlan module (toValidateTypeEnv env)
                (.storageScalarWrite stateId value) with
            | .ok plan => .ok plan
            | .error err => .error { message := err.message }
          let statements ←
            match effectPlan with
            | .storageScalarWriteTarget _ _ =>
                ProofForge.Backend.Evm.ToYul.scalarStorageTargetEffectStmtPlanStatements
                  toYulError
                  (fun expr => lowerExpr module env expr)
                  (lowerPlanEffectExpr module env)
                  (.effect effectPlan)
            | _ =>
                .error { message := "EVM Lower.buildEffectPlan scalar storage write did not produce storageScalarWriteTarget" }
          match statements[0]? with
          | some statement =>
              if statements.size == 1 then
                .ok statement
              else
                .error { message := s!"EVM StmtPlan-to-Yul scalar storage write lowering produced {statements.size} statements, expected 1" }
          | none =>
              .error { message := "EVM StmtPlan-to-Yul scalar storage write lowering produced no statements" }
  | .storageScalarAssignOp stateId op value => do
      match ← scalarStateType module stateId with
      | .structType _ =>
          .error { message := s!"storage.scalar.assign_op does not support struct state `{stateId}` in IR EVM v0" }
      | _ => pure ()
      let effectPlan ←
        match ProofForge.Backend.Evm.Lower.buildEffectPlan module (toValidateTypeEnv env)
            (.storageScalarAssignOp stateId op value) with
        | .ok plan => .ok plan
        | .error err => .error { message := err.message }
      let statements ←
        match effectPlan with
        | .storageScalarAssignOpTarget .. =>
            ProofForge.Backend.Evm.ToYul.scalarStorageTargetEffectStmtPlanStatements
              toYulError
              (fun expr => lowerExpr module env expr)
              (lowerPlanEffectExpr module env)
              (.effect effectPlan)
        | _ =>
            .error { message := "EVM Lower.buildEffectPlan scalar storage assign_op did not produce storageScalarAssignOpTarget" }
      match statements[0]? with
      | some statement =>
          if statements.size == 1 then
            .ok statement
          else
            .error { message := s!"EVM StmtPlan-to-Yul scalar storage assign_op lowering produced {statements.size} statements, expected 1" }
      | none =>
          .error { message := "EVM StmtPlan-to-Yul scalar storage assign_op lowering produced no statements" }
  | _ =>
      .error { message := "EVM StmtPlan-to-Yul scalar storage effect lowering expected storageScalarWrite/storageScalarAssignOp" }

def lowerErc1155BatchReceiverStmtPlan
    (module : Module)
    (env : TypeEnv)
    (operator fromAddr toAddr id0 amount0 id1 amount1 : ProofForge.IR.Expr) :
    Except LowerError Lean.Compiler.Yul.Statement := do
  let effectPlan ←
    match ProofForge.Backend.Evm.Lower.buildEffectPlan module (toValidateTypeEnv env)
        (.checkErc1155BatchReceived operator fromAddr toAddr id0 amount0 id1 amount1) with
    | .ok plan => .ok plan
    | .error err => .error { message := err.message }
  let statements ←
    ProofForge.Backend.Evm.ToYul.erc1155BatchReceiverEffectPlanStatements
      toYulError
      (lowerExprPlanExpr module env)
      effectPlan
  .ok (.block { statements })

def lowerEffectStmt (module : Module) (env : TypeEnv) : Effect → Except LowerError Lean.Compiler.Yul.Statement
  | .storageScalarRead _ =>
      .error { message := "storage.scalar.read must be used as an expression" }
  | .storageScalarWrite stateId value =>
      lowerScalarStorageEffectStmtPlan module env (.storageScalarWrite stateId value)
  | .storageScalarAssignOp stateId op value =>
      lowerScalarStorageEffectStmtPlan module env (.storageScalarAssignOp stateId op value)
  | .storageMapContains _ _ =>
      .error { message := "storage.map.contains must be used as an expression" }
  | .storageMapGet _ _ =>
      .error { message := "storage.map.get must be used as an expression" }
  | .storageMapInsert stateId key value =>
      lowerMapWriteStmtPlan module env stateId (fun stateId key value => .storageMapInsert stateId key value) key value
  | .storageMapSet stateId key value =>
      lowerMapWriteStmtPlan module env stateId (fun stateId key value => .storageMapSet stateId key value) key value
  | .storageArrayRead _ _ =>
      .error { message := "storage.array.read must be used as an expression" }
  | .storageArrayWrite stateId index value =>
      lowerArrayWriteStmtPlan module env stateId index value
  | .storageArrayStructFieldRead _ _ _ =>
      .error { message := "storage.array.struct.field.read must be used as an expression" }
  | .storageArrayStructFieldWrite stateId index fieldName value =>
      lowerStructArrayFieldWriteStmtPlan module env stateId index fieldName value
  | .storageDynamicArrayPush stateId value =>
      lowerDynamicArrayPushStmtPlan module env stateId value
  | .storageDynamicArrayPop stateId =>
      lowerDynamicArrayPopStmtPlan module env stateId
  | .storageStructFieldRead _ _ =>
      .error { message := "storage.struct.field.read must be used as an expression" }
  | .storageStructFieldWrite stateId fieldName value =>
      lowerStructFieldWriteStmtPlan module env stateId fieldName value
  | .storagePathRead _ _ =>
      .error { message := "storage.path.read must be used as an expression" }
  | .storagePathWrite stateId path value =>
      lowerStoragePathWriteStmtPlan module env stateId path value
  | .storagePathAssignOp stateId path op value =>
      lowerStoragePathAssignOpStmtPlan module env stateId path op value
  | .memoryArraySet array index value =>
      lowerMemoryArraySetStmtPlan module env array index value
  | .contextRead _ =>
      .error { message := "context reads must be used as expressions" }
  | .eventEmit name fields =>
      lowerEventEmitStmt module env name fields
  | .eventEmitIndexed name indexedFields dataFields =>
      lowerEventEmitIndexedStmt module env name indexedFields dataFields
  | .checkErc721Received operator fromAddr toAddr tokenId => do
      let operatorYul ← lowerExpr module env operator
      let fromYul ← lowerExpr module env fromAddr
      let toYul ← lowerExpr module env toAddr
      let tokenYul ← lowerExpr module env tokenId
      let stmts :=
        ProofForge.Backend.Evm.ToYul.checkErc721ReceivedStatements
          operatorYul fromYul toYul tokenYul
      -- Wrap multi-statement sequence as a single block statement.
      .ok (.block { statements := stmts })
  | .checkErc1155Received operator fromAddr toAddr id amount => do
      let operatorYul ← lowerExpr module env operator
      let fromYul ← lowerExpr module env fromAddr
      let toYul ← lowerExpr module env toAddr
      let idYul ← lowerExpr module env id
      let amountYul ← lowerExpr module env amount
      let stmts :=
        ProofForge.Backend.Evm.ToYul.checkErc1155ReceivedStatements
          operatorYul fromYul toYul idYul amountYul
      .ok (.block { statements := stmts })

  | .checkErc1155BatchReceived operator fromAddr toAddr id0 amount0 id1 amount1 =>
      lowerErc1155BatchReceiverStmtPlan
        module env operator fromAddr toAddr id0 amount0 id1 amount1
end ProofForge.Backend.Evm.IR
