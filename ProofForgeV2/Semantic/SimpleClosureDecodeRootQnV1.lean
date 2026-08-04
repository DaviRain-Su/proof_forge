import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.SimpleClosureDecodeV1
import ProofForgeV2.Semantic.SimpleClosureEncodeV1
import ProofForgeV2.Semantic.SimpleClosureStructureCertV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.Wire.CodecRoundtripV1
import ProofForgeV2.Semantic.WireV1
import Init.Data.ByteArray.Lemmas
import Init.Data.Array.Lemmas

/-!
  ProofForgeV2.Semantic.SimpleClosureDecodeRootQnV1 — B-SC-DEC root tag + QN leaf

  Closed (kernel, no free htag premise):
    * `expectTaggedHeader_data_midV1` / `expectTag_data_midV1` — production
      mid-offset `expectTag "SemanticProgram.Data" 9` from encodeTagged header bytes
    * `fieldsOk_body_eq` — FieldsOk body = header ++ nine field payloads
    * `expectTag_of_fieldsOk` / `expectTag_of_simpleClosure_fields_ok` — post-magic
      expectTag from sole FieldsOk / `hfields` (composer-callable)

  Runtime (tests): demo + unicode field-path → expectTag after magic +
  `decodeQualifiedName` recovers materialize QN (uses existing QN list induction).

  Residual for full kernel QN composer (not closed here):
    * `encodeArray_strings_legal` parametric (private `encodeNatAsU32le` gate from
      outside CodecV1; public encodeArray_N covers fixed small counts)
    * `validateQualifiedName` / `ofArray_toArray` structure equality under Legal
      (private validator + Array.extract lemmas) so `parseQualifiedName` can be
      discharged without free hparse — then
      `decodeQualifiedName_of_fieldsOk_legal` composes with FieldsOk layout +
      existing `decodeArray_qnComponents_of_legal`.

  No axiom / sorry / native_decide / ofReduceBool / run_tac / unsafe / meta / IO.
-/

namespace ProofForgeV2.Semantic.SimpleClosureDecodeRootQnV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
open ProofForgeV2.Semantic.SimpleClosureDecodeV1
open ProofForgeV2.Semantic.SimpleClosureEncodeV1
open ProofForgeV2.Semantic.SimpleClosureStructureCertV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1

/-! ### Root tag constants -/

def semanticProgramDataTagV1 : String := "SemanticProgram.Data"
def semanticProgramDataHeaderSizeV1 : Nat := 26

private def tagByteList : List UInt8 :=
  [83, 101, 109, 97, 110, 116, 105, 99, 80, 114, 111, 103, 114, 97, 109, 46, 68, 97, 116, 97]

def semanticProgramDataTagBytesV1 : ByteArray :=
  ByteArray.mk tagByteList.toArray

theorem tag_utf8_size : semanticProgramDataTagV1.toUTF8.size = 20 := by decide
theorem tag_nonempty : semanticProgramDataTagV1.isEmpty = false := by decide
theorem tag_ascii : isAsciiTagV1 semanticProgramDataTagV1 = true := by decide
theorem tag_le_max : semanticProgramDataTagV1.toUTF8.size ≤ maxTagAsciiBytes := by
  rw [tag_utf8_size]; decide
theorem tag_le_u32 : semanticProgramDataTagV1.toUTF8.size ≤ UInt32.size - 1 := by
  rw [tag_utf8_size]; decide
theorem tag_utf8_eq_bytes :
    semanticProgramDataTagV1.toUTF8 = semanticProgramDataTagBytesV1 := by decide

private theorem tagByteList_all_ascii :
    (tagByteList.all fun b => decide (b.toNat ≤ 127)) = true := by
  simp only [tagByteList]; decide

