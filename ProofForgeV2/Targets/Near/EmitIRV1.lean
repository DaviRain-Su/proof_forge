import ProofForgeV2.Targets.Near.ValidatePlanV1
import ProofForgeV2.Targets.Near.PfAssetsCatalogV1
import ProofForgeV2.Targets.Near.ReadOnlyWATV1

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
  /-- ADR-0031 S2: block height — host `block_index()` (u64, no conversion). -/
  | blockIndex (destination : Nat)
  /-- ADR-0030 E2-NEAR: host `account_balance` → u128 LE scratch; trap if
      high 64 bits nonzero; low 64 bits → destination (UInt64 range guard). -/
  | accountBalance (destination : Nat)
  /-- Full-width account_balance u128 LE → destination (lo) and destination+1 (hi). -/
  | accountBalanceU128 (destination : Nat)
  /-- ADR-0031 S1: host `predecessor_account_id` → register length → destination
      (Principal length leaf; trap if length ∉ 1..64). -/
  | callerPrincipalLen (destination : Nat)
  /-- ADR-0031 S1: host `predecessor_account_id` → zero-padded 64B body buffer
      → LE UInt64 body word at `wordIndex` (0..7). -/
  | callerPrincipalWord (destination wordIndex : Nat)
  /-- ADR-0031 S3: host `current_account_id` → register length → destination
      (Principal length leaf; trap if length ∉ 1..64). View-safe. -/
  | selfPrincipalLen (destination : Nat)
  /-- ADR-0031 S3: host `current_account_id` → zero-padded 64B body buffer
      → LE UInt64 body word at `wordIndex` (0..7). -/
  | selfPrincipalWord (destination wordIndex : Nat)
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
  /-- B-RET-ABI: host `value_return` of preorder leaves from arbitrary temps.
  When `leafByteWidths` is empty, each leaf is packed as 8-byte LE (historical
  Struct/Array/Option path). Otherwise `leafByteWidths.size == temps.size` and
  each temp is stored with the given width (Bytes N uses all-1 widths). -/
  | setReturnDataLeaves (temps : Array Nat) (leafByteWidths : Array Nat := #[])
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
  /-- UInt8/16/32/128/256 checked left shift. Scalar count ≥ 64 traps;
      multiword count ≥ bitWidth traps. Shifted-out high bits trap. -/
  | narrowShl (bitWidth destination lhs rhs : Nat)
  /-- UInt8/16/32/128/256 logical right shift. Scalar count ≥ 64 traps;
      multiword count ≥ bitWidth traps. -/
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

/-- Lower exactly the operations covered by the bounded typed-WAT refinement
    slice. This is consumed by the production renderer below; unsupported
    operations return `none` rather than acquiring a parallel rendering path. -/
def lowerMethodWATOperationV1
    (registers : RegisterLayout)
    (memory : MemoryLayout) :
    Operation → Option (Array MethodWATInstructionV1)
  | .checkInputLen 0 => some (checkEmptyInputWATV1 registers)
  | .requireZeroAttachedDeposit =>
      some (requireZeroAttachedDepositWATV1 memory)
  | .requireLayoutAbsent marker =>
      some (requireLayoutAbsentWATV1 registers marker)
  | .requireLayout marker value =>
      some (requireLayoutWATV1 registers memory marker value)
  | .zeroState field =>
      some (zeroUInt64StateWATV1 registers memory field)
  | .literal destination value =>
      some (uint64LiteralWATV1 destination value)
  | .loadState destination field =>
      some (loadUInt64StateWATV1 registers memory destination field)
  | .storeState field source =>
      some (storeUInt64StateWATV1 registers memory field source)
  | .setLayout marker value =>
      some (setLayoutWATV1 registers memory marker value)
  | .setReturnData 8 source => some (returnUInt64WATV1 memory source)
  | _ => none

/-- Source-order lowering for a method wholly covered by the bounded typed WAT
    subset. -/
def lowerMethodWATOperationsListV1
    (registers : RegisterLayout)
    (memory : MemoryLayout) :
    List Operation → Option (List (Array MethodWATInstructionV1))
  | [] => some []
  | operation :: remaining => do
      let head ← lowerMethodWATOperationV1 registers memory operation
      let tail ← lowerMethodWATOperationsListV1 registers memory remaining
      return head :: tail

/-- Array wrapper used by the production method renderer and refinement
    theorems. -/
def lowerMethodWATOperationsV1
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (operations : Array Operation) :
    Option (Array MethodWATInstructionV1) :=
  (lowerMethodWATOperationsListV1 registers memory operations.toList).map
    concatMethodWATRecipesV1

/-- Historical read-only names now point to the same sole bounded method-WAT
    lowering. They are aliases, not an alternate lowering. -/
abbrev lowerReadOnlyWATOperationV1 := lowerMethodWATOperationV1
abbrev lowerReadOnlyWATOperationsListV1 := lowerMethodWATOperationsListV1
abbrev lowerReadOnlyWATOperationsV1 := lowerMethodWATOperationsV1

/-- The exact four-operation MethodIR recipe lowers to the typed WAT sequence
    used by the production renderer. -/
theorem lowerReadOnlyWATOperationsV1_nullaryUInt64View
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field : KeyRegion)
    (markerValue : UInt64) :
    lowerReadOnlyWATOperationsV1 registers memory #[
      .checkInputLen 0,
      .requireLayout marker markerValue,
      .loadState 0 field,
      .setReturnData 8 0
    ] = some (nullaryUInt64ViewWATV1 registers memory marker markerValue field) := by
  rfl

/-- The exact production two-UInt64 zero initializer recipe lowers to the same
    typed-WAT sequence consumed by the sole method renderer. -/
theorem lowerMethodWATOperationsV1_nullaryZeroTwoUInt64Initializer
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue : UInt64) :
    lowerMethodWATOperationsV1 registers memory #[
      .checkInputLen 0,
      .requireZeroAttachedDeposit,
      .requireLayoutAbsent marker,
      .zeroState field0,
      .zeroState field1,
      .literal 0 0,
      .storeState field0 0,
      .literal 1 0,
      .storeState field1 1,
      .setLayout marker markerValue
    ] = some (nullaryZeroTwoUInt64InitializerWATV1 registers memory marker
      field0 field1 markerValue) := by
  rfl

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

/-- Proposition-only graph of the production key-region constructor. The
    constructor stays private; this relation exposes only evidence that a
    supplied array is its exact result. -/
def KeyRegionsV1 (plan : Plan) (keys : Array KeyRegion) : Prop :=
  keys = makeKeyRegions plan

