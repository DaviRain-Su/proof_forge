import ProofForgeV2.Semantic.Wire.CodecInvertOpV1

/-!
  ProofForgeV2.Semantic.Wire.CodecInvertTermV1 — generic encode→decode
  invertibility for `JumpTargetV1`, `SwitchCaseV1`, trap codes, and every
  `TerminatorV1` constructor. `Term.Return` is discharged through the same
  FieldRead path as the other summands (reusing option/u32 leaves).
-/

namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common

private theorem toUTF8_size_eq_utf8ByteSize (s : String) :
    s.toUTF8.size = s.utf8ByteSize := rfl

/-! ### ASCII tags -/

theorem asciiTagBytes_JumpTargetV1 : isAsciiTagBytesV1 "JumpTarget".toUTF8 = true := by
  rw [show "JumpTarget".toUTF8 =
    ByteArray.mk #[74, 117, 109, 112, 84, 97, 114, 103, 101, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_SwitchCaseV1 : isAsciiTagBytesV1 "SwitchCase".toUTF8 = true := by
  rw [show "SwitchCase".toUTF8 =
    ByteArray.mk #[83, 119, 105, 116, 99, 104, 67, 97, 115, 101] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TermJumpV1 : isAsciiTagBytesV1 "Term.Jump".toUTF8 = true := by
  rw [show "Term.Jump".toUTF8 =
    ByteArray.mk #[84, 101, 114, 109, 46, 74, 117, 109, 112] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TermBranchV1 : isAsciiTagBytesV1 "Term.Branch".toUTF8 = true := by
  rw [show "Term.Branch".toUTF8 =
    ByteArray.mk #[84, 101, 114, 109, 46, 66, 114, 97, 110, 99, 104] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TermSwitchV1 : isAsciiTagBytesV1 "Term.Switch".toUTF8 = true := by
  rw [show "Term.Switch".toUTF8 =
    ByteArray.mk #[84, 101, 114, 109, 46, 83, 119, 105, 116, 99, 104] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TermReturnV1 : isAsciiTagBytesV1 "Term.Return".toUTF8 = true := by
  rw [show "Term.Return".toUTF8 =
    ByteArray.mk #[84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TermRevertV1 : isAsciiTagBytesV1 "Term.Revert".toUTF8 = true := by
  rw [show "Term.Revert".toUTF8 =
    ByteArray.mk #[84, 101, 114, 109, 46, 82, 101, 118, 101, 114, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TermTrapV1 : isAsciiTagBytesV1 "Term.Trap".toUTF8 = true := by
  rw [show "Term.Trap".toUTF8 =
    ByteArray.mk #[84, 101, 114, 109, 46, 84, 114, 97, 112] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TrapUnreachableV1 :
    isAsciiTagBytesV1 "Trap.Unreachable".toUTF8 = true := by
  rw [show "Trap.Unreachable".toUTF8 =
    ByteArray.mk #[84, 114, 97, 112, 46, 85, 110, 114, 101, 97, 99, 104, 97, 98, 108, 101]
      from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TrapInvalidExternalResponseV1 :
    isAsciiTagBytesV1 "Trap.InvalidExternalResponse".toUTF8 = true := by
  rw [show "Trap.InvalidExternalResponse".toUTF8 =
    ByteArray.mk #[84, 114, 97, 112, 46, 73, 110, 118, 97, 108, 105, 100, 69, 120, 116,
      101, 114, 110, 97, 108, 82, 101, 115, 112, 111, 110, 115, 101] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TrapResourceExhaustedV1 :
    isAsciiTagBytesV1 "Trap.ResourceExhausted".toUTF8 = true := by
  rw [show "Trap.ResourceExhausted".toUTF8 =
    ByteArray.mk #[84, 114, 97, 112, 46, 82, 101, 115, 111, 117, 114, 99, 101, 69, 120,
      104, 97, 117, 115, 116, 101, 100] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_TrapInternalInvariantV1 :
    isAsciiTagBytesV1 "Trap.InternalInvariant".toUTF8 = true := by
  rw [show "Trap.InternalInvariant".toUTF8 =
    ByteArray.mk #[84, 114, 97, 112, 46, 73, 110, 116, 101, 114, 110, 97, 108, 73, 110,
      118, 97, 114, 105, 97, 110, 116] from rfl]
  simp [isAsciiTagBytesV1]

/-! ### JumpTarget -/

theorem fieldRead_jumpTargetV1 (t : JumpTargetV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) (henc : encodeJumpTargetV1 t = .ok b) :
    FieldReadV1 decodeJumpTargetV1 b t nesting := by
  obtain ⟨argsB, hargs, htag⟩ := except_bind_ok_inversionV1 (encodeValueIdArray t.args)
    (fun argsB => encodeTagged "JumpTarget" #[encodeU32le t.blockId, argsB]) b henc
  have hb := encodeTagged_ok_eq_two_fieldsV1 "JumpTarget" (encodeU32le t.blockId) argsB
    b htag
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ hdepth
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "JumpTarget" 2 ++ encodeU32le t.blockId ++ argsB) ++
        post := ⟨_, rfl⟩
  rw [← hB]
  have h0 :=
    (fieldRead_expectTagV1 "JumpTarget" 2 (nesting + 1) (by decide) (by decide)
      (by decide) asciiTagBytes_JumpTargetV1 (by decide)).read B pre.size pre
      (encodeU32le t.blockId ++ argsB ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) rfl
  have h1 := (fieldRead_u32V1 t.blockId (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "JumpTarget" 2).size)
    (pre ++ taggedHeaderBytesV1 "JumpTarget" 2) (argsB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h2 := (fieldRead_u32ArrayV1 t.args argsB (nesting + 1) hargs).read B
    (pre.size + (taggedHeaderBytesV1 "JumpTarget" 2).size + (encodeU32le t.blockId).size)
    (pre ++ taggedHeaderBytesV1 "JumpTarget" 2 ++ encodeU32le t.blockId) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [h0, h1, h2, Bind.bind, Except.bind, Pure.pure, Except.pure]
  simp [ByteArray.size_append, Nat.add_assoc]

/-! ### SwitchCase -/

theorem fieldRead_switchCaseV1 (sc : SwitchCaseV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting) (henc : encodeSwitchCaseV1 sc = .ok b) :
    FieldReadV1 decodeSwitchCaseV1 b sc nesting := by
  obtain ⟨vb, hvb, hrest⟩ := except_bind_ok_inversionV1 (encodeByteArray sc.valueBytes)
    (fun vb => encodeJumpTargetV1 sc.target >>= fun tb =>
      encodeTagged "SwitchCase" #[encodeU32le sc.typeId, vb, tb]) b henc
  obtain ⟨tb, htb, htag⟩ := except_bind_ok_inversionV1 (encodeJumpTargetV1 sc.target)
    (fun tb => encodeTagged "SwitchCase" #[encodeU32le sc.typeId, vb, tb]) b hrest
  have hb := encodeTagged_ok_eq_three_fieldsV1 "SwitchCase" (encodeU32le sc.typeId) vb
    tb b htag
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ (Nat.lt_of_succ_lt hdepth)
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "SwitchCase" 3 ++ encodeU32le sc.typeId ++ vb ++ tb) ++
        post := ⟨_, rfl⟩
  rw [← hB]
  have h0 :=
    (fieldRead_expectTagV1 "SwitchCase" 3 (nesting + 1) (by decide) (by decide)
      (by decide) asciiTagBytes_SwitchCaseV1 (by decide)).read B pre.size pre
      (encodeU32le sc.typeId ++ vb ++ tb ++ post)
      (by rw [hB]; simp [ByteArray.append_assoc]) rfl
  have h1 := (fieldRead_u32V1 sc.typeId (nesting + 1)).read B
    (pre.size + (taggedHeaderBytesV1 "SwitchCase" 3).size)
    (pre ++ taggedHeaderBytesV1 "SwitchCase" 3) (vb ++ tb ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h2 := (fieldRead_byteArrayV1 sc.valueBytes vb (nesting + 1) hvb).read B
    (pre.size + (taggedHeaderBytesV1 "SwitchCase" 3).size + (encodeU32le sc.typeId).size)
    (pre ++ taggedHeaderBytesV1 "SwitchCase" 3 ++ encodeU32le sc.typeId) (tb ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_jumpTargetV1 sc.target tb (nesting + 1) (by omega) htb).read B
    (pre.size + (taggedHeaderBytesV1 "SwitchCase" 3).size + (encodeU32le sc.typeId).size +
      vb.size)
    (pre ++ taggedHeaderBytesV1 "SwitchCase" 3 ++ encodeU32le sc.typeId ++ vb) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [h0, h1, h2, h3, Bind.bind, Except.bind, Pure.pure, Except.pure]
  simp [ByteArray.size_append, Nat.add_assoc]

/-! ### Trap codes -/

def trapCodeTagV1 : SemanticTrapCodeV1 → String
  | .unreachable => "Trap.Unreachable"
  | .invalidExternalResponse => "Trap.InvalidExternalResponse"
  | .resourceExhausted => "Trap.ResourceExhausted"
  | .internalInvariant => "Trap.InternalInvariant"

theorem encodeTrapCode_eq_nullaryV1 (code : SemanticTrapCodeV1) :
    encodeSemanticTrapCodeV1 code = encodeNullary (trapCodeTagV1 code) := by
  cases code <;> rfl

theorem fieldRead_trapCodeV1 (code : SemanticTrapCodeV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) (henc : encodeSemanticTrapCodeV1 code = .ok b) :
    FieldReadV1 decodeSemanticTrapCodeV1 b code nesting := by
  have hnull : encodeNullary (trapCodeTagV1 code) = .ok b := by
    simpa [encodeTrapCode_eq_nullaryV1] using henc
  have hb := encodeNullary_ok_eq_headerV1 (trapCodeTagV1 code) b
    (by cases code <;> decide) (by cases code <;> decide) (by cases code <;> decide)
    hnull
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ hdepth
  intro pre post
  cases code with
  | unreachable =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Trap.Unreachable" 0 ++ post) pre.size pre post
        "Trap.Unreachable" 0 (nesting + 1) rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_TrapUnreachableV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Trap.Unreachable" 0 ++ post)
        (pre.size + 4 + "Trap.Unreachable".utf8ByteSize) pre post "Trap.Unreachable" 0
        (nesting + 1) rfl rfl (by decide)
      simp [trapCodeTagV1, h0, h1, Bind.bind, Except.bind, Pure.pure, Except.pure]
  | invalidExternalResponse =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Trap.InvalidExternalResponse" 0 ++ post) pre.size
        pre post "Trap.InvalidExternalResponse" 0 (nesting + 1) rfl rfl (by decide)
        (by decide) (by decide) asciiTagBytes_TrapInvalidExternalResponseV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Trap.InvalidExternalResponse" 0 ++ post)
        (pre.size + 4 + "Trap.InvalidExternalResponse".utf8ByteSize) pre post
        "Trap.InvalidExternalResponse" 0 (nesting + 1) rfl rfl (by decide)
      simp [trapCodeTagV1, h0, h1, Bind.bind, Except.bind, Pure.pure, Except.pure]
  | resourceExhausted =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Trap.ResourceExhausted" 0 ++ post) pre.size pre post
        "Trap.ResourceExhausted" 0 (nesting + 1) rfl rfl (by decide) (by decide)
        (by decide) asciiTagBytes_TrapResourceExhaustedV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Trap.ResourceExhausted" 0 ++ post)
        (pre.size + 4 + "Trap.ResourceExhausted".utf8ByteSize) pre post
        "Trap.ResourceExhausted" 0 (nesting + 1) rfl rfl (by decide)
      simp [trapCodeTagV1, h0, h1, Bind.bind, Except.bind, Pure.pure, Except.pure]
  | internalInvariant =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Trap.InternalInvariant" 0 ++ post) pre.size pre post
        "Trap.InternalInvariant" 0 (nesting + 1) rfl rfl (by decide) (by decide)
        (by decide) asciiTagBytes_TrapInternalInvariantV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Trap.InternalInvariant" 0 ++ post)
        (pre.size + 4 + "Trap.InternalInvariant".utf8ByteSize) pre post
        "Trap.InternalInvariant" 0 (nesting + 1) rfl rfl (by decide)
      simp [trapCodeTagV1, h0, h1, Bind.bind, Except.bind, Pure.pure, Except.pure]

/-! ### Terminator bodies -/

theorem fieldRead_terminatorBody_jumpV1 (target : JumpTargetV1) (b : ByteArray)
    (nesting : Nat) (hdepth : nesting < maxNesting)
    (henc : encodeTerminatorV1 (.jump target) = .ok b) :
    FieldReadV1 decodeTerminatorBodyV1 b (.jump target) nesting := by
  obtain ⟨tb, htb, htag⟩ := except_bind_ok_inversionV1 (encodeJumpTargetV1 target)
    (fun tb => encodeTagged "Term.Jump" #[tb]) b henc
  have hb := encodeTagged_ok_eq_one_fieldV1 "Term.Jump" tb b htag
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Term.Jump" 1 ++ tb) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre (tb ++ post) "Term.Jump" 1 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide) (by decide)
    asciiTagBytes_TermJumpV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Term.Jump".utf8ByteSize)
    pre (tb ++ post) "Term.Jump" 1 nesting (by rw [hB]; simp [ByteArray.append_assoc])
    rfl (by decide)
  have h2 := (fieldRead_jumpTargetV1 target tb nesting hdepth htb).read B
    (pre.size + (taggedHeaderBytesV1 "Term.Jump" 1).size)
    (pre ++ taggedHeaderBytesV1 "Term.Jump" 1) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeTerminatorBodyV1, h0, h1, h2,
    Bind.bind, Except.bind, Pure.pure, Except.pure]
  simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_terminatorBody_branchV1 (condition : ValueIdV1)
    (thenTarget elseTarget : JumpTargetV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (henc : encodeTerminatorV1 (.branch condition thenTarget elseTarget) = .ok b) :
    FieldReadV1 decodeTerminatorBodyV1 b (.branch condition thenTarget elseTarget)
      nesting := by
  obtain ⟨tB, htB, hrest⟩ := except_bind_ok_inversionV1 (encodeJumpTargetV1 thenTarget)
    (fun tB => encodeJumpTargetV1 elseTarget >>= fun eB =>
      encodeTagged "Term.Branch" #[encodeU32le condition, tB, eB]) b henc
  obtain ⟨eB, heB, htag⟩ := except_bind_ok_inversionV1 (encodeJumpTargetV1 elseTarget)
    (fun eB => encodeTagged "Term.Branch" #[encodeU32le condition, tB, eB]) b hrest
  have hb := encodeTagged_ok_eq_three_fieldsV1 "Term.Branch" (encodeU32le condition) tB
    eB b htag
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Term.Branch" 3 ++ encodeU32le condition ++ tB ++ eB) ++
        post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre
    (encodeU32le condition ++ tB ++ eB ++ post) "Term.Branch" 3 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide) (by decide)
    asciiTagBytes_TermBranchV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Term.Branch".utf8ByteSize)
    pre (encodeU32le condition ++ tB ++ eB ++ post) "Term.Branch" 3 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 condition nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Term.Branch" 3).size)
    (pre ++ taggedHeaderBytesV1 "Term.Branch" 3) (tB ++ eB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_jumpTargetV1 thenTarget tB nesting hdepth htB).read B
    (pre.size + (taggedHeaderBytesV1 "Term.Branch" 3).size + (encodeU32le condition).size)
    (pre ++ taggedHeaderBytesV1 "Term.Branch" 3 ++ encodeU32le condition) (eB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h4 := (fieldRead_jumpTargetV1 elseTarget eB nesting hdepth heB).read B
    (pre.size + (taggedHeaderBytesV1 "Term.Branch" 3).size + (encodeU32le condition).size +
      tB.size)
    (pre ++ taggedHeaderBytesV1 "Term.Branch" 3 ++ encodeU32le condition ++ tB) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeTerminatorBodyV1, h0, h1, h2, h3, h4,
    Bind.bind, Except.bind, Pure.pure, Except.pure]
  simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_terminatorBody_switchV1 (scrutinee : ValueIdV1)
    (cases : Array SwitchCaseV1) (defaultTarget : Option JumpTargetV1) (b : ByteArray)
    (nesting : Nat) (hdepth : nesting + 1 < maxNesting)
    (henc : encodeTerminatorV1 (.switch scrutinee cases defaultTarget) = .ok b) :
    FieldReadV1 decodeTerminatorBodyV1 b (.switch scrutinee cases defaultTarget)
      nesting := by
  obtain ⟨casesB, hcases, hrest⟩ :=
    except_bind_ok_inversionV1 (encodeArray encodeSwitchCaseV1 cases)
      (fun casesB => encodeOption encodeJumpTargetV1 defaultTarget >>= fun defB =>
        encodeTagged "Term.Switch" #[encodeU32le scrutinee, casesB, defB]) b henc
  obtain ⟨defB, hdef, htag⟩ :=
    except_bind_ok_inversionV1 (encodeOption encodeJumpTargetV1 defaultTarget)
      (fun defB => encodeTagged "Term.Switch" #[encodeU32le scrutinee, casesB, defB])
      b hrest
  have hb := encodeTagged_ok_eq_three_fieldsV1 "Term.Switch" (encodeU32le scrutinee)
    casesB defB b htag
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Term.Switch" 3 ++ encodeU32le scrutinee ++ casesB ++
        defB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre
    (encodeU32le scrutinee ++ casesB ++ defB ++ post) "Term.Switch" 3 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide) (by decide)
    asciiTagBytes_TermSwitchV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Term.Switch".utf8ByteSize)
    pre (encodeU32le scrutinee ++ casesB ++ defB ++ post) "Term.Switch" 3 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 scrutinee nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Term.Switch" 3).size)
    (pre ++ taggedHeaderBytesV1 "Term.Switch" 3) (casesB ++ defB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := by
    obtain ⟨hsize, hall⟩ := encodeArray_ok_inversionV1 _ cases casesB hcases
    exact (fieldRead_arrayV1 _ _ maxArrayElements cases casesB nesting hsize
      (by decide) (Nat.le_trans hsize (by decide)) hall
      (fun x _ => exactMidOffsetInvertAt_of_fieldReadV1
        (fun eb hx => fieldRead_switchCaseV1 x eb nesting hdepth hx)) hcases).read B
      (pre.size + (taggedHeaderBytesV1 "Term.Switch" 3).size +
        (encodeU32le scrutinee).size)
      (pre ++ taggedHeaderBytesV1 "Term.Switch" 3 ++ encodeU32le scrutinee)
      (defB ++ post) (by rw [hB]; simp [ByteArray.append_assoc])
      (by simp [ByteArray.size_append])
  have h4 := (fieldRead_optionV1 encodeJumpTargetV1 decodeJumpTargetV1 defaultTarget
      defB nesting hdef (fun x payload _ hx =>
        fieldRead_jumpTargetV1 x payload nesting (Nat.lt_of_succ_lt hdepth) hx)).read B
    (pre.size + (taggedHeaderBytesV1 "Term.Switch" 3).size +
      (encodeU32le scrutinee).size + casesB.size)
    (pre ++ taggedHeaderBytesV1 "Term.Switch" 3 ++ encodeU32le scrutinee ++ casesB) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeTerminatorBodyV1, h0, h1, h2, h3, h4,
    Bind.bind, Except.bind, Pure.pure, Except.pure]
  simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_terminatorBody_returnV1 (value : Option ValueIdV1) (b : ByteArray)
    (nesting : Nat) (henc : encodeTerminatorV1 (.return_ value) = .ok b) :
    FieldReadV1 decodeTerminatorBodyV1 b (.return_ value) nesting := by
  obtain ⟨vB, hvB, htag⟩ :=
    except_bind_ok_inversionV1 (encodeOption (fun id => pure (encodeU32le id)) value)
      (fun vB => encodeTagged "Term.Return" #[vB]) b henc
  have hb := encodeTagged_ok_eq_one_fieldV1 "Term.Return" vB b htag
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Term.Return" 1 ++ vB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre (vB ++ post) "Term.Return" 1 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide) (by decide)
    asciiTagBytes_TermReturnV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Term.Return".utf8ByteSize)
    pre (vB ++ post) "Term.Return" 1 nesting (by rw [hB]; simp [ByteArray.append_assoc])
    rfl (by decide)
  have h2 := (fieldRead_option_pureV1 encodeU32le decodeU32le value vB nesting hvB
      (fun x => fieldRead_u32V1 x nesting)).read B
    (pre.size + (taggedHeaderBytesV1 "Term.Return" 1).size)
    (pre ++ taggedHeaderBytesV1 "Term.Return" 1) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeTerminatorBodyV1, h0, h1, h2,
    Bind.bind, Except.bind, Pure.pure, Except.pure]
  simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_terminatorBody_revertV1 (errorId : ErrorIdV1) (args : Array ValueIdV1)
    (b : ByteArray) (nesting : Nat)
    (henc : encodeTerminatorV1 (.revert errorId args) = .ok b) :
    FieldReadV1 decodeTerminatorBodyV1 b (.revert errorId args) nesting := by
  obtain ⟨argsB, hargs, htag⟩ := except_bind_ok_inversionV1 (encodeValueIdArray args)
    (fun argsB => encodeTagged "Term.Revert" #[encodeU32le errorId, argsB]) b henc
  have hb := encodeTagged_ok_eq_two_fieldsV1 "Term.Revert" (encodeU32le errorId) argsB
    b htag
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Term.Revert" 2 ++ encodeU32le errorId ++ argsB) ++
        post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre (encodeU32le errorId ++ argsB ++ post)
    "Term.Revert" 2 nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl
    (by decide) (by decide) (by decide) asciiTagBytes_TermRevertV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Term.Revert".utf8ByteSize)
    pre (encodeU32le errorId ++ argsB ++ post) "Term.Revert" 2 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 errorId nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Term.Revert" 2).size)
    (pre ++ taggedHeaderBytesV1 "Term.Revert" 2) (argsB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_u32ArrayV1 args argsB nesting hargs).read B
    (pre.size + (taggedHeaderBytesV1 "Term.Revert" 2).size + (encodeU32le errorId).size)
    (pre ++ taggedHeaderBytesV1 "Term.Revert" 2 ++ encodeU32le errorId) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeTerminatorBodyV1, h0, h1, h2, h3,
    Bind.bind, Except.bind, Pure.pure, Except.pure]
  simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_terminatorBody_trapV1 (code : SemanticTrapCodeV1) (b : ByteArray)
    (nesting : Nat) (hdepth : nesting < maxNesting)
    (henc : encodeTerminatorV1 (.trap code) = .ok b) :
    FieldReadV1 decodeTerminatorBodyV1 b (.trap code) nesting := by
  obtain ⟨codeB, hcode, htag⟩ := except_bind_ok_inversionV1 (encodeSemanticTrapCodeV1 code)
    (fun codeB => encodeTagged "Term.Trap" #[codeB]) b henc
  have hb := encodeTagged_ok_eq_one_fieldV1 "Term.Trap" codeB b htag
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Term.Trap" 1 ++ codeB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre (codeB ++ post) "Term.Trap" 1 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide) (by decide)
    asciiTagBytes_TermTrapV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Term.Trap".utf8ByteSize)
    pre (codeB ++ post) "Term.Trap" 1 nesting (by rw [hB]; simp [ByteArray.append_assoc])
    rfl (by decide)
  have h2 := (fieldRead_trapCodeV1 code codeB nesting hdepth hcode).read B
    (pre.size + (taggedHeaderBytesV1 "Term.Trap" 1).size)
    (pre ++ taggedHeaderBytesV1 "Term.Trap" 1) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeTerminatorBodyV1, h0, h1, h2,
    Bind.bind, Except.bind, Pure.pure, Except.pure]
  simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_terminatorBodyV1 (term : TerminatorV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting)
    (henc : encodeTerminatorV1 term = .ok b) :
    FieldReadV1 decodeTerminatorBodyV1 b term nesting := by
  cases term with
  | jump target =>
      exact fieldRead_terminatorBody_jumpV1 target b nesting (Nat.lt_of_succ_lt hdepth)
        henc
  | branch condition thenTarget elseTarget =>
      exact fieldRead_terminatorBody_branchV1 condition thenTarget elseTarget b nesting
        (Nat.lt_of_succ_lt hdepth) henc
  | switch scrutinee cases defaultTarget =>
      exact fieldRead_terminatorBody_switchV1 scrutinee cases defaultTarget b nesting
        hdepth henc
  | return_ value =>
      exact fieldRead_terminatorBody_returnV1 value b nesting henc
  | revert errorId args =>
      exact fieldRead_terminatorBody_revertV1 errorId args b nesting henc
  | trap code =>
      exact fieldRead_terminatorBody_trapV1 code b nesting (Nat.lt_of_succ_lt hdepth)
        henc

theorem fieldRead_terminatorV1 (term : TerminatorV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting + 2 < maxNesting)
    (henc : encodeTerminatorV1 term = .ok b) :
    FieldReadV1 decodeTerminatorV1 b term nesting := by
  apply fieldRead_withTaggedNestingV1 _ _ _ _ (by omega)
  exact fieldRead_terminatorBodyV1 term b (nesting + 1) (by omega) henc

theorem exactMidOffsetInvertAt_terminatorV1 (term : TerminatorV1) (nesting : Nat)
    (hdepth : nesting + 2 < maxNesting) :
    ExactMidOffsetInvertAtV1 encodeTerminatorV1 decodeTerminatorV1 term nesting :=
  exactMidOffsetInvertAt_of_fieldReadV1
    (fun b henc => fieldRead_terminatorV1 term b nesting hdepth henc)

end ProofForgeV2.Semantic.WireV1
