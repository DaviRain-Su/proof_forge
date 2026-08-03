/-
  Ton Plan engineering canonical schema + digest (T9d / M5).

  planDigest = domainSeparatedSha256(
    "pf.ton-plan.engineering.v1",
    encodeEngineeringTonPlanBytesV1(plan))

  **Engineering only — not formal Plan identity / OutputSetV1.**
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Targets.Ton.LowerSemanticV1

namespace ProofForgeV2.Targets.Ton

open ProofForgeV2
open ProofForgeV2.Core.Common

def engineeringTonPlanDomainV1 : String :=
  "pf.ton-plan.engineering.v1"

private def encodeU32le (value : UInt32) : ByteArray :=
  let v := value.toNat
  let b0 := UInt8.ofNat (v % 256)
  let b1 := UInt8.ofNat ((v / 256) % 256)
  let b2 := UInt8.ofNat ((v / 65536) % 256)
  let b3 := UInt8.ofNat ((v / 16777216) % 256)
  ((((ByteArray.empty.push b0).push b1).push b2).push b3)

private def encodeNatAsU32le (count : Nat) : Except String ByteArray := do
  unless count ≤ UInt32.size - 1 do
    throw "ton plan u32 length is not representable"
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

private def encodeString (value : String) : Except String ByteArray := do
  let raw := value.toUTF8
  let header ← encodeNatAsU32le raw.size
  pure (header.append raw)

private def encodeComparisonOp : ComparisonOp → UInt8
  | .eq => 0 | .ne => 1 | .lt => 2 | .le => 3 | .gt => 4 | .ge => 5

private def encodeMethodMode : MethodMode → UInt8
  | .initialize => 0 | .mutate => 1 | .view => 2

private def encodeDepositPolicy : DepositPolicy → UInt8
  | .requireZero => 0 | .queryOnly => 1

private def encodeMethodResultKind : MethodResultKind → UInt8
  | .unit => 0 | .uint64 => 1 | .bool => 2 | .int64 => 3
  | .uint8 => 4 | .uint16 => 5 | .uint32 => 6
  | .int8 => 7 | .int16 => 8 | .int32 => 9
  | .uint128 => 10 | .uint256 => 11

private def encodeEndianness : Endianness → UInt8
  | .little => 0

