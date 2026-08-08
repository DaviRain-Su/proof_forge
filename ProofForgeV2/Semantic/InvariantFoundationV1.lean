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

/-- List-shaped production decoder used by `decodeLogicalStateValuesV1`.
    Explicit recursion keeps singleton/slot-size proofs off the `forIn`
    monadic surface while preserving the same slot protocol. -/
private def decodeLogicalStateSlotsV1
    (types : Array TypeDeclV1)
    (decls : List StateDeclV1)
    (canonicalValues : ByteArray)
    (offset : Nat)
    (acc : Array ByteArray) :
    Except SemanticWireErrorV1 (Array ByteArray) :=
  match decls with
  | [] =>
      if offset == canonicalValues.size then
        .ok acc
      else
        err .trailingBytes
  | decl :: rest => do
      let (lenU, afterLen) ← readU32leAtV1 canonicalValues offset
      let len := lenU.toNat
      unless afterLen + len ≤ canonicalValues.size do
        return ← err .truncated
      let slice := canonicalValues.extract afterLen (afterLen + len)
      validateValueBytesV1 types decl.typeId slice
      decodeLogicalStateSlotsV1 types rest canonicalValues (afterLen + len)
        (acc.push slice)

/-- Parse `canonicalValues` into per-slot valueBytes arrays.

    Each slot is `u32le len || valueBytes` in `logicalState` order; every
    valueBytes is checked by the unique public `validateValueBytesV1`. Missing
    bytes, trailing bytes, or non-canonical values fail closed. -/
def decodeLogicalStateValuesV1 (data : SemanticProgramDataV1) (state : LogicalStateV1) :
    Except SemanticWireErrorV1 (Array ByteArray) :=
  decodeLogicalStateSlotsV1 data.types data.logicalState.toList state.canonicalValues 0
    (Array.emptyWithCapacity data.logicalState.size)

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

/-- Single-slot encode of an 8-byte (UInt64) payload under a successful valueBytes
    gate. Mirrors the closed zero-state encode reduction used by
    `initialLogicalStateV1_single_uint64_no_initializer_eq_ok`. -/