/-- The production key-region graph determines one exact array. -/
theorem keyRegionsV1_unique (plan : Plan) (left right : Array KeyRegion)
    (hleft : KeyRegionsV1 plan left)
    (hright : KeyRegionsV1 plan right) :
    left = right := by
  exact hleft.trans hright.symm

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
    -- valueOffset holds host value_return packing (Map return up to 24×u64
    -- = 192B, sequential with pf.assets scratch which starts at +16 after
    -- any prior host op completes — return is terminal).
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
          -- `validatePlan` proves every product-path localTemp is lexically
          -- bound before recipe lowering; never change its meaning to zero.
          unreachable!
  | .blockTimestampSeconds =>
      { operations := #[.blockTimestampSeconds next]
        value := next
        next := next + 1
      }
  | .blockIndex =>
      { operations := #[.blockIndex next]
        value := next
        next := next + 1
      }
  | .accountBalance =>
      { operations := #[.accountBalance next]
        value := next
        next := next + 1
      }
  | .accountBalanceU128 =>
      -- Two consecutive temps: lo at `next`, hi at `next+1`.
      { operations := #[.accountBalanceU128 next]
        value := next
        next := next + 2
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
  | .selfPrincipalLen =>
      { operations := #[.selfPrincipalLen next]
        value := next
        next := next + 1
      }
  | .selfPrincipalWord wordIndex =>
      { operations := #[.selfPrincipalWord next wordIndex]
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
        -- leaf widths come from Method.resultKind at lowerMethod (passed via
        -- returnByteLen sentinel unused); pack widths are attached when the
        -- resultKind is known — see lowerMethodAggregateReturn.
        let mut leafTemps : Array Nat := #[]
        for leaf in leaves do
          let lowered := lowerExpr keys next fnMode localEnv leaf
          operations := operations ++ lowered.operations
          leafTemps := leafTemps.push lowered.value
          next := lowered.next
        operations := operations.push (.setReturnDataLeaves leafTemps #[])
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
  | .aggregate leaves =>
      -- Prefer sum of declared leaf widths (Bytes N = N; Array N = 8N).
      leaves.foldl (init := 0) (fun acc l => acc + l.byteWidth)

/-- Attach `Method.resultKind` leaf widths onto every `setReturnDataLeaves`,
    including nested if/switch/for arms. Empty widths keep historical N×8
    packing; Bytes N supplies all-1s. -/
private partial def attachAggregateLeafWidthsOps (widths : Array Nat)
    (ops : Array Operation) : Array Operation :=
  ops.map fun op =>
    match op with
    | .setReturnDataLeaves temps _ => .setReturnDataLeaves temps widths
    | .ifRegion c t e =>
        .ifRegion c (attachAggregateLeafWidthsOps widths t)
          (attachAggregateLeafWidthsOps widths e)
    | .switchRegion s cases d =>
        .switchRegion s
          (cases.map fun (k, body) => (k, attachAggregateLeafWidthsOps widths body))
          (attachAggregateLeafWidthsOps widths d)
    | .forRegion v init counter maxI condOps condTemp bodyOps updOps updTemp =>
        .forRegion v init counter maxI
          (attachAggregateLeafWidthsOps widths condOps) condTemp
          (attachAggregateLeafWidthsOps widths bodyOps)
          (attachAggregateLeafWidthsOps widths updOps) updTemp
    | other => other

private def attachAggregateLeafWidths (resultKind : MethodResultKind)
    (ops : Array Operation) : Array Operation :=
  match resultKind with
  | .aggregate leaves =>
      attachAggregateLeafWidthsOps (leaves.map (·.byteWidth)) ops
  | _ => ops

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
  let (bodyOps0, next) := lowerBodyOps keys 0 body false #[] (methodResultByteLen method.resultKind)
  let bodyOps := attachAggregateLeafWidths method.resultKind bodyOps0
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

/-- Proposition-only graph of the production method lowering. This exposes no
    second Plan→IR constructor: the right-hand side is the existing private
    `lowerMethod`, and callers can only carry evidence about its exact result. -/
def MethodIRLoweringV1 (plan : Plan) (keys : Array KeyRegion)
    (method : Method) (methodIR : MethodIR) : Prop :=
  methodIR = lowerMethod plan keys method

/-- The production method lowering graph is inhabited for every input. -/
theorem methodIRLoweringV1_exists (plan : Plan) (keys : Array KeyRegion)
    (method : Method) :
    ∃ methodIR, MethodIRLoweringV1 plan keys method methodIR :=
  ⟨lowerMethod plan keys method, rfl⟩

/-- The proposition-only lowering graph determines one exact recipe. -/
theorem methodIRLoweringV1_unique (plan : Plan) (keys : Array KeyRegion)
    (method : Method) (left right : MethodIR)
    (hleft : MethodIRLoweringV1 plan keys method left)
    (hright : MethodIRLoweringV1 plan keys method right) :
    left = right := by
  exact hleft.trans hright.symm

/-- The production method lowering preserves the source method name. -/
theorem methodIRLoweringV1_name (plan : Plan) (keys : Array KeyRegion)
    (method : Method) (methodIR : MethodIR)
    (hgraph : MethodIRLoweringV1 plan keys method methodIR) :
    methodIR.name = method.name := by
  rw [hgraph]
  cases hmode : method.mode <;>
    cases hdeposit : method.depositPolicy <;>
    simp [lowerMethod, hmode, hdeposit, Id.run, Bind.bind, Pure.pure] <;>
    repeat' split <;> rfl

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
  | .setLayout _ _ | .setReturnData _ _ | .setReturnDataLeaves _ _
  | .loadParam _ _ | .narrowLoadParam _ _ _
  | .blockTimestampSeconds _ | .blockIndex _ | .accountBalance _ | .accountBalanceU128 _
  | .callerPrincipalLen _ | .callerPrincipalWord _ _
  | .selfPrincipalLen _ | .selfPrincipalWord _ _ => true
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

/-- Whether the module import table covers every host function rendered by one
    typed Operation. Recursive regions are checked in source order. This is an
    import dependency contract for the production typed IR, not a WAT parser. -/
private partial def operationHostImportsCoveredV1
    (imports : Array HostImport) : Operation → Bool
  | .checkInputLen bytes =>
      imports.contains .input && imports.contains .registerLen &&
        (bytes == 0 || imports.contains .readRegister)
  | .requireZeroAttachedDeposit | .requireExactAttachedDeposit _ =>
      imports.contains .attachedDeposit
  | .blockTimestampSeconds _ => imports.contains .blockTimestamp
  | .blockIndex _ => imports.contains .blockIndex
  | .accountBalance _ | .accountBalanceU128 _ =>
      imports.contains .accountBalance
  | .callerPrincipalLen _ =>
      imports.contains .predecessorAccountId && imports.contains .registerLen
  | .callerPrincipalWord .. =>
      imports.contains .predecessorAccountId &&
        imports.contains .registerLen && imports.contains .readRegister
  | .selfPrincipalLen _ =>
      imports.contains .currentAccountId && imports.contains .registerLen
  | .selfPrincipalWord .. =>
      imports.contains .currentAccountId && imports.contains .registerLen &&
        imports.contains .readRegister
  | .requireLayoutAbsent _ => imports.contains .storageRead
  | .requireLayout .. | .loadState .. | .narrowLoadState .. =>
      imports.contains .storageRead && imports.contains .registerLen &&
        imports.contains .readRegister
  | .zeroState _ | .narrowZeroState .. | .setLayout .. =>
      imports.contains .storageWrite
  | .storeState .. | .narrowStoreState .. =>
      imports.contains .storageWrite && imports.contains .registerLen
  | .setReturnData .. | .setReturnDataLeaves .. =>
      imports.contains .valueReturn
  | .emitEvent .. => imports.contains .logUtf8
  | .revertError .. => imports.contains .panicUtf8
  | .promiseAccount .. | .promiseTokenTransfer .. =>
      imports.contains .promiseBatchCreate &&
        imports.contains .promiseBatchActionFunctionCall
  | .promiseTransfer .. =>
      imports.contains .promiseBatchCreate &&
        imports.contains .promiseBatchActionTransfer
  | .ifRegion _ thenOps elseOps =>
      thenOps.all (operationHostImportsCoveredV1 imports) &&
        elseOps.all (operationHostImportsCoveredV1 imports)
  | .switchRegion _ cases defaultOps =>
      cases.all (fun (_, caseOps) =>
        caseOps.all (operationHostImportsCoveredV1 imports)) &&
        defaultOps.all (operationHostImportsCoveredV1 imports)
  | .forRegion _ _ _ _ condOps _ bodyOps updateOps _ =>
      condOps.all (operationHostImportsCoveredV1 imports) &&
        bodyOps.all (operationHostImportsCoveredV1 imports) &&
        updateOps.all (operationHostImportsCoveredV1 imports)
  | .literal .. | .loadParam .. | .narrowLoadParam ..
  | .checkedAdd .. | .checkedSub .. | .signedCheckedAdd ..
  | .signedCheckedSub .. | .signedCheckedMul .. | .signedCheckedDiv ..
  | .signedCheckedMod .. | .signedCompare .. | .checkedNeg .. | .sar ..
  | .compare .. | .wideCompare .. | .assert _ | .returnNone
  | .callFn .. | .returnValue _ | .checkedMul .. | .checkedDiv ..
  | .checkedMod .. | .bitAnd .. | .bitOr .. | .bitXor .. | .shl ..
  | .shr .. | .bitNot .. | .narrowCheckedAdd .. | .narrowCheckedSub ..
  | .narrowCheckedMul .. | .narrowCheckedDiv .. | .narrowCheckedMod ..
  | .narrowBitAnd .. | .narrowBitOr .. | .narrowBitXor ..
  | .narrowBitNot .. | .narrowShl .. | .narrowShr .. | .boolNot ..
  | .boolAnd .. | .boolOr .. => true

/-- Fail-closed complete-module host-import consistency. The source Plan must
    own the canonical feature-derived import table, the IR must retain it
    exactly, and every recursively nested typed Operation must have all imports
    used by its production renderer. -/
def validateWATModuleHostImportsV1 (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless ir.imports == ir.sourcePlan.hostImports do
    throw <| .planInvariant .near
      "typed NEAR IR WAT imports are not exactly bound to the canonical source Plan"
  unless ir.methods.all (fun method =>
        method.operations.all (operationHostImportsCoveredV1 ir.imports)) &&
      ir.fns.all (fun fn =>
        fn.operations.all (operationHostImportsCoveredV1 ir.imports)) do
    throw <| .planInvariant .near
      "typed NEAR IR WAT operation requires an undeclared host import"

/-- Proof-relevant successful canonical host-import/dependency validation. -/
def WATModuleHostImportsSafeV1 (ir : IR) : Prop :=
  validateWATModuleHostImportsV1 ir = .ok ()

/-- The production method table retains the exact source Plan method identity
    and order consumed by WAT export emission, plus the parameter/mode metadata
    rendered from that same Plan authority by the ABI emitter. -/
private def methodRowsBoundToPlanV1 (ir : IR) : Bool :=
  let sourceMethods := #[ir.sourcePlan.initializer] ++ ir.sourcePlan.entries
  ir.methods.size == sourceMethods.size &&
    (ir.methods.zip sourceMethods).all (fun pair =>
      pair.1.name == pair.2.name &&
        pair.1.params == pair.2.params &&
        pair.1.mode == pair.2.mode)

/-- Fail-closed generated-module method/export consistency. The canonical Plan
    validates safe, unique names distinct from the fixed `memory` export; this
    gate binds the typed method rows to that exact ordered source table. -/
def validateWATModuleMethodExportsV1 (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless methodRowsBoundToPlanV1 ir do
    throw <| .planInvariant .near
      "typed NEAR IR WAT method exports are not exactly bound to source Plan order and signatures"

/-- Proof-relevant successful method/export table validation. -/
def WATModuleMethodExportsSafeV1 (ir : IR) : Prop :=
  validateWATModuleMethodExportsV1 ir = .ok ()

/-- Whether the consecutive local range beginning at `base` is declared by a
    function whose complete numeric local namespace is `0..<tempCount`. -/
private def tempSpanDeclaredV1 (tempCount base count : Nat) : Bool :=
  count > 0 && base + count <= tempCount

/-- Every numeric `$t<n>` local referenced by one rendered operation is within
    the enclosing method/pureFn declaration. Multiword operations validate the
    complete consecutive limb spans, and structured regions recurse over the
    same operation tree consumed by the sole production renderer. -/
private partial def operationLocalReferencesValidV1
    (tempCount : Nat) : Operation → Bool
  | .checkInputLen _ | .requireZeroAttachedDeposit | .requireLayoutAbsent _
  | .requireLayout .. | .zeroState _ | .narrowZeroState .. | .setLayout ..
  | .returnNone => true
  | .requireExactAttachedDeposit amount => amount < tempCount
  | .blockTimestampSeconds destination | .blockIndex destination
  | .accountBalance destination | .callerPrincipalLen destination
  | .callerPrincipalWord destination _ | .selfPrincipalLen destination
  | .selfPrincipalWord destination _ | .literal destination _
  | .loadParam destination _ | .loadState destination _ =>
      destination < tempCount
  | .accountBalanceU128 destination =>
      tempSpanDeclaredV1 tempCount destination 2
  | .narrowLoadParam bitWidth destination _
  | .narrowLoadState bitWidth destination _ =>
      tempSpanDeclaredV1 tempCount destination
        (limbCountOfBitWidth bitWidth)
  | .checkedAdd destination lhs rhs | .checkedSub destination lhs rhs
  | .signedCheckedAdd destination lhs rhs
  | .signedCheckedSub destination lhs rhs
  | .signedCheckedMul destination lhs rhs
  | .signedCheckedDiv destination lhs rhs
  | .signedCheckedMod destination lhs rhs | .sar destination lhs rhs
  | .checkedMul destination lhs rhs | .checkedDiv destination lhs rhs
  | .checkedMod destination lhs rhs | .bitAnd destination lhs rhs
  | .bitOr destination lhs rhs | .bitXor destination lhs rhs
  | .shl destination lhs rhs | .shr destination lhs rhs
  | .boolAnd destination lhs rhs | .boolOr destination lhs rhs
  | .signedCompare destination lhs rhs _
  | .compare destination lhs rhs _ =>
      destination < tempCount && lhs < tempCount && rhs < tempCount
  | .checkedNeg destination source | .bitNot destination source
  | .boolNot destination source =>
      destination < tempCount && source < tempCount
  | .storeState _ value => value < tempCount
  | .narrowStoreState bitWidth _ value =>
      tempSpanDeclaredV1 tempCount value (limbCountOfBitWidth bitWidth)
  | .setReturnData byteLen value =>
      let count := if byteLen > 8 then byteLen / 8 else 1
      tempSpanDeclaredV1 tempCount value count
  | .setReturnDataLeaves temps _ => temps.all (· < tempCount)
  | .wideCompare bitWidth destination lhs rhs _ =>
      let count := limbCountOfBitWidth bitWidth
      destination < tempCount &&
        tempSpanDeclaredV1 tempCount lhs count &&
        tempSpanDeclaredV1 tempCount rhs count
  | .assert condition => condition < tempCount
  | .emitEvent _ args | .revertError _ args
  | .promiseAccount _ _ args => args.all (· < tempCount)
  | .ifRegion condition thenOps elseOps =>
      condition < tempCount &&
        thenOps.all (operationLocalReferencesValidV1 tempCount) &&
        elseOps.all (operationLocalReferencesValidV1 tempCount)
  | .switchRegion scrutinee cases defaultOps =>
      scrutinee < tempCount &&
        cases.all (fun (_, caseOps) =>
          caseOps.all (operationLocalReferencesValidV1 tempCount)) &&
        defaultOps.all (operationLocalReferencesValidV1 tempCount)
  | .forRegion varTemp initial counterTemp _ condOps condition bodyOps
      updateOps updateValue =>
      varTemp < tempCount && initial < tempCount &&
        counterTemp < tempCount && condition < tempCount &&
        updateValue < tempCount &&
        condOps.all (operationLocalReferencesValidV1 tempCount) &&
        bodyOps.all (operationLocalReferencesValidV1 tempCount) &&
        updateOps.all (operationLocalReferencesValidV1 tempCount)
  | .callFn _ destination args =>
      destination < tempCount && args.all (· < tempCount)
  | .returnValue value => value < tempCount
  | .narrowCheckedAdd bitWidth destination lhs rhs
  | .narrowCheckedSub bitWidth destination lhs rhs
  | .narrowCheckedMul bitWidth destination lhs rhs
  | .narrowCheckedDiv bitWidth destination lhs rhs
  | .narrowCheckedMod bitWidth destination lhs rhs
  | .narrowBitAnd bitWidth destination lhs rhs
  | .narrowBitOr bitWidth destination lhs rhs
  | .narrowBitXor bitWidth destination lhs rhs =>
      let count := limbCountOfBitWidth bitWidth
      tempSpanDeclaredV1 tempCount destination count &&
        tempSpanDeclaredV1 tempCount lhs count &&
        tempSpanDeclaredV1 tempCount rhs count
  | .narrowBitNot bitWidth destination source =>
      let count := limbCountOfBitWidth bitWidth
      tempSpanDeclaredV1 tempCount destination count &&
        tempSpanDeclaredV1 tempCount source count
  | .narrowShl bitWidth destination lhs rhs
  | .narrowShr bitWidth destination lhs rhs =>
      let count := limbCountOfBitWidth bitWidth
      tempSpanDeclaredV1 tempCount destination count &&
        tempSpanDeclaredV1 tempCount lhs count && rhs < tempCount
  | .promiseTransfer dstLen dstWords amount =>
      dstLen < tempCount && amount < tempCount &&
        dstWords.all (· < tempCount)
  | .promiseTokenTransfer mintLen mintWords dstLen dstWords amount =>
      mintLen < tempCount && dstLen < tempCount && amount < tempCount &&
        mintWords.all (· < tempCount) && dstWords.all (· < tempCount)

/-- Fail-closed generated-module numeric-local consistency. Successful
    validation guarantees that every `$t<n>` emitted in any method or pureFn,
    including nested control flow and multiword limb spans, has a matching
    parameter/local declaration in that enclosing function. -/
def validateWATModuleLocalReferencesV1 (ir : IR) : CompileResult Unit := do
  unless ir.methods.all (fun method =>
        method.operations.all
          (operationLocalReferencesValidV1 method.tempCount)) &&
      ir.fns.all (fun fn =>
        fn.paramCount <= fn.tempCount &&
          fn.operations.all
            (operationLocalReferencesValidV1 fn.tempCount)) do
    throw <| .planInvariant .near
      "typed NEAR IR WAT operation references an undeclared numeric local"

/-- Proof-relevant successful generated-module numeric-local validation. -/
def WATModuleLocalReferencesSafeV1 (ir : IR) : Prop :=
  validateWATModuleLocalReferencesV1 ir = .ok ()

/-- Every internal `callFn` rendered by one typed Operation resolves to the
    indexed production FnIR row with its exact Wasm parameter arity. -/
private partial def operationFnReferencesValidV1
    (fns : Array FnIR) : Operation → Bool
  | .callFn fnIndex _ args =>
      match fns[fnIndex]? with
      | some fn => args.size == fn.paramCount
      | none => false
  | .ifRegion _ thenOps elseOps =>
      thenOps.all (operationFnReferencesValidV1 fns) &&
        elseOps.all (operationFnReferencesValidV1 fns)
  | .switchRegion _ cases defaultOps =>
      cases.all (fun (_, caseOps) =>
        caseOps.all (operationFnReferencesValidV1 fns)) &&
        defaultOps.all (operationFnReferencesValidV1 fns)
  | .forRegion _ _ _ _ condOps _ bodyOps updateOps _ =>
      condOps.all (operationFnReferencesValidV1 fns) &&
        bodyOps.all (operationFnReferencesValidV1 fns) &&
        updateOps.all (operationFnReferencesValidV1 fns)
  | _ => true

private def fnRowsBoundToPlanV1 (ir : IR) : Bool :=
  ir.fns.size == ir.sourcePlan.fns.size &&
    (ir.fns.zip ir.sourcePlan.fns).all (fun pair =>
      pair.1.name == pair.2.name &&
        pair.1.paramCount == pair.2.params.size &&
        pair.1.resultIsBool == pair.2.resultIsBool &&
        pair.1.paramCount <= pair.1.tempCount)

/-- Fail-closed complete-module pureFn reference consistency. The canonical
    Plan owns source-order function identities/signatures; every FnIR row keeps
    that index binding and every recursively nested call resolves with exact
    arity. Therefore the production renderer's `$fn_<name>` lookup cannot take
    its invalid-IR `unknown` fallback after successful validation. -/
def validateWATModuleFnReferencesV1 (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless fnRowsBoundToPlanV1 ir do
    throw <| .planInvariant .near
      "typed NEAR IR WAT pureFn table is not exactly bound to source Plan signatures"
  unless ir.methods.all (fun method =>
        method.operations.all (operationFnReferencesValidV1 ir.fns)) &&
      ir.fns.all (fun fn =>
        fn.operations.all (operationFnReferencesValidV1 ir.fns)) do
    throw <| .planInvariant .near
      "typed NEAR IR WAT pureFn call has a dangling index or wrong arity"

/-- Proof-relevant successful pureFn table/reference validation. -/
def WATModuleFnReferencesSafeV1 (ir : IR) : Prop :=
  validateWATModuleFnReferencesV1 ir = .ok ()

/-- First-seen order of schedule receiver/method strings across the IR. The
    renderer and module-memory validator share this sole collection path. -/
private partial def collectPromiseStringsFromOps
    (ops : Array Operation) : Array String :=
  ops.foldl (fun acc op =>
    match op with
    | .promiseAccount receiver method _ =>
        let acc := if acc.contains receiver then acc else acc.push receiver
        if acc.contains method then acc else acc.push method
    | .promiseTokenTransfer .. =>
        if acc.contains "ft_transfer" then acc else acc.push "ft_transfer"
    | .ifRegion _ thenOps elseOps =>
        acc ++ collectPromiseStringsFromOps thenOps ++
          collectPromiseStringsFromOps elseOps
    | .switchRegion _ cases defaultOps =>
        cases.foldl
          (fun current (_, caseOps) =>
            current ++ collectPromiseStringsFromOps caseOps)
          (acc ++ collectPromiseStringsFromOps defaultOps)
    | .forRegion _ _ _ _ condOps _ bodyOps updateOps _ =>
        acc ++ collectPromiseStringsFromOps condOps ++
          collectPromiseStringsFromOps bodyOps ++
          collectPromiseStringsFromOps updateOps
    | _ => acc) #[]

private def collectPromiseStrings (ir : IR) : Array String :=
  ir.methods.foldl
      (fun acc method =>
        acc ++ collectPromiseStringsFromOps method.operations) #[] ++
    ir.fns.foldl
      (fun acc fn => acc ++ collectPromiseStringsFromOps fn.operations) #[]

/-- The production promise-data region starts after the complete transient
    value scratch envelope. -/
private def promiseDataOffsetV1 (memory : MemoryLayout) : Nat :=
  memory.valueOffset + 1024

/-- Sole production placement for promise strings. Keeping this before both
    validation and rendering prevents an unchecked parallel layout. -/
private def layoutPromiseStrings (memory : MemoryLayout)
    (strings : Array String) : Array (String × Nat) := Id.run do
  let mut offset := promiseDataOffsetV1 memory
  let mut table : Array (String × Nat) := #[]
  for string in strings do
    unless table.any (fun pair => pair.1 == string) do
      table := table.push (string, offset)
      offset := offset + string.toUTF8.size
  pure table

private def promiseStringOffset (table : Array (String × Nat))
    (string : String) : Nat :=
  match table.find? (fun pair => pair.1 == string) with
  | some (_, offset) => offset
  | none => 0

private def maxMemoryEndV1 (left right : Option Nat) : Option Nat :=
  match left, right with
  | some left, some right => some (max left right)
  | _, _ => none

private def keyRegionMemoryEndV1 (region : KeyRegion) : Nat :=
  region.offset + region.key.toUTF8.size

private def keyRegionsContiguousFromV1 : Nat → List KeyRegion → Bool
  | _, [] => true
  | expectedOffset, region :: remaining =>
      let byteLength := region.key.toUTF8.size
      region.offset == expectedOffset && region.length == byteLength &&
        keyRegionsContiguousFromV1 (expectedOffset + byteLength) remaining

private def interfaceMessageMemoryEndV1
    (memory : MemoryLayout)
    (tag : String)
    (bindings : Array InterfaceBinding)
    (bindingIndex argCount : Nat) : Option Nat :=
  match bindings[bindingIndex]? with
  | none => none
  | some binding =>
      let prefixLength := s!"pf-{tag}:{binding.name}".toUTF8.size
      let payloadLength :=
        if argCount = 0 then prefixLength
        else prefixLength + 1 + 16 * argCount + (argCount - 1)
      some (memory.valueOffset + 8 + payloadLength)

/-- Cover both the host-visible return span and every concrete store emitted
    for aggregate leaves. Missing widths default to an 8-byte store in the
    renderer, so malformed typed IR must not make this bound smaller. -/
private def returnDataLeavesMemoryEndV1
    (memory : MemoryLayout)
    (temps leafByteWidths : Array Nat) : Nat := Id.run do
  let widths :=
    if leafByteWidths.isEmpty then Array.replicate temps.size 8
    else leafByteWidths
  let returnLength := widths.foldl (fun total width => total + width) 0
  let mut offset := memory.valueOffset
  let mut storeEnd := offset
  for index in [:temps.size] do
    let width := match widths[index]? with | some width => width | none => 8
    let storeWidth :=
      match width with
      | 1 => 1
      | 2 => 2
      | 4 => 4
      | _ => 8
    storeEnd := max storeEnd (offset + storeWidth)
    offset := offset + width
  return max storeEnd (memory.valueOffset + returnLength)

/-- Highest exclusive linear-memory address touched by one production
    Operation. `none` rejects a dangling interface reference. This typed IR
    footprint is shared by the complete-module validator; it is not a WAT text
    parser or an execution semantics. -/
private partial def operationMemoryEndV1 (ir : IR) : Operation → Option Nat
  | .checkInputLen bytes => some (ir.memory.inputOffset + bytes)
  | .requireZeroAttachedDeposit | .requireExactAttachedDeposit _ =>
      some (ir.memory.depositOffset + 16)
  | .accountBalance _ | .accountBalanceU128 _ =>
      some (ir.memory.depositOffset + 16)
  | .requireLayoutAbsent marker => some (keyRegionMemoryEndV1 marker)
  | .requireLayout marker _ =>
      some (max (keyRegionMemoryEndV1 marker) (ir.memory.valueOffset + 8))
  | .zeroState field =>
      some (max (keyRegionMemoryEndV1 field) (ir.memory.valueOffset + 8))
  | .narrowZeroState bitWidth field =>
      some (max (keyRegionMemoryEndV1 field)
        (ir.memory.valueOffset + bitWidth / 8))
  | .callerPrincipalWord _ wordIndex | .selfPrincipalWord _ wordIndex =>
      some (ir.memory.valueOffset + 16 + max 64 (8 * (wordIndex + 1)))
  | .loadParam _ inputOffset =>
      some (ir.memory.inputOffset + inputOffset + 8)
  | .narrowLoadParam bitWidth _ inputOffset =>
      some (ir.memory.inputOffset + inputOffset + bitWidth / 8)
  | .loadState _ field =>
      some (max (keyRegionMemoryEndV1 field) (ir.memory.valueOffset + 8))
  | .narrowLoadState bitWidth _ field =>
      some (max (keyRegionMemoryEndV1 field)
        (ir.memory.valueOffset + bitWidth / 8))
  | .storeState field _ =>
      some (max (keyRegionMemoryEndV1 field) (ir.memory.valueOffset + 8))
  | .narrowStoreState bitWidth field _ =>
      some (max (keyRegionMemoryEndV1 field)
        (ir.memory.valueOffset + bitWidth / 8))
  | .setLayout marker _ =>
      some (max (keyRegionMemoryEndV1 marker) (ir.memory.valueOffset + 8))
  | .setReturnData byteLength _ =>
      some (ir.memory.valueOffset + max 8 byteLength)
  | .setReturnDataLeaves temps leafByteWidths =>
      some (returnDataLeavesMemoryEndV1 ir.memory temps leafByteWidths)
  | .emitEvent eventIndex args =>
      interfaceMessageMemoryEndV1 ir.memory "event" ir.sourcePlan.events
        eventIndex args.size
  | .revertError errorIndex args =>
      interfaceMessageMemoryEndV1 ir.memory "error" ir.sourcePlan.errors
        errorIndex args.size
  | .promiseAccount _ _ args =>
      some (max (ir.memory.valueOffset + 16)
        (ir.memory.valueOffset + 8 + 8 * args.size))
  | .promiseTransfer _ dstWords _ =>
      some (max (ir.memory.valueOffset + 96)
        (ir.memory.valueOffset + 16 + 8 * dstWords.size))
  | .promiseTokenTransfer _ mintWords _ dstWords _ =>
      let jsonLength := "{\"receiver_id\":\"".toUTF8.size + 64 +
        "\",\"amount\":\"".toUTF8.size + 20 + 1
      -- Decimal conversion first writes at `decBuf + 20`; include that byte.
      some (max (ir.memory.valueOffset + 301)
        (max (ir.memory.valueOffset + 16 + 8 * mintWords.size)
          (max (ir.memory.valueOffset + 80 + 8 * dstWords.size)
            (ir.memory.valueOffset + 144 + jsonLength))))
  | .ifRegion _ thenOps elseOps =>
      maxMemoryEndV1
        (thenOps.foldl
          (fun current operation =>
            maxMemoryEndV1 current (operationMemoryEndV1 ir operation))
          (some 0))
        (elseOps.foldl
          (fun current operation =>
            maxMemoryEndV1 current (operationMemoryEndV1 ir operation))
          (some 0))
  | .switchRegion _ cases defaultOps =>
      cases.foldl
        (fun current (_, caseOps) =>
          maxMemoryEndV1 current <|
            caseOps.foldl
              (fun caseCurrent operation =>
                maxMemoryEndV1 caseCurrent
                  (operationMemoryEndV1 ir operation))
              (some 0))
        (defaultOps.foldl
          (fun current operation =>
            maxMemoryEndV1 current (operationMemoryEndV1 ir operation))
          (some 0))
  | .forRegion _ _ _ _ condOps _ bodyOps updateOps _ =>
      maxMemoryEndV1
        (condOps.foldl
          (fun current operation =>
            maxMemoryEndV1 current (operationMemoryEndV1 ir operation))
          (some 0)) <|
        maxMemoryEndV1
          (bodyOps.foldl
            (fun current operation =>
              maxMemoryEndV1 current (operationMemoryEndV1 ir operation))
            (some 0))
          (updateOps.foldl
            (fun current operation =>
              maxMemoryEndV1 current (operationMemoryEndV1 ir operation))
            (some 0))
  | .literal .. | .blockTimestampSeconds _ | .blockIndex _
  | .callerPrincipalLen _ | .selfPrincipalLen _
  | .checkedAdd .. | .checkedSub .. | .signedCheckedAdd ..
  | .signedCheckedSub .. | .signedCheckedMul .. | .signedCheckedDiv ..
  | .signedCheckedMod .. | .signedCompare .. | .checkedNeg .. | .sar ..
  | .compare .. | .wideCompare .. | .assert _ | .returnNone
  | .callFn .. | .returnValue _ | .checkedMul .. | .checkedDiv ..
  | .checkedMod .. | .bitAnd .. | .bitOr .. | .bitXor .. | .shl ..
  | .shr .. | .bitNot .. | .narrowCheckedAdd .. | .narrowCheckedSub ..
  | .narrowCheckedMul .. | .narrowCheckedDiv .. | .narrowCheckedMod ..
  | .narrowBitAnd .. | .narrowBitOr .. | .narrowBitXor ..
  | .narrowBitNot .. | .narrowShl .. | .narrowShr .. | .boolNot ..
  | .boolAnd .. | .boolOr .. => some 0

private def moduleOperationMemoryEndV1 (ir : IR) : Option Nat :=
  let methodEnd := ir.methods.foldl
    (fun current method =>
      method.operations.foldl
        (fun methodCurrent operation =>
          maxMemoryEndV1 methodCurrent (operationMemoryEndV1 ir operation))
        current) (some 0)
  ir.fns.foldl
    (fun current fn =>
      fn.operations.foldl
        (fun fnCurrent operation =>
          maxMemoryEndV1 fnCurrent (operationMemoryEndV1 ir operation))
        current) methodEnd

/-- Static memory/data-segment gate for a complete generated production WAT
    module. It checks contiguous key bytes, canonical region separation, every
    typed Operation's highest memory access, and the sole promise-string data
    layout against declared linear memory. This validates typed IR metadata,
    not arbitrary textual WAT or Wasm binaries. -/
def validateWATModuleMemoryV1 (ir : IR) : CompileResult Unit := do
  let memoryLimit := ir.memory.minPages * wasmPageBytes
  unless keyRegionsContiguousFromV1 0 ir.keys.toList do
    throw <| .planInvariant .near
      "typed NEAR IR WAT key data regions are not contiguous exact UTF-8 bytes"
  let keyDataEnd := ir.keys.foldl
    (fun current region => max current (keyRegionMemoryEndV1 region)) 0
  unless keyDataEnd <= ir.memory.inputOffset &&
      ir.memory.inputOffset + ir.memory.inputCapacity <=
        ir.memory.depositOffset &&
      ir.memory.depositOffset + 16 <= ir.memory.valueOffset do
    throw <| .planInvariant .near
      "typed NEAR IR WAT key/input/deposit/value memory regions overlap"
  let some operationEnd := moduleOperationMemoryEndV1 ir
    | throw <| .planInvariant .near
        "typed NEAR IR WAT operation has a dangling interface binding"
  let promiseDataOffset := promiseDataOffsetV1 ir.memory
  unless operationEnd <= promiseDataOffset && promiseDataOffset <= memoryLimit do
    throw <| .planInvariant .near
      "typed NEAR IR WAT operation scratch exceeds its reserved memory region"
  let promiseStrings := collectPromiseStrings ir
  let promiseTable := layoutPromiseStrings ir.memory promiseStrings
  let promiseDataEnd := promiseTable.foldl
    (fun current pair => max current (pair.2 + pair.1.toUTF8.size))
    promiseDataOffset
  unless promiseDataEnd <= memoryLimit do
    throw <| .planInvariant .near
      "typed NEAR IR WAT promise data exceeds declared linear memory"

/-- Proof-relevant successful complete-module memory/data validation. -/
def WATModuleMemorySafeV1 (ir : IR) : Prop :=
  validateWATModuleMemoryV1 ir = .ok ()

/-- Core typed host-call recipe validation and exact source-Plan binding. -/
private def validateIRCore (ir : IR) : CompileResult Unit := do
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

/-- Validate the typed host-call recipe, bind it exactly to its source Plan,
    and close the generated WAT module's import/export, function-call,
    numeric-local, and linear-memory/data envelopes. -/
def validateIR (ir : IR) : CompileResult Unit := do
  validateIRCore ir
  validateWATModuleHostImportsV1 ir
  validateWATModuleMethodExportsV1 ir
  validateWATModuleFnReferencesV1 ir
  validateWATModuleLocalReferencesV1 ir
  validateWATModuleMemoryV1 ir

/-- Successful production IR validation exposes the canonical host-import and
    recursive operation-dependency certificate. -/
theorem validateIR_watModuleHostImportsSafeV1
    (ir : IR)
    (hvalidate : validateIR ir = .ok ()) :
    WATModuleHostImportsSafeV1 ir := by
  unfold validateIR at hvalidate
  cases hcore : validateIRCore ir with
  | error error =>
      simp [hcore, Bind.bind, Except.bind] at hvalidate
  | ok result =>
      cases result
      cases himports : validateWATModuleHostImportsV1 ir with
      | error error =>
          simp [hcore, himports, Bind.bind, Except.bind] at hvalidate
      | ok result =>
          cases result
          exact himports

/-- Successful production IR validation exposes the ordered method/export
    identity and signature certificate. -/
theorem validateIR_watModuleMethodExportsSafeV1
    (ir : IR)
    (hvalidate : validateIR ir = .ok ()) :
    WATModuleMethodExportsSafeV1 ir := by
  unfold validateIR at hvalidate
  cases hcore : validateIRCore ir with
  | error error =>
      simp [hcore, Bind.bind, Except.bind] at hvalidate
  | ok result =>
      cases result
      cases himports : validateWATModuleHostImportsV1 ir with
      | error error =>
          simp [hcore, himports, Bind.bind, Except.bind] at hvalidate
      | ok result =>
          cases result
          cases hexports : validateWATModuleMethodExportsV1 ir with
          | error error =>
              simp [hcore, himports, hexports, Bind.bind, Except.bind] at hvalidate
          | ok result =>
              cases result
              exact hexports

/-- Successful production IR validation exposes the source-order pureFn table
    and recursive internal-call reference certificate. -/
theorem validateIR_watModuleFnReferencesSafeV1
    (ir : IR)
    (hvalidate : validateIR ir = .ok ()) :
    WATModuleFnReferencesSafeV1 ir := by
  unfold validateIR at hvalidate
  cases hcore : validateIRCore ir with
  | error error =>
      simp [hcore, Bind.bind, Except.bind] at hvalidate
  | ok result =>
      cases result
      cases himports : validateWATModuleHostImportsV1 ir with
      | error error =>
          simp [hcore, himports, Bind.bind, Except.bind] at hvalidate
      | ok result =>
          cases result
          cases hexports : validateWATModuleMethodExportsV1 ir with
          | error error =>
              simp [hcore, himports, hexports, Bind.bind, Except.bind] at hvalidate
          | ok result =>
              cases result
              cases hfns : validateWATModuleFnReferencesV1 ir with
              | error error =>
                  simp [hcore, himports, hexports, hfns, Bind.bind,
                    Except.bind] at hvalidate
              | ok result =>
                  cases result
                  exact hfns

/-- Successful production IR validation exposes the recursive numeric-local
    declaration/reference certificate. -/
theorem validateIR_watModuleLocalReferencesSafeV1
    (ir : IR)
    (hvalidate : validateIR ir = .ok ()) :
    WATModuleLocalReferencesSafeV1 ir := by
  unfold validateIR at hvalidate
  cases hcore : validateIRCore ir with
  | error error =>
      simp [hcore, Bind.bind, Except.bind] at hvalidate
  | ok result =>
      cases result
      cases himports : validateWATModuleHostImportsV1 ir with
      | error error =>
          simp [hcore, himports, Bind.bind, Except.bind] at hvalidate
      | ok result =>
          cases result
          cases hexports : validateWATModuleMethodExportsV1 ir with
          | error error =>
              simp [hcore, himports, hexports, Bind.bind, Except.bind] at hvalidate
          | ok result =>
              cases result
              cases hfns : validateWATModuleFnReferencesV1 ir with
              | error error =>
                  simp [hcore, himports, hexports, hfns, Bind.bind,
                    Except.bind] at hvalidate
              | ok result =>
                  cases result
                  cases hlocals : validateWATModuleLocalReferencesV1 ir with
                  | error error =>
                      simp [hcore, himports, hexports, hfns, hlocals,
                        Bind.bind, Except.bind] at hvalidate
                  | ok result =>
                      cases result
                      exact hlocals

/-- Successful production IR validation exposes the complete generated-module
    memory/data certificate without replaying a second validator. -/
theorem validateIR_watModuleMemorySafeV1
    (ir : IR)
    (hvalidate : validateIR ir = .ok ()) :
    WATModuleMemorySafeV1 ir := by
  unfold validateIR at hvalidate
  cases hcore : validateIRCore ir with
  | error error =>
      simp [hcore, Bind.bind, Except.bind] at hvalidate
  | ok result =>
      cases result
      cases himports : validateWATModuleHostImportsV1 ir with
      | error error =>
          simp [hcore, himports, Bind.bind, Except.bind] at hvalidate
      | ok result =>
          cases result
          cases hexports : validateWATModuleMethodExportsV1 ir with
          | error error =>
              simp [hcore, himports, hexports, Bind.bind, Except.bind] at hvalidate
          | ok result =>
              cases result
              cases hfns : validateWATModuleFnReferencesV1 ir with
              | error error =>
                  simp [hcore, himports, hexports, hfns, Bind.bind,
                    Except.bind] at hvalidate
              | ok result =>
                  cases result
                  cases hlocals : validateWATModuleLocalReferencesV1 ir with
                  | error error =>
                      simp [hcore, himports, hexports, hfns, hlocals,
                        Bind.bind, Except.bind] at hvalidate
                  | ok result =>
                      cases result
                      simpa [WATModuleMemorySafeV1, hcore, himports, hexports,
                        hfns, hlocals, Bind.bind, Except.bind] using hvalidate

private def makeIR (plan : Plan) : IR :=
  let keys := makeKeyRegions plan
  let memory := makeMemoryLayout plan keys
  {
    sourcePlan := plan
    name := plan.programName
    imports := plan.hostImports
    registers := canonicalRegisters
    keys
    memory
    methods := expectedMethods plan keys
    fns := expectedFns plan keys
  }

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let ir := makeIR plan
  validateIR ir
  return ir

/-- Exact proposition-only graph of successful production Plan→IR lowering.
    This does not expose a public Plan→IR constructor: the right-hand side is
    the existing private validated lowering. -/
def PlanIRLoweringV1 (plan : Plan) (ir : IR) : Prop :=
  lower plan = .ok ir

private theorem planIRLoweringV1_eq_makeIR
    (plan : Plan) (ir : IR)
    (hgraph : PlanIRLoweringV1 plan ir) :
    makeIR plan = ir := by
  unfold PlanIRLoweringV1 lower at hgraph
  cases hplan : validatePlan plan with
  | error error =>
      simp [hplan, Bind.bind, Except.bind] at hgraph
  | ok _ =>
      cases hir : validateIR (makeIR plan) with
      | error error =>
          simp [hplan, hir, Bind.bind, Except.bind] at hgraph
      | ok _ =>
          have hok : (Except.ok (makeIR plan) : CompileResult IR) = .ok ir := by
            simpa [hplan, hir, Bind.bind, Except.bind, Pure.pure,
              Except.pure] using hgraph
          exact Except.ok.inj hok

/-- A successful production lowering retains the exact source Plan. -/
theorem planIRLoweringV1_sourcePlan
    (plan : Plan) (ir : IR)
    (hgraph : PlanIRLoweringV1 plan ir) :
    ir.sourcePlan = plan := by
  have hir := planIRLoweringV1_eq_makeIR plan ir hgraph
  rw [← hir]
  rfl

/-- A successful production lowering uses the exact private canonical key
    regions for its source Plan. -/
theorem planIRLoweringV1_keyRegions
    (plan : Plan) (ir : IR)
    (hgraph : PlanIRLoweringV1 plan ir) :
    KeyRegionsV1 plan ir.keys := by
  have hir := planIRLoweringV1_eq_makeIR plan ir hgraph
  rw [← hir]
  rfl

/-- A successful production lowering uses the exact production method array. -/
theorem planIRLoweringV1_methods
    (plan : Plan) (ir : IR)
    (hgraph : PlanIRLoweringV1 plan ir) :
    ir.methods = expectedMethods plan ir.keys := by
  have hir := planIRLoweringV1_eq_makeIR plan ir hgraph
  rw [← hir]
  rfl

/-- Entry `i` is lowered to IR method `i + 1`; index zero is reserved for the
    initializer. The method evidence is the existing production lowering graph. -/
theorem planIRLoweringV1_entry_lookup
    (plan : Plan) (ir : IR) (i : Nat) (method : Method)
    (hgraph : PlanIRLoweringV1 plan ir)
    (hentry : plan.entries[i]? = some method) :
    ∃ methodIR,
      ir.methods[i + 1]? = some methodIR ∧
      MethodIRLoweringV1 plan ir.keys method methodIR := by
  have hmethods := planIRLoweringV1_methods plan ir hgraph
  refine ⟨lowerMethod plan ir.keys method, ?_, rfl⟩
  rw [hmethods, expectedMethods]
  rw [Array.getElem?_append_right (by simp)]
  simp [Array.getElem?_map, hentry]

/-- If both source and emitted entry lookups are known, the concrete emitted
    MethodIR carries the existing production method-lowering graph evidence. -/
theorem planIRLoweringV1_entry_lookup_eq_some
    (plan : Plan) (ir : IR) (i : Nat) (method : Method) (methodIR : MethodIR)
    (hgraph : PlanIRLoweringV1 plan ir)
    (hentry : plan.entries[i]? = some method)
    (hmethodIR : ir.methods[i + 1]? = some methodIR) :
    MethodIRLoweringV1 plan ir.keys method methodIR := by
  obtain ⟨lowered, hlowered, hgraphMethod⟩ :=
    planIRLoweringV1_entry_lookup plan ir i method hgraph hentry
  have : lowered = methodIR :=
    Option.some.inj (hlowered.symm.trans hmethodIR)
  simpa [this] using hgraphMethod

/-- IR method zero is the sole production lowering of the Plan initializer. -/
theorem planIRLoweringV1_initializer_lookup_eq_some
    (plan : Plan) (ir : IR) (method : Method) (methodIR : MethodIR)
    (hgraph : PlanIRLoweringV1 plan ir)
    (hinitializer : plan.initializer = method)
    (hmethodIR : ir.methods[0]? = some methodIR) :
    MethodIRLoweringV1 plan ir.keys method methodIR := by
  have hmethods := planIRLoweringV1_methods plan ir hgraph
  have hlowered :
      ir.methods[0]? = some (lowerMethod plan ir.keys plan.initializer) := by
    rw [hmethods]
    unfold expectedMethods
    rw [Array.getElem?_append_left (by simp)]
    rfl
  have heq : lowerMethod plan ir.keys plan.initializer = methodIR :=
    Option.some.inj (hlowered.symm.trans hmethodIR)
  subst method
  simp [MethodIRLoweringV1, heq]

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
  | .blockIndex =>
      -- ADR-0031 S2: block_index returns u64 height (view-safe host read).
      "  (import \"env\" \"block_index\" (func $pf_block_index (result i64)))\n"
  | .accountBalance =>
      -- ADR-0030 E2-NEAR: account_balance writes u128 LE to balance_ptr
      -- (same ABI shape as attached_deposit: one pointer param, void return).
      "  (import \"env\" \"account_balance\" (func $pf_account_balance (param i64)))\n"
  | .predecessorAccountId =>
      -- ADR-0031 S1: predecessor_account_id writes UTF-8 account-id into
      -- register_id (void). View contexts forbid this host call at runtime;
      -- Plan already fail-closes view ContextRead caller.
      "  (import \"env\" \"predecessor_account_id\" (func $pf_predecessor_account_id (param i64)))\n"
  | .currentAccountId =>
      -- ADR-0031 S3: current_account_id writes UTF-8 account-id into
      -- a register (view-safe). Used by context.self Principal leaves.
      "  (import \"env\" \"current_account_id\" (func $pf_current_account_id (param i64)))\n"
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

/-- Multiword checked div/mod via restoring binary long division over LE i64
    limbs (UInt128 `nLimbs=2` / UInt256 `nLimbs=4`). Mirrors Solana
    `emitMultiwordDivMod`:

      rem := 0                          -- `nLimbs+1` limbs (extra high digit)
      quot := 0                         -- `nLimbs` limbs
      for bit from (nLimbs·64 − 1) downto 0:
        rem := (rem << 1) | dividend[bit]
        if rem ≥ divisor:               -- zero-extended divisor
          rem := rem − divisor
          quot[bit] := 1

    Divisor zero (all limbs zero) → `unreachable` (same host trap path as
    scalar checked div). Quotient and remainder are always in-range for
    unsigned division; no overflow path beyond div-by-zero.

    Fully unrolled over the bit width so every limb/shift is a compile-time
    immediate. Scratch rem/quot live in named `$t_mw_r*` / `$t_mw_q*` locals
    (declared when multiword div/mod is present) so lhs/rhs/dest aliasing is
    safe. `kind` is `"div"` (write quot) or `"mod"` (write rem low limbs).
    Engineering-only; not formal D2/D4. -/
private def renderMultiwordDivMod (indent : String) (dest lhs rhs nLimbs : Nat)
    (kind : String) : String :=
  Id.run do
    let nBits := nLimbs * 64
    let mut out := s!"{indent};; multiword checked_{kind} nLimbs={nLimbs} binary long division\n"
    -- Divisor nonzero? OR of all limbs.
    out := out ++ s!"{indent}(local.set $t_mw_a (local.get $t{rhs}))\n"
    for i in [1:nLimbs] do
      out := out ++
        s!"{indent}(local.set $t_mw_a (i64.or (local.get $t_mw_a) (local.get $t{rhs + i})))\n"
    out := out ++
      s!"{indent}(if (i64.eqz (local.get $t_mw_a)) (then unreachable))\n"
    -- Zero rem (incl. high digit remHi = $t_mw_r{nLimbs}) and quot.
    for i in [:nLimbs + 1] do
      out := out ++ s!"{indent}(local.set $t_mw_r{i} (i64.const 0))\n"
    for i in [:nLimbs] do
      out := out ++ s!"{indent}(local.set $t_mw_q{i} (i64.const 0))\n"
    -- bit = nBits-1 .. 0 (fully unrolled)
    for j in [:nBits] do
      let bitPos := nBits - 1 - j
      let numLimb := bitPos / 64
      let numBit := bitPos % 64
      out := out ++ s!"{indent};; bit {bitPos} (limb {numLimb} bit {numBit})\n"
      -- rem := rem << 1  (nLimbs+1 limbs, high → low so lower digits stay fresh)
      out := out ++
        s!"{indent}(local.set $t_mw_r{nLimbs} (i64.or (i64.shl (local.get $t_mw_r{nLimbs}) (i64.const 1)) (i64.shr_u (local.get $t_mw_r{nLimbs - 1}) (i64.const 63))))\n"
      for iRev in [:nLimbs] do
        let i := nLimbs - 1 - iRev
        if i > 0 then
          out := out ++
            s!"{indent}(local.set $t_mw_r{i} (i64.or (i64.shl (local.get $t_mw_r{i}) (i64.const 1)) (i64.shr_u (local.get $t_mw_r{i - 1}) (i64.const 63))))\n"
        else
          -- rem[0] = (rem[0] << 1) | dividend[bitPos]
          let bitExtract :=
            if numBit == 0 then
              s!"(i64.and (local.get $t{lhs + numLimb}) (i64.const 1))"
            else
              s!"(i64.and (i64.shr_u (local.get $t{lhs + numLimb}) (i64.const {numBit})) (i64.const 1))"
          out := out ++
            s!"{indent}(local.set $t_mw_r0 (i64.or (i64.shl (local.get $t_mw_r0) (i64.const 1)) {bitExtract}))\n"
      -- if rem ≥ divisor (zero-extended): subtract and set quot bit.
      -- $t_mw_carry = decided; $t_mw_a = ge result.
      out := out ++
        s!"{indent}(local.set $t_mw_carry (i64.const 0))\n" ++
        s!"{indent}(local.set $t_mw_a (i64.const 0))\n" ++
        s!"{indent}(if (i64.ne (local.get $t_mw_r{nLimbs}) (i64.const 0)) (then (local.set $t_mw_a (i64.const 1)) (local.set $t_mw_carry (i64.const 1))))\n"
      for iRev in [:nLimbs] do
        let i := nLimbs - 1 - iRev
        -- (if undecided (then (if gt → ge=1) (else (if lt → ge=0))))
        -- After last local.set completes, six structure closes:
        -- then-lt, if-lt, else-gt, if-gt, then-outer, if-outer.
        out := out ++
          s!"{indent}(if (i64.eqz (local.get $t_mw_carry)) (then\n" ++
          s!"{indent}  (if (i64.gt_u (local.get $t_mw_r{i}) (local.get $t{rhs + i}))\n" ++
          s!"{indent}    (then (local.set $t_mw_a (i64.const 1)) (local.set $t_mw_carry (i64.const 1)))\n" ++
          s!"{indent}    (else (if (i64.lt_u (local.get $t_mw_r{i}) (local.get $t{rhs + i}))\n" ++
          s!"{indent}      (then (local.set $t_mw_a (i64.const 0)) (local.set $t_mw_carry (i64.const 1))))))))\n"
      -- All limbs equal and remHi==0 ⇒ rem == divisor ⇒ ge.
      out := out ++
        s!"{indent}(if (i64.eqz (local.get $t_mw_carry)) (then (local.set $t_mw_a (i64.const 1))))\n"
      out := out ++
        s!"{indent}(if (i64.ne (local.get $t_mw_a) (i64.const 0)) (then\n"
      -- rem_low -= divisor with borrow into remHi (same carry formula as checked_sub).
      out := out ++ s!"{indent}  (local.set $t_mw_carry (i64.const 0))\n"
      for i in [:nLimbs] do
        out := out ++
          s!"{indent}  (local.set $t_mw_b (local.get $t_mw_r{i}))\n" ++
          s!"{indent}  (local.set $t_mw_r{i} (i64.sub (i64.sub (local.get $t_mw_b) (local.get $t{rhs + i})) (local.get $t_mw_carry)))\n" ++
          s!"{indent}  (local.set $t_mw_carry (i64.or (i64.extend_i32_u (i64.lt_u (local.get $t_mw_b) (local.get $t{rhs + i}))) (i64.and (local.get $t_mw_carry) (i64.extend_i32_u (i64.eq (local.get $t_mw_b) (local.get $t{rhs + i}))))))\n"
      out := out ++
        s!"{indent}  (local.set $t_mw_r{nLimbs} (i64.sub (local.get $t_mw_r{nLimbs}) (local.get $t_mw_carry)))\n"
      -- quot[numLimb] |= 1 << numBit
      let quotBit :=
        if numBit == 0 then "(i64.const 1)"
        else s!"(i64.shl (i64.const 1) (i64.const {numBit}))"
      out := out ++
        s!"{indent}  (local.set $t_mw_q{numLimb} (i64.or (local.get $t_mw_q{numLimb}) {quotBit}))\n" ++
        s!"{indent}))\n"
    -- Copy quotient or remainder into dest (named scratch ⇒ alias-safe).
    if kind == "div" then
      for t in [:nLimbs] do
        out := out ++
          s!"{indent}(local.set $t{dest + t} (local.get $t_mw_q{t}))\n"
    else
      for t in [:nLimbs] do
        out := out ++
          s!"{indent}(local.set $t{dest + t} (local.get $t_mw_r{t}))\n"
    pure out

/-- Multiword logical left shift on consecutive i64 LE limbs (UInt128/256).
    Count ≥ bitWidth traps. Whole-limb moves + residual bit shift with
    carry between limbs; high-limb overflow (bits shifted out) traps
    (checked-shl honesty, same as CosmWasm WideShiftProbe).
    Scratch: $t_mw_a/b/carry/0..3 (already declared for multiword methods). -/
private def renderMultiwordShl (indent : String) (dest lhs rhs nLimbs bitWidth : Nat) :
    String :=
  Id.run do
    -- rhs is a single UInt32 temp (not multi-limb).
    let mut out :=
      s!"{indent};; multiword shl nLimbs={nLimbs} bitWidth={bitWidth}\n" ++
      s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const {bitWidth})) (then unreachable))\n"
    for i in [:nLimbs] do
      out := out ++
        s!"{indent}(local.set $t_mw_{i} (local.get $t{lhs + i}))\n"
    out := out ++
      s!"{indent}(local.set $t_mw_a (i64.div_u (local.get $t{rhs}) (i64.const 64)))\n" ++
      s!"{indent}(local.set $t_mw_b (i64.rem_u (local.get $t{rhs}) (i64.const 64)))\n"
    for i in [:nLimbs] do
      out := out ++ s!"{indent}(local.set $t{dest + i} (i64.const 0))\n"
    for whole in [:nLimbs] do
      out := out ++
        s!"{indent}(if (i64.eq (local.get $t_mw_a) (i64.const {whole}))\n" ++
        s!"{indent}  (then\n"
      for i in [:nLimbs - whole] do
        out := out ++
          s!"{indent}    (local.set $t{dest + i + whole} (local.get $t_mw_{i}))\n"
      -- High limbs that would be shifted out must have been zero (checked shl).
      for i in [nLimbs - whole:nLimbs] do
        if whole > 0 then
          out := out ++
            s!"{indent}    (if (i64.ne (local.get $t_mw_{i}) (i64.const 0)) (then unreachable))\n"
      out := out ++ s!"{indent}  )\n{indent})\n"
    out := out ++
      s!"{indent}(if (i64.ne (local.get $t_mw_b) (i64.const 0))\n" ++
      s!"{indent}  (then\n" ++
      s!"{indent}    (local.set $t_mw_carry (i64.const 0))\n"
    for i in [:nLimbs] do
      out := out ++
        s!"{indent}    (local.set $t_mw_a (local.get $t{dest + i}))\n" ++
        s!"{indent}    (local.set $t{dest + i} (i64.or (i64.shl (local.get $t_mw_a) (local.get $t_mw_b)) (local.get $t_mw_carry)))\n" ++
        s!"{indent}    (local.set $t_mw_carry (i64.shr_u (local.get $t_mw_a) (i64.sub (i64.const 64) (local.get $t_mw_b))))\n"
    out := out ++
      s!"{indent}    (if (i64.ne (local.get $t_mw_carry) (i64.const 0)) (then unreachable))\n" ++
      s!"{indent}  )\n" ++
      s!"{indent})\n"
    pure out

/-- Multiword logical right shift on consecutive i64 LE limbs (UInt128/256).
    Count ≥ bitWidth traps. No overflow check (logical shr). -/
private def renderMultiwordShr (indent : String) (dest lhs rhs nLimbs bitWidth : Nat) :
    String :=
  Id.run do
    let mut out :=
      s!"{indent};; multiword shr nLimbs={nLimbs} bitWidth={bitWidth}\n" ++
      s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const {bitWidth})) (then unreachable))\n"
    for i in [:nLimbs] do
      out := out ++
        s!"{indent}(local.set $t_mw_{i} (local.get $t{lhs + i}))\n"
    out := out ++
      s!"{indent}(local.set $t_mw_a (i64.div_u (local.get $t{rhs}) (i64.const 64)))\n" ++
      s!"{indent}(local.set $t_mw_b (i64.rem_u (local.get $t{rhs}) (i64.const 64)))\n"
    for i in [:nLimbs] do
      out := out ++ s!"{indent}(local.set $t{dest + i} (i64.const 0))\n"
    for whole in [:nLimbs] do
      out := out ++
        s!"{indent}(if (i64.eq (local.get $t_mw_a) (i64.const {whole}))\n" ++
        s!"{indent}  (then\n"
      for i in [:nLimbs - whole] do
        out := out ++
          s!"{indent}    (local.set $t{dest + i} (local.get $t_mw_{i + whole}))\n"
      out := out ++ s!"{indent}  )\n{indent})\n"
    out := out ++
      s!"{indent}(if (i64.ne (local.get $t_mw_b) (i64.const 0))\n" ++
      s!"{indent}  (then\n" ++
      s!"{indent}    (local.set $t_mw_carry (i64.const 0))\n"
    let mut i := nLimbs
    while i > 0 do
      i := i - 1
      out := out ++
        s!"{indent}    (local.set $t_mw_a (local.get $t{dest + i}))\n" ++
        s!"{indent}    (local.set $t{dest + i} (i64.or (i64.shr_u (local.get $t_mw_a) (local.get $t_mw_b)) (local.get $t_mw_carry)))\n" ++
        s!"{indent}    (local.set $t_mw_carry (i64.shl (local.get $t_mw_a) (i64.sub (i64.const 64) (local.get $t_mw_b))))\n"
    out := out ++
      s!"{indent}  )\n" ++
      s!"{indent})\n"
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