private partial def encodeExpr (expr : Expr) : Except String ByteArray := do
  match expr with
  | .literal value => pure ((encodeU8 0).append (encodeU64le value))
  | .bigLiteral bitWidth value =>
      let byteLen := bitWidth / 8
      let mut payload := ByteArray.empty
      let mut v := value
      for _ in [:byteLen] do
        payload := payload.push (UInt8.ofNat (v % 256))
        v := v / 256
      pure ((((encodeU8 49).append (← encodeNatAsU32le bitWidth)).append
        (← encodeNatAsU32le byteLen)).append payload)
  | .param inputOffset => pure ((encodeU8 1).append (← encodeNatAsU32le inputOffset))
  | .narrowParam bitWidth inputOffset =>
      pure (((encodeU8 2).append (← encodeNatAsU32le bitWidth)).append
        (← encodeNatAsU32le inputOffset))
  | .stateLoad fieldIndex => pure ((encodeU8 3).append (← encodeNatAsU32le fieldIndex))
  | .narrowStateLoad bitWidth fieldIndex =>
      pure (((encodeU8 4).append (← encodeNatAsU32le bitWidth)).append
        (← encodeNatAsU32le fieldIndex))
  | .checkedAdd lhs rhs => pure (((encodeU8 5).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .checkedSub lhs rhs => pure (((encodeU8 6).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .checkedMul lhs rhs => pure (((encodeU8 7).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .checkedDiv lhs rhs => pure (((encodeU8 8).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .checkedMod lhs rhs => pure (((encodeU8 9).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .bitAnd lhs rhs => pure (((encodeU8 10).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .bitOr lhs rhs => pure (((encodeU8 11).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .bitXor lhs rhs => pure (((encodeU8 12).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .shl lhs rhs => pure (((encodeU8 13).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .shr lhs rhs => pure (((encodeU8 14).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCheckedAdd lhs rhs => pure (((encodeU8 15).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCheckedSub lhs rhs => pure (((encodeU8 16).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCheckedMul lhs rhs => pure (((encodeU8 17).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCheckedDiv lhs rhs => pure (((encodeU8 18).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCheckedMod lhs rhs => pure (((encodeU8 19).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCompare op lhs rhs =>
      pure ((((encodeU8 20).append (encodeU8 (encodeComparisonOp op))).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .checkedNeg operand => pure ((encodeU8 21).append (← encodeExpr operand))
  | .sar lhs rhs => pure (((encodeU8 22).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .bitNot operand => pure ((encodeU8 23).append (← encodeExpr operand))
  | .narrowCheckedAdd bitWidth lhs rhs =>
      pure ((((encodeU8 24).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowCheckedSub bitWidth lhs rhs =>
      pure ((((encodeU8 25).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowCheckedMul bitWidth lhs rhs =>
      pure ((((encodeU8 26).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowCheckedDiv bitWidth lhs rhs =>
      pure ((((encodeU8 27).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowCheckedMod bitWidth lhs rhs =>
      pure ((((encodeU8 28).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowBitAnd bitWidth lhs rhs =>
      pure ((((encodeU8 29).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowBitOr bitWidth lhs rhs =>
      pure ((((encodeU8 30).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowBitXor bitWidth lhs rhs =>
      pure ((((encodeU8 31).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowBitNot bitWidth operand =>
      pure (((encodeU8 32).append (← encodeNatAsU32le bitWidth)).append (← encodeExpr operand))
  | .narrowShl bitWidth lhs rhs =>
      pure ((((encodeU8 33).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowShr bitWidth lhs rhs =>
      pure ((((encodeU8 34).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .boolNot operand => pure ((encodeU8 35).append (← encodeExpr operand))
  | .boolAnd lhs rhs => pure (((encodeU8 36).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .boolOr lhs rhs => pure (((encodeU8 37).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .compare op lhs rhs =>
      pure ((((encodeU8 38).append (encodeU8 (encodeComparisonOp op))).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .wideCompare bitWidth op lhs rhs =>
      pure (((((encodeU8 50).append (← encodeNatAsU32le bitWidth)).append
        (encodeU8 (encodeComparisonOp op))).append (← encodeExpr lhs)).append
        (← encodeExpr rhs))
  | .callFn fnIndex args =>
      let mut out := (encodeU8 39).append (← encodeNatAsU32le fnIndex)
      out := out.append (← encodeNatAsU32le args.size)
      for arg in args do out := out.append (← encodeExpr arg)
      pure out
  | .localTemp index => pure ((encodeU8 40).append (← encodeNatAsU32le index))

private partial def encodeStatement (stmt : Statement) : Except String ByteArray := do
  match stmt with
  | .store op =>
      pure ((((encodeU8 0).append (← encodeNatAsU32le op.fieldIndex)).append
        (← encodeNatAsU32le op.byteWidth)).append (← encodeExpr op.value))
  | .returnValue value => pure ((encodeU8 1).append (← encodeExpr value))
  | .returnNone => pure (encodeU8 2)
  | .assert condition => pure ((encodeU8 3).append (← encodeExpr condition))
  | .emitEvent eventIndex args =>
      let mut out := (encodeU8 4).append (← encodeNatAsU32le eventIndex)
      out := out.append (← encodeNatAsU32le args.size)
      for a in args do out := out.append (← encodeExpr a)
      pure out
  | .revertError errorIndex args =>
      let mut out := (encodeU8 5).append (← encodeNatAsU32le errorIndex)
      out := out.append (← encodeNatAsU32le args.size)
      for a in args do out := out.append (← encodeExpr a)
      pure out
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
  | .forLoop varTemp initial condition update maxIterations body =>
      let mut out := (encodeU8 8).append (← encodeNatAsU32le varTemp)
      out := out.append (← encodeExpr initial)
      out := out.append (← encodeExpr condition)
      out := out.append (← encodeExpr update)
      out := out.append (← encodeNatAsU32le maxIterations)
      out := out.append (← encodeNatAsU32le body.size)
      for s in body do out := out.append (← encodeStatement s)
      pure out
  | .promiseAccount receiver method args =>
      let mut out := (encodeU8 9).append (← encodeString receiver)
      out := out.append (← encodeString method)
      out := out.append (← encodeNatAsU32le args.size)
      for a in args do out := out.append (← encodeExpr a)
      pure out
  | .storeAtomic leaves =>
      -- Tag 10: multi-leaf atomic store (evaluate-all then write-all at IR).
      let mut out := (encodeU8 10).append (← encodeNatAsU32le leaves.size)
      for op in leaves do
        out := out.append (← encodeNatAsU32le op.fieldIndex)
        out := out.append (← encodeNatAsU32le op.byteWidth)
        out := out.append (← encodeExpr op.value)
      pure out

private def encodeParam (p : Param) : Except String ByteArray := do
  pure (((((← encodeNatAsU32le p.sourceId).append (← encodeString p.name)).append
    (← encodeNatAsU32le p.inputOffset)).append (← encodeNatAsU32le p.byteWidth)).append
    (encodeU8 (encodeEndianness p.endianness)))

private def encodeMethod (m : Method) : Except String ByteArray := do
  let mut out := ByteArray.empty
  out := out.append (← encodeString m.name)
  out := out.append (← encodeNatAsU32le m.params.size)
  for p in m.params do out := out.append (← encodeParam p)
  out := out.append (← encodeNatAsU32le m.exactInputLen)
  out := out.append (encodeU8 (encodeMethodMode m.mode))
  out := out.append (encodeU8 (encodeDepositPolicy m.depositPolicy))
  out := out.append (encodeU8 (encodeMethodResultKind m.resultKind))
  out := out.append (← encodeNatAsU32le m.body.size)
  for s in m.body do out := out.append (← encodeStatement s)
  pure out

private def encodeInterfaceBinding (b : InterfaceBinding) : Except String ByteArray := do
  pure ((← encodeString b.name).append (← encodeNatAsU32le b.fieldCount))

private def encodeStorageField (f : StorageField) : Except String ByteArray := do
  pure (((((← encodeNatAsU32le f.sourceId).append (← encodeString f.name)).append
    (← encodeString f.key)).append (← encodeNatAsU32le f.byteWidth)).append
    (encodeU8 (encodeEndianness f.endianness)))

/-- Canonical encode of Ton Plan for engineering planDigest (T9d). -/
def encodeEngineeringTonPlanBytesV1 (plan : Plan) : Except String ByteArray := do
  let mut out := ByteArray.empty
  out := out.append (← encodeNatAsU32le plan.semanticSchemaVersion)
  out := out.append (← encodeString plan.codegenProfile)
  out := out.append (← encodeString plan.hostAbi)
  out := out.append (← encodeString plan.inputAbi)
  out := out.append (← encodeString plan.layoutDomain)
  out := out.append (← encodeString plan.programName)
  out := out.append (← encodeString plan.storage.markerKey)
  out := out.append (encodeU64le plan.storage.markerValue)
  out := out.append (← encodeNatAsU32le plan.storage.fields.size)
  for f in plan.storage.fields do out := out.append (← encodeStorageField f)
  out := out.append (← encodeNatAsU32le plan.events.size)
  for b in plan.events do out := out.append (← encodeInterfaceBinding b)
  out := out.append (← encodeNatAsU32le plan.errors.size)
  for b in plan.errors do out := out.append (← encodeInterfaceBinding b)
  out := out.append (← encodeNatAsU32le plan.fns.size)
  for f in plan.fns do
    out := out.append (← encodeString f.name)
    out := out.append (← encodeNatAsU32le f.params.size)
    for p in f.params do out := out.append (← encodeParam p)
    out := out.append (encodeU8 (if f.resultIsBool then 1 else 0))
    out := out.append (← encodeNatAsU32le f.body.size)
    for s in f.body do out := out.append (← encodeStatement s)
  out := out.append (← encodeMethod plan.initializer)
  out := out.append (← encodeNatAsU32le plan.entries.size)
  for m in plan.entries do out := out.append (← encodeMethod m)
  pure out

def engineeringTonPlanDigestV1 (plan : Plan) : Except String Digest := do
  let bytes ← encodeEngineeringTonPlanBytesV1 plan
  domainSeparatedSha256 engineeringTonPlanDomainV1 bytes

end ProofForgeV2.Targets.Ton
