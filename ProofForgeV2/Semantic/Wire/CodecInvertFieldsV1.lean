import ProofForgeV2.Semantic.WireV1
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

end ProofForgeV2.Semantic.WireV1
