import ProofForge.Frontend.Surface.NormalizeEnv

/-! # Surface AST — Expression Normalization

Normalize Surface expressions into ANF instructions plus a result ValueRef.
Effectful sub-expressions (storage/context reads) are lifted to explicit
instructions. No wildcard arm exists.
-/

namespace ProofForge.Frontend.Surface

open ProofForge.IR.Core

/-- Normalized expression: an ordered sequence of ANF instructions plus the
value reference produced by the last instruction. -/
structure NormalizedValue where
  instructions : Array Instruction
  value : ValueRef
  deriving Repr, BEq, Nonempty

/-- Append an instruction that produces a single value. -/
def emitValueInstruction (op : InstructionOp) (resultType : CoreType) :
    SurfaceM NormalizedValue := do
  let vid ← freshValueId
  let vdef := { id := vid, type := resultType }
  let instr := { results := #[vdef], op := op }
  return { instructions := #[instr], value := { id := vid, type := resultType } }

/-- Build a pure arithmetic instruction from already-normalized operands. -/
def arithmeticValue (mode : OverflowMode) (op : ArithmeticOp) (lhs rhs : ValueRef)
    (resultType : CoreType) : SurfaceM NormalizedValue := do
  emitValueInstruction (.pure (.arithmetic op mode lhs rhs)) resultType

/-- Build a pure comparison instruction from already-normalized operands. -/
def compareValue (op : CompareOp) (lhs rhs : ValueRef) : SurfaceM NormalizedValue := do
  emitValueInstruction (.pure (.compare op lhs rhs)) .bool

/-- Compute the Core result type of a Surface expression. -/
def exprType (e : SurfaceExpr) : SurfaceM CoreType := do
  match e with
  | .literal lit => return (coreLiteralType (← liftExcept (adaptLiteral lit)))
  | .peerRef _ => return .address
  | .local name => return (← lookupLocal name).type
  | .arith _ _ lhs _ => exprType lhs
  | .cast target _ => resolveSurfaceType (← get).env.typeIds target
  | .compare _ _ _ | .boolAnd _ _ | .boolOr _ _ | .unary .not _ => return .bool
  | .hash _ | .hashPair _ _ => return .hash
  | .stateRead name => stateScalarType name
  | .mapRead name _ => return (← stateMapTypes name).2
  | .arrayRead name _ => stateArrayType name
  | .memoryArray elementType _ =>
      return .memoryRef (← resolveSurfaceType (← get).env.typeIds elementType)
  | .contextRead field => return (contextFieldType (adaptContextField field))
  | .hostCall _ _ => return .u64
  | .crosscall _ _ _ _ returnType =>
      resolveSurfaceType (← get).env.typeIds returnType
  | .nativeValue => return .u128
  | .unary .neg arg => exprType arg
  | .index base _ =>
      match ← exprType base with
      | .memoryRef element => return element
      | other => throw (SurfaceNormalizeError.typeMismatch "memory reference" (reprStr other))
  | .field _ _ =>
    throw (SurfaceNormalizeError.unsupportedSurface "field" "field access not in initial fragment")

/-- Normalize a Surface expression into ANF instructions plus a result ValueRef. -/
partial def normalizeExpr (e : SurfaceExpr) : SurfaceM NormalizedValue := do
  match e with
  | .literal lit =>
      let coreLit ← liftExcept (adaptLiteral lit)
      emitValueInstruction (.pure (.literal coreLit)) (coreLiteralType coreLit)
  | .peerRef logicalId =>
      emitValueInstruction (.pure (.literal (.addressLit logicalId))) .address
  | .local name =>
      let ref ← lookupLocal name
      return { instructions := #[], value := ref }
  | .arith op checked lhs rhs =>
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
      let ty ← exprType lhs
      unless nr.value.type == ty do
        throw (SurfaceNormalizeError.typeMismatch (reprStr ty) (reprStr nr.value.type))
      unless ty == .u8 || ty == .u32 || ty == .u64 || ty == .u128 do
        throw (SurfaceNormalizeError.typeMismatch "unsigned integer" (reprStr ty))
      let mode := if checked then .checked else .wrapping
      let coreOp := adaptArithOp op
      let nv ← arithmeticValue mode coreOp nl.value nr.value ty
      return { instructions := nl.instructions ++ nr.instructions ++ nv.instructions, value := nv.value }
  | .compare op lhs rhs =>
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
      unless nl.value.type == nr.value.type do
        throw (SurfaceNormalizeError.typeMismatch (reprStr nl.value.type) (reprStr nr.value.type))
      let coreOp := adaptCompareOp op
      let nv ← compareValue coreOp nl.value nr.value
      return { instructions := nl.instructions ++ nr.instructions ++ nv.instructions, value := nv.value }
  | .boolAnd _ _ =>
      throw (SurfaceNormalizeError.unsupportedSurface "SurfaceExpr.boolAnd" "boolean and not in initial fragment")
  | .boolOr _ _ =>
      throw (SurfaceNormalizeError.unsupportedSurface "SurfaceExpr.boolOr" "boolean or not in initial fragment")
  | .unary op arg =>
      let nv ← normalizeExpr arg
      let coreOp := adaptUnaryOp op
      let resultType ← exprType e
      let nresult ← emitValueInstruction (.pure (.unary coreOp nv.value)) resultType
      return { instructions := nv.instructions ++ nresult.instructions, value := nresult.value }
  | .cast target arg =>
      let nv ← normalizeExpr arg
      let coreTy ← liftExcept (resolveSurfaceType (← get).env.typeIds target)
      let ncast ← emitValueInstruction (.pure (.cast coreTy nv.value)) coreTy
      return { instructions := nv.instructions ++ ncast.instructions, value := ncast.value }
  | .stateRead name =>
      let stateId ← lookupState name
      let resultType ← stateScalarType name
      emitValueInstruction
        (.storageLoad { root := stateId, resultType := resultType }) resultType
  | .mapRead name key =>
      let stateId ← lookupState name
      let (keyType, valueType) ← stateMapTypes name
      let normalizedKey ← normalizeExpr key
      unless normalizedKey.value.type == keyType do
        throw (SurfaceNormalizeError.typeMismatch (reprStr keyType) (reprStr normalizedKey.value.type))
      let loaded ← emitValueInstruction
        (.storageLoad {
          root := stateId,
          path := #[.mapKey normalizedKey.value],
          resultType := valueType }) valueType
      return {
        instructions := normalizedKey.instructions ++ loaded.instructions,
        value := loaded.value }
  | .arrayRead name index =>
      let stateId ← lookupState name
      let elementType ← stateArrayType name
      let normalizedIndex ← normalizeExpr index
      unless normalizedIndex.value.type == .u64 do
        throw (SurfaceNormalizeError.typeMismatch (reprStr CoreType.u64)
          (reprStr normalizedIndex.value.type))
      let loaded ← emitValueInstruction
        (.storageLoad {
          root := stateId,
          path := #[.index normalizedIndex.value],
          resultType := elementType }) elementType
      return {
        instructions := normalizedIndex.instructions ++ loaded.instructions,
        value := loaded.value }
  | .memoryArray elementType values =>
      let coreElement ← liftExcept (resolveSurfaceType (← get).env.typeIds elementType)
      let length ← emitValueInstruction (.pure (.literal (.u64Lit values.size))) .u64
      let allocated ← emitValueInstruction (.memoryAlloc coreElement length.value) (.memoryRef coreElement)
      let mut instructions := length.instructions ++ allocated.instructions
      let mut index := 0
      for value in values do
        let normalizedValue ← normalizeExpr value
        unless normalizedValue.value.type == coreElement do
          throw (SurfaceNormalizeError.typeMismatch (reprStr coreElement)
            (reprStr normalizedValue.value.type))
        let normalizedIndex ← emitValueInstruction (.pure (.literal (.u64Lit index))) .u64
        instructions := instructions ++ normalizedValue.instructions ++ normalizedIndex.instructions
        instructions := instructions.push {
          results := #[], op := .memoryStore allocated.value normalizedIndex.value normalizedValue.value }
        index := index + 1
      return { instructions := instructions, value := allocated.value }
  | .contextRead field =>
      let coreField := adaptContextField field
      let resultType := contextFieldType coreField
      emitValueInstruction (.contextRead coreField) resultType
  | .hash arg =>
      let nv ← normalizeExpr arg
      let nhash ← emitValueInstruction (.pure (.hash nv.value)) .hash
      return { instructions := nv.instructions ++ nhash.instructions, value := nhash.value }
  | .hashPair lhs rhs =>
      let normalizedLhs ← normalizeExpr lhs
      let normalizedRhs ← normalizeExpr rhs
      let hashed ← emitValueInstruction
        (.pure (.hashTwoToOne normalizedLhs.value normalizedRhs.value)) .hash
      return { instructions := normalizedLhs.instructions ++ normalizedRhs.instructions ++
        hashed.instructions, value := hashed.value }
  | .nativeValue =>
      emitValueInstruction (.contextRead .value) .u128
  | .hostCall id args =>
    let mut allInstrs : Array Instruction := #[]
    let mut argRefs : Array ValueRef := #[]
    for arg in args do
      let nv ← normalizeExpr arg
      allInstrs := allInstrs ++ nv.instructions
      argRefs := argRefs.push nv.value
    let nv ← emitValueInstruction (.hostCall { id := id, args := argRefs }) .u64
    return { instructions := allInstrs ++ nv.instructions, value := nv.value }
  | .crosscall mode target method args returnType =>
    let normalizedTarget ← normalizeExpr target
    let normalizedMethod ← normalizeExpr method
    let mut allInstrs := normalizedTarget.instructions ++ normalizedMethod.instructions
    let mut argRefs := #[]
    let mut paramTypes := #[]
    for arg in args do
      let normalizedArg ← normalizeExpr arg
      allInstrs := allInstrs ++ normalizedArg.instructions
      argRefs := argRefs.push normalizedArg.value
      paramTypes := paramTypes.push normalizedArg.value.type
    let coreReturnType ← liftExcept (resolveSurfaceType (← get).env.typeIds returnType)
    let coreMode := match mode with
      | .invoke => CoreCrosscallMode.invoke
      | .staticInvoke => CoreCrosscallMode.staticInvoke
      | .delegateInvoke => CoreCrosscallMode.delegateInvoke
    let normalizedCall ← emitValueInstruction (.crosscall {
      mode := coreMode,
      target := normalizedTarget.value,
      method := normalizedMethod.value,
      paramTypes := paramTypes,
      returnType := coreReturnType
    } argRefs) coreReturnType
    let instructions := allInstrs ++ normalizedCall.instructions
    return { instructions := instructions, value := normalizedCall.value }
  | .field _ _ =>
      throw (SurfaceNormalizeError.unsupportedSurface "SurfaceExpr.field" "field projection not in initial fragment")
  | .index base index =>
      let normalizedBase ← normalizeExpr base
      let elementType ← match normalizedBase.value.type with
        | .memoryRef element => pure element
        | other => throw (SurfaceNormalizeError.typeMismatch "memory reference" (reprStr other))
      let normalizedIndex ← normalizeExpr index
      unless normalizedIndex.value.type == .u64 do
        throw (SurfaceNormalizeError.typeMismatch (reprStr CoreType.u64)
          (reprStr normalizedIndex.value.type))
      let loaded ← emitValueInstruction
        (.memoryLoad normalizedBase.value normalizedIndex.value) elementType
      return {
        instructions := normalizedBase.instructions ++ normalizedIndex.instructions ++ loaded.instructions,
        value := loaded.value }

end ProofForge.Frontend.Surface
