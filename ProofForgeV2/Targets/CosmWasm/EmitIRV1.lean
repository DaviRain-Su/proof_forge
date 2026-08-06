import ProofForgeV2.Targets.CosmWasm.ValidatePlanV1

/-!
# CosmWasm EmitIRV1 — Plan → IR → WAT emission

CosmWasm-owned host-call recipe IR with Region/JSON entry ABI:
* imports: `env.db_read` / `env.db_write` / `env.db_remove` / `env.abort`
* exports: `allocate` / `deallocate` / `interface_version_8` /
  `instantiate` / `execute` / `query`
* memory: exactly one linear memory, min=1, no maximum
* Region = 12-byte `{offset:u32, capacity:u32, length:u32}`
* entry JSON subset: flat instantiate params; execute/query
  `{"method":{...params...}}` with decimal integer fields
* results: `ContractResult` JSON (`ok` Response with attributes + messages, or `error`)
* emit → Response attributes; schedule → Response `messages: [SubMsg]` with
  `reply_on: "never"`; `WasmMsg::Execute.msg` is cosmwasm-std **Binary**
  (base64-encoded UTF-8 JSON `{"<method>":{"a0":N,...}}`); revert →
  `{"error":...}` / `abort`

CW-4 schedule notes (wasmd ≥0.54 `DispatchSubmessages` + cosmwasm-std
`ReplyOn::Never`): same-tx SubMsg savepoint; no reply callback; submsg failure
propagates and fails the parent tx (not parent-continues). `contract_addr` is
a static QN stub, not bech32. Binary msg uses deterministic table-lookup
base64 (`$pf_base64_encode`, no host/lib dependency). Not wasmd runtime /
cosmwasm-check acceptance (A2). Not formal D4.
-/

namespace ProofForgeV2.Targets.CosmWasm

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

inductive Operation where
  | requireLayoutAbsent (marker : KeyRegion)
  | requireLayout (marker : KeyRegion) (value : UInt64)
  | zeroState (field : KeyRegion)
  | literal (destination : Nat) (value : UInt64)
  /-- B-CTX-OPEN: load pre-parsed env.block.time.seconds() into a temp.
      Entry points fill global `$pf_block_time_secs` from Env JSON `"time"`
      (nanoseconds string ÷ 10^9 truncating) before calling method bodies. -/
  | blockTimeSeconds (destination : Nat)
  /-- ADR-0031 S1: load pre-parsed MessageInfo.sender Principal length leaf
      (global `$pf_caller_len`) filled at execute/instantiate before method
      bodies. View/query never loads caller (Plan FC). -/
  | callerPrincipalLen (destination : Nat)
  /-- ADR-0031 S1: load one LE body word of context.caller Principal
      (global `$pf_caller_w{i}`, `wordIndex ∈ 0..7`). -/
  | callerPrincipalWord (wordIndex destination : Nat)
  | loadParam (destination inputOffset : Nat)
  /-- Narrow ABI param copy (`bitWidth ∈ {8,16,32}`); params already
      range-checked at JSON entry (see `renderParamRangeGuard`). -/
  | narrowLoadParam (bitWidth destination inputOffset : Nat)
  | loadState (destination : Nat) (field : KeyRegion)
  /-- Narrow ABI state load: 8-byte Region load + high-bit-zero guard. -/
  | narrowLoadState (bitWidth destination : Nat) (field : KeyRegion)
  | checkedAdd (destination lhs rhs : Nat)
  | checkedSub (destination lhs rhs : Nat)
  | checkedMul (destination lhs rhs : Nat)
  | checkedDiv (destination lhs rhs : Nat)
  | checkedMod (destination lhs rhs : Nat)
  | signedCheckedAdd (destination lhs rhs : Nat)
  | signedCheckedSub (destination lhs rhs : Nat)
  | signedCheckedMul (destination lhs rhs : Nat)
  | signedCheckedDiv (destination lhs rhs : Nat)
  | signedCheckedMod (destination lhs rhs : Nat)
  | signedCompare (destination lhs rhs : Nat) (op : ComparisonOp)
  | checkedNeg (destination source : Nat)
  | sar (destination lhs rhs : Nat)
  | storeState (field : KeyRegion) (value : Nat)
  | setLayout (marker : KeyRegion) (value : UInt64)
  | setReturnData (value : Nat)
  /-- B-RET-ABI: multi-leaf return. Each temp is one UInt64/Int64 word;
  packed as a JSON array of decimals into the execute result attribute
  (or query `ok` string), matching the existing scalar decimal JSON ABI. -/
  | setReturnDataMulti (values : Array Nat)
  | compare (destination lhs rhs : Nat) (op : ComparisonOp)
  | assert (condition : Nat)
  | emitEvent (eventIndex : Nat) (args : Array Nat)
  | revertError (errorIndex : Nat) (args : Array Nat)
  /-- Schedule → Response SubMsg (`reply_on: never`, `id: 0`, WasmMsg::Execute).
      `receiver` is the static QN stub used as `contract_addr` (not bech32).
      `method` is the execute-message object key. `args` are i64 temps encoded
      as decimal JSON fields `a0`.. in source order; the execute `msg` field is
      cosmwasm-std Binary = base64(UTF-8 of `{"method":{"a0":N,...}}`). -/
  | promiseAccount (receiver : String) (method : String) (args : Array Nat)
  /-- ADR-0029 C1: exact one-coin info.funds check (frozen denom + amount temp). -/
  | nativeDeposit (amount : Nat)
  /-- ADR-0029 C1: BankMsg::Send SubMsg (reply_on=never). dstLen + 8 body words. -/
  | nativeTransfer (dstLen : Nat) (dstBodyWords : Array Nat) (amount : Nat)
  /-- ADR-0030 E1-CW: WasmMsg::Execute SubMsg (reply_on=never) targeting the
      CW20 contract at `mint` with `{"transfer":{"recipient":dst,"amount":N}}`.
      mintLen + 8 mint body words + dstLen + 8 dst body words + amount temp. -/
  | tokenTransfer (mintLen : Nat) (mintBodyWords : Array Nat)
      (dstLen : Nat) (dstBodyWords : Array Nat) (amount : Nat)
  /-- ADR-0030 E2-4-CW: `pf.assets.native.balanceOfSelf()` — read-only
      `query_chain` bank balance of `env.contract.address` (frozen `stake`
      denom); result `.amount` parsed as UInt64. Value-producing temp. -/
  | nativeVaultBalance (destination : Nat)
  /-- ADR-0030 E2-4-CW: `pf.assets.token.balanceOfSelf(mint)` — read-only
      `query_chain` CW20 smart-query `{"balance":{"address":<self>}}` at
      `mint`; `BalanceResponse.balance` (Uint128 decimal) parsed as UInt64
      (overflow traps). `resultTemp` binds the returned UInt64 word. -/
  | tokenVaultBalance (mintLen : Nat) (mintBodyWords : Array Nat)
      (resultTemp : Nat)
  /-- ADR-0029 C1: require info.funds == [] (non-deposit mutate/init). -/
  | requireFundsEmpty
  | returnNone
  | ifRegion (condition : Nat) (thenOps elseOps : Array Operation)
  | switchRegion (scrutinee : Nat) (cases : Array (UInt64 × Array Operation))
      (defaultOps : Array Operation)
  | forRegion (varTemp : Nat) (initial : Nat) (counterTemp : Nat)
      (maxIterations : Nat)
      (condOps : Array Operation) (condition : Nat)
      (bodyOps : Array Operation)
      (updateOps : Array Operation) (updateValue : Nat)
  | callFn (fnIndex : Nat) (destination : Nat) (args : Array Nat)
  | returnValue (value : Nat)
  | bitAnd (destination lhs rhs : Nat)
  | bitOr (destination lhs rhs : Nat)
  | bitXor (destination lhs rhs : Nat)
  | shl (destination lhs rhs : Nat)
  | shr (destination lhs rhs : Nat)
  | bitNot (destination source : Nat)
  /-- Narrow body checked arithmetic (`bitWidth ∈ {8,16,32}`); high-bit guards. -/
  | narrowCheckedAdd (bitWidth destination lhs rhs : Nat)
  | narrowCheckedSub (bitWidth destination lhs rhs : Nat)
  | narrowCheckedMul (bitWidth destination lhs rhs : Nat)
  | narrowCheckedDiv (bitWidth destination lhs rhs : Nat)
  | narrowCheckedMod (bitWidth destination lhs rhs : Nat)
  | narrowBitAnd (bitWidth destination lhs rhs : Nat)
  | narrowBitOr (bitWidth destination lhs rhs : Nat)
  | narrowBitXor (bitWidth destination lhs rhs : Nat)
  | narrowBitNot (bitWidth destination source : Nat)
  | narrowShl (bitWidth destination lhs rhs : Nat)
  | narrowShr (bitWidth destination lhs rhs : Nat)
  | boolNot (destination source : Nat)
  | boolAnd (destination lhs rhs : Nat)
  | boolOr (destination lhs rhs : Nat)
  deriving BEq, Inhabited, Repr

structure MethodIR where
  name : String
  params : Array Param
  mode : MethodMode
  resultKind : MethodResultKind
  depositPolicy : DepositPolicy := .requireZero
  tempCount : Nat
  operations : Array Operation
  deriving BEq, Inhabited, Repr

structure FnIR where
  name : String
  paramCount : Nat
  resultIsBool : Bool
  tempCount : Nat
  operations : Array Operation
  deriving BEq, Inhabited, Repr

/-- Typed CosmWasm host-call/Wasm recipe.
    Private `mk`: public Plan→IR construction is capability-gated only. -/
structure IR where
  private mk ::
  sourcePlan : Plan
  name : String
  imports : Array HostImport
  keys : Array KeyRegion
  memory : MemoryLayout
  methods : Array MethodIR
  fns : Array FnIR
  deriving BEq, Repr

private def align8 (value : Nat) : Nat :=
  ((value + 7) / 8) * 8

/-- Pack key bytes contiguously from offset 64 (leave low addresses for
    allocator metadata / small scratch). Each KeyRegion.offset points at the
    UTF-8 key bytes; Regions for db_* are built at runtime over these bytes. -/
private def makeKeyRegions (plan : Plan) : Array KeyRegion := Id.run do
  let mut regions : Array KeyRegion := #[]
  let mut offset := 64
  let markerLength := plan.storage.markerKey.toUTF8.size
  regions := regions.push { key := plan.storage.markerKey, offset, length := markerLength }
  offset := offset + markerLength
  for field in plan.storage.fields do
    let length := field.key.toUTF8.size
    regions := regions.push { key := field.key, offset, length }
    offset := offset + length
  return regions

/-- CosmWasm memory: one page min, no maximum (exported). Static key data in low
    memory; bump heap starts at 4096; JSON/result scratch after keys.
    Layout: [scratch 1536 | attr 512 | msg 1536 | value cell …]. -/
private def makeMemoryLayout (plan : Plan) (keys : Array KeyRegion) : MemoryLayout :=
  let keysEnd := keys.foldl (fun current key => max current (key.offset + key.length)) 64
  let scratchOffset := align8 (max keysEnd 256)
  {
    minPages := plan.resourceLimits.wasmMemoryPages
    inputOffset := scratchOffset          -- reused as JSON/result scratch base
    inputCapacity := 1536
    depositOffset := scratchOffset + 1536 -- attribute buffer base (512 bytes)
    -- value cell sits after attribute (512) + messages (1536) buffers
    valueOffset := scratchOffset + 1536 + 512 + 1536
  }

/-- Messages buffer base: immediately after the 512-byte attribute buffer. -/
private def msgBufferBase (memory : MemoryLayout) : Nat :=
  memory.depositOffset + 512

private structure LoweredExpr where
  operations : Array Operation
  value : Nat
  next : Nat
  deriving Inhabited

private def fieldRegion (keys : Array KeyRegion) (fieldIndex : Nat) : KeyRegion :=
  keys[fieldIndex + 1]!

