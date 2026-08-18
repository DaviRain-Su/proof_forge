import ProofForgeV2.Semantic.Wire.CodecInvertTermV1

/-!
  ProofForgeV2.Semantic.Wire.CodecInvertCallableBodyV1 — generic invert of
  Instruction / BlockParameter / Block / Parameter / CallableResult /
  LoopBound / CallableKind / ValueDef and the `callables` root table
  under `size ≤ maxTableElements`.
-/

namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common

private theorem toUTF8_size_eq_utf8ByteSize (s : String) :
    s.toUTF8.size = s.utf8ByteSize := rfl

/-! ### ASCII -/

theorem asciiTagBytes_InstructionV1 : isAsciiTagBytesV1 "Instruction".toUTF8 = true := by
  rw [show "Instruction".toUTF8 =
    ByteArray.mk #[73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_BlockParameterV1 :
    isAsciiTagBytesV1 "BlockParameter".toUTF8 = true := by
  rw [show "BlockParameter".toUTF8 =
    ByteArray.mk #[66, 108, 111, 99, 107, 80, 97, 114, 97, 109, 101, 116, 101, 114]
      from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_BlockV1 : isAsciiTagBytesV1 "Block".toUTF8 = true := by
  rw [show "Block".toUTF8 = ByteArray.mk #[66, 108, 111, 99, 107] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_ParameterV1 : isAsciiTagBytesV1 "Parameter".toUTF8 = true := by
  rw [show "Parameter".toUTF8 =
    ByteArray.mk #[80, 97, 114, 97, 109, 101, 116, 101, 114] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_CallableResultV1 :
    isAsciiTagBytesV1 "CallableResult".toUTF8 = true := by
  rw [show "CallableResult".toUTF8 =
    ByteArray.mk #[67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116]
      from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_ValueDefV1 : isAsciiTagBytesV1 "ValueDef".toUTF8 = true := by
  rw [show "ValueDef".toUTF8 =
    ByteArray.mk #[86, 97, 108, 117, 101, 68, 101, 102] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_LoopBoundV1 : isAsciiTagBytesV1 "LoopBound".toUTF8 = true := by
  rw [show "LoopBound".toUTF8 =
    ByteArray.mk #[76, 111, 111, 112, 66, 111, 117, 110, 100] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_CallableV1 : isAsciiTagBytesV1 "Callable".toUTF8 = true := by
  rw [show "Callable".toUTF8 =
    ByteArray.mk #[67, 97, 108, 108, 97, 98, 108, 101] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_CallableInitializerV1 :
    isAsciiTagBytesV1 "Callable.Initializer".toUTF8 = true := by
  rw [show "Callable.Initializer".toUTF8 =
    ByteArray.mk #[67, 97, 108, 108, 97, 98, 108, 101, 46, 73, 110, 105, 116, 105, 97,
      108, 105, 122, 101, 114] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_CallableEntryV1 :
    isAsciiTagBytesV1 "Callable.Entry".toUTF8 = true := by
  rw [show "Callable.Entry".toUTF8 =
    ByteArray.mk #[67, 97, 108, 108, 97, 98, 108, 101, 46, 69, 110, 116, 114, 121]
      from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_CallableViewV1 :
    isAsciiTagBytesV1 "Callable.View".toUTF8 = true := by
  rw [show "Callable.View".toUTF8 =
    ByteArray.mk #[67, 97, 108, 108, 97, 98, 108, 101, 46, 86, 105, 101, 119] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_CallablePureFnV1 :
    isAsciiTagBytesV1 "Callable.PureFn".toUTF8 = true := by
  rw [show "Callable.PureFn".toUTF8 =
    ByteArray.mk #[67, 97, 108, 108, 97, 98, 108, 101, 46, 80, 117, 114, 101, 70, 110]
      from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_CallableInvariantV1 :
    isAsciiTagBytesV1 "Callable.Invariant".toUTF8 = true := by
  rw [show "Callable.Invariant".toUTF8 =
    ByteArray.mk #[67, 97, 108, 108, 97, 98, 108, 101, 46, 73, 110, 118, 97, 114, 105,
      97, 110, 116] from rfl]
  simp [isAsciiTagBytesV1]

/-! ### Nine-field tagged layout -/

theorem taggedBytes_nine_fieldsV1 (tag : String)
    (f0 f1 f2 f3 f4 f5 f6 f7 f8 : ByteArray) :
    taggedBytesV1 tag #[f0, f1, f2, f3, f4, f5, f6, f7, f8] =
      taggedHeaderBytesV1 tag 9 ++ f0 ++ f1 ++ f2 ++ f3 ++ f4 ++ f5 ++ f6 ++ f7 ++ f8 := by
  have h := taggedBytesV1_eq_header_payload tag #[f0, f1, f2, f3, f4, f5, f6, f7, f8]
  have hfold :
      (#[f0, f1, f2, f3, f4, f5, f6, f7, f8] : Array ByteArray).foldl
        (fun out f => out.append f) ByteArray.empty =
        f0 ++ f1 ++ f2 ++ f3 ++ f4 ++ f5 ++ f6 ++ f7 ++ f8 := by
    simp [List.foldl]
  have hsz : (#[f0, f1, f2, f3, f4, f5, f6, f7, f8] : Array ByteArray).size = 9 := rfl
  rw [h, hfold, hsz]
  simp [ByteArray.append_assoc]

theorem encodeTagged_ok_eq_nine_fieldsV1 (tag : String)
    (f0 f1 f2 f3 f4 f5 f6 f7 f8 b : ByteArray)
    (h : encodeTagged tag #[f0, f1, f2, f3, f4, f5, f6, f7, f8] = .ok b) :
    b = taggedHeaderBytesV1 tag 9 ++ f0 ++ f1 ++ f2 ++ f3 ++ f4 ++ f5 ++ f6 ++ f7 ++ f8 := by
  rw [(encodeTagged_ok_eq_taggedBytesV1 tag #[f0, f1, f2, f3, f4, f5, f6, f7, f8] b h).1,
    taggedBytes_nine_fieldsV1]

/-! ### ValueDef / LoopBound / BlockParameter / CallableKind -/

theorem fieldRead_valueDefV1 (v : ValueDefV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) (henc : encodeValueDefV1 v = .ok b) :
    FieldReadV1 decodeValueDefV1 b v nesting := by
  have hb := encodeTagged_ok_eq_two_fieldsV1 "ValueDef" (encodeU32le v.valueId)
    (encodeU32le v.typeId) b henc
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ hdepth
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "ValueDef" 2 ++ encodeU32le v.valueId ++
        encodeU32le v.typeId) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 :=
    (fieldRead_expectTagV1 "ValueDef" 2 (nesting + 1) (by decide) (by decide)
      (by decide) asciiTagBytes_ValueDefV1 (by decide)).read B pre.size pre
      (encodeU32le v.valueId ++ encodeU32le v.typeId ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) rfl
  have h1 := (fieldRead_u32V1 v.valueId (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "ValueDef" 2).size)
    (pre ++ taggedHeaderBytesV1 "ValueDef" 2) (encodeU32le v.typeId ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h2 := (fieldRead_u32V1 v.typeId (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "ValueDef" 2).size + (encodeU32le v.valueId).size)
    (pre ++ taggedHeaderBytesV1 "ValueDef" 2 ++ encodeU32le v.valueId) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [decodeValueDefBodyV1, h0, h1, h2, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_loopBoundV1 (lb : LoopBoundV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) (henc : encodeLoopBoundV1 lb = .ok b) :
    FieldReadV1 decodeLoopBoundV1 b lb nesting := by
  have hb := encodeTagged_ok_eq_three_fieldsV1 "LoopBound" (encodeU32le lb.header)
    (encodeU32le lb.backEdgeFrom) (encodeU32le lb.maxIterations) b henc
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ hdepth
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "LoopBound" 3 ++ encodeU32le lb.header ++
        encodeU32le lb.backEdgeFrom ++ encodeU32le lb.maxIterations) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 :=
    (fieldRead_expectTagV1 "LoopBound" 3 (nesting + 1) (by decide) (by decide)
      (by decide) asciiTagBytes_LoopBoundV1 (by decide)).read B pre.size pre
      (encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
        encodeU32le lb.maxIterations ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) rfl
  have h1 := (fieldRead_u32V1 lb.header (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "LoopBound" 3).size)
    (pre ++ taggedHeaderBytesV1 "LoopBound" 3)
    (encodeU32le lb.backEdgeFrom ++ encodeU32le lb.maxIterations ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h2 := (fieldRead_u32V1 lb.backEdgeFrom (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "LoopBound" 3).size + (encodeU32le lb.header).size)
    (pre ++ taggedHeaderBytesV1 "LoopBound" 3 ++ encodeU32le lb.header)
    (encodeU32le lb.maxIterations ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_u32V1 lb.maxIterations (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "LoopBound" 3).size + (encodeU32le lb.header).size +
      (encodeU32le lb.backEdgeFrom).size)
    (pre ++ taggedHeaderBytesV1 "LoopBound" 3 ++ encodeU32le lb.header ++
      encodeU32le lb.backEdgeFrom) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [decodeLoopBoundBodyV1, h0, h1, h2, h3, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_blockParameterV1 (p : BlockParameterV1) (b : ByteArray)
    (nesting : Nat) (hdepth : nesting < maxNesting)
    (henc : encodeBlockParameterV1 p = .ok b) :
    FieldReadV1 decodeBlockParameterV1 b p nesting := by
  have hb := encodeTagged_ok_eq_two_fieldsV1 "BlockParameter" (encodeU32le p.valueId)
    (encodeU32le p.typeId) b henc
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ hdepth
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "BlockParameter" 2 ++ encodeU32le p.valueId ++
        encodeU32le p.typeId) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 :=
    (fieldRead_expectTagV1 "BlockParameter" 2 (nesting + 1) (by decide) (by decide)
      (by decide) asciiTagBytes_BlockParameterV1 (by decide)).read B pre.size pre
      (encodeU32le p.valueId ++ encodeU32le p.typeId ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) rfl
  have h1 := (fieldRead_u32V1 p.valueId (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "BlockParameter" 2).size)
    (pre ++ taggedHeaderBytesV1 "BlockParameter" 2) (encodeU32le p.typeId ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h2 := (fieldRead_u32V1 p.typeId (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "BlockParameter" 2).size +
      (encodeU32le p.valueId).size)
    (pre ++ taggedHeaderBytesV1 "BlockParameter" 2 ++ encodeU32le p.valueId) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [h0, h1, h2, Bind.bind, Except.bind, Pure.pure, Except.pure]
  simp [ByteArray.size_append, Nat.add_assoc]

def callableKindTagV1 : CallableKindV1 → String
  | .initializer => "Callable.Initializer"
  | .entry => "Callable.Entry"
  | .view => "Callable.View"
  | .pureFn => "Callable.PureFn"
  | .invariant => "Callable.Invariant"

theorem encodeCallableKind_eq_nullaryV1 (k : CallableKindV1) :
    encodeCallableKindV1 k = encodeNullary (callableKindTagV1 k) := by
  cases k <;> rfl

theorem fieldRead_callableKindV1 (k : CallableKindV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) (henc : encodeCallableKindV1 k = .ok b) :
    FieldReadV1 decodeCallableKindV1 b k nesting := by
  have hnull : encodeNullary (callableKindTagV1 k) = .ok b := by
    simpa [encodeCallableKind_eq_nullaryV1] using henc
  have hb := encodeNullary_ok_eq_headerV1 (callableKindTagV1 k) b
    (by cases k <;> decide) (by cases k <;> decide) (by cases k <;> decide) hnull
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ hdepth
  intro pre post
  cases k with
  | initializer =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Callable.Initializer" 0 ++ post) pre.size pre post
        "Callable.Initializer" 0 (nesting + 1) rfl rfl (by decide) (by decide)
        (by decide) asciiTagBytes_CallableInitializerV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Callable.Initializer" 0 ++ post)
        (pre.size + 4 + "Callable.Initializer".utf8ByteSize) pre post
        "Callable.Initializer" 0 (nesting + 1) rfl rfl (by decide)
      simp [callableKindTagV1, decodeCallableKindBodyV1, h0, h1, Bind.bind,
        Except.bind, Pure.pure, Except.pure]
  | entry =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Callable.Entry" 0 ++ post) pre.size pre post
        "Callable.Entry" 0 (nesting + 1) rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_CallableEntryV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Callable.Entry" 0 ++ post)
        (pre.size + 4 + "Callable.Entry".utf8ByteSize) pre post "Callable.Entry" 0
        (nesting + 1) rfl rfl (by decide)
      simp [callableKindTagV1, decodeCallableKindBodyV1, h0, h1, Bind.bind,
        Except.bind, Pure.pure, Except.pure]
  | view =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Callable.View" 0 ++ post) pre.size pre post
        "Callable.View" 0 (nesting + 1) rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_CallableViewV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Callable.View" 0 ++ post)
        (pre.size + 4 + "Callable.View".utf8ByteSize) pre post "Callable.View" 0
        (nesting + 1) rfl rfl (by decide)
      simp [callableKindTagV1, decodeCallableKindBodyV1, h0, h1, Bind.bind,
        Except.bind, Pure.pure, Except.pure]
  | pureFn =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Callable.PureFn" 0 ++ post) pre.size pre post
        "Callable.PureFn" 0 (nesting + 1) rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_CallablePureFnV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Callable.PureFn" 0 ++ post)
        (pre.size + 4 + "Callable.PureFn".utf8ByteSize) pre post "Callable.PureFn" 0
        (nesting + 1) rfl rfl (by decide)
      simp [callableKindTagV1, decodeCallableKindBodyV1, h0, h1, Bind.bind,
        Except.bind, Pure.pure, Except.pure]
  | invariant =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Callable.Invariant" 0 ++ post) pre.size pre post
        "Callable.Invariant" 0 (nesting + 1) rfl rfl (by decide) (by decide)
        (by decide) asciiTagBytes_CallableInvariantV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Callable.Invariant" 0 ++ post)
        (pre.size + 4 + "Callable.Invariant".utf8ByteSize) pre post
        "Callable.Invariant" 0 (nesting + 1) rfl rfl (by decide)
      simp [callableKindTagV1, decodeCallableKindBodyV1, h0, h1, Bind.bind,
        Except.bind, Pure.pure, Except.pure]

theorem fieldRead_visibilityV1 (v : VisibilityV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) (henc : encodeVisibilityV1 v = .ok b) :
    FieldReadV1 decodeVisibilityV1 b v nesting :=
  FieldReadV1.ofGlobal midOffsetInvert_encodeVisibility_decodeVisibility hdepth henc

/-! ### Parameter / CallableResult -/

theorem fieldRead_parameterV1 (p : ParameterV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting) (henc : encodeParameterV1 p = .ok b) :
    FieldReadV1 decodeParameterV1 b p nesting := by
  obtain ⟨nameB, hname, hrest⟩ := except_bind_ok_inversionV1 (encodeString p.name)
    (fun nameB => encodeVisibilityV1 p.visibility >>= fun visB =>
      encodeTagged "Parameter"
        #[encodeU32le p.valueId, nameB, encodeU32le p.typeId, visB]) b henc
  obtain ⟨visB, hvis, htag⟩ := except_bind_ok_inversionV1 (encodeVisibilityV1 p.visibility)
    (fun visB => encodeTagged "Parameter"
      #[encodeU32le p.valueId, nameB, encodeU32le p.typeId, visB]) b hrest
  have hb := encodeTagged_ok_eq_four_fieldsV1 "Parameter" (encodeU32le p.valueId) nameB
    (encodeU32le p.typeId) visB b htag
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ (Nat.lt_of_succ_lt hdepth)
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Parameter" 4 ++ encodeU32le p.valueId ++ nameB ++
        encodeU32le p.typeId ++ visB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 :=
    (fieldRead_expectTagV1 "Parameter" 4 (nesting + 1) (by decide) (by decide)
      (by decide) asciiTagBytes_ParameterV1 (by decide)).read B pre.size pre
      (encodeU32le p.valueId ++ nameB ++ encodeU32le p.typeId ++ visB ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) rfl
  have h1 := (fieldRead_u32V1 p.valueId (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "Parameter" 4).size)
    (pre ++ taggedHeaderBytesV1 "Parameter" 4)
    (nameB ++ encodeU32le p.typeId ++ visB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h2 := (fieldRead_stringV1 p.name nameB (nesting + 1) hname).read B
    (pre.size + (taggedHeaderBytesV1 "Parameter" 4).size + (encodeU32le p.valueId).size)
    (pre ++ taggedHeaderBytesV1 "Parameter" 4 ++ encodeU32le p.valueId)
    (encodeU32le p.typeId ++ visB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_u32V1 p.typeId (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "Parameter" 4).size + (encodeU32le p.valueId).size +
      nameB.size)
    (pre ++ taggedHeaderBytesV1 "Parameter" 4 ++ encodeU32le p.valueId ++ nameB)
    (visB ++ post) (by rw [hB]; simp [ByteArray.append_assoc])
    (by simp [ByteArray.size_append])
  have h4 := (fieldRead_visibilityV1 p.visibility visB (nesting + 1) (by omega) hvis).read
    B (pre.size + (taggedHeaderBytesV1 "Parameter" 4).size + (encodeU32le p.valueId).size +
      nameB.size + (encodeU32le p.typeId).size)
    (pre ++ taggedHeaderBytesV1 "Parameter" 4 ++ encodeU32le p.valueId ++ nameB ++
      encodeU32le p.typeId) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [decodeParameterBodyV1, h0, h1, h2, h3, h4, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_callableResultV1 (r : CallableResultV1) (b : ByteArray)
    (nesting : Nat) (hdepth : nesting + 1 < maxNesting)
    (henc : encodeCallableResultV1 r = .ok b) :
    FieldReadV1 decodeCallableResultV1 b r nesting := by
  obtain ⟨visB, hvis, htag⟩ := except_bind_ok_inversionV1 (encodeVisibilityV1 r.visibility)
    (fun visB => encodeTagged "CallableResult" #[encodeU32le r.typeId, visB]) b henc
  have hb := encodeTagged_ok_eq_two_fieldsV1 "CallableResult" (encodeU32le r.typeId)
    visB b htag
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ (Nat.lt_of_succ_lt hdepth)
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le r.typeId ++ visB) ++
        post := ⟨_, rfl⟩
  rw [← hB]
  have h0 :=
    (fieldRead_expectTagV1 "CallableResult" 2 (nesting + 1) (by decide) (by decide)
      (by decide) asciiTagBytes_CallableResultV1 (by decide)).read B pre.size pre
      (encodeU32le r.typeId ++ visB ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) rfl
  have h1 := (fieldRead_u32V1 r.typeId (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "CallableResult" 2).size)
    (pre ++ taggedHeaderBytesV1 "CallableResult" 2) (visB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h2 := (fieldRead_visibilityV1 r.visibility visB (nesting + 1) (by omega) hvis).read
    B (pre.size + (taggedHeaderBytesV1 "CallableResult" 2).size +
      (encodeU32le r.typeId).size)
    (pre ++ taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le r.typeId) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [decodeCallableResultBodyV1, h0, h1, h2, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  simp [ByteArray.size_append, Nat.add_assoc]

/-! ### Instruction / Block / Callable -/

theorem fieldRead_instructionV1 (i : InstructionV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting + 2 < maxNesting) (henc : encodeInstructionV1 i = .ok b) :
    FieldReadV1 decodeInstructionV1 b i nesting := by
  obtain ⟨resultB, hresult, hrest⟩ :=
    except_bind_ok_inversionV1 (encodeOption encodeValueDefV1 i.result)
      (fun resultB => encodeSemanticOpV1 i.op >>= fun opB =>
        encodeTagged "Instruction" #[resultB, opB]) b henc
  obtain ⟨opB, hop, htag⟩ := except_bind_ok_inversionV1 (encodeSemanticOpV1 i.op)
    (fun opB => encodeTagged "Instruction" #[resultB, opB]) b hrest
  have hb := encodeTagged_ok_eq_two_fieldsV1 "Instruction" resultB opB b htag
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ (by omega)
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Instruction" 2 ++ resultB ++ opB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 :=
    (fieldRead_expectTagV1 "Instruction" 2 (nesting + 1) (by decide) (by decide)
      (by decide) asciiTagBytes_InstructionV1 (by decide)).read B pre.size pre
      (resultB ++ opB ++ post) (by rw [hB]; simp [ByteArray.append_assoc]) rfl
  have h1 := (fieldRead_optionV1 encodeValueDefV1 decodeValueDefV1 i.result resultB
      (nesting + 1) hresult (fun x payload _ hx =>
        fieldRead_valueDefV1 x payload (nesting + 1) (by omega) hx)).read B
    (pre.size + (taggedHeaderBytesV1 "Instruction" 2).size)
    (pre ++ taggedHeaderBytesV1 "Instruction" 2) (opB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h2 := (fieldRead_semanticOpV1 i.op opB (nesting + 1) (by omega) hop).read B
    (pre.size + (taggedHeaderBytesV1 "Instruction" 2).size + resultB.size)
    (pre ++ taggedHeaderBytesV1 "Instruction" 2 ++ resultB) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [decodeInstructionBodyV1, h0, h1, h2, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_blockV1 (blk : BlockV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting + 3 < maxNesting) (henc : encodeBlockV1 blk = .ok b) :
    FieldReadV1 decodeBlockV1 b blk nesting := by
  obtain ⟨paramsB, hparams, hrest1⟩ :=
    except_bind_ok_inversionV1 (encodeArray encodeBlockParameterV1 blk.params)
      (fun paramsB => encodeArray encodeInstructionV1 blk.instructions >>= fun instrB =>
        encodeTerminatorV1 blk.terminator >>= fun termB =>
          encodeTagged "Block" #[encodeU32le blk.id, paramsB, instrB, termB]) b henc
  obtain ⟨instrB, hinstr, hrest2⟩ :=
    except_bind_ok_inversionV1 (encodeArray encodeInstructionV1 blk.instructions)
      (fun instrB => encodeTerminatorV1 blk.terminator >>= fun termB =>
        encodeTagged "Block" #[encodeU32le blk.id, paramsB, instrB, termB]) b hrest1
  obtain ⟨termB, hterm, htag⟩ := except_bind_ok_inversionV1 (encodeTerminatorV1 blk.terminator)
    (fun termB => encodeTagged "Block" #[encodeU32le blk.id, paramsB, instrB, termB])
    b hrest2
  have hb := encodeTagged_ok_eq_four_fieldsV1 "Block" (encodeU32le blk.id) paramsB instrB
    termB b htag
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ (by omega)
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++
        termB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 :=
    (fieldRead_expectTagV1 "Block" 4 (nesting + 1) (by decide) (by decide) (by decide)
      asciiTagBytes_BlockV1 (by decide)).read B pre.size pre
      (encodeU32le blk.id ++ paramsB ++ instrB ++ termB ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) rfl
  have h1 := (fieldRead_u32V1 blk.id (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "Block" 4).size)
    (pre ++ taggedHeaderBytesV1 "Block" 4) (paramsB ++ instrB ++ termB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h2 := by
    obtain ⟨hsize, hall⟩ := encodeArray_ok_inversionV1 _ blk.params paramsB hparams
    exact (fieldRead_arrayV1 _ _ maxArrayElements blk.params paramsB (nesting + 1)
      hsize (by decide) (Nat.le_trans hsize (by decide)) hall
      (fun x _ => exactMidOffsetInvertAt_of_fieldReadV1 (fun eb hx =>
        fieldRead_blockParameterV1 x eb (nesting + 1) (by omega) hx)) hparams).read B
      (pre.size + (taggedHeaderBytesV1 "Block" 4).size + (encodeU32le blk.id).size)
      (pre ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id)
      (instrB ++ termB ++ post) (by rw [hB]; simp [ByteArray.append_assoc])
      (by simp [ByteArray.size_append])
  have h3 := by
    obtain ⟨hsize, hall⟩ := encodeArray_ok_inversionV1 _ blk.instructions instrB hinstr
    exact (fieldRead_arrayV1 _ _ maxArrayElements blk.instructions instrB (nesting + 1)
      hsize (by decide) (Nat.le_trans hsize (by decide)) hall
      (fun x _ => exactMidOffsetInvertAt_of_fieldReadV1 (fun eb hx =>
        fieldRead_instructionV1 x eb (nesting + 1) (by omega) hx)) hinstr).read B
      (pre.size + (taggedHeaderBytesV1 "Block" 4).size + (encodeU32le blk.id).size +
        paramsB.size)
      (pre ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB)
      (termB ++ post) (by rw [hB]; simp [ByteArray.append_assoc])
      (by simp [ByteArray.size_append])
  have h4 := (fieldRead_terminatorV1 blk.terminator termB (nesting + 1) (by omega)
      hterm).read B
    (pre.size + (taggedHeaderBytesV1 "Block" 4).size + (encodeU32le blk.id).size +
      paramsB.size + instrB.size)
    (pre ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB)
    post (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [decodeBlockBodyV1, h0, h1, h2, h3, h4, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_callableV1 (c : CallableV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting + 4 < maxNesting) (henc : encodeCallableV1 c = .ok b) :
    FieldReadV1 decodeCallableV1 b c nesting := by
  obtain ⟨kindB, hkind, r1⟩ := except_bind_ok_inversionV1 (encodeCallableKindV1 c.kind)
    (fun kindB => encodeOption encodeString c.name >>= fun nameB =>
      encodeArray encodeParameterV1 c.params >>= fun paramsB =>
        encodeCallableResultV1 c.result >>= fun resultB =>
          encodeArray encodeBlockV1 c.blocks >>= fun blocksB =>
            encodeArray encodeLoopBoundV1 c.loopBounds >>= fun loopB =>
              encodeOption (fun v => pure (encodeU64le v)) c.invariantSteps >>=
                fun stepsB =>
                  encodeTagged "Callable" #[encodeU32le c.id, kindB, nameB, paramsB,
                    resultB, encodeU32le c.entryBlock, blocksB, loopB, stepsB]) b henc
  obtain ⟨nameB, hname, r2⟩ := except_bind_ok_inversionV1 (encodeOption encodeString c.name)
    (fun nameB => encodeArray encodeParameterV1 c.params >>= fun paramsB =>
      encodeCallableResultV1 c.result >>= fun resultB =>
        encodeArray encodeBlockV1 c.blocks >>= fun blocksB =>
          encodeArray encodeLoopBoundV1 c.loopBounds >>= fun loopB =>
            encodeOption (fun v => pure (encodeU64le v)) c.invariantSteps >>=
              fun stepsB =>
                encodeTagged "Callable" #[encodeU32le c.id, kindB, nameB, paramsB,
                  resultB, encodeU32le c.entryBlock, blocksB, loopB, stepsB]) b r1
  obtain ⟨paramsB, hparams, r3⟩ :=
    except_bind_ok_inversionV1 (encodeArray encodeParameterV1 c.params)
      (fun paramsB => encodeCallableResultV1 c.result >>= fun resultB =>
        encodeArray encodeBlockV1 c.blocks >>= fun blocksB =>
          encodeArray encodeLoopBoundV1 c.loopBounds >>= fun loopB =>
            encodeOption (fun v => pure (encodeU64le v)) c.invariantSteps >>=
              fun stepsB =>
                encodeTagged "Callable" #[encodeU32le c.id, kindB, nameB, paramsB,
                  resultB, encodeU32le c.entryBlock, blocksB, loopB, stepsB]) b r2
  obtain ⟨resultB, hresult, r4⟩ :=
    except_bind_ok_inversionV1 (encodeCallableResultV1 c.result)
      (fun resultB => encodeArray encodeBlockV1 c.blocks >>= fun blocksB =>
        encodeArray encodeLoopBoundV1 c.loopBounds >>= fun loopB =>
          encodeOption (fun v => pure (encodeU64le v)) c.invariantSteps >>=
            fun stepsB =>
              encodeTagged "Callable" #[encodeU32le c.id, kindB, nameB, paramsB,
                resultB, encodeU32le c.entryBlock, blocksB, loopB, stepsB]) b r3
  obtain ⟨blocksB, hblocks, r5⟩ :=
    except_bind_ok_inversionV1 (encodeArray encodeBlockV1 c.blocks)
      (fun blocksB => encodeArray encodeLoopBoundV1 c.loopBounds >>= fun loopB =>
        encodeOption (fun v => pure (encodeU64le v)) c.invariantSteps >>= fun stepsB =>
          encodeTagged "Callable" #[encodeU32le c.id, kindB, nameB, paramsB, resultB,
            encodeU32le c.entryBlock, blocksB, loopB, stepsB]) b r4
  obtain ⟨loopB, hloop, r6⟩ :=
    except_bind_ok_inversionV1 (encodeArray encodeLoopBoundV1 c.loopBounds)
      (fun loopB => encodeOption (fun v => pure (encodeU64le v)) c.invariantSteps >>=
        fun stepsB =>
          encodeTagged "Callable" #[encodeU32le c.id, kindB, nameB, paramsB, resultB,
            encodeU32le c.entryBlock, blocksB, loopB, stepsB]) b r5
  obtain ⟨stepsB, hsteps, htag⟩ :=
    except_bind_ok_inversionV1
      (encodeOption (fun v => pure (encodeU64le v)) c.invariantSteps)
      (fun stepsB => encodeTagged "Callable" #[encodeU32le c.id, kindB, nameB, paramsB,
        resultB, encodeU32le c.entryBlock, blocksB, loopB, stepsB]) b r6
  have hb := encodeTagged_ok_eq_nine_fieldsV1 "Callable" (encodeU32le c.id) kindB nameB
    paramsB resultB (encodeU32le c.entryBlock) blocksB loopB stepsB b htag
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ (by omega)
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++
        paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB) ++
        post := ⟨_, rfl⟩
  rw [← hB]
  have h0 :=
    (fieldRead_expectTagV1 "Callable" 9 (nesting + 1) (by decide) (by decide)
      (by decide) asciiTagBytes_CallableV1 (by decide)).read B pre.size pre
      (encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++
        encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) rfl
  have h1 := (fieldRead_u32V1 c.id (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "Callable" 9).size)
    (pre ++ taggedHeaderBytesV1 "Callable" 9)
    (kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++
      loopB ++ stepsB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h2 := (fieldRead_callableKindV1 c.kind kindB (nesting + 1) (by omega) hkind).read B
    (pre.size + (taggedHeaderBytesV1 "Callable" 9).size + (encodeU32le c.id).size)
    (pre ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id)
    (nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++
      stepsB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_optionV1 encodeString decodeString c.name nameB (nesting + 1)
      hname (fun x payload _ hx => fieldRead_stringV1 x payload (nesting + 1) hx)).read B
    (pre.size + (taggedHeaderBytesV1 "Callable" 9).size + (encodeU32le c.id).size +
      kindB.size)
    (pre ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB)
    (paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++
      post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h4 := by
    obtain ⟨hsize, hall⟩ := encodeArray_ok_inversionV1 _ c.params paramsB hparams
    exact (fieldRead_arrayV1 _ _ maxArrayElements c.params paramsB (nesting + 1) hsize
      (by decide) (Nat.le_trans hsize (by decide)) hall
      (fun x _ => exactMidOffsetInvertAt_of_fieldReadV1 (fun eb hx =>
        fieldRead_parameterV1 x eb (nesting + 1) (by omega) hx)) hparams).read B
      (pre.size + (taggedHeaderBytesV1 "Callable" 9).size + (encodeU32le c.id).size +
        kindB.size + nameB.size)
      (pre ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB)
      (resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h5 := (fieldRead_callableResultV1 c.result resultB (nesting + 1) (by omega)
      hresult).read B
    (pre.size + (taggedHeaderBytesV1 "Callable" 9).size + (encodeU32le c.id).size +
      kindB.size + nameB.size + paramsB.size)
    (pre ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++
      paramsB)
    (encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h6 := (fieldRead_u32V1 c.entryBlock (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "Callable" 9).size + (encodeU32le c.id).size +
      kindB.size + nameB.size + paramsB.size + resultB.size)
    (pre ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++
      paramsB ++ resultB)
    (blocksB ++ loopB ++ stepsB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h7 := by
    obtain ⟨hsize, hall⟩ := encodeArray_ok_inversionV1 _ c.blocks blocksB hblocks
    exact (fieldRead_arrayV1 _ _ maxArrayElements c.blocks blocksB (nesting + 1) hsize
      (by decide) (Nat.le_trans hsize (by decide)) hall
      (fun x _ => exactMidOffsetInvertAt_of_fieldReadV1 (fun eb hx =>
        fieldRead_blockV1 x eb (nesting + 1) (by omega) hx)) hblocks).read B
      (pre.size + (taggedHeaderBytesV1 "Callable" 9).size + (encodeU32le c.id).size +
        kindB.size + nameB.size + paramsB.size + resultB.size +
        (encodeU32le c.entryBlock).size)
      (pre ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++
        paramsB ++ resultB ++ encodeU32le c.entryBlock)
      (loopB ++ stepsB ++ post) (by rw [hB]; simp [ByteArray.append_assoc])
      (by simp [ByteArray.size_append])
  have h8 := by
    obtain ⟨hsize, hall⟩ := encodeArray_ok_inversionV1 _ c.loopBounds loopB hloop
    exact (fieldRead_arrayV1 _ _ maxArrayElements c.loopBounds loopB (nesting + 1)
      hsize (by decide) (Nat.le_trans hsize (by decide)) hall
      (fun x _ => exactMidOffsetInvertAt_of_fieldReadV1 (fun eb hx =>
        fieldRead_loopBoundV1 x eb (nesting + 1) (by omega) hx)) hloop).read B
      (pre.size + (taggedHeaderBytesV1 "Callable" 9).size + (encodeU32le c.id).size +
        kindB.size + nameB.size + paramsB.size + resultB.size +
        (encodeU32le c.entryBlock).size + blocksB.size)
      (pre ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++
        paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB)
      (stepsB ++ post) (by rw [hB]; simp [ByteArray.append_assoc])
      (by simp [ByteArray.size_append])
  have h9 := (fieldRead_option_pureV1 encodeU64le decodeU64le c.invariantSteps stepsB
      (nesting + 1) hsteps (fun x => fieldRead_u64V1 x (nesting + 1))).read B
    (pre.size + (taggedHeaderBytesV1 "Callable" 9).size + (encodeU32le c.id).size +
      kindB.size + nameB.size + paramsB.size + resultB.size +
      (encodeU32le c.entryBlock).size + blocksB.size + loopB.size)
    (pre ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++
      paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [decodeCallableBodyV1, h0, h1, h2, h3, h4, h5, h6, h7, h8, h9, Bind.bind,
    Except.bind, Pure.pure, Except.pure]
  simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_callablesTableV1 (callables : Array CallableV1) (b : ByteArray)
    (nesting : Nat) (hdepth : nesting + 4 < maxNesting)
    (hsize : callables.size ≤ maxTableElements)
    (henc : encodeArray encodeCallableV1 callables = .ok b) :
    FieldReadV1 (decodeArray maxTableElements decodeCallableV1) b callables nesting := by
  obtain ⟨_, hall⟩ := encodeArray_ok_inversionV1 _ callables b henc
  refine fieldRead_arrayV1 _ _ maxTableElements callables b nesting hsize (by decide)
    (Nat.le_trans hsize (by decide)) hall ?_ henc
  intro x _
  exact exactMidOffsetInvertAt_of_fieldReadV1
    (fun eb hx => fieldRead_callableV1 x eb nesting hdepth hx)

theorem exactMidOffsetInvertAt_callablesTableV1 (callables : Array CallableV1)
    (hsize : callables.size ≤ maxTableElements) :
    ExactMidOffsetInvertAtV1 (encodeArray encodeCallableV1)
      (decodeArray maxTableElements decodeCallableV1) callables 1 :=
  exactMidOffsetInvertAt_of_fieldReadV1 (fun b henc =>
    fieldRead_callablesTableV1 callables b 1 (by decide) hsize henc)

end ProofForgeV2.Semantic.WireV1
