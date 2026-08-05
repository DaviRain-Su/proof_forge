/-
  EVM Plan engineering canonical schema + digest (M4).

  Length-framed encode-only preimage of the target-owned `Plan` surface and a
  domain-separated SHA-256 digest:

    planDigest = domainSeparatedSha256(
      "pf.evm-plan.engineering.v1",
      encodeEngineeringEvmPlanBytesV1(plan))

  Field order is fixed and documented below. Deterministic source order; no map
  iteration; counts and scalar indices are little-endian u32; recursive
  Expr/Statement use closed u8 constructor tags.

  **Engineering only — not formal Plan identity / TASK-D4 / OutputSetV1.**
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Targets.Evm.LowerSemanticV1

namespace ProofForgeV2.Targets.Evm

open ProofForgeV2
open ProofForgeV2.Core.Common

def engineeringEvmPlanDomainV1 : String :=
  "pf.evm-plan.engineering.v1"

private def encodeU32le (value : UInt32) : ByteArray :=
  let v := value.toNat
  let b0 := UInt8.ofNat (v % 256)
  let b1 := UInt8.ofNat ((v / 256) % 256)
  let b2 := UInt8.ofNat ((v / 65536) % 256)
  let b3 := UInt8.ofNat ((v / 16777216) % 256)
  ((((ByteArray.empty.push b0).push b1).push b2).push b3)

private def encodeNatAsU32le (count : Nat) : Except String ByteArray := do
  unless count ≤ UInt32.size - 1 do
    throw "evm plan u32 length is not representable"
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

private def encodeMutability : Mutability → UInt8
  | .nonpayable => 0 | .view => 1 | .payable => 2

private def encodeLeafAbiType (leaf : LeafAbiType) : Except String ByteArray := do
  pure ((encodeBool leaf.isInt).append (← encodeNatAsU32le leaf.byteWidth))

/-- B-RET-ABI: ResultKind encoding. Scalar kinds use a single tag byte (0..11).
Aggregate uses tag 12 followed by u32le leaf count + per-leaf encoding. -/
private def encodeResultKind : ResultKind → Except String ByteArray
  | .uint64 => pure (encodeU8 0) | .bool => pure (encodeU8 1) | .int64 => pure (encodeU8 2)
  | .field => pure (encodeU8 3) | .uint8 => pure (encodeU8 4) | .uint16 => pure (encodeU8 5)
  | .uint32 => pure (encodeU8 6) | .uint128 => pure (encodeU8 7) | .uint256 => pure (encodeU8 8)
  | .int8 => pure (encodeU8 9) | .int16 => pure (encodeU8 10) | .int32 => pure (encodeU8 11)
  | .aggregate leaves => do
      let mut out := encodeU8 12
      out := out.append (← encodeNatAsU32le leaves.size)
      for leaf in leaves do out := out.append (← encodeLeafAbiType leaf)
      pure out

