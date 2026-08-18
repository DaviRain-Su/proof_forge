import ProofForgeV2.Semantic.Wire.CodecInvertFieldReadV1

/-!
  ProofForgeV2.Semantic.Wire.CodecInvertDeclTablesV1 — generic encode→decode
  invertibility for the `constants`, `logicalState`, `events` and `errors`
  root fields.

  Closes, for **arbitrary** values (not fixtures), the production codec
  inversion of `Constant`, `StateDecl`, `InterfaceField`, `EventDecl`,
  `ErrorDecl` and of the four corresponding root tables, through the
  `FieldReadV1` algebra of `Wire.CodecInvertFieldReadV1`.

  No axiom / sorry / native_decide / ofReduceBool / run_tac / unsafe / meta / IO.
-/

namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common

/-! ### ASCII tag certificates -/

theorem asciiTagBytes_ConstantV1 : isAsciiTagBytesV1 "Constant".toUTF8 = true := by
  rw [show "Constant".toUTF8 =
    ByteArray.mk #[67, 111, 110, 115, 116, 97, 110, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_StateDeclV1 : isAsciiTagBytesV1 "StateDecl".toUTF8 = true := by
  rw [show "StateDecl".toUTF8 =
    ByteArray.mk #[83, 116, 97, 116, 101, 68, 101, 99, 108] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_InterfaceFieldV1 : isAsciiTagBytesV1 "InterfaceField".toUTF8 = true := by
  rw [show "InterfaceField".toUTF8 =
    ByteArray.mk #[73, 110, 116, 101, 114, 102, 97, 99, 101, 70, 105, 101, 108, 100] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_EventDeclV1 : isAsciiTagBytesV1 "EventDecl".toUTF8 = true := by
  rw [show "EventDecl".toUTF8 =
    ByteArray.mk #[69, 118, 101, 110, 116, 68, 101, 99, 108] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_ErrorDeclV1 : isAsciiTagBytesV1 "ErrorDecl".toUTF8 = true := by
  rw [show "ErrorDecl".toUTF8 =
    ByteArray.mk #[69, 114, 114, 111, 114, 68, 101, 99, 108] from rfl]
  simp [isAsciiTagBytesV1]

/-! ### Constant -/

theorem encodeConstant_ok_eqV1 (d : ConstantV1) (b : ByteArray)
    (h : encodeConstantV1 d = .ok b) :
    ∃ nameB valueB, encodeString d.name = .ok nameB ∧
      encodeByteArray d.valueBytes = .ok valueB ∧
      b = taggedHeaderBytesV1 "Constant" 4 ++ encodeU32le d.id ++ nameB ++ encodeU32le d.typeId ++ valueB := by
  have h0 : (encodeString d.name >>= fun nameB => (encodeByteArray d.valueBytes >>= fun valueB => encodeTagged "Constant" #[encodeU32le d.id, nameB, encodeU32le d.typeId, valueB])) = .ok b := h
  obtain ⟨nameB, hnameB, r0⟩ := except_bind_ok_inversionV1 _ _ b h0
  obtain ⟨valueB, hvalueB, r1⟩ := except_bind_ok_inversionV1 _ _ b r0
  exact ⟨nameB, valueB, hnameB, hvalueB,
    encodeTagged_ok_eq_four_fieldsV1 _ _ _ _ _ b r1⟩

theorem fieldRead_constantV1 (d : ConstantV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) (henc : encodeConstantV1 d = .ok b) :
    FieldReadV1 decodeConstantV1 b d nesting := by
  obtain ⟨nameB, valueB, hnameB, hvalueB, hb⟩ :=
    encodeConstant_ok_eqV1 d b henc
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ (hdepth)
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B = pre ++ (taggedHeaderBytesV1 "Constant" 4 ++ encodeU32le d.id ++ nameB ++ encodeU32le d.typeId ++ valueB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 :=
    (fieldRead_expectTagV1 "Constant" 4 (nesting + 1) (by decide) (by decide) (by decide)
      asciiTagBytes_ConstantV1 (by decide)).read B pre.size pre (encodeU32le d.id ++ nameB ++ encodeU32le d.typeId ++ valueB ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) rfl
  have h1 := (fieldRead_u32V1 d.id (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "Constant" 4).size) (pre ++ taggedHeaderBytesV1 "Constant" 4) (nameB ++ encodeU32le d.typeId ++ valueB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h2 := (fieldRead_stringV1 d.name nameB (nesting + 1) hnameB).read B
    (pre.size + (taggedHeaderBytesV1 "Constant" 4).size + (encodeU32le d.id).size) (pre ++ taggedHeaderBytesV1 "Constant" 4 ++ encodeU32le d.id) (encodeU32le d.typeId ++ valueB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_u32V1 d.typeId (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "Constant" 4).size + (encodeU32le d.id).size + (nameB).size) (pre ++ taggedHeaderBytesV1 "Constant" 4 ++ encodeU32le d.id ++ nameB) (valueB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h4 := (fieldRead_byteArrayV1 d.valueBytes valueB (nesting + 1) hvalueB).read B
    (pre.size + (taggedHeaderBytesV1 "Constant" 4).size + (encodeU32le d.id).size + (nameB).size + (encodeU32le d.typeId).size) (pre ++ taggedHeaderBytesV1 "Constant" 4 ++ encodeU32le d.id ++ nameB ++ encodeU32le d.typeId) (post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp only [decodeConstantV1, h0, h1, h2, h3, h4, Bind.bind, Except.bind, Pure.pure, Except.pure]
  have hsz : pre.size + (taggedHeaderBytesV1 "Constant" 4).size + (encodeU32le d.id).size + (nameB).size + (encodeU32le d.typeId).size + (valueB).size = pre.size + (taggedHeaderBytesV1 "Constant" 4 ++ encodeU32le d.id ++ nameB ++ encodeU32le d.typeId ++ valueB).size := by
    simp only [ByteArray.size_append]; omega
  rw [hsz]


/-! ### StateDecl -/

theorem encodeStateDecl_ok_eqV1 (d : StateDeclV1) (b : ByteArray)
    (h : encodeStateDeclV1 d = .ok b) :
    ∃ nameB visB, encodeString d.name = .ok nameB ∧
      encodeVisibilityV1 d.visibility = .ok visB ∧
      b = taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le d.id ++ nameB ++ encodeU32le d.typeId ++ visB := by
  have h0 : (encodeString d.name >>= fun nameB => (encodeVisibilityV1 d.visibility >>= fun visB => encodeTagged "StateDecl" #[encodeU32le d.id, nameB, encodeU32le d.typeId, visB])) = .ok b := h
  obtain ⟨nameB, hnameB, r0⟩ := except_bind_ok_inversionV1 _ _ b h0
  obtain ⟨visB, hvisB, r1⟩ := except_bind_ok_inversionV1 _ _ b r0
  exact ⟨nameB, visB, hnameB, hvisB,
    encodeTagged_ok_eq_four_fieldsV1 _ _ _ _ _ b r1⟩

theorem fieldRead_stateDeclV1 (d : StateDeclV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting) (henc : encodeStateDeclV1 d = .ok b) :
    FieldReadV1 decodeStateDeclV1 b d nesting := by
  obtain ⟨nameB, visB, hnameB, hvisB, hb⟩ :=
    encodeStateDecl_ok_eqV1 d b henc
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ (by omega)
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B = pre ++ (taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le d.id ++ nameB ++ encodeU32le d.typeId ++ visB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 :=
    (fieldRead_expectTagV1 "StateDecl" 4 (nesting + 1) (by decide) (by decide) (by decide)
      asciiTagBytes_StateDeclV1 (by decide)).read B pre.size pre (encodeU32le d.id ++ nameB ++ encodeU32le d.typeId ++ visB ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) rfl
  have h1 := (fieldRead_u32V1 d.id (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "StateDecl" 4).size) (pre ++ taggedHeaderBytesV1 "StateDecl" 4) (nameB ++ encodeU32le d.typeId ++ visB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h2 := (fieldRead_stringV1 d.name nameB (nesting + 1) hnameB).read B
    (pre.size + (taggedHeaderBytesV1 "StateDecl" 4).size + (encodeU32le d.id).size) (pre ++ taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le d.id) (encodeU32le d.typeId ++ visB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_u32V1 d.typeId (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "StateDecl" 4).size + (encodeU32le d.id).size + (nameB).size) (pre ++ taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le d.id ++ nameB) (visB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h4 := (FieldReadV1.ofGlobal midOffsetInvert_encodeVisibility_decodeVisibility (by omega) hvisB).read B
    (pre.size + (taggedHeaderBytesV1 "StateDecl" 4).size + (encodeU32le d.id).size + (nameB).size + (encodeU32le d.typeId).size) (pre ++ taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le d.id ++ nameB ++ encodeU32le d.typeId) (post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp only [decodeStateDeclBodyV1, h0, h1, h2, h3, h4, Bind.bind, Except.bind, Pure.pure, Except.pure]
  have hsz : pre.size + (taggedHeaderBytesV1 "StateDecl" 4).size + (encodeU32le d.id).size + (nameB).size + (encodeU32le d.typeId).size + (visB).size = pre.size + (taggedHeaderBytesV1 "StateDecl" 4 ++ encodeU32le d.id ++ nameB ++ encodeU32le d.typeId ++ visB).size := by
    simp only [ByteArray.size_append]; omega
  rw [hsz]


/-! ### InterfaceField -/

theorem encodeInterfaceField_ok_eqV1 (f : InterfaceFieldV1) (b : ByteArray)
    (h : encodeInterfaceFieldV1 f = .ok b) :
    ∃ nameB visB, encodeString f.name = .ok nameB ∧
      encodeVisibilityV1 f.visibility = .ok visB ∧
      b = taggedHeaderBytesV1 "InterfaceField" 3 ++ nameB ++ encodeU32le f.typeId ++ visB := by
  have h0 : (encodeString f.name >>= fun nameB => (encodeVisibilityV1 f.visibility >>= fun visB => encodeTagged "InterfaceField" #[nameB, encodeU32le f.typeId, visB])) = .ok b := h
  obtain ⟨nameB, hnameB, r0⟩ := except_bind_ok_inversionV1 _ _ b h0
  obtain ⟨visB, hvisB, r1⟩ := except_bind_ok_inversionV1 _ _ b r0
  exact ⟨nameB, visB, hnameB, hvisB,
    encodeTagged_ok_eq_three_fieldsV1 _ _ _ _ b r1⟩

theorem fieldRead_interfaceFieldV1 (f : InterfaceFieldV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting) (henc : encodeInterfaceFieldV1 f = .ok b) :
    FieldReadV1 decodeInterfaceFieldV1 b f nesting := by
  obtain ⟨nameB, visB, hnameB, hvisB, hb⟩ :=
    encodeInterfaceField_ok_eqV1 f b henc
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ (by omega)
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B = pre ++ (taggedHeaderBytesV1 "InterfaceField" 3 ++ nameB ++ encodeU32le f.typeId ++ visB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 :=
    (fieldRead_expectTagV1 "InterfaceField" 3 (nesting + 1) (by decide) (by decide) (by decide)
      asciiTagBytes_InterfaceFieldV1 (by decide)).read B pre.size pre (nameB ++ encodeU32le f.typeId ++ visB ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) rfl
  have h1 := (fieldRead_stringV1 f.name nameB (nesting + 1) hnameB).read B
    (pre.size + (taggedHeaderBytesV1 "InterfaceField" 3).size) (pre ++ taggedHeaderBytesV1 "InterfaceField" 3) (encodeU32le f.typeId ++ visB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h2 := (fieldRead_u32V1 f.typeId (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "InterfaceField" 3).size + (nameB).size) (pre ++ taggedHeaderBytesV1 "InterfaceField" 3 ++ nameB) (visB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (FieldReadV1.ofGlobal midOffsetInvert_encodeVisibility_decodeVisibility (by omega) hvisB).read B
    (pre.size + (taggedHeaderBytesV1 "InterfaceField" 3).size + (nameB).size + (encodeU32le f.typeId).size) (pre ++ taggedHeaderBytesV1 "InterfaceField" 3 ++ nameB ++ encodeU32le f.typeId) (post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp only [decodeInterfaceFieldV1, h0, h1, h2, h3, Bind.bind, Except.bind, Pure.pure, Except.pure]
  have hsz : pre.size + (taggedHeaderBytesV1 "InterfaceField" 3).size + (nameB).size + (encodeU32le f.typeId).size + (visB).size = pre.size + (taggedHeaderBytesV1 "InterfaceField" 3 ++ nameB ++ encodeU32le f.typeId ++ visB).size := by
    simp only [ByteArray.size_append]; omega
  rw [hsz]


/-! ### InterfaceField arrays -/

theorem fieldRead_interfaceFieldArrayV1 (fields : Array InterfaceFieldV1) (b : ByteArray)
    (nesting : Nat) (hdepth : nesting + 1 < maxNesting)
    (henc : encodeArray encodeInterfaceFieldV1 fields = .ok b) :
    FieldReadV1 (decodeArray maxArrayElements decodeInterfaceFieldV1) b fields nesting := by
  obtain ⟨hsize, hall⟩ := encodeArray_ok_inversionV1 _ fields b henc
  refine fieldRead_arrayV1 _ _ maxArrayElements fields b nesting hsize (Nat.le_refl _)
    (Nat.le_trans hsize (by decide)) hall ?_ henc
  intro x _
  exact exactMidOffsetInvertAt_of_fieldReadV1
    (fun eb hx => fieldRead_interfaceFieldV1 x eb nesting hdepth hx)


/-! ### EventDecl -/

theorem encodeEventDecl_ok_eqV1 (d : EventDeclV1) (b : ByteArray)
    (h : encodeEventDeclV1 d = .ok b) :
    ∃ nameB fieldsB, encodeString d.name = .ok nameB ∧
      encodeArray encodeInterfaceFieldV1 d.fields = .ok fieldsB ∧
      b = taggedHeaderBytesV1 "EventDecl" 3 ++ encodeU32le d.id ++ nameB ++ fieldsB := by
  have h0 : (encodeString d.name >>= fun nameB => (encodeArray encodeInterfaceFieldV1 d.fields >>= fun fieldsB => encodeTagged "EventDecl" #[encodeU32le d.id, nameB, fieldsB])) = .ok b := h
  obtain ⟨nameB, hnameB, r0⟩ := except_bind_ok_inversionV1 _ _ b h0
  obtain ⟨fieldsB, hfieldsB, r1⟩ := except_bind_ok_inversionV1 _ _ b r0
  exact ⟨nameB, fieldsB, hnameB, hfieldsB,
    encodeTagged_ok_eq_three_fieldsV1 _ _ _ _ b r1⟩

theorem fieldRead_eventDeclV1 (d : EventDeclV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting + 2 < maxNesting) (henc : encodeEventDeclV1 d = .ok b) :
    FieldReadV1 decodeEventDeclV1 b d nesting := by
  obtain ⟨nameB, fieldsB, hnameB, hfieldsB, hb⟩ :=
    encodeEventDecl_ok_eqV1 d b henc
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ (by omega)
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B = pre ++ (taggedHeaderBytesV1 "EventDecl" 3 ++ encodeU32le d.id ++ nameB ++ fieldsB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 :=
    (fieldRead_expectTagV1 "EventDecl" 3 (nesting + 1) (by decide) (by decide) (by decide)
      asciiTagBytes_EventDeclV1 (by decide)).read B pre.size pre (encodeU32le d.id ++ nameB ++ fieldsB ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) rfl
  have h1 := (fieldRead_u32V1 d.id (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "EventDecl" 3).size) (pre ++ taggedHeaderBytesV1 "EventDecl" 3) (nameB ++ fieldsB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h2 := (fieldRead_stringV1 d.name nameB (nesting + 1) hnameB).read B
    (pre.size + (taggedHeaderBytesV1 "EventDecl" 3).size + (encodeU32le d.id).size) (pre ++ taggedHeaderBytesV1 "EventDecl" 3 ++ encodeU32le d.id) (fieldsB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_interfaceFieldArrayV1 d.fields fieldsB (nesting + 1) (by omega) hfieldsB).read B
    (pre.size + (taggedHeaderBytesV1 "EventDecl" 3).size + (encodeU32le d.id).size + (nameB).size) (pre ++ taggedHeaderBytesV1 "EventDecl" 3 ++ encodeU32le d.id ++ nameB) (post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp only [decodeEventDeclV1, h0, h1, h2, h3, Bind.bind, Except.bind, Pure.pure, Except.pure]
  have hsz : pre.size + (taggedHeaderBytesV1 "EventDecl" 3).size + (encodeU32le d.id).size + (nameB).size + (fieldsB).size = pre.size + (taggedHeaderBytesV1 "EventDecl" 3 ++ encodeU32le d.id ++ nameB ++ fieldsB).size := by
    simp only [ByteArray.size_append]; omega
  rw [hsz]


/-! ### ErrorDecl -/

theorem encodeErrorDecl_ok_eqV1 (d : ErrorDeclV1) (b : ByteArray)
    (h : encodeErrorDeclV1 d = .ok b) :
    ∃ nameB fieldsB, encodeString d.name = .ok nameB ∧
      encodeArray encodeInterfaceFieldV1 d.fields = .ok fieldsB ∧
      b = taggedHeaderBytesV1 "ErrorDecl" 3 ++ encodeU32le d.id ++ nameB ++ fieldsB := by
  have h0 : (encodeString d.name >>= fun nameB => (encodeArray encodeInterfaceFieldV1 d.fields >>= fun fieldsB => encodeTagged "ErrorDecl" #[encodeU32le d.id, nameB, fieldsB])) = .ok b := h
  obtain ⟨nameB, hnameB, r0⟩ := except_bind_ok_inversionV1 _ _ b h0
  obtain ⟨fieldsB, hfieldsB, r1⟩ := except_bind_ok_inversionV1 _ _ b r0
  exact ⟨nameB, fieldsB, hnameB, hfieldsB,
    encodeTagged_ok_eq_three_fieldsV1 _ _ _ _ b r1⟩

theorem fieldRead_errorDeclV1 (d : ErrorDeclV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting + 2 < maxNesting) (henc : encodeErrorDeclV1 d = .ok b) :
    FieldReadV1 decodeErrorDeclV1 b d nesting := by
  obtain ⟨nameB, fieldsB, hnameB, hfieldsB, hb⟩ :=
    encodeErrorDecl_ok_eqV1 d b henc
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ (by omega)
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B = pre ++ (taggedHeaderBytesV1 "ErrorDecl" 3 ++ encodeU32le d.id ++ nameB ++ fieldsB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 :=
    (fieldRead_expectTagV1 "ErrorDecl" 3 (nesting + 1) (by decide) (by decide) (by decide)
      asciiTagBytes_ErrorDeclV1 (by decide)).read B pre.size pre (encodeU32le d.id ++ nameB ++ fieldsB ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) rfl
  have h1 := (fieldRead_u32V1 d.id (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "ErrorDecl" 3).size) (pre ++ taggedHeaderBytesV1 "ErrorDecl" 3) (nameB ++ fieldsB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h2 := (fieldRead_stringV1 d.name nameB (nesting + 1) hnameB).read B
    (pre.size + (taggedHeaderBytesV1 "ErrorDecl" 3).size + (encodeU32le d.id).size) (pre ++ taggedHeaderBytesV1 "ErrorDecl" 3 ++ encodeU32le d.id) (fieldsB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_interfaceFieldArrayV1 d.fields fieldsB (nesting + 1) (by omega) hfieldsB).read B
    (pre.size + (taggedHeaderBytesV1 "ErrorDecl" 3).size + (encodeU32le d.id).size + (nameB).size) (pre ++ taggedHeaderBytesV1 "ErrorDecl" 3 ++ encodeU32le d.id ++ nameB) (post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp only [decodeErrorDeclV1, h0, h1, h2, h3, Bind.bind, Except.bind, Pure.pure, Except.pure]
  have hsz : pre.size + (taggedHeaderBytesV1 "ErrorDecl" 3).size + (encodeU32le d.id).size + (nameB).size + (fieldsB).size = pre.size + (taggedHeaderBytesV1 "ErrorDecl" 3 ++ encodeU32le d.id ++ nameB ++ fieldsB).size := by
    simp only [ByteArray.size_append]; omega
  rw [hsz]


/-! ### Root tables -/

/-- The `constants` field of `RootFieldInvertV1`, for an **arbitrary** table
    within the production table-size gate. -/
theorem exactMidOffsetInvertAt_constantsTableV1 (xs : Array ConstantV1)
    (hsize : xs.size ≤ maxTableElements) :
    ExactMidOffsetInvertAtV1 (encodeArray encodeConstantV1) (decodeArray maxTableElements decodeConstantV1)
      xs 1 := by
  refine exactMidOffsetInvertAt_of_fieldReadV1 (fun b hb => ?_)
  obtain ⟨_, hall⟩ := encodeArray_ok_inversionV1 _ xs b hb
  refine fieldRead_arrayV1 _ _ maxTableElements xs b 1 hsize (by decide)
    (Nat.le_trans hsize (by decide)) hall ?_ hb
  intro x _
  exact exactMidOffsetInvertAt_of_fieldReadV1
    (fun eb hx => fieldRead_constantV1 x eb 1 (by decide) hx)


/-- The `logicalState` field of `RootFieldInvertV1`, for an **arbitrary** table
    within the production table-size gate. -/
theorem exactMidOffsetInvertAt_logicalStateTableV1 (xs : Array StateDeclV1)
    (hsize : xs.size ≤ maxTableElements) :
    ExactMidOffsetInvertAtV1 (encodeArray encodeStateDeclV1) (decodeArray maxTableElements decodeStateDeclV1)
      xs 1 := by
  refine exactMidOffsetInvertAt_of_fieldReadV1 (fun b hb => ?_)
  obtain ⟨_, hall⟩ := encodeArray_ok_inversionV1 _ xs b hb
  refine fieldRead_arrayV1 _ _ maxTableElements xs b 1 hsize (by decide)
    (Nat.le_trans hsize (by decide)) hall ?_ hb
  intro x _
  exact exactMidOffsetInvertAt_of_fieldReadV1
    (fun eb hx => fieldRead_stateDeclV1 x eb 1 (by decide) hx)


/-- The `events` field of `RootFieldInvertV1`, for an **arbitrary** table
    within the production table-size gate. -/
theorem exactMidOffsetInvertAt_eventsTableV1 (xs : Array EventDeclV1)
    (hsize : xs.size ≤ maxTableElements) :
    ExactMidOffsetInvertAtV1 (encodeArray encodeEventDeclV1) (decodeArray maxTableElements decodeEventDeclV1)
      xs 1 := by
  refine exactMidOffsetInvertAt_of_fieldReadV1 (fun b hb => ?_)
  obtain ⟨_, hall⟩ := encodeArray_ok_inversionV1 _ xs b hb
  refine fieldRead_arrayV1 _ _ maxTableElements xs b 1 hsize (by decide)
    (Nat.le_trans hsize (by decide)) hall ?_ hb
  intro x _
  exact exactMidOffsetInvertAt_of_fieldReadV1
    (fun eb hx => fieldRead_eventDeclV1 x eb 1 (by decide) hx)


/-- The `errors` field of `RootFieldInvertV1`, for an **arbitrary** table
    within the production table-size gate. -/
theorem exactMidOffsetInvertAt_errorsTableV1 (xs : Array ErrorDeclV1)
    (hsize : xs.size ≤ maxTableElements) :
    ExactMidOffsetInvertAtV1 (encodeArray encodeErrorDeclV1) (decodeArray maxTableElements decodeErrorDeclV1)
      xs 1 := by
  refine exactMidOffsetInvertAt_of_fieldReadV1 (fun b hb => ?_)
  obtain ⟨_, hall⟩ := encodeArray_ok_inversionV1 _ xs b hb
  refine fieldRead_arrayV1 _ _ maxTableElements xs b 1 hsize (by decide)
    (Nat.le_trans hsize (by decide)) hall ?_ hb
  intro x _
  exact exactMidOffsetInvertAt_of_fieldReadV1
    (fun eb hx => fieldRead_errorDeclV1 x eb 1 (by decide) hx)


end ProofForgeV2.Semantic.WireV1
