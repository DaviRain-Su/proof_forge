import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Semantic.Wire.CodecRoundtripV1
import ProofForgeV2.Semantic.Wire.CodecInvertV1
import Init.Data.ByteArray.Lemmas
import Init.Data.Array.Lemmas

/-!
  ProofForgeV2.Semantic.Wire.CodecInvertRootV1 — mig-a1-root

  Closes the composition half of `DecodeEncodeRoundtripGoalV1`:

    encodeSemanticProgramDataV1 data = .ok bytes →
      RootFieldInvertV1 data →
        decodeSemanticProgramDataV1 bytes = .ok data

  under mid-offset invertibility of the nine root field codecs.

  Hard boundaries:
    * no axiom / sorry / native_decide / ofReduceBool
    * no second encoder or structure-gate bypass
    * sole production encode/decode authorities
    * does **not** discharge RootFieldInvert for arbitrary programs
      (field-family invert remains per-field; composition is the residual closed here)
-/

set_option maxHeartbeats 4000000

namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common

/-! ### SemanticProgram.Data tag certificates -/

private theorem utf8_SemanticProgram_Data :
    "SemanticProgram.Data".toUTF8 =
      ByteArray.mk #[83, 101, 109, 97, 110, 116, 105, 99, 80, 114, 111, 103, 114, 97,
        109, 46, 68, 97, 116, 97] := by
  rfl

private theorem isAsciiTagBytes_SemanticProgram_Data :
    isAsciiTagBytesV1 "SemanticProgram.Data".toUTF8 = true := by
  rw [utf8_SemanticProgram_Data]
  exact isAsciiTagBytes_of_list_all
    [83, 101, 109, 97, 110, 116, 105, 99, 80, 114, 111, 103, 114, 97, 109, 46, 68, 97,
      116, 97]
    (by decide)

private theorem tag_SemanticProgram_Data_size :
    "SemanticProgram.Data".toUTF8.size = 20 := by decide

private abbrev semanticProgramDataHeaderSizeV1 : Nat := 26

private theorem header_size_SemanticProgram_Data :
    (taggedHeaderBytesV1 "SemanticProgram.Data" 9).size =
      semanticProgramDataHeaderSizeV1 := by
  simp only [taggedHeaderBytesV1_size, tag_SemanticProgram_Data_size,
    semanticProgramDataHeaderSizeV1]

/-! ### Nine-field tagged layout -/

private theorem appendTaggedFields_nine
    (init f0 f1 f2 f3 f4 f5 f6 f7 f8 : ByteArray) :
    appendTaggedFieldsV1 init #[f0, f1, f2, f3, f4, f5, f6, f7, f8] =
      init ++ f0 ++ f1 ++ f2 ++ f3 ++ f4 ++ f5 ++ f6 ++ f7 ++ f8 := by
  simp [appendTaggedFieldsV1]

