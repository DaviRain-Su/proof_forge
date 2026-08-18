import ProofForgeV2.Semantic.Wire.CodecInvertFieldReadV1

/-!
  ProofForgeV2.Semantic.Wire.CodecInvertRequirementsV1 — generic invert of
  every `RequirementPredicateV1` constructor, `RequirementRequestV1` with an
  arbitrary predicates array, and `ProgramRequirementsV1` framing.

  Built from the sole production codecs through `FieldReadV1`. No second
  encoder, no fixture, no `native_decide` / `ofReduceBool` / sorry / axiom.
-/

namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common

private theorem toUTF8_size_eq_utf8ByteSize (s : String) :
    s.toUTF8.size = s.utf8ByteSize := rfl

/-! ### ASCII -/

theorem asciiTagBytes_ReqUintAtLeastV1 :
    isAsciiTagBytesV1 "Req.UintAtLeast".toUTF8 = true := by
  rw [show "Req.UintAtLeast".toUTF8 =
    ByteArray.mk #[82, 101, 113, 46, 85, 105, 110, 116, 65, 116, 76, 101, 97, 115, 116]
      from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_ReqUintAtMostV1 :
    isAsciiTagBytesV1 "Req.UintAtMost".toUTF8 = true := by
  rw [show "Req.UintAtMost".toUTF8 =
    ByteArray.mk #[82, 101, 113, 46, 85, 105, 110, 116, 65, 116, 77, 111, 115, 116]
      from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_ReqBoolEqualsV1 :
    isAsciiTagBytesV1 "Req.BoolEquals".toUTF8 = true := by
  rw [show "Req.BoolEquals".toUTF8 =
    ByteArray.mk #[82, 101, 113, 46, 66, 111, 111, 108, 69, 113, 117, 97, 108, 115]
      from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_ReqEnumContainsV1 :
    isAsciiTagBytesV1 "Req.EnumContains".toUTF8 = true := by
  rw [show "Req.EnumContains".toUTF8 =
    ByteArray.mk #[82, 101, 113, 46, 69, 110, 117, 109, 67, 111, 110, 116, 97, 105, 110,
      115] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_ReqDigestEqualsV1 :
    isAsciiTagBytesV1 "Req.DigestEquals".toUTF8 = true := by
  rw [show "Req.DigestEquals".toUTF8 =
    ByteArray.mk #[82, 101, 113, 46, 68, 105, 103, 101, 115, 116, 69, 113, 117, 97, 108,
      115] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_RequirementRequestV1 :
    isAsciiTagBytesV1 "RequirementRequest".toUTF8 = true := by
  rw [show "RequirementRequest".toUTF8 =
    ByteArray.mk #[82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 82, 101, 113,
      117, 101, 115, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_ProgramRequirementsV1 :
    isAsciiTagBytesV1 "ProgramRequirements".toUTF8 = true := by
  rw [show "ProgramRequirements".toUTF8 =
    ByteArray.mk #[80, 114, 111, 103, 114, 97, 109, 82, 101, 113, 117, 105, 114, 101,
      109, 101, 110, 116, 115] from rfl]
  simp [isAsciiTagBytesV1]

/-! ### Leaves -/

theorem fieldRead_boolV1 (v : Bool) (nesting : Nat) :
    FieldReadV1 decodeBool (encodeBool v) v nesting := by
  intro pre post
  cases v with
  | false =>
      have hmarker := decodeU8_encode_midV1 pre post (0 : UInt8) nesting
      simp [encodeBool, decodeBool, hmarker, Bind.bind, Except.bind, Pure.pure,
        Except.pure, encodeU8_sizeV1]
  | true =>
      have hmarker := decodeU8_encode_midV1 pre post (1 : UInt8) nesting
      simp [encodeBool, decodeBool, hmarker, Bind.bind, Except.bind, Pure.pure,
        Except.pure, encodeU8_sizeV1]

theorem fieldRead_digestV1 (digest : Digest) (b : ByteArray) (nesting : Nat)
    (henc : encodeDigest digest = .ok b) :
    FieldReadV1 decodeDigest b digest nesting :=
  fun pre post => decodeDigest_of_encode_midV1 digest b pre post nesting henc

theorem fieldRead_semVerV1 (version : SemVer) (b : ByteArray) (nesting : Nat)
    (henc : encodeSemVer version = .ok b) :
    FieldReadV1 decodeSemVer b version nesting := by
  have hrender : ∃ s, renderSemVer version = .ok s ∧ encodeString s = .ok b := by
    cases hr : renderSemVer version with
    | error e =>
        simp [encodeSemVer, mapCommon, hr, Bind.bind, Except.bind] at henc
    | ok s =>
        refine ⟨s, rfl, ?_⟩
        simpa [encodeSemVer, mapCommon, hr, Bind.bind, Except.bind] using henc
  obtain ⟨s, hr, hstr⟩ := hrender
  have hparse : parseSemVer s = .ok version :=
    parseSemVer_of_renderSemVer_ok version s hr
  intro pre post
  have hread := fieldRead_stringV1 s b nesting hstr pre post
  exact decodeSemVer_eq_of_stringV1 _ _ s version hread hparse

theorem fieldRead_stringArrayV1 (xs : Array String) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (henc : encodeArray encodeString xs = .ok b) :
    FieldReadV1 (decodeArray maxArrayElements decodeString) b xs nesting := by
  obtain ⟨hsize, hall⟩ := encodeArray_ok_inversionV1 _ xs b henc
  refine fieldRead_arrayV1 _ _ maxArrayElements xs b nesting hsize (by decide)
    (Nat.le_trans hsize (by decide)) hall ?_ henc
  intro x _
  exact ExactMidOffsetInvertAtV1.ofGlobal
    midOffsetInvert_encodeString_decodeString x hdepth

/-! ### Predicates -/

theorem fieldRead_requirementPredicateV1 (pred : RequirementPredicateV1)
    (b : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting)
    (henc : encodeRequirementPredicateV1 pred = .ok b) :
    FieldReadV1 decodeRequirementPredicateV1 b pred nesting := by
  simp only [decodeRequirementPredicateV1]
  apply fieldRead_withTaggedNestingV1 _ _ _ _ (Nat.lt_of_succ_lt hdepth)
  cases pred with
  | uintAtLeast name value =>
      obtain ⟨nameB, hname, htag⟩ := except_bind_ok_inversionV1 (encodeString name)
        (fun nameB => encodeTagged "Req.UintAtLeast" #[nameB, encodeU64le value]) b
        (by simpa [encodeRequirementPredicateV1] using henc)
      have hb := encodeTagged_ok_eq_two_fieldsV1 "Req.UintAtLeast" nameB
        (encodeU64le value) b htag
      subst hb
      intro pre post
      obtain ⟨B, hB⟩ : ∃ B, B =
          pre ++ (taggedHeaderBytesV1 "Req.UintAtLeast" 2 ++ nameB ++
            encodeU64le value) ++ post := ⟨_, rfl⟩
      rw [← hB]
      have h0 := decodeTag_header_readV1 B pre.size pre
        (nameB ++ encodeU64le value ++ post) "Req.UintAtLeast" 2 (nesting + 1)
        (by rw [hB]; simp [ByteArray.append_assoc]) rfl
        (by decide) (by decide) (by decide) asciiTagBytes_ReqUintAtLeastV1 (by decide)
      have h1 := decodeFieldCount_header_readV1 B
        (pre.size + 4 + "Req.UintAtLeast".utf8ByteSize) pre
        (nameB ++ encodeU64le value ++ post) "Req.UintAtLeast" 2 (nesting + 1)
        (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
      have h2 := (fieldRead_stringV1 name nameB (nesting + 1) hname).read B
        (pre.size + (taggedHeaderBytesV1 "Req.UintAtLeast" 2).size)
        (pre ++ taggedHeaderBytesV1 "Req.UintAtLeast" 2) (encodeU64le value ++ post)
        (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
      have h3 := (fieldRead_u64V1 value (nesting + 1)).read B
        (pre.size + (taggedHeaderBytesV1 "Req.UintAtLeast" 2).size + nameB.size)
        (pre ++ taggedHeaderBytesV1 "Req.UintAtLeast" 2 ++ nameB) post
        (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
      simp [toUTF8_size_eq_utf8ByteSize] at h0
      simp only [toUTF8_size_eq_utf8ByteSize, h0, h1, h2, h3, Bind.bind,
        Except.bind, Pure.pure, Except.pure]
      try simp [ByteArray.size_append, Nat.add_assoc]
  | uintAtMost name value =>
      obtain ⟨nameB, hname, htag⟩ := except_bind_ok_inversionV1 (encodeString name)
        (fun nameB => encodeTagged "Req.UintAtMost" #[nameB, encodeU64le value]) b
        (by simpa [encodeRequirementPredicateV1] using henc)
      have hb := encodeTagged_ok_eq_two_fieldsV1 "Req.UintAtMost" nameB
        (encodeU64le value) b htag
      subst hb
      intro pre post
      obtain ⟨B, hB⟩ : ∃ B, B =
          pre ++ (taggedHeaderBytesV1 "Req.UintAtMost" 2 ++ nameB ++
            encodeU64le value) ++ post := ⟨_, rfl⟩
      rw [← hB]
      have h0 := decodeTag_header_readV1 B pre.size pre
        (nameB ++ encodeU64le value ++ post) "Req.UintAtMost" 2 (nesting + 1)
        (by rw [hB]; simp [ByteArray.append_assoc]) rfl
        (by decide) (by decide) (by decide) asciiTagBytes_ReqUintAtMostV1 (by decide)
      have h1 := decodeFieldCount_header_readV1 B
        (pre.size + 4 + "Req.UintAtMost".utf8ByteSize) pre
        (nameB ++ encodeU64le value ++ post) "Req.UintAtMost" 2 (nesting + 1)
        (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
      have h2 := (fieldRead_stringV1 name nameB (nesting + 1) hname).read B
        (pre.size + (taggedHeaderBytesV1 "Req.UintAtMost" 2).size)
        (pre ++ taggedHeaderBytesV1 "Req.UintAtMost" 2) (encodeU64le value ++ post)
        (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
      have h3 := (fieldRead_u64V1 value (nesting + 1)).read B
        (pre.size + (taggedHeaderBytesV1 "Req.UintAtMost" 2).size + nameB.size)
        (pre ++ taggedHeaderBytesV1 "Req.UintAtMost" 2 ++ nameB) post
        (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
      simp [toUTF8_size_eq_utf8ByteSize] at h0
      simp only [toUTF8_size_eq_utf8ByteSize, h0, h1, h2, h3, Bind.bind,
        Except.bind, Pure.pure, Except.pure]
      try simp [ByteArray.size_append, Nat.add_assoc]
  | boolEquals name value =>
      obtain ⟨nameB, hname, htag⟩ := except_bind_ok_inversionV1 (encodeString name)
        (fun nameB => encodeTagged "Req.BoolEquals" #[nameB, encodeBool value]) b
        (by simpa [encodeRequirementPredicateV1] using henc)
      have hb := encodeTagged_ok_eq_two_fieldsV1 "Req.BoolEquals" nameB
        (encodeBool value) b htag
      subst hb
      intro pre post
      obtain ⟨B, hB⟩ : ∃ B, B =
          pre ++ (taggedHeaderBytesV1 "Req.BoolEquals" 2 ++ nameB ++
            encodeBool value) ++ post := ⟨_, rfl⟩
      rw [← hB]
      have h0 := decodeTag_header_readV1 B pre.size pre
        (nameB ++ encodeBool value ++ post) "Req.BoolEquals" 2 (nesting + 1)
        (by rw [hB]; simp [ByteArray.append_assoc]) rfl
        (by decide) (by decide) (by decide) asciiTagBytes_ReqBoolEqualsV1 (by decide)
      have h1 := decodeFieldCount_header_readV1 B
        (pre.size + 4 + "Req.BoolEquals".utf8ByteSize) pre
        (nameB ++ encodeBool value ++ post) "Req.BoolEquals" 2 (nesting + 1)
        (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
      have h2 := (fieldRead_stringV1 name nameB (nesting + 1) hname).read B
        (pre.size + (taggedHeaderBytesV1 "Req.BoolEquals" 2).size)
        (pre ++ taggedHeaderBytesV1 "Req.BoolEquals" 2) (encodeBool value ++ post)
        (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
      have h3 := (fieldRead_boolV1 value (nesting + 1)).read B
        (pre.size + (taggedHeaderBytesV1 "Req.BoolEquals" 2).size + nameB.size)
        (pre ++ taggedHeaderBytesV1 "Req.BoolEquals" 2 ++ nameB) post
        (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
      simp [toUTF8_size_eq_utf8ByteSize] at h0
      simp only [toUTF8_size_eq_utf8ByteSize, h0, h1, h2, h3, Bind.bind,
        Except.bind, Pure.pure, Except.pure]
      try simp [ByteArray.size_append, Nat.add_assoc]
  | enumContains name values =>
      obtain ⟨nameB, hname, r1⟩ := except_bind_ok_inversionV1 (encodeString name)
        (fun nameB => encodeArray encodeString values >>= fun valuesB =>
          encodeTagged "Req.EnumContains" #[nameB, valuesB]) b
        (by simpa [encodeRequirementPredicateV1] using henc)
      obtain ⟨valuesB, hvalues, htag⟩ := except_bind_ok_inversionV1
        (encodeArray encodeString values)
        (fun valuesB => encodeTagged "Req.EnumContains" #[nameB, valuesB]) b r1
      have hb := encodeTagged_ok_eq_two_fieldsV1 "Req.EnumContains" nameB valuesB b htag
      subst hb
      intro pre post
      obtain ⟨B, hB⟩ : ∃ B, B =
          pre ++ (taggedHeaderBytesV1 "Req.EnumContains" 2 ++ nameB ++ valuesB) ++
            post := ⟨_, rfl⟩
      rw [← hB]
      have h0 := decodeTag_header_readV1 B pre.size pre (nameB ++ valuesB ++ post)
        "Req.EnumContains" 2 (nesting + 1)
        (by rw [hB]; simp [ByteArray.append_assoc]) rfl
        (by decide) (by decide) (by decide) asciiTagBytes_ReqEnumContainsV1 (by decide)
      have h1 := decodeFieldCount_header_readV1 B
        (pre.size + 4 + "Req.EnumContains".utf8ByteSize) pre
        (nameB ++ valuesB ++ post) "Req.EnumContains" 2 (nesting + 1)
        (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
      have h2 := (fieldRead_stringV1 name nameB (nesting + 1) hname).read B
        (pre.size + (taggedHeaderBytesV1 "Req.EnumContains" 2).size)
        (pre ++ taggedHeaderBytesV1 "Req.EnumContains" 2) (valuesB ++ post)
        (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
      have h3 := (fieldRead_stringArrayV1 values valuesB (nesting + 1)
          (by omega) hvalues).read B
        (pre.size + (taggedHeaderBytesV1 "Req.EnumContains" 2).size + nameB.size)
        (pre ++ taggedHeaderBytesV1 "Req.EnumContains" 2 ++ nameB) post
        (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
      simp [toUTF8_size_eq_utf8ByteSize] at h0
      simp only [toUTF8_size_eq_utf8ByteSize, h0, h1, h2, h3, Bind.bind,
        Except.bind, Pure.pure, Except.pure]
      try simp [ByteArray.size_append, Nat.add_assoc]
  | digestEquals name value =>
      obtain ⟨nameB, hname, r1⟩ := except_bind_ok_inversionV1 (encodeString name)
        (fun nameB => encodeDigest value >>= fun digB =>
          encodeTagged "Req.DigestEquals" #[nameB, digB]) b
        (by simpa [encodeRequirementPredicateV1] using henc)
      obtain ⟨digB, hdig, htag⟩ := except_bind_ok_inversionV1 (encodeDigest value)
        (fun digB => encodeTagged "Req.DigestEquals" #[nameB, digB]) b r1
      have hb := encodeTagged_ok_eq_two_fieldsV1 "Req.DigestEquals" nameB digB b htag
      subst hb
      intro pre post
      obtain ⟨B, hB⟩ : ∃ B, B =
          pre ++ (taggedHeaderBytesV1 "Req.DigestEquals" 2 ++ nameB ++ digB) ++
            post := ⟨_, rfl⟩
      rw [← hB]
      have h0 := decodeTag_header_readV1 B pre.size pre (nameB ++ digB ++ post)
        "Req.DigestEquals" 2 (nesting + 1)
        (by rw [hB]; simp [ByteArray.append_assoc]) rfl
        (by decide) (by decide) (by decide) asciiTagBytes_ReqDigestEqualsV1 (by decide)
      have h1 := decodeFieldCount_header_readV1 B
        (pre.size + 4 + "Req.DigestEquals".utf8ByteSize) pre
        (nameB ++ digB ++ post) "Req.DigestEquals" 2 (nesting + 1)
        (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
      have h2 := (fieldRead_stringV1 name nameB (nesting + 1) hname).read B
        (pre.size + (taggedHeaderBytesV1 "Req.DigestEquals" 2).size)
        (pre ++ taggedHeaderBytesV1 "Req.DigestEquals" 2) (digB ++ post)
        (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
      have h3 := (fieldRead_digestV1 value digB (nesting + 1) hdig).read B
        (pre.size + (taggedHeaderBytesV1 "Req.DigestEquals" 2).size + nameB.size)
        (pre ++ taggedHeaderBytesV1 "Req.DigestEquals" 2 ++ nameB) post
        (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
      simp [toUTF8_size_eq_utf8ByteSize] at h0
      simp only [toUTF8_size_eq_utf8ByteSize, h0, h1, h2, h3, Bind.bind,
        Except.bind, Pure.pure, Except.pure]
      try simp [ByteArray.size_append, Nat.add_assoc]

theorem exactMidOffsetInvertAt_requirementPredicateV1
    (pred : RequirementPredicateV1) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting) :
    ExactMidOffsetInvertAtV1 encodeRequirementPredicateV1
      decodeRequirementPredicateV1 pred nesting :=
  exactMidOffsetInvertAt_of_fieldReadV1 (fun b henc =>
    fieldRead_requirementPredicateV1 pred b nesting hdepth henc)

/-! ### RequirementRequest -/

theorem fieldRead_requirementRequestV1 (r : RequirementRequestV1) (b : ByteArray)
    (nesting : Nat) (hdepth : nesting + 2 < maxNesting)
    (henc : encodeRequirementRequestV1 r = .ok b) :
    FieldReadV1 decodeRequirementRequestV1 b r nesting := by
  obtain ⟨idB, hid, r1⟩ := except_bind_ok_inversionV1 (encodeString r.id)
    (fun idB => encodeSemVer r.version >>= fun verB =>
      encodeDigest r.digest >>= fun digB =>
        encodeArray encodeRequirementPredicateV1 r.predicates >>= fun predB =>
          encodeTagged "RequirementRequest" #[idB, verB, digB, predB]) b
    (by simpa [encodeRequirementRequestV1] using henc)
  obtain ⟨verB, hver, r2⟩ := except_bind_ok_inversionV1 (encodeSemVer r.version)
    (fun verB => encodeDigest r.digest >>= fun digB =>
      encodeArray encodeRequirementPredicateV1 r.predicates >>= fun predB =>
        encodeTagged "RequirementRequest" #[idB, verB, digB, predB]) b r1
  obtain ⟨digB, hdig, r3⟩ := except_bind_ok_inversionV1 (encodeDigest r.digest)
    (fun digB => encodeArray encodeRequirementPredicateV1 r.predicates >>= fun predB =>
      encodeTagged "RequirementRequest" #[idB, verB, digB, predB]) b r2
  obtain ⟨predB, hpred, htag⟩ := except_bind_ok_inversionV1
    (encodeArray encodeRequirementPredicateV1 r.predicates)
    (fun predB => encodeTagged "RequirementRequest" #[idB, verB, digB, predB]) b r3
  have hb := encodeTagged_ok_eq_four_fieldsV1 "RequirementRequest" idB verB digB predB
    b htag
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ (by omega)
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB ++
        predB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 :=
    (fieldRead_expectTagV1 "RequirementRequest" 4 (nesting + 1) (by decide)
      (by decide) (by decide) asciiTagBytes_RequirementRequestV1 (by decide)).read B
      pre.size pre (idB ++ verB ++ digB ++ predB ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) rfl
  have h1 := (fieldRead_stringV1 r.id idB (nesting + 1) hid).read B
    (pre.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size)
    (pre ++ taggedHeaderBytesV1 "RequirementRequest" 4)
    (verB ++ digB ++ predB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h2 := (fieldRead_semVerV1 r.version verB (nesting + 1) hver).read B
    (pre.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size + idB.size)
    (pre ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB)
    (digB ++ predB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_digestV1 r.digest digB (nesting + 1) hdig).read B
    (pre.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size + idB.size +
      verB.size)
    (pre ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB)
    (predB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h4 := by
    obtain ⟨hsize, hall⟩ := encodeArray_ok_inversionV1 _ r.predicates predB hpred
    exact (fieldRead_arrayV1 _ _ maxArrayElements r.predicates predB (nesting + 1)
      hsize (by decide) (Nat.le_trans hsize (by decide)) hall
      (fun x _ => exactMidOffsetInvertAt_requirementPredicateV1 x (nesting + 1)
        (by omega)) hpred).read B
      (pre.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size + idB.size +
        verB.size + digB.size)
      (pre ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++ idB ++ verB ++ digB)
      post (by rw [hB]; simp [ByteArray.append_assoc])
      (by simp [ByteArray.size_append])
  simp [h0, h1, h2, h3, h4, Bind.bind, Except.bind, Pure.pure, Except.pure]
  simp [ByteArray.size_append, Nat.add_assoc]

theorem exactMidOffsetInvertAt_requirementRequestV1 (r : RequirementRequestV1)
    (nesting : Nat) (hdepth : nesting + 2 < maxNesting) :
    ExactMidOffsetInvertAtV1 encodeRequirementRequestV1 decodeRequirementRequestV1
      r nesting :=
  exactMidOffsetInvertAt_of_fieldReadV1 (fun b henc =>
    fieldRead_requirementRequestV1 r b nesting hdepth henc)

/-! ### ProgramRequirements -/

theorem fieldRead_programRequirementsV1 (r : ProgramRequirementsV1) (b : ByteArray)
    (nesting : Nat) (hdepth : nesting + 3 < maxNesting)
    (henc : encodeProgramRequirementsV1 r = .ok b) :
    FieldReadV1 decodeProgramRequirementsV1 b r nesting := by
  obtain ⟨itemsB, hitems, htag⟩ := except_bind_ok_inversionV1
    (encodeArray encodeRequirementRequestV1 r.items)
    (fun itemsB => encodeTagged "ProgramRequirements" #[itemsB]) b
    (by simpa [encodeProgramRequirementsV1] using henc)
  have hb := encodeTagged_ok_eq_one_fieldV1 "ProgramRequirements" itemsB b htag
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ (by omega)
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "ProgramRequirements" 1 ++ itemsB) ++ post :=
    ⟨_, rfl⟩
  rw [← hB]
  have h0 :=
    (fieldRead_expectTagV1 "ProgramRequirements" 1 (nesting + 1) (by decide)
      (by decide) (by decide) asciiTagBytes_ProgramRequirementsV1 (by decide)).read B
      pre.size pre (itemsB ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) rfl
  have h1 := by
    obtain ⟨hsize, hall⟩ := encodeArray_ok_inversionV1 _ r.items itemsB hitems
    exact (fieldRead_arrayV1 _ _ maxArrayElements r.items itemsB (nesting + 1) hsize
      (by decide) (Nat.le_trans hsize (by decide)) hall
      (fun x _ => exactMidOffsetInvertAt_requirementRequestV1 x (nesting + 1)
        (by omega)) hitems).read B
      (pre.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size)
      (pre ++ taggedHeaderBytesV1 "ProgramRequirements" 1) post
      (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have hbody := decodeProgramRequirementsBodyV1_eq_of_fields
    ⟨B, pre.size, nesting + 1⟩
    ⟨B, pre.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size, nesting + 1⟩
    ⟨B, pre.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size + itemsB.size,
      nesting + 1⟩
    r.items h0 h1
  simpa [ByteArray.size_append, Nat.add_assoc, hB] using hbody

theorem exactMidOffsetInvertAt_requirementsV1 (r : ProgramRequirementsV1) :
    ExactMidOffsetInvertAtV1 encodeProgramRequirementsV1
      decodeProgramRequirementsV1 r 1 :=
  exactMidOffsetInvertAt_of_fieldReadV1 (fun b henc =>
    fieldRead_programRequirementsV1 r b 1 (by decide) henc)

end ProofForgeV2.Semantic.WireV1
