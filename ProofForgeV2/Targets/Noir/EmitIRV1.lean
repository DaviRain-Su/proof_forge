import ProofForgeV2.Targets.Noir.ValidatePlanV1

/-!
# Noir EmitIRV1 — Plan → IR emission

Typed relation IR, validateIR, lower/emitFromIR.
-/

namespace ProofForgeV2.Targets.Noir

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

inductive ValueRef where
  | input (index : Nat)
  | literal (value : UInt64)
  | temp (index : Nat)
  deriving BEq, Inhabited, Repr

inductive Operation where
  | checkedAdd (destination : Nat) (lhs rhs : ValueRef)
  | checkedSub (destination : Nat) (lhs rhs : ValueRef)
  | checkedMul (destination : Nat) (lhs rhs : ValueRef)
  | checkedDiv (destination : Nat) (lhs rhs : ValueRef)
  | checkedMod (destination : Nat) (lhs rhs : ValueRef)
  /-- Exact mod-p Field arithmetic (Noir native Field = bn254 Fr). -/
  | fieldAdd (destination : Nat) (lhs rhs : ValueRef)
  | fieldSub (destination : Nat) (lhs rhs : ValueRef)
  | fieldMul (destination : Nat) (lhs rhs : ValueRef)
  | fieldDiv (destination : Nat) (lhs rhs : ValueRef)
  | bitNot (destination : Nat) (source : ValueRef)
  /-- Materialize a UInt128 Plan literal as a native Noir `u128` temp (T11). -/
  | bigLiteral (destination : Nat) (value : Nat)
  /-- Narrow/wide body UInt ops (`bitWidth ∈ {8,16,32,128}`); UInt64 keeps
      historical. Field never uses these. bitWidth=128 → native u128 (T11). -/
  | narrowCheckedAdd (bitWidth destination : Nat) (lhs rhs : ValueRef)
  | narrowCheckedSub (bitWidth destination : Nat) (lhs rhs : ValueRef)
  | narrowCheckedMul (bitWidth destination : Nat) (lhs rhs : ValueRef)
  | narrowCheckedDiv (bitWidth destination : Nat) (lhs rhs : ValueRef)
  | narrowCheckedMod (bitWidth destination : Nat) (lhs rhs : ValueRef)
  | narrowBitAnd (bitWidth destination : Nat) (lhs rhs : ValueRef)
  | narrowBitOr (bitWidth destination : Nat) (lhs rhs : ValueRef)
  | narrowBitXor (bitWidth destination : Nat) (lhs rhs : ValueRef)
  | narrowBitNot (bitWidth destination : Nat) (source : ValueRef)
  | narrowShl (bitWidth destination : Nat) (lhs rhs : ValueRef)
  | narrowShr (bitWidth destination : Nat) (lhs rhs : ValueRef)
  | boolNot (destination : Nat) (source : ValueRef)
  | checkedNeg (destination : Nat) (source : ValueRef)
  | fieldNeg (destination : Nat) (source : ValueRef)
  | signedCompare (op : ComparisonOp) (destination : Nat) (lhs rhs : ValueRef)
  | bitAnd (destination : Nat) (lhs rhs : ValueRef)
  | bitOr (destination : Nat) (lhs rhs : ValueRef)
  | bitXor (destination : Nat) (lhs rhs : ValueRef)
  | boolAnd (destination : Nat) (lhs rhs : ValueRef)
  | boolOr (destination : Nat) (lhs rhs : ValueRef)
  | assertEqual (lhs rhs : ValueRef)
  | assertBool (inputIndex : Nat) (expected : Bool)
  | compare (op : ComparisonOp) (destination : Nat) (lhs rhs : ValueRef)
  | assertConstraint (condition : ValueRef)
  | ifRegion (condition : ValueRef) (thenOps elseOps : Array Operation)
  | switchRegion (scrutinee : ValueRef) (scrutIsBool : Bool)
      (cases : Array (UInt64 × Array Operation)) (defaultOps : Array Operation)
  | selectRegion (destination : Nat) (condition : ValueRef) (resultIsBool : Bool)
      (thenOps : Array Operation) (thenValue : ValueRef)
      (elseOps : Array Operation) (elseValue : ValueRef)
  | selectSwitch (destination : Nat) (scrutinee : ValueRef) (scrutIsBool : Bool)
      (resultIsBool : Bool)
      (cases : Array (UInt64 × Array Operation × ValueRef))
      (defaultOps : Array Operation) (defaultValue : ValueRef)
  deriving BEq, Inhabited, Repr

structure RelationIR where
  sourceRelation : Relation
  tempCount : Nat
  operations : Array Operation
  deriving BEq, Inhabited, Repr

/-- Exact typed circuit recipe. Rendering source is later than Plan-to-IR
validation so source strings cannot rediscover business semantics.
    Private `mk`: public Plan→IR construction is capability-gated only
    (`irFromCapability`). -/
structure IR where
  private mk ::
  sourcePlan : Plan
  name : String
  relations : Array RelationIR
  -- No Inhabited: IR embeds Plan → TargetDescriptor identities.
  deriving BEq, Repr

private structure LoweredExpr where
  operations : Array Operation
  value : ValueRef
  next : Nat
  deriving Inhabited

private def inputIndexFor (relation : Relation) (role : InputRole) : Nat := Id.run do
  for index in [0:relation.inputs.size] do
    if relation.inputs[index]!.role == role then return index
  return 0

/-- Whether every path through a statement list ends in a return (valued or
    bare marker), matching the region emitter's closedness: a list closes iff
    its last statement is a return or a region whose arms all close. An empty
    else/default arm is a fallthrough (open). -/
private partial def statementListClosesV1 : List Statement → Bool
  | [] => false
  | [statement] =>
      match statement with
      | .returnValue _ | .returnNone | .revertError .. => true
      | .ifThenElse _ thenBody elseBody =>
          !elseBody.isEmpty && statementListClosesV1 thenBody.toList &&
            statementListClosesV1 elseBody.toList
      | .switchOn _ cases defaultBody =>
          !defaultBody.isEmpty && statementListClosesV1 defaultBody.toList &&
            cases.all fun (_, caseBody) => statementListClosesV1 caseBody.toList
      | .store _ | .assert _ | .emitEvent .. | .externalCall .. | .schedule .. | .forLoop .. => false
  | _ :: _ :: rest => statementListClosesV1 rest


mutual

/-- Constant-fold a shift-count expression. UInt32 values in this envelope
    arise only from literals and literal arithmetic; a non-constant shape or
    a failing/overflowing count expression yields none (the caller fails
    closed — a statically known u32 overflow is outside the target pilot,
    while counts ≥ 64 lower to the literal invalidShift guard). -/
private partial def constShiftCount? : Expr → Option Nat
  | .literal value => some value.toNat
  | .checkedAdd lhs rhs
  | .narrowCheckedAdd _ lhs rhs => do
      let l ← constShiftCount? lhs
      let r ← constShiftCount? rhs
      let n := l + r
      if n >= 4294967296 then none else some n
  | .checkedSub lhs rhs
  | .narrowCheckedSub _ lhs rhs => do
      let l ← constShiftCount? lhs
      let r ← constShiftCount? rhs
      if l < r then none else some (l - r)
  | .checkedMul lhs rhs
  | .narrowCheckedMul _ lhs rhs => do
      let l ← constShiftCount? lhs
      let r ← constShiftCount? rhs
      let n := l * r
      if n >= 4294967296 then none else some n
  | .checkedDiv lhs rhs
  | .narrowCheckedDiv _ lhs rhs => do
      let l ← constShiftCount? lhs
      let r ← constShiftCount? rhs
      if r == 0 then none else some (l / r)
  | .checkedMod lhs rhs
  | .narrowCheckedMod _ lhs rhs => do
      let l ← constShiftCount? lhs
      let r ← constShiftCount? rhs
      if r == 0 then none else some (l % r)
  | _ => none

/-- Relation-level expression lowering. Pure calls inline the callee body at
    the call site (circuits have no call instruction); everything else maps
    to the flat temp/constraint form. -/
