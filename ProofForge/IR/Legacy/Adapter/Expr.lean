import ProofForge.IR.Legacy.Adapter.Env

namespace ProofForge.IR.Legacy.Adapter

open ProofForge.IR
open ProofForge.IR.Core

/- Lift an `Except` into the `AdapterM` monad. -/

def liftExcept {α} : Except CanonicalizeError α → AdapterM α :=
  fun x => match x with | .ok a => return a | .error e => throw e

/- Normalized expression: an ordered sequence of ANF instructions plus the
value reference produced by the last instruction. -/

structure NormalizedValue where
  instructions : Array Instruction
  value : ValueRef
  deriving Repr, BEq, Inhabited

/- Append an instruction that produces a single value. -/

def emitValueInstruction (op : InstructionOp) (resultType : CoreType) : AdapterM NormalizedValue := do
  let vid ← freshValueId
  let vdef := { id := vid, type := resultType }
  let instr := { results := #[vdef], op := op }
  return { instructions := #[instr], value := { id := vid, type := resultType } }

/- Convert a legacy `AssignOp` to a canonical `ArithmeticOp`. -/

def adaptAssignOp (op : AssignOp) : Except CanonicalizeError ArithmeticOp :=
  match op with
  | .add => .ok .add
  | .sub => .ok .sub
  | .mul => .ok .mul
  | .div => .ok .div
  | .mod => .ok .mod
  | .bitAnd => .ok .and
  | .bitOr => .ok .or
  | .bitXor => .ok .xor
  | .shiftLeft => .ok .shl
  | .shiftRight => .ok .shr

/- Convert a legacy `Literal` to a canonical `CoreLiteral`, checking fixed-width
ranges before any narrowing occurs. -/

def adaptLiteral (l : Literal) : Except CanonicalizeError CoreLiteral :=
  match l with
  | .u8 n =>
      if n < 256 then .ok (.u8Lit n)
      else .error (CanonicalizeError.literalOutOfRange "u8" (toString n))
  | .u32 n =>
      if n < 4294967296 then .ok (.u32Lit n)
      else .error (CanonicalizeError.literalOutOfRange "u32" (toString n))
  | .u64 n =>
      if n < 18446744073709551616 then .ok (.u64Lit n)
      else .error (CanonicalizeError.literalOutOfRange "u64" (toString n))
  | .u128 n =>
      if n < 340282366920938463463374607431768211456 then .ok (.u128Lit n)
      else .error (CanonicalizeError.literalOutOfRange "u128" (toString n))
  | .bool b => .ok (.boolLit b)
  | .hash4 a b c d =>
      let maxU64 := 18446744073709551615
      if a > maxU64 || b > maxU64 || c > maxU64 || d > maxU64 then
        .error (CanonicalizeError.literalOutOfRange "hash4 limb" s!"{a},{b},{c},{d}")
      else
        let word := ((((a * 18446744073709551616) + b) * 18446744073709551616 + c) *
          18446744073709551616 + d)
        .ok (.hashLit (toString word))
  | .address n => .ok (.addressLit (toString n))

/- Core literal result type. -/

def coreLiteralType (l : CoreLiteral) : CoreType :=
  match l with
  | .unitLit => .unit
  | .boolLit _ => .bool
  | .u8Lit _ => .u8
  | .u32Lit _ => .u32
  | .u64Lit _ => .u64
  | .u128Lit _ => .u128
  | .addressLit _ => .address
  | .bytesLit _ => .bytes
  | .stringLit _ => .string
  | .hashLit _ => .hash

/- Build a pure arithmetic instruction from already-normalized operands. -/

def arithmeticValue (mode : OverflowMode) (op : ArithmeticOp) (lhs rhs : ValueRef)
    (resultType : CoreType) : AdapterM NormalizedValue := do
  emitValueInstruction (.pure (.arithmetic op mode lhs rhs)) resultType

/- Build a pure comparison instruction from already-normalized operands. -/

def compareValue (op : CompareOp) (lhs rhs : ValueRef) : AdapterM NormalizedValue := do
  emitValueInstruction (.pure (.compare op lhs rhs)) .bool

/- The scalar element type of a state variable. -/

def stateScalarType (name : String) : AdapterM CoreType := do
  let shape ← lookupStateShape name
  match shape with
  | .scalar ty => return ty
  | _ => throw (CanonicalizeError.typeMismatch "scalar" "non-scalar state")

def stateMapTypes (name : String) : AdapterM (CoreType × CoreType) := do
  match ← lookupStateShape name with
  | .map key value _ => return (key, value)
  | _ => throw (CanonicalizeError.typeMismatch "map" "non-map state")

private def storagePathResultType (shape : StateShape)
    (segments : Array ProofForge.IR.StoragePathSegment) : AdapterM CoreType := do
  let mut current := shape
  for segment in segments do
    match segment, current with
    | .mapKey _, .map _ value _ => current := .scalar value
    | .index _, .fixedArray element _ => current := .scalar element
    | .field _, _ =>
        throw (CanonicalizeError.unsupportedConstructor "StoragePathSegment.field"
          "record field IDs are not available in the initial adapter environment")
    | _, _ => throw (CanonicalizeError.typeMismatch "compatible storage path" (reprStr current))
  let resultType ← match current with
    | .scalar type => pure type
    | _ => throw (CanonicalizeError.typeMismatch "scalar storage leaf" (reprStr current))
  return resultType

/- Compute the canonical result type of a legacy expression. -/

def exprType (e : Expr) : AdapterM CoreType := do
  match e with
  | .literal l => return (coreLiteralType (← liftExcept (adaptLiteral l)))
  | .local name => do return (← lookupLocal name).type
  | .add lhs _ _ | .sub lhs _ _ | .mul lhs _ _ | .div lhs _ | .mod lhs _ | .pow lhs _
  | .bitAnd lhs _ | .bitOr lhs _ | .bitXor lhs _ | .shiftLeft lhs _ | .shiftRight lhs _ =>
      exprType lhs
  | .cast _ targetType => liftExcept (adaptType (← get).env.typeIds targetType)
  | .eq _ _ | .ne _ _ | .lt _ _ | .le _ _ | .gt _ _ | .ge _ _
  | .boolAnd _ _ | .boolOr _ _ | .boolNot _ => return .bool
  | .effect (.storageScalarRead name) => stateScalarType name
  | .effect (.contextRead .userIdHash) => return .hash
  | .effect (.contextRead field) => contextFieldType <$> liftExcept (adaptContextField field)
  | .effect (.storageMapGet name _) => return (← stateMapTypes name).2
  | .effect (.storagePathRead name path) =>
      storagePathResultType (← lookupStateShape name) path
  | .hash _ | .hashTwoToOne _ _ => return .hash
  | .crosscallInvoke _ _ _ => return .u64
  | .nativeValue => return .unit
  | _ => throw (CanonicalizeError.typeMismatch "known" "unknown expression type")

/- Stable constructor tag for error messages. -/

def exprTag (e : Expr) : String :=
  match e with
  | .literal _ => "Expr.literal"
  | .local _ => "Expr.local"
  | .arrayLit _ _ => "Expr.arrayLit"
  | .arrayGet _ _ => "Expr.arrayGet"
  | .memoryArrayNew _ _ => "Expr.memoryArrayNew"
  | .memoryArrayLength _ => "Expr.memoryArrayLength"
  | .memoryArrayGet _ _ => "Expr.memoryArrayGet"
  | .structLit _ _ => "Expr.structLit"
  | .field _ _ => "Expr.field"
  | .add _ _ _ => "Expr.add"
  | .sub _ _ _ => "Expr.sub"
  | .mul _ _ _ => "Expr.mul"
  | .div _ _ => "Expr.div"
  | .mod _ _ => "Expr.mod"
  | .pow _ _ => "Expr.pow"
  | .bitAnd _ _ => "Expr.bitAnd"
  | .bitOr _ _ => "Expr.bitOr"
  | .bitXor _ _ => "Expr.bitXor"
  | .shiftLeft _ _ => "Expr.shiftLeft"
  | .shiftRight _ _ => "Expr.shiftRight"
  | .cast _ _ => "Expr.cast"
  | .eq _ _ => "Expr.eq"
  | .ne _ _ => "Expr.ne"
  | .lt _ _ => "Expr.lt"
  | .le _ _ => "Expr.le"
  | .gt _ _ => "Expr.gt"
  | .ge _ _ => "Expr.ge"
  | .boolAnd _ _ => "Expr.boolAnd"
  | .boolOr _ _ => "Expr.boolOr"
  | .boolNot _ => "Expr.boolNot"
  | .hashValue _ _ _ _ => "Expr.hashValue"
  | .hash _ => "Expr.hash"
  | .hashTwoToOne _ _ => "Expr.hashTwoToOne"
  | .ecrecover _ _ _ _ => "Expr.ecrecover"
  | .eip712PermitDigest _ _ _ _ _ _ => "Expr.eip712PermitDigest"
  | .nativeValue => "Expr.nativeValue"
  | .crosscallAbiPacked _ _ _ _ _ _ _ _ _ => "Expr.crosscallAbiPacked"
  | .crosscallInvoke _ _ _ => "Expr.crosscallInvoke"
  | .crosscallInvokeTyped _ _ _ _ => "Expr.crosscallInvokeTyped"
  | .crosscallInvokeValueTyped _ _ _ _ _ => "Expr.crosscallInvokeValueTyped"
  | .crosscallInvokeStaticTyped _ _ _ _ => "Expr.crosscallInvokeStaticTyped"
  | .crosscallInvokeDelegateTyped _ _ _ _ => "Expr.crosscallInvokeDelegateTyped"
  | .crosscallCreate _ _ => "Expr.crosscallCreate"
  | .crosscallCreate2 _ _ _ => "Expr.crosscallCreate2"
  | .crosscallNamed _ _ _ _ => "Expr.crosscallNamed"
  | .nearCrosscallInvokePool _ _ _ _ => "Expr.nearCrosscallInvokePool"
  | .nearPromiseThen _ _ _ _ => "Expr.nearPromiseThen"
  | .nearPromiseResultsCount => "Expr.nearPromiseResultsCount"
  | .nearPromiseResultStatus _ => "Expr.nearPromiseResultStatus"
  | .nearPromiseResultU64 _ => "Expr.nearPromiseResultU64"
  | .effect _ => "Expr.effect"

/- Stable constructor tag for effects. -/

def effectTag (eff : Effect) : String :=
  match eff with
  | .storageScalarRead _ => "Effect.storageScalarRead"
  | .storageScalarWrite _ _ => "Effect.storageScalarWrite"
  | .storageScalarAssignOp _ _ _ => "Effect.storageScalarAssignOp"
  | .storageMapContains _ _ => "Effect.storageMapContains"
  | .storageMapGet _ _ => "Effect.storageMapGet"
  | .storageMapInsert _ _ _ => "Effect.storageMapInsert"
  | .storageMapSet _ _ _ => "Effect.storageMapSet"
  | .storageArrayRead _ _ => "Effect.storageArrayRead"
  | .storageArrayWrite _ _ _ => "Effect.storageArrayWrite"
  | .storageArrayStructFieldRead _ _ _ => "Effect.storageArrayStructFieldRead"
  | .storageArrayStructFieldWrite _ _ _ _ => "Effect.storageArrayStructFieldWrite"
  | .storageDynamicArrayPush _ _ => "Effect.storageDynamicArrayPush"
  | .storageDynamicArrayPop _ => "Effect.storageDynamicArrayPop"
  | .memoryArraySet _ _ _ => "Effect.memoryArraySet"
  | .storageStructFieldRead _ _ => "Effect.storageStructFieldRead"
  | .storageStructFieldWrite _ _ _ => "Effect.storageStructFieldWrite"
  | .storagePathRead _ _ => "Effect.storagePathRead"
  | .storagePathWrite _ _ _ => "Effect.storagePathWrite"
  | .storagePathAssignOp _ _ _ _ => "Effect.storagePathAssignOp"
  | .contextRead _ => "Effect.contextRead"
  | .eventEmit _ _ => "Effect.eventEmit"
  | .eventEmitIndexed _ _ _ => "Effect.eventEmitIndexed"
  | .checkErc721Received _ _ _ _ => "Effect.checkErc721Received"
  | .checkErc1155Received _ _ _ _ _ => "Effect.checkErc1155Received"
  | .checkErc1155BatchReceived _ _ _ _ _ _ _ => "Effect.checkErc1155BatchReceived"

/- Normalize a legacy `Expr` into ANF instructions plus a result `ValueRef`.
Effectful sub-expressions (storage/context reads) are lifted to explicit
instructions. No wildcard arm exists. -/

partial def normalizeExpr (e : Expr) : AdapterM NormalizedValue := do
  match e with
  | .literal l =>
      let lit ← liftExcept (adaptLiteral l)
      emitValueInstruction (.pure (.literal lit)) (coreLiteralType lit)
  | .local name =>
      let ref ← lookupLocal name
      return { instructions := #[], value := ref }
  | .add lhs rhs checked =>
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
      let ty ← exprType lhs
      let nv ← arithmeticValue (if checked then .checked else .wrapping) .add nl.value nr.value ty
      return { instructions := nl.instructions ++ nr.instructions ++ nv.instructions, value := nv.value }
  | .sub lhs rhs checked =>
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
      let ty ← exprType lhs
      let nv ← arithmeticValue (if checked then .checked else .wrapping) .sub nl.value nr.value ty
      return { instructions := nl.instructions ++ nr.instructions ++ nv.instructions, value := nv.value }
  | .mul lhs rhs checked =>
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
      let ty ← exprType lhs
      let nv ← arithmeticValue (if checked then .checked else .wrapping) .mul nl.value nr.value ty
      return { instructions := nl.instructions ++ nr.instructions ++ nv.instructions, value := nv.value }
  | .div lhs rhs =>
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
      let ty ← exprType lhs
      let nv ← arithmeticValue .wrapping .div nl.value nr.value ty
      return { instructions := nl.instructions ++ nr.instructions ++ nv.instructions, value := nv.value }
  | .mod lhs rhs =>
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
      let ty ← exprType lhs
      let nv ← arithmeticValue .wrapping .mod nl.value nr.value ty
      return { instructions := nl.instructions ++ nr.instructions ++ nv.instructions, value := nv.value }
  | .pow _ _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.pow"
        "Core has no exact exponentiation primitive")
  | .bitAnd lhs rhs =>
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
      let ty ← exprType lhs
      let nv ← arithmeticValue .wrapping .and nl.value nr.value ty
      return { instructions := nl.instructions ++ nr.instructions ++ nv.instructions, value := nv.value }
  | .bitOr lhs rhs =>
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
      let ty ← exprType lhs
      let nv ← arithmeticValue .wrapping .or nl.value nr.value ty
      return { instructions := nl.instructions ++ nr.instructions ++ nv.instructions, value := nv.value }
  | .bitXor lhs rhs =>
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
      let ty ← exprType lhs
      let nv ← arithmeticValue .wrapping .xor nl.value nr.value ty
      return { instructions := nl.instructions ++ nr.instructions ++ nv.instructions, value := nv.value }
  | .shiftLeft lhs rhs =>
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
      let ty ← exprType lhs
      let nv ← arithmeticValue .wrapping .shl nl.value nr.value ty
      return { instructions := nl.instructions ++ nr.instructions ++ nv.instructions, value := nv.value }
  | .shiftRight lhs rhs =>
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
      let ty ← exprType lhs
      let nv ← arithmeticValue .wrapping .shr nl.value nr.value ty
      return { instructions := nl.instructions ++ nr.instructions ++ nv.instructions, value := nv.value }
  | .eq lhs rhs =>
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
      let nv ← compareValue .eq nl.value nr.value
      return { instructions := nl.instructions ++ nr.instructions ++ nv.instructions, value := nv.value }
  | .ne lhs rhs =>
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
      let nv ← compareValue .ne nl.value nr.value
      return { instructions := nl.instructions ++ nr.instructions ++ nv.instructions, value := nv.value }
  | .lt lhs rhs =>
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
      let nv ← compareValue .lt nl.value nr.value
      return { instructions := nl.instructions ++ nr.instructions ++ nv.instructions, value := nv.value }
  | .le lhs rhs =>
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
      let nv ← compareValue .le nl.value nr.value
      return { instructions := nl.instructions ++ nr.instructions ++ nv.instructions, value := nv.value }
  | .gt lhs rhs =>
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
      let nv ← compareValue .gt nl.value nr.value
      return { instructions := nl.instructions ++ nr.instructions ++ nv.instructions, value := nv.value }
  | .ge lhs rhs =>
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
      let nv ← compareValue .ge nl.value nr.value
      return { instructions := nl.instructions ++ nr.instructions ++ nv.instructions, value := nv.value }
  | .boolAnd _ _ => throw (CanonicalizeError.unsupportedConstructor "Expr.boolAnd" "boolean and not in initial fragment")
  | .boolOr _ _ => throw (CanonicalizeError.unsupportedConstructor "Expr.boolOr" "boolean or not in initial fragment")
  | .boolNot value =>
      let nv ← normalizeExpr value
      let nnot ← emitValueInstruction (.pure (.unary .not nv.value)) .bool
      return { instructions := nv.instructions ++ nnot.instructions, value := nnot.value }
  | .cast value targetType =>
      let nv ← normalizeExpr value
      let coreTy ← liftExcept (adaptType (← get).env.typeIds targetType)
      let ncast ← emitValueInstruction (.pure (.cast coreTy nv.value)) coreTy
      return { instructions := nv.instructions ++ ncast.instructions, value := ncast.value }
  | .effect (.storageScalarRead name) =>
      let stateId ← lookupState name
      let resultType ← stateScalarType name
      emitValueInstruction (.storageLoad { root := stateId, resultType := resultType }) resultType
  | .effect (.storageMapGet name key) =>
      let stateId ← lookupState name
      let (keyType, valueType) ← stateMapTypes name
      let normalizedKey ← normalizeExpr key
      unless normalizedKey.value.type == keyType do
        throw (CanonicalizeError.typeMismatch (reprStr keyType) (reprStr normalizedKey.value.type))
      let loaded ← emitValueInstruction (.storageLoad {
        root := stateId, path := #[.mapKey normalizedKey.value], resultType := valueType }) valueType
      return { instructions := normalizedKey.instructions ++ loaded.instructions, value := loaded.value }
  | .effect (.storagePathRead name path) =>
      let stateId ← lookupState name
      let mut instructions := #[]
      let mut segments := #[]
      let mut current ← lookupStateShape name
      for segment in path do
        match segment, current with
        | .mapKey key, .map expectedKey value _ =>
            let normalized ← normalizeExpr key
            unless normalized.value.type == expectedKey do
              throw (CanonicalizeError.typeMismatch (reprStr expectedKey) (reprStr normalized.value.type))
            instructions := instructions ++ normalized.instructions
            segments := segments.push (.mapKey normalized.value)
            current := .scalar value
        | .index index, .fixedArray element _ =>
            let normalized ← normalizeExpr index
            unless normalized.value.type == .u64 do
              throw (CanonicalizeError.typeMismatch (reprStr CoreType.u64) (reprStr normalized.value.type))
            instructions := instructions ++ normalized.instructions
            segments := segments.push (.index normalized.value)
            current := .scalar element
        | .field _, _ =>
            throw (CanonicalizeError.unsupportedConstructor "StoragePathSegment.field"
              "record field IDs are not available in the initial adapter environment")
        | _, _ => throw (CanonicalizeError.typeMismatch "compatible storage path" (reprStr current))
      let resultType ← match current with
        | .scalar type => pure type
        | _ => throw (CanonicalizeError.typeMismatch "scalar storage leaf" (reprStr current))
      let loaded ← emitValueInstruction
        (.storageLoad { root := stateId, path := segments, resultType }) resultType
      return { instructions := instructions ++ loaded.instructions, value := loaded.value }
  | .effect (.contextRead .userIdHash) =>
      let sender ← emitValueInstruction (.contextRead .sender) .address
      let hashed ← emitValueInstruction (.pure (.hash sender.value)) .hash
      return { instructions := sender.instructions ++ hashed.instructions, value := hashed.value }
  | .effect (.contextRead field) =>
      let coreField ← liftExcept (adaptContextField field)
      let resultType := contextFieldType coreField
      emitValueInstruction (.contextRead coreField) resultType
  | .effect other =>
      throw (CanonicalizeError.unsupportedConstructor (effectTag other) "effect expression not in initial fragment")
  | .hash preimage =>
      let nv ← normalizeExpr preimage
      let nhash ← emitValueInstruction (.pure (.hash nv.value)) .hash
      return { instructions := nv.instructions ++ nhash.instructions, value := nhash.value }
  | .hashTwoToOne _ _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.hashTwoToOne"
        "Core has no two-input hash primitive")
  | .nativeValue =>
      emitValueInstruction (.contextRead .value) .u128
  | .arrayLit _ _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.arrayLit" "array literal not in initial fragment")
  | .arrayGet _ _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.arrayGet" "array get not in initial fragment")
  | .memoryArrayNew _ _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.memoryArrayNew" "memory array not in initial fragment")
  | .memoryArrayLength _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.memoryArrayLength" "memory array length not in initial fragment")
  | .memoryArrayGet _ _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.memoryArrayGet" "memory array get not in initial fragment")
  | .structLit _ _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.structLit" "struct literal not in initial fragment")
  | .field _ _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.field" "field projection not in initial fragment")
  | .hashValue _ _ _ _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.hashValue" "four-input hash not in initial fragment")
  | .ecrecover _ _ _ _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.ecrecover" "ecrecover not in initial fragment")
  | .eip712PermitDigest _ _ _ _ _ _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.eip712PermitDigest" "EIP-712 permit digest not in initial fragment")
  | .crosscallAbiPacked _ _ _ _ _ _ _ _ _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.crosscallAbiPacked" "crosscall ABI packing not in initial fragment")
  | .crosscallInvoke target method args => do
      let normalizedTarget ← normalizeExpr target
      let normalizedMethod ← match method with
        | .literal (.address n) | .literal (.u64 n) | .literal (.u32 n) |
            .literal (.u8 n) | .literal (.u128 n) =>
            emitValueInstruction (.pure (.literal (.stringLit (toString n)))) .string
        | _ => normalizeExpr method
      let mut instructions := normalizedTarget.instructions ++ normalizedMethod.instructions
      let mut argRefs := #[]
      let mut paramTypes := #[]
      for arg in args do
        let normalizedArg ← match arg with
          | .literal literal =>
              let coreLiteral ← liftExcept (adaptLiteral literal)
              emitValueInstruction (.pure (.literal coreLiteral)) (coreLiteralType coreLiteral)
          | .local name =>
              let value ← lookupLocal name
              pure { instructions := #[], value }
          | _ => throw (CanonicalizeError.unsupportedConstructor
              (exprTag arg) "portable crosscall arguments currently support only scalar literals and locals")
        instructions := instructions ++ normalizedArg.instructions
        argRefs := argRefs.push normalizedArg.value
        paramTypes := paramTypes.push normalizedArg.value.type
      let normalizedCall ← emitValueInstruction (.crosscall {
        mode := .invoke
        target := normalizedTarget.value
        method := normalizedMethod.value
        paramTypes
        returnType := .u64
      } argRefs) .u64
      return {
        instructions := instructions ++ normalizedCall.instructions
        value := normalizedCall.value
      }
  | .crosscallInvokeTyped _ _ _ _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.crosscallInvokeTyped" "typed crosscall invoke not in initial fragment")
  | .crosscallInvokeValueTyped _ _ _ _ _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.crosscallInvokeValueTyped" "value-typed crosscall invoke not in initial fragment")
  | .crosscallInvokeStaticTyped _ _ _ _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.crosscallInvokeStaticTyped" "static typed crosscall invoke not in initial fragment")
  | .crosscallInvokeDelegateTyped _ _ _ _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.crosscallInvokeDelegateTyped" "delegate typed crosscall invoke not in initial fragment")
  | .crosscallCreate _ _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.crosscallCreate" "crosscall create not in initial fragment")
  | .crosscallCreate2 _ _ _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.crosscallCreate2" "crosscall create2 not in initial fragment")
  | .crosscallNamed _ _ _ _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.crosscallNamed" "named crosscall not in initial fragment")
  | .nearCrosscallInvokePool _ _ _ _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.nearCrosscallInvokePool" "NEAR crosscall invoke pool not in initial fragment")
  | .nearPromiseThen _ _ _ _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.nearPromiseThen" "NEAR promise then not in initial fragment")
  | .nearPromiseResultsCount =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.nearPromiseResultsCount" "NEAR promise results count not in initial fragment")
  | .nearPromiseResultStatus _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.nearPromiseResultStatus" "NEAR promise result status not in initial fragment")
  | .nearPromiseResultU64 _ =>
      throw (CanonicalizeError.unsupportedConstructor "Expr.nearPromiseResultU64" "NEAR promise result u64 not in initial fragment")

end ProofForge.IR.Legacy.Adapter