theorem taggedBytes_SemanticProgram_Data_nine
    (f0 f1 f2 f3 f4 f5 f6 f7 f8 : ByteArray) :
    taggedBytesV1 "SemanticProgram.Data" #[f0, f1, f2, f3, f4, f5, f6, f7, f8] =
      taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++
        f0 ++ f1 ++ f2 ++ f3 ++ f4 ++ f5 ++ f6 ++ f7 ++ f8 := by
  have h := taggedBytesV1_eq_header_payload "SemanticProgram.Data"
    #[f0, f1, f2, f3, f4, f5, f6, f7, f8]
  have hfold :
      (#[f0, f1, f2, f3, f4, f5, f6, f7, f8] : Array ByteArray).foldl
          (fun out f => out.append f) ByteArray.empty =
        f0 ++ f1 ++ f2 ++ f3 ++ f4 ++ f5 ++ f6 ++ f7 ++ f8 := by
    simp [List.foldl]
  have hsz : (#[f0, f1, f2, f3, f4, f5, f6, f7, f8] : Array ByteArray).size = 9 := rfl
  rw [h, hfold, hsz]
  simp [ByteArray.append_assoc]

theorem encodeTagged_SemanticProgram_Data_nine_ok
    (f0 f1 f2 f3 f4 f5 f6 f7 f8 body : ByteArray)
    (h : encodeTagged "SemanticProgram.Data"
      #[f0, f1, f2, f3, f4, f5, f6, f7, f8] = .ok body) :
    body =
      taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++
        f0 ++ f1 ++ f2 ++ f3 ++ f4 ++ f5 ++ f6 ++ f7 ++ f8 := by
  have htag := encodeTagged_ok_eq_taggedBytesV1 "SemanticProgram.Data"
    #[f0, f1, f2, f3, f4, f5, f6, f7, f8] body h
  exact htag.1.trans
    (taggedBytes_SemanticProgram_Data_nine f0 f1 f2 f3 f4 f5 f6 f7 f8)

/-! ### Root field-path success package -/

/-- Production field-byte witness from a successful sole body encode. -/
structure RootEncodeFieldsOkV1 (data : SemanticProgramDataV1) (b : ByteArray) where
  qnB : ByteArray
  typesB : ByteArray
  constantsB : ByteArray
  stateB : ByteArray
  eventsB : ByteArray
  errorsB : ByteArray
  callablesB : ByteArray
  invariantsB : ByteArray
  requirementsB : ByteArray
  body : ByteArray
  hqn : encodeQualifiedName data.qualifiedName = .ok qnB
  htypes : encodeArray encodeTypeDeclV1 data.types = .ok typesB
  hconstants : encodeArray encodeConstantV1 data.constants = .ok constantsB
  hstate : encodeArray encodeStateDeclV1 data.logicalState = .ok stateB
  hevents : encodeArray encodeEventDeclV1 data.events = .ok eventsB
  herrors : encodeArray encodeErrorDeclV1 data.errors = .ok errorsB
  hcallables : encodeArray encodeCallableV1 data.callables = .ok callablesB
  hinvariants : encodeArray encodeInvariantDeclV1 data.invariants = .ok invariantsB
  hrequirements : encodeProgramRequirementsV1 data.requirements = .ok requirementsB
  hbody : encodeTagged "SemanticProgram.Data"
      #[qnB, typesB, constantsB, stateB, eventsB, errorsB, callablesB,
        invariantsB, requirementsB] = .ok body
  hb : b = encodeMagicPrefix semanticProgramMagicV1 ++ body
  hsize : b.size ≤ maxCanonicalProgramBytes

/-- Invert sole body encode success into field bytes + framing. -/
def rootEncodeFieldsOk_of_body
    (data : SemanticProgramDataV1) (b : ByteArray)
    (h : encodeSemanticProgramDataBodyV1 data = .ok b) :
    RootEncodeFieldsOkV1 data b := by
  simp only [encodeSemanticProgramDataBodyV1] at h
  cases hqn : encodeQualifiedName data.qualifiedName with
  | error e => simp [hqn, Bind.bind, Except.bind] at h
  | ok qnB =>
  cases htypes : encodeArray encodeTypeDeclV1 data.types with
  | error e => simp [hqn, htypes, Bind.bind, Except.bind] at h
  | ok typesB =>
  cases hconst : encodeArray encodeConstantV1 data.constants with
  | error e => simp [hqn, htypes, hconst, Bind.bind, Except.bind] at h
  | ok constantsB =>
  cases hstate : encodeArray encodeStateDeclV1 data.logicalState with
  | error e => simp [hqn, htypes, hconst, hstate, Bind.bind, Except.bind] at h
  | ok stateB =>
  cases hevents : encodeArray encodeEventDeclV1 data.events with
  | error e => simp [hqn, htypes, hconst, hstate, hevents, Bind.bind, Except.bind] at h
  | ok eventsB =>
  cases herrors : encodeArray encodeErrorDeclV1 data.errors with
  | error e =>
      simp [hqn, htypes, hconst, hstate, hevents, herrors, Bind.bind, Except.bind] at h
  | ok errorsB =>
  cases hcall : encodeArray encodeCallableV1 data.callables with
  | error e =>
      simp [hqn, htypes, hconst, hstate, hevents, herrors, hcall, Bind.bind,
        Except.bind] at h
  | ok callablesB =>
  cases hinv : encodeArray encodeInvariantDeclV1 data.invariants with
  | error e =>
      simp [hqn, htypes, hconst, hstate, hevents, herrors, hcall, hinv, Bind.bind,
        Except.bind] at h
  | ok invariantsB =>
  cases hreq : encodeProgramRequirementsV1 data.requirements with
  | error e =>
      simp [hqn, htypes, hconst, hstate, hevents, herrors, hcall, hinv, hreq,
        Bind.bind, Except.bind] at h
  | ok requirementsB =>
  cases hbody : encodeTagged "SemanticProgram.Data"
      #[qnB, typesB, constantsB, stateB, eventsB, errorsB, callablesB, invariantsB,
        requirementsB] with
  | error e =>
      simp [hqn, htypes, hconst, hstate, hevents, herrors, hcall, hinv, hreq, hbody,
        Bind.bind, Except.bind] at h
  | ok body =>
  simp [hqn, htypes, hconst, hstate, hevents, herrors, hcall, hinv, hreq, hbody,
    Bind.bind, Pure.pure, Except.bind, Except.pure, err] at h
  by_cases hs :
      (encodeMagicPrefix semanticProgramMagicV1).size + body.size ≤
        maxCanonicalProgramBytes
  · simp only [hs, ↓reduceIte, Except.ok.injEq] at h
    exact {
      qnB := qnB, typesB := typesB, constantsB := constantsB, stateB := stateB,
      eventsB := eventsB, errorsB := errorsB, callablesB := callablesB,
      invariantsB := invariantsB, requirementsB := requirementsB, body := body,
      hqn := hqn, htypes := htypes, hconstants := hconst, hstate := hstate,
      hevents := hevents, herrors := herrors, hcallables := hcall,
      hinvariants := hinv, hrequirements := hreq, hbody := hbody,
      hb := by simpa [ByteArray.append_eq] using h.symm
      hsize := by
        have hb' : b = encodeMagicPrefix semanticProgramMagicV1 ++ body := by
          simpa [ByteArray.append_eq] using h.symm
        rw [hb', ByteArray.size_append]
        exact hs
    }
  · simp only [hs, ↓reduceIte] at h
    cases h

private theorem except_bind_unit_ok {ε α}
    {x : Except ε Unit} {y : Except ε α} {a : α}
    (h : x >>= (fun _ => y) = .ok a) : x = .ok () ∧ y = .ok a := by
  cases x with
  | error e =>
      simp only [Bind.bind, Except.bind] at h
      cases h
  | ok u =>
      cases u
      simp only [Bind.bind, Except.bind] at h
      exact ⟨rfl, h⟩

/-- Successful structure-gated root encode implies sole body encode of the same
    bytes. -/
theorem encodeSemanticProgramDataV1_ok_implies_body
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (h : encodeSemanticProgramDataV1 data = .ok bytes) :
    encodeSemanticProgramDataBodyV1 data = .ok bytes := by
  simp only [encodeSemanticProgramDataV1] at h
  obtain ⟨_, h⟩ := except_bind_unit_ok h
  obtain ⟨_, h⟩ := except_bind_unit_ok h
  obtain ⟨_, h⟩ := except_bind_unit_ok h
  obtain ⟨_, h⟩ := except_bind_unit_ok h
  obtain ⟨_, h⟩ := except_bind_unit_ok h
  obtain ⟨_, h⟩ := except_bind_unit_ok h
  obtain ⟨_, h⟩ := except_bind_unit_ok h
  obtain ⟨_, h⟩ := except_bind_unit_ok h
  obtain ⟨_, h⟩ := except_bind_unit_ok h
  exact h

/-- Root encode success ⇒ field-path package. -/
def rootEncodeFieldsOk_of_encode
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (h : encodeSemanticProgramDataV1 data = .ok bytes) :
    RootEncodeFieldsOkV1 data bytes :=
  rootEncodeFieldsOk_of_body data bytes
    (encodeSemanticProgramDataV1_ok_implies_body data bytes h)

theorem rootEncodeFieldsOk_body_eq
    (data : SemanticProgramDataV1) (b : ByteArray)
    (fok : RootEncodeFieldsOkV1 data b) :
    fok.body =
      taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++
        fok.qnB ++ fok.typesB ++ fok.constantsB ++ fok.stateB ++
        fok.eventsB ++ fok.errorsB ++ fok.callablesB ++
        fok.invariantsB ++ fok.requirementsB :=
  encodeTagged_SemanticProgram_Data_nine_ok
    fok.qnB fok.typesB fok.constantsB fok.stateB fok.eventsB fok.errorsB
    fok.callablesB fok.invariantsB fok.requirementsB fok.body fok.hbody

/-! ### Cursor offsets after magic + header + successive fields

    Offsets are pure Nat functions of field byte sizes (no `b` dependency), so
    layout rewrites never hit motive/type-correctness issues.
-/

private abbrev magicSizeV1 : Nat := (encodeMagicPrefix semanticProgramMagicV1).size

private def oTagV1 : Nat := magicSizeV1 + semanticProgramDataHeaderSizeV1

private def oTypesV1 (qnB : ByteArray) : Nat := oTagV1 + qnB.size
private def oConstV1 (qnB typesB : ByteArray) : Nat :=
  oTypesV1 qnB + typesB.size
private def oStateV1 (qnB typesB constantsB : ByteArray) : Nat :=
  oConstV1 qnB typesB + constantsB.size
private def oEventsV1 (qnB typesB constantsB stateB : ByteArray) : Nat :=
  oStateV1 qnB typesB constantsB + stateB.size
private def oErrorsV1 (qnB typesB constantsB stateB eventsB : ByteArray) : Nat :=
  oEventsV1 qnB typesB constantsB stateB + eventsB.size
private def oCallablesV1
    (qnB typesB constantsB stateB eventsB errorsB : ByteArray) : Nat :=
  oErrorsV1 qnB typesB constantsB stateB eventsB + errorsB.size
private def oInvariantsV1
    (qnB typesB constantsB stateB eventsB errorsB callablesB : ByteArray) : Nat :=
  oCallablesV1 qnB typesB constantsB stateB eventsB errorsB + callablesB.size
private def oRequirementsV1
    (qnB typesB constantsB stateB eventsB errorsB callablesB invariantsB :
      ByteArray) : Nat :=
  oInvariantsV1 qnB typesB constantsB stateB eventsB errorsB callablesB +
    invariantsB.size
private def oEndV1
    (qnB typesB constantsB stateB eventsB errorsB callablesB invariantsB
      requirementsB : ByteArray) : Nat :=
  oRequirementsV1 qnB typesB constantsB stateB eventsB errorsB callablesB
      invariantsB + requirementsB.size

theorem rootEncodeFieldsOk_end_offset
    (data : SemanticProgramDataV1) (b : ByteArray)
    (fok : RootEncodeFieldsOkV1 data b) :
    oEndV1 fok.qnB fok.typesB fok.constantsB fok.stateB fok.eventsB fok.errorsB
        fok.callablesB fok.invariantsB fok.requirementsB =
      b.size := by
  -- Project field bytes first so layout equalities never abstract under `fok`.
  let qnB := fok.qnB
  let typesB := fok.typesB
  let constantsB := fok.constantsB
  let stateB := fok.stateB
  let eventsB := fok.eventsB
  let errorsB := fok.errorsB
  let callablesB := fok.callablesB
  let invariantsB := fok.invariantsB
  let requirementsB := fok.requirementsB
  let body := fok.body
  have hb : b = encodeMagicPrefix semanticProgramMagicV1 ++ body := by
    simpa [ByteArray.append_eq, body] using fok.hb
  have hbody :
      body =
        taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++
          qnB ++ typesB ++ constantsB ++ stateB ++ eventsB ++ errorsB ++
          callablesB ++ invariantsB ++ requirementsB := by
    simpa [body, qnB, typesB, constantsB, stateB, eventsB, errorsB, callablesB,
      invariantsB, requirementsB] using rootEncodeFieldsOk_body_eq data b fok
  have hhs := header_size_SemanticProgram_Data
  have hlayout :
      b =
        encodeMagicPrefix semanticProgramMagicV1 ++
          taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++
          qnB ++ typesB ++ constantsB ++ stateB ++ eventsB ++ errorsB ++
          callablesB ++ invariantsB ++ requirementsB := by
    calc
      b = encodeMagicPrefix semanticProgramMagicV1 ++ body := hb
      _ = encodeMagicPrefix semanticProgramMagicV1 ++
            (taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++
              qnB ++ typesB ++ constantsB ++ stateB ++ eventsB ++ errorsB ++
              callablesB ++ invariantsB ++ requirementsB) := by rw [hbody]
      _ = encodeMagicPrefix semanticProgramMagicV1 ++
            taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++
            qnB ++ typesB ++ constantsB ++ stateB ++ eventsB ++ errorsB ++
            callablesB ++ invariantsB ++ requirementsB := by
        simp only [ByteArray.append_assoc]
  -- Expand oEndV1 and close via size_append on the projected layout.
  change
    (encodeMagicPrefix semanticProgramMagicV1).size +
        semanticProgramDataHeaderSizeV1 +
        qnB.size + typesB.size + constantsB.size + stateB.size + eventsB.size +
        errorsB.size + callablesB.size + invariantsB.size + requirementsB.size =
      b.size
  have hsz := congrArg ByteArray.size hlayout
  -- Goal: size-sum = b.size  →  size-sum = layout.size
  rw [hsz]
  simp only [ByteArray.size_append, hhs]

/-! ### expectTag + nine field mid-decodes under RootFieldInvert -/

theorem expectTag_of_rootEncodeFieldsOk
    (data : SemanticProgramDataV1) (b : ByteArray)
    (fok : RootEncodeFieldsOkV1 data b) (nesting : Nat) :
    expectTag "SemanticProgram.Data" 9 ⟨b, magicSizeV1, nesting⟩ =
      .ok ((), ⟨b, oTagV1, nesting⟩) := by
  let qnB := fok.qnB
  let typesB := fok.typesB
  let constantsB := fok.constantsB
  let stateB := fok.stateB
  let eventsB := fok.eventsB
  let errorsB := fok.errorsB
  let callablesB := fok.callablesB
  let invariantsB := fok.invariantsB
  let requirementsB := fok.requirementsB
  let body := fok.body
  have hb : b = encodeMagicPrefix semanticProgramMagicV1 ++ body := by
    simpa [ByteArray.append_eq, body] using fok.hb
  have hbody :
      body =
        taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++
          qnB ++ typesB ++ constantsB ++ stateB ++ eventsB ++ errorsB ++
          callablesB ++ invariantsB ++ requirementsB := by
    simpa [body, qnB, typesB, constantsB, stateB, eventsB, errorsB, callablesB,
      invariantsB, requirementsB] using rootEncodeFieldsOk_body_eq data b fok
  let rest :=
    qnB ++ typesB ++ constantsB ++ stateB ++ eventsB ++ errorsB ++ callablesB ++
      invariantsB ++ requirementsB
  have hin :
      b =
        encodeMagicPrefix semanticProgramMagicV1 ++
          taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++ rest := by
    calc
      b = encodeMagicPrefix semanticProgramMagicV1 ++ body := hb
      _ = encodeMagicPrefix semanticProgramMagicV1 ++
            (taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++ rest) := by
        rw [hbody]; simp only [rest, ByteArray.append_assoc]
      _ = encodeMagicPrefix semanticProgramMagicV1 ++
            taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++ rest := by
        simp only [ByteArray.append_assoc]
  have hmid :=
    expectTag_encode_midV1 (encodeMagicPrefix semanticProgramMagicV1)
      ByteArray.empty "SemanticProgram.Data" 9 rest nesting
      (by decide) (by decide) (by decide) isAsciiTagBytes_SemanticProgram_Data
      (by decide)
  have hflat :
      encodeMagicPrefix semanticProgramMagicV1 ++
          taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++ rest ++
          ByteArray.empty =
        encodeMagicPrefix semanticProgramMagicV1 ++
          taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++ rest := by
    simp [ByteArray.append_empty]
  have hsz :
      (encodeMagicPrefix semanticProgramMagicV1).size +
          (taggedHeaderBytesV1 "SemanticProgram.Data" 9).size =
        oTagV1 := by
    simp only [oTagV1, magicSizeV1, header_size_SemanticProgram_Data]
  have hmid' :
      expectTag "SemanticProgram.Data" 9
          ⟨encodeMagicPrefix semanticProgramMagicV1 ++
              taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++ rest,
            (encodeMagicPrefix semanticProgramMagicV1).size, nesting⟩ =
        .ok ((),
          ⟨encodeMagicPrefix semanticProgramMagicV1 ++
              taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++ rest,
            (encodeMagicPrefix semanticProgramMagicV1).size +
              (taggedHeaderBytesV1 "SemanticProgram.Data" 9).size,
            nesting⟩) := by
    simpa [hflat] using hmid
  have hgoal :
      expectTag "SemanticProgram.Data" 9
          ⟨encodeMagicPrefix semanticProgramMagicV1 ++
              taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++ rest,
            magicSizeV1, nesting⟩ =
        .ok ((),
          ⟨encodeMagicPrefix semanticProgramMagicV1 ++
              taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++ rest,
            oTagV1, nesting⟩) := by
    simpa [magicSizeV1, hsz] using hmid'
  -- `hin` only mentions plain ByteArrays (projected locals), so rewrite is safe.
  rw [hin]
  exact hgoal

private theorem mid_field
    (b : ByteArray) (decode : Decoder α) (val : α) (fieldB left right : ByteArray)
    (nesting : Nat) (offset next : Nat)
    (hin : b = left ++ fieldB ++ right)
    (hL : left.size = offset)
    (hoff : offset + fieldB.size = next)
    (hdec :
      decode ⟨left ++ fieldB ++ right, left.size, nesting⟩ =
        .ok (val, ⟨left ++ fieldB ++ right, left.size + fieldB.size, nesting⟩)) :
    decode ⟨b, offset, nesting⟩ = .ok (val, ⟨b, next, nesting⟩) := by
  have h := hdec
  rw [← hin, hL, hoff] at h
  exact h

/-- Flat full-buffer layout under FieldsOk. -/
private theorem rootEncodeFieldsOk_flat_layout
    (data : SemanticProgramDataV1) (b : ByteArray)
    (fok : RootEncodeFieldsOkV1 data b) :
    b =
      encodeMagicPrefix semanticProgramMagicV1 ++
        taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++
        fok.qnB ++ fok.typesB ++ fok.constantsB ++ fok.stateB ++
        fok.eventsB ++ fok.errorsB ++ fok.callablesB ++
        fok.invariantsB ++ fok.requirementsB := by
  let qnB := fok.qnB
  let typesB := fok.typesB
  let constantsB := fok.constantsB
  let stateB := fok.stateB
  let eventsB := fok.eventsB
  let errorsB := fok.errorsB
  let callablesB := fok.callablesB
  let invariantsB := fok.invariantsB
  let requirementsB := fok.requirementsB
  let body := fok.body
  have hb : b = encodeMagicPrefix semanticProgramMagicV1 ++ body := by
    simpa [ByteArray.append_eq, body] using fok.hb
  have hbody :
      body =
        taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++
          qnB ++ typesB ++ constantsB ++ stateB ++ eventsB ++ errorsB ++
          callablesB ++ invariantsB ++ requirementsB := by
    simpa [body, qnB, typesB, constantsB, stateB, eventsB, errorsB, callablesB,
      invariantsB, requirementsB] using rootEncodeFieldsOk_body_eq data b fok
  have h :
      b =
        encodeMagicPrefix semanticProgramMagicV1 ++
          taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++
          qnB ++ typesB ++ constantsB ++ stateB ++ eventsB ++ errorsB ++
          callablesB ++ invariantsB ++ requirementsB := by
    calc
      b = encodeMagicPrefix semanticProgramMagicV1 ++ body := hb
      _ = encodeMagicPrefix semanticProgramMagicV1 ++
            (taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++
              qnB ++ typesB ++ constantsB ++ stateB ++ eventsB ++ errorsB ++
              callablesB ++ invariantsB ++ requirementsB) := by rw [hbody]
      _ = encodeMagicPrefix semanticProgramMagicV1 ++
            taggedHeaderBytesV1 "SemanticProgram.Data" 9 ++
            qnB ++ typesB ++ constantsB ++ stateB ++ eventsB ++ errorsB ++
            callablesB ++ invariantsB ++ requirementsB := by
        simp only [ByteArray.append_assoc]
  simpa [qnB, typesB, constantsB, stateB, eventsB, errorsB, callablesB,
    invariantsB, requirementsB] using h

/-- Nine-field tagged body transport decode under RootFieldInvert + FieldsOk. -/
theorem decodeSemanticProgramDataTagged_of_rootFieldInvert
    (data : SemanticProgramDataV1) (b : ByteArray)
    (fok : RootEncodeFieldsOkV1 data b)
    (hinvert : RootFieldInvertV1 data) :
    decodeSemanticProgramDataTaggedV1 ⟨b, magicSizeV1, 0⟩ =
      .ok (data, ⟨b, b.size, 0⟩) := by
  have hdepth : (0 : Nat) < maxNesting := by decide
  have htag := expectTag_of_rootEncodeFieldsOk data b fok 1
  have hlayout := rootEncodeFieldsOk_flat_layout data b fok
  -- Bind field sizes into local Nats.
  let qnB := fok.qnB
  let typesB := fok.typesB
  let constantsB := fok.constantsB
  let stateB := fok.stateB
  let eventsB := fok.eventsB
  let errorsB := fok.errorsB
  let callablesB := fok.callablesB
  let invariantsB := fok.invariantsB
  let requirementsB := fok.requirementsB
  let ot := oTagV1
  let oty := oTypesV1 qnB
  let oc := oConstV1 qnB typesB
  let os := oStateV1 qnB typesB constantsB
  let oev := oEventsV1 qnB typesB constantsB stateB
  let oer := oErrorsV1 qnB typesB constantsB stateB eventsB
  let oca := oCallablesV1 qnB typesB constantsB stateB eventsB errorsB
  let oin := oInvariantsV1 qnB typesB constantsB stateB eventsB errorsB callablesB
  let oreq :=
    oRequirementsV1 qnB typesB constantsB stateB eventsB errorsB callablesB
      invariantsB
  let oend :=
    oEndV1 qnB typesB constantsB stateB eventsB errorsB callablesB invariantsB
      requirementsB
  -- QN
  let Lqn :=
    encodeMagicPrefix semanticProgramMagicV1 ++
      taggedHeaderBytesV1 "SemanticProgram.Data" 9
  let Rqn :=
    typesB ++ constantsB ++ stateB ++ eventsB ++ errorsB ++ callablesB ++
      invariantsB ++ requirementsB
  have hinQn : b = Lqn ++ qnB ++ Rqn := by
    simpa [Lqn, Rqn, qnB, typesB, constantsB, stateB, eventsB, errorsB,
      callablesB, invariantsB, requirementsB, ByteArray.append_assoc] using hlayout
  have hLqn : Lqn.size = ot := by
    simp only [Lqn, ot, oTagV1, magicSizeV1, ByteArray.size_append,
      header_size_SemanticProgram_Data]
  have hname :=
    mid_field b decodeQualifiedName data.qualifiedName qnB Lqn Rqn 1 ot oty
      hinQn hLqn (by simp only [oty, oTypesV1, ot, oTagV1])
      (by
        have h := hinvert.qualifiedName qnB Lqn Rqn
          (by simpa [qnB] using fok.hqn)
        exact h)
  -- types
  let Ltypes := Lqn ++ qnB
  let Rtypes :=
    constantsB ++ stateB ++ eventsB ++ errorsB ++ callablesB ++ invariantsB ++
      requirementsB
  have hinTypes : b = Ltypes ++ typesB ++ Rtypes := by
    simpa [Ltypes, Lqn, Rtypes, qnB, typesB, constantsB, stateB, eventsB, errorsB,
      callablesB, invariantsB, requirementsB, ByteArray.append_assoc] using hlayout
  have hLtypes : Ltypes.size = oty := by
    simp only [Ltypes, Lqn, oty, oTypesV1, ot, oTagV1, magicSizeV1,
      ByteArray.size_append, header_size_SemanticProgram_Data]
  have htypes :=
    mid_field b (decodeArray maxTableElements decodeTypeDeclV1) data.types typesB
      Ltypes Rtypes 1 oty oc hinTypes hLtypes
      (by simp only [oc, oConstV1, oty, oTypesV1])
      (hinvert.types typesB Ltypes Rtypes
        (by simpa [typesB] using fok.htypes))
  -- constants
  let Lconst := Ltypes ++ typesB
  let Rconst :=
    stateB ++ eventsB ++ errorsB ++ callablesB ++ invariantsB ++ requirementsB
  have hinConst : b = Lconst ++ constantsB ++ Rconst := by
    simpa [Lconst, Ltypes, Lqn, Rconst, qnB, typesB, constantsB, stateB, eventsB,
      errorsB, callablesB, invariantsB, requirementsB, ByteArray.append_assoc]
      using hlayout
  have hLconst : Lconst.size = oc := by
    simp only [Lconst, Ltypes, Lqn, oc, oConstV1, oty, oTypesV1, ot, oTagV1,
      magicSizeV1, ByteArray.size_append, header_size_SemanticProgram_Data]
  have hconst :=
    mid_field b (decodeArray maxTableElements decodeConstantV1) data.constants
      constantsB Lconst Rconst 1 oc os hinConst hLconst
      (by simp only [os, oStateV1, oc, oConstV1])
      (hinvert.constants constantsB Lconst Rconst
        (by simpa [constantsB] using fok.hconstants))
  -- state
  let Lstate := Lconst ++ constantsB
  let Rstate := eventsB ++ errorsB ++ callablesB ++ invariantsB ++ requirementsB
  have hinState : b = Lstate ++ stateB ++ Rstate := by
    simpa [Lstate, Lconst, Ltypes, Lqn, Rstate, qnB, typesB, constantsB, stateB,
      eventsB, errorsB, callablesB, invariantsB, requirementsB,
      ByteArray.append_assoc] using hlayout
  have hLstate : Lstate.size = os := by
    simp only [Lstate, Lconst, Ltypes, Lqn, os, oStateV1, oc, oConstV1, oty,
      oTypesV1, ot, oTagV1, magicSizeV1, ByteArray.size_append,
      header_size_SemanticProgram_Data]
  have hstate :=
    mid_field b (decodeArray maxTableElements decodeStateDeclV1) data.logicalState
      stateB Lstate Rstate 1 os oev hinState hLstate
      (by simp only [oev, oEventsV1, os, oStateV1])
      (hinvert.logicalState stateB Lstate Rstate
        (by simpa [stateB] using fok.hstate))
  -- events
  let Levents := Lstate ++ stateB
  let Revents := errorsB ++ callablesB ++ invariantsB ++ requirementsB
  have hinEvents : b = Levents ++ eventsB ++ Revents := by
    simpa [Levents, Lstate, Lconst, Ltypes, Lqn, Revents, qnB, typesB, constantsB,
      stateB, eventsB, errorsB, callablesB, invariantsB, requirementsB,
      ByteArray.append_assoc] using hlayout
  have hLevents : Levents.size = oev := by
    simp only [Levents, Lstate, Lconst, Ltypes, Lqn, oev, oEventsV1, os, oStateV1,
      oc, oConstV1, oty, oTypesV1, ot, oTagV1, magicSizeV1, ByteArray.size_append,
      header_size_SemanticProgram_Data]
  have hevents :=
    mid_field b (decodeArray maxTableElements decodeEventDeclV1) data.events
      eventsB Levents Revents 1 oev oer hinEvents hLevents
      (by simp only [oer, oErrorsV1, oev, oEventsV1])
      (hinvert.events eventsB Levents Revents
        (by simpa [eventsB] using fok.hevents))
  -- errors
  let Lerrors := Levents ++ eventsB
  let Rerrors := callablesB ++ invariantsB ++ requirementsB
  have hinErrors : b = Lerrors ++ errorsB ++ Rerrors := by
    simpa [Lerrors, Levents, Lstate, Lconst, Ltypes, Lqn, Rerrors, qnB, typesB,
      constantsB, stateB, eventsB, errorsB, callablesB, invariantsB, requirementsB,
      ByteArray.append_assoc] using hlayout
  have hLerrors : Lerrors.size = oer := by
    simp only [Lerrors, Levents, Lstate, Lconst, Ltypes, Lqn, oer, oErrorsV1, oev,
      oEventsV1, os, oStateV1, oc, oConstV1, oty, oTypesV1, ot, oTagV1,
      magicSizeV1, ByteArray.size_append, header_size_SemanticProgram_Data]
  have herrors :=
    mid_field b (decodeArray maxTableElements decodeErrorDeclV1) data.errors
      errorsB Lerrors Rerrors 1 oer oca hinErrors hLerrors
      (by simp only [oca, oCallablesV1, oer, oErrorsV1])
      (hinvert.errors errorsB Lerrors Rerrors
        (by simpa [errorsB] using fok.herrors))
  -- callables
  let Lcall := Lerrors ++ errorsB
  let Rcall := invariantsB ++ requirementsB
  have hinCall : b = Lcall ++ callablesB ++ Rcall := by
    simpa [Lcall, Lerrors, Levents, Lstate, Lconst, Ltypes, Lqn, Rcall, qnB,
      typesB, constantsB, stateB, eventsB, errorsB, callablesB, invariantsB,
      requirementsB, ByteArray.append_assoc] using hlayout
  have hLcall : Lcall.size = oca := by
    simp only [Lcall, Lerrors, Levents, Lstate, Lconst, Ltypes, Lqn, oca,
      oCallablesV1, oer, oErrorsV1, oev, oEventsV1, os, oStateV1, oc, oConstV1,
      oty, oTypesV1, ot, oTagV1, magicSizeV1, ByteArray.size_append,
      header_size_SemanticProgram_Data]
  have hcall :=
    mid_field b (decodeArray maxTableElements decodeCallableV1) data.callables
      callablesB Lcall Rcall 1 oca oin hinCall hLcall
      (by simp only [oin, oInvariantsV1, oca, oCallablesV1])
      (hinvert.callables callablesB Lcall Rcall
        (by simpa [callablesB] using fok.hcallables))
  -- invariants
  let Linv := Lcall ++ callablesB
  let Rinv := requirementsB
  have hinInv : b = Linv ++ invariantsB ++ Rinv := by
    simpa [Linv, Lcall, Lerrors, Levents, Lstate, Lconst, Ltypes, Lqn, Rinv, qnB,
      typesB, constantsB, stateB, eventsB, errorsB, callablesB, invariantsB,
      requirementsB, ByteArray.append_assoc] using hlayout
  have hLinv : Linv.size = oin := by
    simp only [Linv, Lcall, Lerrors, Levents, Lstate, Lconst, Ltypes, Lqn, oin,
      oInvariantsV1, oca, oCallablesV1, oer, oErrorsV1, oev, oEventsV1, os,
      oStateV1, oc, oConstV1, oty, oTypesV1, ot, oTagV1, magicSizeV1,
      ByteArray.size_append, header_size_SemanticProgram_Data]
  have hinv :=
    mid_field b (decodeArray maxTableElements decodeInvariantDeclV1)
      data.invariants invariantsB Linv Rinv 1 oin oreq hinInv hLinv
      (by simp only [oreq, oRequirementsV1, oin, oInvariantsV1])
      (hinvert.invariants invariantsB Linv Rinv
        (by simpa [invariantsB] using fok.hinvariants))
  -- requirements
  let Lreq := Linv ++ invariantsB
  let Rreq : ByteArray := ByteArray.empty
  have hinReq : b = Lreq ++ requirementsB ++ Rreq := by
    have h := hlayout
    -- last field; right is empty
    simpa [Lreq, Linv, Lcall, Lerrors, Levents, Lstate, Lconst, Ltypes, Lqn, Rreq,
      qnB, typesB, constantsB, stateB, eventsB, errorsB, callablesB, invariantsB,
      requirementsB, ByteArray.append_assoc, ByteArray.append_empty] using h
  have hLreq : Lreq.size = oreq := by
    simp only [Lreq, Linv, Lcall, Lerrors, Levents, Lstate, Lconst, Ltypes, Lqn,
      oreq, oRequirementsV1, oin, oInvariantsV1, oca, oCallablesV1, oer,
      oErrorsV1, oev, oEventsV1, os, oStateV1, oc, oConstV1, oty, oTypesV1, ot,
      oTagV1, magicSizeV1, ByteArray.size_append, header_size_SemanticProgram_Data]
  have hreq :=
    mid_field b decodeProgramRequirementsV1 data.requirements requirementsB Lreq
      Rreq 1 oreq oend hinReq hLreq
      (by simp only [oend, oEndV1, oreq, oRequirementsV1])
      (hinvert.requirements requirementsB Lreq Rreq
        (by simpa [requirementsB] using fok.hrequirements))
  have hend :
      oend = b.size := by
    simpa [oend, qnB, typesB, constantsB, stateB, eventsB, errorsB, callablesB,
      invariantsB, requirementsB] using rootEncodeFieldsOk_end_offset data b fok
  have hdata :
      ({
        qualifiedName := data.qualifiedName
        types := data.types
        constants := data.constants
        logicalState := data.logicalState
        events := data.events
        errors := data.errors
        callables := data.callables
        invariants := data.invariants
        requirements := data.requirements
      } : SemanticProgramDataV1) = data := by
    cases data; rfl
  have htagged :=
    decodeSemanticProgramDataTaggedV1_eq_of_fields
      ⟨b, magicSizeV1, 0⟩
      ⟨b, ot, 1⟩
      ⟨b, oty, 1⟩
      ⟨b, oc, 1⟩
      ⟨b, os, 1⟩
      ⟨b, oev, 1⟩
      ⟨b, oer, 1⟩
      ⟨b, oca, 1⟩
      ⟨b, oin, 1⟩
      ⟨b, oreq, 1⟩
      ⟨b, oend, 1⟩
      data.qualifiedName data.types data.constants data.logicalState data.events
      data.errors data.callables data.invariants data.requirements
      hdepth htag hname htypes hconst hstate hevents herrors hcall hinv hreq
  have h' :
      decodeSemanticProgramDataTaggedV1 ⟨b, magicSizeV1, 0⟩ =
        .ok (data, ⟨b, oend, 0⟩) := by
    simpa [hdata] using htagged
  simpa [hend] using h'

/-! ### Full transport decode composition -/

theorem decodeSemanticProgramDataV1_of_rootEncodeFieldsOk
    (data : SemanticProgramDataV1) (b : ByteArray)
    (fok : RootEncodeFieldsOkV1 data b)
    (hinvert : RootFieldInvertV1 data) :
    decodeSemanticProgramDataV1 b = .ok data := by
  have hsize := fok.hsize
  have hb : b = encodeMagicPrefix semanticProgramMagicV1 ++ fok.body := by
    simpa [ByteArray.append_eq] using fok.hb
  have hmagic :
      consumeMagic semanticProgramMagicV1 (start b) =
        .ok ((), ⟨b, magicSizeV1, 0⟩) := by
    rw [hb]
    simpa [magicSizeV1] using
      consumeMagic_append_bodyV1 semanticProgramMagicV1 fok.body
  have hdata := decodeSemanticProgramDataTagged_of_rootFieldInvert data b fok hinvert
  have hfinish : finish ⟨b, b.size, 0⟩ = .ok () := finish_at_endV1 b 0
  exact decodeSemanticProgramDataV1_eq_of_framing b
    ⟨b, magicSizeV1, 0⟩ ⟨b, b.size, 0⟩ data hsize hmagic hdata hfinish

/-- **mig-a1-root composition close.**

    Structure-gated encode success + nine root-field mid-offset invert packages
    ⇒ transport decode recovers the same `data`. -/
theorem decodeSemanticProgramDataV1_of_encode_ok_of_rootFieldInvert
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes)
    (hinvert : RootFieldInvertV1 data) :
    decodeSemanticProgramDataV1 bytes = .ok data :=
  decodeSemanticProgramDataV1_of_rootEncodeFieldsOk data bytes
    (rootEncodeFieldsOk_of_encode data bytes hencode) hinvert

/-- Discharge of `DecodeEncodeRoundtripGoalV1` (composition form). -/
theorem decodeEncodeRoundtripGoal_discharged
    (data : SemanticProgramDataV1) (bytes : ByteArray) :
    DecodeEncodeRoundtripGoalV1 data bytes :=
  fun hencode hinvert =>
    decodeSemanticProgramDataV1_of_encode_ok_of_rootFieldInvert data bytes
      hencode hinvert

/-- Alias used by ProofBridge / author paths. -/
theorem decodeSemanticProgramDataV1_of_encode_ok
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes)
    (hinvert : RootFieldInvertV1 data) :
    decodeSemanticProgramDataV1 bytes = .ok data :=
  decodeSemanticProgramDataV1_of_encode_ok_of_rootFieldInvert data bytes hencode
    hinvert

end ProofForgeV2.Semantic.WireV1