private partial def encodeExpr (expr : Expr) : Except String ByteArray := do
  match expr with
  | .literal value => pure ((encodeU8 0).append (encodeU64le value))
  | .bigLiteral value =>
      -- Tag 49: u32le length + little-endian value bytes (minimal width ≤ 32).
      let mut bs : Array UInt8 := #[]
      let mut n := value
      if n == 0 then
        bs := #[0]
      else
        for _ in [:32] do
          if n == 0 then break
          bs := bs.push (UInt8.ofNat (n % 256))
          n := n / 256
      let len := bs.size
      pure (((encodeU8 49).append (← encodeNatAsU32le len)).append (ByteArray.mk bs))
  | .param wordIndex => pure ((encodeU8 1).append (← encodeNatAsU32le wordIndex))
  | .temp tempIndex => pure ((encodeU8 2).append (← encodeNatAsU32le tempIndex))
  | .storageLoad slot => pure ((encodeU8 3).append (← encodeNatAsU32le slot))
  | .checkedAdd lhs rhs => pure (((encodeU8 4).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .checkedSub lhs rhs => pure (((encodeU8 5).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .compare op lhs rhs =>
      pure ((((encodeU8 6).append (encodeU8 (encodeComparisonOp op))).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .checkedMul lhs rhs => pure (((encodeU8 7).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .checkedDiv lhs rhs => pure (((encodeU8 8).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .checkedMod lhs rhs => pure (((encodeU8 9).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .add lhs rhs => pure (((encodeU8 10).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .bitNot operand => pure ((encodeU8 11).append (← encodeExpr operand))
  | .boolNot operand => pure ((encodeU8 12).append (← encodeExpr operand))
  | .bitAnd lhs rhs => pure (((encodeU8 13).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .bitOr lhs rhs => pure (((encodeU8 14).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .bitXor lhs rhs => pure (((encodeU8 15).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .shl lhs rhs => pure (((encodeU8 16).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .shr lhs rhs => pure (((encodeU8 17).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .logicalAnd lhs rhs => pure (((encodeU8 18).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .logicalOr lhs rhs => pure (((encodeU8 19).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .callFn fnIndex args =>
      let mut out := (encodeU8 20).append (← encodeNatAsU32le fnIndex)
      out := out.append (← encodeNatAsU32le args.size)
      for arg in args do out := out.append (← encodeExpr arg)
      pure out
  | .narrowCheckedAdd bitWidth lhs rhs =>
      pure ((((encodeU8 21).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowCheckedSub bitWidth lhs rhs =>
      pure ((((encodeU8 22).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowCheckedMul bitWidth lhs rhs =>
      pure ((((encodeU8 23).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowCheckedDiv bitWidth lhs rhs =>
      pure ((((encodeU8 24).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowCheckedMod bitWidth lhs rhs =>
      pure ((((encodeU8 25).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowBitAnd bitWidth lhs rhs =>
      pure ((((encodeU8 26).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowBitOr bitWidth lhs rhs =>
      pure ((((encodeU8 27).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowBitXor bitWidth lhs rhs =>
      pure ((((encodeU8 28).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowBitNot bitWidth operand =>
      pure (((encodeU8 29).append (← encodeNatAsU32le bitWidth)).append (← encodeExpr operand))
  | .narrowShl bitWidth lhs rhs =>
      pure ((((encodeU8 30).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowShr bitWidth lhs rhs =>
      pure ((((encodeU8 31).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCheckedAdd lhs rhs => pure (((encodeU8 32).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCheckedSub lhs rhs => pure (((encodeU8 33).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCheckedMul lhs rhs => pure (((encodeU8 34).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCheckedDiv lhs rhs => pure (((encodeU8 35).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCheckedMod lhs rhs => pure (((encodeU8 36).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .signedCompare op lhs rhs =>
      pure ((((encodeU8 37).append (encodeU8 (encodeComparisonOp op))).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .checkedNeg operand => pure ((encodeU8 38).append (← encodeExpr operand))
  | .sar lhs rhs => pure (((encodeU8 39).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowStorageLoad bitWidth slot =>
      pure (((encodeU8 40).append (← encodeNatAsU32le bitWidth)).append
        (← encodeNatAsU32le slot))
  | .narrowParam bitWidth wordIndex =>
      pure (((encodeU8 41).append (← encodeNatAsU32le bitWidth)).append
        (← encodeNatAsU32le wordIndex))
  -- N2b-EVM Field constructors (tags 42..47 appended; prior tags byte-identical).
  | .fieldAdd lhs rhs => pure (((encodeU8 42).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .fieldSub lhs rhs => pure (((encodeU8 43).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .fieldMul lhs rhs => pure (((encodeU8 44).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .fieldDiv lhs rhs => pure (((encodeU8 45).append (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .fieldNeg operand => pure ((encodeU8 46).append (← encodeExpr operand))
  | .fieldStorageLoad slot => pure ((encodeU8 47).append (← encodeNatAsU32le slot))
  -- EvmIndex ArrayState constructors (tags 48..50; prior tags byte-identical).
  | .indexedStorageLoad baseSlot length index byteWidth =>
      pure ((((((encodeU8 48).append (← encodeNatAsU32le baseSlot)).append
        (← encodeNatAsU32le length)).append (← encodeExpr index)).append
        (← encodeNatAsU32le byteWidth)))
  | .arrayIndexGet index leaves => do
      let mut out := (encodeU8 49).append (← encodeExpr index)
      out := out.append (← encodeNatAsU32le leaves.size)
      for leaf in leaves do out := out.append (← encodeExpr leaf)
      pure out
  | .boundsCheckedIndex index length =>
      pure (((encodeU8 50).append (← encodeExpr index)).append
        (← encodeNatAsU32le length))
  -- T9c narrow signed (tags 51..58; prior tags byte-identical).
  | .narrowSignedCheckedAdd bitWidth lhs rhs =>
      pure ((((encodeU8 51).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowSignedCheckedSub bitWidth lhs rhs =>
      pure ((((encodeU8 52).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowSignedCheckedMul bitWidth lhs rhs =>
      pure ((((encodeU8 53).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowSignedCheckedDiv bitWidth lhs rhs =>
      pure ((((encodeU8 54).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowSignedCheckedMod bitWidth lhs rhs =>
      pure ((((encodeU8 55).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowSignedCompare bitWidth op lhs rhs =>
      pure (((((encodeU8 56).append (← encodeNatAsU32le bitWidth)).append
        (encodeU8 (encodeComparisonOp op))).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  | .narrowCheckedNeg bitWidth operand =>
      pure (((encodeU8 57).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr operand))
  | .narrowSar bitWidth lhs rhs =>
      pure ((((encodeU8 58).append (← encodeNatAsU32le bitWidth)).append
        (← encodeExpr lhs)).append (← encodeExpr rhs))
  -- B-CTX-OPEN: block timestamp seconds (tag 59 appended; prior tags
  -- byte-identical).
  | .timestamp => pure (encodeU8 59)
  -- ADR-0030 E2-3: SELFBALANCE opcode (tag 60 appended; prior tags
  -- byte-identical).
  | .selfBalance => pure (encodeU8 60)

private partial def encodeStatement (stmt : Statement) : Except String ByteArray := do
  match stmt with
  | .store operation =>
      pure ((((encodeU8 0).append (← encodeNatAsU32le operation.slot)).append
        (← encodeNatAsU32le operation.byteWidth)).append (← encodeExpr operation.value))
  | .returnValue value => pure ((encodeU8 1).append (← encodeExpr value))
  | .returnAggregate leaves leafIsInt =>
      let mut out := encodeU8 13
      out := out.append (← encodeNatAsU32le leaves.size)
      for leaf in leaves do out := out.append (← encodeExpr leaf)
      out := out.append (← encodeNatAsU32le leafIsInt.size)
      for flag in leafIsInt do out := out.append (encodeBool flag)
      pure out
  | .returnNone => pure (encodeU8 2)
  | .assert condition => pure ((encodeU8 3).append (← encodeExpr condition))
  | .emitEvent eventIndex args =>
      let mut out := (encodeU8 4).append (← encodeNatAsU32le eventIndex)
      out := out.append (← encodeNatAsU32le args.size)
      for arg in args do out := out.append (← encodeExpr arg)
      pure out
  | .revertError errorIndex args =>
      let mut out := (encodeU8 5).append (← encodeNatAsU32le errorIndex)
      out := out.append (← encodeNatAsU32le args.size)
      for arg in args do out := out.append (← encodeExpr arg)
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
      for c in cases do
        let (lit, body) := c
        out := out.append (encodeU64le lit)
        out := out.append (← encodeNatAsU32le body.size)
        for s in body do out := out.append (← encodeStatement s)
      out := out.append (← encodeNatAsU32le defaultBody.size)
      for s in defaultBody do out := out.append (← encodeStatement s)
      pure out
  | .forLoop varTemp counterTemp maxIterations initial cond update body =>
      let mut out := (encodeU8 8).append (← encodeNatAsU32le varTemp)
      out := out.append (← encodeNatAsU32le counterTemp)
      out := out.append (encodeU32le maxIterations)
      out := out.append (← encodeExpr initial)
      out := out.append (← encodeExpr cond)
      out := out.append (← encodeExpr update)
      out := out.append (← encodeNatAsU32le body.size)
      for s in body do out := out.append (← encodeStatement s)
      pure out
  -- AddressBearing: static QualifiedName external call / schedule (tags 9/10).
  | .externalCall callee args => do
      let mut out := encodeU8 9
      out := out.append (← encodeNatAsU32le callee.size)
      for c in callee do out := out.append (← encodeString c)
      out := out.append (← encodeNatAsU32le args.size)
      for arg in args do out := out.append (← encodeExpr arg)
      pure out
  | .schedule callee args => do
      let mut out := encodeU8 10
      out := out.append (← encodeNatAsU32le callee.size)
      for c in callee do out := out.append (← encodeString c)
      out := out.append (← encodeNatAsU32le args.size)
      for arg in args do out := out.append (← encodeExpr arg)
      pure out
  -- Tag 11: atomic multi-leaf aggregate store (evaluate-all then sstore-all).
  | .storeAtomic operations => do
      let mut out := encodeU8 11
      out := out.append (← encodeNatAsU32le operations.size)
      for operation in operations do
        out := out.append (← encodeNatAsU32le operation.slot)
        out := out.append (← encodeNatAsU32le operation.byteWidth)
        out := out.append (← encodeExpr operation.value)
      pure out
  -- Tag 12 (N-CALL-RET): result-bearing external call (returndata → temp).
  | .externalCallResult callee args resultTemp => do
      let mut out := encodeU8 12
      out := out.append (← encodeNatAsU32le callee.size)
      for c in callee do out := out.append (← encodeString c)
      out := out.append (← encodeNatAsU32le args.size)
      for arg in args do out := out.append (← encodeExpr arg)
      out := out.append (← encodeNatAsU32le resultTemp)
      pure out
  -- Tag 13 (ADR-0029 B2): pf.assets.native.deposit(amount).
  | .nativeDeposit amount => do
      pure ((encodeU8 13).append (← encodeExpr amount))
  -- Tag 14 (ADR-0029 B2): pf.assets.native.transfer(dst, amount).
  | .nativeTransfer dstLen dstBodyWords amount => do
      let mut out := (encodeU8 14).append (← encodeExpr dstLen)
      out := out.append (← encodeNatAsU32le dstBodyWords.size)
      for w in dstBodyWords do out := out.append (← encodeExpr w)
      out := out.append (← encodeExpr amount)
      pure out
  -- Tag 15 (ADR-0030 E1a): pf.assets.token.transfer(mint, dst, amount).
  | .tokenTransfer mintLen mintBodyWords dstLen dstBodyWords amount => do
      let mut out := (encodeU8 15).append (← encodeExpr mintLen)
      out := out.append (← encodeNatAsU32le mintBodyWords.size)
      for w in mintBodyWords do out := out.append (← encodeExpr w)
      out := out.append (← encodeExpr dstLen)
      out := out.append (← encodeNatAsU32le dstBodyWords.size)
      for w in dstBodyWords do out := out.append (← encodeExpr w)
      out := out.append (← encodeExpr amount)
      pure out
  -- Tag 16 (ADR-0030 E2-3): pf.assets.token.balanceOfSelf(mint) STATICCALL.
  | .tokenBalanceOf mintLen mintBodyWords resultTemp => do
      let mut out := (encodeU8 16).append (← encodeExpr mintLen)
      out := out.append (← encodeNatAsU32le mintBodyWords.size)
      for w in mintBodyWords do out := out.append (← encodeExpr w)
      out := out.append (← encodeNatAsU32le resultTemp)
      pure out

private def encodeParam (p : Param) : Except String ByteArray := do
  let mut out := ByteArray.empty
  out := out.append (← encodeNatAsU32le p.sourceId)
  out := out.append (← encodeString p.name)
  out := out.append (← encodeNatAsU32le p.wordIndex)
  out := out.append (encodeBool p.isInt)
  out := out.append (← encodeNatAsU32le p.byteWidth)
  pure out

private def encodeParams (params : Array Param) : Except String ByteArray := do
  let mut out ← encodeNatAsU32le params.size
  for p in params do out := out.append (← encodeParam p)
  pure out

private def encodeStorageBinding (b : StorageBinding) : Except String ByteArray := do
  let mut out := ByteArray.empty
  out := out.append (← encodeNatAsU32le b.sourceId)
  out := out.append (← encodeString b.name)
  out := out.append (← encodeNatAsU32le b.slot)
  out := out.append (← encodeNatAsU32le b.byteWidth)
  pure out

private def encodeStore (s : Store) : Except String ByteArray := do
  pure (((← encodeNatAsU32le s.slot).append (← encodeNatAsU32le s.byteWidth)).append
    (← encodeExpr s.value))

private def encodeInterfaceBinding (b : InterfaceBinding) : Except String ByteArray := do
  let mut out := ByteArray.empty
  out := out.append (← encodeString b.name)
  out := out.append (← encodeNatAsU32le b.fieldCount)
  pure out

private def encodeStatements (stmts : Array Statement) : Except String ByteArray := do
  let mut out ← encodeNatAsU32le stmts.size
  for s in stmts do out := out.append (← encodeStatement s)
  pure out

private def encodeConstructor (c : Constructor) : Except String ByteArray := do
  let mut out ← encodeParams c.params
  out := out.append (← encodeNatAsU32le c.stores.size)
  for s in c.stores do out := out.append (← encodeStore s)
  out := out.append (← encodeStatements c.body)
  pure out

private def encodeEntry (e : Entry) : Except String ByteArray := do
  let mut out := ByteArray.empty
  out := out.append (← encodeString e.name)
  out := out.append (← encodeString e.selector)
  out := out.append (← encodeParams e.params)
  out := out.append (encodeU8 (encodeMutability e.mutability))
  out := out.append (← encodeStatements e.body)
  out := out.append (← encodeResultKind e.resultKind)
  pure out

private def encodeFnBinding (f : FnBinding) : Except String ByteArray := do
  let mut out := ByteArray.empty
  out := out.append (← encodeString f.name)
  out := out.append (← encodeParams f.params)
  out := out.append (← encodeStatements f.body)
  out := out.append (encodeBool f.resultIsBool)
  out := out.append (encodeBool f.resultIsInt)
  pure out

/-- Canonical engineering EVM Plan preimage bytes.

    Layout: objectName, runtimeObjectName, storageLayout[], events[], errors[],
    constructor option, entries[], fns[] — length-framed, LE u32, closed Expr/Stmt tags.
-/
def encodeEngineeringEvmPlanBytesV1 (plan : Plan) : Except String ByteArray := do
  let mut out := ByteArray.empty
  out := out.append (← encodeString plan.objectName)
  out := out.append (← encodeString plan.runtimeObjectName)
  out := out.append (← encodeNatAsU32le plan.storageLayout.size)
  for b in plan.storageLayout do out := out.append (← encodeStorageBinding b)
  out := out.append (← encodeNatAsU32le plan.events.size)
  for b in plan.events do out := out.append (← encodeInterfaceBinding b)
  out := out.append (← encodeNatAsU32le plan.errors.size)
  for b in plan.errors do out := out.append (← encodeInterfaceBinding b)
  match plan.constructor with
  | none => out := out.append (encodeU8 0)
  | some c =>
      out := out.append (encodeU8 1)
      out := out.append (← encodeConstructor c)
  out := out.append (← encodeNatAsU32le plan.entries.size)
  for e in plan.entries do out := out.append (← encodeEntry e)
  out := out.append (← encodeNatAsU32le plan.fns.size)
  for f in plan.fns do out := out.append (← encodeFnBinding f)
  pure out

def engineeringEvmPlanDigestV1 (plan : Plan) : Except String Digest := do
  let bytes ← encodeEngineeringEvmPlanBytesV1 plan
  domainSeparatedSha256 engineeringEvmPlanDomainV1 bytes

end ProofForgeV2.Targets.Evm
