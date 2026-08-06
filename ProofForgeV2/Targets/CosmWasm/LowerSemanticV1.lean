import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1
import ProofForgeV2.Targets.CosmWasm.PfAssetsCatalogV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.RequirementIdsV1

/-!
# CosmWasm LowerSemanticV1 — Plan types + SemanticProgramV1 → Plan lowering

Owns the CosmWasm-owned Plan surface and Semantic→Plan body.

## ADR-0029 Phase C1 — `pf.assets` native binding

Void `Op.ExternalCall` whose callee is in the closed `pf.assets` catalog is
admitted only when the retained freeze carries exact `extension.pf-assets`,
and only for the Phase C bank subset:

* `pf.assets.native.deposit(amount)` — entry requires exact one-coin
  `info.funds` with frozen denom (`stake`) and amount == arg; non-deposit
  mutate/init entries require empty funds.
* `pf.assets.native.transfer(dst, amount)` — BankMsg::Send SubMsg with
  `reply_on=never` (error-propagating; coexists with CW-4 async schedule).

## ADR-0030 E1-CW — `pf.assets.token.transfer` CW20 binding

* `pf.assets.token.transfer(mint, dst, amount)` — WasmMsg::Execute SubMsg
  targeting the CW20 contract at `mint` with `{"transfer":{"recipient":dst,
  "amount":"<amount>"}}` and `reply_on=never` (error-propagating, same sync
  discipline as C1). `mint` is a controlled dynamic callee (catalog token
  family only). Entry stays non-payable (no `info.funds` movement).

Token/async catalog QNs and non-catalog sync call stay fail closed.
-/

namespace ProofForgeV2.Targets.CosmWasm

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.RequirementIdsV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1
open ProofForgeV2.Targets.CosmWasm.PfAssetsCatalogV1

/-- Shared descriptor data (single source: DescriptorDataV1). -/
def descriptor : TargetDescriptor := DescriptorDataV1.cosmwasm

def hostAbiVersion : String := "cosmwasm-host-abi-v1"
def rawInputAbi : String := "cosmwasm-json-msg-v1"
def stateLayoutDomain : String := "proof-forge-cosmwasm-layout-v1:"
def layoutMarkerKey : String := "pf:cw:v1:layout"

inductive Endianness where
  | little
  deriving BEq, Inhabited, Repr

inductive PayloadInitializationPolicy where
  | zeroAllFields
  deriving BEq, Inhabited, Repr

inductive FailureAction where
  | trap
  | returnStatus
  deriving BEq, Inhabited, Repr

structure FailurePolicy where
  invalidInput : FailureAction
  uninitializedLayout : FailureAction
  corruptStorage : FailureAction
  arithmeticOverflow : FailureAction
  nonzeroDeposit : FailureAction
  deriving BEq, Inhabited, Repr

inductive ReceiptCommitPolicy where
  | rollbackOnTrap
  | retainWritesOnTrap
  deriving BEq, Inhabited, Repr

inductive MethodMode where
  | initialize
  | mutate
  | view
  deriving BEq, Inhabited, Repr

inductive DepositPolicy where
  | requireZero
  | queryOnly
  /-- ADR-0029 C1: entry body contains `nativeDeposit`; runtime requires
      exact one-coin `info.funds` of the frozen native denom equal to the
      deposit amount expression. At most one deposit per method. -/
  | requireExactNative
  deriving BEq, Inhabited, Repr

/-- CosmWasm MVP host imports (cosmwasm-std / wasmd env).
    No iterator (db_scan/db_next), no IBC, no query_chain at MVP. -/
inductive HostImport where
  | dbRead
  | dbWrite
  | dbRemove
  | abort
  /-- ADR-0030 E2-4-CW: `env.query_chain` — cosmwasm-vm canonical raw-WASM
      querier channel. Takes a Region containing a serialized
      `QueryRequest<Empty>` JSON; returns a Region containing a
      `QuerierResult` (`SystemResult<ContractResult<Binary>>`) JSON. -/
  | queryChain
  deriving BEq, Inhabited, Repr

structure ResourceLimits where
  maxArtifactStemBytes : Nat
  maxStateFields : Nat
  maxEntries : Nat
  maxParams : Nat
  maxBodyStatements : Nat
  maxExprDepth : Nat
  maxPlanNodes : Nat
  maxRecipeNodes : Nat
  maxMethodLocals : Nat
  wasmMemoryPages : Nat
  deriving BEq, Inhabited, Repr

structure StorageField where
  sourceId : Nat
  name : String
  key : String
  byteWidth : Nat
  endianness : Endianness
  deriving BEq, Inhabited, Repr

structure StorageLayout where
  markerKey : String
  markerValue : UInt64
  payloadInitialization : PayloadInitializationPolicy
  fields : Array StorageField
  /-- T12 Principal: `stateLeaves[stateId]` lists physical field indices for that
      logical state (scalar → singleton; Principal → 9 leaves). Empty array means
      legacy 1:1 `fields[stateId]`. -/
  stateLeaves : Array (Array Nat) := #[]
  /-- Exact `extension.pf-assets` row present in retained requirements
      (ADR-0029 C1 QN gate). Not part of planDigest storage identity. -/
  pfAssetsDeclared : Bool := false
  deriving BEq, Inhabited, Repr

structure Param where
  sourceId : Nat
  name : String
  inputOffset : Nat
  byteWidth : Nat
  endianness : Endianness
  deriving BEq, Inhabited, Repr

/-- Unsigned comparison operators for the public-UInt64 comparison envelope. -/
inductive ComparisonOp where
  | eq | ne | lt | le | gt | ge
  deriving BEq, Inhabited, Repr

