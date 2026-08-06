import ProofForgeV2.Targets.Near.ValidatePlanV1
import ProofForgeV2.Targets.Near.PfAssetsCatalogV1

/-!
# Near EmitIRV1 — Plan → IR emission

Host-call recipe IR, validateIR, lower/emitFromIR.
-/

namespace ProofForgeV2.Targets.Near

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1
open ProofForgeV2.Targets.Near.PfAssetsCatalogV1

inductive Operation where
  | checkInputLen (bytes : Nat)
  | requireZeroAttachedDeposit
  /-- ADR-0029 C2: exact `attached_deposit` u128 == amount (lo) || 0 (hi).
      `amount` is a temp holding the UInt64 yoctoNEAR amount. -/
  | requireExactAttachedDeposit (amount : Nat)
  /-- B-CTX-OPEN: block timestamp seconds — host `block_timestamp()` (ns)
      divided by 10^9 (truncating). -/
  | blockTimestampSeconds (destination : Nat)
  /-- ADR-0030 E2-NEAR: host `account_balance` → u128 LE scratch; trap if
      high 64 bits nonzero; low 64 bits → destination (UInt64 range guard). -/
  | accountBalance (destination : Nat)
  /-- ADR-0031 S1: host `predecessor_account_id` → register length → destination
      (Principal length leaf; trap if length ∉ 1..64). -/
  | callerPrincipalLen (destination : Nat)
  /-- ADR-0031 S1: host `predecessor_account_id` → zero-padded 64B body buffer
      → LE UInt64 body word at `wordIndex` (0..7). -/
  | callerPrincipalWord (destination wordIndex : Nat)
  | requireLayoutAbsent (marker : KeyRegion)
  | requireLayout (marker : KeyRegion) (value : UInt64)
  | zeroState (field : KeyRegion)
  /-- Narrow field zero on init (`bitWidth ∈ {8,16,32}`); UInt64 keeps `zeroState`. -/
  | narrowZeroState (bitWidth : Nat) (field : KeyRegion)
  | literal (destination : Nat) (value : UInt64)
  | loadParam (destination inputOffset : Nat)
  /-- Narrow ABI param load (`bitWidth ∈ {8,16,32}`); UInt64/Int64 keep `loadParam`. -/
  | narrowLoadParam (bitWidth destination inputOffset : Nat)
  | loadState (destination : Nat) (field : KeyRegion)
  /-- Narrow ABI state load (`bitWidth ∈ {8,16,32}`); UInt64/Int64 keep `loadState`. -/
  | narrowLoadState (bitWidth destination : Nat) (field : KeyRegion)
  | checkedAdd (destination lhs rhs : Nat)
  | checkedSub (destination lhs rhs : Nat)
  | signedCheckedAdd (destination lhs rhs : Nat)
  | signedCheckedSub (destination lhs rhs : Nat)
  | signedCheckedMul (destination lhs rhs : Nat)
  | signedCheckedDiv (destination lhs rhs : Nat)
  | signedCheckedMod (destination lhs rhs : Nat)
  | signedCompare (destination lhs rhs : Nat) (op : ComparisonOp)
  | checkedNeg (destination source : Nat)
  | sar (destination lhs rhs : Nat)
  | storeState (field : KeyRegion) (value : Nat)
  /-- Narrow field store (`bitWidth ∈ {8,16,32}`); UInt64/Int64 keep `storeState`. -/
  | narrowStoreState (bitWidth : Nat) (field : KeyRegion) (value : Nat)
  | setLayout (marker : KeyRegion) (value : UInt64)
  /-- Host `value_return` payload: `byteLen` ∈ {1,2,4,8,16,32} from MethodResultKind
  (scalar/multiword consecutive temps starting at `value`). -/
  | setReturnData (byteLen value : Nat)
  /-- B-RET-ABI: host `value_return` of N×8-byte leaves from arbitrary temps
  (preorder flatten). Total payload length is `8 * temps.size` (1..8). -/
  | setReturnDataLeaves (temps : Array Nat)
  | compare (destination lhs rhs : Nat) (op : ComparisonOp)
  /-- Multiword unsigned compare (T9e): lhs/rhs bases of bitWidth/64 limbs. -/
  | wideCompare (bitWidth destination lhs rhs : Nat) (op : ComparisonOp)
  | assert (condition : Nat)
  | emitEvent (eventIndex : Nat) (args : Array Nat)
  | revertError (errorIndex : Nat) (args : Array Nat)
  | returnNone
  | ifRegion (condition : Nat) (thenOps elseOps : Array Operation)
  | switchRegion (scrutinee : Nat) (cases : Array (UInt64 × Array Operation))
      (defaultOps : Array Operation)
  /-- Structured bounded loop. Host/WAT re-run `condOps` each iteration;
      `varTemp` is seeded from `initial` then rewritten from `updateValue`
      after each body. `counterTemp` counts completed bodies; the static bound
      is checked at the back edge after the body (reference `noteBackEdge`
      placement): body runs first, then trap if `counterTemp ≥ maxIterations`,
      then increment + update. A body `return`/`revert` exits before the check. -/
  | forRegion (varTemp : Nat) (initial : Nat) (counterTemp : Nat)
      (maxIterations : Nat)
      (condOps : Array Operation) (condition : Nat)
      (bodyOps : Array Operation)
      (updateOps : Array Operation) (updateValue : Nat)
  | callFn (fnIndex : Nat) (destination : Nat) (args : Array Nat)
  | returnValue (value : Nat)
  | checkedMul (destination lhs rhs : Nat)
  | checkedDiv (destination lhs rhs : Nat)
  | checkedMod (destination lhs rhs : Nat)
  | bitAnd (destination lhs rhs : Nat)
  | bitOr (destination lhs rhs : Nat)
  | bitXor (destination lhs rhs : Nat)
  /-- Count guard (≥ 64 → trap) then i64.shl then overflow round-trip guard. -/
  | shl (destination lhs rhs : Nat)
  /-- Count guard (≥ 64 → trap) then i64.shr_u. -/
  | shr (destination lhs rhs : Nat)
  | bitNot (destination source : Nat)
  /-- Narrow body checked arithmetic (`bitWidth ∈ {8,16,32}`); UInt64 keeps historical. -/
  | narrowCheckedAdd (bitWidth destination lhs rhs : Nat)
  | narrowCheckedSub (bitWidth destination lhs rhs : Nat)
  | narrowCheckedMul (bitWidth destination lhs rhs : Nat)
  | narrowCheckedDiv (bitWidth destination lhs rhs : Nat)
  | narrowCheckedMod (bitWidth destination lhs rhs : Nat)
  | narrowBitAnd (bitWidth destination lhs rhs : Nat)
  | narrowBitOr (bitWidth destination lhs rhs : Nat)
  | narrowBitXor (bitWidth destination lhs rhs : Nat)
  | narrowBitNot (bitWidth destination source : Nat)
  /-- Count ≥ 64 trap; shl; high bits above bitWidth must be 0. -/
  | narrowShl (bitWidth destination lhs rhs : Nat)
  /-- Count ≥ 64 trap; shr_u. -/
  | narrowShr (bitWidth destination lhs rhs : Nat)
  | boolNot (destination source : Nat)
  /-- Strict Bool AND: i64.and on 0/1 words. -/
  | boolAnd (destination lhs rhs : Nat)
  /-- Strict Bool OR: i64.or on 0/1 words. -/
  | boolOr (destination lhs rhs : Nat)
  /-- Async schedule → `promise_batch_create` + `promise_batch_action_function_call`.
      Args are temp indices whose i64 values are stored LE into the scratch
      payload. Deposit (u128 = 0,0) and gas (0) are explicit artifact
      placeholders, not economics. Fire-and-forget: no response, no revert
      propagation. -/
  | promiseAccount (receiver : String) (method : String) (args : Array Nat)
  /-- ADR-0029 C2: fire-and-forget Transfer promise.
      `dstLen` + `dstWords` are Principal leaves (len + 8 body words);
      `amount` is UInt64 yoctoNEAR (u128 hi word forced 0). Runtime validates
      account-id grammar and emits `promise_batch_create` +
      `promise_batch_action_transfer`. -/
  | promiseTransfer (dstLen : Nat) (dstWords : Array Nat) (amount : Nat)
  /-- ADR-0030 E1-NEAR: fire-and-forget NEP-141 `ft_transfer` function-call
      promise. `mintLen`/`mintWords` decode the token contract account id;
      `dstLen`/`dstWords` decode the receiver account id; `amount` is UInt64
      base units. Runtime validates both account-id grammars, builds JSON args
      `{"receiver_id":"<dst>","amount":"<decimal>"}`, and emits
      `promise_batch_create(mint)` + `promise_batch_action_function_call(
      "ft_transfer", json_args, gas, deposit=1 yoctoNEAR)`. -/
  | promiseTokenTransfer
      (mintLen : Nat) (mintWords : Array Nat)
      (dstLen : Nat) (dstWords : Array Nat)
      (amount : Nat)
  deriving BEq, Inhabited, Repr

structure MethodIR where
  name : String
  params : Array Param
  mode : MethodMode
  tempCount : Nat
  operations : Array Operation
  deriving BEq, Inhabited, Repr

/-- Pure-function recipe: params occupy temps `0..paramCount-1`; body ops use
    `returnValue` (Wasm `return`) rather than host `value_return`. -/
structure FnIR where
  name : String
  paramCount : Nat
  resultIsBool : Bool
  tempCount : Nat
  operations : Array Operation
  deriving BEq, Inhabited, Repr

/-- Typed NEAR host-call/Wasm recipe. Rendering WAT is deliberately later than
the exact Plan-to-recipe binding check.
    Private `mk`: public Plan→IR construction is capability-gated only
    (`irFromCapability`); the private packaging ctor is not a product emission API. -/
structure IR where
  private mk ::
  sourcePlan : Plan
  name : String
  imports : Array HostImport
  registers : RegisterLayout
  keys : Array KeyRegion
  memory : MemoryLayout
  methods : Array MethodIR
  fns : Array FnIR
  -- No Inhabited: IR embeds Plan → TargetDescriptor identities.
  deriving BEq, Repr

private def align8 (value : Nat) : Nat :=
  ((value + 7) / 8) * 8

private def makeKeyRegions (plan : Plan) : Array KeyRegion := Id.run do
  let mut regions : Array KeyRegion := #[]
  let mut offset := 0
  let markerLength := plan.storage.markerKey.toUTF8.size
  regions := regions.push { key := plan.storage.markerKey, offset, length := markerLength }
  offset := offset + markerLength
  for field in plan.storage.fields do
    let length := field.key.toUTF8.size
    regions := regions.push { key := field.key, offset, length }
    offset := offset + length
  return regions

private def maxInputLen (plan : Plan) : Nat :=
  plan.entries.foldl (fun current method => max current method.exactInputLen)
    plan.initializer.exactInputLen

private def makeMemoryLayout (plan : Plan) (keys : Array KeyRegion) : MemoryLayout :=
  let keysEnd := keys.foldl (fun current key => max current (key.offset + key.length)) 0
  let inputOffset := align8 keysEnd
  let inputCapacity := maxInputLen plan
  let depositOffset := align8 (inputOffset + inputCapacity)
  {
    minPages := plan.resourceLimits.wasmMemoryPages
    inputOffset
    inputCapacity
    depositOffset
    valueOffset := depositOffset + 16
  }

private structure LoweredExpr where
  operations : Array Operation
  value : Nat
  next : Nat
  deriving Inhabited

private def fieldRegion (keys : Array KeyRegion) (fieldIndex : Nat) : KeyRegion :=
  keys[fieldIndex + 1]!

/-- LE i64 limb count for multiword body widths (T9e). -/
private def limbCountOfBitWidth (bitWidth : Nat) : Nat :=
  if bitWidth ≤ 64 then 1 else bitWidth / 64

/-- Split `n` into `count` little-endian UInt64 limbs. -/
private def natToLimbsLE (n : Nat) (count : Nat) : Array UInt64 := Id.run do
  let mut out : Array UInt64 := #[]
  let mut v := n
  for _ in [:count] do
    out := out.push (UInt64.ofNat v)
    v := v / UInt64.size
  pure out

/-- `paramAsTemp`: pureFn bodies bind params to temps `0..n-1` (Wasm params),
    so `.param` is a direct temp reference rather than a host input load.
    `localEnv` maps plan `.localTemp` indices to IR temps (loop induction). -/