private partial def lowerExpr (plan : Plan) (fuel : Nat)
    (loopEnv : Array (Nat × ValueRef))
    (stateValues : Array ValueRef) (next : Nat) :
    Expr → CompileResult LoweredExpr
  | .literal value => pure { operations := #[], value := .literal value, next }
  | .bigLiteral bitWidth value => do
      unless bitWidth == 128 do
        throw <| .planInvariant .noir
          s!"unsupported Noir semantic shape: bigLiteral bitWidth {bitWidth} is not admitted"
      pure {
        operations := #[.bigLiteral next value]
        value := .temp next
        next := next + 1
      }
  | .param inputIndex => pure { operations := #[], value := .input inputIndex, next }
  | .loopParam slot =>
      match loopEnv.findSome? (fun (s, ref) => if s == slot then some ref else none) with
      | some ref => pure { operations := #[], value := ref, next }
      | none =>
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: loop parameter reference outside its loop"
  | .stateLoad fieldIndex =>
      match stateValues[fieldIndex]? with
      | some value => pure { operations := #[], value, next }
      | none =>
          throw <| .planInvariant .noir
            s!"noir stateLoad fieldIndex {fieldIndex} out of range"
  | .checkedAdd lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedAdd rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .checkedSub lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedSub rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .checkedMul lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedMul rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .checkedDiv lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedDiv rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .checkedMod lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedMod rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .fieldAdd lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.fieldAdd rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .fieldSub lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.fieldSub rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .fieldMul lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.fieldMul rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .fieldDiv lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.fieldDiv rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .bitNot operand => do
      let operand ← lowerExpr plan fuel loopEnv stateValues next operand
      pure {
        operations := operand.operations ++ #[.bitNot operand.next operand.value]
        value := .temp operand.next
        next := operand.next + 1
      }
  | .narrowCheckedAdd bitWidth lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedAdd bitWidth rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .narrowCheckedSub bitWidth lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedSub bitWidth rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .narrowCheckedMul bitWidth lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedMul bitWidth rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .narrowCheckedDiv bitWidth lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedDiv bitWidth rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .narrowCheckedMod bitWidth lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedMod bitWidth rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .narrowBitAnd bitWidth lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowBitAnd bitWidth rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .narrowBitOr bitWidth lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowBitOr bitWidth rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .narrowBitXor bitWidth lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowBitXor bitWidth rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .narrowShl bitWidth lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowShl bitWidth rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .narrowShr bitWidth lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowShr bitWidth rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .narrowBitNot bitWidth operand => do
      let operand ← lowerExpr plan fuel loopEnv stateValues next operand
      pure {
        operations := operand.operations ++ #[.narrowBitNot bitWidth operand.next operand.value]
        value := .temp operand.next
        next := operand.next + 1
      }
  | .boolNot operand => do
      let operand ← lowerExpr plan fuel loopEnv stateValues next operand
      pure {
        operations := operand.operations ++ #[.boolNot operand.next operand.value]
        value := .temp operand.next
        next := operand.next + 1
      }
  | .bitAnd lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.bitAnd rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .bitOr lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.bitOr rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .bitXor lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.bitXor rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .boolAnd lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.boolAnd rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .boolOr lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.boolOr rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .shl lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let some k := constShiftCount? rhs |
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: shift count is not a compile-time constant"
      -- count ≥ 64 renders the invalidShift guard as a literal-false
      -- constraint (inadmissible); shl ≡ x * 2^k and the checked u64
      -- multiply carries the arithmeticOverflow constraint. The folded
      -- count is UInt32-bounded but can be huge (e.g. 0xFFFFFFFF - 1), so
      -- 2^k is only evaluated for k < 64; the wrapped literal is otherwise
      -- dead inside the inadmissible constraint.
      let pow : UInt64 := if k < 64 then UInt64.ofNat (2 ^ k) else 0
      pure {
        operations := lhs.operations ++
          #[.assertConstraint (.literal (if k < 64 then 1 else 0)),
            .checkedMul lhs.next lhs.value (.literal pow)]
        value := .temp lhs.next
        next := lhs.next + 1
      }
  | .shr lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let some k := constShiftCount? rhs |
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: shift count is not a compile-time constant"
      -- shr ≡ x / 2^k (truncating); the invalidShift guard is literal when
      -- the count is out of range. 2^k is only evaluated for k < 64 (see shl).
      let pow : UInt64 := if k < 64 then UInt64.ofNat (2 ^ k) else 0
      pure {
        operations := lhs.operations ++
          #[.assertConstraint (.literal (if k < 64 then 1 else 0)),
            .checkedDiv lhs.next lhs.value (.literal pow)]
        value := .temp lhs.next
        next := lhs.next + 1
      }
  | .compare op lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.compare op rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .signedCompare op lhs rhs => do
      let lhs ← lowerExpr plan fuel loopEnv stateValues next lhs
      let rhs ← lowerExpr plan fuel loopEnv stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.signedCompare op rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .checkedNeg operand => do
      let operand ← lowerExpr plan fuel loopEnv stateValues next operand
      pure {
        operations := operand.operations ++ #[.checkedNeg operand.next operand.value]
        value := .temp operand.next
        next := operand.next + 1
      }
  | .fieldNeg operand => do
      let operand ← lowerExpr plan fuel loopEnv stateValues next operand
      pure {
        operations := operand.operations ++ #[.fieldNeg operand.next operand.value]
        value := .temp operand.next
        next := operand.next + 1
      }
  | .callFn fnIndex args => do
      let some fn := plan.fns.find? (fun binding => binding.callableId == fnIndex) |
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: pure call target is not a declared fn"
      unless args.size == fn.params.size do
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: pure call argument count mismatch"
      if fuel == 0 then
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: pure call inlining exceeds the operation limit"
      let mut acc : Array Operation := #[]
      let mut next' := next
      let mut argRefs : Array ValueRef := #[]
      for arg in args do
        let value ← lowerExpr plan fuel loopEnv stateValues next' arg
        acc := acc ++ value.operations
        argRefs := argRefs.push value.value
        next' := value.next
      let (inlineOps, result, next'') ← inlineStmtsV1 plan (fuel - 1) 1
        fn.resultIsBool argRefs stateValues next' #[] fn.body.toList
      pure {
        operations := acc ++ inlineOps
        value := result
        next := next''
      }

/-- Fn-body expression lowering: `.param` resolves against the caller's
    argument ValueRefs (inlining substitution); `.stateLoad` fails closed
    (fn purity). Everything else mirrors the relation-level lowerExpr. -/
private partial def lowerExprFn (plan : Plan) (fuel depth : Nat)
    (paramValues stateValues : Array ValueRef) (next : Nat) :
    Expr → CompileResult LoweredExpr
  | .literal value =>
      pure { operations := #[], value := .literal value, next }
  | .bigLiteral bitWidth value => do
      unless bitWidth == 128 do
        throw <| .planInvariant .noir
          s!"unsupported Noir semantic shape: bigLiteral bitWidth {bitWidth} is not admitted"
      pure {
        operations := #[.bigLiteral next value]
        value := .temp next
        next := next + 1
      }
  | .param inputIndex =>
      match paramValues[inputIndex]? with
      | some value => pure { operations := #[], value, next }
      | none =>
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: fn param reference out of range"
  | .stateLoad _ =>
      throw <| .planInvariant .noir
        "unsupported Noir semantic shape: fn body reads state"
  | .loopParam _ =>
      throw <| .planInvariant .noir
        "unsupported Noir semantic shape: loop induction reference inside an inlined fn"
  | .checkedAdd lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedAdd rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .checkedSub lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedSub rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .checkedMul lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedMul rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .checkedDiv lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedDiv rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .checkedMod lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedMod rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .fieldAdd lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.fieldAdd rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .fieldSub lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.fieldSub rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .fieldMul lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.fieldMul rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .fieldDiv lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.fieldDiv rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .bitNot operand => do
      let operand ← lowerExprFn plan fuel depth paramValues stateValues next operand
      pure {
        operations := operand.operations ++ #[.bitNot operand.next operand.value]
        value := .temp operand.next
        next := operand.next + 1
      }
  | .narrowCheckedAdd bitWidth lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedAdd bitWidth rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .narrowCheckedSub bitWidth lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedSub bitWidth rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .narrowCheckedMul bitWidth lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedMul bitWidth rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .narrowCheckedDiv bitWidth lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedDiv bitWidth rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .narrowCheckedMod bitWidth lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedMod bitWidth rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .narrowBitAnd bitWidth lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowBitAnd bitWidth rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .narrowBitOr bitWidth lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowBitOr bitWidth rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .narrowBitXor bitWidth lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowBitXor bitWidth rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .narrowShl bitWidth lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowShl bitWidth rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .narrowShr bitWidth lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowShr bitWidth rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .narrowBitNot bitWidth operand => do
      let operand ← lowerExprFn plan fuel depth paramValues stateValues next operand
      pure {
        operations := operand.operations ++ #[.narrowBitNot bitWidth operand.next operand.value]
        value := .temp operand.next
        next := operand.next + 1
      }
  | .boolNot operand => do
      let operand ← lowerExprFn plan fuel depth paramValues stateValues next operand
      pure {
        operations := operand.operations ++ #[.boolNot operand.next operand.value]
        value := .temp operand.next
        next := operand.next + 1
      }
  | .bitAnd lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.bitAnd rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .bitOr lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.bitOr rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .bitXor lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.bitXor rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .boolAnd lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.boolAnd rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .boolOr lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.boolOr rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .shl lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let some k := constShiftCount? rhs |
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: shift count is not a compile-time constant"
      let pow : UInt64 := UInt64.ofNat (2 ^ k)
      pure {
        operations := lhs.operations ++
          #[.assertConstraint (.literal (if k < 64 then 1 else 0)),
            .checkedMul lhs.next lhs.value (.literal pow)]
        value := .temp lhs.next
        next := lhs.next + 1
      }
  | .shr lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let some k := constShiftCount? rhs |
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: shift count is not a compile-time constant"
      let pow : UInt64 := UInt64.ofNat (2 ^ k)
      pure {
        operations := lhs.operations ++
          #[.assertConstraint (.literal (if k < 64 then 1 else 0)),
            .checkedDiv lhs.next lhs.value (.literal pow)]
        value := .temp lhs.next
        next := lhs.next + 1
      }
  | .compare op lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.compare op rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .signedCompare op lhs rhs => do
      let lhs ← lowerExprFn plan fuel depth paramValues stateValues next lhs
      let rhs ← lowerExprFn plan fuel depth paramValues stateValues lhs.next rhs
      pure {
        operations := lhs.operations ++ rhs.operations ++
          #[.signedCompare op rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .checkedNeg operand => do
      let operand ← lowerExprFn plan fuel depth paramValues stateValues next operand
      pure {
        operations := operand.operations ++ #[.checkedNeg operand.next operand.value]
        value := .temp operand.next
        next := operand.next + 1
      }
  | .fieldNeg operand => do
      let operand ← lowerExprFn plan fuel depth paramValues stateValues next operand
      pure {
        operations := operand.operations ++ #[.fieldNeg operand.next operand.value]
        value := .temp operand.next
        next := operand.next + 1
      }
  | .callFn fnIndex args => do
      let some fn := plan.fns.find? (fun binding => binding.callableId == fnIndex) |
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: nested pure call target is not a declared fn"
      unless args.size == fn.params.size do
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: nested pure call argument count mismatch"
      if fuel == 0 then
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: pure call inlining exceeds the operation limit"
      if depth > plan.fns.size then
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: pure call inlining exceeds the fn depth bound"
      let mut acc : Array Operation := #[]
      let mut next' := next
      let mut argRefs : Array ValueRef := #[]
      for arg in args do
        let value ← lowerExprFn plan fuel depth paramValues stateValues next' arg
        acc := acc ++ value.operations
        argRefs := argRefs.push value.value
        next' := value.next
      let (inlineOps, result, next'') ← inlineStmtsV1 plan (fuel - 1) (depth + 1)
        fn.resultIsBool argRefs stateValues next' #[] fn.body.toList
      pure {
        operations := acc ++ inlineOps
        value := result
        next := next''
      }

/-- Inline a pure-fn statement tree at a call site: path-enumerate with
    params substituted by the caller's argument ValueRefs. Regions produce
    result-selecting temps (Noir block-valued if/else-if expressions), so the
    enclosing expression keeps a single result value per path. Reverting
    paths emit assert(false) (inadmissible, discarding any partial path). -/
private partial def inlineStmtsV1
    (plan : Plan) (fuel depth : Nat) (resultIsBool : Bool)
    (paramValues stateValues : Array ValueRef) (next : Nat)
    (acc : Array Operation) (statements : List Statement) :
    CompileResult (Array Operation × ValueRef × Nat) := do
  match statements with
  | [] =>
      throw <| .planInvariant .noir
        "unsupported Noir semantic shape: fn body path does not end in a return"
  | statement :: rest =>
      if fuel == 0 then
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: pure call inlining exceeds the operation limit"
      let fuel := fuel - 1
      match statement with
      | .store _ =>
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: fn body writes state"
      | .emitEvent .. =>
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: fn body emits an event"
      | .externalCall .. =>
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: fn body makes an external call"
      | .schedule .. =>
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: fn body schedules a workflow"
      | .forLoop .. =>
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: loops inside fn bodies are outside the Noir pilot"
      | .assert condition => do
          let value ← lowerExprFn plan fuel depth paramValues stateValues next condition
          inlineStmtsV1 plan fuel depth resultIsBool paramValues stateValues value.next
            (acc ++ value.operations ++ #[.assertConstraint value.value]) rest
      | .returnValue valueExpr => do
          unless rest.isEmpty do
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: fn body has a statement after a return"
          let value ← lowerExprFn plan fuel depth paramValues stateValues next valueExpr
          pure (acc ++ value.operations, value.value, value.next)
      | .returnNone =>
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: fn body must return a value"
      | .revertError _ args => do
          unless rest.isEmpty do
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: fn body has a statement after a revert"
          let mut acc' := acc
          let mut next' := next
          for arg in args do
            let value ← lowerExprFn plan fuel depth paramValues stateValues next' arg
            acc' := acc' ++ value.operations
            next' := value.next
          pure (acc' ++ #[.assertConstraint (.literal 0)], .literal 0, next')
      | .ifThenElse condition thenBody elseBody => do
          let condition ← lowerExprFn plan fuel depth paramValues stateValues next condition
          if statementListClosesV1 thenBody.toList &&
              statementListClosesV1 elseBody.toList && !rest.isEmpty then
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: fn body has a continuation after a closed region"
          let fold := fun (arm : Array Statement) =>
            if statementListClosesV1 arm.toList then arm.toList else arm.toList ++ rest
          let (thenOps, thenValue, next1) ← inlineStmtsV1 plan fuel depth resultIsBool
            paramValues stateValues condition.next #[] (fold thenBody)
          let (elseOps, elseValue, next2) ← inlineStmtsV1 plan fuel depth resultIsBool
            paramValues stateValues next1 #[] (fold elseBody)
          let destination := next2
          pure (acc ++ condition.operations ++ #[
              .selectRegion destination condition.value resultIsBool
                thenOps thenValue elseOps elseValue
            ], .temp destination, next2 + 1)
      | .switchOn scrutineeExpr cases defaultBody => do
          let scrutIsBool := match scrutineeExpr with
            | .compare .. => true
            | _ => false
          let scrutinee ← lowerExprFn plan fuel depth paramValues stateValues next scrutineeExpr
          if statementListClosesV1 defaultBody.toList &&
              (cases.all fun (_, caseBody) => statementListClosesV1 caseBody.toList) &&
              !rest.isEmpty then
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: fn body has a continuation after a closed region"
          let fold := fun (arm : Array Statement) =>
            if statementListClosesV1 arm.toList then arm.toList else arm.toList ++ rest
          let mut caseOps : Array (UInt64 × Array Operation × ValueRef) := #[]
          let mut nextAcc := scrutinee.next
          for (caseValue, caseBody) in cases do
            let (operations, value, next') ← inlineStmtsV1 plan fuel depth resultIsBool
              paramValues stateValues nextAcc #[] (fold caseBody)
            caseOps := caseOps.push (caseValue, operations, value)
            nextAcc := next'
          let (defaultOps, defaultValue, next') ← inlineStmtsV1 plan fuel depth resultIsBool
            paramValues stateValues nextAcc #[] (fold defaultBody)
          let destination := next'
          pure (acc ++ scrutinee.operations ++ #[
              .selectSwitch destination scrutinee.value scrutIsBool resultIsBool
                caseOps defaultOps defaultValue
            ], .temp destination, next' + 1)

end

/-- The per-relation static effect slots: event arg slots, external-call
    status/arg slots, and schedule arg slots, all keyed by the shared
    canonical EffectId sequence. -/
private structure RelationSlotsV1 where
  emit : Array (Nat × Nat × Nat)
  call : Array (Nat × Nat)
  schedule : Array (Nat × Nat)

/-- Resolve a path-recorded effect-arg value, or zero when the path never
    executed that effect. Fail closed if the recorded arity is shorter than
    the static slot table (plan-internal invariant). -/
private def pathEffectArgValueV1 (pathEmits : Array (Nat × Array ValueRef))
    (effectId argIndex : Nat) (slotKind : String) : CompileResult ValueRef := do
  match pathEmits.findSome? (fun (slotId, values) =>
      if slotId == effectId then some values else none) with
  | none => pure (.literal 0)
  | some values =>
      match values[argIndex]? with
      | some v => pure v
      | none =>
          throw <| .planInvariant .noir
            s!"noir path {slotKind} arg index {argIndex} out of range for effect {effectId}"

/-- Final path assertions: post-state equality per field, post-initialized
    flag, (non-initializer) the public result binding, and event-slot
    bindings. Each static emit in `emitSlots` binds its argument slots to the
    values recorded on this path, or to zero on paths that did not execute it
    (and on reverted paths, whose effects are discarded). Fail-closed on
    missing post-state/result/path-arg plan-internal invariants (no bang). -/
private def leafAssertions (plan : Plan) (relation : Relation)
    (emitSlots : Array (Nat × Nat × Nat))
    (callSlots : Array (Nat × Nat)) (scheduleSlots : Array (Nat × Nat))
    (stateValues : Array ValueRef) (returned : Option ValueRef)
    (pathEmits : Array (Nat × Array ValueRef)) : CompileResult (Array Operation) := do
  let mut operations : Array Operation := #[]
  for field in plan.states do
    match stateValues[field.sourceId]? with
    | none =>
        throw <| .planInvariant .noir
          s!"noir post-state value missing for field sourceId {field.sourceId}"
    | some stateValue =>
        operations := operations.push <| .assertEqual
          (.input (inputIndexFor relation (.postState field.sourceId)))
          stateValue
  if !plan.states.isEmpty then
    operations := operations.push <| .assertBool
      (inputIndexFor relation .postInitialized) true
  if relation.mode != .initialize then
    match returned with
    | some v =>
        operations := operations.push <| .assertEqual
          (.input (inputIndexFor relation .result)) v
    | none =>
        throw <| .planInvariant .noir
          "noir relation result missing outside initialize"
  for (effectId, _, argCount) in emitSlots do
    for argIndex in [0:argCount] do
      let value ← pathEffectArgValueV1 pathEmits effectId argIndex "emit"
      operations := operations.push <| .assertEqual
        (.input (inputIndexFor relation (.eventSlot effectId argIndex))) value
  for (effectId, argCount) in callSlots do
    let pathValues? := pathEmits.findSome? fun (slotId, values) =>
      if slotId == effectId then some values else none
    for argIndex in [0:argCount] do
      let value ← pathEffectArgValueV1 pathEmits effectId argIndex "call"
      operations := operations.push <| .assertEqual
        (.input (inputIndexFor relation (.callArgSlot effectId argIndex))) value
    -- Status witness: true when this path executed the call (a returned
    -- response); false on paths that never made it.
    operations := operations.push <| .assertBool
      (inputIndexFor relation (.callStatus effectId)) pathValues?.isSome
  for (effectId, argCount) in scheduleSlots do
    for argIndex in [0:argCount] do
      let value ← pathEffectArgValueV1 pathEmits effectId argIndex "schedule"
      operations := operations.push <| .assertEqual
        (.input (inputIndexFor relation (.scheduleArgSlot effectId argIndex))) value
  pure operations

/-- Reverted path assertions: every event slot zeroed (effects are discarded
    on revert) and the path marked inadmissible — a reverting call admits no
    post-state or result witness. -/
private def revertAssertions (relation : Relation)
    (emitSlots : Array (Nat × Nat × Nat))
    (callSlots : Array (Nat × Nat)) (scheduleSlots : Array (Nat × Nat)) :
    Array Operation := Id.run do
  let mut operations : Array Operation := #[]
  for (effectId, _, argCount) in emitSlots do
    for argIndex in [0:argCount] do
      operations := operations.push <| .assertEqual
        (.input (inputIndexFor relation (.eventSlot effectId argIndex))) (.literal 0)
  for (effectId, argCount) in callSlots do
    for argIndex in [0:argCount] do
      operations := operations.push <| .assertEqual
        (.input (inputIndexFor relation (.callArgSlot effectId argIndex))) (.literal 0)
    operations := operations.push <| .assertBool
      (inputIndexFor relation (.callStatus effectId)) false
  for (effectId, argCount) in scheduleSlots do
    for argIndex in [0:argCount] do
      operations := operations.push <| .assertEqual
        (.input (inputIndexFor relation (.scheduleArgSlot effectId argIndex))) (.literal 0)
  operations.push (.assertConstraint (.literal 0))

/-- Continuation invoked at an open path leaf (a fall-through with no
    statements left): the default ends initializer paths; a loop body's
    continuation descends into the next unrolling level. Takes the current
    state environment, temp counter, path emits, and accumulated ops. -/
private abbrev OpenLeafV1 :=
  Array ValueRef → Nat → Array (Nat × Array ValueRef) → Array Operation →
    CompileResult (Array Operation × Nat)

/-- Default open leaf: only the initializer's implicit fallthrough may reach
    it; every other relation path must end in a return or declared revert. -/
private def defaultOpenLeafV1 (plan : Plan) (relation : Relation)
    (slots : RelationSlotsV1) : OpenLeafV1 :=
  fun stateValues next pathEmits acc => do
    unless relation.mode == .initialize do
      throw <| .planInvariant .noir
        s!"relation '{relation.name}' path does not end in a return"
    let assertions ← leafAssertions plan relation slots.emit slots.call slots.schedule
      stateValues none pathEmits
    pure (acc ++ assertions, next)

mutual

/-- Lower a relation statement list into a complete path constraint sequence
    (path enumeration). A region folds the enclosing continuation into each
    of its open arms, so every walk ends at a leaf — a return marker, a
    declared revert, or the open-leaf continuation — which emits its own
    post-state/result/event-slot assertions. Straight-line walking is
    tail-recursive; only region arm recursion nests (bounded by statement
    nesting). Path duplication from sequential diamonds is bounded by `fuel`
    and fails closed. -/
private partial def lowerPathStatementsV1
    (plan : Plan) (relation : Relation) (fuel : Nat)
    (slots : RelationSlotsV1)
    (loopEnv : Array (Nat × ValueRef))
    (openLeaf : OpenLeafV1)
    (stateValues : Array ValueRef) (next : Nat)
    (pathEmits : Array (Nat × Array ValueRef))
    (acc : Array Operation) (statements : List Statement) :
    CompileResult (Array Operation × Nat) := do
  match statements with
  | [] =>
      -- Open leaf: the continuation decides (initializer fallthrough by
      -- default, loop-level descent inside loop bodies).
      openLeaf stateValues next pathEmits acc
  | statement :: rest =>
      if fuel == 0 then
        throw <| .planInvariant .noir
          s!"relation '{relation.name}' path expansion exceeds the operation limit"
      let fuel := fuel - 1
      match statement with
      | .store store =>
          let value ← lowerExpr plan fuel loopEnv stateValues next store.value
          lowerPathStatementsV1 plan relation fuel slots loopEnv openLeaf
            (stateValues.set! store.fieldIndex value.value) value.next pathEmits
            (acc ++ value.operations) rest
      | .assert condition =>
          let value ← lowerExpr plan fuel loopEnv stateValues next condition
          lowerPathStatementsV1 plan relation fuel slots loopEnv openLeaf
            stateValues value.next
            pathEmits (acc ++ value.operations ++ #[.assertConstraint value.value]) rest
      | .emitEvent effectId _ args =>
          -- Evaluate args into the current path; the slot binding lands at
          -- the path leaf (path-dependent), not at the emission point.
          let mut acc' := acc
          let mut next' := next
          let mut argRefs : Array ValueRef := #[]
          for arg in args do
            let value ← lowerExpr plan fuel loopEnv stateValues next' arg
            acc' := acc' ++ value.operations
            argRefs := argRefs.push value.value
            next' := value.next
          lowerPathStatementsV1 plan relation fuel slots loopEnv openLeaf
            stateValues next'
            (pathEmits.push (effectId, argRefs)) acc' rest
      | .externalCall effectId _ args =>
          -- Evaluate args into the current path; arg slot and status
          -- bindings land at the path leaf.
          let mut acc' := acc
          let mut next' := next
          let mut argRefs : Array ValueRef := #[]
          for arg in args do
            let value ← lowerExpr plan fuel loopEnv stateValues next' arg
            acc' := acc' ++ value.operations
            argRefs := argRefs.push value.value
            next' := value.next
          lowerPathStatementsV1 plan relation fuel slots loopEnv openLeaf
            stateValues next'
            (pathEmits.push (effectId, argRefs)) acc' rest
      | .schedule effectId _ args =>
          -- Evaluate args into the current path; schedule arg slot bindings
          -- land at the path leaf (fire-and-forget: no status exists).
          let mut acc' := acc
          let mut next' := next
          let mut argRefs : Array ValueRef := #[]
          for arg in args do
            let value ← lowerExpr plan fuel loopEnv stateValues next' arg
            acc' := acc' ++ value.operations
            argRefs := argRefs.push value.value
            next' := value.next
          lowerPathStatementsV1 plan relation fuel slots loopEnv openLeaf
            stateValues next'
            (pathEmits.push (effectId, argRefs)) acc' rest
      | .returnValue valueExpr =>
          unless rest.isEmpty do
            throw <| .planInvariant .noir
              s!"relation '{relation.name}' has a statement after a return"
          let value ← lowerExpr plan fuel loopEnv stateValues next valueExpr
          let assertions ← leafAssertions plan relation slots.emit slots.call slots.schedule
            stateValues (some value.value) pathEmits
          pure (acc ++ value.operations ++ assertions, value.next)
      | .returnNone =>
          unless rest.isEmpty do
            throw <| .planInvariant .noir
              s!"relation '{relation.name}' has a statement after a return"
          let assertions ← leafAssertions plan relation slots.emit slots.call slots.schedule
            stateValues none pathEmits
          pure (acc ++ assertions, next)
      | .revertError _ args =>
          unless rest.isEmpty do
            throw <| .planInvariant .noir
              s!"relation '{relation.name}' has a statement after a revert"
          -- Revert args are evaluated for their checked-arithmetic failure
          -- constraints (they execute before the revert), then the path is
          -- marked inadmissible with every event slot zeroed.
          let mut acc' := acc
          let mut next' := next
          for arg in args do
            let value ← lowerExpr plan fuel loopEnv stateValues next' arg
            acc' := acc' ++ value.operations
            next' := value.next
          pure (acc' ++ revertAssertions relation slots.emit slots.call slots.schedule, next')
      | .ifThenElse condition thenBody elseBody =>
          let condition ← lowerExpr plan fuel loopEnv stateValues next condition
          -- Emission invariant: a region followed by a continuation always
          -- has at least one open arm (the continuation folds into it).
          if statementListClosesV1 thenBody.toList &&
              statementListClosesV1 elseBody.toList && !rest.isEmpty then
            throw <| .planInvariant .noir
              s!"relation '{relation.name}' has a continuation after a closed region"
          let fold := fun (arm : Array Statement) =>
            if statementListClosesV1 arm.toList then arm.toList else arm.toList ++ rest
          let (thenOps, next1) ← lowerPathStatementsV1 plan relation fuel slots
            loopEnv openLeaf stateValues condition.next pathEmits #[] (fold thenBody)
          let (elseOps, next2) ← lowerPathStatementsV1 plan relation fuel slots
            loopEnv openLeaf stateValues next1 pathEmits #[] (fold elseBody)
          pure (acc ++ condition.operations ++
            #[.ifRegion condition.value thenOps elseOps], next2)
      | .switchOn scrutineeExpr cases defaultBody =>
          -- Bool scrutinees arise only from comparison expressions in this
          -- envelope (Bool state/params fail closed at the plan boundary).
          let scrutIsBool := match scrutineeExpr with
            | .compare .. => true
            | _ => false
          let scrutinee ← lowerExpr plan fuel loopEnv stateValues next scrutineeExpr
          if statementListClosesV1 defaultBody.toList &&
              (cases.all fun (_, caseBody) => statementListClosesV1 caseBody.toList) &&
              !rest.isEmpty then
            throw <| .planInvariant .noir
              s!"relation '{relation.name}' has a continuation after a closed region"
          let fold := fun (arm : Array Statement) =>
            if statementListClosesV1 arm.toList then arm.toList else arm.toList ++ rest
          let mut caseOps : Array (UInt64 × Array Operation) := #[]
          let mut nextAcc := scrutinee.next
          for (caseValue, caseBody) in cases do
            let (operations, next') ← lowerPathStatementsV1 plan relation fuel slots
              loopEnv openLeaf stateValues nextAcc pathEmits #[] (fold caseBody)
            caseOps := caseOps.push (caseValue, operations)
            nextAcc := next'
          let (defaultOps, next') ← lowerPathStatementsV1 plan relation fuel slots
            loopEnv openLeaf stateValues nextAcc pathEmits #[] (fold defaultBody)
          pure (acc ++ scrutinee.operations ++
            #[.switchRegion scrutinee.value scrutIsBool caseOps defaultOps], next')
      | .forLoop slot bound initE condE updateE body => do
          -- One static effect slot cannot bind multiple dynamic occurrences.
          unless (collectEmitSlots body).isEmpty &&
              (collectCallSlots body).isEmpty &&
              (collectScheduleSlots body).isEmpty do
            throw <| .planInvariant .noir
              s!"relation '{relation.name}' has an effect statement inside a loop"
          let init ← lowerExpr plan fuel loopEnv stateValues next initE
          lowerLoopLevelV1 plan relation fuel slots slot bound condE updateE body
            0 init.value loopEnv openLeaf stateValues init.next pathEmits
            (acc ++ init.operations) rest

/-- One unrolling level of a `forLoop`: evaluate the condition against the
    current induction value, then nest the gated body level (which descends
    through the update) beside the exit continuation. At the static bound
    the body still walks (returns inside it complete normally) but its open
    leaf — the back edge — is inadmissible, mirroring the reference
    machine's boundExceeded revert on the back edge after the (bound+1)-th
    body execution. The exit arm always continues with the post-loop
    statements from this level's environment. -/
private partial def lowerLoopLevelV1
    (plan : Plan) (relation : Relation) (fuel : Nat)
    (slots : RelationSlotsV1)
    (slot : Nat) (bound : UInt32) (condE updateE : Expr) (body : Array Statement)
    (level : Nat) (iRef : ValueRef)
    (loopEnv : Array (Nat × ValueRef))
    (openLeaf : OpenLeafV1)
    (stateValues : Array ValueRef) (next : Nat)
    (pathEmits : Array (Nat × Array ValueRef))
    (acc : Array Operation) (rest : List Statement) :
    CompileResult (Array Operation × Nat) := do
  if fuel == 0 then
    throw <| .planInvariant .noir
      s!"relation '{relation.name}' loop unrolling exceeds the operation limit"
  let fuel := fuel - 1
  let loopEnvK := (loopEnv.filter (·.1 != slot)).push (slot, iRef)
  let cond ← lowerExpr plan fuel loopEnvK stateValues next condE
  -- Exit continuation: walk the post-loop statements from this level's
  -- environment (reached when the condition first fails).
  let exitWalk := fun (nx : Nat) =>
    lowerPathStatementsV1 plan relation fuel slots loopEnv openLeaf
      stateValues nx pathEmits #[] rest
  if level ≥ bound.toNat then
    -- Exact back-edge placement: the (bound+1)-th body still executes (a
    -- return inside it completes the path normally); only its open leaf —
    -- the back edge — reverts, rendered as an inadmissible assertion. Body
    -- values flowing into the discarded state environment are anchored by
    -- trivial self-equalities so their checked-arithmetic failure stays
    -- constrained for the liveness gate (the path rejects regardless).
    let boundLeaf : OpenLeafV1 := fun sv nx _ ac => do
      let mut anchored := ac
      for ref in sv do
        match ref with
        | .temp _ => anchored := anchored.push (.assertEqual ref ref)
        | _ => pure ()
      pure (anchored.push (.assertConstraint (.literal 0)), nx)
    let (thenOps, thenNext) ← lowerPathStatementsV1 plan relation fuel slots
      loopEnvK boundLeaf stateValues cond.next pathEmits #[] body.toList
    let (exitOps, exitNext) ← exitWalk thenNext
    pure (acc ++ cond.operations ++ #[.ifRegion cond.value thenOps exitOps], exitNext)
  else do
    -- The body's open leaf evaluates the update and descends one level.
    let bodyLeaf : OpenLeafV1 := fun sv nx pe ac => do
      let update ← lowerExpr plan fuel loopEnvK sv nx updateE
      lowerLoopLevelV1 plan relation fuel slots slot bound condE updateE body
        (level + 1) update.value loopEnv openLeaf sv update.next pe
        (ac ++ update.operations) rest
    let (thenOps, thenNext) ← lowerPathStatementsV1 plan relation fuel slots
      loopEnvK bodyLeaf stateValues cond.next pathEmits #[] body.toList
    let (exitOps, exitNext) ← exitWalk thenNext
    pure (acc ++ cond.operations ++ #[.ifRegion cond.value thenOps exitOps], exitNext)

end

private def lowerRelation (plan : Plan) (relation : Relation) :
    CompileResult RelationIR := do
  let mut stateValues : Array ValueRef := #[]
  for field in plan.states do
    stateValues := stateValues.push <| if relation.mode == .initialize then
      .literal 0
    else
      .input (inputIndexFor relation (.preState field.sourceId))
  let mut operations : Array Operation := #[]
  if !plan.states.isEmpty then
    operations := operations.push <| .assertBool
      (inputIndexFor relation .preInitialized) (relation.mode != .initialize)
  let slots : RelationSlotsV1 := {
    emit := collectEmitSlots relation.body
    call := collectCallSlots relation.body
    schedule := collectScheduleSlots relation.body
  }
  let (pathOps, next) ← lowerPathStatementsV1 plan relation
    plan.resourceLimits.maxIrOperations slots #[]
    (defaultOpenLeafV1 plan relation slots)
    stateValues 0 #[] #[] relation.body.toList
  pure {
    sourceRelation := relation
    tempCount := next
    operations := operations ++ pathOps
  }

private def expectedRelations (plan : Plan) : CompileResult (Array RelationIR) :=
  plan.relations.mapM (lowerRelation plan)

private def addLiveTemp (live : Array Nat) : ValueRef → Array Nat
  | .temp index => if live.contains index then live else live.push index
  | .input .. | .literal .. => live

/-- Noir may eliminate an unused checked integer expression, including its
failure constraint. Reject every checked add/sub/compare result that is not
transitively consumed by a final equality, assert, or region condition. Each
region arm is a complete self-contained path, so a temp defined inside an arm
must be consumed within that same arm; a temp defined before a region may be
consumed inside any arm (it stays live for the enclosing walk). -/
private partial def collectLiveTempsV1 (relationName : String)
    (operations : Array Operation) (live0 : Array Nat) :
    CompileResult (Array Nat) := do
  let mut live := live0
  for offset in [0:operations.size] do
    let operation := operations[operations.size - 1 - offset]!
    match operation with
    | .assertEqual lhs rhs =>
        live := addLiveTemp (addLiveTemp live lhs) rhs
    | .assertConstraint condition =>
        live := addLiveTemp live condition
    | .assertBool .. => pure ()
    | .ifRegion condition thenOps elseOps =>
        live := addLiveTemp live condition
        live ← collectLiveTempsV1 relationName thenOps live
        live ← collectLiveTempsV1 relationName elseOps live
    | .switchRegion scrutinee _ cases defaultOps =>
        live := addLiveTemp live scrutinee
        for (_, caseOps) in cases do
          live ← collectLiveTempsV1 relationName caseOps live
        live ← collectLiveTempsV1 relationName defaultOps live
    | .selectRegion destination condition _ thenOps thenValue elseOps elseValue =>
        -- The select result is consumed downstream (it is a def whose uses
        -- appear later); the arm tail values are roots (they feed it).
        unless live.contains destination do
          throw <| .planInvariant .noir
            s!"relation '{relationName}' contains dead checked arithmetic whose failure would not be constrained"
        live := addLiveTemp (addLiveTemp (addLiveTemp live condition) thenValue) elseValue
        live ← collectLiveTempsV1 relationName thenOps live
        live ← collectLiveTempsV1 relationName elseOps live
    | .selectSwitch destination scrutinee _ _ cases defaultOps defaultValue =>
        unless live.contains destination do
          throw <| .planInvariant .noir
            s!"relation '{relationName}' contains dead checked arithmetic whose failure would not be constrained"
        live := addLiveTemp (addLiveTemp live scrutinee) defaultValue
        for (_, caseOps, caseValue) in cases do
          live := addLiveTemp live caseValue
          live ← collectLiveTempsV1 relationName caseOps live
        live ← collectLiveTempsV1 relationName defaultOps live
    | .checkedAdd destination lhs rhs
    | .checkedSub destination lhs rhs
    | .checkedMul destination lhs rhs
    | .checkedDiv destination lhs rhs
    | .checkedMod destination lhs rhs
    | .narrowCheckedAdd _ destination lhs rhs
    | .narrowCheckedSub _ destination lhs rhs
    | .narrowCheckedMul _ destination lhs rhs
    | .narrowCheckedDiv _ destination lhs rhs
    | .narrowCheckedMod _ destination lhs rhs
    | .narrowBitAnd _ destination lhs rhs
    | .narrowBitOr _ destination lhs rhs
    | .narrowBitXor _ destination lhs rhs
    | .narrowShl _ destination lhs rhs
    | .narrowShr _ destination lhs rhs
    | .fieldAdd destination lhs rhs
    | .fieldSub destination lhs rhs
    | .fieldMul destination lhs rhs
    | .fieldDiv destination lhs rhs
    | .bitAnd destination lhs rhs
    | .bitOr destination lhs rhs
    | .bitXor destination lhs rhs
    | .boolAnd destination lhs rhs
    | .boolOr destination lhs rhs
    | .compare _ destination lhs rhs
    | .signedCompare _ destination lhs rhs =>
        unless live.contains destination do
          throw <| .planInvariant .noir
            s!"relation '{relationName}' contains dead checked arithmetic whose failure would not be constrained"
        live := addLiveTemp (addLiveTemp live lhs) rhs
    | .bitNot destination source
    | .narrowBitNot _ destination source
    | .boolNot destination source
    | .checkedNeg destination source
    | .fieldNeg destination source =>
        unless live.contains destination do
          throw <| .planInvariant .noir
            s!"relation '{relationName}' contains dead unary arithmetic whose value would not be constrained"
        live := addLiveTemp live source
    | .bigLiteral destination _value =>
        -- Pure materialization of a Plan constant; dead only if unused.
        unless live.contains destination do
          throw <| .planInvariant .noir
            s!"relation '{relationName}' contains a dead UInt128 literal"
  pure live

private def validateCheckedArithmeticLiveness
    (relation : RelationIR) : CompileResult Unit := do
  let _ ← collectLiveTempsV1 relation.sourceRelation.name relation.operations #[]
  pure ()

/-- Total operation count including region arm bodies (the top-level list
    size alone would let nested regions evade the resource limit). -/
private partial def countOperationsV1 (operations : Array Operation) : Nat :=
  operations.foldl (fun total operation => total + match operation with
    | .ifRegion _ thenOps elseOps =>
        1 + countOperationsV1 thenOps + countOperationsV1 elseOps
    | .switchRegion _ _ cases defaultOps =>
        1 + countOperationsV1 defaultOps +
          (cases.foldl (fun subtotal (_, caseOps) =>
            subtotal + countOperationsV1 caseOps) 0)
    | .selectRegion _ _ _ thenOps _ elseOps _ =>
        1 + countOperationsV1 thenOps + countOperationsV1 elseOps
    | .selectSwitch _ _ _ _ cases defaultOps _ =>
        1 + countOperationsV1 defaultOps +
          (cases.foldl (fun subtotal (_, caseOps, _) =>
            subtotal + countOperationsV1 caseOps) 0)
    | _ => 1) 0

def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless ir.name == ir.sourcePlan.programName &&
      ir.relations.size == ir.sourcePlan.relations.size do
    throw <| .planInvariant .noir "typed Noir IR identity/catalog is not bound to its Plan"
  let limit := ir.sourcePlan.resourceLimits.maxIrOperations
  let mut operationCount := 0
  for relation in ir.relations do
    if relation.tempCount > limit - operationCount then
      throw <| .planInvariant .noir "typed Noir IR exceeds operation limit"
    operationCount := operationCount + relation.tempCount
    if countOperationsV1 relation.operations > limit - operationCount then
      throw <| .planInvariant .noir "typed Noir IR exceeds operation limit"
    operationCount := operationCount + countOperationsV1 relation.operations
    validateCheckedArithmeticLiveness relation
  let expected ← expectedRelations ir.sourcePlan
  unless ir.relations == expected do
    throw <| .planInvariant .noir
      "typed Noir IR operations are not the exact lowering of their source Plan"

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let relations ← expectedRelations plan
  let ir : IR := {
    sourcePlan := plan
    name := plan.programName
    relations := relations
  }
  validateIR ir
  return ir


private def narrowUintMaskImm (bitWidth : Nat) : Nat :=
  match bitWidth with
  | 8 => 255
  | 16 => 65535
  | 32 => 4294967295
  | 128 => 0  -- full u128; mask unused for bitNot u128 (native !)
  | _ => 0

/-- Render a ValueRef. Narrow ABI public inputs (u8/u16/u32, T8b) zero-extend
    into the UInt64 body pilot via `as u64` so checked arithmetic stays on the
    historical u64 surface until T8d. Field/bool/u64/u128 inputs keep their
    names (T11: native u128 surface). -/
private def renderValue (relation : Relation) : ValueRef → String
  | .input index =>
      let input := relation.inputs[index]!
      match input.type with
      | .u8 | .u16 | .u32 => s!"({input.name} as u64)"
      | .i8 | .i16 | .i32 | .i64 => s!"({input.name} as u64)"
      | .u64 | .u128 | .bool | .field => input.name
  | .literal value => toString value.toNat
  | .temp index => s!"t{index}"

/-- Render a ValueRef coerced to native Noir `u128` (T11 multi-limb surface). -/
private def renderValueAsU128 (relation : Relation) : ValueRef → String
  | .input index =>
      let input := relation.inputs[index]!
      match input.type with
      | .u128 => input.name
      | .u64 | .u8 | .u16 | .u32 => s!"({input.name} as u128)"
      | .i8 | .i16 | .i32 | .i64 => s!"({input.name} as u128)"
      | .bool | .field => s!"({input.name} as u128)"
  | .literal value => s!"({value.toNat} as u128)"
  | .temp index => s!"(t{index} as u128)"

private def renderComparisonOp : ComparisonOp → String
  | .eq => "=="
  | .ne => "!="
  | .lt => "<"
  | .le => "<="
  | .gt => ">"
  | .ge => ">="

/-- Render a condition ValueRef for `assert(...)`. Bool plan literals are
encoded as UInt64 0/1 and surface as native Noir `true`/`false`. -/
private def renderAssertCondition (relation : Relation) : ValueRef → String
  | .literal 0 => "false"
  | .literal 1 => "true"
  | value => renderValue relation value

/-- True when an assertEqual involves a Bool-typed public input (result or
    lifecycle flag). Bool plan literals are UInt64 0/1 and must surface as
    native Noir `true`/`false` on the equality. -/
private def assertEqualUsesBool (relation : Relation) (lhs rhs : ValueRef) : Bool :=
  let isBoolInput : ValueRef → Bool
    | .input index =>
        match relation.inputs[index]? with
        | some input => input.type == .bool
        | none => false
    | _ => false
  isBoolInput lhs || isBoolInput rhs

/-- Native Noir type string for a narrow ABI input, used when casting a u64
    body temp down to match a post-state/public equality operand. -/
private def narrowInputTypeString? : InputType → Option String
  | .u8 => some "u8"
  | .u16 => some "u16"
  | .u32 => some "u32"
  | .u128 => some "u128"
  | .i8 => some "i8"
  | .i16 => some "i16"
  | .i32 => some "i32"
  | .i64 => some "i64"
  | .u64 | .bool | .field => none

/-- Equality operands for assertEqual. Narrow post-state/public inputs keep
    their native Noir type; the paired body u64 word (temp/literal) is cast
    down so `assert(post_u8 == (t as u8))` type-checks. -/
private def renderEqualOperand (relation : Relation) (asBool : Bool)
    (peer : ValueRef) : ValueRef → String
  | .literal value =>
      if asBool then
        if value == 0 then "false" else "true"
      else
        match peer with
        | .input index =>
            match relation.inputs[index]? with
            | some input =>
                match narrowInputTypeString? input.type with
                | some ty => s!"({value.toNat} as {ty})"
                | none => toString value.toNat
            | none => toString value.toNat
        | _ => toString value.toNat
  | .input index =>
      -- Keep native type on the input side of equality.
      relation.inputs[index]!.name
  | .temp index =>
      match peer with
      | .input pidx =>
          match relation.inputs[pidx]? with
          | some input =>
              match narrowInputTypeString? input.type with
              | some ty => s!"(t{index} as {ty})"
              | none => s!"t{index}"
          | none => s!"t{index}"
      | _ => s!"t{index}"

private partial def renderOperation (relation : Relation) (indent : String) :
    Operation → String
  | .checkedAdd destination lhs rhs =>
      s!"{indent}let t{destination}: u64 = {renderValue relation lhs} + {renderValue relation rhs};\n"
  | .checkedSub destination lhs rhs =>
      s!"{indent}assert({renderValue relation lhs} >= {renderValue relation rhs});\n" ++
        s!"{indent}let t{destination}: u64 = {renderValue relation lhs} - {renderValue relation rhs};\n"
  | .checkedMul destination lhs rhs =>
      s!"{indent}let t{destination}: u64 = {renderValue relation lhs} * {renderValue relation rhs};\n"
  | .checkedDiv destination lhs rhs =>
      s!"{indent}assert({renderValue relation rhs} != 0);\n" ++
        s!"{indent}let t{destination}: u64 = {renderValue relation lhs} / {renderValue relation rhs};\n"
  | .checkedMod destination lhs rhs =>
      s!"{indent}assert({renderValue relation rhs} != 0);\n" ++
        s!"{indent}let t{destination}: u64 = {renderValue relation lhs} % {renderValue relation rhs};\n"
  | .fieldAdd destination lhs rhs =>
      -- Native Noir Field = bn254 Fr; modular add (no overflow assert).
      s!"{indent}let t{destination}: Field = {renderValue relation lhs} + {renderValue relation rhs};\n"
  | .fieldSub destination lhs rhs =>
      s!"{indent}let t{destination}: Field = {renderValue relation lhs} - {renderValue relation rhs};\n"
  | .fieldMul destination lhs rhs =>
      s!"{indent}let t{destination}: Field = {renderValue relation lhs} * {renderValue relation rhs};\n"
  | .fieldDiv destination lhs rhs =>
      -- Div-by-zero is a circuit failure (assert non-zero before inverse).
      s!"{indent}assert({renderValue relation rhs} != 0);\n" ++
        s!"{indent}let t{destination}: Field = {renderValue relation lhs} / {renderValue relation rhs};\n"
  | .bitNot destination source =>
      s!"{indent}let t{destination}: u64 = !{renderValue relation source};\n"
  | .bigLiteral destination value =>
      -- T11: UInt128 Plan literal → native Noir u128 constant.
      s!"{indent}let t{destination}: u128 = {value};\n"
  | .narrowCheckedAdd bitWidth destination lhs rhs =>
      if bitWidth == 128 then
        -- T11 multi-limb add: native Noir u128 checked add (2×u64 software
        -- multiword analogue of T9e; circuit surface is one u128 word).
        s!"{indent}let t{destination}: u128 = {renderValueAsU128 relation lhs} + {renderValueAsU128 relation rhs};\n"
      else
        s!"{indent}let t{destination}: u64 = {renderValue relation lhs} + {renderValue relation rhs};\n" ++
          s!"{indent}assert((t{destination} >> {bitWidth}) == 0);\n"
  | .narrowCheckedSub bitWidth destination lhs rhs =>
      if bitWidth == 128 then
        s!"{indent}assert({renderValueAsU128 relation lhs} >= {renderValueAsU128 relation rhs});\n" ++
          s!"{indent}let t{destination}: u128 = {renderValueAsU128 relation lhs} - {renderValueAsU128 relation rhs};\n"
      else
        s!"{indent}assert({renderValue relation lhs} >= {renderValue relation rhs});\n" ++
          s!"{indent}let t{destination}: u64 = {renderValue relation lhs} - {renderValue relation rhs};\n"
  | .narrowCheckedMul bitWidth destination lhs rhs =>
      -- UInt128 mul is rejected at Plan lower; bitWidth=128 should not reach emit.
      s!"{indent}let t{destination}: u64 = {renderValue relation lhs} * {renderValue relation rhs};\n" ++
        s!"{indent}assert((t{destination} >> {bitWidth}) == 0);\n"
  | .narrowCheckedDiv bitWidth destination lhs rhs =>
      let _ := bitWidth
      s!"{indent}assert({renderValue relation rhs} != 0);\n" ++
        s!"{indent}let t{destination}: u64 = {renderValue relation lhs} / {renderValue relation rhs};\n"
  | .narrowCheckedMod bitWidth destination lhs rhs =>
      let _ := bitWidth
      s!"{indent}assert({renderValue relation rhs} != 0);\n" ++
        s!"{indent}let t{destination}: u64 = {renderValue relation lhs} % {renderValue relation rhs};\n"
  | .narrowBitAnd bitWidth destination lhs rhs =>
      if bitWidth == 128 then
        s!"{indent}let t{destination}: u128 = {renderValueAsU128 relation lhs} & {renderValueAsU128 relation rhs};\n"
      else
        s!"{indent}let t{destination}: u64 = {renderValue relation lhs} & {renderValue relation rhs};\n"
  | .narrowBitOr bitWidth destination lhs rhs =>
      if bitWidth == 128 then
        s!"{indent}let t{destination}: u128 = {renderValueAsU128 relation lhs} | {renderValueAsU128 relation rhs};\n"
      else
        s!"{indent}let t{destination}: u64 = {renderValue relation lhs} | {renderValue relation rhs};\n"
  | .narrowBitXor bitWidth destination lhs rhs =>
      if bitWidth == 128 then
        s!"{indent}let t{destination}: u128 = {renderValueAsU128 relation lhs} ^ {renderValueAsU128 relation rhs};\n"
      else
        s!"{indent}let t{destination}: u64 = {renderValue relation lhs} ^ {renderValue relation rhs};\n"
  | .narrowBitNot bitWidth destination source =>
      if bitWidth == 128 then
        s!"{indent}let t{destination}: u128 = !{renderValueAsU128 relation source};\n"
      else
        s!"{indent}let t{destination}: u64 = (!{renderValue relation source}) & {narrowUintMaskImm bitWidth};\n"
  | .narrowShl bitWidth destination lhs rhs =>
      if bitWidth == 128 then
        s!"{indent}let t{destination}: u128 = {renderValueAsU128 relation lhs} << {renderValue relation rhs};\n"
      else
        s!"{indent}let t{destination}: u64 = {renderValue relation lhs} << {renderValue relation rhs};\n" ++
          s!"{indent}assert((t{destination} >> {bitWidth}) == 0);\n"
  | .narrowShr bitWidth destination lhs rhs =>
      if bitWidth == 128 then
        s!"{indent}let t{destination}: u128 = {renderValueAsU128 relation lhs} >> {renderValue relation rhs};\n"
      else
        s!"{indent}let t{destination}: u64 = {renderValue relation lhs} >> {renderValue relation rhs};\n"
  | .boolNot destination source =>
      s!"{indent}let t{destination}: bool = !{renderValue relation source};\n"
  | .bitAnd destination lhs rhs =>
      s!"{indent}let t{destination}: u64 = {renderValue relation lhs} & {renderValue relation rhs};\n"
  | .bitOr destination lhs rhs =>
      s!"{indent}let t{destination}: u64 = {renderValue relation lhs} | {renderValue relation rhs};\n"
  | .bitXor destination lhs rhs =>
      s!"{indent}let t{destination}: u64 = {renderValue relation lhs} ^ {renderValue relation rhs};\n"
  | .boolAnd destination lhs rhs =>
      s!"{indent}let t{destination}: bool = {renderValue relation lhs} & {renderValue relation rhs};\n"
  | .boolOr destination lhs rhs =>
      s!"{indent}let t{destination}: bool = {renderValue relation lhs} | {renderValue relation rhs};\n"
  | .assertEqual lhs rhs =>
      let asBool := assertEqualUsesBool relation lhs rhs
      s!"{indent}assert({renderEqualOperand relation asBool rhs lhs} == {renderEqualOperand relation asBool lhs rhs});\n"
  | .assertBool inputIndex expected =>
      s!"{indent}assert({relation.inputs[inputIndex]!.name} == {if expected then "true" else "false"});\n"
  | .compare op destination lhs rhs =>
      -- Operands may be u64 (historical) or u128 (T11); Noir compares same-typed
      -- values. Cast both sides when either side is already u128-typed is handled
      -- by Plan compare on matching widths; body temps keep native type.
      s!"{indent}let t{destination}: bool = {renderValue relation lhs} {renderComparisonOp op} {renderValue relation rhs};\n"
  | .signedCompare op destination lhs rhs =>
      -- i64 surface: cast u64 bit patterns to i64 for signed ordering.
      s!"{indent}let t{destination}: bool = ({renderValue relation lhs} as i64) {renderComparisonOp op} ({renderValue relation rhs} as i64);\n"
  | .checkedNeg destination source =>
      s!"{indent}assert({renderValue relation source} != 9223372036854775808);\n" ++
        s!"{indent}let t{destination}: u64 = (0 as u64).wrapping_sub({renderValue relation source});\n"
  | .fieldNeg destination source =>
      s!"{indent}let t{destination}: Field = -{renderValue relation source};\n"
  | .assertConstraint condition =>
      s!"{indent}assert({renderAssertCondition relation condition});\n"
  | .ifRegion condition thenOps elseOps =>
      let renderArm := fun operations =>
        String.intercalate "" <|
          operations.toList.map (renderOperation relation (indent ++ "  "))
      s!"{indent}if {renderAssertCondition relation condition} \{\n" ++
        renderArm thenOps ++
        s!"{indent}}} else \{\n" ++
        renderArm elseOps ++
        s!"{indent}}}\n"
  | .switchRegion scrutinee scrutIsBool cases defaultOps =>
      let scrut := renderValue relation scrutinee
      let renderArm := fun operations =>
        String.intercalate "" <|
          operations.toList.map (renderOperation relation (indent ++ "  "))
      let renderCaseValue := fun (value : UInt64) =>
        if scrutIsBool then
          if value == 0 then "false" else "true"
        else
          toString value.toNat
      let branches := cases.toList.mapIdx fun index (caseValue, caseOps) =>
        let keyword := if index == 0 then s!"{indent}if" else " else if"
        s!"{keyword} {scrut} == {renderCaseValue caseValue} \{\n" ++
          renderArm caseOps ++
          s!"{indent}}}"
      String.intercalate "" branches ++
        s!" else \{\n" ++
        renderArm defaultOps ++
        s!"{indent}}}\n"
  | .selectRegion destination condition resultIsBool thenOps thenValue elseOps elseValue =>
      let renderArm := fun operations =>
        String.intercalate "" <|
          operations.toList.map (renderOperation relation (indent ++ "  "))
      let type := if resultIsBool then "bool" else "u64"
      s!"{indent}let t{destination}: {type} = if {renderAssertCondition relation condition} \{\n" ++
        renderArm thenOps ++
        s!"{indent}  {renderValue relation thenValue}\n" ++
        s!"{indent}}} else \{\n" ++
        renderArm elseOps ++
        s!"{indent}  {renderValue relation elseValue}\n" ++
        s!"{indent}}};\n"
  | .selectSwitch destination scrutinee scrutIsBool resultIsBool cases defaultOps defaultValue =>
      let scrut := renderValue relation scrutinee
      let renderArm := fun operations =>
        String.intercalate "" <|
          operations.toList.map (renderOperation relation (indent ++ "  "))
      let renderCaseValue := fun (value : UInt64) =>
        if scrutIsBool then
          if value == 0 then "false" else "true"
        else
          toString value.toNat
      let type := if resultIsBool then "bool" else "u64"
      let branches := cases.toList.mapIdx fun index (caseValue, caseOps, caseResult) =>
        let keyword := if index == 0 then "if" else " else if"
        s!"{keyword} {scrut} == {renderCaseValue caseValue} \{\n" ++
          renderArm caseOps ++
          s!"{indent}  {renderValue relation caseResult}\n" ++
          s!"{indent}}}"
      s!"{indent}let t{destination}: {type} = " ++
        String.intercalate "" branches ++
        s!" else \{\n" ++
        renderArm defaultOps ++
        s!"{indent}  {renderValue relation defaultValue}\n" ++
        s!"{indent}}};\n"

private def renderInputType : InputType → String
  | .u64 => "u64"
  | .bool => "bool"
  | .field => "Field"
  | .u8 => "u8"
  | .u16 => "u16"
  | .u32 => "u32"
  | .u128 => "u128"
  | .i8 => "i8"
  | .i16 => "i16"
  | .i32 => "i32"
  | .i64 => "i64"

private def renderInput (input : InputBinding) : String :=
  let visibility := if input.visibility == .verifier then "pub " else ""
  let type := renderInputType input.type
  s!"{input.name}: {visibility}{type}"

private def renderSource (relation : RelationIR) : String :=
  let signature := String.intercalate ", " <|
    relation.sourceRelation.inputs.toList.map renderInput
  let operations := String.intercalate "" <|
    relation.operations.toList.map (renderOperation relation.sourceRelation "    ")
  s!"fn main({signature}) \{\n" ++ operations ++ "}\n"

private def renderPackage (relation : Relation) : String :=
  "[package]\n" ++
    s!"name = \"pf_relation_{relation.index}\"\n" ++
    "type = \"bin\"\n" ++
    "authors = [\"ProofForge V2\"]\n"

private def renderMode : RelationMode → String
  | .initialize => "initialize"
  | .mutate => "mutate"
  | .view => "view"

private def renderVisibility : InputVisibility → String
  | .verifier => "public"
  | .witness => "private-witness"

private def renderInputJson (input : InputBinding) : String :=
  let (role, sourceId) := match input.role with
    | .preInitialized => ("pre-initialized", "null")
    | .preState id => ("pre-state", toString id)
    | .parameter id => ("parameter", toString id)
    | .postState id => ("post-state", toString id)
    | .postInitialized => ("post-initialized", "null")
    | .result => ("result", "null")
    | .eventSlot emitIndex argIndex => ("event-slot", s!"[{emitIndex},{argIndex}]")
    | .callStatus callIndex => ("call-status", toString callIndex)
    | .callArgSlot callIndex argIndex => ("call-arg-slot", s!"[{callIndex},{argIndex}]")
    | .scheduleArgSlot scheduleIndex argIndex =>
        ("schedule-arg-slot", s!"[{scheduleIndex},{argIndex}]")
  let type := renderInputType input.type
  "{" ++
    s!"\"name\":\"{Targets.escapeJson input.name}\"," ++
    s!"\"sourceName\":\"{Targets.escapeJson input.sourceName}\"," ++
    s!"\"sourceId\":{sourceId}," ++
    s!"\"role\":\"{role}\"," ++
    s!"\"visibility\":\"{renderVisibility input.visibility}\"," ++
    s!"\"type\":\"{type}\"}"

private def renderRelationJson (relation : RelationIR) : String :=
  let inputs := String.intercalate "," <|
    relation.sourceRelation.inputs.toList.map renderInputJson
  "{" ++
    s!"\"index\":{relation.sourceRelation.index}," ++
    s!"\"name\":\"{Targets.escapeJson relation.sourceRelation.name}\"," ++
    s!"\"mode\":\"{renderMode relation.sourceRelation.mode}\"," ++
    s!"\"package\":\"relations/{relation.sourceRelation.artifactStem}\"," ++
    s!"\"operationCount\":{countOperationsV1 relation.operations}," ++
    s!"\"inputs\":[{inputs}]}"

private def renderInterface (ir : IR) : String :=
  let relations := String.intercalate ",\n    " <|
    ir.relations.toList.map renderRelationJson
  let continuity := if ir.sourcePlan.continuity == .none then "none" else "external-public-pre-post"
  "{\n" ++
    "  \"schema\": \"proof-forge-noir-relations/v1alpha1\",\n" ++
    s!"  \"program\": \"{Targets.escapeJson ir.name}\",\n" ++
    s!"  \"codegenProfile\": \"{ir.sourcePlan.codegenProfile}\",\n" ++
    s!"  \"sourceDialect\": \"{ir.sourcePlan.sourceDialect}\",\n" ++
    s!"  \"sourceHash\": \"{ir.sourcePlan.sourceHash}\",\n" ++
    s!"  \"semanticHash\": \"{ir.sourcePlan.semanticHash}\",\n" ++
    s!"  \"planHash\": \"{ir.sourcePlan.planHash}\",\n" ++
    "  \"artifactKind\": \"source-only\",\n" ++
    s!"  \"stateContinuity\": \"{continuity}\",\n" ++
    "  \"arithmetic\": \"native-checked-u64\",\n" ++
    "  \"proofStatus\": \"not-produced\",\n" ++
    "  \"relations\": [\n    " ++ relations ++ "\n  ]\n" ++
    "}\n"

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
  validateIR ir
  let mut files : Array OutputFile := #[{
    path := s!"{ir.name}.noir-relations.json"
    mediaType := "application/json"
    contents := renderInterface ir
  }]
  for relation in ir.relations do
    let root := s!"relations/{relation.sourceRelation.artifactStem}"
    files := files.push {
      path := s!"{root}/src/main.nr"
      mediaType := "text/x-noir"
      contents := renderSource relation
    }
    files := files.push {
      path := s!"{root}/Nargo.toml"
      mediaType := "text/toml"
      contents := renderPackage relation.sourceRelation
    }
  return files

/-- Replace relations on an existing IR (private `mk`; for validateIR characterization). -/
def withRelations (ir : IR) (relations : Array RelationIR) : IR :=
  { ir with relations }


/-- Capability-gated public IR inspection (S6 repair). Input must be
    `ResolvedEngineeringBuildV1`; returns typed TargetIR without emitting files.
    Not a residual Plan→IR bypass. -/
def irFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult IR := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  lower plan

/-- Capability-gated public materialize entry (S6). -/
def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCapability capability
  emitFromIR ir

end ProofForgeV2.Targets.Noir