private partial def renderOperation (registers : RegisterLayout) (memory : MemoryLayout)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (fnNames : Array String) (promiseStr : Array (String × Nat))
    (indent : String) : Operation → String
  | .checkInputLen bytes =>
      if bytes = 0 then
        renderMethodWATInstructionsV1 indent (checkEmptyInputWATV1 registers)
      else
        s!"{indent}(call $pf_input (i64.const {registers.input}))\n" ++
          s!"{indent}(if (i64.ne (call $pf_register_len (i64.const {registers.input})) (i64.const {bytes})) (then unreachable))\n" ++
          s!"{indent}(call $pf_read_register (i64.const {registers.input}) (i64.const {memory.inputOffset}))\n"
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
      renderMethodWATInstructionsV1 indent
        (requireLayoutWATV1 registers memory marker value)
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
  | .blockIndex destination =>
      -- ADR-0031 S2: host block_index → u64 height (no conversion).
      s!"{indent}(local.set $t{destination} (call $pf_block_index))\n"
  | .accountBalance destination =>
      -- ADR-0030 E2-NEAR: host account_balance → u128 LE at depositOffset
      -- (shared 16-byte scratch with attached_deposit; not live simultaneously
      -- across a single expr eval). High 64 bits must be zero (UInt64 range
      -- guard, same discipline as EVM SELFBALANCE); low 64 bits are the result.
      s!"{indent}(call $pf_account_balance (i64.const {memory.depositOffset}))\n" ++
        s!"{indent}(if (i64.ne (i64.load (i32.const {memory.depositOffset + 8})) (i64.const 0)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.load (i32.const {memory.depositOffset})))\n"
  | .accountBalanceU128 destination =>
      -- Full-width u128 LE: lo → t{destination}, hi → t{destination+1}. No trap.
      s!"{indent}(call $pf_account_balance (i64.const {memory.depositOffset}))\n" ++
        s!"{indent}(local.set $t{destination} (i64.load (i32.const {memory.depositOffset})))\n" ++
        s!"{indent}(local.set $t{destination + 1} (i64.load (i32.const {memory.depositOffset + 8})))\n"
  | .callerPrincipalLen destination =>
      -- ADR-0031 S1: predecessor_account_id → layout.predecessor → length leaf.
      -- Canonical Principal wire = u32le(L)||account-id-utf8; leaf0 = L.
      -- Bound L ∈ 1..64 (pilot Principal body max; NEAR account-id ≤ 64).
      -- Register id is sole-owned by `registers.predecessor` (canonical = 3).
      s!"{indent}(call $pf_predecessor_account_id (i64.const {registers.predecessor}))\n" ++
        s!"{indent}(local.set $t{destination} (call $pf_register_len (i64.const {registers.predecessor})))\n" ++
        s!"{indent}(if (i64.lt_u (local.get $t{destination}) (i64.const 1)) (then unreachable))\n" ++
        s!"{indent}(if (i64.gt_u (local.get $t{destination}) (i64.const 64)) (then unreachable))\n"
  | .callerPrincipalWord destination wordIndex =>
      -- ADR-0031 S1: predecessor → zero-pad 64B body buffer → LE word.
      -- Scratch at valueOffset+16 (64 bytes); not live across other host ops
      -- in the same leaf eval. Unused tail bytes forced 0 so Principal leaf
      -- equality is length-exact (trailing pad must match).
      -- Register id is sole-owned by `registers.predecessor` (canonical = 3).
      let bodyBuf := memory.valueOffset + 16
      Id.run do
        let mut out :=
          s!"{indent}(call $pf_predecessor_account_id (i64.const {registers.predecessor}))\n" ++
          s!"{indent}(local.set $t_pf_i (call $pf_register_len (i64.const {registers.predecessor})))\n" ++
          s!"{indent}(if (i64.lt_u (local.get $t_pf_i) (i64.const 1)) (then unreachable))\n" ++
          s!"{indent}(if (i64.gt_u (local.get $t_pf_i) (i64.const 64)) (then unreachable))\n"
        -- Zero the full 64-byte body buffer before read_register (host only
        -- writes `len` bytes; pad must be 0 for Principal leaf identity).
        for j in [0:8] do
          out := out ++
            s!"{indent}(i64.store (i32.const {bodyBuf + 8 * j}) (i64.const 0))\n"
        out := out ++
          s!"{indent}(call $pf_read_register (i64.const {registers.predecessor}) (i64.const {bodyBuf}))\n" ++
          s!"{indent}(local.set $t{destination} (i64.load (i32.const {bodyBuf + 8 * wordIndex})))\n"
        pure out
  | .selfPrincipalLen destination =>
      -- ADR-0031 S3: current_account_id → layout.current → length leaf.
      -- Canonical Principal wire = u32le(L)||account-id-utf8; leaf0 = L.
      -- Bound L ∈ 1..64 (pilot Principal body max; NEAR account-id ≤ 64).
      -- Register id is sole-owned by `registers.current` (canonical = 4).
      s!"{indent}(call $pf_current_account_id (i64.const {registers.current}))\n" ++
        s!"{indent}(local.set $t{destination} (call $pf_register_len (i64.const {registers.current})))\n" ++
        s!"{indent}(if (i64.lt_u (local.get $t{destination}) (i64.const 1)) (then unreachable))\n" ++
        s!"{indent}(if (i64.gt_u (local.get $t{destination}) (i64.const 64)) (then unreachable))\n"
  | .selfPrincipalWord destination wordIndex =>
      -- ADR-0031 S3: current → zero-pad 64B body buffer → LE word.
      -- Scratch at valueOffset+16 (64 bytes); not live across other host ops
      -- in the same leaf eval. Unused tail bytes forced 0 so Principal leaf
      -- equality is length-exact (trailing pad must match).
      -- Register id is sole-owned by `registers.current` (canonical = 4).
      let bodyBuf := memory.valueOffset + 16
      Id.run do
        let mut out :=
          s!"{indent}(call $pf_current_account_id (i64.const {registers.current}))\n" ++
          s!"{indent}(local.set $t_pf_i (call $pf_register_len (i64.const {registers.current})))\n" ++
          s!"{indent}(if (i64.lt_u (local.get $t_pf_i) (i64.const 1)) (then unreachable))\n" ++
          s!"{indent}(if (i64.gt_u (local.get $t_pf_i) (i64.const 64)) (then unreachable))\n"
        -- Zero the full 64-byte body buffer before read_register (host only
        -- writes `len` bytes; pad must be 0 for Principal leaf identity).
        for j in [0:8] do
          out := out ++
            s!"{indent}(i64.store (i32.const {bodyBuf + 8 * j}) (i64.const 0))\n"
        out := out ++
          s!"{indent}(call $pf_read_register (i64.const {registers.current}) (i64.const {bodyBuf}))\n" ++
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
      renderMethodWATInstructionsV1 indent
        (loadUInt64StateWATV1 registers memory destination field)
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
        -- Multiword (UInt128/256): restoring binary long division over LE limbs.
        renderMultiwordDivMod indent destination lhs rhs (limbCountOfBitWidth bitWidth) "div"
      else
        s!"{indent}(if (i64.eqz (local.get $t{rhs})) (then unreachable))\n" ++
          s!"{indent}(local.set $t{destination} (i64.div_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .narrowCheckedMod bitWidth destination lhs rhs =>
      if bitWidth > 64 then
        -- Multiword (UInt128/256): same long division; write remainder limbs.
        renderMultiwordDivMod indent destination lhs rhs (limbCountOfBitWidth bitWidth) "mod"
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
        renderMultiwordShl indent destination lhs rhs
          (limbCountOfBitWidth bitWidth) bitWidth
      else
        -- Count ≥ 64 trap; shl; high bits above bitWidth must be 0.
        s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const 64)) (then unreachable))\n" ++
          s!"{indent}(local.set $t{destination} (i64.shl (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
          s!"{indent}(if (i64.ne (i64.shr_u (local.get $t{destination}) (i64.const {bitWidth})) (i64.const 0)) (then unreachable))\n"
  | .narrowShr bitWidth destination lhs rhs =>
      if bitWidth > 64 then
        renderMultiwordShr indent destination lhs rhs
          (limbCountOfBitWidth bitWidth) bitWidth
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
      if byteLen = 8 then
        renderMethodWATInstructionsV1 indent
          (returnUInt64WATV1 memory value)
      else if byteLen > 8 then
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

  | .setReturnDataLeaves temps leafByteWidths =>
      Id.run do
        -- Empty widths → historical N×8 LE packing (Struct/Array/Option).
        let widths : Array Nat :=
          if leafByteWidths.isEmpty then
            Array.replicate temps.size 8
          else
            leafByteWidths
        let mut byteLen := 0
        for w in widths do
          byteLen := byteLen + w
        let mut out := ""
        let mut offset := memory.valueOffset
        for i in [:temps.size] do
          let t := temps[i]!
          let w := match widths[i]? with | some x => x | none => 8
          if w == 1 then
            out := out ++
              s!"{indent}(i32.store8 (i32.const {offset}) (i32.wrap_i64 (local.get $t{t})))
