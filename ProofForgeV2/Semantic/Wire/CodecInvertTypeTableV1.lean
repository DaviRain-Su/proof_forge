import ProofForgeV2.Semantic.Wire.CodecInvertFieldReadV1

/-!
  ProofForgeV2.Semantic.Wire.CodecInvertTypeTableV1 — generic encode→decode
  invertibility for the `types` root field.

  Closes, for **arbitrary** values (not fixtures), the production codec
  inversion of

    FieldSpec, StructField, EnumVariant, TypeShape (all thirteen shapes),
    TypeDecl, and the `types` table array.

  Everything is proved from the sole production encoders/decoders through the
  `FieldReadV1` algebra of `Wire.CodecInvertFieldReadV1`; no second encoder, no
  structure-gate bypass, no fixture.

  No axiom / sorry / native_decide / ofReduceBool / run_tac / unsafe / meta / IO.
-/

namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common

/-! ### ASCII tag certificates -/

theorem asciiTagBytes_FieldSpecV1 : isAsciiTagBytesV1 "FieldSpec".toUTF8 = true := by
  rw [show "FieldSpec".toUTF8 =
    ByteArray.mk #[70, 105, 101, 108, 100, 83, 112, 101, 99] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_StructFieldV1 : isAsciiTagBytesV1 "StructField".toUTF8 = true := by
  rw [show "StructField".toUTF8 =
    ByteArray.mk #[83, 116, 114, 117, 99, 116, 70, 105, 101, 108, 100] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_EnumVariantV1 : isAsciiTagBytesV1 "EnumVariant".toUTF8 = true := by
  rw [show "EnumVariant".toUTF8 =
    ByteArray.mk #[69, 110, 117, 109, 86, 97, 114, 105, 97, 110, 116] from rfl]
  simp [isAsciiTagBytesV1]

/-! ### FieldSpec -/

theorem encodeFieldSpec_ok_eqV1 (spec : FieldSpecV1) (b : ByteArray)
    (h : encodeFieldSpecV1 spec = .ok b) :
    ∃ idB modB, encodeSchemaId spec.id = .ok idB ∧
      encodeByteArray spec.modulusBE = .ok modB ∧
      b = taggedHeaderBytesV1 "FieldSpec" 2 ++ idB ++ modB := by
  simp only [encodeFieldSpecV1] at h
  match hi : encodeSchemaId spec.id with
  | .error e => simp only [hi, Bind.bind, Except.bind] at h; cases h
  | .ok idB =>
      simp only [hi, Bind.bind, Except.bind] at h
      match hm : encodeByteArray spec.modulusBE with
      | .error e => simp only [hm, Bind.bind, Except.bind] at h; cases h
      | .ok modB =>
          simp only [hm, Bind.bind, Except.bind] at h
          have htag := encodeTagged_ok_eq_taggedBytesV1 "FieldSpec" #[idB, modB] b h
          exact ⟨idB, modB, rfl, rfl, by rw [htag.1, taggedBytes_two_fields_fields]⟩

theorem fieldRead_fieldSpecV1 (spec : FieldSpecV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) (henc : encodeFieldSpecV1 spec = .ok b) :
    FieldReadV1 decodeFieldSpecV1 b spec nesting := by
  obtain ⟨idB, modB, hid, hmod, hb⟩ := encodeFieldSpec_ok_eqV1 spec b henc
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ hdepth
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "FieldSpec" 2 ++ idB ++ modB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 :=
    (fieldRead_expectTagV1 "FieldSpec" 2 (nesting + 1) (by decide) (by decide)
      (by decide) asciiTagBytes_FieldSpecV1 (by decide)).read B pre.size pre
      (idB ++ modB ++ post) (by rw [hB]; simp [ByteArray.append_assoc]) rfl
  have h1 :=
    (fieldRead_schemaIdV1 spec.id idB (nesting + 1) hid).read B
      (pre.size + (taggedHeaderBytesV1 "FieldSpec" 2).size)
      (pre ++ taggedHeaderBytesV1 "FieldSpec" 2) (modB ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h2 :=
    (fieldRead_byteArrayV1 spec.modulusBE modB (nesting + 1) hmod).read B
      (pre.size + (taggedHeaderBytesV1 "FieldSpec" 2).size + idB.size)
      (pre ++ taggedHeaderBytesV1 "FieldSpec" 2 ++ idB) post
      (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp only [decodeFieldSpecV1, h0, h1, h2, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  have hsz : pre.size + (taggedHeaderBytesV1 "FieldSpec" 2).size + idB.size + modB.size =
      pre.size + (taggedHeaderBytesV1 "FieldSpec" 2 ++ idB ++ modB).size := by
    simp [ByteArray.size_append]; omega
  rw [hsz]

/-! ### StructField -/

theorem encodeStructField_ok_eqV1 (f : StructFieldV1) (b : ByteArray)
    (h : encodeStructFieldV1 f = .ok b) :
    ∃ nameB, encodeString f.name = .ok nameB ∧
      b = taggedHeaderBytesV1 "StructField" 2 ++ nameB ++ encodeU32le f.typeId := by
  simp only [encodeStructFieldV1] at h
  match hn : encodeString f.name with
  | .error e => simp only [hn, Bind.bind, Except.bind] at h; cases h
  | .ok nameB =>
      simp only [hn, Bind.bind, Except.bind] at h
      have htag := encodeTagged_ok_eq_taggedBytesV1 "StructField"
        #[nameB, encodeU32le f.typeId] b h
      exact ⟨nameB, rfl, by rw [htag.1, taggedBytes_two_fields_fields]⟩

theorem fieldRead_structFieldV1 (f : StructFieldV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) (henc : encodeStructFieldV1 f = .ok b) :
    FieldReadV1 decodeStructFieldV1 b f nesting := by
  obtain ⟨nameB, hname, hb⟩ := encodeStructField_ok_eqV1 f b henc
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ hdepth
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "StructField" 2 ++ nameB ++ encodeU32le f.typeId) ++
        post := ⟨_, rfl⟩
  rw [← hB]
  have h0 :=
    (fieldRead_expectTagV1 "StructField" 2 (nesting + 1) (by decide) (by decide)
      (by decide) asciiTagBytes_StructFieldV1 (by decide)).read B pre.size pre
      (nameB ++ encodeU32le f.typeId ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) rfl
  have h1 :=
    (fieldRead_stringV1 f.name nameB (nesting + 1) hname).read B
      (pre.size + (taggedHeaderBytesV1 "StructField" 2).size)
      (pre ++ taggedHeaderBytesV1 "StructField" 2) (encodeU32le f.typeId ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h2 :=
    (fieldRead_u32V1 f.typeId (nesting + 1)).read B
      (pre.size + (taggedHeaderBytesV1 "StructField" 2).size + nameB.size)
      (pre ++ taggedHeaderBytesV1 "StructField" 2 ++ nameB) post
      (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp only [decodeStructFieldV1, h0, h1, h2, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  have hsz : pre.size + (taggedHeaderBytesV1 "StructField" 2).size + nameB.size +
        (encodeU32le f.typeId).size =
      pre.size + (taggedHeaderBytesV1 "StructField" 2 ++ nameB ++
        encodeU32le f.typeId).size := by
    simp [ByteArray.size_append]; omega
  rw [hsz]

/-! ### EnumVariant -/

/-- The payload-type array codec of `EnumVariant` is a `u32` identity codec. -/
theorem fieldRead_u32ArrayV1 (ids : Array TypeIdV1) (b : ByteArray) (nesting : Nat)
    (henc : encodeArray (fun id => pure (encodeU32le id)) ids = .ok b) :
    FieldReadV1 (decodeArray maxArrayElements decodeU32le) b ids nesting := by
  obtain ⟨hsize, _⟩ := encodeArray_ok_inversionV1 _ ids b henc
  refine fieldRead_arrayV1 _ decodeU32le maxArrayElements ids b nesting hsize
    (Nat.le_refl _) (Nat.le_trans hsize (by decide)) ?_ ?_ henc
  · intro x _
    exact ⟨encodeU32le x, rfl⟩
  · intro x _
    refine exactMidOffsetInvertAt_of_fieldReadV1 ?_
    intro eb hx
    have : eb = encodeU32le x := (Except.ok.inj hx).symm
    subst this
    exact fieldRead_u32V1 x nesting

theorem encodeEnumVariant_ok_eqV1 (v : EnumVariantV1) (b : ByteArray)
    (h : encodeEnumVariantV1 v = .ok b) :
    ∃ nameB payloadB, encodeString v.name = .ok nameB ∧
      encodeArray (fun id => pure (encodeU32le id)) v.payloadTypes = .ok payloadB ∧
      b = taggedHeaderBytesV1 "EnumVariant" 2 ++ nameB ++ payloadB := by
  simp only [encodeEnumVariantV1] at h
  match hn : encodeString v.name with
  | .error e => simp only [hn, Bind.bind, Except.bind] at h; cases h
  | .ok nameB =>
      simp only [hn, Bind.bind, Except.bind] at h
      match hp : encodeArray (fun id => pure (encodeU32le id)) v.payloadTypes with
      | .error e => simp only [hp, Bind.bind, Except.bind] at h; cases h
      | .ok payloadB =>
          simp only [hp, Bind.bind, Except.bind] at h
          have htag := encodeTagged_ok_eq_taggedBytesV1 "EnumVariant"
            #[nameB, payloadB] b h
          exact ⟨nameB, payloadB, rfl, rfl,
            by rw [htag.1, taggedBytes_two_fields_fields]⟩

theorem fieldRead_enumVariantV1 (v : EnumVariantV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) (henc : encodeEnumVariantV1 v = .ok b) :
    FieldReadV1 decodeEnumVariantV1 b v nesting := by
  obtain ⟨nameB, payloadB, hname, hpayload, hb⟩ := encodeEnumVariant_ok_eqV1 v b henc
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ hdepth
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "EnumVariant" 2 ++ nameB ++ payloadB) ++ post :=
    ⟨_, rfl⟩
  rw [← hB]
  have h0 :=
    (fieldRead_expectTagV1 "EnumVariant" 2 (nesting + 1) (by decide) (by decide)
      (by decide) asciiTagBytes_EnumVariantV1 (by decide)).read B pre.size pre
      (nameB ++ payloadB ++ post) (by rw [hB]; simp [ByteArray.append_assoc]) rfl
  have h1 :=
    (fieldRead_stringV1 v.name nameB (nesting + 1) hname).read B
      (pre.size + (taggedHeaderBytesV1 "EnumVariant" 2).size)
      (pre ++ taggedHeaderBytesV1 "EnumVariant" 2) (payloadB ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h2 :=
    (fieldRead_u32ArrayV1 v.payloadTypes payloadB (nesting + 1) hpayload).read B
      (pre.size + (taggedHeaderBytesV1 "EnumVariant" 2).size + nameB.size)
      (pre ++ taggedHeaderBytesV1 "EnumVariant" 2 ++ nameB) post
      (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp only [decodeEnumVariantV1, h0, h1, h2, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  have hsz : pre.size + (taggedHeaderBytesV1 "EnumVariant" 2).size + nameB.size +
        payloadB.size =
      pre.size + (taggedHeaderBytesV1 "EnumVariant" 2 ++ nameB ++ payloadB).size := by
    simp [ByteArray.size_append]; omega
  rw [hsz]

/-! ### Element array lifts -/

theorem fieldRead_structFieldArrayV1 (fields : Array StructFieldV1) (b : ByteArray)
    (nesting : Nat) (hdepth : nesting < maxNesting)
    (henc : encodeArray encodeStructFieldV1 fields = .ok b) :
    FieldReadV1 (decodeArray maxArrayElements decodeStructFieldV1) b fields nesting := by
  obtain ⟨hsize, hall⟩ := encodeArray_ok_inversionV1 _ fields b henc
  refine fieldRead_arrayV1 _ _ maxArrayElements fields b nesting hsize (Nat.le_refl _)
    (Nat.le_trans hsize (by decide)) hall ?_ henc
  intro x _
  refine exactMidOffsetInvertAt_of_fieldReadV1 ?_
  intro eb hx
  exact fieldRead_structFieldV1 x eb nesting hdepth hx

theorem fieldRead_enumVariantArrayV1 (variants : Array EnumVariantV1) (b : ByteArray)
    (nesting : Nat) (hdepth : nesting < maxNesting)
    (henc : encodeArray encodeEnumVariantV1 variants = .ok b) :
    FieldReadV1 (decodeArray maxArrayElements decodeEnumVariantV1) b variants nesting := by
  obtain ⟨hsize, hall⟩ := encodeArray_ok_inversionV1 _ variants b henc
  refine fieldRead_arrayV1 _ _ maxArrayElements variants b nesting hsize (Nat.le_refl _)
    (Nat.le_trans hsize (by decide)) hall ?_ henc
  intro x _
  refine exactMidOffsetInvertAt_of_fieldReadV1 ?_
  intro eb hx
  exact fieldRead_enumVariantV1 x eb nesting hdepth hx

/-! ### Nullary tagged encodings -/

theorem encodeNullary_ok_eq_headerV1 (tag : String) (b : ByteArray)
    (hnonempty : tag.isEmpty = false) (hascii : isAsciiTagV1 tag = true)
    (hlimit : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (h : encodeNullary tag = .ok b) :
    b = taggedHeaderBytesV1 tag 0 := by
  have hok := encodeNullary_eq_okV1 tag hnonempty hascii hlimit
  have hb := Except.ok.inj (h.symm.trans hok)
  rw [hb]
  simp only [taggedHeaderBytesV1]
  rfl

/-! ### TypeShape ASCII tag certificates -/

theorem asciiTagBytes_TypeBoolV1 : isAsciiTagBytesV1 "Type.Bool".toUTF8 = true := by
  rw [show "Type.Bool".toUTF8 =
    ByteArray.mk #[84, 121, 112, 101, 46, 66, 111, 111, 108] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TypeUIntV1 : isAsciiTagBytesV1 "Type.UInt".toUTF8 = true := by
  rw [show "Type.UInt".toUTF8 =
    ByteArray.mk #[84, 121, 112, 101, 46, 85, 73, 110, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TypeIntV1 : isAsciiTagBytesV1 "Type.Int".toUTF8 = true := by
  rw [show "Type.Int".toUTF8 =
    ByteArray.mk #[84, 121, 112, 101, 46, 73, 110, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TypePrincipalV1 : isAsciiTagBytesV1 "Type.Principal".toUTF8 = true := by
  rw [show "Type.Principal".toUTF8 =
    ByteArray.mk #[84, 121, 112, 101, 46, 80, 114, 105, 110, 99, 105, 112, 97, 108] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TypeUnitV1 : isAsciiTagBytesV1 "Type.Unit".toUTF8 = true := by
  rw [show "Type.Unit".toUTF8 =
    ByteArray.mk #[84, 121, 112, 101, 46, 85, 110, 105, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TypeStringV1 : isAsciiTagBytesV1 "Type.String".toUTF8 = true := by
  rw [show "Type.String".toUTF8 =
    ByteArray.mk #[84, 121, 112, 101, 46, 83, 116, 114, 105, 110, 103] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TypeBytesV1 : isAsciiTagBytesV1 "Type.Bytes".toUTF8 = true := by
  rw [show "Type.Bytes".toUTF8 =
    ByteArray.mk #[84, 121, 112, 101, 46, 66, 121, 116, 101, 115] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TypeArrayV1 : isAsciiTagBytesV1 "Type.Array".toUTF8 = true := by
  rw [show "Type.Array".toUTF8 =
    ByteArray.mk #[84, 121, 112, 101, 46, 65, 114, 114, 97, 121] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TypeMapV1 : isAsciiTagBytesV1 "Type.Map".toUTF8 = true := by
  rw [show "Type.Map".toUTF8 =
    ByteArray.mk #[84, 121, 112, 101, 46, 77, 97, 112] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TypeOptionV1 : isAsciiTagBytesV1 "Type.Option".toUTF8 = true := by
  rw [show "Type.Option".toUTF8 =
    ByteArray.mk #[84, 121, 112, 101, 46, 79, 112, 116, 105, 111, 110] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TypeFieldV1 : isAsciiTagBytesV1 "Type.Field".toUTF8 = true := by
  rw [show "Type.Field".toUTF8 =
    ByteArray.mk #[84, 121, 112, 101, 46, 70, 105, 101, 108, 100] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TypeStructV1 : isAsciiTagBytesV1 "Type.Struct".toUTF8 = true := by
  rw [show "Type.Struct".toUTF8 =
    ByteArray.mk #[84, 121, 112, 101, 46, 83, 116, 114, 117, 99, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TypeEnumV1 : isAsciiTagBytesV1 "Type.Enum".toUTF8 = true := by
  rw [show "Type.Enum".toUTF8 =
    ByteArray.mk #[84, 121, 112, 101, 46, 69, 110, 117, 109] from rfl]
  simp [isAsciiTagBytesV1]

/-! ### TypeShape sum-body branches -/

theorem fieldRead_typeShapeBody_boolV1 (b : ByteArray) (nesting : Nat)
    (henc : encodeTypeShapeV1 TypeShapeV1.bool = .ok b) :
    FieldReadV1 decodeTypeShapeBodyV1 b TypeShapeV1.bool nesting := by
  have hb : b = taggedHeaderBytesV1 "Type.Bool" 0 :=
    encodeNullary_ok_eq_headerV1 "Type.Bool" b (by decide) (by decide) (by decide) henc
  subst hb
  intro pre post
  have h0 := decodeTag_header_readV1 (pre ++ taggedHeaderBytesV1 "Type.Bool" 0 ++ post)
    pre.size pre post "Type.Bool" 0 nesting rfl rfl (by decide) (by decide) (by decide)
    asciiTagBytes_TypeBoolV1 (by decide)
  have h1 := decodeFieldCount_header_readV1
    (pre ++ taggedHeaderBytesV1 "Type.Bool" 0 ++ post)
    (pre.size + 4 + "Type.Bool".toUTF8.size) pre post "Type.Bool" 0 nesting rfl rfl (by decide)
  simp only [decodeTypeShapeBodyV1, h0, h1, Bind.bind, Except.bind, Pure.pure,
    Except.pure]

theorem fieldRead_typeShapeBody_principalV1 (b : ByteArray) (nesting : Nat)
    (henc : encodeTypeShapeV1 TypeShapeV1.principal = .ok b) :
    FieldReadV1 decodeTypeShapeBodyV1 b TypeShapeV1.principal nesting := by
  have hb : b = taggedHeaderBytesV1 "Type.Principal" 0 :=
    encodeNullary_ok_eq_headerV1 "Type.Principal" b (by decide) (by decide) (by decide) henc
  subst hb
  intro pre post
  have h0 := decodeTag_header_readV1 (pre ++ taggedHeaderBytesV1 "Type.Principal" 0 ++ post)
    pre.size pre post "Type.Principal" 0 nesting rfl rfl (by decide) (by decide) (by decide)
    asciiTagBytes_TypePrincipalV1 (by decide)
  have h1 := decodeFieldCount_header_readV1
    (pre ++ taggedHeaderBytesV1 "Type.Principal" 0 ++ post)
    (pre.size + 4 + "Type.Principal".toUTF8.size) pre post "Type.Principal" 0 nesting rfl rfl (by decide)
  simp only [decodeTypeShapeBodyV1, h0, h1, Bind.bind, Except.bind, Pure.pure,
    Except.pure]

theorem fieldRead_typeShapeBody_unitV1 (b : ByteArray) (nesting : Nat)
    (henc : encodeTypeShapeV1 TypeShapeV1.unit = .ok b) :
    FieldReadV1 decodeTypeShapeBodyV1 b TypeShapeV1.unit nesting := by
  have hb : b = taggedHeaderBytesV1 "Type.Unit" 0 :=
    encodeNullary_ok_eq_headerV1 "Type.Unit" b (by decide) (by decide) (by decide) henc
  subst hb
  intro pre post
  have h0 := decodeTag_header_readV1 (pre ++ taggedHeaderBytesV1 "Type.Unit" 0 ++ post)
    pre.size pre post "Type.Unit" 0 nesting rfl rfl (by decide) (by decide) (by decide)
    asciiTagBytes_TypeUnitV1 (by decide)
  have h1 := decodeFieldCount_header_readV1
    (pre ++ taggedHeaderBytesV1 "Type.Unit" 0 ++ post)
    (pre.size + 4 + "Type.Unit".toUTF8.size) pre post "Type.Unit" 0 nesting rfl rfl (by decide)
  simp only [decodeTypeShapeBodyV1, h0, h1, Bind.bind, Except.bind, Pure.pure,
    Except.pure]

theorem fieldRead_typeShapeBody_stringV1 (b : ByteArray) (nesting : Nat)
    (henc : encodeTypeShapeV1 TypeShapeV1.string = .ok b) :
    FieldReadV1 decodeTypeShapeBodyV1 b TypeShapeV1.string nesting := by
  have hb : b = taggedHeaderBytesV1 "Type.String" 0 :=
    encodeNullary_ok_eq_headerV1 "Type.String" b (by decide) (by decide) (by decide) henc
  subst hb
  intro pre post
  have h0 := decodeTag_header_readV1 (pre ++ taggedHeaderBytesV1 "Type.String" 0 ++ post)
    pre.size pre post "Type.String" 0 nesting rfl rfl (by decide) (by decide) (by decide)
    asciiTagBytes_TypeStringV1 (by decide)
  have h1 := decodeFieldCount_header_readV1
    (pre ++ taggedHeaderBytesV1 "Type.String" 0 ++ post)
    (pre.size + 4 + "Type.String".toUTF8.size) pre post "Type.String" 0 nesting rfl rfl (by decide)
  simp only [decodeTypeShapeBodyV1, h0, h1, Bind.bind, Except.bind, Pure.pure,
    Except.pure]

theorem fieldRead_typeShapeBody_uintV1 (w : UInt16) (b : ByteArray) (nesting : Nat)
    (henc : encodeTypeShapeV1 (TypeShapeV1.uint w) = .ok b) :
    FieldReadV1 decodeTypeShapeBodyV1 b (TypeShapeV1.uint w) nesting := by
  have henc' : encodeTagged "Type.UInt" #[encodeU16le w] = .ok b := henc
  have hb := encodeTagged_ok_eq_one_fieldV1 _ _ b henc'
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B = pre ++ (taggedHeaderBytesV1 "Type.UInt" 1 ++ encodeU16le w) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre (encodeU16le w ++ post) "Type.UInt" 1
    nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide)
    (by decide) asciiTagBytes_TypeUIntV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Type.UInt".toUTF8.size) pre
    (encodeU16le w ++ post) "Type.UInt" 1 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u16V1 w nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Type.UInt" 1).size) (pre ++ taggedHeaderBytesV1 "Type.UInt" 1) (post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp only [decodeTypeShapeBodyV1, h0, h1, h2, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  have hsz : pre.size + (taggedHeaderBytesV1 "Type.UInt" 1).size + (encodeU16le w).size = pre.size + (taggedHeaderBytesV1 "Type.UInt" 1 ++ encodeU16le w).size := by
    simp only [ByteArray.size_append]; omega
  rw [hsz]

theorem fieldRead_typeShapeBody_intV1 (w : UInt16) (b : ByteArray) (nesting : Nat)
    (henc : encodeTypeShapeV1 (TypeShapeV1.int w) = .ok b) :
    FieldReadV1 decodeTypeShapeBodyV1 b (TypeShapeV1.int w) nesting := by
  have henc' : encodeTagged "Type.Int" #[encodeU16le w] = .ok b := henc
  have hb := encodeTagged_ok_eq_one_fieldV1 _ _ b henc'
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B = pre ++ (taggedHeaderBytesV1 "Type.Int" 1 ++ encodeU16le w) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre (encodeU16le w ++ post) "Type.Int" 1
    nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide)
    (by decide) asciiTagBytes_TypeIntV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Type.Int".toUTF8.size) pre
    (encodeU16le w ++ post) "Type.Int" 1 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u16V1 w nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Type.Int" 1).size) (pre ++ taggedHeaderBytesV1 "Type.Int" 1) (post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp only [decodeTypeShapeBodyV1, h0, h1, h2, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  have hsz : pre.size + (taggedHeaderBytesV1 "Type.Int" 1).size + (encodeU16le w).size = pre.size + (taggedHeaderBytesV1 "Type.Int" 1 ++ encodeU16le w).size := by
    simp only [ByteArray.size_append]; omega
  rw [hsz]

theorem fieldRead_typeShapeBody_bytesV1 (len : UInt32) (b : ByteArray) (nesting : Nat)
    (henc : encodeTypeShapeV1 (TypeShapeV1.bytes len) = .ok b) :
    FieldReadV1 decodeTypeShapeBodyV1 b (TypeShapeV1.bytes len) nesting := by
  have henc' : encodeTagged "Type.Bytes" #[encodeU32le len] = .ok b := henc
  have hb := encodeTagged_ok_eq_one_fieldV1 _ _ b henc'
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B = pre ++ (taggedHeaderBytesV1 "Type.Bytes" 1 ++ encodeU32le len) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre (encodeU32le len ++ post) "Type.Bytes" 1
    nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide)
    (by decide) asciiTagBytes_TypeBytesV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Type.Bytes".toUTF8.size) pre
    (encodeU32le len ++ post) "Type.Bytes" 1 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 len nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Type.Bytes" 1).size) (pre ++ taggedHeaderBytesV1 "Type.Bytes" 1) (post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp only [decodeTypeShapeBodyV1, h0, h1, h2, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  have hsz : pre.size + (taggedHeaderBytesV1 "Type.Bytes" 1).size + (encodeU32le len).size = pre.size + (taggedHeaderBytesV1 "Type.Bytes" 1 ++ encodeU32le len).size := by
    simp only [ByteArray.size_append]; omega
  rw [hsz]

theorem fieldRead_typeShapeBody_arrayV1 (element : TypeIdV1) (length : UInt32) (b : ByteArray) (nesting : Nat)
    (henc : encodeTypeShapeV1 (TypeShapeV1.array element length) = .ok b) :
    FieldReadV1 decodeTypeShapeBodyV1 b (TypeShapeV1.array element length) nesting := by
  have henc' : encodeTagged "Type.Array" #[encodeU32le element, encodeU32le length] = .ok b := henc
  have hb := encodeTagged_ok_eq_two_fieldsV1 _ _ _ b henc'
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B = pre ++ (taggedHeaderBytesV1 "Type.Array" 2 ++ encodeU32le element ++ encodeU32le length) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre (encodeU32le element ++ encodeU32le length ++ post) "Type.Array" 2
    nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide)
    (by decide) asciiTagBytes_TypeArrayV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Type.Array".toUTF8.size) pre
    (encodeU32le element ++ encodeU32le length ++ post) "Type.Array" 2 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 element nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Type.Array" 2).size) (pre ++ taggedHeaderBytesV1 "Type.Array" 2) (encodeU32le length ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_u32V1 length nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Type.Array" 2).size + (encodeU32le element).size) (pre ++ taggedHeaderBytesV1 "Type.Array" 2 ++ encodeU32le element) (post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp only [decodeTypeShapeBodyV1, h0, h1, h2, h3, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  have hsz : pre.size + (taggedHeaderBytesV1 "Type.Array" 2).size + (encodeU32le element).size + (encodeU32le length).size = pre.size + (taggedHeaderBytesV1 "Type.Array" 2 ++ encodeU32le element ++ encodeU32le length).size := by
    simp only [ByteArray.size_append]; omega
  rw [hsz]

theorem fieldRead_typeShapeBody_mapV1 (key value : TypeIdV1) (b : ByteArray) (nesting : Nat)
    (henc : encodeTypeShapeV1 (TypeShapeV1.map key value) = .ok b) :
    FieldReadV1 decodeTypeShapeBodyV1 b (TypeShapeV1.map key value) nesting := by
  have henc' : encodeTagged "Type.Map" #[encodeU32le key, encodeU32le value] = .ok b := henc
  have hb := encodeTagged_ok_eq_two_fieldsV1 _ _ _ b henc'
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B = pre ++ (taggedHeaderBytesV1 "Type.Map" 2 ++ encodeU32le key ++ encodeU32le value) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre (encodeU32le key ++ encodeU32le value ++ post) "Type.Map" 2
    nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide)
    (by decide) asciiTagBytes_TypeMapV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Type.Map".toUTF8.size) pre
    (encodeU32le key ++ encodeU32le value ++ post) "Type.Map" 2 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 key nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Type.Map" 2).size) (pre ++ taggedHeaderBytesV1 "Type.Map" 2) (encodeU32le value ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_u32V1 value nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Type.Map" 2).size + (encodeU32le key).size) (pre ++ taggedHeaderBytesV1 "Type.Map" 2 ++ encodeU32le key) (post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp only [decodeTypeShapeBodyV1, h0, h1, h2, h3, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  have hsz : pre.size + (taggedHeaderBytesV1 "Type.Map" 2).size + (encodeU32le key).size + (encodeU32le value).size = pre.size + (taggedHeaderBytesV1 "Type.Map" 2 ++ encodeU32le key ++ encodeU32le value).size := by
    simp only [ByteArray.size_append]; omega
  rw [hsz]

theorem fieldRead_typeShapeBody_optionV1 (element : TypeIdV1) (b : ByteArray) (nesting : Nat)
    (henc : encodeTypeShapeV1 (TypeShapeV1.option element) = .ok b) :
    FieldReadV1 decodeTypeShapeBodyV1 b (TypeShapeV1.option element) nesting := by
  have henc' : encodeTagged "Type.Option" #[encodeU32le element] = .ok b := henc
  have hb := encodeTagged_ok_eq_one_fieldV1 _ _ b henc'
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B = pre ++ (taggedHeaderBytesV1 "Type.Option" 1 ++ encodeU32le element) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre (encodeU32le element ++ post) "Type.Option" 1
    nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide)
    (by decide) asciiTagBytes_TypeOptionV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Type.Option".toUTF8.size) pre
    (encodeU32le element ++ post) "Type.Option" 1 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 element nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Type.Option" 1).size) (pre ++ taggedHeaderBytesV1 "Type.Option" 1) (post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp only [decodeTypeShapeBodyV1, h0, h1, h2, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  have hsz : pre.size + (taggedHeaderBytesV1 "Type.Option" 1).size + (encodeU32le element).size = pre.size + (taggedHeaderBytesV1 "Type.Option" 1 ++ encodeU32le element).size := by
    simp only [ByteArray.size_append]; omega
  rw [hsz]

theorem fieldRead_typeShapeBody_fieldV1 (spec : FieldSpecV1) (b : ByteArray) (nesting : Nat) (hdepth : nesting < maxNesting)
    (henc : encodeTypeShapeV1 (TypeShapeV1.field spec) = .ok b) :
    FieldReadV1 decodeTypeShapeBodyV1 b (TypeShapeV1.field spec) nesting := by
  have henc' : (encodeFieldSpecV1 spec >>= fun specB => encodeTagged "Type.Field" #[specB]) = .ok b := henc
  obtain ⟨specB, hsub, htagged⟩ := except_bind_ok_inversionV1 _ _ b henc'
  have hb := encodeTagged_ok_eq_one_fieldV1 _ _ b htagged
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B = pre ++ (taggedHeaderBytesV1 "Type.Field" 1 ++ specB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre (specB ++ post) "Type.Field" 1
    nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide)
    (by decide) asciiTagBytes_TypeFieldV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Type.Field".toUTF8.size) pre
    (specB ++ post) "Type.Field" 1 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_fieldSpecV1 spec specB nesting hdepth hsub).read B
    (pre.size + (taggedHeaderBytesV1 "Type.Field" 1).size) (pre ++ taggedHeaderBytesV1 "Type.Field" 1) (post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp only [decodeTypeShapeBodyV1, h0, h1, h2, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  have hsz : pre.size + (taggedHeaderBytesV1 "Type.Field" 1).size + (specB).size = pre.size + (taggedHeaderBytesV1 "Type.Field" 1 ++ specB).size := by
    simp only [ByteArray.size_append]; omega
  rw [hsz]

theorem fieldRead_typeShapeBody_structV1 (fields : Array StructFieldV1) (b : ByteArray) (nesting : Nat) (hdepth : nesting < maxNesting)
    (henc : encodeTypeShapeV1 (TypeShapeV1.struct fields) = .ok b) :
    FieldReadV1 decodeTypeShapeBodyV1 b (TypeShapeV1.struct fields) nesting := by
  have henc' : (encodeArray encodeStructFieldV1 fields >>= fun fieldsB => encodeTagged "Type.Struct" #[fieldsB]) = .ok b := henc
  obtain ⟨fieldsB, hsub, htagged⟩ := except_bind_ok_inversionV1 _ _ b henc'
  have hb := encodeTagged_ok_eq_one_fieldV1 _ _ b htagged
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B = pre ++ (taggedHeaderBytesV1 "Type.Struct" 1 ++ fieldsB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre (fieldsB ++ post) "Type.Struct" 1
    nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide)
    (by decide) asciiTagBytes_TypeStructV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Type.Struct".toUTF8.size) pre
    (fieldsB ++ post) "Type.Struct" 1 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_structFieldArrayV1 fields fieldsB nesting hdepth hsub).read B
    (pre.size + (taggedHeaderBytesV1 "Type.Struct" 1).size) (pre ++ taggedHeaderBytesV1 "Type.Struct" 1) (post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp only [decodeTypeShapeBodyV1, h0, h1, h2, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  have hsz : pre.size + (taggedHeaderBytesV1 "Type.Struct" 1).size + (fieldsB).size = pre.size + (taggedHeaderBytesV1 "Type.Struct" 1 ++ fieldsB).size := by
    simp only [ByteArray.size_append]; omega
  rw [hsz]

theorem fieldRead_typeShapeBody_enumV1 (variants : Array EnumVariantV1) (b : ByteArray) (nesting : Nat) (hdepth : nesting < maxNesting)
    (henc : encodeTypeShapeV1 (TypeShapeV1.enum variants) = .ok b) :
    FieldReadV1 decodeTypeShapeBodyV1 b (TypeShapeV1.enum variants) nesting := by
  have henc' : (encodeArray encodeEnumVariantV1 variants >>= fun variantsB => encodeTagged "Type.Enum" #[variantsB]) = .ok b := henc
  obtain ⟨variantsB, hsub, htagged⟩ := except_bind_ok_inversionV1 _ _ b henc'
  have hb := encodeTagged_ok_eq_one_fieldV1 _ _ b htagged
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B = pre ++ (taggedHeaderBytesV1 "Type.Enum" 1 ++ variantsB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre (variantsB ++ post) "Type.Enum" 1
    nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide)
    (by decide) asciiTagBytes_TypeEnumV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Type.Enum".toUTF8.size) pre
    (variantsB ++ post) "Type.Enum" 1 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_enumVariantArrayV1 variants variantsB nesting hdepth hsub).read B
    (pre.size + (taggedHeaderBytesV1 "Type.Enum" 1).size) (pre ++ taggedHeaderBytesV1 "Type.Enum" 1) (post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp only [decodeTypeShapeBodyV1, h0, h1, h2, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  have hsz : pre.size + (taggedHeaderBytesV1 "Type.Enum" 1).size + (variantsB).size = pre.size + (taggedHeaderBytesV1 "Type.Enum" 1 ++ variantsB).size := by
    simp only [ByteArray.size_append]; omega
  rw [hsz]

/-- Generic encode→decode invertibility of the production `TypeShape` codec. -/
theorem fieldRead_typeShapeV1 (shape : TypeShapeV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting) (henc : encodeTypeShapeV1 shape = .ok b) :
    FieldReadV1 decodeTypeShapeV1 b shape nesting := by
  apply fieldRead_withTaggedNestingV1 _ _ _ _ (Nat.lt_of_succ_lt hdepth)
  cases shape with
  | bool => exact fieldRead_typeShapeBody_boolV1 b (nesting + 1) henc
  | uint w => exact fieldRead_typeShapeBody_uintV1 w b (nesting + 1) henc
  | int w => exact fieldRead_typeShapeBody_intV1 w b (nesting + 1) henc
  | principal => exact fieldRead_typeShapeBody_principalV1 b (nesting + 1) henc
  | unit => exact fieldRead_typeShapeBody_unitV1 b (nesting + 1) henc
  | string => exact fieldRead_typeShapeBody_stringV1 b (nesting + 1) henc
  | bytes len => exact fieldRead_typeShapeBody_bytesV1 len b (nesting + 1) henc
  | array element length =>
      exact fieldRead_typeShapeBody_arrayV1 element length b (nesting + 1) henc
  | map key value =>
      exact fieldRead_typeShapeBody_mapV1 key value b (nesting + 1) henc
  | option element =>
      exact fieldRead_typeShapeBody_optionV1 element b (nesting + 1) henc
  | field spec =>
      exact fieldRead_typeShapeBody_fieldV1 spec b (nesting + 1) hdepth henc
  | struct fields =>
      exact fieldRead_typeShapeBody_structV1 fields b (nesting + 1) hdepth henc
  | enum variants =>
      exact fieldRead_typeShapeBody_enumV1 variants b (nesting + 1) hdepth henc

/-! ### TypeDecl -/

theorem asciiTagBytes_TypeDeclV1 : isAsciiTagBytesV1 "TypeDecl".toUTF8 = true := by
  rw [show "TypeDecl".toUTF8 =
    ByteArray.mk #[84, 121, 112, 101, 68, 101, 99, 108] from rfl]
  simp [isAsciiTagBytesV1]

theorem encodeTypeDecl_ok_eqV1 (d : TypeDeclV1) (b : ByteArray)
    (h : encodeTypeDeclV1 d = .ok b) :
    ∃ nameB shapeB, encodeOption encodeString d.name = .ok nameB ∧
      encodeTypeShapeV1 d.shape = .ok shapeB ∧
      b = taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le d.id ++ nameB ++ shapeB := by
  have h' : (encodeOption encodeString d.name >>= fun nameB =>
      encodeTypeShapeV1 d.shape >>= fun shapeB =>
        encodeTagged "TypeDecl" #[encodeU32le d.id, nameB, shapeB]) = .ok b := h
  obtain ⟨nameB, hname, h2⟩ := except_bind_ok_inversionV1 _ _ b h'
  obtain ⟨shapeB, hshape, h3⟩ := except_bind_ok_inversionV1 _ _ b h2
  exact ⟨nameB, shapeB, hname, hshape, encodeTagged_ok_eq_three_fieldsV1 _ _ _ _ b h3⟩

theorem fieldRead_typeDeclBodyV1 (d : TypeDeclV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting) (henc : encodeTypeDeclV1 d = .ok b) :
    FieldReadV1 decodeTypeDeclBodyV1 b d nesting := by
  obtain ⟨nameB, shapeB, hname, hshape, hb⟩ := encodeTypeDecl_ok_eqV1 d b henc
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le d.id ++ nameB ++ shapeB)
        ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 :=
    (fieldRead_expectTagV1 "TypeDecl" 3 nesting (by decide) (by decide) (by decide)
      asciiTagBytes_TypeDeclV1 (by decide)).read B pre.size pre
      (encodeU32le d.id ++ nameB ++ shapeB ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) rfl
  have h1 :=
    (fieldRead_u32V1 d.id nesting).read B
      (pre.size + (taggedHeaderBytesV1 "TypeDecl" 3).size)
      (pre ++ taggedHeaderBytesV1 "TypeDecl" 3) (nameB ++ shapeB ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h2 :=
    (fieldRead_optionV1 encodeString decodeString d.name nameB nesting hname
      (fun x payload _ hx => fieldRead_stringV1 x payload nesting hx)).read B
      (pre.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + (encodeU32le d.id).size)
      (pre ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le d.id) (shapeB ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 :=
    (fieldRead_typeShapeV1 d.shape shapeB nesting hdepth hshape).read B
      (pre.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + (encodeU32le d.id).size +
        nameB.size)
      (pre ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le d.id ++ nameB) post
      (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp only [decodeTypeDeclBodyV1, h0, h1, h2, h3, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  have hsz : pre.size + (taggedHeaderBytesV1 "TypeDecl" 3).size +
        (encodeU32le d.id).size + nameB.size + shapeB.size =
      pre.size + (taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le d.id ++ nameB ++
        shapeB).size := by
    simp only [ByteArray.size_append]; omega
  rw [hsz]

/-- Generic encode→decode invertibility of the production `TypeDecl` codec. -/
theorem fieldRead_typeDeclV1 (d : TypeDeclV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting + 2 < maxNesting) (henc : encodeTypeDeclV1 d = .ok b) :
    FieldReadV1 decodeTypeDeclV1 b d nesting := by
  apply fieldRead_withTaggedNestingV1 _ _ _ _ (by omega)
  exact fieldRead_typeDeclBodyV1 d b (nesting + 1) (by omega) henc

/-! ### The `types` root table -/

theorem fieldRead_typeTableV1 (types : Array TypeDeclV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting + 2 < maxNesting) (hsize : types.size ≤ maxTableElements)
    (henc : encodeArray encodeTypeDeclV1 types = .ok b) :
    FieldReadV1 (decodeArray maxTableElements decodeTypeDeclV1) b types nesting := by
  obtain ⟨_, hall⟩ := encodeArray_ok_inversionV1 _ types b henc
  refine fieldRead_arrayV1 _ _ maxTableElements types b nesting hsize (by decide)
    (Nat.le_trans hsize (by decide)) hall ?_ henc
  intro x _
  exact exactMidOffsetInvertAt_of_fieldReadV1
    (fun eb hx => fieldRead_typeDeclV1 x eb nesting hdepth hx)

/-- The `types` field of `RootFieldInvertV1`, for an **arbitrary** type table
    within the production table-size gate. -/
theorem exactMidOffsetInvertAt_typeTableV1 (types : Array TypeDeclV1)
    (hsize : types.size ≤ maxTableElements) :
    ExactMidOffsetInvertAtV1 (encodeArray encodeTypeDeclV1)
      (decodeArray maxTableElements decodeTypeDeclV1) types 1 :=
  exactMidOffsetInvertAt_of_fieldReadV1
    (fun b hb => fieldRead_typeTableV1 types b 1 (by decide) hsize hb)

end ProofForgeV2.Semantic.WireV1