private partial def lowerExpr (keys : Array KeyRegion) (next : Nat)
    (paramAsTemp : Bool) (localEnv : Array (Nat × Nat)) : Expr → LoweredExpr
  | .literal value =>
      { operations := #[.literal next value], value := next, next := next + 1 }
  | .bigLiteral _ value =>
      -- Multiword FC at plan; defensive: truncate to low 64.
      { operations := #[.literal next (UInt64.ofNat value)], value := next, next := next + 1 }
  | .blockTimeSeconds =>
      { operations := #[.blockTimeSeconds next], value := next, next := next + 1 }
  | .nativeVaultBalance =>
      { operations := #[.nativeVaultBalance next], value := next, next := next + 1 }
  | .callerPrincipalLen =>
      { operations := #[.callerPrincipalLen next], value := next, next := next + 1 }
  | .callerPrincipalWord wordIndex =>
      { operations := #[.callerPrincipalWord wordIndex next], value := next, next := next + 1 }
  | .param inputOffset =>
      if paramAsTemp then
        { operations := #[], value := inputOffset / 8, next := next }
      else
        { operations := #[.loadParam next inputOffset], value := next, next := next + 1 }
  | .narrowParam bitWidth inputOffset =>
      if paramAsTemp then
        { operations := #[], value := inputOffset / 8, next := next }
      else
        { operations := #[.narrowLoadParam bitWidth next inputOffset]
          value := next, next := next + 1 }
  | .localTemp index =>
      match localEnv.find? (fun p => p.1 == index) with
      | some (_, irTemp) =>
          { operations := #[], value := irTemp, next := next }
      | none =>
          { operations := #[.literal next 0], value := next, next := next + 1 }
  | .stateLoad fieldIndex =>
      {
        operations := #[.loadState next (fieldRegion keys fieldIndex)]
        value := next
        next := next + 1
      }
  | .narrowStateLoad bitWidth fieldIndex =>
      {
        operations := #[.narrowLoadState bitWidth next (fieldRegion keys fieldIndex)]
        value := next
        next := next + 1
      }
  | .checkedAdd lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.checkedAdd rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .checkedSub lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.checkedSub rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .checkedMul lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.checkedMul rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .checkedDiv lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.checkedDiv rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .checkedMod lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.checkedMod rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .signedCheckedAdd lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedAdd rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .signedCheckedSub lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedSub rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .signedCheckedMul lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedMul rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .signedCheckedDiv lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedDiv rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .signedCheckedMod lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedMod rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .signedCompare op lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.signedCompare rhs.next lhs.value rhs.value op]
        value := rhs.next, next := rhs.next + 1 }
  | .checkedNeg operand =>
      let op := lowerExpr keys next paramAsTemp localEnv operand
      { operations := op.operations ++ #[.checkedNeg op.next op.value]
        value := op.next, next := op.next + 1 }
  | .bitAnd lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.bitAnd rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .bitOr lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.bitOr rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .bitXor lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.bitXor rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .shl lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.shl rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .shr lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.shr rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .sar lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.sar rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .bitNot operand =>
      let op := lowerExpr keys next paramAsTemp localEnv operand
      { operations := op.operations ++ #[.bitNot op.next op.value]
        value := op.next, next := op.next + 1 }
  | .narrowCheckedAdd bitWidth lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedAdd bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .narrowCheckedSub bitWidth lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedSub bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .narrowCheckedMul bitWidth lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedMul bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .narrowCheckedDiv bitWidth lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedDiv bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .narrowCheckedMod bitWidth lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedMod bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .narrowBitAnd bitWidth lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.narrowBitAnd bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .narrowBitOr bitWidth lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.narrowBitOr bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .narrowBitXor bitWidth lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.narrowBitXor bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .narrowBitNot bitWidth operand =>
      let op := lowerExpr keys next paramAsTemp localEnv operand
      { operations := op.operations ++ #[.narrowBitNot bitWidth op.next op.value]
        value := op.next, next := op.next + 1 }
  | .narrowShl bitWidth lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.narrowShl bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .narrowShr bitWidth lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.narrowShr bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .boolNot operand =>
      let op := lowerExpr keys next paramAsTemp localEnv operand
      { operations := op.operations ++ #[.boolNot op.next op.value]
        value := op.next, next := op.next + 1 }
  | .boolAnd lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.boolAnd rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .boolOr lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.boolOr rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .compare op lhs rhs | .wideCompare _ op lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.compare rhs.next lhs.value rhs.value op]
        value := rhs.next, next := rhs.next + 1 }
  | .callFn fnIndex args =>
      Id.run do
        let mut ops : Array Operation := #[]
        let mut cur := next
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let lowered := lowerExpr keys cur paramAsTemp localEnv arg
          ops := ops ++ lowered.operations
          argTemps := argTemps.push lowered.value
          cur := lowered.next
        ops := ops.push (.callFn fnIndex cur argTemps)
        pure { operations := ops, value := cur, next := cur + 1 }

private partial def lowerBodyOps (keys : Array KeyRegion) (next : Nat)
    (body : Array Statement) (fnMode : Bool) (localEnv : Array (Nat × Nat))
    (_returnByteLen : Nat) : Array Operation × Nat := Id.run do
  let mut operations : Array Operation := #[]
  let mut next := next
  let mut localEnv := localEnv
  for stmt in body do
    match stmt with
    | .store op =>
        let value := lowerExpr keys next fnMode localEnv op.value
        operations := operations ++ value.operations
        operations := operations.push (.storeState (fieldRegion keys op.fieldIndex) value.value)
        next := value.next
    | .storeAtomic leaves =>
        -- Evaluate all leaf exprs first, then write (pre-store snapshot).
        let mut vals : Array (Nat × Nat) := #[]  -- (fieldIndex, temp)
        for leaf in leaves do
          let value := lowerExpr keys next fnMode localEnv leaf.value
          operations := operations ++ value.operations
          vals := vals.push (leaf.fieldIndex, value.value)
          next := value.next
        for (fieldIndex, temp) in vals do
          operations := operations.push (.storeState (fieldRegion keys fieldIndex) temp)
    | .returnValue value =>
        let value := lowerExpr keys next fnMode localEnv value
        operations := operations ++ value.operations
        if fnMode then
          operations := operations.push (.returnValue value.value)
        else
          operations := operations.push (.setReturnData value.value)
        next := value.next
    | .returnAggregate leaves _leafIsInt =>
        -- B-RET-ABI: lower each leaf expr, then one multi-word setReturnDataMulti.
        let mut temps : Array Nat := #[]
        for leaf in leaves do
          let value := lowerExpr keys next fnMode localEnv leaf
          operations := operations ++ value.operations
          temps := temps.push value.value
          next := value.next
        if fnMode then
          -- pureFn must not emit aggregate return (validated); fall closed.
          operations := operations.push (.returnValue (temps[0]?.getD 0))
        else
          operations := operations.push (.setReturnDataMulti temps)
    | .returnNone =>
        operations := operations.push .returnNone
    | .assert condition =>
        let value := lowerExpr keys next fnMode localEnv condition
        operations := operations ++ value.operations ++ #[.assert value.value]
        next := value.next
    | .emitEvent eventIndex args =>
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let value := lowerExpr keys next fnMode localEnv arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push (.emitEvent eventIndex argTemps)
    | .revertError errorIndex args =>
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let value := lowerExpr keys next fnMode localEnv arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push (.revertError errorIndex argTemps)
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
        operations := operations.push (.nativeDeposit value.value)
        next := value.next
    | .nativeTransfer dstLen dstBodyWords amount =>
        let lenL := lowerExpr keys next fnMode localEnv dstLen
        operations := operations ++ lenL.operations
        next := lenL.next
        let mut wordTemps : Array Nat := #[]
        for w in dstBodyWords do
          let wl := lowerExpr keys next fnMode localEnv w
          operations := operations ++ wl.operations
          wordTemps := wordTemps.push wl.value
          next := wl.next
        let amountL := lowerExpr keys next fnMode localEnv amount
        operations := operations ++ amountL.operations
        operations := operations.push
          (.nativeTransfer lenL.value wordTemps amountL.value)
        next := amountL.next
    | .tokenTransfer mintLen mintBodyWords dstLen dstBodyWords amount =>
        let mintLenL := lowerExpr keys next fnMode localEnv mintLen
        operations := operations ++ mintLenL.operations
        next := mintLenL.next
        let mut mintWordTemps : Array Nat := #[]
        for w in mintBodyWords do
          let wl := lowerExpr keys next fnMode localEnv w
          operations := operations ++ wl.operations
          mintWordTemps := mintWordTemps.push wl.value
          next := wl.next
        let dstLenL := lowerExpr keys next fnMode localEnv dstLen
        operations := operations ++ dstLenL.operations
        next := dstLenL.next
        let mut dstWordTemps : Array Nat := #[]
        for w in dstBodyWords do
          let wl := lowerExpr keys next fnMode localEnv w
          operations := operations ++ wl.operations
          dstWordTemps := dstWordTemps.push wl.value
          next := wl.next
        let amountL := lowerExpr keys next fnMode localEnv amount
        operations := operations ++ amountL.operations
        operations := operations.push
          (.tokenTransfer mintLenL.value mintWordTemps dstLenL.value dstWordTemps
            amountL.value)
        next := amountL.next
    | .tokenVaultBalance mintLen mintBodyWords resultTemp =>
        -- Plan `resultTemp` is a Semantic ValueId (like forLoop `varTemp`).
        -- Allocate a fresh IR temp for the query result and bind it into
        -- localEnv so subsequent `.localTemp resultTemp` (e.g. return) resolve
        -- to the real balance — not the unmapped-localTemp fallback of
        -- literal 0.
        let mintLenL := lowerExpr keys next fnMode localEnv mintLen
        operations := operations ++ mintLenL.operations
        next := mintLenL.next
        let mut mintWordTemps : Array Nat := #[]
        for w in mintBodyWords do
          let wl := lowerExpr keys next fnMode localEnv w
          operations := operations ++ wl.operations
          mintWordTemps := mintWordTemps.push wl.value
          next := wl.next
        let irDest := next
        next := next + 1
        operations := operations.push
          (.tokenVaultBalance mintLenL.value mintWordTemps irDest)
        localEnv := localEnv.push (resultTemp, irDest)
    | .ifThenElse condition thenBody elseBody =>
        let value := lowerExpr keys next fnMode localEnv condition
        operations := operations ++ value.operations
        let (thenOps, next1) := lowerBodyOps keys value.next thenBody fnMode localEnv _returnByteLen
        let (elseOps, next2) := lowerBodyOps keys next1 elseBody fnMode localEnv _returnByteLen
        operations := operations.push (.ifRegion value.value thenOps elseOps)
        next := next2
    | .switchOn scrutinee cases defaultBody =>
        let value := lowerExpr keys next fnMode localEnv scrutinee
        operations := operations ++ value.operations
        let mut caseOps : Array (UInt64 × Array Operation) := #[]
        let mut nextC := value.next
        for (caseValue, caseBody) in cases do
          let (ops, next1) := lowerBodyOps keys nextC caseBody fnMode localEnv _returnByteLen
          caseOps := caseOps.push (caseValue, ops)
          nextC := next1
        let (defaultOps, nextD) := lowerBodyOps keys nextC defaultBody fnMode localEnv _returnByteLen
        operations := operations.push (.switchRegion value.value caseOps defaultOps)
        next := nextD
    | .forLoop varTemp initial condition update maxIterations body =>
        let initL := lowerExpr keys next fnMode localEnv initial
        operations := operations ++ initL.operations
        let irVar := initL.next
        let counterTemp := initL.next + 1
        next := initL.next + 2
        let localEnv' := localEnv.push (varTemp, irVar)
        let condL := lowerExpr keys next fnMode localEnv' condition
        let condOps := condL.operations
        let condTemp := condL.value
        next := condL.next
        let (bodyOps, nextB) := lowerBodyOps keys next body fnMode localEnv' _returnByteLen
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

private def lowerMethod (plan : Plan) (keys : Array KeyRegion)
    (method : Method) : MethodIR := Id.run do
  let marker := keys[0]!
  let mut operations : Array Operation := #[]
  if method.mode == .initialize then
    operations := operations.push (.requireLayoutAbsent marker)
    for index in [0:plan.storage.fields.size] do
      operations := operations.push (.zeroState (fieldRegion keys index))
  else
    operations := operations.push (.requireLayout marker plan.storage.markerValue)
  -- ADR-0029 C1: non-deposit mutate/init require empty funds prologue.
  -- Exact-native deposit check is emitted at the nativeDeposit statement.
  if (method.mode == .initialize || method.mode == .mutate) &&
      method.depositPolicy == .requireZero then
    operations := operations.push .requireFundsEmpty
  let body := if method.body.back? == some .returnNone then
    method.body.pop
  else
    method.body
  let (bodyOps, next) := lowerBodyOps keys 0 body false #[] 8
  operations := operations ++ bodyOps
  if method.mode == .initialize then
    operations := operations.push (.setLayout marker plan.storage.markerValue)
  return {
    name := method.name
    params := method.params
    mode := method.mode
    resultKind := method.resultKind
    depositPolicy := method.depositPolicy
    tempCount := next
    operations
  }

private def lowerFn (keys : Array KeyRegion) (fn : FnBinding) : FnIR :=
  let paramCount := fn.params.size
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

private partial def opIsMethodOnlyV1 : Operation → Bool
  | .requireLayoutAbsent _ | .requireLayout _ _
  | .zeroState _ | .loadState _ _ | .narrowLoadState _ _ _
  | .storeState _ _
  | .setLayout _ _ | .setReturnData _ | .setReturnDataMulti _
  | .loadParam _ _ | .narrowLoadParam _ _ _
  | .nativeVaultBalance _ | .tokenVaultBalance _ _ _
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

def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless ir.name == ir.sourcePlan.programName do
    throw <| .planInvariant .cosmwasm "typed CosmWasm IR identity is not bound to its source Plan"
  unless ir.imports == ir.sourcePlan.hostImports do
    throw <| .planInvariant .cosmwasm "typed CosmWasm IR host imports are not canonical"
  let expectedKeys := makeKeyRegions ir.sourcePlan
  unless ir.keys == expectedKeys do
    throw <| .planInvariant .cosmwasm "typed CosmWasm IR key regions are not bound to the Plan KV layout"
  let expectedMemory := makeMemoryLayout ir.sourcePlan expectedKeys
  unless ir.memory == expectedMemory &&
      ir.memory.minPages == ir.sourcePlan.resourceLimits.wasmMemoryPages do
    throw <| .planInvariant .cosmwasm "typed CosmWasm IR memory layout is not canonical"
  if ir.methods.size != ir.sourcePlan.entries.size + 1 then
    throw <| .planInvariant .cosmwasm "typed CosmWasm IR export count does not match its source Plan"
  if ir.fns.size != ir.sourcePlan.fns.size then
    throw <| .planInvariant .cosmwasm "typed CosmWasm IR pureFn count does not match its source Plan"
  for method in ir.methods do
    if method.tempCount > ir.sourcePlan.resourceLimits.maxMethodLocals then
      throw <| .planInvariant .cosmwasm
        s!"typed CosmWasm IR method '{method.name}' exceeds local limit {ir.sourcePlan.resourceLimits.maxMethodLocals}"
    if method.operations.any opIsFnReturnValueV1 then
      throw <| .planInvariant .cosmwasm
        s!"typed CosmWasm IR method '{method.name}' must not use pureFn returnValue ops"
  for fn in ir.fns do
    if fn.tempCount > ir.sourcePlan.resourceLimits.maxMethodLocals then
      throw <| .planInvariant .cosmwasm
        s!"typed CosmWasm IR pureFn '{fn.name}' exceeds local limit {ir.sourcePlan.resourceLimits.maxMethodLocals}"
    if fn.operations.any opIsMethodOnlyV1 then
      throw <| .planInvariant .cosmwasm
        s!"typed CosmWasm IR pureFn '{fn.name}' must not use method-only host ops"
  let expected := expectedMethods ir.sourcePlan expectedKeys
  unless ir.methods == expected do
    throw <| .planInvariant .cosmwasm
      "typed CosmWasm IR methods/operations are not the exact lowering of their source Plan"
  let expectedFnIR := expectedFns ir.sourcePlan expectedKeys
  unless ir.fns == expectedFnIR do
    throw <| .planInvariant .cosmwasm
      "typed CosmWasm IR pureFn operations are not the exact lowering of their source Plan"

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let keys := makeKeyRegions plan
  let memory := makeMemoryLayout plan keys
  let ir : IR := {
    sourcePlan := plan
    name := plan.programName
    imports := plan.hostImports
    keys
    memory
    methods := expectedMethods plan keys
    fns := expectedFns plan keys
  }
  validateIR ir
  return ir

/-- Replace methods on an existing IR (private `mk`; for validateIR characterization). -/
def withMethods (ir : IR) (methods : Array MethodIR) : IR :=
  { ir with methods }

def withFns (ir : IR) (fns : Array FnIR) : IR :=
  { ir with fns }

/-! ### WAT rendering (CosmWasm Region / JSON / db_*) -/

private def renderImport : HostImport → String
  | .dbRead =>
      "  (import \"env\" \"db_read\" (func $db_read (param i32) (result i32)))\n"
  | .dbWrite =>
      "  (import \"env\" \"db_write\" (func $db_write (param i32 i32)))\n"
  | .dbRemove =>
      "  (import \"env\" \"db_remove\" (func $db_remove (param i32)))\n"
  | .abort =>
      "  (import \"env\" \"abort\" (func $abort (param i32)))\n"
  | .queryChain =>
      "  (import \"env\" \"query_chain\" (func $query_chain (param i32) (result i32)))\n"

/-- Shared runtime helpers: bump allocate, Region builders, db load/store U64,
    JSON ok/error result builders, minimal JSON integer field scan. -/
private def renderRuntimeHelpers (memory : MemoryLayout) : String :=
  let heapInit := 4096
  let scratch := memory.inputOffset
  let attrBase := memory.depositOffset
  let msgBase := msgBufferBase memory
  let valueCell := memory.valueOffset
  -- Keep helpers compact but complete for Counter MVP + CW-4 SubMsg schedule.
  -- inner_len: scratch-side builder for Binary execute-msg JSON (pre-base64).
  s!"  (global $heap (mut i32) (i32.const {heapInit}))\n" ++
  s!"  (global $attr_len (mut i32) (i32.const 0))\n" ++
  s!"  (global $msg_len (mut i32) (i32.const 0))\n" ++
  s!"  (global $inner_len (mut i32) (i32.const 0))\n" ++
  s!"  (global $ret_kind (mut i32) (i32.const 0))\n" ++  -- 0=none 1=scalar 4=aggregate
  s!"  (global $ret_val (mut i64) (i64.const 0))\n" ++
  s!"  (global $ret_count (mut i32) (i32.const 0))\n" ++  -- B-RET-ABI leaf count (1..8)
  -- B-CTX-OPEN: whole-second block time from Env JSON (set at entry when used).
  s!"  (global $pf_block_time_secs (mut i64) (i64.const 0))\n" ++
  -- ADR-0030 E2-4-CW: Env Region ptr cached at entry for env-read queries.
  "  (global $pf_env_ptr (mut i32) (i32.const 0))\n" ++
  -- ADR-0029 C1: info region cached at entry for funds checks (deposit/empty).
  "  (global $info_off (mut i32) (i32.const 0))\n" ++
  "  (global $info_len (mut i32) (i32.const 0))\n" ++
  -- ADR-0031 S1: MessageInfo.sender Principal leaves (len + 8 LE body words).
  -- Filled by $pf_load_caller_principal at execute/instantiate only.
  "  (global $pf_caller_len (mut i64) (i64.const 0))\n" ++
  "  (global $pf_caller_w0 (mut i64) (i64.const 0))\n" ++
  "  (global $pf_caller_w1 (mut i64) (i64.const 0))\n" ++
  "  (global $pf_caller_w2 (mut i64) (i64.const 0))\n" ++
  "  (global $pf_caller_w3 (mut i64) (i64.const 0))\n" ++
  "  (global $pf_caller_w4 (mut i64) (i64.const 0))\n" ++
  "  (global $pf_caller_w5 (mut i64) (i64.const 0))\n" ++
  "  (global $pf_caller_w6 (mut i64) (i64.const 0))\n" ++
  "  (global $pf_caller_w7 (mut i64) (i64.const 0))\n" ++
  -- ret_leaves live at valueCell (8×i64 = 64B); capacity-guarded by ret_count≤8
  -- allocate(size) -> region_ptr: Region{offset=data, capacity=size, length=size}
  "  (func $pf_allocate (param $size i32) (result i32)\n" ++
  "    (local $region i32) (local $data i32) (local $h i32)\n" ++
  "    (local.set $h (global.get $heap))\n" ++
  "    (local.set $region (local.get $h))\n" ++
  "    (local.set $data (i32.add (local.get $h) (i32.const 16)))\n" ++
  "    (i32.store (local.get $region) (local.get $data))\n" ++
  "    (i32.store offset=4 (local.get $region) (local.get $size))\n" ++
  "    (i32.store offset=8 (local.get $region) (local.get $size))\n" ++
  "    (global.set $heap (i32.add (local.get $data) (i32.and (i32.add (local.get $size) (i32.const 7)) (i32.const -8))))\n" ++
  "    (local.get $region)\n" ++
  "  )\n" ++
  -- region over static key bytes (length fixed, no copy)
  "  (func $pf_key_region (param $off i32) (param $len i32) (result i32)\n" ++
  "    (local $region i32)\n" ++
  "    (local.set $region (global.get $heap))\n" ++
  "    (global.set $heap (i32.add (local.get $region) (i32.const 16)))\n" ++
  "    (i32.store (local.get $region) (local.get $off))\n" ++
  "    (i32.store offset=4 (local.get $region) (local.get $len))\n" ++
  "    (i32.store offset=8 (local.get $region) (local.get $len))\n" ++
  "    (local.get $region)\n" ++
  "  )\n" ++
  -- write u64 value into a fresh region
  "  (func $pf_u64_region (param $v i64) (result i32)\n" ++
  "    (local $region i32) (local $data i32)\n" ++
  "    (local.set $region (call $pf_allocate (i32.const 8)))\n" ++
  "    (local.set $data (i32.load (local.get $region)))\n" ++
  "    (i64.store (local.get $data) (local.get $v))\n" ++
  "    (local.get $region)\n" ++
  "  )\n" ++
  -- db_read key → u64 (trap if missing or wrong len)
  "  (func $pf_db_load_u64 (param $key_off i32) (param $key_len i32) (result i64)\n" ++
  "    (local $key_r i32) (local $val_r i32) (local $data i32) (local $len i32)\n" ++
  "    (local.set $key_r (call $pf_key_region (local.get $key_off) (local.get $key_len)))\n" ++
  "    (local.set $val_r (call $db_read (local.get $key_r)))\n" ++
  "    (if (i32.eqz (local.get $val_r)) (then unreachable))\n" ++
  "    (local.set $len (i32.load offset=8 (local.get $val_r)))\n" ++
  "    (if (i32.ne (local.get $len) (i32.const 8)) (then unreachable))\n" ++
  "    (local.set $data (i32.load (local.get $val_r)))\n" ++
  "    (i64.load (local.get $data))\n" ++
  "  )\n" ++
  -- db_write key ← u64
  "  (func $pf_db_store_u64 (param $key_off i32) (param $key_len i32) (param $v i64)\n" ++
  "    (local $key_r i32) (local $val_r i32)\n" ++
  "    (local.set $key_r (call $pf_key_region (local.get $key_off) (local.get $key_len)))\n" ++
  "    (local.set $val_r (call $pf_u64_region (local.get $v)))\n" ++
  "    (call $db_write (local.get $key_r) (local.get $val_r))\n" ++
  "  )\n" ++
  -- db_read presence (0/1)
  "  (func $pf_db_has (param $key_off i32) (param $key_len i32) (result i32)\n" ++
  "    (local $key_r i32) (local $val_r i32)\n" ++
  "    (local.set $key_r (call $pf_key_region (local.get $key_off) (local.get $key_len)))\n" ++
  "    (local.set $val_r (call $db_read (local.get $key_r)))\n" ++
  "    (i32.ne (local.get $val_r) (i32.const 0))\n" ++
  "  )\n" ++
  -- build error JSON region {"error":"<msg>"} and return it (for ContractResult::Err)
  "  (func $pf_error_result (param $msg_off i32) (param $msg_len i32) (result i32)\n" ++
  s!"    (local $region i32) (local $data i32) (local $i i32) (local $p i32)\n" ++
  s!"    (local.set $region (call $pf_allocate (i32.add (local.get $msg_len) (i32.const 16))))\n" ++
  s!"    (local.set $data (i32.load (local.get $region)))\n" ++
  -- {"error":"
  s!"    (i32.store8 (local.get $data) (i32.const 123))\n" ++
  s!"    (i32.store8 offset=1 (local.get $data) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=2 (local.get $data) (i32.const 101))\n" ++
  s!"    (i32.store8 offset=3 (local.get $data) (i32.const 114))\n" ++
  s!"    (i32.store8 offset=4 (local.get $data) (i32.const 114))\n" ++
  s!"    (i32.store8 offset=5 (local.get $data) (i32.const 111))\n" ++
  s!"    (i32.store8 offset=6 (local.get $data) (i32.const 114))\n" ++
  s!"    (i32.store8 offset=7 (local.get $data) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=8 (local.get $data) (i32.const 58))\n" ++
  s!"    (i32.store8 offset=9 (local.get $data) (i32.const 34))\n" ++
  s!"    (local.set $p (i32.add (local.get $data) (i32.const 10)))\n" ++
  s!"    (local.set $i (i32.const 0))\n" ++
  s!"    (block $copy_done\n" ++
  s!"      (loop $copy\n" ++
  s!"        (br_if $copy_done (i32.ge_u (local.get $i) (local.get $msg_len)))\n" ++
  s!"        (i32.store8 (i32.add (local.get $p) (local.get $i)) (i32.load8_u (i32.add (local.get $msg_off) (local.get $i))))\n" ++
  s!"        (local.set $i (i32.add (local.get $i) (i32.const 1)))\n" ++
  s!"        (br $copy)))\n" ++
  s!"    (i32.store8 (i32.add (local.get $p) (local.get $msg_len)) (i32.const 34))\n" ++
  s!"    (i32.store8 (i32.add (i32.add (local.get $p) (local.get $msg_len)) (i32.const 1)) (i32.const 125))\n" ++
  s!"    (i32.store offset=8 (local.get $region) (i32.add (local.get $msg_len) (i32.const 12)))\n" ++
  s!"    (local.get $region)\n" ++
  "  )\n" ++
  -- format unsigned decimal of i64 into scratch; returns length
  s!"  (func $pf_fmt_u64 (param $v i64) (param $dst i32) (result i32)\n" ++
  s!"    (local $tmp i64) (local $n i32) (local $i i32) (local $d i32)\n" ++
  s!"    (if (i64.eqz (local.get $v)) (then\n" ++
  s!"      (i32.store8 (local.get $dst) (i32.const 48))\n" ++
  s!"      (return (i32.const 1))))\n" ++
  s!"    (local.set $tmp (local.get $v))\n" ++
  s!"    (local.set $n (i32.const 0))\n" ++
  s!"    (block $done_count\n" ++
  s!"      (loop $count\n" ++
  s!"        (br_if $done_count (i64.eqz (local.get $tmp)))\n" ++
  s!"        (local.set $tmp (i64.div_u (local.get $tmp) (i64.const 10)))\n" ++
  s!"        (local.set $n (i32.add (local.get $n) (i32.const 1)))\n" ++
  s!"        (br $count)))\n" ++
  s!"    (local.set $tmp (local.get $v))\n" ++
  s!"    (local.set $i (local.get $n))\n" ++
  s!"    (block $done_write\n" ++
  s!"      (loop $write\n" ++
  s!"        (br_if $done_write (i32.eqz (local.get $i)))\n" ++
  s!"        (local.set $i (i32.sub (local.get $i) (i32.const 1)))\n" ++
  s!"        (local.set $d (i32.wrap_i64 (i64.rem_u (local.get $tmp) (i64.const 10))))\n" ++
  s!"        (i32.store8 (i32.add (local.get $dst) (local.get $i)) (i32.add (local.get $d) (i32.const 48)))\n" ++
  s!"        (local.set $tmp (i64.div_u (local.get $tmp) (i64.const 10)))\n" ++
  s!"        (br $write)))\n" ++
  s!"    (local.get $n)\n" ++
  "  )\n" ++
  -- ADR-0030 E2-4-CW: raw memcpy — copy (srcOff, srcLen) bytes to dstOff.
  -- Used by query-request builders (not the messages buffer).
  s!"  (func $pf_copy_bytes (param $dst i32) (param $src i32) (param $len i32)\n" ++
  s!"    (local $i i32)\n" ++
  s!"    (local.set $i (i32.const 0))\n" ++
  s!"    (block $done\n" ++
  s!"      (loop $copy\n" ++
  s!"        (br_if $done (i32.ge_u (local.get $i) (local.get $len)))\n" ++
  s!"        (i32.store8 (i32.add (local.get $dst) (local.get $i))\n" ++
  s!"          (i32.load8_u (i32.add (local.get $src) (local.get $i))))\n" ++
  s!"        (local.set $i (i32.add (local.get $i) (i32.const 1)))\n" ++
  s!"        (br $copy)))\n" ++
  "  )\n" ++
  -- ADR-0030 E2-4-CW: pack Principal leaves (len + 8 LE body words) into a
  -- contiguous heap buffer of the body bytes. Returns a Region ptr
  -- (offset=buffer, length=bodyLen). Used by tokenVaultBalance to rebuild the
  -- mint bech32 address from Principal wire-identity leaves.
  s!"  (func $pf_pack_addr (param $len i64) (param $w0 i64) (param $w1 i64) (param $w2 i64) (param $w3 i64) (param $w4 i64) (param $w5 i64) (param $w6 i64) (param $w7 i64) (result i32)\n" ++
  s!"    (local $region i32) (local $data i32) (local $bodyLen i32)\n" ++
  s!"    (local.set $bodyLen (i32.wrap_i64 (local.get $len)))\n" ++
  s!"    (if (i32.gt_u (local.get $bodyLen) (i32.const 64)) (then unreachable))\n" ++
  s!"    (if (i32.eqz (local.get $bodyLen)) (then unreachable))\n" ++
  s!"    (local.set $region (call $pf_allocate (i32.const 72)))\n" ++
  s!"    (local.set $data (i32.load (local.get $region)))\n" ++
  -- Principal leaves are 8 LE u64 words; writing each word little-endian into
  -- the contiguous buffer yields exactly the wire-identity byte sequence.
  s!"    (i64.store (local.get $data) (local.get $w0))\n" ++
  s!"    (i64.store offset=8 (local.get $data) (local.get $w1))\n" ++
  s!"    (i64.store offset=16 (local.get $data) (local.get $w2))\n" ++
  s!"    (i64.store offset=24 (local.get $data) (local.get $w3))\n" ++
  s!"    (i64.store offset=32 (local.get $data) (local.get $w4))\n" ++
  s!"    (i64.store offset=40 (local.get $data) (local.get $w5))\n" ++
  s!"    (i64.store offset=48 (local.get $data) (local.get $w6))\n" ++
  s!"    (i64.store offset=56 (local.get $data) (local.get $w7))\n" ++
  s!"    (i32.store offset=8 (local.get $region) (local.get $bodyLen))\n" ++
  s!"    (local.get $region)\n" ++
  "  )\n" ++
  -- ADR-0030 E2-4-CW: env.contract.address extraction from Env JSON.
  -- Finds `"contract":{"address":"` needle, copies the bech32 address bytes
  -- (until the closing `"`) into a fresh heap buffer. Returns region ptr
  -- (offset=buffer, length=addr-len). Traps if needle missing or addr empty.
  s!"  (func $pf_env_contract_addr (param $env_ptr i32) (result i32)\n" ++
  s!"    (local $off i32) (local $len i32) (local $idx i32) (local $p i32) (local $end i32) (local $c i32) (local $n i32) (local $region i32) (local $data i32)\n" ++
  s!"    (local.set $off (call $pf_region_off (local.get $env_ptr)))\n" ++
  s!"    (local.set $len (call $pf_region_len (local.get $env_ptr)))\n" ++
  s!"    (local.set $idx (call $pf_find (local.get $off) (local.get $len) (i32.const 3055) (i32.const 23)))\n" ++
  s!"    (if (i32.eq (local.get $idx) (i32.const -1)) (then unreachable))\n" ++
  s!"    (local.set $p (i32.add (i32.add (local.get $off) (local.get $idx)) (i32.const 23)))\n" ++
  s!"    (local.set $end (i32.add (local.get $off) (local.get $len)))\n" ++
  s!"    (local.set $region (call $pf_allocate (i32.const 128)))\n" ++
  s!"    (local.set $data (i32.load (local.get $region)))\n" ++
  s!"    (local.set $n (i32.const 0))\n" ++
  s!"    (block $copy_done\n" ++
  s!"      (loop $copy\n" ++
  s!"        (if (i32.ge_u (local.get $p) (local.get $end)) (then unreachable))\n" ++
  s!"        (local.set $c (i32.load8_u (local.get $p)))\n" ++
  s!"        (if (i32.eq (local.get $c) (i32.const 34)) (then (br $copy_done)))\n" ++
  s!"        (if (i32.ge_u (local.get $n) (i32.const 90)) (then unreachable))\n" ++
  s!"        (i32.store8 (i32.add (local.get $data) (local.get $n)) (local.get $c))\n" ++
  s!"        (local.set $n (i32.add (local.get $n) (i32.const 1)))\n" ++
  s!"        (local.set $p (i32.add (local.get $p) (i32.const 1)))\n" ++
  s!"        (br $copy)))\n" ++
  s!"    (if (i32.eqz (local.get $n)) (then unreachable))\n" ++
  s!"    (i32.store offset=8 (local.get $region) (local.get $n))\n" ++
  s!"    (local.get $region)\n" ++
  "  )\n" ++
  -- ADR-0030 E2-4-CW: base64 decode of the inner ok string in a query_chain
  -- response. Input: (srcOff, srcLen) pointing at the base64 text inside
  -- `{"ok":{"ok":"<b64>"}}`. Output: decoded bytes written to dst. Returns
  -- decoded length. Standard base64 alphabet A-Za-z0-9+/ with = padding.
  s!"  (func $pf_b64_decode (param $src i32) (param $srcLen i32) (param $dst i32) (result i32)\n" ++
  s!"    (local $i i32) (local $o i32) (local $c i32) (local $v i32) (local $acc i32) (local $bits i32) (local $quad i32)\n" ++
  s!"    (local.set $i (i32.const 0))\n" ++
  s!"    (local.set $o (i32.const 0))\n" ++
  s!"    (local.set $acc (i32.const 0))\n" ++
  s!"    (local.set $bits (i32.const 0))\n" ++
  s!"    (block $done\n" ++
  s!"      (loop $next\n" ++
  s!"        (br_if $done (i32.ge_u (local.get $i) (local.get $srcLen)))\n" ++
  s!"        (local.set $c (i32.load8_u (i32.add (local.get $src) (local.get $i))))\n" ++
  s!"        (local.set $i (i32.add (local.get $i) (i32.const 1)))\n" ++
  s!"        (if (i32.eq (local.get $c) (i32.const 61)) (then (br $done)))\n" ++  -- '=' padding
  s!"        (if (i32.and (i32.ge_u (local.get $c) (i32.const 65)) (i32.le_u (local.get $c) (i32.const 90))) (then\n" ++  -- A-Z → 0..25
  s!"          (local.set $v (i32.sub (local.get $c) (i32.const 65))))\n" ++
  s!"        (else (if (i32.and (i32.ge_u (local.get $c) (i32.const 97)) (i32.le_u (local.get $c) (i32.const 122))) (then\n" ++  -- a-z → 26..51
  s!"          (local.set $v (i32.sub (local.get $c) (i32.const 71))))\n" ++
  s!"        (else (if (i32.and (i32.ge_u (local.get $c) (i32.const 48)) (i32.le_u (local.get $c) (i32.const 57))) (then\n" ++  -- 0-9 → 52..61
  s!"          (local.set $v (i32.add (i32.sub (local.get $c) (i32.const 48)) (i32.const 52))))\n" ++
  s!"        (else (if (i32.eq (local.get $c) (i32.const 43)) (then\n" ++  -- + → 62
  s!"          (local.set $v (i32.const 62)))\n" ++
  s!"        (else (if (i32.eq (local.get $c) (i32.const 47)) (then\n" ++  -- / → 63
  s!"          (local.set $v (i32.const 63)))\n" ++
  s!"        (else (br $done)))))))))))\n" ++  -- non-alphabet → stop
  s!"        (local.set $acc (i32.or (i32.shl (local.get $acc) (i32.const 6)) (local.get $v)))\n" ++
  s!"        (local.set $bits (i32.add (local.get $bits) (i32.const 6)))\n" ++
  s!"        (if (i32.ge_u (local.get $bits) (i32.const 8)) (then\n" ++
  s!"          (local.set $bits (i32.sub (local.get $bits) (i32.const 8)))\n" ++
  s!"          (local.set $quad (i32.shr_u (local.get $acc) (local.get $bits)))\n" ++
  s!"          (i32.store8 (i32.add (local.get $dst) (local.get $o)) (i32.and (local.get $quad) (i32.const 255)))\n" ++
  s!"          (local.set $o (i32.add (local.get $o) (i32.const 1)))\n" ++
  s!"          (local.set $acc (i32.and (local.get $acc) (i32.sub (i32.shl (i32.const 1) (local.get $bits)) (i32.const 1))))))\n" ++
  s!"        (br $next)))\n" ++
  s!"    (local.get $o)\n" ++
  "  )\n" ++
  -- ADR-0030 E2-4-CW: query_chain + parse balance. Takes a request Region ptr,
  -- calls $query_chain, reads the response, finds `{"ok":{"ok":"<b64>"}}`,
  -- base64-decodes the inner string, scans for `"amount":"<decimal>"`, parses
  -- the decimal as UInt64 (overflow traps). Returns i64. Any error layer
  -- (system error / contract error / missing needle / bad decimal) → unreachable.
  s!"  (func $pf_query_balance (param $req_ptr i32) (param $needleOff i32) (param $needleLen i32) (result i64)\n" ++
  s!"    (local $resp_ptr i32) (local $rOff i32) (local $rLen i32) (local $idx i32) (local $p i32) (local $end i32) (local $c i32) (local $v i64) (local $any i32) (local $b64Off i32) (local $decOff i32) (local $decLen i32)\n" ++
  s!"    (local.set $resp_ptr (call $query_chain (local.get $req_ptr)))\n" ++
  s!"    (if (i32.eqz (local.get $resp_ptr)) (then unreachable))\n" ++
  s!"    (local.set $rOff (call $pf_region_off (local.get $resp_ptr)))\n" ++
  s!"    (local.set $rLen (call $pf_region_len (local.get $resp_ptr)))\n" ++
  "    ;; Find inner `{\"ok\":\"<b64>\"` — the `\"ok\":\"` needle (offset 3222).\n" ++
  "    ;; Response is `{\"ok\":{\"ok\":\"<b64>\"}}`; the inner `\"ok\":\"` has the base64.\n" ++
  s!"    (local.set $idx (call $pf_find (local.get $rOff) (local.get $rLen) (i32.const 3222) (i32.const 6)))\n" ++
  s!"    (if (i32.eq (local.get $idx) (i32.const -1)) (then unreachable))\n" ++
  s!"    (local.set $b64Off (i32.add (i32.add (local.get $rOff) (local.get $idx)) (i32.const 6)))\n" ++
  s!"    ;; Find the closing quote of the base64 string.\n" ++
  s!"    (local.set $p (local.get $b64Off))\n" ++
  s!"    (local.set $end (i32.add (local.get $rOff) (local.get $rLen)))\n" ++
  s!"    (local.set $c (i32.const 0))\n" ++
  s!"    (block $q_done\n" ++
  s!"      (loop $q\n" ++
  s!"        (if (i32.ge_u (local.get $p) (local.get $end)) (then unreachable))\n" ++
  s!"        (if (i32.eq (i32.load8_u (local.get $p)) (i32.const 34)) (then (br $q_done)))\n" ++
  s!"        (local.set $p (i32.add (local.get $p) (i32.const 1)))\n" ++
  s!"        (br $q)))\n" ++
  s!"    (local.set $decOff (i32.load (call $pf_allocate (i32.const 256))))\n" ++
  s!"    (local.set $decLen (call $pf_b64_decode (local.get $b64Off) (i32.sub (local.get $p) (local.get $b64Off)) (local.get $decOff)))\n" ++
  s!"    ;; Scan decoded bytes for the field needle and parse decimal.\n" ++
  s!"    (local.set $idx (call $pf_find (local.get $decOff) (local.get $decLen) (local.get $needleOff) (local.get $needleLen)))\n" ++
  s!"    (if (i32.eq (local.get $idx) (i32.const -1)) (then unreachable))\n" ++
  s!"    (local.set $p (i32.add (i32.add (local.get $decOff) (local.get $idx)) (local.get $needleLen)))\n" ++
  s!"    (local.set $end (i32.add (local.get $decOff) (local.get $decLen)))\n" ++
  s!"    (local.set $v (i64.const 0))\n" ++
  s!"    (local.set $any (i32.const 0))\n" ++
  s!"    (block $num_done\n" ++
  s!"      (loop $num\n" ++
  s!"        (if (i32.ge_u (local.get $p) (local.get $end)) (then (br $num_done)))\n" ++
  s!"        (local.set $c (i32.load8_u (local.get $p)))\n" ++
  s!"        (br_if $num_done (i32.or (i32.lt_u (local.get $c) (i32.const 48)) (i32.gt_u (local.get $c) (i32.const 57))))\n" ++
  s!"        (if (i64.gt_u (local.get $v) (i64.const 1844674407370955161)) (then unreachable))\n" ++
  s!"        (if (i64.eq (local.get $v) (i64.const 1844674407370955161)) (then (if (i32.gt_u (i32.sub (local.get $c) (i32.const 48)) (i32.const 5)) (then unreachable))))\n" ++
  s!"        (local.set $v (i64.add (i64.mul (local.get $v) (i64.const 10)) (i64.extend_i32_u (i32.sub (local.get $c) (i32.const 48)))))\n" ++
  s!"        (local.set $any (i32.const 1))\n" ++
  s!"        (local.set $p (i32.add (local.get $p) (i32.const 1)))\n" ++
  s!"        (br $num)))\n" ++
  s!"    (if (i32.eqz (local.get $any)) (then unreachable))\n" ++
  s!"    (local.get $v)\n" ++
  "  )\n" ++
  -- ADR-0030 E2-4-CW: build bank balance query request on heap, call query_chain.
  -- Request: `{\"bank\":{\"balance\":{\"address\":\"<self>\",\"denom\":\"stake\"}}}`.
  -- $env_ptr is the Env Region. Returns i64 balance.
  s!"  (func $pf_native_balance (param $env_ptr i32) (result i64)\n" ++
  s!"    (local $addrRegion i32) (local $addrOff i32) (local $addrLen i32) (local $reqRegion i32) (local $reqData i32) (local $p i32)\n" ++
  s!"    (local.set $addrRegion (call $pf_env_contract_addr (local.get $env_ptr)))\n" ++
  s!"    (local.set $addrOff (call $pf_region_off (local.get $addrRegion)))\n" ++
  s!"    (local.set $addrLen (call $pf_region_len (local.get $addrRegion)))\n" ++
  s!"    (local.set $reqRegion (call $pf_allocate (i32.const 256)))\n" ++
  s!"    (local.set $reqData (i32.load (local.get $reqRegion)))\n" ++
  s!"    (local.set $p (local.get $reqData))\n" ++
  s!"    (call $pf_copy_bytes (local.get $p) (i32.const 3100) (i32.const 31))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (i32.const 31)))\n" ++
  s!"    (call $pf_copy_bytes (local.get $p) (local.get $addrOff) (local.get $addrLen))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (local.get $addrLen)))\n" ++
  s!"    (call $pf_copy_bytes (local.get $p) (i32.const 3079) (i32.const 20))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (i32.const 20)))\n" ++
  s!"    (i32.store offset=8 (local.get $reqRegion) (i32.sub (local.get $p) (local.get $reqData)))\n" ++
  s!"    (call $pf_query_balance (local.get $reqRegion) (i32.const 3211) (i32.const 10))\n" ++
  "  )\n" ++
  -- ADR-0030 E2-4-CW: build CW20 smart-query request on heap, call query_chain.
  -- Request envelope:
  --   `{"wasm":{"smart":{"contract_addr":"<mint>","msg":"<b64>"}}}`
  -- where <b64> is the base64 of the inner CW20 balance query JSON
  --   `{"balance":{"address":"<self>"}}`
  -- (Binary is a base64 string in the QueryRequest envelope, not inline JSON).
  -- $env_ptr is the Env Region; $mintRegion is a Region ptr with the mint addr.
  s!"  (func $pf_token_balance (param $env_ptr i32) (param $mintRegion i32) (result i64)\n" ++
  s!"    (local $addrRegion i32) (local $addrOff i32) (local $addrLen i32) (local $mintOff i32) (local $mintLen i32) (local $reqRegion i32) (local $reqData i32) (local $innerRegion i32) (local $innerData i32) (local $innerLen i32) (local $b64Len i32) (local $p i32)\n" ++
  s!"    (local.set $addrRegion (call $pf_env_contract_addr (local.get $env_ptr)))\n" ++
  s!"    (local.set $addrOff (call $pf_region_off (local.get $addrRegion)))\n" ++
  s!"    (local.set $addrLen (call $pf_region_len (local.get $addrRegion)))\n" ++
  s!"    (local.set $mintOff (call $pf_region_off (local.get $mintRegion)))\n" ++
  s!"    (local.set $mintLen (call $pf_region_len (local.get $mintRegion)))\n" ++
  -- Build inner CW20 balance query JSON in a scratch region.
  s!"    (local.set $innerRegion (call $pf_allocate (i32.const 128)))\n" ++
  s!"    (local.set $innerData (i32.load (local.get $innerRegion)))\n" ++
  s!"    (local.set $p (local.get $innerData))\n" ++
  s!"    (call $pf_copy_bytes (local.get $p) (i32.const 3178) (i32.const 23))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (i32.const 23)))\n" ++
  s!"    (call $pf_copy_bytes (local.get $p) (local.get $addrOff) (local.get $addrLen))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (local.get $addrLen)))\n" ++
  s!"    (call $pf_copy_bytes (local.get $p) (i32.const 3202) (i32.const 3))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (i32.const 3)))\n" ++
  s!"    (local.set $innerLen (i32.sub (local.get $p) (local.get $innerData)))\n" ++
  -- Envelope: prefix + mint + `","msg":"` + base64(inner) + `"}}}`.
  s!"    (local.set $reqRegion (call $pf_allocate (i32.const 512)))\n" ++
  s!"    (local.set $reqData (i32.load (local.get $reqRegion)))\n" ++
  s!"    (local.set $p (local.get $reqData))\n" ++
  s!"    (call $pf_copy_bytes (local.get $p) (i32.const 3132) (i32.const 35))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (i32.const 35)))\n" ++
  s!"    (call $pf_copy_bytes (local.get $p) (local.get $mintOff) (local.get $mintLen))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (local.get $mintLen)))\n" ++
  s!"    (call $pf_copy_bytes (local.get $p) (i32.const 3168) (i32.const 9))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (i32.const 9)))\n" ++
  s!"    (local.set $b64Len (call $pf_base64_encode (local.get $innerData) (local.get $innerLen) (local.get $p)))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (local.get $b64Len)))\n" ++
  s!"    (call $pf_copy_bytes (local.get $p) (i32.const 3206) (i32.const 4))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (i32.const 4)))\n" ++
  s!"    (i32.store offset=8 (local.get $reqRegion) (i32.sub (local.get $p) (local.get $reqData)))\n" ++
  s!"    (call $pf_query_balance (local.get $reqRegion) (i32.const 3229) (i32.const 11))\n" ++
  "  )\n" ++
  -- build ok Response JSON with attributes buffer + optional result attribute
  -- attributes are pre-built at attrBase as comma-separated {"key":"...","value":"..."} items
  s!"  (func $pf_ok_result (result i32)\n" ++
  s!"    (local $region i32) (local $data i32) (local $p i32) (local $n i32) (local $alen i32) (local $mlen i32) (local $i i32)\n" ++
  "    ;; ok Response JSON: messages from msg buffer, attributes from attr buffer\n" ++
  s!"    (local.set $region (call $pf_allocate (i32.const 3072)))\n" ++
  s!"    (local.set $data (i32.load (local.get $region)))\n" ++
  s!"    (local.set $p (local.get $data))\n" ++
  -- {"ok":{"messages":[
  s!"    (i32.store8 (local.get $p) (i32.const 123))\n" ++
  s!"    (i32.store8 offset=1 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=2 (local.get $p) (i32.const 111))\n" ++
  s!"    (i32.store8 offset=3 (local.get $p) (i32.const 107))\n" ++
  s!"    (i32.store8 offset=4 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=5 (local.get $p) (i32.const 58))\n" ++
  s!"    (i32.store8 offset=6 (local.get $p) (i32.const 123))\n" ++
  s!"    (i32.store8 offset=7 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=8 (local.get $p) (i32.const 109))\n" ++
  s!"    (i32.store8 offset=9 (local.get $p) (i32.const 101))\n" ++
  s!"    (i32.store8 offset=10 (local.get $p) (i32.const 115))\n" ++
  s!"    (i32.store8 offset=11 (local.get $p) (i32.const 115))\n" ++
  s!"    (i32.store8 offset=12 (local.get $p) (i32.const 97))\n" ++
  s!"    (i32.store8 offset=13 (local.get $p) (i32.const 103))\n" ++
  s!"    (i32.store8 offset=14 (local.get $p) (i32.const 101))\n" ++
  s!"    (i32.store8 offset=15 (local.get $p) (i32.const 115))\n" ++
  s!"    (i32.store8 offset=16 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=17 (local.get $p) (i32.const 58))\n" ++
  s!"    (i32.store8 offset=18 (local.get $p) (i32.const 91))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (i32.const 19)))\n" ++
  -- append collected SubMsg JSON objects
  s!"    (local.set $mlen (global.get $msg_len))\n" ++
  s!"    (local.set $i (i32.const 0))\n" ++
  s!"    (block $mcopy_done\n" ++
  s!"      (loop $mcopy\n" ++
  s!"        (br_if $mcopy_done (i32.ge_u (local.get $i) (local.get $mlen)))\n" ++
  s!"        (i32.store8 (i32.add (local.get $p) (local.get $i)) (i32.load8_u (i32.add (i32.const {msgBase}) (local.get $i))))\n" ++
  s!"        (local.set $i (i32.add (local.get $i) (i32.const 1)))\n" ++
  s!"        (br $mcopy)))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (local.get $mlen)))\n" ++
  -- ],"attributes":[
  s!"    (i32.store8 (local.get $p) (i32.const 93))\n" ++
  s!"    (i32.store8 offset=1 (local.get $p) (i32.const 44))\n" ++
  s!"    (i32.store8 offset=2 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=3 (local.get $p) (i32.const 97))\n" ++
  s!"    (i32.store8 offset=4 (local.get $p) (i32.const 116))\n" ++
  s!"    (i32.store8 offset=5 (local.get $p) (i32.const 116))\n" ++
  s!"    (i32.store8 offset=6 (local.get $p) (i32.const 114))\n" ++
  s!"    (i32.store8 offset=7 (local.get $p) (i32.const 105))\n" ++
  s!"    (i32.store8 offset=8 (local.get $p) (i32.const 98))\n" ++
  s!"    (i32.store8 offset=9 (local.get $p) (i32.const 117))\n" ++
  s!"    (i32.store8 offset=10 (local.get $p) (i32.const 116))\n" ++
  s!"    (i32.store8 offset=11 (local.get $p) (i32.const 101))\n" ++
  s!"    (i32.store8 offset=12 (local.get $p) (i32.const 115))\n" ++
  s!"    (i32.store8 offset=13 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=14 (local.get $p) (i32.const 58))\n" ++
  s!"    (i32.store8 offset=15 (local.get $p) (i32.const 91))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (i32.const 16)))\n" ++
  -- append collected attributes
  s!"    (local.set $alen (global.get $attr_len))\n" ++
  s!"    (local.set $i (i32.const 0))\n" ++
  s!"    (block $acopy_done\n" ++
  s!"      (loop $acopy\n" ++
  s!"        (br_if $acopy_done (i32.ge_u (local.get $i) (local.get $alen)))\n" ++
  s!"        (i32.store8 (i32.add (local.get $p) (local.get $i)) (i32.load8_u (i32.add (i32.const {attrBase}) (local.get $i))))\n" ++
  s!"        (local.set $i (i32.add (local.get $i) (i32.const 1)))\n" ++
  s!"        (br $acopy)))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (local.get $alen)))\n" ++
  -- if return value present, append result attribute
  -- scalar (ret_kind=1): value="<decimal>"; aggregate (ret_kind=4): value="[d0,d1,...]"
  s!"    (if (i32.ne (global.get $ret_kind) (i32.const 0)) (then\n" ++
  s!"      (if (i32.ne (local.get $alen) (i32.const 0)) (then\n" ++
  s!"        (i32.store8 (local.get $p) (i32.const 44))\n" ++
  s!"        (local.set $p (i32.add (local.get $p) (i32.const 1)))))\n" ++
  "      ;; result attribute object\n" ++
  s!"      (i32.store8 (local.get $p) (i32.const 123))\n" ++
  s!"      (i32.store8 offset=1 (local.get $p) (i32.const 34))\n" ++
  s!"      (i32.store8 offset=2 (local.get $p) (i32.const 107))\n" ++
  s!"      (i32.store8 offset=3 (local.get $p) (i32.const 101))\n" ++
  s!"      (i32.store8 offset=4 (local.get $p) (i32.const 121))\n" ++
  s!"      (i32.store8 offset=5 (local.get $p) (i32.const 34))\n" ++
  s!"      (i32.store8 offset=6 (local.get $p) (i32.const 58))\n" ++
  s!"      (i32.store8 offset=7 (local.get $p) (i32.const 34))\n" ++
  s!"      (i32.store8 offset=8 (local.get $p) (i32.const 114))\n" ++
  s!"      (i32.store8 offset=9 (local.get $p) (i32.const 101))\n" ++
  s!"      (i32.store8 offset=10 (local.get $p) (i32.const 115))\n" ++
  s!"      (i32.store8 offset=11 (local.get $p) (i32.const 117))\n" ++
  s!"      (i32.store8 offset=12 (local.get $p) (i32.const 108))\n" ++
  s!"      (i32.store8 offset=13 (local.get $p) (i32.const 116))\n" ++
  s!"      (i32.store8 offset=14 (local.get $p) (i32.const 34))\n" ++
  s!"      (i32.store8 offset=15 (local.get $p) (i32.const 44))\n" ++
  s!"      (i32.store8 offset=16 (local.get $p) (i32.const 34))\n" ++
  s!"      (i32.store8 offset=17 (local.get $p) (i32.const 118))\n" ++
  s!"      (i32.store8 offset=18 (local.get $p) (i32.const 97))\n" ++
  s!"      (i32.store8 offset=19 (local.get $p) (i32.const 108))\n" ++
  s!"      (i32.store8 offset=20 (local.get $p) (i32.const 117))\n" ++
  s!"      (i32.store8 offset=21 (local.get $p) (i32.const 101))\n" ++
  s!"      (i32.store8 offset=22 (local.get $p) (i32.const 34))\n" ++
  s!"      (i32.store8 offset=23 (local.get $p) (i32.const 58))\n" ++
  s!"      (i32.store8 offset=24 (local.get $p) (i32.const 34))\n" ++
  s!"      (local.set $p (i32.add (local.get $p) (i32.const 25)))\n" ++
  -- B-RET-ABI: aggregate → JSON array of decimals inside the attribute value string
  s!"      (if (i32.eq (global.get $ret_kind) (i32.const 4)) (then\n" ++
  s!"        (i32.store8 (local.get $p) (i32.const 91))\n" ++  -- '['
  s!"        (local.set $p (i32.add (local.get $p) (i32.const 1)))\n" ++
  s!"        (local.set $i (i32.const 0))\n" ++
  s!"        (block $agg_done\n" ++
  s!"          (loop $agg_loop\n" ++
  s!"            (br_if $agg_done (i32.ge_u (local.get $i) (global.get $ret_count)))\n" ++
  s!"            (if (i32.ne (local.get $i) (i32.const 0)) (then\n" ++
  s!"              (i32.store8 (local.get $p) (i32.const 44))\n" ++
  s!"              (local.set $p (i32.add (local.get $p) (i32.const 1)))))\n" ++
  -- capacity guard: leave room for max 20-digit decimal + closing `"]}`
  s!"            (if (i32.gt_u (i32.sub (i32.add (local.get $data) (i32.const 3000)) (local.get $p)) (i32.const 24)) (then\n" ++
  s!"              (local.set $n (call $pf_fmt_u64 (i64.load (i32.add (i32.const {valueCell}) (i32.shl (local.get $i) (i32.const 3)))) (local.get $p)))\n" ++
  s!"              (local.set $p (i32.add (local.get $p) (local.get $n))))\n" ++
  s!"              (else unreachable))\n" ++
  s!"            (local.set $i (i32.add (local.get $i) (i32.const 1)))\n" ++
  s!"            (br $agg_loop)))\n" ++
  s!"        (i32.store8 (local.get $p) (i32.const 93))\n" ++  -- ']'
  s!"        (local.set $p (i32.add (local.get $p) (i32.const 1))))\n" ++
  s!"      (else\n" ++
  s!"        (local.set $n (call $pf_fmt_u64 (global.get $ret_val) (local.get $p)))\n" ++
  s!"        (local.set $p (i32.add (local.get $p) (local.get $n)))))\n" ++
  s!"      (i32.store8 (local.get $p) (i32.const 34))\n" ++
  s!"      (i32.store8 offset=1 (local.get $p) (i32.const 125))\n" ++
  s!"      (local.set $p (i32.add (local.get $p) (i32.const 2)))))\n" ++
  -- close: ],"events":[],"data":null}}
  s!"    (i32.store8 (local.get $p) (i32.const 93))\n" ++
  s!"    (i32.store8 offset=1 (local.get $p) (i32.const 44))\n" ++
  s!"    (i32.store8 offset=2 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=3 (local.get $p) (i32.const 101))\n" ++
  s!"    (i32.store8 offset=4 (local.get $p) (i32.const 118))\n" ++
  s!"    (i32.store8 offset=5 (local.get $p) (i32.const 101))\n" ++
  s!"    (i32.store8 offset=6 (local.get $p) (i32.const 110))\n" ++
  s!"    (i32.store8 offset=7 (local.get $p) (i32.const 116))\n" ++
  s!"    (i32.store8 offset=8 (local.get $p) (i32.const 115))\n" ++
  s!"    (i32.store8 offset=9 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=10 (local.get $p) (i32.const 58))\n" ++
  s!"    (i32.store8 offset=11 (local.get $p) (i32.const 91))\n" ++
  s!"    (i32.store8 offset=12 (local.get $p) (i32.const 93))\n" ++
  s!"    (i32.store8 offset=13 (local.get $p) (i32.const 44))\n" ++
  s!"    (i32.store8 offset=14 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=15 (local.get $p) (i32.const 100))\n" ++
  s!"    (i32.store8 offset=16 (local.get $p) (i32.const 97))\n" ++
  s!"    (i32.store8 offset=17 (local.get $p) (i32.const 116))\n" ++
  s!"    (i32.store8 offset=18 (local.get $p) (i32.const 97))\n" ++
  s!"    (i32.store8 offset=19 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=20 (local.get $p) (i32.const 58))\n" ++
  s!"    (i32.store8 offset=21 (local.get $p) (i32.const 110))\n" ++
  s!"    (i32.store8 offset=22 (local.get $p) (i32.const 117))\n" ++
  s!"    (i32.store8 offset=23 (local.get $p) (i32.const 108))\n" ++
  s!"    (i32.store8 offset=24 (local.get $p) (i32.const 108))\n" ++
  s!"    (i32.store8 offset=25 (local.get $p) (i32.const 125))\n" ++
  s!"    (i32.store8 offset=26 (local.get $p) (i32.const 125))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (i32.const 27)))\n" ++
  s!"    (i32.store offset=8 (local.get $region) (i32.sub (local.get $p) (local.get $data)))\n" ++
  s!"    (local.get $region)\n" ++
  "  )\n" ++
  -- query ok: {"ok":"<decimal>"} as binary-as-utf8 (not base64 — MVP query data is decimal text)
  s!"  (func $pf_query_ok (param $v i64) (result i32)\n" ++
  s!"    (local $region i32) (local $data i32) (local $p i32) (local $n i32)\n" ++
  s!"    (local.set $region (call $pf_allocate (i32.const 64)))\n" ++
  s!"    (local.set $data (i32.load (local.get $region)))\n" ++
  s!"    (i32.store8 (local.get $data) (i32.const 123))\n" ++
  s!"    (i32.store8 offset=1 (local.get $data) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=2 (local.get $data) (i32.const 111))\n" ++
  s!"    (i32.store8 offset=3 (local.get $data) (i32.const 107))\n" ++
  s!"    (i32.store8 offset=4 (local.get $data) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=5 (local.get $data) (i32.const 58))\n" ++
  s!"    (i32.store8 offset=6 (local.get $data) (i32.const 34))\n" ++
  s!"    (local.set $p (i32.add (local.get $data) (i32.const 7)))\n" ++
  s!"    (local.set $n (call $pf_fmt_u64 (local.get $v) (local.get $p)))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (local.get $n)))\n" ++
  s!"    (i32.store8 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=1 (local.get $p) (i32.const 125))\n" ++
  s!"    (i32.store offset=8 (local.get $region) (i32.add (local.get $n) (i32.const 9)))\n" ++
  s!"    (local.get $region)\n" ++
  "  )\n" ++
  -- B-RET-ABI query ok: {"ok":"[d0,d1,...]"} — ok value is a JSON-array-as-string
  -- (same shape class as scalar {"ok":"<decimal>"}; multi-leaf generalized).
  -- Cap: 8×20-digit + commas + framing ≤ 256B allocated.
  s!"  (func $pf_query_ok_agg (result i32)\n" ++
  s!"    (local $region i32) (local $data i32) (local $p i32) (local $n i32) (local $i i32)\n" ++
  s!"    (local.set $region (call $pf_allocate (i32.const 256)))\n" ++
  s!"    (local.set $data (i32.load (local.get $region)))\n" ++
  s!"    (i32.store8 (local.get $data) (i32.const 123))\n" ++
  s!"    (i32.store8 offset=1 (local.get $data) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=2 (local.get $data) (i32.const 111))\n" ++
  s!"    (i32.store8 offset=3 (local.get $data) (i32.const 107))\n" ++
  s!"    (i32.store8 offset=4 (local.get $data) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=5 (local.get $data) (i32.const 58))\n" ++
  s!"    (i32.store8 offset=6 (local.get $data) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=7 (local.get $data) (i32.const 91))\n" ++  -- '["
  s!"    (local.set $p (i32.add (local.get $data) (i32.const 8)))\n" ++
  s!"    (local.set $i (i32.const 0))\n" ++
  s!"    (block $qagg_done\n" ++
  s!"      (loop $qagg_loop\n" ++
  s!"        (br_if $qagg_done (i32.ge_u (local.get $i) (global.get $ret_count)))\n" ++
  s!"        (if (i32.ne (local.get $i) (i32.const 0)) (then\n" ++
  s!"          (i32.store8 (local.get $p) (i32.const 44))\n" ++
  s!"          (local.set $p (i32.add (local.get $p) (i32.const 1)))))\n" ++
  -- capacity: 256B region, leave ≥24B for decimal + closing `"]}`
  s!"        (if (i32.gt_u (i32.sub (i32.add (local.get $data) (i32.const 256)) (local.get $p)) (i32.const 24))\n" ++
  s!"          (then\n" ++
  s!"            (local.set $n (call $pf_fmt_u64 (i64.load (i32.add (i32.const {valueCell}) (i32.shl (local.get $i) (i32.const 3)))) (local.get $p)))\n" ++
  s!"            (local.set $p (i32.add (local.get $p) (local.get $n))))\n" ++
  s!"          (else unreachable))\n" ++
  s!"        (local.set $i (i32.add (local.get $i) (i32.const 1)))\n" ++
  s!"        (br $qagg_loop)))\n" ++
  s!"    (i32.store8 (local.get $p) (i32.const 93))\n" ++  -- ']'
  s!"    (i32.store8 offset=1 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=2 (local.get $p) (i32.const 125))\n" ++
  s!"    (i32.store offset=8 (local.get $region) (i32.add (i32.sub (local.get $p) (local.get $data)) (i32.const 3)))\n" ++
  s!"    (local.get $region)\n" ++
  "  )\n" ++
  -- find substring needle in haystack (byte compare); return start index or 0xFFFFFFFF
  s!"  (func $pf_find (param $hay i32) (param $hay_len i32) (param $needle i32) (param $needle_len i32) (result i32)\n" ++
  s!"    (local $i i32) (local $j i32) (local $ok i32)\n" ++
  s!"    (if (i32.gt_u (local.get $needle_len) (local.get $hay_len)) (then (return (i32.const -1))))\n" ++
  s!"    (local.set $i (i32.const 0))\n" ++
  s!"    (block $outer_done\n" ++
  s!"      (loop $outer\n" ++
  s!"        (br_if $outer_done (i32.gt_u (i32.add (local.get $i) (local.get $needle_len)) (local.get $hay_len)))\n" ++
  s!"        (local.set $j (i32.const 0))\n" ++
  s!"        (local.set $ok (i32.const 1))\n" ++
  s!"        (block $inner_done\n" ++
  s!"          (loop $inner\n" ++
  s!"            (br_if $inner_done (i32.ge_u (local.get $j) (local.get $needle_len)))\n" ++
  s!"            (if (i32.ne (i32.load8_u (i32.add (local.get $hay) (i32.add (local.get $i) (local.get $j))))\n" ++
  s!"                       (i32.load8_u (i32.add (local.get $needle) (local.get $j)))) (then\n" ++
  s!"              (local.set $ok (i32.const 0))\n" ++
  s!"              (br $inner_done)))\n" ++
  s!"            (local.set $j (i32.add (local.get $j) (i32.const 1)))\n" ++
  s!"            (br $inner)))\n" ++
  s!"        (if (local.get $ok) (then (return (local.get $i))))\n" ++
  s!"        (local.set $i (i32.add (local.get $i) (i32.const 1)))\n" ++
  s!"        (br $outer)))\n" ++
  s!"    (i32.const -1)\n" ++
  "  )\n" ++
  -- parse unsigned decimal after a field name \"name\":NUMBER starting search at from
  s!"  (func $pf_parse_u64_field (param $hay i32) (param $hay_len i32) (param $name i32) (param $name_len i32) (result i64)\n" ++
  s!"    (local $idx i32) (local $p i32) (local $end i32) (local $c i32) (local $v i64) (local $any i32)\n" ++
  s!"    (local.set $idx (call $pf_find (local.get $hay) (local.get $hay_len) (local.get $name) (local.get $name_len)))\n" ++
  s!"    (if (i32.eq (local.get $idx) (i32.const -1)) (then unreachable))\n" ++
  s!"    (local.set $p (i32.add (i32.add (local.get $hay) (local.get $idx)) (local.get $name_len)))\n" ++
  s!"    (local.set $end (i32.add (local.get $hay) (local.get $hay_len)))\n" ++
  -- skip to ':'
  s!"    (block $find_colon\n" ++
  s!"      (loop $sc\n" ++
  s!"        (if (i32.ge_u (local.get $p) (local.get $end)) (then unreachable))\n" ++
  s!"        (local.set $c (i32.load8_u (local.get $p)))\n" ++
  s!"        (local.set $p (i32.add (local.get $p) (i32.const 1)))\n" ++
  s!"        (br_if $find_colon (i32.eq (local.get $c) (i32.const 58)))\n" ++
  s!"        (br $sc)))\n" ++
  -- skip spaces
  s!"    (block $skip_sp\n" ++
  s!"      (loop $sp\n" ++
  s!"        (if (i32.ge_u (local.get $p) (local.get $end)) (then (br $skip_sp)))\n" ++
  s!"        (local.set $c (i32.load8_u (local.get $p)))\n" ++
  s!"        (br_if $skip_sp (i32.ne (local.get $c) (i32.const 32)))\n" ++
  s!"        (local.set $p (i32.add (local.get $p) (i32.const 1)))\n" ++
  s!"        (br $sp)))\n" ++
  s!"    (local.set $v (i64.const 0))\n" ++
  s!"    (local.set $any (i32.const 0))\n" ++
  s!"    (block $num_done\n" ++
  s!"      (loop $num\n" ++
  s!"        (if (i32.ge_u (local.get $p) (local.get $end)) (then (br $num_done)))\n" ++
  s!"        (local.set $c (i32.load8_u (local.get $p)))\n" ++
  s!"        (br_if $num_done (i32.or (i32.lt_u (local.get $c) (i32.const 48)) (i32.gt_u (local.get $c) (i32.const 57))))\n" ++
  -- P0-2 fix: reject silently wrapping decimal accumulation. Before
  -- v = v*10 + digit, require v < floor((2^64-1)/10) == 1844674407370955161,
  -- or v == that bound with digit ≤ 5 (2^64-1 ends in 5). Anything larger
  -- cannot be an exact UInt64 and must trap, never wrap.
  s!"        (if (i64.gt_u (local.get $v) (i64.const 1844674407370955161)) (then unreachable))\n" ++
  s!"        (if (i64.eq (local.get $v) (i64.const 1844674407370955161)) (then (if (i32.gt_u (i32.sub (local.get $c) (i32.const 48)) (i32.const 5)) (then unreachable))))\n" ++
  s!"        (local.set $v (i64.add (i64.mul (local.get $v) (i64.const 10)) (i64.extend_i32_u (i32.sub (local.get $c) (i32.const 48)))))\n" ++
  s!"        (local.set $any (i32.const 1))\n" ++
  s!"        (local.set $p (i32.add (local.get $p) (i32.const 1)))\n" ++
  s!"        (br $num)))\n" ++
  s!"    (if (i32.eqz (local.get $any)) (then unreachable))\n" ++
  s!"    (local.get $v)\n" ++
  "  )\n" ++
  -- region payload view: (offset, length) from region ptr
  s!"  (func $pf_region_off (param $r i32) (result i32) (i32.load (local.get $r)))\n" ++
  s!"  (func $pf_region_len (param $r i32) (result i32) (i32.load offset=8 (local.get $r)))\n" ++
  -- B-CTX-OPEN: parse cosmwasm-std Timestamp JSON string field after name needle.
  -- Shape: `"time":"1571797419879305533"` (quoted decimal nanoseconds). Optional
  -- leading quote after ':' is skipped; bare digits also accepted. Overflow
  -- discipline matches $pf_parse_u64_field.
  s!"  (func $pf_parse_u64_string_field (param $hay i32) (param $hay_len i32) (param $name i32) (param $name_len i32) (result i64)\n" ++
  s!"    (local $idx i32) (local $p i32) (local $end i32) (local $c i32) (local $v i64) (local $any i32)\n" ++
  s!"    (local.set $idx (call $pf_find (local.get $hay) (local.get $hay_len) (local.get $name) (local.get $name_len)))\n" ++
  s!"    (if (i32.eq (local.get $idx) (i32.const -1)) (then unreachable))\n" ++
  s!"    (local.set $p (i32.add (i32.add (local.get $hay) (local.get $idx)) (local.get $name_len)))\n" ++
  s!"    (local.set $end (i32.add (local.get $hay) (local.get $hay_len)))\n" ++
  s!"    (block $find_colon\n" ++
  s!"      (loop $sc\n" ++
  s!"        (if (i32.ge_u (local.get $p) (local.get $end)) (then unreachable))\n" ++
  s!"        (local.set $c (i32.load8_u (local.get $p)))\n" ++
  s!"        (local.set $p (i32.add (local.get $p) (i32.const 1)))\n" ++
  s!"        (br_if $find_colon (i32.eq (local.get $c) (i32.const 58)))\n" ++
  s!"        (br $sc)))\n" ++
  s!"    (block $skip_sp\n" ++
  s!"      (loop $sp\n" ++
  s!"        (if (i32.ge_u (local.get $p) (local.get $end)) (then (br $skip_sp)))\n" ++
  s!"        (local.set $c (i32.load8_u (local.get $p)))\n" ++
  s!"        (br_if $skip_sp (i32.ne (local.get $c) (i32.const 32)))\n" ++
  s!"        (local.set $p (i32.add (local.get $p) (i32.const 1)))\n" ++
  s!"        (br $sp)))\n" ++
  -- optional leading quote (cosmwasm-std Timestamp / Uint64 JSON string form)
  s!"    (if (i32.lt_u (local.get $p) (local.get $end)) (then\n" ++
  s!"      (if (i32.eq (i32.load8_u (local.get $p)) (i32.const 34)) (then\n" ++
  s!"        (local.set $p (i32.add (local.get $p) (i32.const 1)))))))\n" ++
  s!"    (local.set $v (i64.const 0))\n" ++
  s!"    (local.set $any (i32.const 0))\n" ++
  s!"    (block $num_done\n" ++
  s!"      (loop $num\n" ++
  s!"        (if (i32.ge_u (local.get $p) (local.get $end)) (then (br $num_done)))\n" ++
  s!"        (local.set $c (i32.load8_u (local.get $p)))\n" ++
  s!"        (br_if $num_done (i32.or (i32.lt_u (local.get $c) (i32.const 48)) (i32.gt_u (local.get $c) (i32.const 57))))\n" ++
  s!"        (if (i64.gt_u (local.get $v) (i64.const 1844674407370955161)) (then unreachable))\n" ++
  s!"        (if (i64.eq (local.get $v) (i64.const 1844674407370955161)) (then (if (i32.gt_u (i32.sub (local.get $c) (i32.const 48)) (i32.const 5)) (then unreachable))))\n" ++
  s!"        (local.set $v (i64.add (i64.mul (local.get $v) (i64.const 10)) (i64.extend_i32_u (i32.sub (local.get $c) (i32.const 48)))))\n" ++
  s!"        (local.set $any (i32.const 1))\n" ++
  s!"        (local.set $p (i32.add (local.get $p) (i32.const 1)))\n" ++
  s!"        (br $num)))\n" ++
  s!"    (if (i32.eqz (local.get $any)) (then unreachable))\n" ++
  s!"    (local.get $v)\n" ++
  "  )\n" ++
  -- B-CTX-OPEN: Env Region → block time whole seconds.
  -- cosmwasm-std Env.block.time is Timestamp = nanoseconds since epoch as a
  -- JSON string field `"time"`. Divide by 10^9 truncating (same discipline as
  -- NEAR host block_timestamp). `.seconds()` is already u64 — exact UInt64
  -- fit, NO range guard (unlike EVM 256-bit timestamp()).
  -- Needle for `"time"` is fixed at offset 3000 length 6 (see renderDataSectionV2).
  s!"  (func $pf_env_block_time_seconds (param $env_ptr i32) (result i64)\n" ++
  s!"    (local $off i32) (local $len i32) (local $ns i64)\n" ++
  s!"    (local.set $off (call $pf_region_off (local.get $env_ptr)))\n" ++
  s!"    (local.set $len (call $pf_region_len (local.get $env_ptr)))\n" ++
  s!"    (local.set $ns (call $pf_parse_u64_string_field (local.get $off) (local.get $len) (i32.const 3000) (i32.const 6)))\n" ++
  s!"    (i64.div_u (local.get $ns) (i64.const 1000000000))\n" ++
  "  )\n" ++
  -- reset per-entry attribute/messages/return/inner-json state
  s!"  (func $pf_reset_result\n" ++
  s!"    (global.set $attr_len (i32.const 0))\n" ++
  s!"    (global.set $msg_len (i32.const 0))\n" ++
  s!"    (global.set $inner_len (i32.const 0))\n" ++
  s!"    (global.set $ret_kind (i32.const 0))\n" ++
  s!"    (global.set $ret_val (i64.const 0))\n" ++
  s!"    (global.set $ret_count (i32.const 0))\n" ++
  "  )\n" ++
  -- append one raw byte to the messages buffer (CW-4 SubMsg JSON builder)
  s!"  (func $pf_msg_byte (param $b i32)\n" ++
  s!"    (local $p i32)\n" ++
  s!"    (if (i32.ge_u (global.get $msg_len) (i32.const 1536)) (then unreachable))\n" ++
  s!"    (local.set $p (i32.add (i32.const {msgBase}) (global.get $msg_len)))\n" ++
  s!"    (i32.store8 (local.get $p) (local.get $b))\n" ++
  s!"    (global.set $msg_len (i32.add (global.get $msg_len) (i32.const 1)))\n" ++
  "  )\n" ++
  -- append ASCII string from linear memory to messages buffer
  s!"  (func $pf_msg_bytes (param $off i32) (param $len i32)\n" ++
  s!"    (local $i i32) (local $p i32)\n" ++
  s!"    (if (i32.gt_u (i32.add (global.get $msg_len) (local.get $len)) (i32.const 1536)) (then unreachable))\n" ++
  s!"    (local.set $p (i32.add (i32.const {msgBase}) (global.get $msg_len)))\n" ++
  s!"    (local.set $i (i32.const 0))\n" ++
  s!"    (block $done\n" ++
  s!"      (loop $copy\n" ++
  s!"        (br_if $done (i32.ge_u (local.get $i) (local.get $len)))\n" ++
  s!"        (i32.store8 (i32.add (local.get $p) (local.get $i))\n" ++
  s!"          (i32.load8_u (i32.add (local.get $off) (local.get $i))))\n" ++
  s!"        (local.set $i (i32.add (local.get $i) (i32.const 1)))\n" ++
  s!"        (br $copy)))\n" ++
  s!"    (global.set $msg_len (i32.add (global.get $msg_len) (local.get $len)))\n" ++
  "  )\n" ++
  -- append decimal of i64 to messages buffer (reuses pf_fmt_u64)
  s!"  (func $pf_msg_u64 (param $v i64)\n" ++
  s!"    (local $p i32) (local $n i32)\n" ++
  -- P0-4 fix: the messages buffer has a fixed 1536-byte capacity by layout
  -- (msg..valueCell). Trap instead of bleeding into the value cell.
  s!"    (if (i32.gt_u (i32.add (global.get $msg_len) (i32.const 24)) (i32.const 1536)) (then unreachable))\n" ++
  s!"    (local.set $p (i32.add (i32.const {msgBase}) (global.get $msg_len)))\n" ++
  s!"    (local.set $n (call $pf_fmt_u64 (local.get $v) (local.get $p)))\n" ++
  s!"    (global.set $msg_len (i32.add (global.get $msg_len) (local.get $n)))\n" ++
  "  )\n" ++
  -- ADR-0029 C1: funds helpers. info region cached in $info_off/$info_len.
  -- Needles live at fixed data offsets 3007 (`"funds":[]`, 10B) and 3018
  -- (`"funds":[{"denom":"stake","amount":"`, 36B); see renderDataSectionV2.
  -- requireFundsEmpty: exact `"funds":[]` present in info JSON.
  s!"  (func $pf_funds_empty (result i32)\n" ++
  s!"    (local $idx i32)\n" ++
  s!"    (local.set $idx (call $pf_find (global.get $info_off) (global.get $info_len) (i32.const 3007) (i32.const 10)))\n" ++
  s!"    (if (i32.eq (local.get $idx) (i32.const -1)) (then (return (i32.const 0))))\n" ++
  s!"    (i32.const 1)\n" ++
  "  )\n" ++
  -- nativeDeposit: exactly one coin {denom:"stake", amount == $amount}.
  s!"  (func $pf_funds_exact (param $amount i64) (result i32)\n" ++
  s!"    (local $idx i32) (local $p i32) (local $end i32) (local $c i32) (local $v i64) (local $any i32)\n" ++
  s!"    (local.set $idx (call $pf_find (global.get $info_off) (global.get $info_len) (i32.const 3018) (i32.const 36)))\n" ++
  s!"    (if (i32.eq (local.get $idx) (i32.const -1)) (then (return (i32.const 0))))\n" ++
  s!"    (local.set $p (i32.add (i32.add (global.get $info_off) (local.get $idx)) (i32.const 36)))\n" ++
  s!"    (local.set $end (i32.add (global.get $info_off) (global.get $info_len)))\n" ++
  s!"    (local.set $v (i64.const 0))\n" ++
  s!"    (local.set $any (i32.const 0))\n" ++
  s!"    (block $num_done\n" ++
  s!"      (loop $num\n" ++
  s!"        (if (i32.ge_u (local.get $p) (local.get $end)) (then (br $num_done)))\n" ++
  s!"        (local.set $c (i32.load8_u (local.get $p)))\n" ++
  s!"        (br_if $num_done (i32.or (i32.lt_u (local.get $c) (i32.const 48)) (i32.gt_u (local.get $c) (i32.const 57))))\n" ++
  -- same no-wrap decimal discipline as $pf_parse_u64_field
  s!"        (if (i64.gt_u (local.get $v) (i64.const 1844674407370955161)) (then (return (i32.const 0))))\n" ++
  s!"        (if (i64.eq (local.get $v) (i64.const 1844674407370955161)) (then (if (i32.gt_u (i32.sub (local.get $c) (i32.const 48)) (i32.const 5)) (then (return (i32.const 0))))))\n" ++
  s!"        (local.set $v (i64.add (i64.mul (local.get $v) (i64.const 10)) (i64.extend_i32_u (i32.sub (local.get $c) (i32.const 48)))))\n" ++
  s!"        (local.set $any (i32.const 1))\n" ++
  s!"        (local.set $p (i32.add (local.get $p) (i32.const 1)))\n" ++
  s!"        (br $num)))\n" ++
  s!"    (if (i32.eqz (local.get $any)) (then (return (i32.const 0))))\n" ++
  s!"    (if (i64.ne (local.get $v) (local.get $amount)) (then (return (i32.const 0))))\n" ++
  -- closing `\"}]` — exactly one coin in the funds array
  s!"    (if (i32.gt_u (i32.add (local.get $p) (i32.const 3)) (local.get $end)) (then (return (i32.const 0))))\n" ++
  s!"    (if (i32.ne (i32.load8_u (local.get $p)) (i32.const 34)) (then (return (i32.const 0))))\n" ++
  s!"    (if (i32.ne (i32.load8_u (i32.add (local.get $p) (i32.const 1))) (i32.const 125)) (then (return (i32.const 0))))\n" ++
  s!"    (if (i32.ne (i32.load8_u (i32.add (local.get $p) (i32.const 2))) (i32.const 93)) (then (return (i32.const 0))))\n" ++
  s!"    (i32.const 1)\n" ++
  "  )\n" ++
  -- ADR-0031 S1: MessageInfo.sender → pilot Principal leaves.
  -- Needle `"sender":"` is fixed at offset 3241 length 10 (see renderDataSectionV2).
  -- CosmWasm-std serializes MessageInfo as `{"sender":"<addr>","funds":[...]}`
  -- (Addr is a plain JSON string). Copy UTF-8 bytes until the closing `"` into
  -- a fresh 64B zeroed heap buffer (above bump base 4096 — never collides with
  -- static needles or attr/msg scratch), require 1..64 length, then pack LE
  -- u64 body words into `$pf_caller_len` / `$pf_caller_w0`..`$pf_caller_w7`.
  -- Canonical wire is `u32le(len)||sender-utf8`; materialization is len +
  -- 8×UInt64 LE leaves (high body bytes beyond `len` stay 0 from the zeroed
  -- buffer). Traps on missing needle / empty / too-long sender — never forges
  -- env.contract.address or empty-string fallback. Query has no info region
  -- and never calls this helper (Plan view-FC).
  s!"  (func $pf_load_caller_principal\n" ++
  s!"    (local $idx i32) (local $p i32) (local $end i32) (local $c i32) (local $n i32)\n" ++
  s!"    (local $region i32) (local $buf i32)\n" ++
  s!"    (local.set $region (call $pf_allocate (i32.const 64)))\n" ++
  s!"    (local.set $buf (i32.load (local.get $region)))\n" ++
  -- Zero the 64B body so high bytes beyond sender len stay 0.
  s!"    (i64.store (local.get $buf) (i64.const 0))\n" ++
  s!"    (i64.store offset=8 (local.get $buf) (i64.const 0))\n" ++
  s!"    (i64.store offset=16 (local.get $buf) (i64.const 0))\n" ++
  s!"    (i64.store offset=24 (local.get $buf) (i64.const 0))\n" ++
  s!"    (i64.store offset=32 (local.get $buf) (i64.const 0))\n" ++
  s!"    (i64.store offset=40 (local.get $buf) (i64.const 0))\n" ++
  s!"    (i64.store offset=48 (local.get $buf) (i64.const 0))\n" ++
  s!"    (i64.store offset=56 (local.get $buf) (i64.const 0))\n" ++
  s!"    (local.set $idx (call $pf_find (global.get $info_off) (global.get $info_len) (i32.const 3241) (i32.const 10)))\n" ++
  s!"    (if (i32.eq (local.get $idx) (i32.const -1)) (then unreachable))\n" ++
  s!"    (local.set $p (i32.add (i32.add (global.get $info_off) (local.get $idx)) (i32.const 10)))\n" ++
  s!"    (local.set $end (i32.add (global.get $info_off) (global.get $info_len)))\n" ++
  s!"    (local.set $n (i32.const 0))\n" ++
  s!"    (block $copy_done\n" ++
  s!"      (loop $copy\n" ++
  s!"        (if (i32.ge_u (local.get $p) (local.get $end)) (then unreachable))\n" ++
  s!"        (local.set $c (i32.load8_u (local.get $p)))\n" ++
  s!"        (if (i32.eq (local.get $c) (i32.const 34)) (then (br $copy_done)))\n" ++
  s!"        (if (i32.ge_u (local.get $n) (i32.const 64)) (then unreachable))\n" ++
  s!"        (i32.store8 (i32.add (local.get $buf) (local.get $n)) (local.get $c))\n" ++
  s!"        (local.set $n (i32.add (local.get $n) (i32.const 1)))\n" ++
  s!"        (local.set $p (i32.add (local.get $p) (i32.const 1)))\n" ++
  s!"        (br $copy)))\n" ++
  s!"    (if (i32.eqz (local.get $n)) (then unreachable))\n" ++
  s!"    (global.set $pf_caller_len (i64.extend_i32_u (local.get $n)))\n" ++
  s!"    (global.set $pf_caller_w0 (i64.load (local.get $buf)))\n" ++
  s!"    (global.set $pf_caller_w1 (i64.load offset=8 (local.get $buf)))\n" ++
  s!"    (global.set $pf_caller_w2 (i64.load offset=16 (local.get $buf)))\n" ++
  s!"    (global.set $pf_caller_w3 (i64.load offset=24 (local.get $buf)))\n" ++
  s!"    (global.set $pf_caller_w4 (i64.load offset=32 (local.get $buf)))\n" ++
  s!"    (global.set $pf_caller_w5 (i64.load offset=40 (local.get $buf)))\n" ++
  s!"    (global.set $pf_caller_w6 (i64.load offset=48 (local.get $buf)))\n" ++
  s!"    (global.set $pf_caller_w7 (i64.load offset=56 (local.get $buf)))\n" ++
  "  )\n" ++
  -- nativeTransfer/tokenTransfer dst+mint: len ∈ 1..64, zero padding beyond
  -- len in the 64B body, and body bytes restricted to the lowercase bech32
  -- charset [a-z0-9]. The charset gate is what makes raw JSON embedding of
  -- the address injection-safe (no quote/backslash/control bytes possible).
  s!"  (func $pf_dst_check (param $len i64) (param $buf i32) (result i32)\n" ++
  s!"    (local $i i64) (local $b i32)\n" ++
  s!"    (if (i64.eqz (local.get $len)) (then (return (i32.const 0))))\n" ++
  s!"    (if (i64.gt_u (local.get $len) (i64.const 64)) (then (return (i32.const 0))))\n" ++
  s!"    (local.set $i (i64.const 0))\n" ++
  s!"    (block $body_done\n" ++
  s!"      (loop $body_scan\n" ++
  s!"        (br_if $body_done (i64.ge_u (local.get $i) (local.get $len)))\n" ++
  s!"        (local.set $b (i32.load8_u (i32.add (local.get $buf) (i32.wrap_i64 (local.get $i)))))\n" ++
  s!"        (if (i32.eqz (i32.or\n" ++
  s!"              (i32.and (i32.ge_u (local.get $b) (i32.const 48)) (i32.le_u (local.get $b) (i32.const 57)))\n" ++
  s!"              (i32.and (i32.ge_u (local.get $b) (i32.const 97)) (i32.le_u (local.get $b) (i32.const 122)))))\n" ++
  s!"          (then (return (i32.const 0))))\n" ++
  s!"        (local.set $i (i64.add (local.get $i) (i64.const 1)))\n" ++
  s!"        (br $body_scan)))\n" ++
  s!"    (local.set $i (local.get $len))\n" ++
  s!"    (block $done\n" ++
  s!"      (loop $scan\n" ++
  s!"        (br_if $done (i64.ge_u (local.get $i) (i64.const 64)))\n" ++
  s!"        (if (i32.ne (i32.load8_u (i32.add (local.get $buf) (i32.wrap_i64 (local.get $i)))) (i32.const 0)) (then (return (i32.const 0))))\n" ++
  s!"        (local.set $i (i64.add (local.get $i) (i64.const 1)))\n" ++
  s!"        (br $scan)))\n" ++
  s!"    (i32.const 1)\n" ++
  "  )\n" ++
  -- Inner JSON buffer (scratch@{scratch}, cap 512): pre-base64 execute msg body.
  -- Content shape: {"<method>":{"a0":N,...}} (UTF-8 JSON bytes).
  s!"  (func $pf_inner_reset\n" ++
  s!"    (global.set $inner_len (i32.const 0))\n" ++
  "  )\n" ++
  s!"  (func $pf_inner_byte (param $b i32)\n" ++
  s!"    (local $p i32)\n" ++
  s!"    (if (i32.ge_u (global.get $inner_len) (i32.const 512)) (then unreachable))\n" ++
  s!"    (local.set $p (i32.add (i32.const {scratch}) (global.get $inner_len)))\n" ++
  s!"    (i32.store8 (local.get $p) (local.get $b))\n" ++
  s!"    (global.set $inner_len (i32.add (global.get $inner_len) (i32.const 1)))\n" ++
  "  )\n" ++
  -- append ASCII/raw bytes from linear memory to inner JSON buffer
  -- (used by E1-CW tokenTransfer to embed bech32 addresses into the execute msg).
  s!"  (func $pf_inner_bytes (param $off i32) (param $len i32)\n" ++
  s!"    (local $i i32) (local $p i32)\n" ++
  s!"    (if (i32.gt_u (i32.add (global.get $inner_len) (local.get $len)) (i32.const 512)) (then unreachable))\n" ++
  s!"    (local.set $p (i32.add (i32.const {scratch}) (global.get $inner_len)))\n" ++
  s!"    (local.set $i (i32.const 0))\n" ++
  s!"    (block $done\n" ++
  s!"      (loop $copy\n" ++
  s!"        (br_if $done (i32.ge_u (local.get $i) (local.get $len)))\n" ++
  s!"        (i32.store8 (i32.add (local.get $p) (local.get $i))\n" ++
  s!"          (i32.load8_u (i32.add (local.get $off) (local.get $i))))\n" ++
  s!"        (local.set $i (i32.add (local.get $i) (i32.const 1)))\n" ++
  s!"        (br $copy)))\n" ++
  s!"    (global.set $inner_len (i32.add (global.get $inner_len) (local.get $len)))\n" ++
  "  )\n" ++
  s!"  (func $pf_inner_u64 (param $v i64)\n" ++
  s!"    (local $p i32) (local $n i32)\n" ++
  s!"    (if (i32.gt_u (i32.add (global.get $inner_len) (i32.const 24)) (i32.const 512)) (then unreachable))\n" ++
  s!"    (local.set $p (i32.add (i32.const {scratch}) (global.get $inner_len)))\n" ++
  s!"    (local.set $n (call $pf_fmt_u64 (local.get $v) (local.get $p)))\n" ++
  s!"    (global.set $inner_len (i32.add (global.get $inner_len) (local.get $n)))\n" ++
  "  )\n" ++
  -- Base64 alphabet char for sextet 0..63 (A-Za-z0-9+/). Deterministic, no table data.
  s!"  (func $pf_b64_char (param $n i32) (result i32)\n" ++
  s!"    (if (i32.lt_u (local.get $n) (i32.const 26)) (then\n" ++
  s!"      (return (i32.add (local.get $n) (i32.const 65)))))\n" ++  -- A-Z
  s!"    (if (i32.lt_u (local.get $n) (i32.const 52)) (then\n" ++
  s!"      (return (i32.add (i32.sub (local.get $n) (i32.const 26)) (i32.const 97)))))\n" ++  -- a-z
  s!"    (if (i32.lt_u (local.get $n) (i32.const 62)) (then\n" ++
  s!"      (return (i32.add (i32.sub (local.get $n) (i32.const 52)) (i32.const 48)))))\n" ++  -- 0-9
  s!"    (if (i32.eq (local.get $n) (i32.const 62)) (then (return (i32.const 43))))\n" ++  -- +
  s!"    (i32.const 47)\n" ++  -- /
  "  )\n" ++
  -- Standard base64 encode (RFC 4648, with `=` padding). No deps; O(n) lookup.
  -- Writes encoded ASCII to dst; returns encoded byte length ((len+2)/3*4).
  -- Empty input → length 0. Used by SubMsg Binary msg field via $pf_msg_b64.
  s!"  (func $pf_base64_encode (param $src i32) (param $len i32) (param $dst i32) (result i32)\n" ++
  s!"    (local $i i32) (local $o i32) (local $rem i32)\n" ++
  s!"    (local $b0 i32) (local $b1 i32) (local $b2 i32)\n" ++
  s!"    (local.set $i (i32.const 0))\n" ++
  s!"    (local.set $o (i32.const 0))\n" ++
  -- Full 3-byte groups first
  s!"    (block $full_done\n" ++
  s!"      (loop $full\n" ++
  s!"        (br_if $full_done (i32.gt_u (i32.add (local.get $i) (i32.const 3)) (local.get $len)))\n" ++
  s!"        (local.set $b0 (i32.load8_u (i32.add (local.get $src) (local.get $i))))\n" ++
  s!"        (local.set $b1 (i32.load8_u (i32.add (local.get $src) (i32.add (local.get $i) (i32.const 1)))))\n" ++
  s!"        (local.set $b2 (i32.load8_u (i32.add (local.get $src) (i32.add (local.get $i) (i32.const 2)))))\n" ++
  s!"        (i32.store8 (i32.add (local.get $dst) (local.get $o))\n" ++
  s!"          (call $pf_b64_char (i32.shr_u (local.get $b0) (i32.const 2))))\n" ++
  s!"        (i32.store8 (i32.add (local.get $dst) (i32.add (local.get $o) (i32.const 1)))\n" ++
  s!"          (call $pf_b64_char (i32.or (i32.shl (i32.and (local.get $b0) (i32.const 3)) (i32.const 4))\n" ++
  s!"            (i32.shr_u (local.get $b1) (i32.const 4)))))\n" ++
  s!"        (i32.store8 (i32.add (local.get $dst) (i32.add (local.get $o) (i32.const 2)))\n" ++
  s!"          (call $pf_b64_char (i32.or (i32.shl (i32.and (local.get $b1) (i32.const 15)) (i32.const 2))\n" ++
  s!"            (i32.shr_u (local.get $b2) (i32.const 6)))))\n" ++
  s!"        (i32.store8 (i32.add (local.get $dst) (i32.add (local.get $o) (i32.const 3)))\n" ++
  s!"          (call $pf_b64_char (i32.and (local.get $b2) (i32.const 63))))\n" ++
  s!"        (local.set $o (i32.add (local.get $o) (i32.const 4)))\n" ++
  s!"        (local.set $i (i32.add (local.get $i) (i32.const 3)))\n" ++
  s!"        (br $full)))\n" ++
  -- Remainder 1 → XX==  or  2 → XXX=
  s!"    (local.set $rem (i32.sub (local.get $len) (local.get $i)))\n" ++
  s!"    (if (i32.eq (local.get $rem) (i32.const 1)) (then\n" ++
  s!"      (local.set $b0 (i32.load8_u (i32.add (local.get $src) (local.get $i))))\n" ++
  s!"      (i32.store8 (i32.add (local.get $dst) (local.get $o))\n" ++
  s!"        (call $pf_b64_char (i32.shr_u (local.get $b0) (i32.const 2))))\n" ++
  s!"      (i32.store8 (i32.add (local.get $dst) (i32.add (local.get $o) (i32.const 1)))\n" ++
  s!"        (call $pf_b64_char (i32.shl (i32.and (local.get $b0) (i32.const 3)) (i32.const 4))))\n" ++
  s!"      (i32.store8 (i32.add (local.get $dst) (i32.add (local.get $o) (i32.const 2))) (i32.const 61))\n" ++
  s!"      (i32.store8 (i32.add (local.get $dst) (i32.add (local.get $o) (i32.const 3))) (i32.const 61))\n" ++
  s!"      (local.set $o (i32.add (local.get $o) (i32.const 4)))))\n" ++
  s!"    (if (i32.eq (local.get $rem) (i32.const 2)) (then\n" ++
  s!"      (local.set $b0 (i32.load8_u (i32.add (local.get $src) (local.get $i))))\n" ++
  s!"      (local.set $b1 (i32.load8_u (i32.add (local.get $src) (i32.add (local.get $i) (i32.const 1)))))\n" ++
  s!"      (i32.store8 (i32.add (local.get $dst) (local.get $o))\n" ++
  s!"        (call $pf_b64_char (i32.shr_u (local.get $b0) (i32.const 2))))\n" ++
  s!"      (i32.store8 (i32.add (local.get $dst) (i32.add (local.get $o) (i32.const 1)))\n" ++
  s!"        (call $pf_b64_char (i32.or (i32.shl (i32.and (local.get $b0) (i32.const 3)) (i32.const 4))\n" ++
  s!"          (i32.shr_u (local.get $b1) (i32.const 4)))))\n" ++
  s!"      (i32.store8 (i32.add (local.get $dst) (i32.add (local.get $o) (i32.const 2)))\n" ++
  s!"        (call $pf_b64_char (i32.shl (i32.and (local.get $b1) (i32.const 15)) (i32.const 2))))\n" ++
  s!"      (i32.store8 (i32.add (local.get $dst) (i32.add (local.get $o) (i32.const 3))) (i32.const 61))\n" ++
  s!"      (local.set $o (i32.add (local.get $o) (i32.const 4)))))\n" ++
  s!"    (local.get $o)\n" ++
  "  )\n" ++
  -- Encode [src,src+len) as base64 into the messages buffer (Binary string body).
  s!"  (func $pf_msg_b64 (param $src i32) (param $len i32)\n" ++
  s!"    (local $need i32) (local $p i32) (local $n i32)\n" ++
  s!"    (local.set $need (i32.mul (i32.div_u (i32.add (local.get $len) (i32.const 2)) (i32.const 3)) (i32.const 4)))\n" ++
  s!"    (if (i32.gt_u (i32.add (global.get $msg_len) (local.get $need)) (i32.const 1536)) (then unreachable))\n" ++
  s!"    (local.set $p (i32.add (i32.const {msgBase}) (global.get $msg_len)))\n" ++
  s!"    (local.set $n (call $pf_base64_encode (local.get $src) (local.get $len) (local.get $p)))\n" ++
  s!"    (global.set $msg_len (i32.add (global.get $msg_len) (local.get $n)))\n" ++
  "  )\n" ++
  -- append attribute {"key":"K","value":"V"} where V is decimal of u64 temp
  s!"  (func $pf_push_attr_u64 (param $key_off i32) (param $key_len i32) (param $v i64)\n" ++
  s!"    (local $p i32) (local $n i32) (local $i i32)\n" ++
  -- P0-4 fix: the attribute buffer has a fixed 512-byte capacity by layout
  -- (attr..msg). Each entry costs key_len + ≤48 overhead; trap instead of
  -- silently overflowing into the messages buffer (bounded-for emit loops).
  s!"    (if (i32.gt_u (i32.add (i32.add (global.get $attr_len) (local.get $key_len)) (i32.const 48)) (i32.const 512)) (then unreachable))\n" ++
  s!"    (local.set $p (i32.add (i32.const {attrBase}) (global.get $attr_len)))\n" ++
  s!"    (if (i32.ne (global.get $attr_len) (i32.const 0)) (then\n" ++
  s!"      (i32.store8 (local.get $p) (i32.const 44))\n" ++
  s!"      (local.set $p (i32.add (local.get $p) (i32.const 1)))\n" ++
  s!"      (global.set $attr_len (i32.add (global.get $attr_len) (i32.const 1)))))\n" ++
  s!"    (i32.store8 (local.get $p) (i32.const 123))\n" ++
  s!"    (i32.store8 offset=1 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=2 (local.get $p) (i32.const 107))\n" ++
  s!"    (i32.store8 offset=3 (local.get $p) (i32.const 101))\n" ++
  s!"    (i32.store8 offset=4 (local.get $p) (i32.const 121))\n" ++
  s!"    (i32.store8 offset=5 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=6 (local.get $p) (i32.const 58))\n" ++
  s!"    (i32.store8 offset=7 (local.get $p) (i32.const 34))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (i32.const 8)))\n" ++
  s!"    (local.set $i (i32.const 0))\n" ++
  s!"    (block $kdone\n" ++
  s!"      (loop $kcopy\n" ++
  s!"        (br_if $kdone (i32.ge_u (local.get $i) (local.get $key_len)))\n" ++
  s!"        (i32.store8 (i32.add (local.get $p) (local.get $i)) (i32.load8_u (i32.add (local.get $key_off) (local.get $i))))\n" ++
  s!"        (local.set $i (i32.add (local.get $i) (i32.const 1)))\n" ++
  s!"        (br $kcopy)))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (local.get $key_len)))\n" ++
  s!"    (i32.store8 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=1 (local.get $p) (i32.const 44))\n" ++
  s!"    (i32.store8 offset=2 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=3 (local.get $p) (i32.const 118))\n" ++
  s!"    (i32.store8 offset=4 (local.get $p) (i32.const 97))\n" ++
  s!"    (i32.store8 offset=5 (local.get $p) (i32.const 108))\n" ++
  s!"    (i32.store8 offset=6 (local.get $p) (i32.const 117))\n" ++
  s!"    (i32.store8 offset=7 (local.get $p) (i32.const 101))\n" ++
  s!"    (i32.store8 offset=8 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=9 (local.get $p) (i32.const 58))\n" ++
  s!"    (i32.store8 offset=10 (local.get $p) (i32.const 34))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (i32.const 11)))\n" ++
  s!"    (local.set $n (call $pf_fmt_u64 (local.get $v) (local.get $p)))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (local.get $n)))\n" ++
  s!"    (i32.store8 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=1 (local.get $p) (i32.const 125))\n" ++
  s!"    (global.set $attr_len (i32.sub (i32.add (local.get $p) (i32.const 2)) (i32.const {attrBase})))\n" ++
  "  )\n" ++
  s!"  ;; buffers: attr@{attrBase} msg@{msgBase} valueCell@{valueCell} scratch@{scratch}\n" ++
  s!"  ;; scratch[0..512): SubMsg Binary inner JSON; $pf_base64_encode → msg buffer\n"

private partial def renderOperation (memory : MemoryLayout)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (fnNames : Array String)
    (indent : String) : Operation → String
  | .requireLayoutAbsent marker =>
      s!"{indent}(if (call $pf_db_has (i32.const {marker.offset}) (i32.const {marker.length})) (then unreachable))\n"
  | .requireLayout marker value =>
      s!"{indent}(if (i32.eqz (call $pf_db_has (i32.const {marker.offset}) (i32.const {marker.length}))) (then unreachable))\n" ++
        s!"{indent}(if (i64.ne (call $pf_db_load_u64 (i32.const {marker.offset}) (i32.const {marker.length})) (i64.const {value.toNat})) (then unreachable))\n"
  | .zeroState field =>
      s!"{indent}(call $pf_db_store_u64 (i32.const {field.offset}) (i32.const {field.length}) (i64.const 0))\n"
  | .literal destination value =>
      s!"{indent}(local.set $t{destination} (i64.const {value.toNat}))\n"
  | .blockTimeSeconds destination =>
      -- B-CTX-OPEN: env.block.time.seconds() pre-parsed into global at entry.
      -- CosmWasm Timestamp.seconds() is u64 — exact UInt64 fit, no range guard.
      s!"{indent}(local.set $t{destination} (global.get $pf_block_time_secs))\n"
  | .callerPrincipalLen destination =>
      -- ADR-0031 S1: MessageInfo.sender length leaf (pre-parsed at entry).
      s!"{indent}(local.set $t{destination} (global.get $pf_caller_len))\n"
  | .callerPrincipalWord wordIndex destination =>
      -- ADR-0031 S1: one LE body word of sender Principal (pre-parsed at entry).
      let g :=
        match wordIndex with
        | 0 => "$pf_caller_w0" | 1 => "$pf_caller_w1" | 2 => "$pf_caller_w2"
        | 3 => "$pf_caller_w3" | 4 => "$pf_caller_w4" | 5 => "$pf_caller_w5"
        | 6 => "$pf_caller_w6" | 7 => "$pf_caller_w7"
        | _ => "$pf_caller_w0"  -- validatePlan rejects wordIndex ≥ 8
      s!"{indent}(local.set $t{destination} (global.get {g}))\n"
  | .nativeVaultBalance destination =>
      -- ADR-0030 E2-4-CW: query_chain bank balance of env.contract.address.
      s!"{indent}(local.set $t{destination} (call $pf_native_balance (global.get $pf_env_ptr)))\n"
  | .tokenVaultBalance mintLen mintBodyWords resultTemp =>
      -- ADR-0030 E2-4-CW: query_chain CW20 smart-query balanceOf(mint, self).
      -- Reconstruct the mint bech32 address from Principal leaves (len + 8 LE
      -- body words) via $pf_pack_addr, then call $pf_token_balance with the
      -- mint Region. $pf_token_balance takes (env_ptr, mintRegion) → i64.
      let args := s!"(local.get $t{mintLen}) " ++
        String.intercalate " " (mintBodyWords.toList.map fun w => s!"(local.get $t{w})")
      s!"{indent}(local.set $t{resultTemp} (call $pf_token_balance\n" ++
        s!"{indent}    (global.get $pf_env_ptr) (call $pf_pack_addr {args})))\n"
  | .loadParam destination inputOffset =>
      -- Params live in locals $p{inputOffset/8} filled by JSON parse before body.
      s!"{indent}(local.set $t{destination} (local.get $p{inputOffset / 8}))\n"
  | .narrowLoadParam _bitWidth destination inputOffset =>
      -- Range already enforced at JSON entry (`renderParamRangeGuard`); body
      -- copies the same $pN local as UInt64.
      s!"{indent}(local.set $t{destination} (local.get $p{inputOffset / 8}))\n"
  | .loadState destination field =>
      s!"{indent}(local.set $t{destination} (call $pf_db_load_u64 (i32.const {field.offset}) (i32.const {field.length})))\n"
  | .narrowLoadState bitWidth destination field =>
      -- Physical CosmWasm KV is always 8-byte LE. Semantic narrow values live
      -- in the low bytes with high bytes zero; corrupt high bits trap.
      s!"{indent}(local.set $t{destination} (call $pf_db_load_u64 (i32.const {field.offset}) (i32.const {field.length})))\n" ++
        s!"{indent}(if (i64.ne (i64.shr_u (local.get $t{destination}) (i64.const {bitWidth})) (i64.const 0)) (then unreachable))\n"
  | .storeState field value =>
      -- Always 8-byte Region store; narrow temps already high-bit-clean from
      -- body guards / entry range checks (high bytes zero by construction).
      s!"{indent}(call $pf_db_store_u64 (i32.const {field.offset}) (i32.const {field.length}) (local.get $t{value}))\n"
  | .setLayout marker value =>
      s!"{indent}(call $pf_db_store_u64 (i32.const {marker.offset}) (i32.const {marker.length}) (i64.const {value.toNat}))\n"
  | .setReturnData value =>
      s!"{indent}(global.set $ret_kind (i32.const 1))\n" ++
        s!"{indent}(global.set $ret_val (local.get $t{value}))\n"
  | .setReturnDataMulti values =>
      -- B-RET-ABI: store N leaf temps into valueCell (8B each), ret_kind=4.
      -- Capacity guard: N must be 1..8 (Plan validate); trap if >8.
      Id.run do
        let n := values.size
        let mut out :=
          s!"{indent}(if (i32.gt_u (i32.const {n}) (i32.const 8)) (then unreachable))\n" ++
          s!"{indent}(global.set $ret_kind (i32.const 4))\n" ++
          s!"{indent}(global.set $ret_count (i32.const {n}))\n"
        for i in [0:n] do
          let temp := values[i]!
          let off := i * 8
          out := out ++
            s!"{indent}(i64.store offset={off} (i32.const {memory.valueOffset}) (local.get $t{temp}))\n"
        pure out
  | .returnNone =>
      s!"{indent};; return none\n"
  | .returnValue value =>
      s!"{indent}(return (local.get $t{value}))\n"
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
      s!"{indent}(local.set $t{destination} (i64.add (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.lt_s (i64.and (i64.xor (local.get $t{lhs}) (local.get $t{destination})) (i64.xor (local.get $t{rhs}) (local.get $t{destination}))) (i64.const 0)) (then unreachable))\n"
  | .signedCheckedSub destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.sub (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.lt_s (i64.and (i64.xor (local.get $t{lhs}) (local.get $t{rhs})) (i64.xor (local.get $t{lhs}) (local.get $t{destination}))) (i64.const 0)) (then unreachable))\n"
  | .signedCheckedMul destination lhs rhs =>
      -- P0-3 fix: (-1) × Int64.min silently wrapped (result min, unrepresentable
      -- as +min). Guard the single hole before the multiply; the existing
      -- divide-round-trip check covers every other lhs.
      s!"{indent}(if (i64.eq (local.get $t{lhs}) (i64.const -1)) (then (if (i64.eq (local.get $t{rhs}) (i64.const -9223372036854775808)) (then unreachable))))\n" ++
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
      let insn := match op with
        | .eq => "i64.eq" | .ne => "i64.ne" | .lt => "i64.lt_s"
        | .le => "i64.le_s" | .gt => "i64.gt_s" | .ge => "i64.ge_s"
      s!"{indent}(local.set $t{destination} (i64.extend_i32_u ({insn} (local.get $t{lhs}) (local.get $t{rhs}))))\n"
  | .checkedNeg destination source =>
      s!"{indent}(if (i64.eq (local.get $t{source}) (i64.const -9223372036854775808)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.sub (i64.const 0) (local.get $t{source})))\n"
  | .compare destination lhs rhs op =>
      let insn := match op with
        | .eq => "i64.eq" | .ne => "i64.ne" | .lt => "i64.lt_u"
        | .le => "i64.le_u" | .gt => "i64.gt_u" | .ge => "i64.ge_u"
      s!"{indent}(local.set $t{destination} (i64.extend_i32_u ({insn} (local.get $t{lhs}) (local.get $t{rhs}))))\n"
  | .assert condition =>
      s!"{indent}(if (i64.eqz (local.get $t{condition})) (then unreachable))\n"
  | .bitAnd destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.and (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .bitOr destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.or (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .bitXor destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.xor (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .bitNot destination source =>
      s!"{indent}(local.set $t{destination} (i64.xor (local.get $t{source}) (i64.const -1)))\n"
  | .shl destination lhs rhs =>
      s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const 64)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.shl (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.ne (i64.shr_u (local.get $t{destination}) (local.get $t{rhs})) (local.get $t{lhs})) (then unreachable))\n"
  | .shr destination lhs rhs =>
      s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const 64)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.shr_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .sar destination lhs rhs =>
      s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const 64)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.shr_s (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .narrowCheckedAdd bitWidth destination lhs rhs =>
      -- i64.add then high bits above bitWidth must be zero (overflow trap).
      s!"{indent}(local.set $t{destination} (i64.add (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.ne (i64.shr_u (local.get $t{destination}) (i64.const {bitWidth})) (i64.const 0)) (then unreachable))\n"
  | .narrowCheckedSub _bitWidth destination lhs rhs =>
      -- Underflow guard identical to UInt64; result auto in-range for UInt.
      s!"{indent}(if (i64.lt_u (local.get $t{lhs}) (local.get $t{rhs})) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.sub (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .narrowCheckedMul bitWidth destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.mul (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.ne (i64.shr_u (local.get $t{destination}) (i64.const {bitWidth})) (i64.const 0)) (then unreachable))\n"
  | .narrowCheckedDiv _bitWidth destination lhs rhs =>
      s!"{indent}(if (i64.eqz (local.get $t{rhs})) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.div_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .narrowCheckedMod _bitWidth destination lhs rhs =>
      s!"{indent}(if (i64.eqz (local.get $t{rhs})) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.rem_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .narrowBitAnd _bitWidth destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.and (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .narrowBitOr _bitWidth destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.or (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .narrowBitXor _bitWidth destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.xor (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .narrowBitNot bitWidth destination source =>
      let mask :=
        match bitWidth with
        | 8 => "255"
        | 16 => "65535"
        | 32 => "4294967295"
        | _ => "18446744073709551615"
      s!"{indent}(local.set $t{destination} (i64.and (i64.xor (local.get $t{source}) (i64.const -1)) (i64.const {mask})))\n"
  | .narrowShl bitWidth destination lhs rhs =>
      -- Count ≥ 64 trap; shl; high bits above bitWidth must be 0.
      s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const 64)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.shl (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.ne (i64.shr_u (local.get $t{destination}) (i64.const {bitWidth})) (i64.const 0)) (then unreachable))\n"
  | .narrowShr _bitWidth destination lhs rhs =>
      s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const 64)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.shr_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .boolNot destination source =>
      s!"{indent}(local.set $t{destination} (i64.extend_i32_u (i64.eqz (local.get $t{source}))))\n"
  | .boolAnd destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.and (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .boolOr destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.or (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .callFn fnIndex destination args =>
      let name := fnNames[fnIndex]!
      let argList := String.intercalate " " (args.toList.map fun a => s!"(local.get $t{a})")
      s!"{indent}(local.set $t{destination} (call $fn_{name} {argList}))\n"
  | .emitEvent eventIndex args =>
      let binding := events[eventIndex]!
      -- Attribute key = event name; value = first arg decimal (MVP multi-arg: first only + count)
      if args.isEmpty then
        s!"{indent};; emit {binding.name} (no args)\n" ++
          s!"{indent}(call $pf_push_attr_u64 (i32.const 0) (i32.const 0) (i64.const 0))\n"
      else
        -- Use event name from static data — embed via immediate store of name bytes into scratch
        Id.run do
          let nameBytes := binding.name.toUTF8
          let mut out := s!"{indent};; emit event {binding.name}\n"
          -- write event name to a fixed scratch slot at valueOffset+16
          let nameOff := memory.valueOffset + 16
          for i in [0:nameBytes.size] do
            out := out ++
              s!"{indent}(i32.store8 (i32.const {nameOff + i}) (i32.const {nameBytes[i]!.toNat}))\n"
          out := out ++
            s!"{indent}(call $pf_push_attr_u64 (i32.const {nameOff}) (i32.const {nameBytes.size}) (local.get $t{args[0]!}))\n"
          pure out
  | .promiseAccount receiver method args =>
      -- CW-4 SubMsg JSON into messages buffer. WasmMsg::Execute.msg is Binary:
      -- base64(UTF-8 of {"<method>":{"a0":N,...}}), matching cosmwasm-std/
      -- wasmd serde (not a nested JSON object).
      --
      -- Outer shape:
      -- {"id":0,"msg":{"wasm":{"execute":{"contract_addr":"<receiver>",
      --   "msg":"<base64>","funds":[]}}},"reply_on":"never"}
      --
      -- Honesty:
      -- * contract_addr = static QN join (receiver); NOT bech32 AccAddress.
      -- * msg = Binary (base64); inner JSON object key = method, fields a0..
      -- * gas_limit omitted (= None). payload omitted (serde default empty).
      -- * id=0 = cosmwasm_std::UNUSED_MSG_ID.
      -- * reply_on=never: no reply entrypoint; same-tx dispatch; submsg failure
      --   fails parent tx (wasmd DispatchSubmessages). See Plan docstring.
      Id.run do
        let _ := events
        let _ := errors
        let _ := fnNames
        let scratch := memory.inputOffset
        -- Full shape comment (searchable in WAT; Binary msg, not nested object).
        let shapeHint :=
          "{\"id\":0,\"msg\":{\"wasm\":{\"execute\":{\"contract_addr\":\"" ++
          receiver ++ "\",\"msg\":\"<base64>\",\"funds\":[]}}},\"reply_on\":\"never\"}"
        let binaryDoc :=
          "base64(UTF-8 of {\"" ++ method ++ "\":{\"a0\":N,...}})"
        let mut out :=
          s!"{indent};; schedule SubMsg reply_on=never → {receiver} / {method}\n" ++
          s!"{indent};; SubMsg shape (Binary msg): {shapeHint}\n" ++
          s!"{indent};; Binary = {binaryDoc}\n"
        -- 1) Build inner execute-msg JSON into scratch via $pf_inner_*.
        out := out ++ s!"{indent}(call $pf_inner_reset)\n"
        let emitInner (s : String) : String := Id.run do
          let bytes := s.toUTF8
          let mut t := ""
          for i in [0:bytes.size] do
            t := t ++ s!"{indent}(call $pf_inner_byte (i32.const {bytes[i]!.toNat}))\n"
          pure t
        out := out ++ emitInner "{\""
        out := out ++ emitInner method
        out := out ++ emitInner "\":{"
        for i in [0:args.size] do
          if i > 0 then
            out := out ++ emitInner ","
          out := out ++ emitInner s!"\"a{i}\":"
          out := out ++ s!"{indent}(call $pf_inner_u64 (local.get $t{args[i]!}))\n"
        out := out ++ emitInner "}}"
        -- 2) Append SubMsg envelope into messages buffer; msg field = base64.
        -- Leading comma when messages buffer already non-empty
        out := out ++
          s!"{indent}(if (i32.ne (global.get $msg_len) (i32.const 0)) (then\n" ++
          s!"{indent}  (call $pf_msg_byte (i32.const 44))))\n"
        let emitLit (s : String) : String := Id.run do
          let bytes := s.toUTF8
          let mut t := ""
          for i in [0:bytes.size] do
            t := t ++ s!"{indent}(call $pf_msg_byte (i32.const {bytes[i]!.toNat}))\n"
          pure t
        out := out ++ emitLit "{\"id\":0,\"msg\":{\"wasm\":{\"execute\":{\"contract_addr\":\""
        out := out ++ emitLit receiver
        out := out ++ emitLit "\",\"msg\":\""
        -- Binary body: base64-encode scratch[0..inner_len) into msg buffer
        out := out ++
          s!"{indent}(call $pf_msg_b64 (i32.const {scratch}) (global.get $inner_len))\n"
        out := out ++ emitLit "\",\"funds\":[]}}},\"reply_on\":\"never\"}"
        pure out
  | .nativeDeposit amount =>
      -- ADR-0029 C1: exact one-coin info.funds check (denom "stake", amount).
      s!"{indent}(if (i32.eqz (call $pf_funds_exact (local.get $t{amount}))) (then unreachable))\n"
  | .requireFundsEmpty =>
      -- ADR-0029 C1: non-deposit mutate/init requires `"funds":[]`.
      s!"{indent}(if (i32.eqz (call $pf_funds_empty)) (then unreachable))\n"
  | .nativeTransfer dstLen dstBodyWords amount =>
      -- ADR-0029 C1: BankMsg::Send SubMsg (reply_on=never, error-propagating).
      -- {"id":0,"msg":{"bank":{"send":{"to_address":"<dst>","amount":
      --   [{"denom":"stake","amount":"<N>"}]}}},"reply_on":"never"}
      Id.run do
        let _ := events
        let _ := errors
        let _ := fnNames
        let dstBuf := memory.valueOffset + 16
        let mut out :=
          s!"{indent};; pf.assets.native.transfer → BankMsg::Send reply_on=never\n"
        -- materialize 8 body words into a contiguous 64-byte dst buffer
        for j in [0:dstBodyWords.size] do
          out := out ++
            s!"{indent}(i64.store (i32.const {dstBuf + 8 * j}) (local.get $t{dstBodyWords[j]!}))\n"
        -- len ∈ 1..64 and zero padding beyond len
        out := out ++
          s!"{indent}(if (i32.eqz (call $pf_dst_check (local.get $t{dstLen}) (i32.const {dstBuf}))) (then unreachable))\n"
        -- leading comma when messages buffer already non-empty
        out := out ++
          s!"{indent}(if (i32.ne (global.get $msg_len) (i32.const 0)) (then\n" ++
          s!"{indent}  (call $pf_msg_byte (i32.const 44))))\n"
        let emitLit (s : String) : String := Id.run do
          let bytes := s.toUTF8
          let mut t := ""
          for i in [0:bytes.size] do
            t := t ++ s!"{indent}(call $pf_msg_byte (i32.const {bytes[i]!.toNat}))\n"
          pure t
        out := out ++ emitLit "{\"id\":0,\"msg\":{\"bank\":{\"send\":{\"to_address\":\""
        out := out ++
          s!"{indent}(call $pf_msg_bytes (i32.const {dstBuf}) (i32.wrap_i64 (local.get $t{dstLen})))\n"
        out := out ++ emitLit "\",\"amount\":[{\"denom\":\"stake\",\"amount\":\""
        out := out ++ s!"{indent}(call $pf_msg_u64 (local.get $t{amount}))\n"
        out := out ++ emitLit "\"}]}}},\"reply_on\":\"never\"}"
        pure out
  | .tokenTransfer mintLen mintBodyWords dstLen dstBodyWords amount =>
      -- ADR-0030 E1-CW: WasmMsg::Execute SubMsg (reply_on=never, error-propagating).
      -- {"id":0,"msg":{"wasm":{"execute":{"contract_addr":"<mint>",
      --   "msg":"<base64 of {"transfer":{"recipient":"<dst>","amount":"<N>"}}>",
      --   "funds":[]}}},"reply_on":"never"}
      --
      -- mint and dst are bech32 contract addresses materialized from Principal
      -- wire leaves (len + 8×u64 LE body words → 64-byte buffer, len bytes used).
      -- The inner execute-msg JSON is built in the inner scratch buffer and
      -- base64-encoded into the messages buffer (same Binary discipline as
      -- promiseAccount schedule SubMsg).
      Id.run do
        let _ := events
        let _ := errors
        let _ := fnNames
        let scratch := memory.inputOffset
        let mintBuf := memory.valueOffset + 16
        let dstBuf := memory.valueOffset + 16 + 64
        let mut out :=
          s!"{indent};; pf.assets.token.transfer → WasmMsg::Execute reply_on=never\n"
        -- materialize 8 mint body words into a contiguous 64-byte mint buffer
        for j in [0:mintBodyWords.size] do
          out := out ++
            s!"{indent}(i64.store (i32.const {mintBuf + 8 * j}) (local.get $t{mintBodyWords[j]!}))\n"
        -- mint len ∈ 1..64 and zero padding beyond len
        out := out ++
          s!"{indent}(if (i32.eqz (call $pf_dst_check (local.get $t{mintLen}) (i32.const {mintBuf}))) (then unreachable))\n"
        -- materialize 8 dst body words into a contiguous 64-byte dst buffer
        for j in [0:dstBodyWords.size] do
          out := out ++
            s!"{indent}(i64.store (i32.const {dstBuf + 8 * j}) (local.get $t{dstBodyWords[j]!}))\n"
        -- dst len ∈ 1..64 and zero padding beyond len
        out := out ++
          s!"{indent}(if (i32.eqz (call $pf_dst_check (local.get $t{dstLen}) (i32.const {dstBuf}))) (then unreachable))\n"
        -- 1) Build inner execute-msg JSON into scratch via $pf_inner_*.
        --    Shape: {"transfer":{"recipient":"<dst>","amount":"<N>"}}
        out := out ++ s!"{indent}(call $pf_inner_reset)\n"
        let emitInner (s : String) : String := Id.run do
          let bytes := s.toUTF8
          let mut t := ""
          for i in [0:bytes.size] do
            t := t ++ s!"{indent}(call $pf_inner_byte (i32.const {bytes[i]!.toNat}))\n"
          pure t
        out := out ++ emitInner "{\"transfer\":{\"recipient\":\""
        out := out ++
          s!"{indent}(call $pf_inner_bytes (i32.const {dstBuf}) (i32.wrap_i64 (local.get $t{dstLen})))\n"
        out := out ++ emitInner "\",\"amount\":\""
        out := out ++ s!"{indent}(call $pf_inner_u64 (local.get $t{amount}))\n"
        out := out ++ emitInner "\"}}"
        -- 2) Append SubMsg envelope into messages buffer; msg field = base64.
        out := out ++
          s!"{indent}(if (i32.ne (global.get $msg_len) (i32.const 0)) (then\n" ++
          s!"{indent}  (call $pf_msg_byte (i32.const 44))))\n"
        let emitLit (s : String) : String := Id.run do
          let bytes := s.toUTF8
          let mut t := ""
          for i in [0:bytes.size] do
            t := t ++ s!"{indent}(call $pf_msg_byte (i32.const {bytes[i]!.toNat}))\n"
          pure t
        out := out ++ emitLit "{\"id\":0,\"msg\":{\"wasm\":{\"execute\":{\"contract_addr\":\""
        out := out ++
          s!"{indent}(call $pf_msg_bytes (i32.const {mintBuf}) (i32.wrap_i64 (local.get $t{mintLen})))\n"
        out := out ++ emitLit "\",\"msg\":\""
        out := out ++
          s!"{indent}(call $pf_msg_b64 (i32.const {scratch}) (global.get $inner_len))\n"
        out := out ++ emitLit "\",\"funds\":[]}}},\"reply_on\":\"never\"}"
        pure out
  | .revertError errorIndex args =>
      let binding := errors[errorIndex]!
      let nameBytes := binding.name.toUTF8
      Id.run do
        let nameOff := memory.valueOffset + 16
        let mut out := s!"{indent};; revert {binding.name}\n"
        for i in [0:nameBytes.size] do
          out := out ++
            s!"{indent}(i32.store8 (i32.const {nameOff + i}) (i32.const {nameBytes[i]!.toNat}))\n"
        -- Build error result and return it (caller entrypoints use block+br or direct return)
        out := out ++
          s!"{indent}(return (call $pf_error_result (i32.const {nameOff}) (i32.const {nameBytes.size})))\n"
        pure out
  | .ifRegion condition thenOps elseOps =>
      let thenText := thenOps.foldl (fun o op =>
        o ++ renderOperation memory events errors fnNames (indent ++ "  ") op) ""
      let elseText := elseOps.foldl (fun o op =>
        o ++ renderOperation memory events errors fnNames (indent ++ "  ") op) ""
      let thenBody := if thenText.isEmpty then s!"{indent}  nop\n" else thenText
      let elseBody := if elseText.isEmpty then s!"{indent}  nop\n" else elseText
      s!"{indent}(if (i64.ne (local.get $t{condition}) (i64.const 0))\n" ++
        s!"{indent}  (then\n" ++ thenBody ++
        s!"{indent}  )\n" ++
        s!"{indent}  (else\n" ++ elseBody ++
        s!"{indent}  )\n" ++
        s!"{indent})\n"
  | .switchRegion scrutinee cases defaultOps =>
      let rec renderCases (indent : String) (remaining : List (UInt64 × Array Operation)) : String :=
        match remaining with
        | [] =>
            defaultOps.foldl (fun o op =>
              o ++ renderOperation memory events errors fnNames indent op) ""
        | (caseValue, caseOps) :: rest =>
            let caseText := caseOps.foldl (fun o op =>
              o ++ renderOperation memory events errors fnNames (indent ++ "  ") op) ""
            let elseText := renderCases (indent ++ "  ") rest
            let elseBody := if elseText.isEmpty then s!"{indent}  nop\n" else elseText
            let caseBody := if caseText.isEmpty then s!"{indent}    nop\n" else caseText
            s!"{indent}(if (i64.eq (local.get $t{scrutinee}) (i64.const {caseValue.toNat}))\n" ++
              s!"{indent}  (then\n" ++ caseBody ++
              s!"{indent}  )\n" ++
              s!"{indent}  (else\n" ++ elseBody ++
              s!"{indent}  )\n" ++
              s!"{indent})\n"
      renderCases indent cases.toList
  | .forRegion varTemp initial counterTemp maxIterations condOps condition bodyOps updateOps updateValue =>
      let condText := condOps.foldl (fun o op =>
        o ++ renderOperation memory events errors fnNames (indent ++ "    ") op) ""
      let bodyText := bodyOps.foldl (fun o op =>
        o ++ renderOperation memory events errors fnNames (indent ++ "    ") op) ""
      let updateText := updateOps.foldl (fun o op =>
        o ++ renderOperation memory events errors fnNames (indent ++ "    ") op) ""
      s!"{indent}(local.set $t{varTemp} (local.get $t{initial}))\n" ++
        s!"{indent}(local.set $t{counterTemp} (i64.const 0))\n" ++
        s!"{indent}(block $for_break_{varTemp}\n" ++
        s!"{indent}  (loop $for_loop_{varTemp}\n" ++
        condText ++
        s!"{indent}    (br_if $for_break_{varTemp} (i64.eqz (local.get $t{condition})))\n" ++
        bodyText ++
        -- back-edge bound: after body, if counter >= maxIterations trap (N+1 body then trap)
        s!"{indent}    (if (i64.ge_u (local.get $t{counterTemp}) (i64.const {maxIterations})) (then unreachable))\n" ++
        s!"{indent}    (local.set $t{counterTemp} (i64.add (local.get $t{counterTemp}) (i64.const 1)))\n" ++
        updateText ++
        s!"{indent}    (local.set $t{varTemp} (local.get $t{updateValue}))\n" ++
        s!"{indent}    (br $for_loop_{varTemp})\n" ++
        s!"{indent}  )\n" ++
        s!"{indent})\n"

private def renderFn (ir : IR) (fn : FnIR) : String :=
  let fnNames := ir.fns.map (·.name)
  let params := String.intercalate "" <| (Array.range fn.paramCount).toList.map fun index =>
    s!" (param $t{index} i64)"
  let extraLocals :=
    if fn.tempCount <= fn.paramCount then ""
    else
      String.intercalate "" <|
        (List.range (fn.tempCount - fn.paramCount)).map fun i =>
          s!" (local $t{fn.paramCount + i} i64)"
  let operations := String.intercalate "" <| fn.operations.toList.map
    (renderOperation ir.memory ir.sourcePlan.events ir.sourcePlan.errors fnNames "    ")
  s!"  (func $fn_{fn.name}{params} (result i64){extraLocals}\n" ++
    operations ++ "  )\n"

/-- Render method body as an internal func `$m_<name>` used by entry dispatch.
    Params arrive in `$p0..` locals (filled by JSON parse at call site). -/
private def renderMethodBody (ir : IR) (method : MethodIR) : String :=
  let fnNames := ir.fns.map (·.name)
  let paramLocals := String.intercalate "" <| (Array.range method.params.size).toList.map fun i =>
    s!" (param $p{i} i64)"
  let temps := String.intercalate "" <| (Array.range method.tempCount).toList.map fun i =>
    s!" (local $t{i} i64)"
  let operations := String.intercalate "" <| method.operations.toList.map
    (renderOperation ir.memory ir.sourcePlan.events ir.sourcePlan.errors fnNames "    ")
  -- Methods return i32 region ptr for ContractResult (via setReturnData globals + pf_ok_result)
  -- View: scalar → pf_query_ok(ret_val); aggregate (ret_kind=4) → pf_query_ok_agg.
  let epilogue :=
    match method.mode with
    | .view =>
        -- Typed if (result i32): aggregate vs scalar query ok builders.
        "    (return (if (result i32) (i32.eq (global.get $ret_kind) (i32.const 4))\n" ++
        "      (then (call $pf_query_ok_agg))\n" ++
        "      (else (call $pf_query_ok (global.get $ret_val)))))\n"
    | .initialize | .mutate =>
        "    (return (call $pf_ok_result))\n"
  s!"  (func $m_{method.name}{paramLocals} (result i32){temps}\n" ++
    "    (call $pf_reset_result)\n" ++
    operations ++ epilogue ++ "  )\n"

/-- Static data: key strings + quoted method/param needles for JSON scan.
    P0-1 fix: needles live in `[3000, 4096)` — a compile-time capacity gate
    must prove keysEnd ≤ 3000 and every needle end ≤ 4096 (bump heap base),
    failing closed at Plan/IR emission instead of silently overlapping the
    heap for long/many method names. -/
private def renderDataSectionV2 (ir : IR) (keysEnd : Nat) : Except CompileError (String × Array (String × Nat × Nat) × Array (String × Nat × Nat)) := do
  let needleBase := 3000
  let heapBase := 4096
  if keysEnd > needleBase then
    throw <| .planInvariant .cosmwasm
      s!"static key data end {keysEnd} overlaps needle base {needleBase}"
  let mut out := ""
  for key in ir.keys do
    out := out ++ s!"  (data (i32.const {key.offset}) \"{key.key}\")\n"
  let mut off := needleBase
  -- B-CTX-OPEN: fixed first needle `"time"` for Env.block.time Timestamp parse.
  -- cosmwasm-std serializes Timestamp/Uint64 as a JSON string of nanoseconds.
  -- Length 6 (`"time"`); reserved even when unused so offsets stay stable.
  let timeNeedleBytes := "\"time\"".toUTF8
  if off + timeNeedleBytes.size + 1 > heapBase then
    throw <| .planInvariant .cosmwasm
      s!"time needle would overlap bump heap at {heapBase}"
  out := out ++ s!"  (data (i32.const {off}) \"\\\"time\\\"\")\n"
  -- Helper $pf_env_block_time_seconds hard-codes this offset/len (must stay 3000/6).
  unless off == 3000 && timeNeedleBytes.size == 6 do
    throw <| .planInvariant .cosmwasm
      "internal: time needle must be at offset 3000 with length 6"
  off := off + timeNeedleBytes.size + 1
  -- ADR-0029 C1: funds needles at fixed offsets 3007 / 3018 (helpers hard-code).
  -- `"funds":[]` (10B) gates requireFundsEmpty;
  -- `"funds":[{"denom":"stake","amount":"` (34B) anchors nativeDeposit.
  let fundsEmptyNeedle := "\"funds\":[]".toUTF8
  if off + fundsEmptyNeedle.size + 1 > heapBase then
    throw <| .planInvariant .cosmwasm
      "funds-empty needle would overlap bump heap"
  out := out ++ s!"  (data (i32.const {off}) \"\\\"funds\\\":[]\")\n"
  unless off == 3007 && fundsEmptyNeedle.size == 10 do
    throw <| .planInvariant .cosmwasm
      "internal: funds-empty needle must be at offset 3007 with length 10"
  off := off + fundsEmptyNeedle.size + 1
  let fundsExactNeedle := "\"funds\":[{\"denom\":\"stake\",\"amount\":\"".toUTF8
  if off + fundsExactNeedle.size + 1 > heapBase then
    throw <| .planInvariant .cosmwasm
      "funds-exact needle would overlap bump heap"
  let fundsExactData :=
    "  (data (i32.const " ++ toString off ++ ") " ++
    "\"\\\"funds\\\":[{\\\"denom\\\":\\\"stake\\\",\\\"amount\\\":\\\"" ++ "\")\n"
  out := out ++ fundsExactData
  unless off == 3018 && fundsExactNeedle.size == 36 do
    throw <| .planInvariant .cosmwasm
      "internal: funds-exact needle must be at offset 3018 with length 36"
  off := off + fundsExactNeedle.size + 1
  -- ADR-0030 E2-4-CW: env-read needles at fixed offsets (helpers hard-code).
  -- `"contract":{"address":"` (23B) anchors env.contract.address extraction.
  let envContractNeedle := "\"contract\":{\"address\":\"".toUTF8
  if off + envContractNeedle.size + 1 > heapBase then
    throw <| .planInvariant .cosmwasm
      "env-contract needle would overlap bump heap"
  out := out ++ ("  (data (i32.const " ++ toString off ++ ") \"\\\"contract\\\":{\\\"address\\\":\\\"\")\n")
  unless off == 3055 && envContractNeedle.size == 23 do
    throw <| .planInvariant .cosmwasm
      "internal: env-contract needle must be at offset 3055 with length 23"
  off := off + envContractNeedle.size + 1
  -- `","denom":"stake"}}}` (20B) — bank query request suffix (after self addr).
  let bankReqSuffixNeedle := "\",\"denom\":\"stake\"}}}".toUTF8
  if off + bankReqSuffixNeedle.size + 1 > heapBase then
    throw <| .planInvariant .cosmwasm
      "bank-req-suffix needle would overlap bump heap"
  out := out ++ s!"  (data (i32.const {off}) \"\\\",\\\"denom\\\":\\\"stake\\\"}}}\")\n"
  unless off == 3079 && bankReqSuffixNeedle.size == 20 do
    throw <| .planInvariant .cosmwasm
      "internal: bank-req-suffix needle must be at offset 3079 with length 20"
  off := off + bankReqSuffixNeedle.size + 1
  -- `{"bank":{"balance":{"address":"` (31B) — bank query request prefix.
  let bankReqPrefixNeedle := "{\"bank\":{\"balance\":{\"address\":\"".toUTF8
  if off + bankReqPrefixNeedle.size + 1 > heapBase then
    throw <| .planInvariant .cosmwasm
      "bank-req-prefix needle would overlap bump heap"
  out := out ++ ("  (data (i32.const " ++ toString off ++ ") \"{\\\"bank\\\":{\\\"balance\\\":{\\\"address\\\":\\\"\")\n")
  unless off == 3100 && bankReqPrefixNeedle.size == 31 do
    throw <| .planInvariant .cosmwasm
      "internal: bank-req-prefix needle must be at offset 3100 with length 31"
  off := off + bankReqPrefixNeedle.size + 1
  -- `{"wasm":{"smart":{"contract_addr":"` (35B) — wasm smart query prefix.
  let wasmSmartPrefixNeedle := "{\"wasm\":{\"smart\":{\"contract_addr\":\"".toUTF8
  if off + wasmSmartPrefixNeedle.size + 1 > heapBase then
    throw <| .planInvariant .cosmwasm
      "wasm-smart-prefix needle would overlap bump heap"
  out := out ++ ("  (data (i32.const " ++ toString off ++ ") \"{\\\"wasm\\\":{\\\"smart\\\":{\\\"contract_addr\\\":\\\"\")\n")
  unless off == 3132 && wasmSmartPrefixNeedle.size == 35 do
    throw <| .planInvariant .cosmwasm
      "internal: wasm-smart-prefix needle must be at offset 3132 with length 35"
  off := off + wasmSmartPrefixNeedle.size + 1
  -- `","msg":"` (9B) — wasm smart query Binary msg quote anchor; the CW20
  -- execute msg JSON is base64-encoded after this anchor (Binary is a base64
  -- string in the QueryRequest envelope, not inline JSON).
  let wasmMsgQuoteNeedle := "\",\"msg\":\"".toUTF8
  if off + wasmMsgQuoteNeedle.size + 1 > heapBase then
    throw <| .planInvariant .cosmwasm
      "wasm-msg-quote needle would overlap bump heap"
  out := out ++ ("  (data (i32.const " ++ toString off ++ ") \"\\\",\\\"msg\\\":\\\"\")\n")
  unless off == 3168 && wasmMsgQuoteNeedle.size == 9 do
    throw <| .planInvariant .cosmwasm
      "internal: wasm-msg-quote needle must be at offset 3168 with length 9"
  off := off + wasmMsgQuoteNeedle.size + 1
  -- `{"balance":{"address":"` (23B) — inner CW20 balance query prefix.
  let innerBalancePrefixNeedle := "{\"balance\":{\"address\":\"".toUTF8
  if off + innerBalancePrefixNeedle.size + 1 > heapBase then
    throw <| .planInvariant .cosmwasm
      "inner-balance-prefix needle would overlap bump heap"
  out := out ++ ("  (data (i32.const " ++ toString off ++ ") \"{\\\"balance\\\":{\\\"address\\\":\\\"\")\n")
  unless off == 3178 && innerBalancePrefixNeedle.size == 23 do
    throw <| .planInvariant .cosmwasm
      "internal: inner-balance-prefix needle must be at offset 3178 with length 23"
  off := off + innerBalancePrefixNeedle.size + 1
  -- `"}}` (3B) — inner CW20 balance query suffix (address quote + 2 closes).
  let innerBalanceSuffixNeedle := "\"}}".toUTF8
  if off + innerBalanceSuffixNeedle.size + 1 > heapBase then
    throw <| .planInvariant .cosmwasm
      "inner-balance-suffix needle would overlap bump heap"
  out := out ++ s!"  (data (i32.const {off}) \"\\\"}}\")\n"
  unless off == 3202 && innerBalanceSuffixNeedle.size == 3 do
    throw <| .planInvariant .cosmwasm
      "internal: inner-balance-suffix needle must be at offset 3202 with length 3"
  off := off + innerBalanceSuffixNeedle.size + 1
  -- `"}}}` (4B) — wasm smart query envelope suffix (b64 quote + 3 closes).
  let wasmSmartSuffixNeedle := "\"}}}".toUTF8
  if off + wasmSmartSuffixNeedle.size + 1 > heapBase then
    throw <| .planInvariant .cosmwasm
      "wasm-smart-suffix needle would overlap bump heap"
  out := out ++ s!"  (data (i32.const {off}) \"\\\"}}}\")\n"
  unless off == 3206 && wasmSmartSuffixNeedle.size == 4 do
    throw <| .planInvariant .cosmwasm
      "internal: wasm-smart-suffix needle must be at offset 3206 with length 4"
  off := off + wasmSmartSuffixNeedle.size + 1
  -- `"amount":"` (10B) — balance decimal scan in decoded BalanceResponse.
  let amountNeedle := "\"amount\":\"".toUTF8
  if off + amountNeedle.size + 1 > heapBase then
    throw <| .planInvariant .cosmwasm
      "amount needle would overlap bump heap"
  out := out ++ s!"  (data (i32.const {off}) \"\\\"amount\\\":\\\"\")\n"
  unless off == 3211 && amountNeedle.size == 10 do
    throw <| .planInvariant .cosmwasm
      "internal: amount needle must be at offset 3211 with length 10"
  off := off + amountNeedle.size + 1
  -- `"ok":"` (6B) — query_chain response inner-ok quote anchor.
  let okQuoteNeedle := "\"ok\":\"".toUTF8
  if off + okQuoteNeedle.size + 1 > heapBase then
    throw <| .planInvariant .cosmwasm
      "ok-quote needle would overlap bump heap"
  out := out ++ s!"  (data (i32.const {off}) \"\\\"ok\\\":\\\"\")\n"
  unless off == 3222 && okQuoteNeedle.size == 6 do
    throw <| .planInvariant .cosmwasm
      "internal: ok-quote needle must be at offset 3222 with length 6"
  off := off + okQuoteNeedle.size + 1
  -- `"balance":"` (11B) — CW20 BalanceResponse balance decimal scan
  -- (bank uses `"amount":"` at 3211; CW20 uses `"balance":"` here).
  let balanceNeedle := "\"balance\":\"".toUTF8
  if off + balanceNeedle.size + 1 > heapBase then
    throw <| .planInvariant .cosmwasm
      "balance needle would overlap bump heap"
  out := out ++ s!"  (data (i32.const {off}) \"\\\"balance\\\":\\\"\")\n"
  unless off == 3229 && balanceNeedle.size == 11 do
    throw <| .planInvariant .cosmwasm
      "internal: balance needle must be at offset 3229 with length 11"
  off := off + balanceNeedle.size + 1
  -- ADR-0031 S1: `"sender":"` (10B) anchors MessageInfo.sender extraction.
  -- Fixed at 3241 so $pf_load_caller_principal can hard-code the offset.
  let senderNeedle := "\"sender\":\"".toUTF8
  if off + senderNeedle.size + 1 > heapBase then
    throw <| .planInvariant .cosmwasm
      "sender needle would overlap bump heap"
  out := out ++ s!"  (data (i32.const {off}) \"\\\"sender\\\":\\\"\")\n"
  unless off == 3241 && senderNeedle.size == 10 do
    throw <| .planInvariant .cosmwasm
      "internal: sender needle must be at offset 3241 with length 10"
  off := off + senderNeedle.size + 1
  let mut methodNeedles : Array (String × Nat × Nat) := #[]
  for method in ir.methods do
    -- WAT string containing the bytes of `"name"` (quotes included for JSON find).
    let needleBytes := s!"\"{method.name}\"".toUTF8
    if off + needleBytes.size + 1 > heapBase then
      throw <| .planInvariant .cosmwasm
        s!"method needle '{method.name}' would overlap bump heap at {heapBase}"
    out := out ++ s!"  (data (i32.const {off}) \"\\\"{method.name}\\\"\")\n"
    methodNeedles := methodNeedles.push (method.name, off, needleBytes.size)
    off := off + needleBytes.size + 1
  let mut paramNeedles : Array (String × Nat × Nat) := #[]
  for method in ir.methods do
    for p in method.params do
      let needleBytes := s!"\"{p.name}\"".toUTF8
      if off + needleBytes.size + 1 > heapBase then
        throw <| .planInvariant .cosmwasm
          s!"param needle '{method.name}.{p.name}' would overlap bump heap at {heapBase}"
      out := out ++ s!"  (data (i32.const {off}) \"\\\"{p.name}\\\"\")\n"
      paramNeedles := paramNeedles.push (s!"{method.name}.{p.name}", off, needleBytes.size)
      off := off + needleBytes.size + 1
  pure (out, methodNeedles, paramNeedles)

private def findNeedle (needles : Array (String × Nat × Nat)) (key : String) : Nat × Nat :=
  match needles.find? (fun p => p.1 == key) with
  | some (_, off, len) => (off, len)
  | none => (0, 0)

/-- After JSON decimal parse into `$p{i}`, reject values outside the param's
    admitted ABI width. Critical honesty for JSON number inputs: never silently
    truncate UInt8/16/32. UInt64 keeps the existing `pf_parse_u64_field` bound
    alone (`2^64−1`). Narrow: trap if `shr_u p bitWidth ≠ 0`. -/
private def renderParamRangeGuard (indent : String) (i : Nat) (byteWidth : Nat) : String :=
  let bitWidth := byteWidth * 8
  if bitWidth ≥ 64 then ""
  else
    s!"{indent}(if (i64.ne (i64.shr_u (local.get $p{i}) (i64.const {bitWidth})) (i64.const 0)) (then unreachable))\n"

/-- B-CTX-OPEN: capture env.block.time.seconds into the shared global before
    method bodies that may read `context.unixTimeSeconds`. Always set so any
    Plan using `.blockTimeSeconds` sees a fresh value per entry call. -/
private def renderLoadBlockTime (indent : String) : String :=
  s!"{indent}(global.set $pf_block_time_secs (call $pf_env_block_time_seconds (local.get $env_ptr)))\n"

/-- ADR-0031 S1: parse MessageInfo.sender into Principal leaf globals before
    execute/instantiate method bodies. Requires `$info_off`/`$info_len` already
    set. Query never calls this (no MessageInfo; view Plan FC on caller). -/
private def renderLoadCallerPrincipal (indent : String) : String :=
  s!"{indent}(call $pf_load_caller_principal)\n"

private def renderInstantiate (ir : IR) (paramNeedles : Array (String × Nat × Nat)) : String :=
  Id.run do
    let init := ir.methods[0]!  -- initializer is always first
    let mut parse := ""
    for i in [0:init.params.size] do
      let p := init.params[i]!
      let (off, len) := findNeedle paramNeedles s!"{init.name}.{p.name}"
      parse := parse ++
        s!"    (local.set $p{i} (call $pf_parse_u64_field (local.get $msg_off) (local.get $msg_len) (i32.const {off}) (i32.const {len})))\n" ++
        renderParamRangeGuard "    " i p.byteWidth
    let args := String.intercalate " " <| (Array.range init.params.size).toList.map fun i =>
      s!"(local.get $p{i})"
    let paramLocals := String.intercalate "" <| (Array.range init.params.size).toList.map fun i =>
      s!" (local $p{i} i64)"
    pure <|
      "  (func (export \"instantiate\") (param $env_ptr i32) (param $info_ptr i32) (param $msg_ptr i32) (result i32)\n" ++
        "    (local $msg_off i32) (local $msg_len i32)" ++ paramLocals ++ "\n" ++
        "    (local.set $msg_off (call $pf_region_off (local.get $msg_ptr)))\n" ++
        "    (local.set $msg_len (call $pf_region_len (local.get $msg_ptr)))\n" ++
        "    (global.set $info_off (call $pf_region_off (local.get $info_ptr)))\n" ++
        "    (global.set $info_len (call $pf_region_len (local.get $info_ptr)))\n" ++
        "    (global.set $pf_env_ptr (local.get $env_ptr))\n" ++
        renderLoadBlockTime "    " ++
        renderLoadCallerPrincipal "    " ++
        parse ++
        s!"    (return (call $m_{init.name} {args}))\n" ++
        "  )\n"

private def renderExecute (ir : IR) (methodNeedles paramNeedles : Array (String × Nat × Nat)) : String :=
  Id.run do
    let entries := ir.methods[1:].toArray.filter (fun m => m.mode == .mutate)
    let mut dispatch := ""
    for method in entries do
      let (mOff, mLen) := findNeedle methodNeedles method.name
      let mut parse := ""
      for i in [0:method.params.size] do
        let p := method.params[i]!
        let (off, len) := findNeedle paramNeedles s!"{method.name}.{p.name}"
        parse := parse ++
          s!"        (local.set $p{i} (call $pf_parse_u64_field (local.get $msg_off) (local.get $msg_len) (i32.const {off}) (i32.const {len})))\n" ++
          renderParamRangeGuard "        " i p.byteWidth
      let args := String.intercalate " " <| (Array.range method.params.size).toList.map fun i =>
        s!"(local.get $p{i})"
      dispatch := dispatch ++
        s!"    (if (i32.ne (call $pf_find (local.get $msg_off) (local.get $msg_len) (i32.const {mOff}) (i32.const {mLen})) (i32.const -1)) (then\n" ++
        parse ++
        s!"        (return (call $m_{method.name} {args}))\n" ++
        "      ))\n"
    let maxParams := entries.foldl (fun n m => max n m.params.size) 0
    let paramLocals := String.intercalate "" <| (Array.range maxParams).toList.map fun i =>
      s!" (local $p{i} i64)"
    pure <|
      "  (func (export \"execute\") (param $env_ptr i32) (param $info_ptr i32) (param $msg_ptr i32) (result i32)\n" ++
        "    (local $msg_off i32) (local $msg_len i32)" ++ paramLocals ++ "\n" ++
        "    (local.set $msg_off (call $pf_region_off (local.get $msg_ptr)))\n" ++
        "    (local.set $msg_len (call $pf_region_len (local.get $msg_ptr)))\n" ++
        "    (global.set $info_off (call $pf_region_off (local.get $info_ptr)))\n" ++
        "    (global.set $info_len (call $pf_region_len (local.get $info_ptr)))\n" ++
        "    (global.set $pf_env_ptr (local.get $env_ptr))\n" ++
        renderLoadBlockTime "    " ++
        renderLoadCallerPrincipal "    " ++
        dispatch ++
        "    (return (call $pf_error_result (i32.const 0) (i32.const 0)))\n" ++
        "  )\n"

private def renderQuery (ir : IR) (methodNeedles paramNeedles : Array (String × Nat × Nat)) : String :=
  Id.run do
    let views := ir.methods[1:].toArray.filter (fun m => m.mode == .view)
    let mut dispatch := ""
    for method in views do
      let (mOff, mLen) := findNeedle methodNeedles method.name
      let mut parse := ""
      for i in [0:method.params.size] do
        let p := method.params[i]!
        let (off, len) := findNeedle paramNeedles s!"{method.name}.{p.name}"
        parse := parse ++
          s!"        (local.set $p{i} (call $pf_parse_u64_field (local.get $msg_off) (local.get $msg_len) (i32.const {off}) (i32.const {len})))\n" ++
          renderParamRangeGuard "        " i p.byteWidth
      let args := String.intercalate " " <| (Array.range method.params.size).toList.map fun i =>
        s!"(local.get $p{i})"
      dispatch := dispatch ++
        s!"    (if (i32.ne (call $pf_find (local.get $msg_off) (local.get $msg_len) (i32.const {mOff}) (i32.const {mLen})) (i32.const -1)) (then\n" ++
        parse ++
        s!"        (return (call $m_{method.name} {args}))\n" ++
        "      ))\n"
    let maxParams := views.foldl (fun n m => max n m.params.size) 0
    let paramLocals := String.intercalate "" <| (Array.range maxParams).toList.map fun i =>
      s!" (local $p{i} i64)"
    pure <|
      "  (func (export \"query\") (param $env_ptr i32) (param $msg_ptr i32) (result i32)\n" ++
        "    (local $msg_off i32) (local $msg_len i32)" ++ paramLocals ++ "\n" ++
        "    (local.set $msg_off (call $pf_region_off (local.get $msg_ptr)))\n" ++
        "    (local.set $msg_len (call $pf_region_len (local.get $msg_ptr)))\n" ++
        "    (global.set $pf_env_ptr (local.get $env_ptr))\n" ++
        renderLoadBlockTime "    " ++
        dispatch ++
        "    (return (call $pf_error_result (i32.const 0) (i32.const 0)))\n" ++
        "  )\n"

private def renderWat (ir : IR) : Except CompileError String := do
  let keysEnd := ir.keys.foldl (fun acc key => max acc (key.offset + key.length)) 64
  let (dataSec, methodNeedles, paramNeedles) ← renderDataSectionV2 ir keysEnd
  let imports := String.intercalate "" <| ir.imports.toList.map renderImport
  let helpers := renderRuntimeHelpers ir.memory
  let fns := String.intercalate "" <| ir.fns.toList.map (renderFn ir)
  let methodBodies := String.intercalate "" <| ir.methods.toList.map (renderMethodBody ir)
  let allocateExport :=
    "  (func (export \"allocate\") (param $size i32) (result i32)\n" ++
    "    (call $pf_allocate (local.get $size))\n" ++
    "  )\n"
  let deallocateExport :=
    "  (func (export \"deallocate\") (param $region_ptr i32)\n" ++
    "    nop\n" ++
    "  )\n"
  let versionExport :=
    "  (func (export \"interface_version_8\") (result i32)\n" ++
    "    (i32.const 8)\n" ++
    "  )\n"
  pure ("(module\n" ++ imports ++
    "  (memory (export \"memory\") 1)\n" ++
    dataSec ++
    helpers ++
    allocateExport ++ deallocateExport ++ versionExport ++
    fns ++ methodBodies ++
    renderInstantiate ir paramNeedles ++
    renderExecute ir methodNeedles paramNeedles ++
    renderQuery ir methodNeedles paramNeedles ++
    ")\n")

private def renderMode : MethodMode → String
  | .initialize => "instantiate"
  | .mutate => "execute"
  | .view => "query"

/-- ABI JSON type token from Plan semantic byteWidth (physical KV remains
    8-byte LE Region; JSON params are decimal with exact range check). -/
private def renderAbiTypeString (byteWidth : Nat) : String :=
  match byteWidth with
  | 1 => "u8"
  | 2 => "u16"
  | 4 => "u32"
  | _ => "u64"

private def renderParamJson (param : Param) : String :=
  s!"\{\"name\":\"{Targets.escapeJson param.name}\",\"type\":\"{renderAbiTypeString param.byteWidth}\"}"

private def renderMethodJson (method : Method) : String :=
  let returns :=
    match method.resultKind with
    | .unit => "null"
    | .uint64 => "\"u64\""
    | .uint8 => "\"u8\""
    | .uint16 => "\"u16\""
    | .uint32 => "\"u32\""
    | .bool => "\"bool\""
    | .int64 => "\"i64\""
    -- B-RET-ABI: leaf tuple as a JSON array of leaf type strings
    -- (execute result attr / query ok = decimal JSON array string).
    | .aggregate leaves =>
        let parts := leaves.toList.map fun (leaf : LeafAbiType) =>
          if leaf.isInt then "\"i64\"" else "\"u64\""
        "[" ++ String.intercalate "," parts ++ "]"
    | _ => "\"u64\""
  "{" ++
    s!"\"name\":\"{Targets.escapeJson method.name}\"," ++
    s!"\"export\":\"{renderMode method.mode}\"," ++
    s!"\"mode\":\"{renderMode method.mode}\"," ++
    s!"\"args\":[{String.intercalate "," (method.params.toList.map renderParamJson)}]," ++
    s!"\"returns\":{returns}" ++
    "}"

private def renderAbi (plan : Plan) : String :=
  let fields := String.intercalate "," (plan.storage.fields.toList.map fun f =>
    s!"\{\"name\":\"{Targets.escapeJson f.name}\",\"key\":\"{Targets.escapeJson f.key}\",\"type\":\"{renderAbiTypeString f.byteWidth}\"}")
  let methods := #[plan.initializer] ++ plan.entries
  let exports := String.intercalate ",\n    " (methods.toList.map renderMethodJson)
  "{\n" ++
    "  \"schema\": \"proof-forge-cosmwasm-abi/v1alpha1\",\n" ++
    s!"  \"program\": \"{Targets.escapeJson plan.programName}\",\n" ++
    s!"  \"codegenProfile\": \"{plan.codegenProfile}\",\n" ++
    s!"  \"hostAbi\": \"{plan.hostAbi}\",\n" ++
    s!"  \"encoding\": \"{plan.inputAbi}\",\n" ++
    "  \"entrypoints\": [\"instantiate\",\"execute\",\"query\",\"allocate\",\"deallocate\",\"interface_version_8\"],\n" ++
    "  \"imports\": [\"env.db_read\",\"env.db_write\",\"env.db_remove\",\"env.abort\"],\n" ++
    "  \"region\": {\"size\":12,\"fields\":[\"offset:u32\",\"capacity:u32\",\"length:u32\"]},\n" ++
    "  \"jsonSubset\": \"flat-instantiate-params | {\\\"method\\\":{params}} decimal integers\",\n" ++
    "  \"storage\": {" ++
    s!"\"markerKey\":\"{plan.storage.markerKey}\"," ++
    s!"\"fields\":[{fields}]" ++
    "},\n" ++
    "  \"methods\": [\n    " ++ exports ++ "\n  ]\n" ++
    "}\n"

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
  validateIR ir
  let wat ← renderWat ir
  return #[
    {
      path := s!"{ir.name}.wat"
      mediaType := "application/wasm-text"
      contents := wat
    },
    {
      path := s!"{ir.name}.cosmwasm-abi.json"
      mediaType := "application/json"
      contents := renderAbi ir.sourcePlan
    }
  ]

def irFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult IR := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  lower plan

def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCapability capability
  emitFromIR ir

/-- Engineering Plan → IR (CW-4 schedule pin tests; not product capability path). -/
def engineeringIrFromPlan (plan : Plan) : CompileResult IR := do
  validatePlan plan
  lower plan

/-- Engineering Plan → WAT/ABI files (CW-4 schedule pin tests). -/
def engineeringFilesFromPlan (plan : Plan) : CompileResult (Array OutputFile) := do
  let ir ← engineeringIrFromPlan plan
  emitFromIR ir

end ProofForgeV2.Targets.CosmWasm