inductive Expr where
  | literal (value : UInt64)
  /-- Multi-limb literal for UInt128/256 (T9e). `bitWidth ∈ {128,256}`. -/
  | bigLiteral (bitWidth : Nat) (value : Nat)
  | param (inputOffset : Nat)
  /-- Narrow ABI param load (`bitWidth ∈ {8,16,32}`); UInt64/Int64 keep `param`. -/
  | narrowParam (bitWidth : Nat) (inputOffset : Nat)
  | stateLoad (fieldIndex : Nat)
  /-- Narrow ABI state load (`bitWidth ∈ {8,16,32}`); UInt64/Int64 keep `stateLoad`. -/
  | narrowStateLoad (bitWidth : Nat) (fieldIndex : Nat)
  | checkedAdd (lhs rhs : Expr)
  | checkedSub (lhs rhs : Expr)
  | checkedMul (lhs rhs : Expr)
  | checkedDiv (lhs rhs : Expr)
  | checkedMod (lhs rhs : Expr)
  | bitAnd (lhs rhs : Expr)
  | bitOr (lhs rhs : Expr)
  | bitXor (lhs rhs : Expr)
  /-- UInt64 left shift by a UInt32 count (zero-extended into the plan literal /
      temp surface). Count ≥ 64 and result overflow trap. -/
  | shl (lhs rhs : Expr)
  /-- UInt64 logical right shift by a UInt32 count. Count ≥ 64 traps. -/
  | shr (lhs rhs : Expr)
  | signedCheckedAdd (lhs rhs : Expr)
  | signedCheckedSub (lhs rhs : Expr)
  | signedCheckedMul (lhs rhs : Expr)
  | signedCheckedDiv (lhs rhs : Expr)
  | signedCheckedMod (lhs rhs : Expr)
  | signedCompare (op : ComparisonOp) (lhs rhs : Expr)
  | checkedNeg (operand : Expr)
  | sar (lhs rhs : Expr)
  | bitNot (operand : Expr)
  /-- Narrow body checked arithmetic (`bitWidth ∈ {8,16,32}`); UInt64 keeps historical. -/
  | narrowCheckedAdd (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedSub (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedMul (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedDiv (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedMod (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitAnd (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitOr (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitXor (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitNot (bitWidth : Nat) (operand : Expr)
  | narrowShl (bitWidth : Nat) (lhs rhs : Expr)
  | narrowShr (bitWidth : Nat) (lhs rhs : Expr)
  | boolNot (operand : Expr)
  /-- Strict Bool AND on 0/1 words (both sides always evaluate). -/
  | boolAnd (lhs rhs : Expr)
  /-- Strict Bool OR on 0/1 words (both sides always evaluate). -/
  | boolOr (lhs rhs : Expr)
  | compare (op : ComparisonOp) (lhs rhs : Expr)
  /-- Multiword unsigned compare (`bitWidth ∈ {128,256}`); result Bool. -/
  | wideCompare (bitWidth : Nat) (op : ComparisonOp) (lhs rhs : Expr)
  | callFn (fnIndex : Nat) (args : Array Expr)
  /-- Mutable plan-local (loop induction). Index is method-local and unique per
      forLoop; IR lowering maps it to a stable Wasm temp rewritten each latch. -/
  | localTemp (index : Nat)
  /-- B-CTX-OPEN: CosmWasm `env.block.time.seconds()` — host Env JSON field
      `"time"` is a Timestamp of **nanoseconds** (cosmwasm-std string); IR divides
      by 10^9 (truncating) so DSL `context.unixTimeSeconds` holds exactly.
      Result is u64 from `.seconds()` — exact UInt64 fit, **no** range guard
      (unlike EVM's 256-bit `timestamp()` word). UInt64-typed. -/
  | blockTimeSeconds
  /-- ADR-0031 S2: CosmWasm `env.block.height` — host Env JSON field `"height"`
      is a bare u64 decimal number (cosmwasm-std `BlockInfo.height: u64`, not a
      string). Result is exact UInt64 — **no** range guard (height is already
      u64; `pf_parse_u64_field` traps only on digit overflow past 2^64−1).
      Available on instantiate/execute/**query** (Env always present). -/
  | blockHeight
  /-- ADR-0030 E2-4-CW: `pf.assets.native.balanceOfSelf()` — read-only host
      query via `env.query_chain` (bank balance of `env.contract.address` in
      the frozen `stake` denom). Zero args; result UInt64. View/entry-callable,
      effect-free. Emitted as a WAT helper that builds the
      `{"bank":{"balance":{"address":<self>,"denom":"stake"}}}` request Region,
      calls `env.query_chain`, and parses `.amount`. -/
  | nativeVaultBalance
  /-- ADR-0031 S1: length leaf of `context.caller` Principal wire identity
      assembled from CosmWasm `MessageInfo.sender` UTF-8 bytes:
      `u32le(len) || sender-utf8` materialized as pilot Principal leaves
      (len + 8×UInt64 LE body, zero-padded). Runtime value is the sender
      byte length (1..64). **View-forbidden**: CosmWasm `query` has no
      MessageInfo; view/pureFn bodies using this key fail closed at Plan.
      Execute (`entry`) and instantiate (`init`) bind real `info.sender`.
      Does **not** unlock Principal→AccAddress CALL mapping. -/
  | callerPrincipalLen
  /-- ADR-0031 S1: one LE body word of `context.caller` Principal
      (`wordIndex ∈ 0..7`). Body is sender UTF-8 bytes packed little-endian
      into 8×UInt64 with high bytes zero beyond `len`. See
      `callerPrincipalLen`. -/
  | callerPrincipalWord (wordIndex : Nat)
  deriving BEq, Inhabited, Repr

structure Store where
  fieldIndex : Nat
  value : Expr
  /-- Physical store width in bytes (`1/2/4/8/16/32`). Default 8 keeps historical
      UInt64/Int64 Plan literals byte-identical. -/
  byteWidth : Nat := 8
  deriving BEq, Inhabited, Repr

inductive Statement where
  | store (operation : Store)
  /-- Multi-leaf atomic store for one aggregate StateStore (Principal / Array /
      Map / Bytes / named Struct/Enum). IR lowers as two-phase snapshot: evaluate
      every leaf Expr against the pre-store KV, then write all leaves. Sequential
      leaf stores would re-read already-written occ/key/val mid-upsert (empty-Map
      put hazard). Distinct `storeAtomic` statements remain ordered; later ones
      see earlier writes (Token dual Map store). Scalar StateStore keeps single
      `.store`. -/
  | storeAtomic (leaves : Array Store)
  | returnValue (value : Expr)
  /-- B-RET-ABI: multi-leaf aggregate return (named Struct/Enum or admitted
      anonymous Array/Option). `leaves` are per-leaf expressions in preorder
      flatten order; `leafIsInt` is parallel. Emitted as one JSON array of
      decimal strings (execute result attribute / query `ok` string), matching
      the existing scalar decimal JSON ABI idiom. -/
  | returnAggregate (leaves : Array Expr) (leafIsInt : Array Bool)
  | returnNone
  | assert (condition : Expr)
  | emitEvent (eventIndex : Nat) (args : Array Expr)
  | revertError (errorIndex : Nat) (args : Array Expr)
  | ifThenElse (condition : Expr) (thenBody elseBody : Array Statement)
  | switchOn (scrutinee : Expr) (cases : Array (UInt64 × Array Statement))
      (defaultBody : Array Statement)
  /-- Bounded for-loop recovered from a Semantic header/latch CFG. `varTemp` is
      the induction local; `condition`/`update`/`body` may mention `.localTemp
      varTemp`. `maxIterations` is the static Normalize bound enforced at the
      back edge after each completed body (bodies 1..N pass; the (N+1)-th body
      runs then traps; a `return` inside any body exits before the check). The
      latch update is unchecked `i+1` at WAT level because the body only runs
      while `i < end ≤ UInt64.max`. -/
  | forLoop (varTemp : Nat) (initial : Expr) (condition : Expr) (update : Expr)
      (maxIterations : Nat) (body : Array Statement)
  /-- Async workflow schedule lowered to a CosmWasm `SubMsg` with
      `reply_on = never` (CW-4).

      Plan fields:
      * `receiver` — callee QualifiedName components joined by `.` (verbatim;
        must pass the CosmWasm receiver-stub grammar — no silent case fold).
        Emit uses this string as `WasmMsg::Execute.contract_addr`. **It is a
        static QN identity stub, not a bech32 AccAddress**; deploy-time rewrite
        is required (same honesty class as EVM keccak-addr / Solana
        sha256-program-id stubs).
      * `method` — last QN component (safe identifier); becomes the execute
        message object key inside the Binary-encoded JSON payload.
      * `args` — anonymous public UInt64/Int64 values (Normalize schedule
        surface); encoded as decimal JSON fields `a0`..`aN-1` in source order.
        Emit packs `{"method":{"a0":N,...}}` as UTF-8 then base64 into
        `WasmMsg::Execute.msg` (cosmwasm-std Binary).

      ## wasmd `reply_on=Never` semantics (verified, wasmd ≥0.54 / main)

      Sources:
      * `x/wasm/keeper/msg_dispatcher.go` `MessageDispatcher.DispatchSubmessages`
        (wasmd main / v0.54+ same control flow):
        - Each SubMsg runs in `ctx.CacheContext()` savepoint.
        - On success: `commit()` submsg state; no reply callback when
          `ReplyOn == ReplyNever` (continue to next SubMsg).
        - On failure: discard savepoint (submsg state NOT committed); for
          `ReplyNever`, **return `err` to the parent dispatch**
          (`if (ReplySuccess || ReplyNever) && err != nil { return nil, err }`).
          Parent tx therefore fails; parent contract state is rolled back with
          the atomic Cosmos SDK transaction. This is **not**
          "parent continues / parent state retained on submsg failure".
        - Unit coverage: `msg_dispatcher_test.go` case
          `"never reply - with error"` → `expErr: true`, `expCommits: false`.
      * `packages/std/src/results/submessages.rs` (`cosmwasm-std`):
        - `ReplyOn::Never` = "Never make a callback - this is like the original
          CosmosMsg semantics"; `SubMsg::reply_never` / `UNUSED_MSG_ID = 0`.
        - Struct doc: on error, submessage partial state reverts; calling
          contract state is preserved **only when a reply path handles the
          error** (ReplyError/Always/Success). ReplyNever has no reply path, so
          the dispatcher propagates the error instead.

      ## Mapping to ReferenceV1 `Op.Schedule`

      Reference records schedule as an ordered effect with **no response cursor**
      (`ReferenceMachineV1` schedule arm: push `.schedule` effect, continue;
      no external-response wait). CosmWasm `reply_on=never` matches the
      **no-reply / no response channel** half of that model.

      Honest caveats (B-CALL-SEM / not full platform async):
      1. **Same-transaction sequential dispatch**, not cross-tx async (unlike
         NEAR `promise_batch_*` fire-and-forget across receipts).
      2. **Submsg failure fails the whole tx** under ReplyNever (see wasmd
         above) — stronger coupling than Reference schedule, which never waits
         on the receiver.
      3. `contract_addr` is a QN stub, not a real chain address.

      Deposit/gas are not Plan fields; emit uses empty `funds: []` and omits
      `gas_limit` (None / unlimited within parent gas). -/
  | promiseAccount (receiver : String) (method : String) (args : Array Expr)
  /-- ADR-0029 C1: `pf.assets.native.deposit(amount)`. Runtime exact-eq
      `info.funds == [{denom: frozenNative, amount}]` (one coin). Entry
      depositPolicy becomes `.requireExactNative`. -/
  | nativeDeposit (amount : Expr)
  /-- ADR-0029 C1: `pf.assets.native.transfer(dst, amount)`.
      `dstLen` + 8 LE body words are the Principal wire identity leaves
      (`len + 8×UInt64`); runtime requires framed UTF-8 bech32 body
      (`u32le(len)||utf8-bech32-bytes`), then enqueues BankMsg::Send SubMsg
      with `reply_on=never` (error-propagating; see PfAssetsCatalogV1).
      Opaque external effect on bank balances (no recipient code execution). -/
  | nativeTransfer (dstLen : Expr) (dstBodyWords : Array Expr) (amount : Expr)
  /-- ADR-0030 E1-CW: `pf.assets.token.transfer(mint, dst, amount)`.
      `mintLen` + 8 LE body words are the CW20 contract address Principal
      wire identity leaves (`len + 8×UInt64`); runtime requires framed UTF-8
      bech32 body (`u32le(len)||utf8-bech32-bytes`), used as
      `WasmMsg::Execute.contract_addr`. `dstLen` + 8 LE body words are the
      recipient Principal (same encoding contract as C1 native transfer dst).
      Emits `WasmMsg::Execute { contract_addr: mint, msg:
      {"transfer":{"recipient":dst,"amount":"<amount>"}}, funds: [] }` as
      SubMsg `reply_on=never` (error-propagating; failure of the CW20 call
      traps the whole transaction — sync, same as C1). The contract's own
      CW20 balance is the vault; no `info.funds` movement. -/
  | tokenTransfer (mintLen : Expr) (mintBodyWords : Array Expr)
      (dstLen : Expr) (dstBodyWords : Array Expr) (amount : Expr)
  /-- ADR-0030 E2-4-CW: `pf.assets.token.balanceOfSelf(mint)`.
      `mintLen` + 8 LE body words are the CW20 contract address Principal
      wire identity leaves (`len + 8×UInt64`); used as
      `WasmQuery::Smart.contract_addr`. Emits a `query_chain` host call with
      `{"wasm":{"smart":{"contract_addr":<mint>,"msg":<base64 of
      {"balance":{"address":<self>}}>}}}` (`msg` is a `Binary`, base64 in the
      QueryRequest JSON); decodes the CW20 `BalanceResponse.balance` (Uint128
      decimal string) and requires it to fit UInt64 (else trap). Read-only,
      view/entry-callable, effect-free. `resultTemp` is the ValueId-canonical
      temp bound to the returned UInt64 word. -/
  | tokenVaultBalance (mintLen : Expr) (mintBodyWords : Array Expr)
      (resultTemp : Nat)
  deriving BEq, Inhabited, Repr

/-- ABI type of one aggregate return leaf. B-RET-ABI pilot: leaves are
UInt64/Int64 words (`isInt` selects i64 vs u64 in the ABI leaf array);
`byteWidth` is 8. Wire format reuses the scalar decimal-JSON idiom (see Emit). -/
structure LeafAbiType where
  isInt : Bool
  byteWidth : Nat
  deriving BEq, Inhabited, Repr

/-- Result kind of a CosmWasm method export. Init is always unit; entry/view may be
UInt{8,16,32,64}/Bool/Int64 (T9a). UInt64/Int64/Bool wire as decimal JSON
(execute: result attribute; query: `{"ok":"<decimal>"}`); UInt{8,16,32} as
narrower LE payloads when admitted. B-RET-ABI: `.aggregate` packs 1..8
UInt64/Int64 leaves as a JSON array of decimals (preorder flatten; Enum =
tag + max-payload). ABI JSON `returns` distinguishes the declared type. -/
inductive MethodResultKind where
  | unit
  | uint64
  | bool
  | int64
  | uint8
  | uint16
  | uint32
  | int8
  | int16
  | int32
  /-- T9e: multiword public UInt entry/view results (16/32-byte LE). -/
  | uint128
  | uint256
  /-- B-RET-ABI: named Struct/Enum or admitted anonymous Array/Option aggregate
  return. `leaves` is preorder flatten order (1..8). Map/Bytes/nested/narrow
  anonymous containers stay fail-closed. -/
  | aggregate (leaves : Array LeafAbiType)
  deriving BEq, Inhabited, Repr

structure Method where
  name : String
  params : Array Param
  exactInputLen : Nat
  mode : MethodMode
  depositPolicy : DepositPolicy
  resultKind : MethodResultKind
  body : Array Statement
  deriving BEq, Inhabited, Repr

/-- Pure function binding: public UInt64 params, UInt64-or-Bool result, and a
    pure statement body (no state/event effects). Indexed by Plan.fns. -/
structure FnBinding where
  name : String
  params : Array Param
  resultIsBool : Bool
  body : Array Statement
  deriving BEq, Inhabited, Repr

/-- One declared event/error binding: its name and UInt64 argument count. -/
structure InterfaceBinding where
  name : String
  fieldCount : Nat
  deriving BEq, Inhabited, Repr

/-- The CosmWasm-owned KV, raw ABI, method, and error policy for the supported
UInt64 (+ Bool result) fragment. It deliberately retains no SemanticProgram. -/
structure Plan where
  targetDescriptor : TargetDescriptor
  semanticSchemaVersion : Nat
  codegenProfile : String
  hostAbi : String
  inputAbi : String
  layoutDomain : String
  hostImports : Array HostImport
  failurePolicy : FailurePolicy
  commitPolicy : ReceiptCommitPolicy
  resourceLimits : ResourceLimits
  programName : String
  storage : StorageLayout
  events : Array InterfaceBinding
  errors : Array InterfaceBinding
  fns : Array FnBinding
  initializer : Method
  entries : Array Method
  -- No Inhabited: Plan embeds TargetDescriptor (opaque TargetId/profile).
  deriving BEq, Repr

structure RegisterLayout where
  input : Nat
  storage : Nat
  evicted : Nat
  deriving BEq, Inhabited, Repr

structure KeyRegion where
  key : String
  offset : Nat
  length : Nat
  deriving BEq, Inhabited, Repr

structure MemoryLayout where
  minPages : Nat
  inputOffset : Nat
  inputCapacity : Nat
  depositOffset : Nat
  valueOffset : Nat
  deriving BEq, Inhabited, Repr
private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .cosmwasm message

private def maxIdentifierBytes : Nat := 240
-- `.cosmwasm-abi.json` is the longest emitted suffix (14 bytes) under the CLI's
-- 240-byte relative-path ceiling.
def maxArtifactStemBytes : Nat := 226
def maxStateFields : Nat := 1024
def maxEntries : Nat := 255
def maxParams : Nat := 64
def maxBodyStatements : Nat := 4096
def maxExprDepth : Nat := 256
def maxPlanNodes : Nat := 100000
def maxRecipeNodes : Nat := 110000
def maxMethodLocals : Nat := 50000
def wasmPageBytes : Nat := 65536

def canonicalFailurePolicy : FailurePolicy := {
  invalidInput := .trap
  uninitializedLayout := .trap
  corruptStorage := .trap
  arithmeticOverflow := .trap
  nonzeroDeposit := .trap
}

def canonicalResourceLimits : ResourceLimits := {
  maxArtifactStemBytes
  maxStateFields
  maxEntries
  maxParams
  maxBodyStatements
  maxExprDepth
  maxPlanNodes
  maxRecipeNodes
  maxMethodLocals
  wasmMemoryPages := 1
}

/-- Fixed CosmWasm MVP host import set. Schedule → SubMsg is pure Response JSON
    (no extra host imports; unlike NEAR promise_batch_*). ADR-0030 E2-4-CW
    adds `query_chain` for read-only env-read host queries (bank balance /
    CW20 smart query); cosmwasm-vm always provides it. -/
def canonicalImports : Array HostImport := #[
  .dbRead, .dbWrite, .dbRemove, .abort, .queryChain
]

def hostImportsFor (_usesPromise : Bool) : Array HostImport :=
  canonicalImports

def canonicalRegisters : RegisterLayout := {
  input := 0
  storage := 1
  evicted := 2
}

/-- Thin adapter: binds CosmWasm's `maxIdentifierBytes` (240) to the shared grammar. -/
def isIdentifier (value : String) : Bool :=
  isAsciiIdentifier maxIdentifierBytes value

/-- CosmWasm schedule **receiver stub** grammar (pilot): lowercase ASCII
    letters, digits, `_`, `-`, `.`; UTF-8 length 2..64; no leading or trailing
    `.`. Uppercase is rejected (never case-normalized).

    This is **not** bech32 AccAddress validation. The joined static QN is stored
    as `contract_addr` stub for deterministic engineering artifacts; production
    deployment must rewrite to a real chain address. Name retained as
    `isNearAccountId` for NEAR-shared lowering text parity on this leaf. -/
def isNearAccountId (value : String) : Bool :=
  let n := value.toUTF8.size
  let chars := value.toList.toArray
  (2 ≤ n && n ≤ 64) && !chars.isEmpty &&
    chars[0]! != '.' && chars[chars.size - 1]! != '.' &&
      chars.all fun character =>
        let code := character.toNat
        (97 ≤ code && code ≤ 122) ||
          (48 ≤ code && code ≤ 57) ||
          character == '_' || character == '-' || character == '.'

/-- Sole schedule-receiver stub error text (lowering + validatePlan). -/
def nearAccountIdError (receiver : String) : String :=
  s!"schedule receiver '{receiver}' is not a valid CosmWasm account id (lowercase letters, digits, underscore, hyphen or dot, length 2..64, no leading/trailing dot)"

/-- Sole view/pureFn schedule-disallow error text (lowering + validatePlan).
    `kind` is the richer lowering form, e.g. `"view callable schedules a workflow"`
    or `"pureFn cannot schedule workflows"`. -/
def nearScheduleDisallowedError (kind : String) : String :=
  s!"unsupported CosmWasm semantic shape: {kind}"

def stateKey (sourceId : Nat) : String :=
  s!"pf:cw:v1:state:{sourceId}"

/-- Layout field type suffix from physical byte width (`u8-le` … `u64-le`). -/
def layoutFieldTypeSuffix (byteWidth : Nat) : String :=
  match byteWidth with
  | 1 => "u8-le"
  | 2 => "u16-le"
  | 4 => "u32-le"
  | 16 => "u128-le"
  | 32 => "u256-le"
  | _ => "u64-le"

/-- Input slot pitch for a param physical width (T9e multiword). -/
def slotPitchOfByteWidth (byteWidth : Nat) : Nat :=
  let limbs := (byteWidth + 7) / 8
  if limbs ≤ 1 then 8 else limbs * 8

/-- Total raw input length for a param list (last offset + pitch, or 0). -/
def exactInputLenOfParams (params : Array Param) : Nat :=
  match params.back? with
  | none => 0
  | some p => p.inputOffset + slotPitchOfByteWidth p.byteWidth

/-- ABI / IDL type string for a param or storage field (Int64 keeps `u64-le`). -/
def abiScalarTypeString (byteWidth : Nat) : String :=
  layoutFieldTypeSuffix byteWidth

private def layoutFieldSignature (field : StorageField) : String :=
  s!"{field.sourceId}:{field.name}:{field.key}:{field.byteWidth}:{layoutFieldTypeSuffix field.byteWidth}"

private def layoutSignature (fields : Array StorageField) : String :=
  s!"{fields.size}|{String.intercalate "|" (fields.toList.map layoutFieldSignature)}"

private def firstWordBE (bytes : ByteArray) : UInt64 := Id.run do
  let mut value : UInt64 := 0
  for index in [0:8] do
    value := UInt64.shiftLeft value 8 ||| bytes[index]!.toUInt64
  return value

def layoutMarker (fields : Array StorageField) : UInt64 :=
  firstWordBE <| Crypto.sha256 (stateLayoutDomain ++ layoutSignature fields).toUTF8

/-! ### Retained SemanticProgramV1 public-UInt64 Plan lowering -/

/-- Value kinds admitted in the CosmWasm pilot value table. Bool is admitted for
comparison/logical/literal temps, assert conditions, and entry/view return
values. Body multi-width (T8c) admits UInt{8,16,32,64} temps; UInt32 also
covers shift-count temps (zero-extended into the i64 plan surface). Top-level
state/params admit UInt{8,16,32,64}|Int64 (T8b). Initializer result stays Unit. -/
private inductive CosmWasmValueKindV1 where
  | uint64
  | uint32
  | uint16
  | uint8
  | bool
  | int64
  /-- T9e multiword body kinds. -/
  | uint128
  | uint256
  deriving BEq, Inhabited, Repr

/-- Map admitted body UInt width to plan value kind. -/
private def uintKindOfWidthV1 (w : Nat) : Option CosmWasmValueKindV1 :=
  match w with
  | 8 => some .uint8
  | 16 => some .uint16
  | 32 => some .uint32
  | 64 => some .uint64
  | 128 => some .uint128
  | 256 => some .uint256
  | _ => none


/-- Inverse of `uintKindOfWidthV1` for store/width gates. -/
private def widthOfUintKindV1 (k : CosmWasmValueKindV1) : Option Nat :=
  match k with
  | .uint8 => some 8
  | .uint16 => some 16
  | .uint32 => some 32
  | .uint64 => some 64
  | .uint128 => some 128
  | .uint256 => some 256
  | .bool | .int64 => none

/-- CosmWasm pilot type-closure carrier (shared `PilotTypeClosureV1`).
    Bool/UInt32 optional; state/params admit UInt{8,16,32,64}|Int64 (T8b). -/
private abbrev CosmWasmTypeClosureV1 := PilotTypeClosureV1

private def cosmwasmPlanErr (message : String) : CompileError :=
  .planInvariant .cosmwasm message

/-- CosmWasm admits body+ABI multi-width UInt{8,16,32,64} (BL-15 / T8 pattern)
    plus Int64 and named Struct/Enum (B-RET-ABI + state flatten).
    Array + Map container state via `pilotContainerStatePolicyArrayMap`
    (Array → N×UInt64 leaves; Map → capacity-8×(occ,key,val); Option admitted
    as Map IndexGet intermediate / N-ANON-RESULT return shape — never pushed to
    `containerTypeIds`). **B-OPT-STATE / BL-33**: anonymous `Option UInt64`
    **state** admitted as Enum-shaped tag+payload KV leaves (`name_tag`/
    `name_p0`; none default = zero fields; storeAtomic on assign; match via
    VariantTag/VariantPayload). Option of non-UInt64, nested Option, Option
    params stay fail closed. Bytes, Field, String, UInt128/256, narrow
    Int{8,16,32} fail closed at type closure. **T12 + ADR-0029 C1**: Principal
    admitted as full wire-identity storage/param leaves (len + 8×UInt64; not
    bech32 AccAddress pin).
    **N-ANON-RESULT (CosmWasm ABI)**: anonymous `Array UInt64 N` (1..8) and
    `Option UInt64` entry/view returns reuse B-RET-ABI multi-leaf JSON decimal
    arrays (execute `result` attr + query `{"ok":"[d0,...]"}`); Map/Bytes/
    nested/narrow-element anonymous returns stay fail closed. Named aggregate
    params and pureFn aggregate returns stay fail closed at callable lowering.

    Physical KV honesty: CosmWasm always stores scalar state as an 8-byte LE
    Region value (`pf_db_store_u64`). Narrow Plan `field.byteWidth` records the
    semantic ABI width for layout markers / ABI JSON; high bytes must be zero
    on load (Emit narrowStateLoad high-bit guard). Params arrive as JSON
    decimals and are range-checked to `2^bitWidth − 1` at the entry boundary
    (no silent truncation). -/
private def cosmwasmUintWidthPolicyV1 : PilotUintWidthPolicy where
  admittedWidths := #[64, 32, 8, 16]

private def cosmwasmTypeClosureWording : PilotTypeClosureWording where
  targetLabel := "CosmWasm"
  uint32DuplicateDetail := "expected one anonymous UInt32 type"
  badIntegerWidthDetail :=
    "only anonymous UInt{8,16,32,64} and Int64 integer types are supported (UInt128/256 and narrow Int fail closed)"
  unsupportedShapeDetail :=
    "only UInt{8,16,32,64}, Int64, Unit, Bool, Principal, named Struct/Enum, and admitted Array/Map containers are supported (no Field/Bytes)"

private def validateCosmWasmTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult CosmWasmTypeClosureV1 :=
  validatePilotTypeClosure cosmwasmPlanErr cosmwasmTypeClosureWording types
    cosmwasmUintWidthPolicyV1
    (intPolicy := pilotIntWidthPolicyI64)
    (principalPolicy := pilotPrincipalPolicyAdmit)
    (namedAggregatePolicy := pilotNamedAggregateStatePolicyAdmit)
    (containerPolicy := pilotContainerStatePolicyArrayMap)

/-- CosmWasm pilot Principal storage layout (T12, isomorphic to EVM T10):
    * leaf 0: wire body length (`UInt64`)
    * leaves 1..8: up to 64 opaque body bytes packed little-endian into
      8×UInt64 words (zero-padded)
    Each leaf is a separate KV field (key=`pf:v1:s{sourceId}`); EmitIR reuses
    existing per-field storage_read/write. Body >64 fails closed.
    Design note: a single variable-length `u32le||body` KV is deferred —
    9 fixed leaves keep Plan/Emit multi-temp free while preserving lossless
    wire identity (not account-id string). -/
private def nearPrincipalMaxPayloadBytesV1 : Nat := 64
private def nearPrincipalDataWordCountV1 : Nat := 8

/-- Flatten Principal into ordered leaf names: `{prefix}_len` + `{prefix}_w0`..`_w7`. -/
private def flattenPrincipalLeafSpecsV1 (namePrefix : String) :
    CompileResult (Array String) := do
  let lenName :=
    if namePrefix.isEmpty then "len" else namePrefix ++ "_len"
  unless isIdentifier lenName do
    throw <| .planInvariant .cosmwasm
      s!"state name '{lenName}' is not a safe identifier"
  let mut out : Array String := #[lenName]
  for i in [0:nearPrincipalDataWordCountV1] do
    let wName :=
      if namePrefix.isEmpty then s!"w{i}" else namePrefix ++ "_w" ++ toString i
    unless isIdentifier wName do
      throw <| .planInvariant .cosmwasm
        s!"state name '{wName}' is not a safe identifier"
    out := out.push wName
  pure out

/-- Pack wire Principal valueBytes into CosmWasm pilot leaves. -/
private def decodePrincipalLiteralLeavesV1 (bytes : ByteArray) :
    CompileResult (Array Expr) := do
  unless bytes.size ≥ 4 do
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: Principal literal valueBytes too short"
  let len :=
    (bytes.get! 0).toNat + (bytes.get! 1).toNat * 256 +
      (bytes.get! 2).toNat * 65536 + (bytes.get! 3).toNat * 16777216
  unless bytes.size == 4 + len do
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: Principal literal valueBytes length framing mismatch"
  unless 1 ≤ len do
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: Principal body shorter than 1 byte"
  unless len ≤ nearPrincipalMaxPayloadBytesV1 do
    throw <| .planInvariant .cosmwasm
      s!"unsupported CosmWasm semantic shape: Principal longer than {nearPrincipalMaxPayloadBytesV1} bytes (CosmWasm pilot bound)"
  let payload := bytes.extract 4 bytes.size
  let mut leaves : Array Expr := #[.literal (UInt64.ofNat len)]
  for w in [0:nearPrincipalDataWordCountV1] do
    let mut word : Nat := 0
    let mut place : Nat := 1
    for b in [0:8] do
      let idx := w * 8 + b
      let byte := if idx < payload.size then (payload.get! idx).toNat else 0
      word := word + byte * place
      place := place * 256
    leaves := leaves.push (.literal (UInt64.ofNat word))
  pure leaves

/-- Resolve admitted scalar state/param TypeId to physical byte width (1/2/4/8). -/
private def abiByteWidthOfTypeV1
    (types : CosmWasmTypeClosureV1) (typeId : TypeIdV1) : CompileResult Nat := do
  match types.uintWidthOf typeId with
  | some w =>
      -- CosmWasm ABI admits UInt{8,16,32,64} only (no multiword 128/256).
      unless isAbiUintWidth w do
        throw <| .planInvariant .cosmwasm
          s!"unsupported CosmWasm semantic shape: ABI UInt{w} is not admitted"
      pure (byteWidthOfBitWidth w)
  | none =>
      match types.intWidthOf typeId with
      | some w =>
          -- Int64 only on CosmWasm (narrow Int FC via type-closure policy).
          unless w == 64 do
            throw <| .planInvariant .cosmwasm
              s!"unsupported CosmWasm semantic shape: ABI Int{w} is not admitted"
          pure (byteWidthOfBitWidth w)
      | none =>
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: ABI type must be UInt8/16/32/64 or Int64"

/-- Width-dispatch for ABI param loads: UInt64/Int64 keep historical `param`. -/
private def mkParamExpr (bitWidth : Nat) (inputOffset : Nat) : Expr :=
  if bitWidth == 64 then .param inputOffset else .narrowParam bitWidth inputOffset

/-- Width-dispatch for state loads: UInt64/Int64 keep historical `stateLoad`. -/
private def mkStateLoadExpr (bitWidth : Nat) (fieldIndex : Nat) : Expr :=
  if bitWidth == 64 then .stateLoad fieldIndex
  else .narrowStateLoad bitWidth fieldIndex

/-- Dense Map pilot capacity (aligned with EVM/Solana Token pilot). -/
private def nearMapPilotCapacityV1 : Nat := 8
private def nearMapSlotsPerEntryV1 : Nat := 3
private def nearMapPilotLeafCountV1 : Nat :=
  nearMapPilotCapacityV1 * nearMapSlotsPerEntryV1

/-- Container leaf layout for CosmWasm KV flattening: `(leafCount, leafByteWidth)`.
    Array: fixed `Array UInt64 N` → N×8-byte UInt64 leaves. Map: dense
    capacity-8 occ/key/val → 24×8-byte leaves. Bytes: fixed `Bytes N` →
    N×1-byte UInt8 leaves (byte-exact KV identity; element-wise IndexGet/
    IndexSet). -/
private def containerLeafLayoutV1
    (typeDecls : Array TypeDeclV1) (types : CosmWasmTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult (Option (Nat × Nat)) := do
  unless types.isContainer typeId do
    return none
  match typeDecls[typeId.toNat]? with
  | some { shape := .array elTid len, .. } =>
      unless elTid == types.uint64TypeId do
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: Array state element must be UInt64"
      let n := len.toNat
      unless n ≥ 1 do
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: Array state length must be ≥ 1"
      pure (some (n, 8))
  | some { shape := .map keyTid valTid, .. } =>
      unless keyTid == types.uint64TypeId && valTid == types.uint64TypeId do
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: Map state admits only Map UInt64 UInt64"
      pure (some (nearMapPilotLeafCountV1, 8))
  | some { shape := .bytes len, .. } =>
      let n := len.toNat
      unless n ≥ 1 do
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: Bytes state length must be ≥ 1"
      pure (some (n, 1))
  | _ =>
      throw <| .planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: container TypeId is not Array/Map/Bytes"

/-- Flatten a type into ordered `(name, isInt)` pairs under CosmWasm named-aggregate
    policy. Scalars inside aggregates: UInt64 / Int64 only (matching EVM N3 / Psy H3).
    Named Struct: field preorder. Named Enum: tag (UInt64, isInt=false) + max-payload
    slots (`_tag`, `_p0`…). Nested containers / narrow UInt / Bool / Field as leaves
    fail closed. -/
private partial def flattenTypeLeafSpecsV1
    (typeDecls : Array TypeDeclV1) (types : CosmWasmTypeClosureV1)
    (typeId : TypeIdV1) (namePrefix : String) :
    CompileResult (Array (String × Bool)) := do
  if typeId == types.uint64TypeId then
    pure #[(namePrefix, false)]
  else if types.int64TypeId == some typeId then
    pure #[(namePrefix, true)]
  else if types.isNamedAggregate typeId then
    match typeDecls[typeId.toNat]? with
    | none =>
        throw <| .planInvariant .cosmwasm
          s!"unsupported CosmWasm semantic shape: missing TypeDecl for aggregate {typeId}"
    | some decl =>
        match decl.shape with
        | .struct fields => do
            unless fields.size > 0 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: named Struct requires at least one field"
            let mut out : Array (String × Bool) := #[]
            for f in fields do
              let subName :=
                if namePrefix.isEmpty then f.name else namePrefix ++ "_" ++ f.name
              unless isIdentifier subName do
                throw <| .planInvariant .cosmwasm
                  s!"state name '{subName}' is not a safe identifier"
              let sub ← flattenTypeLeafSpecsV1 typeDecls types f.typeId subName
              out := out ++ sub
            pure out
        | .enum variants => do
            unless variants.size > 0 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: named Enum requires at least one variant"
            let tagName :=
              if namePrefix.isEmpty then "tag" else namePrefix ++ "_tag"
            unless isIdentifier tagName do
              throw <| .planInvariant .cosmwasm
                s!"state name '{tagName}' is not a safe identifier"
            let mut maxPay : Nat := 0
            for v in variants do
              let mut n : Nat := 0
              for pt in v.payloadTypes do
                let sub ← flattenTypeLeafSpecsV1 typeDecls types pt "tmp"
                n := n + sub.size
              if n > maxPay then maxPay := n
            -- Tag is UInt64; pad slots are UInt64 zero-fill (not Int).
            let mut out : Array (String × Bool) := #[(tagName, false)]
            for i in [0:maxPay] do
              let pName :=
                if namePrefix.isEmpty then s!"p{i}" else namePrefix ++ "_p" ++ toString i
              unless isIdentifier pName do
                throw <| .planInvariant .cosmwasm
                  s!"state name '{pName}' is not a safe identifier"
              out := out.push (pName, false)
            pure out
        | _ =>
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: named type must be Struct or Enum"
  else
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: aggregate leaf must be UInt64, Int64, or named Struct/Enum"

private def leafCountOfTypeV1
    (typeDecls : Array TypeDeclV1) (types : CosmWasmTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult Nat := do
  let specs ← flattenTypeLeafSpecsV1 typeDecls types typeId "x"
  pure specs.size

/-- True when `typeId` is an anonymous Option TypeDecl. Option is admitted by
    the Map container policy as a Map IndexGet intermediate and (B-OPT-STATE)
    as state layout — it is **never** pushed to `containerTypeIds`. -/
private def isAnonymousOptionTypeIdV1
    (typeDecls : Array TypeDeclV1) (typeId : TypeIdV1) : Bool :=
  match typeDecls[typeId.toNat]? with
  | some { shape := .option _, name := none, .. } => true
  | _ => false

/-- B-OPT-STATE: admit only anonymous `Option UInt64` for state (tag+payload).
    Non-UInt64 / nested / named Option stay fail closed. -/
private def requireOptionUInt64StateV1
    (typeDecls : Array TypeDeclV1) (types : CosmWasmTypeClosureV1)
    (typeId : TypeIdV1) (stateName : String) : CompileResult Unit := do
  match typeDecls[typeId.toNat]? with
  | some { shape := .option elTid, name := none, .. } =>
      unless elTid == types.uint64TypeId do
        throw <| .planInvariant .cosmwasm
          s!"unsupported CosmWasm semantic shape: Option state '{stateName}' requires UInt64 payload"
  | _ =>
      throw <| .planInvariant .cosmwasm
        s!"unsupported CosmWasm semantic shape: state '{stateName}' is not anonymous Option UInt64"

/-- N-ANON-RESULT (CosmWasm ABI): anonymous result leaf layout for admitted
container returns. `Array UInt64 N` → N×u64 leaves; `Option UInt64` →
tag+payload (none=(0,0), some v=(1,v)). Map/Bytes throw for precise FC. -/
private def anonymousReturnLeafAbiV1
    (typeDecls : Array TypeDeclV1) (types : CosmWasmTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult (Option (Array LeafAbiType)) := do
  match typeDecls[typeId.toNat]? with
  | some { shape := .array elTid len, name := none, .. } =>
      unless elTid == types.uint64TypeId do
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: anonymous Array return requires UInt64 elements"
      let n := len.toNat
      unless n ≥ 1 do
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: anonymous Array return length must be ≥ 1"
      pure (some (Array.replicate n { isInt := false, byteWidth := 8 }))
  | some { shape := .option elTid, name := none, .. } =>
      unless elTid == types.uint64TypeId do
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: anonymous Option return requires UInt64 payload"
      pure (some #[{ isInt := false, byteWidth := 8 }, { isInt := false, byteWidth := 8 }])
  | some { shape := .map .., name := none, .. } =>
      throw <| .planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: anonymous Map return is outside the CosmWasm B-RET ABI"
  | some { shape := .bytes .., name := none, .. } =>
      throw <| .planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: anonymous Bytes return is outside the CosmWasm B-RET ABI"
  | some { shape := .array .., .. } | some { shape := .option .., .. } =>
      pure none
  | _ => pure none

/-- True when `typeId` should resolve through the aggregate result path
(named Struct/Enum or anonymous Array/Map/Bytes/Option, so Map/Bytes get
precise fail-closed diagnostics instead of a scalar fallthrough). -/
private def isAggregateResultCandidateV1
    (typeDecls : Array TypeDeclV1) (types : CosmWasmTypeClosureV1)
    (typeId : TypeIdV1) : Bool :=
  if types.isNamedAggregate typeId then true
  else
    match typeDecls[typeId.toNat]? with
    | some { shape := .array .., name := none, .. }
    | some { shape := .option .., name := none, .. }
    | some { shape := .map .., name := none, .. }
    | some { shape := .bytes .., name := none, .. } => true
    | _ => false

/-- B-RET-ABI: resolve a named Struct/Enum or admitted anonymous Array/Option
result TypeId into an aggregate `MethodResultKind`. Enforces 1..8 leaves.
Map/Bytes/nested/narrow-element anonymous containers fail closed. -/
private def aggregateResultKindOfV1
    (typeDecls : Array TypeDeclV1) (types : CosmWasmTypeClosureV1)
    (owner : String) (typeId : TypeIdV1) : CompileResult MethodResultKind := do
  let leaves ←
    if types.isNamedAggregate typeId then
      let specs ← flattenTypeLeafSpecsV1 typeDecls types typeId "ret"
      let mut out : Array LeafAbiType := #[]
      for (_, isInt) in specs do
        out := out.push { isInt, byteWidth := 8 }
      pure out
    else
      match ← anonymousReturnLeafAbiV1 typeDecls types typeId with
      | some ls => pure ls
      | none =>
          throw <| .planInvariant .cosmwasm
            s!"{owner} does not return a named Struct/Enum or admitted anonymous Array/Option aggregate"
  let n := leaves.size
  unless n > 0 do
    throw <| .planInvariant .cosmwasm
      s!"{owner} aggregate return must have at least one leaf"
  unless n ≤ 8 do
    throw <| .planInvariant .cosmwasm
      s!"{owner} aggregate return has {n} leaves, exceeding the B-RET-ABI cap of 8"
  pure (.aggregate leaves)

/-- Struct field leaf range (start, length) within the flattened leaf vector. -/
private def structFieldLeafRangeV1
    (typeDecls : Array TypeDeclV1) (types : CosmWasmTypeClosureV1)
    (fields : Array StructFieldV1) (fieldIndex : Nat) :
    CompileResult (Nat × Nat) := do
  let mut start : Nat := 0
  for i in [0:fields.size] do
    let some f := fields[i]? |
      throw <| .planInvariant .cosmwasm "struct field index out of range"
    let n ← leafCountOfTypeV1 typeDecls types f.typeId
    if i == fieldIndex then return (start, n)
    start := start + n
  throw <| .planInvariant .cosmwasm "struct field index out of range"

/-- Enum max payload leaf count (excluding tag). -/
private def enumMaxPayloadLeavesV1
    (typeDecls : Array TypeDeclV1) (types : CosmWasmTypeClosureV1)
    (variants : Array EnumVariantV1) : CompileResult Nat := do
  let mut maxPay : Nat := 0
  for v in variants do
    let mut n : Nat := 0
    for pt in v.payloadTypes do
      let c ← leafCountOfTypeV1 typeDecls types pt
      n := n + c
    if n > maxPay then maxPay := n
  pure maxPay

/-- Payload leaf offset of `payloadIndex` within variant `variantIndex`
    (0-based within the payload region after the tag). -/
private def enumPayloadLeafRangeV1
    (typeDecls : Array TypeDeclV1) (types : CosmWasmTypeClosureV1)
    (variants : Array EnumVariantV1) (variantIndex payloadIndex : Nat) :
    CompileResult (Nat × Nat) := do
  let some v := variants[variantIndex]? |
    throw <| .planInvariant .cosmwasm "enum variant index out of range"
  let mut start : Nat := 0
  for i in [0:v.payloadTypes.size] do
    let some pt := v.payloadTypes[i]? |
      throw <| .planInvariant .cosmwasm "enum payload index out of range"
    let n ← leafCountOfTypeV1 typeDecls types pt
    if i == payloadIndex then return (start, n)
    start := start + n
  throw <| .planInvariant .cosmwasm "enum payload index out of range"

/-- Resolve scalar kind for a fieldGet/variantPayload leaf result. -/
private def scalarKindOfNamedLeafResultV1
    (types : CosmWasmTypeClosureV1) (typeId : TypeIdV1) :
    CompileResult CosmWasmValueKindV1 := do
  if typeId == types.uint64TypeId then
    pure .uint64
  else if types.int64TypeId == some typeId then
    pure .int64
  else
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: named-aggregate scalar leaf must be UInt64 or Int64"

/-- Dense Map IndexGet → Option UInt64 as `[tag, payload]`. -/
private def mapLookupOptionLeavesV1
    (mapLeaves : Array Expr) (key : Expr) : CompileResult (Array Expr) := do
  unless mapLeaves.size == nearMapPilotLeafCountV1 do
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: Map leaf count must match pilot capacity"
  let mut found : Expr := .literal 0
  let mut payload : Expr := .literal 0
  for e in [0:nearMapPilotCapacityV1] do
    let base := e * nearMapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      throw <| .planInvariant .cosmwasm "Map lookup occ leaf missing"
    let some k := mapLeaves[base + 1]? |
      throw <| .planInvariant .cosmwasm "Map lookup key leaf missing"
    let some v := mapLeaves[base + 2]? |
      throw <| .planInvariant .cosmwasm "Map lookup val leaf missing"
    let hit := Expr.checkedMul occ (Expr.compare .eq k key)
    let miss := Expr.boolNot hit
    found := Expr.boolOr found hit
    payload :=
      Expr.checkedAdd (Expr.checkedMul hit v) (Expr.checkedMul miss payload)
  pure #[Expr.checkedAdd found (.literal 0), payload]

/-- Dense Map IndexSet upsert. Returns (newLeaves, okInsert). -/
private def mapUpsertLeavesV1
    (mapLeaves : Array Expr) (key value : Expr) :
    CompileResult (Array Expr × Expr) := do
  unless mapLeaves.size == nearMapPilotLeafCountV1 do
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: Map leaf count must match pilot capacity"
  let mut anyMatch : Expr := .literal 0
  for e in [0:nearMapPilotCapacityV1] do
    let base := e * nearMapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      throw <| .planInvariant .cosmwasm "Map upsert occ leaf missing"
    let some k := mapLeaves[base + 1]? |
      throw <| .planInvariant .cosmwasm "Map upsert key leaf missing"
    let hit := Expr.checkedMul occ (Expr.compare .eq k key)
    anyMatch := Expr.boolOr anyMatch hit
  let mut seenEmpty : Expr := .literal 0
  let mut isFirstEmpty : Array Expr := #[]
  for e in [0:nearMapPilotCapacityV1] do
    let base := e * nearMapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      throw <| .planInvariant .cosmwasm "Map upsert empty-scan occ missing"
    let empty := Expr.boolNot occ
    let first := Expr.checkedMul empty (Expr.boolNot seenEmpty)
    isFirstEmpty := isFirstEmpty.push first
    seenEmpty := Expr.boolOr seenEmpty empty
  let okInsert := Expr.boolOr anyMatch seenEmpty
  let mut out : Array Expr := #[]
  for e in [0:nearMapPilotCapacityV1] do
    let base := e * nearMapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      throw <| .planInvariant .cosmwasm "Map upsert rebuild occ missing"
    let some k := mapLeaves[base + 1]? |
      throw <| .planInvariant .cosmwasm "Map upsert rebuild key missing"
    let some v := mapLeaves[base + 2]? |
      throw <| .planInvariant .cosmwasm "Map upsert rebuild val missing"
    let matchHit := Expr.checkedMul occ (Expr.compare .eq k key)
    let some firstE := isFirstEmpty[e]? |
      throw <| .planInvariant .cosmwasm "Map upsert firstEmpty missing"
    let insertHere := Expr.checkedMul firstE (Expr.boolNot anyMatch)
    let write := Expr.boolOr matchHit insertHere
    let miss := Expr.boolNot write
    let occ' := Expr.checkedAdd (Expr.boolOr occ write) (.literal 0)
    let k' :=
      Expr.checkedAdd (Expr.checkedMul write key) (Expr.checkedMul miss k)
    let v' :=
      Expr.checkedAdd (Expr.checkedMul write value) (Expr.checkedMul miss v)
    out := out.push occ' |>.push k' |>.push v'
  pure (out, okInsert)

private def makeStorageLayoutV1
    (types : CosmWasmTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (states : Array StateDeclV1) : CompileResult StorageLayout := do
  if states.isEmpty || states.size > maxStateFields then
    throw <| .planInvariant .cosmwasm "state count is outside the profile limits"
  let mut fields : Array StorageField := #[]
  let mut stateLeaves : Array (Array Nat) := #[]
  for state in states do
    unless state.id.toNat == stateLeaves.size do
      throw <| .planInvariant .cosmwasm "semantic state ids must match declaration order"
    unless isIdentifier state.name do
      throw <| .planInvariant .cosmwasm s!"state name '{state.name}' is not a safe identifier"
    match ← containerLeafLayoutV1 typeDecls types state.typeId with
    | some (n, leafByteWidth) =>
        -- Array/Map: N consecutive 8-byte UInt64 KV fields; Bytes: N
        -- consecutive 1-byte UInt8 KV fields. Physical names `name_0`..
        -- `name_{n-1}` keep layout markers deterministic.
        -- Visibility: same N1 allowNonPublic as scalar state.
        if fields.size + n > maxStateFields then
          throw <| .planInvariant .cosmwasm "state count is outside the profile limits"
        let mut leaves : Array Nat := #[]
        for i in [0:n] do
          let leafName := state.name ++ "_" ++ toString i
          unless isIdentifier leafName do
            throw <| .planInvariant .cosmwasm
              s!"state name '{leafName}' is not a safe identifier"
          let fi := fields.size
          leaves := leaves.push fi
          fields := fields.push {
            sourceId := fi
            name := leafName
            key := stateKey fi
            byteWidth := leafByteWidth
            endianness := .little
          }
        stateLeaves := stateLeaves.push leaves
    | none =>
        if isAnonymousOptionTypeIdV1 typeDecls state.typeId then
          -- B-OPT-STATE / BL-33: Option UInt64 → tag + payload (2×8-byte KV
          -- leaves), same physical shape as a 1-payload Enum. Names follow
          -- Enum convention (`name_tag` / `name_p0`). Default zero fields =
          -- Option.none; storeAtomic writes both leaves; none construct zeroes
          -- payload (pin). Non-UInt64 Option payload fails closed above.
          requireOptionUInt64StateV1 typeDecls types state.typeId state.name
          let tagName := state.name ++ "_tag"
          let pName := state.name ++ "_p0"
          unless isIdentifier tagName do
            throw <| .planInvariant .cosmwasm
              s!"state name '{tagName}' is not a safe identifier"
          unless isIdentifier pName do
            throw <| .planInvariant .cosmwasm
              s!"state name '{pName}' is not a safe identifier"
          if fields.size + 2 > maxStateFields then
            throw <| .planInvariant .cosmwasm "state count is outside the profile limits"
          let mut leaves : Array Nat := #[]
          for leafName in #[tagName, pName] do
            let fi := fields.size
            leaves := leaves.push fi
            fields := fields.push {
              sourceId := fi
              name := leafName
              key := stateKey fi
              byteWidth := 8
              endianness := .little
            }
          stateLeaves := stateLeaves.push leaves
        else if types.isNamedAggregate state.typeId then
          -- Named Struct/Enum: preorder UInt64/Int64 leaves as separate 8-byte
          -- KV fields (`name_field` / `name_tag` / `name_p0`…). Atomic
          -- storeAtomic for StateStore (same store-then-read hazard fix as Map).
          requirePublicUInt64OrInt64OrFieldOrPrincipalOrNamedState cosmwasmPlanErr types state
            (allowNonPublic := true)
          let leafSpecs ← flattenTypeLeafSpecsV1 typeDecls types state.typeId state.name
          if leafSpecs.isEmpty then
            throw <| .planInvariant .cosmwasm
              s!"state '{state.name}' produced zero named-aggregate leaves"
          if fields.size + leafSpecs.size > maxStateFields then
            throw <| .planInvariant .cosmwasm "state count is outside the profile limits"
          let mut leaves : Array Nat := #[]
          for (leafName, _) in leafSpecs do
            let fi := fields.size
            leaves := leaves.push fi
            fields := fields.push {
              sourceId := fi
              name := leafName
              key := stateKey fi
              byteWidth := 8
              endianness := .little
            }
          stateLeaves := stateLeaves.push leaves
        else if types.isPrincipal state.typeId then
          -- T12 Principal: 9 KV fields (`name_len` + `name_w0`..`name_w7`).
          -- ValidatePlan requires sourceId == physical field index (dense).
          -- Logical state → leaf indices live only in `stateLeaves`.
          requirePublicUInt64OrInt64OrFieldOrPrincipalState cosmwasmPlanErr types state
            (allowNonPublic := true)
          let leafSpecs ← flattenPrincipalLeafSpecsV1 state.name
          if fields.size + leafSpecs.size > maxStateFields then
            throw <| .planInvariant .cosmwasm "state count is outside the profile limits"
          let mut leaves : Array Nat := #[]
          for leafName in leafSpecs do
            let fi := fields.size
            leaves := leaves.push fi
            fields := fields.push {
              sourceId := fi
              name := leafName
              key := stateKey fi
              byteWidth := 8
              endianness := .little
            }
          stateLeaves := stateLeaves.push leaves
        else
          -- T8b/BL-15: scalar state admits UInt{8,16,32,64} / Int64 with Plan
          -- byteWidth 1/2/4/8. Physical CosmWasm KV is always an 8-byte Region
          -- (high bytes zero for narrow values); see type-closure docstring.
          requirePublicUintAbiOrInt64State cosmwasmPlanErr types state (allowNonPublic := true)
          let byteWidth ← abiByteWidthOfTypeV1 types state.typeId
          let fi := fields.size
          fields := fields.push {
            sourceId := fi
            name := state.name
            key := stateKey fi
            byteWidth
            endianness := .little
          }
          stateLeaves := stateLeaves.push #[fi]
  let marker := layoutMarker fields
  if marker == 0 then
    throw <| .planInvariant .cosmwasm
      "state layout marker collides with the reserved uninitialized value"
  pure {
    markerKey := layoutMarkerKey
    markerValue := marker
    payloadInitialization := .zeroAllFields
    fields
    stateLeaves
    pfAssetsDeclared := false
  }

private structure LoweredValueV1 where
  expr : Expr
  kind : CosmWasmValueKindV1
  depth : Nat
  expandedNodes : Nat
  dependencies : Array ValueIdV1
  /-- Multi-leaf carrier: Principal (len+8 words), Array UInt64 N, Map capacity-8
      occ/key/val, Bytes N (1-byte UInt8 leaves), named Struct/Enum (preorder
      UInt64/Int64 leaves), or Option `[tag,payload]` (Map IndexGet intermediate
      or B-OPT-STATE Option UInt64 state / construct).
      `expr` mirrors `leaves[0]!` (or literal 0). Scalar values keep `none`. -/
  aggregateLeaves : Option (Array Expr) := none
  /-- Physical byte width of each leaf KV value: 8 for UInt64 leaves
      (Array/Map/Principal/named Struct/Enum/Option), 1 for Bytes leaves (UInt8).
      Scalar values keep 8. -/
  leafByteWidth : Nat := 8
  deriving Inhabited

private def LoweredValueV1.isAggregate (v : LoweredValueV1) : Bool :=
  v.aggregateLeaves.isSome

private def LoweredValueV1.leafExprs (v : LoweredValueV1) : Array Expr :=
  match v.aggregateLeaves with
  | some ls => ls
  | none => #[v.expr]

private def mkAggregateValueV1 (leaves : Array Expr) (deps : Array ValueIdV1)
    (depth expandedNodes : Nat) (leafByteWidth : Nat := 8) : LoweredValueV1 :=
  let head := match leaves[0]? with | some e => e | none => .literal 0
  { expr := head
    -- Aggregate carrier uses uint64 kind only as a placeholder; isAggregate
    -- gates eq/store; pureCall/arith reject aggregates via isAggregate.
    kind := .uint64
    depth
    expandedNodes
    dependencies := deps
    aggregateLeaves := some leaves
    leafByteWidth }

/-- Promote pure ValueIds across effect boundaries (Token dual Map store). -/
private def promoteDominatingPureV1
    (blockEntry : Nat) (values : Array LoweredValueV1)
    (base : Array ValueIdV1) : Array ValueIdV1 := Id.run do
  let mut out := base
  for i in [blockEntry:values.size] do
    let id : ValueIdV1 := UInt32.ofNat i
    unless out.contains id do
      out := out.push id
  pure out

/-- Match-arm free values: scrutinee + dependency closure. -/
private def extendArmReadablesV1
    (values : Array LoweredValueV1) (armReadables : Array ValueIdV1)
    (scrutId : ValueIdV1) : Array ValueIdV1 := Id.run do
  let mut out := armReadables
  if !out.contains scrutId then
    out := out.push scrutId
  match values[scrutId.toNat]? with
  | none => pure out
  | some v =>
      for d in v.dependencies do
        if !out.contains d then
          out := out.push d
      pure out

private def makeParamsV1 (owner : String) (types : CosmWasmTypeClosureV1)
    (typeDecls : Array TypeDeclV1) (params : Array ParameterV1) :
    CompileResult (Array Param × Array LoweredValueV1) := do
  if params.size > maxParams then
    throw <| .planInvariant .cosmwasm s!"parameter count in {owner} exceeds profile limit {maxParams}"
  let mut planned : Array Param := #[]
  let mut values : Array LoweredValueV1 := #[]
  let mut nextInputOffset : Nat := 0
  for param in params do
    -- ValueId tracks logical params (values.size); planned may expand (Principal leaves).
    unless param.valueId.toNat == values.size do
      throw <| .planInvariant .cosmwasm
        s!"semantic parameter ValueIds in {owner} must match declaration order"
    unless isIdentifier param.name do
      throw <| .planInvariant .cosmwasm
        s!"parameter name '{param.name}' in {owner} is not a safe identifier"
    if types.isPrincipal param.typeId then
      -- T12: Principal expands to 9×UInt64 input words (leaf tuple).
      requirePublicUInt64OrInt64OrFieldOrPrincipalParam
        cosmwasmPlanErr types owner param (allowNonPublic := true)
      let leafSpecs ← flattenPrincipalLeafSpecsV1 param.name
      if planned.size + leafSpecs.size > maxParams then
        throw <| .planInvariant .cosmwasm
          s!"parameter count in {owner} exceeds profile limit {maxParams}"
      let mut leafExprs : Array Expr := #[]
      for leafName in leafSpecs do
        unless isIdentifier leafName do
          throw <| .planInvariant .cosmwasm
            s!"parameter name '{leafName}' in {owner} is not a safe identifier"
        let binding : Param := {
          sourceId := planned.size
          name := leafName
          inputOffset := nextInputOffset
          byteWidth := 8
          endianness := .little
        }
        planned := planned.push binding
        leafExprs := leafExprs.push (.param nextInputOffset)
        nextInputOffset := nextInputOffset + 8
      values := values.push (mkAggregateValueV1 leafExprs #[] 1 leafExprs.size)
    else if isAnonymousOptionTypeIdV1 typeDecls param.typeId then
      -- B-OPT-STATE residual: Option params stay fail closed (mirror Enum
      -- policy — state + entry/view Option returns are admitted; params not).
      throw <| .planInvariant .cosmwasm
        s!"unsupported CosmWasm semantic shape: Option parameter '{param.name}' in {owner} is outside the CosmWasm pilot (params stay fail closed)"
    else if types.isNamedAggregate param.typeId then
      -- B-RET-ABI residual: named Struct/Enum params stay fail closed on
      -- CosmWasm (state + entry/view returns are admitted; params are not).
      throw <| .planInvariant .cosmwasm
        s!"unsupported CosmWasm semantic shape: named Struct/Enum parameter '{param.name}' in {owner} is outside the B-RET-ABI surface (params stay fail closed)"
    else if types.isContainer param.typeId then
      -- Bytes N param: flatten to N×UInt8 input words (read-only aggregate;
      -- IndexGet on the leaves is the only access — params are immutable).
      -- Array/Map params stay fail closed: no CosmWasm array-param ABI in this
      -- pilot (Bytes leaves are the only flattened container param surface).
      let some (n, leafByteWidth) ←
        containerLeafLayoutV1 typeDecls types param.typeId |
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: container param is not Array/Map/Bytes"
      unless leafByteWidth == 1 do
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: Array/Map params are outside the CosmWasm pilot (only Bytes N params flatten to UInt8 leaves)"
      if planned.size + n > maxParams then
        throw <| .planInvariant .cosmwasm
          s!"parameter count in {owner} exceeds profile limit {maxParams}"
      let mut leafExprs : Array Expr := #[]
      for i in [0:n] do
        let leafName := param.name ++ "_" ++ toString i
        unless isIdentifier leafName do
          throw <| .planInvariant .cosmwasm
            s!"parameter name '{leafName}' in {owner} is not a safe identifier"
        let binding : Param := {
          sourceId := planned.size
          name := leafName
          inputOffset := nextInputOffset
          byteWidth := 1
          endianness := .little
        }
        planned := planned.push binding
        leafExprs := leafExprs.push (.narrowParam 8 nextInputOffset)
        nextInputOffset := nextInputOffset + slotPitchOfByteWidth 1
      values := values.push (mkAggregateValueV1 leafExprs #[] 1 leafExprs.size
        (leafByteWidth := 1))
    else
      -- T8b/BL-15: ABI params admit UInt{8,16,32,64}/Int64; cumulative 8-byte pitch.
      -- JSON entry range-checks to 2^bitWidth−1 (Emit); no silent truncation.
      requirePublicUintAbiOrInt64Param cosmwasmPlanErr types owner param
        (allowNonPublic := true)
      let isInt := (types.intWidthOf param.typeId).isSome
      let byteWidth ← abiByteWidthOfTypeV1 types param.typeId
      let bitWidth := bitWidthOfByteWidth byteWidth
      let binding : Param := {
        sourceId := planned.size
        name := param.name
        inputOffset := nextInputOffset
        byteWidth
        endianness := .little
      }
      nextInputOffset := nextInputOffset + slotPitchOfByteWidth byteWidth
      planned := planned.push binding
      let kind ←
        if isInt then pure CosmWasmValueKindV1.int64
        else match uintKindOfWidthV1 bitWidth with
          | some k => pure k
          | none =>
              throw <| .planInvariant .cosmwasm
                s!"unsupported CosmWasm semantic shape: ABI UInt{bitWidth} is not admitted"
      values := values.push {
        -- T8c: narrow ABI params retain semantic width for body arithmetic;
        -- IR loads still zero-extend into i64 temps.
        expr := mkParamExpr bitWidth binding.inputOffset
        kind
        depth := 1
        expandedNodes := 1
        dependencies := #[]
      }
  pure (planned, values)

private def findFieldV1 (layout : StorageLayout)
    (id : StateIdV1) : CompileResult StorageField :=
  -- Scalar path: stateLeaves singleton → physical field. sourceId is the
  -- physical field index (ValidatePlan dense), not the logical state id.
  match layout.stateLeaves[id.toNat]? with
  | some leaves =>
      match leaves[0]? with
      | some fi =>
          if leaves.size != 1 then
            planError s!"semantic expression references multi-leaf state id {id.toNat} as scalar"
          else match layout.fields[fi]? with
            | some field =>
                if field.sourceId == fi then .ok field
                else planError s!"semantic expression references noncanonical state id {id.toNat}"
            | none => planError s!"semantic expression references unknown state id {id.toNat}"
      | none => planError s!"semantic expression references empty leaf list for state id {id.toNat}"
  | none =>
      match layout.fields[id.toNat]? with
      | some field =>
          if field.sourceId == id.toNat then .ok field
          else planError s!"semantic expression references noncanonical state id {id.toNat}"
      | none => planError s!"semantic expression references unknown state id {id.toNat}"

/-- Resolve all physical leaf fields for a logical state id (T12 Principal). -/
private def findStateLeafFieldsV1 (layout : StorageLayout)
    (id : StateIdV1) : CompileResult (Array StorageField) := do
  match layout.stateLeaves[id.toNat]? with
  | some leaves =>
      let mut out : Array StorageField := #[]
      for fi in leaves do
        match layout.fields[fi]? with
        | some field =>
            unless field.sourceId == fi do
              throw <| .planInvariant .cosmwasm
                s!"semantic expression references noncanonical state leaf {fi}"
            out := out.push field
        | none =>
            throw <| .planInvariant .cosmwasm
              s!"semantic expression references unknown state leaf {fi}"
      pure out
  | none =>
      let field ← findFieldV1 layout id
      pure #[field]

private def findValueV1 (values : Array LoweredValueV1)
    (id : ValueIdV1) : CompileResult LoweredValueV1 :=
  match values[id.toNat]? with
  | some value => .ok value
  | none => planError s!"semantic expression references unknown ValueId {id.toNat}"

/-- Require a compile-time UInt32/UInt64 literal index for Array IndexGet/IndexSet. -/
private def literalIndexNatV1 (v : LoweredValueV1) : CompileResult Nat := do
  unless v.kind == .uint32 || v.kind == .uint64 do
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: Array index must be a UInt32/UInt64 literal"
  match v.expr with
  | .literal n => pure n.toNat
  | _ =>
      throw <| .planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: Array IndexGet/IndexSet requires a compile-time constant index"

private def decodeUInt64LiteralV1 (bytes : ByteArray) : CompileResult UInt64 :=
  decodeUInt64LiteralLe cosmwasmPlanErr "CosmWasm" bytes

/-- Decode a 4-byte little-endian UInt32 literal into a zero-extended UInt64
    plan value (shift counts only). -/
private def decodeUInt32LiteralV1 (bytes : ByteArray) : CompileResult UInt64 :=
  decodeUInt32LiteralLe cosmwasmPlanErr "CosmWasm" bytes

private def decodeBoolLiteralV1 (bytes : ByteArray) : CompileResult Bool :=
  decodeBoolLiteralBit cosmwasmPlanErr "CosmWasm" bytes

private def comparisonOpOfBinaryV1 (op : BinaryOpV1) : Option ComparisonOp :=
  match op with
  | .eq => some .eq
  | .ne => some .ne
  | .lt => some .lt
  | .le => some .le
  | .gt => some .gt
  | .ge => some .ge
  | _ => none

/-- Effect-boundary gate (Solana-aligned): values defined before `blockEntry`
    dominate this block (params, earlier pure SSA, loop-header temps). Only
    in-block pure values between `blockEntry` and `segmentStart` are sealed by
    an effect — unless promoted into `armReadables`. -/
private def currentValueV1
    (values : Array LoweredValueV1)
    (blockEntry segmentStart : Nat)
    (id : ValueIdV1) : CompileResult LoweredValueV1 := do
  let index := id.toNat
  if index >= blockEntry && index < segmentStart then
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: computed ValueId crosses an effect boundary"
  findValueV1 values id

/-- Match-bind / free-set readability: scrutinees and pure values promoted
    across an effect boundary may be referenced even when they fall in the
    sealed in-block range. Dominating values (`index < blockEntry`) stay free. -/
private def currentValueWithArmsV1
    (values : Array LoweredValueV1)
    (blockEntry segmentStart : Nat)
    (armReadables : Array ValueIdV1)
    (id : ValueIdV1) : CompileResult LoweredValueV1 := do
  let index := id.toNat
  if index >= blockEntry && index < segmentStart && !armReadables.contains id then
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: computed ValueId crosses an effect boundary"
  findValueV1 values id

private def makeBinaryTreeValueKindsV1
    (mk : Expr → Expr → Expr)
    (lhsKind rhsKind resultKind : CosmWasmValueKindV1)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless lhs.kind == lhsKind && rhs.kind == rhsKind do
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: binary operand kinds do not match the operator"
  let depth := 1 + max lhs.depth rhs.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .cosmwasm s!"CosmWasm plan expression exceeds depth {maxExprDepth}"
  if lhs.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .cosmwasm s!"CosmWasm plan expression exceeds node limit {maxPlanNodes}"
  let remaining := maxPlanNodes - 1 - lhs.expandedNodes
  if rhs.expandedNodes > remaining then
    throw <| .planInvariant .cosmwasm s!"CosmWasm plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := mk lhs.expr rhs.expr
    kind := resultKind
    depth
    expandedNodes := 1 + lhs.expandedNodes + rhs.expandedNodes
    dependencies := #[lhsId, rhsId]
  }

private def makeBinaryTreeValueV1
    (mk : Expr → Expr → Expr)
    (kind : CosmWasmValueKindV1)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 mk .uint64 .uint64 kind lhsId rhsId lhs rhs

/-- Width-dispatch: UInt64 keeps historical constructors; narrow widths use
    `narrow*` so Emit can attach width overflow/mask guards. -/
private def mkCheckedAdd (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .checkedAdd l r else .narrowCheckedAdd w l r
private def mkCheckedSub (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .checkedSub l r else .narrowCheckedSub w l r
private def mkCheckedMul (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .checkedMul l r else .narrowCheckedMul w l r
private def mkCheckedDiv (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .checkedDiv l r else .narrowCheckedDiv w l r
private def mkCheckedMod (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .checkedMod l r else .narrowCheckedMod w l r
private def mkBitAnd (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .bitAnd l r else .narrowBitAnd w l r
private def mkBitOr (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .bitOr l r else .narrowBitOr w l r
private def mkBitXor (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .bitXor l r else .narrowBitXor w l r
private def mkBitNot (w : Nat) (o : Expr) : Expr :=
  if w == 64 then .bitNot o else .narrowBitNot w o
private def mkShl (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .shl l r else .narrowShl w l r
private def mkShr (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .shr l r else .narrowShr w l r

private def makeCheckedAddValueV1
    (kind : CosmWasmValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkCheckedAdd bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeCheckedSubValueV1
    (kind : CosmWasmValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkCheckedSub bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeCheckedMulValueV1
    (kind : CosmWasmValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkCheckedMul bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeCheckedDivValueV1
    (kind : CosmWasmValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkCheckedDiv bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeCheckedModValueV1
    (kind : CosmWasmValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkCheckedMod bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeBitAndValueV1
    (kind : CosmWasmValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkBitAnd bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeBitOrValueV1
    (kind : CosmWasmValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkBitOr bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeBitXorValueV1
    (kind : CosmWasmValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkBitXor bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeShlValueV1
    (lhsKind : CosmWasmValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkShl bitWidth) lhsKind .uint32 lhsKind
    lhsId rhsId lhs rhs

private def makeShrValueV1
    (lhsKind : CosmWasmValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkShr bitWidth) lhsKind .uint32 lhsKind
    lhsId rhsId lhs rhs

private def makeBoolAndValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (fun l r => .boolAnd l r) .bool .bool .bool
    lhsId rhsId lhs rhs

private def makeBoolOrValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (fun l r => .boolOr l r) .bool .bool .bool
    lhsId rhsId lhs rhs

private def makeUnaryTreeValueV1
    (mk : Expr → Expr)
    (operandKind resultKind : CosmWasmValueKindV1)
    (operandId : ValueIdV1)
    (operand : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless operand.kind == operandKind do
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: unary operand kind mismatch"
  let depth := 1 + operand.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .cosmwasm s!"CosmWasm plan expression exceeds depth {maxExprDepth}"
  if operand.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .cosmwasm s!"CosmWasm plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := mk operand.expr
    kind := resultKind
    depth
    expandedNodes := 1 + operand.expandedNodes
    dependencies := #[operandId]
  }

private def makeBitNotValueV1
    (kind : CosmWasmValueKindV1) (bitWidth : Nat)
    (operandId : ValueIdV1)
    (operand : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeUnaryTreeValueV1 (mkBitNot bitWidth) kind kind operandId operand

private def makeBoolNotValueV1
    (operandId : ValueIdV1)
    (operand : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeUnaryTreeValueV1 (fun o => .boolNot o) .bool .bool operandId operand

private def makeCompareValueV1
    (op : ComparisonOp)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless lhs.kind == rhs.kind do
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: comparison operand kinds do not match"
  unless (widthOfUintKindV1 lhs.kind).isSome do
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: unsigned comparison requires UInt operands"
  let bw := match widthOfUintKindV1 lhs.kind with | some w => w | none => 64
  if bw > 64 then
    makeBinaryTreeValueKindsV1 (fun l r => .wideCompare bw op l r) lhs.kind rhs.kind .bool
      lhsId rhsId lhs rhs
  else
    makeBinaryTreeValueKindsV1 (fun l r => .compare op l r) lhs.kind rhs.kind .bool
      lhsId rhsId lhs rhs

/-- Admit a wire result TypeId for UInt-width arithmetic/bitwise and return
    `(typeId, kind, bitWidth)`. UInt8/16/32/64 only; UInt128/256 fail closed. -/
private def admitUIntWidthResultTypeV1
    (types : CosmWasmTypeClosureV1) (resultTypeId : TypeIdV1) :
    CompileResult (TypeIdV1 × CosmWasmValueKindV1 × Nat) := do
  match types.uintWidthOf resultTypeId with
  | some w =>
      unless isPilotBodyUintWidth w do
        throw <| .planInvariant .cosmwasm
          s!"unsupported CosmWasm semantic shape: arithmetic/bitwise result UInt{w} is not admitted"
      match uintKindOfWidthV1 w with
      | some k => pure (resultTypeId, k, w)
      | none =>
          throw <| .planInvariant .cosmwasm
            s!"unsupported CosmWasm semantic shape: arithmetic/bitwise result UInt{w} is not admitted"
  | none =>
      throw <| .planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: arithmetic/bitwise result must be admitted UInt width"

private def consumeCurrentSegmentV1
    (values : Array LoweredValueV1)
    (blockEntry segmentStart : Nat)
    (root : ValueIdV1) : CompileResult Expr := do
  let rootValue ← currentValueV1 values blockEntry segmentStart root
  let segmentCount := values.size - segmentStart
  let mut visited : Array Bool := Array.mk (List.replicate segmentCount false)
  let mut stack : Array Nat := #[]
  -- Only walk in-block segment values; dominating SSA is already closed.
  if root.toNat >= segmentStart then
    stack := stack.push root.toNat
  let mut visitedCount := 0
  while !stack.isEmpty do
    let index := stack.back!
    stack := stack.pop
    unless segmentStart <= index && index < values.size do
      throw <| .planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: sink references a stale ValueId"
    let localIndex := index - segmentStart
    if visited[localIndex]? == some false then
      visited := visited.set! localIndex true
      visitedCount := visitedCount + 1
      let value := values[index]!
      for dependency in value.dependencies do
        let dependencyIndex := dependency.toNat
        if dependencyIndex >= segmentStart then
          unless dependencyIndex < values.size do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: expression crosses an effect boundary"
          stack := stack.push dependencyIndex
        else if dependencyIndex >= blockEntry then
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: expression crosses an effect boundary"
  unless visitedCount == segmentCount do
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: dead or reordered value instructions"
  pure rootValue.expr

/-- B-RET-ABI: segment consume that returns the full `LoweredValueV1` (with
aggregate leaves) instead of just the head expr. Same segment discipline as
`consumeCurrentSegmentV1`. -/
private def consumeCurrentSegmentValueV1
    (values : Array LoweredValueV1)
    (blockEntry segmentStart : Nat)
    (root : ValueIdV1) : CompileResult LoweredValueV1 := do
  let rootValue ← currentValueV1 values blockEntry segmentStart root
  let segmentCount := values.size - segmentStart
  let mut visited : Array Bool := Array.mk (List.replicate segmentCount false)
  let mut stack : Array Nat := #[]
  if root.toNat >= segmentStart then
    stack := stack.push root.toNat
  let mut visitedCount := 0
  while !stack.isEmpty do
    let index := stack.back!
    stack := stack.pop
    unless segmentStart <= index && index < values.size do
      throw <| .planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: sink references a stale ValueId"
    let localIndex := index - segmentStart
    if visited[localIndex]? == some false then
      visited := visited.set! localIndex true
      visitedCount := visitedCount + 1
      let value := values[index]!
      for dependency in value.dependencies do
        let dependencyIndex := dependency.toNat
        if dependencyIndex >= segmentStart then
          unless dependencyIndex < values.size do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: expression crosses an effect boundary"
          stack := stack.push dependencyIndex
        else if dependencyIndex >= blockEntry then
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: expression crosses an effect boundary"
  unless visitedCount == segmentCount do
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: dead or reordered value instructions"
  pure rootValue

/-- Multi-root effect-boundary consumption (event/revert argument lists):
    every value produced in the current segment must be reachable from at
    least one sink root, mirroring the single-root discipline. -/
private def consumeSegmentRootsV1
    (values : Array LoweredValueV1)
    (blockEntry segmentStart : Nat)
    (roots : Array ValueIdV1) : CompileResult Unit := do
  for root in roots do
    let _ ← currentValueV1 values blockEntry segmentStart root
  let segmentCount := values.size - segmentStart
  let mut visited : Array Bool := Array.mk (List.replicate segmentCount false)
  let mut stack : Array Nat := #[]
  for root in roots do
    if root.toNat >= segmentStart then
      stack := stack.push root.toNat
  let mut visitedCount := 0
  while !stack.isEmpty do
    let index := stack.back!
    stack := stack.pop
    unless segmentStart <= index && index < values.size do
      throw <| .planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: sink references a stale ValueId"
    let localIndex := index - segmentStart
    if visited[localIndex]? == some false then
      visited := visited.set! localIndex true
      visitedCount := visitedCount + 1
      let value := values[index]!
      for dependency in value.dependencies do
        let dependencyIndex := dependency.toNat
        if dependencyIndex >= segmentStart then
          unless dependencyIndex < values.size do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: expression crosses an effect boundary"
          stack := stack.push dependencyIndex
        else if dependencyIndex >= blockEntry then
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: expression crosses an effect boundary"
  unless visitedCount == segmentCount do
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: dead or reordered value instructions"
  pure ()

private def appendResultValueV1
    (expectedTypeId : TypeIdV1)
    (values : Array LoweredValueV1)
    (result : ValueDefV1)
    (value : LoweredValueV1) : CompileResult (Array LoweredValueV1) := do
  unless result.valueId.toNat == values.size && result.typeId == expectedTypeId do
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: result ValueId/type is not canonical for its kind"
  if values.size >= maxPlanNodes then
    throw <| .planInvariant .cosmwasm s!"CosmWasm value table exceeds node limit {maxPlanNodes}"
  pure (values.push value)

private inductive SemanticCallableModeV1 where
  | initialize
  | mutate
  | view
  | pureFn
  deriving BEq

/-- PureFn signature environment used while lowering: `byCallable[callableId]`
    is `some fnIndex` for pureFn callables; `sigs` is indexed by fnIndex. -/
private structure CosmWasmFnSigV1 where
  paramCount : Nat
  resultKind : CosmWasmValueKindV1
  deriving BEq, Inhabited

private structure CosmWasmFnEnvV1 where
  byCallable : Array (Option Nat)
  sigs : Array CosmWasmFnSigV1
  deriving Inhabited

private def emptyCosmWasmFnEnvV1 : CosmWasmFnEnvV1 := { byCallable := #[], sigs := #[] }

private structure LoweredCallableV1 where
  params : Array Param
  body : Array Statement

private structure LoweredBlockV1 where
  statements : Array Statement
  values : Array LoweredValueV1
  segmentStart : Nat
  armReadables : Array ValueIdV1

private def makeCallFnValueV1
    (fnIndex : Nat)
    (resultKind : CosmWasmValueKindV1)
    (argIds : Array ValueIdV1)
    (args : Array LoweredValueV1) : CompileResult LoweredValueV1 := do
  let mut depth : Nat := 1
  let mut expanded : Nat := 1
  for arg in args do
    unless arg.kind == .uint64 || arg.kind == .int64 do
      throw <| .planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: pureCall arguments must be UInt64 or Int64"
    depth := max depth (1 + arg.depth)
    if expanded > maxPlanNodes - arg.expandedNodes then
      throw <| .planInvariant .cosmwasm s!"CosmWasm plan expression exceeds node limit {maxPlanNodes}"
    expanded := expanded + arg.expandedNodes
  if depth > maxExprDepth then
    throw <| .planInvariant .cosmwasm s!"CosmWasm plan expression exceeds depth {maxExprDepth}"
  pure {
    expr := .callFn fnIndex (args.map (·.expr))
    kind := resultKind
    depth
    expandedNodes := expanded
    dependencies := argIds
  }

/-- Lower one block's instruction sequence (terminator handled by the region
    walker). Each block starts a fresh effect segment; values from dominating
    blocks stay referenceable via the stable prefix, match-arm scrutinees, or
    pre-materialized loop-header block params. -/
private def lowerBlockInstructionsV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (types : CosmWasmTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (layout : StorageLayout)
    (fnEnv : CosmWasmFnEnvV1)
    (_stableCount : Nat)
    (armReadables0 : Array ValueIdV1)
    (block : BlockV1)
    (values0 : Array LoweredValueV1) : CompileResult LoweredBlockV1 := do
  -- Block params are admitted only as pre-materialized loop induction slots
  -- (filled by the region walker before entering a header). Empty is the
  -- non-loop case; non-empty without a prior materialization fails closed.
  for p in block.params do
    let some slot := values0[p.valueId.toNat]? |
      throw <| .planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: block parameter ValueId is out of range"
    match slot.expr with
    | .localTemp _ =>
        unless slot.kind == .uint64 && p.typeId == types.uint64TypeId do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: loop induction must be public UInt64"
    | _ =>
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: block parameters are not supported outside loop headers"
  if block.instructions.size > maxBodyStatements then
    throw <| .planInvariant .cosmwasm
      s!"{owner} instruction count exceeds profile limit {maxBodyStatements}"
  let mut values := values0
  let blockEntry := values0.size
  let mut segmentStart := values0.size
  let mut armReadables := armReadables0
  let mut body : Array Statement := #[]
  for instruction in block.instructions do
    match instruction.op, instruction.result with
    | .literal typeId bytes, some result =>
        if let some bitWidth := types.intWidthOf typeId then
          unless isAbiIntWidth bitWidth do
            throw <| .planInvariant .cosmwasm
              s!"unsupported CosmWasm semantic shape: Int{bitWidth} literal is not admitted"
          let value ← decodeIntWidthLiteralLe cosmwasmPlanErr "CosmWasm" bitWidth bytes
          values := ← appendResultValueV1 typeId values result {
            expr := .literal value
            kind := .int64
            depth := 1
            expandedNodes := 1
            dependencies := #[]
          }
        else if let some bitWidth := types.uintWidthOf typeId then
          unless isPilotBodyUintWidth bitWidth do
            throw <| .planInvariant .cosmwasm
              s!"unsupported CosmWasm semantic shape: UInt{bitWidth} literal is not admitted"
          let kind ← match uintKindOfWidthV1 bitWidth with
            | some k => pure k
            | none =>
                throw <| .planInvariant .cosmwasm
                  s!"unsupported CosmWasm semantic shape: UInt{bitWidth} literal is not admitted"
          if bitWidth ≤ 64 then
            let value ← decodeUIntWidthLiteralLe cosmwasmPlanErr "CosmWasm" bitWidth bytes
            values := ← appendResultValueV1 typeId values result {
              expr := .literal value
              kind
              depth := 1
              expandedNodes := 1
              dependencies := #[]
            }
          else
            let n ← decodeUIntWideLiteralLe cosmwasmPlanErr "CosmWasm" bitWidth bytes
            values := ← appendResultValueV1 typeId values result {
              expr := .bigLiteral bitWidth n
              kind
              depth := 1
              expandedNodes := 1
              dependencies := #[]
            }
        else if types.isPrincipal typeId then
          let leafExprs ← decodePrincipalLiteralLeavesV1 bytes
          let value := mkAggregateValueV1 leafExprs #[] 1 leafExprs.size
          values := ← appendResultValueV1 typeId values result value
        else
          let boolTypeId ← match types.boolTypeId with
            | some tid =>
                unless typeId == tid do
                  throw <| .planInvariant .cosmwasm
                    "unsupported CosmWasm semantic shape: literal is not admitted UInt width, Int64, Bool, or Principal"
                pure tid
            | none =>
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: Bool type is missing for Bool literal"
          let flag ← decodeBoolLiteralV1 bytes
          values := ← appendResultValueV1 boolTypeId values result {
            expr := .literal (if flag then 1 else 0)
            kind := .bool
            depth := 1
            expandedNodes := 1
            dependencies := #[]
          }
    | .stateLoad stateId, some result =>
        if mode == .pureFn then
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: pureFn cannot load state"
        let leafIdxs ← match layout.stateLeaves[stateId.toNat]? with
          | some ls => pure ls
          | none =>
              -- Legacy 1:1 without stateLeaves: physical index == stateId.
              pure #[stateId.toNat]
        if types.isContainer result.typeId then
          let some (n, leafByteWidth) ←
            containerLeafLayoutV1 typeDecls types result.typeId |
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: container state load is not Array/Map/Bytes UInt64"
          unless leafIdxs.size == n do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: Array/Map/Bytes state load leaf count mismatch"
          let mut leafExprs : Array Expr := #[]
          for fi in leafIdxs do
            -- Array/Map leaves are 8-byte UInt64 loads; Bytes leaves are
            -- 1-byte UInt8 loads (zero-extended into the i64 plan surface).
            leafExprs := leafExprs.push
              (if leafByteWidth == 8 then .stateLoad fi else .narrowStateLoad 8 fi)
          let value := mkAggregateValueV1 leafExprs #[] 1 leafExprs.size
            (leafByteWidth := leafByteWidth)
          values := ← appendResultValueV1 result.typeId values result value
        else if types.isPrincipal result.typeId then
          unless leafIdxs.size == nearPrincipalDataWordCountV1 + 1 do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: Principal state load leaf count mismatch"
          let mut leafExprs : Array Expr := #[]
          for fi in leafIdxs do
            leafExprs := leafExprs.push (.stateLoad fi)
          let value := mkAggregateValueV1 leafExprs #[] 1 leafExprs.size
          values := ← appendResultValueV1 result.typeId values result value
        else if isAnonymousOptionTypeIdV1 typeDecls result.typeId then
          -- B-OPT-STATE: Option UInt64 state load → 2-leaf aggregate (tag, payload).
          requireOptionUInt64StateV1 typeDecls types result.typeId "load"
          unless leafIdxs.size == 2 do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: Option state load leaf count mismatch"
          let mut leafExprs : Array Expr := #[]
          for fi in leafIdxs do
            leafExprs := leafExprs.push (.stateLoad fi)
          let value := mkAggregateValueV1 leafExprs #[] 1 leafExprs.size
          values := ← appendResultValueV1 result.typeId values result value
        else if types.isNamedAggregate result.typeId then
          let n ← leafCountOfTypeV1 typeDecls types result.typeId
          unless leafIdxs.size == n do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: named Struct/Enum state load leaf count mismatch"
          let mut leafExprs : Array Expr := #[]
          for fi in leafIdxs do
            leafExprs := leafExprs.push (.stateLoad fi)
          let value := mkAggregateValueV1 leafExprs #[] 1 leafExprs.size
          values := ← appendResultValueV1 result.typeId values result value
        else
          let fi ← match leafIdxs[0]? with
            | some i =>
                unless leafIdxs.size == 1 do
                  throw <| .planInvariant .cosmwasm
                    "unsupported CosmWasm semantic shape: scalar state load saw multi-leaf layout"
                pure i
            | none =>
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: state load has no leaf fields"
          let field ← match layout.fields[fi]? with
            | some f => pure f
            | none =>
                throw <| .planInvariant .cosmwasm
                  s!"unsupported CosmWasm semantic shape: state field {fi} missing"
          let isInt := (types.intWidthOf result.typeId).isSome
          let bitWidth ←
            if isInt then pure 64
            else match types.uintWidthOf result.typeId with
              | some w =>
                  unless isAbiUintWidth w do
                    throw <| .planInvariant .cosmwasm
                      s!"unsupported CosmWasm semantic shape: state load UInt{w} is not admitted"
                  pure w
              | none =>
                  throw <| .planInvariant .cosmwasm
                    "unsupported CosmWasm semantic shape: state load must be UInt{8,16,32,64}, Int64, Principal, named Struct/Enum, Array/Map, or Option UInt64"
          unless field.byteWidth == byteWidthOfBitWidth bitWidth do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: state load width does not match field layout"
          let kind ←
            if isInt then pure CosmWasmValueKindV1.int64
            else match uintKindOfWidthV1 bitWidth with
              | some k => pure k
              | none =>
                  throw <| .planInvariant .cosmwasm
                    s!"unsupported CosmWasm semantic shape: state load UInt{bitWidth} is not admitted"
          values := ← appendResultValueV1 result.typeId values result {
            -- T8c: narrow ABI loads retain semantic width for body arithmetic;
            -- IR still zero-extends into i64 temps.
            expr := mkStateLoadExpr bitWidth fi
            kind
            depth := 1
            expandedNodes := 1
            dependencies := #[]
          }
    | .binary op lhsId rhsId, some result =>
        let lhs ← currentValueWithArmsV1 values blockEntry segmentStart armReadables lhsId
        let rhs ← currentValueWithArmsV1 values blockEntry segmentStart armReadables rhsId
        if lhs.isAggregate || rhs.isAggregate then
          -- T12 Principal: only == / != via leaf-wise eq.
          match comparisonOpOfBinaryV1 op with
          | some cmpOp =>
              unless cmpOp == .eq || cmpOp == .ne do
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: aggregate comparison only supports == / !="
              let boolTypeId ← match types.boolTypeId with
                | some tid => pure tid
                | none =>
                    throw <| .planInvariant .cosmwasm
                      "unsupported CosmWasm semantic shape: Bool type is missing for aggregate comparison"
              unless result.typeId == boolTypeId do
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: aggregate comparison result must be Bool"
              unless lhs.isAggregate && rhs.isAggregate do
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: aggregate comparison requires both operands aggregate"
              let le := lhs.leafExprs
              let re := rhs.leafExprs
              unless le.size == re.size && le.size > 0 do
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: aggregate comparison leaf count mismatch"
              let mut acc : Expr := .compare .eq le[0]! re[0]!
              for i in [1:le.size] do
                acc := .boolAnd acc (.compare .eq le[i]! re[i]!)
              let expr := if cmpOp == .ne then .boolNot acc else acc
              values := ← appendResultValueV1 boolTypeId values result {
                expr
                kind := .bool
                depth := max lhs.depth rhs.depth + le.size + 1
                expandedNodes := lhs.expandedNodes + rhs.expandedNodes + le.size + 1
                dependencies := (lhs.dependencies ++ rhs.dependencies).push lhsId |>.push rhsId
              }
          | none =>
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: binary ops on aggregate operands only support == / !="
        else if op == .and || op == .or then
          let boolTypeId ← match types.boolTypeId with
            | some tid => pure tid
            | none =>
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: Bool type is missing for logical op"
          unless result.typeId == boolTypeId do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: logical result must be Bool"
          let value ←
            if op == .and then makeBoolAndValueV1 lhsId rhsId lhs rhs
            else makeBoolOrValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 boolTypeId values result value
        else if op == .shl || op == .shr then
          -- Shifts: admitted body UInt/Int64 operand, UInt32 count; result matches lhs.
          unless (widthOfUintKindV1 lhs.kind).isSome || lhs.kind == .int64 do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: shift operand must be admitted integer width"
          unless rhs.kind == .uint32 do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: shift count must be UInt32"
          if lhs.kind == .int64 then
            let resultTid ← match types.int64TypeId with
              | some tid =>
                  unless result.typeId == tid do
                    throw <| .planInvariant .cosmwasm
                      "unsupported CosmWasm semantic shape: Int64 shift result type mismatch"
                  pure tid
              | none => throw (.planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: Int64 type is missing for shift")
            if op == .shl then
              let value ← makeShlValueV1 .int64 64 lhsId rhsId lhs rhs
              values := ← appendResultValueV1 resultTid values result value
            else
              let value ← makeBinaryTreeValueKindsV1 (fun l r => .sar l r)
                .int64 .uint32 .int64 lhsId rhsId lhs rhs
              values := ← appendResultValueV1 resultTid values result value
          else
            let (widthTid, kind, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            unless kind == lhs.kind do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: shift result width mismatch"
            -- Cross-limb shift is not implemented: the multiword surface is
            -- add/sub/mul/compare/bitwise. Wide shifts fail closed explicitly
            -- (a single-limb WAT shift would silently corrupt high limbs).
            if bitWidth > 64 then
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: multiword shift is fail-closed on CosmWasm (shift counts < 64 only; wide shift not implemented)"
            let value ←
              if op == .shl then makeShlValueV1 kind bitWidth lhsId rhsId lhs rhs
              else makeShrValueV1 kind bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        else
          -- Body multi-width UInt arithmetic / bitwise / comparison, or Int64.
          unless lhs.kind != .bool && rhs.kind != .bool do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: binary operands must be integer"
          unless (lhs.kind == .int64) == (rhs.kind == .int64) do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: binary operands must share signedness"
          if lhs.kind == .int64 then
            let wordTid ← match types.intWidthOf result.typeId with
              | some _ => pure result.typeId
              | none => throw (.planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: Int type is missing")
            if op == .add then
              unless result.typeId == wordTid do
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: arithmetic result type mismatch"
              let value ← makeBinaryTreeValueKindsV1 (fun l r => .signedCheckedAdd l r)
                .int64 .int64 .int64 lhsId rhsId lhs rhs
              values := ← appendResultValueV1 wordTid values result value
            else if op == .sub then
              unless result.typeId == wordTid do
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: arithmetic result type mismatch"
              let value ← makeBinaryTreeValueKindsV1 (fun l r => .signedCheckedSub l r)
                .int64 .int64 .int64 lhsId rhsId lhs rhs
              values := ← appendResultValueV1 wordTid values result value
            else if op == .mul then
              unless result.typeId == wordTid do
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: arithmetic result type mismatch"
              let value ← makeBinaryTreeValueKindsV1 (fun l r => .signedCheckedMul l r)
                .int64 .int64 .int64 lhsId rhsId lhs rhs
              values := ← appendResultValueV1 wordTid values result value
            else if op == .div then
              unless result.typeId == wordTid do
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: arithmetic result type mismatch"
              let value ← makeBinaryTreeValueKindsV1 (fun l r => .signedCheckedDiv l r)
                .int64 .int64 .int64 lhsId rhsId lhs rhs
              values := ← appendResultValueV1 wordTid values result value
            else if op == .mod then
              unless result.typeId == wordTid do
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: arithmetic result type mismatch"
              let value ← makeBinaryTreeValueKindsV1 (fun l r => .signedCheckedMod l r)
                .int64 .int64 .int64 lhsId rhsId lhs rhs
              values := ← appendResultValueV1 wordTid values result value
            else if op == .bitAnd || op == .bitOr || op == .bitXor then
              unless result.typeId == wordTid do
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: bitwise result type mismatch"
              let value ←
                if op == .bitAnd then
                  makeBinaryTreeValueKindsV1 (fun l r => .bitAnd l r)
                    .int64 .int64 .int64 lhsId rhsId lhs rhs
                else if op == .bitOr then
                  makeBinaryTreeValueKindsV1 (fun l r => .bitOr l r)
                    .int64 .int64 .int64 lhsId rhsId lhs rhs
                else
                  makeBinaryTreeValueKindsV1 (fun l r => .bitXor l r)
                    .int64 .int64 .int64 lhsId rhsId lhs rhs
              values := ← appendResultValueV1 wordTid values result value
            else
              match comparisonOpOfBinaryV1 op with
              | some cmpOp =>
                  let boolTypeId ← match types.boolTypeId with
                    | some tid => pure tid
                    | none =>
                        throw <| .planInvariant .cosmwasm
                          "unsupported CosmWasm semantic shape: Bool type is missing for comparison"
                  unless result.typeId == boolTypeId do
                    throw <| .planInvariant .cosmwasm
                      "unsupported CosmWasm semantic shape: comparison result must be Bool"
                  let value ← makeBinaryTreeValueKindsV1 (fun l r => .signedCompare cmpOp l r)
                    .int64 .int64 .bool lhsId rhsId lhs rhs
                  values := ← appendResultValueV1 boolTypeId values result value
              | none =>
                  throw <| .planInvariant .cosmwasm
                    "unsupported CosmWasm semantic shape: only checked Int64 arith/bitwise and comparisons are supported"
          else
            -- Unsigned body multi-width path (UInt8/16/32/64).
            unless lhs.kind == rhs.kind do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: binary operands must share admitted UInt width"
            let some bitWidth := widthOfUintKindV1 lhs.kind |
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: binary operands must be admitted UInt width"
            unless isPilotBodyUintWidth bitWidth do
              throw <| .planInvariant .cosmwasm
                s!"unsupported CosmWasm semantic shape: UInt{bitWidth} is not an admitted body width"
            if op == .add || op == .sub || op == .mul || op == .div ||
                op == .mod || op == .bitAnd || op == .bitOr || op == .bitXor then
              -- Multiword div/mod are not implemented: the wide surface is
              -- add/sub/mul (schoolbook) plus compare/bitwise. Failing closed
              -- here keeps a single-limb `i64.div_u` from silently corrupting
              -- the high limbs of a UInt128/256 value.
              if bitWidth > 64 && (op == .div || op == .mod) then
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: multiword div/mod is fail-closed on CosmWasm (only multiword add/sub/mul are implemented)"
              let (widthTid, kind, w) ← admitUIntWidthResultTypeV1 types result.typeId
              unless kind == lhs.kind && w == bitWidth do
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: arithmetic/bitwise result width mismatch"
              let value ←
                if op == .add then makeCheckedAddValueV1 kind w lhsId rhsId lhs rhs
                else if op == .sub then makeCheckedSubValueV1 kind w lhsId rhsId lhs rhs
                else if op == .mul then makeCheckedMulValueV1 kind w lhsId rhsId lhs rhs
                else if op == .div then makeCheckedDivValueV1 kind w lhsId rhsId lhs rhs
                else if op == .mod then makeCheckedModValueV1 kind w lhsId rhsId lhs rhs
                else if op == .bitAnd then makeBitAndValueV1 kind w lhsId rhsId lhs rhs
                else if op == .bitOr then makeBitOrValueV1 kind w lhsId rhsId lhs rhs
                else makeBitXorValueV1 kind w lhsId rhsId lhs rhs
              values := ← appendResultValueV1 widthTid values result value
            else
              match comparisonOpOfBinaryV1 op with
              | some cmpOp =>
                  let boolTypeId ← match types.boolTypeId with
                    | some tid => pure tid
                    | none =>
                        throw <| .planInvariant .cosmwasm
                          "unsupported CosmWasm semantic shape: Bool type is missing for comparison"
                  unless result.typeId == boolTypeId do
                    throw <| .planInvariant .cosmwasm
                      "unsupported CosmWasm semantic shape: comparison result must be Bool"
                  let value ← makeCompareValueV1 cmpOp lhsId rhsId lhs rhs
                  values := ← appendResultValueV1 boolTypeId values result value
              | none =>
                  throw <| .planInvariant .cosmwasm
                    "unsupported CosmWasm semantic shape: only checked multi-width UInt arith/bitwise, shift, Bool logical, and comparisons are supported"
    | .unary op operandId, some result =>
        let operand ← currentValueWithArmsV1 values blockEntry segmentStart armReadables operandId
        match op with
        | .bitNot =>
            if operand.kind == .int64 then
              let wordTid ← match types.intWidthOf result.typeId with
              | some _ => pure result.typeId
              | none => throw (.planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: Int type is missing")
              unless result.typeId == wordTid do
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: bitNot result type mismatch"
              let value ← makeBitNotValueV1 .int64 64 operandId operand
              values := ← appendResultValueV1 wordTid values result value
            else
              let some bitWidth := widthOfUintKindV1 operand.kind |
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: bitNot operand must be admitted integer width"
              let (widthTid, kind, w) ← admitUIntWidthResultTypeV1 types result.typeId
              unless kind == operand.kind && w == bitWidth do
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: bitNot result width mismatch"
              let value ← makeBitNotValueV1 kind w operandId operand
              values := ← appendResultValueV1 widthTid values result value
        | .not =>
            let boolTypeId ← match types.boolTypeId with
              | some tid => pure tid
              | none =>
                  throw <| .planInvariant .cosmwasm
                    "unsupported CosmWasm semantic shape: Bool type is missing for bool not"
            unless result.typeId == boolTypeId do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: bool not result must be Bool"
            let value ← makeBoolNotValueV1 operandId operand
            values := ← appendResultValueV1 boolTypeId values result value
        | .neg =>
            unless operand.kind == .int64 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: Op.Unary.neg requires Int64"
            let tid ← match types.int64TypeId with
              | some t => pure t
              | none => throw (.planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: Int64 type is missing for neg")
            unless result.typeId == tid do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: checkedNeg result must be Int64"
            let value ← makeUnaryTreeValueV1 (fun o => .checkedNeg o) .int64 .int64
              operandId operand
            values := ← appendResultValueV1 tid values result value
    | .pureCall callableId argIds, some result =>
        let fnIndex ← match fnEnv.byCallable[callableId.toNat]? with
          | some (some idx) => pure idx
          | _ =>
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pureCall target is not a declared pureFn"
        let sig ← match fnEnv.sigs[fnIndex]? with
          | some s => pure s
          | none =>
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pureCall fnIndex is out of range"
        unless argIds.size == sig.paramCount do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: pureCall arity does not match the callee"
        let expectedTypeId ← match sig.resultKind with
          | .uint64 => pure types.uint64TypeId
          | .int64 =>
              match types.int64TypeId with
              | some tid => pure tid
              | none => throw (.planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: Int64 type is missing for pureCall")
          | .bool =>
              match types.boolTypeId with
              | some tid => pure tid
              | none =>
                  throw <| .planInvariant .cosmwasm
                    "unsupported CosmWasm semantic shape: Bool type is missing for pureCall result"
          | .uint32 | .uint16 | .uint8 | .uint128 | .uint256 =>
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pureCall result cannot be narrow/multiword UInt"
        unless result.typeId == expectedTypeId do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: pureCall result type does not match the callee"
        let mut argValues : Array LoweredValueV1 := #[]
        for argId in argIds do
          let root ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
          unless !root.isAggregate && (root.kind == .uint64 || root.kind == .int64) do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: pureCall arguments must be UInt64 or Int64"
          argValues := argValues.push root
        -- Pure expression (not an effect boundary): stay inside the segment;
        -- dependencies on the arg roots let later sinks consume the tree.
        let value ← makeCallFnValueV1 fnIndex sig.resultKind argIds argValues
        values := ← appendResultValueV1 expectedTypeId values result value
    | .stateStore stateId valueId, none =>
        if mode == .view then
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: view callable writes state"
        if mode == .pureFn then
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: pureFn cannot store state"
        let leafIdxs ← match layout.stateLeaves[stateId.toNat]? with
          | some ls => pure ls
          | none => pure #[stateId.toNat]
        let root ← currentValueWithArmsV1 values blockEntry segmentStart armReadables valueId
        if root.isAggregate then
          -- Principal / Array / Map / Bytes / named Struct/Enum / Option UInt64
          -- multi-leaf store as one atomic unit. Soft: dual Map stores leave pure
          -- values for a later store (Token). Atomic: all leaf Exprs share the
          -- pre-store KV snapshot at IR lower (store-then-read hazard).
          let leaves := root.leafExprs
          unless leaves.size == leafIdxs.size do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: aggregate state store leaf count mismatch"
          unless leaves.size > 0 do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: aggregate state store has zero leaves"
          let _ ← currentValueWithArmsV1 values blockEntry segmentStart armReadables valueId
          let mut storeLeaves : Array Store := #[]
          for i in [0:leaves.size] do
            let some fi := leafIdxs[i]? |
              throw <| .planInvariant .cosmwasm "aggregate state store field missing"
            let some leafExpr := leaves[i]? |
              throw <| .planInvariant .cosmwasm "aggregate state store leaf missing"
            let field ← match layout.fields[fi]? with
              | some f => pure f
              | none =>
                  throw <| .planInvariant .cosmwasm
                    s!"unsupported CosmWasm semantic shape: aggregate store field {fi} missing"
            storeLeaves := storeLeaves.push {
              fieldIndex := fi
              value := leafExpr
              byteWidth := field.byteWidth
            }
          body := body.push (.storeAtomic storeLeaves)
          armReadables := promoteDominatingPureV1 blockEntry values armReadables
          segmentStart := values.size
        else
          let fi ← match leafIdxs[0]? with
            | some i =>
                unless leafIdxs.size == 1 do
                  throw <| .planInvariant .cosmwasm
                    "unsupported CosmWasm semantic shape: scalar store to multi-leaf state"
                pure i
            | none =>
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: state store has no leaf fields"
          let field ← match layout.fields[fi]? with
            | some f => pure f
            | none =>
                throw <| .planInvariant .cosmwasm
                  s!"unsupported CosmWasm semantic shape: state field {fi} missing"
          let expectedBitWidth := bitWidthOfByteWidth field.byteWidth
          -- T8c: store value width must match field layout (narrow body temps OK).
          if root.kind == .int64 then
            unless field.byteWidth == 8 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: Int state store requires 8-byte field"
          else
            let some valueWidth := widthOfUintKindV1 root.kind |
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: state store value must be admitted UInt width or Int64"
            unless valueWidth == expectedBitWidth do
              throw <| .planInvariant .cosmwasm
                s!"unsupported CosmWasm semantic shape: state store value width {valueWidth} must match field bitWidth {expectedBitWidth}"
            unless isAbiUintWidth valueWidth do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: state store value must be admitted UInt width or Int64"
          let value ← consumeCurrentSegmentV1 values blockEntry segmentStart valueId
          body := body.push (.store {
            fieldIndex := fi
            value
            byteWidth := field.byteWidth
          })
          armReadables := promoteDominatingPureV1 blockEntry values armReadables
          segmentStart := values.size
    | .assert_ condId errorId args, none =>
        unless errorId.isNone && args.isEmpty do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: assert must use errorId=none and empty args"
        let root ← currentValueWithArmsV1 values blockEntry segmentStart armReadables condId
        unless root.kind == .bool do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: assert condition must be Bool"
        let condition ← consumeCurrentSegmentV1 values blockEntry segmentStart condId
        body := body.push (.assert condition)
        armReadables := promoteDominatingPureV1 blockEntry values armReadables
        segmentStart := values.size
    | .emit _effectId eventId argIds, none =>
        if mode == .view then
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: view callable emits an event"
        if mode == .pureFn then
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: pureFn cannot emit events"
        let mut argExprs : Array Expr := #[]
        for argId in argIds do
          let root ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
          unless root.kind == .uint64 do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: event arguments must be UInt64"
          argExprs := argExprs.push root.expr
        -- Multi-root effect boundary: every value produced in the current
        -- segment must be reachable from at least one argument tree.
        let _ ← consumeSegmentRootsV1 values blockEntry segmentStart argIds
        body := body.push (.emitEvent eventId.toNat argExprs)
        armReadables := promoteDominatingPureV1 blockEntry values armReadables
        segmentStart := values.size
    | .externalCall _effectId callee argIds, none =>
        -- Non-catalog sync call remains fail closed (WasmMsg::Execute is SubMsg
        -- savepoint, not EVM CALL). ADR-0029 C1 opens catalog pf.assets native
        -- deposit/transfer only when extension.pf-assets is declared.
        if mode == .view then
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: view callable makes an external call"
        if mode == .pureFn then
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: pureFn cannot make external calls"
        let components := callee.components.toArray
        unless components.size ≥ 2 do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: external call callee must have at least two components"
        let qn := String.intercalate "." components.toList
        if isPfAssetsCatalogQnV1 qn then
          unless layout.pfAssetsDeclared do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: pf.assets catalog call requires extension.pf-assets declaration"
          if qn == "pf.assets.native.deposit" then
            unless argIds.size == 1 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.native.deposit requires one UInt64 arg"
            let some amountId := argIds[0]? |
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.native.deposit arg missing"
            let amountRoot ← currentValueWithArmsV1 values blockEntry segmentStart
              armReadables amountId
            unless amountRoot.kind == .uint64 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.native.deposit amount must be UInt64"
            let _ ← consumeSegmentRootsV1 values blockEntry segmentStart argIds
            body := body.push (.nativeDeposit amountRoot.expr)
            armReadables := promoteDominatingPureV1 blockEntry values armReadables
            segmentStart := values.size
          else if qn == "pf.assets.native.transfer" then
            unless argIds.size == 2 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.native.transfer requires Principal + UInt64 args"
            let some dstId := argIds[0]? |
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.native.transfer dst missing"
            let some amountId := argIds[1]? |
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.native.transfer amount missing"
            let dstRoot ← currentValueWithArmsV1 values blockEntry segmentStart
              armReadables dstId
            unless dstRoot.isAggregate do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.native.transfer dst must be Principal"
            let dstLeaves := dstRoot.leafExprs
            unless dstLeaves.size == 1 + nearPrincipalDataWordCountV1 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.native.transfer dst Principal leaf count mismatch"
            let some dstLen := dstLeaves[0]? |
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.native.transfer dst len missing"
            let dstWords := dstLeaves.extract 1 dstLeaves.size
            unless dstWords.size == nearPrincipalDataWordCountV1 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.native.transfer dst body words mismatch"
            let amountRoot ← currentValueWithArmsV1 values blockEntry segmentStart
              armReadables amountId
            unless amountRoot.kind == .uint64 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.native.transfer amount must be UInt64"
            let _ ← consumeSegmentRootsV1 values blockEntry segmentStart argIds
            body := body.push (.nativeTransfer dstLen dstWords amountRoot.expr)
            armReadables := promoteDominatingPureV1 blockEntry values armReadables
            segmentStart := values.size
          else if qn == "pf.assets.token.transfer" then
            -- ADR-0030 E1-CW: controlled dynamic callee (CW20 Transfer).
            unless argIds.size == 3 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.token.transfer requires mint + dst + UInt64 args"
            let some mintId := argIds[0]? |
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.token.transfer mint missing"
            let some dstId := argIds[1]? |
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.token.transfer dst missing"
            let some amountId := argIds[2]? |
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.token.transfer amount missing"
            -- mint Principal (CW20 contract address): same wire-shape gate as dst.
            let mintRoot ← currentValueWithArmsV1 values blockEntry segmentStart
              armReadables mintId
            unless mintRoot.isAggregate do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.token.transfer mint must be Principal"
            let mintLeaves := mintRoot.leafExprs
            unless mintLeaves.size == 1 + nearPrincipalDataWordCountV1 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.token.transfer mint Principal leaf count mismatch"
            let some mintLen := mintLeaves[0]? |
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.token.transfer mint len missing"
            let mintWords := mintLeaves.extract 1 mintLeaves.size
            unless mintWords.size == nearPrincipalDataWordCountV1 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.token.transfer mint body words mismatch"
            -- dst Principal (CW20 recipient): same wire-shape gate as C1 native.
            let dstRoot ← currentValueWithArmsV1 values blockEntry segmentStart
              armReadables dstId
            unless dstRoot.isAggregate do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.token.transfer dst must be Principal"
            let dstLeaves := dstRoot.leafExprs
            unless dstLeaves.size == 1 + nearPrincipalDataWordCountV1 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.token.transfer dst Principal leaf count mismatch"
            let some dstLen := dstLeaves[0]? |
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.token.transfer dst len missing"
            let dstWords := dstLeaves.extract 1 dstLeaves.size
            unless dstWords.size == nearPrincipalDataWordCountV1 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.token.transfer dst body words mismatch"
            -- amount must be UInt64.
            let amountRoot ← currentValueWithArmsV1 values blockEntry segmentStart
              armReadables amountId
            unless amountRoot.kind == .uint64 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: pf.assets.token.transfer amount must be UInt64"
            let _ ← consumeSegmentRootsV1 values blockEntry segmentStart argIds
            body := body.push
              (.tokenTransfer mintLen mintWords dstLen dstWords amountRoot.expr)
            armReadables := promoteDominatingPureV1 blockEntry values armReadables
            segmentStart := values.size
          else
            throw <| .planInvariant .cosmwasm
              s!"unsupported CosmWasm semantic shape: pf.assets QN '{qn}' is outside admitted scope (async/tokenAsync fail closed)"
        else
          throw <| .planInvariant .cosmwasm
            "call/sync external call is outside the CosmWasm MVP envelope (WasmMsg::Execute is SubMsg savepoint, not sync CALL; non-catalog call fail closed; pf.assets native deposit/transfer only)"
    | .schedule _effectId callee argIds, none =>
        -- CW-4: schedule → SubMsg { reply_on: never, id: 0, WasmMsg::Execute }.
        -- See Statement.promiseAccount docstring for wasmd ReplyNever verification
        -- and same-tx / failure-propagation caveats vs Reference fire-and-forget.
        if mode == .view then
          throw <| .planInvariant .cosmwasm
            (nearScheduleDisallowedError "view callable schedules a workflow")
        if mode == .pureFn then
          throw <| .planInvariant .cosmwasm
            (nearScheduleDisallowedError "pureFn cannot schedule workflows")
        let components := callee.components.toArray
        unless components.size ≥ 2 do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: schedule callee must have at least two components"
        let receiver := String.intercalate "." components.toList
        unless isNearAccountId receiver do
          throw <| .planInvariant .cosmwasm (nearAccountIdError receiver)
        let method := components[components.size - 1]!
        unless isIdentifier method do
          throw <| .planInvariant .cosmwasm
            s!"schedule method '{method}' is not a safe identifier"
        let mut argExprs : Array Expr := #[]
        for argId in argIds do
          let root ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
          unless root.kind == .uint64 || root.kind == .int64 do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: schedule arguments must be UInt64 or Int64"
          argExprs := argExprs.push root.expr
        let _ ← consumeSegmentRootsV1 values blockEntry segmentStart argIds
        body := body.push (.promiseAccount receiver method argExprs)
        armReadables := promoteDominatingPureV1 blockEntry values armReadables
        segmentStart := values.size
    -- Array construct N args, Map.empty (ctor 0, 0 args → dense zero leaves),
    -- or named Struct/Enum construct (field/payload leaf assembly).
    -- Bytes has no source constructor (Normalize never emits `.construct` for
    -- Bytes); the gate below is a defensive fail-closed boundary.
    | .construct typeId ctorIdx argIds, some result => do
        unless result.typeId == typeId do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: construct result typeId must match op typeId"
        match ← containerLeafLayoutV1 typeDecls types typeId with
        | some (n, leafByteWidth) => do
            unless leafByteWidth == 8 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: Bytes construct is outside the CosmWasm pilot (Bytes values enter via state/params only)"
            unless ctorIdx == 0 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: Array/Map construct ctorIdx must be 0"
            -- N-MAP-CONSTRUCT: nonempty Map construct (flattened kv pairs) is
            -- outside the CosmWasm pilot; product maps are built via IndexSet.
            let isMapConstruct := match typeDecls[typeId.toNat]? with
              | some { shape := .map _ _, .. } => true
              | _ => false
            if isMapConstruct && !argIds.isEmpty then
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: nonempty Map construct is outside the CosmWasm pilot (build maps via IndexSet upsert)"
            if n == nearMapPilotLeafCountV1 && argIds.isEmpty then
              let mut zeros : Array Expr := #[]
              for _ in [0:n] do
                zeros := zeros.push (.literal 0)
              let value := mkAggregateValueV1 zeros #[] 1 n
              values := ← appendResultValueV1 result.typeId values result value
            else do
              unless argIds.size == n do
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: Array construct arity mismatch"
              let mut leafExprs : Array Expr := #[]
              let mut deps : Array ValueIdV1 := #[]
              let mut depth : Nat := 1
              let mut nodes : Nat := 0
              for argId in argIds do
                let arg ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
                unless !arg.isAggregate && arg.kind == .uint64 do
                  throw <| .planInvariant .cosmwasm
                    "unsupported CosmWasm semantic shape: Array construct args must be scalar UInt64"
                leafExprs := leafExprs.push arg.expr
                deps := deps.push argId
                depth := Nat.max depth (arg.depth + 1)
                nodes := nodes + arg.expandedNodes
              let value := mkAggregateValueV1 leafExprs deps depth (nodes + n)
              values := ← appendResultValueV1 result.typeId values result value
        | none => do
            -- Option UInt64 construct (none/some) for anonymous-result returns;
            -- named Struct/Enum construct remains the other non-container path.
            match typeDecls[typeId.toNat]? with
            | some { shape := .option elTid, name := none, .. } => do
                unless elTid == types.uint64TypeId do
                  throw <| .planInvariant .cosmwasm
                    "unsupported CosmWasm semantic shape: Option construct requires UInt64 payload"
                match ctorIdx.toNat with
                | 0 =>
                    -- Option.none → (tag=0, payload=0)
                    unless argIds.isEmpty do
                      throw <| .planInvariant .cosmwasm
                        "unsupported CosmWasm semantic shape: Option.none construct takes no args"
                    let leaves : Array Expr := #[.literal 0, .literal 0]
                    let value := mkAggregateValueV1 leaves #[] 1 2
                    values := ← appendResultValueV1 result.typeId values result value
                | 1 =>
                    -- Option.some(v) → (tag=1, payload=v)
                    unless argIds.size == 1 do
                      throw <| .planInvariant .cosmwasm
                        "unsupported CosmWasm semantic shape: Option.some construct takes one arg"
                    let some argId := argIds[0]? |
                      throw <| .planInvariant .cosmwasm "Option.some construct arg missing"
                    let arg ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
                    unless !arg.isAggregate && arg.kind == .uint64 do
                      throw <| .planInvariant .cosmwasm
                        "unsupported CosmWasm semantic shape: Option.some arg must be scalar UInt64"
                    let leaves : Array Expr := #[.literal 1, arg.expr]
                    let value := mkAggregateValueV1 leaves #[argId]
                      (arg.depth + 1) (arg.expandedNodes + 2)
                    values := ← appendResultValueV1 result.typeId values result value
                | _ =>
                    throw <| .planInvariant .cosmwasm
                      "unsupported CosmWasm semantic shape: Option construct ctorIdx must be 0 (none) or 1 (some)"
            | _ => do
                unless types.isNamedAggregate typeId do
                  throw <| .planInvariant .cosmwasm
                    "unsupported CosmWasm semantic shape: construct admits only Array/Map UInt64, Option UInt64, or named Struct/Enum on CosmWasm"
                let some decl := typeDecls[typeId.toNat]? |
                  throw <| .planInvariant .cosmwasm
                    "unsupported CosmWasm semantic shape: construct TypeDecl missing"
                match decl.shape with
                | .struct fields => do
                    unless ctorIdx.toNat == 0 do
                      throw <| .planInvariant .cosmwasm
                        "unsupported CosmWasm semantic shape: struct construct ctorIdx must be 0"
                    unless argIds.size == fields.size do
                      throw <| .planInvariant .cosmwasm
                        "unsupported CosmWasm semantic shape: struct construct arity mismatch"
                    let mut leaves : Array Expr := #[]
                    let mut deps : Array ValueIdV1 := #[]
                    let mut depth : Nat := 1
                    let mut nodes : Nat := 1
                    for i in [0:argIds.size] do
                      let some argId := argIds[i]? |
                        throw <| .planInvariant .cosmwasm "struct construct arg missing"
                      let some field := fields[i]? |
                        throw <| .planInvariant .cosmwasm "struct construct field missing"
                      let arg ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
                      let expectedLeaves ← leafCountOfTypeV1 typeDecls types field.typeId
                      let argLeaves := arg.leafExprs
                      unless argLeaves.size == expectedLeaves do
                        throw <| .planInvariant .cosmwasm
                          "unsupported CosmWasm semantic shape: struct construct field leaf count mismatch"
                      leaves := leaves ++ argLeaves
                      deps := deps.push argId
                      depth := Nat.max depth (arg.depth + 1)
                      nodes := nodes + arg.expandedNodes
                    let value := mkAggregateValueV1 leaves deps depth nodes
                    values := ← appendResultValueV1 typeId values result value
                | .enum variants => do
                    let vi := ctorIdx.toNat
                    let some variant := variants[vi]? |
                      throw <| .planInvariant .cosmwasm
                        "unsupported CosmWasm semantic shape: enum construct variant out of range"
                    unless argIds.size == variant.payloadTypes.size do
                      throw <| .planInvariant .cosmwasm
                        "unsupported CosmWasm semantic shape: enum construct arity mismatch"
                    let maxPay ← enumMaxPayloadLeavesV1 typeDecls types variants
                    let mut leaves : Array Expr := #[.literal (UInt64.ofNat vi)]
                    let mut deps : Array ValueIdV1 := #[]
                    let mut depth : Nat := 1
                    let mut nodes : Nat := 1
                    for i in [0:argIds.size] do
                      let some argId := argIds[i]? |
                        throw <| .planInvariant .cosmwasm "enum construct arg missing"
                      let some pt := variant.payloadTypes[i]? |
                        throw <| .planInvariant .cosmwasm "enum construct payload type missing"
                      let arg ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
                      let expectedLeaves ← leafCountOfTypeV1 typeDecls types pt
                      let argLeaves := arg.leafExprs
                      unless argLeaves.size == expectedLeaves do
                        throw <| .planInvariant .cosmwasm
                          "unsupported CosmWasm semantic shape: enum construct payload leaf count mismatch"
                      leaves := leaves ++ argLeaves
                      deps := deps.push argId
                      depth := Nat.max depth (arg.depth + 1)
                      nodes := nodes + arg.expandedNodes
                    while leaves.size < 1 + maxPay do
                      leaves := leaves.push (.literal 0)
                    let value := mkAggregateValueV1 leaves deps depth nodes
                    values := ← appendResultValueV1 typeId values result value
                | _ =>
                    throw <| .planInvariant .cosmwasm
                      "unsupported CosmWasm semantic shape: construct requires Struct or Enum shape"
    | .indexGet baseId idxId, some result => do
        let base ← currentValueWithArmsV1 values blockEntry segmentStart armReadables baseId
        unless base.isAggregate do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: IndexGet base must be an Array/Map/Bytes aggregate"
        let idx ← currentValueWithArmsV1 values blockEntry segmentStart armReadables idxId
        if base.leafExprs.size == nearMapPilotLeafCountV1 then
          let optLeaves ← mapLookupOptionLeavesV1 base.leafExprs idx.expr
          let value := mkAggregateValueV1 optLeaves #[baseId, idxId]
            (Nat.max base.depth idx.depth + 1)
            (base.expandedNodes + idx.expandedNodes + 1)
          values := ← appendResultValueV1 result.typeId values result value
        else do
          let i ← literalIndexNatV1 idx
          let leaves := base.leafExprs
          unless i < leaves.size do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: Array/Bytes IndexGet index out of range"
          let some leaf := leaves[i]? |
            throw <| .planInvariant .cosmwasm "Array/Bytes IndexGet leaf missing"
          if base.leafByteWidth == 1 then
            -- Bytes element read → scalar UInt8 (zero-extended i64 temp).
            let u8Tid ← match types.uintTypeIdAt 8 with
              | some t => pure t
              | none => throw (.planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: UInt8 type is missing for Bytes IndexGet")
            unless result.typeId == u8Tid do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: Bytes IndexGet result must be UInt8"
            values := ← appendResultValueV1 result.typeId values result {
              expr := leaf
              kind := .uint8
              depth := base.depth + 1
              expandedNodes := base.expandedNodes + 1
              dependencies := #[baseId, idxId]
            }
          else
            unless result.typeId == types.uint64TypeId do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: Array IndexGet result must be UInt64"
            values := ← appendResultValueV1 result.typeId values result {
              expr := leaf
              kind := .uint64
              depth := base.depth + 1
              expandedNodes := base.expandedNodes + 1
              dependencies := #[baseId, idxId]
            }
    | .indexSet baseId idxId valueId, some result => do
        let base ← currentValueWithArmsV1 values blockEntry segmentStart armReadables baseId
        unless base.isAggregate do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: IndexSet base must be an Array/Map/Bytes aggregate"
        unless types.isContainer result.typeId do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: IndexSet result must be Array/Map container"
        let idx ← currentValueWithArmsV1 values blockEntry segmentStart armReadables idxId
        let val ← currentValueWithArmsV1 values blockEntry segmentStart armReadables valueId
        unless !val.isAggregate do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: IndexSet value must be a scalar UInt8/UInt64"
        if base.leafExprs.size == nearMapPilotLeafCountV1 then
          unless val.kind == .uint64 do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: Map IndexSet value must be scalar UInt64"
          let (outLeaves0, okInsert) ←
            mapUpsertLeavesV1 base.leafExprs idx.expr val.expr
          let gate := Expr.checkedDiv (.literal 1) okInsert
          let mut outLeaves : Array Expr := #[]
          for i in [0:outLeaves0.size] do
            let some e := outLeaves0[i]? |
              throw <| .planInvariant .cosmwasm "Map IndexSet leaf missing after upsert"
            let e' :=
              if i == 0 then
                Expr.checkedAdd e (Expr.checkedMul gate (.literal 0))
              else e
            outLeaves := outLeaves.push e'
          let value := mkAggregateValueV1 outLeaves #[baseId, idxId, valueId]
            (Nat.max (Nat.max base.depth idx.depth) val.depth + 1)
            (base.expandedNodes + idx.expandedNodes + val.expandedNodes + 1)
          values := ← appendResultValueV1 result.typeId values result value
        else do
          let i ← literalIndexNatV1 idx
          let leaves := base.leafExprs
          unless i < leaves.size do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: Array/Bytes IndexSet index out of range"
          if base.leafByteWidth == 1 then
            -- Bytes element write → scalar UInt8; rebuild the aggregate with
            -- the updated leaf so a later store persists it (byte-exact KV).
            unless val.kind == .uint8 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: Bytes IndexSet value must be scalar UInt8"
            let mut outLeaves : Array Expr := #[]
            for j in [0:leaves.size] do
              if j == i then
                outLeaves := outLeaves.push val.expr
              else
                let some e := leaves[j]? |
                  throw <| .planInvariant .cosmwasm "Bytes IndexSet leaf missing"
                outLeaves := outLeaves.push e
            let value := mkAggregateValueV1 outLeaves #[baseId, idxId, valueId]
              (Nat.max base.depth val.depth + 1)
              (base.expandedNodes + val.expandedNodes + 1)
              (leafByteWidth := 1)
            values := ← appendResultValueV1 result.typeId values result value
          else
            unless val.kind == .uint64 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: Array IndexSet value must be scalar UInt64"
            let mut outLeaves : Array Expr := #[]
            for j in [0:leaves.size] do
              if j == i then
                outLeaves := outLeaves.push val.expr
              else
                let some e := leaves[j]? |
                  throw <| .planInvariant .cosmwasm "Array IndexSet leaf missing"
                outLeaves := outLeaves.push e
            let value := mkAggregateValueV1 outLeaves #[baseId, idxId, valueId]
              (Nat.max base.depth val.depth + 1)
              (base.expandedNodes + val.expandedNodes + 1)
            values := ← appendResultValueV1 result.typeId values result value
    | .fieldGet baseId fieldIndex, some result => do
        let base ← currentValueWithArmsV1 values blockEntry segmentStart armReadables baseId
        unless base.isAggregate do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: fieldGet base must be a named aggregate"
        let baseLeaves := base.leafExprs
        let mut hit : Option (Nat × Nat) := none
        for tid in types.namedTypeIds do
          match typeDecls[tid.toNat]? with
          | some { shape := .struct fields, .. } => do
              let total ← leafCountOfTypeV1 typeDecls types tid
              if total == baseLeaves.size && fieldIndex.toNat < fields.size then
                match fields[fieldIndex.toNat]? with
                | some f =>
                    if f.typeId == result.typeId then
                      let (s, l) ←
                        structFieldLeafRangeV1 typeDecls types fields fieldIndex.toNat
                      hit := some (s, l)
                | none => pure ()
          | _ => pure ()
        let (start, len) ← match hit with
          | some r => pure r
          | none =>
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: fieldGet could not resolve struct field range"
        unless start + len <= baseLeaves.size do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: fieldGet leaf range out of bounds"
        let mut outLeaves : Array Expr := #[]
        for i in [start:start+len] do
          let some e := baseLeaves[i]? |
            throw <| .planInvariant .cosmwasm "fieldGet leaf missing"
          outLeaves := outLeaves.push e
        let value ←
          if types.isNamedAggregate result.typeId then
            pure (mkAggregateValueV1 outLeaves #[baseId]
              (base.depth + 1) (base.expandedNodes + 1))
          else
            let some e0 := outLeaves[0]? |
              throw <| .planInvariant .cosmwasm "fieldGet scalar leaf missing"
            let kind ← scalarKindOfNamedLeafResultV1 types result.typeId
            pure {
              expr := e0
              kind
              depth := base.depth + 1
              expandedNodes := base.expandedNodes + 1
              dependencies := #[baseId]
            }
        values := ← appendResultValueV1 result.typeId values result value
    | .fieldSet baseId fieldIndex valueId, some result => do
        let base ← currentValueWithArmsV1 values blockEntry segmentStart armReadables baseId
        let val ← currentValueWithArmsV1 values blockEntry segmentStart armReadables valueId
        unless base.isAggregate do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: fieldSet base must be a named aggregate"
        unless types.isNamedAggregate result.typeId do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: fieldSet result must be named aggregate"
        let baseLeaves := base.leafExprs
        let valLeaves := val.leafExprs
        let mut hit : Option (Nat × Nat) := none
        for tid in types.namedTypeIds do
          if tid == result.typeId then
            match typeDecls[tid.toNat]? with
            | some { shape := .struct fields, .. } => do
                if fieldIndex.toNat < fields.size then
                  let (s, l) ←
                    structFieldLeafRangeV1 typeDecls types fields fieldIndex.toNat
                  hit := some (s, l)
            | _ => pure ()
        let (start, len) ← match hit with
          | some r => pure r
          | none =>
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: fieldSet could not resolve struct field range"
        unless start + len <= baseLeaves.size && valLeaves.size == len do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: fieldSet leaf range/value size mismatch"
        let mut outLeaves : Array Expr := #[]
        for i in [0:baseLeaves.size] do
          if i >= start && i < start + len then
            let j := i - start
            let some e := valLeaves[j]? |
              throw <| .planInvariant .cosmwasm "fieldSet value leaf missing"
            outLeaves := outLeaves.push e
          else
            let some e := baseLeaves[i]? |
              throw <| .planInvariant .cosmwasm "fieldSet base leaf missing"
            outLeaves := outLeaves.push e
        let value := mkAggregateValueV1 outLeaves #[baseId, valueId]
          (Nat.max base.depth val.depth + 1)
          (base.expandedNodes + val.expandedNodes + 1)
        values := ← appendResultValueV1 result.typeId values result value
    | .variantTag baseId, some result => do
        let base ← currentValueWithArmsV1 values blockEntry segmentStart armReadables baseId
        unless base.isAggregate do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: variantTag base must be an aggregate (Enum or Option)"
        let kind ← match types.uintWidthOf result.typeId with
          | some 32 => pure CosmWasmValueKindV1.uint32
          | some 64 => pure CosmWasmValueKindV1.uint64
          | _ =>
              if result.typeId == types.uint64TypeId then pure CosmWasmValueKindV1.uint64
              else
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: variantTag result must be UInt32"
        let some tagExpr := base.leafExprs[0]? |
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: variantTag aggregate has no tag leaf"
        values := ← appendResultValueV1 result.typeId values result {
          expr := tagExpr
          kind
          depth := base.depth + 1
          expandedNodes := base.expandedNodes + 1
          dependencies := #[baseId]
        }
    | .variantPayload baseId variantIndex payloadIndex, some result => do
        let base ← currentValueWithArmsV1 values blockEntry segmentStart armReadables baseId
        unless base.isAggregate do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: variantPayload base must be an aggregate (Enum or Option)"
        let mut hit : Option (Nat × Nat) := none
        for tid in types.namedTypeIds do
          match typeDecls[tid.toNat]? with
          | some { shape := .enum variants, .. } => do
              let total ← leafCountOfTypeV1 typeDecls types tid
              if total == base.leafExprs.size then
                let (s, l) ← enumPayloadLeafRangeV1 typeDecls types variants
                  variantIndex.toNat payloadIndex.toNat
                -- payload region starts after tag (offset +1)
                hit := some (s + 1, l)
          | _ => pure ()
        let (start, len) ← match hit with
          | some r => pure r
          | none =>
              -- Map IndexGet Option intermediate: 2-leaf (tag, payload).
              if variantIndex.toNat == 1 && payloadIndex.toNat == 0 &&
                  base.leafExprs.size == 2 then
                pure (1, 1)
              else if variantIndex.toNat == 0 then
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: variantPayload of Option.none is empty"
              else
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: variantPayload could not resolve range"
        let baseLeaves := base.leafExprs
        unless start + len <= baseLeaves.size do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: variantPayload leaf range out of bounds"
        let mut outLeaves : Array Expr := #[]
        for i in [start:start+len] do
          let some e := baseLeaves[i]? |
            throw <| .planInvariant .cosmwasm "variantPayload leaf missing"
          outLeaves := outLeaves.push e
        let value ←
          if types.isNamedAggregate result.typeId then
            pure (mkAggregateValueV1 outLeaves #[baseId]
              (base.depth + 1) (base.expandedNodes + 1))
          else
            let some e0 := outLeaves[0]? |
              throw <| .planInvariant .cosmwasm "variantPayload scalar leaf missing"
            let kind ←
              if result.typeId == types.uint64TypeId then pure CosmWasmValueKindV1.uint64
              else scalarKindOfNamedLeafResultV1 types result.typeId
            pure {
              expr := e0
              kind
              depth := base.depth + 1
              expandedNodes := base.expandedNodes + 1
              dependencies := #[baseId]
            }
        values := ← appendResultValueV1 result.typeId values result value
    | .envRead key args, some result =>
        -- ADR-0030 E2-4-CW: read-only self-vault observation (value-producing,
        -- view-callable, effect-free). Requires exact extension.pf-assets
        -- (same gate as the catalog QNs). Result must be UInt64.
        unless layout.pfAssetsDeclared do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: pf.assets env-read requires extension.pf-assets declaration"
        unless result.typeId == types.uint64TypeId do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: envRead result must be UInt64"
        -- pureFn/invariant contexts stay fail closed (envRead is a host read,
        -- not a pure expression; invariant closures forbid host reads).
        if mode == .pureFn then
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: pureFn cannot use envRead (host read is not pure)"
        match key with
        | .nativeVaultBalance =>
            -- query_chain bank balance of env.contract.address (frozen denom).
            -- Zero args; value-producing Expr (like blockTimeSeconds).
            unless args.isEmpty do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: nativeVaultBalance takes no arguments"
            values := ← appendResultValueV1 result.typeId values result {
              expr := .nativeVaultBalance
              kind := .uint64
              depth := 1
              expandedNodes := 1
              dependencies := #[]
            }
        | .tokenVaultBalance =>
            -- query_chain CW20 smart-query balanceOf(mint, self).
            -- One Principal arg (the mint); value-producing Statement that
            -- binds a resultTemp (the query needs to assemble a Region with
            -- the mint address embedded, call query_chain, then parse).
            unless args.size == 1 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: tokenVaultBalance takes exactly one Principal argument"
            let some mintId := args[0]? |
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: tokenVaultBalance mint argument missing"
            let mintRoot ← currentValueWithArmsV1 values blockEntry segmentStart
              armReadables mintId
            unless mintRoot.isAggregate do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: tokenVaultBalance mint must be Principal"
            let mintLeaves := mintRoot.leafExprs
            unless mintLeaves.size == 1 + nearPrincipalDataWordCountV1 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: tokenVaultBalance mint Principal leaf count mismatch"
            let some mintLen := mintLeaves[0]? |
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: tokenVaultBalance mint len missing"
            let mintWords := mintLeaves.extract 1 mintLeaves.size
            unless mintWords.size == nearPrincipalDataWordCountV1 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: tokenVaultBalance mint body words mismatch"
            let _ ← consumeSegmentRootsV1 values blockEntry segmentStart args
            let resultTemp := result.valueId.toNat
            body := body.push (.tokenVaultBalance mintLen mintWords resultTemp)
            values := ← appendResultValueV1 result.typeId values result {
              expr := .localTemp resultTemp
              kind := .uint64
              depth := 1
              expandedNodes := 1
              dependencies := #[]
            }
    -- N5: Commit = identity passthrough; ContextRead unix-time admitted (B-CTX-OPEN).
    | .commit valueId, some result => do
        unless pilotContextPolicyCommitIdentity.admitCommitIdentity do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: Commit is not admitted by pilot context policy"
        let operand ← findValueV1 values valueId
        values := ← appendResultValueV1 result.typeId values result {
          expr := operand.expr
          kind := operand.kind
          depth := operand.depth + 1
          expandedNodes := operand.expandedNodes + 1
          dependencies := operand.dependencies.push valueId
          aggregateLeaves := operand.aggregateLeaves
        }
    | .contextRead key, some result =>
        -- B-CTX-OPEN / ADR-0031 S1+S2 (CosmWasm):
        --   * `context.unixTimeSeconds` → Env.block.time.seconds()
        --     (Env JSON `"time"` nanoseconds string ÷ 10^9 truncating).
        --   * `context.blockHeight` → Env.block.height
        --     (Env JSON `"height"` bare u64 decimal; exact UInt64 fit).
        --   * `context.caller` → Principal aggregate
        --     `u32le(len)||sender-utf8` from MessageInfo.sender
        --     (execute/init only; view/query has no sender → Plan FC).
        -- Unknown keys fail closed.
        if key == callerContextKeyV1 then
          -- View-forbidden: CosmWasm query entry has no MessageInfo; do not
          -- forge env.contract.address, empty string, or any fallback.
          if mode == .view then
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: ContextRead context.caller is not available in view/query (MessageInfo.sender absent)"
          if mode == .pureFn then
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: pureFn cannot use ContextRead context.caller"
          unless types.isPrincipal result.typeId do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: ContextRead context.caller result must be Principal"
          -- 9-leaf pilot Principal: len + 8 LE body words.
          let mut leaves : Array Expr := #[.callerPrincipalLen]
          for i in [0:nearPrincipalDataWordCountV1] do
            leaves := leaves.push (.callerPrincipalWord i)
          unless leaves.size == 1 + nearPrincipalDataWordCountV1 do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: context.caller Principal leaf count mismatch"
          let value := mkAggregateValueV1 leaves #[] 1 leaves.size
          values := ← appendResultValueV1 result.typeId values result value
        else if key == unixTimeSecondsContextKeyV1 then
          unless result.typeId == types.uint64TypeId do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: ContextRead unix-time-seconds result must be UInt64"
          values := ← appendResultValueV1 result.typeId values result {
            expr := .blockTimeSeconds
            kind := .uint64
            depth := 1
            expandedNodes := 1
            dependencies := #[]
          }
        else if key == blockHeightContextKeyV1 then
          unless result.typeId == types.uint64TypeId do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: ContextRead context.blockHeight result must be UInt64"
          values := ← appendResultValueV1 result.typeId values result {
            expr := .blockHeight
            kind := .uint64
            depth := 1
            expandedNodes := 1
            dependencies := #[]
          }
        else
          throw <| .planInvariant .cosmwasm
            s!"unsupported CosmWasm semantic shape: unknown ContextRead key '{key.value}'"
    | _, _ =>
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: instruction op/result is outside the current UInt64 pilot"
  pure { statements := body, values, segmentStart, armReadables }

/-- Decode a switch case constant against the scrutinee kind.
    UInt32 covers Option.variantTag from Map IndexGet. -/
private def decodeSwitchCaseValueV1 (scrutIsBool : Bool) (scrutIsUInt32 : Bool)
    (bytes : ByteArray) : CompileResult UInt64 := do
  if scrutIsBool then
    let bit ← decodeBoolLiteralV1 bytes
    pure (if bit then 1 else 0)
  else if scrutIsUInt32 then
    decodeUInt32LiteralV1 bytes
  else
    decodeUInt64LiteralV1 bytes

/-- Region continuation after emitting a block sequence. -/
private inductive RegionContV1 where
  | closed
  | join (blockId : Nat)
  | latch (args : Array ValueIdV1)
  deriving Inhabited

private def findLoopBoundV1 (loopBounds : Array LoopBoundV1) (headerId : Nat) :
    Option LoopBoundV1 :=
  loopBounds.find? (fun lb => lb.header.toNat == headerId)

private def isLoopHeaderV1 (loopBounds : Array LoopBoundV1) (blockId : Nat) : Bool :=
  (findLoopBoundV1 loopBounds blockId).isSome

/-- Validate the Normalize loop envelope: each loopBounds header carries
    exactly one UInt64 block param; every param'd block is a recorded header;
    each latch is a jump back to its header with one arg; degenerate param'd
    blocks without a loopBounds row fail closed. -/
private def validateCallableLoopsV1
    (types : CosmWasmTypeClosureV1) (callable : CallableV1) : CompileResult Nat := do
  let mut blockParamCount : Nat := 0
  for block in callable.blocks do
    if block.params.isEmpty then
      pure ()
    else
      unless block.params.size == 1 do
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: loop header must carry exactly one block param"
      let some p := block.params[0]? |
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: loop header must carry exactly one block param"
      unless p.typeId == types.uint64TypeId do
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: loop induction must be public UInt64"
      unless p.valueId.toNat == callable.params.size + blockParamCount do
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: block parameter ValueIds are not canonical"
      unless isLoopHeaderV1 callable.loopBounds block.id.toNat do
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: block parameters require a loopBounds header entry"
      blockParamCount := blockParamCount + 1
  for lb in callable.loopBounds do
    let some header := callable.blocks[lb.header.toNat]? |
      throw <| .planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: loopBounds header is out of range"
    unless header.params.size == 1 do
      throw <| .planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: loopBounds header must have one block param"
    let some latch := callable.blocks[lb.backEdgeFrom.toNat]? |
      throw <| .planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: loopBounds backEdgeFrom is out of range"
    match latch.terminator with
    | .jump target =>
        unless target.blockId == lb.header && target.args.size == 1 do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: loop latch must jump to its header with one arg"
    | _ =>
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: loop latch terminator must be a jump"
    unless lb.maxIterations.toNat ≤ 4096 do
      throw <| .planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: loop maxIterations exceeds the wire ceiling"
  pure blockParamCount

/-- Structured emission of multi-block CFGs: forward diamonds (branch/switch)
    and Normalize loop headers (loopBounds + single induction param). Fuel
    bounds recursion to the block count. `enclosingHeader` is set while walking
    a loop body so a jump back to that header ends the body as a latch.
    Returns (statements, values, nextLocal, continuation). -/
private partial def emitRegionV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (expectedReturn : Option CosmWasmValueKindV1)
    (expectedAggregateLeaves : Option (Array LeafAbiType))
    (types : CosmWasmTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (layout : StorageLayout)
    (fnEnv : CosmWasmFnEnvV1)
    (blocks : Array BlockV1)
    (loopBounds : Array LoopBoundV1)
    (stableCount : Nat)
    (nextLocal0 : Nat)
    (enclosingHeader : Option Nat)
    (armReadables : Array ValueIdV1)
    (fuel : Nat)
    (start : Nat)
    (values0 : Array LoweredValueV1) :
    CompileResult (Array Statement × Array LoweredValueV1 × Nat × RegionContV1) := do
  if fuel == 0 then
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: CFG region exceeds block bound"
  let block ← match blocks[start]? with
    | some value => pure value
    | none => throw (.planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: region references a missing block")
  unless block.id.toNat == start do
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: block ids are not dense"
  -- Starting emission at a loop header is only valid when the induction slot
  -- was already materialised (nested entry is via the jump-to-header path).
  if isLoopHeaderV1 loopBounds start then
    let some p := block.params[0]? |
      throw <| .planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: loop header missing induction param"
    let some slot := values0[p.valueId.toNat]? |
      throw <| .planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: loop header must be entered via its pre-header jump"
    match slot.expr with
    | .localTemp _ => pure ()
    | _ =>
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: loop header must be entered via its pre-header jump"
  let lowered ← lowerBlockInstructionsV1
    owner mode types typeDecls layout fnEnv stableCount armReadables block values0
  let instrs := lowered.statements
  let values := lowered.values
  let segmentStart := lowered.segmentStart
  let freeAfter := lowered.armReadables
  let blockEntry := values0.size
  match block.terminator with
  | .return_ (some valueId) =>
      match mode with
      | .initialize =>
          throw <| .planInvariant .cosmwasm "initializer cannot return a value"
      | .mutate | .view | .pureFn =>
          let root ← currentValueWithArmsV1 values blockEntry segmentStart freeAfter valueId
          match expectedAggregateLeaves with
          | some expectedLeaves =>
              -- B-RET-ABI: named Struct/Enum or admitted anonymous Array/Option.
              -- pureFn aggregate returns stay fail closed (makePureFn never
              -- sets expectedAggregateLeaves; guard here for safety).
              if mode == .pureFn then
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: pureFn cannot return aggregate (B-RET-ABI)"
              unless root.isAggregate do
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: aggregate return value must be a multi-leaf aggregate"
              let gotLeaves := root.leafExprs
              unless gotLeaves.size == expectedLeaves.size do
                throw <| .planInvariant .cosmwasm
                  s!"unsupported CosmWasm semantic shape: aggregate return leaf count mismatch (expected {expectedLeaves.size}, got {gotLeaves.size})"
              unless root.leafByteWidth == 8 do
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: multi-leaf return requires 8-byte leaves (Bytes/narrow container returns stay fail closed)"
              let consumed ← consumeCurrentSegmentValueV1 values blockEntry segmentStart valueId
              let leafIsInt := expectedLeaves.map (·.isInt)
              pure (instrs.push (.returnAggregate consumed.leafExprs leafIsInt),
                values, nextLocal0, .closed)
          | none =>
              let expectedKind ← match expectedReturn with
                | some kind => pure kind
                | none =>
                    throw <| .planInvariant .cosmwasm
                      "unsupported CosmWasm semantic shape: entry/view/pureFn is missing expected return kind"
              if root.isAggregate then
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: multi-leaf aggregate cannot be returned as scalar (B-RET-ABI: named Struct/Enum or admitted anonymous Array/Option only)"
              unless root.kind == expectedKind do
                let expectedLabel :=
                  match expectedKind with
                  | .uint64 => "UInt64"
                  | .uint32 => "UInt32"
                  | .uint16 => "UInt16"
                  | .uint8 => "UInt8"
                  | .uint128 => "UInt128"
                  | .uint256 => "UInt256"
                  | .bool => "Bool"
                  | .int64 => "Int64"
                throw <| .planInvariant .cosmwasm
                  s!"unsupported CosmWasm semantic shape: return value must be {expectedLabel}"
              let value ← consumeCurrentSegmentV1 values blockEntry segmentStart valueId
              pure (instrs.push (.returnValue value), values, nextLocal0, .closed)
  | .return_ none =>
      unless expectedReturn.isNone do
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: initializer expected-return kind is non-empty"
      unless segmentStart == values.size do
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: block has unconsumed values"
      -- Explicit marker: an early bare `return` inside a branch arm is
      -- otherwise indistinguishable from a fallthrough arm once the join
      -- continuation is emitted after the region.
      pure (instrs.push .returnNone, values, nextLocal0, .closed)
  | .jump target =>
      let targetId := target.blockId.toNat
      -- Latch: jump back to the loop currently being lowered as a body.
      if enclosingHeader == some targetId then
        unless target.args.size == 1 do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: loop latch must carry exactly one induction arg"
        -- Latch args may reference the just-produced increment; do not require
        -- the segment to be empty — the update expr is recovered from args.
        let _ ← currentValueWithArmsV1 values blockEntry segmentStart freeAfter target.args[0]!
        pure (instrs, values, nextLocal0, .latch target.args)
      else if isLoopHeaderV1 loopBounds targetId then
        -- Enter a (possibly nested) bounded for-loop.
        let some lb := findLoopBoundV1 loopBounds targetId |
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: missing loopBounds for loop header"
        unless target.args.size == 1 do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: loop pre-header must jump with one start arg"
        let initRoot ←
          currentValueWithArmsV1 values blockEntry segmentStart freeAfter target.args[0]!
        unless initRoot.kind == .uint64 do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: loop start value must be UInt64"
        let initial := initRoot.expr
        -- Freeze every value produced so far (params, block-param slots,
        -- pre-header lets/arithmetic) as loop-stable for the header/body.
        let loopStable := values.size
        let some header := blocks[targetId]? |
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: loop header block is missing"
        unless header.params.size == 1 do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: loop header must carry exactly one block param"
        let some inductionParam := header.params[0]? |
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: loop header must carry exactly one block param"
        let inductionVid := inductionParam.valueId
        unless inductionVid.toNat < values.size do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: induction ValueId slot was not pre-allocated"
        let varTemp := nextLocal0
        let nextLocal1 := nextLocal0 + 1
        let inductionSlot : LoweredValueV1 := {
          expr := .localTemp varTemp
          kind := .uint64
          depth := 1
          expandedNodes := 1
          dependencies := #[]
        }
        let mut valuesH := values.set! inductionVid.toNat inductionSlot
        let freeH := freeAfter
        let headerBlockEntry := valuesH.size
        let loweredH ← lowerBlockInstructionsV1
          owner mode types typeDecls layout fnEnv loopStable freeH header valuesH
        valuesH := loweredH.values
        let headerSeg := loweredH.segmentStart
        let freeHeader := loweredH.armReadables
        unless loweredH.statements.isEmpty do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: loop header may not contain effect instructions"
        let loopResult ← match header.terminator with
          | .branch condId thenT elseT => do
              let condRoot ←
                currentValueWithArmsV1 valuesH headerBlockEntry headerSeg freeHeader condId
              unless condRoot.kind == .bool do
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: loop condition must be Bool"
              let cond ← consumeCurrentSegmentV1 valuesH headerBlockEntry headerSeg condId
              unless thenT.args.isEmpty && elseT.args.isEmpty do
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: loop branch targets must carry empty args"
              -- Body region ends at the latch (jump back to this header).
              let (bodyStmts, valuesB, nextLocal2, bodyCont) ←
                emitRegionV1 owner mode expectedReturn expectedAggregateLeaves types typeDecls layout fnEnv blocks loopBounds
                  loopStable nextLocal1 (some targetId) freeHeader (fuel - 1)
                  thenT.blockId.toNat valuesH
              let updateArgs ← match bodyCont with
                | .latch args => pure args
                | .closed =>
                    throw <| .planInvariant .cosmwasm
                      "unsupported CosmWasm semantic shape: loop body closed without a latch (degenerate one-shot loops are out of pilot)"
                | .join _ =>
                    throw <| .planInvariant .cosmwasm
                      "unsupported CosmWasm semantic shape: loop body must end at its latch jump"
              unless updateArgs.size == 1 do
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: loop latch must carry exactly one update arg"
              -- Re-derive the update expr from the already-lowered value table
              -- (latch increment is left in valuesB by the body walk).
              let updateRoot ← findValueV1 valuesB updateArgs[0]!
              unless updateRoot.kind == .uint64 do
                throw <| .planInvariant .cosmwasm
                  "unsupported CosmWasm semantic shape: loop update must be UInt64"
              let update := updateRoot.expr
              let forStmt : Statement :=
                .forLoop varTemp initial cond update lb.maxIterations.toNat bodyStmts
              -- Continue the enclosing walk at the exit (else target).
              let (rest, valuesE, nextLocal3, exitCont) ←
                emitRegionV1 owner mode expectedReturn expectedAggregateLeaves types typeDecls layout fnEnv blocks loopBounds
                  loopStable nextLocal2 enclosingHeader freeHeader (fuel - 1)
                  elseT.blockId.toNat valuesB
              pure (instrs ++ #[forStmt] ++ rest, valuesE, nextLocal3, exitCont)
          | _ =>
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: loop header terminator must be a branch"
        pure loopResult
      else
        -- Forward join: no phi / block args in the non-loop pilot.
        unless target.args.isEmpty do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: non-loop jump targets must carry empty args"
        unless segmentStart == values.size do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: block has unconsumed values"
        pure (instrs, values, nextLocal0, .join targetId)
  | .branch condId thenT elseT =>
      let condRoot ← currentValueWithArmsV1 values blockEntry segmentStart freeAfter condId
      unless condRoot.kind == .bool do
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: branch condition must be Bool"
      let cond ← consumeCurrentSegmentV1 values blockEntry segmentStart condId
      let (thenBody, values1, nextLocal1, thenNext) ←
        emitRegionV1 owner mode expectedReturn expectedAggregateLeaves types typeDecls layout fnEnv blocks loopBounds
          stableCount nextLocal0 enclosingHeader freeAfter (fuel - 1)
          thenT.blockId.toNat values
      -- A latch may only arise on the then-arm of a loop header (handled
      -- above); diamond arms must not latch.
      let thenJoin ← match thenNext with
        | .latch _ =>
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: loop latch outside loop-body walk"
        | .closed => pure (none : Option Nat)
        | .join j => pure (some j)
      match thenJoin with
      | some j =>
          if elseT.blockId.toNat == j then
            let (rest, values2, nextLocal2, next) ←
              emitRegionV1 owner mode expectedReturn expectedAggregateLeaves types typeDecls layout fnEnv blocks loopBounds
                stableCount nextLocal1 enclosingHeader freeAfter (fuel - 1) j values1
            pure (instrs ++ #[.ifThenElse cond thenBody #[]] ++ rest, values2, nextLocal2, next)
          else
            let (elseBody, values2, nextLocal2, elseNext) ←
              emitRegionV1 owner mode expectedReturn expectedAggregateLeaves types typeDecls layout fnEnv blocks loopBounds
                stableCount nextLocal1 enclosingHeader freeAfter (fuel - 1)
                elseT.blockId.toNat values1
            let elseJoin ← match elseNext with
              | .latch _ =>
                  throw <| .planInvariant .cosmwasm
                    "unsupported CosmWasm semantic shape: loop latch outside loop-body walk"
              | .closed => pure (none : Option Nat)
              | .join j2 => pure (some j2)
            match elseJoin with
            | some j2 =>
                unless j == j2 do
                  throw <| .planInvariant .cosmwasm
                    "unsupported CosmWasm semantic shape: branch arms converge on divergent joins"
                let (rest, values3, nextLocal3, next) ←
                  emitRegionV1 owner mode expectedReturn expectedAggregateLeaves types typeDecls layout fnEnv blocks loopBounds
                    stableCount nextLocal2 enclosingHeader freeAfter (fuel - 1) j values2
                pure (instrs ++ #[.ifThenElse cond thenBody elseBody] ++ rest,
                  values3, nextLocal3, next)
            | none =>
                let (rest, values3, nextLocal3, next) ←
                  emitRegionV1 owner mode expectedReturn expectedAggregateLeaves types typeDecls layout fnEnv blocks loopBounds
                    stableCount nextLocal2 enclosingHeader freeAfter (fuel - 1) j values2
                pure (instrs ++ #[.ifThenElse cond thenBody elseBody] ++ rest,
                  values3, nextLocal3, next)
      | none =>
          let (elseBody, values2, nextLocal2, elseNext) ←
            emitRegionV1 owner mode expectedReturn expectedAggregateLeaves types typeDecls layout fnEnv blocks loopBounds
              stableCount nextLocal1 enclosingHeader freeAfter (fuel - 1)
              elseT.blockId.toNat values1
          match elseNext with
          | .latch _ =>
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: loop latch outside loop-body walk"
          | .closed =>
              pure (instrs ++ #[.ifThenElse cond thenBody elseBody], values2, nextLocal2, .closed)
          | .join j =>
              pure (instrs ++ #[.ifThenElse cond thenBody elseBody], values2, nextLocal2, .join j)
  | .switch scrutId cases defaultTarget =>
      let scrutVal ← currentValueWithArmsV1 values blockEntry segmentStart freeAfter scrutId
      let scrut ← consumeCurrentSegmentV1 values blockEntry segmentStart scrutId
      let some defaultT := defaultTarget |
        throw (.planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: switch must carry a default target")
      let scrutIsBool := scrutVal.kind == .bool
      let scrutIsUInt32 := scrutVal.kind == .uint32
      let armFree := extendArmReadablesV1 values freeAfter scrutId
      let mut caseBodies : Array (UInt64 × Array Statement) := #[]
      let mut joinAcc : Option Nat := none
      let mut valuesA := values
      let mut nextLocalA := nextLocal0
      for switchCase in cases do
        let caseValue ← decodeSwitchCaseValueV1 scrutIsBool scrutIsUInt32 switchCase.valueBytes
        let (body, values1, nextLocal1, armNext) ←
          emitRegionV1 owner mode expectedReturn expectedAggregateLeaves types typeDecls layout fnEnv blocks loopBounds
            stableCount nextLocalA enclosingHeader armFree (fuel - 1)
            switchCase.target.blockId.toNat valuesA
        caseBodies := caseBodies.push (caseValue, body)
        valuesA := values1
        nextLocalA := nextLocal1
        match armNext, joinAcc with
        | .closed, _ => pure ()
        | .latch _, _ =>
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: loop latch outside loop-body walk"
        | .join j, none => joinAcc := some j
        | .join j, some j0 =>
            unless j == j0 do
              throw <| .planInvariant .cosmwasm
                "unsupported CosmWasm semantic shape: switch arms converge on divergent joins"
      let (defaultBody, values2, nextLocal2, defaultNext) ←
        emitRegionV1 owner mode expectedReturn expectedAggregateLeaves types typeDecls layout fnEnv blocks loopBounds
          stableCount nextLocalA enclosingHeader armFree (fuel - 1)
          defaultT.blockId.toNat valuesA
      match defaultNext, joinAcc with
      | .closed, _ => pure ()
      | .latch _, _ =>
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: loop latch outside loop-body walk"
      | .join j, none => joinAcc := some j
      | .join j, some j0 =>
          unless j == j0 do
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: switch arms converge on divergent joins"
      match joinAcc with
      | none =>
          pure (instrs ++ #[.switchOn scrut caseBodies defaultBody], values2, nextLocal2, .closed)
      | some j =>
          let (rest, values3, nextLocal3, next) ←
            emitRegionV1 owner mode expectedReturn expectedAggregateLeaves types typeDecls layout fnEnv blocks loopBounds
              stableCount nextLocal2 enclosingHeader freeAfter (fuel - 1) j values2
          pure (instrs ++ #[.switchOn scrut caseBodies defaultBody] ++ rest,
            values3, nextLocal3, next)
  | .revert errorId argIds =>
      let mut argExprs : Array Expr := #[]
      for argId in argIds do
        let root ← currentValueWithArmsV1 values blockEntry segmentStart freeAfter argId
        unless root.kind == .uint64 do
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: revert arguments must be UInt64"
        argExprs := argExprs.push root.expr
      let _ ← consumeSegmentRootsV1 values blockEntry segmentStart argIds
      pure (instrs.push (.revertError errorId.toNat argExprs), values, nextLocal0, .closed)
  | .trap _ =>
      throw <| .planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: trap terminators are outside the current pilot"

private def lowerCallableV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (expectedReturn : Option CosmWasmValueKindV1)
    (expectedAggregateLeaves : Option (Array LeafAbiType))
    (types : CosmWasmTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (layout : StorageLayout)
    (fnEnv : CosmWasmFnEnvV1)
    (callable : CallableV1) : CompileResult LoweredCallableV1 := do
  unless callable.entryBlock.toNat == 0 && !callable.blocks.isEmpty &&
      callable.invariantSteps.isNone do
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: callable must start at dense entry block 0"
  let blockParamCount ← validateCallableLoopsV1 types callable
  let (params, initialValues) ← makeParamsV1 owner types typeDecls callable.params
  -- Pre-allocate dense ValueId slots for every loop induction (canonical
  -- order: callable params < all block params < instruction results).
  let mut valuesInit := initialValues
  for _ in [0:blockParamCount] do
    valuesInit := valuesInit.push {
      expr := .literal 0
      kind := .uint64
      depth := 1
      expandedNodes := 1
      dependencies := #[]
    }
  let stableCount0 := valuesInit.size
  let (body0, values0, _nextLocal0, cont0) ←
    emitRegionV1 owner mode expectedReturn expectedAggregateLeaves types typeDecls layout fnEnv callable.blocks
      callable.loopBounds stableCount0 0 none #[] callable.blocks.size 0 valuesInit
  -- Fold trailing join continuations (an arm that returned early leaves the
  -- remaining open path's join to the caller). Join targets strictly increase
  -- in the forward-only CFG, so this terminates within blocks.size folds.
  let mut body := body0
  let mut values := values0
  let mut nextLocal := _nextLocal0
  let mut cont := cont0
  for _ in [0:callable.blocks.size] do
    match cont with
    | .closed => break
    | .latch _ =>
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: loop latch escaped its body walk"
    | .join j =>
        let (rest, values1, nextLocal1, next1) ←
          emitRegionV1 owner mode expectedReturn expectedAggregateLeaves types typeDecls layout fnEnv callable.blocks
            callable.loopBounds stableCount0 nextLocal none #[]
            callable.blocks.size j values
        body := body ++ rest
        values := values1
        nextLocal := nextLocal1
        cont := next1
  match cont with
  | .closed => pure ()
  | _ =>
      throw <| .planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: callable does not end in return on all paths"
  if body.size > maxBodyStatements then
    throw <| .planInvariant .cosmwasm s!"{owner} body exceeds profile limit {maxBodyStatements}"
  pure { params, body }

private def makeInitializerV1
    (types : CosmWasmTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (layout : StorageLayout)
    (fnEnv : CosmWasmFnEnvV1)
    (callable : CallableV1) : CompileResult Method := do
  unless callable.name.isNone && callable.result.visibility == .public_ do
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: initializer signature is invalid"
  let unitTypeId ← match types.unitTypeId with
    | some value => pure value
    | none => throw (.planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: initializer Unit type is missing")
  unless callable.result.typeId == unitTypeId do
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: initializer result is not Unit"
  let lowered ←
    lowerCallableV1 "initializer" .initialize none none types typeDecls layout fnEnv callable
  pure {
    name := "init"
    params := lowered.params
    exactInputLen := exactInputLenOfParams lowered.params
    mode := .initialize
    depositPolicy := .requireZero
    resultKind := .unit
    body := lowered.body
  }

/-- Count of `nativeDeposit` statements in a body tree (must be 0 or 1). -/
partial def statementsNativeDepositCountV1 (statements : Array Statement) : Nat :=
  statements.foldl (init := 0) fun acc statement =>
    match statement with
    | .nativeDeposit _ => acc + 1
    | .ifThenElse _ thenBody elseBody =>
        acc + statementsNativeDepositCountV1 thenBody +
          statementsNativeDepositCountV1 elseBody
    | .switchOn _ cases defaultBody =>
        acc + statementsNativeDepositCountV1 defaultBody +
          cases.foldl (init := 0) fun a (_, caseBody) =>
            a + statementsNativeDepositCountV1 caseBody
    | .forLoop _ _ _ _ _ body => acc + statementsNativeDepositCountV1 body
    | _ => acc

private def makeEntryV1
    (types : CosmWasmTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (layout : StorageLayout)
    (fnEnv : CosmWasmFnEnvV1)
    (callable : CallableV1) : CompileResult Method := do
  let name ← match callable.name with
    | some value => pure value
    | none => throw (.planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: named entry is missing its name")
  unless isIdentifier name do
    throw <| .planInvariant .cosmwasm s!"entry name '{name}' is not a safe identifier"
  unless callable.result.visibility == .public_ do
    throw <| .planInvariant .cosmwasm s!"entry '{name}' does not return a public result"
  -- BL-15: scalar ABI is UInt{8,16,32,64} / Bool / Int64; B-RET-ABI admits named
  -- Struct/Enum and anonymous Array UInt64 N / Option UInt64 (≤8 leaves).
  -- Map/Bytes/nested/narrow-element anonymous returns, UInt128/256, narrow Int
  -- stay FC. JSON result wire remains decimal for all scalar UInt; multi-leaf
  -- reuses the JSON-array-of-decimals idiom (BL-9 / N-ANON-RESULT).
  let (resultKind, expectedReturn, expectedAggregateLeaves) ←
    if isAggregateResultCandidateV1 typeDecls types callable.result.typeId then
      let kind ← aggregateResultKindOfV1 typeDecls types s!"entry '{name}'"
        callable.result.typeId
      match kind with
      | .aggregate leaves => pure (kind, none, some leaves)
      | _ =>
          throw <| .planInvariant .cosmwasm
            s!"entry '{name}' aggregate result kind resolution failed"
    else
      match types.uintWidthOf callable.result.typeId with
      | some 8 => pure (MethodResultKind.uint8, some CosmWasmValueKindV1.uint8, none)
      | some 16 => pure (MethodResultKind.uint16, some CosmWasmValueKindV1.uint16, none)
      | some 32 => pure (MethodResultKind.uint32, some CosmWasmValueKindV1.uint32, none)
      | some 64 => pure (MethodResultKind.uint64, some CosmWasmValueKindV1.uint64, none)
      | some w =>
          throw <| .planInvariant .cosmwasm
            s!"entry '{name}' does not return public UInt8/16/32/64 (UInt{w} multi-width fail closed on CosmWasm)"
      | none =>
          match types.intWidthOf callable.result.typeId with
          | some 64 => pure (MethodResultKind.int64, some CosmWasmValueKindV1.int64, none)
          | some w =>
              throw <| .planInvariant .cosmwasm
                s!"entry '{name}' does not return public Int64 (Int{w} multi-width fail closed on CosmWasm)"
          | none =>
            if types.boolTypeId == some callable.result.typeId then
              pure (MethodResultKind.bool, some CosmWasmValueKindV1.bool, none)
            else
              throw <| .planInvariant .cosmwasm
                s!"entry '{name}' does not return public UInt8/16/32/64, Int64, Bool, named Struct/Enum, or admitted anonymous Array/Option"
  let semanticMode : SemanticCallableModeV1 ← match callable.kind with
    | .entry => pure .mutate
    | .view => pure .view
    | _ => throw (.planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: callable is not an entry or view")
  let mode : MethodMode := match semanticMode with
    | .mutate => .mutate
    | .view => .view
    | .initialize => .initialize
    | .pureFn => .mutate
  let lowered ←
    lowerCallableV1 s!"entry '{name}'" semanticMode expectedReturn expectedAggregateLeaves
      types typeDecls layout fnEnv callable
  let depositCount := statementsNativeDepositCountV1 lowered.body
  unless depositCount ≤ 1 do
    throw <| .planInvariant .cosmwasm
      s!"entry '{name}' may contain at most one pf.assets.native.deposit (got {depositCount})"
  if depositCount == 1 && mode == .view then
    throw <| .planInvariant .cosmwasm
      s!"view entry '{name}' cannot contain pf.assets.native.deposit"
  let depositPolicy : DepositPolicy :=
    if mode == .view then .queryOnly
    else if depositCount == 1 then .requireExactNative
    else .requireZero
  pure {
    name
    params := lowered.params
    exactInputLen := exactInputLenOfParams lowered.params
    mode
    depositPolicy
    resultKind
    body := lowered.body
  }

private def makePureFnV1
    (types : CosmWasmTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (layout : StorageLayout)
    (fnEnv : CosmWasmFnEnvV1)
    (callable : CallableV1) : CompileResult FnBinding := do
  let name ← match callable.name with
    | some value => pure value
    | none => throw (.planInvariant .cosmwasm
        "unsupported CosmWasm semantic shape: pureFn is missing its name")
  unless isIdentifier name do
    throw <| .planInvariant .cosmwasm s!"pureFn name '{name}' is not a safe identifier"
  unless callable.result.visibility == .public_ do
    throw <| .planInvariant .cosmwasm s!"pureFn '{name}' does not return a public result"
  let (resultIsBool, expectedReturn) ←
    if callable.result.typeId == types.uint64TypeId then
      pure (false, CosmWasmValueKindV1.uint64)
    else if types.boolTypeId == some callable.result.typeId then
      pure (true, CosmWasmValueKindV1.bool)
    else if isAggregateResultCandidateV1 typeDecls types callable.result.typeId then
      throw <| .planInvariant .cosmwasm
        s!"pureFn '{name}' cannot return aggregate (B-RET-ABI: pureFn aggregate returns stay fail closed)"
    else
      throw <| .planInvariant .cosmwasm
        s!"pureFn '{name}' does not return public UInt64 or Bool"
  let lowered ←
    lowerCallableV1 s!"pureFn '{name}'" .pureFn (some expectedReturn) none types typeDecls layout fnEnv
      callable
  pure {
    name
    params := lowered.params
    resultIsBool
    body := lowered.body
  }

/-- UInt64-compatible plan expression (comparison / boolNot / boolAnd / boolOr /
    Bool callFn results are not; shift/bitwise trees are). -/
partial def statementsUsePromiseV1 (statements : Array Statement) : Bool :=
  statements.any fun statement =>
    match statement with
    | .promiseAccount .. => true
    | .ifThenElse _ thenBody elseBody =>
        statementsUsePromiseV1 thenBody || statementsUsePromiseV1 elseBody
    | .switchOn _ cases defaultBody =>
        statementsUsePromiseV1 defaultBody ||
          cases.any fun (_, caseBody) => statementsUsePromiseV1 caseBody
    | .forLoop _ _ _ _ _ body => statementsUsePromiseV1 body
    | .store _ | .storeAtomic _ | .returnValue _ | .returnAggregate .. | .returnNone
    | .assert _ | .emitEvent .. | .revertError ..
    | .nativeDeposit _ | .nativeTransfer .. | .tokenTransfer ..
    | .tokenVaultBalance .. => false

def planUsesPromiseV1 (plan : Plan) : Bool :=
  statementsUsePromiseV1 plan.initializer.body ||
    plan.entries.any (fun m => statementsUsePromiseV1 m.body) ||
    plan.fns.any (fun f => statementsUsePromiseV1 f.body)

/-- ADR-0031 S1 follow-up: does an expression tree read `context.caller`
    Principal leaves (`callerPrincipalLen` / `callerPrincipalWord`)?
    Conservative structural scan; drives per-method MessageInfo.sender load
    so programs/entries that never touch caller are not bound to sender
    1..64 / bech32-charset restrictions. Bounded by Plan expr/statement depth
    (already gated by resource limits). -/
partial def exprUsesCallerPrincipalV1 (expr : Expr) : Bool :=
  match expr with
  | .callerPrincipalLen | .callerPrincipalWord _ => true
  | .literal _ | .bigLiteral _ _ | .param _ | .narrowParam _ _
  | .stateLoad _ | .narrowStateLoad _ _ | .localTemp _
  | .blockTimeSeconds | .blockHeight | .nativeVaultBalance => false
  | .checkedAdd l r | .checkedSub l r | .checkedMul l r | .checkedDiv l r
  | .checkedMod l r | .bitAnd l r | .bitOr l r | .bitXor l r | .shl l r
  | .shr l r | .signedCheckedAdd l r | .signedCheckedSub l r
  | .signedCheckedMul l r | .signedCheckedDiv l r | .signedCheckedMod l r
  | .signedCompare _ l r | .sar l r | .boolAnd l r | .boolOr l r
  | .compare _ l r | .wideCompare _ _ l r | .narrowCheckedAdd _ l r
  | .narrowCheckedSub _ l r | .narrowCheckedMul _ l r | .narrowCheckedDiv _ l r
  | .narrowCheckedMod _ l r | .narrowBitAnd _ l r | .narrowBitOr _ l r
  | .narrowBitXor _ l r | .narrowShl _ l r | .narrowShr _ l r =>
      exprUsesCallerPrincipalV1 l || exprUsesCallerPrincipalV1 r
  | .checkedNeg e | .bitNot e | .narrowBitNot _ e | .boolNot e =>
      exprUsesCallerPrincipalV1 e
  | .callFn _ args => args.any exprUsesCallerPrincipalV1

/-- Recursive statement-tree scan for `context.caller` Principal leaves. -/
partial def statementsUseCallerPrincipalV1 (statements : Array Statement) : Bool :=
  statements.any fun statement =>
    match statement with
    | .store op => exprUsesCallerPrincipalV1 op.value
    | .storeAtomic leaves =>
        leaves.any fun leaf => exprUsesCallerPrincipalV1 leaf.value
    | .returnValue value => exprUsesCallerPrincipalV1 value
    | .returnAggregate leaves _ => leaves.any exprUsesCallerPrincipalV1
    | .assert condition => exprUsesCallerPrincipalV1 condition
    | .emitEvent _ args => args.any exprUsesCallerPrincipalV1
    | .revertError _ args => args.any exprUsesCallerPrincipalV1
    | .promiseAccount _ _ args => args.any exprUsesCallerPrincipalV1
    | .nativeDeposit amount => exprUsesCallerPrincipalV1 amount
    | .nativeTransfer dstLen dstWords amount =>
        exprUsesCallerPrincipalV1 dstLen ||
          dstWords.any exprUsesCallerPrincipalV1 ||
          exprUsesCallerPrincipalV1 amount
    | .tokenTransfer mintLen mintWords dstLen dstWords amount =>
        exprUsesCallerPrincipalV1 mintLen ||
          mintWords.any exprUsesCallerPrincipalV1 ||
          exprUsesCallerPrincipalV1 dstLen ||
          dstWords.any exprUsesCallerPrincipalV1 ||
          exprUsesCallerPrincipalV1 amount
    | .tokenVaultBalance mintLen mintWords _ =>
        exprUsesCallerPrincipalV1 mintLen ||
          mintWords.any exprUsesCallerPrincipalV1
    | .ifThenElse condition thenBody elseBody =>
        exprUsesCallerPrincipalV1 condition ||
          statementsUseCallerPrincipalV1 thenBody ||
          statementsUseCallerPrincipalV1 elseBody
    | .switchOn scrutinee cases defaultBody =>
        exprUsesCallerPrincipalV1 scrutinee ||
          statementsUseCallerPrincipalV1 defaultBody ||
          cases.any fun (_, caseBody) => statementsUseCallerPrincipalV1 caseBody
    | .forLoop _ initial cond update _ body =>
        exprUsesCallerPrincipalV1 initial || exprUsesCallerPrincipalV1 cond ||
          exprUsesCallerPrincipalV1 update || statementsUseCallerPrincipalV1 body
    | .returnNone => false

/-- True when a Plan method body (init/entry) reads `context.caller`.
    View bodies that reach this predicate are already Plan-FC on caller. -/
def methodUsesCallerPrincipalV1 (method : Method) : Bool :=
  statementsUseCallerPrincipalV1 method.body

private def makeInterfaceBindingV1 (label : String) (name : String)
    (fields : Array InterfaceFieldV1) (uint64TypeId : TypeIdV1) :
    CompileResult InterfaceBinding := do
  unless isIdentifier name do
    throw <| .planInvariant .cosmwasm
      s!"unsupported CosmWasm semantic shape: {label} name '{name}' is not a safe identifier"
  for field in fields do
    unless field.typeId == uint64TypeId && field.visibility == .public_ do
      throw <| .planInvariant .cosmwasm
        s!"unsupported CosmWasm semantic shape: {label} '{name}' fields must be public UInt64"
  pure { name, fieldCount := fields.size }

/-- Build the pureFn index environment from the unified callable table without
    lowering bodies (signatures only). -/
private def buildCosmWasmFnEnvV1
    (types : CosmWasmTypeClosureV1)
    (callables : Array CallableV1) : CompileResult CosmWasmFnEnvV1 := do
  let mut byCallable : Array (Option Nat) := Array.replicate callables.size none
  let mut sigs : Array CosmWasmFnSigV1 := #[]
  for callable in callables do
    match callable.kind with
    | .pureFn =>
        let resultKind ←
          if callable.result.typeId == types.uint64TypeId then
            pure CosmWasmValueKindV1.uint64
          else if types.int64TypeId == some callable.result.typeId then
            pure CosmWasmValueKindV1.int64
          else if types.boolTypeId == some callable.result.typeId then
            pure CosmWasmValueKindV1.bool
          else
            throw <| .planInvariant .cosmwasm
              "unsupported CosmWasm semantic shape: pureFn result is not UInt64, Int64, or Bool"
        let fnIndex := sigs.size
        if callable.id.toNat < byCallable.size then
          byCallable := byCallable.set! callable.id.toNat (some fnIndex)
        else
          throw <| .planInvariant .cosmwasm
            "unsupported CosmWasm semantic shape: pureFn CallableId is out of range"
        sigs := sigs.push { paramCount := callable.params.size, resultKind }
    | _ => pure ()
  pure { byCallable, sigs }

/-- CosmWasm-private retained SemanticProgramV1 data → target-owned Plan pilot. -/

private def makePlanFromSemanticDataV1
    (source : SemanticProgramDataV1) : CompileResult Plan := do
  if !source.constants.isEmpty || !source.invariants.isEmpty then
    throw <| .planInvariant .cosmwasm
      "unsupported CosmWasm semantic shape: constants/invariants are outside the current UInt64 pilot"
  -- init + entries + pureFns share the profile budget (maxEntries each class,
  -- plus one initializer); total still fails closed above 2·maxEntries + 1.
  if source.callables.size > maxEntries + maxEntries + 1 then
    throw <| .planInvariant .cosmwasm
      s!"callable count exceeds CosmWasm profile limit {maxEntries + maxEntries + 1}"
  if source.requirements.items.size > Targets.maxRequirementKinds then
    throw <| .planInvariant .cosmwasm
      s!"requirement count exceeds canonical limit {Targets.maxRequirementKinds}"
  let types ← validateCosmWasmTypeClosureV1 source.types
  let typeDecls := source.types
  let pfAssetsDeclared :=
    source.requirements.items.any (·.id == wireExtensionPfAssetsIdV1)
  let storage0 ← makeStorageLayoutV1 types typeDecls source.logicalState
  let storage := { storage0 with pfAssetsDeclared }
  let events ← source.events.mapM (fun d =>
    makeInterfaceBindingV1 "event" d.name d.fields types.uint64TypeId)
  let errors ← source.errors.mapM (fun d =>
    makeInterfaceBindingV1 "error" d.name d.fields types.uint64TypeId)
  let components := source.qualifiedName.components.toArray
  let programName := components.back!
  let fnEnv ← buildCosmWasmFnEnvV1 types source.callables
  let mut initializer : Option Method := none
  let mut entries : Array Method := #[]
  let mut fns : Array FnBinding := #[]
  for callable in source.callables do
    match callable.kind with
    | .initializer =>
        if initializer.isSome then
          throw <| .planInvariant .cosmwasm "semantic program has multiple initializers"
        initializer := some (← makeInitializerV1 types typeDecls storage fnEnv callable)
    | .entry | .view =>
        if entries.size >= maxEntries then
          throw <| .planInvariant .cosmwasm s!"entry count exceeds profile limit {maxEntries}"
        entries := entries.push (← makeEntryV1 types typeDecls storage fnEnv callable)
    | .pureFn =>
        if fns.size >= maxEntries then
          throw <| .planInvariant .cosmwasm s!"pureFn count exceeds profile limit {maxEntries}"
        fns := fns.push (← makePureFnV1 types typeDecls storage fnEnv callable)
    | .invariant =>
        throw <| .planInvariant .cosmwasm
          "unsupported CosmWasm semantic shape: invariants are outside the current UInt64 pilot"
  let resolvedInitializer ← match initializer with
    | some value => pure value
    | none => throw <| .planInvariant .cosmwasm "KV-state programs require an initializer"
  let usesPromise :=
    statementsUsePromiseV1 resolvedInitializer.body ||
      entries.any (fun m => statementsUsePromiseV1 m.body) ||
      fns.any (fun f => statementsUsePromiseV1 f.body)
  let plan : Plan := {
    targetDescriptor := descriptor
    semanticSchemaVersion := semanticProgramSchemaVersionV1
    codegenProfile := descriptor.codegenProfile.toString
    hostAbi := hostAbiVersion
    inputAbi := rawInputAbi
    layoutDomain := stateLayoutDomain
    hostImports := hostImportsFor usesPromise
    failurePolicy := canonicalFailurePolicy
    commitPolicy := .rollbackOnTrap
    resourceLimits := canonicalResourceLimits
    programName
    storage
    events
    errors
    fns
    initializer := resolvedInitializer
    entries
  }
  pure plan

private def makePlanFromSemanticV1
    (source : SemanticProgramV1) : CompileResult Plan := do
  -- Semantic structure was validated once at the capability mint
  -- (resolveEngineeringRequirementsV1 → validateSemanticProgramV1); the
  -- carrier is private-ctor so re-validation here is redundant. Transport
  -- decode still yields SemanticProgramDataV1 for the Plan body.
  let data ← match decodeSemanticProgramDataV1 source.canonicalBytes with
    | .ok value => pure value
    | .error _ =>
        throw <| .invalidProgram "CosmWasm received an invalid SemanticProgramV1 carrier"
  makePlanFromSemanticDataV1 data

/-- Internal CosmWasm family phase entry: capability → Plan (pre-canonicity). -/
def materializePlanFromCapabilityV1 (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .cosmwasm do
    throw <| .planInvariant .cosmwasm "engineering capability kind is not CosmWasm"
  let source := CompiledSemanticV1.semanticV1Of
    (ResolvedEngineeringBuildV1.compiledOf capability)
  makePlanFromSemanticV1 source

/-- Engineering Plan-layer entry that bypasses capability resolve.

    Used by CW-4 schedule Plan/IR/WAT pin tests while the CosmWasm resolver
    still declines `effect.asynchronous-workflow` (main agent re-opens the key
    at integration). **Not** a product path — product remains
    `planFromCapability` after capability resolve. -/
def engineeringPlanFromSemanticV1 (source : SemanticProgramV1) : CompileResult Plan :=
  makePlanFromSemanticV1 source

end ProofForgeV2.Targets.CosmWasm