private theorem tagByteArray_all_ascii :
    (tagByteList.toArray.all fun b => decide (b.toNat ≤ 127)) = true := by
  have h := tagByteList_all_ascii
  rw [Array.all_eq_true]
  intro i hi
  have hi' : i < tagByteList.length := by simpa using hi
  have hget : tagByteList.toArray[i] = tagByteList[i]'(hi') :=
    List.getElem_toArray (xs := tagByteList) (i := i) (h := by simpa using hi)
  rw [hget]
  exact ((List.all_eq_true).1 h) _ (List.getElem_mem hi')

theorem tag_bytes_ascii :
    isAsciiTagBytesV1 semanticProgramDataTagBytesV1 = true := by
  unfold isAsciiTagBytesV1 semanticProgramDataTagBytesV1
  exact tagByteArray_all_ascii

theorem tag_utf8_ascii :
    isAsciiTagBytesV1 semanticProgramDataTagV1.toUTF8 = true := by
  rw [tag_utf8_eq_bytes]; exact tag_bytes_ascii

/-! ### encodeTagged nine-field body layout -/

def taggedHeaderBytesV1 (tag : String) (fieldCount : Nat) : ByteArray :=
  ((encodeU32le (UInt32.ofNat tag.toUTF8.size)).append tag.toUTF8).append
    (encodeU16le (UInt16.ofNat fieldCount))

theorem header_size :
    (taggedHeaderBytesV1 semanticProgramDataTagV1 9).size =
      semanticProgramDataHeaderSizeV1 := by
  unfold taggedHeaderBytesV1 semanticProgramDataHeaderSizeV1
  have h1 : (encodeU32le (UInt32.ofNat semanticProgramDataTagV1.toUTF8.size)).size = 4 :=
    encodeU32le_sizeV1 _
  have h2 : (encodeU16le (UInt16.ofNat 9)).size = 2 := encodeU16le_sizeV1 _
  have h3 : semanticProgramDataTagV1.toUTF8.size = 20 := tag_utf8_size
  calc
    (((encodeU32le (UInt32.ofNat semanticProgramDataTagV1.toUTF8.size)).append
        semanticProgramDataTagV1.toUTF8).append (encodeU16le (UInt16.ofNat 9))).size
        = (encodeU32le (UInt32.ofNat semanticProgramDataTagV1.toUTF8.size)).size +
            semanticProgramDataTagV1.toUTF8.size +
            (encodeU16le (UInt16.ofNat 9)).size := by
          simp [ByteArray.size_append]
    _ = 4 + 20 + 2 := by rw [h1, h2, h3]
    _ = 26 := rfl

theorem encodeTagged_data_nine
    (f0 f1 f2 f3 f4 f5 f6 f7 f8 : ByteArray) :
    encodeTagged "SemanticProgram.Data" #[f0, f1, f2, f3, f4, f5, f6, f7, f8] =
      .ok (taggedBytesV1 "SemanticProgram.Data" #[f0, f1, f2, f3, f4, f5, f6, f7, f8]) := by
  have hfields : (#[f0, f1, f2, f3, f4, f5, f6, f7, f8] : Array ByteArray).size ≤
      UInt16.size - 1 := by
    change 9 ≤ UInt16.size - 1
    decide
  exact encodeTagged_eq_okV1 "SemanticProgram.Data" #[f0, f1, f2, f3, f4, f5, f6, f7, f8]
    tag_nonempty tag_ascii tag_le_max tag_le_u32 hfields

theorem appendTagged_nine (initial f0 f1 f2 f3 f4 f5 f6 f7 f8 : ByteArray) :
    appendTaggedFieldsV1 initial #[f0, f1, f2, f3, f4, f5, f6, f7, f8] =
      initial ++ f0 ++ f1 ++ f2 ++ f3 ++ f4 ++ f5 ++ f6 ++ f7 ++ f8 := by
  simp [appendTaggedFieldsV1]

theorem taggedBytes_data_nine
    (f0 f1 f2 f3 f4 f5 f6 f7 f8 : ByteArray) :
    taggedBytesV1 "SemanticProgram.Data" #[f0, f1, f2, f3, f4, f5, f6, f7, f8] =
      taggedHeaderBytesV1 semanticProgramDataTagV1 9 ++
        f0 ++ f1 ++ f2 ++ f3 ++ f4 ++ f5 ++ f6 ++ f7 ++ f8 := by
  simp only [taggedBytesV1, taggedBytesFromBytesV1, taggedHeaderBytesV1,
    semanticProgramDataTagV1]
  have hsz : (#[f0, f1, f2, f3, f4, f5, f6, f7, f8] : Array ByteArray).size = 9 := rfl
  simp only [hsz, appendTagged_nine]

theorem encodeTagged_data_nine_body
    (f0 f1 f2 f3 f4 f5 f6 f7 f8 body : ByteArray)
    (h : encodeTagged "SemanticProgram.Data" #[f0, f1, f2, f3, f4, f5, f6, f7, f8] = .ok body) :
    body =
      taggedHeaderBytesV1 semanticProgramDataTagV1 9 ++
        f0 ++ f1 ++ f2 ++ f3 ++ f4 ++ f5 ++ f6 ++ f7 ++ f8 := by
  have hok := encodeTagged_data_nine f0 f1 f2 f3 f4 f5 f6 f7 f8
  have hb : body = taggedBytesV1 "SemanticProgram.Data" #[f0, f1, f2, f3, f4, f5, f6, f7, f8] :=
    Except.ok.inj (h.symm.trans hok)
  exact hb.trans (taggedBytes_data_nine f0 f1 f2 f3 f4 f5 f6 f7 f8)

theorem fieldsOk_body_eq
    (data : SemanticProgramDataV1) (b : ByteArray)
    (fok : SemanticProgramFieldsOkV1 data b) :
    fok.body =
      taggedHeaderBytesV1 semanticProgramDataTagV1 9 ++
        fok.qnB ++ fok.typesB ++ fok.constantsB ++ fok.stateB ++
        fok.eventsB ++ fok.errorsB ++ fok.callablesB ++
        fok.invariantsB ++ fok.requirementsB :=
  encodeTagged_data_nine_body
    fok.qnB fok.typesB fok.constantsB fok.stateB fok.eventsB fok.errorsB
    fok.callablesB fok.invariantsB fok.requirementsB fok.body fok.hbody

/-! ### expectTag mid-offset from production header -/

theorem expectTaggedHeader_data_midV1
    (left right : ByteArray) :
    expectTaggedHeaderBytesAtV1
        (left ++ taggedHeaderBytesV1 semanticProgramDataTagV1 9 ++ right)
        left.size
        semanticProgramDataTagV1.toUTF8
        9 =
      .ok (left.size + semanticProgramDataHeaderSizeV1) := by
  have hsz : semanticProgramDataTagV1.toUTF8.size = 20 := tag_utf8_size
  have hpay :
      taggedHeaderBytesV1 semanticProgramDataTagV1 9 =
        encodeU32le (UInt32.ofNat 20) ++
          semanticProgramDataTagV1.toUTF8 ++
          encodeU16le (UInt16.ofNat 9) := by
    simp only [taggedHeaderBytesV1, ByteArray.append_eq, hsz]
  have hin :
      left ++ taggedHeaderBytesV1 semanticProgramDataTagV1 9 ++ right =
        left ++ encodeU32le (UInt32.ofNat 20) ++
          (semanticProgramDataTagV1.toUTF8 ++ encodeU16le (UInt16.ofNat 9) ++ right) := by
    simp [hpay, ByteArray.append_assoc]
  unfold expectTaggedHeaderBytesAtV1 readTagBytesAtV1
  rw [hin]
  have hread :
      readU32leAtV1
          (left ++ encodeU32le (UInt32.ofNat 20) ++
            (semanticProgramDataTagV1.toUTF8 ++ encodeU16le (UInt16.ofNat 9) ++ right))
          left.size =
        .ok (UInt32.ofNat 20, left.size + 4) :=
    readU32le_encode_midV1 left
      (semanticProgramDataTagV1.toUTF8 ++ encodeU16le (UInt16.ofNat 9) ++ right)
      (UInt32.ofNat 20)
  simp only [hread]
  have hlen : (UInt32.ofNat 20).toNat = 20 := by decide
  simp only [hlen]
  have hneg : (!(decide (1 ≤ 20) && decide (20 ≤ maxTagAsciiBytes))) = false := by
    decide
  simp only [hneg, Bool.false_eq_true, ↓reduceIte]
  have htake :
      takeBytesAtV1
          (left ++ encodeU32le (UInt32.ofNat 20) ++
            (semanticProgramDataTagV1.toUTF8 ++ encodeU16le (UInt16.ofNat 9) ++ right))
          (left.size + 4) 20 =
        .ok semanticProgramDataTagV1.toUTF8 := by
    have hs4 : (encodeU32le (UInt32.ofNat 20)).size = 4 := encodeU32le_sizeV1 _
    have hA :
        left ++ encodeU32le (UInt32.ofNat 20) ++
            (semanticProgramDataTagV1.toUTF8 ++ encodeU16le (UInt16.ofNat 9) ++ right) =
          (left ++ encodeU32le (UInt32.ofNat 20)) ++ semanticProgramDataTagV1.toUTF8 ++
            (encodeU16le (UInt16.ofNat 9) ++ right) := by
      simp [ByteArray.append_assoc]
    have hoff : (left ++ encodeU32le (UInt32.ofNat 20)).size = left.size + 4 := by
      rw [ByteArray.size_append, hs4]
    have hlen20 : semanticProgramDataTagV1.toUTF8.size = 20 := hsz
    rw [hA, ← hoff, ← hlen20]
    exact takeBytes_mid_payloadV1 _ semanticProgramDataTagV1.toUTF8
      (encodeU16le (UInt16.ofNat 9) ++ right)
  simp only [htake, tag_utf8_ascii, ↓reduceIte]
  have hbeq : (semanticProgramDataTagV1.toUTF8 != semanticProgramDataTagV1.toUTF8) = false := by
    have heq : (semanticProgramDataTagV1.toUTF8 == semanticProgramDataTagV1.toUTF8) = true :=
      ByteArray_beq_reflV1 _
    change (!(semanticProgramDataTagV1.toUTF8 == semanticProgramDataTagV1.toUTF8)) = false
    rw [heq]; rfl
  simp only [hbeq, Bool.false_eq_true, ↓reduceIte]
  have hin2 :
      left ++ encodeU32le (UInt32.ofNat 20) ++
          (semanticProgramDataTagV1.toUTF8 ++ encodeU16le (UInt16.ofNat 9) ++ right) =
        (left ++ encodeU32le (UInt32.ofNat 20) ++ semanticProgramDataTagV1.toUTF8) ++
          encodeU16le (UInt16.ofNat 9) ++ right := by
    simp [ByteArray.append_assoc]
  have hoff2 :
      left.size + 4 + 20 =
        (left ++ encodeU32le (UInt32.ofNat 20) ++ semanticProgramDataTagV1.toUTF8).size := by
    have h :
        (left ++ encodeU32le (UInt32.ofNat 20) ++ semanticProgramDataTagV1.toUTF8).size =
          left.size + 4 + semanticProgramDataTagV1.toUTF8.size := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    rw [h, hsz]
  have hu16 :
      readU16leAtV1
          (left ++ encodeU32le (UInt32.ofNat 20) ++
            (semanticProgramDataTagV1.toUTF8 ++ encodeU16le (UInt16.ofNat 9) ++ right))
          (left.size + 4 + 20) =
        .ok (UInt16.ofNat 9, left.size + 4 + 20 + 2) := by
    rw [hin2, hoff2]
    simpa [ByteArray.size_append, encodeU32le_sizeV1, hsz, Nat.add_assoc] using
      (readU16le_encode_midV1
        (left ++ encodeU32le (UInt32.ofNat 20) ++ semanticProgramDataTagV1.toUTF8)
        right (UInt16.ofNat 9))
  simp only [hu16]
  have hoff3 : left.size + 4 + 20 + 2 = left.size + semanticProgramDataHeaderSizeV1 := by
    simp only [semanticProgramDataHeaderSizeV1]
  simp [hoff3]

theorem expectTag_data_midV1
    (left right : ByteArray) (nesting : Nat) :
    expectTag "SemanticProgram.Data" 9
        ⟨left ++ taggedHeaderBytesV1 semanticProgramDataTagV1 9 ++ right,
          left.size, nesting⟩ =
      .ok ((),
        ⟨left ++ taggedHeaderBytesV1 semanticProgramDataTagV1 9 ++ right,
          left.size + semanticProgramDataHeaderSizeV1, nesting⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1
      (left ++ taggedHeaderBytesV1 semanticProgramDataTagV1 9 ++ right)
      left.size semanticProgramDataTagV1.toUTF8 9 =
    .ok (left.size + semanticProgramDataHeaderSizeV1)
  exact expectTaggedHeader_data_midV1 left right

theorem expectTag_of_fieldsOk
    (data : SemanticProgramDataV1) (b : ByteArray)
    (fok : SemanticProgramFieldsOkV1 data b) (nesting : Nat) :
    expectTag "SemanticProgram.Data" 9
        ⟨b, (encodeMagicPrefix semanticProgramMagicV1).size, nesting⟩ =
      .ok ((),
        ⟨b,
          (encodeMagicPrefix semanticProgramMagicV1).size +
            semanticProgramDataHeaderSizeV1,
          nesting⟩) := by
  have hb : b = encodeMagicPrefix semanticProgramMagicV1 ++ fok.body := by
    simpa [ByteArray.append_eq] using fok.hb
  have hbody := fieldsOk_body_eq data b fok
  let rest :=
    fok.qnB ++ fok.typesB ++ fok.constantsB ++ fok.stateB ++
      fok.eventsB ++ fok.errorsB ++ fok.callablesB ++
      fok.invariantsB ++ fok.requirementsB
  have hin :
      b =
        encodeMagicPrefix semanticProgramMagicV1 ++
          taggedHeaderBytesV1 semanticProgramDataTagV1 9 ++ rest := by
    rw [hb, hbody]
    simp [rest, ByteArray.append_assoc]
  rw [hin]
  simpa [ByteArray.append_assoc] using
    expectTag_data_midV1 (encodeMagicPrefix semanticProgramMagicV1) rest nesting

theorem expectTag_of_simpleClosure_fields_ok
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (hfields : encodeSimpleClosureDataFieldsV1 p = .ok b) (nesting : Nat) :
    expectTag "SemanticProgram.Data" 9
        ⟨b, (encodeMagicPrefix semanticProgramMagicV1).size, nesting⟩ =
      .ok ((),
        ⟨b,
          (encodeMagicPrefix semanticProgramMagicV1).size +
            semanticProgramDataHeaderSizeV1,
          nesting⟩) :=
  expectTag_of_fieldsOk (materializeSimpleClosureDataV1 p) b
    (encodeSimpleClosureFields_ok_inv p b hfields) nesting



end ProofForgeV2.Semantic.SimpleClosureDecodeRootQnV1
