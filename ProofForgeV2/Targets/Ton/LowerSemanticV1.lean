import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1
import ProofForgeV2.Compiler.Pipeline

/-!
# Ton LowerSemanticV1 — Plan types + SemanticProgramV1 → Plan lowering

Owns the TON/TVM Plan surface (c4 cell storage, internal-message op dispatch,
get-methods) and Semantic→Plan body for the public-UInt64 state-cell pilot.

CAP-5 admits exact `pf.crypto.sha256` (UInt256→UInt256) as Tolk
`slice.bitsHash()` / TVM `SHA256U` over the Semantic 32-byte LE image.
`pf.crypto.keccak256` and sibling QNs stay fail closed. FunC `string_hash`
is forbidden (cell-hash-flavored name; not this binding).
-/

namespace ProofForgeV2.Targets.Ton

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

/-- Shared descriptor data (single source: DescriptorDataV1). -/
def descriptor : TargetDescriptor := DescriptorDataV1.ton

def hostAbiVersion : String := "ton-tvm-abi-v1"
def rawInputAbi : String := "ton-internal-msg-v1"
def stateLayoutDomain : String := "proof-forge-ton-layout-v1:"
def layoutMarkerKey : String := "pf:ton:v1:layout"

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
  deriving BEq, Inhabited, Repr

/-- Ton MVP host surface: pure TVM cell storage (c4) + async messages.
    No Wasm host imports; no masterchain/library/extra-currency opcodes. -/
inductive HostImport where
  | tvmCellStorage
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
  /-- Signed Int{8,16,32,64} cell field (`intN` + `loadInt`). Default false
      keeps historical unsigned UInt{8,16,32,64,128,256} Plan literals. -/
  isInt : Bool := false
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
  /-- Scalar const table (UInt{8,16,32,64}/Int64/Bool). Empty keeps historical
      Plans byte-identical. Dense tags live in `constantKinds`. -/
  constantTypeIds : Array TypeIdV1 := #[]
  constantKinds : Array Nat := #[]
  constantValues : Array UInt64 := #[]
  deriving BEq, Inhabited, Repr

structure Param where
  sourceId : Nat
  name : String
  inputOffset : Nat
  byteWidth : Nat
  endianness : Endianness
  /-- Signed Int{8,16,32,64} message/get-method param (`loadInt`). Default
      false keeps historical unsigned UInt params. -/
  isInt : Bool := false
  deriving BEq, Inhabited, Repr

/-- Unsigned comparison operators for the public-UInt64 comparison envelope. -/
inductive ComparisonOp where
  | eq | ne | lt | le | gt | ge
  deriving BEq, Inhabited, Repr

inductive Expr where
  | literal (value : UInt64)
  /-- Wide unsigned literal (UInt128 and UInt256). `value` is the full
      unsigned magnitude — never `UInt64.ofNat` / never a 128-bit truncate. -/
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
  /-- Narrow signed body checked arithmetic (`bitWidth ∈ {8,16,32}`);
      Int64 keeps historical `signedChecked*`. Bitwise/shift/neg on
      narrow Int stay fail closed. -/
  | narrowSignedCheckedAdd (bitWidth : Nat) (lhs rhs : Expr)
  | narrowSignedCheckedSub (bitWidth : Nat) (lhs rhs : Expr)
  | narrowSignedCheckedMul (bitWidth : Nat) (lhs rhs : Expr)
  | narrowSignedCheckedDiv (bitWidth : Nat) (lhs rhs : Expr)
  | narrowSignedCheckedMod (bitWidth : Nat) (lhs rhs : Expr)
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
  /-- B-CTX-OPEN: block unix time in whole seconds. Tolk stdlib
      `blockchain.now()` (TVM `NOW`) returns the current block unixtime as
      `int` (~1.7e9 today, always far inside UInt64), so the IR emits it
      directly with no range guard. Carries `context.unixTimeSeconds`;
      UInt64-typed. -/
  | blockUnixTimeSeconds
  /-- CAP-5: SHA-256 of the Semantic UInt256 little-endian 32-byte
      valueBytes via Tolk `slice.bitsHash()` (TVM `SHA256U`).
      Forbidden: FunC `string_hash` spelling / cell representation hash
      (`slice.hash` / `HASHCU` / `HASHBU`). -/
  | sha256 (operand : Expr)
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
      Map / Bytes / named Struct/Enum / B-OPT-STATE Option UInt64). IR lowers as
      two-phase snapshot: evaluate every leaf Expr against the pre-store KV,
      then write all leaves. Sequential leaf stores would re-read already-written
      occ/key/val mid-upsert (empty-Map put hazard). Distinct `storeAtomic`
      statements remain ordered; later ones see earlier writes (Token dual Map
      store). Scalar StateStore keeps single `.store`. -/
  | storeAtomic (leaves : Array Store)
  | returnValue (value : Expr)
  /-- B-RET-ABI / N-ANON-RESULT: multi-leaf view return. `leaves` are preorder
  flatten expressions (UInt64/Int64 only, ≤8); `leafIsInt` is parallel ABI
  signedness. Covers named Struct/Enum, anonymous `Array UInt64 N` (1..8),
  and `Option UInt64` (tag+payload; B-OPT-STATE state load or construct).
  Emitted as a TVM get-method multi-stack return
  (`get fun f(): (int, int, …) { return (t0, t1, …); }`). Entry (mutate)
  aggregate returns stay fail-closed — TON async actors have no return
  channel on internal messages. -/
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
  /-- Async fire-and-forget cross-contract schedule → TON internal out-message.

      ## Reference mapping

      ReferenceV1 `Op.Schedule` is an ordered effect with **no response cursor**.
      TON has no synchronous cross-contract return; the honest native surface is
      an async internal message (`createMessage` + `send`). Sync
      `Op.ExternalCall` remains fail-closed on this target.

      ## Plan fields

      * `receiver` — static QualifiedName **target path** = all components
        except the last, joined by `.` (verbatim; no silent case fold). Must
        pass the schedule-receiver stub grammar below. Emit derives the
        destination account id as
        `SHA-256(UTF-8(receiver))` → basechain workchain `0` + 256-bit hash
        (`dest: (0, 0x… as uint256)`). **This is a deterministic stub of the
        same honesty class as EVM keccak-addr / Solana sha256-program-id /
        NEAR receiver / CosmWasm contract_addr stubs** — it is **not** a real
        on-chain address; production deployment must rewrite to the true
        account id before use.
      * `method` — last QN component (safe identifier). Emit encodes a 32-bit
        op as the first 4 bytes (big-endian) of `SHA-256(UTF-8(method))`.
      * `args` — anonymous public UInt64 expressions (Normalize schedule
        surface). Body layout matches the product internal-message envelope:
        `storeUint(op,32) · storeUint(query_id=0,64) · storeUint(arg_i,64)*`
        in source order. `query_id` is fixed 0 (no correlation / no callback
        channel on this MVP).

      ## Bounce / send-mode / value (materializer fixed policy)

      * **bounce = `BounceMode.NoBounce`**. Schedule has no response channel;
        a bounce reverse-message would be an unexpected inbound that the
        caller does not handle. With MVP `value = 0` there is also no
        application-value recovery role for bounce. This matches
        "failure never propagates to the caller" (Reference schedule and the
        existing promiseAccount comment).
      * **send mode = `SEND_MODE_PAY_FEES_SEPARATELY`** (same as product emit
        external-log path). Fees are paid from the sender balance separately
        from message value.
      * **value = 0**. MVP does not attach GRAM/tokens to schedule messages.
        **Message value economics are a later slice** — not modeled here.

      Deposit/gas are not Plan fields; emit hard-codes the constants above. -/
  | promiseAccount (receiver : String) (method : String) (args : Array Expr)
  deriving BEq, Inhabited, Repr

/-- ABI type of one aggregate return leaf. B-RET-ABI pilot: leaves are
UInt64/Int64 words carried on TVM int257 with explicit range guards
(`isInt` selects signed Int64 vs unsigned UInt64); `byteWidth` is 8. -/
structure LeafAbiType where
  isInt : Bool
  byteWidth : Nat
  deriving BEq, Inhabited, Repr

/-- Result kind of a Ton method export. Init is always unit; entry/view may be
UInt{8,16,32,64,128,256}/Bool/Int{8,16,32,64}. UInt64/Int64/Bool wire as 8-byte
little-endian i64 (Bool is 0/1); UInt{8,16,32}/Int{8,16,32} wire as 1/2/4-byte
cell fields (`uintN`/`intN`) and `loadUint`/`loadInt`; UInt128 is one 16-byte
`uint128` cell / `loadUint(128)`; UInt256 is one 32-byte `uint256` cell /
`loadUint(256)` / nonnegative int257 (already `0 ≤ t < 2^256`; not CosmWasm
multi-limb). ABI JSON
`returns` distinguishes the declared type. B-RET-ABI / N-ANON-RESULT adds
`.aggregate` for **view-only** named Struct/Enum and admitted anonymous
`Array UInt64 N` / `Option UInt64` returns: preorder UInt64/Int64 leaves (1..8)
as a multi-stack get-method return; entry aggregate stays fail-closed. Map /
Bytes / nested / non-UInt64-element anonymous returns stay fail closed.
Int128/256 stay fail closed. -/
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
  /-- B-RET-ABI / N-ANON-RESULT: multi-leaf aggregate view return. `leaves` is
  preorder flatten order (1..8). Covers named Struct/Enum, anonymous
  `Array UInt64 N` (1..8), and `Option UInt64` (tag+payload). Map/Bytes/
  nested/non-UInt64 elements stay fail closed at result-kind resolution.
  Only `.view` methods may carry this kind (entry async has no return channel). -/
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

/-- The Ton-owned KV, raw ABI, method, and error policy for the supported
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
  .error <| .planInvariant .ton message

private def maxIdentifierBytes : Nat := 240
-- `.ton-abi.json` is the longest emitted suffix (14 bytes) under the CLI's
-- 240-byte relative-path ceiling.
def maxArtifactStemBytes : Nat := 222
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

/-- Fixed Ton MVP host import set (c4 cell storage only). -/
def canonicalImports : Array HostImport := #[
  .tvmCellStorage
]

def hostImportsFor (_usesPromise : Bool) : Array HostImport :=
  canonicalImports

def canonicalRegisters : RegisterLayout := {
  input := 0
  storage := 1
  evicted := 2
}

/-- Thin adapter: binds Ton's `maxIdentifierBytes` (240) to the shared grammar. -/
def isIdentifier (value : String) : Bool :=
  isAsciiIdentifier maxIdentifierBytes value

/-- CAP-5: reserve the whole `pf.crypto.*` namespace. Only exact sha256
    is admitted; keccak256 and siblings keep the named host-binding FC. -/
private def isPfCryptoCalleeV1 (components : Array String) : Bool :=
  components[0]? == some "pf" && components[1]? == some "crypto"

private def isPfCryptoSha256CalleeV1 (components : Array String) : Bool :=
  components.size == 3 &&
    components[0]? == some "pf" &&
    components[1]? == some "crypto" &&
    components[2]? == some "sha256"

private def pfCryptoSha256ArityErrorV1 : String :=
  "unsupported Ton semantic shape: pf.crypto.sha256 requires exactly one UInt256 argument and UInt256 result"

private def pfCryptoScheduleErrorV1 : String :=
  "unsupported Ton semantic shape: pf.crypto calls cannot be scheduled"

private def pfCryptoHostBindingErrorV1 (qn : String) : String :=
  s!"unsupported Ton semantic shape: pf.crypto QN '{qn}' has no Ton host binding (keccak256 and siblings stay fail closed)"

/-- Schedule **receiver stub** grammar (pilot): lowercase ASCII letters, digits,
    `_`, `-`, `.`; UTF-8 length 2..64; no leading or trailing `.`. Uppercase is
    rejected (never case-normalized).

    This is **not** TON friendly/raw address validation. The joined static QN
    target path is a deterministic identity stub hashed at emit time; production
    deployment must rewrite to a real account id. Name retained as
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
  s!"schedule receiver '{receiver}' is not a valid Ton schedule-receiver stub (lowercase letters, digits, underscore, hyphen or dot, length 2..64, no leading/trailing dot)"

/-- Sole view/pureFn schedule-disallow error text (lowering + validatePlan).
    `kind` is the richer lowering form, e.g. `"view callable schedules a workflow"`
    or `"pureFn cannot schedule workflows"`. -/
def nearScheduleDisallowedError (kind : String) : String :=
  s!"unsupported Ton semantic shape: {kind}"

/-- Deterministic destination account-id hash for a schedule target path
    (SHA-256 of UTF-8 path → 64 lower-case hex chars). Same honesty class as
    Solana `programIdHex` / EVM keccak address stubs. -/
def scheduleDestHashHexV1 (targetPath : String) : String :=
  Crypto.sha256Hex targetPath.toUTF8

/-- Deterministic 32-bit op code for a schedule method name: first 4 bytes of
    SHA-256(UTF-8 method) interpreted big-endian. Stub encoding — not CRC32 of
    a TL-B type name; real ABI rewrite is a later slice. -/
def scheduleMethodOpCodeV1 (method : String) : UInt32 :=
  let digest := Crypto.sha256 method.toUTF8
  let b0 := digest[0]!.toUInt32
  let b1 := digest[1]!.toUInt32
  let b2 := digest[2]!.toUInt32
  let b3 := digest[3]!.toUInt32
  UInt32.shiftLeft b0 24 ||| UInt32.shiftLeft b1 16 |||
    UInt32.shiftLeft b2 8 ||| b3

def stateKey (sourceId : Nat) : String :=
  s!"pf:ton:v1:state:{sourceId}"

/-- Layout field type suffix from physical byte width (`u8-le` … `u64-le`,
    or `i8-le` … `i64-le` when `isInt`). -/
def layoutFieldTypeSuffix (byteWidth : Nat) (isInt : Bool := false) : String :=
  if isInt then
    match byteWidth with
    | 1 => "i8-le"
    | 2 => "i16-le"
    | 4 => "i32-le"
    | _ => "i64-le"
  else
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

/-- ABI / IDL type string for a param or storage field. -/
def abiScalarTypeString (byteWidth : Nat) (isInt : Bool := false) : String :=
  layoutFieldTypeSuffix byteWidth isInt

private def layoutFieldSignature (field : StorageField) : String :=
  s!"{field.sourceId}:{field.name}:{field.key}:{field.byteWidth}:{layoutFieldTypeSuffix field.byteWidth field.isInt}"

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

/-- Value kinds admitted in the Ton pilot value table. Bool is admitted for
comparison/logical/literal temps, assert conditions, and entry/view return
values. Body multi-width admits UInt{8,16,32,64,128,256} temps (UInt128/256
are one TVM int257 temp + a representable width guard: `0 ≤ t < 2^w` for
w<256, nonnegative-only for w=256); UInt32 also covers shift-count
temps. Top-level state/params admit UInt{8,16,32,64,128,256}|Int{8,16,32,64}.
Int128/256 stay fail closed. Initializer result stays Unit. -/
private inductive TonValueKindV1 where
  | uint64
  | uint32
  | uint16
  | uint8
  | bool
  | int64
  | int32
  | int16
  | int8
  /-- T9e multiword body kinds. -/
  | uint128
  | uint256
  deriving BEq, Inhabited, Repr

/-- Map admitted body UInt width to plan value kind. -/
private def uintKindOfWidthV1 (w : Nat) : Option TonValueKindV1 :=
  match w with
  | 8 => some .uint8
  | 16 => some .uint16
  | 32 => some .uint32
  | 64 => some .uint64
  | 128 => some .uint128
  | 256 => some .uint256
  | _ => none


/-- Inverse of `uintKindOfWidthV1` for store/width gates. -/
private def widthOfUintKindV1 (k : TonValueKindV1) : Option Nat :=
  match k with
  | .uint8 => some 8
  | .uint16 => some 16
  | .uint32 => some 32
  | .uint64 => some 64
  | .uint128 => some 128
  | .uint256 => some 256
  | .bool | .int64 | .int32 | .int16 | .int8 => none

/-- Map admitted Int width to plan value kind. -/
private def intKindOfWidthV1 (w : Nat) : Option TonValueKindV1 :=
  match w with
  | 8 => some .int8
  | 16 => some .int16
  | 32 => some .int32
  | 64 => some .int64
  | _ => none

/-- Inverse of `intKindOfWidthV1`. -/
private def widthOfIntKindV1 (k : TonValueKindV1) : Option Nat :=
  match k with
  | .int8 => some 8
  | .int16 => some 16
  | .int32 => some 32
  | .int64 => some 64
  | _ => none

/-- Ton pilot type-closure carrier (shared `PilotTypeClosureV1`).
    Bool/UInt32 optional; state/params admit
    UInt{8,16,32,64,128,256}|Int{8,16,32,64}. -/
private abbrev TonTypeClosureV1 := PilotTypeClosureV1

private def tonPlanErr (message : String) : CompileError :=
  .planInvariant .ton message

/-- Ton multi-width policy: UInt{8,16,32,64,128,256} for body and state/param
    ABI. UInt128/256 are one Tolk `uintN` cell / `loadUint(N)` / int257 temp
    with a representable width guard (`0 ≤ t < 2^N` for N<256;
    nonnegative-only for N=256) — not CosmWasm lo/hi or 4-limb.
    Int{8,16,32,64} use native Tolk `intN` + `loadInt`/`storeInt`. -/
private def tonUintWidthPolicyV1 : PilotUintWidthPolicy where
  admittedWidths := #[64, 32, 8, 16, 128, 256]

/-- Body/ABI UInt width gate for Ton: `{8,16,32,64,128,256}`. -/
private def isTonBodyUintWidth (w : Nat) : Bool :=
  w == 8 || w == 16 || w == 32 || w == 64 || w == 128 || w == 256

private def isTonAbiUintWidth (w : Nat) : Bool := isTonBodyUintWidth w