"
          else if w == 2 then
            out := out ++
              s!"{indent}(i32.store16 (i32.const {offset}) (i32.wrap_i64 (local.get $t{t})))
"
          else if w == 4 then
            out := out ++
              s!"{indent}(i32.store (i32.const {offset}) (i32.wrap_i64 (local.get $t{t})))
"
          else
            out := out ++
              s!"{indent}(i64.store (i32.const {offset}) (local.get $t{t}))
"
          offset := offset + w
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
      s!"{indent}(if (i64.ne (local.get $t{condition}) (i64.const 0))\n{indent}  (then\n" ++ thenBody ++
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

private structure WATScratchRequirementsV1 where
  multiword : Bool := false
  multiwordDivMod : Bool := false
  principalOrTransfer : Bool := false
  tokenTransfer : Bool := false
  deriving Inhabited

private def mergeWATScratchRequirementsV1
    (left right : WATScratchRequirementsV1) : WATScratchRequirementsV1 := {
  multiword := left.multiword || right.multiword
  multiwordDivMod := left.multiwordDivMod || right.multiwordDivMod
  principalOrTransfer := left.principalOrTransfer || right.principalOrTransfer
  tokenTransfer := left.tokenTransfer || right.tokenTransfer
}

/-- Recursive scratch-local dependency analysis for the sole WAT renderer.
    Control-flow regions render their nested operations recursively, so local
    declarations must use the same complete operation tree rather than only
    the callable's top-level rows. -/
