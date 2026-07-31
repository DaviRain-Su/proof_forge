import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Semantic.WireV1

/-!
# Shared public-UInt64 pilot envelope policy (Plan-free)

`EnvelopeV1` holds the **target-neutral** admission rules that every Phase-1
materializer (EVM / Solana / NEAR / Noir) currently reimplements:

* ASCII identifier grammar (cap is target-local)
* generic array duplicate scan
* anonymous UInt64 / optional UInt32 / Unit / Bool type-closure admission
* public-UInt64 state/parameter type+visibility predicates
* LE wire literal decoders (UInt64 / UInt32-via-`decodeU32le` / Bool bit)

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

/-- Anonymous type ids admitted by the public-UInt64 pilot envelope.
    UInt64 is required; Unit / Bool / UInt32 are optional (at most one each). -/
structure PilotTypeClosureV1 where
  uint64TypeId : TypeIdV1
  unitTypeId : Option TypeIdV1
  boolTypeId : Option TypeIdV1
  /-- Optional anonymous UInt32, interned only when a shift-count literal or
      other UInt32 value appears (Normalize interns at most one). -/
  uint32TypeId : Option TypeIdV1
  deriving BEq, Repr

/-- Per-target detail strings that already diverged before EnvelopeV1.
    Common details (named types, one UInt64, duplicate Unit/Bool, missing
    UInt64) are fixed modulo `targetLabel` and must not be rewritten here. -/
structure PilotTypeClosureWording where
  /-- Embedded label, e.g. `"EVM"`, `"Solana"`, `"NEAR"`, `"Noir"`. -/
  targetLabel : String
  /-- UInt32 duplicate detail (EVM/Solana: "at most one…"; NEAR/Noir: "one…"). -/
  uint32DuplicateDetail : String
  /-- Non-64/non-32 integer width detail (four historical strings). -/
  badIntegerWidthDetail : String
  /-- Shapes other than uint/unit/bool (Noir historically omits UInt32). -/
  unsupportedShapeDetail : String
  deriving BEq, Repr

/-- Byte-identical EVM type-closure diagnostic wording. -/
def evmTypeClosureWording : PilotTypeClosureWording where
  targetLabel := "EVM"
  uint32DuplicateDetail := "expected at most one anonymous UInt32 type"
  badIntegerWidthDetail := "only anonymous UInt64/UInt32 integer widths are supported"
  unsupportedShapeDetail := "only UInt64, UInt32, Unit, and Bool are supported"

/-- Byte-identical Solana type-closure diagnostic wording. -/
def solanaTypeClosureWording : PilotTypeClosureWording where
  targetLabel := "Solana"
  uint32DuplicateDetail := "expected at most one anonymous UInt32 type"
  badIntegerWidthDetail := "only anonymous UInt64/UInt32 widths are supported"
  unsupportedShapeDetail := "only UInt64, UInt32, Unit, and Bool are supported"

/-- Byte-identical NEAR type-closure diagnostic wording. -/
def nearTypeClosureWording : PilotTypeClosureWording where
  targetLabel := "NEAR"
  uint32DuplicateDetail := "expected one anonymous UInt32 type"
  badIntegerWidthDetail := "only anonymous UInt64/UInt32 integer types are supported"
  unsupportedShapeDetail := "only UInt64, UInt32, Unit, and Bool are supported"

/-- Byte-identical Noir type-closure diagnostic wording.

    Note: `badIntegerWidthDetail` reuses the one-UInt64 phrase (historical);
    `unsupportedShapeDetail` omits UInt32 even though UInt32 is accepted. -/
def noirTypeClosureWording : PilotTypeClosureWording where
  targetLabel := "Noir"
  uint32DuplicateDetail := "expected one anonymous UInt32 type"
  badIntegerWidthDetail := "expected one anonymous UInt64 type"
  unsupportedShapeDetail := "only UInt64, Unit, and Bool are supported"

private def shapeMsg (label detail : String) : String :=
  s!"unsupported {label} semantic shape: {detail}"

/-- Admit the public-UInt64 pilot type closure.

    Rules (shared): reject named types; require exactly one anonymous UInt64;
    accept at most one anonymous UInt32 / Unit / Bool; reject all other shapes.
    Diagnostics use `mkErr` (target owns `.planInvariant .evm`/…) and
    `wording` for the few historically divergent detail strings. -/
def validatePilotTypeClosure
    (mkErr : String → CompileError)
    (wording : PilotTypeClosureWording)
    (types : Array TypeDeclV1) : CompileResult PilotTypeClosureV1 := do
  let label := wording.targetLabel
  let mut uint64TypeId : Option TypeIdV1 := none
  let mut unitTypeId : Option TypeIdV1 := none
  let mut boolTypeId : Option TypeIdV1 := none
  let mut uint32TypeId : Option TypeIdV1 := none
  for decl in types do
    unless decl.name.isNone do
      throw <| mkErr (shapeMsg label
        "named types are outside the current UInt64 pilot")
    match decl.shape with
    | .uint width =>
        match width.toNat with
        | 64 =>
            unless uint64TypeId.isNone do
              throw <| mkErr (shapeMsg label
                "expected one anonymous UInt64 type")
            uint64TypeId := some decl.id
        | 32 =>
            unless uint32TypeId.isNone do
              throw <| mkErr (shapeMsg label wording.uint32DuplicateDetail)
            uint32TypeId := some decl.id
        | _ =>
            throw <| mkErr (shapeMsg label wording.badIntegerWidthDetail)
    | .unit =>
        unless unitTypeId.isNone do
          throw <| mkErr (shapeMsg label "duplicate Unit type")
        unitTypeId := some decl.id
    | .bool =>
        unless boolTypeId.isNone do
          throw <| mkErr (shapeMsg label "duplicate Bool type")
        boolTypeId := some decl.id
    | _ =>
        throw <| mkErr (shapeMsg label wording.unsupportedShapeDetail)
  let resolvedUInt64TypeId ← match uint64TypeId with
    | some value => pure value
    | none => throw (mkErr (shapeMsg label "UInt64 type is missing"))
  pure {
    uint64TypeId := resolvedUInt64TypeId
    unitTypeId
    boolTypeId
    uint32TypeId
  }

/-! ### Public-UInt64 state / parameter predicates

    Type+visibility messages are identical across the four targets (no label
    substitution). Identifier grammar and identifier **phrasing** stay with the
    caller: EVM says "EVM ABI identifier"; Solana/NEAR/Noir say "safe
    identifier". Callers compose `requirePublicUInt64*` with
    `isAsciiIdentifier` + a target-local message. -/

/-- Fail unless `state` is public UInt64 under `uint64TypeId`.
    Message: `state '{name}' is not public UInt64`. -/
def requirePublicUInt64State
    (mkErr : String → CompileError)
    (uint64TypeId : TypeIdV1)
    (state : StateDeclV1) : CompileResult Unit := do
  unless state.typeId == uint64TypeId && state.visibility == .public_ do
    throw <| mkErr s!"state '{state.name}' is not public UInt64"

/-- Fail unless `param` is public UInt64 under `uint64TypeId`.
    Message: `parameter '{name}' in {owner} is not public UInt64`.
    `owner` is the target-local owner string (e.g. `"entry 'inc'"`). -/
def requirePublicUInt64Param
    (mkErr : String → CompileError)
    (uint64TypeId : TypeIdV1)
    (owner : String)
    (param : ParameterV1) : CompileResult Unit := do
  unless param.typeId == uint64TypeId && param.visibility == .public_ do
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

end ProofForgeV2.Targets.EnvelopeV1