private partial def lowerExpr (keys : Array KeyRegion) (next : Nat)
    (paramAsTemp : Bool) (localEnv : Array (Nat × Nat)) : Expr → LoweredExpr
  | .literal value =>
      { operations := #[.literal next value], value := next, next := next + 1 }
  | .bigLiteral bitWidth value =>
      Id.run do
        let nLimbs := limbCountOfBitWidth bitWidth
        let limbs := natToLimbsLE value nLimbs
        let mut ops : Array Operation := #[]
        for i in [:nLimbs] do
          ops := ops.push (.literal (next + i) (limbs[i]!))
        pure { operations := ops, value := next, next := next + nLimbs }
  | .param inputOffset =>
      if paramAsTemp then
        { operations := #[], value := inputOffset / 8, next := next }
      else
        { operations := #[.loadParam next inputOffset], value := next, next := next + 1 }
  | .narrowParam bitWidth inputOffset =>
      let nLimbs := limbCountOfBitWidth bitWidth
      if paramAsTemp then
        -- pureFn params still occupy one Wasm i64 slot each (8-byte pitch).
        { operations := #[], value := inputOffset / 8, next := next }
      else
        { operations := #[.narrowLoadParam bitWidth next inputOffset],
          value := next, next := next + nLimbs }
  | .localTemp index =>
      match localEnv.find? (fun p => p.1 == index) with
      | some (_, irTemp) =>
          { operations := #[], value := irTemp, next := next }
      | none =>
          -- Unresolved local: allocate a sink temp so validation still binds;
          -- well-formed plans always resolve induction locals via forLoop.
          { operations := #[.literal next 0], value := next, next := next + 1 }
  | .blockTimestampSeconds =>
      { operations := #[.blockTimestampSeconds next]
        value := next
        next := next + 1
      }
  | .accountBalance =>
      { operations := #[.accountBalance next]
        value := next
        next := next + 1
      }
  | .callerPrincipalLen =>
      { operations := #[.callerPrincipalLen next]
        value := next
        next := next + 1
      }
  | .callerPrincipalWord wordIndex =>
      { operations := #[.callerPrincipalWord next wordIndex]
        value := next
        next := next + 1
      }
  | .stateLoad fieldIndex =>
      {
        operations := #[.loadState next (fieldRegion keys fieldIndex)]
        value := next
        next := next + 1
      }
  | .narrowStateLoad bitWidth fieldIndex =>
      let nLimbs := limbCountOfBitWidth bitWidth
      {
        operations := #[.narrowLoadState bitWidth next (fieldRegion keys fieldIndex)]
        value := next
        next := next + nLimbs
      }
  | .checkedAdd lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedAdd rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedSub lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedSub rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedMul lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedMul rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedDiv lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedDiv rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedMod lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedMod rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .bitAnd lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.bitAnd rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .bitOr lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.bitOr rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .bitXor lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.bitXor rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .shl lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.shl rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .shr lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.shr rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .bitNot operand =>
      let operand := lowerExpr keys next paramAsTemp localEnv operand
      {
        operations := operand.operations ++ #[.bitNot operand.next operand.value]
        value := operand.next
        next := operand.next + 1
      }
  | .narrowCheckedAdd bitWidth lhs rhs =>
      let nLimbs := limbCountOfBitWidth bitWidth
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedAdd bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + nLimbs
      }
  | .narrowCheckedSub bitWidth lhs rhs =>
      let nLimbs := limbCountOfBitWidth bitWidth
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedSub bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + nLimbs
      }
  | .narrowCheckedMul bitWidth lhs rhs =>
      let nLimbs := limbCountOfBitWidth bitWidth
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedMul bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + nLimbs
      }
  | .narrowCheckedDiv bitWidth lhs rhs =>
      let nLimbs := limbCountOfBitWidth bitWidth
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedDiv bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + nLimbs
      }
  | .narrowCheckedMod bitWidth lhs rhs =>
      let nLimbs := limbCountOfBitWidth bitWidth
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedMod bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + nLimbs
      }
  | .narrowBitAnd bitWidth lhs rhs =>
      let nLimbs := limbCountOfBitWidth bitWidth
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowBitAnd bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + nLimbs
      }
  | .narrowBitOr bitWidth lhs rhs =>
      let nLimbs := limbCountOfBitWidth bitWidth
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowBitOr bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + nLimbs
      }
  | .narrowBitXor bitWidth lhs rhs =>
      let nLimbs := limbCountOfBitWidth bitWidth
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowBitXor bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + nLimbs
      }
  | .narrowBitNot bitWidth operand =>
      let nLimbs := limbCountOfBitWidth bitWidth
      let operand := lowerExpr keys next paramAsTemp localEnv operand
      {
        operations := operand.operations ++
          #[.narrowBitNot bitWidth operand.next operand.value]
        value := operand.next
        next := operand.next + nLimbs
      }
  | .narrowShl bitWidth lhs rhs =>
      let nLimbs := limbCountOfBitWidth bitWidth
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowShl bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + nLimbs
      }
  | .narrowShr bitWidth lhs rhs =>
      let nLimbs := limbCountOfBitWidth bitWidth
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowShr bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + nLimbs
      }
  | .boolNot operand =>
      let operand := lowerExpr keys next paramAsTemp localEnv operand
      {
        operations := operand.operations ++ #[.boolNot operand.next operand.value]
        value := operand.next
        next := operand.next + 1
      }
  | .boolAnd lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.boolAnd rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .boolOr lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.boolOr rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .compare op lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.compare rhs.next lhs.value rhs.value op]
        value := rhs.next
        next := rhs.next + 1
      }
  | .wideCompare bitWidth op lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.wideCompare bitWidth rhs.next lhs.value rhs.value op]
        value := rhs.next
        next := rhs.next + 1
      }
  | .signedCheckedAdd lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedAdd rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .signedCheckedSub lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedSub rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .signedCheckedMul lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedMul rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .signedCheckedDiv lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedDiv rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .signedCheckedMod lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedMod rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .signedCompare op lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.signedCompare rhs.next lhs.value rhs.value op]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedNeg operand =>
      let operand := lowerExpr keys next paramAsTemp localEnv operand
      {
        operations := operand.operations ++ #[.checkedNeg operand.next operand.value]
        value := operand.next
        next := operand.next + 1
      }
  | .sar lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.sar rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .callFn fnIndex args => Id.run do
      let mut operations : Array Operation := #[]
      let mut next := next
      let mut argTemps : Array Nat := #[]
      for arg in args do
        let lowered := lowerExpr keys next paramAsTemp localEnv arg
        operations := operations ++ lowered.operations
        argTemps := argTemps.push lowered.value
        next := lowered.next
      pure {
        operations := operations.push (.callFn fnIndex next argTemps)
        value := next
        next := next + 1
      }

/-- Whether every path through a statement list ends in a return (valued or
    bare marker), matching the region emitter's closedness: a list closes iff
    its last statement is a return or a region whose arms all close. An empty
    else/default arm is a fallthrough (open). Used to append a hard `return`
    after arms whose value_return would otherwise fall through into the
    region's continuation (the host call does not halt execution). -/
private partial def statementListClosesV1 : List Statement → Bool
  | [] => false
  | [statement] =>
      match statement with
      | .returnValue _ | .returnAggregate .. | .returnNone | .revertError .. => true
      | .ifThenElse _ thenBody elseBody =>
          !elseBody.isEmpty && statementListClosesV1 thenBody.toList &&
            statementListClosesV1 elseBody.toList
      | .switchOn _ cases defaultBody =>
          !defaultBody.isEmpty && statementListClosesV1 defaultBody.toList &&
            cases.all fun (_, caseBody) => statementListClosesV1 caseBody.toList
      | .store _ | .storeAtomic _ | .assert _ | .emitEvent .. | .forLoop ..
      | .promiseAccount .. | .nativeDeposit _ | .promiseTransfer ..
      | .promiseTokenTransfer .. => false
  | _ :: _ :: rest => statementListClosesV1 rest

/-- Append the hard return after a closed region arm, unless the arm already
    ends in a halting statement (the initializer's bare-return marker, a
    declared revert, or — in pureFn mode — a valued `return` which is already
    a Wasm `return`). Aggregate `value_return` does not halt (same as scalar). -/
private def armOpsWithHardReturn (arm : Array Statement)
    (operations : Array Operation) (fnMode : Bool) : Array Operation :=
  let alreadyHalts := match arm.back? with
    | some .returnNone | some (.revertError ..) => true
    | some (.returnValue _) => fnMode
    | some (.returnAggregate ..) => false
    | _ => false
  if statementListClosesV1 arm.toList && !alreadyHalts then
    operations.push .returnNone
  else
    operations

private partial def lowerBodyOps
    (keys : Array KeyRegion) (next : Nat) (statements : Array Statement)
    (fnMode : Bool) (localEnv : Array (Nat × Nat))
    (returnByteLen : Nat) :
    Array Operation × Nat := Id.run do
  let mut operations : Array Operation := #[]
  let mut next := next
  let mut localEnv := localEnv
  for statement in statements do
    match statement with
    | .store store =>
        let value := lowerExpr keys next fnMode localEnv store.value
        operations := operations ++ value.operations
        let storeOp : Operation :=
          if store.byteWidth == 8 then
            .storeState (fieldRegion keys store.fieldIndex) value.value
          else
            .narrowStoreState (store.byteWidth * 8) (fieldRegion keys store.fieldIndex) value.value
        operations := operations.push storeOp
        next := value.next
    | .storeAtomic leaves =>
        -- Two-phase snapshot: lower every leaf Expr first (all stateLoads read
        -- the pre-store KV), then emit all store ops. Sequential lower+store
        -- would make later leaves observe earlier writes mid-Map upsert.
        let mut valueTemps : Array (Nat × Nat × Nat) := #[]
        for store in leaves do
          let value := lowerExpr keys next fnMode localEnv store.value
          operations := operations ++ value.operations
          valueTemps := valueTemps.push (store.fieldIndex, store.byteWidth, value.value)
          next := value.next
        for item in valueTemps do
          let (fieldIndex, byteWidth, temp) := item
          let storeOp : Operation :=
            if byteWidth == 8 then
              .storeState (fieldRegion keys fieldIndex) temp
            else
              .narrowStoreState (byteWidth * 8) (fieldRegion keys fieldIndex) temp
          operations := operations.push storeOp
    | .returnValue value =>
        let value := lowerExpr keys next fnMode localEnv value
        operations := operations ++ value.operations
        if fnMode then
          operations := operations.push (.returnValue value.value)
        else
          operations := operations.push (.setReturnData returnByteLen value.value)
        next := value.next
    | .returnAggregate leaves _leafIsInt =>
        -- B-RET-ABI: lower each preorder leaf independently, then pack via
        -- setReturnDataLeaves (temps need not be consecutive).
        let mut leafTemps : Array Nat := #[]
        for leaf in leaves do
          let lowered := lowerExpr keys next fnMode localEnv leaf
          operations := operations ++ lowered.operations
          leafTemps := leafTemps.push lowered.value
          next := lowered.next
        operations := operations.push (.setReturnDataLeaves leafTemps)
    | .returnNone =>
        -- Valid only inside region arms (validated); the initializer's own
        -- final marker is stripped by lowerMethod before lowering.
        operations := operations.push .returnNone
    | .emitEvent eventIndex args =>
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let value := lowerExpr keys next fnMode localEnv arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push (.emitEvent eventIndex argTemps)
    | .promiseAccount receiver method args =>
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let value := lowerExpr keys next fnMode localEnv arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push (.promiseAccount receiver method argTemps)
    | .nativeDeposit amount =>
        let value := lowerExpr keys next fnMode localEnv amount
        operations := operations ++ value.operations
        operations := operations.push (.requireExactAttachedDeposit value.value)
        next := value.next
    | .promiseTransfer dstLen dstWords amount =>
        let lenL := lowerExpr keys next fnMode localEnv dstLen
        operations := operations ++ lenL.operations
        next := lenL.next
        let mut wordTemps : Array Nat := #[]
        for w in dstWords do
          let wl := lowerExpr keys next fnMode localEnv w
          operations := operations ++ wl.operations
          wordTemps := wordTemps.push wl.value
          next := wl.next
        let amtL := lowerExpr keys next fnMode localEnv amount
        operations := operations ++ amtL.operations
        next := amtL.next
        operations := operations.push
          (.promiseTransfer lenL.value wordTemps amtL.value)
    | .promiseTokenTransfer mintLen mintWords dstLen dstWords amount =>
        let mintLenL := lowerExpr keys next fnMode localEnv mintLen
        operations := operations ++ mintLenL.operations
        next := mintLenL.next
        let mut mintWordTemps : Array Nat := #[]
        for w in mintWords do
          let wl := lowerExpr keys next fnMode localEnv w
          operations := operations ++ wl.operations
          mintWordTemps := mintWordTemps.push wl.value
          next := wl.next
        let dstLenL := lowerExpr keys next fnMode localEnv dstLen
        operations := operations ++ dstLenL.operations
        next := dstLenL.next
        let mut dstWordTemps : Array Nat := #[]
        for w in dstWords do
          let wl := lowerExpr keys next fnMode localEnv w
          operations := operations ++ wl.operations
          dstWordTemps := dstWordTemps.push wl.value
          next := wl.next
        let amtL := lowerExpr keys next fnMode localEnv amount
        operations := operations ++ amtL.operations
        next := amtL.next
        operations := operations.push
          (.promiseTokenTransfer mintLenL.value mintWordTemps
            dstLenL.value dstWordTemps amtL.value)
    | .revertError errorIndex args =>
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let value := lowerExpr keys next fnMode localEnv arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push (.revertError errorIndex argTemps)
    | .assert condition =>
        let value := lowerExpr keys next fnMode localEnv condition
        operations := operations ++ value.operations
        operations := operations.push (.assert value.value)
        next := value.next
    | .ifThenElse condition thenBody elseBody =>
        let value := lowerExpr keys next fnMode localEnv condition
        operations := operations ++ value.operations
        let (thenOps, next1) := lowerBodyOps keys value.next thenBody fnMode localEnv returnByteLen
        let (elseOps, next2) := lowerBodyOps keys next1 elseBody fnMode localEnv returnByteLen
        operations := operations.push (.ifRegion value.value
          (armOpsWithHardReturn thenBody thenOps fnMode)
          (armOpsWithHardReturn elseBody elseOps fnMode))
        next := next2
    | .switchOn scrutinee cases defaultBody =>
        let value := lowerExpr keys next fnMode localEnv scrutinee
        operations := operations ++ value.operations
        let mut caseOps : Array (UInt64 × Array Operation) := #[]
        let mut nextC := value.next
        for (caseValue, caseBody) in cases do
          let (ops, next1) := lowerBodyOps keys nextC caseBody fnMode localEnv returnByteLen
          caseOps := caseOps.push (caseValue, armOpsWithHardReturn caseBody ops fnMode)
          nextC := next1
        let (defaultOps, nextD) := lowerBodyOps keys nextC defaultBody fnMode localEnv returnByteLen
        operations := operations.push (.switchRegion value.value caseOps
          (armOpsWithHardReturn defaultBody defaultOps fnMode))
        next := nextD
    | .forLoop varTemp initial condition update maxIterations body =>
        let initL := lowerExpr keys next fnMode localEnv initial
        operations := operations ++ initL.operations
        let irVar := initL.next
        let counterTemp := initL.next + 1
        next := initL.next + 2
        -- Seed the induction temp from the initial expression.
        -- forRegion copies initial → varTemp at entry and zeroes counterTemp.
        let localEnv' := localEnv.push (varTemp, irVar)
        let condL := lowerExpr keys next fnMode localEnv' condition
        let condOps := condL.operations
        let condTemp := condL.value
        next := condL.next
        let (bodyOps, nextB) := lowerBodyOps keys next body fnMode localEnv' returnByteLen
        next := nextB
        let updateL := lowerExpr keys next fnMode localEnv' update
        let updateOps := updateL.operations
        let updateTemp := updateL.value
        next := updateL.next
        operations := operations.push
          (.forRegion irVar initL.value counterTemp maxIterations
            condOps condTemp bodyOps updateOps updateTemp)
        localEnv := localEnv'
  pure (operations, next)


private def methodResultByteLen : MethodResultKind → Nat
  | .unit => 8
  | .uint64 | .int64 | .bool => 8
  | .uint8 | .int8 => 1
  | .uint16 | .int16 => 2
  | .uint32 | .int32 => 4
  | .uint128 => 16
  | .uint256 => 32
  -- Aggregate return uses setReturnDataLeaves (byteLen derived from temps);
  -- returnByteLen is unused for that path but kept defined for lowerMethod.
  | .aggregate leaves => 8 * leaves.size