private partial def operationWATScratchRequirementsV1 :
    Operation → WATScratchRequirementsV1
  | .narrowCheckedDiv bitWidth .. | .narrowCheckedMod bitWidth .. =>
      if bitWidth > 64 then
        { multiword := true, multiwordDivMod := true }
      else {}
  | .narrowCheckedAdd bitWidth .. | .narrowCheckedSub bitWidth ..
  | .narrowCheckedMul bitWidth .. | .narrowShl bitWidth ..
  | .narrowShr bitWidth .. =>
      if bitWidth > 64 then { multiword := true } else {}
  | .wideCompare .. => { multiword := true }
  | .callerPrincipalWord .. | .selfPrincipalWord .. | .promiseTransfer .. =>
      { principalOrTransfer := true }
  | .promiseTokenTransfer .. =>
      { principalOrTransfer := true, tokenTransfer := true }
  | .ifRegion _ thenOps elseOps =>
      let thenRequirements := thenOps.foldl
        (fun requirements operation =>
          mergeWATScratchRequirementsV1 requirements
            (operationWATScratchRequirementsV1 operation)) {}
      elseOps.foldl
        (fun requirements operation =>
          mergeWATScratchRequirementsV1 requirements
            (operationWATScratchRequirementsV1 operation)) thenRequirements
  | .switchRegion _ cases defaultOps =>
      let caseRequirements := cases.foldl
        (fun requirements (_, caseOps) =>
          caseOps.foldl
            (fun current operation =>
              mergeWATScratchRequirementsV1 current
                (operationWATScratchRequirementsV1 operation)) requirements) {}
      defaultOps.foldl
        (fun requirements operation =>
          mergeWATScratchRequirementsV1 requirements
            (operationWATScratchRequirementsV1 operation)) caseRequirements
  | .forRegion _ _ _ _ condOps _ bodyOps updateOps _ =>
      let condRequirements := condOps.foldl
        (fun requirements operation =>
          mergeWATScratchRequirementsV1 requirements
            (operationWATScratchRequirementsV1 operation)) {}
      let bodyRequirements := bodyOps.foldl
        (fun requirements operation =>
          mergeWATScratchRequirementsV1 requirements
            (operationWATScratchRequirementsV1 operation)) condRequirements
      updateOps.foldl
        (fun requirements operation =>
          mergeWATScratchRequirementsV1 requirements
            (operationWATScratchRequirementsV1 operation)) bodyRequirements
  | _ => {}

