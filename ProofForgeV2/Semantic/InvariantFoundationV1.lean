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

/-- Tail-recursive source-order encoder for logical-state slots. Arity mismatch
    is rejected before any partial state can be constructed; every payload
    still passes through the sole public valueBytes validator and slot encoder.
    `canonical` is the production accumulator, defaulted to the empty carrier. -/
private def encodeLogicalStateSlotsV1
    (types : Array TypeDeclV1)
    (decls : List StateDeclV1)
    (values : List ByteArray)
    (canonical : ByteArray := ByteArray.empty) :
    Except SemanticWireErrorV1 ByteArray :=
  match decls, values with
  | [], [] => pure canonical
  | decl :: restDecls, valueBytes :: restValues => do
      validateValueBytesV1 types decl.typeId valueBytes
      let slot ← encodeStateSlotV1 valueBytes
      encodeLogicalStateSlotsV1 types restDecls restValues (canonical.append slot)
  | _, _ => err .nonCanonical

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
    Except SemanticWireErrorV1 (Array ByteArray × Nat) :=
  match decls with
  | [] => pure (acc, offset)
  | decl :: rest => do
      let (lenU, afterLen) ← readU32leAtV1 canonicalValues offset
      let len := lenU.toNat
      unless afterLen + len ≤ canonicalValues.size do
        return ← err .truncated
      let slice := canonicalValues.extract afterLen (afterLen + len)
      validateValueBytesV1 types decl.typeId slice
      decodeLogicalStateSlotsV1 types rest canonicalValues (afterLen + len)
        (acc.push slice)

/-- A successful production slot decode has output cardinality equal to the
    initial accumulator plus the declaration count. This is an arity fact about
    the sole decoder, not a second state-shape checker. -/
private theorem decodeLogicalStateSlotsV1_size
    (types : Array TypeDeclV1)
    (decls : List StateDeclV1)
    (canonicalValues : ByteArray)
    (offset : Nat)
    (acc values : Array ByteArray)
    (after : Nat)
    (hdecode :
      decodeLogicalStateSlotsV1 types decls canonicalValues offset acc =
        .ok (values, after)) :
    values.size = acc.size + decls.length := by
  induction decls generalizing offset acc values after with
  | nil =>
      simp only [decodeLogicalStateSlotsV1, Pure.pure, Except.pure] at hdecode
      have hpair : (acc, offset) = (values, after) := Except.ok.inj hdecode
      have hvalues : acc = values := congrArg Prod.fst hpair
      subst values
      simp
  | cons decl rest ih =>
      unfold decodeLogicalStateSlotsV1 at hdecode
      cases hread : readU32leAtV1 canonicalValues offset with
      | error error =>
          simp [hread, Bind.bind, Except.bind] at hdecode
      | ok pair =>
          rcases pair with ⟨lenU, afterLen⟩
          simp only [hread, Bind.bind, Except.bind, Pure.pure, Except.pure] at hdecode
          by_cases hfit : afterLen + lenU.toNat ≤ canonicalValues.size
          · simp only [if_pos hfit] at hdecode
            cases hcanonical :
                validateValueBytesV1 types decl.typeId
                  (canonicalValues.extract afterLen (afterLen + lenU.toNat)) with
            | error error =>
                simp [hcanonical, Bind.bind, Except.bind] at hdecode
            | ok unit =>
                cases unit
                simp only [hcanonical, Bind.bind, Except.bind] at hdecode
                have hrest :=
                  ih (afterLen + lenU.toNat)
                    (acc.push
                      (canonicalValues.extract afterLen (afterLen + lenU.toNat)))
                    values after hdecode
                simp only [Array.size_push, List.length_cons] at hrest ⊢
                omega
          · simp only [if_neg hfit, err] at hdecode
            cases hdecode

/-- Parse `canonicalValues` into per-slot valueBytes arrays.

    Each slot is `u32le len || valueBytes` in `logicalState` order; every
    valueBytes is checked by the unique public `validateValueBytesV1`. Missing
    bytes, trailing bytes, or non-canonical values fail closed. -/
def decodeLogicalStateValuesV1 (data : SemanticProgramDataV1) (state : LogicalStateV1) :
    Except SemanticWireErrorV1 (Array ByteArray) :=
  do
    let (values, offset) ←
      decodeLogicalStateSlotsV1 data.types data.logicalState.toList
        state.canonicalValues 0
        (Array.emptyWithCapacity data.logicalState.size)
    unless offset == state.canonicalValues.size do
      return ← err .trailingBytes
    pure values

/-- Every successful production logical-state decode returns an array whose
    size equals the logical-state declaration count. Generated typed projections
    use this theorem instead of repeating an arity parser. -/
theorem decodeLogicalStateValuesV1_size
    (data : SemanticProgramDataV1)
    (state : LogicalStateV1)
    (values : Array ByteArray)
    (hdecode : decodeLogicalStateValuesV1 data state = .ok values) :
    values.size = data.logicalState.size := by
  unfold decodeLogicalStateValuesV1 at hdecode
  cases hslots :
      decodeLogicalStateSlotsV1 data.types data.logicalState.toList
        state.canonicalValues 0
        #[] with
  | error error =>
      simp [Array.emptyWithCapacity_eq, hslots, Bind.bind, Except.bind] at hdecode
  | ok pair =>
      rcases pair with ⟨decoded, after⟩
      simp only [Array.emptyWithCapacity_eq, hslots, Bind.bind, Except.bind,
        Pure.pure, Except.pure] at hdecode
      by_cases htrail : (after == state.canonicalValues.size) = true
      · simp only [htrail, ↓reduceIte] at hdecode
        have hvalues : decoded = values := Except.ok.inj hdecode
        have hsize :=
          decodeLogicalStateSlotsV1_size data.types data.logicalState.toList
            state.canonicalValues 0
            #[] decoded after hslots
        rw [hvalues] at hsize
        simpa using hsize
      · simp [htrail, err] at hdecode

/-- Build a `LogicalStateV1` from per-slot valueBytes.

    Arity must match `data.logicalState`; each value is structure-gated by
    `validateValueBytesV1` before length-prefix concatenation. -/
def encodeLogicalStateValuesV1 (data : SemanticProgramDataV1) (initialized : Bool)
    (values : Array ByteArray) : Except SemanticWireErrorV1 LogicalStateV1 := do
  unless values.size == data.logicalState.size do
    return ← err .nonCanonical
  let canonical ←
    encodeLogicalStateSlotsV1 data.types data.logicalState.toList values.toList
  pure { initialized, canonicalValues := canonical }

/-- Successful tail-recursive encoding preserves its exact input prefix. -/
private theorem encodeLogicalStateSlotsV1_prefix
    (types : Array TypeDeclV1)
    (decls : List StateDeclV1)
    (values : List ByteArray)
    (left encoded : ByteArray)
    (hencode : encodeLogicalStateSlotsV1 types decls values left = .ok encoded) :
    ∃ suffix, encoded = left ++ suffix := by
  induction decls generalizing values left encoded with
  | nil =>
      cases values with
      | nil =>
          simp only [encodeLogicalStateSlotsV1, Pure.pure, Except.pure] at hencode
          have hencoded : encoded = left :=
            (Except.ok.inj hencode).symm
          exact ⟨ByteArray.empty, by simp [hencoded]⟩
      | cons value restValues =>
          simp [encodeLogicalStateSlotsV1] at hencode
          cases hencode
  | cons decl restDecls ih =>
      cases values with
      | nil =>
          simp [encodeLogicalStateSlotsV1] at hencode
          cases hencode
      | cons valueBytes restValues =>
          unfold encodeLogicalStateSlotsV1 at hencode
          cases hcanonical : validateValueBytesV1 types decl.typeId valueBytes with
          | error error =>
              simp [hcanonical, Bind.bind, Except.bind] at hencode
          | ok unit =>
              cases unit
              simp only [hcanonical, Bind.bind, Except.bind] at hencode
              cases hslot : encodeStateSlotV1 valueBytes with
              | error error =>
                  simp [hslot] at hencode
              | ok slot =>
                  simp only [hslot] at hencode
                  obtain ⟨suffix, hsuffix⟩ :=
                    ih restValues (left ++ slot) encoded hencode
                  exact ⟨slot ++ suffix, by simpa [ByteArray.append_assoc] using hsuffix⟩

/-- The production logical-state decoder inverts the production slot encoder.
    The generalized production-accumulator statement lets the proof follow the
    decoder's source-order cursor without introducing a proof-only codec. -/
