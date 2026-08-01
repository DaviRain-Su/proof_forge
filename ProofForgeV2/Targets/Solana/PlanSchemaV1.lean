/-
  Solana Plan engineering canonical schema + digest (T9d / M5).

  planDigest = domainSeparatedSha256(
    "pf.solana-plan.engineering.v1",
    encodeEngineeringSolanaPlanBytesV1(plan))

  Length-framed LE u32 counts/indices; closed u8 Expr/Statement tags.
  **Engineering only — not formal Plan identity / OutputSetV1.**
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Targets.Solana.LowerSemanticV1

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2
open ProofForgeV2.Core.Common

def engineeringSolanaPlanDomainV1 : String :=
  "pf.solana-plan.engineering.v1"

private def encodeU32le (value : UInt32) : ByteArray :=
  let v := value.toNat
  let b0 := UInt8.ofNat (v % 256)
  let b1 := UInt8.ofNat ((v / 256) % 256)
  let b2 := UInt8.ofNat ((v / 65536) % 256)
  let b3 := UInt8.ofNat ((v / 16777216) % 256)
  ((((ByteArray.empty.push b0).push b1).push b2).push b3)

private def encodeNatAsU32le (count : Nat) : Except String ByteArray := do
  unless count ≤ UInt32.size - 1 do
    throw "solana plan u32 length is not representable"
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

private def encodeBool (value : Bool) : ByteArray :=
  encodeU8 (if value then 1 else 0)

private def encodeComparisonOp : ComparisonOp → UInt8
  | .eq => 0 | .ne => 1 | .lt => 2 | .le => 3 | .gt => 4 | .ge => 5

private def encodeHandlerMode : HandlerMode → UInt8
  | .initialize => 0 | .mutate => 1 | .view => 2

private def encodeResultKind : ResultKind → UInt8
  | .u64 => 0 | .bool => 1 | .i64 => 2
  | .u8 => 3 | .u16 => 4 | .u32 => 5
  | .i8 => 6 | .i16 => 7 | .i32 => 8

private def encodeEndianness : Endianness → UInt8
  | .little => 0