private def operationsWATScratchRequirementsV1
    (operations : Array Operation) : WATScratchRequirementsV1 :=
  operations.foldl
    (fun requirements operation =>
      mergeWATScratchRequirementsV1 requirements
        (operationWATScratchRequirementsV1 operation)) {}

private def renderWATScratchLocalsV1
    (requirements : WATScratchRequirementsV1) : String := Id.run do
  let mut locals := ""
  if requirements.multiword then
    -- Shared scratch: add/sub use a/b/carry; schoolbook mul uses a..7;
    -- binary long division reuses a/b/carry for ge/borrow;
    -- multiword shl/shr use a/b/carry + mw_0.. for limb snapshots.
    locals := locals ++
      " (local $t_mw_a i64) (local $t_mw_b i64) (local $t_mw_carry i64)" ++
      " (local $t_mw_0 i64) (local $t_mw_1 i64) (local $t_mw_2 i64) (local $t_mw_3 i64)" ++
      " (local $t_mw_4 i64) (local $t_mw_5 i64) (local $t_mw_6 i64) (local $t_mw_7 i64)"
  if requirements.multiwordDivMod then
    -- rem[0..4] (nLimbs+1 max for UInt256) + quot[0..3] for long division.
    locals := locals ++
      " (local $t_mw_r0 i64) (local $t_mw_r1 i64) (local $t_mw_r2 i64)" ++
      " (local $t_mw_r3 i64) (local $t_mw_r4 i64)" ++
      " (local $t_mw_q0 i64) (local $t_mw_q1 i64) (local $t_mw_q2 i64) (local $t_mw_q3 i64)"
  if requirements.principalOrTransfer then
    locals := locals ++ " (local $t_pf_i i64) (local $t_pf_b i64)"
  if requirements.tokenTransfer then
    -- Extra scratch for decimal conversion + JSON assembly:
    -- $t_pf_n = remaining value, $t_pf_d = current digit,
    -- $t_pf_j = JSON write cursor, $t_pf_k = decimal digit count.
    locals := locals ++
      " (local $t_pf_n i64) (local $t_pf_d i64) (local $t_pf_j i64) (local $t_pf_k i64)"
  return locals

private def renderMethod (ir : IR) (promiseStr : Array (String × Nat))
    (method : MethodIR) : String :=
  let fnNames := ir.fns.map (·.name)
  let requirements := operationsWATScratchRequirementsV1 method.operations
  let locals :=
    String.intercalate "" ((Array.range method.tempCount).toList.map fun index =>
      s!" (local $t{index} i64)") ++
      renderWATScratchLocalsV1 requirements
  let operations := String.intercalate "" <| method.operations.toList.map
    (renderOperation ir.registers ir.memory
      ir.sourcePlan.events ir.sourcePlan.errors fnNames promiseStr "    ")
  match lowerMethodWATOperationsV1 ir.registers ir.memory method.operations with
  | some instructions =>
      renderMethodWATV1 method.name method.tempCount instructions
  | none =>
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
  let tempLocals :=
    if fn.tempCount <= fn.paramCount then ""
    else
      String.intercalate "" <|
        (List.range (fn.tempCount - fn.paramCount)).map fun i =>
          s!" (local $t{fn.paramCount + i} i64)"
  let requirements := operationsWATScratchRequirementsV1 fn.operations
  let extraLocals := tempLocals ++ renderWATScratchLocalsV1 requirements
  let operations := String.intercalate "" <| fn.operations.toList.map
    (renderOperation ir.registers ir.memory
      ir.sourcePlan.events ir.sourcePlan.errors fnNames promiseStr "    ")
  s!"  (func $fn_{fn.name}{params} (result i64){extraLocals}\n" ++
    operations ++ "  )\n"

private def renderWatBeforeMethods
    (ir : IR) (promiseStr : Array (String × Nat)) : String :=
  let imports := String.intercalate "" <| ir.imports.toList.map renderImport
  let keyData := String.intercalate "" <| ir.keys.toList.map fun key =>
    s!"  (data (i32.const {key.offset}) \"{key.key}\")\n"
  -- Escape is unnecessary: account-id grammar and identifier method names are
  -- restricted to safe ASCII (no quotes/backslashes).
  let promiseData := String.intercalate "" <| promiseStr.toList.map fun (s, off) =>
    s!"  (data (i32.const {off}) \"{s}\")\n"
  let fns := String.intercalate "" <| ir.fns.toList.map (renderFn ir promiseStr)
  "(module\n" ++ imports ++
    s!"  (memory (export \"memory\") {ir.memory.minPages})\n" ++
    keyData ++ promiseData ++ fns

private def renderWat (ir : IR) : String :=
  let promiseStr := layoutPromiseStrings ir.memory (collectPromiseStrings ir)
  let methods := String.intercalate "" <|
    ir.methods.toList.map (renderMethod ir promiseStr)
  renderWatBeforeMethods ir promiseStr ++ methods ++ ")\n"

/-- Exact complete-module framing graph of the sole production WAT renderer.
    `renderWatBeforeMethods` owns the module opener, imports, memory, key and
    promise data segments, and pure functions; the ordered method renderer and
    closing delimiter follow exactly. This is generated-text ownership from a
    typed IR, not a parser or validator for arbitrary textual WAT. -/
def WATModuleEmissionV1 (ir : IR) (watText : String) : Prop :=
  let promiseStr := layoutPromiseStrings ir.memory (collectPromiseStrings ir)
  let methods := String.intercalate "" <|
    ir.methods.toList.map (renderMethod ir promiseStr)
  watText = renderWatBeforeMethods ir promiseStr ++ methods ++ ")\n"

/-- One production IR owns at most one complete WAT module text. -/
theorem watModuleEmissionV1_unique
    (ir : IR)
    (left right : String)
    (hleft : WATModuleEmissionV1 ir left)
    (hright : WATModuleEmissionV1 ir right) :
    left = right := by
  exact hleft.trans hright.symm

private theorem intercalateEmpty_eq_join (values : List String) :
    String.intercalate "" values = String.join values := by
  induction values with
  | nil => simp
  | cons head tail ih =>
      cases tail with
      | nil => simp
      | cons next rest => simp [ih]

private theorem intercalateMapEmpty_split_of_getElem?_eq_some
    {α : Type} (values : List α) (render : α → String)
    (index : Nat) (value : α)
    (hlookup : values[index]? = some value) :
    String.intercalate "" (values.map render) =
      String.intercalate "" ((values.take index).map render) ++
        render value ++
        String.intercalate "" ((values.drop (index + 1)).map render) := by
  rw [List.getElem?_eq_some_iff] at hlookup
  obtain ⟨hindex, hvalue⟩ := hlookup
  have hdrop := List.drop_eq_getElem_cons hindex
  rw [hvalue] at hdrop
  have hsplit := List.take_append_drop index values
  rw [hdrop] at hsplit
  simp only [intercalateEmpty_eq_join]
  calc
    String.join (values.map render) =
        String.join ((values.take index ++
          value :: values.drop (index + 1)).map render) := by
      exact congrArg (fun items => String.join (items.map render)) hsplit.symm
    _ = String.join ((values.take index).map render) ++ render value ++
        String.join ((values.drop (index + 1)).map render) := by
      simp [String.append_assoc]

