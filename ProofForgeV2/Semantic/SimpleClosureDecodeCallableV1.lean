import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.SimpleClosureStructureCertV1
import ProofForgeV2.Semantic.Wire.CodecRoundtripV1
import ProofForgeV2.Semantic.WireV1
import Init.Data.ByteArray.Lemmas
import Init.Data.Array.Lemmas

/-!
  ProofForgeV2.Semantic.SimpleClosureDecodeCallableV1 — B-SC-DEC callable leaf

  Root-composer kernel lemmas without free nested-decode premises.
  Allowed premises: production encode equality and/or `SimpleClosureParamsLegalV1`.
  Public theorems recover exact values at mid-offset `left ++ encoded ++ right`.
-/

namespace ProofForgeV2.Semantic.SimpleClosureDecodeCallableV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.SimpleClosureStructureCertV1
open ProofForgeV2.Semantic.WireV1

set_option maxHeartbeats 12000000
set_option maxRecDepth 4096

/-! ### Tagged framing -/

theorem appendTaggedFields_two_init (init a b : ByteArray) :
    appendTaggedFieldsV1 init #[a, b] = init ++ a ++ b := by
  simp [appendTaggedFieldsV1]

theorem appendTaggedFields_one_init (init a : ByteArray) :
    appendTaggedFieldsV1 init #[a] = init ++ a := by
  simp [appendTaggedFieldsV1]

theorem appendTaggedFields_zero_init (init : ByteArray) :
    appendTaggedFieldsV1 init #[] = init := rfl

theorem appendTaggedFields_four_init (init a b c d : ByteArray) :
    appendTaggedFieldsV1 init #[a, b, c, d] = init ++ a ++ b ++ c ++ d := by
  simp [appendTaggedFieldsV1]

theorem appendTaggedFields_nine_init (init a0 a1 a2 a3 a4 a5 a6 a7 a8 : ByteArray) :
    appendTaggedFieldsV1 init #[a0, a1, a2, a3, a4, a5, a6, a7, a8] =
      init ++ a0 ++ a1 ++ a2 ++ a3 ++ a4 ++ a5 ++ a6 ++ a7 ++ a8 := by
  simp [appendTaggedFieldsV1]

def taggedHeaderBytesV1 (tag : String) (fieldCount : UInt16) : ByteArray :=
  encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++ encodeU16le fieldCount

theorem taggedHeaderBytes_size (tag : String) (fieldCount : UInt16) :
    (taggedHeaderBytesV1 tag fieldCount).size = 4 + tag.toUTF8.size + 2 := by
  simp [taggedHeaderBytesV1, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1]

theorem taggedBytes_zero_eq (tag : String) :
    taggedBytesV1 tag #[] = taggedHeaderBytesV1 tag 0 := by
  -- encodeTagged nullary framing is header with field-count 0
  simp [taggedBytesV1, taggedBytesFromBytesV1, taggedHeaderBytesV1,
    appendTaggedFieldsV1]