private partial def encodeExpr (expr : Expr) : Except String ByteArray := do
  match expr with
  | .literal value => pure ((encodeU8 0).append (encodeU64le value))
  | .param dataOffset => pure ((encodeU8 1).append (← encodeNatAsU32le dataOffset))
  | .narrowParam bitWidth dataOffset =>
      pure (((encodeU8 2).append (← encodeNatAsU32le bitWidth)).append
        (← encodeNatAsU32le dataOffset))
  | .stateLoad accountIndex byteOffset =>
      pure (((encodeU8 3).append (← encodeNatAsU32le accountIndex)).append
        (← encodeNatAsU32le byteOffset))
  | .narrowStateLoad bitWidth accountIndex byteOffset =>
      pure ((((encodeU8 4).append (← encodeNatAsU32le bitWidth)).append
        (← encodeNatAsU32le accountIndex)).append (← encodeNatAsU32le byteOffset))
  | .checkedAdd lhs rhs => pure (((encodeU8 5).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .checkedSub lhs rhs => pure (((encodeU8 6).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .checkedMul lhs rhs => pure (((encodeU8 7).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .checkedDiv lhs rhs => pure (((encodeU8 8).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .checkedMod lhs rhs => pure (((encodeU8 9).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCheckedAdd lhs rhs => pure (((encodeU8 10).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCheckedSub lhs rhs => pure (((encodeU8 11).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCheckedMul lhs rhs => pure (((encodeU8 12).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCheckedDiv lhs rhs => pure (((encodeU8 13).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCheckedMod lhs rhs => pure (((encodeU8 14).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .bitAnd lhs rhs => pure (((encodeU8 15).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .bitOr lhs rhs => pure (((encodeU8 16).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .bitXor lhs rhs => pure (((encodeU8 17).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .shl lhs rhs => pure (((encodeU8 18).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .shr lhs rhs => pure (((encodeU8 19).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .sar lhs rhs => pure (((encodeU8 20).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .bitNot operand => pure ((encodeU8 21).append (← encodeExpr operand))
  | .boolNot operand => pure ((encodeU8 22).append (← encodeExpr operand))
  | .checkedNeg operand => pure ((encodeU8 23).append (← encodeExpr operand))
  | .boolAnd lhs rhs => pure (((encodeU8 24).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .boolOr lhs rhs => pure (((encodeU8 25).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .compare op lhs rhs =>
      pure ((((encodeU8 26).append (encodeU8 (encodeComparisonOp op))).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCompare op lhs rhs =>
      pure ((((encodeU8 27).append (encodeU8 (encodeComparisonOp op))).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .callFn fnIndex args =>
      let mut out := (encodeU8 28).append (← encodeNatAsU32le fnIndex)
      out := out.append (← encodeNatAsU32le args.size)
      for arg in args do out := out.append (← encodeExpr arg)
      pure out
  | .temp id => pure ((encodeU8 29).append (← encodeNatAsU32le id))
  | .narrowCheckedAdd bitWidth lhs rhs =>
      pure ((((encodeU8 30).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowCheckedSub bitWidth lhs rhs =>
      pure ((((encodeU8 31).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowCheckedMul bitWidth lhs rhs =>
      pure ((((encodeU8 32).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowCheckedDiv bitWidth lhs rhs =>
      pure ((((encodeU8 33).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowCheckedMod bitWidth lhs rhs =>
      pure ((((encodeU8 34).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowBitAnd bitWidth lhs rhs =>
      pure ((((encodeU8 35).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowBitOr bitWidth lhs rhs =>
      pure ((((encodeU8 36).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowBitXor bitWidth lhs rhs =>
      pure ((((encodeU8 37).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowBitNot bitWidth operand =>
      pure (((encodeU8 38).append (← encodeNatAsU32le bitWidth)).append (← encodeExpr operand))
  | .narrowShl bitWidth lhs rhs =>
      pure ((((encodeU8 39).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowShr bitWidth lhs rhs =>
      pure ((((encodeU8 40).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowSignedCheckedAdd bitWidth lhs rhs =>
      pure ((((encodeU8 41).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowSignedCheckedSub bitWidth lhs rhs =>
      pure ((((encodeU8 42).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowSignedCheckedMul bitWidth lhs rhs =>
      pure ((((encodeU8 43).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowSignedCheckedDiv bitWidth lhs rhs =>
      pure ((((encodeU8 44).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowSignedCheckedMod bitWidth lhs rhs =>
      pure ((((encodeU8 45).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowSignedCompare bitWidth op lhs rhs =>
      pure (((((encodeU8 46).append (← encodeNatAsU32le bitWidth)).append
        (encodeU8 (encodeComparisonOp op))).append (← encodeExpr lhs)).append
        (← encodeExpr rhs))
  | .narrowCheckedNeg bitWidth operand =>
      pure (((encodeU8 47).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr operand))
  | .narrowSar bitWidth lhs rhs =>
      pure ((((encodeU8 48).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))

private partial def encodeStatement (stmt : Statement) : Except String ByteArray := do
  match stmt with
  | .store op =>
      pure ((((((encodeU8 0).append (← encodeNatAsU32le op.accountIndex)).append
        (← encodeNatAsU32le op.byteOffset)).append (← encodeNatAsU32le op.byteWidth)).append
        (← encodeExpr op.value)))
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
  | .forLoop varTemp initial cond update maxIterations body =>
      let mut out := (encodeU8 8).append (← encodeNatAsU32le varTemp)
      out := out.append (← encodeExpr initial)
      out := out.append (← encodeExpr cond)
      out := out.append (← encodeExpr update)
      out := out.append (← encodeNatAsU32le maxIterations)
      out := out.append (← encodeNatAsU32le body.size)
      for s in body do out := out.append (← encodeStatement s)
      pure out

private def encodeParam (p : Param) : Except String ByteArray := do
  let mut out := ByteArray.empty
  out := out.append (← encodeNatAsU32le p.sourceId)
  out := out.append (← encodeString p.name)
  out := out.append (← encodeNatAsU32le p.dataOffset)
  out := out.append (← encodeNatAsU32le p.byteWidth)
  out := out.append (encodeU8 (encodeEndianness p.endianness))
  out := out.append (encodeBool p.isInt)
  pure out

private def encodeStateField (f : StateField) : Except String ByteArray := do
  let mut out := ByteArray.empty
  out := out.append (← encodeNatAsU32le f.sourceId)
  out := out.append (← encodeString f.name)
  out := out.append (← encodeNatAsU32le f.accountIndex)
  out := out.append (← encodeNatAsU32le f.byteOffset)
  out := out.append (← encodeNatAsU32le f.byteWidth)
  out := out.append (encodeU8 (encodeEndianness f.endianness))
  out := out.append (encodeBool f.isInt)
  pure out

private def encodeHandler (h : Handler) : Except String ByteArray := do
  let mut out := ByteArray.empty
  out := out.append (← encodeString h.name)
  out := out.append (← encodeString h.discriminator)
  out := out.append (← encodeNatAsU32le h.params.size)
  for p in h.params do out := out.append (← encodeParam p)
  out := out.append (encodeU8 (encodeHandlerMode h.mode))
  out := out.append (encodeU8 (encodeResultKind h.resultKind))
  out := out.append (← encodeNatAsU32le h.accountAccess.accountIndex)
  out := out.append (encodeBool h.accountAccess.signerRequired)
  out := out.append (encodeBool h.accountAccess.writableRequired)
  out := out.append (← encodeNatAsU32le h.body.size)
  for s in h.body do out := out.append (← encodeStatement s)
  pure out

private def encodeFnBinding (f : FnBinding) : Except String ByteArray := do
  let mut out := ByteArray.empty
  out := out.append (← encodeString f.name)
  out := out.append (← encodeNatAsU32le f.params.size)
  for p in f.params do out := out.append (← encodeParam p)
  out := out.append (encodeBool f.resultIsBool)
  out := out.append (encodeBool f.resultIsInt)
  out := out.append (← encodeNatAsU32le f.body.size)
  for s in f.body do out := out.append (← encodeStatement s)
  pure out

private def encodeInterfaceBinding (b : InterfaceBinding) : Except String ByteArray := do
  pure (((← encodeString b.name).append (← encodeNatAsU32le b.fieldCount)))

/-- Canonical encode of Solana Plan for engineering planDigest (T9d). -/
def encodeEngineeringSolanaPlanBytesV1 (plan : Plan) : Except String ByteArray := do
  let mut out := ByteArray.empty
  out := out.append (← encodeString plan.codegenProfile)
  out := out.append (← encodeString plan.instructionDiscriminatorDomain)
  out := out.append (← encodeNatAsU32le plan.instructionDiscriminatorBytes)
  out := out.append (← encodeString plan.stateLayoutDomain)
  out := out.append (← encodeNatAsU32le plan.arithmeticOverflowError)
  out := out.append (← encodeNatAsU32le plan.assertionFailedError)
  out := out.append (← encodeNatAsU32le plan.loopBoundExceededError)
  out := out.append (← encodeNatAsU32le plan.invalidShiftError)
  out := out.append (← encodeString plan.programName)
  let acc := plan.stateAccount
  out := out.append (← encodeNatAsU32le acc.index)
  out := out.append (← encodeString acc.name)
  out := out.append (← encodeNatAsU32le acc.exactDataLen)
  out := out.append (← encodeNatAsU32le acc.headerOffset)
  out := out.append (← encodeNatAsU32le acc.headerWidth)
  out := out.append (encodeU64le acc.initializedMarker)
  out := out.append (← encodeNatAsU32le acc.fields.size)
  for f in acc.fields do out := out.append (← encodeStateField f)
  out := out.append (← encodeNatAsU32le plan.events.size)
  for b in plan.events do out := out.append (← encodeInterfaceBinding b)
  out := out.append (← encodeNatAsU32le plan.errors.size)
  for b in plan.errors do out := out.append (← encodeInterfaceBinding b)
  out := out.append (← encodeNatAsU32le plan.fns.size)
  for f in plan.fns do out := out.append (← encodeFnBinding f)
  out := out.append (← encodeHandler plan.initializer)
  out := out.append (← encodeNatAsU32le plan.entries.size)
  for h in plan.entries do out := out.append (← encodeHandler h)
  pure out

def engineeringSolanaPlanDigestV1 (plan : Plan) : Except String Digest := do
  let bytes ← encodeEngineeringSolanaPlanBytesV1 plan
  domainSeparatedSha256 engineeringSolanaPlanDomainV1 bytes

end ProofForgeV2.Targets.Solana
