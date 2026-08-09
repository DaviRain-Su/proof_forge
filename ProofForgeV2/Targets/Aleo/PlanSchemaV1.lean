/-
  Aleo Plan engineering canonical schema + digest (ALEO-I1).

  planDigest = domainSeparatedSha256(
    "pf.aleo-plan.engineering.v1",
    encodeEngineeringAleoPlanBytesV1(plan))

  Length-framed closed-tag encoding of every Aleo.Plan content field and the
  recursive Expr / Statement / ResultKind / FunctionKind /
  PlanParam / PlanFunction / PlanView surface. No `repr` / map iteration.
  `validatePlan` runs before encoding so caller-constructed Plans cannot bypass
  canonicity gates.

  **Engineering only — not formal Plan identity / OutputSetV1.**
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Targets.Aleo.ValidatePlanV1

namespace ProofForgeV2.Targets.Aleo

open ProofForgeV2
open ProofForgeV2.Core.Common

def engineeringAleoPlanDomainV1 : String :=
  "pf.aleo-plan.engineering.v1"

private def encodeU32le (value : UInt32) : ByteArray :=
  let v := value.toNat
  let b0 := UInt8.ofNat (v % 256)
  let b1 := UInt8.ofNat ((v / 256) % 256)
  let b2 := UInt8.ofNat ((v / 65536) % 256)
  let b3 := UInt8.ofNat ((v / 16777216) % 256)
  ((((ByteArray.empty.push b0).push b1).push b2).push b3)

private def encodeNatAsU32le (count : Nat) : Except String ByteArray := do
  unless count ≤ UInt32.size - 1 do
    throw "aleo plan u32 length is not representable"
  pure (encodeU32le (UInt32.ofNat count))

private def encodeU64le (value : UInt64) : ByteArray := Id.run do
  let mut out := ByteArray.empty
  let mut v := value
  for _ in [:8] do
    out := out.push v.toUInt8
    v := UInt64.shiftRight v 8
  pure out

private def encodeU8 (value : UInt8) : ByteArray :=
  ByteArray.empty.push value

private def encodeBool (value : Bool) : ByteArray :=
  encodeU8 (if value then 1 else 0)

private def encodeString (value : String) : Except String ByteArray := do
  let raw := value.toUTF8
  let header ← encodeNatAsU32le raw.size
  pure (header.append raw)

private def encodeComparisonOp : ComparisonOp → UInt8
  | .eq => 0 | .ne => 1 | .lt => 2 | .le => 3 | .gt => 4 | .ge => 5

private def encodeFieldArithOp : FieldArithOp → UInt8
  | .add => 0 | .sub => 1 | .mul => 2 | .div => 3

private def encodeFunctionKind : FunctionKind → UInt8
  | .initialize => 0 | .mutate => 1


private def encodeLeafAbiType (leaf : LeafAbiType) : Except String ByteArray := do
  pure ((encodeBool leaf.isInt).append (← encodeNatAsU32le leaf.byteWidth))

/-- Closed ResultKind tags: scalars 0..7; aggregate = 8 + leaves. -/
private def encodeResultKind : ResultKind → Except String ByteArray
  | .u64 => pure (encodeU8 0)
  | .bool => pure (encodeU8 1)
  | .i64 => pure (encodeU8 2)
  | .u8 => pure (encodeU8 3)
  | .u16 => pure (encodeU8 4)
  | .u32 => pure (encodeU8 5)
  | .field => pure (encodeU8 6)
  | .unit => pure (encodeU8 7)
  | .aggregate leaves => do
      let mut out := encodeU8 8
      out := out.append (← encodeNatAsU32le leaves.size)
      for leaf in leaves do out := out.append (← encodeLeafAbiType leaf)
      pure out