private def lowerMethod (plan : Plan) (keys : Array KeyRegion)
    (method : Method) : MethodIR := Id.run do
  let marker := keys[0]!
  let mut operations : Array Operation := #[.checkInputLen method.exactInputLen]
  -- ADR-0029 C2: allowAttached skips the prologue zero-deposit gate so body
  -- `requireExactAttachedDeposit` is the sole authority; queryOnly views never
  -- call attached_deposit (NEAR ViewFunction forbids it).
  if method.depositPolicy == .requireZero then
    operations := operations.push .requireZeroAttachedDeposit
  if method.mode == .initialize then
    operations := operations.push (.requireLayoutAbsent marker)
    for index in [0:plan.storage.fields.size] do
      let field := plan.storage.fields[index]!
      let zeroOp : Operation :=
        if field.byteWidth == 8 then
          .zeroState (fieldRegion keys index)
        else
          .narrowZeroState (field.byteWidth * 8) (fieldRegion keys index)
      operations := operations.push zeroOp
  else
    operations := operations.push (.requireLayout marker plan.storage.markerValue)
  -- The initializer's final bare-return marker is the natural fall-through;
  -- in-arm markers are rejected by validatePlan and never reach this point.
  let body := if method.body.back? == some .returnNone then
    method.body.pop
  else
    method.body
  let (bodyOps, next) := lowerBodyOps keys 0 body false #[] (methodResultByteLen method.resultKind)
  operations := operations ++ bodyOps
  if method.mode == .initialize then
    operations := operations.push (.setLayout marker plan.storage.markerValue)
  return {
    name := method.name
    params := method.params
    mode := method.mode
    tempCount := next
    operations
  }

private def lowerFn (keys : Array KeyRegion) (fn : FnBinding) : FnIR :=
  let paramCount := fn.params.size
  -- Temps `0..paramCount-1` are the Wasm parameters; body lowering starts after.
  let (bodyOps, next) := lowerBodyOps keys paramCount fn.body true #[] 8
  {
    name := fn.name
    paramCount
    resultIsBool := fn.resultIsBool
    tempCount := next
    operations := bodyOps
  }

private def expectedMethods (plan : Plan) (keys : Array KeyRegion) : Array MethodIR :=
  #[lowerMethod plan keys plan.initializer] ++ plan.entries.map (lowerMethod plan keys)

private def expectedFns (plan : Plan) (keys : Array KeyRegion) : Array FnIR :=
  plan.fns.map (lowerFn keys)

/-- PureFn ops may not touch host storage, layout, deposits, method returns,
    or host context reads (timestamp/balance/caller). -/
private partial def opIsMethodOnlyV1 : Operation → Bool
  | .checkInputLen _ | .requireZeroAttachedDeposit | .requireExactAttachedDeposit _
  | .requireLayoutAbsent _ | .requireLayout _ _
  | .zeroState _ | .narrowZeroState _ _
  | .loadState _ _ | .narrowLoadState _ _ _
  | .storeState _ _ | .narrowStoreState _ _ _
  | .setLayout _ _ | .setReturnData _ _ | .setReturnDataLeaves _
  | .loadParam _ _ | .narrowLoadParam _ _ _
  | .blockTimestampSeconds _ | .accountBalance _
  | .callerPrincipalLen _ | .callerPrincipalWord _ _ => true
  | .ifRegion _ thenOps elseOps =>
      thenOps.any opIsMethodOnlyV1 || elseOps.any opIsMethodOnlyV1
  | .switchRegion _ cases defaultOps =>
      defaultOps.any opIsMethodOnlyV1 ||
        cases.any fun (_, ops) => ops.any opIsMethodOnlyV1
  | .forRegion _ _ _ _ condOps _ bodyOps updateOps _ =>
      condOps.any opIsMethodOnlyV1 || bodyOps.any opIsMethodOnlyV1 ||
        updateOps.any opIsMethodOnlyV1
  | _ => false

private partial def opIsFnReturnValueV1 : Operation → Bool
  | .returnValue _ => true
  | .ifRegion _ thenOps elseOps =>
      thenOps.any opIsFnReturnValueV1 || elseOps.any opIsFnReturnValueV1
  | .switchRegion _ cases defaultOps =>
      defaultOps.any opIsFnReturnValueV1 ||
        cases.any fun (_, ops) => ops.any opIsFnReturnValueV1
  | .forRegion _ _ _ _ condOps _ bodyOps updateOps _ =>
      condOps.any opIsFnReturnValueV1 || bodyOps.any opIsFnReturnValueV1 ||
        updateOps.any opIsFnReturnValueV1
  | _ => false

/-- Validate the typed host-call recipe and bind it exactly to its source Plan. -/
def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless ir.name == ir.sourcePlan.programName do
    throw <| .planInvariant .near "typed NEAR IR identity is not bound to its source Plan"
  unless ir.imports == ir.sourcePlan.hostImports && ir.registers == canonicalRegisters do
    throw <| .planInvariant .near "typed NEAR IR host imports/registers are not canonical"
  let expectedKeys := makeKeyRegions ir.sourcePlan
  unless ir.keys == expectedKeys do
    throw <| .planInvariant .near "typed NEAR IR key regions are not bound to the Plan KV layout"
  let expectedMemory := makeMemoryLayout ir.sourcePlan expectedKeys
  unless ir.memory == expectedMemory &&
      ir.memory.minPages == ir.sourcePlan.resourceLimits.wasmMemoryPages &&
      ir.memory.valueOffset + 8 <= ir.memory.minPages * wasmPageBytes do
    throw <| .planInvariant .near "typed NEAR IR memory layout is not canonical or exceeds one page"
  if ir.methods.size != ir.sourcePlan.entries.size + 1 then
    throw <| .planInvariant .near "typed NEAR IR export count does not match its source Plan"
  if ir.fns.size != ir.sourcePlan.fns.size then
    throw <| .planInvariant .near "typed NEAR IR pureFn count does not match its source Plan"
  for method in ir.methods do
    if method.tempCount > ir.sourcePlan.resourceLimits.maxMethodLocals then
      throw <| .planInvariant .near
        s!"typed NEAR IR method '{method.name}' exceeds local limit {ir.sourcePlan.resourceLimits.maxMethodLocals}"
    if method.operations.any opIsFnReturnValueV1 then
      throw <| .planInvariant .near
        s!"typed NEAR IR method '{method.name}' must not use pureFn returnValue ops"
  for fn in ir.fns do
    if fn.tempCount > ir.sourcePlan.resourceLimits.maxMethodLocals then
      throw <| .planInvariant .near
        s!"typed NEAR IR pureFn '{fn.name}' exceeds local limit {ir.sourcePlan.resourceLimits.maxMethodLocals}"
    if fn.operations.any opIsMethodOnlyV1 then
      throw <| .planInvariant .near
        s!"typed NEAR IR pureFn '{fn.name}' must not use method-only host ops"
  let operationCount :=
    ir.methods.foldl (fun total method =>
      total + method.params.size + method.operations.size) 0 +
    ir.fns.foldl (fun total fn =>
      total + fn.paramCount + fn.operations.size) 0
  if operationCount > ir.sourcePlan.resourceLimits.maxRecipeNodes then
    throw <| .planInvariant .near
      s!"typed NEAR IR exceeds recipe node limit {ir.sourcePlan.resourceLimits.maxRecipeNodes}"
  let expected := expectedMethods ir.sourcePlan expectedKeys
  unless ir.methods == expected do
    throw <| .planInvariant .near
      "typed NEAR IR methods/operations are not the exact lowering of their source Plan"
  let expectedFnIR := expectedFns ir.sourcePlan expectedKeys
  unless ir.fns == expectedFnIR do
    throw <| .planInvariant .near
      "typed NEAR IR pureFn operations are not the exact lowering of their source Plan"

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let keys := makeKeyRegions plan
  let memory := makeMemoryLayout plan keys
  let ir : IR := {
    sourcePlan := plan
    name := plan.programName
    imports := plan.hostImports
    registers := canonicalRegisters
    keys
    memory
    methods := expectedMethods plan keys
    fns := expectedFns plan keys
  }
  validateIR ir
  return ir

private def uint64Hex (value : UInt64) : String :=
  let raw := String.ofList (Nat.toDigits 16 value.toNat)
  let raw := if raw.isEmpty then "0" else raw
  String.ofList (List.replicate (16 - raw.length) '0') ++ raw

private def renderImport : HostImport → String
  | .input => "  (import \"env\" \"input\" (func $pf_input (param i64)))\n"
  | .registerLen =>
      "  (import \"env\" \"register_len\" (func $pf_register_len (param i64) (result i64)))\n"
  | .readRegister =>
      "  (import \"env\" \"read_register\" (func $pf_read_register (param i64 i64)))\n"
  | .storageRead =>
      "  (import \"env\" \"storage_read\" (func $pf_storage_read (param i64 i64 i64) (result i64)))\n"
  | .storageWrite =>
      "  (import \"env\" \"storage_write\" (func $pf_storage_write (param i64 i64 i64 i64 i64) (result i64)))\n"
  | .valueReturn =>
      "  (import \"env\" \"value_return\" (func $pf_value_return (param i64 i64)))\n"
  | .attachedDeposit =>
      "  (import \"env\" \"attached_deposit\" (func $pf_attached_deposit (param i64)))\n"
  | .logUtf8 =>
      "  (import \"env\" \"log_utf8\" (func $pf_log_utf8 (param i64 i64)))\n"
  | .panicUtf8 =>
      "  (import \"env\" \"panic_utf8\" (func $pf_panic_utf8 (param i64 i64)))\n"
  | .blockTimestamp =>
      "  (import \"env\" \"block_timestamp\" (func $pf_block_timestamp (result i64)))\n"
  | .accountBalance =>
      -- ADR-0030 E2-NEAR: account_balance writes u128 LE to balance_ptr
      -- (same ABI shape as attached_deposit: one pointer param, void return).
      "  (import \"env\" \"account_balance\" (func $pf_account_balance (param i64)))\n"
  | .predecessorAccountId =>
      -- ADR-0031 S1: predecessor_account_id writes UTF-8 account-id into
      -- register_id (void). View contexts forbid this host call at runtime;
      -- Plan already fail-closes view ContextRead caller.
      "  (import \"env\" \"predecessor_account_id\" (func $pf_predecessor_account_id (param i64)))\n"
  | .promiseBatchCreate =>
      -- account_id_len, account_id_ptr → promise_index
      "  (import \"env\" \"promise_batch_create\" (func $pf_promise_batch_create (param i64 i64) (result i64)))\n"
  | .promiseBatchActionFunctionCall =>
      -- promise_idx, method_len, method_ptr, args_len, args_ptr,
      -- amount_ptr (pointer to 16-byte LE u128 deposit), gas.
      -- Deposit/gas are always zero placeholders in the schedule pilot
      -- (explicit in the call site, not silent economics).
      "  (import \"env\" \"promise_batch_action_function_call\" (func $pf_promise_batch_action_function_call (param i64 i64 i64 i64 i64 i64 i64)))\n"
  | .promiseBatchActionTransfer =>
      -- ADR-0029 C2: promise_idx, amount_ptr → 16-byte little-endian u128.
      "  (import \"env\" \"promise_batch_action_transfer\" (func $pf_promise_batch_action_transfer (param i64 i64)))\n"


/-- Multiword checked add on consecutive i64 temps (LE limbs); final carry → trap.
    Uses scratch locals `$t_mw_a`, `$t_mw_b`, `$t_mw_carry` declared in each method. -/
private def renderMultiwordCheckedAdd (indent : String) (dest lhs rhs nLimbs : Nat) : String :=
  Id.run do
    let mut out := s!"{indent};; multiword checked_add nLimbs={nLimbs}\n"
    out := out ++ s!"{indent}(local.set $t_mw_carry (i64.const 0))\n"
    for i in [:nLimbs] do
      out := out ++
        s!"{indent}(local.set $t_mw_a (local.get $t{lhs + i}))\n" ++
        s!"{indent}(local.set $t_mw_b (local.get $t{rhs + i}))\n" ++
        s!"{indent}(local.set $t{dest + i} (i64.add (i64.add (local.get $t_mw_a) (local.get $t_mw_b)) (local.get $t_mw_carry)))\n" ++
        s!"{indent}(local.set $t_mw_carry (i64.or (i64.extend_i32_u (i64.lt_u (local.get $t{dest + i}) (local.get $t_mw_a))) (i64.and (local.get $t_mw_carry) (i64.extend_i32_u (i64.eq (local.get $t{dest + i}) (local.get $t_mw_a))))))\n"
    out := out ++ s!"{indent}(if (i64.ne (local.get $t_mw_carry) (i64.const 0)) (then unreachable))\n"
    pure out

/-- Multiword checked sub; final borrow → trap. -/
private def renderMultiwordCheckedSub (indent : String) (dest lhs rhs nLimbs : Nat) : String :=
  Id.run do
    let mut out := s!"{indent};; multiword checked_sub nLimbs={nLimbs}\n"
    out := out ++ s!"{indent}(local.set $t_mw_carry (i64.const 0))\n"
    for i in [:nLimbs] do
      out := out ++
        s!"{indent}(local.set $t_mw_a (local.get $t{lhs + i}))\n" ++
        s!"{indent}(local.set $t_mw_b (local.get $t{rhs + i}))\n" ++
        s!"{indent}(local.set $t{dest + i} (i64.sub (i64.sub (local.get $t_mw_a) (local.get $t_mw_b)) (local.get $t_mw_carry)))\n" ++
        s!"{indent}(local.set $t_mw_carry (i64.or (i64.extend_i32_u (i64.lt_u (local.get $t_mw_a) (local.get $t_mw_b))) (i64.and (local.get $t_mw_carry) (i64.extend_i32_u (i64.eq (local.get $t_mw_a) (local.get $t_mw_b))))))\n"
    out := out ++ s!"{indent}(if (i64.ne (local.get $t_mw_carry) (i64.const 0)) (then unreachable))\n"
    pure out

/-- Multiword checked mul: exact base-2^32 schoolbook product on consecutive
    i64 limbs (LE). Writes 2·nLimbs result limbs to `dest..dest+2n-1`, then
    traps unless the high nLimbs are zero (the product fits the operand
    width). Each 64×64 limb product is decomposed into 32-bit halves
    (`hi = x1·y1 + w2 + (w1>>32)`, `lo = (w0 & 0xffffffff) | ((w1 & 0xffffffff)
    << 32)` — verified against Nat arithmetic in the host model), and the
    accumulation is a fixed-length ripple: the carry is 0/1 and adding 0
    never re-ignites it, so unrolling to the result width is exact.
    Uses scratch locals `$t_mw_a..$t_mw_7` declared in each method.
    Engineering-only; not formal D2/D4. -/
