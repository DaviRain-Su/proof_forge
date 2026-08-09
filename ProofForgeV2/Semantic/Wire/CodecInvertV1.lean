import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Semantic.Wire.CodecRoundtripV1
import Init.Data.ByteArray.Lemmas
import Init.Data.Array.Lemmas

/-!
  ProofForgeV2.Semantic.Wire.CodecInvertV1 — generic encode→decode invertibility
  foundation (mig-a1 codec wave-3′).

  Closes the **composition layer** of the ProofBridge remaining gap:

    parametric `decodeSemanticProgramDataV1 (encode data) = .ok data`

  under **mid-offset invertibility** of each production field codec.

  Foundation (this module): MidOffsetInvert predicate, Visibility complete leaf,
  array zero/one helpers, RootFieldInvert package, DecodeEncodeRoundtripGoal.

  Field-family invert (mig-a1-fields): see `Wire.CodecInvertFieldsV1` —
  InvariantDecl full MidOffsetInvert, empty root tables, empty Requirements,
  Type.Bool shape, QN single-component + encode success foundation.
  Callable / full multi-component QN / full TypeShape residual → mig-a1-callable/root.

  Hard boundaries:
    * no axiom / sorry / native_decide / ofReduceBool
    * no second encoder or structure-gate bypass
    * sole production encode/decode authorities
-/

namespace ProofForgeV2.Semantic.WireV1

/-! ### Mid-offset invertibility predicate -/

/-- A decoder recovers every value that its paired encoder successfully
    framed, at an arbitrary mid-offset of a larger byte buffer (when nesting
    admits the tagged frame). -/
def MidOffsetInvertV1 (encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) : Prop :=
  ∀ (x : α) (b left right : ByteArray) (nesting : Nat),
    nesting < maxNesting →
    encode x = .ok b →
    decode ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (x, ⟨left ++ b ++ right, left.size + b.size, nesting⟩)

/-- String production codec is mid-offset invertible (re-export). -/
theorem midOffsetInvert_encodeString_decodeString :
    MidOffsetInvertV1 encodeString decodeString := by
  intro s b left right nesting _hdepth h
  exact decodeString_of_encodeString_okV1 left right s b nesting h

/-! ### Visibility (complete leaf family) -/

private theorem isAsciiBytes_Visibility_Public :
    isAsciiTagBytesV1 "Visibility.Public".toUTF8 = true := by
  have h : "Visibility.Public".toUTF8 =
      ByteArray.mk #[86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117,
        98, 108, 105, 99] := rfl
  rw [h]; simp [isAsciiTagBytesV1]

private theorem isAsciiBytes_Visibility_Private :
    isAsciiTagBytesV1 "Visibility.Private".toUTF8 = true := by
  have h : "Visibility.Private".toUTF8 =
      ByteArray.mk #[86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 114,
        105, 118, 97, 116, 101] := rfl
  rw [h]; simp [isAsciiTagBytesV1]

private theorem isAsciiBytes_Visibility_Commitment :
    isAsciiTagBytesV1 "Visibility.Commitment".toUTF8 = true := by
  have h : "Visibility.Commitment".toUTF8 =
      ByteArray.mk #[86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 67, 111,
        109, 109, 105, 116, 109, 101, 110, 116] := rfl
  rw [h]; simp [isAsciiTagBytesV1]