/-- TON ABI predicate: UInt{8,16,32,64,128,256} or Int{8,16,32,64}. -/
private def isTonUintAbiOrInt64
    (types : TonTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  match types.uintWidthOf typeId with
  | some w => isTonAbiUintWidth w
  | none =>
      match types.intWidthOf typeId with
      | some w => isAbiIntWidth w
      | none => false

private def requirePublicTonUintAbiOrInt64State
    (types : TonTypeClosureV1) (state : StateDeclV1) : CompileResult Unit := do
  unless isTonUintAbiOrInt64 types state.typeId do
    throw <| tonPlanErr s!"state '{state.name}' is not public UInt64"

private def requirePublicTonUintAbiOrInt64Param
    (types : TonTypeClosureV1) (owner : String) (param : ParameterV1) :
    CompileResult Unit := do
  unless isTonUintAbiOrInt64 types param.typeId do
    throw <| tonPlanErr s!"parameter '{param.name}' in {owner} is not public UInt64"

private def tonTypeClosureWording : PilotTypeClosureWording where
  targetLabel := "Ton"
  uint32DuplicateDetail := "expected one anonymous UInt32 type"
  badIntegerWidthDetail :=
    "only anonymous UInt{8,16,32,64,128,256} and Int{8,16,32,64} integer types are supported (Int128/256 fail closed)"
  unsupportedShapeDetail :=
    "only UInt{8,16,32,64,128,256}, Int{8,16,32,64}, Unit, Bool, Principal (9-leaf wire identity), named Struct/Enum, and anonymous Array/Map/Bytes/Option are supported (no Field; Int128/256 fail closed)"

/-- Ton multi-width + aggregate type closure.
    **Named Struct/Enum** via `pilotNamedAggregateStatePolicyAdmit` (flatten to
    UInt64/Int64 c4 leaves; construct/fieldGet/fieldSet/variant ops; **view-only
    named-aggregate return** via B-RET-ABI multi-stack get method ≤8 leaves).
    **Anonymous containers** via `pilotContainerStatePolicyArrayMapBytes`
    (Array → N×UInt64 leaves; Map → dense cap-8; Bytes → N×UInt8; Option admitted
    as body intermediate when Map is on — never pushed into `containerTypeIds`).
    **B-OPT-STATE / BL-34**: anonymous `Option UInt64`, `Option Int64`, or
    `Option UInt128` **state** admitted as Enum-shaped tag+payload c4 leaves
    (`name_tag` / `name_p0`; tag is always unsigned uint64; payload is
    signed int64 only for Int64, or one unsigned uint128 cell for
    UInt128 — not a UInt64 alias, not two UInt64 limbs, and not CosmWasm
    2-limb Regions; none default = zero fields; storeAtomic on assign;
    match via VariantTag/VariantPayload). Option Int8/16/32, Option
    UInt256, nested Option, Option params, and Option UInt128/Int64
    return stay fail closed.
    **N-ANON-RESULT (TON ABI)**: anonymous `Array UInt64 N` (1..8) and
    `Option UInt64` **view** returns reuse the same multi-stack get-method path;
    entry aggregate stays fail closed (no return channel); Map/Bytes/nested/
    narrow-element anonymous returns stay fail closed. -/
private def validateTonTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult TonTypeClosureV1 :=
  validatePilotTypeClosure tonPlanErr tonTypeClosureWording types
    tonUintWidthPolicyV1
    (intPolicy := pilotIntWidthPolicyNarrow)
    (principalPolicy := pilotPrincipalPolicyAdmit)
    (stringPolicy := pilotStringPolicyAdmit)
    (namedAggregatePolicy := pilotNamedAggregateStatePolicyAdmit)
    (containerPolicy := pilotContainerStatePolicyArrayMapBytes)

/-- Ton pilot Principal storage layout (T12, isomorphic to EVM T10):
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
    throw <| .planInvariant .ton
      s!"state name '{lenName}' is not a safe identifier"
  let mut out : Array String := #[lenName]
  for i in [0:nearPrincipalDataWordCountV1] do
    let wName :=
      if namePrefix.isEmpty then s!"w{i}" else namePrefix ++ "_w" ++ toString i
    unless isIdentifier wName do
      throw <| .planInvariant .ton
        s!"state name '{wName}' is not a safe identifier"
    out := out.push wName
  pure out

/-- Pack wire Principal valueBytes into Ton pilot leaves. -/
private def decodePrincipalLiteralLeavesV1 (bytes : ByteArray) :
    CompileResult (Array Expr) := do
  unless bytes.size ≥ 4 do
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: Principal literal valueBytes too short"
  let len :=
    (bytes.get! 0).toNat + (bytes.get! 1).toNat * 256 +
      (bytes.get! 2).toNat * 65536 + (bytes.get! 3).toNat * 16777216
  unless bytes.size == 4 + len do
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: Principal literal valueBytes length framing mismatch"
  unless 1 ≤ len do
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: Principal body shorter than 1 byte"
  unless len ≤ nearPrincipalMaxPayloadBytesV1 do
    throw <| .planInvariant .ton
      s!"unsupported Ton semantic shape: Principal longer than {nearPrincipalMaxPayloadBytesV1} bytes (Ton pilot bound)"
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

/-- Resolve admitted scalar state/param TypeId to physical byte width
    (1/2/4/8/16/32). Ton admits UInt{8,16,32,64,128,256}/Int{8,16,32,64}
    (UInt256 is one 32-byte cell; Int128/256 FC). -/
private def abiByteWidthOfTypeV1
    (types : TonTypeClosureV1) (typeId : TypeIdV1) : CompileResult Nat := do
  match types.uintWidthOf typeId with
  | some w =>
      unless isTonAbiUintWidth w do
        throw <| .planInvariant .ton
          s!"unsupported Ton semantic shape: ABI UInt{w} is not admitted"
      pure (byteWidthOfBitWidth w)
  | none =>
      match types.intWidthOf typeId with
      | some w =>
          unless isAbiIntWidth w do
            throw <| .planInvariant .ton
              s!"unsupported Ton semantic shape: ABI Int{w} is not admitted (Int128/256 fail closed)"
          pure (byteWidthOfBitWidth w)
      | none =>
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: ABI type must be UInt8/16/32/64/128/256 or Int8/16/32/64"

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

/-- Container leaf layout for Ton KV flattening:
    `(leafCount, leafByteWidth, leafIsInt)`.
    Array: fixed `Array UInt64 N` or `Array Int64 N` → N×8-byte cells
    (`leafIsInt` only for Int64; not a packed array, not a UInt64 alias,
    and not CosmWasm Regions). `Array UInt128 N` → N consecutive 16-byte
    unsigned `uint128` cells (same flatten; `leafIsInt=false`; not
    CosmWasm 2-limb Regions and not two UInt64 leaves). Shared-cell
    budget `64+N*128 ≤ 1023` (`__layout` uint64 + N×uint128; N=8 FC).
    `makeStorageLayoutV1` then re-checks `64+Σ(field.byteWidth*8)`
    whenever any 16-byte leaf is present, so N=7 plus a sibling
    uint64 cannot overflow the same cell.
    Map: dense capacity-8 occ/key/val → 24×8-byte cells. Third Bool is
    **value-is-Int64** for `Map UInt64 Int64` (occ/key stay unsigned
    uint64 cells; not a UInt64-value alias); `Map UInt64 UInt64` keeps
    it false. Bytes: fixed `Bytes N` → N×1-byte UInt8 leaves (byte-exact
    KV identity; element-wise IndexGet/IndexSet). -/
private def containerLeafLayoutV1
    (typeDecls : Array TypeDeclV1) (types : TonTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult (Option (Nat × Nat × Bool)) := do
  unless types.isContainer typeId do
    return none
  match typeDecls[typeId.toNat]? with
  | some { shape := .array elTid len, .. } =>
      -- Keep the historical "must be UInt64" needle as a contains-match so
      -- ArrI8 / ArrU256 stay fail closed without a new string.
      let n := len.toNat
      let leaf :=
        if types.isUInt64 elTid then some (8, false)
        else if types.int64TypeId == some elTid then some (8, true)
        else if types.uintTypeIdAt 128 == some elTid then some (16, false)
        else none
      let some (leafByteWidth, leafIsInt) := leaf |
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: Array state element must be UInt64 or Int64"
      unless n ≥ 1 do
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: Array state length must be ≥ 1"
      -- Honest N≤7 when the layout word shares the c4 cell. Do not flatten
      -- as 2×UInt64 limbs to fake N=8.
      if leafByteWidth == 16 && 64 + n * 128 > 1023 then
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: Array UInt128 exceeds the 1023-bit c4 cell budget"
      pure (some (n, leafByteWidth, leafIsInt))
  | some { shape := .map keyTid valTid, .. } =>
      -- Historical needle stays a contains-match so MapInt8 / MapU128 /
      -- Int64-key / other value shapes stay fail closed. Third Bool is
      -- value-is-Int64, not a uniform 24-leaf signed flag.
      unless types.isUInt64 keyTid &&
          (types.isUInt64 valTid || types.int64TypeId == some valTid) do
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: Map state admits only Map UInt64 UInt64"
      let valIsInt := types.int64TypeId == some valTid
      pure (some (nearMapPilotLeafCountV1, 8, valIsInt))
  | some { shape := .bytes len, .. } =>
      let n := len.toNat
      unless n ≥ 1 do
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: Bytes state length must be ≥ 1"
      pure (some (n, 1, false))
  | _ =>
      throw <| .planInvariant .ton
        "unsupported Ton semantic shape: container TypeId is not Array/Map/Bytes"

/-- True when `typeId` is an anonymous Option TypeDecl. Option is admitted by
    the Map container policy as a Map IndexGet intermediate, by N-ANON-RESULT
    as a view-return shape, and (B-OPT-STATE) as Enum-shaped state layout —
    it is **never** pushed to `containerTypeIds`. -/
private def isAnonymousOptionTypeIdV1
    (typeDecls : Array TypeDeclV1) (typeId : TypeIdV1) : Bool :=
  match typeDecls[typeId.toNat]? with
  | some { shape := .option _, name := none, .. } => true
  | _ => false

/-- B-OPT-STATE: admit anonymous `Option UInt64`, `Option Int64`, or
    `Option UInt128` state (tag+payload). Returns
    `(payloadByteWidth, payloadIsInt)`. Tag stays unsigned uint64.
    Option Int8/16/32, Option UInt256, nested, and named Option stay
    fail closed. Historical needle `requires UInt64 payload` is
    preserved as a contains-match. -/
private def requireOptionUInt64StateV1
    (typeDecls : Array TypeDeclV1) (types : TonTypeClosureV1)
    (typeId : TypeIdV1) (stateName : String) : CompileResult (Nat × Bool) := do
  match typeDecls[typeId.toNat]? with
  | some { shape := .option elTid, name := none, .. } =>
      if types.isUInt64 elTid then
        pure (8, false)
      else if types.int64TypeId == some elTid then
        pure (8, true)
      else if types.uintTypeIdAt 128 == some elTid then
        -- One uint128 cell, not CosmWasm 2-limb / not two UInt64 leaves.
        pure (16, false)
      else
        throw <| .planInvariant .ton
          s!"unsupported Ton semantic shape: Option state '{stateName}' requires UInt64 payload or Int64 payload"
  | _ =>
      throw <| .planInvariant .ton
        s!"unsupported Ton semantic shape: state '{stateName}' is not anonymous Option UInt64"

/-- Flatten a type into ordered leaf names under Ton named-aggregate policy.
    Scalars inside aggregates: UInt64 / Int64 only (matching EVM N3 / Psy H3).
    Named Struct: field preorder. Named Enum: tag (UInt64) + max-payload slots
    (`_tag`, `_p0`…). Nested containers / narrow UInt / Bool / Field as leaves
    fail closed. -/
private partial def flattenTypeLeafSpecsV1
    (typeDecls : Array TypeDeclV1) (types : TonTypeClosureV1)
    (typeId : TypeIdV1) (namePrefix : String) :
    CompileResult (Array String) := do
  if types.isUInt64 typeId then
    pure #[namePrefix]
  else if types.int64TypeId == some typeId then
    pure #[namePrefix]
  else if types.isNamedAggregate typeId then
    match typeDecls[typeId.toNat]? with
    | none =>
        throw <| .planInvariant .ton
          s!"unsupported Ton semantic shape: missing TypeDecl for aggregate {typeId}"
    | some decl =>
        match decl.shape with
        | .struct fields => do
            unless fields.size > 0 do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: named Struct requires at least one field"
            let mut out : Array String := #[]
            for f in fields do
              let subName :=
                if namePrefix.isEmpty then f.name else namePrefix ++ "_" ++ f.name
              unless isIdentifier subName do
                throw <| .planInvariant .ton
                  s!"state name '{subName}' is not a safe identifier"
              let sub ← flattenTypeLeafSpecsV1 typeDecls types f.typeId subName
              out := out ++ sub
            pure out
        | .enum variants => do
            unless variants.size > 0 do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: named Enum requires at least one variant"
            let tagName :=
              if namePrefix.isEmpty then "tag" else namePrefix ++ "_tag"
            unless isIdentifier tagName do
              throw <| .planInvariant .ton
                s!"state name '{tagName}' is not a safe identifier"
            let mut maxPay : Nat := 0
            for v in variants do
              let mut n : Nat := 0
              for pt in v.payloadTypes do
                let sub ← flattenTypeLeafSpecsV1 typeDecls types pt "tmp"
                n := n + sub.size
              if n > maxPay then maxPay := n
            let mut out : Array String := #[tagName]
            for i in [0:maxPay] do
              let pName :=
                if namePrefix.isEmpty then s!"p{i}" else namePrefix ++ "_p" ++ toString i
              unless isIdentifier pName do
                throw <| .planInvariant .ton
                  s!"state name '{pName}' is not a safe identifier"
              out := out.push pName
            pure out
        | _ =>
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: named type must be Struct or Enum"
  else
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: aggregate leaf must be UInt64, Int64, or named Struct/Enum"

private def leafCountOfTypeV1
    (typeDecls : Array TypeDeclV1) (types : TonTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult Nat := do
  let specs ← flattenTypeLeafSpecsV1 typeDecls types typeId "x"
  pure specs.size

/-- B-RET-ABI: resolve a named Struct/Enum result TypeId into per-leaf ABI
types (preorder UInt64/Int64). Enum tag is unsigned; payload pad slots are
unsigned zero-fill (variant max-payload layout). -/
private partial def flattenTypeLeafAbiV1
    (typeDecls : Array TypeDeclV1) (types : TonTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult (Array LeafAbiType) := do
  if types.isUInt64 typeId then
    pure #[{ isInt := false, byteWidth := 8 }]
  else if types.int64TypeId == some typeId then
    pure #[{ isInt := true, byteWidth := 8 }]
  else if types.isNamedAggregate typeId then
    match typeDecls[typeId.toNat]? with
    | none =>
        throw <| .planInvariant .ton
          s!"unsupported Ton semantic shape: missing TypeDecl for aggregate {typeId}"
    | some decl =>
        match decl.shape with
        | .struct fields => do
            unless fields.size > 0 do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: named Struct requires at least one field"
            let mut out : Array LeafAbiType := #[]
            for f in fields do
              let sub ← flattenTypeLeafAbiV1 typeDecls types f.typeId
              out := out ++ sub
            pure out
        | .enum variants => do
            unless variants.size > 0 do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: named Enum requires at least one variant"
            let mut maxPay : Nat := 0
            for v in variants do
              let mut n : Nat := 0
              for pt in v.payloadTypes do
                let sub ← flattenTypeLeafAbiV1 typeDecls types pt
                n := n + sub.size
              if n > maxPay then maxPay := n
            -- Tag is always unsigned UInt64; payload pad slots are unsigned.
            let mut out : Array LeafAbiType := #[{ isInt := false, byteWidth := 8 }]
            for _ in [0:maxPay] do
              out := out.push { isInt := false, byteWidth := 8 }
            pure out
        | _ =>
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: named type must be Struct or Enum"
  else
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: aggregate leaf must be UInt64, Int64, or named Struct/Enum"

/-- N-ANON-RESULT (TON ABI): anonymous result leaf layout for admitted
container **view** returns. `Array UInt64 N` → N×u64 leaves; `Option UInt64` →
tag+payload (none=(0,0), some v=(1,v)). Map/Bytes throw for precise FC. -/
private def anonymousReturnLeafAbiV1
    (typeDecls : Array TypeDeclV1) (types : TonTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult (Option (Array LeafAbiType)) := do
  match typeDecls[typeId.toNat]? with
  | some { shape := .array elTid len, name := none, .. } =>
      let leafIsInt := types.int64TypeId == some elTid
      unless types.isUInt64 elTid || leafIsInt do
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: anonymous Array return requires UInt64 or Int64 elements"
      let n := len.toNat
      unless n ≥ 1 do
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: anonymous Array return length must be ≥ 1"
      pure (some (Array.replicate n { isInt := leafIsInt, byteWidth := 8 }))
  | some { shape := .option elTid, name := none, .. } =>
      let payloadIsInt := types.int64TypeId == some elTid
      unless types.isUInt64 elTid || payloadIsInt do
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: anonymous Option return requires UInt64 or Int64 payload"
      pure (some #[
        { isInt := false, byteWidth := 8 },
        { isInt := payloadIsInt, byteWidth := 8 }])
  | some { shape := .map keyTid valTid, name := none, .. } =>
      -- B-RET-MAP view-only: cap-8 × occ/key/val = 24 leaves. Entry stays FC.
      let valIsInt := types.int64TypeId == some valTid
      unless keyTid == types.uint64TypeId &&
          (valTid == types.uint64TypeId || valIsInt) do
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: anonymous Map return is outside the Ton B-RET ABI"
      let n := nearMapPilotLeafCountV1
      let mut leaves : Array LeafAbiType := #[]
      for i in [0:n] do
        leaves := leaves.push {
          isInt := valIsInt && i % 3 == 2
          byteWidth := 8
        }
      pure (some leaves)
  | some { shape := .bytes len, name := none, .. } =>
      let n := len.toNat
      unless n ≥ 1 && n ≤ 8 do
        throw <| .planInvariant .ton
          s!"unsupported Ton semantic shape: anonymous Bytes return length must be in 1..8, got {n}"
      pure (some (Array.replicate n { isInt := false, byteWidth := 1 }))
  | some { shape := .array .., .. } | some { shape := .option .., .. } =>
      pure none
  | _ => pure none

/-- True when `typeId` should be resolved through the aggregate result path
(named Struct/Enum or anonymous Array/Map/Bytes/Option, so Map/Bytes get
precise fail-closed diagnostics instead of a scalar fallthrough). -/
private def isAggregateResultCandidateV1
    (typeDecls : Array TypeDeclV1) (types : TonTypeClosureV1)
    (typeId : TypeIdV1) : Bool :=
  if types.isNamedAggregate typeId || types.isPrincipal typeId || types.isString typeId then true
  else
    match typeDecls[typeId.toNat]? with
    | some { shape := .array .., name := none, .. }
    | some { shape := .option .., name := none, .. }
    | some { shape := .map .., name := none, .. }
    | some { shape := .bytes .., name := none, .. } => true
    | _ => false

/-- B-RET-ABI / N-ANON-RESULT: resolve a named Struct/Enum or admitted
anonymous Array/Option/Map result TypeId into an aggregate `MethodResultKind`.
Enforces 1..8 leaves except the dense Map pilot (B-RET-MAP, 24 leaves).
Callers must still enforce view-only (entry has no return channel). -/
private def aggregateResultKindOfV1
    (typeDecls : Array TypeDeclV1) (types : TonTypeClosureV1)
    (owner : String) (typeId : TypeIdV1) : CompileResult MethodResultKind := do
  let leaves ←
    if types.isPrincipal typeId || types.isString typeId then
      pure (Array.replicate (nearPrincipalDataWordCountV1 + 1)
        { isInt := false, byteWidth := 8 })
    else if types.isNamedAggregate typeId then
      flattenTypeLeafAbiV1 typeDecls types typeId
    else
      match ← anonymousReturnLeafAbiV1 typeDecls types typeId with
      | some ls => pure ls
      | none =>
          throw <| .planInvariant .ton
            s!"{owner} does not return a named Struct/Enum or admitted anonymous Array/Option/Principal/String aggregate"
  let n := leaves.size
  unless n > 0 do
    throw <| .planInvariant .ton
      s!"{owner} aggregate return must have at least one leaf"
  let maxLeaves :=
    if types.isPrincipal typeId || types.isString typeId then nearPrincipalDataWordCountV1 + 1
    else
      match typeDecls[typeId.toNat]? with
      | some { shape := .map _ _, name := none, .. } => nearMapPilotLeafCountV1
      | _ => 8
  unless n ≤ maxLeaves do
    throw <| .planInvariant .ton
      s!"{owner} aggregate return has {n} leaves, exceeding the B-RET-ABI cap of {maxLeaves}"
  pure (.aggregate leaves)

/-- Expected return shape for region emission (scalar vs B-RET aggregate). -/
private inductive ExpectedReturnV1 where
  | none_
  | scalar (kind : TonValueKindV1)
  | aggregate (leaves : Array LeafAbiType)
  deriving Inhabited

/-- Struct field leaf range (start, length) within the flattened leaf vector. -/
private def structFieldLeafRangeV1
    (typeDecls : Array TypeDeclV1) (types : TonTypeClosureV1)
    (fields : Array StructFieldV1) (fieldIndex : Nat) :
    CompileResult (Nat × Nat) := do
  let mut start : Nat := 0
  for i in [0:fields.size] do
    let some f := fields[i]? |
      throw <| .planInvariant .ton "struct field index out of range"
    let n ← leafCountOfTypeV1 typeDecls types f.typeId
    if i == fieldIndex then return (start, n)
    start := start + n
  throw <| .planInvariant .ton "struct field index out of range"

/-- Enum max payload leaf count (excluding tag). -/
private def enumMaxPayloadLeavesV1
    (typeDecls : Array TypeDeclV1) (types : TonTypeClosureV1)
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
    (typeDecls : Array TypeDeclV1) (types : TonTypeClosureV1)
    (variants : Array EnumVariantV1) (variantIndex payloadIndex : Nat) :
    CompileResult (Nat × Nat) := do
  let some v := variants[variantIndex]? |
    throw <| .planInvariant .ton "enum variant index out of range"
  let mut start : Nat := 0
  for i in [0:v.payloadTypes.size] do
    let some pt := v.payloadTypes[i]? |
      throw <| .planInvariant .ton "enum payload index out of range"
    let n ← leafCountOfTypeV1 typeDecls types pt
    if i == payloadIndex then return (start, n)
    start := start + n
  throw <| .planInvariant .ton "enum payload index out of range"

/-- Resolve scalar kind for a fieldGet/variantPayload leaf result. -/
private def scalarKindOfNamedLeafResultV1
    (types : TonTypeClosureV1) (typeId : TypeIdV1) :
    CompileResult TonValueKindV1 := do
  if types.isUInt64 typeId then
    pure .uint64
  else if types.int64TypeId == some typeId then
    pure .int64
  else
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: named-aggregate scalar leaf must be UInt64 or Int64"

/-- Select `chosen` vs `kept` with a 0/1 write/miss pair.
    Unsigned mux attaches `uint64RangeCheck` (`0 <= dest < 1<<64`) and
    traps `loadInt` negatives. Signed mux uses Int64 range. Occ/key
    always pass `signed := false`. -/
private def mapSelectLeafV1 (write miss chosen kept : Expr) (signed : Bool) : Expr :=
  if signed then
    Expr.signedCheckedAdd
      (Expr.signedCheckedMul write chosen)
      (Expr.signedCheckedMul miss kept)
  else
    Expr.checkedAdd
      (Expr.checkedMul write chosen)
      (Expr.checkedMul miss kept)

/-- Dense Map IndexGet → Option as `[tag, payload]`. `valIsInt` is
    TypeDecl `.map` value-is-Int64 (not `n == 24`): only the payload
    word uses the signed select. Occ/key hit math stays unsigned. -/
private def mapLookupOptionLeavesV1
    (mapLeaves : Array Expr) (key : Expr) (valIsInt : Bool) :
    CompileResult (Array Expr) := do
  unless mapLeaves.size == nearMapPilotLeafCountV1 do
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: Map leaf count must match pilot capacity"
  let mut found : Expr := .literal 0
  let mut payload : Expr := .literal 0
  for e in [0:nearMapPilotCapacityV1] do
    let base := e * nearMapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      throw <| .planInvariant .ton "Map lookup occ leaf missing"
    let some k := mapLeaves[base + 1]? |
      throw <| .planInvariant .ton "Map lookup key leaf missing"
    let some v := mapLeaves[base + 2]? |
      throw <| .planInvariant .ton "Map lookup val leaf missing"
    let hit := Expr.checkedMul occ (Expr.compare .eq k key)
    let miss := Expr.boolNot hit
    found := Expr.boolOr found hit
    payload := mapSelectLeafV1 hit miss v payload valIsInt
  pure #[Expr.checkedAdd found (.literal 0), payload]

/-- Dense Map IndexSet upsert. Returns (newLeaves, okInsert).
    `valIsInt` muxes only the val slot with signedChecked*; occ/key
    stay unsigned checkedMul/Add. -/
private def mapUpsertLeavesV1
    (mapLeaves : Array Expr) (key value : Expr) (valIsInt : Bool) :
    CompileResult (Array Expr × Expr) := do
  unless mapLeaves.size == nearMapPilotLeafCountV1 do
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: Map leaf count must match pilot capacity"
  let mut anyMatch : Expr := .literal 0
  for e in [0:nearMapPilotCapacityV1] do
    let base := e * nearMapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      throw <| .planInvariant .ton "Map upsert occ leaf missing"
    let some k := mapLeaves[base + 1]? |
      throw <| .planInvariant .ton "Map upsert key leaf missing"
    let hit := Expr.checkedMul occ (Expr.compare .eq k key)
    anyMatch := Expr.boolOr anyMatch hit
  let mut seenEmpty : Expr := .literal 0
  let mut isFirstEmpty : Array Expr := #[]
  for e in [0:nearMapPilotCapacityV1] do
    let base := e * nearMapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      throw <| .planInvariant .ton "Map upsert empty-scan occ missing"
    let empty := Expr.boolNot occ
    let first := Expr.checkedMul empty (Expr.boolNot seenEmpty)
    isFirstEmpty := isFirstEmpty.push first
    seenEmpty := Expr.boolOr seenEmpty empty
  let okInsert := Expr.boolOr anyMatch seenEmpty
  let mut out : Array Expr := #[]
  for e in [0:nearMapPilotCapacityV1] do
    let base := e * nearMapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      throw <| .planInvariant .ton "Map upsert rebuild occ missing"
    let some k := mapLeaves[base + 1]? |
      throw <| .planInvariant .ton "Map upsert rebuild key missing"
    let some v := mapLeaves[base + 2]? |
      throw <| .planInvariant .ton "Map upsert rebuild val missing"
    let matchHit := Expr.checkedMul occ (Expr.compare .eq k key)
    let some firstE := isFirstEmpty[e]? |
      throw <| .planInvariant .ton "Map upsert firstEmpty missing"
    let insertHere := Expr.checkedMul firstE (Expr.boolNot anyMatch)
    let write := Expr.boolOr matchHit insertHere
    let miss := Expr.boolNot write
    let occ' := Expr.checkedAdd (Expr.boolOr occ write) (.literal 0)
    let k' := mapSelectLeafV1 write miss key k false
    let v' := mapSelectLeafV1 write miss value v valIsInt
    out := out.push occ' |>.push k' |>.push v'
  pure (out, okInsert)

private def makeStorageLayoutV1
    (types : TonTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (states : Array StateDeclV1) : CompileResult StorageLayout := do
  if states.isEmpty || states.size > maxStateFields then
    throw <| .planInvariant .ton "state count is outside the profile limits"
  let mut fields : Array StorageField := #[]
  let mut stateLeaves : Array (Array Nat) := #[]
  for state in states do
    unless state.id.toNat == stateLeaves.size do
      throw <| .planInvariant .ton "semantic state ids must match declaration order"
    unless isIdentifier state.name do
      throw <| .planInvariant .ton s!"state name '{state.name}' is not a safe identifier"
    match ← containerLeafLayoutV1 typeDecls types state.typeId with
    | some (n, leafByteWidth, leafIsInt) =>
        -- Array: N consecutive 8-byte UInt64 or Int64 c4 cells (`isInt`
        -- selects Tolk `int64` / `loadInt`, not a UInt64 alias), or N
        -- consecutive 16-byte unsigned uint128 cells for Array UInt128
        -- (`leafByteWidth=16`, not CosmWasm 2-limb / not two UInt64
        -- leaves). Map cap-8: 24×8-byte occ/key/val; `leafIsInt` is
        -- value-is-Int64 so only val slots (`i % 3 == 2`) are
        -- int64/loadInt — occ/key stay unsigned (not a UInt64-value
        -- alias). Bytes: N consecutive 1-byte UInt8 cells. Physical
        -- names `name_0`..`name_{n-1}` keep layout markers deterministic.
        -- Visibility: same N1 allowNonPublic as scalar state. Signedness
        -- follows TypeDecl shape, never leaf count: Array Int64 24 stays
        -- 24 uniform int64 cells.
        if fields.size + n > maxStateFields then
          throw <| .planInvariant .ton "state count is outside the profile limits"
        let isMapState :=
          match typeDecls[state.typeId.toNat]? with
          | some { shape := .map .., .. } => true
          | _ => false
        let mut leaves : Array Nat := #[]
        for i in [0:n] do
          let leafName := state.name ++ "_" ++ toString i
          unless isIdentifier leafName do
            throw <| .planInvariant .ton
              s!"state name '{leafName}' is not a safe identifier"
          let fi := fields.size
          leaves := leaves.push fi
          -- Map: val signed only when value-is-Int64. Array/Bytes keep a
          -- uniform `leafIsInt` even when N happens to be 24.
          let slotIsInt :=
            if isMapState then
              leafIsInt && (i % 3 == 2)
            else
              leafIsInt
          fields := fields.push {
            sourceId := fi
            name := leafName
            key := stateKey fi
            byteWidth := leafByteWidth
            endianness := .little
            isInt := slotIsInt
          }
        stateLeaves := stateLeaves.push leaves
    | none =>
        if types.isNamedAggregate state.typeId then
          -- Named Struct/Enum: preorder UInt64/Int64 leaves as separate 8-byte
          -- KV fields (`name_field` / `name_tag` / `name_p0`…). Atomic
          -- storeAtomic for StateStore (same store-then-read hazard fix as Map).
          requirePublicUInt64OrInt64OrFieldOrPrincipalOrNamedState tonPlanErr types state
            (allowNonPublic := true)
          let leafSpecs ← flattenTypeLeafSpecsV1 typeDecls types state.typeId state.name
          if leafSpecs.isEmpty then
            throw <| .planInvariant .ton
              s!"state '{state.name}' produced zero named-aggregate leaves"
          if fields.size + leafSpecs.size > maxStateFields then
            throw <| .planInvariant .ton "state count is outside the profile limits"
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
        else if isAnonymousOptionTypeIdV1 typeDecls state.typeId then
          -- B-OPT-STATE / BL-34: Option UInt64, Int64, or UInt128 → tag +
          -- payload. Names follow Enum convention (`name_tag` / `name_p0`).
          -- Tag is always unsigned uint64; payload is int64 only for Int64,
          -- or one unsigned uint128 cell for UInt128 (not a UInt64 alias,
          -- not two UInt64 limbs, and not CosmWasm 2-limb Regions). Default
          -- zero fields = Option.none; storeAtomic writes both leaves; none
          -- construct zeroes payload (pin). Int8/16/32 and UInt256 Option
          -- payloads fail closed above. Cell budget: tag 64 + payload 128
          -- + `__layout` 64 = 256 ≤ 1023.
          let (payloadByteWidth, payloadIsInt) ←
            requireOptionUInt64StateV1 typeDecls types state.typeId state.name
          let tagName := state.name ++ "_tag"
          let pName := state.name ++ "_p0"
          unless isIdentifier tagName do
            throw <| .planInvariant .ton
              s!"state name '{tagName}' is not a safe identifier"
          unless isIdentifier pName do
            throw <| .planInvariant .ton
              s!"state name '{pName}' is not a safe identifier"
          if fields.size + 2 > maxStateFields then
            throw <| .planInvariant .ton "state count is outside the profile limits"
          let mut leaves : Array Nat := #[]
          for (leafName, leafIsInt, leafByteWidth) in
              #[(tagName, false, (8 : Nat)), (pName, payloadIsInt, payloadByteWidth)] do
            let fi := fields.size
            leaves := leaves.push fi
            fields := fields.push {
              sourceId := fi
              name := leafName
              key := stateKey fi
              byteWidth := leafByteWidth
              endianness := .little
              isInt := leafIsInt
            }
          stateLeaves := stateLeaves.push leaves
        else if types.isPrincipal state.typeId || types.isString state.typeId then
          -- T12 Principal / B-RET-STR String: 9 KV fields (`name_len` + `name_w0`..`name_w7`).
          -- ValidatePlan requires sourceId == physical field index (dense).
          -- Logical state → leaf indices live only in `stateLeaves`.
          requirePublicUInt64OrInt64OrFieldOrPrincipalOrNamedState tonPlanErr types state
            (allowNonPublic := true)
          let leafSpecs ← flattenPrincipalLeafSpecsV1 state.name
          if fields.size + leafSpecs.size > maxStateFields then
            throw <| .planInvariant .ton "state count is outside the profile limits"
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
          -- BL-14/T8b: scalar state admits UInt{8,16,32,64,128,256} /
          -- Int{8,16,32,64} with byteWidth 1/2/4/8/16/32. Cell fields use
          -- exact bit width at emit. UInt256 pitch is 32 bytes.
          requirePublicTonUintAbiOrInt64State types state
          let byteWidth ← abiByteWidthOfTypeV1 types state.typeId
          let isInt := (types.intWidthOf state.typeId).isSome
          let fi := fields.size
          fields := fields.push {
            sourceId := fi
            name := state.name
            key := stateKey fi
            byteWidth
            endianness := .little
            isInt
          }
          stateLeaves := stateLeaves.push #[fi]
  -- Shared c4 cell: `__layout` uint64 + every field. Only enforce when a
  -- 16-byte (uint128) leaf is present — do not apply this to the
  -- historical Map 24×uint64 flatten, which already exceeds one cell.
  if fields.any (fun f => f.byteWidth == 16) then
    let payloadBits : Nat :=
      fields.foldl (fun (acc : Nat) f => acc + f.byteWidth * 8) 0
    if 64 + payloadBits > 1023 then
      throw <| .planInvariant .ton
        "unsupported Ton semantic shape: Array UInt128 exceeds the 1023-bit c4 cell budget"
  let marker := layoutMarker fields
  if marker == 0 then
    throw <| .planInvariant .ton
      "state layout marker collides with the reserved uninitialized value"
  pure {
    markerKey := layoutMarkerKey
    markerValue := marker
    payloadInitialization := .zeroAllFields
    fields
    stateLeaves
  }

private structure LoweredValueV1 where
  expr : Expr
  kind : TonValueKindV1
  depth : Nat
  expandedNodes : Nat
  dependencies : Array ValueIdV1
  /-- Multi-leaf carrier: Principal (len+8 words), Array UInt64 N, Map capacity-8
      occ/key/val, Bytes N (1-byte UInt8 leaves), named Struct/Enum (preorder
      UInt64/Int64 leaves), or Option `[tag,payload]` (Map IndexGet intermediate,
      N-ANON-RESULT construct/return, or B-OPT-STATE storage load/store).
      `expr` mirrors `leaves[0]!` (or literal 0). Scalar values keep `none`. -/
  aggregateLeaves : Option (Array Expr) := none
  /-- Physical byte width of each leaf KV value: 8 for UInt64 leaves
      (Array/Map/Principal/named Struct/Enum), 16 for Array UInt128
      unsigned cells, 1 for Bytes leaves (UInt8). Scalar values keep 8. -/
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

private def makeParamsV1 (owner : String) (types : TonTypeClosureV1)
    (typeDecls : Array TypeDeclV1) (params : Array ParameterV1) :
    CompileResult (Array Param × Array LoweredValueV1) := do
  if params.size > maxParams then
    throw <| .planInvariant .ton s!"parameter count in {owner} exceeds profile limit {maxParams}"
  let mut planned : Array Param := #[]
  let mut values : Array LoweredValueV1 := #[]
  let mut nextInputOffset : Nat := 0
  for param in params do
    -- ValueId tracks logical params (values.size); planned may expand (Principal leaves).
    unless param.valueId.toNat == values.size do
      throw <| .planInvariant .ton
        s!"semantic parameter ValueIds in {owner} must match declaration order"
    unless isIdentifier param.name do
      throw <| .planInvariant .ton
        s!"parameter name '{param.name}' in {owner} is not a safe identifier"
    if types.isPrincipal param.typeId || types.isString param.typeId then
      -- T12 / B-RET-STR: Principal/String expands to 9×UInt64 input words.
      requirePublicUInt64OrInt64OrFieldOrPrincipalOrNamedParam
        tonPlanErr types owner param (allowNonPublic := true)
      let leafSpecs ← flattenPrincipalLeafSpecsV1 param.name
      if planned.size + leafSpecs.size > maxParams then
        throw <| .planInvariant .ton
          s!"parameter count in {owner} exceeds profile limit {maxParams}"
      let mut leafExprs : Array Expr := #[]
      for leafName in leafSpecs do
        unless isIdentifier leafName do
          throw <| .planInvariant .ton
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
    else if types.isNamedAggregate param.typeId then
      -- Named Struct/Enum param: flatten to 8-byte UInt64 input words (leaf
      -- tuple); field/variant access on the aggregate is leaf-level only.
      requirePublicUInt64OrInt64OrFieldOrPrincipalOrNamedParam
        tonPlanErr types owner param (allowNonPublic := true)
      let leafSpecs ← flattenTypeLeafSpecsV1 typeDecls types param.typeId param.name
      if leafSpecs.isEmpty then
        throw <| .planInvariant .ton
          s!"parameter '{param.name}' in {owner} produced zero named-aggregate leaves"
      if planned.size + leafSpecs.size > maxParams then
        throw <| .planInvariant .ton
          s!"parameter count in {owner} exceeds profile limit {maxParams}"
      let mut leafExprs : Array Expr := #[]
      for leafName in leafSpecs do
        unless isIdentifier leafName do
          throw <| .planInvariant .ton
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
      match typeDecls[param.typeId.toNat]? with
      | some { shape := .option elTid, name := none, .. } =>
          unless types.isUInt64 elTid || types.int64TypeId == some elTid do
            throw <| .planInvariant .ton
              s!"unsupported Ton semantic shape: Option parameter '{param.name}' payload must be UInt64 or Int64"
          if planned.size + 2 > maxParams then
            throw <| .planInvariant .ton
              s!"parameter count in {owner} exceeds profile limit {maxParams}"
          let mut leafExprs : Array Expr := #[]
          for leafName in #[param.name ++ "_tag", param.name ++ "_p0"] do
            unless isIdentifier leafName do
              throw <| .planInvariant .ton
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
      | _ =>
          throw <| .planInvariant .ton
            s!"unsupported Ton semantic shape: Option parameter '{param.name}' must be anonymous Option UInt64/Int64"
    else if types.isContainer param.typeId then
      let some (n, leafByteWidth, leafIsInt) ←
        containerLeafLayoutV1 typeDecls types param.typeId |
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: container param is not Array/Map/Bytes"
      match typeDecls[param.typeId.toNat]? with
      | some { shape := .bytes .., .. } =>
          unless leafByteWidth == 1 do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: Bytes param leaves must be UInt8"
          if planned.size + n > maxParams then
            throw <| .planInvariant .ton
              s!"parameter count in {owner} exceeds profile limit {maxParams}"
          let mut leafExprs : Array Expr := #[]
          for i in [0:n] do
            let leafName := param.name ++ "_" ++ toString i
            unless isIdentifier leafName do
              throw <| .planInvariant .ton
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
      | some { shape := .array .., .. } =>
          unless 1 ≤ n && n ≤ 8 do
            throw <| .planInvariant .ton
              s!"parameter '{param.name}' in {owner} Array N must flatten to 1..8 leaves (got {n})"
          if planned.size + n > maxParams then
            throw <| .planInvariant .ton
              s!"parameter count in {owner} exceeds profile limit {maxParams}"
          let mut leafExprs : Array Expr := #[]
          for i in [0:n] do
            let leafName := param.name ++ "_" ++ toString i
            unless isIdentifier leafName do
              throw <| .planInvariant .ton
                s!"parameter name '{leafName}' in {owner} is not a safe identifier"
            let binding : Param := {
              sourceId := planned.size
              name := leafName
              inputOffset := nextInputOffset
              byteWidth := leafByteWidth
              endianness := .little
              isInt := leafIsInt
            }
            planned := planned.push binding
            leafExprs := leafExprs.push (.param nextInputOffset)
            nextInputOffset := nextInputOffset + slotPitchOfByteWidth leafByteWidth
          values := values.push (mkAggregateValueV1 leafExprs #[] 1 leafExprs.size
            (leafByteWidth := leafByteWidth))
      | some { shape := .map keyTid valTid, .. } =>
          let valIsInt := types.int64TypeId == some valTid
          unless keyTid == types.uint64TypeId &&
              (valTid == types.uint64TypeId || valIsInt) &&
              n == nearMapPilotLeafCountV1 do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: Map params stay fail closed (Array/Bytes N params flatten)"
          if planned.size + n > maxParams then
            throw <| .planInvariant .ton
              s!"parameter count in {owner} exceeds profile limit {maxParams}"
          let mut leafExprs : Array Expr := #[]
          for i in [0:n] do
            let leafName := param.name ++ "_" ++ toString i
            unless isIdentifier leafName do
              throw <| .planInvariant .ton
                s!"parameter name '{leafName}' in {owner} is not a safe identifier"
            let binding : Param := {
              sourceId := planned.size
              name := leafName
              inputOffset := nextInputOffset
              byteWidth := leafByteWidth
              endianness := .little
              isInt := valIsInt && i % 3 == 2
            }
            planned := planned.push binding
            leafExprs := leafExprs.push (.param nextInputOffset)
            nextInputOffset := nextInputOffset + slotPitchOfByteWidth leafByteWidth
          values := values.push (mkAggregateValueV1 leafExprs #[] 1 leafExprs.size
            (leafByteWidth := leafByteWidth))
      | _ =>
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: Map params stay fail closed (Array/Bytes N params flatten)"
    else
      -- BL-14/T8b: ABI params admit UInt{8,16,32,64,128,256}/Int{8,16,32,64}.
      -- UInt128 pitch is 16 bytes; UInt256 pitch is 32 bytes; narrower
      -- values occupy one 8-byte slot.
      requirePublicTonUintAbiOrInt64Param types owner param
      let isInt := (types.intWidthOf param.typeId).isSome
      let byteWidth ← abiByteWidthOfTypeV1 types param.typeId
      let bitWidth := bitWidthOfByteWidth byteWidth
      let binding : Param := {
        sourceId := planned.size
        name := param.name
        inputOffset := nextInputOffset
        byteWidth
        endianness := .little
        isInt
      }
      nextInputOffset := nextInputOffset + slotPitchOfByteWidth byteWidth
      planned := planned.push binding
      let kind ←
        if isInt then
          match intKindOfWidthV1 bitWidth with
          | some k => pure k
          | none =>
              throw <| .planInvariant .ton
                s!"unsupported Ton semantic shape: ABI Int{bitWidth} is not admitted"
        else match uintKindOfWidthV1 bitWidth with
          | some k => pure k
          | none =>
              throw <| .planInvariant .ton
                s!"unsupported Ton semantic shape: ABI UInt{bitWidth} is not admitted"
      values := values.push {
        -- Narrow ABI params retain semantic width for body arithmetic;
        -- signed loads use `loadInt` at emit (param.isInt).
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

private def findValueV1 (values : Array LoweredValueV1)
    (id : ValueIdV1) : CompileResult LoweredValueV1 :=
  match values[id.toNat]? with
  | some value => .ok value
  | none => planError s!"semantic expression references unknown ValueId {id.toNat}"

/-- Require a compile-time UInt32/UInt64 literal index for Array IndexGet/IndexSet. -/
private def literalIndexNatV1 (v : LoweredValueV1) : CompileResult Nat := do
  unless v.kind == .uint32 || v.kind == .uint64 do
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: Array index must be a UInt32/UInt64 literal"
  match v.expr with
  | .literal n => pure n.toNat
  | _ =>
      throw <| .planInvariant .ton
        "unsupported Ton semantic shape: Array IndexGet/IndexSet requires a compile-time constant index"

private def decodeUInt64LiteralV1 (bytes : ByteArray) : CompileResult UInt64 :=
  decodeUInt64LiteralLe tonPlanErr "Ton" bytes

/-- Decode a 4-byte little-endian UInt32 literal into a zero-extended UInt64
    plan value (shift counts only). -/
private def decodeUInt32LiteralV1 (bytes : ByteArray) : CompileResult UInt64 :=
  decodeUInt32LiteralLe tonPlanErr "Ton" bytes

private def decodeBoolLiteralV1 (bytes : ByteArray) : CompileResult Bool :=
  decodeBoolLiteralBit tonPlanErr "Ton" bytes

/-- Dense tag for `StorageLayout.constantKinds`. -/
private def tonConstantKindTagV1 : TonValueKindV1 → Nat
  | .uint64 => 0
  | .uint32 => 1
  | .uint16 => 2
  | .uint8 => 3
  | .bool => 4
  | .int64 => 5
  | .int32 | .int16 | .int8 | .uint128 | .uint256 => 0

private def tonConstantKindOfTagV1 (tag : Nat) : Option TonValueKindV1 :=
  match tag with
  | 0 => some .uint64
  | 1 => some .uint32
  | 2 => some .uint16
  | 3 => some .uint8
  | 4 => some .bool
  | 5 => some .int64
  | _ => none

private def isTonScalarConstUintWidth (w : Nat) : Bool :=
  w == 8 || w == 16 || w == 32 || w == 64

private def decodeTonConstantSlotV1
    (types : TonTypeClosureV1) (typeId : TypeIdV1) (bytes : ByteArray) :
    CompileResult (TonValueKindV1 × UInt64) := do
  if let some bitWidth := types.intWidthOf typeId then
    unless bitWidth == 64 do
      throw <| .planInvariant .ton
        s!"unsupported Ton semantic shape: Int{bitWidth} constant is not admitted"
    let value ← decodeIntWidthLiteralLe tonPlanErr "Ton" bitWidth bytes
    pure (.int64, value)
  else if let some bitWidth := types.uintWidthOf typeId then
    unless isTonScalarConstUintWidth bitWidth do
      throw <| .planInvariant .ton
        s!"unsupported Ton semantic shape: UInt{bitWidth} constant is outside the Ton scalar const pilot"
    let kind ← match uintKindOfWidthV1 bitWidth with
      | some k => pure k
      | none =>
          throw <| .planInvariant .ton
            s!"unsupported Ton semantic shape: UInt{bitWidth} constant is not admitted"
    let value ← decodeUIntWidthLiteralLe tonPlanErr "Ton" bitWidth bytes
    pure (kind, value)
  else
    let boolTid ← match types.boolTypeId with
      | some tid => pure tid
      | none =>
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: Bool type is missing for Bool constant"
    unless typeId == boolTid do
      throw <| .planInvariant .ton
        "unsupported Ton semantic shape: constant is not admitted UInt width, Int64, or Bool"
    let flag ← decodeBoolLiteralV1 bytes
    pure (.bool, if flag then 1 else 0)

private def makeTonConstantTableV1
    (types : TonTypeClosureV1) (constants : Array ConstantV1) :
    CompileResult (Array TypeIdV1 × Array Nat × Array UInt64) := do
  let mut typeIds : Array TypeIdV1 := #[]
  let mut kinds : Array Nat := #[]
  let mut values : Array UInt64 := #[]
  for i in [0:constants.size] do
    let some c := constants[i]? |
      throw <| .planInvariant .ton
        "unsupported Ton semantic shape: constant table hole"
    unless c.id.toNat == i do
      throw <| .planInvariant .ton
        "unsupported Ton semantic shape: Constant id does not match declaration order"
    let (kind, value) ← decodeTonConstantSlotV1 types c.typeId c.valueBytes
    typeIds := typeIds.push c.typeId
    kinds := kinds.push (tonConstantKindTagV1 kind)
    values := values.push value
  pure (typeIds, kinds, values)

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
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: computed ValueId crosses an effect boundary"
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
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: computed ValueId crosses an effect boundary"
  findValueV1 values id

private def makeBinaryTreeValueKindsV1
    (mk : Expr → Expr → Expr)
    (lhsKind rhsKind resultKind : TonValueKindV1)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless lhs.kind == lhsKind && rhs.kind == rhsKind do
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: binary operand kinds do not match the operator"
  let depth := 1 + max lhs.depth rhs.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .ton s!"Ton plan expression exceeds depth {maxExprDepth}"
  if lhs.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .ton s!"Ton plan expression exceeds node limit {maxPlanNodes}"
  let remaining := maxPlanNodes - 1 - lhs.expandedNodes
  if rhs.expandedNodes > remaining then
    throw <| .planInvariant .ton s!"Ton plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := mk lhs.expr rhs.expr
    kind := resultKind
    depth
    expandedNodes := 1 + lhs.expandedNodes + rhs.expandedNodes
    dependencies := #[lhsId, rhsId]
  }

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
private def mkSignedCheckedAdd (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .signedCheckedAdd l r else .narrowSignedCheckedAdd w l r
private def mkSignedCheckedSub (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .signedCheckedSub l r else .narrowSignedCheckedSub w l r
private def mkSignedCheckedMul (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .signedCheckedMul l r else .narrowSignedCheckedMul w l r
private def mkSignedCheckedDiv (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .signedCheckedDiv l r else .narrowSignedCheckedDiv w l r
private def mkSignedCheckedMod (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .signedCheckedMod l r else .narrowSignedCheckedMod w l r
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
    (kind : TonValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkCheckedAdd bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeCheckedSubValueV1
    (kind : TonValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkCheckedSub bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeCheckedMulValueV1
    (kind : TonValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkCheckedMul bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeCheckedDivValueV1
    (kind : TonValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkCheckedDiv bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeCheckedModValueV1
    (kind : TonValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkCheckedMod bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeBitAndValueV1
    (kind : TonValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkBitAnd bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeBitOrValueV1
    (kind : TonValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkBitOr bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeBitXorValueV1
    (kind : TonValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkBitXor bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeShlValueV1
    (lhsKind : TonValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkShl bitWidth) lhsKind .uint32 lhsKind
    lhsId rhsId lhs rhs

private def makeShrValueV1
    (lhsKind : TonValueKindV1) (bitWidth : Nat)
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
    (operandKind resultKind : TonValueKindV1)
    (operandId : ValueIdV1)
    (operand : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless operand.kind == operandKind do
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: unary operand kind mismatch"
  let depth := 1 + operand.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .ton s!"Ton plan expression exceeds depth {maxExprDepth}"
  if operand.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .ton s!"Ton plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := mk operand.expr
    kind := resultKind
    depth
    expandedNodes := 1 + operand.expandedNodes
    dependencies := #[operandId]
  }

private def makeBitNotValueV1
    (kind : TonValueKindV1) (bitWidth : Nat)
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
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: comparison operand kinds do not match"
  unless (widthOfUintKindV1 lhs.kind).isSome do
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: unsigned comparison requires UInt operands"
  let bw := match widthOfUintKindV1 lhs.kind with | some w => w | none => 64
  if bw > 64 then
    makeBinaryTreeValueKindsV1 (fun l r => .wideCompare bw op l r) lhs.kind rhs.kind .bool
      lhsId rhsId lhs rhs
  else
    makeBinaryTreeValueKindsV1 (fun l r => .compare op l r) lhs.kind rhs.kind .bool
      lhsId rhsId lhs rhs

/-- Admit a wire result TypeId for UInt-width arithmetic/bitwise and return
    `(typeId, kind, bitWidth)`. UInt8/16/32/64/128/256. -/
private def admitUIntWidthResultTypeV1
    (types : TonTypeClosureV1) (resultTypeId : TypeIdV1) :
    CompileResult (TypeIdV1 × TonValueKindV1 × Nat) := do
  match types.uintWidthOf resultTypeId with
  | some w =>
      unless isTonBodyUintWidth w do
        throw <| .planInvariant .ton
          s!"unsupported Ton semantic shape: arithmetic/bitwise result UInt{w} is not admitted"
      match uintKindOfWidthV1 w with
      | some k => pure (resultTypeId, k, w)
      | none =>
          throw <| .planInvariant .ton
            s!"unsupported Ton semantic shape: arithmetic/bitwise result UInt{w} is not admitted"
  | none =>
      throw <| .planInvariant .ton
        "unsupported Ton semantic shape: arithmetic/bitwise result must be admitted UInt width"

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
      throw <| .planInvariant .ton
        "unsupported Ton semantic shape: sink references a stale ValueId"
    let localIndex := index - segmentStart
    if visited[localIndex]? == some false then
      visited := visited.set! localIndex true
      visitedCount := visitedCount + 1
      let value := values[index]!
      for dependency in value.dependencies do
        let dependencyIndex := dependency.toNat
        if dependencyIndex >= segmentStart then
          unless dependencyIndex < values.size do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: expression crosses an effect boundary"
          stack := stack.push dependencyIndex
        else if dependencyIndex >= blockEntry then
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: expression crosses an effect boundary"
  unless visitedCount == segmentCount do
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: dead or reordered value instructions"
  pure rootValue.expr

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
      throw <| .planInvariant .ton
        "unsupported Ton semantic shape: sink references a stale ValueId"
    let localIndex := index - segmentStart
    if visited[localIndex]? == some false then
      visited := visited.set! localIndex true
      visitedCount := visitedCount + 1
      let value := values[index]!
      for dependency in value.dependencies do
        let dependencyIndex := dependency.toNat
        if dependencyIndex >= segmentStart then
          unless dependencyIndex < values.size do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: expression crosses an effect boundary"
          stack := stack.push dependencyIndex
        else if dependencyIndex >= blockEntry then
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: expression crosses an effect boundary"
  unless visitedCount == segmentCount do
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: dead or reordered value instructions"
  pure ()

private def appendResultValueV1
    (expectedTypeId : TypeIdV1)
    (values : Array LoweredValueV1)
    (result : ValueDefV1)
    (value : LoweredValueV1) : CompileResult (Array LoweredValueV1) := do
  unless result.valueId.toNat == values.size && result.typeId == expectedTypeId do
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: result ValueId/type is not canonical for its kind"
  if values.size >= maxPlanNodes then
    throw <| .planInvariant .ton s!"Ton value table exceeds node limit {maxPlanNodes}"
  pure (values.push value)

private inductive SemanticCallableModeV1 where
  | initialize
  | mutate
  | view
  | pureFn
  deriving BEq

/-- PureFn signature environment used while lowering: `byCallable[callableId]`
    is `some fnIndex` for pureFn callables; `sigs` is indexed by fnIndex. -/
private structure TonFnSigV1 where
  paramCount : Nat
  resultKind : TonValueKindV1
  deriving BEq, Inhabited

private structure TonFnEnvV1 where
  byCallable : Array (Option Nat)
  sigs : Array TonFnSigV1
  deriving Inhabited

private def emptyTonFnEnvV1 : TonFnEnvV1 := { byCallable := #[], sigs := #[] }

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
    (resultKind : TonValueKindV1)
    (argIds : Array ValueIdV1)
    (args : Array LoweredValueV1) : CompileResult LoweredValueV1 := do
  let mut depth : Nat := 1
  let mut expanded : Nat := 1
  for arg in args do
    unless arg.kind == .uint64 || arg.kind == .int64 do
      throw <| .planInvariant .ton
        "unsupported Ton semantic shape: pureCall arguments must be UInt64 or Int64"
    depth := max depth (1 + arg.depth)
    if expanded > maxPlanNodes - arg.expandedNodes then
      throw <| .planInvariant .ton s!"Ton plan expression exceeds node limit {maxPlanNodes}"
    expanded := expanded + arg.expandedNodes
  if depth > maxExprDepth then
    throw <| .planInvariant .ton s!"Ton plan expression exceeds depth {maxExprDepth}"
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
    (types : TonTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (layout : StorageLayout)
    (fnEnv : TonFnEnvV1)
    (_stableCount : Nat)
    (armReadables0 : Array ValueIdV1)
    (block : BlockV1)
    (values0 : Array LoweredValueV1) : CompileResult LoweredBlockV1 := do
  -- Block params are admitted only as pre-materialized loop induction slots
  -- (filled by the region walker before entering a header). Empty is the
  -- non-loop case; non-empty without a prior materialization fails closed.
  for p in block.params do
    let some slot := values0[p.valueId.toNat]? |
      throw <| .planInvariant .ton
        "unsupported Ton semantic shape: block parameter ValueId is out of range"
    match slot.expr with
    | .localTemp _ =>
        unless slot.kind == .uint64 && types.isUInt64 p.typeId do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: loop induction must be public UInt64"
    | _ =>
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: block parameters are not supported outside loop headers"
  if block.instructions.size > maxBodyStatements then
    throw <| .planInvariant .ton
      s!"{owner} instruction count exceeds profile limit {maxBodyStatements}"
  let mut values := values0
  let blockEntry := values0.size
  let mut segmentStart := values0.size
  let mut armReadables := armReadables0
  let mut body : Array Statement := #[]
  for instruction in block.instructions do
    match instruction.op, instruction.result with
    | .constant constantId, some result =>
        let some typeId := layout.constantTypeIds[constantId.toNat]? |
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: Constant references an unknown constant id"
        let some kindTag := layout.constantKinds[constantId.toNat]? |
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: Constant kind table is incomplete"
        let some value := layout.constantValues[constantId.toNat]? |
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: Constant value table is incomplete"
        unless result.typeId == typeId do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: Constant result typeId must match the declaration"
        let kind ← match tonConstantKindOfTagV1 kindTag with
          | some k => pure k
          | none =>
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: Constant kind tag is corrupt"
        values := ← appendResultValueV1 typeId values result {
          expr := .literal value
          kind
          depth := 1
          expandedNodes := 1
          dependencies := #[]
        }
    | .literal typeId bytes, some result =>
        if let some bitWidth := types.intWidthOf typeId then
          unless isAbiIntWidth bitWidth do
            throw <| .planInvariant .ton
              s!"unsupported Ton semantic shape: Int{bitWidth} literal is not admitted"
          let kind ← match intKindOfWidthV1 bitWidth with
            | some k => pure k
            | none =>
                throw <| .planInvariant .ton
                  s!"unsupported Ton semantic shape: Int{bitWidth} literal is not admitted"
          let value ← decodeIntWidthLiteralLe tonPlanErr "Ton" bitWidth bytes
          values := ← appendResultValueV1 typeId values result {
            expr := .literal value
            kind
            depth := 1
            expandedNodes := 1
            dependencies := #[]
          }
        else if let some bitWidth := types.uintWidthOf typeId then
          unless isTonBodyUintWidth bitWidth do
            throw <| .planInvariant .ton
              s!"unsupported Ton semantic shape: UInt{bitWidth} literal is not admitted"
          let kind ← match uintKindOfWidthV1 bitWidth with
            | some k => pure k
            | none =>
                throw <| .planInvariant .ton
                  s!"unsupported Ton semantic shape: UInt{bitWidth} literal is not admitted"
          if bitWidth ≤ 64 then
            let value ← decodeUIntWidthLiteralLe tonPlanErr "Ton" bitWidth bytes
            values := ← appendResultValueV1 typeId values result {
              expr := .literal value
              kind
              depth := 1
              expandedNodes := 1
              dependencies := #[]
            }
          else
            let n ← decodeUIntWideLiteralLe tonPlanErr "Ton" bitWidth bytes
            values := ← appendResultValueV1 typeId values result {
              expr := .bigLiteral bitWidth n
              kind
              depth := 1
              expandedNodes := 1
              dependencies := #[]
            }
        else if types.isPrincipal typeId || types.isString typeId then
          let leafExprs ← decodePrincipalLiteralLeavesV1 bytes
          let value := mkAggregateValueV1 leafExprs #[] 1 leafExprs.size
          values := ← appendResultValueV1 typeId values result value
        else
          let boolTypeId ← match types.boolTypeId with
            | some tid =>
                unless typeId == tid do
                  throw <| .planInvariant .ton
                    "unsupported Ton semantic shape: literal is not admitted UInt width, Int{8,16,32,64}, Bool, Principal, or String"
                pure tid
            | none =>
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: Bool type is missing for Bool literal"
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
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: pureFn cannot load state"
        let leafIdxs ← match layout.stateLeaves[stateId.toNat]? with
          | some ls => pure ls
          | none =>
              -- Legacy 1:1 without stateLeaves: physical index == stateId.
              pure #[stateId.toNat]
        if types.isContainer result.typeId then
          let some (n, leafByteWidth, _) ←
            containerLeafLayoutV1 typeDecls types result.typeId |
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: container state load is not Array/Map/Bytes UInt64"
          unless leafIdxs.size == n do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: Array/Map/Bytes state load leaf count mismatch"
          let mut leafExprs : Array Expr := #[]
          for fi in leafIdxs do
            -- Array/Map 8-byte leaves stay historical `stateLoad` (Int64
            -- signedness is on the layout/ABI `isInt` bit, not a second load
            -- opcode). Bytes leaves are 1-byte UInt8 loads (zero-extended
            -- `narrowStateLoad 8`). Array UInt128 leaves are one 16-byte
            -- cell each (`narrowStateLoad 128`), not the Bytes 8-bit path
            -- and not two UInt64 limbs.
            leafExprs := leafExprs.push
              (if leafByteWidth == 8 then .stateLoad fi
                else .narrowStateLoad (leafByteWidth * 8) fi)
          let value := mkAggregateValueV1 leafExprs #[] 1 leafExprs.size
            (leafByteWidth := leafByteWidth)
          values := ← appendResultValueV1 result.typeId values result value
        else if types.isPrincipal result.typeId || types.isString result.typeId then
          unless leafIdxs.size == nearPrincipalDataWordCountV1 + 1 do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: Principal/String state load leaf count mismatch"
          let mut leafExprs : Array Expr := #[]
          for fi in leafIdxs do
            leafExprs := leafExprs.push (.stateLoad fi)
          let value := mkAggregateValueV1 leafExprs #[] 1 leafExprs.size
          values := ← appendResultValueV1 result.typeId values result value
        else if types.isNamedAggregate result.typeId then
          let n ← leafCountOfTypeV1 typeDecls types result.typeId
          unless leafIdxs.size == n do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: named Struct/Enum state load leaf count mismatch"
          let mut leafExprs : Array Expr := #[]
          for fi in leafIdxs do
            leafExprs := leafExprs.push (.stateLoad fi)
          let value := mkAggregateValueV1 leafExprs #[] 1 leafExprs.size
          values := ← appendResultValueV1 result.typeId values result value
        else if isAnonymousOptionTypeIdV1 typeDecls result.typeId then
          -- B-OPT-STATE: Option UInt64 / Int64 / UInt128 state load →
          -- 2-leaf aggregate (tag unsigned uint64; payload signed only
          -- for Int64; UInt128 payload is one `narrowStateLoad 128`).
          let (payloadByteWidth, _) ←
            requireOptionUInt64StateV1 typeDecls types result.typeId "load"
          unless leafIdxs.size == 2 do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: Option state load leaf count mismatch"
          let mut leafExprs : Array Expr := #[]
          for i in [0:leafIdxs.size] do
            let some fi := leafIdxs[i]? |
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: Option state load leaf missing"
            leafExprs := leafExprs.push
              (if i == 1 && payloadByteWidth == 16 then
                .narrowStateLoad 128 fi
              else
                .stateLoad fi)
          let value := mkAggregateValueV1 leafExprs #[] 1 leafExprs.size
          values := ← appendResultValueV1 result.typeId values result value
        else
          let fi ← match leafIdxs[0]? with
            | some i =>
                unless leafIdxs.size == 1 do
                  throw <| .planInvariant .ton
                    "unsupported Ton semantic shape: scalar state load saw multi-leaf layout"
                pure i
            | none =>
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: state load has no leaf fields"
          let field ← match layout.fields[fi]? with
            | some f => pure f
            | none =>
                throw <| .planInvariant .ton
                  s!"unsupported Ton semantic shape: state field {fi} missing"
          let isInt := (types.intWidthOf result.typeId).isSome
          let bitWidth ←
            if isInt then
              match types.intWidthOf result.typeId with
              | some w =>
                  unless isAbiIntWidth w do
                    throw <| .planInvariant .ton
                      s!"unsupported Ton semantic shape: state load Int{w} is not admitted"
                  pure w
              | none =>
                  throw <| .planInvariant .ton
                    "unsupported Ton semantic shape: state load Int width is missing"
            else match types.uintWidthOf result.typeId with
              | some w =>
                  unless isTonAbiUintWidth w do
                    throw <| .planInvariant .ton
                      s!"unsupported Ton semantic shape: state load UInt{w} is not admitted"
                  pure w
              | none =>
                  throw <| .planInvariant .ton
                    "unsupported Ton semantic shape: state load must be UInt{8,16,32,64,128,256}, Int{8,16,32,64}, Principal, named Struct/Enum, Array/Map, or Option UInt64"
          unless field.byteWidth == byteWidthOfBitWidth bitWidth do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: state load width does not match field layout"
          unless field.isInt == isInt do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: state load signedness does not match field layout"
          let kind ←
            if isInt then
              match intKindOfWidthV1 bitWidth with
              | some k => pure k
              | none =>
                  throw <| .planInvariant .ton
                    s!"unsupported Ton semantic shape: state load Int{bitWidth} is not admitted"
            else match uintKindOfWidthV1 bitWidth with
              | some k => pure k
              | none =>
                  throw <| .planInvariant .ton
                    s!"unsupported Ton semantic shape: state load UInt{bitWidth} is not admitted"
          values := ← appendResultValueV1 result.typeId values result {
            -- Narrow ABI loads retain semantic width for body arithmetic;
            -- signed cell fields use Tolk `intN` at emit (field.isInt).
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
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: aggregate comparison only supports == / !="
              let boolTypeId ← match types.boolTypeId with
                | some tid => pure tid
                | none =>
                    throw <| .planInvariant .ton
                      "unsupported Ton semantic shape: Bool type is missing for aggregate comparison"
              unless result.typeId == boolTypeId do
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: aggregate comparison result must be Bool"
              unless lhs.isAggregate && rhs.isAggregate do
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: aggregate comparison requires both operands aggregate"
              let le := lhs.leafExprs
              let re := rhs.leafExprs
              unless le.size == re.size && le.size > 0 do
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: aggregate comparison leaf count mismatch"
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
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: binary ops on aggregate operands only support == / !="
        else if op == .and || op == .or then
          let boolTypeId ← match types.boolTypeId with
            | some tid => pure tid
            | none =>
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: Bool type is missing for logical op"
          unless result.typeId == boolTypeId do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: logical result must be Bool"
          let value ←
            if op == .and then makeBoolAndValueV1 lhsId rhsId lhs rhs
            else makeBoolOrValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 boolTypeId values result value
        else if op == .shl || op == .shr then
          -- Shifts: admitted body UInt/Int64 operand, UInt32 count; result matches lhs.
          unless (widthOfUintKindV1 lhs.kind).isSome || lhs.kind == .int64 do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: shift operand must be admitted integer width"
          unless rhs.kind == .uint32 do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: shift count must be UInt32"
          if lhs.kind == .int64 then
            let resultTid ← match types.int64TypeId with
              | some tid =>
                  unless result.typeId == tid do
                    throw <| .planInvariant .ton
                      "unsupported Ton semantic shape: Int64 shift result type mismatch"
                  pure tid
              | none => throw (.planInvariant .ton
                  "unsupported Ton semantic shape: Int64 type is missing for shift")
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
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: shift result width mismatch"
            -- UInt128 shifts stay fail closed: TVM int257 can hold the
            -- value, but a 64-count-only shift would silently drop bits
            -- above the historical UInt64 envelope.
            if bitWidth > 64 then
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: multiword shift is fail-closed on Ton (shift counts < 64 only; wide shift not implemented)"
            let value ←
              if op == .shl then makeShlValueV1 kind bitWidth lhsId rhsId lhs rhs
              else makeShrValueV1 kind bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        else
          -- Body multi-width UInt arithmetic / bitwise / comparison, or
          -- signed Int{8,16,32,64}. Bitwise/shift/neg on narrow Int stay FC.
          unless lhs.kind != .bool && rhs.kind != .bool do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: binary operands must be integer"
          unless (widthOfIntKindV1 lhs.kind).isSome == (widthOfIntKindV1 rhs.kind).isSome do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: binary operands must share signedness"
          if let some bitWidth := widthOfIntKindV1 lhs.kind then
            unless lhs.kind == rhs.kind do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: binary operands must share signed Int width"
            unless isAbiIntWidth bitWidth do
              throw <| .planInvariant .ton
                s!"unsupported Ton semantic shape: Int{bitWidth} is not an admitted body width"
            if op == .add || op == .sub || op == .mul || op == .div || op == .mod then
              let wordTid ← match types.intWidthOf result.typeId with
                | some w =>
                    unless w == bitWidth do
                      throw <| .planInvariant .ton
                        "unsupported Ton semantic shape: arithmetic result width mismatch"
                    pure result.typeId
                | none => throw (.planInvariant .ton
                    "unsupported Ton semantic shape: Int type is missing")
              let value ←
                if op == .add then
                  makeBinaryTreeValueKindsV1 (mkSignedCheckedAdd bitWidth)
                    lhs.kind lhs.kind lhs.kind lhsId rhsId lhs rhs
                else if op == .sub then
                  makeBinaryTreeValueKindsV1 (mkSignedCheckedSub bitWidth)
                    lhs.kind lhs.kind lhs.kind lhsId rhsId lhs rhs
                else if op == .mul then
                  makeBinaryTreeValueKindsV1 (mkSignedCheckedMul bitWidth)
                    lhs.kind lhs.kind lhs.kind lhsId rhsId lhs rhs
                else if op == .div then
                  makeBinaryTreeValueKindsV1 (mkSignedCheckedDiv bitWidth)
                    lhs.kind lhs.kind lhs.kind lhsId rhsId lhs rhs
                else
                  makeBinaryTreeValueKindsV1 (mkSignedCheckedMod bitWidth)
                    lhs.kind lhs.kind lhs.kind lhsId rhsId lhs rhs
              values := ← appendResultValueV1 wordTid values result value
            else if op == .bitAnd || op == .bitOr || op == .bitXor then
              unless bitWidth == 64 do
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: bitwise on narrow Int fail closed"
              let wordTid ← match types.intWidthOf result.typeId with
                | some 64 => pure result.typeId
                | some _ =>
                    throw <| .planInvariant .ton
                      "unsupported Ton semantic shape: bitwise result width mismatch"
                | none => throw (.planInvariant .ton
                    "unsupported Ton semantic shape: Int type is missing")
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
                        throw <| .planInvariant .ton
                          "unsupported Ton semantic shape: Bool type is missing for comparison"
                  unless result.typeId == boolTypeId do
                    throw <| .planInvariant .ton
                      "unsupported Ton semantic shape: comparison result must be Bool"
                  let value ← makeBinaryTreeValueKindsV1 (fun l r => .signedCompare cmpOp l r)
                    lhs.kind lhs.kind .bool lhsId rhsId lhs rhs
                  values := ← appendResultValueV1 boolTypeId values result value
              | none =>
                  throw <| .planInvariant .ton
                    "unsupported Ton semantic shape: only checked Int{8,16,32,64} arith and comparisons are supported (bitwise/shift/neg on narrow Int fail closed)"
          else
            -- Unsigned body multi-width path (UInt8/16/32/64/128/256).
            -- add/sub/mul/div/mod admit UInt128/256 via narrowChecked* +
            -- int257 width guard (one temp, not multi-limb). bitAnd/bitOr/
            -- bitXor stay fail closed above 64 (same class as shift >64).
            unless lhs.kind == rhs.kind do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: binary operands must share admitted UInt width"
            let some bitWidth := widthOfUintKindV1 lhs.kind |
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: binary operands must be admitted UInt width"
            unless isTonBodyUintWidth bitWidth do
              throw <| .planInvariant .ton
                s!"unsupported Ton semantic shape: UInt{bitWidth} is not an admitted body width"
            if op == .add || op == .sub || op == .mul || op == .div || op == .mod then
              -- UInt128/256 are one int257 temp + representable width guard
              -- (`1 << 128` for 128; nonnegative-only for 256).
              let (widthTid, kind, w) ← admitUIntWidthResultTypeV1 types result.typeId
              unless kind == lhs.kind && w == bitWidth do
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: arithmetic result width mismatch"
              let value ←
                if op == .add then makeCheckedAddValueV1 kind w lhsId rhsId lhs rhs
                else if op == .sub then makeCheckedSubValueV1 kind w lhsId rhsId lhs rhs
                else if op == .mul then makeCheckedMulValueV1 kind w lhsId rhsId lhs rhs
                else if op == .div then makeCheckedDivValueV1 kind w lhsId rhsId lhs rhs
                else makeCheckedModValueV1 kind w lhsId rhsId lhs rhs
              values := ← appendResultValueV1 widthTid values result value
            else if op == .bitAnd || op == .bitOr || op == .bitXor then
              if bitWidth > 64 then
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: multiword bitwise is fail-closed on Ton (UInt128 bitwise not implemented)"
              let (widthTid, kind, w) ← admitUIntWidthResultTypeV1 types result.typeId
              unless kind == lhs.kind && w == bitWidth do
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: bitwise result width mismatch"
              let value ←
                if op == .bitAnd then makeBitAndValueV1 kind w lhsId rhsId lhs rhs
                else if op == .bitOr then makeBitOrValueV1 kind w lhsId rhsId lhs rhs
                else makeBitXorValueV1 kind w lhsId rhsId lhs rhs
              values := ← appendResultValueV1 widthTid values result value
            else
              match comparisonOpOfBinaryV1 op with
              | some cmpOp =>
                  let boolTypeId ← match types.boolTypeId with
                    | some tid => pure tid
                    | none =>
                        throw <| .planInvariant .ton
                          "unsupported Ton semantic shape: Bool type is missing for comparison"
                  unless result.typeId == boolTypeId do
                    throw <| .planInvariant .ton
                      "unsupported Ton semantic shape: comparison result must be Bool"
                  let value ← makeCompareValueV1 cmpOp lhsId rhsId lhs rhs
                  values := ← appendResultValueV1 boolTypeId values result value
              | none =>
                  throw <| .planInvariant .ton
                    "unsupported Ton semantic shape: only checked multi-width UInt arith/bitwise, shift, Bool logical, and comparisons are supported"
    | .unary op operandId, some result =>
        let operand ← currentValueWithArmsV1 values blockEntry segmentStart armReadables operandId
        match op with
        | .bitNot =>
            if operand.kind == .int64 then
              let wordTid ← match types.intWidthOf result.typeId with
              | some _ => pure result.typeId
              | none => throw (.planInvariant .ton
                  "unsupported Ton semantic shape: Int type is missing")
              unless result.typeId == wordTid do
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: bitNot result type mismatch"
              let value ← makeBitNotValueV1 .int64 64 operandId operand
              values := ← appendResultValueV1 wordTid values result value
            else
              let some bitWidth := widthOfUintKindV1 operand.kind |
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: bitNot operand must be admitted integer width"
              if bitWidth > 64 then
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: multiword bitwise is fail-closed on Ton (UInt128 bitNot not implemented)"
              let (widthTid, kind, w) ← admitUIntWidthResultTypeV1 types result.typeId
              unless kind == operand.kind && w == bitWidth do
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: bitNot result width mismatch"
              let value ← makeBitNotValueV1 kind w operandId operand
              values := ← appendResultValueV1 widthTid values result value
        | .not =>
            let boolTypeId ← match types.boolTypeId with
              | some tid => pure tid
              | none =>
                  throw <| .planInvariant .ton
                    "unsupported Ton semantic shape: Bool type is missing for bool not"
            unless result.typeId == boolTypeId do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: bool not result must be Bool"
            let value ← makeBoolNotValueV1 operandId operand
            values := ← appendResultValueV1 boolTypeId values result value
        | .neg =>
            unless operand.kind == .int64 do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: Op.Unary.neg requires Int64"
            let tid ← match types.int64TypeId with
              | some t => pure t
              | none => throw (.planInvariant .ton
                  "unsupported Ton semantic shape: Int64 type is missing for neg")
            unless result.typeId == tid do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: checkedNeg result must be Int64"
            let value ← makeUnaryTreeValueV1 (fun o => .checkedNeg o) .int64 .int64
              operandId operand
            values := ← appendResultValueV1 tid values result value
    | .pureCall callableId argIds, some result =>
        let fnIndex ← match fnEnv.byCallable[callableId.toNat]? with
          | some (some idx) => pure idx
          | _ =>
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: pureCall target is not a declared pureFn"
        let sig ← match fnEnv.sigs[fnIndex]? with
          | some s => pure s
          | none =>
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: pureCall fnIndex is out of range"
        unless argIds.size == sig.paramCount do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: pureCall arity does not match the callee"
        let expectedTypeId ← match sig.resultKind with
          | .uint64 => types.requireUInt64 tonPlanErr "ton"
          | .int64 =>
              match types.int64TypeId with
              | some tid => pure tid
              | none => throw (.planInvariant .ton
                  "unsupported Ton semantic shape: Int64 type is missing for pureCall")
          | .bool =>
              match types.boolTypeId with
              | some tid => pure tid
              | none =>
                  throw <| .planInvariant .ton
                    "unsupported Ton semantic shape: Bool type is missing for pureCall result"
          | .uint32 | .uint16 | .uint8 | .uint128 | .uint256 =>
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: pureCall result cannot be narrow/multiword UInt"
          | .int32 | .int16 | .int8 =>
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: pureCall result cannot be narrow Int"
        unless result.typeId == expectedTypeId do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: pureCall result type does not match the callee"
        let mut argValues : Array LoweredValueV1 := #[]
        for argId in argIds do
          let root ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
          unless !root.isAggregate && (root.kind == .uint64 || root.kind == .int64) do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: pureCall arguments must be UInt64 or Int64"
          argValues := argValues.push root
        -- Pure expression (not an effect boundary): stay inside the segment;
        -- dependencies on the arg roots let later sinks consume the tree.
        let value ← makeCallFnValueV1 fnIndex sig.resultKind argIds argValues
        values := ← appendResultValueV1 expectedTypeId values result value
    | .stateStore stateId valueId, none =>
        if mode == .view then
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: view callable writes state"
        if mode == .pureFn then
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: pureFn cannot store state"
        let leafIdxs ← match layout.stateLeaves[stateId.toNat]? with
          | some ls => pure ls
          | none => pure #[stateId.toNat]
        let root ← currentValueWithArmsV1 values blockEntry segmentStart armReadables valueId
        if root.isAggregate then
          -- Principal / Array / Map / Bytes / named Struct/Enum / Option UInt64
          -- multi-leaf store as one atomic unit. Soft: dual Map stores leave
          -- pure values for a later store (Token). Atomic: all leaf Exprs share
          -- the pre-store KV snapshot at IR lower (store-then-read hazard on
          -- sequential leaves). Option.none zeros both tag and payload.
          let leaves := root.leafExprs
          unless leaves.size == leafIdxs.size do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: aggregate state store leaf count mismatch"
          unless leaves.size > 0 do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: aggregate state store has zero leaves"
          let _ ← currentValueWithArmsV1 values blockEntry segmentStart armReadables valueId
          let mut storeLeaves : Array Store := #[]
          for i in [0:leaves.size] do
            let some fi := leafIdxs[i]? |
              throw <| .planInvariant .ton "aggregate state store field missing"
            let some leafExpr := leaves[i]? |
              throw <| .planInvariant .ton "aggregate state store leaf missing"
            let field ← match layout.fields[fi]? with
              | some f => pure f
              | none =>
                  throw <| .planInvariant .ton
                    s!"unsupported Ton semantic shape: aggregate store field {fi} missing"
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
                  throw <| .planInvariant .ton
                    "unsupported Ton semantic shape: scalar store to multi-leaf state"
                pure i
            | none =>
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: state store has no leaf fields"
          let field ← match layout.fields[fi]? with
            | some f => pure f
            | none =>
                throw <| .planInvariant .ton
                  s!"unsupported Ton semantic shape: state field {fi} missing"
          let expectedBitWidth := bitWidthOfByteWidth field.byteWidth
          -- T8c: store value width must match field layout (narrow body temps OK).
          if let some valueWidth := widthOfIntKindV1 root.kind then
            unless field.isInt do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: Int state store requires a signed field"
            unless valueWidth == expectedBitWidth do
              throw <| .planInvariant .ton
                s!"unsupported Ton semantic shape: Int state store value width {valueWidth} must match field bitWidth {expectedBitWidth}"
            unless isAbiIntWidth valueWidth do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: state store value must be admitted Int width"
          else
            unless !field.isInt do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: unsigned state store requires an unsigned field"
            let some valueWidth := widthOfUintKindV1 root.kind |
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: state store value must be admitted UInt width or Int{8,16,32,64}"
            unless valueWidth == expectedBitWidth do
              throw <| .planInvariant .ton
                s!"unsupported Ton semantic shape: state store value width {valueWidth} must match field bitWidth {expectedBitWidth}"
            unless isTonAbiUintWidth valueWidth do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: state store value must be admitted UInt width or Int{8,16,32,64}"
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
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: assert must use errorId=none and empty args"
        let root ← currentValueWithArmsV1 values blockEntry segmentStart armReadables condId
        unless root.kind == .bool do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: assert condition must be Bool"
        let condition ← consumeCurrentSegmentV1 values blockEntry segmentStart condId
        body := body.push (.assert condition)
        armReadables := promoteDominatingPureV1 blockEntry values armReadables
        segmentStart := values.size
    | .emit _effectId eventId argIds, none =>
        if mode == .view then
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: view callable emits an event"
        if mode == .pureFn then
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: pureFn cannot emit events"
        let mut argExprs : Array Expr := #[]
        for argId in argIds do
          let root ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
          unless root.kind == .uint64 do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: event arguments must be UInt64"
          argExprs := argExprs.push root.expr
        -- Multi-root effect boundary: every value produced in the current
        -- segment must be reachable from at least one argument tree.
        let _ ← consumeSegmentRootsV1 values blockEntry segmentStart argIds
        body := body.push (.emitEvent eventId.toNat argExprs)
        armReadables := promoteDominatingPureV1 blockEntry values armReadables
        segmentStart := values.size
    | .externalCall _effectId callee argIds, some result =>
        -- CAP-5: exact `pf.crypto.sha256` UInt256→UInt256 is a host SHA-256
        -- leaf (Tolk `bitsHash` / TVM `SHA256U`), not a sync call. keccak256
        -- and siblings stay named FC. Generic result-bearing CALL stays
        -- outside the envelope.
        let components := callee.components.toArray
        let qn := String.intercalate "." components.toList
        if isPfCryptoSha256CalleeV1 components then
          if mode == .pureFn then
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: pureFn cannot call pf.crypto.sha256"
          unless argIds.size == 1 && types.uintTypeIdAt 256 == some result.typeId do
            throw <| .planInvariant .ton pfCryptoSha256ArityErrorV1
          let some argId := argIds[0]? |
            throw <| .planInvariant .ton pfCryptoSha256ArityErrorV1
          let root ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
          unless root.kind == .uint256 do
            throw <| .planInvariant .ton pfCryptoSha256ArityErrorV1
          let value ← makeUnaryTreeValueV1 (fun o => .sha256 o) .uint256 .uint256 argId root
          values := ← appendResultValueV1 result.typeId values result value
        else if isPfCryptoCalleeV1 components then
          throw <| .planInvariant .ton (pfCryptoHostBindingErrorV1 qn)
        else
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: result-bearing ExternalCall is outside the Ton envelope"
    | .externalCall _effectId callee _argIds, none =>
        -- Ton has no synchronous cross-contract calls. The S2 resolver already
        -- declines effect.synchronous-call; this is the defensive plan gate.
        -- Void sha256 is not a host-syscall shape (result is required).
        let components := callee.components.toArray
        let qn := String.intercalate "." components.toList
        if isPfCryptoSha256CalleeV1 components then
          throw <| .planInvariant .ton pfCryptoSha256ArityErrorV1
        if isPfCryptoCalleeV1 components then
          throw <| .planInvariant .ton (pfCryptoHostBindingErrorV1 qn)
        throw <| .planInvariant .ton
          "call/sync external call is outside the Ton MVP envelope (TON has no synchronous cross-contract return; use schedule/callback)"
    | .schedule _effectId callee argIds, none =>
        -- schedule → async internal out-message (createMessage + send).
        -- See Statement.promiseAccount docstring for bounce/send-mode/value
        -- and destination-hash stub decisions.
        if mode == .view then
          throw <| .planInvariant .ton
            (nearScheduleDisallowedError "view callable schedules a workflow")
        if mode == .pureFn then
          throw <| .planInvariant .ton
            (nearScheduleDisallowedError "pureFn cannot schedule workflows")
        let components := callee.components.toArray
        if isPfCryptoCalleeV1 components then
          throw <| .planInvariant .ton pfCryptoScheduleErrorV1
        unless components.size ≥ 2 do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: schedule callee must have at least two components"
        let targetParts := components.extract 0 (components.size - 1)
        let receiver := String.intercalate "." targetParts.toList
        unless isNearAccountId receiver do
          throw <| .planInvariant .ton (nearAccountIdError receiver)
        let method := components[components.size - 1]!
        unless isIdentifier method do
          throw <| .planInvariant .ton
            s!"schedule method '{method}' is not a safe identifier"
        let mut argExprs : Array Expr := #[]
        for argId in argIds do
          let root ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
          unless root.kind == .uint64 do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: schedule arguments must be UInt64"
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
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: construct result typeId must match op typeId"
        match ← containerLeafLayoutV1 typeDecls types typeId with
        | some (n, leafByteWidth, leafIsInt) => do
            -- Bytes (leafByteWidth=1) stay FC. Allow 8 (UInt64/Int64/Map)
            -- and 16 (Array UInt128 only).
            unless leafByteWidth == 8 || leafByteWidth == 16 do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: Bytes construct is outside the Ton pilot (Bytes values enter via state/params only)"
            unless ctorIdx == 0 do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: Array/Map construct ctorIdx must be 0"
            -- N-MAP-CONSTRUCT: nonempty Map construct (flattened kv pairs) is
            -- outside the Ton pilot; product maps are built via IndexSet.
            let isMapConstruct := match typeDecls[typeId.toNat]? with
              | some { shape := .map _ _, .. } => true
              | _ => false
            if isMapConstruct && !argIds.isEmpty then
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: nonempty Map construct is outside the Ton pilot (build maps via IndexSet upsert)"
            if n == nearMapPilotLeafCountV1 && argIds.isEmpty then
              let mut zeros : Array Expr := #[]
              for _ in [0:n] do
                zeros := zeros.push (.literal 0)
              let value := mkAggregateValueV1 zeros #[] 1 n
              values := ← appendResultValueV1 result.typeId values result value
            else do
              unless argIds.size == n do
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: Array construct arity mismatch"
              let mut leafExprs : Array Expr := #[]
              let mut deps : Array ValueIdV1 := #[]
              let mut depth : Nat := 1
              let mut nodes : Nat := 0
              let wantKind :=
                if leafByteWidth == 16 then TonValueKindV1.uint128
                else if leafIsInt then TonValueKindV1.int64
                else .uint64
              let wantKindName :=
                match wantKind with
                | .uint128 => "UInt128"
                | .int64 => "Int64"
                | _ => "UInt64"
              for argId in argIds do
                let arg ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
                unless !arg.isAggregate && arg.kind == wantKind do
                  throw <| .planInvariant .ton
                    s!"unsupported Ton semantic shape: Array construct args must be scalar {wantKindName} matching the array element"
                leafExprs := leafExprs.push arg.expr
                deps := deps.push argId
                depth := Nat.max depth (arg.depth + 1)
                nodes := nodes + arg.expandedNodes
              let value := mkAggregateValueV1 leafExprs deps depth (nodes + n)
                (leafByteWidth := leafByteWidth)
              values := ← appendResultValueV1 result.typeId values result value
        | none => do
            -- Option UInt64/Int64/UInt128 construct (none/some) for
            -- B-OPT-STATE storage and UInt64 anonymous-result returns;
            -- named Struct/Enum construct remains the other non-container
            -- path. Option UInt128/Int64 return stays UInt64-only in
            -- `anonymousReturnLeafAbiV1`.
            match typeDecls[typeId.toNat]? with
            | some { shape := .option elTid, name := none, .. } => do
                unless types.isUInt64 elTid ||
                    types.int64TypeId == some elTid ||
                    types.uintTypeIdAt 128 == some elTid do
                  throw <| .planInvariant .ton
                    "unsupported Ton semantic shape: Option construct requires UInt64 payload"
                let wantKind :=
                  if types.int64TypeId == some elTid then
                    TonValueKindV1.int64
                  else if types.uintTypeIdAt 128 == some elTid then
                    TonValueKindV1.uint128
                  else
                    TonValueKindV1.uint64
                match ctorIdx.toNat with
                | 0 =>
                    -- Option.none → (tag=0, payload=0)
                    unless argIds.isEmpty do
                      throw <| .planInvariant .ton
                        "unsupported Ton semantic shape: Option.none construct takes no args"
                    let leaves : Array Expr := #[.literal 0, .literal 0]
                    let value := mkAggregateValueV1 leaves #[] 1 2
                    values := ← appendResultValueV1 result.typeId values result value
                | 1 =>
                    -- Option.some(v) → (tag=1, payload=v); v is UInt64,
                    -- Int64, or UInt128 matching elTid.
                    unless argIds.size == 1 do
                      throw <| .planInvariant .ton
                        "unsupported Ton semantic shape: Option.some construct takes one arg"
                    let some argId := argIds[0]? |
                      throw <| .planInvariant .ton "Option.some construct arg missing"
                    let arg ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
                    unless !arg.isAggregate && arg.kind == wantKind do
                      throw <| .planInvariant .ton
                        "unsupported Ton semantic shape: Option.some arg must be scalar UInt64, Int64, or UInt128 matching the Option payload"
                    let leaves : Array Expr := #[.literal 1, arg.expr]
                    let value := mkAggregateValueV1 leaves #[argId]
                      (arg.depth + 1) (arg.expandedNodes + 2)
                    values := ← appendResultValueV1 result.typeId values result value
                | _ =>
                    throw <| .planInvariant .ton
                      "unsupported Ton semantic shape: Option construct ctorIdx must be 0 (none) or 1 (some)"
            | _ => do
                unless types.isNamedAggregate typeId do
                  throw <| .planInvariant .ton
                    "unsupported Ton semantic shape: construct admits only Array/Map UInt64, Option UInt64, or named Struct/Enum on Ton"
                let some decl := typeDecls[typeId.toNat]? |
                  throw <| .planInvariant .ton
                    "unsupported Ton semantic shape: construct TypeDecl missing"
                match decl.shape with
                | .struct fields => do
                    unless ctorIdx.toNat == 0 do
                      throw <| .planInvariant .ton
                        "unsupported Ton semantic shape: struct construct ctorIdx must be 0"
                    unless argIds.size == fields.size do
                      throw <| .planInvariant .ton
                        "unsupported Ton semantic shape: struct construct arity mismatch"
                    let mut leaves : Array Expr := #[]
                    let mut deps : Array ValueIdV1 := #[]
                    let mut depth : Nat := 1
                    let mut nodes : Nat := 1
                    for i in [0:argIds.size] do
                      let some argId := argIds[i]? |
                        throw <| .planInvariant .ton "struct construct arg missing"
                      let some field := fields[i]? |
                        throw <| .planInvariant .ton "struct construct field missing"
                      let arg ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
                      let expectedLeaves ← leafCountOfTypeV1 typeDecls types field.typeId
                      let argLeaves := arg.leafExprs
                      unless argLeaves.size == expectedLeaves do
                        throw <| .planInvariant .ton
                          "unsupported Ton semantic shape: struct construct field leaf count mismatch"
                      leaves := leaves ++ argLeaves
                      deps := deps.push argId
                      depth := Nat.max depth (arg.depth + 1)
                      nodes := nodes + arg.expandedNodes
                    let value := mkAggregateValueV1 leaves deps depth nodes
                    values := ← appendResultValueV1 typeId values result value
                | .enum variants => do
                    let vi := ctorIdx.toNat
                    let some variant := variants[vi]? |
                      throw <| .planInvariant .ton
                        "unsupported Ton semantic shape: enum construct variant out of range"
                    unless argIds.size == variant.payloadTypes.size do
                      throw <| .planInvariant .ton
                        "unsupported Ton semantic shape: enum construct arity mismatch"
                    let maxPay ← enumMaxPayloadLeavesV1 typeDecls types variants
                    let mut leaves : Array Expr := #[.literal (UInt64.ofNat vi)]
                    let mut deps : Array ValueIdV1 := #[]
                    let mut depth : Nat := 1
                    let mut nodes : Nat := 1
                    for i in [0:argIds.size] do
                      let some argId := argIds[i]? |
                        throw <| .planInvariant .ton "enum construct arg missing"
                      let some pt := variant.payloadTypes[i]? |
                        throw <| .planInvariant .ton "enum construct payload type missing"
                      let arg ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
                      let expectedLeaves ← leafCountOfTypeV1 typeDecls types pt
                      let argLeaves := arg.leafExprs
                      unless argLeaves.size == expectedLeaves do
                        throw <| .planInvariant .ton
                          "unsupported Ton semantic shape: enum construct payload leaf count mismatch"
                      leaves := leaves ++ argLeaves
                      deps := deps.push argId
                      depth := Nat.max depth (arg.depth + 1)
                      nodes := nodes + arg.expandedNodes
                    while leaves.size < 1 + maxPay do
                      leaves := leaves.push (.literal 0)
                    let value := mkAggregateValueV1 leaves deps depth nodes
                    values := ← appendResultValueV1 typeId values result value
                | _ =>
                    throw <| .planInvariant .ton
                      "unsupported Ton semantic shape: construct requires Struct or Enum shape"
    | .indexGet baseId idxId, some result => do
        let base ← currentValueWithArmsV1 values blockEntry segmentStart armReadables baseId
        unless base.isAggregate do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: IndexGet base must be an Array/Map/Bytes aggregate"
        let idx ← currentValueWithArmsV1 values blockEntry segmentStart armReadables idxId
        if base.leafExprs.size == nearMapPilotLeafCountV1 then
          -- Payload signedness follows Option element TypeId (Map value),
          -- not n==24. Occ/key hit math stays unsigned inside lookup.
          let valIsInt :=
            match typeDecls[result.typeId.toNat]? with
            | some { shape := .option elTid, .. } =>
                types.int64TypeId == some elTid
            | _ => false
          let optLeaves ← mapLookupOptionLeavesV1 base.leafExprs idx.expr valIsInt
          let value := mkAggregateValueV1 optLeaves #[baseId, idxId]
            (Nat.max base.depth idx.depth + 1)
            (base.expandedNodes + idx.expandedNodes + 1)
          values := ← appendResultValueV1 result.typeId values result value
        else do
          let i ← literalIndexNatV1 idx
          let leaves := base.leafExprs
          unless i < leaves.size do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: Array/Bytes IndexGet index out of range"
          let some leaf := leaves[i]? |
            throw <| .planInvariant .ton "Array/Bytes IndexGet leaf missing"
          if base.leafByteWidth == 1 then
            -- Bytes element read → scalar UInt8 (zero-extended i64 temp).
            let u8Tid ← match types.uintTypeIdAt 8 with
              | some t => pure t
              | none => throw (.planInvariant .ton
                  "unsupported Ton semantic shape: UInt8 type is missing for Bytes IndexGet")
            unless result.typeId == u8Tid do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: Bytes IndexGet result must be UInt8"
            values := ← appendResultValueV1 result.typeId values result {
              expr := leaf
              kind := .uint8
              depth := base.depth + 1
              expandedNodes := base.expandedNodes + 1
              dependencies := #[baseId, idxId]
            }
          else if base.leafByteWidth == 16 then
            -- Array UInt128: one 16-byte unsigned cell per element.
            let u128Tid ← match types.uintTypeIdAt 128 with
              | some t => pure t
              | none => throw (.planInvariant .ton
                  "unsupported Ton semantic shape: UInt128 type is missing for Array UInt128 IndexGet")
            unless result.typeId == u128Tid do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: Array IndexGet result must be UInt128"
            values := ← appendResultValueV1 result.typeId values result {
              expr := leaf
              kind := .uint128
              depth := base.depth + 1
              expandedNodes := base.expandedNodes + 1
              dependencies := #[baseId, idxId]
            }
          else
            -- Array 8-byte leaf: UInt64 or Int64. Reject mixed signedness
            -- (Int64 result from a UInt64 array or the reverse).
            let wantInt := types.int64TypeId == some result.typeId
            unless types.isUInt64 result.typeId || wantInt do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: Array IndexGet result must be UInt64 or Int64"
            values := ← appendResultValueV1 result.typeId values result {
              expr := leaf
              kind := if wantInt then .int64 else .uint64
              depth := base.depth + 1
              expandedNodes := base.expandedNodes + 1
              dependencies := #[baseId, idxId]
            }
    | .indexSet baseId idxId valueId, some result => do
        let base ← currentValueWithArmsV1 values blockEntry segmentStart armReadables baseId
        unless base.isAggregate do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: IndexSet base must be an Array/Map/Bytes aggregate"
        unless types.isContainer result.typeId do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: IndexSet result must be Array/Map container"
        let idx ← currentValueWithArmsV1 values blockEntry segmentStart armReadables idxId
        let val ← currentValueWithArmsV1 values blockEntry segmentStart armReadables valueId
        unless !val.isAggregate do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: IndexSet value must be a scalar UInt8/UInt64/UInt128/Int64"
        if base.leafExprs.size == nearMapPilotLeafCountV1 then
          -- Map UInt64 UInt64 keeps unsigned val mux; Map UInt64 Int64
          -- accepts Int64 and muxes only the val slot with signedChecked*
          -- (occ/key stay unsigned). Branch on TypeDecl `.map` valTid,
          -- not n==24 — Array Int64 24 is not a Map.
          let wantInt :=
            match typeDecls[result.typeId.toNat]? with
            | some { shape := .map _ valTid, .. } =>
                types.int64TypeId == some valTid
            | _ => false
          let wantKind := if wantInt then TonValueKindV1.int64 else .uint64
          unless val.kind == wantKind do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: Map IndexSet value must be scalar UInt64 or Int64 matching the map value"
          let (outLeaves0, okInsert) ←
            mapUpsertLeavesV1 base.leafExprs idx.expr val.expr wantInt
          let gate := Expr.checkedDiv (.literal 1) okInsert
          let mut outLeaves : Array Expr := #[]
          for i in [0:outLeaves0.size] do
            let some e := outLeaves0[i]? |
              throw <| .planInvariant .ton "Map IndexSet leaf missing after upsert"
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
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: Array/Bytes IndexSet index out of range"
          if base.leafByteWidth == 1 then
            -- Bytes element write → scalar UInt8; rebuild the aggregate with
            -- the updated leaf so a later store persists it (byte-exact KV).
            unless val.kind == .uint8 do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: Bytes IndexSet value must be scalar UInt8"
            let mut outLeaves : Array Expr := #[]
            for j in [0:leaves.size] do
              if j == i then
                outLeaves := outLeaves.push val.expr
              else
                let some e := leaves[j]? |
                  throw <| .planInvariant .ton "Bytes IndexSet leaf missing"
                outLeaves := outLeaves.push e
            let value := mkAggregateValueV1 outLeaves #[baseId, idxId, valueId]
              (Nat.max base.depth val.depth + 1)
              (base.expandedNodes + val.expandedNodes + 1)
              (leafByteWidth := 1)
            values := ← appendResultValueV1 result.typeId values result value
          else if base.leafByteWidth == 16 then
            -- Array UInt128: one 16-byte unsigned cell per element.
            unless val.kind == .uint128 do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: Array IndexSet value must be scalar UInt128 matching the array element"
            let mut outLeaves : Array Expr := #[]
            for j in [0:leaves.size] do
              if j == i then
                outLeaves := outLeaves.push val.expr
              else
                let some e := leaves[j]? |
                  throw <| .planInvariant .ton "Array IndexSet leaf missing"
                outLeaves := outLeaves.push e
            let value := mkAggregateValueV1 outLeaves #[baseId, idxId, valueId]
              (Nat.max base.depth val.depth + 1)
              (base.expandedNodes + val.expandedNodes + 1)
              (leafByteWidth := 16)
            values := ← appendResultValueV1 result.typeId values result value
          else
            -- Array 8-byte: value kind must match the result Array element.
            -- Do not accept `.uint64` into an Int64 array (or the reverse).
            -- Signedness follows TypeDecl `.array` elTid, never n==24.
            let wantInt :=
              match typeDecls[result.typeId.toNat]? with
              | some { shape := .array elTid _, .. } =>
                  types.int64TypeId == some elTid
              | _ => false
            unless (wantInt && val.kind == .int64) ||
                (!wantInt && val.kind == .uint64) do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: Array IndexSet value must be scalar UInt64 or Int64 matching the array element"
            let mut outLeaves : Array Expr := #[]
            for j in [0:leaves.size] do
              if j == i then
                outLeaves := outLeaves.push val.expr
              else
                let some e := leaves[j]? |
                  throw <| .planInvariant .ton "Array IndexSet leaf missing"
                outLeaves := outLeaves.push e
            let value := mkAggregateValueV1 outLeaves #[baseId, idxId, valueId]
              (Nat.max base.depth val.depth + 1)
              (base.expandedNodes + val.expandedNodes + 1)
            values := ← appendResultValueV1 result.typeId values result value
    | .fieldGet baseId fieldIndex, some result => do
        let base ← currentValueWithArmsV1 values blockEntry segmentStart armReadables baseId
        unless base.isAggregate do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: fieldGet base must be a named aggregate"
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
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: fieldGet could not resolve struct field range"
        unless start + len <= baseLeaves.size do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: fieldGet leaf range out of bounds"
        let mut outLeaves : Array Expr := #[]
        for i in [start:start+len] do
          let some e := baseLeaves[i]? |
            throw <| .planInvariant .ton "fieldGet leaf missing"
          outLeaves := outLeaves.push e
        let value ←
          if types.isNamedAggregate result.typeId then
            pure (mkAggregateValueV1 outLeaves #[baseId]
              (base.depth + 1) (base.expandedNodes + 1))
          else
            let some e0 := outLeaves[0]? |
              throw <| .planInvariant .ton "fieldGet scalar leaf missing"
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
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: fieldSet base must be a named aggregate"
        unless types.isNamedAggregate result.typeId do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: fieldSet result must be named aggregate"
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
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: fieldSet could not resolve struct field range"
        unless start + len <= baseLeaves.size && valLeaves.size == len do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: fieldSet leaf range/value size mismatch"
        let mut outLeaves : Array Expr := #[]
        for i in [0:baseLeaves.size] do
          if i >= start && i < start + len then
            let j := i - start
            let some e := valLeaves[j]? |
              throw <| .planInvariant .ton "fieldSet value leaf missing"
            outLeaves := outLeaves.push e
          else
            let some e := baseLeaves[i]? |
              throw <| .planInvariant .ton "fieldSet base leaf missing"
            outLeaves := outLeaves.push e
        let value := mkAggregateValueV1 outLeaves #[baseId, valueId]
          (Nat.max base.depth val.depth + 1)
          (base.expandedNodes + val.expandedNodes + 1)
        values := ← appendResultValueV1 result.typeId values result value
    | .variantTag baseId, some result => do
        let base ← currentValueWithArmsV1 values blockEntry segmentStart armReadables baseId
        unless base.isAggregate do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: variantTag base must be an aggregate (Enum or Option)"
        let kind ← match types.uintWidthOf result.typeId with
          | some 32 => pure TonValueKindV1.uint32
          | some 64 => pure TonValueKindV1.uint64
          | _ =>
              if types.isUInt64 result.typeId then pure TonValueKindV1.uint64
              else
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: variantTag result must be UInt32"
        let some tagExpr := base.leafExprs[0]? |
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: variantTag aggregate has no tag leaf"
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
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: variantPayload base must be an aggregate (Enum or Option)"
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
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: variantPayload of Option.none is empty"
              else
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: variantPayload could not resolve range"
        let baseLeaves := base.leafExprs
        unless start + len <= baseLeaves.size do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: variantPayload leaf range out of bounds"
        let mut outLeaves : Array Expr := #[]
        for i in [start:start+len] do
          let some e := baseLeaves[i]? |
            throw <| .planInvariant .ton "variantPayload leaf missing"
          outLeaves := outLeaves.push e
        let value ←
          if types.isNamedAggregate result.typeId then
            pure (mkAggregateValueV1 outLeaves #[baseId]
              (base.depth + 1) (base.expandedNodes + 1))
          else
            let some e0 := outLeaves[0]? |
              throw <| .planInvariant .ton "variantPayload scalar leaf missing"
            let kind ←
              if types.isUInt64 result.typeId then pure TonValueKindV1.uint64
              else if types.uintTypeIdAt 128 == some result.typeId then
                -- Option UInt128 payload extract. Do not open UInt128 as
                -- a named-Struct/Enum leaf (those stay UInt64/Int64).
                pure TonValueKindV1.uint128
              else scalarKindOfNamedLeafResultV1 types result.typeId
            pure {
              expr := e0
              kind
              depth := base.depth + 1
              expandedNodes := base.expandedNodes + 1
              dependencies := #[baseId]
            }
        values := ← appendResultValueV1 result.typeId values result value
    -- N5: Commit = identity passthrough; ContextRead admits unixTimeSeconds only.
    | .commit valueId, some result => do
        unless pilotContextPolicyCommitIdentity.admitCommitIdentity do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: Commit is not admitted by pilot context policy"
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
        -- B-CTX-OPEN (TON): `context.unixTimeSeconds` lowers to Tolk
        -- `blockchain.now()` (block unixtime as int, always ≪ 2^64 — no
        -- range guard). See Expr.blockUnixTimeSeconds. `context.caller` /
        -- `context.self` stay fail closed (Principal ≠ TON address).
        -- attachedValue / chainId / blockHeight have no TON host in this
        -- pilot. Unknown keys stay fail closed.
        if key == callerContextKeyV1 then
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: ContextRead (context.caller) is not admitted by pilot context policy (Principal to TON address mapping deferred)"
        if key == selfContextKeyV1 then
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: ContextRead (context.self) is not admitted by pilot context policy (Principal to TON address mapping deferred)"
        if key == blockHeightContextKeyV1 then
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: ContextRead (context.blockHeight) is not admitted (no honest TON block-height binding in pilot)"
        if key == attachedValueContextKeyV1 then
          throw <| .planInvariant .ton
            s!"unsupported Ton semantic shape: ContextRead '{key.value}' has no Ton host binding (attachedValue / msg value stays fail closed)"
        if key == chainIdContextKeyV1 then
          throw <| .planInvariant .ton
            s!"unsupported Ton semantic shape: ContextRead '{key.value}' has no Ton host binding (chainId stays fail closed)"
        unless key == unixTimeSecondsContextKeyV1 do
          throw <| .planInvariant .ton
            s!"unsupported Ton semantic shape: unknown ContextRead key '{key.value}'"
        unless types.isUInt64 result.typeId do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: ContextRead unix-time-seconds result must be UInt64"
        values := ← appendResultValueV1 result.typeId values result {
          expr := .blockUnixTimeSeconds
          kind := .uint64
          depth := 1
          expandedNodes := 1
          dependencies := #[]
        }
    -- SYS-E2: name nativeVaultBalance. Do not open a TON vault host.
    -- token/U128 stay on the generic EnvRead envelope. unixTime ContextRead
    -- above stays admitted (`blockchain.now()`).
    | .envRead key _, some _ =>
        if key == .nativeVaultBalance then
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: envRead nativeVaultBalance has no Ton host binding (pf.assets.native.balanceOfSelf stays fail closed)"
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: EnvRead is not admitted by pilot context policy"
    | _, _ =>
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: instruction op/result is outside the current UInt64 pilot"
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
    (types : TonTypeClosureV1) (callable : CallableV1) : CompileResult Nat := do
  let mut blockParamCount : Nat := 0
  for block in callable.blocks do
    if block.params.isEmpty then
      pure ()
    else
      unless block.params.size == 1 do
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: loop header must carry exactly one block param"
      let some p := block.params[0]? |
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: loop header must carry exactly one block param"
      unless types.isUInt64 p.typeId do
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: loop induction must be public UInt64"
      unless p.valueId.toNat == callable.params.size + blockParamCount do
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: block parameter ValueIds are not canonical"
      unless isLoopHeaderV1 callable.loopBounds block.id.toNat do
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: block parameters require a loopBounds header entry"
      blockParamCount := blockParamCount + 1
  for lb in callable.loopBounds do
    let some header := callable.blocks[lb.header.toNat]? |
      throw <| .planInvariant .ton
        "unsupported Ton semantic shape: loopBounds header is out of range"
    unless header.params.size == 1 do
      throw <| .planInvariant .ton
        "unsupported Ton semantic shape: loopBounds header must have one block param"
    let some latch := callable.blocks[lb.backEdgeFrom.toNat]? |
      throw <| .planInvariant .ton
        "unsupported Ton semantic shape: loopBounds backEdgeFrom is out of range"
    match latch.terminator with
    | .jump target =>
        unless target.blockId == lb.header && target.args.size == 1 do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: loop latch must jump to its header with one arg"
    | _ =>
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: loop latch terminator must be a jump"
    unless lb.maxIterations.toNat ≤ 4096 do
      throw <| .planInvariant .ton
        "unsupported Ton semantic shape: loop maxIterations exceeds the wire ceiling"
  pure blockParamCount

/-- Structured emission of multi-block CFGs: forward diamonds (branch/switch)
    and Normalize loop headers (loopBounds + single induction param). Fuel
    bounds recursion to the block count. `enclosingHeader` is set while walking
    a loop body so a jump back to that header ends the body as a latch.
    Returns (statements, values, nextLocal, continuation). -/
private partial def emitRegionV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (expectedReturn : ExpectedReturnV1)
    (types : TonTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (layout : StorageLayout)
    (fnEnv : TonFnEnvV1)
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
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: CFG region exceeds block bound"
  let block ← match blocks[start]? with
    | some value => pure value
    | none => throw (.planInvariant .ton
        "unsupported Ton semantic shape: region references a missing block")
  unless block.id.toNat == start do
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: block ids are not dense"
  -- Starting emission at a loop header is only valid when the induction slot
  -- was already materialised (nested entry is via the jump-to-header path).
  if isLoopHeaderV1 loopBounds start then
    let some p := block.params[0]? |
      throw <| .planInvariant .ton
        "unsupported Ton semantic shape: loop header missing induction param"
    let some slot := values0[p.valueId.toNat]? |
      throw <| .planInvariant .ton
        "unsupported Ton semantic shape: loop header must be entered via its pre-header jump"
    match slot.expr with
    | .localTemp _ => pure ()
    | _ =>
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: loop header must be entered via its pre-header jump"
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
          throw <| .planInvariant .ton "initializer cannot return a value"
      | .mutate | .view | .pureFn =>
          let root ← currentValueWithArmsV1 values blockEntry segmentStart freeAfter valueId
          match expectedReturn with
          | .none_ =>
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: entry/view/pureFn is missing expected return kind"
          | .scalar expectedKind =>
              if root.isAggregate then
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: multi-leaf aggregate cannot be returned as scalar"
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
                  | .int32 => "Int32"
                  | .int16 => "Int16"
                  | .int8 => "Int8"
                throw <| .planInvariant .ton
                  s!"unsupported Ton semantic shape: return value must be {expectedLabel}"
              let value ← consumeCurrentSegmentV1 values blockEntry segmentStart valueId
              pure (instrs.push (.returnValue value), values, nextLocal0, .closed)
          | .aggregate expectedLeaves =>
              -- B-RET-ABI / N-ANON-RESULT: named Struct/Enum or admitted
              -- anonymous Array/Option view-only (entry FC at makeEntry).
              unless root.isAggregate do
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: aggregate return value must be a multi-leaf aggregate"
              let expectedWidth :=
                expectedLeaves[0]?.map (·.byteWidth) |>.getD 8
              unless expectedLeaves.all (fun l => l.byteWidth == expectedWidth) do
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: aggregate return leaves must share one byteWidth"
              unless root.leafByteWidth == expectedWidth &&
                  (expectedWidth == 8 || expectedWidth == 1) do
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: aggregate return leaves must be 8-byte UInt64/Int64 words or 1-byte Bytes cells"
              let returnedLeaves := root.leafExprs
              unless returnedLeaves.size == expectedLeaves.size do
                throw <| .planInvariant .ton
                  s!"unsupported Ton semantic shape: aggregate return leaf count mismatch (expected {expectedLeaves.size}, got {returnedLeaves.size})"
              let leafIsInt := expectedLeaves.map (·.isInt)
              let _ ← consumeCurrentSegmentV1 values blockEntry segmentStart valueId
              pure (instrs.push (.returnAggregate returnedLeaves leafIsInt),
                values, nextLocal0, .closed)
  | .return_ none =>
      match expectedReturn with
      | .none_ => pure ()
      | .scalar _ | .aggregate _ =>
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: initializer expected-return kind is non-empty"
      unless segmentStart == values.size do
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: block has unconsumed values"
      -- Explicit marker: an early bare `return` inside a branch arm is
      -- otherwise indistinguishable from a fallthrough arm once the join
      -- continuation is emitted after the region.
      pure (instrs.push .returnNone, values, nextLocal0, .closed)
  | .jump target =>
      let targetId := target.blockId.toNat
      -- Latch: jump back to the loop currently being lowered as a body.
      if enclosingHeader == some targetId then
        unless target.args.size == 1 do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: loop latch must carry exactly one induction arg"
        -- Latch args may reference the just-produced increment; do not require
        -- the segment to be empty — the update expr is recovered from args.
        let _ ← currentValueWithArmsV1 values blockEntry segmentStart freeAfter target.args[0]!
        pure (instrs, values, nextLocal0, .latch target.args)
      else if isLoopHeaderV1 loopBounds targetId then
        -- Enter a (possibly nested) bounded for-loop.
        let some lb := findLoopBoundV1 loopBounds targetId |
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: missing loopBounds for loop header"
        unless target.args.size == 1 do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: loop pre-header must jump with one start arg"
        let initRoot ←
          currentValueWithArmsV1 values blockEntry segmentStart freeAfter target.args[0]!
        unless initRoot.kind == .uint64 do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: loop start value must be UInt64"
        let initial := initRoot.expr
        -- Freeze every value produced so far (params, block-param slots,
        -- pre-header lets/arithmetic) as loop-stable for the header/body.
        let loopStable := values.size
        let some header := blocks[targetId]? |
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: loop header block is missing"
        unless header.params.size == 1 do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: loop header must carry exactly one block param"
        let some inductionParam := header.params[0]? |
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: loop header must carry exactly one block param"
        let inductionVid := inductionParam.valueId
        unless inductionVid.toNat < values.size do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: induction ValueId slot was not pre-allocated"
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
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: loop header may not contain effect instructions"
        let loopResult ← match header.terminator with
          | .branch condId thenT elseT => do
              let condRoot ←
                currentValueWithArmsV1 valuesH headerBlockEntry headerSeg freeHeader condId
              unless condRoot.kind == .bool do
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: loop condition must be Bool"
              let cond ← consumeCurrentSegmentV1 valuesH headerBlockEntry headerSeg condId
              unless thenT.args.isEmpty && elseT.args.isEmpty do
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: loop branch targets must carry empty args"
              -- Body region ends at the latch (jump back to this header).
              let (bodyStmts, valuesB, nextLocal2, bodyCont) ←
                emitRegionV1 owner mode expectedReturn types typeDecls layout fnEnv blocks loopBounds
                  loopStable nextLocal1 (some targetId) freeHeader (fuel - 1)
                  thenT.blockId.toNat valuesH
              let updateArgs ← match bodyCont with
                | .latch args => pure args
                | .closed =>
                    throw <| .planInvariant .ton
                      "unsupported Ton semantic shape: loop body closed without a latch (degenerate one-shot loops are out of pilot)"
                | .join _ =>
                    throw <| .planInvariant .ton
                      "unsupported Ton semantic shape: loop body must end at its latch jump"
              unless updateArgs.size == 1 do
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: loop latch must carry exactly one update arg"
              -- Re-derive the update expr from the already-lowered value table
              -- (latch increment is left in valuesB by the body walk).
              let updateRoot ← findValueV1 valuesB updateArgs[0]!
              unless updateRoot.kind == .uint64 do
                throw <| .planInvariant .ton
                  "unsupported Ton semantic shape: loop update must be UInt64"
              let update := updateRoot.expr
              let forStmt : Statement :=
                .forLoop varTemp initial cond update lb.maxIterations.toNat bodyStmts
              -- Continue the enclosing walk at the exit (else target).
              let (rest, valuesE, nextLocal3, exitCont) ←
                emitRegionV1 owner mode expectedReturn types typeDecls layout fnEnv blocks loopBounds
                  loopStable nextLocal2 enclosingHeader freeHeader (fuel - 1)
                  elseT.blockId.toNat valuesB
              pure (instrs ++ #[forStmt] ++ rest, valuesE, nextLocal3, exitCont)
          | _ =>
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: loop header terminator must be a branch"
        pure loopResult
      else
        -- Forward join: no phi / block args in the non-loop pilot.
        unless target.args.isEmpty do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: non-loop jump targets must carry empty args"
        unless segmentStart == values.size do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: block has unconsumed values"
        pure (instrs, values, nextLocal0, .join targetId)
  | .branch condId thenT elseT =>
      let condRoot ← currentValueWithArmsV1 values blockEntry segmentStart freeAfter condId
      unless condRoot.kind == .bool do
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: branch condition must be Bool"
      let cond ← consumeCurrentSegmentV1 values blockEntry segmentStart condId
      let (thenBody, values1, nextLocal1, thenNext) ←
        emitRegionV1 owner mode expectedReturn types typeDecls layout fnEnv blocks loopBounds
          stableCount nextLocal0 enclosingHeader freeAfter (fuel - 1)
          thenT.blockId.toNat values
      -- A latch may only arise on the then-arm of a loop header (handled
      -- above); diamond arms must not latch.
      let thenJoin ← match thenNext with
        | .latch _ =>
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: loop latch outside loop-body walk"
        | .closed => pure (none : Option Nat)
        | .join j => pure (some j)
      match thenJoin with
      | some j =>
          if elseT.blockId.toNat == j then
            let (rest, values2, nextLocal2, next) ←
              emitRegionV1 owner mode expectedReturn types typeDecls layout fnEnv blocks loopBounds
                stableCount nextLocal1 enclosingHeader freeAfter (fuel - 1) j values1
            pure (instrs ++ #[.ifThenElse cond thenBody #[]] ++ rest, values2, nextLocal2, next)
          else
            let (elseBody, values2, nextLocal2, elseNext) ←
              emitRegionV1 owner mode expectedReturn types typeDecls layout fnEnv blocks loopBounds
                stableCount nextLocal1 enclosingHeader freeAfter (fuel - 1)
                elseT.blockId.toNat values1
            let elseJoin ← match elseNext with
              | .latch _ =>
                  throw <| .planInvariant .ton
                    "unsupported Ton semantic shape: loop latch outside loop-body walk"
              | .closed => pure (none : Option Nat)
              | .join j2 => pure (some j2)
            match elseJoin with
            | some j2 =>
                unless j == j2 do
                  throw <| .planInvariant .ton
                    "unsupported Ton semantic shape: branch arms converge on divergent joins"
                let (rest, values3, nextLocal3, next) ←
                  emitRegionV1 owner mode expectedReturn types typeDecls layout fnEnv blocks loopBounds
                    stableCount nextLocal2 enclosingHeader freeAfter (fuel - 1) j values2
                pure (instrs ++ #[.ifThenElse cond thenBody elseBody] ++ rest,
                  values3, nextLocal3, next)
            | none =>
                let (rest, values3, nextLocal3, next) ←
                  emitRegionV1 owner mode expectedReturn types typeDecls layout fnEnv blocks loopBounds
                    stableCount nextLocal2 enclosingHeader freeAfter (fuel - 1) j values2
                pure (instrs ++ #[.ifThenElse cond thenBody elseBody] ++ rest,
                  values3, nextLocal3, next)
      | none =>
          let (elseBody, values2, nextLocal2, elseNext) ←
            emitRegionV1 owner mode expectedReturn types typeDecls layout fnEnv blocks loopBounds
              stableCount nextLocal1 enclosingHeader freeAfter (fuel - 1)
              elseT.blockId.toNat values1
          match elseNext with
          | .latch _ =>
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: loop latch outside loop-body walk"
          | .closed =>
              pure (instrs ++ #[.ifThenElse cond thenBody elseBody], values2, nextLocal2, .closed)
          | .join j =>
              pure (instrs ++ #[.ifThenElse cond thenBody elseBody], values2, nextLocal2, .join j)
  | .switch scrutId cases defaultTarget =>
      let scrutVal ← currentValueWithArmsV1 values blockEntry segmentStart freeAfter scrutId
      let scrut ← consumeCurrentSegmentV1 values blockEntry segmentStart scrutId
      let some defaultT := defaultTarget |
        throw (.planInvariant .ton
          "unsupported Ton semantic shape: switch must carry a default target")
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
          emitRegionV1 owner mode expectedReturn types typeDecls layout fnEnv blocks loopBounds
            stableCount nextLocalA enclosingHeader armFree (fuel - 1)
            switchCase.target.blockId.toNat valuesA
        caseBodies := caseBodies.push (caseValue, body)
        valuesA := values1
        nextLocalA := nextLocal1
        match armNext, joinAcc with
        | .closed, _ => pure ()
        | .latch _, _ =>
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: loop latch outside loop-body walk"
        | .join j, none => joinAcc := some j
        | .join j, some j0 =>
            unless j == j0 do
              throw <| .planInvariant .ton
                "unsupported Ton semantic shape: switch arms converge on divergent joins"
      let (defaultBody, values2, nextLocal2, defaultNext) ←
        emitRegionV1 owner mode expectedReturn types typeDecls layout fnEnv blocks loopBounds
          stableCount nextLocalA enclosingHeader armFree (fuel - 1)
          defaultT.blockId.toNat valuesA
      match defaultNext, joinAcc with
      | .closed, _ => pure ()
      | .latch _, _ =>
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: loop latch outside loop-body walk"
      | .join j, none => joinAcc := some j
      | .join j, some j0 =>
          unless j == j0 do
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: switch arms converge on divergent joins"
      match joinAcc with
      | none =>
          pure (instrs ++ #[.switchOn scrut caseBodies defaultBody], values2, nextLocal2, .closed)
      | some j =>
          let (rest, values3, nextLocal3, next) ←
            emitRegionV1 owner mode expectedReturn types typeDecls layout fnEnv blocks loopBounds
              stableCount nextLocal2 enclosingHeader freeAfter (fuel - 1) j values2
          pure (instrs ++ #[.switchOn scrut caseBodies defaultBody] ++ rest,
            values3, nextLocal3, next)
  | .revert errorId argIds =>
      let mut argExprs : Array Expr := #[]
      for argId in argIds do
        let root ← currentValueWithArmsV1 values blockEntry segmentStart freeAfter argId
        unless root.kind == .uint64 do
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: revert arguments must be UInt64"
        argExprs := argExprs.push root.expr
      let _ ← consumeSegmentRootsV1 values blockEntry segmentStart argIds
      pure (instrs.push (.revertError errorId.toNat argExprs), values, nextLocal0, .closed)
  | .trap _ =>
      throw <| .planInvariant .ton
        "unsupported Ton semantic shape: trap terminators are outside the current pilot"

private def lowerCallableV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (expectedReturn : ExpectedReturnV1)
    (types : TonTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (layout : StorageLayout)
    (fnEnv : TonFnEnvV1)
    (callable : CallableV1) : CompileResult LoweredCallableV1 := do
  unless callable.entryBlock.toNat == 0 && !callable.blocks.isEmpty &&
      callable.invariantSteps.isNone do
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: callable must start at dense entry block 0"
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
    emitRegionV1 owner mode expectedReturn types typeDecls layout fnEnv callable.blocks
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
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: loop latch escaped its body walk"
    | .join j =>
        let (rest, values1, nextLocal1, next1) ←
          emitRegionV1 owner mode expectedReturn types typeDecls layout fnEnv callable.blocks
            callable.loopBounds stableCount0 nextLocal none #[]
            callable.blocks.size j values
        body := body ++ rest
        values := values1
        nextLocal := nextLocal1
        cont := next1
  match cont with
  | .closed => pure ()
  | _ =>
      throw <| .planInvariant .ton
        "unsupported Ton semantic shape: callable does not end in return on all paths"
  if body.size > maxBodyStatements then
    throw <| .planInvariant .ton s!"{owner} body exceeds profile limit {maxBodyStatements}"
  pure { params, body }

private def makeInitializerV1
    (types : TonTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (layout : StorageLayout)
    (fnEnv : TonFnEnvV1)
    (callable : CallableV1) : CompileResult Method := do
  unless callable.name.isNone && callable.result.visibility == .public_ do
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: initializer signature is invalid"
  let unitTypeId ← match types.unitTypeId with
    | some value => pure value
    | none => throw (.planInvariant .ton
        "unsupported Ton semantic shape: initializer Unit type is missing")
  unless callable.result.typeId == unitTypeId do
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: initializer result is not Unit"
  let lowered ←
    lowerCallableV1 "initializer" .initialize .none_ types typeDecls layout fnEnv callable
  pure {
    name := "init"
    params := lowered.params
    exactInputLen := exactInputLenOfParams lowered.params
    mode := .initialize
    depositPolicy := .requireZero
    resultKind := .unit
    body := lowered.body
  }

private def makeEntryV1
    (types : TonTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (layout : StorageLayout)
    (fnEnv : TonFnEnvV1)
    (callable : CallableV1) : CompileResult Method := do
  let name ← match callable.name with
    | some value => pure value
    | none => throw (.planInvariant .ton
        "unsupported Ton semantic shape: named entry is missing its name")
  unless isIdentifier name do
    throw <| .planInvariant .ton s!"entry name '{name}' is not a safe identifier"
  unless callable.result.visibility == .public_ do
    throw <| .planInvariant .ton s!"entry '{name}' does not return a public result"
  let semanticMode : SemanticCallableModeV1 ← match callable.kind with
    | .entry => pure .mutate
    | .view => pure .view
    | _ => throw (.planInvariant .ton
        "unsupported Ton semantic shape: callable is not an entry or view")
  -- B-RET-ABI / N-ANON-RESULT: named Struct/Enum + admitted anonymous
  -- Array UInt64 N / Option UInt64 **view** returns (multi-stack get method).
  -- Entry (mutate) aggregate stays fail closed — TON async actors have no
  -- return channel on internal messages. Map/Bytes/nested/narrow-element
  -- anonymous returns fail closed in aggregateResultKindOfV1 with precise
  -- messages.
  let (resultKind, expectedReturn) ←
    if isAggregateResultCandidateV1 typeDecls types callable.result.typeId then
      match semanticMode with
      | .view => do
          let kind ←
            aggregateResultKindOfV1 typeDecls types s!"view '{name}'" callable.result.typeId
          match kind with
          | .aggregate leaves => pure (kind, ExpectedReturnV1.aggregate leaves)
          | _ =>
              throw <| .planInvariant .ton
                s!"view '{name}' aggregate result kind resolution failed"
      | .mutate =>
          throw <| .planInvariant .ton
            s!"unsupported Ton semantic shape: entry '{name}' cannot return multi-leaf aggregate (TON async actor has no return channel; B-RET-ABI admits view-only named Struct/Enum and anonymous Array/Option)"
      | _ =>
          throw <| .planInvariant .ton
            s!"unsupported Ton semantic shape: entry '{name}' cannot return multi-leaf aggregate"
    else
      -- BL-14: scalar ABI is UInt{8,16,32,64,128,256} / Bool / Int{8,16,32,64}
      -- (Int128/256 FC).
      match types.uintWidthOf callable.result.typeId with
      | some 8 => pure (MethodResultKind.uint8, ExpectedReturnV1.scalar .uint8)
      | some 16 => pure (MethodResultKind.uint16, ExpectedReturnV1.scalar .uint16)
      | some 32 => pure (MethodResultKind.uint32, ExpectedReturnV1.scalar .uint32)
      | some 64 => pure (MethodResultKind.uint64, ExpectedReturnV1.scalar .uint64)
      | some 128 => pure (MethodResultKind.uint128, ExpectedReturnV1.scalar .uint128)
      | some 256 => pure (MethodResultKind.uint256, ExpectedReturnV1.scalar .uint256)
      | some w =>
          throw <| .planInvariant .ton
            s!"entry '{name}' does not return public UInt8/16/32/64/128/256 (UInt{w} fail closed on Ton)"
      | none =>
          match types.intWidthOf callable.result.typeId with
          | some 8 => pure (MethodResultKind.int8, ExpectedReturnV1.scalar .int8)
          | some 16 => pure (MethodResultKind.int16, ExpectedReturnV1.scalar .int16)
          | some 32 => pure (MethodResultKind.int32, ExpectedReturnV1.scalar .int32)
          | some 64 => pure (MethodResultKind.int64, ExpectedReturnV1.scalar .int64)
          | some w =>
              throw <| .planInvariant .ton
                s!"entry '{name}' does not return public Int8/16/32/64 (Int{w} fail closed on Ton)"
          | none =>
            if types.boolTypeId == some callable.result.typeId then
              pure (MethodResultKind.bool, ExpectedReturnV1.scalar .bool)
            else
              throw <| .planInvariant .ton
                s!"entry '{name}' does not return public UInt8/16/32/64/128/256, Int8/16/32/64, Bool, named Struct/Enum view aggregate, or admitted anonymous Array/Option view aggregate"
  let mode : MethodMode := match semanticMode with
    | .mutate => .mutate
    | .view => .view
    | .initialize => .initialize
    | .pureFn => .mutate
  let lowered ←
    lowerCallableV1 s!"entry '{name}'" semanticMode expectedReturn types typeDecls layout fnEnv
      callable
  pure {
    name
    params := lowered.params
    exactInputLen := exactInputLenOfParams lowered.params
    mode
    depositPolicy := if mode == .view then .queryOnly else .requireZero
    resultKind
    body := lowered.body
  }

private def makePureFnV1
    (types : TonTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (layout : StorageLayout)
    (fnEnv : TonFnEnvV1)
    (callable : CallableV1) : CompileResult FnBinding := do
  let name ← match callable.name with
    | some value => pure value
    | none => throw (.planInvariant .ton
        "unsupported Ton semantic shape: pureFn is missing its name")
  unless isIdentifier name do
    throw <| .planInvariant .ton s!"pureFn name '{name}' is not a safe identifier"
  unless callable.result.visibility == .public_ do
    throw <| .planInvariant .ton s!"pureFn '{name}' does not return a public result"
  -- pureFn aggregate returns stay fail closed (B-RET-ABI / N-ANON-RESULT view-only).
  if isAggregateResultCandidateV1 typeDecls types callable.result.typeId ||
      types.isPrincipal callable.result.typeId then
    throw <| .planInvariant .ton
      s!"pureFn '{name}' cannot return a multi-leaf aggregate (B-RET-ABI: pureFn aggregate returns stay fail-closed; view-only named Struct/Enum and anonymous Array/Option)"
  let (resultIsBool, expectedReturn) ←
    if types.isUInt64 callable.result.typeId then
      pure (false, ExpectedReturnV1.scalar .uint64)
    else if types.boolTypeId == some callable.result.typeId then
      pure (true, ExpectedReturnV1.scalar .bool)
    else
      throw <| .planInvariant .ton
        s!"pureFn '{name}' does not return public UInt64 or Bool"
  let lowered ←
    lowerCallableV1 s!"pureFn '{name}'" .pureFn expectedReturn types typeDecls layout fnEnv
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
    | .store _ | .storeAtomic _ | .returnValue _ | .returnAggregate ..
    | .returnNone | .assert _ | .emitEvent .. | .revertError .. => false

def planUsesPromiseV1 (plan : Plan) : Bool :=
  statementsUsePromiseV1 plan.initializer.body ||
    plan.entries.any (fun m => statementsUsePromiseV1 m.body) ||
    plan.fns.any (fun f => statementsUsePromiseV1 f.body)
private def makeInterfaceBindingV1 (label : String) (name : String)
    (fields : Array InterfaceFieldV1) (uint64TypeId : TypeIdV1) :
    CompileResult InterfaceBinding := do
  unless isIdentifier name do
    throw <| .planInvariant .ton
      s!"unsupported Ton semantic shape: {label} name '{name}' is not a safe identifier"
  for field in fields do
    unless field.typeId == uint64TypeId && field.visibility == .public_ do
      throw <| .planInvariant .ton
        s!"unsupported Ton semantic shape: {label} '{name}' fields must be public UInt64"
  pure { name, fieldCount := fields.size }

/-- Build the pureFn index environment from the unified callable table without
    lowering bodies (signatures only). -/
private def buildTonFnEnvV1
    (types : TonTypeClosureV1)
    (callables : Array CallableV1) : CompileResult TonFnEnvV1 := do
  let mut byCallable : Array (Option Nat) := Array.replicate callables.size none
  let mut sigs : Array TonFnSigV1 := #[]
  for callable in callables do
    match callable.kind with
    | .pureFn =>
        let resultKind ←
          if types.isUInt64 callable.result.typeId then
            pure TonValueKindV1.uint64
          else if types.int64TypeId == some callable.result.typeId then
            pure TonValueKindV1.int64
          else if types.boolTypeId == some callable.result.typeId then
            pure TonValueKindV1.bool
          else
            throw <| .planInvariant .ton
              "unsupported Ton semantic shape: pureFn result is not UInt64, Int64, or Bool"
        let fnIndex := sigs.size
        if callable.id.toNat < byCallable.size then
          byCallable := byCallable.set! callable.id.toNat (some fnIndex)
        else
          throw <| .planInvariant .ton
            "unsupported Ton semantic shape: pureFn CallableId is out of range"
        sigs := sigs.push { paramCount := callable.params.size, resultKind }
    | _ => pure ()
  pure { byCallable, sigs }

/-- Ton-private retained SemanticProgramV1 data → target-owned Plan pilot. -/

private def makePlanFromSemanticDataV1
    (source : SemanticProgramDataV1) : CompileResult Plan := do
  if !source.invariants.isEmpty then
    throw <| .planInvariant .ton
      "unsupported Ton semantic shape: constants/invariants are outside the current UInt64 pilot"
  -- init + entries + pureFns share the profile budget (maxEntries each class,
  -- plus one initializer); total still fails closed above 2·maxEntries + 1.
  if source.callables.size > maxEntries + maxEntries + 1 then
    throw <| .planInvariant .ton
      s!"callable count exceeds Ton profile limit {maxEntries + maxEntries + 1}"
  if source.requirements.items.size > Targets.maxRequirementKinds then
    throw <| .planInvariant .ton
      s!"requirement count exceeds canonical limit {Targets.maxRequirementKinds}"
  let types ← validateTonTypeClosureV1 source.types
  let typeDecls := source.types
  let storage0 ← makeStorageLayoutV1 types typeDecls source.logicalState
  let (constTypeIds, constKinds, constValues) ←
    makeTonConstantTableV1 types source.constants
  let storage := {
    storage0 with
      constantTypeIds := constTypeIds
      constantKinds := constKinds
      constantValues := constValues
  }
    let events ← source.events.mapM (fun d => do
    let u64Tid ← types.requireUInt64 tonPlanErr "ton"
    makeInterfaceBindingV1 "event" d.name d.fields u64Tid)
  let errors ← source.errors.mapM (fun d => do
    let u64Tid ← types.requireUInt64 tonPlanErr "ton"
    makeInterfaceBindingV1 "error" d.name d.fields u64Tid)
  let components := source.qualifiedName.components.toArray
  let programName := components.back!
  let fnEnv ← buildTonFnEnvV1 types source.callables
  let mut initializer : Option Method := none
  let mut entries : Array Method := #[]
  let mut fns : Array FnBinding := #[]
  for callable in source.callables do
    match callable.kind with
    | .initializer =>
        if initializer.isSome then
          throw <| .planInvariant .ton "semantic program has multiple initializers"
        initializer := some (← makeInitializerV1 types typeDecls storage fnEnv callable)
    | .entry | .view =>
        if entries.size >= maxEntries then
          throw <| .planInvariant .ton s!"entry count exceeds profile limit {maxEntries}"
        entries := entries.push (← makeEntryV1 types typeDecls storage fnEnv callable)
    | .pureFn =>
        if fns.size >= maxEntries then
          throw <| .planInvariant .ton s!"pureFn count exceeds profile limit {maxEntries}"
        fns := fns.push (← makePureFnV1 types typeDecls storage fnEnv callable)
    | .invariant =>
        throw <| .planInvariant .ton
          "unsupported Ton semantic shape: invariants are outside the current UInt64 pilot"
  let resolvedInitializer ← match initializer with
    | some value => pure value
    | none => throw <| .planInvariant .ton "KV-state programs require an initializer"
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
        throw <| .invalidProgram "Ton received an invalid SemanticProgramV1 carrier"
  makePlanFromSemanticDataV1 data

/-- Internal Ton family phase entry: capability → Plan (pre-canonicity). -/
def materializePlanFromCapabilityV1 (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .ton do
    throw <| .planInvariant .ton "engineering capability kind is not Ton"
  let source := CompiledSemanticV1.semanticV1Of
    (ResolvedEngineeringBuildV1.compiledOf capability)
  makePlanFromSemanticV1 source

/-- Engineering Plan-layer entry that bypasses capability resolve.

    Used to pin named fail-closed diagnostics (generic sync CALL, pf.assets)
    while the Ton resolver still declines `effect.synchronous-call`.
    CAP-5 `pf.crypto.sha256` is a product-path leaf (no sync-call
    contribution). **Not** a product path. -/
def engineeringPlanFromSemanticV1 (source : SemanticProgramV1) : CompileResult Plan :=
  makePlanFromSemanticV1 source

end ProofForgeV2.Targets.Ton
