import ProofForgeV2.Semantic.WireV1

/-
  ProofForgeV2.Semantic.InvariantFoundationV1 — lower D2-07 state ABI foundation.

  Defines the foundation declarations in their public
  `ProofForgeV2.Semantic.InvariantABI` namespace so the `InvariantABI` façade
  owns `evalInvariantV1` without creating an import cycle through the reference
  machine.

  Engineering subset only:
    * carrier validation via `validateSemanticProgramV1`
    * type-driven default values for every TypeShapeV1 (explicit fuel;
      Option-none truncates recursion)
    * length-prefixed `canonicalValues` slots in logicalState order
    * slot valueBytes validated solely by public `validateValueBytesV1`
    * additive decode/encode helpers for ReferenceV1

  Internal implementation module; consumers import `InvariantABI`.
  Does not itself implement `evalInvariantV1` / `InvariantTheoremV1`; the
  public InvariantABI façade owns those declarations.
  No partial / unsafe / IO.
-/

namespace ProofForgeV2.Semantic.InvariantABI

open ProofForgeV2.Semantic.WireV1

/-- Stable ordinal into `program.invariants` (SPEC §8 / proof ABI). -/
abbrev InvariantOrdinalV1 := UInt32

/-- Closed logical-state carrier shared by proof ABI and reference interpreter. -/
structure LogicalStateV1 where
  initialized     : Bool
  canonicalValues : ByteArray
  deriving BEq

/-- Total evaluation result for a pure invariant callable (SPEC §8). -/
inductive InvariantEvalResultV1 where
  | returnedTrue
  | returnedFalse
  | reverted
  | trapped
  deriving BEq, Repr, DecidableEq

private def err (e : SemanticWireErrorV1) : Except SemanticWireErrorV1 α :=
  .error e

/-- Zero-filled byte vector of exact length `n`. -/
private def zeroBytesV1 (n : Nat) : ByteArray := Id.run do
  let mut out := ByteArray.emptyWithCapacity n
  for _ in [:n] do
    out := out.push 0
  pure out

/-- Big-endian modulus bytes → Nat (local; Wire helper is private). -/
private def beBytesToNatV1 (bytes : ByteArray) : Nat := Id.run do
  let mut n : Nat := 0
  for i in [:bytes.size] do
    n := n * 256 + (bytes.get! i).toNat
  pure n

/-- `ceil(bitLength(p)/8)` for Field value width (SPEC §5). -/
private def fieldValueByteLengthV1 (modulusBE : ByteArray) : Nat :=
  let p := beBytesToNatV1 modulusBE
  if p == 0 then 0
  else
    let bitLength := Nat.log2 p + 1
    (bitLength + 7) / 8

/-- Read little-endian u32 at `offset`; returns value and next offset. -/
private def readU32leAtV1 (bytes : ByteArray) (offset : Nat) :
    Except SemanticWireErrorV1 (UInt32 × Nat) := do
  unless offset + 4 ≤ bytes.size do
    return ← err .truncated
  let b0 := (bytes.get! offset).toNat
  let b1 := (bytes.get! (offset + 1)).toNat
  let b2 := (bytes.get! (offset + 2)).toNat
  let b3 := (bytes.get! (offset + 3)).toNat
  let v := b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
  pure (UInt32.ofNat v, offset + 4)

/-- Encode `valueBytes` as one logical-state slot: `u32le len || bytes`. -/
private def encodeStateSlotV1 (valueBytes : ByteArray) :
    Except SemanticWireErrorV1 ByteArray := do
  unless valueBytes.size ≤ UInt32.size - 1 do
    return ← err .limitExceeded
  pure ((encodeU32le (UInt32.ofNat valueBytes.size)).append valueBytes)

/-- Fuel-bounded type-driven default canonical valueBytes (SPEC-SEM-CORE default).

    Bool=false; UInt/Int/Field=0; Principal payload=`00` (with u32 length);
    Unit=empty; Bytes=zeros; Array=N×element default; Map=empty; Option=none
    (does not recurse into element); Struct=field defaults; Enum=variant 0 +
    payload defaults. Fuel exhaust / missing type / empty enum → error. -/
private def defaultValueAtV1 (types : Array TypeDeclV1) (typeId : TypeIdV1) :
    (fuel : Nat) → Except SemanticWireErrorV1 ByteArray
  | 0 => err .limitExceeded
  | fuel + 1 => do
    match types[typeId.toNat]? with
    | none => err .badReference
    | some decl =>
      match decl.shape with
      | .bool =>
          pure (encodeU8 0)
      | .uint width | .int width =>
          pure (zeroBytesV1 (width.toNat / 8))
      | .principal =>
          -- opaque payload = single byte `00`; canonical includes u32 length.
          pure ((encodeU32le 1).append (encodeU8 0))
      | .unit =>
          pure ByteArray.empty
      | .string =>
          -- Empty string: u32le(0) with no body (N4; empty is legal).
          pure (encodeU32le 0)
      | .bytes length =>
          pure (zeroBytesV1 length.toNat)
      | .array element length => do
          let mut out := ByteArray.empty
          for _ in [:length.toNat] do
            let chunk ← defaultValueAtV1 types element fuel
            out := out.append chunk
          pure out
      | .map _key _value =>
          pure (encodeU32le 0)
      | .option _element =>
          -- Option-none truncates recursion (does not consult element type).
          pure (encodeU8 0)
      | .field spec =>
          pure (zeroBytesV1 (fieldValueByteLengthV1 spec.modulusBE))
      | .struct fields => do
          let mut out := ByteArray.empty
          for f in fields do
            let chunk ← defaultValueAtV1 types f.typeId fuel
            out := out.append chunk
          pure out
      | .enum variants => do
          match variants[0]? with
          | none => err .badType
          | some variant => do
              let mut out := encodeU32le 0
              for payloadType in variant.payloadTypes do
                let chunk ← defaultValueAtV1 types payloadType fuel
                out := out.append chunk
              pure out