private theorem decodeVisibility_nullary_midV1
    (tag : String) (vis : VisibilityV1)
    (left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (hnonempty : 1 ≤ tag.toUTF8.size)
    (hmax : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (hfit : tag.toUTF8.size ≤ UInt32.size - 1)
    (hasciiBytes : isAsciiTagBytesV1 tag.toUTF8 = true)
    (hasciiTag : isAsciiTagV1 tag = true)
    (hbody :
      ∀ (c afterTag afterFields : Cursor),
        decodeTag c = .ok (tag, afterTag) →
        decodeFieldCount 0 afterTag = .ok ((), afterFields) →
        decodeVisibilityBodyV1 c = .ok (vis, afterFields)) :
    decodeVisibilityV1
        ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right, left.size, nesting⟩ =
      .ok (vis,
        ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right,
          left.size + (taggedHeaderBytesV1 tag 0).size, nesting⟩) := by
  refine decodeVisibilityV1_eq_of_bodyV1
    ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right, left.size, nesting⟩ vis
    ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right,
      left.size + (taggedHeaderBytesV1 tag 0).size, nesting + 1⟩ hdepth ?_
  have henc :
      taggedHeaderBytesV1 tag 0 =
        encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++
          encodeU16le 0 := by
    simp [taggedHeaderBytesV1, ByteArray.append_assoc]
  have hin :
      left ++ taggedHeaderBytesV1 tag 0 ++ right =
        left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++
          (encodeU16le 0 ++ right) := by
    simp [henc, ByteArray.append_assoc]
  have htag :
      decodeTag
          ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right, left.size, nesting + 1⟩ =
        .ok (tag,
          ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right,
            left.size + 4 + tag.toUTF8.size, nesting + 1⟩) := by
    rw [hin]
    have h :=
      decodeTag_encode_midV1 left (encodeU16le 0 ++ right) tag (nesting + 1)
        hnonempty hmax hfit hasciiBytes hasciiTag
    simpa [hin.symm, ByteArray.append_assoc] using h
  have hszFinal :
      left.size + 4 + tag.toUTF8.size + 2 =
        left.size + (taggedHeaderBytesV1 tag 0).size := by
    simp only [taggedHeaderBytesV1_size]; omega
  have hfc :
      decodeFieldCount 0
          ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right,
            left.size + 4 + tag.toUTF8.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right,
            left.size + (taggedHeaderBytesV1 tag 0).size, nesting + 1⟩) := by
    have hassoc :
        left ++ taggedHeaderBytesV1 tag 0 ++ right =
          (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8) ++
            encodeU16le 0 ++ right := by
      simp [henc, ByteArray.append_assoc]
    have hsz :
        (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8).size =
          left.size + 4 + tag.toUTF8.size := by
      rw [ByteArray.size_append, ByteArray.size_append, encodeU32le_sizeV1]
    have hread :
        readU16leAtV1 (left ++ taggedHeaderBytesV1 tag 0 ++ right)
            (left.size + 4 + tag.toUTF8.size) =
          .ok (0, left.size + 4 + tag.toUTF8.size + 2) := by
      rw [hassoc, ← hsz]
      simpa [hsz] using
        readU16le_encode_midV1
          (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8)
          right 0
    rw [← hszFinal]
    have h := decodeFieldCount_eq_of_readU16leV1 0
      ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right,
        left.size + 4 + tag.toUTF8.size, nesting + 1⟩
      0 (left.size + 4 + tag.toUTF8.size + 2) hread
    simpa using h
  exact hbody _ _ _ htag hfc

theorem encodeVisibility_public_eq :
    encodeVisibilityV1 .public_ = .ok (taggedHeaderBytesV1 "Visibility.Public" 0) := by
  change encodeNullary "Visibility.Public" = .ok (taggedHeaderBytesV1 "Visibility.Public" 0)
  have h := encodeNullary_eq_okV1 "Visibility.Public" (by decide) (by decide) (by decide)
  have heq :
      (((encodeU32le (UInt32.ofNat "Visibility.Public".toUTF8.size)).append
          "Visibility.Public".toUTF8).append (encodeU16le 0)) =
        taggedHeaderBytesV1 "Visibility.Public" 0 := by
    simp only [taggedHeaderBytesV1]; rfl
  rwa [heq] at h

theorem encodeVisibility_private_eq :
    encodeVisibilityV1 .private_ = .ok (taggedHeaderBytesV1 "Visibility.Private" 0) := by
  change encodeNullary "Visibility.Private" = .ok (taggedHeaderBytesV1 "Visibility.Private" 0)
  have h := encodeNullary_eq_okV1 "Visibility.Private" (by decide) (by decide) (by decide)
  have heq :
      (((encodeU32le (UInt32.ofNat "Visibility.Private".toUTF8.size)).append
          "Visibility.Private".toUTF8).append (encodeU16le 0)) =
        taggedHeaderBytesV1 "Visibility.Private" 0 := by
    simp only [taggedHeaderBytesV1]; rfl
  rwa [heq] at h

theorem encodeVisibility_commitment_eq :
    encodeVisibilityV1 .commitment =
      .ok (taggedHeaderBytesV1 "Visibility.Commitment" 0) := by
  change encodeNullary "Visibility.Commitment" =
    .ok (taggedHeaderBytesV1 "Visibility.Commitment" 0)
  have h := encodeNullary_eq_okV1 "Visibility.Commitment" (by decide) (by decide) (by decide)
  have heq :
      (((encodeU32le (UInt32.ofNat "Visibility.Commitment".toUTF8.size)).append
          "Visibility.Commitment".toUTF8).append (encodeU16le 0)) =
        taggedHeaderBytesV1 "Visibility.Commitment" 0 := by
    simp only [taggedHeaderBytesV1]; rfl
  rwa [heq] at h

theorem decodeVisibility_public_midV1
    (left right : ByteArray) (nesting : Nat) (hdepth : nesting < maxNesting) :
    decodeVisibilityV1
        ⟨left ++ taggedHeaderBytesV1 "Visibility.Public" 0 ++ right,
          left.size, nesting⟩ =
      .ok (.public_,
        ⟨left ++ taggedHeaderBytesV1 "Visibility.Public" 0 ++ right,
          left.size + (taggedHeaderBytesV1 "Visibility.Public" 0).size, nesting⟩) :=
  decodeVisibility_nullary_midV1 "Visibility.Public" .public_ left right nesting hdepth
    (by decide) (by decide) (by decide) isAsciiBytes_Visibility_Public (by decide)
    (fun c afterTag afterFields htag hfields =>
      decodeVisibilityBodyV1_public c afterTag afterFields htag hfields)

theorem decodeVisibility_private_midV1
    (left right : ByteArray) (nesting : Nat) (hdepth : nesting < maxNesting) :
    decodeVisibilityV1
        ⟨left ++ taggedHeaderBytesV1 "Visibility.Private" 0 ++ right,
          left.size, nesting⟩ =
      .ok (.private_,
        ⟨left ++ taggedHeaderBytesV1 "Visibility.Private" 0 ++ right,
          left.size + (taggedHeaderBytesV1 "Visibility.Private" 0).size, nesting⟩) :=
  decodeVisibility_nullary_midV1 "Visibility.Private" .private_ left right nesting hdepth
    (by decide) (by decide) (by decide) isAsciiBytes_Visibility_Private (by decide)
    (fun c afterTag afterFields htag hfields => by
      simp only [decodeVisibilityBodyV1, htag, hfields, Bind.bind, Pure.pure,
        Except.bind, Except.pure])

theorem decodeVisibility_commitment_midV1
    (left right : ByteArray) (nesting : Nat) (hdepth : nesting < maxNesting) :
    decodeVisibilityV1
        ⟨left ++ taggedHeaderBytesV1 "Visibility.Commitment" 0 ++ right,
          left.size, nesting⟩ =
      .ok (.commitment,
        ⟨left ++ taggedHeaderBytesV1 "Visibility.Commitment" 0 ++ right,
          left.size + (taggedHeaderBytesV1 "Visibility.Commitment" 0).size,
          nesting⟩) :=
  decodeVisibility_nullary_midV1 "Visibility.Commitment" .commitment left right nesting
    hdepth (by decide) (by decide) (by decide) isAsciiBytes_Visibility_Commitment
    (by decide)
    (fun c afterTag afterFields htag hfields => by
      simp only [decodeVisibilityBodyV1, htag, hfields, Bind.bind, Pure.pure,
        Except.bind, Except.pure])

/-- Practical form: invert Visibility under `nesting < maxNesting`. -/
theorem decodeVisibility_of_encode_midV1
    (vis : VisibilityV1) (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (henc : encodeVisibilityV1 vis = .ok b) :
    decodeVisibilityV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (vis, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  match vis with
  | .public_ =>
      have hb : b = taggedHeaderBytesV1 "Visibility.Public" 0 :=
        Except.ok.inj (henc.symm.trans encodeVisibility_public_eq)
      subst b
      simpa using decodeVisibility_public_midV1 left right nesting hdepth
  | .private_ =>
      have hb : b = taggedHeaderBytesV1 "Visibility.Private" 0 :=
        Except.ok.inj (henc.symm.trans encodeVisibility_private_eq)
      subst b
      simpa using decodeVisibility_private_midV1 left right nesting hdepth
  | .commitment =>
      have hb : b = taggedHeaderBytesV1 "Visibility.Commitment" 0 :=
        Except.ok.inj (henc.symm.trans encodeVisibility_commitment_eq)
      subst b
      simpa using decodeVisibility_commitment_midV1 left right nesting hdepth

/-- Complete leaf: Visibility production codec is mid-offset invertible. -/
theorem midOffsetInvert_encodeVisibility_decodeVisibility :
    MidOffsetInvertV1 encodeVisibilityV1 decodeVisibilityV1 := by
  intro vis b left right nesting hdepth henc
  exact decodeVisibility_of_encode_midV1 vis b left right nesting hdepth henc

/-! ### Array zero-element invert (parametric) -/

/-- Zero-element array: encode → mid-offset decode recovers `#[]`. -/
theorem decodeArray_of_encodeArray_zero_midV1
    (_encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) (maxCount : Nat)
    (left right : ByteArray) (nesting : Nat) :
    decodeArray maxCount decode
        ⟨left ++ encodeU32le 0 ++ right, left.size, nesting⟩ =
      .ok (#[], ⟨left ++ encodeU32le 0 ++ right, left.size + 4, nesting⟩) :=
  decodeArray_encode_zero_midV1 maxCount decode left right nesting

/-- One-element array mid-offset invert from a successful element mid-decode. -/
theorem decodeArray_of_encodeArray_one_midV1
    (_encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) (maxCount : Nat)
    (v0 : α) (b0 : ByteArray)
    (left right : ByteArray) (nesting : Nat)
    (hmax : 1 ≤ maxCount)
    (hinv :
      decode ⟨left ++ encodeU32le 1 ++ b0 ++ right, left.size + 4, nesting⟩ =
        .ok (v0, ⟨left ++ encodeU32le 1 ++ b0 ++ right,
          left.size + 4 + b0.size, nesting⟩)) :
    decodeArray maxCount decode
        ⟨left ++ encodeU32le 1 ++ b0 ++ right, left.size, nesting⟩ =
      .ok (#[v0],
        ⟨left ++ encodeU32le 1 ++ b0 ++ right, left.size + 4 + b0.size, nesting⟩) := by
  have hcount :
      readArrayCountAtV1 (left ++ encodeU32le 1 ++ b0 ++ right) left.size maxCount =
        .ok (1, left.size + 4) := by
    have hassoc :
        left ++ encodeU32le 1 ++ b0 ++ right =
          left ++ encodeU32le 1 ++ (b0 ++ right) := by
      simp [ByteArray.append_assoc]
    rw [hassoc]
    exact readArrayCount_encode_midV1 left (b0 ++ right) 1 maxCount (by decide) hmax
  apply decodeArray_oneV1 maxCount decode
    ⟨left ++ encodeU32le 1 ++ b0 ++ right, left.size, nesting⟩
    (left.size + 4) v0
    ⟨left ++ encodeU32le 1 ++ b0 ++ right, left.size + 4 + b0.size, nesting⟩
    hcount
  exact hinv

/-! ### Root composition under field mid-decodes -/

/-- Package of nine root-field mid-offset invertibility hypotheses.
    Once each field codec is invertible, `decode_of_encode_ok` follows. -/
structure RootFieldInvertV1 (data : SemanticProgramDataV1) : Prop where
  qualifiedName :
    MidOffsetInvertV1 encodeQualifiedName decodeQualifiedName
  types :
    MidOffsetInvertV1 (encodeArray encodeTypeDeclV1)
      (decodeArray maxTableElements decodeTypeDeclV1)
  constants :
    MidOffsetInvertV1 (encodeArray encodeConstantV1)
      (decodeArray maxTableElements decodeConstantV1)
  logicalState :
    MidOffsetInvertV1 (encodeArray encodeStateDeclV1)
      (decodeArray maxTableElements decodeStateDeclV1)
  events :
    MidOffsetInvertV1 (encodeArray encodeEventDeclV1)
      (decodeArray maxTableElements decodeEventDeclV1)
  errors :
    MidOffsetInvertV1 (encodeArray encodeErrorDeclV1)
      (decodeArray maxTableElements decodeErrorDeclV1)
  callables :
    MidOffsetInvertV1 (encodeArray encodeCallableV1)
      (decodeArray maxTableElements decodeCallableV1)
  invariants :
    MidOffsetInvertV1 (encodeArray encodeInvariantDeclV1)
      (decodeArray maxTableElements decodeInvariantDeclV1)
  requirements :
    MidOffsetInvertV1 encodeProgramRequirementsV1 decodeProgramRequirementsV1

/-- **mig-a1 residual goal form.**

    `RootFieldInvertV1 data` + successful structure-gated encode implies transport
    decode recovers `data`. Field-family invertibility proofs discharge
    `RootFieldInvertV1`; the composition theorem
    `decodeSemanticProgramDataV1_of_encode_ok_of_rootFieldInvert` is the
    remaining kernel obligation (stated, not yet closed in this foundation
    slice).

    This slice ships: MidOffsetInvert predicate, Visibility complete leaf,
    array zero/one helpers, RootFieldInvert package, goal form. Full discharge
    of `RootFieldInvertV1` for arbitrary `data` plus the composition theorem
    is the subsequent field-family wave (TypeDecl → Callable/Op → Requirements). -/
def DecodeEncodeRoundtripGoalV1 (data : SemanticProgramDataV1) (bytes : ByteArray) :
    Prop :=
  encodeSemanticProgramDataV1 data = .ok bytes →
    RootFieldInvertV1 data →
      decodeSemanticProgramDataV1 bytes = .ok data

end ProofForgeV2.Semantic.WireV1