private def renderMultiwordCheckedMul (indent : String) (dest lhs rhs nLimbs : Nat) : String :=
  Id.run do
    let mut out := s!"{indent};; multiword checked_mul nLimbs={nLimbs}\n"
    for k in [:2 * nLimbs] do
      out := out ++ s!"{indent}(local.set $t{dest + k} (i64.const 0))\n"
    -- Ripple-add the 64-bit value in `$t_mw_6` at column `col` (fixed steps).
    let addAt := fun (col : Nat) => Id.run do
      let mut s := ""
      s := s ++ s!"{indent}(local.set $t_mw_a (local.get $t{dest + col}))\n"
      s := s ++ s!"{indent}(local.set $t{dest + col} (i64.add (local.get $t_mw_a) (local.get $t_mw_6)))\n"
      s := s ++ s!"{indent}(local.set $t_mw_7 (i64.extend_i32_u (i64.lt_u (local.get $t{dest + col}) (local.get $t_mw_a))))\n"
      for k in [col + 1 : 2 * nLimbs] do
        s := s ++ s!"{indent}(local.set $t_mw_a (local.get $t{dest + k}))\n"
        s := s ++ s!"{indent}(local.set $t{dest + k} (i64.add (local.get $t_mw_a) (local.get $t_mw_7)))\n"
        s := s ++ s!"{indent}(local.set $t_mw_7 (i64.extend_i32_u (i64.lt_u (local.get $t{dest + k}) (local.get $t_mw_a))))\n"
      pure s
    for i in [:nLimbs] do
      for j in [:nLimbs] do
        out := out ++ s!"{indent};; limb pair ({i},{j})\n"
        out := out ++ s!"{indent}(local.set $t_mw_a (i64.and (local.get $t{lhs + i}) (i64.const 4294967295)))\n"
        out := out ++ s!"{indent}(local.set $t_mw_b (i64.shr_u (local.get $t{lhs + i}) (i64.const 32)))\n"
        out := out ++ s!"{indent}(local.set $t_mw_carry (i64.and (local.get $t{rhs + j}) (i64.const 4294967295)))\n"
        out := out ++ s!"{indent}(local.set $t_mw_0 (i64.shr_u (local.get $t{rhs + j}) (i64.const 32)))\n"
        out := out ++ s!"{indent}(local.set $t_mw_1 (i64.mul (local.get $t_mw_a) (local.get $t_mw_carry)))\n"
        out := out ++ s!"{indent}(local.set $t_mw_2 (i64.add (i64.mul (local.get $t_mw_b) (local.get $t_mw_carry)) (i64.shr_u (local.get $t_mw_1) (i64.const 32))))\n"
        out := out ++ s!"{indent}(local.set $t_mw_3 (i64.and (local.get $t_mw_2) (i64.const 4294967295)))\n"
        out := out ++ s!"{indent}(local.set $t_mw_4 (i64.shr_u (local.get $t_mw_2) (i64.const 32)))\n"
        out := out ++ s!"{indent}(local.set $t_mw_3 (i64.add (i64.mul (local.get $t_mw_a) (local.get $t_mw_0)) (local.get $t_mw_3)))\n"
        out := out ++ s!"{indent}(local.set $t_mw_5 (i64.add (i64.add (i64.mul (local.get $t_mw_b) (local.get $t_mw_0)) (local.get $t_mw_4)) (i64.shr_u (local.get $t_mw_3) (i64.const 32))))\n"
        out := out ++ s!"{indent}(local.set $t_mw_6 (i64.or (i64.shl (i64.and (local.get $t_mw_3) (i64.const 4294967295)) (i64.const 32)) (i64.and (local.get $t_mw_1) (i64.const 4294967295))))\n"
        out := out ++ addAt (i + j)
        out := out ++ s!"{indent}(local.set $t_mw_6 (local.get $t_mw_5))\n"
        out := out ++ addAt (i + j + 1)
    -- Overflow gate: the high nLimbs must be zero (product < 2^(64·nLimbs)).
    for k in [nLimbs : 2 * nLimbs] do
      out := out ++ s!"{indent}(if (i64.ne (local.get $t{dest + k}) (i64.const 0)) (then unreachable))\n"
    pure out

/-- Load a LE integer of `byteWidth` from `addr` into an i64 local (zero-extend). -/
private def renderLoadLeToI64 (indent : String) (destination addr byteWidth : Nat) : String :=
  match byteWidth with
  | 1 =>
      s!"{indent}(local.set $t{destination} (i64.extend_i32_u (i32.load8_u (i32.const {addr}))))\n"
  | 2 =>
      s!"{indent}(local.set $t{destination} (i64.extend_i32_u (i32.load16_u (i32.const {addr}))))\n"
  | 4 =>
      s!"{indent}(local.set $t{destination} (i64.extend_i32_u (i32.load (i32.const {addr}))))\n"
  | _ =>
      s!"{indent}(local.set $t{destination} (i64.load (i32.const {addr})))\n"

/-- Store low `byteWidth` bytes of an i64 local to `addr` (LE). -/
private def renderStoreI64Le (indent : String) (addr valueTemp byteWidth : Nat) : String :=
  match byteWidth with
  | 1 =>
      s!"{indent}(i32.store8 (i32.const {addr}) (i32.wrap_i64 (local.get $t{valueTemp})))\n"
  | 2 =>
      s!"{indent}(i32.store16 (i32.const {addr}) (i32.wrap_i64 (local.get $t{valueTemp})))\n"
  | 4 =>
      s!"{indent}(i32.store (i32.const {addr}) (i32.wrap_i64 (local.get $t{valueTemp})))\n"
  | _ =>
      s!"{indent}(i64.store (i32.const {addr}) (local.get $t{valueTemp}))\n"

/-- Zero `byteWidth` bytes at `addr`. Multiword widths (16/32) zero each
    i64 limb so the KV value is fully zeroed (a single 8-byte store would
    leave the high limbs uninitialized). -/
private def renderZeroLe (indent : String) (addr byteWidth : Nat) : String :=
  match byteWidth with
  | 1 => s!"{indent}(i32.store8 (i32.const {addr}) (i32.const 0))\n"
  | 2 => s!"{indent}(i32.store16 (i32.const {addr}) (i32.const 0))\n"
  | 4 => s!"{indent}(i32.store (i32.const {addr}) (i32.const 0))\n"
  | 8 => s!"{indent}(i64.store (i32.const {addr}) (i64.const 0))\n"
  | _ => Id.run do
      let mut out := ""
      for i in [:byteWidth / 8] do
        out := out ++ s!"{indent}(i64.store (i32.const {addr + i * 8}) (i64.const 0))\n"
      pure out

private def renderReadKey (registers : RegisterLayout) (memory : MemoryLayout)
    (indent : String) (destination : Nat) (field : KeyRegion)
    (byteWidth : Nat := 8) : String :=
  let header :=
    s!"{indent}(if (i64.ne (call $pf_storage_read (i64.const {field.length}) (i64.const {field.offset}) (i64.const {registers.storage})) (i64.const 1)) (then unreachable))\n" ++
      s!"{indent}(if (i64.ne (call $pf_register_len (i64.const {registers.storage})) (i64.const {byteWidth})) (then unreachable))\n" ++
      s!"{indent}(call $pf_read_register (i64.const {registers.storage}) (i64.const {memory.valueOffset}))\n"
  if byteWidth > 8 then
    Id.run do
      let nLimbs := byteWidth / 8
      let mut out := header
      for i in [:nLimbs] do
        out := out ++
          s!"{indent}(local.set $t{destination + i} (i64.load (i32.const {memory.valueOffset + i * 8})))\n"
      pure out
  else
    header ++ renderLoadLeToI64 indent destination memory.valueOffset byteWidth


/-- Offset of the transient interface-message scratch region (right after the
    8-byte value-return cell; bounded well inside the first memory page). -/
private def messageOffset (memory : MemoryLayout) : Nat :=
  memory.valueOffset + 8

/-- Render a u64 temp as 16 lowercase-hex chars (MSB first) at consecutive
    scratch offsets. `c = d + 48 + 39·(d > 9)` per nibble. -/
private def renderHexArg (indent : String) (offset : Nat) (arg : Nat) : String := Id.run do
  let mut output := ""
  for nibble in [0:16] do
    let shift := 60 - 4 * nibble
    let digit :=
      s!"(i64.and (i64.shr_u (local.get $t{arg}) (i64.const {shift})) (i64.const 15))"
    output := output ++
      s!"{indent}(i32.store8 (i32.const {offset + nibble}) (i32.add (i32.add (i32.const 48) (i32.wrap_i64 {digit})) (i32.mul (i32.const 39) (i64.gt_u {digit} (i64.const 9)))))\n"
  return output

/-- Render the canonical interface message `pf-{tag}:{name}:{hex,...}` into the
    scratch region and the host call consuming it. -/
private def renderInterfaceMessage (registers : RegisterLayout) (memory : MemoryLayout)
    (indent : String) (tag : String) (hostCall : String)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (isEvent : Bool) (declIndex : Nat) (args : Array Nat) : String := Id.run do
  let _ := registers
  let binding := (if isEvent then events else errors)[declIndex]!
  let prefixBytes := s!"pf-{tag}:{binding.name}".toUTF8
  let offset := messageOffset memory
  let mut output := ""
  for i in [0:prefixBytes.size] do
    output := output ++
      s!"{indent}(i32.store8 (i32.const {offset + i}) (i32.const {prefixBytes[i]!.toNat}))\n"
  let mut cursor := offset + prefixBytes.size
  if !args.isEmpty then
    output := output ++
      s!"{indent}(i32.store8 (i32.const {cursor}) (i32.const 58))\n"
    cursor := cursor + 1
    for j in [0:args.size] do
      if j > 0 then
        output := output ++
          s!"{indent}(i32.store8 (i32.const {cursor}) (i32.const 44))\n"
        cursor := cursor + 1
      output := output ++ renderHexArg indent cursor args[j]!
      cursor := cursor + 16
  output := output ++
    s!"{indent}(call ${hostCall} (i64.const {cursor - offset}) (i64.const {offset}))\n"
  return output

/-- First-seen order of schedule receiver/method strings across the IR, used to
    pin account-id/method bytes as `(data ...)` segments so the WAT artifact
    contains the literal strings (not only store8 immediates). -/
private partial def collectPromiseStringsFromOps (ops : Array Operation) : Array String :=
  ops.foldl (fun acc op =>
    match op with
    | .promiseAccount receiver method _ =>
        let acc := if acc.contains receiver then acc else acc.push receiver
        if acc.contains method then acc else acc.push method
    | .promiseTokenTransfer .. =>
        -- "ft_transfer" is a frozen constant method name pinned as a (data ...)
        -- segment by the WAT renderer; no receiver string (mint is runtime).
        if acc.contains "ft_transfer" then acc else acc.push "ft_transfer"
    | .ifRegion _ thenOps elseOps =>
        acc ++ collectPromiseStringsFromOps thenOps ++ collectPromiseStringsFromOps elseOps
    | .switchRegion _ cases defaultOps =>
        cases.foldl (fun a (_, caseOps) => a ++ collectPromiseStringsFromOps caseOps)
          (acc ++ collectPromiseStringsFromOps defaultOps)
    | .forRegion _ _ _ _ condOps _ bodyOps updateOps _ =>
        acc ++ collectPromiseStringsFromOps condOps ++
          collectPromiseStringsFromOps bodyOps ++
          collectPromiseStringsFromOps updateOps
    | _ => acc) #[]

private def collectPromiseStrings (ir : IR) : Array String :=
  ir.methods.foldl (fun acc m => acc ++ collectPromiseStringsFromOps m.operations) #[] ++
    ir.fns.foldl (fun acc f => acc ++ collectPromiseStringsFromOps f.operations) #[]

/-- Place promise strings in a fixed free region after the value/scratch area so
    they never collide with KV key data, input packing, or deposit cells.
    Returns (string → offset) pairs in first-seen order. -/
private def layoutPromiseStrings (memory : MemoryLayout) (strings : Array String) :
    Array (String × Nat) := Id.run do
  -- valueOffset+8 is the interface-message scratch; leave 1 KiB for event/
  -- error/arg payloads, then pin schedule account/method bytes.
  let mut offset := memory.valueOffset + 1024
  let mut table : Array (String × Nat) := #[]
  for s in strings do
    unless table.any (fun p => p.1 == s) do
      table := table.push (s, offset)
      offset := offset + s.toUTF8.size
  pure table

private def promiseStringOffset (table : Array (String × Nat)) (s : String) : Nat :=
  match table.find? (fun p => p.1 == s) with
  | some (_, off) => off
  | none => 0