theorem taggedBytes_one_eq (tag : String) (a : ByteArray) :
    taggedBytesV1 tag #[a] = taggedHeaderBytesV1 tag 1 ++ a := by
  simp only [taggedBytesV1, taggedBytesFromBytesV1, taggedHeaderBytesV1]
  have hsz : (#[a] : Array ByteArray).size = 1 := rfl
  simp only [hsz]
  simpa [ByteArray.append_eq, ByteArray.append_assoc] using
    appendTaggedFields_one_init
      (encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++ encodeU16le 1) a

theorem taggedBytes_two_eq (tag : String) (a b : ByteArray) :
    taggedBytesV1 tag #[a, b] = taggedHeaderBytesV1 tag 2 ++ a ++ b := by
  simp only [taggedBytesV1, taggedBytesFromBytesV1, taggedHeaderBytesV1]
  have hsz : (#[a, b] : Array ByteArray).size = 2 := rfl
  simp only [hsz]
  simpa [ByteArray.append_eq, ByteArray.append_assoc] using
    appendTaggedFields_two_init
      (encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++ encodeU16le 2) a b

theorem taggedBytes_four_eq (tag : String) (a b c d : ByteArray) :
    taggedBytesV1 tag #[a, b, c, d] =
      taggedHeaderBytesV1 tag 4 ++ a ++ b ++ c ++ d := by
  simp only [taggedBytesV1, taggedBytesFromBytesV1, taggedHeaderBytesV1]
  have hsz : (#[a, b, c, d] : Array ByteArray).size = 4 := rfl
  simp only [hsz]
  simpa [ByteArray.append_eq, ByteArray.append_assoc] using
    appendTaggedFields_four_init
      (encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++ encodeU16le 4) a b c d

theorem taggedBytes_nine_eq (tag : String)
    (a0 a1 a2 a3 a4 a5 a6 a7 a8 : ByteArray) :
    taggedBytesV1 tag #[a0, a1, a2, a3, a4, a5, a6, a7, a8] =
      taggedHeaderBytesV1 tag 9 ++ a0 ++ a1 ++ a2 ++ a3 ++ a4 ++ a5 ++ a6 ++ a7 ++ a8 := by
  simp only [taggedBytesV1, taggedBytesFromBytesV1, taggedHeaderBytesV1]
  have hsz : (#[a0, a1, a2, a3, a4, a5, a6, a7, a8] : Array ByteArray).size = 9 := rfl
  simp only [hsz]
  simpa [ByteArray.append_eq, ByteArray.append_assoc] using
    appendTaggedFields_nine_init
      (encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++ encodeU16le 9)
      a0 a1 a2 a3 a4 a5 a6 a7 a8

/-! ### ASCII certificates (no native_decide) -/

theorem isAsciiTagBytes_of_list_all (bs : List UInt8)
    (h : (bs.all fun b => decide (b.toNat ≤ 127)) = true) :
    isAsciiTagBytesV1 (ByteArray.mk bs.toArray) = true := by
  simp only [isAsciiTagBytesV1]
  apply (Array.all_eq_true).mpr
  intro i hi
  have hi' : i < bs.length := by simpa using hi
  have hmem : bs[i] ∈ bs := List.getElem_mem hi'
  exact List.all_eq_true.1 h bs[i] hmem

theorem utf8_ValueDef :
    "ValueDef".toUTF8 = ByteArray.mk #[86, 97, 108, 117, 101, 68, 101, 102] := by rfl

theorem isAsciiTagBytes_ValueDef : isAsciiTagBytesV1 "ValueDef".toUTF8 = true := by
  rw [utf8_ValueDef]
  exact isAsciiTagBytes_of_list_all [86, 97, 108, 117, 101, 68, 101, 102] (by decide)

theorem isAsciiTag_ValueDef : isAsciiTagV1 "ValueDef" = true := by decide


theorem utf8_Op_Literal :
    "Op.Literal".toUTF8 = ByteArray.mk #[79, 112, 46, 76, 105, 116, 101, 114, 97, 108] := by rfl

theorem isAsciiTagBytes_Op_Literal : isAsciiTagBytesV1 "Op.Literal".toUTF8 = true := by
  rw [utf8_Op_Literal]
  exact isAsciiTagBytes_of_list_all [79, 112, 46, 76, 105, 116, 101, 114, 97, 108] (by decide)

theorem isAsciiTag_Op_Literal : isAsciiTagV1 "Op.Literal" = true := by decide


theorem utf8_Instruction :
    "Instruction".toUTF8 = ByteArray.mk #[73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] := by rfl

theorem isAsciiTagBytes_Instruction : isAsciiTagBytesV1 "Instruction".toUTF8 = true := by
  rw [utf8_Instruction]
  exact isAsciiTagBytes_of_list_all [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by decide)

theorem isAsciiTag_Instruction : isAsciiTagV1 "Instruction" = true := by decide


theorem utf8_Term_Return :
    "Term.Return".toUTF8 = ByteArray.mk #[84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110] := by rfl

theorem isAsciiTagBytes_Term_Return : isAsciiTagBytesV1 "Term.Return".toUTF8 = true := by
  rw [utf8_Term_Return]
  exact isAsciiTagBytes_of_list_all [84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110] (by decide)

theorem isAsciiTag_Term_Return : isAsciiTagV1 "Term.Return" = true := by decide


theorem utf8_Block :
    "Block".toUTF8 = ByteArray.mk #[66, 108, 111, 99, 107] := by rfl

theorem isAsciiTagBytes_Block : isAsciiTagBytesV1 "Block".toUTF8 = true := by
  rw [utf8_Block]
  exact isAsciiTagBytes_of_list_all [66, 108, 111, 99, 107] (by decide)

theorem isAsciiTag_Block : isAsciiTagV1 "Block" = true := by decide


theorem utf8_Callable :
    "Callable".toUTF8 = ByteArray.mk #[67, 97, 108, 108, 97, 98, 108, 101] := by rfl

theorem isAsciiTagBytes_Callable : isAsciiTagBytesV1 "Callable".toUTF8 = true := by
  rw [utf8_Callable]
  exact isAsciiTagBytes_of_list_all [67, 97, 108, 108, 97, 98, 108, 101] (by decide)

theorem isAsciiTag_Callable : isAsciiTagV1 "Callable" = true := by decide


theorem utf8_Callable_View :
    "Callable.View".toUTF8 = ByteArray.mk #[67, 97, 108, 108, 97, 98, 108, 101, 46, 86, 105, 101, 119] := by rfl

theorem isAsciiTagBytes_Callable_View : isAsciiTagBytesV1 "Callable.View".toUTF8 = true := by
  rw [utf8_Callable_View]
  exact isAsciiTagBytes_of_list_all [67, 97, 108, 108, 97, 98, 108, 101, 46, 86, 105, 101, 119] (by decide)

theorem isAsciiTag_Callable_View : isAsciiTagV1 "Callable.View" = true := by decide


theorem utf8_Callable_Invariant :
    "Callable.Invariant".toUTF8 = ByteArray.mk #[67, 97, 108, 108, 97, 98, 108, 101, 46, 73, 110, 118, 97, 114, 105, 97, 110, 116] := by rfl

theorem isAsciiTagBytes_Callable_Invariant : isAsciiTagBytesV1 "Callable.Invariant".toUTF8 = true := by
  rw [utf8_Callable_Invariant]
  exact isAsciiTagBytes_of_list_all [67, 97, 108, 108, 97, 98, 108, 101, 46, 73, 110, 118, 97, 114, 105, 97, 110, 116] (by decide)

theorem isAsciiTag_Callable_Invariant : isAsciiTagV1 "Callable.Invariant" = true := by decide


theorem utf8_CallableResult :
    "CallableResult".toUTF8 = ByteArray.mk #[67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116] := by rfl

theorem isAsciiTagBytes_CallableResult : isAsciiTagBytesV1 "CallableResult".toUTF8 = true := by
  rw [utf8_CallableResult]
  exact isAsciiTagBytes_of_list_all [67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116] (by decide)

theorem isAsciiTag_CallableResult : isAsciiTagV1 "CallableResult" = true := by decide


theorem utf8_Visibility_Public :
    "Visibility.Public".toUTF8 = ByteArray.mk #[86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99] := by rfl

theorem isAsciiTagBytes_Visibility_Public : isAsciiTagBytesV1 "Visibility.Public".toUTF8 = true := by
  rw [utf8_Visibility_Public]
  exact isAsciiTagBytes_of_list_all [86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99] (by decide)

theorem isAsciiTag_Visibility_Public : isAsciiTagV1 "Visibility.Public" = true := by decide


/-! ### Tag mid-offset + expectTag -/

theorem readTagBytes_ascii_midV1 (left right : ByteArray) (tag : String)
    (hnonempty : 1 ≤ tag.toUTF8.size)
    (hlimit : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (hasciiBytes : isAsciiTagBytesV1 tag.toUTF8 = true) :
    readTagBytesAtV1
        (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++ right)
        left.size =
      .ok (tag.toUTF8, left.size + 4 + tag.toUTF8.size) := by
  have hassoc :
      left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++ right =
        left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ (tag.toUTF8 ++ right) := by
    simp [ByteArray.append_assoc]
  rw [hassoc]
  have hread :=
    readU32le_encode_midV1 left (tag.toUTF8 ++ right) (UInt32.ofNat tag.toUTF8.size)
  have hfit : (UInt32.ofNat tag.toUTF8.size).toNat = tag.toUTF8.size := by
    have : tag.toUTF8.size ≤ UInt32.size - 1 :=
      Nat.le_trans hlimit (by decide : maxTagAsciiBytes ≤ UInt32.size - 1)
    exact Nat.mod_eq_of_lt (Nat.lt_of_le_of_lt this (by decide))
  have htake :
      takeBytesAtV1
          (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ (tag.toUTF8 ++ right))
          (left.size + 4) tag.toUTF8.size = .ok tag.toUTF8 := by
    have hs4 : (encodeU32le (UInt32.ofNat tag.toUTF8.size)).size = 4 := encodeU32le_sizeV1 _
    have hoff : (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size)).size = left.size + 4 := by
      rw [ByteArray.size_append, hs4]
    have hA :
        left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ (tag.toUTF8 ++ right) =
          (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size)) ++ tag.toUTF8 ++ right := by
      simp [ByteArray.append_assoc]
    rw [hA, ← hoff]
    exact takeBytes_mid_payloadV1 _ tag.toUTF8 right
  unfold readTagBytesAtV1
  rw [hread]
  simp only [hfit]
  have hgate : (1 ≤ tag.toUTF8.size && tag.toUTF8.size ≤ maxTagAsciiBytes) = true := by
    cases h1 : decide (1 ≤ tag.toUTF8.size) <;>
      cases h2 : decide (tag.toUTF8.size ≤ maxTagAsciiBytes)
    · exact absurd hnonempty (of_decide_eq_false h1)
    · exact absurd hnonempty (of_decide_eq_false h1)
    · exact absurd hlimit (of_decide_eq_false h2)
    · simp [h1, h2]
  have hneg : (!(1 ≤ tag.toUTF8.size && tag.toUTF8.size ≤ maxTagAsciiBytes)) = false := by
    rw [hgate]; rfl
  rw [hneg]
  change (match takeBytesAtV1
      (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ (tag.toUTF8 ++ right))
      (left.size + 4) tag.toUTF8.size with
    | Except.error e => Except.error e
    | Except.ok raw =>
        if isAsciiTagBytesV1 raw = true then
          Except.ok (raw, left.size + 4 + tag.toUTF8.size)
        else Except.error SemanticWireErrorV1.badTag) =
    Except.ok (tag.toUTF8, left.size + 4 + tag.toUTF8.size)
  rw [htake]
  simp only [hasciiBytes, ↓reduceIte]

theorem expectTag_header_midV1 (left right : ByteArray) (tag : String)
    (fieldCount : Nat) (nesting : Nat)
    (hnonempty : 1 ≤ tag.toUTF8.size)
    (hlimit : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (hasciiBytes : isAsciiTagBytesV1 tag.toUTF8 = true)
    (hfitCount : fieldCount ≤ UInt16.size - 1) :
    expectTag tag fieldCount
        ⟨left ++ taggedHeaderBytesV1 tag (UInt16.ofNat fieldCount) ++ right,
          left.size, nesting⟩ =
      .ok ((),
        ⟨left ++ taggedHeaderBytesV1 tag (UInt16.ofNat fieldCount) ++ right,
          left.size + (taggedHeaderBytesV1 tag (UInt16.ofNat fieldCount)).size,
          nesting⟩) := by
  apply expectTag_eq_of_headerV1
  unfold expectTaggedHeaderBytesAtV1
  have hin :
      left ++ taggedHeaderBytesV1 tag (UInt16.ofNat fieldCount) ++ right =
        left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++
          (encodeU16le (UInt16.ofNat fieldCount) ++ right) := by
    simp [taggedHeaderBytesV1, ByteArray.append_assoc]
  have htag :=
    readTagBytes_ascii_midV1 left
      (encodeU16le (UInt16.ofNat fieldCount) ++ right) tag hnonempty hlimit hasciiBytes
  have htag' :
      readTagBytesAtV1
          (left ++ taggedHeaderBytesV1 tag (UInt16.ofNat fieldCount) ++ right) left.size =
        .ok (tag.toUTF8, left.size + 4 + tag.toUTF8.size) := by
    rw [hin]; exact htag
  simp only [htag']
  have hbeq : (tag.toUTF8 != tag.toUTF8) = false := by
    change (!(tag.toUTF8.data == tag.toUTF8.data)) = false
    simp
  simp only [hbeq, Bool.false_eq_true, ↓reduceIte]
  have hleft' :
      (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8).size =
        left.size + 4 + tag.toUTF8.size := by
    simp [ByteArray.size_append, encodeU32le_sizeV1]
  have hin2 :
      left ++ taggedHeaderBytesV1 tag (UInt16.ofNat fieldCount) ++ right =
        (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8) ++
          encodeU16le (UInt16.ofNat fieldCount) ++ right := by
    simp [taggedHeaderBytesV1, ByteArray.append_assoc]
  have hu16 :=
    readU16le_encode_midV1
      (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8) right
      (UInt16.ofNat fieldCount)
  have hu16' :
      readU16leAtV1
          (left ++ taggedHeaderBytesV1 tag (UInt16.ofNat fieldCount) ++ right)
          (left.size + 4 + tag.toUTF8.size) =
        .ok (UInt16.ofNat fieldCount, left.size + 4 + tag.toUTF8.size + 2) := by
    rw [hin2, ← hleft']; simpa using hu16
  simp only [hu16']
  have hcnt : ((UInt16.ofNat fieldCount).toNat == fieldCount) = true := by
    have : (UInt16.ofNat fieldCount).toNat = fieldCount :=
      Nat.mod_eq_of_lt (Nat.lt_of_le_of_lt hfitCount (by decide))
    simp [this]
  simp only [hcnt, ↓reduceIte]
  have hoff :
      left.size + 4 + tag.toUTF8.size + 2 =
        left.size + (taggedHeaderBytesV1 tag (UInt16.ofNat fieldCount)).size := by
    rw [taggedHeaderBytes_size]; omega
  exact congrArg Except.ok hoff

/-! ### ValueDef {0,0} leaf -/

def valueDef00BytesV1 : ByteArray :=
  taggedBytesV1 "ValueDef" #[encodeU32le 0, encodeU32le 0]

theorem encode_valueDef00 :
    encodeValueDefV1 { valueId := 0, typeId := 0 } = .ok valueDef00BytesV1 := by
  simp only [encodeValueDefV1, valueDef00BytesV1]
  exact encodeTagged_eq_okV1 "ValueDef" #[encodeU32le 0, encodeU32le 0]
    (by decide) isAsciiTag_ValueDef (by decide) (by decide) (by decide)

theorem decode_valueDef00_mid (left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) :
    decodeValueDefV1 ⟨left ++ valueDef00BytesV1 ++ right, left.size, nesting⟩ =
      .ok ({ valueId := 0, typeId := 0 },
        ⟨left ++ valueDef00BytesV1 ++ right,
          left.size + valueDef00BytesV1.size, nesting⟩) := by
  have hb : valueDef00BytesV1 =
      taggedHeaderBytesV1 "ValueDef" 2 ++ encodeU32le 0 ++ encodeU32le 0 := by
    simp only [valueDef00BytesV1]
    exact taggedBytes_two_eq "ValueDef" (encodeU32le 0) (encodeU32le 0)
  apply decodeValueDefV1_eq_of_fieldsV1
    ⟨left ++ valueDef00BytesV1 ++ right, left.size, nesting⟩
    ⟨left ++ valueDef00BytesV1 ++ right,
      left.size + (taggedHeaderBytesV1 "ValueDef" 2).size, nesting + 1⟩
    ⟨left ++ valueDef00BytesV1 ++ right,
      left.size + (taggedHeaderBytesV1 "ValueDef" 2).size + 4, nesting + 1⟩
    ⟨left ++ valueDef00BytesV1 ++ right,
      left.size + (taggedHeaderBytesV1 "ValueDef" 2).size + 8, nesting + 1⟩
    0 0 hdepth
  · have hin :
        left ++ valueDef00BytesV1 ++ right =
          left ++ taggedHeaderBytesV1 "ValueDef" 2 ++
            (encodeU32le 0 ++ encodeU32le 0 ++ right) := by
      simp [hb, ByteArray.append_assoc]
    have hexp :=
      expectTag_header_midV1 left (encodeU32le 0 ++ encodeU32le 0 ++ right)
        "ValueDef" 2 (nesting + 1) (by decide) (by decide)
        isAsciiTagBytes_ValueDef (by decide)
    simpa [hin, ByteArray.append_assoc] using hexp
  · have hin :
        left ++ valueDef00BytesV1 ++ right =
          (left ++ taggedHeaderBytesV1 "ValueDef" 2) ++ encodeU32le 0 ++
            (encodeU32le 0 ++ right) := by
      simp [hb, ByteArray.append_assoc]
    have hsz : (left ++ taggedHeaderBytesV1 "ValueDef" 2).size =
        left.size + (taggedHeaderBytesV1 "ValueDef" 2).size := by
      simp [ByteArray.size_append]
    have h :=
      decodeU32le_encode_midV1 (left ++ taggedHeaderBytesV1 "ValueDef" 2)
        (encodeU32le 0 ++ right) 0 (nesting + 1)
    simpa [hin, hsz] using h
  · have hin :
        left ++ valueDef00BytesV1 ++ right =
          (left ++ taggedHeaderBytesV1 "ValueDef" 2 ++ encodeU32le 0) ++
            encodeU32le 0 ++ right := by
      simp [hb, ByteArray.append_assoc]
    have hsz :
        (left ++ taggedHeaderBytesV1 "ValueDef" 2 ++ encodeU32le 0).size =
          left.size + (taggedHeaderBytesV1 "ValueDef" 2).size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    have htotal :
        left.size + (taggedHeaderBytesV1 "ValueDef" 2).size + 8 =
          left.size + valueDef00BytesV1.size := by
      simp [hb, ByteArray.size_append, encodeU32le_sizeV1, taggedHeaderBytes_size]
      omega
    have h :=
      decodeU32le_encode_midV1
        (left ++ taggedHeaderBytesV1 "ValueDef" 2 ++ encodeU32le 0) right 0 (nesting + 1)
    -- transport along input/offset identities
    have h' :
        decodeU32le
            ⟨left ++ valueDef00BytesV1 ++ right,
              left.size + (taggedHeaderBytesV1 "ValueDef" 2).size + 4, nesting + 1⟩ =
          .ok (0,
            ⟨left ++ valueDef00BytesV1 ++ right,
              left.size + (taggedHeaderBytesV1 "ValueDef" 2).size + 8, nesting + 1⟩) := by
      simpa [hin, hsz] using h
    simpa [htotal] using h'

/-- Public ValueDef leaf. -/
theorem decodeValueDefV1_simpleClosure00_of_encode
    (left right : ByteArray) (b : ByteArray) (nesting : Nat)
    (henc : encodeValueDefV1 { valueId := 0, typeId := 0 } = .ok b)
    (hdepth : nesting < maxNesting) :
    decodeValueDefV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok ({ valueId := 0, typeId := 0 },
        ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hb : b = valueDef00BytesV1 := Except.ok.inj (henc.symm.trans encode_valueDef00)
  subst hb
  exact decode_valueDef00_mid left right nesting hdepth

/-! ### Fixed encode spines (production encoder equality via rfl) -/

theorem encode_litTrueInstruction :
    encodeInstructionV1 simpleClosureLitTrueV1 = .ok (
      taggedBytesV1 "Instruction"
        #[encodeU8 1 ++ valueDef00BytesV1,
          taggedBytesV1 "Op.Literal" #[encodeU32le 0, encodeU32le 1 ++ encodeU8 1]]) := by
  rfl

theorem encode_termReturn0 :
    encodeTerminatorV1 (.return_ (some 0)) =
      .ok (taggedBytesV1 "Term.Return" #[encodeU8 1 ++ encodeU32le 0]) := by
  rfl

theorem encode_simpleClosureBlock :
    encodeBlockV1 simpleClosureBlockV1 = .ok (
      taggedBytesV1 "Block"
        #[encodeU32le 0, encodeU32le 0,
          encodeU32le 1 ++
            taggedBytesV1 "Instruction"
              #[encodeU8 1 ++ valueDef00BytesV1,
                taggedBytesV1 "Op.Literal" #[encodeU32le 0, encodeU32le 1 ++ encodeU8 1]],
          taggedBytesV1 "Term.Return" #[encodeU8 1 ++ encodeU32le 0]]) := by
  rfl

theorem encode_kindView :
    encodeCallableKindV1 .view = .ok (taggedBytesV1 "Callable.View" #[]) := by rfl

theorem encode_kindInv :
    encodeCallableKindV1 .invariant = .ok (taggedBytesV1 "Callable.Invariant" #[]) := by rfl

theorem encode_callableResultPublicBool :
    encodeCallableResultV1 { typeId := 0, visibility := .public_ } =
      .ok (taggedBytesV1 "CallableResult"
        #[encodeU32le 0, taggedBytesV1 "Visibility.Public" #[]]) := by
  rfl

theorem encode_emptyParams :
    encodeArray encodeParameterV1 #[] = .ok (encodeU32le 0) :=
  encodeArray_zeroV1 _

theorem encode_emptyLoops :
    encodeArray encodeLoopBoundV1 #[] = .ok (encodeU32le 0) :=
  encodeArray_zeroV1 _

theorem encode_stepsNone :
    encodeOption (fun v => pure (encodeU64le v)) none = .ok (encodeU8 0) := by rfl

theorem encode_stepsSome3 :
    encodeOption (fun v => pure (encodeU64le v)) (some 3) =
      .ok (encodeU8 1 ++ encodeU64le 3) := by rfl

theorem encodeOptionString_of_identifier (s : String)
    (h : validateIdentifierComponent s = .ok ()) :
    encodeOption encodeString (some s) = .ok (someStringPayloadBytesV1 s) := by
  simp only [encodeOption, encodeString_of_identifierV1 s h, Bind.bind, Pure.pure,
    Except.bind, Except.pure, someStringPayloadBytesV1, encodeU8, ByteArray.append_eq]

def viewCallableBytesV1 (viewName : String) : ByteArray :=
  taggedBytesV1 "Callable"
    #[encodeU32le 0, taggedBytesV1 "Callable.View" #[],
      someStringPayloadBytesV1 viewName, encodeU32le 0,
      taggedBytesV1 "CallableResult" #[encodeU32le 0, taggedBytesV1 "Visibility.Public" #[]],
      encodeU32le 0,
      encodeU32le 1 ++
        taggedBytesV1 "Block"
          #[encodeU32le 0, encodeU32le 0,
            encodeU32le 1 ++
              taggedBytesV1 "Instruction"
                #[encodeU8 1 ++ valueDef00BytesV1,
                  taggedBytesV1 "Op.Literal" #[encodeU32le 0, encodeU32le 1 ++ encodeU8 1]],
            taggedBytesV1 "Term.Return" #[encodeU8 1 ++ encodeU32le 0]],
      encodeU32le 0, encodeU8 0]

def invCallableBytesV1 (invName : String) : ByteArray :=
  taggedBytesV1 "Callable"
    #[encodeU32le 1, taggedBytesV1 "Callable.Invariant" #[],
      someStringPayloadBytesV1 invName, encodeU32le 0,
      taggedBytesV1 "CallableResult" #[encodeU32le 0, taggedBytesV1 "Visibility.Public" #[]],
      encodeU32le 0,
      encodeU32le 1 ++
        taggedBytesV1 "Block"
          #[encodeU32le 0, encodeU32le 0,
            encodeU32le 1 ++
              taggedBytesV1 "Instruction"
                #[encodeU8 1 ++ valueDef00BytesV1,
                  taggedBytesV1 "Op.Literal" #[encodeU32le 0, encodeU32le 1 ++ encodeU8 1]],
            taggedBytesV1 "Term.Return" #[encodeU8 1 ++ encodeU32le 0]],
      encodeU32le 0, encodeU8 1 ++ encodeU64le 3]

theorem encode_viewCallable_of_legal (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) :
    encodeCallableV1 (simpleClosureViewCallableV1 p.viewName) =
      .ok (viewCallableBytesV1 p.viewName) := by
  apply encodeCallableV1_eq_of_fields (simpleClosureViewCallableV1 p.viewName)
    (taggedBytesV1 "Callable.View" #[]) (someStringPayloadBytesV1 p.viewName)
    (encodeU32le 0)
    (taggedBytesV1 "CallableResult" #[encodeU32le 0, taggedBytesV1 "Visibility.Public" #[]])
    (encodeU32le 1 ++
      taggedBytesV1 "Block"
        #[encodeU32le 0, encodeU32le 0,
          encodeU32le 1 ++
            taggedBytesV1 "Instruction"
              #[encodeU8 1 ++ valueDef00BytesV1,
                taggedBytesV1 "Op.Literal" #[encodeU32le 0, encodeU32le 1 ++ encodeU8 1]],
          taggedBytesV1 "Term.Return" #[encodeU8 1 ++ encodeU32le 0]])
    (encodeU32le 0) (encodeU8 0) (viewCallableBytesV1 p.viewName)
  · exact encode_kindView
  · exact encodeOptionString_of_identifier p.viewName legal.hview
  · exact encode_emptyParams
  · exact encode_callableResultPublicBool
  · have hblock := encode_simpleClosureBlock
    have harr :=
      encodeArray_oneV1 encodeBlockV1 simpleClosureBlockV1
        (taggedBytesV1 "Block"
          #[encodeU32le 0, encodeU32le 0,
            encodeU32le 1 ++
              taggedBytesV1 "Instruction"
                #[encodeU8 1 ++ valueDef00BytesV1,
                  taggedBytesV1 "Op.Literal" #[encodeU32le 0, encodeU32le 1 ++ encodeU8 1]],
            taggedBytesV1 "Term.Return" #[encodeU8 1 ++ encodeU32le 0]])
        hblock
    exact harr
  · exact encode_emptyLoops
  · exact encode_stepsNone
  · simp only [viewCallableBytesV1, simpleClosureViewCallableV1]
    let fields : Array ByteArray :=
      #[encodeU32le 0, taggedBytesV1 "Callable.View" #[],
        someStringPayloadBytesV1 p.viewName, encodeU32le 0,
        taggedBytesV1 "CallableResult" #[encodeU32le 0, taggedBytesV1 "Visibility.Public" #[]],
        encodeU32le 0,
        encodeU32le 1 ++
          taggedBytesV1 "Block"
            #[encodeU32le 0, encodeU32le 0,
              encodeU32le 1 ++
                taggedBytesV1 "Instruction"
                  #[encodeU8 1 ++ valueDef00BytesV1,
                    taggedBytesV1 "Op.Literal" #[encodeU32le 0, encodeU32le 1 ++ encodeU8 1]],
              taggedBytesV1 "Term.Return" #[encodeU8 1 ++ encodeU32le 0]],
        encodeU32le 0, encodeU8 0]
    have hsz : fields.size = 9 := rfl
    exact encodeTagged_eq_okV1 "Callable" fields
      (by decide) isAsciiTag_Callable (by decide) (by decide)
      (by rw [hsz]; decide)

theorem encode_invCallable_of_legal (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) :
    encodeCallableV1 (simpleClosureInvCallableV1 p.invName) =
      .ok (invCallableBytesV1 p.invName) := by
  apply encodeCallableV1_eq_of_fields (simpleClosureInvCallableV1 p.invName)
    (taggedBytesV1 "Callable.Invariant" #[]) (someStringPayloadBytesV1 p.invName)
    (encodeU32le 0)
    (taggedBytesV1 "CallableResult" #[encodeU32le 0, taggedBytesV1 "Visibility.Public" #[]])
    (encodeU32le 1 ++
      taggedBytesV1 "Block"
        #[encodeU32le 0, encodeU32le 0,
          encodeU32le 1 ++
            taggedBytesV1 "Instruction"
              #[encodeU8 1 ++ valueDef00BytesV1,
                taggedBytesV1 "Op.Literal" #[encodeU32le 0, encodeU32le 1 ++ encodeU8 1]],
          taggedBytesV1 "Term.Return" #[encodeU8 1 ++ encodeU32le 0]])
    (encodeU32le 0) (encodeU8 1 ++ encodeU64le 3) (invCallableBytesV1 p.invName)
  · exact encode_kindInv
  · exact encodeOptionString_of_identifier p.invName legal.hinv
  · exact encode_emptyParams
  · exact encode_callableResultPublicBool
  · have hblock := encode_simpleClosureBlock
    exact encodeArray_oneV1 encodeBlockV1 simpleClosureBlockV1
      (taggedBytesV1 "Block"
        #[encodeU32le 0, encodeU32le 0,
          encodeU32le 1 ++
            taggedBytesV1 "Instruction"
              #[encodeU8 1 ++ valueDef00BytesV1,
                taggedBytesV1 "Op.Literal" #[encodeU32le 0, encodeU32le 1 ++ encodeU8 1]],
          taggedBytesV1 "Term.Return" #[encodeU8 1 ++ encodeU32le 0]])
      hblock
  · exact encode_emptyLoops
  · exact encode_stepsSome3
  · simp only [invCallableBytesV1, simpleClosureInvCallableV1]
    let fields : Array ByteArray :=
      #[encodeU32le 1, taggedBytesV1 "Callable.Invariant" #[],
        someStringPayloadBytesV1 p.invName, encodeU32le 0,
        taggedBytesV1 "CallableResult" #[encodeU32le 0, taggedBytesV1 "Visibility.Public" #[]],
        encodeU32le 0,
        encodeU32le 1 ++
          taggedBytesV1 "Block"
            #[encodeU32le 0, encodeU32le 0,
              encodeU32le 1 ++
                taggedBytesV1 "Instruction"
                  #[encodeU8 1 ++ valueDef00BytesV1,
                    taggedBytesV1 "Op.Literal" #[encodeU32le 0, encodeU32le 1 ++ encodeU8 1]],
              taggedBytesV1 "Term.Return" #[encodeU8 1 ++ encodeU32le 0]],
        encodeU32le 0, encodeU8 1 ++ encodeU64le 3]
    have hsz : fields.size = 9 := rfl
    exact encodeTagged_eq_okV1 "Callable" fields
      (by decide) isAsciiTag_Callable (by decide) (by decide)
      (by rw [hsz]; decide)

def callablesArrayBytesV1 (p : SimpleClosureParamsV1) : ByteArray :=
  encodeU32le 2 ++ viewCallableBytesV1 p.viewName ++ invCallableBytesV1 p.invName

theorem encode_callablesArray_of_legal (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) :
    encodeArray encodeCallableV1
        #[simpleClosureViewCallableV1 p.viewName, simpleClosureInvCallableV1 p.invName] =
      .ok (callablesArrayBytesV1 p) := by
  have h :=
    encodeArray_twoV1 encodeCallableV1
      (simpleClosureViewCallableV1 p.viewName) (simpleClosureInvCallableV1 p.invName)
      (viewCallableBytesV1 p.viewName) (invCallableBytesV1 p.invName)
      (encode_viewCallable_of_legal p legal) (encode_invCallable_of_legal p legal)
  simpa [callablesArrayBytesV1, ByteArray.append_assoc] using h

/-! ### Demo Legal params (no Tests FQN) -/

def demoParamsV1 : SimpleClosureParamsV1 :=
  { qnHead := "Module", qnTail := #["Prog"], viewName := "alive", invName := "safe" }

private theorem ident_Module : validateIdentifierComponent "Module" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "Module" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]; simp only [Pure.pure, Except.pure]; rfl

private theorem ident_Prog : validateIdentifierComponent "Prog" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "Prog" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]; simp only [Pure.pure, Except.pure]; rfl

private theorem ident_alive : validateIdentifierComponent "alive" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "alive" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]; simp only [Pure.pure, Except.pure]; rfl

private theorem ident_safe : validateIdentifierComponent "safe" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "safe" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]; simp only [Pure.pure, Except.pure]; rfl

theorem demoParams_legal : SimpleClosureParamsLegalV1 demoParamsV1 := by
  refine {
    hqnSize := by decide, hdistinct := by decide, hqnHead := ident_Module,
    hqnTail := ?_, hview := ident_alive, hinv := ident_safe }
  intro i hi
  have : i = 0 := by simp [demoParamsV1] at hi; omega
  subst this; exact ident_Prog

def unicodeLegalParamsV1 : SimpleClosureParamsV1 :=
  { qnHead := "ModuleΑ", qnTail := #["ProgΒ"], viewName := "aliveΑ", invName := "safeΒ" }

end ProofForgeV2.Semantic.SimpleClosureDecodeCallableV1
