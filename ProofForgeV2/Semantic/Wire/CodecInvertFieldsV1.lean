import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.Wire.CodecRoundtripV1
import ProofForgeV2.Semantic.Wire.CodecInvertV1
import Init.Data.ByteArray.Lemmas
import Init.Data.Array.Lemmas

/-!
  ProofForgeV2.Semantic.Wire.CodecInvertFieldsV1 — mig-a1-fields

  Field-family mid-offset invertibility package (wave-3′ A):
    * empty table arrays (Constant/State/Event/Error/Invariant/Types tables)
    * InvariantDecl full MidOffsetInvert
    * ProgramRequirements empty-items invert
    * Type.Bool nullary TypeShape invert (TypeDecl leaf)
    * QN single-component invert + parse/render foundation
    * StateDecl depth-margin invert (nested Visibility fuel)

  Callable / full multi-component QN induction / full TypeShape residual →
  mig-a1-callable / mig-a1-root.

  Hard boundaries: no axiom / sorry / native_decide / ofReduceBool.
-/

namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.RequirementsV1

/-! ### Fixed ASCII tag certificates -/

private theorem utf8_InvariantDecl :
    "InvariantDecl".toUTF8 =
      ByteArray.mk #[73, 110, 118, 97, 114, 105, 97, 110, 116, 68, 101, 99, 108] := by
  rfl

private theorem isAsciiTagBytes_InvariantDecl :
    isAsciiTagBytesV1 "InvariantDecl".toUTF8 = true := by
  rw [utf8_InvariantDecl]
  exact isAsciiTagBytes_of_list_all
    [73, 110, 118, 97, 114, 105, 97, 110, 116, 68, 101, 99, 108] (by decide)

private theorem utf8_Type_Bool :
    "Type.Bool".toUTF8 =
      ByteArray.mk #[84, 121, 112, 101, 46, 66, 111, 111, 108] := by rfl

private theorem isAsciiTagBytes_Type_Bool :
    isAsciiTagBytesV1 "Type.Bool".toUTF8 = true := by
  rw [utf8_Type_Bool]
  exact isAsciiTagBytes_of_list_all
    [84, 121, 112, 101, 46, 66, 111, 111, 108] (by decide)

private theorem isAsciiTag_Type_Bool : isAsciiTagV1 "Type.Bool" = true := by decide

private theorem utf8_ProgramRequirements :
    "ProgramRequirements".toUTF8 =
      ByteArray.mk #[80, 114, 111, 103, 114, 97, 109, 82, 101, 113, 117, 105, 114, 101,
        109, 101, 110, 116, 115] := by rfl

private theorem isAsciiTagBytes_ProgramRequirements :
    isAsciiTagBytesV1 "ProgramRequirements".toUTF8 = true := by
  rw [utf8_ProgramRequirements]
  exact isAsciiTagBytes_of_list_all
    [80, 114, 111, 103, 114, 97, 109, 82, 101, 113, 117, 105, 114, 101, 109, 101, 110,
      116, 115] (by decide)

/-! ### Tagged body layouts -/