/-- Exact method-scoped graph of the sole production WAT renderer. The method
    lookup ties `methodText` to one authoritative IR row, while the split ties
    that exact rendering to the complete production WAT text. This is syntax
    provenance, not a WAT parser, evaluator, or execution relation. -/
def MethodWATEmissionV1
    (ir : IR)
    (methodIndex : Nat)
    (method : MethodIR)
    (watText methodText : String) : Prop :=
  let promiseStr := layoutPromiseStrings ir.memory (collectPromiseStrings ir)
  let render := renderMethod ir promiseStr
  let methodsText := String.intercalate "" (ir.methods.toList.map render)
  ir.methods[methodIndex]? = some method ∧
  methodText = render method ∧
  watText = renderWat ir ∧
  methodsText =
    String.intercalate "" ((ir.methods.toList.take methodIndex).map render) ++
      methodText ++
      String.intercalate ""
        ((ir.methods.toList.drop (methodIndex + 1)).map render) ∧
  ∃ before after, watText = before ++ methodsText ++ after

/-- Every method-scoped production graph retains ownership of the complete
    surrounding module framing from the same sole renderer. -/
theorem methodWATEmissionV1_watModuleEmissionV1
    (ir : IR)
    (methodIndex : Nat)
    (method : MethodIR)
    (watText methodText : String)
    (hemission :
      MethodWATEmissionV1 ir methodIndex method watText methodText) :
    WATModuleEmissionV1 ir watText := by
  simpa [WATModuleEmissionV1, renderWat] using hemission.2.2.1

/-- Production WAT emission whose selected method is wholly rendered from the
    bounded typed WAT subset. The complete base WAT remains tied to the sole
    private emitter through `MethodWATEmissionV1`. -/
def ReadOnlyMethodWATEmissionV1
    (ir : IR)
    (methodIndex : Nat)
    (method : MethodIR)
    (watText methodText : String)
    (instructions : Array ReadOnlyWATInstructionV1) : Prop :=
  MethodWATEmissionV1 ir methodIndex method watText methodText ∧
  lowerReadOnlyWATOperationsV1 ir.registers ir.memory method.operations =
    some instructions ∧
  methodText =
    renderReadOnlyWATMethodV1 method.name method.tempCount instructions

/-- Exact production text identity plus successful static validation for one
    method represented by the bounded typed-WAT subset. This relation does not
    parse arbitrary WAT: it binds the sole production renderer's exact method
    fragment to its typed source and validator result. -/
def ValidatedReadOnlyMethodWATEmissionV1
    (ir : IR)
    (methodIndex : Nat)
    (method : MethodIR)
    (watText methodText : String)
    (instructions : Array ReadOnlyWATInstructionV1) : Prop :=
  ReadOnlyMethodWATEmissionV1 ir methodIndex method watText methodText
    instructions ∧
  validateReadOnlyWATMethodV1 ir.keys ir.memory method.tempCount instructions =
    .ok ()

/-- A validated production IR owns the complete generated WAT module framing,
    while one selected method is exactly rendered from and validated against
    the bounded typed-WAT subset. This validates the typed IR and selected
    method syntax only; it is not general textual-WAT module validation. -/
structure ValidatedReadOnlyWATModuleEmissionV1
    (ir : IR)
    (methodIndex : Nat)
    (method : MethodIR)
    (watText methodText : String)
    (instructions : Array ReadOnlyWATInstructionV1) : Prop where
  moduleEmission : WATModuleEmissionV1 ir watText
  irValidation : validateIR ir = .ok ()
  moduleHostImportsSafety : WATModuleHostImportsSafeV1 ir
  moduleMethodExportsSafety : WATModuleMethodExportsSafeV1 ir
  moduleFnReferencesSafety : WATModuleFnReferencesSafeV1 ir
  moduleLocalReferencesSafety : WATModuleLocalReferencesSafeV1 ir
  moduleMemorySafety : WATModuleMemorySafeV1 ir
  methodEmission :
    ValidatedReadOnlyMethodWATEmissionV1 ir methodIndex method watText
      methodText instructions

/-- A successful bounded lowering upgrades the existing exact production text
    graph to typed WAT emission. -/
theorem readOnlyMethodWATEmissionV1_of_methodWATEmissionV1
    (ir : IR)
    (methodIndex : Nat)
    (method : MethodIR)
    (watText methodText : String)
    (instructions : Array ReadOnlyWATInstructionV1)
    (hemission :
      MethodWATEmissionV1 ir methodIndex method watText methodText)
    (hlower :
      lowerReadOnlyWATOperationsV1 ir.registers ir.memory method.operations =
        some instructions) :
    ReadOnlyMethodWATEmissionV1 ir methodIndex method watText methodText
      instructions := by
  refine ⟨hemission, hlower, ?_⟩
  calc
    methodText =
        renderMethod ir
          (layoutPromiseStrings ir.memory (collectPromiseStrings ir)) method :=
      hemission.2.1
    _ = renderReadOnlyWATMethodV1 method.name method.tempCount instructions := by
      simp [renderMethod, hlower]

/-- A validated bounded emission gives a direct byte-for-byte decomposition of
    the complete production WAT around the exact typed method rendering. This
    is the generated method-fragment text identity boundary, not a parser or a
    statement about the surrounding module framing. -/
theorem validatedReadOnlyMethodWATEmissionV1_textIdentity
    (ir : IR)
    (methodIndex : Nat)
    (method : MethodIR)
    (watText methodText : String)
    (instructions : Array ReadOnlyWATInstructionV1)
    (hemission :
      ValidatedReadOnlyMethodWATEmissionV1 ir methodIndex method watText
        methodText instructions) :
    methodText =
        renderReadOnlyWATMethodV1 method.name method.tempCount instructions ∧
      ∃ before after,
        watText = before ++
          renderReadOnlyWATMethodV1 method.name method.tempCount instructions ++
            after := by
  rcases hemission.1 with ⟨hmethod, _, hmethodText⟩
  rcases hmethod with
    ⟨_, _, _, hmethodsText, outerBefore, outerAfter, hwatText⟩
  refine ⟨hmethodText, ?_⟩
  refine ⟨outerBefore ++ String.intercalate ""
      ((ir.methods.toList.take methodIndex).map
        (renderMethod ir
          (layoutPromiseStrings ir.memory (collectPromiseStrings ir)))),
    String.intercalate ""
        ((ir.methods.toList.drop (methodIndex + 1)).map
          (renderMethod ir
            (layoutPromiseStrings ir.memory (collectPromiseStrings ir)))) ++
      outerAfter, ?_⟩
  rw [hwatText, hmethodsText, hmethodText]
  simp [String.append_assoc]

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

private def renderAbiBeforeExports (plan : Plan) : String :=
  let fields := String.intercalate "," (plan.storage.fields.toList.map renderFieldJson)
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
    "  \"exports\": [\n    "

private def renderAbi (plan : Plan) : String :=
  let methods := #[plan.initializer] ++ plan.entries
  let exports := String.intercalate ",\n    " (methods.toList.map renderMethodJson)
  renderAbiBeforeExports plan ++ exports ++ "\n  ]\n}\n"

/-- Exact method-scoped graph of the sole production NEAR ABI renderer. The
    Plan lookup and rendered-list split retain the method's ordered export
    ownership; the complete exports text is then embedded in the exact ABI
    output. This is JSON text provenance, not parsing or consumer semantics. -/