private partial def encodeExpr (expr : Expr) : Except String ByteArray := do
  match expr with
  | .literal value => pure ((encodeU8 0).append (encodeU64le value))
  | .i64Literal value => pure ((encodeU8 1).append (encodeU64le value))
  | .uintLiteral bitWidth value =>
      pure (((encodeU8 2).append (← encodeNatAsU32le bitWidth)).append
        (encodeU64le value))
  | .boolLiteral value => pure ((encodeU8 3).append (encodeBool value))
  | .param inputIndex => pure ((encodeU8 4).append (← encodeNatAsU32le inputIndex))
  | .loopVar loopDepth => pure ((encodeU8 5).append (← encodeNatAsU32le loopDepth))
  | .stateLoad fieldIndex => pure ((encodeU8 6).append (← encodeNatAsU32le fieldIndex))
  | .checkedAdd lhs rhs =>
      pure (((encodeU8 7).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .checkedSub lhs rhs =>
      pure (((encodeU8 8).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .checkedMul lhs rhs =>
      pure (((encodeU8 9).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .checkedDiv lhs rhs =>
      pure (((encodeU8 10).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .checkedMod lhs rhs =>
      pure (((encodeU8 11).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowCheckedAdd bitWidth lhs rhs =>
      pure ((((encodeU8 12).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowCheckedSub bitWidth lhs rhs =>
      pure ((((encodeU8 13).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowCheckedMul bitWidth lhs rhs =>
      pure ((((encodeU8 14).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowCheckedDiv bitWidth lhs rhs =>
      pure ((((encodeU8 15).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowCheckedMod bitWidth lhs rhs =>
      pure ((((encodeU8 16).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .compare op lhs rhs =>
      pure ((((encodeU8 17).append (encodeU8 (encodeComparisonOp op))).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCheckedAdd lhs rhs =>
      pure (((encodeU8 18).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCheckedSub lhs rhs =>
      pure (((encodeU8 19).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCheckedMul lhs rhs =>
      pure (((encodeU8 20).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCheckedDiv lhs rhs =>
      pure (((encodeU8 21).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCheckedMod lhs rhs =>
      pure (((encodeU8 22).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCompare op lhs rhs =>
      pure ((((encodeU8 23).append (encodeU8 (encodeComparisonOp op))).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .bitAnd lhs rhs =>
      pure (((encodeU8 24).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .bitOr lhs rhs =>
      pure (((encodeU8 25).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .bitXor lhs rhs =>
      pure (((encodeU8 26).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowBitAnd bitWidth lhs rhs =>
      pure ((((encodeU8 27).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowBitOr bitWidth lhs rhs =>
      pure ((((encodeU8 28).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowBitXor bitWidth lhs rhs =>
      pure ((((encodeU8 29).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedBitAnd lhs rhs =>
      pure (((encodeU8 30).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedBitOr lhs rhs =>
      pure (((encodeU8 31).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedBitXor lhs rhs =>
      pure (((encodeU8 32).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .logicalAnd lhs rhs =>
      pure (((encodeU8 33).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .logicalOr lhs rhs =>
      pure (((encodeU8 34).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .shl lhs rhs =>
      pure (((encodeU8 35).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .shr lhs rhs =>
      pure (((encodeU8 36).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowShl bitWidth lhs rhs =>
      pure ((((encodeU8 37).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowShr bitWidth lhs rhs =>
      pure ((((encodeU8 38).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedShl lhs rhs =>
      pure (((encodeU8 39).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedShr lhs rhs =>
      pure (((encodeU8 40).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .bitNot operand => pure ((encodeU8 41).append (← encodeExpr operand))
  | .signedBitNot operand => pure ((encodeU8 42).append (← encodeExpr operand))
  | .narrowBitNot bitWidth operand =>
      pure (((encodeU8 43).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr operand))
  | .boolNot operand => pure ((encodeU8 44).append (← encodeExpr operand))
  | .checkedNeg operand => pure ((encodeU8 45).append (← encodeExpr operand))
  | .ternary condition thenValue elseValue =>
      pure ((((encodeU8 46).append (← encodeExpr condition)).append
        (← encodeExpr thenValue)).append (← encodeExpr elseValue))
  | .fieldLiteral value => pure ((encodeU8 47).append (encodeU64le value))
  | .fieldBinary op lhs rhs =>
      pure ((((encodeU8 48).append (encodeU8 (encodeFieldArithOp op))).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .fieldCompare op lhs rhs =>
      pure ((((encodeU8 49).append (encodeU8 (encodeComparisonOp op))).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .fieldNeg operand => pure ((encodeU8 50).append (← encodeExpr operand))
  | .callFn fnName args =>
      let mut out := (encodeU8 51).append (← encodeString fnName)
      out := out.append (← encodeNatAsU32le args.size)
      for arg in args do out := out.append (← encodeExpr arg)
      pure out

private partial def encodeStatement (stmt : Statement) : Except String ByteArray := do
  match stmt with
  | .store fieldIndex value =>
      pure (((encodeU8 0).append (← encodeNatAsU32le fieldIndex)).append
        (← encodeExpr value))
  | .storeAggregate leaves =>
      let mut out := (encodeU8 1).append (← encodeNatAsU32le leaves.size)
      for op in leaves do
        out := out.append (← encodeNatAsU32le op.fieldIndex)
        out := out.append (← encodeExpr op.value)
      pure out
  | .assert condition => pure ((encodeU8 2).append (← encodeExpr condition))
  | .returnValue value => pure ((encodeU8 3).append (← encodeExpr value))
  | .returnAggregate leaves leafIsInt =>
      let mut out := (encodeU8 4).append (← encodeNatAsU32le leaves.size)
      for leaf in leaves do out := out.append (← encodeExpr leaf)
      out := out.append (← encodeNatAsU32le leafIsInt.size)
      for flag in leafIsInt do out := out.append (encodeBool flag)
      pure out
  | .returnNone => pure (encodeU8 5)
  | .ifThenElse condition thenBody elseBody =>
      let mut out := (encodeU8 6).append (← encodeExpr condition)
      out := out.append (← encodeNatAsU32le thenBody.size)
      for s in thenBody do out := out.append (← encodeStatement s)
      out := out.append (← encodeNatAsU32le elseBody.size)
      for s in elseBody do out := out.append (← encodeStatement s)
      pure out
  | .switchOn scrutinee cases defaultBody =>
      let mut out := (encodeU8 7).append (← encodeExpr scrutinee)
      out := out.append (← encodeNatAsU32le cases.size)
      for (k, body) in cases do
        out := out.append (encodeU64le k)
        out := out.append (← encodeNatAsU32le body.size)
        for s in body do out := out.append (← encodeStatement s)
      out := out.append (← encodeNatAsU32le defaultBody.size)
      for s in defaultBody do out := out.append (← encodeStatement s)
      pure out
  | .forLoop start endExclusive maxIterations body =>
      let mut out := (encodeU8 8).append (← encodeExpr start)
      out := out.append (← encodeExpr endExclusive)
      out := out.append (← encodeNatAsU32le maxIterations)
      out := out.append (← encodeNatAsU32le body.size)
      for s in body do out := out.append (← encodeStatement s)
      pure out
  | .emitEvent eventIndex args =>
      let mut out := (encodeU8 9).append (← encodeNatAsU32le eventIndex)
      out := out.append (← encodeNatAsU32le args.size)
      for a in args do out := out.append (← encodeExpr a)
      pure out
  | .revertError errorIndex args =>
      let mut out := (encodeU8 10).append (← encodeNatAsU32le errorIndex)
      out := out.append (← encodeNatAsU32le args.size)
      for a in args do out := out.append (← encodeExpr a)
      pure out

private def encodePlanParam (p : PlanParam) : Except String ByteArray := do
  let mut out := ByteArray.empty
  out := out.append (← encodeNatAsU32le p.sourceIndex)
  out := out.append (← encodeString p.name)
  out := out.append (encodeBool p.isBool)
  out := out.append (encodeBool p.isInt)
  out := out.append (← encodeNatAsU32le p.uintWidth)
  out := out.append (encodeBool p.isField)
  pure out

private def encodePlanFunction (fn : PlanFunction) : Except String ByteArray := do
  let mut out := ByteArray.empty
  out := out.append (← encodeNatAsU32le fn.index)
  out := out.append (← encodeString fn.name)
  out := out.append (encodeU8 (encodeFunctionKind fn.kind))
  out := out.append (← encodeNatAsU32le fn.params.size)
  for p in fn.params do out := out.append (← encodePlanParam p)
  out := out.append (← encodeNatAsU32le fn.body.size)
  for s in fn.body do out := out.append (← encodeStatement s)
  out := out.append (encodeBool fn.touchesState)
  out := out.append (encodeBool fn.resultIsBool)
  out := out.append (encodeBool fn.resultIsInt)
  out := out.append (← encodeNatAsU32le fn.resultUintWidth)
  out := out.append (encodeBool fn.resultIsField)
  -- Stored aggregate leaves, then derived ResultKind (closed tags).
  match fn.resultAggregateLeaves with
  | none => out := out.append (encodeU8 0)
  | some leaves =>
      out := out.append (encodeU8 1)
      out := out.append (← encodeNatAsU32le leaves.size)
      for leaf in leaves do out := out.append (← encodeLeafAbiType leaf)
  out := out.append (← encodeResultKind fn.resultKind)
  out := out.append (encodeBool fn.resultDropped)
  out := out.append (encodeBool fn.isPureHelper)
  pure out

private def encodePlanView (v : PlanView) : Except String ByteArray := do
  pure ((← encodeString v.name).append (← encodeNatAsU32le v.stateFieldIndex))

/-- Canonical encode of Aleo Plan for engineering planDigest (ALEO-I1).
    Validation runs first so invalid Plans fail closed before hashing. -/
def encodeEngineeringAleoPlanBytesV1 (plan : Plan) : Except String ByteArray := do
  match validatePlan plan with
  | .ok _ => pure ()
  | .error e => throw e.render
  let mut out := ByteArray.empty
  out := out.append (← encodeString plan.programName)
  out := out.append (← encodeNatAsU32le plan.stateFieldNames.size)
  for name in plan.stateFieldNames do out := out.append (← encodeString name)
  out := out.append (← encodeNatAsU32le plan.stateFieldIsInt.size)
  for flag in plan.stateFieldIsInt do out := out.append (encodeBool flag)
  out := out.append (← encodeNatAsU32le plan.stateFieldUintWidth.size)
  for w in plan.stateFieldUintWidth do out := out.append (← encodeNatAsU32le w)
  out := out.append (← encodeNatAsU32le plan.stateFieldIsField.size)
  for flag in plan.stateFieldIsField do out := out.append (encodeBool flag)
  out := out.append (← encodeNatAsU32le plan.functions.size)
  for fn in plan.functions do out := out.append (← encodePlanFunction fn)
  out := out.append (← encodeNatAsU32le plan.views.size)
  for v in plan.views do out := out.append (← encodePlanView v)
  out := out.append (← encodeString plan.sourceHash)
  out := out.append (← encodeString plan.semanticHash)
  pure out

def engineeringAleoPlanDigestV1 (plan : Plan) : Except String Digest := do
  let bytes ← encodeEngineeringAleoPlanBytesV1 plan
  domainSeparatedSha256 engineeringAleoPlanDomainV1 bytes

end ProofForgeV2.Targets.Aleo