private partial def renderOperation (registers : RegisterLayout) (memory : MemoryLayout)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (fnNames : Array String) (promiseStr : Array (String × Nat))
    (indent : String) : Operation → String
  | .checkInputLen bytes =>
      s!"{indent}(call $pf_input (i64.const {registers.input}))\n" ++
        s!"{indent}(if (i64.ne (call $pf_register_len (i64.const {registers.input})) (i64.const {bytes})) (then unreachable))\n" ++
        (if bytes == 0 then "" else
          s!"{indent}(call $pf_read_register (i64.const {registers.input}) (i64.const {memory.inputOffset}))\n")
  | .requireZeroAttachedDeposit =>
      s!"{indent}(call $pf_attached_deposit (i64.const {memory.depositOffset}))\n" ++
        s!"{indent}(if (i64.ne (i64.load (i32.const {memory.depositOffset})) (i64.const 0)) (then unreachable))\n" ++
        s!"{indent}(if (i64.ne (i64.load (i32.const {memory.depositOffset + 8})) (i64.const 0)) (then unreachable))\n"
  | .requireExactAttachedDeposit amount =>
      -- ADR-0029 C2: exact attached_deposit u128 == amount (lo) || 0 (hi).
      -- amount is UInt64 yoctoNEAR; high word must be zero (no silent truncation).
      s!"{indent}(call $pf_attached_deposit (i64.const {memory.depositOffset}))\n" ++
        s!"{indent}(if (i64.ne (i64.load (i32.const {memory.depositOffset})) (local.get $t{amount})) (then unreachable))\n" ++
        s!"{indent}(if (i64.ne (i64.load (i32.const {memory.depositOffset + 8})) (i64.const 0)) (then unreachable))\n"
  | .requireLayoutAbsent marker =>
      s!"{indent}(if (i64.ne (call $pf_storage_read (i64.const {marker.length}) (i64.const {marker.offset}) (i64.const {registers.storage})) (i64.const 0)) (then unreachable))\n"
  | .requireLayout marker value =>
      s!"{indent}(if (i64.ne (call $pf_storage_read (i64.const {marker.length}) (i64.const {marker.offset}) (i64.const {registers.storage})) (i64.const 1)) (then unreachable))\n" ++
        s!"{indent}(if (i64.ne (call $pf_register_len (i64.const {registers.storage})) (i64.const 8)) (then unreachable))\n" ++
        s!"{indent}(call $pf_read_register (i64.const {registers.storage}) (i64.const {memory.valueOffset}))\n" ++
        s!"{indent}(if (i64.ne (i64.load (i32.const {memory.valueOffset})) (i64.const {value.toNat})) (then unreachable))\n"
  | .zeroState field =>
      renderZeroLe indent memory.valueOffset 8 ++
        s!"{indent}(if (i64.ne (call $pf_storage_write (i64.const {field.length}) (i64.const {field.offset}) (i64.const 8) (i64.const {memory.valueOffset}) (i64.const {registers.evicted})) (i64.const 0)) (then unreachable))\n"
  | .narrowZeroState bitWidth field =>
      let bw := bitWidth / 8
      renderZeroLe indent memory.valueOffset bw ++
        s!"{indent}(if (i64.ne (call $pf_storage_write (i64.const {field.length}) (i64.const {field.offset}) (i64.const {bw}) (i64.const {memory.valueOffset}) (i64.const {registers.evicted})) (i64.const 0)) (then unreachable))\n"
  | .literal destination value =>
      s!"{indent}(local.set $t{destination} (i64.const {value.toNat}))\n"
  | .blockTimestampSeconds destination =>
      -- B-CTX-OPEN: host block_timestamp (ns) → whole seconds (truncating div).
      s!"{indent}(local.set $t{destination} (i64.div_u (call $pf_block_timestamp) (i64.const 1000000000)))\n"
  | .accountBalance destination =>
      -- ADR-0030 E2-NEAR: host account_balance → u128 LE at depositOffset
      -- (shared 16-byte scratch with attached_deposit; not live simultaneously
      -- across a single expr eval). High 64 bits must be zero (UInt64 range
      -- guard, same discipline as EVM SELFBALANCE); low 64 bits are the result.
      s!"{indent}(call $pf_account_balance (i64.const {memory.depositOffset}))\n" ++
        s!"{indent}(if (i64.ne (i64.load (i32.const {memory.depositOffset + 8})) (i64.const 0)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.load (i32.const {memory.depositOffset})))\n"
  | .callerPrincipalLen destination =>
      -- ADR-0031 S1: predecessor_account_id → register 3 → length leaf.
      -- Canonical Principal wire = u32le(L)||account-id-utf8; leaf0 = L.
      -- Bound L ∈ 1..64 (pilot Principal body max; NEAR account-id ≤ 64).
      let predReg : Nat := 3
      s!"{indent}(call $pf_predecessor_account_id (i64.const {predReg}))\n" ++
        s!"{indent}(local.set $t{destination} (call $pf_register_len (i64.const {predReg})))\n" ++
        s!"{indent}(if (i64.lt_u (local.get $t{destination}) (i64.const 1)) (then unreachable))\n" ++
        s!"{indent}(if (i64.gt_u (local.get $t{destination}) (i64.const 64)) (then unreachable))\n"
  | .callerPrincipalWord destination wordIndex =>
      -- ADR-0031 S1: predecessor → zero-pad 64B body buffer → LE word.
      -- Scratch at valueOffset+16 (64 bytes); not live across other host ops
      -- in the same leaf eval. Unused tail bytes forced 0 so Principal leaf
      -- equality is length-exact (trailing pad must match).
      let predReg : Nat := 3
      let bodyBuf := memory.valueOffset + 16
      Id.run do
        let mut out :=
          s!"{indent}(call $pf_predecessor_account_id (i64.const {predReg}))\n" ++
          s!"{indent}(local.set $t_pf_i (call $pf_register_len (i64.const {predReg})))\n" ++
          s!"{indent}(if (i64.lt_u (local.get $t_pf_i) (i64.const 1)) (then unreachable))\n" ++
          s!"{indent}(if (i64.gt_u (local.get $t_pf_i) (i64.const 64)) (then unreachable))\n"
        -- Zero the full 64-byte body buffer before read_register (host only
        -- writes `len` bytes; pad must be 0 for Principal leaf identity).
        for j in [0:8] do
          out := out ++
            s!"{indent}(i64.store (i32.const {bodyBuf + 8 * j}) (i64.const 0))\n"
        out := out ++
          s!"{indent}(call $pf_read_register (i64.const {predReg}) (i64.const {bodyBuf}))\n" ++
          s!"{indent}(local.set $t{destination} (i64.load (i32.const {bodyBuf + 8 * wordIndex})))\n"
        pure out
  | .loadParam destination inputOffset =>
      s!"{indent}(local.set $t{destination} (i64.load (i32.const {memory.inputOffset + inputOffset})))\n"
  | .narrowLoadParam bitWidth destination inputOffset =>
      if bitWidth > 64 then
        Id.run do
          let nLimbs := limbCountOfBitWidth bitWidth
          let mut out := ""
          for i in [:nLimbs] do
            out := out ++
              s!"{indent}(local.set $t{destination + i} (i64.load (i32.const {memory.inputOffset + inputOffset + i * 8})))\n"
          pure out
      else
        renderLoadLeToI64 indent destination (memory.inputOffset + inputOffset) (bitWidth / 8)
  | .loadState destination field =>
      renderReadKey registers memory indent destination field 8
  | .narrowLoadState bitWidth destination field =>
      renderReadKey registers memory indent destination field (bitWidth / 8)
  | .checkedAdd destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.add (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.lt_u (local.get $t{destination}) (local.get $t{lhs})) (then unreachable))\n"
  | .checkedSub destination lhs rhs =>
      s!"{indent}(if (i64.lt_u (local.get $t{lhs}) (local.get $t{rhs})) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.sub (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .checkedMul destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.mul (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.ne (local.get $t{lhs}) (i64.const 0)) (then (if (i64.ne (i64.div_u (local.get $t{destination}) (local.get $t{lhs})) (local.get $t{rhs})) (then unreachable))))\n"
  | .checkedDiv destination lhs rhs =>
      s!"{indent}(if (i64.eqz (local.get $t{rhs})) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.div_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .checkedMod destination lhs rhs =>
      s!"{indent}(if (i64.eqz (local.get $t{rhs})) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.rem_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .signedCheckedAdd destination lhs rhs =>
      -- i64 add with signed overflow: ((a^r)&(b^r)) sign bit set.
      s!"{indent}(local.set $t{destination} (i64.add (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.lt_s (i64.and (i64.xor (local.get $t{lhs}) (local.get $t{destination})) (i64.xor (local.get $t{rhs}) (local.get $t{destination}))) (i64.const 0)) (then unreachable))\n"
  | .signedCheckedSub destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.sub (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.lt_s (i64.and (i64.xor (local.get $t{lhs}) (local.get $t{rhs})) (i64.xor (local.get $t{lhs}) (local.get $t{destination}))) (i64.const 0)) (then unreachable))\n"
  | .signedCheckedMul destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.mul (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.ne (local.get $t{lhs}) (i64.const 0)) (then (if (i64.ne (local.get $t{lhs}) (i64.const -1)) (then (if (i64.ne (i64.div_s (local.get $t{destination}) (local.get $t{lhs})) (local.get $t{rhs})) (then unreachable))))))\n"
  | .signedCheckedDiv destination lhs rhs =>
      s!"{indent}(if (i64.eqz (local.get $t{rhs})) (then unreachable))\n" ++
        s!"{indent}(if (i64.eq (local.get $t{lhs}) (i64.const -9223372036854775808)) (then (if (i64.eq (local.get $t{rhs}) (i64.const -1)) (then unreachable))))\n" ++
        s!"{indent}(local.set $t{destination} (i64.div_s (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .signedCheckedMod destination lhs rhs =>
      s!"{indent}(if (i64.eqz (local.get $t{rhs})) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.rem_s (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .signedCompare destination lhs rhs op =>
      let insn :=
        match op with
        | .eq => "i64.eq"
        | .ne => "i64.ne"
        | .lt => "i64.lt_s"
        | .le => "i64.le_s"
        | .gt => "i64.gt_s"
        | .ge => "i64.ge_s"
      s!"{indent}(local.set $t{destination} (i64.extend_i32_u ({insn} (local.get $t{lhs}) (local.get $t{rhs}))))\n"
  | .checkedNeg destination source =>
      s!"{indent}(if (i64.eq (local.get $t{source}) (i64.const -9223372036854775808)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.sub (i64.const 0) (local.get $t{source})))\n"
  | .sar destination lhs rhs =>
      s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const 64)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.shr_s (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .bitAnd destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.and (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .bitOr destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.or (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .bitXor destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.xor (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .shl destination lhs rhs =>
      -- Wasm i64.shl masks the count mod 64; guard count ≥ 64 first so the
      -- host trap matches the wire invalidShift semantics, then emit the
      -- shift and a round-trip overflow guard exact for k < 64.
      s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const 64)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.shl (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.ne (i64.shr_u (local.get $t{destination}) (local.get $t{rhs})) (local.get $t{lhs})) (then unreachable))\n"
  | .shr destination lhs rhs =>
      s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const 64)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.shr_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .bitNot destination source =>
      s!"{indent}(local.set $t{destination} (i64.xor (local.get $t{source}) (i64.const -1)))\n"
  | .narrowCheckedAdd bitWidth destination lhs rhs =>
      if bitWidth > 64 then
        -- Multiword (UInt128/256): limb-wise checked add with final carry trap.
        renderMultiwordCheckedAdd indent destination lhs rhs (limbCountOfBitWidth bitWidth)
      else
        -- i64.add then high bits above bitWidth must be zero.
        s!"{indent}(local.set $t{destination} (i64.add (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
          s!"{indent}(if (i64.ne (i64.shr_u (local.get $t{destination}) (i64.const {bitWidth})) (i64.const 0)) (then unreachable))\n"
  | .narrowCheckedSub bitWidth destination lhs rhs =>
      if bitWidth > 64 then
        -- Multiword (UInt128/256): limb-wise checked sub with final borrow trap.
        renderMultiwordCheckedSub indent destination lhs rhs (limbCountOfBitWidth bitWidth)
      else
        -- Underflow guard identical to UInt64; result auto in-range for UInt.
        s!"{indent}(if (i64.lt_u (local.get $t{lhs}) (local.get $t{rhs})) (then unreachable))\n" ++
          s!"{indent}(local.set $t{destination} (i64.sub (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .narrowCheckedMul bitWidth destination lhs rhs =>
      if bitWidth > 64 then
        -- Multiword (UInt128/256): exact base-2^32 schoolbook product.
        renderMultiwordCheckedMul indent destination lhs rhs (limbCountOfBitWidth bitWidth)
      else
        s!"{indent}(local.set $t{destination} (i64.mul (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
          s!"{indent}(if (i64.ne (i64.shr_u (local.get $t{destination}) (i64.const {bitWidth})) (i64.const 0)) (then unreachable))\n"
  | .narrowCheckedDiv bitWidth destination lhs rhs =>
      if bitWidth > 64 then
        -- Defensive trap only: wide div/mod fail closed at the NEAR Plan
        -- lowering (multiword division is not implemented in this slice).
        s!"{indent};; wide div/mod fail closed at lowering (defensive trap)\n{indent}(unreachable)\n"
      else
        s!"{indent}(if (i64.eqz (local.get $t{rhs})) (then unreachable))\n" ++
          s!"{indent}(local.set $t{destination} (i64.div_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .narrowCheckedMod bitWidth destination lhs rhs =>
      if bitWidth > 64 then
        -- Defensive trap only: wide div/mod fail closed at the NEAR Plan
        -- lowering (multiword division is not implemented in this slice).
        s!"{indent};; wide div/mod fail closed at lowering (defensive trap)\n{indent}(unreachable)\n"
      else
        s!"{indent}(if (i64.eqz (local.get $t{rhs})) (then unreachable))\n" ++
          s!"{indent}(local.set $t{destination} (i64.rem_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .narrowBitAnd bitWidth destination lhs rhs =>
      if bitWidth > 64 then
        Id.run do
          let nLimbs := limbCountOfBitWidth bitWidth
          let mut out := s!"{indent};; multiword bit_and nLimbs={nLimbs}\n"
          for i in [:nLimbs] do
            out := out ++ s!"{indent}(local.set $t{destination + i} (i64.and (local.get $t{lhs + i}) (local.get $t{rhs + i})))\n"
          pure out
      else
        s!"{indent}(local.set $t{destination} (i64.and (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .narrowBitOr bitWidth destination lhs rhs =>
      if bitWidth > 64 then
        Id.run do
          let nLimbs := limbCountOfBitWidth bitWidth
          let mut out := s!"{indent};; multiword bit_or nLimbs={nLimbs}\n"
          for i in [:nLimbs] do
            out := out ++ s!"{indent}(local.set $t{destination + i} (i64.or (local.get $t{lhs + i}) (local.get $t{rhs + i})))\n"
          pure out
      else
        s!"{indent}(local.set $t{destination} (i64.or (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .narrowBitXor bitWidth destination lhs rhs =>
      if bitWidth > 64 then
        Id.run do
          let nLimbs := limbCountOfBitWidth bitWidth
          let mut out := s!"{indent};; multiword bit_xor nLimbs={nLimbs}\n"
          for i in [:nLimbs] do
            out := out ++ s!"{indent}(local.set $t{destination + i} (i64.xor (local.get $t{lhs + i}) (local.get $t{rhs + i})))\n"
          pure out
      else
        s!"{indent}(local.set $t{destination} (i64.xor (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .narrowBitNot bitWidth destination source =>
      let mask :=
        match bitWidth with
        | 8 => "255"
        | 16 => "65535"
        | 32 => "4294967295"
        | _ => "18446744073709551615"
      if bitWidth > 64 then
        Id.run do
          let nLimbs := limbCountOfBitWidth bitWidth
          let mut out := s!"{indent};; multiword bit_not nLimbs={nLimbs}\n"
          for i in [:nLimbs] do
            out := out ++ s!"{indent}(local.set $t{destination + i} (i64.xor (local.get $t{source + i}) (i64.const -1)))\n"
          pure out
      else
        s!"{indent}(local.set $t{destination} (i64.and (i64.xor (local.get $t{source}) (i64.const -1)) (i64.const {mask})))\n"
  | .narrowShl bitWidth destination lhs rhs =>
      if bitWidth > 64 then
        -- Defensive trap only: wide shifts fail closed at the NEAR Plan
        -- lowering (cross-limb shift is not implemented in this slice).
        s!"{indent};; wide shift fail closed at lowering (defensive trap)\n{indent}(unreachable)\n"
      else
        -- Count ≥ 64 trap; shl; high bits above bitWidth must be 0.
        s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const 64)) (then unreachable))\n" ++
          s!"{indent}(local.set $t{destination} (i64.shl (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
          s!"{indent}(if (i64.ne (i64.shr_u (local.get $t{destination}) (i64.const {bitWidth})) (i64.const 0)) (then unreachable))\n"
  | .narrowShr bitWidth destination lhs rhs =>
      if bitWidth > 64 then
        -- Defensive trap only: wide shifts fail closed at the NEAR Plan
        -- lowering (cross-limb shift is not implemented in this slice).
        s!"{indent};; wide shift fail closed at lowering (defensive trap)\n{indent}(unreachable)\n"
      else
        s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const 64)) (then unreachable))\n" ++
          s!"{indent}(local.set $t{destination} (i64.shr_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .boolNot destination source =>
      s!"{indent}(local.set $t{destination} (i64.extend_i32_u (i64.eqz (local.get $t{source}))))\n"
  | .boolAnd destination lhs rhs =>
      -- Bitwise == logical on 0/1 Bool words; both sides already evaluated.
      s!"{indent}(local.set $t{destination} (i64.and (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .boolOr destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.or (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .compare destination lhs rhs op =>
      let insn :=
        match op with
        | .eq => "i64.eq"
        | .ne => "i64.ne"
        | .lt => "i64.lt_u"
        | .le => "i64.le_u"
        | .gt => "i64.gt_u"
        | .ge => "i64.ge_u"
      s!"{indent}(local.set $t{destination} (i64.extend_i32_u ({insn} (local.get $t{lhs}) (local.get $t{rhs}))))\n"
  | .wideCompare bitWidth destination lhs rhs op =>
      let nLimbs := limbCountOfBitWidth bitWidth
      match op with
      | .eq =>
          Id.run do
            let mut out := s!"{indent}(local.set $t{destination} (i64.const 1))
