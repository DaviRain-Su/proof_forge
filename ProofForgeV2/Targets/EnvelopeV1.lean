import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Semantic.WireV1

/-!
# Shared public-UInt64 pilot envelope policy (Plan-free)

`EnvelopeV1` holds the **target-neutral** admission rules that every Phase-1
materializer (EVM / Solana / NEAR / Noir / Psy) currently reimplements:

* ASCII identifier grammar (cap is target-local)
* generic array duplicate scan
* anonymous UInt64 / optional UInt32 / Unit / Bool / optional Int64 /
  optional Field / optional Principal type-closure admission (Int widths are
  per-target; first honest slice is Int64-only on every Phase-1 target;
  Principal defaults fail-closed — wire identity is variable-length)
* UInt64/Int64 state/parameter type predicates with per-target visibility
  policy (`allowNonPublic` — EVM/Solana/NEAR accept private/commitment;
  Noir declines)
* LE wire literal decoders (UInt64 / UInt32-via-`decodeU32le` / Bool bit /
  Int64 two's-complement as UInt64 bit pattern)

## What stays target-local

* Target-owned `Plan` / `Expr` / layout / emitter / IR types and all region walkers
* Profile limits (`maxParams`, `maxIdentifierBytes`, body/node caps, …)
* Dense pureFn index construction (later lane)
* Identifier **error phrasing** that is not a pure `targetLabel` substitution
  (EVM uses "EVM ABI identifier" in several seats; others use "safe identifier")
* Solana's hand-rolled 4-byte UInt32 decode (no trailing-byte finish check)
* Noir's inline 4-byte UInt32 decode and its distinct Bool invalid-byte wording
  (`"Bool literal byte must be 0x00 or 0x01"`)

## Message identity

Shared functions never invent wording. Callers pass
`mkErr : String → CompileError` (typically `fun m => .planInvariant .evm m`)
and either a `targetLabel` (`"EVM"` / `"Solana"` / `"NEAR"` / `"Noir"`) or a
`PilotTypeClosureWording` that freezes the few per-target detail strings that
already diverged before this module existed. Error **constructors** stay
target-owned so wire codes / `TargetKind` tags remain byte-identical.

This module imports `ProofForgeV2.Semantic.WireV1` and Core diagnostics only —
never any `Targets.Evm` / `Solana` / `Near` / `Noir` Plan surface.
-/

namespace ProofForgeV2.Targets.EnvelopeV1

open ProofForgeV2
open ProofForgeV2.Semantic.WireV1

/-! ### Identifier grammar + uniqueness -/

/-- Shared ASCII identifier grammar for target Plan envelopes.

    Accepts non-empty strings of `[A-Za-z_][A-Za-z0-9_]*` whose UTF-8 byte
    length is `≤ maxBytes`. Cap is **target-local** (EVM/Solana/NEAR = 240,
    Noir = 120) and must be supplied by the caller; this module does not own a
    global limit table. -/
def isAsciiIdentifier (maxBytes : Nat) (value : String) : Bool :=
  value.toUTF8.size <= maxBytes && match value.toList with
  | [] => false
  | first :: rest =>
      let isAsciiLetter (character : Char) : Bool :=
        let code := character.toNat
        (65 <= code && code <= 90) || (97 <= code && code <= 122)
      let isAsciiDigit (character : Char) : Bool :=
        let code := character.toNat
        48 <= code && code <= 57
      (isAsciiLetter first || first == '_') &&
        rest.all (fun character =>
          isAsciiLetter character || isAsciiDigit character || character == '_')

/-- Linear duplicate scan used by plan validation uniqueness checks.
    Preserves first-seen order; pure and target-neutral. -/
def hasDuplicates [BEq α] (values : Array α) : Bool := Id.run do
  let mut seen : Array α := #[]
  for value in values do
    if seen.contains value then return true
    seen := seen.push value
  return false

/-! ### Pilot type closure -/

/-- Per-target admission set for anonymous UInt widths.

    UInt64 is always required (exactly one). Other listed widths may appear
    at most once each. Historical Phase-1 targets admit `{64, 32}` only;
    EVM body multi-width extends with `{8, 16}` (UInt128/256 stay fail-closed
    at the EVM Plan seam even if listed elsewhere). -/
structure PilotUintWidthPolicy where
  /-- Allowed anonymous UInt bit-widths. Must contain 64. -/
  admittedWidths : Array Nat
  deriving BEq, Repr

/-- Historical shared policy: UInt64 + optional UInt32 (shift-count). -/
def pilotUintWidthPolicyU64U32 : PilotUintWidthPolicy where
  admittedWidths := #[64, 32]

/-- EVM body multi-width policy: UInt64 + UInt32 + UInt8 + UInt16.
    UInt128/256 remain fail-closed at the EVM Plan seam. -/
def pilotUintWidthPolicyEvmBody : PilotUintWidthPolicy where
  admittedWidths := #[64, 32, 8, 16]

/-- Solana body multi-width policy: same admitted set as EVM body
    (`{64, 32, 8, 16}`). Return ABI stays UInt64/Bool/Int64; state/param ABI
    admits UInt{8,16,32,64}+Int64 via `requirePublicUintAbiOrInt64*` (T8b);
    UInt128/256 remain fail-closed at the Solana Plan seam. -/
def pilotUintWidthPolicySolanaBody : PilotUintWidthPolicy where
  admittedWidths := #[64, 32, 8, 16]

/-- NEAR type-table policy for T8b ABI multi-width: admits UInt{8,16,32,64}
    so top-level state/param types may appear. Superseded for full plan
    admission by `pilotUintWidthPolicyNearBody` (T8c); kept as named ABI alias. -/
def pilotUintWidthPolicyNearAbi : PilotUintWidthPolicy where
  admittedWidths := #[64, 32, 8, 16]

/-- NEAR body multi-width policy (T8c): same admitted set as EVM/Solana body
    (`{64, 32, 8, 16}`). State/param ABI multi-width remains via
    `requirePublicUintAbiOrInt64*` (T8b); UInt128/256 fail closed at the Plan seam. -/
def pilotUintWidthPolicyNearBody : PilotUintWidthPolicy where
  admittedWidths := #[64, 32, 8, 16]

/-- Noir type-table policy for T8b ABI multi-width: admits UInt{8,16,32,64}
    so top-level state/param types may appear alongside Field. Body multi-width
    arithmetic remains the historical UInt64/UInt32-shift pilot (T8d); narrow
    body ops stay fail closed. -/
def pilotUintWidthPolicyNoirAbi : PilotUintWidthPolicy where
  admittedWidths := #[64, 32, 8, 16]

/-- Admitted body UInt widths for Phase-1 multi-width pilots (EVM/Solana/NEAR body).
    Distinct from the historical `{64,32}` default still used by Noir body (T8d). -/
def isPilotBodyUintWidth (w : Nat) : Bool :=
  w == 8 || w == 16 || w == 32 || w == 64

/-- NEAR body UInt width gate (alias of `isPilotBodyUintWidth`). -/
def isNearBodyUintWidth (w : Nat) : Bool := isPilotBodyUintWidth w


/-- Per-target admission set for anonymous Int widths.

    Empty = Int fail-closed (historical). First honest product slice admits
    only Int64 on every Phase-1 target (native i64 / sign-checked i256).
    Larger widths stay fail closed unless a target can express exact checked
    semantics. -/
structure PilotIntWidthPolicy where
  admittedWidths : Array Nat
  deriving BEq, Repr

/-- Historical / opt-out: no Int widths. -/
def pilotIntWidthPolicyNone : PilotIntWidthPolicy where
  admittedWidths := #[]

/-- Shared Phase-1 Int64-only policy (EVM / Solana / NEAR / Noir / Psy). -/
def pilotIntWidthPolicyI64 : PilotIntWidthPolicy where
  admittedWidths := #[64]

/-- Per-target admission for sole catalog Field (bn254 Fr).

    Empty / false = Field fail-closed (historical default for EVM / Solana /
    NEAR / Psy). Noir admits bn254 because its native `Field` is the Barretenberg
    bn254 scalar field — exact modulus match with `bn254FrFieldSpecV1`.
    Any non-catalog FieldSpec fails closed even when admission is enabled. -/
structure PilotFieldPolicy where
  /-- When true, admit at most one anonymous `.field bn254FrFieldSpecV1`. -/
  admitBn254Fr : Bool
  deriving BEq, Repr

/-- Historical / opt-out: Field fail-closed. -/
def pilotFieldPolicyNone : PilotFieldPolicy where
  admitBn254Fr := false

/-- Noir (and future targets whose native field is exactly bn254 Fr). -/
def pilotFieldPolicyBn254 : PilotFieldPolicy where
  admitBn254Fr := true

/-- Per-target admission for identity-only Principal.

    Wire Principal valueBytes are **variable-length**: `u32 LE length` (1..=4096)
    + opaque body (`maxTypeLengthV1`). No Phase-1 target identity is an exact
    canonical-bytes match:
    * EVM `address` = fixed 20 bytes (not variable-length u32-prefixed)
    * Solana pubkey = fixed 32 bytes
    * NEAR account id = UTF-8 string, not binary identity payload
    * Noir Field / Psy Felt = field elements, not opaque identity bytes

    Default is fail-closed. A future target may set `admitPrincipal := true`
    only when it can store and byte-compare the full wire encoding. -/
structure PilotPrincipalPolicy where
  admitPrincipal : Bool
  deriving BEq, Repr

/-- Historical / opt-out: Principal fail-closed (all Phase-1 targets). -/
def pilotPrincipalPolicyNone : PilotPrincipalPolicy where
  admitPrincipal := false

/-- Admit at most one anonymous Principal type (reserved; no Phase-1 user yet). -/
def pilotPrincipalPolicyAdmit : PilotPrincipalPolicy where
  admitPrincipal := true

/-- Per-target admission for named Struct/Enum aggregate types (N3).
    Default fail-closed. When true, named Struct/Enum TypeDecls are recorded
    in `PilotTypeClosureV1.namedTypeIds` and may appear as state/param types. -/
structure PilotNamedAggregateStatePolicy where
  admitNamedStructEnum : Bool
  deriving BEq, Repr

def pilotNamedAggregateStatePolicyNone : PilotNamedAggregateStatePolicy where
  admitNamedStructEnum := false

def pilotNamedAggregateStatePolicyAdmit : PilotNamedAggregateStatePolicy where
  admitNamedStructEnum := true

/-- Per-target admission for N4 `TypeShapeV1.string` (variable-length NFC UTF-8).
    Default fail-closed. A positive lane must store and byte-compare the full
    wire encoding (`u32le len || UTF-8`, len ≤ maxTypeLengthV1) or a documented
    pilot bound (EVM: fixed length+8×u64 data leaves, max 64 payload bytes). -/
structure PilotStringPolicy where
  admitString : Bool
  deriving BEq, Repr

def pilotStringPolicyNone : PilotStringPolicy where
  admitString := false

def pilotStringPolicyAdmit : PilotStringPolicy where
  admitString := true

/-- Per-target admission for N5 ContextRead / Commit ops.

    Default fail-closed (`none`). A positive lane must:
    * ContextRead: only the sole wire key
      `proof-forge.context.unix-time-seconds.v1` (anonymous UInt64 result;
      immutable invocation-start Unix epoch seconds snapshot). Other SPEC keys
      (caller/authorizers/randomness) stay fail closed.
    * Commit: label-only identity (exact TypeId + canonical valueBytes;
      no hash/salt). Cryptographic commitment realization is a later target
      capability.

    N5 engineering: every Phase-1 target uses `none` for ContextRead
    (PlanSchema/ValidatePlan frozen against EVM `timestamp()` Expr tags; no
    host clock ABI on Solana/NEAR/Noir/Psy). Commit is admitted as **identity
    passthrough** on EVM/Solana/NEAR (operand Expr reused; no Plan Expr node).
    Noir declines Commit (N1 public relation slots cannot represent commitment
    labels). Psy keeps both closed. -/
structure PilotContextPolicy where
  admitContextUnixTimeSeconds : Bool
  admitCommitIdentity : Bool
  deriving BEq, Repr

def pilotContextPolicyNone : PilotContextPolicy where
  admitContextUnixTimeSeconds := false
  admitCommitIdentity := false

/-- Commit identity only (no ContextRead). Used by EVM/Solana/NEAR/Noir N5. -/
def pilotContextPolicyCommitIdentity : PilotContextPolicy where
  admitContextUnixTimeSeconds := false
  admitCommitIdentity := true

/-- Full ContextRead + Commit (reserved for a future PlanSchema unfreeze). -/
def pilotContextPolicyAdmit : PilotContextPolicy where
  admitContextUnixTimeSeconds := true
  admitCommitIdentity := true

/-- Anonymous type ids admitted by a pilot type-closure policy.
    UInt64 is required; Unit / Bool / Int64 / Field / Principal / String are
    optional (at most one each). Named Struct/Enum TypeIds appear in
    `namedTypeIds` when N3 policy admits them. -/
structure PilotTypeClosureV1 where
  uint64TypeId : TypeIdV1
  unitTypeId : Option TypeIdV1
  boolTypeId : Option TypeIdV1
  /-- Optional anonymous UInt32, interned only when a shift-count literal or
      other UInt32 value appears (Normalize interns at most one).
      Retained for call-site compatibility; also present in `otherUintByWidth`. -/
  uint32TypeId : Option TypeIdV1
  /-- All non-64 admitted anonymous UInt widths as `(width, typeId)` pairs
      in first-seen order. Empty for UInt64-only programs. -/
  otherUintByWidth : Array (Nat × TypeIdV1) := #[]
  /-- Optional anonymous Int64 when the Int policy admits width 64. -/
  int64TypeId : Option TypeIdV1 := none
  /-- All admitted anonymous Int widths as `(width, typeId)` pairs in
      first-seen order. Empty when Int is fail-closed. -/
  otherIntByWidth : Array (Nat × TypeIdV1) := #[]
  /-- Optional sole catalog Field (bn254 Fr) when Field policy admits. -/
  fieldTypeId : Option TypeIdV1 := none
  /-- Optional anonymous Principal when Principal policy admits. -/
  principalTypeId : Option TypeIdV1 := none
  /-- Optional anonymous String when String policy admits (N4). -/
  stringTypeId : Option TypeIdV1 := none
  /-- Named Struct/Enum TypeIds in source order when N3 aggregate policy admits. -/
  namedTypeIds : Array TypeIdV1 := #[]
  deriving BEq, Repr

/-- Look up an admitted non-64 UInt TypeId by bit width. -/
def PilotTypeClosureV1.uintTypeIdAt
    (c : PilotTypeClosureV1) (width : Nat) : Option TypeIdV1 :=
  if width == 64 then some c.uint64TypeId
  else c.otherUintByWidth.findSome? fun (w, tid) =>
    if w == width then some tid else none

/-- Resolve an admitted anonymous UInt TypeId to its bit width. -/
def PilotTypeClosureV1.uintWidthOf
    (c : PilotTypeClosureV1) (typeId : TypeIdV1) : Option Nat :=
  if typeId == c.uint64TypeId then some 64
  else c.otherUintByWidth.findSome? fun (w, tid) =>
    if tid == typeId then some w else none

/-- Look up an admitted Int TypeId by bit width. -/
def PilotTypeClosureV1.intTypeIdAt
    (c : PilotTypeClosureV1) (width : Nat) : Option TypeIdV1 :=
  if width == 64 then c.int64TypeId
  else c.otherIntByWidth.findSome? fun (w, tid) =>
    if w == width then some tid else none

/-- Resolve an admitted anonymous Int TypeId to its bit width. -/
def PilotTypeClosureV1.intWidthOf
    (c : PilotTypeClosureV1) (typeId : TypeIdV1) : Option Nat :=
  match c.int64TypeId with
  | some tid => if tid == typeId then some 64 else
      c.otherIntByWidth.findSome? fun (w, tid') =>
        if tid' == typeId then some w else none
  | none =>
      c.otherIntByWidth.findSome? fun (w, tid) =>
        if tid == typeId then some w else none

/-- True when `typeId` is the admitted UInt64 or Int64 type. -/
def PilotTypeClosureV1.isUInt64OrInt64
    (c : PilotTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  typeId == c.uint64TypeId || c.int64TypeId == some typeId

/-- Admitted **ABI** UInt widths for state/param: `{8,16,32,64}`.
    Shared by EVM, Solana, NEAR, and Noir T8b. Distinct from body multi-width
    only by documentation — same set today; UInt128/256 stay fail closed. Int
    narrow widths are **not** admitted on the ABI surface. -/
def isAbiUintWidth (w : Nat) : Bool :=
  w == 8 || w == 16 || w == 32 || w == 64

/-- EVM **ABI** UInt widths — alias of `isAbiUintWidth` (historical name). -/
def isEvmAbiUintWidth (w : Nat) : Bool := isAbiUintWidth w

/-- Solana **ABI** UInt widths — alias of `isAbiUintWidth`. -/
def isSolanaAbiUintWidth (w : Nat) : Bool := isAbiUintWidth w

/-- NEAR **ABI** UInt widths — alias of `isAbiUintWidth` (`{8,16,32,64}`). -/
def isNearAbiUintWidth (w : Nat) : Bool := isAbiUintWidth w

/-- Noir **ABI** UInt widths — alias of `isAbiUintWidth`. -/
def isNoirAbiUintWidth (w : Nat) : Bool := isAbiUintWidth w

/-- Bit width ↔ byte width for admitted ABI UInt widths. -/
def bitWidthOfByteWidth (byteWidth : Nat) : Nat := byteWidth * 8

def byteWidthOfBitWidth (bitWidth : Nat) : Nat := bitWidth / 8

/-- True when `typeId` is admitted UInt{8,16,32,64} or Int64 (ABI surface). -/
def PilotTypeClosureV1.isUintAbiOrInt64
    (c : PilotTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  match c.uintWidthOf typeId with
  | some w => isAbiUintWidth w
  | none => c.int64TypeId == some typeId

/-- True when `typeId` is the admitted sole catalog Field (bn254 Fr). -/
def PilotTypeClosureV1.isField
    (c : PilotTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  c.fieldTypeId == some typeId

/-- True when `typeId` is the admitted anonymous Principal. -/
def PilotTypeClosureV1.isPrincipal
    (c : PilotTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  c.principalTypeId == some typeId

/-- True when `typeId` is the admitted anonymous String (N4). -/
def PilotTypeClosureV1.isString
    (c : PilotTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  c.stringTypeId == some typeId

/-- True when `typeId` is admitted UInt64, Int64, or Field. -/
def PilotTypeClosureV1.isUInt64OrInt64OrField
    (c : PilotTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  c.isUInt64OrInt64 typeId || c.isField typeId

/-- True when `typeId` is admitted ABI UInt{8,16,32,64}, Int64, or Field
    (Noir T8b state/param surface; narrow UInt coexists with Field). -/
def PilotTypeClosureV1.isUintAbiOrInt64OrField
    (c : PilotTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  c.isUintAbiOrInt64 typeId || c.isField typeId

/-- True when `typeId` is admitted UInt64, Int64, Field, or Principal. -/
def PilotTypeClosureV1.isUInt64OrInt64OrFieldOrPrincipal
    (c : PilotTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  c.isUInt64OrInt64OrField typeId || c.isPrincipal typeId

/-- True when `typeId` is admitted UInt64/Int64/Field/Principal/String. -/
def PilotTypeClosureV1.isUInt64OrInt64OrFieldOrPrincipalOrString
    (c : PilotTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  c.isUInt64OrInt64OrFieldOrPrincipal typeId || c.isString typeId

/-- True when `typeId` is an admitted named Struct/Enum (N3). -/
def PilotTypeClosureV1.isNamedAggregate
    (c : PilotTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  c.namedTypeIds.contains typeId

/-- True when `typeId` is a scalar pilot type or an admitted named aggregate. -/
def PilotTypeClosureV1.isUInt64OrInt64OrFieldOrPrincipalOrNamed
    (c : PilotTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  c.isUInt64OrInt64OrFieldOrPrincipal typeId || c.isNamedAggregate typeId

/-- Scalar pilot + named aggregate + String (N4 EVM positive lane). -/
def PilotTypeClosureV1.isUInt64OrInt64OrFieldOrPrincipalOrNamedOrString
    (c : PilotTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  c.isUInt64OrInt64OrFieldOrPrincipalOrNamed typeId || c.isString typeId

/-- Per-target detail strings that already diverged before EnvelopeV1.
    Common details (named types, one UInt64, duplicate Unit/Bool, missing
    UInt64) are fixed modulo `targetLabel` and must not be rewritten here. -/
structure PilotTypeClosureWording where
  /-- Embedded label, e.g. `"EVM"`, `"Solana"`, `"NEAR"`, `"Noir"`. -/
  targetLabel : String
  /-- UInt32 duplicate detail (EVM/Solana: "at most one…"; NEAR/Noir: "one…"). -/
  uint32DuplicateDetail : String
  /-- Non-admitted integer width detail (four historical strings). -/
  badIntegerWidthDetail : String
  /-- Shapes other than uint/unit/bool/int (Noir historically omits UInt32). -/
  unsupportedShapeDetail : String
  deriving BEq, Repr

/-- EVM type-closure diagnostic wording (body multi-width UInt + Int64).
    Field stays fail-closed: needs a mod-p arithmetic subsystem (Fermat
    inverse for div). -/
def evmTypeClosureWording : PilotTypeClosureWording where
  targetLabel := "EVM"
  uint32DuplicateDetail := "expected at most one anonymous UInt32 type"
  badIntegerWidthDetail :=
    "only anonymous UInt8/UInt16/UInt32/UInt64 and Int64 integer widths are supported"
  unsupportedShapeDetail :=
    "only UInt8, UInt16, UInt32, UInt64, Int64, Unit, and Bool are supported (Field needs mod-p arithmetic; Principal is variable-length u32-prefixed identity with no EVM address exact match)"

/-- Solana type-closure diagnostic wording (UInt64/32 + Int64).
    Field fail-closed: no native field element. -/
def solanaTypeClosureWording : PilotTypeClosureWording where
  targetLabel := "Solana"
  uint32DuplicateDetail := "expected at most one anonymous UInt32 type"
  badIntegerWidthDetail :=
    "only anonymous UInt64/UInt32 and Int64 widths are supported"
  unsupportedShapeDetail :=
    "only UInt64, UInt32, Int64, Unit, and Bool are supported (no native Field; Principal is variable-length u32-prefixed identity, not fixed 32-byte pubkey)"

/-- NEAR type-closure diagnostic wording (ABI multi-width UInt + Int64).
    Field fail-closed: no native field element. Body multi-width (T8c) is
    still closed even though the type table admits UInt{8,16,32,64}. -/
def nearTypeClosureWording : PilotTypeClosureWording where
  targetLabel := "NEAR"
  uint32DuplicateDetail := "expected one anonymous UInt32 type"
  badIntegerWidthDetail :=
    "only anonymous UInt8/UInt16/UInt32/UInt64 and Int64 integer types are supported"
  unsupportedShapeDetail :=
    "only UInt8, UInt16, UInt32, UInt64, Int64, Unit, and Bool are supported (no native Field; Principal is binary variable-length identity, not NEAR account-id string)"

/-- Noir type-closure diagnostic wording (ABI multi-width UInt + Int64 + Field).

    Wave N2a names Int64; Wave N2b opens sole catalog Field (bn254 Fr = Noir
    native Field). T8b admits UInt{8,16,32,64} on the type table so state/param
    ABI multi-width may appear; body multi-width remains T8d. -/
def noirTypeClosureWording : PilotTypeClosureWording where
  targetLabel := "Noir"
  uint32DuplicateDetail := "expected one anonymous UInt32 type"
  badIntegerWidthDetail :=
    "only anonymous UInt8/UInt16/UInt32/UInt64 and Int64 integer widths are supported"
  unsupportedShapeDetail :=
    "only UInt8, UInt16, UInt32, UInt64, Int64, Unit, Bool, and Field(bn254-fr) are supported (Principal is variable-length identity, not a Field element)"

/-- Psy type-closure diagnostic wording (UInt64/32 + Int64).
    Field fail-closed: Psy Felt is a field element but there is no pinned
    evidence that Psy's Felt modulus equals bn254 Fr (catalog modulus). -/
def psyTypeClosureWording : PilotTypeClosureWording where
  targetLabel := "Psy"
  uint32DuplicateDetail := "expected at most one anonymous UInt32 type"
  badIntegerWidthDetail :=
    "only anonymous UInt64/UInt32 and Int64 widths are supported"
  unsupportedShapeDetail :=
    "only UInt64, UInt32, Int64, Unit, and Bool are supported (Psy Felt modulus not proven equal to bn254 Fr; Principal is variable-length identity, not Felt)"
private def shapeMsg (label detail : String) : String :=
  s!"unsupported {label} semantic shape: {detail}"

private def widthAdmitted (policy : PilotUintWidthPolicy) (width : Nat) : Bool :=
  policy.admittedWidths.contains width

private def intWidthAdmitted (policy : PilotIntWidthPolicy) (width : Nat) : Bool :=
  policy.admittedWidths.contains width

private def duplicateUintDetail
    (wording : PilotTypeClosureWording) (width : Nat) : String :=
  if width == 32 then wording.uint32DuplicateDetail
  else s!"expected at most one anonymous UInt{width} type"

private def duplicateIntDetail (width : Nat) : String :=
  s!"expected at most one anonymous Int{width} type"

/-- Admit a pilot type closure under explicit UInt-, Int-width, Field,
    Principal, String, and named-aggregate policies.

    Rules: require exactly one anonymous UInt64; accept at most one of each
    other admitted UInt width / admitted Int width / Unit / Bool / sole catalog
    Field / Principal / String; named Struct/Enum only when
    `namedAggregatePolicy.admitNamedStructEnum` (N3); reject all other shapes
    (including anonymous Array/Map/Option/Bytes). Diagnostics use `mkErr` and
    `wording`.

    Default named-aggregate/String policies are **none** (fail closed); pass
    `pilotNamedAggregateStatePolicyAdmit` / `pilotStringPolicyAdmit` for
    positive lanes (EVM). -/
def validatePilotTypeClosure
    (mkErr : String → CompileError)
    (wording : PilotTypeClosureWording)
    (types : Array TypeDeclV1)
    (policy : PilotUintWidthPolicy := pilotUintWidthPolicyU64U32)
    (intPolicy : PilotIntWidthPolicy := pilotIntWidthPolicyI64)
    (fieldPolicy : PilotFieldPolicy := pilotFieldPolicyNone)
    (principalPolicy : PilotPrincipalPolicy := pilotPrincipalPolicyNone)
    (namedAggregatePolicy : PilotNamedAggregateStatePolicy :=
      pilotNamedAggregateStatePolicyNone)
    (stringPolicy : PilotStringPolicy := pilotStringPolicyNone) :
    CompileResult PilotTypeClosureV1 := do
  let label := wording.targetLabel
  unless policy.admittedWidths.contains 64 do
    throw <| mkErr (shapeMsg label "UInt64 type is missing")
  let mut uint64TypeId : Option TypeIdV1 := none
  let mut unitTypeId : Option TypeIdV1 := none
  let mut boolTypeId : Option TypeIdV1 := none
  let mut otherUintByWidth : Array (Nat × TypeIdV1) := #[]
  let mut otherIntByWidth : Array (Nat × TypeIdV1) := #[]
  let mut fieldTypeId : Option TypeIdV1 := none
  let mut principalTypeId : Option TypeIdV1 := none
  let mut stringTypeId : Option TypeIdV1 := none
  let mut namedTypeIds : Array TypeIdV1 := #[]
  for decl in types do
    match decl.name with
    | some _ =>
        unless namedAggregatePolicy.admitNamedStructEnum do
          throw <| mkErr (shapeMsg label
            "named types are outside the current UInt64 pilot")
        match decl.shape with
        | .struct fields =>
            unless fields.size > 0 do
              throw <| mkErr (shapeMsg label
                "named Struct requires at least one field")
            namedTypeIds := namedTypeIds.push decl.id
        | .enum variants =>
            unless variants.size > 0 do
              throw <| mkErr (shapeMsg label
                "named Enum requires at least one variant")
            namedTypeIds := namedTypeIds.push decl.id
        | _ =>
            throw <| mkErr (shapeMsg label
              "named types must be Struct or Enum")
    | none =>
      match decl.shape with
      | .uint width =>
          let w := width.toNat
          unless widthAdmitted policy w do
            throw <| mkErr (shapeMsg label wording.badIntegerWidthDetail)
          if w == 64 then
            unless uint64TypeId.isNone do
              throw <| mkErr (shapeMsg label
                "expected one anonymous UInt64 type")
            uint64TypeId := some decl.id
          else
            if otherUintByWidth.any (fun (ew, _) => ew == w) then
              throw <| mkErr (shapeMsg label (duplicateUintDetail wording w))
            otherUintByWidth := otherUintByWidth.push (w, decl.id)
      | .int width =>
          let w := width.toNat
          unless intWidthAdmitted intPolicy w do
            throw <| mkErr (shapeMsg label wording.badIntegerWidthDetail)
          if otherIntByWidth.any (fun (ew, _) => ew == w) then
            throw <| mkErr (shapeMsg label (duplicateIntDetail w))
          otherIntByWidth := otherIntByWidth.push (w, decl.id)
      | .unit =>
          unless unitTypeId.isNone do
            throw <| mkErr (shapeMsg label "duplicate Unit type")
          unitTypeId := some decl.id
      | .bool =>
          unless boolTypeId.isNone do
            throw <| mkErr (shapeMsg label "duplicate Bool type")
          boolTypeId := some decl.id
      | .field spec =>
          unless fieldPolicy.admitBn254Fr do
            throw <| mkErr (shapeMsg label wording.unsupportedShapeDetail)
          unless spec.id.value == bn254FrFieldIdV1 &&
              spec.modulusBE == bn254FrModulusBEV1 do
            throw <| mkErr (shapeMsg label
              "only sole catalog Field bn254-fr (exact modulus) is supported")
          unless fieldTypeId.isNone do
            throw <| mkErr (shapeMsg label
              "expected at most one anonymous Field type")
          fieldTypeId := some decl.id
      | .principal =>
          unless principalPolicy.admitPrincipal do
            throw <| mkErr (shapeMsg label wording.unsupportedShapeDetail)
          unless principalTypeId.isNone do
            throw <| mkErr (shapeMsg label
              "expected at most one anonymous Principal type")
          principalTypeId := some decl.id
      | .string =>
          unless stringPolicy.admitString do
            throw <| mkErr (shapeMsg label wording.unsupportedShapeDetail)
          unless stringTypeId.isNone do
            throw <| mkErr (shapeMsg label
              "expected at most one anonymous String type")
          stringTypeId := some decl.id
      | _ =>
          throw <| mkErr (shapeMsg label wording.unsupportedShapeDetail)
  let resolvedUInt64TypeId ← match uint64TypeId with
    | some value => pure value
    | none => throw (mkErr (shapeMsg label "UInt64 type is missing"))
  let uint32TypeId :=
    otherUintByWidth.findSome? fun (w, tid) => if w == 32 then some tid else none
  let int64TypeId :=
    otherIntByWidth.findSome? fun (w, tid) => if w == 64 then some tid else none
  pure {
    uint64TypeId := resolvedUInt64TypeId
    unitTypeId
    boolTypeId
    uint32TypeId
    otherUintByWidth
    int64TypeId
    otherIntByWidth
    fieldTypeId
    principalTypeId
    stringTypeId
    namedTypeIds
  }

/-! ### UInt64 state / parameter predicates (visibility policy)

    Type messages are identical across the four targets (no label substitution).
    Identifier grammar and identifier **phrasing** stay with the caller: EVM
    says "EVM ABI identifier"; Solana/NEAR/Noir say "safe identifier". Callers
    compose `requirePublicUInt64*` with `isAsciiIdentifier` + a target-local
    message.

    **Visibility policy (N1):**
    * `allowNonPublic = true` — accept public/private/commitment (physical
      storage/calldata is inherently opaque; product disclosure is sole
      CheckV1/DisclosureCheck authority). Used by EVM / Solana / NEAR.
    * `allowNonPublic = false` — require `.public_` (default). Used by Noir:
      relation state/param slots are public inputs, so private/commitment would
      leak into the verifier. Pass `nonPublicMsg` for a clear Noir-local
      decline message. -/

/-- Fail unless `state` is UInt64 under `uint64TypeId`, and public unless
    `allowNonPublic`. Default message when type fails or (visibility fails and
    no `nonPublicMsg`): `state '{name}' is not public UInt64`. -/
def requirePublicUInt64State
    (mkErr : String → CompileError)
    (uint64TypeId : TypeIdV1)
    (state : StateDeclV1)
    (allowNonPublic : Bool := false)
    (nonPublicMsg : Option String := none) : CompileResult Unit := do
  unless state.typeId == uint64TypeId do
    throw <| mkErr s!"state '{state.name}' is not public UInt64"
  unless state.visibility == .public_ || allowNonPublic do
    match nonPublicMsg with
    | some m => throw <| mkErr m
    | none => throw <| mkErr s!"state '{state.name}' is not public UInt64"

/-- Fail unless `state` is UInt64 or admitted Int64, and public unless
    `allowNonPublic`. Message keeps the historical `UInt64` token so existing
    "not public UInt64" negatives still match via substring. -/
def requirePublicUInt64OrInt64State
    (mkErr : String → CompileError)
    (types : PilotTypeClosureV1)
    (state : StateDeclV1)
    (allowNonPublic : Bool := false)
    (nonPublicMsg : Option String := none) : CompileResult Unit := do
  unless types.isUInt64OrInt64 state.typeId do
    throw <| mkErr s!"state '{state.name}' is not public UInt64"
  unless state.visibility == .public_ || allowNonPublic do
    match nonPublicMsg with
    | some m => throw <| mkErr m
    | none => throw <| mkErr s!"state '{state.name}' is not public UInt64"

/-- Fail unless `param` is UInt64 under `uint64TypeId`, and public unless
    `allowNonPublic`. Message: `parameter '{name}' in {owner} is not public
    UInt64` (or `nonPublicMsg` when provided for a visibility decline).
    `owner` is the target-local owner string (e.g. `"entry 'inc'"`). -/
def requirePublicUInt64Param
    (mkErr : String → CompileError)
    (uint64TypeId : TypeIdV1)
    (owner : String)
    (param : ParameterV1)
    (allowNonPublic : Bool := false)
    (nonPublicMsg : Option String := none) : CompileResult Unit := do
  unless param.typeId == uint64TypeId do
    throw <| mkErr s!"parameter '{param.name}' in {owner} is not public UInt64"
  unless param.visibility == .public_ || allowNonPublic do
    match nonPublicMsg with
    | some m => throw <| mkErr m
    | none =>
        throw <| mkErr s!"parameter '{param.name}' in {owner} is not public UInt64"

/-- Fail unless `param` is UInt64 or admitted Int64, and public unless
    `allowNonPublic`. Message keeps the historical `UInt64` token. -/
def requirePublicUInt64OrInt64Param
    (mkErr : String → CompileError)
    (types : PilotTypeClosureV1)
    (owner : String)
    (param : ParameterV1)
    (allowNonPublic : Bool := false)
    (nonPublicMsg : Option String := none) : CompileResult Unit := do
  unless types.isUInt64OrInt64 param.typeId do
    throw <| mkErr s!"parameter '{param.name}' in {owner} is not public UInt64"
  unless param.visibility == .public_ || allowNonPublic do
    match nonPublicMsg with
    | some m => throw <| mkErr m
    | none =>
        throw <| mkErr s!"parameter '{param.name}' in {owner} is not public UInt64"

/-- Fail unless `state` is UInt{8,16,32,64} or Int64 (EVM ABI multi-width), and
    public unless `allowNonPublic`. Message keeps the historical `UInt64` token
    so existing "not public UInt64" substring negatives still match. -/
def requirePublicUintAbiOrInt64State
    (mkErr : String → CompileError)
    (types : PilotTypeClosureV1)
    (state : StateDeclV1)
    (allowNonPublic : Bool := false)
    (nonPublicMsg : Option String := none) : CompileResult Unit := do
  unless types.isUintAbiOrInt64 state.typeId do
    throw <| mkErr s!"state '{state.name}' is not public UInt64"
  unless state.visibility == .public_ || allowNonPublic do
    match nonPublicMsg with
    | some m => throw <| mkErr m
    | none => throw <| mkErr s!"state '{state.name}' is not public UInt64"

/-- Fail unless `param` is UInt{8,16,32,64} or Int64 (EVM ABI multi-width), and
    public unless `allowNonPublic`. Message keeps the historical `UInt64` token. -/
def requirePublicUintAbiOrInt64Param
    (mkErr : String → CompileError)
    (types : PilotTypeClosureV1)
    (owner : String)
    (param : ParameterV1)
    (allowNonPublic : Bool := false)
    (nonPublicMsg : Option String := none) : CompileResult Unit := do
  unless types.isUintAbiOrInt64 param.typeId do
    throw <| mkErr s!"parameter '{param.name}' in {owner} is not public UInt64"
  unless param.visibility == .public_ || allowNonPublic do
    match nonPublicMsg with
    | some m => throw <| mkErr m
    | none =>
        throw <| mkErr s!"parameter '{param.name}' in {owner} is not public UInt64"

/-- Fail unless `state` is UInt64, Int64, or admitted Field, and public unless
    `allowNonPublic`. -/
def requirePublicUInt64OrInt64OrFieldState
    (mkErr : String → CompileError)
    (types : PilotTypeClosureV1)
    (state : StateDeclV1)
    (allowNonPublic : Bool := false)
    (nonPublicMsg : Option String := none) : CompileResult Unit := do
  unless types.isUInt64OrInt64OrField state.typeId do
    throw <| mkErr s!"state '{state.name}' is not public UInt64"
  unless state.visibility == .public_ || allowNonPublic do
    match nonPublicMsg with
    | some m => throw <| mkErr m
    | none => throw <| mkErr s!"state '{state.name}' is not public UInt64"

/-- Fail unless `param` is UInt64, Int64, or admitted Field, and public unless
    `allowNonPublic`. -/
def requirePublicUInt64OrInt64OrFieldParam
    (mkErr : String → CompileError)
    (types : PilotTypeClosureV1)
    (owner : String)
    (param : ParameterV1)
    (allowNonPublic : Bool := false)
    (nonPublicMsg : Option String := none) : CompileResult Unit := do
  unless types.isUInt64OrInt64OrField param.typeId do
    throw <| mkErr s!"parameter '{param.name}' in {owner} is not public UInt64"
  unless param.visibility == .public_ || allowNonPublic do
    match nonPublicMsg with
    | some m => throw <| mkErr m
    | none =>
        throw <| mkErr s!"parameter '{param.name}' in {owner} is not public UInt64"

/-- Fail unless `state` is ABI UInt{8,16,32,64}, Int64, or admitted Field
    (Noir T8b), and public unless `allowNonPublic`. Message keeps the historical
    `UInt64` token so existing "not public UInt64" substring negatives still
    match. -/
def requirePublicUintAbiOrInt64OrFieldState
    (mkErr : String → CompileError)
    (types : PilotTypeClosureV1)
    (state : StateDeclV1)
    (allowNonPublic : Bool := false)
    (nonPublicMsg : Option String := none) : CompileResult Unit := do
  unless types.isUintAbiOrInt64OrField state.typeId do
    throw <| mkErr s!"state '{state.name}' is not public UInt64"
  unless state.visibility == .public_ || allowNonPublic do
    match nonPublicMsg with
    | some m => throw <| mkErr m
    | none => throw <| mkErr s!"state '{state.name}' is not public UInt64"

/-- Fail unless `param` is ABI UInt{8,16,32,64}, Int64, or admitted Field
    (Noir T8b), and public unless `allowNonPublic`. -/
def requirePublicUintAbiOrInt64OrFieldParam
    (mkErr : String → CompileError)
    (types : PilotTypeClosureV1)
    (owner : String)
    (param : ParameterV1)
    (allowNonPublic : Bool := false)
    (nonPublicMsg : Option String := none) : CompileResult Unit := do
  unless types.isUintAbiOrInt64OrField param.typeId do
    throw <| mkErr s!"parameter '{param.name}' in {owner} is not public UInt64"
  unless param.visibility == .public_ || allowNonPublic do
    match nonPublicMsg with
    | some m => throw <| mkErr m
    | none =>
        throw <| mkErr s!"parameter '{param.name}' in {owner} is not public UInt64"

/-- Fail unless `state` is UInt64, Int64, Field, or Principal, and public unless
    `allowNonPublic`. Reserved for a target that admits Principal. -/
def requirePublicUInt64OrInt64OrFieldOrPrincipalState
    (mkErr : String → CompileError)
    (types : PilotTypeClosureV1)
    (state : StateDeclV1)
    (allowNonPublic : Bool := false)
    (nonPublicMsg : Option String := none) : CompileResult Unit := do
  unless types.isUInt64OrInt64OrFieldOrPrincipal state.typeId do
    throw <| mkErr s!"state '{state.name}' is not public UInt64"
  unless state.visibility == .public_ || allowNonPublic do
    match nonPublicMsg with
    | some m => throw <| mkErr m
    | none => throw <| mkErr s!"state '{state.name}' is not public UInt64"

/-- Fail unless `param` is UInt64, Int64, Field, or Principal, and public unless
    `allowNonPublic`. Reserved for a target that admits Principal. -/
def requirePublicUInt64OrInt64OrFieldOrPrincipalParam
    (mkErr : String → CompileError)
    (types : PilotTypeClosureV1)
    (owner : String)
    (param : ParameterV1)
    (allowNonPublic : Bool := false)
    (nonPublicMsg : Option String := none) : CompileResult Unit := do
  unless types.isUInt64OrInt64OrFieldOrPrincipal param.typeId do
    throw <| mkErr s!"parameter '{param.name}' in {owner} is not public UInt64"
  unless param.visibility == .public_ || allowNonPublic do
    match nonPublicMsg with
    | some m => throw <| mkErr m
    | none =>
        throw <| mkErr s!"parameter '{param.name}' in {owner} is not public UInt64"


/-- Fail unless `state` is UInt64/Int64/Field/Principal **or named Struct/Enum**
    (N3) **or String** (N4 when admitted), and public unless `allowNonPublic`. -/
def requirePublicUInt64OrInt64OrFieldOrPrincipalOrNamedState
    (mkErr : String → CompileError)
    (types : PilotTypeClosureV1)
    (state : StateDeclV1)
    (allowNonPublic : Bool := false)
    (nonPublicMsg : Option String := none) : CompileResult Unit := do
  unless types.isUInt64OrInt64OrFieldOrPrincipalOrNamedOrString state.typeId do
    throw <| mkErr s!"state '{state.name}' is not public UInt64"
  unless state.visibility == .public_ || allowNonPublic do
    match nonPublicMsg with
    | some m => throw <| mkErr m
    | none => throw <| mkErr s!"state '{state.name}' is not public UInt64"

/-- Fail unless `param` is UInt64/Int64/Field/Principal **or named Struct/Enum**
    (N3) **or String** (N4 when admitted), and public unless `allowNonPublic`. -/
def requirePublicUInt64OrInt64OrFieldOrPrincipalOrNamedParam
    (mkErr : String → CompileError)
    (types : PilotTypeClosureV1)
    (owner : String)
    (param : ParameterV1)
    (allowNonPublic : Bool := false)
    (nonPublicMsg : Option String := none) : CompileResult Unit := do
  unless types.isUInt64OrInt64OrFieldOrPrincipalOrNamedOrString param.typeId do
    throw <| mkErr s!"parameter '{param.name}' in {owner} is not public UInt64"
  unless param.visibility == .public_ || allowNonPublic do
    match nonPublicMsg with
    | some m => throw <| mkErr m
    | none =>
        throw <| mkErr s!"parameter '{param.name}' in {owner} is not public UInt64"

/-! ### LE literal decoders

    Pure bytes → value decoders. Target Expr wrapping (Bool-as-UInt64 word,
    LoweredValue construction) stays target-owned. -/

/-- Decode an 8-byte little-endian UInt64 literal via WireV1 `decodeU64le` +
    full-consume `finish`. Messages:
    * `unsupported {label} semantic shape: UInt64 literal must contain exactly 8 bytes`
    * `…: invalid UInt64 literal`
    * `…: trailing UInt64 literal bytes` -/
def decodeUInt64LiteralLe
    (mkErr : String → CompileError)
    (targetLabel : String)
    (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 8 do
    throw <| mkErr (shapeMsg targetLabel
      "UInt64 literal must contain exactly 8 bytes")
  match decodeU64le (start bytes) with
  | .error _ =>
      throw <| mkErr (shapeMsg targetLabel "invalid UInt64 literal")
  | .ok (value, cursor) =>
      match finish cursor with
      | .ok () => pure value
      | .error _ =>
          throw <| mkErr (shapeMsg targetLabel "trailing UInt64 literal bytes")

/-- Decode a 4-byte little-endian UInt32 literal via WireV1 `decodeU32le` +
    full-consume `finish`, zero-extended to UInt64.

    Matches EVM and NEAR. **Not** Solana (hand-rolled LE without finish) or
    Noir (inline hand-rolled LE without invalid/trailing messages). -/
def decodeUInt32LiteralLe
    (mkErr : String → CompileError)
    (targetLabel : String)
    (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 4 do
    throw <| mkErr (shapeMsg targetLabel
      "UInt32 literal must contain exactly 4 bytes")
  match decodeU32le (start bytes) with
  | .error _ =>
      throw <| mkErr (shapeMsg targetLabel "invalid UInt32 literal")
  | .ok (value, cursor) =>
      match finish cursor with
      | .ok () => pure (UInt64.ofNat value.toNat)
      | .error _ =>
          throw <| mkErr (shapeMsg targetLabel "trailing UInt32 literal bytes")

/-- Decode a 1-byte Bool literal (`0x00` / `0x01`).

    Default invalid-byte detail is `"Bool literal must be 0x00 or 0x01"`
    (EVM / Solana / NEAR). Noir historically uses
    `"Bool literal byte must be 0x00 or 0x01"` — pass that as
    `invalidDetail` when migrating Noir. Return type is `Bool`; EVM/Noir
    wrap to UInt64 0/1 at the call site. -/
def decodeBoolLiteralBit
    (mkErr : String → CompileError)
    (targetLabel : String)
    (bytes : ByteArray)
    (invalidDetail : String := "Bool literal must be 0x00 or 0x01") :
    CompileResult Bool := do
  unless bytes.size == 1 do
    throw <| mkErr (shapeMsg targetLabel
      "Bool literal must contain exactly 1 byte")
  let b := bytes.get! 0
  unless b == 0 || b == 1 do
    throw <| mkErr (shapeMsg targetLabel invalidDetail)
  pure (b != 0)

/-- Decode a little-endian anonymous UInt literal of `bitWidth` bits
    (`bitWidth ∈ {8,16,32,64}`) into a UInt64 Plan word (zero-extended).
    Full-consume: exact `bitWidth/8` bytes. -/
def decodeUIntWidthLiteralLe
    (mkErr : String → CompileError)
    (targetLabel : String)
    (bitWidth : Nat)
    (bytes : ByteArray) : CompileResult UInt64 := do
  unless bitWidth == 8 || bitWidth == 16 || bitWidth == 32 || bitWidth == 64 do
    throw <| mkErr (shapeMsg targetLabel
      s!"UInt{bitWidth} literal width is not supported")
  let byteLen := bitWidth / 8
  unless bytes.size == byteLen do
    throw <| mkErr (shapeMsg targetLabel
      s!"UInt{bitWidth} literal must contain exactly {byteLen} bytes")
  if bitWidth == 64 then
    decodeUInt64LiteralLe mkErr targetLabel bytes
  else if bitWidth == 32 then
    decodeUInt32LiteralLe mkErr targetLabel bytes
  else
    -- 8 / 16: hand LE fold (Wire has no decodeU16/U8 public path).
    let mut n : Nat := 0
    let mut place : Nat := 1
    for i in [:byteLen] do
      n := n + (bytes.get! i).toNat * place
      place := place * 256
    pure (UInt64.ofNat n)

/-- Decode an 8-byte little-endian Int64 two's-complement wire literal into a
    UInt64 Plan word that carries the same bit pattern. Callers treat the word
    as signed at emission (i64 ops / sign-checked Yul). Messages mirror the
    UInt64 decoder with an `Int64` label. -/
def decodeInt64LiteralLe
    (mkErr : String → CompileError)
    (targetLabel : String)
    (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 8 do
    throw <| mkErr (shapeMsg targetLabel
      "Int64 literal must contain exactly 8 bytes")
  match decodeU64le (start bytes) with
  | .error _ =>
      throw <| mkErr (shapeMsg targetLabel "invalid Int64 literal")
  | .ok (value, cursor) =>
      match finish cursor with
      | .ok () => pure value
      | .error _ =>
          throw <| mkErr (shapeMsg targetLabel "trailing Int64 literal bytes")

end ProofForgeV2.Targets.EnvelopeV1