private theorem decodeLogicalStateSlotsV1_of_encodeLogicalStateSlotsV1
    (types : Array TypeDeclV1)
    (decls : List StateDeclV1)
    (values : List ByteArray)
    (encoded left : ByteArray)
    (acc : Array ByteArray)
    (hencode : encodeLogicalStateSlotsV1 types decls values left = .ok encoded) :
    decodeLogicalStateSlotsV1 types decls encoded left.size acc =
      .ok (acc ++ values.toArray, encoded.size) := by
  induction decls generalizing values encoded left acc with
  | nil =>
      cases values with
      | nil =>
          simp only [encodeLogicalStateSlotsV1, Pure.pure, Except.pure] at hencode
          have hencoded : encoded = left :=
            (Except.ok.inj hencode).symm
          subst encoded
          simp [decodeLogicalStateSlotsV1, Pure.pure, Except.pure]
      | cons value restValues =>
          simp [encodeLogicalStateSlotsV1] at hencode
          cases hencode
  | cons decl restDecls ih =>
      cases values with
      | nil =>
          simp [encodeLogicalStateSlotsV1] at hencode
          cases hencode
      | cons valueBytes restValues =>
          unfold encodeLogicalStateSlotsV1 at hencode
          cases hcanonical : validateValueBytesV1 types decl.typeId valueBytes with
          | error error =>
              simp [hcanonical, Bind.bind, Except.bind] at hencode
          | ok unit =>
              cases unit
              simp only [hcanonical, Bind.bind, Except.bind] at hencode
              cases hslot : encodeStateSlotV1 valueBytes with
              | error error =>
                  simp [hslot] at hencode
              | ok slot =>
                  simp only [hslot] at hencode
                  obtain ⟨suffix, hsuffix⟩ :=
                    encodeLogicalStateSlotsV1_prefix types restDecls restValues
                      (left ++ slot) encoded hencode
                  have hle : valueBytes.size ≤ UInt32.size - 1 := by
                    by_cases hle : valueBytes.size ≤ UInt32.size - 1
                    · exact hle
                    · unfold encodeStateSlotV1 at hslot
                      simp only [if_neg hle, err] at hslot
                      cases hslot
                  have hslotEq :
                      slot =
                        encodeU32le (UInt32.ofNat valueBytes.size) ++ valueBytes := by
                    unfold encodeStateSlotV1 at hslot
                    simp only [if_pos hle, Pure.pure, Except.pure] at hslot
                    exact (Except.ok.inj hslot).symm
                  have hlen :
                      (UInt32.ofNat valueBytes.size).toNat = valueBytes.size := by
                    rw [UInt32.toNat_ofNat', Nat.mod_eq_of_lt]
                    exact Nat.lt_of_le_pred (by decide) hle
                  have hinput :
                      encoded =
                        left ++ encodeU32le (UInt32.ofNat valueBytes.size) ++
                          valueBytes ++ suffix := by
                    rw [hsuffix, hslotEq]
                    simp only [ByteArray.append_assoc]
                  rw [hinput]
                  unfold decodeLogicalStateSlotsV1
                  have hread :=
                    readU32le_encode_midV1 left (valueBytes ++ suffix)
                      (UInt32.ofNat valueBytes.size)
                  rw [ByteArray.append_assoc
                    (a := left ++ encodeU32le (UInt32.ofNat valueBytes.size))
                    (b := valueBytes) (c := suffix)]
                  rw [hread]
                  have hheaderSize :
                      (encodeU32le (UInt32.ofNat valueBytes.size)).size = 4 :=
                    encodeU32le_sizeV1 _
                  have hcanonicalSize :
                      (left ++ encodeU32le (UInt32.ofNat valueBytes.size) ++
                          (valueBytes ++ suffix)).size =
                        left.size + 4 + valueBytes.size + suffix.size := by
                    simp [ByteArray.size_append, hheaderSize]
                    omega
                  have hfit :
                      left.size + 4 + (UInt32.ofNat valueBytes.size).toNat ≤
                        (left ++ encodeU32le (UInt32.ofNat valueBytes.size) ++
                          (valueBytes ++ suffix)).size := by
                    rw [hlen, hcanonicalSize]
                    omega
                  simp only [Bind.bind, Except.bind, Pure.pure, Except.pure]
                  simp only [if_pos hfit]
                  have hextract :
                      (left ++ encodeU32le (UInt32.ofNat valueBytes.size) ++
                          (valueBytes ++ suffix)).extract
                            (left.size + 4)
                            (left.size + 4 +
                              (UInt32.ofNat valueBytes.size).toNat) =
                        valueBytes := by
                    have h :=
                      extract_mid_payloadV1
                        (left ++ encodeU32le (UInt32.ofNat valueBytes.size))
                        valueBytes suffix
                    have hleftSize :
                        (left ++ encodeU32le (UInt32.ofNat valueBytes.size)).size =
                          left.size + 4 := by
                      simp [ByteArray.size_append, hheaderSize]
                    simpa [hleftSize, hlen, ByteArray.append_assoc] using h
                  rw [hextract, hcanonical]
                  simp only [Bind.bind, Except.bind]
                  have hih := ih restValues encoded
                    (left ++ slot) (acc.push valueBytes) hencode
                  have hleftSlotSize :
                      (left ++ slot).size = left.size + 4 + valueBytes.size := by
                    rw [hslotEq]
                    simp [ByteArray.size_append, hheaderSize]
                    omega
                  have harray :
                      (acc.push valueBytes) ++ restValues.toArray =
                        acc ++ (valueBytes :: restValues).toArray := by
                    rw [List.toArray_cons, ← Array.append_assoc,
                      Array.append_singleton]
                  rw [hinput, harray, hleftSlotSize] at hih
                  simpa only [hlen, ByteArray.append_assoc] using hih

/-- Public codec law for the sole production logical-state encoder/decoder.
    In particular, successful encoding is enough to carry all arity,
    canonical-value, and slot-size premises needed by decoding. -/
theorem decodeLogicalStateValuesV1_of_encodeLogicalStateValuesV1
    (data : SemanticProgramDataV1)
    (initialized : Bool)
    (values : Array ByteArray)
    (state : LogicalStateV1)
    (hencode : encodeLogicalStateValuesV1 data initialized values = .ok state) :
    decodeLogicalStateValuesV1 data state = .ok values := by
  unfold encodeLogicalStateValuesV1 at hencode
  by_cases harity : values.size == data.logicalState.size
  · simp only [if_pos harity, Bind.bind, Except.bind] at hencode
    cases hslots :
        encodeLogicalStateSlotsV1 data.types data.logicalState.toList values.toList with
    | error error =>
        simp [hslots, Pure.pure, Except.pure, Bind.bind, Except.bind] at hencode
    | ok encoded =>
        simp only [hslots, Pure.pure, Except.pure] at hencode
        have hstate : state = { initialized, canonicalValues := encoded } :=
          (Except.ok.inj hencode).symm
        subst state
        unfold decodeLogicalStateValuesV1
        have hinvert :=
          decodeLogicalStateSlotsV1_of_encodeLogicalStateSlotsV1
            data.types data.logicalState.toList values.toList encoded
            ByteArray.empty (Array.emptyWithCapacity data.logicalState.size) hslots
        simp only [ByteArray.empty_append, ByteArray.size_empty, Nat.zero_add] at hinvert
        rw [hinvert]
        have hsize : values.size = data.logicalState.size := by
          exact of_decide_eq_true harity
        simp only [Pure.pure, Except.pure, Bind.bind, Except.bind]
        simp [Array.emptyWithCapacity_eq, Array.toArray_toList, hsize]
  · simp [harity, err] at hencode

theorem LogicalStateV1.initialized_of_encodeLogicalStateValuesV1
    (data : SemanticProgramDataV1)
    (initialized : Bool)
    (values : Array ByteArray)
    (state : LogicalStateV1)
    (hencode : encodeLogicalStateValuesV1 data initialized values = .ok state) :
    state.initialized = initialized := by
  unfold encodeLogicalStateValuesV1 at hencode
  by_cases harity : values.size == data.logicalState.size
  · simp only [if_pos harity, Bind.bind, Except.bind] at hencode
    cases hslots :
        encodeLogicalStateSlotsV1 data.types data.logicalState.toList values.toList with
    | error error =>
        simp [hslots, Pure.pure, Except.pure] at hencode
    | ok encoded =>
        simp only [hslots, Pure.pure, Except.pure] at hencode
        have hstate : state = { initialized, canonicalValues := encoded } :=
          (Except.ok.inj hencode).symm
        subst state
        rfl
  · simp [harity, err] at hencode

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
  simp [encodeLogicalStateSlotsV1, hcanonical, hslot, hsize,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

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

/-- Full extract identity: `b = b.extract 0 n ++ b.extract n b.size` when `n ≤ size`. -/
theorem ByteArray_eq_extract_append_extract
    (b : ByteArray) (n : Nat) (hn : n ≤ b.size) :
    b = b.extract 0 n ++ b.extract n b.size := by
  have hfull : b.extract 0 b.size = b := by
    ext1
    simp
  have hsplit :=
    ByteArray.extract_eq_extract_append_extract (a := b) (i := 0) (k := b.size) n
      (Nat.zero_le _) hn
  simpa [hfull] using hsplit.symm

/-- Successful `readU32leAtV1` always advances the cursor by exactly 4. -/
theorem readU32leAtV1_ok_offset
    (b : ByteArray) (off : Nat) (v : UInt32) (after : Nat)
    (h : readU32leAtV1 b off = .ok (v, after)) :
    after = off + 4 := by
  unfold readU32leAtV1 at h
  cases hb0 : readByteAtV1 b off with
  | error e => simp [hb0, Bind.bind, Except.bind] at h
  | ok b0 =>
    cases hb1 : readByteAtV1 b (off + 1) with
    | error e =>
        simp [hb0, hb1, Bind.bind, Pure.pure, Except.bind, Except.pure] at h
    | ok b1 =>
      cases hb2 : readByteAtV1 b (off + 2) with
      | error e =>
          simp [hb0, hb1, hb2, Bind.bind, Pure.pure, Except.bind, Except.pure]
            at h
      | ok b2 =>
        cases hb3 : readByteAtV1 b (off + 3) with
        | error e =>
            simp [hb0, hb1, hb2, hb3, Bind.bind, Pure.pure, Except.bind,
              Except.pure] at h
        | ok b3 =>
            simp [hb0, hb1, hb2, hb3, Bind.bind, Pure.pure, Except.bind,
              Except.pure] at h
            -- Residual is the pure pair equality after four successful reads.
            exact h.2.symm

/-- `readByteAtV1` success exposes the underlying `data` cell. -/
theorem readByteAtV1_ok_data
    (b : ByteArray) (i : Nat) (x : UInt8)
    (h : readByteAtV1 b i = .ok x) :
    b.data[i]? = some x := by
  unfold readByteAtV1 at h
  cases hg : b.data[i]? with
  | none => simp [hg] at h
  | some y =>
      simp [hg] at h
      exact hg ▸ congrArg some h

/-- `readByteAtV1` success recovers the indexed byte. -/
theorem readByteAtV1_ok_getElem
    (b : ByteArray) (i : Nat) (x : UInt8)
    (h : readByteAtV1 b i = .ok x)
    (hi : i < b.size) :
    b[i] = x := by
  have hd := readByteAtV1_ok_data b i x h
  have hbound : i < b.data.size := hi
  have hsome : b.data[i]? = some (b.data[i]'hbound) :=
    Array.getElem?_eq_getElem (xs := b.data) (i := i) hbound
  have heq : b.data[i]'hbound = x := Option.some_inj.mp (hsome.symm.trans hd)
  change b.data[i] = x
  exact heq

/-- Closed spelling of the LE length header used by single-slot UInt64 encode. -/
theorem encodeU32le_eight :
    encodeU32le (8 : UInt32) = ByteArray.mk #[8, 0, 0, 0] := rfl

private theorem uint8_toNat_eightV1 : (8 : UInt8).toNat = 8 := rfl
private theorem uint8_toNat_zeroV1 : (0 : UInt8).toNat = 0 := rfl

/-- If `readU32leAtV1 b 0 = .ok (8, 4)`, the 4-byte prefix is `encodeU32le 8`. -/
theorem readU32leAtV1_ok_eight_prefix
    (b : ByteArray)
    (h : readU32leAtV1 b 0 = .ok ((8 : UInt32), 4)) :
    b.extract 0 4 = encodeU32le (8 : UInt32) := by
  unfold readU32leAtV1 at h
  cases hb0 : readByteAtV1 b 0 with
  | error e => simp [hb0, Bind.bind, Except.bind] at h
  | ok b0 =>
    cases hb1 : readByteAtV1 b 1 with
    | error e =>
        simp [hb0, hb1, Bind.bind, Except.bind] at h
    | ok b1 =>
      cases hb2 : readByteAtV1 b 2 with
      | error e =>
          simp [hb0, hb1, hb2, Bind.bind, Except.bind] at h
      | ok b2 =>
        cases hb3 : readByteAtV1 b 3 with
        | error e =>
            simp [hb0, hb1, hb2, hb3, Bind.bind, Except.bind] at h
        | ok b3 =>
            -- Keep the ofNat residual (avoid toUInt32 rewrite) then inject.
            simp only [hb0, hb1, hb2, hb3, Bind.bind, Except.bind] at h
            have hpair :
                (UInt32.ofNat
                    (b0.toNat + b1.toNat * 256 + b2.toNat * 65536 +
                      b3.toNat * 16777216),
                  (4 : Nat)) =
                  ((8 : UInt32), 4) := by
              simpa [Pure.pure, Except.pure] using h
            have hU :
                UInt32.ofNat
                    (b0.toNat + b1.toNat * 256 + b2.toNat * 65536 +
                      b3.toNat * 16777216) =
                  (8 : UInt32) := (Prod.ext_iff.mp hpair).1
            have hb0lt : b0.toNat < 256 := UInt8.toNat_lt_size b0
            have hb1lt : b1.toNat < 256 := UInt8.toNat_lt_size b1
            have hb2lt : b2.toNat < 256 := UInt8.toNat_lt_size b2
            have hb3lt : b3.toNat < 256 := UInt8.toNat_lt_size b3
            have hmod :
                (b0.toNat + b1.toNat * 256 + b2.toNat * 65536 +
                  b3.toNat * 16777216) % 4294967296 = 8 := by
              have := congrArg UInt32.toNat hU
              simpa [UInt32.toNat_ofNat] using this
            have hlt :
                b0.toNat + b1.toNat * 256 + b2.toNat * 65536 +
                  b3.toNat * 16777216 < 4294967296 := by omega
            have hsum :
                b0.toNat + b1.toNat * 256 + b2.toNat * 65536 +
                  b3.toNat * 16777216 = 8 := by
              rwa [Nat.mod_eq_of_lt hlt] at hmod
            have hb0n : b0.toNat = 8 := by omega
            have hb1n : b1.toNat = 0 := by omega
            have hb2n : b2.toNat = 0 := by omega
            have hb3n : b3.toNat = 0 := by omega
            have hb0' : b0 = 8 :=
              UInt8.toNat_inj.1 (hb0n.trans uint8_toNat_eightV1.symm)
            have hb1' : b1 = 0 :=
              UInt8.toNat_inj.1 (hb1n.trans uint8_toNat_zeroV1.symm)
            have hb2' : b2 = 0 :=
              UInt8.toNat_inj.1 (hb2n.trans uint8_toNat_zeroV1.symm)
            have hb3' : b3 = 0 :=
              UInt8.toNat_inj.1 (hb3n.trans uint8_toNat_zeroV1.symm)
            have hsz : 4 ≤ b.size := by
              have hd3 := readByteAtV1_ok_data b 3 b3 hb3
              have hlt3 : 3 < b.data.size :=
                (Array.getElem?_eq_some_iff.mp hd3).1
              change 4 ≤ b.data.size
              exact Nat.succ_le_of_lt hlt3
            have h0lt : 0 < b.size := Nat.lt_of_lt_of_le (by decide : 0 < 4) hsz
            have h1lt : 1 < b.size := Nat.lt_of_lt_of_le (by decide : 1 < 4) hsz
            have h2lt : 2 < b.size := Nat.lt_of_lt_of_le (by decide : 2 < 4) hsz
            have h3lt : 3 < b.size := Nat.lt_of_lt_of_le (by decide : 3 < 4) hsz
            have g0 : b[0] = b0 := readByteAtV1_ok_getElem b 0 b0 hb0 h0lt
            have g1 : b[1] = b1 := readByteAtV1_ok_getElem b 1 b1 hb1 h1lt
            have g2 : b[2] = b2 := readByteAtV1_ok_getElem b 2 b2 hb2 h2lt
            have g3 : b[3] = b3 := readByteAtV1_ok_getElem b 3 b3 hb3 h3lt
            have hex :
                b.extract 0 4 = [b[0], b[1], b[2], b[3]].toByteArray :=
              ByteArray.extract_add_four (by omega : 0 + 4 ≤ b.size)
            rw [hex, g0, g1, g2, g3, hb0', hb1', hb2', hb3', encodeU32le_eight]
            rfl

/-- If `readU32leAtV1 b 0 = .ok (v, 4)`, the 4-byte prefix is `encodeU32le v`. -/
theorem readU32leAtV1_ok_prefix
    (b : ByteArray) (v : UInt32)
    (h : readU32leAtV1 b 0 = .ok (v, 4)) :
    b.extract 0 4 = encodeU32le v := by
  -- Reduce to the mid-offset encode identity after rebuilding the LE limbs.
  unfold readU32leAtV1 at h
  cases hb0 : readByteAtV1 b 0 with
  | error e => simp [hb0, Bind.bind, Except.bind] at h
  | ok b0 =>
    cases hb1 : readByteAtV1 b 1 with
    | error e => simp [hb0, hb1, Bind.bind, Except.bind] at h
    | ok b1 =>
      cases hb2 : readByteAtV1 b 2 with
      | error e => simp [hb0, hb1, hb2, Bind.bind, Except.bind] at h
      | ok b2 =>
        cases hb3 : readByteAtV1 b 3 with
        | error e =>
            simp [hb0, hb1, hb2, hb3, Bind.bind, Except.bind] at h
        | ok b3 =>
            simp only [hb0, hb1, hb2, hb3, Bind.bind, Except.bind] at h
            have hpair :
                (UInt32.ofNat
                    (b0.toNat + b1.toNat * 256 + b2.toNat * 65536 +
                      b3.toNat * 16777216),
                  (4 : Nat)) =
                  (v, 4) := by
              simpa [Pure.pure, Except.pure] using h
            have hU :
                UInt32.ofNat
                    (b0.toNat + b1.toNat * 256 + b2.toNat * 65536 +
                      b3.toNat * 16777216) =
                  v :=
              (Prod.ext_iff.mp hpair).1
            have hb0lt : b0.toNat < 256 := UInt8.toNat_lt_size b0
            have hb1lt : b1.toNat < 256 := UInt8.toNat_lt_size b1
            have hb2lt : b2.toNat < 256 := UInt8.toNat_lt_size b2
            have hb3lt : b3.toNat < 256 := UInt8.toNat_lt_size b3
            have hsum :
                b0.toNat + b1.toNat * 256 + b2.toNat * 65536 +
                  b3.toNat * 16777216 =
                  v.toNat := by
              have := congrArg UInt32.toNat hU
              have hmod :
                  (b0.toNat + b1.toNat * 256 + b2.toNat * 65536 +
                    b3.toNat * 16777216) % 4294967296 =
                    v.toNat := by
                simpa [UInt32.toNat_ofNat] using this
              have hlt :
                  b0.toNat + b1.toNat * 256 + b2.toNat * 65536 +
                    b3.toNat * 16777216 < 4294967296 := by omega
              rwa [Nat.mod_eq_of_lt hlt] at hmod
            have hb0n : b0.toNat = v.toNat % 256 := by omega
            have hb1n : b1.toNat = (v.toNat / 256) % 256 := by omega
            have hb2n : b2.toNat = (v.toNat / 65536) % 256 := by omega
            have hb3n : b3.toNat = (v.toNat / 16777216) % 256 := by omega
            have hb0' : b0 = UInt8.ofNat (v.toNat % 256) := by
              apply UInt8.toNat_inj.1
              simpa [UInt8_toNat_ofNat_mod256V1] using hb0n
            have hb1' : b1 = UInt8.ofNat ((v.toNat / 256) % 256) := by
              apply UInt8.toNat_inj.1
              simpa [UInt8_toNat_ofNat_mod256V1] using hb1n
            have hb2' : b2 = UInt8.ofNat ((v.toNat / 65536) % 256) := by
              apply UInt8.toNat_inj.1
              simpa [UInt8_toNat_ofNat_mod256V1] using hb2n
            have hb3' : b3 = UInt8.ofNat ((v.toNat / 16777216) % 256) := by
              apply UInt8.toNat_inj.1
              simpa [UInt8_toNat_ofNat_mod256V1] using hb3n
            have hsz : 4 ≤ b.size := by
              have hd3 := readByteAtV1_ok_data b 3 b3 hb3
              have hlt3 : 3 < b.data.size :=
                (Array.getElem?_eq_some_iff.mp hd3).1
              change 4 ≤ b.data.size
              exact Nat.succ_le_of_lt hlt3
            have g0 := readByteAtV1_ok_getElem b 0 b0 hb0
              (Nat.lt_of_lt_of_le (by decide : 0 < 4) hsz)
            have g1 := readByteAtV1_ok_getElem b 1 b1 hb1
              (Nat.lt_of_lt_of_le (by decide : 1 < 4) hsz)
            have g2 := readByteAtV1_ok_getElem b 2 b2 hb2
              (Nat.lt_of_lt_of_le (by decide : 2 < 4) hsz)
            have g3 := readByteAtV1_ok_getElem b 3 b3 hb3
              (Nat.lt_of_lt_of_le (by decide : 3 < 4) hsz)
            have hex :
                b.extract 0 4 = [b0, b1, b2, b3].toByteArray := by
              have h :=
                ByteArray.extract_add_four (a := b) (i := 0)
                  (by omega : 0 + 4 ≤ b.size)
              -- extract_add_four spells b[0+i]; rewrite with getElem facts.
              simp only [h, Nat.zero_add, g0, g1, g2, g3]
            rw [hex, hb0', hb1', hb2', hb3']
            -- encodeU32le is four successive pushes of the LE limbs (= list form).
            change
                [UInt8.ofNat (v.toNat % 256),
                  UInt8.ofNat ((v.toNat / 256) % 256),
                  UInt8.ofNat ((v.toNat / 65536) % 256),
                  UInt8.ofNat ((v.toNat / 16777216) % 256)].toByteArray =
                  encodeU32le v
            -- List.toByteArray = empty.push…push for length 4.
            have hlist (a b c d : UInt8) :
                [a, b, c, d].toByteArray =
                  (((ByteArray.empty.push a).push b).push c).push d := by
              -- `toByteArray` is a left-fold push over the list.
              simp [List.toByteArray, List.toByteArray.loop]
            simp only [encodeU32le]
            exact (hlist _ _ _ _).symm

private theorem uint32_toNat_eightV1 : (8 : UInt32).toNat = 8 := rfl

/-- Successful singleton UInt64-slot decode recovers the closed encode layout
    `encodeU32le 8 ++ valueBytes`. -/
theorem decodeLogicalStateValuesV1_singleton_uint64_layout
    (data : SemanticProgramDataV1)
    (stateDecl : StateDeclV1)
    (state : LogicalStateV1)
    (valueBytes : ByteArray)
    (hstate : data.logicalState = #[stateDecl])
    (hdecode : decodeLogicalStateValuesV1 data state = .ok #[valueBytes])
    (hsize : valueBytes.size = 8) :
    state.canonicalValues = encodeU32le (8 : UInt32) ++ valueBytes := by
  unfold decodeLogicalStateValuesV1 at hdecode
  have hlist : data.logicalState.toList = [stateDecl] := by
    simp [hstate]
  simp only [hlist, decodeLogicalStateSlotsV1, Pure.pure, Except.pure,
    Bind.bind, Except.bind, err] at hdecode
  cases hread : readU32leAtV1 state.canonicalValues 0 with
  | error e =>
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
              -- Residual is already `ok #[slice] = ok #[valueBytes]`.
              have harr :
                  #[state.canonicalValues.extract afterLen
                      (afterLen + lenU.toNat)] =
                    #[valueBytes] :=
                Except.ok.inj hdecode
              have hslice :
                  state.canonicalValues.extract afterLen
                      (afterLen + lenU.toNat) =
                    valueBytes := by
                have := congrArg (fun a : Array ByteArray => a[0]?) harr
                simpa using this
              have hafter : afterLen = 4 :=
                readU32leAtV1_ok_offset state.canonicalValues 0 lenU afterLen
                  hread
              have hex_sz :
                  (state.canonicalValues.extract afterLen
                    (afterLen + lenU.toNat)).size = lenU.toNat := by
                have hmin :
                    min (afterLen + lenU.toNat) state.canonicalValues.size =
                      afterLen + lenU.toNat :=
                  Nat.min_eq_left hfit
                simp [ByteArray.size_extract, hmin, Nat.add_sub_cancel_left]
              have hlen : lenU.toNat = 8 := by
                have : valueBytes.size = lenU.toNat := by
                  rw [← hslice, hex_sz]
                omega
              have hlenU : lenU = (8 : UInt32) :=
                UInt32.toNat_inj.1 (hlen.trans uint32_toNat_eightV1.symm)
              have hread8 :
                  readU32leAtV1 state.canonicalValues 0 =
                    .ok ((8 : UInt32), 4) := by
                rw [hread, hlenU, hafter]
              have hpref :
                  state.canonicalValues.extract 0 4 =
                    encodeU32le (8 : UInt32) :=
                readU32leAtV1_ok_eight_prefix state.canonicalValues hread8
              have hsz4 : 4 ≤ state.canonicalValues.size := by
                omega
              have hsplit :=
                ByteArray_eq_extract_append_extract state.canonicalValues 4 hsz4
              have hpay :
                  state.canonicalValues.extract 4 state.canonicalValues.size =
                    valueBytes := by
                calc
                  state.canonicalValues.extract 4 state.canonicalValues.size
                      = state.canonicalValues.extract afterLen
                          (afterLen + lenU.toNat) := by
                        congr 1 <;> omega
                  _ = valueBytes := hslice
              rw [hsplit, hpref, hpay]
            · simp only [if_neg htrail] at hdecode
              cases hdecode
      · simp only [if_neg hfit] at hdecode
        cases hdecode

/-- Encode of a successful singleton UInt64 decode recovers the same carrier
    (initialized stays true). This is the get-returned post=pre identity. -/
theorem encode_of_singleton_uint64_decode_eq
    (data : SemanticProgramDataV1)
    (stateDecl : StateDeclV1)
    (pre post : LogicalStateV1)
    (valueBytes : ByteArray)
    (hstate : data.logicalState = #[stateDecl])
    (hinit : pre.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data pre = .ok #[valueBytes])
    (hcan :
      validateValueBytesV1 data.types stateDecl.typeId valueBytes = .ok ())
    (hsize : valueBytes.size = 8)
    (hencode :
      encodeLogicalStateValuesV1 data true #[valueBytes] = .ok post) :
    post = pre := by
  have henc :=
    encodeLogicalStateValuesV1_single_uint64_eq_ok data stateDecl valueBytes true
      hstate hcan hsize
  have hpost :
      post = {
        initialized := true
        canonicalValues := encodeU32le (8 : UInt32) ++ valueBytes
      } := by
    have :
        encodeLogicalStateValuesV1 data true #[valueBytes] = .ok {
          initialized := true
          canonicalValues := encodeU32le (8 : UInt32) ++ valueBytes
        } := by
      -- encode lemma spells `.append`; defeq to `++`.
      simpa [HAppend.hAppend] using henc
    rw [this] at hencode
    exact (Except.ok.inj hencode).symm
  have hpre_layout :=
    decodeLogicalStateValuesV1_singleton_uint64_layout data stateDecl pre
      valueBytes hstate hdecode hsize
  have hpre :
      pre = {
        initialized := true
        canonicalValues := encodeU32le (8 : UInt32) ++ valueBytes
      } := by
    cases pre with
    | mk initialized canonicalValues =>
      simp only at hinit hpre_layout ⊢
      subst hinit
      subst hpre_layout
      rfl
  exact hpost.trans hpre.symm

/-- Singleton encode for any validated payload that fits the u32 length header. -/
theorem encodeLogicalStateValuesV1_singleton_eq_ok
    (data : SemanticProgramDataV1)
    (stateDecl : StateDeclV1)
    (valueBytes : ByteArray)
    (initialized : Bool)
    (hstate : data.logicalState = #[stateDecl])
    (hcanonical :
      validateValueBytesV1 data.types stateDecl.typeId valueBytes = .ok ())
    (hle : valueBytes.size ≤ UInt32.size - 1) :
    encodeLogicalStateValuesV1 data initialized #[valueBytes] = .ok {
      initialized
      canonicalValues :=
        (encodeU32le (UInt32.ofNat valueBytes.size)).append valueBytes
    } := by
  have hslot :
      encodeStateSlotV1 valueBytes =
        .ok ((encodeU32le (UInt32.ofNat valueBytes.size)).append valueBytes) := by
    unfold encodeStateSlotV1
    simp only [if_pos hle, Pure.pure, Except.pure, Bind.bind, Except.bind]
  unfold encodeLogicalStateValuesV1
  simp only [hstate]
  simp [encodeLogicalStateSlotsV1, hcanonical, hslot,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- Successful singleton decode recovers `encodeU32le len ++ payload` with
    `len.toNat = payload.size`. -/
theorem decodeLogicalStateValuesV1_singleton_layout
    (data : SemanticProgramDataV1)
    (stateDecl : StateDeclV1)
    (state : LogicalStateV1)
    (valueBytes : ByteArray)
    (hstate : data.logicalState = #[stateDecl])
    (hdecode : decodeLogicalStateValuesV1 data state = .ok #[valueBytes]) :
    ∃ lenU : UInt32,
      valueBytes.size = lenU.toNat ∧
      state.canonicalValues =
        encodeU32le lenU ++ valueBytes := by
  unfold decodeLogicalStateValuesV1 at hdecode
  have hlist : data.logicalState.toList = [stateDecl] := by
    simp [hstate]
  simp only [hlist, decodeLogicalStateSlotsV1, Pure.pure, Except.pure,
    Bind.bind, Except.bind, err] at hdecode
  cases hread : readU32leAtV1 state.canonicalValues 0 with
  | error e =>
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
              have harr :
                  #[state.canonicalValues.extract afterLen
                      (afterLen + lenU.toNat)] =
                    #[valueBytes] :=
                Except.ok.inj hdecode
              have hslice :
                  state.canonicalValues.extract afterLen
                      (afterLen + lenU.toNat) =
                    valueBytes := by
                have := congrArg (fun a : Array ByteArray => a[0]?) harr
                simpa using this
              have hafter : afterLen = 4 :=
                readU32leAtV1_ok_offset state.canonicalValues 0 lenU afterLen
                  hread
              have hex_sz :
                  (state.canonicalValues.extract afterLen
                    (afterLen + lenU.toNat)).size = lenU.toNat := by
                have hmin :
                    min (afterLen + lenU.toNat) state.canonicalValues.size =
                      afterLen + lenU.toNat :=
                  Nat.min_eq_left hfit
                simp [ByteArray.size_extract, hmin, Nat.add_sub_cancel_left]
              have hlen : valueBytes.size = lenU.toNat := by
                rw [← hslice, hex_sz]
              have hread' :
                  readU32leAtV1 state.canonicalValues 0 = .ok (lenU, 4) := by
                rw [hread, hafter]
              have hpref :
                  state.canonicalValues.extract 0 4 = encodeU32le lenU :=
                readU32leAtV1_ok_prefix state.canonicalValues lenU hread'
              have hsz4 : 4 ≤ state.canonicalValues.size := by omega
              have hsplit :=
                ByteArray_eq_extract_append_extract state.canonicalValues 4 hsz4
              have hpay :
                  state.canonicalValues.extract 4 state.canonicalValues.size =
                    valueBytes := by
                calc
                  state.canonicalValues.extract 4 state.canonicalValues.size
                      = state.canonicalValues.extract afterLen
                          (afterLen + lenU.toNat) := by
                        congr 1 <;> omega
                  _ = valueBytes := hslice
              refine ⟨lenU, hlen, ?_⟩
              rw [hsplit, hpref, hpay]
            · simp only [if_neg htrail] at hdecode
              cases hdecode
      · simp only [if_neg hfit] at hdecode
        cases hdecode

/-- Get-returned identity without hardcoding width 8: encode of the decoded
    singleton payload recovers the pre carrier. -/
theorem encode_of_singleton_decode_eq
    (data : SemanticProgramDataV1)
    (stateDecl : StateDeclV1)
    (pre post : LogicalStateV1)
    (valueBytes : ByteArray)
    (hstate : data.logicalState = #[stateDecl])
    (hinit : pre.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data pre = .ok #[valueBytes])
    (hcan :
      validateValueBytesV1 data.types stateDecl.typeId valueBytes = .ok ())
    (hencode :
      encodeLogicalStateValuesV1 data true #[valueBytes] = .ok post) :
    post = pre := by
  have hle := validateValueBytesV1_size_le_u32 data.types stateDecl.typeId
    valueBytes hcan
  have henc :=
    encodeLogicalStateValuesV1_singleton_eq_ok data stateDecl valueBytes true
      hstate hcan hle
  have hpost :
      post = {
        initialized := true
        canonicalValues :=
          (encodeU32le (UInt32.ofNat valueBytes.size)).append valueBytes
      } := by
    rw [henc] at hencode
    exact (Except.ok.inj hencode).symm
  rcases decodeLogicalStateValuesV1_singleton_layout data stateDecl pre
      valueBytes hstate hdecode with ⟨lenU, hlen, hlayout⟩
  have hlenU : UInt32.ofNat valueBytes.size = lenU := by
    apply UInt32.toNat_inj.1
    have hbound : valueBytes.size < UInt32.size := by
      -- hle : size ≤ 2^32 - 1
      have : valueBytes.size ≤ UInt32.size - 1 := hle
      exact Nat.lt_of_le_of_lt this (by decide : UInt32.size - 1 < UInt32.size)
    have hmod : (UInt32.ofNat valueBytes.size).toNat = valueBytes.size := by
      simpa [UInt32.toNat_ofNat, Nat.mod_eq_of_lt hbound]
    rw [hmod, hlen]
  have hpre :
      pre = {
        initialized := true
        canonicalValues :=
          (encodeU32le (UInt32.ofNat valueBytes.size)).append valueBytes
      } := by
    cases pre with
    | mk initialized canonicalValues =>
      simp only at hinit hlayout ⊢
      subst hinit
      rw [hlayout, hlenU]
      rfl
  exact hpost.trans hpre.symm

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
  simp [encodeLogicalStateSlotsV1, hcanonical', hslot, zero, Pure.pure, Except.pure,
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






/-! ### Triple UInt64 logical-state packing (multi-state L1 preservation) -/

/-- Exact triple length-prefixed UInt64 layout (declaration order).
    Left-associated `++` form matches encoder forIn accumulation (via
    `ByteArray.append_assoc`) and Codec mid-offset lemmas. -/
def tripleUint64CanonicalV1 (b0 b1 b2 : ByteArray) : ByteArray :=
  encodeU32le (8 : UInt32) ++ b0 ++ encodeU32le (8 : UInt32) ++ b1 ++
    encodeU32le (8 : UInt32) ++ b2

private theorem array_push3_eq
    (b0 b1 b2 : ByteArray) :
    ((((Array.emptyWithCapacity 3).push b0).push b1).push b2) = #[b0, b1, b2] := by
  apply Array.ext
  · simp [Array.emptyWithCapacity_eq]
  · intro i hi hi'
    match i with
    | 0 => simp
    | 1 => simp
    | 2 => simp
    | n + 3 =>
        have : n + 3 < 3 := by
          simpa [Array.size_push, Array.emptyWithCapacity_eq] using hi
        omega

/-- Triple public-UInt64 encode under successful valueBytes gates. -/
theorem encodeLogicalStateValuesV1_triple_uint64_eq_ok
    (data : SemanticProgramDataV1)
    (s0 s1 s2 : StateDeclV1)
    (b0 b1 b2 : ByteArray)
    (initialized : Bool)
    (hstate : data.logicalState = #[s0, s1, s2])
    (hc0 : validateValueBytesV1 data.types s0.typeId b0 = .ok ())
    (hc1 : validateValueBytesV1 data.types s1.typeId b1 = .ok ())
    (hc2 : validateValueBytesV1 data.types s2.typeId b2 = .ok ())
    (hs0 : b0.size = 8) (hs1 : b1.size = 8) (hs2 : b2.size = 8) :
    encodeLogicalStateValuesV1 data initialized #[b0, b1, b2] = .ok {
      initialized
      canonicalValues := tripleUint64CanonicalV1 b0 b1 b2
    } := by
  have hslot0 :
      encodeStateSlotV1 b0 = .ok ((encodeU32le 8).append b0) := by
    unfold encodeStateSlotV1
    have hle : b0.size ≤ UInt32.size - 1 := by simp [hs0]
    have hsz : UInt32.ofNat b0.size = 8 := by simp [hs0]
    simp only [if_pos hle, hsz, Pure.pure, Except.pure, Bind.bind, Except.bind]
  have hslot1 :
      encodeStateSlotV1 b1 = .ok ((encodeU32le 8).append b1) := by
    unfold encodeStateSlotV1
    have hle : b1.size ≤ UInt32.size - 1 := by simp [hs1]
    have hsz : UInt32.ofNat b1.size = 8 := by simp [hs1]
    simp only [if_pos hle, hsz, Pure.pure, Except.pure, Bind.bind, Except.bind]
  have hslot2 :
      encodeStateSlotV1 b2 = .ok ((encodeU32le 8).append b2) := by
    unfold encodeStateSlotV1
    have hle : b2.size ≤ UInt32.size - 1 := by simp [hs2]
    have hsz : UInt32.ofNat b2.size = 8 := by simp [hs2]
    simp only [if_pos hle, hsz, Pure.pure, Except.pure, Bind.bind, Except.bind]
  unfold encodeLogicalStateValuesV1
  simp only [hstate]
  simp [encodeLogicalStateSlotsV1, hc0, hc1, hc2, hslot0, hslot1, hslot2,
    Pure.pure, Except.pure, Bind.bind, Except.bind, ByteArray.empty_append]
  -- forIn: ((s0++s1)++s2) with si = enc++bi; flatten to mid-friendly layout
  simp [tripleUint64CanonicalV1, ByteArray.append_assoc]

/-- Mid-lemma: read UInt64 length header at `left.size` in a 4+8+… layout. -/
private theorem read_uint64_slot_headerV1
    (left payload right : ByteArray) :
    readU32leAtV1
        (left ++ encodeU32le (8 : UInt32) ++ payload ++ right) left.size =
      .ok ((8 : UInt32), left.size + 4) := by
  have h :=
    readU32le_encode_midV1 left (payload ++ right) (8 : UInt32)
  -- mid: left ++ enc ++ (payload ++ right)
  -- goal layout: left ++ enc ++ payload ++ right
  have heq :
      left ++ encodeU32le (8 : UInt32) ++ (payload ++ right) =
        left ++ encodeU32le (8 : UInt32) ++ payload ++ right := by
    simp [ByteArray.append_assoc]
  rwa [heq] at h

/-- Mid-lemma: extract the 8-byte payload after a UInt64 length header. -/
private theorem extract_uint64_slot_payloadV1
    (left payload right : ByteArray)
    (hsize : payload.size = 8) :
    (left ++ encodeU32le (8 : UInt32) ++ payload ++ right).extract
        (left.size + 4) (left.size + 4 + 8) =
      payload := by
  have h :=
    extract_mid_payloadV1 (left ++ encodeU32le (8 : UInt32)) payload right
  have hleft : (left ++ encodeU32le (8 : UInt32)).size = left.size + 4 := by
    simp [ByteArray.size_append, encodeU32le_sizeV1]
  simp only [hleft, hsize] at h
  -- (left++enc) ++ payload ++ right  =  left ++ enc ++ payload ++ right
  simpa [ByteArray.append_assoc] using h

/-- Decode recovers three UInt64 payloads from the exact triple encode layout. -/
theorem decodeLogicalStateValuesV1_of_triple_uint64_encode
    (data : SemanticProgramDataV1)
    (s0 s1 s2 : StateDeclV1)
    (b0 b1 b2 : ByteArray)
    (initialized : Bool)
    (hstate : data.logicalState = #[s0, s1, s2])
    (hc0 : validateValueBytesV1 data.types s0.typeId b0 = .ok ())
    (hc1 : validateValueBytesV1 data.types s1.typeId b1 = .ok ())
    (hc2 : validateValueBytesV1 data.types s2.typeId b2 = .ok ())
    (hs0 : b0.size = 8) (hs1 : b1.size = 8) (hs2 : b2.size = 8) :
    decodeLogicalStateValuesV1 data {
      initialized
      canonicalValues := tripleUint64CanonicalV1 b0 b1 b2
    } = .ok #[b0, b1, b2] := by
  let state : LogicalStateV1 := {
    initialized
    canonicalValues := tripleUint64CanonicalV1 b0 b1 b2
  }
  change decodeLogicalStateValuesV1 data state = .ok #[b0, b1, b2]
  have hhdr : (encodeU32le (8 : UInt32)).size = 4 := encodeU32le_sizeV1 8
  have hlist : data.logicalState.toList = [s0, s1, s2] := by simp [hstate]
  have h8 : (8 : UInt32).toNat = 8 := by decide
  have hsz : state.canonicalValues.size = 36 := by
    simp [state, tripleUint64CanonicalV1, ByteArray.size_append, hhdr,
      hs0, hs1, hs2]
  -- Slot 0 @ 0
  have hread0 :
      readU32leAtV1 state.canonicalValues 0 = .ok ((8 : UInt32), 4) := by
    have h :=
      read_uint64_slot_headerV1 ByteArray.empty b0
        (encodeU32le (8 : UInt32) ++ b1 ++ encodeU32le (8 : UInt32) ++ b2)
    simpa [state, tripleUint64CanonicalV1, ByteArray.size_empty,
      ByteArray.empty_append, ByteArray.append_assoc] using h
  have hex0 :
      state.canonicalValues.extract 4 (4 + (8 : UInt32).toNat) = b0 := by
    have h :=
      extract_uint64_slot_payloadV1 ByteArray.empty b0
        (encodeU32le (8 : UInt32) ++ b1 ++ encodeU32le (8 : UInt32) ++ b2) hs0
    simpa [state, tripleUint64CanonicalV1, ByteArray.size_empty, h8,
      ByteArray.empty_append, ByteArray.append_assoc] using h
  have hfit0 : 4 + (8 : UInt32).toNat ≤ state.canonicalValues.size := by
    simp [hsz, h8]
  -- Slot 1 @ residual offset 4+toNat 8
  have hleft0 : (encodeU32le (8 : UInt32) ++ b0).size = 12 := by
    simp [ByteArray.size_append, hhdr, hs0]
  have hread1 :
      readU32leAtV1 state.canonicalValues (4 + (8 : UInt32).toNat) =
        .ok ((8 : UInt32), 4 + (8 : UInt32).toNat + 4) := by
    have h :=
      read_uint64_slot_headerV1
        (encodeU32le (8 : UInt32) ++ b0) b1
        (encodeU32le (8 : UInt32) ++ b2)
    have hnum :
        readU32leAtV1
            (encodeU32le (8 : UInt32) ++ b0 ++ encodeU32le (8 : UInt32) ++ b1 ++
              (encodeU32le (8 : UInt32) ++ b2))
            12 =
          .ok ((8 : UInt32), 16) := by
      simpa [hleft0] using h
    have hflat :
        readU32leAtV1 (tripleUint64CanonicalV1 b0 b1 b2) 12 =
          .ok ((8 : UInt32), 16) := by
      simpa [tripleUint64CanonicalV1, ByteArray.append_assoc] using hnum
    simpa [state, h8] using hflat
  have hex1 :
      state.canonicalValues.extract
          (4 + (8 : UInt32).toNat + 4)
          (4 + (8 : UInt32).toNat + 4 + (8 : UInt32).toNat) =
        b1 := by
    have h :=
      extract_uint64_slot_payloadV1
        (encodeU32le (8 : UInt32) ++ b0) b1
        (encodeU32le (8 : UInt32) ++ b2) hs1
    have hnum :
        (encodeU32le (8 : UInt32) ++ b0 ++ encodeU32le (8 : UInt32) ++ b1 ++
            (encodeU32le (8 : UInt32) ++ b2)).extract
          16 (16 + 8) =
        b1 := by
      simpa [hleft0] using h
    have hflat :
        (tripleUint64CanonicalV1 b0 b1 b2).extract 16 (16 + (8 : UInt32).toNat) =
          b1 := by
      have hx :
          (tripleUint64CanonicalV1 b0 b1 b2).extract 16 (16 + 8) = b1 := by
        simpa [tripleUint64CanonicalV1, ByteArray.append_assoc] using hnum
      simpa [h8] using hx
    simpa [state, h8] using hflat
  have hfit1 :
      (4 + (8 : UInt32).toNat + 4) + (8 : UInt32).toNat ≤
        state.canonicalValues.size := by
    simp [hsz, h8]
  -- Slot 2
  have hleft01 :
      (encodeU32le (8 : UInt32) ++ b0 ++ encodeU32le (8 : UInt32) ++ b1).size =
        24 := by
    simp [ByteArray.size_append, hhdr, hs0, hs1]
  have hread2 :
      readU32leAtV1 state.canonicalValues
          (4 + (8 : UInt32).toNat + 4 + (8 : UInt32).toNat) =
        .ok ((8 : UInt32),
          4 + (8 : UInt32).toNat + 4 + (8 : UInt32).toNat + 4) := by
    have h :=
      read_uint64_slot_headerV1
        (encodeU32le (8 : UInt32) ++ b0 ++ encodeU32le (8 : UInt32) ++ b1)
        b2 ByteArray.empty
    have hnum :
        readU32leAtV1
            (encodeU32le (8 : UInt32) ++ b0 ++ encodeU32le (8 : UInt32) ++ b1 ++
              encodeU32le (8 : UInt32) ++ b2 ++ ByteArray.empty)
            24 =
          .ok ((8 : UInt32), 28) := by
      simpa [hleft01] using h
    have hflat :
        readU32leAtV1 (tripleUint64CanonicalV1 b0 b1 b2) 24 =
          .ok ((8 : UInt32), 28) := by
      simpa [tripleUint64CanonicalV1, ByteArray.append_empty] using hnum
    simpa [state, h8] using hflat
  have hex2 :
      state.canonicalValues.extract
          (4 + (8 : UInt32).toNat + 4 + (8 : UInt32).toNat + 4)
          (4 + (8 : UInt32).toNat + 4 + (8 : UInt32).toNat + 4 +
            (8 : UInt32).toNat) =
        b2 := by
    have h :=
      extract_uint64_slot_payloadV1
        (encodeU32le (8 : UInt32) ++ b0 ++ encodeU32le (8 : UInt32) ++ b1)
        b2 ByteArray.empty hs2
    have hnum :
        (encodeU32le (8 : UInt32) ++ b0 ++ encodeU32le (8 : UInt32) ++ b1 ++
            encodeU32le (8 : UInt32) ++ b2 ++ ByteArray.empty).extract
          28 (28 + 8) =
        b2 := by
      simpa [hleft01] using h
    have hflat :
        (tripleUint64CanonicalV1 b0 b1 b2).extract 28 (28 + (8 : UInt32).toNat) =
          b2 := by
      have hx :
          (tripleUint64CanonicalV1 b0 b1 b2).extract 28 (28 + 8) = b2 := by
        simpa [tripleUint64CanonicalV1, ByteArray.append_empty] using hnum
      simpa [h8] using hx
    simpa [state, h8] using hflat
  have hfit2 :
      (4 + (8 : UInt32).toNat + 4 + (8 : UInt32).toNat + 4) +
          (8 : UInt32).toNat ≤
        state.canonicalValues.size := by
    simp [hsz, h8]
  have htrail :
      (4 + (8 : UInt32).toNat + 4 + (8 : UInt32).toNat + 4) +
          (8 : UInt32).toNat =
        state.canonicalValues.size := by
    simp [hsz, h8]
  unfold decodeLogicalStateValuesV1
  simp only [hlist, decodeLogicalStateSlotsV1, Pure.pure, Except.pure,
    Bind.bind, Except.bind, err]
  rw [hread0]
  simp only [if_pos hfit0, hex0, hc0, Bind.bind, Except.bind]
  rw [hread1]
  simp only [if_pos hfit1, hex1, hc1, Bind.bind, Except.bind]
  rw [hread2]
  simp only [if_pos hfit2, hex2, hc2, Bind.bind, Except.bind]
  simp only [decodeLogicalStateSlotsV1, htrail, ↓reduceIte, Pure.pure,
    Except.pure]
  simpa [array_push3_eq b0 b1 b2]

/-- No-initializer product initial state for three public UInt64 slots. -/
theorem initialLogicalStateV1_triple_uint64_no_initializer_eq_ok
    (program : SemanticProgramV1) (data : SemanticProgramDataV1)
    (s0 s1 s2 : StateDeclV1) (typeDecl : TypeDeclV1)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hstate : data.logicalState = #[s0, s1, s2])
    (ht0 : data.types[s0.typeId.toNat]? = some typeDecl)
    (ht1 : data.types[s1.typeId.toNat]? = some typeDecl)
    (ht2 : data.types[s2.typeId.toNat]? = some typeDecl)
    (hshape : typeDecl.shape = .uint 64)
    (hnoInitializer :
      data.callables.any (fun c => c.kind == .initializer) = false)
    (hz0 : validateValueBytesV1 data.types s0.typeId
      (ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0]) = .ok ())
    (hz1 : validateValueBytesV1 data.types s1.typeId
      (ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0]) = .ok ())
    (hz2 : validateValueBytesV1 data.types s2.typeId
      (ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0]) = .ok ()) :
    initialLogicalStateV1 program = .ok {
      initialized := true
      canonicalValues :=
        tripleUint64CanonicalV1
          (ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0])
          (ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0])
          (ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0])
    } := by
  let zero := ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0]
  have hdef (tid : TypeIdV1)
      (hlookup : data.types[tid.toNat]? = some typeDecl) :
      defaultValueAtV1 data.types tid maxNesting = .ok zero := by
    rw [show maxNesting = 255 + 1 by rfl, defaultValueAtV1.eq_2, hlookup]
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
  have hd0 := hdef s0.typeId ht0
  have hd1 := hdef s1.typeId ht1
  have hd2 := hdef s2.typeId ht2
  have hszZ : zero.size = 8 := rfl
  have henc :=
    encodeLogicalStateValuesV1_triple_uint64_eq_ok data s0 s1 s2
      zero zero zero true hstate hz0 hz1 hz2 hszZ hszZ hszZ
  unfold initialLogicalStateV1
  rw [hvalidate]
  simp only [Bind.bind, Except.bind]
  rw [hstate]
  simp [hd0, hd1, hd2, hnoInitializer, Pure.pure, Except.pure, Bind.bind,
    Except.bind]
  simpa [zero, array_push3_eq] using henc

/-- Successful triple decode yields three structure-gated slot payloads. -/
theorem decodeLogicalStateValuesV1_triple_eq
    (data : SemanticProgramDataV1)
    (s0 s1 s2 : StateDeclV1)
    (state : LogicalStateV1)
    (values : Array ByteArray)
    (hstate : data.logicalState = #[s0, s1, s2])
    (hdecode : decodeLogicalStateValuesV1 data state = .ok values) :
    ∃ b0 b1 b2 : ByteArray,
      values = #[b0, b1, b2] ∧
      validateValueBytesV1 data.types s0.typeId b0 = .ok () ∧
      validateValueBytesV1 data.types s1.typeId b1 = .ok () ∧
      validateValueBytesV1 data.types s2.typeId b2 = .ok () := by
  unfold decodeLogicalStateValuesV1 at hdecode
  have hlist : data.logicalState.toList = [s0, s1, s2] := by simp [hstate]
  simp only [hlist, decodeLogicalStateSlotsV1, Pure.pure, Except.pure,
    Bind.bind, Except.bind, err] at hdecode
  cases hread0 : readU32leAtV1 state.canonicalValues 0 with
  | error e => simp [hread0] at hdecode
  | ok pair0 =>
    rcases pair0 with ⟨len0, after0⟩
    simp [hread0] at hdecode
    by_cases hfit0 : after0 + len0.toNat ≤ state.canonicalValues.size
    · simp only [if_pos hfit0] at hdecode
      cases hval0 : validateValueBytesV1 data.types s0.typeId
          (state.canonicalValues.extract after0 (after0 + len0.toNat)) with
      | error e => simp [hval0] at hdecode
      | ok _ =>
        simp [hval0] at hdecode
        cases hread1 : readU32leAtV1 state.canonicalValues
            (after0 + len0.toNat) with
        | error e => simp [hread1] at hdecode
        | ok pair1 =>
          rcases pair1 with ⟨len1, after1⟩
          simp [hread1] at hdecode
          by_cases hfit1 : after1 + len1.toNat ≤ state.canonicalValues.size
          · simp only [if_pos hfit1] at hdecode
            cases hval1 : validateValueBytesV1 data.types s1.typeId
                (state.canonicalValues.extract after1
                  (after1 + len1.toNat)) with
            | error e => simp [hval1] at hdecode
            | ok _ =>
              simp [hval1] at hdecode
              cases hread2 : readU32leAtV1 state.canonicalValues
                  (after1 + len1.toNat) with
              | error e => simp [hread2] at hdecode
              | ok pair2 =>
                rcases pair2 with ⟨len2, after2⟩
                simp [hread2] at hdecode
                by_cases hfit2 :
                    after2 + len2.toNat ≤ state.canonicalValues.size
                · simp only [if_pos hfit2] at hdecode
                  cases hval2 : validateValueBytesV1 data.types s2.typeId
                      (state.canonicalValues.extract after2
                        (after2 + len2.toNat)) with
                  | error e => simp [hval2] at hdecode
                  | ok _ =>
                    simp [hval2] at hdecode
                    by_cases htrail :
                        after2 + len2.toNat = state.canonicalValues.size
                    · simp only [if_pos htrail] at hdecode
                      let b0 := state.canonicalValues.extract after0
                        (after0 + len0.toNat)
                      let b1 := state.canonicalValues.extract after1
                        (after1 + len1.toNat)
                      let b2 := state.canonicalValues.extract after2
                        (after2 + len2.toNat)
                      have hvals :
                          values =
                            ((((Array.emptyWithCapacity 3).push b0).push b1).push
                              b2) :=
                        (Except.ok.inj hdecode).symm
                      refine ⟨b0, b1, b2, ?_, hval0, hval1, hval2⟩
                      simpa [array_push3_eq b0 b1 b2] using hvals
                    · simp only [if_neg htrail] at hdecode
                      cases hdecode
                · simp only [if_neg hfit2] at hdecode
                  cases hdecode
          · simp only [if_neg hfit1] at hdecode
            cases hdecode
    · simp only [if_neg hfit0] at hdecode
      cases hdecode


/-- Mid-offset: successful u32le read recovers the 4-byte encode prefix. -/
theorem readU32leAtV1_ok_extract_eq_encode
    (b : ByteArray) (off : Nat) (v : UInt32)
    (h : readU32leAtV1 b off = .ok (v, off + 4))
    (hle : off + 4 ≤ b.size) :
    b.extract off (off + 4) = encodeU32le v := by
  unfold readU32leAtV1 at h
  cases hb0 : readByteAtV1 b off with
  | error e => simp [hb0, Bind.bind, Except.bind] at h
  | ok b0 =>
    cases hb1 : readByteAtV1 b (off + 1) with
    | error e => simp [hb0, hb1, Bind.bind, Except.bind] at h
    | ok b1 =>
      cases hb2 : readByteAtV1 b (off + 2) with
      | error e => simp [hb0, hb1, hb2, Bind.bind, Except.bind] at h
      | ok b2 =>
        cases hb3 : readByteAtV1 b (off + 3) with
        | error e =>
            simp [hb0, hb1, hb2, hb3, Bind.bind, Except.bind] at h
        | ok b3 =>
            simp only [hb0, hb1, hb2, hb3, Bind.bind, Except.bind] at h
            have hpair :
                (UInt32.ofNat
                    (b0.toNat + b1.toNat * 256 + b2.toNat * 65536 +
                      b3.toNat * 16777216),
                  off + 4) =
                  (v, off + 4) := by
              simpa [Pure.pure, Except.pure] using h
            have hU :
                UInt32.ofNat
                    (b0.toNat + b1.toNat * 256 + b2.toNat * 65536 +
                      b3.toNat * 16777216) =
                  v :=
              (Prod.ext_iff.mp hpair).1
            have hb0lt : b0.toNat < 256 := UInt8.toNat_lt_size b0
            have hb1lt : b1.toNat < 256 := UInt8.toNat_lt_size b1
            have hb2lt : b2.toNat < 256 := UInt8.toNat_lt_size b2
            have hb3lt : b3.toNat < 256 := UInt8.toNat_lt_size b3
            have hsum :
                b0.toNat + b1.toNat * 256 + b2.toNat * 65536 +
                  b3.toNat * 16777216 =
                  v.toNat := by
              have := congrArg UInt32.toNat hU
              have hmod :
                  (b0.toNat + b1.toNat * 256 + b2.toNat * 65536 +
                    b3.toNat * 16777216) % 4294967296 =
                    v.toNat := by
                simpa [UInt32.toNat_ofNat] using this
              have hlt :
                  b0.toNat + b1.toNat * 256 + b2.toNat * 65536 +
                    b3.toNat * 16777216 < 4294967296 := by omega
              rwa [Nat.mod_eq_of_lt hlt] at hmod
            have hb0n : b0.toNat = v.toNat % 256 := by omega
            have hb1n : b1.toNat = (v.toNat / 256) % 256 := by omega
            have hb2n : b2.toNat = (v.toNat / 65536) % 256 := by omega
            have hb3n : b3.toNat = (v.toNat / 16777216) % 256 := by omega
            have hb0' : b0 = UInt8.ofNat (v.toNat % 256) := by
              apply UInt8.toNat_inj.1
              simpa [UInt8_toNat_ofNat_mod256V1] using hb0n
            have hb1' : b1 = UInt8.ofNat ((v.toNat / 256) % 256) := by
              apply UInt8.toNat_inj.1
              simpa [UInt8_toNat_ofNat_mod256V1] using hb1n
            have hb2' : b2 = UInt8.ofNat ((v.toNat / 65536) % 256) := by
              apply UInt8.toNat_inj.1
              simpa [UInt8_toNat_ofNat_mod256V1] using hb2n
            have hb3' : b3 = UInt8.ofNat ((v.toNat / 16777216) % 256) := by
              apply UInt8.toNat_inj.1
              simpa [UInt8_toNat_ofNat_mod256V1] using hb3n
            have g0 := readByteAtV1_ok_getElem b off b0 hb0 (by omega)
            have g1 := readByteAtV1_ok_getElem b (off + 1) b1 hb1 (by omega)
            have g2 := readByteAtV1_ok_getElem b (off + 2) b2 hb2 (by omega)
            have g3 := readByteAtV1_ok_getElem b (off + 3) b3 hb3 (by omega)
            have hex :
                b.extract off (off + 4) = [b0, b1, b2, b3].toByteArray := by
              have h4 :=
                ByteArray.extract_add_four (a := b) (i := off) hle
              -- Avoid dependent getElem rewrite order issues: rewrite the
              -- whole list via congruence on each cell equality.
              rw [h4]
              have hcells :
                  [b[off], b[off + 1], b[off + 2], b[off + 3]] =
                    [b0, b1, b2, b3] := by
                refine List.cons_eq_cons.mpr ⟨g0, ?_⟩
                refine List.cons_eq_cons.mpr ⟨g1, ?_⟩
                refine List.cons_eq_cons.mpr ⟨g2, ?_⟩
                refine List.cons_eq_cons.mpr ⟨g3, rfl⟩
              exact congrArg List.toByteArray hcells
            rw [hex, hb0', hb1', hb2', hb3']
            have hlist (a b c d : UInt8) :
                [a, b, c, d].toByteArray =
                  (((ByteArray.empty.push a).push b).push c).push d := by
              simp [List.toByteArray, List.toByteArray.loop]
            simp only [encodeU32le]
            exact (hlist _ _ _ _).symm

/-- Slice identity: `extract i k = extract i j ++ extract j k` when `i ≤ j ≤ k ≤ size`. -/
private theorem ByteArray_extract_split
    (b : ByteArray) (i j k : Nat)
    (hij : i ≤ j) (hjk : j ≤ k) (_hks : k ≤ b.size) :
    b.extract i k = b.extract i j ++ b.extract j k := by
  exact
    ByteArray.extract_eq_extract_append_extract (a := b) (i := i) (k := k) j
      hij hjk

/-- Successful triple UInt64-slot decode recovers the closed encode layout. -/
theorem decodeLogicalStateValuesV1_triple_uint64_layout
    (data : SemanticProgramDataV1)
    (s0 s1 s2 : StateDeclV1)
    (state : LogicalStateV1)
    (b0 b1 b2 : ByteArray)
    (hstate : data.logicalState = #[s0, s1, s2])
    (hdecode : decodeLogicalStateValuesV1 data state = .ok #[b0, b1, b2])
    (hs0 : b0.size = 8) (hs1 : b1.size = 8) (hs2 : b2.size = 8) :
    state.canonicalValues = tripleUint64CanonicalV1 b0 b1 b2 := by
  unfold decodeLogicalStateValuesV1 at hdecode
  have hlist : data.logicalState.toList = [s0, s1, s2] := by simp [hstate]
  simp only [hlist, decodeLogicalStateSlotsV1, Pure.pure, Except.pure,
    Bind.bind, Except.bind, err] at hdecode
  cases hread0 : readU32leAtV1 state.canonicalValues 0 with
  | error e => simp [hread0] at hdecode
  | ok pair0 =>
    rcases pair0 with ⟨len0, after0⟩
    simp [hread0] at hdecode
    by_cases hfit0 : after0 + len0.toNat ≤ state.canonicalValues.size
    · simp only [if_pos hfit0] at hdecode
      cases hval0 : validateValueBytesV1 data.types s0.typeId
          (state.canonicalValues.extract after0 (after0 + len0.toNat)) with
      | error e => simp [hval0] at hdecode
      | ok _ =>
        simp [hval0] at hdecode
        cases hread1 : readU32leAtV1 state.canonicalValues
            (after0 + len0.toNat) with
        | error e => simp [hread1] at hdecode
        | ok pair1 =>
          rcases pair1 with ⟨len1, after1⟩
          simp [hread1] at hdecode
          by_cases hfit1 : after1 + len1.toNat ≤ state.canonicalValues.size
          · simp only [if_pos hfit1] at hdecode
            cases hval1 : validateValueBytesV1 data.types s1.typeId
                (state.canonicalValues.extract after1
                  (after1 + len1.toNat)) with
            | error e => simp [hval1] at hdecode
            | ok _ =>
              simp [hval1] at hdecode
              cases hread2 : readU32leAtV1 state.canonicalValues
                  (after1 + len1.toNat) with
              | error e => simp [hread2] at hdecode
              | ok pair2 =>
                rcases pair2 with ⟨len2, after2⟩
                simp [hread2] at hdecode
                by_cases hfit2 :
                    after2 + len2.toNat ≤ state.canonicalValues.size
                · simp only [if_pos hfit2] at hdecode
                  cases hval2 : validateValueBytesV1 data.types s2.typeId
                      (state.canonicalValues.extract after2
                        (after2 + len2.toNat)) with
                  | error e => simp [hval2] at hdecode
                  | ok _ =>
                    simp [hval2] at hdecode
                    by_cases htrail :
                        after2 + len2.toNat = state.canonicalValues.size
                    · simp only [if_pos htrail] at hdecode
                      have hvals :
                          ((((Array.emptyWithCapacity 3).push
                                (state.canonicalValues.extract after0
                                  (after0 + len0.toNat))).push
                              (state.canonicalValues.extract after1
                                (after1 + len1.toNat))).push
                            (state.canonicalValues.extract after2
                              (after2 + len2.toNat))) =
                            #[b0, b1, b2] :=
                        Except.ok.inj hdecode
                      have hpush := array_push3_eq
                        (state.canonicalValues.extract after0
                          (after0 + len0.toNat))
                        (state.canonicalValues.extract after1
                          (after1 + len1.toNat))
                        (state.canonicalValues.extract after2
                          (after2 + len2.toNat))
                      have harr :
                          #[state.canonicalValues.extract after0
                              (after0 + len0.toNat),
                            state.canonicalValues.extract after1
                              (after1 + len1.toNat),
                            state.canonicalValues.extract after2
                              (after2 + len2.toNat)] =
                            #[b0, b1, b2] := by
                        simpa [hpush] using hvals
                      have hs0' :
                          state.canonicalValues.extract after0
                              (after0 + len0.toNat) =
                            b0 := by
                        have := congrArg (fun a : Array ByteArray => a[0]?) harr
                        simpa using this
                      have hs1' :
                          state.canonicalValues.extract after1
                              (after1 + len1.toNat) =
                            b1 := by
                        have := congrArg (fun a : Array ByteArray => a[1]?) harr
                        simpa using this
                      have hs2' :
                          state.canonicalValues.extract after2
                              (after2 + len2.toNat) =
                            b2 := by
                        have := congrArg (fun a : Array ByteArray => a[2]?) harr
                        simpa using this
                      have hafter0 : after0 = 4 :=
                        readU32leAtV1_ok_offset state.canonicalValues 0 len0
                          after0 hread0
                      have hex0_sz :
                          (state.canonicalValues.extract after0
                            (after0 + len0.toNat)).size = len0.toNat := by
                        have hmin :
                            min (after0 + len0.toNat)
                              state.canonicalValues.size =
                              after0 + len0.toNat :=
                          Nat.min_eq_left hfit0
                        simp [ByteArray.size_extract, hmin,
                          Nat.add_sub_cancel_left]
                      have hlen0 : len0.toNat = 8 := by
                        have : b0.size = len0.toNat := by
                          rw [← hs0', hex0_sz]
                        omega
                      have hlen0U : len0 = (8 : UInt32) :=
                        UInt32.toNat_inj.1
                          (hlen0.trans uint32_toNat_eightV1.symm)
                      have hafter1 : after1 = after0 + len0.toNat + 4 :=
                        readU32leAtV1_ok_offset state.canonicalValues
                          (after0 + len0.toNat) len1 after1 hread1
                      have hex1_sz :
                          (state.canonicalValues.extract after1
                            (after1 + len1.toNat)).size = len1.toNat := by
                        have hmin :
                            min (after1 + len1.toNat)
                              state.canonicalValues.size =
                              after1 + len1.toNat :=
                          Nat.min_eq_left hfit1
                        simp [ByteArray.size_extract, hmin,
                          Nat.add_sub_cancel_left]
                      have hlen1 : len1.toNat = 8 := by
                        have : b1.size = len1.toNat := by
                          rw [← hs1', hex1_sz]
                        omega
                      have hlen1U : len1 = (8 : UInt32) :=
                        UInt32.toNat_inj.1
                          (hlen1.trans uint32_toNat_eightV1.symm)
                      have hafter2 : after2 = after1 + len1.toNat + 4 :=
                        readU32leAtV1_ok_offset state.canonicalValues
                          (after1 + len1.toNat) len2 after2 hread2
                      have hex2_sz :
                          (state.canonicalValues.extract after2
                            (after2 + len2.toNat)).size = len2.toNat := by
                        have hmin :
                            min (after2 + len2.toNat)
                              state.canonicalValues.size =
                              after2 + len2.toNat :=
                          Nat.min_eq_left hfit2
                        simp [ByteArray.size_extract, hmin,
                          Nat.add_sub_cancel_left]
                      have hlen2 : len2.toNat = 8 := by
                        have : b2.size = len2.toNat := by
                          rw [← hs2', hex2_sz]
                        omega
                      have hlen2U : len2 = (8 : UInt32) :=
                        UInt32.toNat_inj.1
                          (hlen2.trans uint32_toNat_eightV1.symm)
                      -- Collapse offsets: after0=4, after1=16, after2=28, size=36.
                      have hA0 : after0 = 4 := hafter0
                      have hA1 : after1 = 16 := by omega
                      have hA2 : after2 = 28 := by omega
                      have hsz : state.canonicalValues.size = 36 := by omega
                      have hread0_8 :
                          readU32leAtV1 state.canonicalValues 0 =
                            .ok ((8 : UInt32), 4) := by
                        simpa [hlen0U, hA0] using hread0
                      have hread1_8 :
                          readU32leAtV1 state.canonicalValues 12 =
                            .ok ((8 : UInt32), 16) := by
                        have hoff : after0 + len0.toNat = 12 := by omega
                        have h1 :
                            readU32leAtV1 state.canonicalValues 12 =
                              .ok (len1, after1) := by
                          simpa [hoff] using hread1
                        simpa [hlen1U, hA1] using h1
                      have hread2_8 :
                          readU32leAtV1 state.canonicalValues 24 =
                            .ok ((8 : UInt32), 28) := by
                        have hoff : after1 + len1.toNat = 24 := by omega
                        have h2 :
                            readU32leAtV1 state.canonicalValues 24 =
                              .ok (len2, after2) := by
                          simpa [hoff] using hread2
                        simpa [hlen2U, hA2] using h2
                      have he0 :
                          state.canonicalValues.extract 0 4 =
                            encodeU32le (8 : UInt32) :=
                        readU32leAtV1_ok_extract_eq_encode
                          state.canonicalValues 0 8 hread0_8 (by omega)
                      have he1 :
                          state.canonicalValues.extract 12 16 =
                            encodeU32le (8 : UInt32) :=
                        readU32leAtV1_ok_extract_eq_encode
                          state.canonicalValues 12 8 hread1_8 (by omega)
                      have he2 :
                          state.canonicalValues.extract 24 28 =
                            encodeU32le (8 : UInt32) :=
                        readU32leAtV1_ok_extract_eq_encode
                          state.canonicalValues 24 8 hread2_8 (by omega)
                      have hp0 :
                          state.canonicalValues.extract 4 12 = b0 := by
                        have : after0 + len0.toNat = 12 := by omega
                        simpa [hA0, hlen0, this] using hs0'
                      have hp1 :
                          state.canonicalValues.extract 16 24 = b1 := by
                        have : after1 + len1.toNat = 24 := by omega
                        simpa [hA1, hlen1, this] using hs1'
                      have hp2 :
                          state.canonicalValues.extract 28 36 = b2 := by
                        have : after2 + len2.toNat = 36 := by omega
                        simpa [hA2, hlen2, this] using hs2'
                      -- Rebuild cv by successive splits.
                      have h0s :
                          state.canonicalValues.extract 0
                              state.canonicalValues.size =
                            state.canonicalValues.extract 0 4 ++
                              state.canonicalValues.extract 4
                                state.canonicalValues.size :=
                        ByteArray_extract_split state.canonicalValues 0 4
                          state.canonicalValues.size (by omega) (by omega)
                          (by omega)
                      have h4s :
                          state.canonicalValues.extract 4
                              state.canonicalValues.size =
                            state.canonicalValues.extract 4 12 ++
                              state.canonicalValues.extract 12
                                state.canonicalValues.size :=
                        ByteArray_extract_split state.canonicalValues 4 12
                          state.canonicalValues.size (by omega) (by omega)
                          (by omega)
                      have h12s :
                          state.canonicalValues.extract 12
                              state.canonicalValues.size =
                            state.canonicalValues.extract 12 16 ++
                              state.canonicalValues.extract 16
                                state.canonicalValues.size :=
                        ByteArray_extract_split state.canonicalValues 12 16
                          state.canonicalValues.size (by omega) (by omega)
                          (by omega)
                      have h16s :
                          state.canonicalValues.extract 16
                              state.canonicalValues.size =
                            state.canonicalValues.extract 16 24 ++
                              state.canonicalValues.extract 24
                                state.canonicalValues.size :=
                        ByteArray_extract_split state.canonicalValues 16 24
                          state.canonicalValues.size (by omega) (by omega)
                          (by omega)
                      have h24s :
                          state.canonicalValues.extract 24
                              state.canonicalValues.size =
                            state.canonicalValues.extract 24 28 ++
                              state.canonicalValues.extract 28
                                state.canonicalValues.size :=
                        ByteArray_extract_split state.canonicalValues 24 28
                          state.canonicalValues.size (by omega) (by omega)
                          (by omega)
                      have h28s :
                          state.canonicalValues.extract 28
                              state.canonicalValues.size =
                            state.canonicalValues.extract 28 36 := by
                        simp [hsz]
                      -- Rebuild: successive mid splits → tripleUint64CanonicalV1.
                      have hfull :
                          state.canonicalValues.extract 0
                              state.canonicalValues.size =
                            state.canonicalValues := by
                        ext1
                        simp
                      have hcv :
                          state.canonicalValues =
                            encodeU32le (8 : UInt32) ++ b0 ++
                              encodeU32le (8 : UInt32) ++ b1 ++
                              encodeU32le (8 : UInt32) ++ b2 := by
                        have h :
                            state.canonicalValues.extract 0
                                state.canonicalValues.size =
                              encodeU32le (8 : UInt32) ++ b0 ++
                                encodeU32le (8 : UInt32) ++ b1 ++
                                encodeU32le (8 : UInt32) ++ b2 := by
                          rw [h0s, he0, h4s, hp0, h12s, he1, h16s, hp1, h24s,
                            he2, h28s, hp2]
                          simp [ByteArray.append_assoc]
                        exact hfull.symm.trans h
                      simpa [tripleUint64CanonicalV1, ByteArray.append_assoc]
                        using hcv
                    · simp only [if_neg htrail] at hdecode
                      cases hdecode
                · simp only [if_neg hfit2] at hdecode
                  cases hdecode
          · simp only [if_neg hfit1] at hdecode
            cases hdecode
    · simp only [if_neg hfit0] at hdecode
      cases hdecode

/-- Encode of a successful triple UInt64 decode recovers the same carrier
    (initialized stays true). Get-returned post=pre identity for 3-slot state. -/
theorem encode_of_triple_uint64_decode_eq
    (data : SemanticProgramDataV1)
    (s0 s1 s2 : StateDeclV1)
    (pre post : LogicalStateV1)
    (b0 b1 b2 : ByteArray)
    (hstate : data.logicalState = #[s0, s1, s2])
    (hinit : pre.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data pre = .ok #[b0, b1, b2])
    (hc0 : validateValueBytesV1 data.types s0.typeId b0 = .ok ())
    (hc1 : validateValueBytesV1 data.types s1.typeId b1 = .ok ())
    (hc2 : validateValueBytesV1 data.types s2.typeId b2 = .ok ())
    (hs0 : b0.size = 8) (hs1 : b1.size = 8) (hs2 : b2.size = 8)
    (hencode :
      encodeLogicalStateValuesV1 data true #[b0, b1, b2] = .ok post) :
    post = pre := by
  have henc :=
    encodeLogicalStateValuesV1_triple_uint64_eq_ok data s0 s1 s2 b0 b1 b2 true
      hstate hc0 hc1 hc2 hs0 hs1 hs2
  have hpost :
      post = {
        initialized := true
        canonicalValues := tripleUint64CanonicalV1 b0 b1 b2
      } := by
    rw [henc] at hencode
    exact (Except.ok.inj hencode).symm
  have hlayout :=
    decodeLogicalStateValuesV1_triple_uint64_layout data s0 s1 s2 pre b0 b1 b2
      hstate hdecode hs0 hs1 hs2
  have hpre :
      pre = {
        initialized := true
        canonicalValues := tripleUint64CanonicalV1 b0 b1 b2
      } := by
    cases pre with
    | mk initialized canonicalValues =>
      simp only at hinit hlayout ⊢
      subst hinit
      subst hlayout
      rfl
  exact hpost.trans hpre.symm

end ProofForgeV2.Semantic.InvariantABI