"
            for k in [:nLimbs] do
              out := out ++
                s!"{indent}(local.set $t{destination} (i64.and (local.get $t{destination}) (i64.extend_i32_u (i64.eq (local.get $t{lhs + k}) (local.get $t{rhs + k})))))
"
            pure out
      | .ne =>
          Id.run do
            let mut out := s!"{indent}(local.set $t{destination} (i64.const 0))
"
            for k in [:nLimbs] do
              out := out ++
                s!"{indent}(local.set $t{destination} (i64.or (local.get $t{destination}) (i64.extend_i32_u (i64.ne (local.get $t{lhs + k}) (local.get $t{rhs + k})))))
"
            pure out
      | .lt | .le | .gt | .ge =>
          Id.run do
            let mut out := s!"{indent}(local.set $t_mw_carry (i64.const 0))
"
            let eqDef := match op with | .le | .ge => 1 | _ => 0
            out := out ++ s!"{indent}(local.set $t{destination} (i64.const {eqDef}))
"
            for j in [:nLimbs] do
              let k := nLimbs - 1 - j
              let insn :=
                match op with
                | .lt => "i64.lt_u" | .le => "i64.lt_u"
                | .gt => "i64.gt_u" | .ge => "i64.gt_u" | _ => "i64.eq"
              -- For le/ge: on inequality use strict lt/gt; equal limbs continue
              out := out ++
                s!"{indent}(if (i64.eqz (local.get $t_mw_carry))
" ++
                s!"{indent}  (then
" ++
                s!"{indent}    (if (i64.ne (local.get $t{lhs + k}) (local.get $t{rhs + k}))
" ++
                s!"{indent}      (then
" ++
                s!"{indent}        (local.set $t{destination} (i64.extend_i32_u ({insn} (local.get $t{lhs + k}) (local.get $t{rhs + k}))))
" ++
                s!"{indent}        (local.set $t_mw_carry (i64.const 1)))
" ++
                s!"{indent}      (else)))
" ++
                s!"{indent}  (else))