theorem encodeLogicalStateValuesV1_single_uint64_eq_ok
    (data : SemanticProgramDataV1)
    (stateDecl : StateDeclV1)
    (valueBytes : ByteArray)
    (initialized : Bool)
    (hstate : data.logicalState = #[stateDecl])
    (hcanonical :
      validateValueBytesV1 data.types stateDecl.typeId valueBytes = .ok ())
    (hsize : valueBytes.size = 8) :
    encodeLogicalStateValuesV1 data initialized #[valueBytes] = .ok {
      initialized
      canonicalValues := (encodeU32le 8).append valueBytes
    } := by
  have hslot :
      encodeStateSlotV1 valueBytes =
        .ok ((encodeU32le 8).append valueBytes) := by
    unfold encodeStateSlotV1
    have hle : valueBytes.size ≤ UInt32.size - 1 := by simp [hsize]
    have hsz : UInt32.ofNat valueBytes.size = 8 := by
      simp [hsize]
    simp only [if_pos hle, hsz, Pure.pure, Except.pure, Bind.bind, Except.bind]
  unfold encodeLogicalStateValuesV1
  simp only [hstate]
  -- Singleton tables: arity gate + one forIn step (same reduction as zero-slot).
  simp [hcanonical, hslot, hsize, Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- Decode recovers the payload from the exact single-slot UInt64 encode layout
    produced by `encodeLogicalStateValuesV1_single_uint64_eq_ok`. -/
theorem decodeLogicalStateValuesV1_of_single_uint64_encode
    (data : SemanticProgramDataV1)
    (stateDecl : StateDeclV1)
    (valueBytes : ByteArray)
    (initialized : Bool)
    (hstate : data.logicalState = #[stateDecl])
    (hcanonical :
      validateValueBytesV1 data.types stateDecl.typeId valueBytes = .ok ())
    (hsize : valueBytes.size = 8) :
    decodeLogicalStateValuesV1 data {
      initialized
      canonicalValues := (encodeU32le 8).append valueBytes
    } = .ok #[valueBytes] := by
  let hdr := encodeU32le (8 : UInt32)
  let canon := hdr.append valueBytes
  let state : LogicalStateV1 := {
    initialized
    canonicalValues := canon
  }
  -- Align the statement with local `state`/`canon`.
  change decodeLogicalStateValuesV1 data state = .ok #[valueBytes]
  have hhdr : hdr.size = 4 := encodeU32le_sizeV1 8
  have hread : readU32leAtV1 state.canonicalValues 0 = .ok ((8 : UInt32), 4) := by
    have h := readU32le_encode_midV1 ByteArray.empty valueBytes (8 : UInt32)
    simpa [state, canon, hdr, ByteArray.empty_append, ByteArray.size_empty] using h
  have hextract :
      state.canonicalValues.extract 4 (4 + (8 : UInt32).toNat) = valueBytes := by
    have h8 : (8 : UInt32).toNat = 8 := by decide
    have h := extract_mid_payloadV1 hdr valueBytes ByteArray.empty
    simp only [ByteArray.append_empty, hhdr, hsize] at h
    -- h : (hdr ++ valueBytes).extract 4 (4+8) = valueBytes
    simpa [state, canon, h8] using h
  have hsz : state.canonicalValues.size = 12 := by
    simp [state, canon, ByteArray.size_append, hhdr, hsize]
  have h8 : (8 : UInt32).toNat = 8 := by decide
  have hfit : 4 + (8 : UInt32).toNat ≤ state.canonicalValues.size := by
    simp [hsz, h8]
  have htrail : 4 + (8 : UInt32).toNat = state.canonicalValues.size := by
    simp [hsz, h8]
  -- Mirror the successful singleton-eq case split style.
  unfold decodeLogicalStateValuesV1
  have hlist : data.logicalState.toList = [stateDecl] := by
    simp [hstate]
  simp only [hlist, decodeLogicalStateSlotsV1, Pure.pure, Except.pure,
    Bind.bind, Except.bind, err]
  rw [hread]
  simp only [if_pos hfit, hextract, hcanonical, Pure.pure, Except.pure,
    Bind.bind, Except.bind]
  -- Empty tail: after htrail, the offset equals size (BEq true), then push.
  have hslots : data.logicalState.size = 1 := by
    simp [hstate]
  have hbeq :
      (state.canonicalValues.size == state.canonicalValues.size) = true := by
    simp [BEq.beq]
  -- Residual after the singleton recursive step ends in the empty-list branch:
  -- `if (offset == size) then ok (acc.push …)` with offset rewritten to size.
  simp only [decodeLogicalStateSlotsV1, htrail, hbeq, ↓reduceIte, Pure.pure,
    Except.pure, hslots]
  -- emptyWithCapacity 1 |>.push valueBytes = #[valueBytes]
  have hpush :
      ((Array.emptyWithCapacity 1).push valueBytes) = #[valueBytes] := by
    apply Array.ext
    · simp [Array.size_push, Array.emptyWithCapacity_eq]
    · intro i hi
      have : i = 0 := by
        have : i < 1 := by
          simpa [Array.size_push, Array.emptyWithCapacity_eq] using hi
        omega
      subst this
      simp
  simpa [hpush] using rfl

/-- Successful decode of a singleton logicalState table recovers a singleton
    overlay whose sole element is structure-gated for that slot. -/
theorem decodeLogicalStateValuesV1_singleton_eq
    (data : SemanticProgramDataV1)
    (stateDecl : StateDeclV1)
    (state : LogicalStateV1)
    (values : Array ByteArray)
    (hstate : data.logicalState = #[stateDecl])
    (hdecode : decodeLogicalStateValuesV1 data state = .ok values) :
    ∃ valueBytes : ByteArray,
      values = #[valueBytes] ∧
      validateValueBytesV1 data.types stateDecl.typeId valueBytes = .ok () := by
  unfold decodeLogicalStateValuesV1 at hdecode
  have hlist : data.logicalState.toList = [stateDecl] := by
    simp [hstate]
  -- One-cons recursive step under the singleton table.
  simp only [hlist, decodeLogicalStateSlotsV1, Pure.pure, Except.pure,
    Bind.bind, Except.bind, err] at hdecode
  cases hread : readU32leAtV1 state.canonicalValues 0 with
  | error e =>
      -- error = ok is absurd under simp
      simp [hread] at hdecode
  | ok pair =>
      rcases pair with ⟨lenU, afterLen⟩
      simp [hread] at hdecode
      by_cases hfit : afterLen + lenU.toNat ≤ state.canonicalValues.size
      · simp only [if_pos hfit] at hdecode
        cases hval :
            validateValueBytesV1 data.types stateDecl.typeId
              (state.canonicalValues.extract afterLen
                (afterLen + lenU.toNat)) with
        | error e =>
            simp [hval] at hdecode
        | ok _u =>
            simp [hval] at hdecode
            by_cases htrail :
                afterLen + lenU.toNat = state.canonicalValues.size
            · simp only [if_pos htrail] at hdecode
              -- Success: Except.ok #[slice] = Except.ok values
              have hvals :
                  values =
                    #[state.canonicalValues.extract afterLen
                        (afterLen + lenU.toNat)] :=
                (Except.ok.inj hdecode).symm
              exact ⟨_, hvals, hval⟩
            · simp only [if_neg htrail] at hdecode
              cases hdecode
      · simp only [if_neg hfit] at hdecode
        cases hdecode

/-- A validated program with one UInt64 state slot and no initializer starts
    initialized with the exact length-prefixed eight-byte zero value. This is a
    refinement of the sole production default/state encoder, not a second state
    constructor. -/
theorem initialLogicalStateV1_single_uint64_no_initializer_eq_ok
    (program : SemanticProgramV1) (data : SemanticProgramDataV1)
    (stateDecl : StateDeclV1) (typeDecl : TypeDeclV1)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hstate : data.logicalState = #[stateDecl])
    (htype : data.types[stateDecl.typeId.toNat]? = some typeDecl)
    (hshape : typeDecl.shape = .uint 64)
    (hnoInitializer : data.callables.any (fun c => c.kind == .initializer) = false)
    (hcanonical : validateValueBytesV1 data.types stateDecl.typeId
      (ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0]) = .ok ()) :
    initialLogicalStateV1 program = .ok {
      initialized := true
      canonicalValues := (encodeU32le 8).append
        (ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0])
    } := by
  let zero := ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0]
  have hdefault : defaultValueAtV1 data.types stateDecl.typeId maxNesting =
      .ok zero := by
    rw [show maxNesting = 255 + 1 by rfl, defaultValueAtV1.eq_2, htype]
    simp only [hshape, Pure.pure, Except.pure]
    rw [show (64 : UInt16).toNat / 8 = 8 by decide]
    congr 1
    simp [zeroBytesV1, List.range', zero]
    apply ByteArray.ext
    simp only [ByteArray.data_push]
    have hempty : (ByteArray.emptyWithCapacity 8).data = (#[] : Array UInt8) := by
      change (Array.emptyWithCapacity 8 : Array UInt8) = #[]
      exact Array.emptyWithCapacity_eq
    rw [hempty]
    rfl
  unfold initialLogicalStateV1
  rw [hvalidate]
  simp only [Bind.bind, Except.bind]
  rw [hstate]
  simp [hdefault, hnoInitializer, Pure.pure, Except.pure, Bind.bind, Except.bind]
  unfold encodeLogicalStateValuesV1
  simp only [hstate]
  have hcanonical' : validateValueBytesV1 data.types stateDecl.typeId zero = .ok () := by
    simpa [zero] using hcanonical
  have hzeroSize : zero.size = 8 := by rfl
  have hslot : encodeStateSlotV1 zero = .ok ((encodeU32le 8).append zero) := by
    unfold encodeStateSlotV1
    simp [hzeroSize, Pure.pure, Except.pure, Bind.bind, Except.bind]
  simp [hcanonical', hslot, zero, Pure.pure, Except.pure,
    Bind.bind, Except.bind]

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

/-- Construct conformance from the exact successful carrier validation,
    initialized bit, and sole production logical-state decoder result. -/
theorem stateConformsV1_intro_of_validate_eq_ok
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (state : LogicalStateV1)
    (values : Array ByteArray)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hinitialized : state.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data state = .ok values) :
    StateConformsV1 program state := by
  unfold StateConformsV1 stateConformsBoolV1
  rw [hvalidate]
  simp only [hinitialized, Bool.not_true, Bool.false_eq_true, ↓reduceIte,
    hdecode]

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