def MethodABIEmissionV1
    (ir : IR)
    (methodIndex : Nat)
    (method : Method)
    (abiText methodText : String) : Prop :=
  let methods := (#[ir.sourcePlan.initializer] ++ ir.sourcePlan.entries).toList
  let renderedMethods := methods.map renderMethodJson
  let exportsText := String.intercalate ",\n    " renderedMethods
  (#[ir.sourcePlan.initializer] ++ ir.sourcePlan.entries)[methodIndex]? =
      some method ∧
  methodText = renderMethodJson method ∧
  abiText = renderAbi ir.sourcePlan ∧
  renderedMethods =
    (methods.take methodIndex).map renderMethodJson ++
      methodText :: (methods.drop (methodIndex + 1)).map renderMethodJson ∧
  ∃ before after, abiText = before ++ exportsText ++ after

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

/-- Exact successful graph of the sole production IR emitter. This is pure
    emission provenance: it neither exposes another renderer nor claims that
    the emitted WAT implements the IR or that a finalized Wasm executes it. -/
def IREmissionV1 (ir : IR) (files : Array OutputFile) : Prop :=
  emitFromIR ir = .ok files

private theorem irEmissionV1_eq_files
    (ir : IR) (files : Array OutputFile)
    (hemission : IREmissionV1 ir files) :
    files = #[
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
    ] := by
  cases hvalidate : validateIR ir with
  | error error =>
      simp [IREmissionV1, emitFromIR, hvalidate, Bind.bind, Except.bind] at hemission
  | ok _ =>
      simpa [IREmissionV1, emitFromIR, hvalidate, Bind.bind, Except.bind,
        Pure.pure, Except.pure] using hemission.symm

/-- An exact method lookup in a successfully emitted IR determines one
    production-rendered method fragment inside the exact WAT base file. The
    result remains text provenance only: no WAT parsing or execution is
    inferred from the fragment. -/
theorem irEmissionV1_methodWATEmissionV1
    (ir : IR)
    (files : Array OutputFile)
    (watFile : OutputFile)
    (methodIndex : Nat)
    (method : MethodIR)
    (hemission : IREmissionV1 ir files)
    (hwatFile : files[0]? = some watFile)
    (hmethod : ir.methods[methodIndex]? = some method) :
    ∃ methodText,
      MethodWATEmissionV1 ir methodIndex method watFile.contents methodText := by
  have hfiles := irEmissionV1_eq_files ir files hemission
  have hwatFileEq : watFile = {
      path := s!"{ir.name}.wat"
      mediaType := "application/wasm-text"
      contents := renderWat ir
    } := by
    rw [hfiles] at hwatFile
    simpa using hwatFile.symm
  let promiseStr :=
    layoutPromiseStrings ir.memory (collectPromiseStrings ir)
  have hmethodList : ir.methods.toList[methodIndex]? = some method := by
    simpa using hmethod
  let methodBefore := String.intercalate "" <|
    (ir.methods.toList.take methodIndex).map (renderMethod ir promiseStr)
  let methodAfter := String.intercalate "" <|
    (ir.methods.toList.drop (methodIndex + 1)).map
      (renderMethod ir promiseStr)
  have hrenderedMethods :
      String.intercalate ""
          (ir.methods.toList.map (renderMethod ir promiseStr)) =
        methodBefore ++ renderMethod ir promiseStr method ++ methodAfter := by
    exact intercalateMapEmpty_split_of_getElem?_eq_some
      ir.methods.toList (renderMethod ir promiseStr) methodIndex method
      hmethodList
  refine ⟨renderMethod ir promiseStr method, hmethod, rfl, ?_, ?_, ?_⟩
  · rw [hwatFileEq]
  · exact hrenderedMethods
  refine ⟨renderWatBeforeMethods ir promiseStr, ")\n", ?_⟩
  rw [hwatFileEq]
  rfl

/-- An exact Plan-method lookup in a successfully emitted IR determines one
    production-rendered export fragment in the exact ABI base file. The result
    is ordered JSON text provenance only; it does not infer parsing, WAT/ABI
    consistency, or target behavior. -/
theorem irEmissionV1_methodABIEmissionV1
    (ir : IR)
    (files : Array OutputFile)
    (abiFile : OutputFile)
    (methodIndex : Nat)
    (method : Method)
    (hemission : IREmissionV1 ir files)
    (habiFile : files[1]? = some abiFile)
    (hmethod :
      (#[ir.sourcePlan.initializer] ++ ir.sourcePlan.entries)[methodIndex]? =
        some method) :
    ∃ methodText,
      MethodABIEmissionV1 ir methodIndex method abiFile.contents methodText := by
  have hfiles := irEmissionV1_eq_files ir files hemission
  have habiFileEq : abiFile = {
      path := s!"{ir.name}.near-abi.json"
      mediaType := "application/json"
      contents := renderAbi ir.sourcePlan
    } := by
    rw [hfiles] at habiFile
    simpa using habiFile.symm
  let methods :=
    (#[ir.sourcePlan.initializer] ++ ir.sourcePlan.entries).toList
  have hmethodCombinedList :
      (#[ir.sourcePlan.initializer] ++
        ir.sourcePlan.entries).toList[methodIndex]? = some method := by
    rw [Array.getElem?_toList]
    exact hmethod
  have hmethodList : methods[methodIndex]? = some method := by
    exact hmethodCombinedList
  rw [List.getElem?_eq_some_iff] at hmethodList
  obtain ⟨hindex, hvalue⟩ := hmethodList
  have hdrop := List.drop_eq_getElem_cons hindex
  rw [hvalue] at hdrop
  have hsplit := List.take_append_drop methodIndex methods
  rw [hdrop] at hsplit
  have hrenderedMethods :
      methods.map renderMethodJson =
        (methods.take methodIndex).map renderMethodJson ++
          renderMethodJson method ::
            (methods.drop (methodIndex + 1)).map renderMethodJson := by
    calc
      methods.map renderMethodJson =
          ((methods.take methodIndex ++
            method :: methods.drop (methodIndex + 1)).map
              renderMethodJson) := by
        exact congrArg (List.map renderMethodJson) hsplit.symm
      _ = (methods.take methodIndex).map renderMethodJson ++
          renderMethodJson method ::
            (methods.drop (methodIndex + 1)).map renderMethodJson := by
        simp
  refine ⟨renderMethodJson method, hmethod, rfl, ?_, ?_, ?_⟩
  · rw [habiFileEq]
  · exact hrenderedMethods
  refine ⟨renderAbiBeforeExports ir.sourcePlan, "\n  ]\n}\n", ?_⟩
  rw [habiFileEq]
  rfl

/-- Exact source-entry provenance across the two in-memory production base
    outputs. One Plan entry, its private-lowered IR row, and their shared name
    own the corresponding method-scoped WAT and ABI renderer graphs at the
    canonical combined index `entryIndex + 1` (initializer occupies index 0).
    This packages existing production graphs only: it does not parse either
    text, prove WAT/ABI consumer consistency, or describe target execution. -/
structure EntryBaseEmissionV1
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (entryIndex : Nat)
    (method : Method)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (watMethodText abiMethodText : String) : Prop where
  sourcePlan : ir.sourcePlan = plan
  planIRLowering : PlanIRLoweringV1 plan ir
  irEmission : IREmissionV1 ir files
  watFileLookup : files[0]? = some watFile
  abiFileLookup : files[1]? = some abiFile
  planEntryLookup : plan.entries[entryIndex]? = some method
  irMethodLookup : ir.methods[entryIndex + 1]? = some methodIR
  methodIRLowering : MethodIRLoweringV1 plan ir.keys method methodIR
  methodName : methodIR.name = method.name
  watMethodEmission :
    MethodWATEmissionV1 ir (entryIndex + 1) methodIR
      watFile.contents watMethodText
  abiMethodEmission :
    MethodABIEmissionV1 ir (entryIndex + 1) method
      abiFile.contents abiMethodText

/-- A successful production Plan→IR graph and emission graph close one exact
    entry across both ordered base files. The theorem reuses the private-backed
    lowering and renderer relations; it does not inspect or duplicate emitted
    text. -/
theorem irEmissionV1_entryBaseEmissionV1
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (entryIndex : Nat)
    (method : Method)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (hplanIR : PlanIRLoweringV1 plan ir)
    (hemission : IREmissionV1 ir files)
    (hwatFile : files[0]? = some watFile)
    (habiFile : files[1]? = some abiFile)
    (hentry : plan.entries[entryIndex]? = some method)
    (hmethodIR : ir.methods[entryIndex + 1]? = some methodIR) :
    ∃ watMethodText abiMethodText,
      EntryBaseEmissionV1 plan ir files entryIndex method methodIR
        watFile abiFile watMethodText abiMethodText := by
  have hsourcePlan := planIRLoweringV1_sourcePlan plan ir hplanIR
  have hmethodIRLowering :=
    planIRLoweringV1_entry_lookup_eq_some plan ir entryIndex method methodIR
      hplanIR hentry hmethodIR
  have hmethodName := methodIRLoweringV1_name plan ir.keys method methodIR
    hmethodIRLowering
  obtain ⟨watMethodText, hwatMethodEmission⟩ :=
    irEmissionV1_methodWATEmissionV1 ir files watFile (entryIndex + 1)
      methodIR hemission hwatFile hmethodIR
  have habiMethodLookup :
      (#[ir.sourcePlan.initializer] ++
        ir.sourcePlan.entries)[entryIndex + 1]? = some method := by
    rw [hsourcePlan]
    rw [Array.getElem?_append_right (by simp)]
    simpa using hentry
  obtain ⟨abiMethodText, habiMethodEmission⟩ :=
    irEmissionV1_methodABIEmissionV1 ir files abiFile (entryIndex + 1)
      method hemission habiFile habiMethodLookup
  exact ⟨watMethodText, abiMethodText, {
    sourcePlan := hsourcePlan
    planIRLowering := hplanIR
    irEmission := hemission
    watFileLookup := hwatFile
    abiFileLookup := habiFile
    planEntryLookup := hentry
    irMethodLookup := hmethodIR
    methodIRLowering := hmethodIRLowering
    methodName := hmethodName
    watMethodEmission := hwatMethodEmission
    abiMethodEmission := habiMethodEmission
  }⟩

/-- Exact initializer provenance across the two in-memory production base
    outputs. The initializer occupies canonical combined method index zero. -/
structure InitializerBaseEmissionV1
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (method : Method)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (watMethodText abiMethodText : String) : Prop where
  sourcePlan : ir.sourcePlan = plan
  planIRLowering : PlanIRLoweringV1 plan ir
  irEmission : IREmissionV1 ir files
  watFileLookup : files[0]? = some watFile
  abiFileLookup : files[1]? = some abiFile
  planInitializer : plan.initializer = method
  irMethodLookup : ir.methods[0]? = some methodIR
  methodIRLowering : MethodIRLoweringV1 plan ir.keys method methodIR
  methodName : methodIR.name = method.name
  watMethodEmission :
    MethodWATEmissionV1 ir 0 methodIR watFile.contents watMethodText
  abiMethodEmission :
    MethodABIEmissionV1 ir 0 method abiFile.contents abiMethodText

/-- Production Plan→IR and emission graphs close the initializer across both
    ordered base files without another lowering or renderer. -/
theorem irEmissionV1_initializerBaseEmissionV1
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (method : Method)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (hplanIR : PlanIRLoweringV1 plan ir)
    (hemission : IREmissionV1 ir files)
    (hwatFile : files[0]? = some watFile)
    (habiFile : files[1]? = some abiFile)
    (hinitializer : plan.initializer = method)
    (hmethodIR : ir.methods[0]? = some methodIR) :
    ∃ watMethodText abiMethodText,
      InitializerBaseEmissionV1 plan ir files method methodIR watFile abiFile
        watMethodText abiMethodText := by
  have hsourcePlan := planIRLoweringV1_sourcePlan plan ir hplanIR
  have hmethodIRLowering :=
    planIRLoweringV1_initializer_lookup_eq_some plan ir method methodIR hplanIR
      hinitializer hmethodIR
  have hmethodName := methodIRLoweringV1_name plan ir.keys method methodIR
    hmethodIRLowering
  obtain ⟨watMethodText, hwatMethodEmission⟩ :=
    irEmissionV1_methodWATEmissionV1 ir files watFile 0 methodIR hemission
      hwatFile hmethodIR
  have habiMethodLookup :
      (#[ir.sourcePlan.initializer] ++ ir.sourcePlan.entries)[0]? = some method := by
    rw [Array.getElem?_append_left (by simp)]
    simpa [hsourcePlan] using congrArg some hinitializer
  obtain ⟨abiMethodText, habiMethodEmission⟩ :=
    irEmissionV1_methodABIEmissionV1 ir files abiFile 0 method hemission
      habiFile habiMethodLookup
  exact ⟨watMethodText, abiMethodText, {
    sourcePlan := hsourcePlan
    planIRLowering := hplanIR
    irEmission := hemission
    watFileLookup := hwatFile
    abiFileLookup := habiFile
    planInitializer := hinitializer
    irMethodLookup := hmethodIR
    methodIRLowering := hmethodIRLowering
    methodName := hmethodName
    watMethodEmission := hwatMethodEmission
    abiMethodEmission := habiMethodEmission
  }⟩

/-- Successful production emission determines one exact ordered base-file
    array, including both content strings. -/
theorem irEmissionV1_unique
    (ir : IR) (left right : Array OutputFile)
    (hleft : IREmissionV1 ir left)
    (hright : IREmissionV1 ir right) :
    left = right := by
  exact Except.ok.inj (hleft.symm.trans hright)

/-- Emission success retains the production IR validation gate. -/
theorem irEmissionV1_validateIR
    (ir : IR) (files : Array OutputFile)
    (hemission : IREmissionV1 ir files) :
    validateIR ir = .ok () := by
  cases hvalidate : validateIR ir with
  | error error =>
      simp [IREmissionV1, emitFromIR, hvalidate, Bind.bind, Except.bind] at hemission
  | ok unit =>
      cases unit
      rfl

/-- Successful sole production emission plus one validated bounded method
    closes the validated generated-module relation without another renderer. -/
theorem validatedReadOnlyWATModuleEmissionV1_of_irEmissionV1
    (ir : IR)
    (files : Array OutputFile)
    (methodIndex : Nat)
    (method : MethodIR)
    (watText methodText : String)
    (instructions : Array ReadOnlyWATInstructionV1)
    (hirEmission : IREmissionV1 ir files)
    (hmethodEmission :
      ValidatedReadOnlyMethodWATEmissionV1 ir methodIndex method watText
        methodText instructions) :
    ValidatedReadOnlyWATModuleEmissionV1 ir methodIndex method watText
      methodText instructions := by
  exact {
    moduleEmission :=
      methodWATEmissionV1_watModuleEmissionV1 ir methodIndex method watText
        methodText hmethodEmission.1.1
    irValidation := irEmissionV1_validateIR ir files hirEmission
    moduleHostImportsSafety := validateIR_watModuleHostImportsSafeV1 ir <|
      irEmissionV1_validateIR ir files hirEmission
    moduleMethodExportsSafety := validateIR_watModuleMethodExportsSafeV1 ir <|
      irEmissionV1_validateIR ir files hirEmission
    moduleFnReferencesSafety := validateIR_watModuleFnReferencesSafeV1 ir <|
      irEmissionV1_validateIR ir files hirEmission
    moduleLocalReferencesSafety :=
      validateIR_watModuleLocalReferencesSafeV1 ir <|
        irEmissionV1_validateIR ir files hirEmission
    moduleMemorySafety := validateIR_watModuleMemorySafeV1 ir <|
      irEmissionV1_validateIR ir files hirEmission
    methodEmission := hmethodEmission
  }

/-- Derived public envelope of the private-backed emission graph. Content
    strings remain existential so the private WAT/ABI renderers are not exposed
    or duplicated; `IREmissionV1` still binds their exact values. -/
theorem irEmissionV1_output_shape
    (ir : IR) (files : Array OutputFile)
    (hemission : IREmissionV1 ir files) :
    ∃ watText abiJson,
      files = #[
        {
          path := s!"{ir.name}.wat"
          mediaType := "application/wasm-text"
          contents := watText
        },
        {
          path := s!"{ir.name}.near-abi.json"
          mediaType := "application/json"
          contents := abiJson
        }
      ] := by
  cases hvalidate : validateIR ir with
  | error error =>
      simp [IREmissionV1, emitFromIR, hvalidate, Bind.bind, Except.bind] at hemission
  | ok unit =>
      refine ⟨renderWat ir, renderAbi ir.sourcePlan, ?_⟩
      simpa [IREmissionV1, emitFromIR, hvalidate, Bind.bind, Except.bind,
        Pure.pure, Except.pure] using hemission.symm

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

/-- Every successful capability-gated IR result comes from the exact production
    Plan materializer and private validated Plan→IR lowering. -/
theorem irFromCapability_eq_ok_graphsV1
    (capability : ResolvedEngineeringBuildV1) (ir : IR)
    (hir : irFromCapability capability = .ok ir) :
    ∃ plan,
      materializePlanFromCapabilityV1 capability = .ok plan ∧
      PlanIRLoweringV1 plan ir := by
  cases hplan : materializePlanFromCapabilityV1 capability with
  | error error =>
      simp [irFromCapability, hplan, Bind.bind, Except.bind] at hir
  | ok plan =>
      refine ⟨plan, rfl, ?_⟩
      cases hvalidate : validatePlan plan with
      | error error =>
          simp [irFromCapability, hplan, hvalidate, Bind.bind, Except.bind] at hir
      | ok _ =>
          simpa [irFromCapability, hplan, hvalidate, PlanIRLoweringV1,
            Bind.bind, Except.bind] using hir

/-- Exact capability-scoped canonical-WAT consumer graph. The candidate text
    must equal the sole private production renderer for the same validated
    Plan→IR graph. This is re-render identity, not textual WAT parsing,
    execution semantics, or a claim about `wat2wasm`. -/
def CapabilityCanonicalWATConsumptionV1
    (capability : ResolvedEngineeringBuildV1)
    (watText : String) : Prop :=
  ∃ plan ir,
    materializePlanFromCapabilityV1 capability = .ok plan ∧
    irFromCapability capability = .ok ir ∧
    PlanIRLoweringV1 plan ir ∧
    WATModuleEmissionV1 ir watText

/-- Fail-closed consumer for a candidate complete WAT module at the public
    capability boundary. It reuses the sole production lowering and renderer;
    it does not recognize arbitrary WAT or construct a second representation. -/
def validateCanonicalWATFromCapabilityV1
    (capability : ResolvedEngineeringBuildV1)
    (watText : String) : CompileResult Unit := do
  let ir ← irFromCapability capability
  if watText = renderWat ir then
    pure ()
  else
    throw <| .planInvariant .near
      "candidate WAT diverges from the sole capability-derived renderer"

/-- Successful canonical-WAT consumption exposes the exact validated
    capability→Plan→IR→text graph checked by the kernel. -/
theorem validateCanonicalWATFromCapabilityV1_eq_ok_graphsV1
    (capability : ResolvedEngineeringBuildV1)
    (watText : String)
    (hvalidate :
      validateCanonicalWATFromCapabilityV1 capability watText = .ok ()) :
    CapabilityCanonicalWATConsumptionV1 capability watText := by
  cases hir : irFromCapability capability with
  | error error =>
      simp [validateCanonicalWATFromCapabilityV1, hir, Bind.bind,
        Except.bind] at hvalidate
  | ok ir =>
      obtain ⟨plan, hplan, hlowering⟩ :=
        irFromCapability_eq_ok_graphsV1 capability ir hir
      by_cases hwat : watText = renderWat ir
      · refine ⟨plan, ir, hplan, hir, hlowering, ?_⟩
        simpa [WATModuleEmissionV1, renderWat] using hwat
      · simp [validateCanonicalWATFromCapabilityV1, hir, hwat, Bind.bind,
          Except.bind] at hvalidate

/-- Capability-gated public materialize entry (S6). -/
def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCapability capability
  emitFromIR ir

/-- Every successful capability-gated NEAR base build comes from one exact
    production Plan, the private validated Plan→IR lowering, and the sole
    private IR emitter. This stops at in-memory WAT/ABI content strings; it does
    not cover staging writes, `wat2wasm`, finalized Wasm, or execution. -/
theorem buildFromCapability_eq_ok_graphsV1
    (capability : ResolvedEngineeringBuildV1)
    (files : Array OutputFile)
    (hbuild : buildFromCapability capability = .ok files) :
    ∃ plan ir,
      materializePlanFromCapabilityV1 capability = .ok plan ∧
      irFromCapability capability = .ok ir ∧
      PlanIRLoweringV1 plan ir ∧
      IREmissionV1 ir files := by
  cases hir : irFromCapability capability with
  | error error =>
      simp [buildFromCapability, hir, Bind.bind, Except.bind] at hbuild
  | ok ir =>
      obtain ⟨plan, hplan, hlowering⟩ :=
        irFromCapability_eq_ok_graphsV1 capability ir hir
      refine ⟨plan, ir, hplan, rfl, hlowering, ?_⟩
      simpa [buildFromCapability, hir, IREmissionV1, Bind.bind,
        Except.bind] using hbuild

end ProofForgeV2.Targets.Near