"
            pure out

  | .assert condition =>
      s!"{indent}(if (i64.eqz (local.get $t{condition})) (then unreachable))\n"
  | .returnNone =>
      s!"{indent}(return)\n"
  | .emitEvent eventIndex args =>
      renderInterfaceMessage registers memory indent "event" "pf_log_utf8"
        events errors true eventIndex args
  | .promiseAccount receiver method args =>
      -- Account id / method come from module `(data ...)` segments (literal
      -- strings in the WAT). Args are a deterministic u64-LE payload written
      -- into the interface-message scratch (each arg 8-byte LE via i64.store,
      -- source order). Deposit u128=(0,0) and gas=0 are explicit zero
      -- placeholders — not economics. Fire-and-forget: promise failure never
      -- propagates to the caller.
      Id.run do
        let _ := registers
        let _ := events
        let _ := errors
        let _ := fnNames
        let accountOffset := promiseStringOffset promiseStr receiver
        let methodOffset := promiseStringOffset promiseStr method
        let accountLen := receiver.toUTF8.size
        let methodLen := method.toUTF8.size
        let argsOffset := messageOffset memory
        let mut output := ""
        for j in [0:args.size] do
          output := output ++
            s!"{indent}(i64.store (i32.const {argsOffset + 8 * j}) (local.get $t{args[j]!}))\n"
        let argsLen := 8 * args.size
        -- Zero deposit u128 at valueOffset (scratch, transient).
        let depositPtr := memory.valueOffset
        output := output ++
          s!"{indent}(i64.store (i32.const {depositPtr}) (i64.const 0))\n" ++
          s!"{indent}(i64.store (i32.const {depositPtr + 8}) (i64.const 0))\n"
        pure <| output ++
          s!"{indent}(call $pf_promise_batch_action_function_call\n" ++
          s!"{indent}  (call $pf_promise_batch_create (i64.const {accountLen}) (i64.const {accountOffset}))\n" ++
          s!"{indent}  (i64.const {methodLen}) (i64.const {methodOffset})\n" ++
          s!"{indent}  (i64.const {argsLen}) (i64.const {argsOffset})\n" ++
          s!"{indent}  (i64.const {depositPtr}) (i64.const 0))\n"
  | .promiseTransfer dstLen dstWords amount =>
      -- ADR-0029 C2: Principal leaves → account-id buffer + Transfer promise.
      -- Scratch layout (transient, after valueOffset):
      --   accountBuf = valueOffset + 16  (64 bytes of body words)
      --   amountU128 = valueOffset + 80  (16 bytes: amount lo, 0 hi)
      -- Runtime gates: len ∈ 2..64, account-id grammar, trailing body words
      -- zero-padded beyond ceil(len/8). Fire-and-forget: no response cursor.
      Id.run do
        let _ := registers
        let _ := events
        let _ := errors
        let _ := fnNames
        let _ := promiseStr
        let accountBuf := memory.valueOffset + 16
        let amountPtr := memory.valueOffset + 80
        let mut out := ""
        -- Materialize body words into a contiguous 64-byte buffer.
        for j in [0:dstWords.size] do
          out := out ++
            s!"{indent}(i64.store (i32.const {accountBuf + 8 * j}) (local.get $t{dstWords[j]!}))\n"
        -- len ∈ [2, 64]
        out := out ++
          s!"{indent}(if (i64.lt_u (local.get $t{dstLen}) (i64.const 2)) (then unreachable))\n" ++
          s!"{indent}(if (i64.gt_u (local.get $t{dstLen}) (i64.const 64)) (then unreachable))\n"
        -- Account-id grammar scan (a-z | 0-9 | _ | - | .); first/last != '.'.
        -- Uses method-local $t_pf_i / $t_pf_b declared when transfer ops present.
        out := out ++
          s!"{indent}(local.set $t_pf_i (i64.const 0))\n" ++
          s!"{indent}(block $pf_acc_done\n" ++
          s!"{indent}  (loop $pf_acc_check\n" ++
          s!"{indent}    (br_if $pf_acc_done (i64.ge_u (local.get $t_pf_i) (local.get $t{dstLen})))\n" ++
          s!"{indent}    (local.set $t_pf_b (i64.load8_u (i32.add (i32.const {accountBuf}) (i32.wrap_i64 (local.get $t_pf_i)))))\n" ++
          -- valid = (a-z) | (0-9) | '_' | '-' | '.'
          -- Wasm comparisons yield i32; boolean combine must stay i32.
          s!"{indent}    (if (i32.eqz (i32.or (i32.or (i32.or\n" ++
          s!"{indent}      (i32.and (i64.ge_u (local.get $t_pf_b) (i64.const 97)) (i64.le_u (local.get $t_pf_b) (i64.const 122)))\n" ++
          s!"{indent}      (i32.and (i64.ge_u (local.get $t_pf_b) (i64.const 48)) (i64.le_u (local.get $t_pf_b) (i64.const 57))))\n" ++
          s!"{indent}      (i64.eq (local.get $t_pf_b) (i64.const 95)))\n" ++
          s!"{indent}      (i32.or (i64.eq (local.get $t_pf_b) (i64.const 45)) (i64.eq (local.get $t_pf_b) (i64.const 46)))))\n" ++
          s!"{indent}      (then unreachable))\n" ++
          s!"{indent}    (local.set $t_pf_i (i64.add (local.get $t_pf_i) (i64.const 1)))\n" ++
          s!"{indent}    (br $pf_acc_check)\n" ++
          s!"{indent}  )\n" ++
          s!"{indent})\n"
        -- First / last byte must not be '.'
        out := out ++
          s!"{indent}(if (i64.eq (i64.load8_u (i32.const {accountBuf})) (i64.const 46)) (then unreachable))\n" ++
          s!"{indent}(if (i64.eq (i64.load8_u (i32.add (i32.const {accountBuf}) (i32.wrap_i64 (i64.sub (local.get $t{dstLen}) (i64.const 1))))) (i64.const 46)) (then unreachable))\n"
        -- Amount as u128 LE at amountPtr (hi word forced 0).
        out := out ++
          s!"{indent}(i64.store (i32.const {amountPtr}) (local.get $t{amount}))\n" ++
          s!"{indent}(i64.store (i32.const {amountPtr + 8}) (i64.const 0))\n"
        -- Fire-and-forget Transfer promise.
        pure <| out ++
          s!"{indent}(call $pf_promise_batch_action_transfer\n" ++
          s!"{indent}  (call $pf_promise_batch_create (local.get $t{dstLen}) (i64.const {accountBuf}))\n" ++
          s!"{indent}  (i64.const {amountPtr}))\n"
  | .promiseTokenTransfer mintLen mintWords dstLen dstWords amount =>
      -- ADR-0030 E1-NEAR: NEP-141 ft_transfer cross-contract Promise.
      -- Scratch layout (transient, after valueOffset):
      --   mintBuf   = valueOffset + 16   (64 bytes of mint body words)
      --   dstBuf    = valueOffset + 80   (64 bytes of dst body words)
      --   jsonBuf   = valueOffset + 144  (JSON args, ~130 bytes max)
      --   decBuf    = valueOffset + 280  (20 bytes decimal digits, MSB-first)
      -- Runtime gates: mint/dst len ∈ 2..64, account-id grammar for both,
      -- trailing body words zero-padded beyond ceil(len/8).
      -- JSON: {"receiver_id":"<dst>","amount":"<decimal>"}
      -- Deposit = 1 yoctoNEAR (u128 lo=1, hi=0). Gas = frozen constant.
      -- Fire-and-forget: no response cursor.
      Id.run do
        let _ := registers
        let _ := events
        let _ := errors
        let _ := fnNames
        let _ := promiseStr
        let mintBuf := memory.valueOffset + 16
        let dstBuf := memory.valueOffset + 80
        let jsonBuf := memory.valueOffset + 144
        let decBuf := memory.valueOffset + 280
        let gasVal := PfAssetsCatalogV1.tokenTransferGasV1
        let methodOffset := promiseStringOffset promiseStr "ft_transfer"
        let methodLen := "ft_transfer".toUTF8.size
        let mut out := ""
        -- Materialize mint body words into mintBuf (64 bytes).
        for j in [0:mintWords.size] do
          out := out ++
            s!"{indent}(i64.store (i32.const {mintBuf + 8 * j}) (local.get $t{mintWords[j]!}))\n"
        -- mint len ∈ [2, 64]
        out := out ++
          s!"{indent}(if (i64.lt_u (local.get $t{mintLen}) (i64.const 2)) (then unreachable))\n" ++
          s!"{indent}(if (i64.gt_u (local.get $t{mintLen}) (i64.const 64)) (then unreachable))\n"
        -- mint account-id grammar scan.
        out := out ++
          s!"{indent}(local.set $t_pf_i (i64.const 0))\n" ++
          s!"{indent}(block $pf_mint_done\n" ++
          s!"{indent}  (loop $pf_mint_check\n" ++
          s!"{indent}    (br_if $pf_mint_done (i64.ge_u (local.get $t_pf_i) (local.get $t{mintLen})))\n" ++
          s!"{indent}    (local.set $t_pf_b (i64.load8_u (i32.add (i32.const {mintBuf}) (i32.wrap_i64 (local.get $t_pf_i)))))\n" ++
          s!"{indent}    (if (i32.eqz (i32.or (i32.or (i32.or\n" ++
          s!"{indent}      (i32.and (i64.ge_u (local.get $t_pf_b) (i64.const 97)) (i64.le_u (local.get $t_pf_b) (i64.const 122)))\n" ++
          s!"{indent}      (i32.and (i64.ge_u (local.get $t_pf_b) (i64.const 48)) (i64.le_u (local.get $t_pf_b) (i64.const 57))))\n" ++
          s!"{indent}      (i64.eq (local.get $t_pf_b) (i64.const 95)))\n" ++
          s!"{indent}      (i32.or (i64.eq (local.get $t_pf_b) (i64.const 45)) (i64.eq (local.get $t_pf_b) (i64.const 46)))))\n" ++
          s!"{indent}      (then unreachable))\n" ++
          s!"{indent}    (local.set $t_pf_i (i64.add (local.get $t_pf_i) (i64.const 1)))\n" ++
          s!"{indent}    (br $pf_mint_check)\n" ++
          s!"{indent}  )\n" ++
          s!"{indent})\n"
        -- mint first / last byte must not be '.'
        out := out ++
          s!"{indent}(if (i64.eq (i64.load8_u (i32.const {mintBuf})) (i64.const 46)) (then unreachable))\n" ++
          s!"{indent}(if (i64.eq (i64.load8_u (i32.add (i32.const {mintBuf}) (i32.wrap_i64 (i64.sub (local.get $t{mintLen}) (i64.const 1))))) (i64.const 46)) (then unreachable))\n"
        -- Materialize dst body words into dstBuf (64 bytes).
        for j in [0:dstWords.size] do
          out := out ++
            s!"{indent}(i64.store (i32.const {dstBuf + 8 * j}) (local.get $t{dstWords[j]!}))\n"
        -- dst len ∈ [2, 64]
        out := out ++
          s!"{indent}(if (i64.lt_u (local.get $t{dstLen}) (i64.const 2)) (then unreachable))\n" ++
          s!"{indent}(if (i64.gt_u (local.get $t{dstLen}) (i64.const 64)) (then unreachable))\n"
        -- dst account-id grammar scan.
        out := out ++
          s!"{indent}(local.set $t_pf_i (i64.const 0))\n" ++
          s!"{indent}(block $pf_dst_done\n" ++
          s!"{indent}  (loop $pf_dst_check\n" ++
          s!"{indent}    (br_if $pf_dst_done (i64.ge_u (local.get $t_pf_i) (local.get $t{dstLen})))\n" ++
          s!"{indent}    (local.set $t_pf_b (i64.load8_u (i32.add (i32.const {dstBuf}) (i32.wrap_i64 (local.get $t_pf_i)))))\n" ++
          s!"{indent}    (if (i32.eqz (i32.or (i32.or (i32.or\n" ++
          s!"{indent}      (i32.and (i64.ge_u (local.get $t_pf_b) (i64.const 97)) (i64.le_u (local.get $t_pf_b) (i64.const 122)))\n" ++
          s!"{indent}      (i32.and (i64.ge_u (local.get $t_pf_b) (i64.const 48)) (i64.le_u (local.get $t_pf_b) (i64.const 57))))\n" ++
          s!"{indent}      (i64.eq (local.get $t_pf_b) (i64.const 95)))\n" ++
          s!"{indent}      (i32.or (i64.eq (local.get $t_pf_b) (i64.const 45)) (i64.eq (local.get $t_pf_b) (i64.const 46)))))\n" ++
          s!"{indent}      (then unreachable))\n" ++
          s!"{indent}    (local.set $t_pf_i (i64.add (local.get $t_pf_i) (i64.const 1)))\n" ++
          s!"{indent}    (br $pf_dst_check)\n" ++
          s!"{indent}  )\n" ++
          s!"{indent})\n"
        -- dst first / last byte must not be '.'
        out := out ++
          s!"{indent}(if (i64.eq (i64.load8_u (i32.const {dstBuf})) (i64.const 46)) (then unreachable))\n" ++
          s!"{indent}(if (i64.eq (i64.load8_u (i32.add (i32.const {dstBuf}) (i32.wrap_i64 (i64.sub (local.get $t{dstLen}) (i64.const 1))))) (i64.const 46)) (then unreachable))\n"
        -- Build JSON args: {"receiver_id":"<dst>","amount":"<decimal>"}
        -- Write prefix: {"receiver_id":"
        let jsonPrefix := "{\"receiver_id\":\""
        let prefixBytes := jsonPrefix.toUTF8
        for i in [0:prefixBytes.size] do
          out := out ++
            s!"{indent}(i32.store8 (i32.const {jsonBuf + i}) (i32.const {prefixBytes[i]!.toNat}))\n"
        -- Copy dst account-id bytes from dstBuf to jsonBuf + prefixBytes.size
        out := out ++
          s!"{indent}(local.set $t_pf_j (i64.const {prefixBytes.size}))\n" ++
          s!"{indent}(local.set $t_pf_i (i64.const 0))\n" ++
          s!"{indent}(block $pf_json_dst_done\n" ++
          s!"{indent}  (loop $pf_json_dst_copy\n" ++
          s!"{indent}    (br_if $pf_json_dst_done (i64.ge_u (local.get $t_pf_i) (local.get $t{dstLen})))\n" ++
          s!"{indent}    (i32.store8 (i32.add (i32.const {jsonBuf}) (i32.wrap_i64 (local.get $t_pf_j)))\n" ++
          s!"{indent}      (i32.wrap_i64 (i64.load8_u (i32.add (i32.const {dstBuf}) (i32.wrap_i64 (local.get $t_pf_i))))))\n" ++
          s!"{indent}    (local.set $t_pf_j (i64.add (local.get $t_pf_j) (i64.const 1)))\n" ++
          s!"{indent}    (local.set $t_pf_i (i64.add (local.get $t_pf_i) (i64.const 1)))\n" ++
          s!"{indent}    (br $pf_json_dst_copy)\n" ++
          s!"{indent}  )\n" ++
          s!"{indent})\n"
        -- Write middle: ","amount":""
        let mid := "\",\"amount\":\""
        let midBytes := mid.toUTF8
        for i in [0:midBytes.size] do
          out := out ++
            s!"{indent}(i32.store8 (i32.add (i32.const {jsonBuf}) (i32.wrap_i64 (local.get $t_pf_j))) (i32.const {midBytes[i]!.toNat}))\n" ++
            s!"{indent}(local.set $t_pf_j (i64.add (local.get $t_pf_j) (i64.const 1)))\n"
        -- Decimal conversion: write digits MSB-first into decBuf from the end.
        -- $t_pf_n = remaining value, $t_pf_k = digit count (from end of decBuf).
        out := out ++
          s!"{indent}(local.set $t_pf_n (local.get $t{amount}))\n" ++
          s!"{indent}(local.set $t_pf_k (i64.const 0))\n" ++
          s!"{indent}(block $pf_dec_done\n" ++
          s!"{indent}  (loop $pf_dec_loop\n" ++
          s!"{indent}    (br_if $pf_dec_done (i64.eqz (local.get $t_pf_n)))\n" ++
          s!"{indent}    (local.set $t_pf_d (i64.rem_u (local.get $t_pf_n) (i64.const 10)))\n" ++
          s!"{indent}    (i32.store8 (i32.sub (i32.const {decBuf + 20}) (i32.wrap_i64 (local.get $t_pf_k)))\n" ++
          s!"{indent}      (i32.add (i32.wrap_i64 (local.get $t_pf_d)) (i32.const 48)))\n" ++
          s!"{indent}    (local.set $t_pf_k (i64.add (local.get $t_pf_k) (i64.const 1)))\n" ++
          s!"{indent}    (local.set $t_pf_n (i64.div_u (local.get $t_pf_n) (i64.const 10)))\n" ++
          s!"{indent}    (br $pf_dec_loop)\n" ++
          s!"{indent}  )\n" ++
          s!"{indent})\n"
        -- Special case: amount == 0 → write '0' (1 digit)
        out := out ++
          s!"{indent}(if (i64.eqz (local.get $t_pf_k)) (then\n" ++
          s!"{indent}  (i32.store8 (i32.const {decBuf + 19}) (i32.const 48))\n" ++
          s!"{indent}  (local.set $t_pf_k (i64.const 1))))\n"
        -- Copy decimal digits from decBuf+(20-k) to jsonBuf at $t_pf_j
        out := out ++
          s!"{indent}(local.set $t_pf_i (i64.const 0))\n" ++
          s!"{indent}(block $pf_dec_copy_done\n" ++
          s!"{indent}  (loop $pf_dec_copy\n" ++
          s!"{indent}    (br_if $pf_dec_copy_done (i64.ge_u (local.get $t_pf_i) (local.get $t_pf_k)))\n" ++
          s!"{indent}    (i32.store8 (i32.add (i32.const {jsonBuf}) (i32.wrap_i64 (local.get $t_pf_j)))\n" ++
          s!"{indent}      (i32.wrap_i64 (i64.load8_u (i32.add (i32.sub (i32.const {decBuf + 20}) (i32.wrap_i64 (local.get $t_pf_k))) (i32.wrap_i64 (local.get $t_pf_i))))))\n" ++
          s!"{indent}    (local.set $t_pf_j (i64.add (local.get $t_pf_j) (i64.const 1)))\n" ++
          s!"{indent}    (local.set $t_pf_i (i64.add (local.get $t_pf_i) (i64.const 1)))\n" ++
          s!"{indent}    (br $pf_dec_copy)\n" ++
          s!"{indent}  )\n" ++
          s!"{indent})\n"
        -- Write suffix: "}"
        out := out ++
          s!"{indent}(i32.store8 (i32.add (i32.const {jsonBuf}) (i32.wrap_i64 (local.get $t_pf_j))) (i32.const 125))\n" ++
          s!"{indent}(local.set $t_pf_j (i64.add (local.get $t_pf_j) (i64.const 1)))\n"
        -- Fire-and-forget NEP-141 ft_transfer function-call promise.
        -- promise_batch_action_function_call(promise_idx, method_len, method_ptr,
        --   args_len, args_ptr, amount_ptr (u128 LE), gas)
        -- deposit = 1 yoctoNEAR (u128 LE: lo=1, hi=0) at valueOffset scratch.
        let depositPtr := memory.valueOffset
        out := out ++
          s!"{indent}(i64.store (i32.const {depositPtr}) (i64.const 1))\n" ++
          s!"{indent}(i64.store (i32.const {depositPtr + 8}) (i64.const 0))\n"
        pure <| out ++
          s!"{indent}(call $pf_promise_batch_action_function_call\n" ++
          s!"{indent}  (call $pf_promise_batch_create (local.get $t{mintLen}) (i64.const {mintBuf}))\n" ++
          s!"{indent}  (i64.const {methodLen}) (i64.const {methodOffset})\n" ++
          s!"{indent}  (local.get $t_pf_j) (i64.const {jsonBuf})\n" ++
          s!"{indent}  (i64.const {depositPtr}) (i64.const {gasVal}))\n"
  | .revertError errorIndex args =>
      renderInterfaceMessage registers memory indent "error" "pf_panic_utf8"
        events errors false errorIndex args
  | .storeState field value =>
      s!"{indent}(i64.store (i32.const {memory.valueOffset}) (local.get $t{value}))\n" ++
        s!"{indent}(if (i64.ne (call $pf_storage_write (i64.const {field.length}) (i64.const {field.offset}) (i64.const 8) (i64.const {memory.valueOffset}) (i64.const {registers.evicted})) (i64.const 1)) (then unreachable))\n" ++
        s!"{indent}(if (i64.ne (call $pf_register_len (i64.const {registers.evicted})) (i64.const 8)) (then unreachable))\n"
  | .narrowStoreState bitWidth field value =>
      let bw := bitWidth / 8
      if bitWidth > 64 then
        Id.run do
          let nLimbs := limbCountOfBitWidth bitWidth
          let mut out := ""
          for i in [:nLimbs] do
            out := out ++
              s!"{indent}(i64.store (i32.const {memory.valueOffset + i * 8}) (local.get $t{value + i}))
"
          out := out ++
            s!"{indent}(if (i64.ne (call $pf_storage_write (i64.const {field.length}) (i64.const {field.offset}) (i64.const {bw}) (i64.const {memory.valueOffset}) (i64.const {registers.evicted})) (i64.const 1)) (then unreachable))
" ++
            s!"{indent}(if (i64.ne (call $pf_register_len (i64.const {registers.evicted})) (i64.const {bw})) (then unreachable))
"
          pure out
      else
        renderStoreI64Le indent memory.valueOffset value bw ++
          s!"{indent}(if (i64.ne (call $pf_storage_write (i64.const {field.length}) (i64.const {field.offset}) (i64.const {bw}) (i64.const {memory.valueOffset}) (i64.const {registers.evicted})) (i64.const 1)) (then unreachable))
" ++
          s!"{indent}(if (i64.ne (call $pf_register_len (i64.const {registers.evicted})) (i64.const {bw})) (then unreachable))
"

  | .setLayout marker value =>
      s!"{indent}(i64.store (i32.const {memory.valueOffset}) (i64.const {value.toNat}))\n" ++
        s!"{indent}(if (i64.ne (call $pf_storage_write (i64.const {marker.length}) (i64.const {marker.offset}) (i64.const 8) (i64.const {memory.valueOffset}) (i64.const {registers.evicted})) (i64.const 0)) (then unreachable))\n"
  | .setReturnData byteLen value =>
      if byteLen > 8 then
        Id.run do
          let nLimbs := byteLen / 8
          let mut out := ""
          for i in [:nLimbs] do
            out := out ++
              s!"{indent}(i64.store (i32.const {memory.valueOffset + i * 8}) (local.get $t{value + i}))
"
          out := out ++
            s!"{indent}(call $pf_value_return (i64.const {byteLen}) (i64.const {memory.valueOffset}))
"
          pure out
      else
        s!"{indent}(i64.store (i32.const {memory.valueOffset}) (local.get $t{value}))
" ++
          s!"{indent}(call $pf_value_return (i64.const {byteLen}) (i64.const {memory.valueOffset}))
"

  | .setReturnDataLeaves temps =>
      Id.run do
        let byteLen := 8 * temps.size
        let mut out := ""
        for i in [:temps.size] do
          let t := temps[i]!
          out := out ++
            s!"{indent}(i64.store (i32.const {memory.valueOffset + i * 8}) (local.get $t{t}))
"
        out := out ++
          s!"{indent}(call $pf_value_return (i64.const {byteLen}) (i64.const {memory.valueOffset}))
"
        pure out

  | .callFn fnIndex destination args =>
      let name := match fnNames[fnIndex]? with
        | some n => n
        | none => "unknown"
      let argGets := String.intercalate " " <| args.toList.map fun a =>
        s!"(local.get $t{a})"
      let callArgs := if args.isEmpty then "" else " " ++ argGets
      s!"{indent}(local.set $t{destination} (call $fn_{name}{callArgs}))\n"
  | .returnValue value =>
      s!"{indent}(return (local.get $t{value}))\n"
  | .ifRegion condition thenOps elseOps =>
      let thenText := thenOps.foldl (fun output operation =>
        output ++ renderOperation registers memory events errors fnNames promiseStr
          (indent ++ "  ") operation) ""
      let elseText := elseOps.foldl (fun output operation =>
        output ++ renderOperation registers memory events errors fnNames promiseStr
          (indent ++ "  ") operation) ""
      -- wat2wasm rejects empty `(then)` / `(else)` blocks.
      let thenBody := if thenText.isEmpty then s!"{indent}    nop\n" else thenText
      let elseClause :=
        if elseOps.isEmpty then ""
        else
          let elseBody := if elseText.isEmpty then s!"{indent}    nop\n" else elseText
          s!"{indent}  (else\n" ++ elseBody ++ s!"{indent}  )\n"
      s!"{indent}(if (local.get $t{condition})\n{indent}  (then\n" ++ thenBody ++
        s!"{indent}  )\n" ++ elseClause ++
        s!"{indent})\n"
  | .forRegion varTemp initial counterTemp maxIterations
        condOps condition bodyOps updateOps updateValue =>
      -- Canonical Wasm loop. Labels are deterministic from the induction temp
      -- index. Bound check sits at the back edge after the body (reference
      -- noteBackEdge): bodies 1..N pass; the (N+1)-th body runs then traps.
      -- A body return exits before the check. The latch `i := i+1` is
      -- unguarded: Normalize only runs the body while `i < end ≤ UInt64.max`.
      let inner := indent ++ "  "
      let deeper := indent ++ "    "
      let condText := condOps.foldl (fun output operation =>
        output ++ renderOperation registers memory events errors fnNames promiseStr
          deeper operation) ""
      let bodyText := bodyOps.foldl (fun output operation =>
        output ++ renderOperation registers memory events errors fnNames promiseStr
          deeper operation) ""
      let updateText := updateOps.foldl (fun output operation =>
        output ++ renderOperation registers memory events errors fnNames promiseStr
          deeper operation) ""
      s!"{indent}(local.set $t{varTemp} (local.get $t{initial}))\n" ++
        s!"{indent}(local.set $t{counterTemp} (i64.const 0))\n" ++
        s!"{indent}(block $pf_exit{varTemp}\n" ++
        s!"{inner}(loop $pf_loop{varTemp}\n" ++
        condText ++
        s!"{deeper}(br_if $pf_exit{varTemp} (i64.eqz (local.get $t{condition})))\n" ++
        bodyText ++
        s!"{deeper}(if (i64.ge_u (local.get $t{counterTemp}) (i64.const {maxIterations})) (then unreachable))\n" ++
        s!"{deeper}(local.set $t{counterTemp} (i64.add (local.get $t{counterTemp}) (i64.const 1)))\n" ++
        updateText ++
        s!"{deeper}(local.set $t{varTemp} (local.get $t{updateValue}))\n" ++
        s!"{deeper}(br $pf_loop{varTemp})\n" ++
        s!"{inner})\n" ++
        s!"{indent})\n"
  | .switchRegion scrutinee cases defaultOps =>
      -- Right-nested if/else chain: first matching case wins, else default.
      -- The terminal else branch is plain instructions (not a bare `(then …)`),
      -- which is invalid WAT (`expected an instr` at nested `(else (then …))`).
      let rec renderCases (indent : String) (remaining : Array (UInt64 × Array Operation)) : String :=
        match remaining.toList with
        | [] =>
            defaultOps.foldl (fun output operation =>
              output ++ renderOperation registers memory events errors fnNames promiseStr
                indent operation) ""
        | (caseValue, caseOps) :: rest =>
            let caseText := caseOps.foldl (fun output operation =>
              output ++ renderOperation registers memory events errors fnNames promiseStr
                (indent ++ "  ") operation) ""
            let elseText := renderCases (indent ++ "  ") rest.toArray
            -- Empty else still needs an instruction for wat2wasm.
            let elseBody := if elseText.isEmpty then s!"{indent}  nop\n" else elseText
            s!"{indent}(if (i64.eq (local.get $t{scrutinee}) (i64.const {caseValue.toNat}))\n" ++
              s!"{indent}  (then\n" ++
              (if caseText.isEmpty then s!"{indent}    nop\n" else caseText) ++
              s!"{indent}  )\n" ++
              s!"{indent}  (else\n" ++ elseBody ++
              s!"{indent}  )\n" ++
              s!"{indent})\n"
      match cases.toList with
      | [] =>
          defaultOps.foldl (fun output operation =>
            output ++ renderOperation registers memory events errors fnNames promiseStr
              indent operation) ""
      | (caseValue, caseOps) :: rest =>
          let caseText := caseOps.foldl (fun output operation =>
            output ++ renderOperation registers memory events errors fnNames promiseStr
              (indent ++ "  ") operation) ""
          let elseText := renderCases (indent ++ "  ") rest.toArray
          let elseBody := if elseText.isEmpty then s!"{indent}  nop\n" else elseText
          s!"{indent}(if (i64.eq (local.get $t{scrutinee}) (i64.const {caseValue.toNat}))\n" ++
            s!"{indent}  (then\n" ++
            (if caseText.isEmpty then s!"{indent}    nop\n" else caseText) ++
            s!"{indent}  )\n" ++
            s!"{indent}  (else\n" ++ elseBody ++
            s!"{indent}  )\n" ++
            s!"{indent})\n"

private def renderMethod (ir : IR) (promiseStr : Array (String × Nat))
    (method : MethodIR) : String :=
  let fnNames := ir.fns.map (·.name)
  let locals := String.intercalate "" <| (Array.range method.tempCount).toList.map fun index =>
    s!" (local $t{index} i64)"
  let needsMwScratch := method.operations.any fun op =>
    match op with
    | .narrowCheckedAdd bitWidth .. | .narrowCheckedSub bitWidth ..
    | .narrowCheckedMul bitWidth .. => bitWidth > 64
    | .wideCompare .. => true
    | _ => false
  let needsPfScratch := method.operations.any fun op =>
    match op with
    | .promiseTransfer .. => true
    | _ => false
  let needsTokenScratch := method.operations.any fun op =>
    match op with
    | .promiseTokenTransfer .. => true
    | _ => false
  -- ADR-0031 S1: callerPrincipalWord uses $t_pf_i for register_len scratch.
  let needsCallerScratch := method.operations.any fun op =>
    match op with
    | .callerPrincipalWord .. => true
    | _ => false
  let locals :=
    if needsMwScratch then
      -- Shared scratch: add/sub use a/b/carry; schoolbook mul uses a..7.
      locals ++ " (local $t_mw_a i64) (local $t_mw_b i64) (local $t_mw_carry i64)" ++
        " (local $t_mw_0 i64) (local $t_mw_1 i64) (local $t_mw_2 i64) (local $t_mw_3 i64)" ++
        " (local $t_mw_4 i64) (local $t_mw_5 i64) (local $t_mw_6 i64) (local $t_mw_7 i64)"
    else locals
  let locals :=
    if needsPfScratch || needsTokenScratch || needsCallerScratch then
      locals ++ " (local $t_pf_i i64) (local $t_pf_b i64)"
    else locals
  let locals :=
    if needsTokenScratch then
      -- Extra scratch for decimal conversion + JSON assembly:
      -- $t_pf_n = remaining value, $t_pf_d = current digit,
      -- $t_pf_j = JSON write cursor, $t_pf_k = decimal digit count.
      locals ++ " (local $t_pf_n i64) (local $t_pf_d i64) (local $t_pf_j i64) (local $t_pf_k i64)"
    else locals
  let operations := String.intercalate "" <| method.operations.toList.map
    (renderOperation ir.registers ir.memory
      ir.sourcePlan.events ir.sourcePlan.errors fnNames promiseStr "    ")
  s!"  (func (export \"{method.name}\"){locals}\n" ++ operations ++ "  )\n"

/-- PureFn WAT: params occupy the first local indices (`$t0..`), extra temps
    follow, and the body ends with Wasm `return` of the result value.
    Multiword scratch locals are declared for pureFn bodies too (defensive:
    pureCall currently declines multiword results, so wide ops only reach a
    pureFn via a hand-built Plan; the locals keep the WAT well-formed). -/
private def renderFn (ir : IR) (promiseStr : Array (String × Nat)) (fn : FnIR) : String :=
  let fnNames := ir.fns.map (·.name)
  let params := String.intercalate "" <| (Array.range fn.paramCount).toList.map fun index =>
    s!" (param $t{index} i64)"
  let extraLocals :=
    if fn.tempCount <= fn.paramCount then ""
    else
      String.intercalate "" <|
        (List.range (fn.tempCount - fn.paramCount)).map fun i =>
          s!" (local $t{fn.paramCount + i} i64)"
  let needsMwScratch := fn.operations.any fun op =>
    match op with
    | .narrowCheckedAdd bitWidth .. | .narrowCheckedSub bitWidth ..
    | .narrowCheckedMul bitWidth .. => bitWidth > 64
    | .wideCompare .. => true
    | _ => false
  let extraLocals :=
    if needsMwScratch then
      extraLocals ++ " (local $t_mw_a i64) (local $t_mw_b i64) (local $t_mw_carry i64)" ++
        " (local $t_mw_0 i64) (local $t_mw_1 i64) (local $t_mw_2 i64) (local $t_mw_3 i64)" ++
        " (local $t_mw_4 i64) (local $t_mw_5 i64) (local $t_mw_6 i64) (local $t_mw_7 i64)"
    else extraLocals
  let operations := String.intercalate "" <| fn.operations.toList.map
    (renderOperation ir.registers ir.memory
      ir.sourcePlan.events ir.sourcePlan.errors fnNames promiseStr "    ")
  s!"  (func $fn_{fn.name}{params} (result i64){extraLocals}\n" ++
    operations ++ "  )\n"

private def renderWat (ir : IR) : String :=
  let imports := String.intercalate "" <| ir.imports.toList.map renderImport
  let promiseStr := layoutPromiseStrings ir.memory (collectPromiseStrings ir)
  let keyData := String.intercalate "" <| ir.keys.toList.map fun key =>
    s!"  (data (i32.const {key.offset}) \"{key.key}\")\n"
  -- Escape is unnecessary: account-id grammar and identifier method names are
  -- restricted to safe ASCII (no quotes/backslashes).
  let promiseData := String.intercalate "" <| promiseStr.toList.map fun (s, off) =>
    s!"  (data (i32.const {off}) \"{s}\")\n"
  let fns := String.intercalate "" <| ir.fns.toList.map (renderFn ir promiseStr)
  let methods := String.intercalate "" <| ir.methods.toList.map (renderMethod ir promiseStr)
  "(module\n" ++ imports ++
    s!"  (memory (export \"memory\") {ir.memory.minPages})\n" ++
    keyData ++ promiseData ++ fns ++ methods ++ ")\n"

private def renderMode : MethodMode → String
  | .initialize => "initialize"
  | .mutate => "mutate"
  | .view => "view"

private def renderDepositPolicy : DepositPolicy → String
  | .requireZero => "zero-required"
  | .queryOnly => "query-only"
  | .allowAttached => "allow-attached"

private def renderParamJson (param : Param) : String :=
  s!"\{\"name\":\"{Targets.escapeJson param.name}\",\"type\":\"{abiScalarTypeString param.byteWidth}\",\"inputOffset\":{param.inputOffset}}"

private def renderParamsJson (params : Array Param) : String :=
  String.intercalate "," (params.toList.map renderParamJson)

private def renderFieldJson (field : StorageField) : String :=
  s!"\{\"name\":\"{Targets.escapeJson field.name}\",\"sourceId\":{field.sourceId},\"key\":\"{Targets.escapeJson field.key}\",\"type\":\"{abiScalarTypeString field.byteWidth}\"}"

private def renderLeafAbiJson (leaf : LeafAbiType) : String :=
  if leaf.isInt then
    match leaf.byteWidth with
    | 1 => "\"i8-le\""
    | 2 => "\"i16-le\""
    | 4 => "\"i32-le\""
    | _ => "\"i64-le\""
  else
    match leaf.byteWidth with
    | 1 => "\"u8-le\""
    | 2 => "\"u16-le\""
    | 4 => "\"u32-le\""
    | _ => "\"u64-le\""

/-- ABI `returns` field. Scalars stay a single JSON string (historical).
B-RET-ABI aggregates emit a JSON array of per-leaf type strings in preorder
flatten order, e.g. `["u64-le","u64-le"]`. -/
private def renderResultKindJson : MethodResultKind → String
  | .unit => "null"
  | .uint64 => "\"u64-le\""
  | .bool => "\"bool\""
  | .int64 => "\"i64-le\""
  | .uint8 => "\"u8-le\""
  | .uint16 => "\"u16-le\""
  | .uint32 => "\"u32-le\""
  | .uint128 => "\"u128-le\""
  | .uint256 => "\"u256-le\""
  | .int8 => "\"i8-le\""
  | .int16 => "\"i16-le\""
  | .int32 => "\"i32-le\""
  | .aggregate leaves =>
      "[" ++ String.intercalate "," (leaves.map renderLeafAbiJson).toList ++ "]"

private def renderMethodJson (method : Method) : String :=
  let returns := renderResultKindJson method.resultKind
  "{" ++
    s!"\"name\":\"{Targets.escapeJson method.name}\"," ++
    s!"\"mode\":\"{renderMode method.mode}\"," ++
    s!"\"depositPolicy\":\"{renderDepositPolicy method.depositPolicy}\"," ++
    s!"\"exactInputLen\":{method.exactInputLen}," ++
    s!"\"args\":[{renderParamsJson method.params}],\"returns\":{returns}" ++
    "}"

private def renderAbi (plan : Plan) : String :=
  let fields := String.intercalate "," (plan.storage.fields.toList.map renderFieldJson)
  let methods := #[plan.initializer] ++ plan.entries
  let exports := String.intercalate ",\n    " (methods.toList.map renderMethodJson)
  "{\n" ++
    "  \"schema\": \"proof-forge-near-abi/v1alpha1\",\n" ++
    s!"  \"program\": \"{Targets.escapeJson plan.programName}\",\n" ++
    s!"  \"codegenProfile\": \"{plan.codegenProfile}\",\n" ++
    s!"  \"hostAbi\": \"{plan.hostAbi}\",\n" ++
    s!"  \"encoding\": \"{plan.inputAbi}\",\n" ++
    "  \"storage\": {" ++
    s!"\"markerKey\":\"{plan.storage.markerKey}\"," ++
    s!"\"layoutMarker\":\"0x{uint64Hex plan.storage.markerValue}\"," ++
    "\"initializerPayloadPolicy\":\"zero-all-fields\"," ++
    s!"\"fields\":[{fields}]" ++
    "},\n" ++
    "  \"exports\": [\n    " ++ exports ++ "\n  ]\n" ++
    "}\n"

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
  validateIR ir
  return #[
    {
      path := s!"{ir.name}.wat"
      mediaType := "application/wasm-text"
      contents := renderWat ir
    },
    {
      path := s!"{ir.name}.near-abi.json"
      mediaType := "application/json"
      contents := renderAbi ir.sourcePlan
    }
  ]

/-- Replace methods on an existing IR (private `mk`; for validateIR characterization). -/
def withMethods (ir : IR) (methods : Array MethodIR) : IR :=
  { ir with methods }

/-- Replace pureFns on an existing IR (private `mk`; for validateIR characterization). -/
def withFns (ir : IR) (fns : Array FnIR) : IR :=
  { ir with fns }


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

end ProofForgeV2.Targets.Near