/-- Parse `canonicalValues` into per-slot valueBytes arrays.

    Each slot is `u32le len || valueBytes` in `logicalState` order; every
    valueBytes is checked by the unique public `validateValueBytesV1`. Missing
    bytes, trailing bytes, or non-canonical values fail closed. -/
def decodeLogicalStateValuesV1 (data : SemanticProgramDataV1) (state : LogicalStateV1) :
    Except SemanticWireErrorV1 (Array ByteArray) := do
  let mut offset : Nat := 0
  let mut out : Array ByteArray := Array.emptyWithCapacity data.logicalState.size
  for decl in data.logicalState do
    let (lenU, afterLen) ← readU32leAtV1 state.canonicalValues offset
    let len := lenU.toNat
    unless afterLen + len ≤ state.canonicalValues.size do
      return ← err .truncated
    let slice := state.canonicalValues.extract afterLen (afterLen + len)
    offset := afterLen + len
    validateValueBytesV1 data.types decl.typeId slice
    out := out.push slice
  unless offset == state.canonicalValues.size do
    return ← err .trailingBytes
  pure out

/-- Build a `LogicalStateV1` from per-slot valueBytes.

    Arity must match `data.logicalState`; each value is structure-gated by
    `validateValueBytesV1` before length-prefix concatenation. -/
def encodeLogicalStateValuesV1 (data : SemanticProgramDataV1) (initialized : Bool)
    (values : Array ByteArray) : Except SemanticWireErrorV1 LogicalStateV1 := do
  unless values.size == data.logicalState.size do
    return ← err .nonCanonical
  let mut canonical := ByteArray.empty
  let mut i : Nat := 0
  for decl in data.logicalState do
    match values[i]? with
    | none => return ← err .nonCanonical
    | some valueBytes => do
        validateValueBytesV1 data.types decl.typeId valueBytes
        let slot ← encodeStateSlotV1 valueBytes
        canonical := canonical.append slot
        i := i + 1
  pure { initialized, canonicalValues := canonical }

/-- Unique type-driven default canonical value for `typeId` on a validated carrier. -/
def defaultValueV1 (program : SemanticProgramV1) (typeId : TypeIdV1) :
    Except SemanticWireErrorV1 ByteArray := do
  let data ← validateSemanticProgramV1 program
  defaultValueAtV1 data.types typeId maxNesting

/-- Initial logical state: defaults in state order; `initialized=false` iff an
    initializer callable exists, else `true`. -/
def initialLogicalStateV1 (program : SemanticProgramV1) :
    Except SemanticWireErrorV1 LogicalStateV1 := do
  let data ← validateSemanticProgramV1 program
  let mut values : Array ByteArray := Array.emptyWithCapacity data.logicalState.size
  for decl in data.logicalState do
    let v ← defaultValueAtV1 data.types decl.typeId maxNesting
    values := values.push v
  let hasInitializer := data.callables.any fun c => c.kind == .initializer
  encodeLogicalStateValuesV1 data (!hasInitializer) values

/-- Executable StateConforms predicate (SPEC §7).

    Requires validated carrier, `initialized=true`, exact per-slot canonical
    valueBytes for every logicalState entry, and no trailing bytes. All failure
    modes return `false` (total; never throws). -/
def stateConformsBoolV1 (program : SemanticProgramV1) (state : LogicalStateV1) : Bool :=
  match validateSemanticProgramV1 program with
  | .error _ => false
  | .ok data =>
    if !state.initialized then
      false
    else
      match decodeLogicalStateValuesV1 data state with
      | .ok _ => true
      | .error _ => false

/-- Propositional form of StateConforms (definitionally tied to the Bool gate). -/
def StateConformsV1 (program : SemanticProgramV1) (state : LogicalStateV1) : Prop :=
  stateConformsBoolV1 program state = true

/-- Eliminate conformance after an exact successful carrier validation. This
    exposes only the initialized-state and canonical-state decode facts already
    enforced by the sole production conformance predicate. -/
theorem stateConformsV1_elim_of_validate_eq_ok
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (state : LogicalStateV1)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hconforms : StateConformsV1 program state) :
    state.initialized = true ∧
      ∃ values : Array ByteArray,
        decodeLogicalStateValuesV1 data state = .ok values := by
  unfold StateConformsV1 stateConformsBoolV1 at hconforms
  rw [hvalidate] at hconforms
  by_cases hinitialized : state.initialized = true
  · refine ⟨hinitialized, ?_⟩
    simp only [hinitialized, Bool.not_true, Bool.false_eq_true, ↓reduceIte] at hconforms
    generalize hdecode : decodeLogicalStateValuesV1 data state = decoded at hconforms
    cases decoded with
    | error error => contradiction
    | ok values => exact ⟨values, rfl⟩
  · have hfalse : state.initialized = false := by
      cases h : state.initialized <;> simp_all
    simp [hfalse] at hconforms

end ProofForgeV2.Semantic.InvariantABI
