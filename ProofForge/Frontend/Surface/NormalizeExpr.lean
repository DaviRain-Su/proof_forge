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
  | .local name => return (← lookupLocal name).type
  | .arith _ _ lhs _ => exprType lhs
  | .cast target _ => resolveSurfaceType (← get).env.typeIds target
  | .compare _ _ _ | .boolAnd _ _ | .boolOr _ _ | .unary .not _ => return .bool
  | .hash _ => return .hash
  | .stateRead name => stateScalarType name
  | .contextRead field => return (contextFieldType (adaptContextField field))
  | .nativeValue => return .u128
  | .unary .neg arg => exprType arg
  | .field _ _ | .index _ _ =>
    throw (SurfaceNormalizeError.unsupportedSurface "field/index" "field/index access not in initial fragment")

/-- Normalize a Surface expression into ANF instructions plus a result ValueRef. -/
partial def normalizeExpr (e : SurfaceExpr) : SurfaceM NormalizedValue := do
  match e with
  | .literal lit =>
      let coreLit ← liftExcept (adaptLiteral lit)
      emitValueInstruction (.pure (.literal coreLit)) (coreLiteralType coreLit)
  | .local name =>
      let ref ← lookupLocal name
      return { instructions := #[], value := ref }
  | .arith op checked lhs rhs =>
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
      let ty ← exprType lhs
      let mode := if checked then .checked else .wrapping
      let coreOp := adaptArithOp op
      let nv ← arithmeticValue mode coreOp nl.value nr.value ty
      return { instructions := nl.instructions ++ nr.instructions ++ nv.instructions, value := nv.value }
  | .compare op lhs rhs =>
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
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
  | .contextRead field =>
      let coreField := adaptContextField field
      let resultType := contextFieldType coreField
      emitValueInstruction (.contextRead coreField) resultType
  | .hash arg =>
      let nv ← normalizeExpr arg
      let nhash ← emitValueInstruction (.pure (.hash nv.value)) .hash
      return { instructions := nv.instructions ++ nhash.instructions, value := nhash.value }
  | .nativeValue =>
      emitValueInstruction (.contextRead .value) .u128
  | .field _ _ =>
      throw (SurfaceNormalizeError.unsupportedSurface "SurfaceExpr.field" "field projection not in initial fragment")
  | .index _ _ =>
      throw (SurfaceNormalizeError.unsupportedSurface "SurfaceExpr.index" "index access not in initial fragment")

end ProofForge.Frontend.Surface