theorem taggedBytes_three_fields (tag : String) (f0 f1 f2 : ByteArray) :
    taggedBytesV1 tag #[f0, f1, f2] =
      taggedHeaderBytesV1 tag 3 ++ f0 ++ f1 ++ f2 := by
  have h := taggedBytesV1_eq_header_payload tag #[f0, f1, f2]
  have hfold :
      (#[f0, f1, f2] : Array ByteArray).foldl (fun out f => out.append f) ByteArray.empty =
        f0 ++ f1 ++ f2 := by
    simp [List.foldl]
  have hsz : (#[f0, f1, f2] : Array ByteArray).size = 3 := rfl
  rw [h, hfold, hsz]
  simp [ByteArray.append_assoc]

theorem taggedBytes_one_field (tag : String) (f0 : ByteArray) :
    taggedBytesV1 tag #[f0] = taggedHeaderBytesV1 tag 1 ++ f0 := by
  have h := taggedBytesV1_eq_header_payload tag #[f0]
  have hfold :
      (#[f0] : Array ByteArray).foldl (fun out f => out.append f) ByteArray.empty = f0 := by
    simp [List.foldl]
  have hsz : (#[f0] : Array ByteArray).size = 1 := rfl
  rw [h, hfold, hsz]

theorem taggedBytes_two_fields_fields (tag : String) (f0 f1 : ByteArray) :
    taggedBytesV1 tag #[f0, f1] = taggedHeaderBytesV1 tag 2 ++ f0 ++ f1 := by
  have h := taggedBytesV1_eq_header_payload tag #[f0, f1]
  have hfold :
      (#[f0, f1] : Array ByteArray).foldl (fun out f => out.append f) ByteArray.empty =
        f0 ++ f1 := by
    simp [List.foldl]
  have hsz : (#[f0, f1] : Array ByteArray).size = 2 := rfl
  rw [h, hfold, hsz]
  simp [ByteArray.append_assoc]

theorem taggedBytes_four_fields (tag : String) (f0 f1 f2 f3 : ByteArray) :
    taggedBytesV1 tag #[f0, f1, f2, f3] =
      taggedHeaderBytesV1 tag 4 ++ f0 ++ f1 ++ f2 ++ f3 := by
  have h := taggedBytesV1_eq_header_payload tag #[f0, f1, f2, f3]
  have hfold :
      (#[f0, f1, f2, f3] : Array ByteArray).foldl (fun out f => out.append f) ByteArray.empty =
        f0 ++ f1 ++ f2 ++ f3 := by
    simp [List.foldl]
  have hsz : (#[f0, f1, f2, f3] : Array ByteArray).size = 4 := rfl
  rw [h, hfold, hsz]
  simp [ByteArray.append_assoc]

/-! ### Exact array lifts -/

/-- Exact one-element array inversion from an exact element inversion and the
    production element bytes. -/
theorem exactMidOffsetInvert_array_one_of_encoded_exact
    (encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) (maxCount : Nat) (hmax : 1 ≤ maxCount)
    (v0 : α) (b0 : ByteArray)
    (henc0 : encode v0 = .ok b0)
    (h0 : ExactMidOffsetInvertV1 encode decode v0) :
    ExactMidOffsetInvertV1 (encodeArray encode) (decodeArray maxCount decode) #[v0] := by
  intro b left right nesting hdepth henc
  have hinv0 :
      decode ⟨left ++ encodeU32le 1 ++ b0 ++ right, left.size + 4, nesting⟩ =
        .ok (v0, ⟨left ++ encodeU32le 1 ++ b0 ++ right,
          left.size + 4 + b0.size, nesting⟩) := by
    have hmid := h0 b0 (left ++ encodeU32le 1) right nesting hdepth henc0
    have hin :
        (left ++ encodeU32le 1) ++ b0 ++ right =
          left ++ encodeU32le 1 ++ b0 ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ encodeU32le 1).size = left.size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    simpa [hin, hsz] using hmid
  exact decodeArray_of_encodeArray_one_ok_midV1 encode decode maxCount v0 b b0
    left right nesting hmax henc0 henc hinv0

/-- Exact two-element array inversion from exact element inversions and the
    production element bytes. -/
theorem exactMidOffsetInvert_array_two_of_encoded_exact
    (encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) (maxCount : Nat) (hmax : 2 ≤ maxCount)
    (v0 v1 : α) (b0 b1 : ByteArray)
    (henc0 : encode v0 = .ok b0) (henc1 : encode v1 = .ok b1)
    (h0 : ExactMidOffsetInvertV1 encode decode v0)
    (h1 : ExactMidOffsetInvertV1 encode decode v1) :
    ExactMidOffsetInvertV1 (encodeArray encode) (decodeArray maxCount decode) #[v0, v1] := by
  intro b left right nesting hdepth henc
  have hinv0 :
      decode ⟨left ++ encodeU32le 2 ++ b0 ++ b1 ++ right, left.size + 4, nesting⟩ =
        .ok (v0, ⟨left ++ encodeU32le 2 ++ b0 ++ b1 ++ right,
          left.size + 4 + b0.size, nesting⟩) := by
    have hmid := h0 b0 (left ++ encodeU32le 2) (b1 ++ right) nesting hdepth henc0
    have hin :
        (left ++ encodeU32le 2) ++ b0 ++ (b1 ++ right) =
          left ++ encodeU32le 2 ++ b0 ++ b1 ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ encodeU32le 2).size = left.size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    simpa [hin, hsz, ByteArray.append_assoc] using hmid
  have hinv1 :
      decode ⟨left ++ encodeU32le 2 ++ b0 ++ b1 ++ right,
          left.size + 4 + b0.size, nesting⟩ =
        .ok (v1, ⟨left ++ encodeU32le 2 ++ b0 ++ b1 ++ right,
          left.size + 4 + b0.size + b1.size, nesting⟩) := by
    have hmid := h1 b1 (left ++ encodeU32le 2 ++ b0) right nesting hdepth henc1
    have hin :
        (left ++ encodeU32le 2 ++ b0) ++ b1 ++ right =
          left ++ encodeU32le 2 ++ b0 ++ b1 ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ encodeU32le 2 ++ b0).size = left.size + 4 + b0.size := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    simpa [hin, hsz] using hmid
  exact decodeArray_of_encodeArray_two_ok_midV1 encode decode maxCount v0 v1 b b0 b1
    left right nesting hmax henc0 henc1 henc hinv0 hinv1

/-! ### Empty table array invert -/

theorem midOffsetInvert_encodeArray_empty
    (encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) (maxCount : Nat) :
    ∀ (b left right : ByteArray) (nesting : Nat),
      encodeArray encode (#[] : Array α) = .ok b →
      decodeArray maxCount decode ⟨left ++ b ++ right, left.size, nesting⟩ =
        .ok (#[], ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  intro b left right nesting henc
  exact decodeArray_of_encodeArray_zero_ok_midV1 encode decode maxCount b left right
    nesting henc

theorem decodeArray_table_empty_of_encode_midV1
    (encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α)
    (b left right : ByteArray) (nesting : Nat)
    (henc : encodeArray encode (#[] : Array α) = .ok b) :
    decodeArray maxTableElements decode
        ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (#[], ⟨left ++ b ++ right, left.size + b.size, nesting⟩) :=
  midOffsetInvert_encodeArray_empty encode decode maxTableElements b left right
    nesting henc

/-- Empty root-table MidOffsetInvert packages used by RootFieldInvert discharge. -/
theorem midOffsetInvert_empty_types_table :
    ∀ (b left right : ByteArray) (nesting : Nat),
      encodeArray encodeTypeDeclV1 (#[] : Array TypeDeclV1) = .ok b →
      decodeArray maxTableElements decodeTypeDeclV1
          ⟨left ++ b ++ right, left.size, nesting⟩ =
        .ok (#[], ⟨left ++ b ++ right, left.size + b.size, nesting⟩) :=
  fun b left right nesting h =>
    decodeArray_table_empty_of_encode_midV1 encodeTypeDeclV1 decodeTypeDeclV1
      b left right nesting h

theorem midOffsetInvert_empty_constants_table :
    ∀ (b left right : ByteArray) (nesting : Nat),
      encodeArray encodeConstantV1 (#[] : Array ConstantV1) = .ok b →
      decodeArray maxTableElements decodeConstantV1
          ⟨left ++ b ++ right, left.size, nesting⟩ =
        .ok (#[], ⟨left ++ b ++ right, left.size + b.size, nesting⟩) :=
  fun b left right nesting h =>
    decodeArray_table_empty_of_encode_midV1 encodeConstantV1 decodeConstantV1
      b left right nesting h

theorem midOffsetInvert_empty_state_table :
    ∀ (b left right : ByteArray) (nesting : Nat),
      encodeArray encodeStateDeclV1 (#[] : Array StateDeclV1) = .ok b →
      decodeArray maxTableElements decodeStateDeclV1
          ⟨left ++ b ++ right, left.size, nesting⟩ =
        .ok (#[], ⟨left ++ b ++ right, left.size + b.size, nesting⟩) :=
  fun b left right nesting h =>
    decodeArray_table_empty_of_encode_midV1 encodeStateDeclV1 decodeStateDeclV1
      b left right nesting h

theorem midOffsetInvert_empty_events_table :
    ∀ (b left right : ByteArray) (nesting : Nat),
      encodeArray encodeEventDeclV1 (#[] : Array EventDeclV1) = .ok b →
      decodeArray maxTableElements decodeEventDeclV1
          ⟨left ++ b ++ right, left.size, nesting⟩ =
        .ok (#[], ⟨left ++ b ++ right, left.size + b.size, nesting⟩) :=
  fun b left right nesting h =>
    decodeArray_table_empty_of_encode_midV1 encodeEventDeclV1 decodeEventDeclV1
      b left right nesting h

theorem midOffsetInvert_empty_errors_table :
    ∀ (b left right : ByteArray) (nesting : Nat),
      encodeArray encodeErrorDeclV1 (#[] : Array ErrorDeclV1) = .ok b →
      decodeArray maxTableElements decodeErrorDeclV1
          ⟨left ++ b ++ right, left.size, nesting⟩ =
        .ok (#[], ⟨left ++ b ++ right, left.size + b.size, nesting⟩) :=
  fun b left right nesting h =>
    decodeArray_table_empty_of_encode_midV1 encodeErrorDeclV1 decodeErrorDeclV1
      b left right nesting h

theorem midOffsetInvert_empty_invariants_table :
    ∀ (b left right : ByteArray) (nesting : Nat),
      encodeArray encodeInvariantDeclV1 (#[] : Array InvariantDeclV1) = .ok b →
      decodeArray maxTableElements decodeInvariantDeclV1
          ⟨left ++ b ++ right, left.size, nesting⟩ =
        .ok (#[], ⟨left ++ b ++ right, left.size + b.size, nesting⟩) :=
  fun b left right nesting h =>
    decodeArray_table_empty_of_encode_midV1 encodeInvariantDeclV1 decodeInvariantDeclV1
      b left right nesting h

/-! ### InvariantDecl MidOffsetInvert -/

theorem encodeInvariantDecl_ok_eqV1 (d : InvariantDeclV1) (b : ByteArray)
    (h : encodeInvariantDeclV1 d = .ok b) :
    ∃ nameB,
      encodeString d.name = .ok nameB ∧
        b = taggedBytesV1 "InvariantDecl"
          #[encodeU32le d.id, nameB, encodeU32le d.callableId] := by
  simp only [encodeInvariantDeclV1] at h
  match hn : encodeString d.name with
  | .error e => simp only [hn, Bind.bind, Except.bind] at h; cases h
  | .ok nameB =>
      simp only [hn, Bind.bind, Except.bind] at h
      have htag := encodeTagged_ok_eq_taggedBytesV1 "InvariantDecl"
        #[encodeU32le d.id, nameB, encodeU32le d.callableId] b h
      exact ⟨nameB, rfl, htag.1⟩

theorem decodeInvariantDecl_of_encode_midV1
    (d : InvariantDeclV1) (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (henc : encodeInvariantDeclV1 d = .ok b) :
    decodeInvariantDeclV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (d, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  obtain ⟨nameB, hname, hb⟩ := encodeInvariantDecl_ok_eqV1 d b henc
  subst b
  -- Canonical body bytes (flat append chain).
  have hbodyBytes :
      taggedBytesV1 "InvariantDecl"
          #[encodeU32le d.id, nameB, encodeU32le d.callableId] =
        taggedHeaderBytesV1 "InvariantDecl" 3 ++
          encodeU32le d.id ++ nameB ++ encodeU32le d.callableId :=
    taggedBytes_three_fields "InvariantDecl" (encodeU32le d.id) nameB
      (encodeU32le d.callableId)
  -- Flatten `left ++ body ++ right` after subst into left-associated chain.
  have hflatIn :
      left ++
          (taggedHeaderBytesV1 "InvariantDecl" 3 ++
            encodeU32le d.id ++ nameB ++ encodeU32le d.callableId) ++
          right =
        left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
          encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right := by
    simp [ByteArray.append_assoc]
  rw [hbodyBytes, hflatIn]
  -- expectTag
  have hexpect :
      expectTag "InvariantDecl" 3
          ⟨left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
              encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right,
            left.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
              encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right,
            left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size,
            nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
            encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right =
          left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
            (encodeU32le d.id ++ nameB ++ encodeU32le d.callableId) ++ right := by
      simp [ByteArray.append_assoc]
    rw [hin]
    exact expectTag_encode_midV1 left right "InvariantDecl" 3
      (encodeU32le d.id ++ nameB ++ encodeU32le d.callableId) (nesting + 1)
      (by decide) (by decide) (by decide) isAsciiTagBytes_InvariantDecl (by decide)
  -- id field
  have hid :
      decodeU32le
          ⟨left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
              encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right,
            left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size, nesting + 1⟩ =
        .ok (d.id,
          ⟨left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
              encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right,
            left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4,
            nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
            encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right =
          (left ++ taggedHeaderBytesV1 "InvariantDecl" 3) ++ encodeU32le d.id ++
            (nameB ++ encodeU32le d.callableId ++ right) := by
      simp [ByteArray.append_assoc]
    have hszL :
        (left ++ taggedHeaderBytesV1 "InvariantDecl" 3).size =
          left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size := by
      simp [ByteArray.size_append]
    rw [hin, ← hszL]
    exact decodeU32le_encode_midV1 (left ++ taggedHeaderBytesV1 "InvariantDecl" 3)
      (nameB ++ encodeU32le d.callableId ++ right) d.id (nesting + 1)
  -- name field
  have hnameDec :
      decodeString
          ⟨left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
              encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right,
            left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4,
            nesting + 1⟩ =
        .ok (d.name,
          ⟨left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
              encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right,
            left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4 + nameB.size,
            nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
            encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right =
          (left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++ encodeU32le d.id) ++
            nameB ++ (encodeU32le d.callableId ++ right) := by
      simp [ByteArray.append_assoc]
    have hszL :
        (left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++ encodeU32le d.id).size =
          left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    rw [hin, ← hszL]
    exact decodeString_of_encodeString_okV1
      (left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++ encodeU32le d.id)
      (encodeU32le d.callableId ++ right) d.name nameB (nesting + 1) hname
  -- callableId field
  have hcall :
      decodeU32le
          ⟨left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
              encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right,
            left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4 + nameB.size,
            nesting + 1⟩ =
        .ok (d.callableId,
          ⟨left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
              encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right,
            left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4 + nameB.size + 4,
            nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
            encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right =
          (left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++ encodeU32le d.id ++ nameB) ++
            encodeU32le d.callableId ++ right := by
      simp [ByteArray.append_assoc]
    have hszL :
        (left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++ encodeU32le d.id ++ nameB).size =
          left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4 + nameB.size := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    rw [hin, ← hszL]
    exact decodeU32le_encode_midV1
      (left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++ encodeU32le d.id ++ nameB)
      right d.callableId (nesting + 1)
  -- body
  have hbody :
      decodeInvariantDeclBodyV1
          ⟨left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
              encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right,
            left.size, nesting + 1⟩ =
        .ok (d,
          ⟨left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
              encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right,
            left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4 + nameB.size + 4,
            nesting + 1⟩) := by
    have hraw :=
      decodeInvariantDeclBodyV1_eq_of_fields
        ⟨left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
            encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right,
          left.size, nesting + 1⟩
        ⟨left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
            encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right,
          left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size, nesting + 1⟩
        ⟨left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
            encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right,
          left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4, nesting + 1⟩
        ⟨left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
            encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right,
          left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4 + nameB.size,
          nesting + 1⟩
        ⟨left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
            encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right,
          left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4 + nameB.size + 4,
          nesting + 1⟩
        d.id d.callableId d.name hexpect hid hnameDec hcall
    have heq :
        ({ id := d.id, name := d.name, callableId := d.callableId } : InvariantDeclV1) = d := by
      cases d; rfl
    rw [heq] at hraw
    exact hraw
  have hshell :=
    decodeInvariantDeclV1_eq_of_bodyV1
      ⟨left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
          encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right,
        left.size, nesting⟩
      d
      ⟨left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
          encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right,
        left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4 + nameB.size + 4,
        nesting + 1⟩
      hdepth hbody
  have hflat :
      decodeInvariantDeclV1
          ⟨left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
              encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right,
            left.size, nesting⟩ =
        .ok (d,
          ⟨left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
              encodeU32le d.id ++ nameB ++ encodeU32le d.callableId ++ right,
            left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4 + nameB.size + 4,
            nesting⟩) := by
    simpa using hshell
  have hsz :
      left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4 + nameB.size + 4 =
        left.size +
          (taggedHeaderBytesV1 "InvariantDecl" 3 ++
            encodeU32le d.id ++ nameB ++ encodeU32le d.callableId).size := by
    simp [ByteArray.size_append, encodeU32le_sizeV1]; omega
  rw [hflat, hsz]

/-- Complete: InvariantDecl production codec is mid-offset invertible. -/
theorem midOffsetInvert_encodeInvariantDecl_decodeInvariantDecl :
    MidOffsetInvertV1 encodeInvariantDeclV1 decodeInvariantDeclV1 := by
  intro d b left right nesting hdepth henc
  exact decodeInvariantDecl_of_encode_midV1 d b left right nesting hdepth henc

/-! ### ProgramRequirements empty-items invert -/

theorem encodeProgramRequirements_empty_ok_eq
    (b : ByteArray)
    (h : encodeProgramRequirementsV1 { items := #[] } = .ok b) :
    b = taggedBytesV1 "ProgramRequirements" #[encodeU32le 0] := by
  simp only [encodeProgramRequirementsV1] at h
  have hempty := encodeArray_zeroV1 encodeRequirementRequestV1
  simp only [hempty, Bind.bind, Except.bind] at h
  have htag := encodeTagged_ok_eq_taggedBytesV1 "ProgramRequirements"
    #[encodeU32le 0] b h
  exact htag.1

theorem decodeProgramRequirements_empty_of_encode_midV1
    (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (henc : encodeProgramRequirementsV1 { items := #[] } = .ok b) :
    decodeProgramRequirementsV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok ({ items := #[] },
        ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hb := encodeProgramRequirements_empty_ok_eq b henc
  subst b
  have hlayout := taggedBytes_one_field "ProgramRequirements" (encodeU32le 0)
  have hflatIn :
      left ++ (taggedHeaderBytesV1 "ProgramRequirements" 1 ++ encodeU32le 0) ++ right =
        left ++ taggedHeaderBytesV1 "ProgramRequirements" 1 ++ encodeU32le 0 ++ right := by
    simp [ByteArray.append_assoc]
  rw [hlayout, hflatIn]
  have hexpect :
      expectTag "ProgramRequirements" 1
          ⟨left ++ taggedHeaderBytesV1 "ProgramRequirements" 1 ++ encodeU32le 0 ++ right,
            left.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 "ProgramRequirements" 1 ++ encodeU32le 0 ++ right,
            left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size,
            nesting + 1⟩) :=
    expectTag_encode_midV1 left right "ProgramRequirements" 1 (encodeU32le 0)
      (nesting + 1) (by decide) (by decide) (by decide)
      isAsciiTagBytes_ProgramRequirements (by decide)
  have hitems :
      decodeArray maxArrayElements decodeRequirementRequestV1
          ⟨left ++ taggedHeaderBytesV1 "ProgramRequirements" 1 ++ encodeU32le 0 ++ right,
            left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size,
            nesting + 1⟩ =
        .ok (#[],
          ⟨left ++ taggedHeaderBytesV1 "ProgramRequirements" 1 ++ encodeU32le 0 ++ right,
            left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size + 4,
            nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "ProgramRequirements" 1 ++ encodeU32le 0 ++ right =
          (left ++ taggedHeaderBytesV1 "ProgramRequirements" 1) ++ encodeU32le 0 ++
            right := by
      simp [ByteArray.append_assoc]
    have hszL :
        (left ++ taggedHeaderBytesV1 "ProgramRequirements" 1).size =
          left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size := by
      simp [ByteArray.size_append]
    rw [hin, ← hszL]
    exact decodeArray_encode_zero_midV1 maxArrayElements decodeRequirementRequestV1
      (left ++ taggedHeaderBytesV1 "ProgramRequirements" 1) right (nesting + 1)
  have hbody :=
    decodeProgramRequirementsBodyV1_eq_of_fields
      ⟨left ++ taggedHeaderBytesV1 "ProgramRequirements" 1 ++ encodeU32le 0 ++ right,
        left.size, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "ProgramRequirements" 1 ++ encodeU32le 0 ++ right,
        left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "ProgramRequirements" 1 ++ encodeU32le 0 ++ right,
        left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size + 4, nesting + 1⟩
      #[] hexpect hitems
  have hshell :=
    decodeProgramRequirementsV1_eq_of_bodyV1
      ⟨left ++ taggedHeaderBytesV1 "ProgramRequirements" 1 ++ encodeU32le 0 ++ right,
        left.size, nesting⟩
      { items := #[] }
      ⟨left ++ taggedHeaderBytesV1 "ProgramRequirements" 1 ++ encodeU32le 0 ++ right,
        left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size + 4,
        nesting + 1⟩
      hdepth hbody
  have hszGoal :
      left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size + 4 =
        left.size +
          (taggedHeaderBytesV1 "ProgramRequirements" 1 ++ encodeU32le 0).size := by
    simp [ByteArray.size_append, encodeU32le_sizeV1]; omega
  have hflat :
      decodeProgramRequirementsV1
          ⟨left ++ taggedHeaderBytesV1 "ProgramRequirements" 1 ++ encodeU32le 0 ++ right,
            left.size, nesting⟩ =
        .ok ({ items := #[] },
          ⟨left ++ taggedHeaderBytesV1 "ProgramRequirements" 1 ++ encodeU32le 0 ++ right,
            left.size +
              (taggedHeaderBytesV1 "ProgramRequirements" 1 ++ encodeU32le 0).size,
            nesting⟩) := by
    have h0 :
        decodeProgramRequirementsV1
            ⟨left ++ taggedHeaderBytesV1 "ProgramRequirements" 1 ++ encodeU32le 0 ++ right,
              left.size, nesting⟩ =
          .ok ({ items := #[] },
            ⟨left ++ taggedHeaderBytesV1 "ProgramRequirements" 1 ++ encodeU32le 0 ++ right,
              left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size + 4,
              nesting⟩) := by
      simpa using hshell
    rw [h0, hszGoal]
  exact hflat

/-! ### Requirement scalar and table invert -/

private theorem utf8_RequirementRequest :
    "RequirementRequest".toUTF8 =
      ByteArray.mk #[82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 82,
        101, 113, 117, 101, 115, 116] := by
  rfl

private theorem isAsciiTagBytes_RequirementRequest :
    isAsciiTagBytesV1 "RequirementRequest".toUTF8 = true := by
  rw [utf8_RequirementRequest]
  exact isAsciiTagBytes_of_list_all
    [82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 82, 101, 113,
      117, 101, 115, 116] (by decide)

/-- Digest production codec is exact mid-offset invertible from any successful
    `encodeDigest` (which is the fixed SHA-256-width validity gate). -/
theorem decodeDigest_of_encode_midV1
    (digest : Digest) (b left right : ByteArray) (nesting : Nat)
    (henc : encodeDigest digest = .ok b) :
    decodeDigest ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (digest, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hvalid : validateDigest digest = .ok () := by
    simp only [encodeDigest, mapCommon] at henc
    cases hv : validateDigest digest with
    | error e => simp [hv, Bind.bind, Except.bind] at henc
    | ok u => simpa [hv] using hv
  have hb : b = digest.bytes := by
    simp only [encodeDigest, mapCommon, hvalid, Bind.bind, Except.bind, Pure.pure,
      Except.pure] at henc
    exact Except.ok.inj henc.symm
  subst b
  cases digest with
  | mk algorithm bytes =>
      cases algorithm
      have hsize : bytes.size = 32 := by
        simp only [validateDigest] at hvalid
        by_cases hs : bytes.size = 32
        · exact hs
        · simp only [hs, ↓reduceIte] at hvalid
          cases hvalid
      have htake : takeBytesAtV1 (left ++ bytes ++ right) left.size 32 = .ok bytes := by
        rw [← hsize]
        exact takeBytes_mid_payloadV1 left bytes right
      have hdec := decodeDigest_eq_of_takeV1
        ⟨left ++ bytes ++ right, left.size, nesting⟩ bytes htake hvalid
      have hfinal : left.size + 32 = left.size + bytes.size := by rw [hsize]
      simpa [hfinal] using hdec

/-- Exact-value package for Digest production encode/decode. -/
theorem exactMidOffsetInvert_digest (digest : Digest) :
    ExactMidOffsetInvertV1 encodeDigest decodeDigest digest := by
  intro b left right nesting _hdepth henc
  exact decodeDigest_of_encode_midV1 digest b left right nesting henc

private theorem s2RequirementVersion_eq_core_fields :
    s2RequirementVersionV1 = s2CatalogSemVerCoreV1 := by
  unfold s2RequirementVersionV1 s2CatalogSemVerCoreV1
  simp

private theorem renderSemVer_s2RequirementVersion_eq_ok_fields :
    renderSemVer s2RequirementVersionV1 = .ok "1.0.0" := by
  unfold s2RequirementVersionV1 renderSemVer validateSemVer
  change (do pure ("1.0.0" : String)) = Except.ok "1.0.0"
  rfl

private theorem parseSemVer_s2RequirementVersion_eq_ok_fields :
    parseSemVer "1.0.0" = .ok s2RequirementVersionV1 := by
  have h : s2CatalogSemVerCoreV1 = s2RequirementVersionV1 := by
    exact s2RequirementVersion_eq_core_fields.symm
  simpa [h] using parseSemVer_1_0_0

/-- Existing Core.Common fast-path parse certificate, specialized to the S2
    requirement version rendered by production `renderSemVer`. -/
theorem render_parse_s2RequirementVersionV1 :
    ∃ s, renderSemVer s2RequirementVersionV1 = .ok s ∧
      parseSemVer s = .ok s2RequirementVersionV1 := by
  exact ⟨"1.0.0", renderSemVer_s2RequirementVersion_eq_ok_fields,
    parseSemVer_s2RequirementVersion_eq_ok_fields⟩

/-- Production SemVer exact mid-offset inversion for the S2 requirement version
    used by the closed requirements rows. -/
theorem decodeSemVer_s2RequirementVersion_of_encode_midV1
    (b left right : ByteArray) (nesting : Nat)
    (henc : encodeSemVer s2RequirementVersionV1 = .ok b) :
    decodeSemVer ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (s2RequirementVersionV1,
        ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  obtain ⟨s, hr, hp⟩ := render_parse_s2RequirementVersionV1
  have hsEnc : encodeString s = .ok b := by
    unfold encodeSemVer at henc
    simp only [mapCommon, hr, Bind.bind, Pure.pure, Except.bind, Except.pure] at henc
    exact henc
  have hstr := decodeString_of_encodeString_okV1 left right s b nesting hsEnc
  exact decodeSemVer_eq_of_stringV1 _ _ s s2RequirementVersionV1 hstr hp

/-- Exact-value package for the production S2 SemVer requirement version. -/
theorem exactMidOffsetInvert_semVer_s2RequirementVersion :
    ExactMidOffsetInvertV1 encodeSemVer decodeSemVer s2RequirementVersionV1 := by
  intro b left right nesting _hdepth henc
  exact decodeSemVer_s2RequirementVersion_of_encode_midV1 b left right nesting henc

/-- Scalar (non-fuel-consuming) exact mid-offset inversion shape used when a
    SemVer field is nested under a tagged RequirementRequest. -/
def ScalarMidOffsetInvertV1
    (encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) (value : α) : Prop :=
  ∀ (b left right : ByteArray) (nesting : Nat),
    encode value = .ok b →
    decode ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (value, ⟨left ++ b ++ right, left.size + b.size, nesting⟩)

/-- Scalar package for the production S2 SemVer requirement version. -/
theorem scalarMidOffsetInvert_semVer_s2RequirementVersion :
    ScalarMidOffsetInvertV1 encodeSemVer decodeSemVer s2RequirementVersionV1 := by
  intro b left right nesting henc
  exact decodeSemVer_s2RequirementVersion_of_encode_midV1 b left right nesting henc

private theorem encodeRequirementRequest_empty_predicates_ok_eqV1
    (id : String) (version : SemVer) (digest : Digest) (b : ByteArray)
    (h : encodeRequirementRequestV1
        { id := id, version := version, digest := digest, predicates := #[] } = .ok b) :
    ∃ idB verB digB,
      encodeString id = .ok idB ∧
      encodeSemVer version = .ok verB ∧
      encodeDigest digest = .ok digB ∧
      b = taggedBytesV1 "RequirementRequest" #[idB, verB, digB, encodeU32le 0] := by
  unfold encodeRequirementRequestV1 at h
  cases hid : encodeString id with
  | error e => simp [hid, Bind.bind, Except.bind] at h
  | ok idB =>
  cases hver : encodeSemVer version with
  | error e => simp [hid, hver, Bind.bind, Except.bind] at h
  | ok verB =>
  cases hdig : encodeDigest digest with
  | error e => simp [hid, hver, hdig, Bind.bind, Except.bind] at h
  | ok digB =>
      have hidEnc : encodeString id = .ok idB := hid
      have hverEnc : encodeSemVer version = .ok verB := hver
      have hdigEnc : encodeDigest digest = .ok digB := hdig
      simp only [hid, hver, hdig, encodeArray_zeroV1, Bind.bind, Except.bind,
        Pure.pure, Except.pure] at h
      have htag := encodeTagged_ok_eq_taggedBytesV1 "RequirementRequest"
        #[idB, verB, digB, encodeU32le 0] b h
      exact ⟨idB, verB, digB, rfl, rfl, rfl, htag.1⟩

/-- RequirementRequest with an empty predicate array: production exact
    mid-offset inversion, parameterized by the row id/version/digest and by the
    exact SemVer package for the selected version. -/
theorem decodeRequirementRequest_emptyPredicates_of_encode_midV1
    (id : String) (version : SemVer) (digest : Digest)
    (hversionInv : ScalarMidOffsetInvertV1 encodeSemVer decodeSemVer version)
    (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (henc : encodeRequirementRequestV1
        { id := id, version := version, digest := digest, predicates := #[] } = .ok b) :
    decodeRequirementRequestV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok ({ id := id, version := version, digest := digest, predicates := #[] },
        ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  obtain ⟨idB, verB, digB, hidEnc, hverEnc, hdigEnc, hb⟩ :=
    encodeRequirementRequest_empty_predicates_ok_eqV1 id version digest b henc
  subst b
  have hlayout := taggedBytes_four_fields "RequirementRequest" idB verB digB (encodeU32le 0)
  have hflatIn :
      left ++ (taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB ++
          encodeU32le 0) ++ right =
        left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB ++
          encodeU32le 0 ++ right := by
    simp [ByteArray.append_assoc]
  rw [hlayout, hflatIn]
  have hexpect :
      expectTag "RequirementRequest" 4
          ⟨left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB ++
              encodeU32le 0 ++ right, left.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB ++
              encodeU32le 0 ++ right,
            left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size,
            nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB ++
            encodeU32le 0 ++ right =
          left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++
            (idB ++ verB ++ digB ++ encodeU32le 0) ++ right := by
      simp [ByteArray.append_assoc]
    rw [hin]
    exact expectTag_encode_midV1 left right "RequirementRequest" 4
      (idB ++ verB ++ digB ++ encodeU32le 0) (nesting + 1)
      (by decide) (by decide) (by decide) isAsciiTagBytes_RequirementRequest (by decide)
  have hid :
      decodeString
          ⟨left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB ++
              encodeU32le 0 ++ right,
            left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size,
            nesting + 1⟩ =
        .ok (id,
          ⟨left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB ++
              encodeU32le 0 ++ right,
            left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size + idB.size,
            nesting + 1⟩) := by
    have hmid := decodeString_of_encodeString_okV1
      (left ++ taggedHeaderBytesV1 "RequirementRequest" 4)
      (verB ++ digB ++ encodeU32le 0 ++ right) id idB (nesting + 1) hidEnc
    have hin :
        (left ++ taggedHeaderBytesV1 "RequirementRequest" 4) ++ idB ++
            (verB ++ digB ++ encodeU32le 0 ++ right) =
          left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB ++
            encodeU32le 0 ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ taggedHeaderBytesV1 "RequirementRequest" 4).size =
        left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size := by
      simp [ByteArray.size_append]
    simpa [hin, hsz, ByteArray.append_assoc] using hmid
  have hver :
      decodeSemVer
          ⟨left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB ++
              encodeU32le 0 ++ right,
            left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size + idB.size,
            nesting + 1⟩ =
        .ok (version,
          ⟨left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB ++
              encodeU32le 0 ++ right,
            left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size + idB.size +
              verB.size,
            nesting + 1⟩) := by
    have hmid := hversionInv verB
      (left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB)
      (digB ++ encodeU32le 0 ++ right) (nesting + 1) hverEnc
    have hin :
        (left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB) ++ verB ++
            (digB ++ encodeU32le 0 ++ right) =
          left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB ++
            encodeU32le 0 ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB).size =
        left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size + idB.size := by
      simp [ByteArray.size_append]
    simpa [hin, hsz] using hmid
  have hdig :
      decodeDigest
          ⟨left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB ++
              encodeU32le 0 ++ right,
            left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size + idB.size +
              verB.size,
            nesting + 1⟩ =
        .ok (digest,
          ⟨left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB ++
              encodeU32le 0 ++ right,
            left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size + idB.size +
              verB.size + digB.size,
            nesting + 1⟩) := by
    have hmid := decodeDigest_of_encode_midV1 digest digB
      (left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB)
      (encodeU32le 0 ++ right) (nesting + 1) hdigEnc
    have hin :
        (left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB) ++ digB ++
            (encodeU32le 0 ++ right) =
          left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB ++
            encodeU32le 0 ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB).size =
        left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size + idB.size +
          verB.size := by
      simp [ByteArray.size_append]
    simpa [hin, hsz] using hmid
  have hpred :
      decodeArray maxArrayElements decodeRequirementPredicateV1
          ⟨left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB ++
              encodeU32le 0 ++ right,
            left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size + idB.size +
              verB.size + digB.size,
            nesting + 1⟩ =
        .ok (#[],
          ⟨left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB ++
              encodeU32le 0 ++ right,
            left.size + (taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++
              digB ++ encodeU32le 0).size,
            nesting + 1⟩) := by
    have hmid := decodeArray_encode_zero_midV1 maxArrayElements
      decodeRequirementPredicateV1
      (left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB)
      right (nesting + 1)
    have hin :
        (left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB) ++
            encodeU32le 0 ++ right =
          left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB ++
            encodeU32le 0 ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB).size =
        left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size + idB.size +
          verB.size + digB.size := by
      simp [ByteArray.size_append]
    have hfinal :
        left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size + idB.size +
            verB.size + digB.size + 4 =
          left.size + (taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++
            digB ++ encodeU32le 0).size := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]; omega
    simpa [hin, hsz, hfinal] using hmid
  have hbody :
      decodeRequirementRequestV1
          ⟨left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB ++
              encodeU32le 0 ++ right, left.size, nesting⟩ =
        .ok ({ id := id, version := version, digest := digest, predicates := #[] },
          ⟨left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB ++
              encodeU32le 0 ++ right,
            left.size + (taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++
              digB ++ encodeU32le 0).size,
            nesting⟩) := by
    unfold decodeRequirementRequestV1 withTaggedNesting
    simp only [hdepth, ↓reduceIte, hexpect, hid, hver, hdig, hpred, Bind.bind,
      Pure.pure, Except.bind, Except.pure]
  simpa [ByteArray.size_append, encodeU32le_sizeV1] using hbody

/-- Exact-value package for empty-predicate requirement rows. -/
theorem exactMidOffsetInvert_requirementRequest_emptyPredicates
    (id : String) (version : SemVer) (digest : Digest)
    (hversionInv : ScalarMidOffsetInvertV1 encodeSemVer decodeSemVer version) :
    ExactMidOffsetInvertV1 encodeRequirementRequestV1 decodeRequirementRequestV1
      ({ id := id, version := version, digest := digest, predicates := #[] } :
        RequirementRequestV1) := by
  intro b left right nesting hdepth henc
  exact decodeRequirementRequest_emptyPredicates_of_encode_midV1 id version digest
    hversionInv b left right nesting hdepth henc

/-- Exact three-element array inversion from exact element inversions and the
    production element bytes. -/
theorem exactMidOffsetInvert_array_three_of_encoded_exact
    (encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) (maxCount : Nat) (hmax : 3 ≤ maxCount)
    (v0 v1 v2 : α) (b0 b1 b2 : ByteArray)
    (henc0 : encode v0 = .ok b0) (henc1 : encode v1 = .ok b1)
    (henc2 : encode v2 = .ok b2)
    (h0 : ExactMidOffsetInvertV1 encode decode v0)
    (h1 : ExactMidOffsetInvertV1 encode decode v1)
    (h2 : ExactMidOffsetInvertV1 encode decode v2) :
    ExactMidOffsetInvertV1 (encodeArray encode) (decodeArray maxCount decode) #[v0, v1, v2] := by
  intro b left right nesting hdepth henc
  have hinv0 :
      decode ⟨left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right, left.size + 4, nesting⟩ =
        .ok (v0, ⟨left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right,
          left.size + 4 + b0.size, nesting⟩) := by
    have hmid := h0 b0 (left ++ encodeU32le 3) (b1 ++ b2 ++ right) nesting hdepth henc0
    have hin : (left ++ encodeU32le 3) ++ b0 ++ (b1 ++ b2 ++ right) =
        left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ encodeU32le 3).size = left.size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    simpa [hin, hsz, ByteArray.append_assoc] using hmid
  have hinv1 :
      decode ⟨left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right,
          left.size + 4 + b0.size, nesting⟩ =
        .ok (v1, ⟨left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right,
          left.size + 4 + b0.size + b1.size, nesting⟩) := by
    have hmid := h1 b1 (left ++ encodeU32le 3 ++ b0) (b2 ++ right) nesting hdepth henc1
    have hin : (left ++ encodeU32le 3 ++ b0) ++ b1 ++ (b2 ++ right) =
        left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ encodeU32le 3 ++ b0).size = left.size + 4 + b0.size := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    have hoff0 : left.size + (4 + b0.size) = left.size + 4 + b0.size := by omega
    have hoff1 : left.size + (4 + b0.size) + b1.size =
        left.size + 4 + b0.size + b1.size := by omega
    simpa [hin, hsz, hoff0, hoff1, ByteArray.append_assoc, encodeU32le_sizeV1] using hmid
  have hinv2 :
      decode ⟨left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right,
          left.size + 4 + b0.size + b1.size, nesting⟩ =
        .ok (v2, ⟨left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right,
          left.size + 4 + b0.size + b1.size + b2.size, nesting⟩) := by
    have hmid := h2 b2 (left ++ encodeU32le 3 ++ b0 ++ b1) right nesting hdepth henc2
    have hin : (left ++ encodeU32le 3 ++ b0 ++ b1) ++ b2 ++ right =
        left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ encodeU32le 3 ++ b0 ++ b1).size =
        left.size + 4 + b0.size + b1.size := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    have hoff0 : left.size + ((4 + b0.size) + b1.size) =
        left.size + 4 + b0.size + b1.size := by omega
    have hoff1 : left.size + ((4 + b0.size) + b1.size) + b2.size =
        left.size + 4 + b0.size + b1.size + b2.size := by omega
    simpa [hin, hsz, hoff0, hoff1, encodeU32le_sizeV1] using hmid
  have hcount : readArrayCountAtV1 (left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right)
      left.size maxCount = .ok (3, left.size + 4) := by
    have hin : left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right =
        left ++ encodeU32le 3 ++ (b0 ++ b1 ++ b2 ++ right) := by
      simp [ByteArray.append_assoc]
    rw [hin]
    exact readArrayCount_encode_midV1 left (b0 ++ b1 ++ b2 ++ right) 3 maxCount
      (by decide) hmax
  have harr := decodeArray_threeV1 maxCount decode
    ⟨left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right, left.size, nesting⟩
    (left.size + 4) v0 v1 v2
    ⟨left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right,
      left.size + 4 + b0.size, nesting⟩
    ⟨left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right,
      left.size + 4 + b0.size + b1.size, nesting⟩
    ⟨left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right,
      left.size + 4 + b0.size + b1.size + b2.size, nesting⟩
    hcount hinv0 hinv1 hinv2
  have hb : b = (encodeU32le 3).append ((b0.append b1).append b2) := by
    have harray := encodeArray_threeV1 encode v0 v1 v2 b0 b1 b2 henc0 henc1 henc2
    exact Except.ok.inj (henc.symm.trans harray)
  subst b
  have hfinal : left.size + 4 + b0.size + b1.size + b2.size =
      left.size + ((encodeU32le 3).append ((b0.append b1).append b2)).size := by
    simp [ByteArray.size_append, encodeU32le_sizeV1]; omega
  simpa [hfinal, ByteArray.append_assoc] using harr

/-- Exact `ProgramRequirements` inversion for three empty-predicate rows,
    using the production bytes of the three encoded rows.  The `+1` depth
    margin is required because `ProgramRequirements` itself is tagged and its
    nonempty item array decodes tagged `RequirementRequest` elements inside that
    frame. -/
theorem decodeProgramRequirements_three_emptyPredicates_of_encode_midV1
    (id0 id1 id2 : String) (version0 version1 version2 : SemVer)
    (digest0 digest1 digest2 : Digest)
    (hversion0 : ScalarMidOffsetInvertV1 encodeSemVer decodeSemVer version0)
    (hversion1 : ScalarMidOffsetInvertV1 encodeSemVer decodeSemVer version1)
    (hversion2 : ScalarMidOffsetInvertV1 encodeSemVer decodeSemVer version2)
    (row0B row1B row2B b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting)
    (hrow0 : encodeRequirementRequestV1
      { id := id0, version := version0, digest := digest0, predicates := #[] } = .ok row0B)
    (hrow1 : encodeRequirementRequestV1
      { id := id1, version := version1, digest := digest1, predicates := #[] } = .ok row1B)
    (hrow2 : encodeRequirementRequestV1
      { id := id2, version := version2, digest := digest2, predicates := #[] } = .ok row2B)
    (henc : encodeProgramRequirementsV1
      ({ items := #[
        { id := id0, version := version0, digest := digest0, predicates := #[] },
        { id := id1, version := version1, digest := digest1, predicates := #[] },
        { id := id2, version := version2, digest := digest2, predicates := #[] }] } :
        ProgramRequirementsV1) = .ok b) :
    decodeProgramRequirementsV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (({ items := #[
        { id := id0, version := version0, digest := digest0, predicates := #[] },
        { id := id1, version := version1, digest := digest1, predicates := #[] },
        { id := id2, version := version2, digest := digest2, predicates := #[] }] } :
        ProgramRequirementsV1),
        ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  let r0 : RequirementRequestV1 :=
    { id := id0, version := version0, digest := digest0, predicates := #[] }
  let r1 : RequirementRequestV1 :=
    { id := id1, version := version1, digest := digest1, predicates := #[] }
  let r2 : RequirementRequestV1 :=
    { id := id2, version := version2, digest := digest2, predicates := #[] }
  have harray : encodeArray encodeRequirementRequestV1 #[r0, r1, r2] =
      .ok ((encodeU32le 3).append ((row0B.append row1B).append row2B)) := by
    exact encodeArray_threeV1 encodeRequirementRequestV1 r0 r1 r2 row0B row1B row2B
      (by simpa [r0] using hrow0) (by simpa [r1] using hrow1) (by simpa [r2] using hrow2)
  have hb : b = taggedBytesV1 "ProgramRequirements"
      #[((encodeU32le 3).append ((row0B.append row1B).append row2B))] := by
    simp only [encodeProgramRequirementsV1, r0, r1, r2, harray, Bind.bind,
      Pure.pure, Except.bind, Except.pure] at henc
    exact (encodeTagged_ok_eq_taggedBytesV1 "ProgramRequirements"
      #[((encodeU32le 3).append ((row0B.append row1B).append row2B))] b henc).1
  subst b
  have hlayout := taggedBytes_one_field "ProgramRequirements"
    ((encodeU32le 3).append ((row0B.append row1B).append row2B))
  rw [hlayout]
  have houter : nesting < maxNesting := Nat.lt_of_succ_lt hdepth
  refine decodeProgramRequirementsV1_eq_of_bodyV1
    ⟨left ++ (taggedHeaderBytesV1 "ProgramRequirements" 1 ++
        (encodeU32le 3).append ((row0B.append row1B).append row2B)) ++ right,
      left.size, nesting⟩
    ({ items := #[r0, r1, r2] } : ProgramRequirementsV1)
    ⟨left ++ (taggedHeaderBytesV1 "ProgramRequirements" 1 ++
        (encodeU32le 3).append ((row0B.append row1B).append row2B)) ++ right,
      left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1 ++
        (encodeU32le 3).append ((row0B.append row1B).append row2B)).size,
      nesting + 1⟩ houter ?_
  have htag :
      expectTag "ProgramRequirements" 1
          ⟨left ++ (taggedHeaderBytesV1 "ProgramRequirements" 1 ++
              (encodeU32le 3).append ((row0B.append row1B).append row2B)) ++ right,
            left.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ (taggedHeaderBytesV1 "ProgramRequirements" 1 ++
              (encodeU32le 3).append ((row0B.append row1B).append row2B)) ++ right,
            left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size,
            nesting + 1⟩) := by
    have hin :
        left ++ (taggedHeaderBytesV1 "ProgramRequirements" 1 ++
            (encodeU32le 3).append ((row0B.append row1B).append row2B)) ++ right =
          left ++ taggedHeaderBytesV1 "ProgramRequirements" 1 ++
            ((encodeU32le 3).append ((row0B.append row1B).append row2B)) ++ right := by
      simp [ByteArray.append_assoc]
    rw [hin]
    exact expectTag_encode_midV1 left right "ProgramRequirements" 1
      ((encodeU32le 3).append ((row0B.append row1B).append row2B))
      (nesting + 1) (by decide) (by decide) (by decide)
      isAsciiTagBytes_ProgramRequirements (by decide)
  have hitems :
      decodeArray maxArrayElements decodeRequirementRequestV1
          ⟨left ++ (taggedHeaderBytesV1 "ProgramRequirements" 1 ++
              (encodeU32le 3).append ((row0B.append row1B).append row2B)) ++ right,
            left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size,
            nesting + 1⟩ =
        .ok (#[r0, r1, r2],
          ⟨left ++ (taggedHeaderBytesV1 "ProgramRequirements" 1 ++
              (encodeU32le 3).append ((row0B.append row1B).append row2B)) ++ right,
            left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1 ++
              (encodeU32le 3).append ((row0B.append row1B).append row2B)).size,
            nesting + 1⟩) := by
    have hinv0 := exactMidOffsetInvert_requirementRequest_emptyPredicates id0 version0 digest0 hversion0
    have hinv1 := exactMidOffsetInvert_requirementRequest_emptyPredicates id1 version1 digest1 hversion1
    have hinv2 := exactMidOffsetInvert_requirementRequest_emptyPredicates id2 version2 digest2 hversion2
    have hdecoded := exactMidOffsetInvert_array_three_of_encoded_exact
      encodeRequirementRequestV1 decodeRequirementRequestV1 maxArrayElements (by decide)
      r0 r1 r2 row0B row1B row2B
      (by simpa [r0] using hrow0) (by simpa [r1] using hrow1) (by simpa [r2] using hrow2)
      hinv0 hinv1 hinv2
      ((encodeU32le 3).append ((row0B.append row1B).append row2B))
      (left ++ taggedHeaderBytesV1 "ProgramRequirements" 1) right (nesting + 1)
      hdepth harray
    have hoff :
        left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size +
            ((encodeU32le 3).size + (row0B.size + (row1B.size + row2B.size))) =
          left.size +
            ((taggedHeaderBytesV1 "ProgramRequirements" 1).size +
              ((encodeU32le 3).size + (row0B.size + (row1B.size + row2B.size)))) := by
      omega
    simpa [ByteArray.append_assoc, ByteArray.size_append, hoff] using hdecoded
  exact decodeProgramRequirementsBodyV1_eq_of_fields _ _ _ _ htag hitems

/-! ### Type.Bool nullary TypeShape invert -/

private theorem encodeNullary_ok_taggedHeader (tag : String)
    (hnonempty : tag.isEmpty = false)
    (hascii : isAsciiTagV1 tag = true)
    (hlimit : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (b : ByteArray)
    (h : encodeNullary tag = .ok b) :
    b = taggedHeaderBytesV1 tag 0 := by
  have hok := encodeNullary_eq_okV1 tag hnonempty hascii hlimit
  have hb := Except.ok.inj (h.symm.trans hok)
  rw [hb]
  simp only [taggedHeaderBytesV1]
  rfl

theorem decodeTypeShape_bool_of_encode_midV1
    (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (henc : encodeTypeShapeV1 .bool = .ok b) :
    decodeTypeShapeV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (.bool, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hb := encodeNullary_ok_taggedHeader "Type.Bool" (by decide) isAsciiTag_Type_Bool
    (by decide) b henc
  subst b
  have hencH :
      taggedHeaderBytesV1 "Type.Bool" 0 =
        encodeU32le (UInt32.ofNat "Type.Bool".toUTF8.size) ++ "Type.Bool".toUTF8 ++
          encodeU16le 0 := by
    simp [taggedHeaderBytesV1, ByteArray.append_assoc]
  have htag :
      decodeTag
          ⟨left ++ taggedHeaderBytesV1 "Type.Bool" 0 ++ right, left.size, nesting + 1⟩ =
        .ok ("Type.Bool",
          ⟨left ++ taggedHeaderBytesV1 "Type.Bool" 0 ++ right,
            left.size + 4 + "Type.Bool".toUTF8.size, nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "Type.Bool" 0 ++ right =
          left ++ encodeU32le (UInt32.ofNat "Type.Bool".toUTF8.size) ++
            "Type.Bool".toUTF8 ++ (encodeU16le 0 ++ right) := by
      simp [hencH, ByteArray.append_assoc]
    rw [hin]
    simpa [ByteArray.append_assoc] using
      decodeTag_encode_midV1 left (encodeU16le 0 ++ right) "Type.Bool" (nesting + 1)
        (by decide) (by decide) (by decide) isAsciiTagBytes_Type_Bool isAsciiTag_Type_Bool
  have hfc :
      decodeFieldCount 0
          ⟨left ++ taggedHeaderBytesV1 "Type.Bool" 0 ++ right,
            left.size + 4 + "Type.Bool".toUTF8.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 "Type.Bool" 0 ++ right,
            left.size + (taggedHeaderBytesV1 "Type.Bool" 0).size, nesting + 1⟩) := by
    have hassoc :
        left ++ taggedHeaderBytesV1 "Type.Bool" 0 ++ right =
          (left ++ encodeU32le (UInt32.ofNat "Type.Bool".toUTF8.size) ++
            "Type.Bool".toUTF8) ++ encodeU16le 0 ++ right := by
      simp [hencH, ByteArray.append_assoc]
    have hsz :
        (left ++ encodeU32le (UInt32.ofNat "Type.Bool".toUTF8.size) ++
            "Type.Bool".toUTF8).size =
          left.size + 4 + "Type.Bool".toUTF8.size := by
      rw [ByteArray.size_append, ByteArray.size_append, encodeU32le_sizeV1]
    have hread :
        readU16leAtV1 (left ++ taggedHeaderBytesV1 "Type.Bool" 0 ++ right)
            (left.size + 4 + "Type.Bool".toUTF8.size) =
          .ok (0, left.size + 4 + "Type.Bool".toUTF8.size + 2) := by
      rw [hassoc, ← hsz]
      simpa [hsz] using
        readU16le_encode_midV1
          (left ++ encodeU32le (UInt32.ofNat "Type.Bool".toUTF8.size) ++
            "Type.Bool".toUTF8)
          right 0
    have hszFinal :
        left.size + 4 + "Type.Bool".toUTF8.size + 2 =
          left.size + (taggedHeaderBytesV1 "Type.Bool" 0).size := by
      simp only [taggedHeaderBytesV1_size]; omega
    rw [← hszFinal]
    exact decodeFieldCount_eq_of_readU16leV1 0
      ⟨left ++ taggedHeaderBytesV1 "Type.Bool" 0 ++ right,
        left.size + 4 + "Type.Bool".toUTF8.size, nesting + 1⟩
      0 (left.size + 4 + "Type.Bool".toUTF8.size + 2) hread
  have hbody := decodeTypeShapeBodyV1_bool
    ⟨left ++ taggedHeaderBytesV1 "Type.Bool" 0 ++ right, left.size, nesting + 1⟩
    ⟨left ++ taggedHeaderBytesV1 "Type.Bool" 0 ++ right,
      left.size + 4 + "Type.Bool".toUTF8.size, nesting + 1⟩
    ⟨left ++ taggedHeaderBytesV1 "Type.Bool" 0 ++ right,
      left.size + (taggedHeaderBytesV1 "Type.Bool" 0).size, nesting + 1⟩
    htag hfc
  exact decodeTypeShapeV1_eq_of_bodyV1
    ⟨left ++ taggedHeaderBytesV1 "Type.Bool" 0 ++ right, left.size, nesting⟩
    .bool
    ⟨left ++ taggedHeaderBytesV1 "Type.Bool" 0 ++ right,
      left.size + (taggedHeaderBytesV1 "Type.Bool" 0).size, nesting + 1⟩
    hdepth hbody

/-! ### QN foundation: encode success + single-component invert -/

theorem encodeQualifiedName_ok_eqV1 (name : QualifiedName) (b : ByteArray)
    (h : encodeQualifiedName name = .ok b) :
    validateQualifiedName name = .ok () ∧
      encodeArray encodeString name.components.toArray = .ok b := by
  simp only [encodeQualifiedName, renderQualifiedNameComponents] at h
  match hv : validateQualifiedName name with
  | .error e =>
      simp only [hv, mapCommon, Bind.bind, Except.bind] at h; cases h
  | .ok u =>
      simp only [hv, mapCommon, Bind.bind, Pure.pure, Except.bind, Except.pure] at h
      exact And.intro rfl h

/-- Production chunk accumulator composition: changing the initial accumulator
    appends the same encoded suffix produced from the empty accumulator. -/
private theorem encodeArrayChunksV1_acc_eq_empty_append
    (encode : α → Except SemanticWireErrorV1 ByteArray) (xs : List α) (acc : ByteArray) :
    encodeArrayChunksV1 encode xs acc =
      match encodeArrayChunksV1 encode xs ByteArray.empty with
      | .ok payload => .ok (acc ++ payload)
      | .error e => .error e := by
  induction xs generalizing acc with
  | nil => simp [encodeArrayChunksV1, Pure.pure, Except.pure]
  | cons x xs ih =>
      cases hx : encode x with
      | error e => simp [encodeArrayChunksV1, hx, Bind.bind, Except.bind]
      | ok chunk =>
          simp only [encodeArrayChunksV1, hx, Bind.bind, Except.bind]
          rw [ih (acc.append chunk), ih (ByteArray.empty.append chunk)]
          cases htail : encodeArrayChunksV1 encode xs ByteArray.empty with
          | error e => simp
          | ok payload => simp [ByteArray.empty_append, ByteArray.append_assoc]

/-- Generic production-array element decode induction from the sole
    `encodeArrayChunksV1` worker and the sole `decodeArrayElementsV1` worker. -/
private theorem decodeArrayElements_of_encodeArrayChunks_midV1
    (encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) :
    ∀ (xs : List α) (acc : Array α) (payload left right : ByteArray) (nesting : Nat),
      encodeArrayChunksV1 encode xs ByteArray.empty = .ok payload →
      (∀ x ∈ xs, ExactMidOffsetInvertAtV1 encode decode x nesting) →
      decodeArrayElementsV1 decode xs.length acc
          ⟨left ++ payload ++ right, left.size, nesting⟩ =
        .ok (acc ++ xs.toArray,
          ⟨left ++ payload ++ right, left.size + payload.size, nesting⟩) := by
  intro xs
  induction xs with
  | nil =>
      intro acc payload left right nesting hchunks _hinv
      have hp : payload = ByteArray.empty := by
        simpa [encodeArrayChunksV1, Pure.pure, Except.pure] using hchunks.symm
      subst payload
      simp [decodeArrayElementsV1]
  | cons x xs ih =>
      intro acc payload left right nesting hchunks hinv
      cases hencx : encode x with
      | error e =>
          simp [encodeArrayChunksV1, hencx, Bind.bind, Except.bind] at hchunks
      | ok chunk =>
          have hchunks' :
              encodeArrayChunksV1 encode xs (ByteArray.empty.append chunk) = .ok payload := by
            simpa [encodeArrayChunksV1, hencx, Bind.bind, Except.bind] using hchunks
          cases htail : encodeArrayChunksV1 encode xs ByteArray.empty with
          | error e =>
              have hcomp :=
                encodeArrayChunksV1_acc_eq_empty_append encode xs (ByteArray.empty.append chunk)
              rw [htail] at hcomp
              rw [hcomp] at hchunks'
              cases hchunks'
          | ok tailPayload =>
              have hcomp :=
                encodeArrayChunksV1_acc_eq_empty_append encode xs (ByteArray.empty.append chunk)
              rw [htail] at hcomp
              have hpayload : payload = chunk ++ tailPayload := by
                exact Except.ok.inj (hchunks'.symm.trans hcomp)
              subst payload
              have hinvHead : ExactMidOffsetInvertAtV1 encode decode x nesting :=
                hinv x (List.mem_cons_self)
              have htailInv :
                  ∀ y ∈ xs, ExactMidOffsetInvertAtV1 encode decode y nesting := by
                intro y hy
                exact hinv y (List.Mem.tail x hy)
              have hfirst :
                  decode ⟨left ++ (chunk ++ tailPayload) ++ right, left.size, nesting⟩ =
                    .ok (x, ⟨left ++ (chunk ++ tailPayload) ++ right,
                      left.size + chunk.size, nesting⟩) := by
                have hmid := hinvHead chunk left (tailPayload ++ right) hencx
                have hin : left ++ chunk ++ (tailPayload ++ right) =
                    left ++ (chunk ++ tailPayload) ++ right := by
                  simp [ByteArray.append_assoc]
                simpa [hin, ByteArray.append_assoc] using hmid
              have htailRaw :=
                ih (acc.push x) tailPayload (left ++ chunk) right nesting htail htailInv
              have htailDec :
                  decodeArrayElementsV1 decode xs.length (acc.push x)
                    ⟨left ++ (chunk ++ tailPayload) ++ right,
                      left.size + chunk.size, nesting⟩ =
                  .ok (acc ++ (x :: xs).toArray,
                    ⟨left ++ (chunk ++ tailPayload) ++ right,
                      left.size + chunk.size + tailPayload.size, nesting⟩) := by
                have hin : (left ++ chunk) ++ tailPayload ++ right =
                    left ++ (chunk ++ tailPayload) ++ right := by
                  simp [ByteArray.append_assoc]
                have hsz : (left ++ chunk).size = left.size + chunk.size := by
                  simp [ByteArray.size_append]
                have hoff : (left ++ chunk).size + tailPayload.size =
                    left.size + chunk.size + tailPayload.size := by
                  simp [ByteArray.size_append]
                simpa [hin, hsz, hoff] using htailRaw
              have hsucc := decodeArrayElementsV1_succ decode xs.length acc
                ⟨left ++ (chunk ++ tailPayload) ++ right, left.size, nesting⟩
                ⟨left ++ (chunk ++ tailPayload) ++ right, left.size + chunk.size, nesting⟩
                x
                (.ok (acc ++ (x :: xs).toArray,
                  ⟨left ++ (chunk ++ tailPayload) ++ right,
                    left.size + chunk.size + tailPayload.size, nesting⟩))
                hfirst htailDec
              have hoffFinal : left.size + chunk.size + tailPayload.size =
                  left.size + (chunk.size + tailPayload.size) := by
                omega
              simpa [List.length_cons, ByteArray.size_append, hoffFinal] using hsucc

/-- Generic fixed-depth exact inversion for production arrays, parameterized
    by element encode success and fixed-depth element exact inversion.

    This is the reusable root-table seam: callers prove only the production
    codec facts for each source element, while this theorem owns the sole
    `encodeArrayChunksV1` / `decodeArrayElementsV1` induction. -/
theorem exactMidOffsetInvertAt_array_of_forall_encoded_exactAt
    (encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) (maxCount : Nat) (values : Array α) (nesting : Nat)
    (hmax : values.size ≤ maxCount)
    (hmaxArray : maxCount ≤ maxArrayElements)
    (hsizeU32 : values.size ≤ UInt32.size - 1)
    (hencElems : ∀ x ∈ values.toList, ∃ b, encode x = .ok b)
    (hinv :
      ∀ x ∈ values.toList, ExactMidOffsetInvertAtV1 encode decode x nesting) :
    ExactMidOffsetInvertAtV1
      (encodeArray encode) (decodeArray maxCount decode) values nesting := by
  intro b left right henc
  obtain ⟨payload, hchunks⟩ :=
    encodeArrayChunksV1_ok_of_forall encode values.toList ByteArray.empty hencElems
  have harray := encodeArray_eq_of_chunksV1 encode values payload
    (Nat.le_trans hmax hmaxArray) hsizeU32 hchunks
  have hb : b = (encodeU32le (UInt32.ofNat values.size)).append payload :=
    Except.ok.inj (henc.symm.trans harray)
  subst b
  have hcount :
      readArrayCountAtV1
          (left ++ (encodeU32le (UInt32.ofNat values.size)).append payload ++ right)
          left.size maxCount = .ok (values.size, left.size + 4) := by
    have hin : left ++ (encodeU32le (UInt32.ofNat values.size)).append payload ++ right =
        left ++ encodeU32le (UInt32.ofNat values.size) ++ (payload ++ right) := by
      simp [ByteArray.append_assoc]
    rw [hin]
    exact readArrayCount_encode_midV1 left (payload ++ right) values.size maxCount hsizeU32 hmax
  have helemsRaw := decodeArrayElements_of_encodeArrayChunks_midV1 encode decode
    values.toList #[] payload (left ++ encodeU32le (UInt32.ofNat values.size))
      right nesting hchunks hinv
  have helems :
      decodeArrayElementsV1 decode values.size #[]
          ⟨left ++ (encodeU32le (UInt32.ofNat values.size)).append payload ++ right,
            left.size + 4, nesting⟩ =
        .ok (values,
          ⟨left ++ (encodeU32le (UInt32.ofNat values.size)).append payload ++ right,
            left.size + 4 + payload.size, nesting⟩) := by
    have hin : (left ++ encodeU32le (UInt32.ofNat values.size)) ++ payload ++ right =
        left ++ (encodeU32le (UInt32.ofNat values.size)).append payload ++ right := by
      simp [ByteArray.append_assoc]
    have hszL : (left ++ encodeU32le (UInt32.ofNat values.size)).size = left.size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    have hlen : values.toList.length = values.size := by
      simp
    have harrayVals : (#[] : Array α) ++ values.toList.toArray = values := by
      simp
    simpa [hin, hszL, hlen, harrayVals] using helemsRaw
  have hdec := decodeArray_eq_of_elementsV1 maxCount decode
    ⟨left ++ (encodeU32le (UInt32.ofNat values.size)).append payload ++ right,
      left.size, nesting⟩ values.size (left.size + 4) values
    ⟨left ++ (encodeU32le (UInt32.ofNat values.size)).append payload ++ right,
      left.size + 4 + payload.size, nesting⟩ hcount helems
  have hoff : left.size + 4 + payload.size =
      left.size + ((encodeU32le (UInt32.ofNat values.size)).append payload).size := by
    simp [ByteArray.size_append, encodeU32le_sizeV1]
    omega
  simpa [hoff, ByteArray.append_assoc] using hdec

/-- Generic all-depth production-array inversion. This is a wrapper around the
    fixed-depth theorem above, so both root-only nested codecs and globally
    invertible leaf codecs share one array-worker proof. -/
theorem exactMidOffsetInvert_array_of_forall_encoded_exact
    (encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) (maxCount : Nat) (values : Array α)
    (hmax : values.size ≤ maxCount)
    (hmaxArray : maxCount ≤ maxArrayElements)
    (hsizeU32 : values.size ≤ UInt32.size - 1)
    (hencElems : ∀ x ∈ values.toList, ∃ b, encode x = .ok b)
    (hinv : ∀ x ∈ values.toList, ExactMidOffsetInvertV1 encode decode x) :
    ExactMidOffsetInvertV1 (encodeArray encode) (decodeArray maxCount decode) values := by
  intro b left right nesting hdepth henc
  exact
    exactMidOffsetInvertAt_array_of_forall_encoded_exactAt
      encode decode maxCount values nesting hmax hmaxArray hsizeU32 hencElems
      (by
        intro value hvalue
        exact ExactMidOffsetInvertAtV1.ofExact (hinv value hvalue) hdepth)
      b left right henc

/-- Successful list validation implies every component satisfies the shared
    production identifier-component validator. -/
private theorem validateIdentifierComponentsListV1_forall_of_ok
    (xs : List String)
    (h : validateIdentifierComponentsListV1 xs = .ok ()) :
    ∀ x ∈ xs, validateIdentifierComponent x = .ok () := by
  induction xs with
  | nil =>
      intro x hx
      cases hx
  | cons y ys ih =>
      intro x hx
      have hy : validateIdentifierComponent y = .ok () := by
        cases hv : validateIdentifierComponent y with
        | error e =>
            simp [validateIdentifierComponentsListV1, hv, Bind.bind, Except.bind] at h
        | ok u =>
            cases u
            rfl
      have hys : validateIdentifierComponentsListV1 ys = .ok () := by
        simp [validateIdentifierComponentsListV1, hy, Bind.bind, Except.bind] at h
        exact h
      cases hx with
      | head => exact hy
      | tail _ hxys => exact ih hys x hxys

/-- Successful qualified-name validation exposes the generic size bound. -/
private theorem validateQualifiedName_size_le_of_ok (name : QualifiedName)
    (h : validateQualifiedName name = .ok ()) :
    name.components.toArray.size ≤ 256 := by
  unfold validateQualifiedName at h
  by_cases hsize : name.components.toArray.size ≤ 256
  · exact hsize
  · simp only [hsize, ↓reduceIte, Bind.bind, Except.bind] at h
    cases h

/-- Successful qualified-name validation exposes component-wise identifier
    validation for the exact production component order. -/
private theorem validateQualifiedName_components_forall_of_ok (name : QualifiedName)
    (h : validateQualifiedName name = .ok ()) :
    ∀ x ∈ name.components.toArray.toList, validateIdentifierComponent x = .ok () := by
  unfold validateQualifiedName at h
  by_cases hsize : name.components.toArray.size ≤ 256
  · simp only [hsize, ↓reduceIte, Bind.bind, Except.bind, Pure.pure, Except.pure] at h
    exact validateIdentifierComponentsListV1_forall_of_ok name.components.toArray.toList h
  · simp only [hsize, ↓reduceIte, Bind.bind, Except.bind] at h
    cases h

/-- Generic `parseQualifiedName` inversion on the production `components.toArray`
    for any validated qualified name. -/
theorem parseQualifiedName_toArray_of_validate (name : QualifiedName)
    (hval : validateQualifiedName name = .ok ()) :
    parseQualifiedName name.components.toArray = .ok name := by
  have hof : NonEmptyArray.ofArray name.components.toArray = .ok name.components := by
    cases name with
    | mk comps =>
      cases comps with
      | mk head tail =>
        simp [NonEmptyArray.ofArray, NonEmptyArray.toArray]
  simp only [parseQualifiedName, hof, hval, Bind.bind, Pure.pure, Except.bind, Except.pure]

/-- Generic production QualifiedName codec inversion for arbitrary valid
    component length.  The only validation used is the one returned by the
    successful production encoder. -/
theorem exactMidOffsetInvert_qualifiedName (name : QualifiedName) :
    ExactMidOffsetInvertV1 encodeQualifiedName decodeQualifiedName name := by
  intro bytes left right nesting hdepth henc
  obtain ⟨hvalidate, harr⟩ := encodeQualifiedName_ok_eqV1 name bytes henc
  have hcomponents := validateQualifiedName_components_forall_of_ok name hvalidate
  have hencElems : ∀ x ∈ name.components.toArray.toList, ∃ b, encodeString x = .ok b := by
    intro x hx
    exact ⟨stringPayloadBytesV1 x, encodeString_of_identifierV1 x (hcomponents x hx)⟩
  have hinv : ∀ x ∈ name.components.toArray.toList,
      ExactMidOffsetInvertV1 encodeString decodeString x := by
    intro x _hx
    exact ExactMidOffsetInvertV1.ofGlobal midOffsetInvert_encodeString_decodeString x
  have harrayExact :
      ExactMidOffsetInvertV1 (encodeArray encodeString) (decodeArray 256 decodeString)
        name.components.toArray :=
    exactMidOffsetInvert_array_of_forall_encoded_exact encodeString decodeString 256
      name.components.toArray (validateQualifiedName_size_le_of_ok name hvalidate)
      (by decide) (Nat.le_trans (validateQualifiedName_size_le_of_ok name hvalidate)
        (by decide : 256 ≤ UInt32.size - 1)) hencElems hinv
  have harrDec := harrayExact bytes left right nesting hdepth harr
  exact decodeQualifiedName_eq_of_arrayV1
    ⟨left ++ bytes ++ right, left.size, nesting⟩
    ⟨left ++ bytes ++ right, left.size + bytes.size, nesting⟩
    name.components.toArray name harrDec
    (parseQualifiedName_toArray_of_validate name hvalidate)

/-- Single-component `#[comp]` ofArray recovers `{ head := comp, tail := #[] }`. -/
theorem NonEmptyArray_ofArray_singleton (comp : String) :
    NonEmptyArray.ofArray #[comp] = .ok ⟨comp, #[]⟩ := by
  have hsz : (#[comp] : Array String).size = 1 := rfl
  have hpos : 0 < (#[comp] : Array String).size := by rw [hsz]; exact Nat.zero_lt_one
  simp only [NonEmptyArray.ofArray, hpos, ↓reduceDIte]
  have h0 : (#[comp] : Array String)[0] = comp := rfl
  have htail : (#[comp] : Array String).extract 1 (#[comp] : Array String).size = #[] := by
    rw [hsz]
    apply Array.ext
    · simp
    · intro i hi hi'; cases hi
  -- After ofArray: .ok { head := arr[0], tail := extract 1 size }
  simp only [h0, htail]

theorem parseQualifiedName_singleton (comp : String)
    (hval : validateIdentifierComponent comp = .ok ()) :
    parseQualifiedName #[comp] = .ok { components := ⟨comp, #[]⟩ } := by
  -- ofArray succeeds
  have hof := NonEmptyArray_ofArray_singleton comp
  -- validate the recovered name
  have hqn : validateQualifiedName { components := ⟨comp, #[]⟩ } = .ok () := by
    unfold validateQualifiedName
    -- components.toArray = #[comp]
    have harr : ({ components := ⟨comp, #[]⟩ } : QualifiedName).components.toArray =
        #[comp] := by
      simp [NonEmptyArray.toArray]
    simp only [harr]
    have hle : (#[comp] : Array String).size ≤ 256 := by
      change 1 ≤ 256; exact Nat.le_of_lt (by decide : 1 < 256)
    -- unless gate
    simp only [hle, ↓reduceIte, Bind.bind, Pure.pure, Except.bind, Except.pure]
    exact validateIdentifierComponentsListV1_ok_of_forall [comp] (by
      intro x hx
      cases hx with
      | head => exact hval
      | tail _ h => cases h)
  -- Compose parseQualifiedName
  simp only [parseQualifiedName, hof, hqn, Bind.bind, Pure.pure, Except.bind, Except.pure]

/-- QN mid-offset invert for single-component names. -/
theorem decodeQualifiedName_one_component_of_encode_midV1
    (comp : String) (b left right : ByteArray) (nesting : Nat)
    (hval : validateIdentifierComponent comp = .ok ())
    (henc : encodeQualifiedName { components := ⟨comp, #[]⟩ } = .ok b) :
    decodeQualifiedName ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok ({ components := ⟨comp, #[]⟩ },
        ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  obtain ⟨_hvalidate, harr⟩ :=
    encodeQualifiedName_ok_eqV1 { components := ⟨comp, #[]⟩ } b henc
  have hcomps :
      ({ components := ⟨comp, #[]⟩ } : QualifiedName).components.toArray = #[comp] := by
    simp [NonEmptyArray.toArray]
  rw [hcomps] at harr
  have hstr : encodeString comp = .ok (stringPayloadBytesV1 comp) :=
    encodeString_of_identifierV1 comp hval
  have harr1 := encodeArray_oneV1 encodeString comp (stringPayloadBytesV1 comp) hstr
  have hb : b = encodeU32le 1 ++ stringPayloadBytesV1 comp :=
    Except.ok.inj (harr.symm.trans harr1)
  subst b
  -- Flatten association for decode work.
  have hflatIn :
      left ++ (encodeU32le 1 ++ stringPayloadBytesV1 comp) ++ right =
        left ++ encodeU32le 1 ++ stringPayloadBytesV1 comp ++ right := by
    simp [ByteArray.append_assoc]
  rw [hflatIn]
  have hcount :
      readArrayCountAtV1
          (left ++ encodeU32le 1 ++ stringPayloadBytesV1 comp ++ right) left.size 256 =
        .ok (1, left.size + 4) := by
    have hassoc :
        left ++ encodeU32le 1 ++ stringPayloadBytesV1 comp ++ right =
          left ++ encodeU32le 1 ++ (stringPayloadBytesV1 comp ++ right) := by
      simp [ByteArray.append_assoc]
    rw [hassoc]
    exact readArrayCount_encode_midV1 left (stringPayloadBytesV1 comp ++ right) 1 256
      (by decide) (by decide)
  have hstrDec :
      decodeString
          ⟨left ++ encodeU32le 1 ++ stringPayloadBytesV1 comp ++ right,
            left.size + 4, nesting⟩ =
        .ok (comp,
          ⟨left ++ encodeU32le 1 ++ stringPayloadBytesV1 comp ++ right,
            left.size + 4 + (stringPayloadBytesV1 comp).size, nesting⟩) := by
    have hin :
        left ++ encodeU32le 1 ++ stringPayloadBytesV1 comp ++ right =
          (left ++ encodeU32le 1) ++ stringPayloadBytesV1 comp ++ right := by
      simp [ByteArray.append_assoc]
    have hszL : (left ++ encodeU32le 1).size = left.size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    have h0 :=
      decodeString_of_identifier_midV1 (left ++ encodeU32le 1) right comp nesting hval
    have hin2 :
        (left ++ encodeU32le 1) ++ stringPayloadBytesV1 comp ++ right =
          left ++ encodeU32le 1 ++ stringPayloadBytesV1 comp ++ right := by
      simp [ByteArray.append_assoc]
    have hsp : (stringPayloadBytesV1 comp).size = 4 + comp.toUTF8.size := by
      simp [stringPayloadBytesV1, ByteArray.size_append, encodeU32le_sizeV1]
    have hx := h0
    rw [hin2, hszL] at hx
    -- hx offset is left.size + 4 + 4 + utf8; goal wants left.size + 4 + stringPayload.size
    have hoff2 :
        left.size + 4 + 4 + comp.toUTF8.size =
          left.size + 4 + (stringPayloadBytesV1 comp).size := by
      rw [hsp]; omega
    rw [hoff2] at hx
    exact hx
  have harrDec :=
    decodeArray_oneV1 256 decodeString
      ⟨left ++ encodeU32le 1 ++ stringPayloadBytesV1 comp ++ right, left.size, nesting⟩
      (left.size + 4) comp
      ⟨left ++ encodeU32le 1 ++ stringPayloadBytesV1 comp ++ right,
        left.size + 4 + (stringPayloadBytesV1 comp).size, nesting⟩
      hcount hstrDec
  have hparse := parseQualifiedName_singleton comp hval
  have hqn :=
    decodeQualifiedName_eq_of_arrayV1
      ⟨left ++ encodeU32le 1 ++ stringPayloadBytesV1 comp ++ right, left.size, nesting⟩
      ⟨left ++ encodeU32le 1 ++ stringPayloadBytesV1 comp ++ right,
        left.size + 4 + (stringPayloadBytesV1 comp).size, nesting⟩
      #[comp] { components := ⟨comp, #[]⟩ } harrDec hparse
  have hsz :
      left.size + 4 + (stringPayloadBytesV1 comp).size =
        left.size + (encodeU32le 1 ++ stringPayloadBytesV1 comp).size := by
    simp [ByteArray.size_append, encodeU32le_sizeV1]; omega
  rw [hsz] at hqn
  exact hqn


/-! ### Additional exact non-callable root-field packages -/

/-- Two-component `#[a,b]` ofArray recovers `{ head := a, tail := #[b] }`. -/
theorem NonEmptyArray_ofArray_two (a b : String) :
    NonEmptyArray.ofArray #[a, b] = .ok ⟨a, #[b]⟩ := by
  simp [NonEmptyArray.ofArray]

/-- Parse a two-component qualified name from exactly two valid identifier components. -/
theorem parseQualifiedName_two (a b : String)
    (ha : validateIdentifierComponent a = .ok ())
    (hb : validateIdentifierComponent b = .ok ()) :
    parseQualifiedName #[a, b] = .ok { components := ⟨a, #[b]⟩ } := by
  have hof := NonEmptyArray_ofArray_two a b
  have hqn : validateQualifiedName { components := ⟨a, #[b]⟩ } = .ok () := by
    unfold validateQualifiedName
    have harr : ({ components := ⟨a, #[b]⟩ } : QualifiedName).components.toArray = #[a, b] := by
      simp [NonEmptyArray.toArray]
    simp only [harr]
    have hle : (#[a, b] : Array String).size ≤ 256 := by
      change 2 ≤ 256; exact Nat.le_of_lt (by decide : 2 < 256)
    simp only [hle, ↓reduceIte, Bind.bind, Pure.pure, Except.bind, Except.pure]
    exact validateIdentifierComponentsListV1_ok_of_forall [a, b] (by
      intro x hx
      cases hx with
      | head => exact ha
      | tail _ hx' =>
          cases hx' with
          | head => exact hb
          | tail _ hnil => cases hnil)
  simp only [parseQualifiedName, hof, hqn, Bind.bind, Pure.pure, Except.bind, Except.pure]

/-- Exact mid-offset inversion for two-component qualified names. -/
theorem exactMidOffsetInvert_qualifiedName_two_components
    (a b : String)
    (ha : validateIdentifierComponent a = .ok ())
    (hb : validateIdentifierComponent b = .ok ()) :
    ExactMidOffsetInvertV1 encodeQualifiedName decodeQualifiedName
      ({ components := ⟨a, #[b]⟩ } : QualifiedName) := by
  intro bytes left right nesting _hdepth henc
  obtain ⟨_hvalidate, harr⟩ :=
    encodeQualifiedName_ok_eqV1 ({ components := ⟨a, #[b]⟩ } : QualifiedName) bytes henc
  have hcomps : ({ components := ⟨a, #[b]⟩ } : QualifiedName).components.toArray = #[a, b] := by
    simp [NonEmptyArray.toArray]
  rw [hcomps] at harr
  let ba := stringPayloadBytesV1 a
  let bb := stringPayloadBytesV1 b
  have henca : encodeString a = .ok ba := encodeString_of_identifierV1 a ha
  have hencb : encodeString b = .ok bb := encodeString_of_identifierV1 b hb
  have harray : encodeArray encodeString #[a, b] = .ok (encodeU32le 2 ++ ba ++ bb) := by
    have h := encodeArray_twoV1 encodeString a b ba bb henca hencb
    simpa [ByteArray.append_assoc] using h
  have hbytes : bytes = encodeU32le 2 ++ ba ++ bb := Except.ok.inj (harr.symm.trans harray)
  subst bytes
  have hdeca :
      decodeString ⟨left ++ encodeU32le 2 ++ ba ++ bb ++ right, left.size + 4, nesting⟩ =
        .ok (a, ⟨left ++ encodeU32le 2 ++ ba ++ bb ++ right, left.size + 4 + ba.size, nesting⟩) := by
    have hmid := decodeString_of_encodeString_okV1 (left ++ encodeU32le 2) (bb ++ right) a ba nesting henca
    have hin : (left ++ encodeU32le 2) ++ ba ++ (bb ++ right) =
        left ++ encodeU32le 2 ++ ba ++ bb ++ right := by simp [ByteArray.append_assoc]
    have hsz : (left ++ encodeU32le 2).size = left.size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    simpa [hin, hsz, ByteArray.append_assoc] using hmid
  have hdecb :
      decodeString ⟨left ++ encodeU32le 2 ++ ba ++ bb ++ right, left.size + 4 + ba.size, nesting⟩ =
        .ok (b, ⟨left ++ encodeU32le 2 ++ ba ++ bb ++ right,
          left.size + 4 + ba.size + bb.size, nesting⟩) := by
    have hmid := decodeString_of_encodeString_okV1 (left ++ encodeU32le 2 ++ ba) right b bb nesting hencb
    have hin : (left ++ encodeU32le 2 ++ ba) ++ bb ++ right =
        left ++ encodeU32le 2 ++ ba ++ bb ++ right := by simp [ByteArray.append_assoc]
    have hsz : (left ++ encodeU32le 2 ++ ba).size = left.size + 4 + ba.size := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    simpa [hin, hsz] using hmid
  have hcount : readArrayCountAtV1 (left ++ encodeU32le 2 ++ ba ++ bb ++ right) left.size 256 =
      .ok (2, left.size + 4) := by
    have hin : left ++ encodeU32le 2 ++ ba ++ bb ++ right =
        left ++ encodeU32le 2 ++ (ba ++ bb ++ right) := by simp [ByteArray.append_assoc]
    rw [hin]
    exact readArrayCount_encode_midV1 left (ba ++ bb ++ right) 2 256 (by decide) (by decide)
  have harrDec := decodeArray_twoV1 256 decodeString
    ⟨left ++ encodeU32le 2 ++ ba ++ bb ++ right, left.size, nesting⟩
    (left.size + 4) a b
    ⟨left ++ encodeU32le 2 ++ ba ++ bb ++ right, left.size + 4 + ba.size, nesting⟩
    ⟨left ++ encodeU32le 2 ++ ba ++ bb ++ right, left.size + 4 + ba.size + bb.size, nesting⟩
    hcount hdeca hdecb
  have hparse := parseQualifiedName_two a b ha hb
  have hqn := decodeQualifiedName_eq_of_arrayV1
    ⟨left ++ encodeU32le 2 ++ ba ++ bb ++ right, left.size, nesting⟩
    ⟨left ++ encodeU32le 2 ++ ba ++ bb ++ right, left.size + 4 + ba.size + bb.size, nesting⟩
    #[a, b] ({ components := ⟨a, #[b]⟩ } : QualifiedName) harrDec hparse
  have hsz : left.size + 4 + ba.size + bb.size = left.size + (encodeU32le 2 ++ ba ++ bb).size := by
    simp [ByteArray.size_append, encodeU32le_sizeV1]; omega
  simpa [hsz, ByteArray.append_assoc] using hqn

/-- Three-component `#[a,b,c]` recovers the corresponding nonempty component array. -/
theorem NonEmptyArray_ofArray_three (a b c : String) :
    NonEmptyArray.ofArray #[a, b, c] = .ok ⟨a, #[b, c]⟩ := by
  simp [NonEmptyArray.ofArray]

/-- Parse a three-component qualified name from valid identifier components. -/
theorem parseQualifiedName_three (a b c : String)
    (ha : validateIdentifierComponent a = .ok ())
    (hb : validateIdentifierComponent b = .ok ())
    (hc : validateIdentifierComponent c = .ok ()) :
    parseQualifiedName #[a, b, c] = .ok { components := ⟨a, #[b, c]⟩ } := by
  have hof := NonEmptyArray_ofArray_three a b c
  have hqn : validateQualifiedName { components := ⟨a, #[b, c]⟩ } = .ok () := by
    unfold validateQualifiedName
    have harr : ({ components := ⟨a, #[b, c]⟩ } : QualifiedName).components.toArray =
        #[a, b, c] := by
      simp [NonEmptyArray.toArray]
    simp only [harr]
    have hle : (#[a, b, c] : Array String).size ≤ 256 := by
      change 3 ≤ 256
      decide
    simp only [hle, ↓reduceIte, Bind.bind, Pure.pure, Except.bind, Except.pure]
    exact validateIdentifierComponentsListV1_ok_of_forall [a, b, c] (by
      intro x hx
      cases hx with
      | head => exact ha
      | tail _ hx' =>
          cases hx' with
          | head => exact hb
          | tail _ hx'' =>
              cases hx'' with
              | head => exact hc
              | tail _ hnil => cases hnil)
  simp only [parseQualifiedName, hof, hqn, Bind.bind, Pure.pure, Except.bind, Except.pure]

/-- Exact mid-offset inversion for three-component qualified names. -/
theorem exactMidOffsetInvert_qualifiedName_three_components
    (a b c : String)
    (ha : validateIdentifierComponent a = .ok ())
    (hb : validateIdentifierComponent b = .ok ())
    (hc : validateIdentifierComponent c = .ok ()) :
    ExactMidOffsetInvertV1 encodeQualifiedName decodeQualifiedName
      ({ components := ⟨a, #[b, c]⟩ } : QualifiedName) := by
  intro bytes left right nesting hdepth henc
  obtain ⟨_hvalidate, harr⟩ :=
    encodeQualifiedName_ok_eqV1 ({ components := ⟨a, #[b, c]⟩ } : QualifiedName) bytes henc
  have hcomps : ({ components := ⟨a, #[b, c]⟩ } : QualifiedName).components.toArray =
      #[a, b, c] := by
    simp [NonEmptyArray.toArray]
  rw [hcomps] at harr
  let ba := stringPayloadBytesV1 a
  let bb := stringPayloadBytesV1 b
  let bc := stringPayloadBytesV1 c
  have henca : encodeString a = .ok ba := encodeString_of_identifierV1 a ha
  have hencb : encodeString b = .ok bb := encodeString_of_identifierV1 b hb
  have hencc : encodeString c = .ok bc := encodeString_of_identifierV1 c hc
  have harrayExact :
      ExactMidOffsetInvertV1 (encodeArray encodeString) (decodeArray 256 decodeString)
        #[a, b, c] :=
    exactMidOffsetInvert_array_three_of_encoded_exact encodeString decodeString 256
      (by decide) a b c ba bb bc henca hencb hencc
      (ExactMidOffsetInvertV1.ofGlobal midOffsetInvert_encodeString_decodeString a)
      (ExactMidOffsetInvertV1.ofGlobal midOffsetInvert_encodeString_decodeString b)
      (ExactMidOffsetInvertV1.ofGlobal midOffsetInvert_encodeString_decodeString c)
  have harrDec := harrayExact bytes left right nesting hdepth harr
  exact decodeQualifiedName_eq_of_arrayV1
    ⟨left ++ bytes ++ right, left.size, nesting⟩
    ⟨left ++ bytes ++ right, left.size + bytes.size, nesting⟩
    #[a, b, c] ({ components := ⟨a, #[b, c]⟩ } : QualifiedName) harrDec
    (parseQualifiedName_three a b c ha hb hc)

/-- Exact empty constants table inversion. -/
theorem exactMidOffsetInvert_empty_constants_table :
    ExactMidOffsetInvertV1 (encodeArray encodeConstantV1)
      (decodeArray maxTableElements decodeConstantV1) (#[] : Array ConstantV1) := by
  intro b left right nesting _ henc
  exact midOffsetInvert_empty_constants_table b left right nesting henc

/-- Exact empty events table inversion. -/
theorem exactMidOffsetInvert_empty_events_table :
    ExactMidOffsetInvertV1 (encodeArray encodeEventDeclV1)
      (decodeArray maxTableElements decodeEventDeclV1) (#[] : Array EventDeclV1) := by
  intro b left right nesting _ henc
  exact midOffsetInvert_empty_events_table b left right nesting henc

/-- Exact empty errors table inversion. -/
theorem exactMidOffsetInvert_empty_errors_table :
    ExactMidOffsetInvertV1 (encodeArray encodeErrorDeclV1)
      (decodeArray maxTableElements decodeErrorDeclV1) (#[] : Array ErrorDeclV1) := by
  intro b left right nesting _ henc
  exact midOffsetInvert_empty_errors_table b left right nesting henc

/-! ### Type and State exact non-callable codecs -/

private theorem utf8_Type_UInt :
    "Type.UInt".toUTF8 = ByteArray.mk #[84, 121, 112, 101, 46, 85, 73, 110, 116] := by
  rfl

private theorem isAsciiTagBytes_Type_UInt :
    isAsciiTagBytesV1 "Type.UInt".toUTF8 = true := by
  rw [utf8_Type_UInt]
  exact isAsciiTagBytes_of_list_all
    [84, 121, 112, 101, 46, 85, 73, 110, 116] (by decide)

private theorem isAsciiTag_Type_UInt : isAsciiTagV1 "Type.UInt" = true := by decide

private theorem utf8_TypeDecl :
    "TypeDecl".toUTF8 = ByteArray.mk #[84, 121, 112, 101, 68, 101, 99, 108] := by
  rfl

private theorem isAsciiTagBytes_TypeDecl :
    isAsciiTagBytesV1 "TypeDecl".toUTF8 = true := by
  rw [utf8_TypeDecl]
  exact isAsciiTagBytes_of_list_all
    [84, 121, 112, 101, 68, 101, 99, 108] (by decide)

private theorem utf8_StateDecl :
    "StateDecl".toUTF8 = ByteArray.mk #[83, 116, 97, 116, 101, 68, 101, 99, 108] := by
  rfl

private theorem isAsciiTagBytes_StateDecl :
    isAsciiTagBytesV1 "StateDecl".toUTF8 = true := by
  rw [utf8_StateDecl]
  exact isAsciiTagBytes_of_list_all
    [83, 116, 97, 116, 101, 68, 101, 99, 108] (by decide)

private def optionNoneBytesV1 : ByteArray := encodeU8 0

private theorem encodeOptionString_none_eq_ok :
    encodeOption encodeString (none : Option String) = .ok optionNoneBytesV1 := by
  rfl

private theorem decodeOptionString_none_midV1
    (left right : ByteArray) (nesting : Nat) :
    decodeOption decodeString
        ⟨left ++ optionNoneBytesV1 ++ right, left.size, nesting⟩ =
      .ok (none,
        ⟨left ++ optionNoneBytesV1 ++ right, left.size + optionNoneBytesV1.size, nesting⟩) := by
  have hs : optionNoneBytesV1.size = 1 := by
    simp [optionNoneBytesV1, encodeU8, ByteArray.size_push, ByteArray.size_empty]
  have hg : optionNoneBytesV1.data[0]? = some 0 := by
    simp [optionNoneBytesV1, encodeU8, ByteArray.data_push, ByteArray.data_empty]
  have hmarker :
      decodeU8 ⟨left ++ optionNoneBytesV1 ++ right, left.size, nesting⟩ =
        .ok (0, ⟨left ++ optionNoneBytesV1 ++ right, left.size + 1, nesting⟩) := by
    apply decodeU8_eq_of_readV1
    exact readByte_mid_payloadV1 left optionNoneBytesV1 right 0 0
      (by simp [hs]) hg
  have h := decodeOption_noneV1 decodeString _ _ hmarker
  simpa [hs] using h

/-- Exact mid-offset inversion for the production UInt TypeShape codec. -/
theorem decodeTypeShape_uint_of_encode_midV1
    (w : UInt16) (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (henc : encodeTypeShapeV1 (.uint w) = .ok b) :
    decodeTypeShapeV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (.uint w, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hb : b = taggedBytesV1 "Type.UInt" #[encodeU16le w] := by
    simp only [encodeTypeShapeV1] at henc
    exact (encodeTagged_ok_eq_taggedBytesV1 "Type.UInt" #[encodeU16le w] b henc).1
  subst b
  have hlayout := taggedBytes_one_field "Type.UInt" (encodeU16le w)
  have hflatIn :
      left ++ (taggedHeaderBytesV1 "Type.UInt" 1 ++ encodeU16le w) ++ right =
        left ++ taggedHeaderBytesV1 "Type.UInt" 1 ++ encodeU16le w ++ right := by
    simp [ByteArray.append_assoc]
  rw [hlayout, hflatIn]
  refine decodeTypeShapeV1_eq_of_bodyV1
    ⟨left ++ taggedHeaderBytesV1 "Type.UInt" 1 ++ encodeU16le w ++ right,
      left.size, nesting⟩ (.uint w)
    ⟨left ++ taggedHeaderBytesV1 "Type.UInt" 1 ++ encodeU16le w ++ right,
      left.size + (taggedHeaderBytesV1 "Type.UInt" 1 ++ encodeU16le w).size,
      nesting + 1⟩ hdepth ?_
  have hencH :
      taggedHeaderBytesV1 "Type.UInt" 1 =
        encodeU32le (UInt32.ofNat "Type.UInt".toUTF8.size) ++ "Type.UInt".toUTF8 ++
          encodeU16le 1 := by
    simp [taggedHeaderBytesV1, ByteArray.append_assoc]
  have htag :
      decodeTag
          ⟨left ++ taggedHeaderBytesV1 "Type.UInt" 1 ++ encodeU16le w ++ right,
            left.size, nesting + 1⟩ =
        .ok ("Type.UInt",
          ⟨left ++ taggedHeaderBytesV1 "Type.UInt" 1 ++ encodeU16le w ++ right,
            left.size + 4 + "Type.UInt".toUTF8.size, nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "Type.UInt" 1 ++ encodeU16le w ++ right =
          left ++ encodeU32le (UInt32.ofNat "Type.UInt".toUTF8.size) ++
            "Type.UInt".toUTF8 ++ (encodeU16le 1 ++ encodeU16le w ++ right) := by
      simp [hencH, ByteArray.append_assoc]
    rw [hin]
    simpa [ByteArray.append_assoc] using
      decodeTag_encode_midV1 left (encodeU16le 1 ++ encodeU16le w ++ right)
        "Type.UInt" (nesting + 1) (by decide) (by decide) (by decide)
        isAsciiTagBytes_Type_UInt isAsciiTag_Type_UInt
  have hfc :
      decodeFieldCount 1
          ⟨left ++ taggedHeaderBytesV1 "Type.UInt" 1 ++ encodeU16le w ++ right,
            left.size + 4 + "Type.UInt".toUTF8.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 "Type.UInt" 1 ++ encodeU16le w ++ right,
            left.size + 4 + "Type.UInt".toUTF8.size + 2, nesting + 1⟩) := by
    have hassoc :
        left ++ taggedHeaderBytesV1 "Type.UInt" 1 ++ encodeU16le w ++ right =
          (left ++ encodeU32le (UInt32.ofNat "Type.UInt".toUTF8.size) ++
            "Type.UInt".toUTF8) ++ encodeU16le 1 ++ (encodeU16le w ++ right) := by
      simp [hencH, ByteArray.append_assoc]
    have hsz :
        (left ++ encodeU32le (UInt32.ofNat "Type.UInt".toUTF8.size) ++
          "Type.UInt".toUTF8).size =
          left.size + 4 + "Type.UInt".toUTF8.size := by
      rw [ByteArray.size_append, ByteArray.size_append, encodeU32le_sizeV1]
    have hread :
        readU16leAtV1
          (left ++ taggedHeaderBytesV1 "Type.UInt" 1 ++ encodeU16le w ++ right)
          (left.size + 4 + "Type.UInt".toUTF8.size) =
          .ok (1, left.size + 4 + "Type.UInt".toUTF8.size + 2) := by
      rw [hassoc, ← hsz]
      simpa [hsz] using
        readU16le_encode_midV1
          (left ++ encodeU32le (UInt32.ofNat "Type.UInt".toUTF8.size) ++
            "Type.UInt".toUTF8)
          (encodeU16le w ++ right) 1
    exact decodeFieldCount_eq_of_readU16leV1 1
      ⟨left ++ taggedHeaderBytesV1 "Type.UInt" 1 ++ encodeU16le w ++ right,
        left.size + 4 + "Type.UInt".toUTF8.size, nesting + 1⟩
      1 (left.size + 4 + "Type.UInt".toUTF8.size + 2) hread
  have hwidth :
      decodeU16le
          ⟨left ++ taggedHeaderBytesV1 "Type.UInt" 1 ++ encodeU16le w ++ right,
            left.size + 4 + "Type.UInt".toUTF8.size + 2, nesting + 1⟩ =
        .ok (w,
          ⟨left ++ taggedHeaderBytesV1 "Type.UInt" 1 ++ encodeU16le w ++ right,
            left.size + (taggedHeaderBytesV1 "Type.UInt" 1 ++ encodeU16le w).size,
            nesting + 1⟩) := by
    have hassoc :
        left ++ taggedHeaderBytesV1 "Type.UInt" 1 ++ encodeU16le w ++ right =
          (left ++ encodeU32le (UInt32.ofNat "Type.UInt".toUTF8.size) ++
            "Type.UInt".toUTF8 ++ encodeU16le 1) ++ encodeU16le w ++ right := by
      simp [hencH, ByteArray.append_assoc]
    have hsz :
        (left ++ encodeU32le (UInt32.ofNat "Type.UInt".toUTF8.size) ++
          "Type.UInt".toUTF8 ++ encodeU16le 1).size =
          left.size + 4 + "Type.UInt".toUTF8.size + 2 := by
      rw [ByteArray.size_append, ByteArray.size_append, ByteArray.size_append,
        encodeU32le_sizeV1, encodeU16le_sizeV1]
    have hfinal :
        left.size + 4 + "Type.UInt".toUTF8.size + 2 + 2 =
          left.size + (taggedHeaderBytesV1 "Type.UInt" 1 ++ encodeU16le w).size := by
      simp [ByteArray.size_append, taggedHeaderBytesV1_size, encodeU16le_sizeV1]; omega
    apply decodeU16le_eq_of_readV1
    rw [← hfinal, hassoc, ← hsz]
    simpa [hsz] using
      readU16le_encode_midV1
        (left ++ encodeU32le (UInt32.ofNat "Type.UInt".toUTF8.size) ++
          "Type.UInt".toUTF8 ++ encodeU16le 1)
        right w
  exact decodeTypeShapeBodyV1_uint _ _ _ _ w htag hfc hwidth

/-- Exact mid-offset inversion for the production Bool TypeShape codec. -/
theorem exactMidOffsetInvert_typeShape_bool :
    ExactMidOffsetInvertV1 encodeTypeShapeV1 decodeTypeShapeV1 .bool := by
  intro b left right nesting hdepth henc
  exact decodeTypeShape_bool_of_encode_midV1 b left right nesting hdepth henc

/-- Exact mid-offset inversion for the production UInt TypeShape codec. -/
theorem exactMidOffsetInvert_typeShape_uint (w : UInt16) :
    ExactMidOffsetInvertV1 encodeTypeShapeV1 decodeTypeShapeV1 (.uint w) := by
  intro b left right nesting hdepth henc
  exact decodeTypeShape_uint_of_encode_midV1 w b left right nesting hdepth henc

private theorem encodeTypeDecl_none_ok_eqV1
    (id : UInt32) (shape : TypeShapeV1) (b : ByteArray)
    (h : encodeTypeDeclV1 { id := id, name := none, shape := shape } = .ok b) :
    ∃ shapeB,
      encodeTypeShapeV1 shape = .ok shapeB ∧
        b = taggedBytesV1 "TypeDecl" #[encodeU32le id, optionNoneBytesV1, shapeB] := by
  simp only [encodeTypeDeclV1, encodeOptionString_none_eq_ok, Bind.bind, Except.bind,
    Pure.pure, Except.pure] at h
  match hs : encodeTypeShapeV1 shape with
  | .error e => simp only [hs, Bind.bind, Except.bind] at h; cases h
  | .ok shapeB =>
      simp only [hs, Bind.bind, Except.bind] at h
      have htag := encodeTagged_ok_eq_taggedBytesV1 "TypeDecl"
        #[encodeU32le id, optionNoneBytesV1, shapeB] b h
      exact ⟨shapeB, by simpa [hs], htag.1⟩

/-- Generic anonymous TypeDecl mid-offset inversion for leaf shapes whose nested
    TypeShape production codec has an exact inversion proof.  The `+1` depth
    margin is the production nesting consumed by TypeDecl before decoding the
    nested TypeShape. -/
theorem decodeTypeDecl_none_of_encode_midV1
    (id : UInt32) (shape : TypeShapeV1)
    (hshapeInv : ExactMidOffsetInvertV1 encodeTypeShapeV1 decodeTypeShapeV1 shape)
    (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting)
    (henc : encodeTypeDeclV1 { id := id, name := none, shape := shape } = .ok b) :
    decodeTypeDeclV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok ({ id := id, name := none, shape := shape },
        ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  obtain ⟨shapeB, hshapeEnc, hb⟩ := encodeTypeDecl_none_ok_eqV1 id shape b henc
  subst b
  have hlayout := taggedBytes_three_fields "TypeDecl" (encodeU32le id) optionNoneBytesV1 shapeB
  have hflatIn :
      left ++
          (taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++ shapeB) ++
          right =
        left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
          shapeB ++ right := by
    simp [ByteArray.append_assoc]
  rw [hlayout, hflatIn]
  have houter : nesting < maxNesting := Nat.lt_of_succ_lt hdepth
  refine decodeTypeDeclV1_eq_of_bodyV1
    ⟨left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
        shapeB ++ right, left.size, nesting⟩
    ({ id := id, name := none, shape := shape } : TypeDeclV1)
    ⟨left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
        shapeB ++ right,
      left.size + (taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
        shapeB).size, nesting + 1⟩ houter ?_
  have hexpect :
      expectTag "TypeDecl" 3
          ⟨left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
              shapeB ++ right, left.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
              shapeB ++ right,
            left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size, nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
            shapeB ++ right =
          left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++
            (encodeU32le id ++ optionNoneBytesV1 ++ shapeB) ++ right := by
      simp [ByteArray.append_assoc]
    rw [hin]
    exact expectTag_encode_midV1 left right "TypeDecl" 3
      (encodeU32le id ++ optionNoneBytesV1 ++ shapeB) (nesting + 1)
      (by decide) (by decide) (by decide) isAsciiTagBytes_TypeDecl (by decide)
  have hid :
      decodeU32le
          ⟨left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
              shapeB ++ right,
            left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size, nesting + 1⟩ =
        .ok (id,
          ⟨left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
              shapeB ++ right,
            left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4, nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
            shapeB ++ right =
          (left ++ taggedHeaderBytesV1 "TypeDecl" 3) ++ encodeU32le id ++
            (optionNoneBytesV1 ++ shapeB ++ right) := by
      simp [ByteArray.append_assoc]
    have hsz :
        (left ++ taggedHeaderBytesV1 "TypeDecl" 3).size =
          left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size := by
      simp [ByteArray.size_append]
    rw [hin, ← hsz]
    exact decodeU32le_encode_midV1 (left ++ taggedHeaderBytesV1 "TypeDecl" 3)
      (optionNoneBytesV1 ++ shapeB ++ right) id (nesting + 1)
  have hname :
      decodeOption decodeString
          ⟨left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
              shapeB ++ right,
            left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4, nesting + 1⟩ =
        .ok (none,
          ⟨left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
              shapeB ++ right,
            left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4 + optionNoneBytesV1.size,
            nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
            shapeB ++ right =
          (left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id) ++
            optionNoneBytesV1 ++ (shapeB ++ right) := by
      simp [ByteArray.append_assoc]
    have hsz :
        (left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id).size =
          left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    have h := decodeOptionString_none_midV1
      (left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id)
      (shapeB ++ right) (nesting + 1)
    simpa [hin, hsz] using h
  have hshape :
      decodeTypeShapeV1
          ⟨left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
              shapeB ++ right,
            left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4 + optionNoneBytesV1.size,
            nesting + 1⟩ =
        .ok (shape,
          ⟨left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
              shapeB ++ right,
            left.size + (taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
              shapeB).size, nesting + 1⟩) := by
    have hmid := hshapeInv shapeB
      (left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1)
      right (nesting + 1) hdepth hshapeEnc
    have hin :
        (left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1) ++
            shapeB ++ right =
          left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
            shapeB ++ right := by
      simp [ByteArray.append_assoc]
    have hsz :
        (left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1).size =
          left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4 + optionNoneBytesV1.size := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    have hfinal :
        left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4 + optionNoneBytesV1.size +
            shapeB.size =
          left.size +
            ((taggedHeaderBytesV1 "TypeDecl" 3).size + (encodeU32le id).size +
              optionNoneBytesV1.size + shapeB.size) := by
      simp only [encodeU32le_sizeV1]
      omega
    simpa [hin, hsz, hfinal, ByteArray.size_append, encodeU32le_sizeV1] using hmid
  have hbody := decodeTypeDeclBodyV1_eq_of_fields
    ⟨left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
        shapeB ++ right, left.size, nesting + 1⟩
    ⟨left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
        shapeB ++ right, left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size, nesting + 1⟩
    ⟨left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
        shapeB ++ right, left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4, nesting + 1⟩
    ⟨left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
        shapeB ++ right,
      left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4 + optionNoneBytesV1.size,
      nesting + 1⟩
    ⟨left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
        shapeB ++ right,
      left.size + (taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le id ++ optionNoneBytesV1 ++
        shapeB).size, nesting + 1⟩
    id none shape hexpect hid hname hshape
  simpa using hbody

/-- Exact mid-offset inversion for anonymous UInt TypeDecls. -/
theorem decodeTypeDecl_uint_none_of_encode_midV1
    (id : UInt32) (w : UInt16) (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting)
    (henc : encodeTypeDeclV1 { id := id, name := none, shape := .uint w } = .ok b) :
    decodeTypeDeclV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok ({ id := id, name := none, shape := .uint w },
        ⟨left ++ b ++ right, left.size + b.size, nesting⟩) :=
  decodeTypeDecl_none_of_encode_midV1 id (.uint w) (exactMidOffsetInvert_typeShape_uint w)
    b left right nesting hdepth henc

/-- Exact mid-offset inversion for anonymous Bool TypeDecls. -/
theorem decodeTypeDecl_bool_none_of_encode_midV1
    (id : UInt32) (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting)
    (henc : encodeTypeDeclV1 { id := id, name := none, shape := .bool } = .ok b) :
    decodeTypeDeclV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok ({ id := id, name := none, shape := .bool },
        ⟨left ++ b ++ right, left.size + b.size, nesting⟩) :=
  decodeTypeDecl_none_of_encode_midV1 id .bool exactMidOffsetInvert_typeShape_bool
    b left right nesting hdepth henc

/-- Fixed-depth exact inversion for an anonymous TypeDecl whose nested shape
    has a production exact-inversion certificate. -/
theorem exactAt_typeDecl_none_of_shapeV1
    (id : UInt32) (shape : TypeShapeV1) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting)
    (hshapeInv : ExactMidOffsetInvertV1 encodeTypeShapeV1 decodeTypeShapeV1 shape) :
    ExactMidOffsetInvertAtV1 encodeTypeDeclV1 decodeTypeDeclV1
      ({ id := id, name := none, shape := shape } : TypeDeclV1) nesting := by
  intro b left right henc
  exact
    decodeTypeDecl_none_of_encode_midV1 id shape hshapeInv b left right
      nesting hdepth henc

/-- Fixed-depth anonymous UInt TypeDecl inversion. -/
theorem exactAt_typeDecl_uint_noneV1
    (id : UInt32) (width : UInt16) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting) :
    ExactMidOffsetInvertAtV1 encodeTypeDeclV1 decodeTypeDeclV1
      ({ id := id, name := none, shape := .uint width } : TypeDeclV1) nesting :=
  exactAt_typeDecl_none_of_shapeV1 id (.uint width) nesting hdepth
    (exactMidOffsetInvert_typeShape_uint width)

/-- Fixed-depth anonymous Bool TypeDecl inversion. -/
theorem exactAt_typeDecl_bool_noneV1
    (id : UInt32) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting) :
    ExactMidOffsetInvertAtV1 encodeTypeDeclV1 decodeTypeDeclV1
      ({ id := id, name := none, shape := .bool } : TypeDeclV1) nesting :=
  exactAt_typeDecl_none_of_shapeV1 id .bool nesting hdepth
    exactMidOffsetInvert_typeShape_bool

/-- Exact two-element anonymous TypeDecl root table for UInt64 then Bool. -/
theorem decodeTypes_uint64_bool_table_of_encode_midV1
    (uintB boolB : ByteArray)
    (huint : encodeTypeDeclV1 { id := 0, name := none, shape := .uint 64 } = .ok uintB)
    (hbool : encodeTypeDeclV1 { id := 1, name := none, shape := .bool } = .ok boolB)
    (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting)
    (henc : encodeArray encodeTypeDeclV1
      #[{ id := 0, name := none, shape := .uint 64 }, { id := 1, name := none, shape := .bool }] = .ok b) :
    decodeArray maxTableElements decodeTypeDeclV1
        ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (#[{ id := 0, name := none, shape := .uint 64 },
          { id := 1, name := none, shape := .bool }],
        ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hinv0 :
      decodeTypeDeclV1 ⟨left ++ encodeU32le 2 ++ uintB ++ boolB ++ right,
          left.size + 4, nesting⟩ =
        .ok ({ id := 0, name := none, shape := .uint 64 },
          ⟨left ++ encodeU32le 2 ++ uintB ++ boolB ++ right,
            left.size + 4 + uintB.size, nesting⟩) := by
    have hmid := decodeTypeDecl_uint_none_of_encode_midV1 0 64 uintB
      (left ++ encodeU32le 2) (boolB ++ right) nesting hdepth huint
    have hin :
        (left ++ encodeU32le 2) ++ uintB ++ (boolB ++ right) =
          left ++ encodeU32le 2 ++ uintB ++ boolB ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ encodeU32le 2).size = left.size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    simpa [hin, hsz, ByteArray.append_assoc] using hmid
  have hinv1 :
      decodeTypeDeclV1 ⟨left ++ encodeU32le 2 ++ uintB ++ boolB ++ right,
          left.size + 4 + uintB.size, nesting⟩ =
        .ok ({ id := 1, name := none, shape := .bool },
          ⟨left ++ encodeU32le 2 ++ uintB ++ boolB ++ right,
            left.size + 4 + uintB.size + boolB.size, nesting⟩) := by
    have hmid := decodeTypeDecl_bool_none_of_encode_midV1 1 boolB
      (left ++ encodeU32le 2 ++ uintB) right nesting hdepth hbool
    have hin :
        (left ++ encodeU32le 2 ++ uintB) ++ boolB ++ right =
          left ++ encodeU32le 2 ++ uintB ++ boolB ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ encodeU32le 2 ++ uintB).size = left.size + 4 + uintB.size := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    simpa [hin, hsz] using hmid
  exact decodeArray_of_encodeArray_two_ok_midV1 encodeTypeDeclV1 decodeTypeDeclV1
    maxTableElements { id := 0, name := none, shape := .uint 64 }
    { id := 1, name := none, shape := .bool } b uintB boolB left right nesting
    (by decide) huint hbool henc hinv0 hinv1

/-- Exact mid-offset inversion for the public state declaration leaf used by the
    non-callable root table package. -/
theorem decodeStateDecl_public_of_encode_midV1
    (id typeId : UInt32) (stateName : String)
    (hval : validateIdentifierComponent stateName = .ok ())
    (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting)
    (henc : encodeStateDeclV1
      { id, name := stateName, typeId, visibility := .public_ } = .ok b) :
    decodeStateDeclV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok ({ id, name := stateName, typeId, visibility := .public_ },
        ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hnameEnc : encodeString stateName = .ok (stringPayloadBytesV1 stateName) :=
    encodeString_of_identifierV1 stateName hval
  have hvisEnc : encodeVisibilityV1 .public_ = .ok (taggedHeaderBytesV1 "Visibility.Public" 0) :=
    encodeVisibility_public_eq
  simp only [encodeStateDeclV1, hnameEnc, hvisEnc, Bind.bind, Except.bind,
    Pure.pure, Except.pure] at henc
  have hb := (encodeTagged_ok_eq_taggedBytesV1 "StateDecl"
    #[encodeU32le id, stringPayloadBytesV1 stateName, encodeU32le typeId,
      taggedHeaderBytesV1 "Visibility.Public" 0] b henc).1
  subst b
  have hlayout := taggedBytes_four_fields "StateDecl" (encodeU32le id)
    (stringPayloadBytesV1 stateName) (encodeU32le typeId)
    (taggedHeaderBytesV1 "Visibility.Public" 0)
  rw [hlayout]
  have hflatIn :
      left ++
          (taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le id ++ stringPayloadBytesV1 stateName ++
            encodeU32le typeId ++ taggedHeaderBytesV1 "Visibility.Public" 0) ++ right =
        left ++ taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le id ++ stringPayloadBytesV1 stateName ++
          encodeU32le typeId ++ taggedHeaderBytesV1 "Visibility.Public" 0 ++ right := by
    simp [ByteArray.append_assoc]
  rw [hflatIn]
  have houter : nesting < maxNesting := Nat.lt_of_succ_lt hdepth
  let input := left ++ taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le id ++
    stringPayloadBytesV1 stateName ++ encodeU32le typeId ++ taggedHeaderBytesV1 "Visibility.Public" 0 ++ right
  let body := taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le id ++
    stringPayloadBytesV1 stateName ++ encodeU32le typeId ++ taggedHeaderBytesV1 "Visibility.Public" 0
  have hexpect :
      expectTag "StateDecl" 4 ⟨input, left.size, nesting + 1⟩ =
        .ok ((), ⟨input, left.size + (taggedHeaderBytesV1 "StateDecl" 4).size, nesting + 1⟩) := by
    subst input
    have hin :
        left ++ taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le id ++ stringPayloadBytesV1 stateName ++
            encodeU32le typeId ++ taggedHeaderBytesV1 "Visibility.Public" 0 ++ right =
          left ++ taggedHeaderBytesV1 "StateDecl" 4 ++
            (encodeU32le id ++ stringPayloadBytesV1 stateName ++ encodeU32le typeId ++
              taggedHeaderBytesV1 "Visibility.Public" 0) ++ right := by
      simp [ByteArray.append_assoc]
    rw [hin]
    exact expectTag_encode_midV1 left right "StateDecl" 4
      (encodeU32le id ++ stringPayloadBytesV1 stateName ++ encodeU32le typeId ++
        taggedHeaderBytesV1 "Visibility.Public" 0) (nesting + 1)
      (by decide) (by decide) (by decide) isAsciiTagBytes_StateDecl (by decide)
  have hid :
      decodeU32le ⟨input, left.size + (taggedHeaderBytesV1 "StateDecl" 4).size, nesting + 1⟩ =
        .ok (id, ⟨input, left.size + (taggedHeaderBytesV1 "StateDecl" 4).size + 4, nesting + 1⟩) := by
    subst input
    have hin :
        left ++ taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le id ++ stringPayloadBytesV1 stateName ++
            encodeU32le typeId ++ taggedHeaderBytesV1 "Visibility.Public" 0 ++ right =
          (left ++ taggedHeaderBytesV1 "StateDecl" 4) ++ encodeU32le id ++
            (stringPayloadBytesV1 stateName ++ encodeU32le typeId ++ taggedHeaderBytesV1 "Visibility.Public" 0 ++ right) := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ taggedHeaderBytesV1 "StateDecl" 4).size =
        left.size + (taggedHeaderBytesV1 "StateDecl" 4).size := by simp [ByteArray.size_append]
    rw [hin, ← hsz]
    exact decodeU32le_encode_midV1 (left ++ taggedHeaderBytesV1 "StateDecl" 4)
      (stringPayloadBytesV1 stateName ++ encodeU32le typeId ++ taggedHeaderBytesV1 "Visibility.Public" 0 ++ right)
      id (nesting + 1)
  have hname :
      decodeString ⟨input, left.size + (taggedHeaderBytesV1 "StateDecl" 4).size + 4, nesting + 1⟩ =
        .ok (stateName,
          ⟨input, left.size + (taggedHeaderBytesV1 "StateDecl" 4).size + 4 +
            (stringPayloadBytesV1 stateName).size, nesting + 1⟩) := by
    subst input
    have hmid := decodeString_of_encodeString_okV1
      (left ++ taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le id)
      (encodeU32le typeId ++ taggedHeaderBytesV1 "Visibility.Public" 0 ++ right)
      stateName (stringPayloadBytesV1 stateName) (nesting + 1) hnameEnc
    have hin :
        (left ++ taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le id) ++
            stringPayloadBytesV1 stateName ++
            (encodeU32le typeId ++ taggedHeaderBytesV1 "Visibility.Public" 0 ++ right) =
          left ++ taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le id ++
            stringPayloadBytesV1 stateName ++ encodeU32le typeId ++
            taggedHeaderBytesV1 "Visibility.Public" 0 ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le id).size =
        left.size + (taggedHeaderBytesV1 "StateDecl" 4).size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    simpa [hin, hsz] using hmid
  have htype :
      decodeU32le ⟨input,
        left.size + (taggedHeaderBytesV1 "StateDecl" 4).size + 4 +
          (stringPayloadBytesV1 stateName).size, nesting + 1⟩ =
        .ok (typeId, ⟨input,
          left.size + (taggedHeaderBytesV1 "StateDecl" 4).size + 4 +
            (stringPayloadBytesV1 stateName).size + 4, nesting + 1⟩) := by
    subst input
    have hmid := decodeU32le_encode_midV1
      (left ++ taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le id ++
        stringPayloadBytesV1 stateName)
      (taggedHeaderBytesV1 "Visibility.Public" 0 ++ right) typeId (nesting + 1)
    have hin :
        (left ++ taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le id ++
            stringPayloadBytesV1 stateName) ++ encodeU32le typeId ++
            (taggedHeaderBytesV1 "Visibility.Public" 0 ++ right) =
          left ++ taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le id ++
            stringPayloadBytesV1 stateName ++ encodeU32le typeId ++
            taggedHeaderBytesV1 "Visibility.Public" 0 ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le id ++
        stringPayloadBytesV1 stateName).size =
        left.size + (taggedHeaderBytesV1 "StateDecl" 4).size + 4 +
          (stringPayloadBytesV1 stateName).size := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    simpa [hin, hsz] using hmid
  have hvis :
      decodeVisibilityV1 ⟨input,
        left.size + (taggedHeaderBytesV1 "StateDecl" 4).size + 4 +
          (stringPayloadBytesV1 stateName).size + 4, nesting + 1⟩ =
        .ok (.public_, ⟨input, left.size + body.size, nesting + 1⟩) := by
    subst input body
    have hmid := decodeVisibility_of_encode_midV1 .public_
      (taggedHeaderBytesV1 "Visibility.Public" 0)
      (left ++ taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le id ++
        stringPayloadBytesV1 stateName ++ encodeU32le typeId)
      right (nesting + 1) hdepth hvisEnc
    have hin :
        (left ++ taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le id ++
            stringPayloadBytesV1 stateName ++ encodeU32le typeId) ++
            taggedHeaderBytesV1 "Visibility.Public" 0 ++ right =
          left ++ taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le id ++
            stringPayloadBytesV1 stateName ++ encodeU32le typeId ++
            taggedHeaderBytesV1 "Visibility.Public" 0 ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le id ++
        stringPayloadBytesV1 stateName ++ encodeU32le typeId).size =
        left.size + (taggedHeaderBytesV1 "StateDecl" 4).size + 4 +
          (stringPayloadBytesV1 stateName).size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    have hfinal :
        left.size + (taggedHeaderBytesV1 "StateDecl" 4).size + 4 +
            (stringPayloadBytesV1 stateName).size + 4 +
            (taggedHeaderBytesV1 "Visibility.Public" 0).size =
          left.size +
            ((taggedHeaderBytesV1 "StateDecl" 4).size + (encodeU32le id).size +
              (stringPayloadBytesV1 stateName).size + (encodeU32le typeId).size +
              (taggedHeaderBytesV1 "Visibility.Public" 0).size) := by
      simp only [encodeU32le_sizeV1]
      omega
    simpa [hin, hsz, hfinal, ByteArray.size_append, encodeU32le_sizeV1] using hmid
  have hbody := decodeStateDeclBodyV1_eq_of_fields
    ⟨input, left.size, nesting + 1⟩
    ⟨input, left.size + (taggedHeaderBytesV1 "StateDecl" 4).size, nesting + 1⟩
    ⟨input, left.size + (taggedHeaderBytesV1 "StateDecl" 4).size + 4, nesting + 1⟩
    ⟨input, left.size + (taggedHeaderBytesV1 "StateDecl" 4).size + 4 +
      (stringPayloadBytesV1 stateName).size, nesting + 1⟩
    ⟨input, left.size + (taggedHeaderBytesV1 "StateDecl" 4).size + 4 +
      (stringPayloadBytesV1 stateName).size + 4, nesting + 1⟩
    ⟨input, left.size + body.size, nesting + 1⟩
    id typeId stateName .public_ hexpect hid hname htype hvis
  have hs := decodeStateDeclV1_eq_of_bodyV1
    ⟨input, left.size, nesting⟩
    ({ id, name := stateName, typeId, visibility := .public_ } : StateDeclV1)
    ⟨input, left.size + body.size, nesting + 1⟩ houter hbody
  subst input body
  simpa [ByteArray.size_append, encodeU32le_sizeV1] using hs

/-- Fixed-depth exact inversion for a public state declaration with arbitrary
    declaration and type ids. -/
theorem exactAt_stateDecl_publicV1
    (id typeId : UInt32) (stateName : String)
    (hval : validateIdentifierComponent stateName = .ok ())
    (nesting : Nat) (hdepth : nesting + 1 < maxNesting) :
    ExactMidOffsetInvertAtV1 encodeStateDeclV1 decodeStateDeclV1
      ({ id, name := stateName, typeId, visibility := .public_ } : StateDeclV1)
      nesting := by
  intro b left right henc
  exact
    decodeStateDecl_public_of_encode_midV1 id typeId stateName hval b left right
      nesting hdepth henc

/-- Exact singleton public state table inversion. -/
theorem decodeStateDecl_singleton_public_table_of_encode_midV1
    (stateName : String) (hval : validateIdentifierComponent stateName = .ok ())
    (stateB : ByteArray)
    (hstate : encodeStateDeclV1 { id := 0, name := stateName, typeId := 0, visibility := .public_ } = .ok stateB)
    (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting)
    (henc : encodeArray encodeStateDeclV1
      #[{ id := 0, name := stateName, typeId := 0, visibility := .public_ }] = .ok b) :
    decodeArray maxTableElements decodeStateDeclV1
        ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (#[{ id := 0, name := stateName, typeId := 0, visibility := .public_ }],
        ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hinv :
      decodeStateDeclV1 ⟨left ++ encodeU32le 1 ++ stateB ++ right,
          left.size + 4, nesting⟩ =
        .ok ({ id := 0, name := stateName, typeId := 0, visibility := .public_ },
          ⟨left ++ encodeU32le 1 ++ stateB ++ right,
            left.size + 4 + stateB.size, nesting⟩) := by
    have hmid := decodeStateDecl_public_of_encode_midV1 0 0 stateName hval stateB
      (left ++ encodeU32le 1) right nesting hdepth hstate
    have hin : (left ++ encodeU32le 1) ++ stateB ++ right =
        left ++ encodeU32le 1 ++ stateB ++ right := by simp [ByteArray.append_assoc]
    have hsz : (left ++ encodeU32le 1).size = left.size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    simpa [hin, hsz] using hmid
  exact decodeArray_of_encodeArray_one_ok_midV1 encodeStateDeclV1 decodeStateDeclV1
    maxTableElements { id := 0, name := stateName, typeId := 0, visibility := .public_ }
    b stateB left right nesting (by decide) hstate henc hinv

/-- Exact singleton invariant table inversion from the InvariantDecl codec. -/
theorem exactMidOffsetInvert_singleton_invariant_table
    (d : InvariantDeclV1) (bd : ByteArray)
    (hd : encodeInvariantDeclV1 d = .ok bd) :
    ExactMidOffsetInvertV1 (encodeArray encodeInvariantDeclV1)
      (decodeArray maxTableElements decodeInvariantDeclV1) #[d] :=
  exactMidOffsetInvert_array_one_of_encoded_exact encodeInvariantDeclV1 decodeInvariantDeclV1
    maxTableElements (by decide) d bd hd
    (ExactMidOffsetInvertV1.ofGlobal midOffsetInvert_encodeInvariantDecl_decodeInvariantDecl d)

end ProofForgeV2.Semantic.WireV1
