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

/-! ### Named fixed payload aliases (defeq to encode spines) -/

def opLiteralTrueBytesV1 : ByteArray :=
  taggedBytesV1 "Op.Literal" #[encodeU32le 0, encodeU32le 1 ++ encodeU8 1]

def litTrueInstructionBytesV1 : ByteArray :=
  taggedBytesV1 "Instruction"
    #[encodeU8 1 ++ valueDef00BytesV1, opLiteralTrueBytesV1]

def termReturn0BytesV1 : ByteArray :=
  taggedBytesV1 "Term.Return" #[encodeU8 1 ++ encodeU32le 0]

def simpleClosureBlockBytesV1 : ByteArray :=
  taggedBytesV1 "Block"
    #[encodeU32le 0, encodeU32le 0,
      encodeU32le 1 ++ litTrueInstructionBytesV1, termReturn0BytesV1]

def callableKindViewBytesV1 : ByteArray := taggedBytesV1 "Callable.View" #[]
def callableKindInvBytesV1 : ByteArray := taggedBytesV1 "Callable.Invariant" #[]
def visibilityPublicBytesV1 : ByteArray := taggedBytesV1 "Visibility.Public" #[]
def callableResultPublicBoolBytesV1 : ByteArray :=
  taggedBytesV1 "CallableResult" #[encodeU32le 0, visibilityPublicBytesV1]

theorem viewCallableBytes_eq (viewName : String) :
    viewCallableBytesV1 viewName =
      taggedBytesV1 "Callable"
        #[encodeU32le 0, callableKindViewBytesV1, someStringPayloadBytesV1 viewName,
          encodeU32le 0, callableResultPublicBoolBytesV1, encodeU32le 0,
          encodeU32le 1 ++ simpleClosureBlockBytesV1, encodeU32le 0, encodeU8 0] := by
  simp [viewCallableBytesV1, callableKindViewBytesV1, callableResultPublicBoolBytesV1,
    visibilityPublicBytesV1, simpleClosureBlockBytesV1, litTrueInstructionBytesV1,
    opLiteralTrueBytesV1, termReturn0BytesV1]

theorem invCallableBytes_eq (invName : String) :
    invCallableBytesV1 invName =
      taggedBytesV1 "Callable"
        #[encodeU32le 1, callableKindInvBytesV1, someStringPayloadBytesV1 invName,
          encodeU32le 0, callableResultPublicBoolBytesV1, encodeU32le 0,
          encodeU32le 1 ++ simpleClosureBlockBytesV1, encodeU32le 0,
          encodeU8 1 ++ encodeU64le 3] := by
  simp [invCallableBytesV1, callableKindInvBytesV1, callableResultPublicBoolBytesV1,
    visibilityPublicBytesV1, simpleClosureBlockBytesV1, litTrueInstructionBytesV1,
    opLiteralTrueBytesV1, termReturn0BytesV1]

/-! ### Scalar / option / tag decode mid-offset helpers -/

theorem decodeTag_ascii_midV1 (left right : ByteArray) (tag : String) (nesting : Nat)
    (hnonempty : 1 ≤ tag.toUTF8.size)
    (hlimit : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (hasciiBytes : isAsciiTagBytesV1 tag.toUTF8 = true)
    (hasciiTag : isAsciiTagV1 tag = true) :
    decodeTag
        ⟨left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++ right,
          left.size, nesting⟩ =
      .ok (tag,
        ⟨left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++ right,
          left.size + 4 + tag.toUTF8.size, nesting⟩) :=
  decodeTag_eq_of_valueV1 _
    tag.toUTF8 (left.size + 4 + tag.toUTF8.size) tag
    (readTagBytes_ascii_midV1 left right tag hnonempty hlimit hasciiBytes)
    (fromUTF8?_toUTF8V1 tag) hasciiTag

theorem decodeU16le_encode_midV1 (left right : ByteArray) (v : UInt16) (nesting : Nat) :
    decodeU16le ⟨left ++ encodeU16le v ++ right, left.size, nesting⟩ =
      .ok (v, ⟨left ++ encodeU16le v ++ right, left.size + 2, nesting⟩) := by
  apply decodeU16le_eq_of_readV1
  exact readU16le_encode_midV1 left right v

theorem decodeFieldCount_encode_midV1 (left right : ByteArray) (expected nesting : Nat)
    (hfit : expected ≤ UInt16.size - 1) :
    decodeFieldCount expected
        ⟨left ++ encodeU16le (UInt16.ofNat expected) ++ right, left.size, nesting⟩ =
      .ok ((),
        ⟨left ++ encodeU16le (UInt16.ofNat expected) ++ right, left.size + 2, nesting⟩) := by
  let c : Cursor := ⟨left ++ encodeU16le (UInt16.ofNat expected) ++ right, left.size, nesting⟩
  have hread : readU16leAtV1 c.input c.offset =
      .ok (UInt16.ofNat expected, left.size + 2) :=
    readU16le_encode_midV1 left right (UInt16.ofNat expected)
  have h := decodeFieldCount_eq_of_readU16leV1 expected c
    (UInt16.ofNat expected) (left.size + 2) hread
  have hto : (UInt16.ofNat expected).toNat = expected :=
    Nat.mod_eq_of_lt (Nat.lt_of_le_of_lt hfit (by decide))
  simp only [c, h, hto, beq_self_eq_true, ↓reduceIte]

theorem decodeU8_zero_payload_midV1 (left right : ByteArray) (nesting : Nat) :
    decodeU8 ⟨left ++ ByteArray.empty.push 0 ++ right, left.size, nesting⟩ =
      .ok (0, ⟨left ++ ByteArray.empty.push 0 ++ right, left.size + 1, nesting⟩) := by
  have hone : (ByteArray.empty.push 0).size = 1 := by
    simp [ByteArray.size_push, ByteArray.size_empty]
  have hget : (ByteArray.empty.push 0).data[0]? = some 0 := by
    simp [ByteArray.data_push, ByteArray.data_empty]
  apply decodeU8_eq_of_readV1
  exact readByte_mid_payloadV1 left (ByteArray.empty.push 0) right 0 0
    (by simp [hone]) hget

theorem encodeU64le_sizeV1 (v : UInt64) : (encodeU64le v).size = 8 := by
  simp [encodeU64le, ByteArray.size_push, ByteArray.size_empty]

theorem readU64le_encode3_midV1 (left right : ByteArray) :
    readU64leAtV1 (left ++ encodeU64le 3 ++ right) left.size =
      .ok (3, left.size + 8) := by
  have hs : (encodeU64le 3).size = 8 := encodeU64le_sizeV1 3
  have d0 : (encodeU64le 3).data[0]? = some 3 := by
    simp [encodeU64le, ByteArray.data_push, ByteArray.data_empty]
  have d1 : (encodeU64le 3).data[1]? = some 0 := by
    simp [encodeU64le, ByteArray.data_push, ByteArray.data_empty]
  have d2 : (encodeU64le 3).data[2]? = some 0 := by
    simp [encodeU64le, ByteArray.data_push, ByteArray.data_empty]
  have d3 : (encodeU64le 3).data[3]? = some 0 := by
    simp [encodeU64le, ByteArray.data_push, ByteArray.data_empty]
  have d4 : (encodeU64le 3).data[4]? = some 0 := by
    simp [encodeU64le, ByteArray.data_push, ByteArray.data_empty]
  have d5 : (encodeU64le 3).data[5]? = some 0 := by
    simp [encodeU64le, ByteArray.data_push, ByteArray.data_empty]
  have d6 : (encodeU64le 3).data[6]? = some 0 := by
    simp [encodeU64le, ByteArray.data_push, ByteArray.data_empty]
  have d7 : (encodeU64le 3).data[7]? = some 0 := by
    simp [encodeU64le, ByteArray.data_push, ByteArray.data_empty]
  have r0 := readByte_mid_payloadV1 left (encodeU64le 3) right 0 3 (by rw [hs]; decide) d0
  have r1 := readByte_mid_payloadV1 left (encodeU64le 3) right 1 0 (by rw [hs]; decide) d1
  have r2 := readByte_mid_payloadV1 left (encodeU64le 3) right 2 0 (by rw [hs]; decide) d2
  have r3 := readByte_mid_payloadV1 left (encodeU64le 3) right 3 0 (by rw [hs]; decide) d3
  have r4 := readByte_mid_payloadV1 left (encodeU64le 3) right 4 0 (by rw [hs]; decide) d4
  have r5 := readByte_mid_payloadV1 left (encodeU64le 3) right 5 0 (by rw [hs]; decide) d5
  have r6 := readByte_mid_payloadV1 left (encodeU64le 3) right 6 0 (by rw [hs]; decide) d6
  have r7 := readByte_mid_payloadV1 left (encodeU64le 3) right 7 0 (by rw [hs]; decide) d7
  have r0' : readByteAtV1 (left ++ encodeU64le 3 ++ right) left.size = .ok 3 := by
    simpa using r0
  unfold readU64leAtV1
  simp only [r0', r1, r2, r3, r4, r5, r6, r7, Bind.bind, Pure.pure, Except.bind, Except.pure]
  rfl

theorem decodeU64le_encode3_midV1 (left right : ByteArray) (nesting : Nat) :
    decodeU64le ⟨left ++ encodeU64le 3 ++ right, left.size, nesting⟩ =
      .ok (3, ⟨left ++ encodeU64le 3 ++ right, left.size + 8, nesting⟩) := by
  apply decodeU64le_eq_of_readV1
  exact readU64le_encode3_midV1 left right

theorem decodeByteArray_u8one_mid (left right : ByteArray) (nesting : Nat) :
    decodeByteArray maxCanonicalProgramBytes
        ⟨left ++ encodeU32le 1 ++ encodeU8 1 ++ right, left.size, nesting⟩ =
      .ok (encodeU8 1,
        ⟨left ++ encodeU32le 1 ++ encodeU8 1 ++ right, left.size + 4 + 1, nesting⟩) := by
  have hin :
      left ++ encodeU32le 1 ++ encodeU8 1 ++ right =
        left ++ encodeU32le 1 ++ (encodeU8 1 ++ right) := by
    simp [ByteArray.append_assoc]
  rw [hin]
  have hread := readU32le_encode_midV1 left (encodeU8 1 ++ right) 1
  unfold decodeByteArray readSizedBytesAtV1
  simp only [hread]
  have hfit : (1 : UInt32).toNat = 1 := rfl
  simp only [hfit]
  have hlim : ¬((1 : Nat) > maxCanonicalProgramBytes) := by decide
  simp only [hlim, ↓reduceIte]
  have hs1 : (encodeU32le 1).size = 4 := encodeU32le_sizeV1 _
  have hoff : (left ++ encodeU32le 1).size = left.size + 4 := by
    rw [ByteArray.size_append, hs1]
  have hA :
      left ++ encodeU32le 1 ++ (encodeU8 1 ++ right) =
        (left ++ encodeU32le 1) ++ encodeU8 1 ++ right := by
    simp [ByteArray.append_assoc]
  have hpay : (encodeU8 1).size = 1 := by
    simp [encodeU8, ByteArray.size_push, ByteArray.size_empty]
  have htake :
      takeBytesAtV1 (left ++ encodeU32le 1 ++ (encodeU8 1 ++ right))
          (left.size + 4) 1 = .ok (encodeU8 1) := by
    rw [hA, ← hoff, ← hpay]
    exact takeBytes_mid_payloadV1 _ (encodeU8 1) right
  simp only [htake, Bind.bind, Pure.pure, Except.bind, Except.pure]

theorem decodeOption_none_u64_midV1 (left right : ByteArray) (nesting : Nat) :
    decodeOption decodeU64le
        ⟨left ++ encodeU8 0 ++ right, left.size, nesting⟩ =
      .ok (none, ⟨left ++ encodeU8 0 ++ right, left.size + 1, nesting⟩) := by
  have hin : encodeU8 0 = ByteArray.empty.push 0 := rfl
  rw [hin]
  apply decodeOption_noneV1
  exact decodeU8_zero_payload_midV1 left right nesting

theorem decodeOption_some_u64_3_midV1 (left right : ByteArray) (nesting : Nat) :
    decodeOption decodeU64le
        ⟨left ++ encodeU8 1 ++ encodeU64le 3 ++ right, left.size, nesting⟩ =
      .ok (some 3,
        ⟨left ++ encodeU8 1 ++ encodeU64le 3 ++ right, left.size + 1 + 8, nesting⟩) := by
  have hin :
      left ++ encodeU8 1 ++ encodeU64le 3 ++ right =
        left ++ ByteArray.empty.push 1 ++ encodeU64le 3 ++ right := by
    simp [encodeU8, ByteArray.append_assoc]
  rw [hin]
  have hmarker :=
    decodeU8_one_payload_midV1 left (encodeU64le 3 ++ right) nesting
  have hleft1 : (left ++ ByteArray.empty.push 1).size = left.size + 1 := by
    simp [ByteArray.size_append, ByteArray.size_push, ByteArray.size_empty]
  have hin2 :
      left ++ ByteArray.empty.push 1 ++ encodeU64le 3 ++ right =
        (left ++ ByteArray.empty.push 1) ++ encodeU64le 3 ++ right := by
    simp [ByteArray.append_assoc]
  have hval :
      decodeU64le
          ⟨left ++ ByteArray.empty.push 1 ++ encodeU64le 3 ++ right,
            left.size + 1, nesting⟩ =
        .ok (3,
          ⟨left ++ ByteArray.empty.push 1 ++ encodeU64le 3 ++ right,
            left.size + 1 + 8, nesting⟩) := by
    rw [hin2]
    have h := decodeU64le_encode3_midV1 (left ++ ByteArray.empty.push 1) right nesting
    simpa [hleft1] using h
  exact decodeOption_someV1 decodeU64le
    ⟨left ++ ByteArray.empty.push 1 ++ encodeU64le 3 ++ right, left.size, nesting⟩
    ⟨left ++ ByteArray.empty.push 1 ++ encodeU64le 3 ++ right, left.size + 1, nesting⟩
    ⟨left ++ ByteArray.empty.push 1 ++ encodeU64le 3 ++ right, left.size + 1 + 8, nesting⟩
    3 (by simpa [ByteArray.append_assoc] using hmarker) hval

theorem decodeOption_some_valueDef00_mid (left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) :
    decodeOption decodeValueDefV1
        ⟨left ++ encodeU8 1 ++ valueDef00BytesV1 ++ right, left.size, nesting⟩ =
      .ok (some { valueId := 0, typeId := 0 },
        ⟨left ++ encodeU8 1 ++ valueDef00BytesV1 ++ right,
          left.size + 1 + valueDef00BytesV1.size, nesting⟩) := by
  have hin :
      left ++ encodeU8 1 ++ valueDef00BytesV1 ++ right =
        left ++ ByteArray.empty.push 1 ++ valueDef00BytesV1 ++ right := by
    simp [encodeU8, ByteArray.append_assoc]
  rw [hin]
  have hmarker :=
    decodeU8_one_payload_midV1 left (valueDef00BytesV1 ++ right) nesting
  have hleft1 : (left ++ ByteArray.empty.push 1).size = left.size + 1 := by
    simp [ByteArray.size_append, ByteArray.size_push, ByteArray.size_empty]
  have hin2 :
      left ++ ByteArray.empty.push 1 ++ valueDef00BytesV1 ++ right =
        (left ++ ByteArray.empty.push 1) ++ valueDef00BytesV1 ++ right := by
    simp [ByteArray.append_assoc]
  have hval :=
    decode_valueDef00_mid (left ++ ByteArray.empty.push 1) right nesting hdepth
  have hval' :
      decodeValueDefV1
          ⟨left ++ ByteArray.empty.push 1 ++ valueDef00BytesV1 ++ right,
            left.size + 1, nesting⟩ =
        .ok ({ valueId := 0, typeId := 0 },
          ⟨left ++ ByteArray.empty.push 1 ++ valueDef00BytesV1 ++ right,
            left.size + 1 + valueDef00BytesV1.size, nesting⟩) := by
    rw [hin2]; simpa [hleft1] using hval
  exact decodeOption_someV1 decodeValueDefV1
    ⟨left ++ ByteArray.empty.push 1 ++ valueDef00BytesV1 ++ right, left.size, nesting⟩
    ⟨left ++ ByteArray.empty.push 1 ++ valueDef00BytesV1 ++ right, left.size + 1, nesting⟩
    ⟨left ++ ByteArray.empty.push 1 ++ valueDef00BytesV1 ++ right,
      left.size + 1 + valueDef00BytesV1.size, nesting⟩
    { valueId := 0, typeId := 0 }
    (by simpa [ByteArray.append_assoc] using hmarker) hval'

theorem decodeOption_some_u32_0_mid (left right : ByteArray) (nesting : Nat) :
    decodeOption decodeU32le
        ⟨left ++ encodeU8 1 ++ encodeU32le 0 ++ right, left.size, nesting⟩ =
      .ok (some 0,
        ⟨left ++ encodeU8 1 ++ encodeU32le 0 ++ right, left.size + 1 + 4, nesting⟩) := by
  have hin :
      left ++ encodeU8 1 ++ encodeU32le 0 ++ right =
        left ++ ByteArray.empty.push 1 ++ encodeU32le 0 ++ right := by
    simp [encodeU8, ByteArray.append_assoc]
  rw [hin]
  have hmarker := decodeU8_one_payload_midV1 left (encodeU32le 0 ++ right) nesting
  have hleft1 : (left ++ ByteArray.empty.push 1).size = left.size + 1 := by
    simp [ByteArray.size_append, ByteArray.size_push, ByteArray.size_empty]
  have hin2 :
      left ++ ByteArray.empty.push 1 ++ encodeU32le 0 ++ right =
        (left ++ ByteArray.empty.push 1) ++ encodeU32le 0 ++ right := by
    simp [ByteArray.append_assoc]
  have hval :
      decodeU32le
          ⟨left ++ ByteArray.empty.push 1 ++ encodeU32le 0 ++ right,
            left.size + 1, nesting⟩ =
        .ok (0,
          ⟨left ++ ByteArray.empty.push 1 ++ encodeU32le 0 ++ right,
            left.size + 1 + 4, nesting⟩) := by
    rw [hin2]
    have h := decodeU32le_encode_midV1 (left ++ ByteArray.empty.push 1) right 0 nesting
    simpa [hleft1] using h
  exact decodeOption_someV1 decodeU32le
    ⟨left ++ ByteArray.empty.push 1 ++ encodeU32le 0 ++ right, left.size, nesting⟩
    ⟨left ++ ByteArray.empty.push 1 ++ encodeU32le 0 ++ right, left.size + 1, nesting⟩
    ⟨left ++ ByteArray.empty.push 1 ++ encodeU32le 0 ++ right, left.size + 1 + 4, nesting⟩
    0 (by simpa [ByteArray.append_assoc] using hmarker) hval

/-! ### Op.Literal true decode -/

theorem decode_opLiteralTrue_mid (left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) :
    decodeSemanticOpV1 ⟨left ++ opLiteralTrueBytesV1 ++ right, left.size, nesting⟩ =
      .ok (.literal 0 (encodeU8 1),
        ⟨left ++ opLiteralTrueBytesV1 ++ right,
          left.size + opLiteralTrueBytesV1.size, nesting⟩) := by
  have hshape :
      opLiteralTrueBytesV1 =
        encodeU32le (UInt32.ofNat "Op.Literal".toUTF8.size) ++ "Op.Literal".toUTF8 ++
          encodeU16le (UInt16.ofNat 2) ++ encodeU32le 0 ++ encodeU32le 1 ++ encodeU8 1 := by
    simp only [opLiteralTrueBytesV1]
    have h := taggedBytes_two_eq "Op.Literal" (encodeU32le 0) (encodeU32le 1 ++ encodeU8 1)
    simp only [h, taggedHeaderBytesV1]
    simp [ByteArray.append_assoc]
  have hsz :
      opLiteralTrueBytesV1.size =
        4 + "Op.Literal".toUTF8.size + 2 + 4 + 4 + 1 := by
    simp [hshape, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1, encodeU8,
      ByteArray.size_push, ByteArray.size_empty]
  have hpay :
      left ++ opLiteralTrueBytesV1 ++ right =
        left ++ encodeU32le (UInt32.ofNat "Op.Literal".toUTF8.size) ++ "Op.Literal".toUTF8 ++
          encodeU16le (UInt16.ofNat 2) ++ encodeU32le 0 ++ encodeU32le 1 ++ encodeU8 1 ++
          right := by
    simp [hshape, ByteArray.append_assoc]
  rw [hpay]
  let input :=
    left ++ encodeU32le (UInt32.ofNat "Op.Literal".toUTF8.size) ++ "Op.Literal".toUTF8 ++
      encodeU16le (UInt16.ofNat 2) ++ encodeU32le 0 ++ encodeU32le 1 ++ encodeU8 1 ++ right
  change decodeSemanticOpV1 ⟨input, left.size, nesting⟩ =
    .ok (.literal 0 (encodeU8 1),
      ⟨input, left.size + opLiteralTrueBytesV1.size, nesting⟩)
  have htag :
      decodeTag ⟨input, left.size, nesting + 1⟩ =
        .ok ("Op.Literal",
          ⟨input, left.size + 4 + "Op.Literal".toUTF8.size, nesting + 1⟩) := by
    have hin :
        input =
          left ++ encodeU32le (UInt32.ofNat "Op.Literal".toUTF8.size) ++
            "Op.Literal".toUTF8 ++
            (encodeU16le (UInt16.ofNat 2) ++ encodeU32le 0 ++ encodeU32le 1 ++
              encodeU8 1 ++ right) := by
      simp only [input, ByteArray.append_assoc]
    have h :=
      decodeTag_ascii_midV1 left
        (encodeU16le (UInt16.ofNat 2) ++ encodeU32le 0 ++ encodeU32le 1 ++
          encodeU8 1 ++ right)
        "Op.Literal" (nesting + 1) (by decide) (by decide)
        isAsciiTagBytes_Op_Literal isAsciiTag_Op_Literal
    rw [hin]; exact h
  have hfields :
      decodeFieldCount 2
          ⟨input, left.size + 4 + "Op.Literal".toUTF8.size, nesting + 1⟩ =
        .ok ((),
          ⟨input, left.size + 4 + "Op.Literal".toUTF8.size + 2, nesting + 1⟩) := by
    let L := left ++ encodeU32le (UInt32.ofNat "Op.Literal".toUTF8.size) ++
      "Op.Literal".toUTF8
    let R := encodeU32le 0 ++ encodeU32le 1 ++ encodeU8 1 ++ right
    have hin : input = L ++ encodeU16le (UInt16.ofNat 2) ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = left.size + 4 + "Op.Literal".toUTF8.size := by
      simp [L, ByteArray.size_append, encodeU32le_sizeV1]
    have h := decodeFieldCount_encode_midV1 L R 2 (nesting + 1) (by decide)
    rw [← hin, hL] at h
    exact h
  have htype :
      decodeU32le
          ⟨input, left.size + 4 + "Op.Literal".toUTF8.size + 2, nesting + 1⟩ =
        .ok (0,
          ⟨input, left.size + 4 + "Op.Literal".toUTF8.size + 2 + 4, nesting + 1⟩) := by
    let L := left ++ encodeU32le (UInt32.ofNat "Op.Literal".toUTF8.size) ++
      "Op.Literal".toUTF8 ++ encodeU16le (UInt16.ofNat 2)
    let R := encodeU32le 1 ++ encodeU8 1 ++ right
    have hin : input = L ++ encodeU32le 0 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = left.size + 4 + "Op.Literal".toUTF8.size + 2 := by
      simp [L, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1]
    have h := decodeU32le_encode_midV1 L R 0 (nesting + 1)
    rw [← hin, hL] at h
    exact h
  have hbytes :
      decodeByteArray maxCanonicalProgramBytes
          ⟨input, left.size + 4 + "Op.Literal".toUTF8.size + 2 + 4, nesting + 1⟩ =
        .ok (encodeU8 1,
          ⟨input, left.size + 4 + "Op.Literal".toUTF8.size + 2 + 4 + 4 + 1,
            nesting + 1⟩) := by
    let L := left ++ encodeU32le (UInt32.ofNat "Op.Literal".toUTF8.size) ++
      "Op.Literal".toUTF8 ++ encodeU16le (UInt16.ofNat 2) ++ encodeU32le 0
    let R := right
    have hin : input = L ++ encodeU32le 1 ++ encodeU8 1 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = left.size + 4 + "Op.Literal".toUTF8.size + 2 + 4 := by
      simp [L, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1]
    have h := decodeByteArray_u8one_mid L R (nesting + 1)
    rw [← hin, hL] at h
    exact h
  have hend :
      left.size + 4 + "Op.Literal".toUTF8.size + 2 + 4 + 4 + 1 =
        left.size + opLiteralTrueBytesV1.size := by
    rw [hsz]; omega
  have hbody :=
    decodeSemanticOpV1_literal
      ⟨input, left.size, nesting⟩
      ⟨input, left.size + 4 + "Op.Literal".toUTF8.size, nesting + 1⟩
      ⟨input, left.size + 4 + "Op.Literal".toUTF8.size + 2, nesting + 1⟩
      ⟨input, left.size + 4 + "Op.Literal".toUTF8.size + 2 + 4, nesting + 1⟩
      ⟨input, left.size + 4 + "Op.Literal".toUTF8.size + 2 + 4 + 4 + 1, nesting + 1⟩
      0 (encodeU8 1) hdepth htag hfields htype hbytes
  rw [hend] at hbody
  exact hbody

/-! ### Instruction lit-true decode -/

theorem decode_litTrueInstruction_mid (left right : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting) :
    decodeInstructionV1 ⟨left ++ litTrueInstructionBytesV1 ++ right, left.size, nesting⟩ =
      .ok (simpleClosureLitTrueV1,
        ⟨left ++ litTrueInstructionBytesV1 ++ right,
          left.size + litTrueInstructionBytesV1.size, nesting⟩) := by
  have hdepth0 : nesting < maxNesting := Nat.lt_of_succ_lt hdepth
  have hdepth1 : nesting + 1 < maxNesting := hdepth
  have hshape :
      litTrueInstructionBytesV1 =
        encodeU32le (UInt32.ofNat "Instruction".toUTF8.size) ++ "Instruction".toUTF8 ++
          encodeU16le (UInt16.ofNat 2) ++ encodeU8 1 ++ valueDef00BytesV1 ++
          opLiteralTrueBytesV1 := by
    simp only [litTrueInstructionBytesV1]
    have h := taggedBytes_two_eq "Instruction" (encodeU8 1 ++ valueDef00BytesV1)
      opLiteralTrueBytesV1
    simp only [h, taggedHeaderBytesV1]
    simp [ByteArray.append_assoc]
  have hsz :
      litTrueInstructionBytesV1.size =
        4 + "Instruction".toUTF8.size + 2 + 1 + valueDef00BytesV1.size +
          opLiteralTrueBytesV1.size := by
    simp [hshape, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1, encodeU8,
      ByteArray.size_push, ByteArray.size_empty]
  have hpay :
      left ++ litTrueInstructionBytesV1 ++ right =
        left ++ encodeU32le (UInt32.ofNat "Instruction".toUTF8.size) ++ "Instruction".toUTF8 ++
          encodeU16le (UInt16.ofNat 2) ++ encodeU8 1 ++ valueDef00BytesV1 ++
          opLiteralTrueBytesV1 ++ right := by
    simp [hshape, ByteArray.append_assoc]
  rw [hpay]
  let input :=
    left ++ encodeU32le (UInt32.ofNat "Instruction".toUTF8.size) ++ "Instruction".toUTF8 ++
      encodeU16le (UInt16.ofNat 2) ++ encodeU8 1 ++ valueDef00BytesV1 ++
      opLiteralTrueBytesV1 ++ right
  change decodeInstructionV1 ⟨input, left.size, nesting⟩ =
    .ok (simpleClosureLitTrueV1,
      ⟨input, left.size + litTrueInstructionBytesV1.size, nesting⟩)
  -- expectTag Instruction 2
  have htag :
      expectTag "Instruction" 2 ⟨input, left.size, nesting + 1⟩ =
        .ok ((), ⟨input, left.size + (4 + "Instruction".toUTF8.size + 2), nesting + 1⟩) := by
    let L := left
    let R := encodeU8 1 ++ valueDef00BytesV1 ++ opLiteralTrueBytesV1 ++ right
    have hin : input =
        L ++ taggedHeaderBytesV1 "Instruction" (UInt16.ofNat 2) ++ R := by
      simp only [input, L, R, taggedHeaderBytesV1, ByteArray.append_assoc]
    have h :=
      expectTag_header_midV1 L R "Instruction" 2 (nesting + 1)
        (by decide) (by decide) isAsciiTagBytes_Instruction (by decide)
    have hszH := taggedHeaderBytes_size "Instruction" (UInt16.ofNat 2)
    rw [← hin, hszH] at h
    simpa [L] using h
  -- option some ValueDef
  have hresult :
      decodeOption decodeValueDefV1
          ⟨input, left.size + (4 + "Instruction".toUTF8.size + 2), nesting + 1⟩ =
        .ok (some { valueId := 0, typeId := 0 },
          ⟨input,
            left.size + (4 + "Instruction".toUTF8.size + 2) + 1 + valueDef00BytesV1.size,
            nesting + 1⟩) := by
    let L := left ++ encodeU32le (UInt32.ofNat "Instruction".toUTF8.size) ++
      "Instruction".toUTF8 ++ encodeU16le (UInt16.ofNat 2)
    let R := opLiteralTrueBytesV1 ++ right
    have hin : input = L ++ encodeU8 1 ++ valueDef00BytesV1 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = left.size + (4 + "Instruction".toUTF8.size + 2) := by
      simp [L, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1]
      omega
    have h := decodeOption_some_valueDef00_mid L R (nesting + 1) hdepth1
    rw [← hin, hL] at h
    exact h
  -- op literal
  have hop :
      decodeSemanticOpV1
          ⟨input,
            left.size + (4 + "Instruction".toUTF8.size + 2) + 1 + valueDef00BytesV1.size,
            nesting + 1⟩ =
        .ok (.literal 0 (encodeU8 1),
          ⟨input,
            left.size + (4 + "Instruction".toUTF8.size + 2) + 1 + valueDef00BytesV1.size +
              opLiteralTrueBytesV1.size,
            nesting + 1⟩) := by
    let L := left ++ encodeU32le (UInt32.ofNat "Instruction".toUTF8.size) ++
      "Instruction".toUTF8 ++ encodeU16le (UInt16.ofNat 2) ++ encodeU8 1 ++
      valueDef00BytesV1
    let R := right
    have hin : input = L ++ opLiteralTrueBytesV1 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size =
        left.size + (4 + "Instruction".toUTF8.size + 2) + 1 + valueDef00BytesV1.size := by
      simp [L, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1, encodeU8,
        ByteArray.size_push, ByteArray.size_empty]
      omega
    have h := decode_opLiteralTrue_mid L R (nesting + 1) hdepth1
    rw [← hin, hL] at h
    exact h
  have hend :
      left.size + (4 + "Instruction".toUTF8.size + 2) + 1 + valueDef00BytesV1.size +
          opLiteralTrueBytesV1.size =
        left.size + litTrueInstructionBytesV1.size := by
    rw [hsz]; omega
  have hbody :=
    decodeInstructionV1_eq_of_fieldsV1
      ⟨input, left.size, nesting⟩
      ⟨input, left.size + (4 + "Instruction".toUTF8.size + 2), nesting + 1⟩
      ⟨input,
        left.size + (4 + "Instruction".toUTF8.size + 2) + 1 + valueDef00BytesV1.size,
        nesting + 1⟩
      ⟨input,
        left.size + (4 + "Instruction".toUTF8.size + 2) + 1 + valueDef00BytesV1.size +
          opLiteralTrueBytesV1.size,
        nesting + 1⟩
      (some { valueId := 0, typeId := 0 })
      (.literal 0 (encodeU8 1)) hdepth0 htag hresult hop
  -- align simpleClosureLitTrueV1
  have hlit : simpleClosureLitTrueV1 =
      { result := some { valueId := 0, typeId := 0 },
        op := .literal 0 (encodeU8 1) } := by
    simp [simpleClosureLitTrueV1]
  rw [← hlit] at hbody
  rw [hend] at hbody
  exact hbody

/-! ### Term.Return some 0 decode -/

theorem decode_termReturn0_mid (left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) :
    decodeTerminatorV1 ⟨left ++ termReturn0BytesV1 ++ right, left.size, nesting⟩ =
      .ok (.return_ (some 0),
        ⟨left ++ termReturn0BytesV1 ++ right,
          left.size + termReturn0BytesV1.size, nesting⟩) := by
  have hshape :
      termReturn0BytesV1 =
        encodeU32le (UInt32.ofNat "Term.Return".toUTF8.size) ++ "Term.Return".toUTF8 ++
          encodeU16le (UInt16.ofNat 1) ++ encodeU8 1 ++ encodeU32le 0 := by
    simp only [termReturn0BytesV1]
    have h := taggedBytes_one_eq "Term.Return" (encodeU8 1 ++ encodeU32le 0)
    simp only [h, taggedHeaderBytesV1]
    simp [ByteArray.append_assoc]
  have hsz :
      termReturn0BytesV1.size = 4 + "Term.Return".toUTF8.size + 2 + 1 + 4 := by
    simp [hshape, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1, encodeU8,
      ByteArray.size_push, ByteArray.size_empty]
  have hpay :
      left ++ termReturn0BytesV1 ++ right =
        left ++ encodeU32le (UInt32.ofNat "Term.Return".toUTF8.size) ++ "Term.Return".toUTF8 ++
          encodeU16le (UInt16.ofNat 1) ++ encodeU8 1 ++ encodeU32le 0 ++ right := by
    simp [hshape, ByteArray.append_assoc]
  rw [hpay]
  let input :=
    left ++ encodeU32le (UInt32.ofNat "Term.Return".toUTF8.size) ++ "Term.Return".toUTF8 ++
      encodeU16le (UInt16.ofNat 1) ++ encodeU8 1 ++ encodeU32le 0 ++ right
  change decodeTerminatorV1 ⟨input, left.size, nesting⟩ =
    .ok (.return_ (some 0),
      ⟨input, left.size + termReturn0BytesV1.size, nesting⟩)
  have htag :
      decodeTag ⟨input, left.size, nesting + 1⟩ =
        .ok ("Term.Return",
          ⟨input, left.size + (4 + "Term.Return".toUTF8.size), nesting + 1⟩) := by
    have hin :
        input =
          left ++ encodeU32le (UInt32.ofNat "Term.Return".toUTF8.size) ++
            "Term.Return".toUTF8 ++
            (encodeU16le (UInt16.ofNat 1) ++ encodeU8 1 ++ encodeU32le 0 ++ right) := by
      simp only [input, ByteArray.append_assoc]
    have h :=
      decodeTag_ascii_midV1 left
        (encodeU16le (UInt16.ofNat 1) ++ encodeU8 1 ++ encodeU32le 0 ++ right)
        "Term.Return" (nesting + 1) (by decide) (by decide)
        isAsciiTagBytes_Term_Return isAsciiTag_Term_Return
    rw [hin]; exact h
  have hfields :
      decodeFieldCount 1
          ⟨input, left.size + (4 + "Term.Return".toUTF8.size), nesting + 1⟩ =
        .ok ((),
          ⟨input, left.size + (4 + "Term.Return".toUTF8.size + 2), nesting + 1⟩) := by
    let L := left ++ encodeU32le (UInt32.ofNat "Term.Return".toUTF8.size) ++
      "Term.Return".toUTF8
    let R := encodeU8 1 ++ encodeU32le 0 ++ right
    have hin : input = L ++ encodeU16le (UInt16.ofNat 1) ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = left.size + (4 + "Term.Return".toUTF8.size) := by
      simp [L, ByteArray.size_append, encodeU32le_sizeV1]
      omega
    have h := decodeFieldCount_encode_midV1 L R 1 (nesting + 1) (by decide)
    rw [← hin, hL] at h
    exact h
  have hval :
      decodeOption decodeU32le
          ⟨input, left.size + (4 + "Term.Return".toUTF8.size + 2), nesting + 1⟩ =
        .ok (some 0,
          ⟨input, left.size + (4 + "Term.Return".toUTF8.size + 2 + 1 + 4),
            nesting + 1⟩) := by
    let L := left ++ encodeU32le (UInt32.ofNat "Term.Return".toUTF8.size) ++
      "Term.Return".toUTF8 ++ encodeU16le (UInt16.ofNat 1)
    let R := right
    have hin : input = L ++ encodeU8 1 ++ encodeU32le 0 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = left.size + (4 + "Term.Return".toUTF8.size + 2) := by
      simp [L, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1]
      omega
    have h := decodeOption_some_u32_0_mid L R (nesting + 1)
    rw [← hin, hL] at h
    exact h
  have hend :
      left.size + (4 + "Term.Return".toUTF8.size + 2 + 1 + 4) =
        left.size + termReturn0BytesV1.size := by
    rw [hsz]
  have hbody :=
    decodeTerminatorV1_return
      ⟨input, left.size, nesting⟩
      ⟨input, left.size + (4 + "Term.Return".toUTF8.size), nesting + 1⟩
      ⟨input, left.size + (4 + "Term.Return".toUTF8.size + 2), nesting + 1⟩
      ⟨input, left.size + (4 + "Term.Return".toUTF8.size + 2 + 1 + 4), nesting + 1⟩
      (some 0) hdepth htag hfields hval
  rw [hend] at hbody
  exact hbody

/-! ### Block decode -/

theorem decode_simpleClosureBlock_mid (left right : ByteArray) (nesting : Nat)
    (hdepth : nesting + 2 < maxNesting) :
    decodeBlockV1 ⟨left ++ simpleClosureBlockBytesV1 ++ right, left.size, nesting⟩ =
      .ok (simpleClosureBlockV1,
        ⟨left ++ simpleClosureBlockBytesV1 ++ right,
          left.size + simpleClosureBlockBytesV1.size, nesting⟩) := by
  have hdepth0 : nesting < maxNesting := by omega
  have hdepth1 : nesting + 1 < maxNesting := by omega
  have hdepth2 : nesting + 2 < maxNesting := hdepth
  have hshape :
      simpleClosureBlockBytesV1 =
        encodeU32le (UInt32.ofNat "Block".toUTF8.size) ++ "Block".toUTF8 ++
          encodeU16le (UInt16.ofNat 4) ++ encodeU32le 0 ++ encodeU32le 0 ++
          encodeU32le 1 ++ litTrueInstructionBytesV1 ++ termReturn0BytesV1 := by
    simp only [simpleClosureBlockBytesV1]
    have h := taggedBytes_four_eq "Block" (encodeU32le 0) (encodeU32le 0)
      (encodeU32le 1 ++ litTrueInstructionBytesV1) termReturn0BytesV1
    simp only [h, taggedHeaderBytesV1]
    simp [ByteArray.append_assoc]
  have hsz :
      simpleClosureBlockBytesV1.size =
        4 + "Block".toUTF8.size + 2 + 4 + 4 + 4 + litTrueInstructionBytesV1.size +
          termReturn0BytesV1.size := by
    simp [hshape, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1]
  have hpay :
      left ++ simpleClosureBlockBytesV1 ++ right =
        left ++ encodeU32le (UInt32.ofNat "Block".toUTF8.size) ++ "Block".toUTF8 ++
          encodeU16le (UInt16.ofNat 4) ++ encodeU32le 0 ++ encodeU32le 0 ++
          encodeU32le 1 ++ litTrueInstructionBytesV1 ++ termReturn0BytesV1 ++ right := by
    simp [hshape, ByteArray.append_assoc]
  rw [hpay]
  let input :=
    left ++ encodeU32le (UInt32.ofNat "Block".toUTF8.size) ++ "Block".toUTF8 ++
      encodeU16le (UInt16.ofNat 4) ++ encodeU32le 0 ++ encodeU32le 0 ++
      encodeU32le 1 ++ litTrueInstructionBytesV1 ++ termReturn0BytesV1 ++ right
  change decodeBlockV1 ⟨input, left.size, nesting⟩ =
    .ok (simpleClosureBlockV1,
      ⟨input, left.size + simpleClosureBlockBytesV1.size, nesting⟩)
  let oHdr := left.size + (4 + "Block".toUTF8.size + 2)
  let oId := oHdr + 4
  let oParams := oId + 4
  let oInstrHdr := oParams + 4
  let oInstrEnd := oInstrHdr + litTrueInstructionBytesV1.size
  let oEnd := oInstrEnd + termReturn0BytesV1.size
  have hend : oEnd = left.size + simpleClosureBlockBytesV1.size := by
    simp only [oEnd, oInstrEnd, oInstrHdr, oParams, oId, oHdr, hsz]; omega
  -- expectTag Block 4
  have htag :
      expectTag "Block" 4 ⟨input, left.size, nesting + 1⟩ =
        .ok ((), ⟨input, oHdr, nesting + 1⟩) := by
    let L := left
    let R := encodeU32le 0 ++ encodeU32le 0 ++ encodeU32le 1 ++
      litTrueInstructionBytesV1 ++ termReturn0BytesV1 ++ right
    have hin : input = L ++ taggedHeaderBytesV1 "Block" (UInt16.ofNat 4) ++ R := by
      simp only [input, L, R, taggedHeaderBytesV1, ByteArray.append_assoc]
    have h := expectTag_header_midV1 L R "Block" 4 (nesting + 1)
      (by decide) (by decide) isAsciiTagBytes_Block (by decide)
    have hszH := taggedHeaderBytes_size "Block" (UInt16.ofNat 4)
    rw [← hin, hszH] at h
    simpa [L, oHdr] using h
  have hid :
      decodeU32le ⟨input, oHdr, nesting + 1⟩ =
        .ok (0, ⟨input, oId, nesting + 1⟩) := by
    let L := left ++ encodeU32le (UInt32.ofNat "Block".toUTF8.size) ++ "Block".toUTF8 ++
      encodeU16le (UInt16.ofNat 4)
    let R := encodeU32le 0 ++ encodeU32le 1 ++ litTrueInstructionBytesV1 ++
      termReturn0BytesV1 ++ right
    have hin : input = L ++ encodeU32le 0 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = oHdr := by
      simp [L, oHdr, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1]
      omega
    have h := decodeU32le_encode_midV1 L R 0 (nesting + 1)
    rw [← hin, hL] at h
    simpa [oId, oHdr] using h
  have hparams :
      readArrayCountAtV1 input oId maxArrayElements = .ok (0, oParams) := by
    let L := left ++ encodeU32le (UInt32.ofNat "Block".toUTF8.size) ++ "Block".toUTF8 ++
      encodeU16le (UInt16.ofNat 4) ++ encodeU32le (UInt32.ofNat 0)
    let R := encodeU32le (UInt32.ofNat 1) ++ litTrueInstructionBytesV1 ++ termReturn0BytesV1 ++ right
    have hin : input = L ++ encodeU32le (UInt32.ofNat 0) ++ R := by
      simp [input, L, R, ByteArray.append_assoc]
    have hL : L.size = oId := by
      simp [L, oId, oHdr, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1]
      omega
    have h := readArrayCount_encode_midV1 L R 0 maxArrayElements (by decide) (by decide)
    -- h uses encodeU32le (UInt32.ofNat 0) from ofNat 0
    rw [← hin, hL] at h
    have : oParams = oId + 4 := rfl
    simpa [this, oParams, oId] using h
  have hinstrCount :
      readArrayCountAtV1 input oParams maxArrayElements = .ok (1, oInstrHdr) := by
    let L := left ++ encodeU32le (UInt32.ofNat "Block".toUTF8.size) ++ "Block".toUTF8 ++
      encodeU16le (UInt16.ofNat 4) ++ encodeU32le (UInt32.ofNat 0) ++ encodeU32le (UInt32.ofNat 0)
    let R := litTrueInstructionBytesV1 ++ termReturn0BytesV1 ++ right
    have hin : input = L ++ encodeU32le (UInt32.ofNat 1) ++ R := by
      simp [input, L, R, ByteArray.append_assoc]
    have hL : L.size = oParams := by
      simp [L, oParams, oId, oHdr, ByteArray.size_append, encodeU32le_sizeV1,
        encodeU16le_sizeV1]
      omega
    have h := readArrayCount_encode_midV1 L R 1 maxArrayElements (by decide) (by decide)
    rw [← hin, hL] at h
    have : oInstrHdr = oParams + 4 := rfl
    simpa [this, oInstrHdr, oParams] using h
  have hinstr :
      decodeInstructionV1 ⟨input, oInstrHdr, nesting + 1⟩ =
        .ok (simpleClosureLitTrueV1, ⟨input, oInstrEnd, nesting + 1⟩) := by
    let L := left ++ encodeU32le (UInt32.ofNat "Block".toUTF8.size) ++ "Block".toUTF8 ++
      encodeU16le (UInt16.ofNat 4) ++ encodeU32le 0 ++ encodeU32le 0 ++ encodeU32le 1
    let R := termReturn0BytesV1 ++ right
    have hin : input = L ++ litTrueInstructionBytesV1 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = oInstrHdr := by
      simp [L, oInstrHdr, oParams, oId, oHdr, ByteArray.size_append, encodeU32le_sizeV1,
        encodeU16le_sizeV1]
      omega
    have h := decode_litTrueInstruction_mid L R (nesting + 1) hdepth2
    rw [← hin, hL] at h
    simpa [oInstrEnd, oInstrHdr] using h
  have hterm :
      decodeTerminatorV1 ⟨input, oInstrEnd, nesting + 1⟩ =
        .ok (.return_ (some 0), ⟨input, oEnd, nesting + 1⟩) := by
    let L := left ++ encodeU32le (UInt32.ofNat "Block".toUTF8.size) ++ "Block".toUTF8 ++
      encodeU16le (UInt16.ofNat 4) ++ encodeU32le 0 ++ encodeU32le 0 ++ encodeU32le 1 ++
      litTrueInstructionBytesV1
    let R := right
    have hin : input = L ++ termReturn0BytesV1 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = oInstrEnd := by
      simp [L, oInstrEnd, oInstrHdr, oParams, oId, oHdr, ByteArray.size_append,
        encodeU32le_sizeV1, encodeU16le_sizeV1]
      omega
    have h := decode_termReturn0_mid L R (nesting + 1) hdepth1
    rw [← hin, hL] at h
    simpa [oEnd, oInstrEnd] using h
  have hbody :=
    decodeBlockV1_oneInstructionV1
      ⟨input, left.size, nesting⟩
      ⟨input, oHdr, nesting + 1⟩
      ⟨input, oId, nesting + 1⟩
      ⟨input, oInstrEnd, nesting + 1⟩
      ⟨input, oEnd, nesting + 1⟩
      oParams oInstrHdr 0 simpleClosureLitTrueV1 (.return_ (some 0)) hdepth0
      htag hid hparams hinstrCount hinstr hterm
  rw [hend] at hbody
  exact hbody


/-! ### CallableKind / Visibility / CallableResult mid-offset -/

private theorem u16_ofNat0 : encodeU16le (UInt16.ofNat 0) = encodeU16le 0 := rfl
private theorem u32_ofNat0 : encodeU32le (UInt32.ofNat 0) = encodeU32le 0 := rfl
private theorem u32_ofNat1 : encodeU32le (UInt32.ofNat 1) = encodeU32le 1 := rfl

theorem someStringPayloadBytes_sizeV1 (s : String) :
    (someStringPayloadBytesV1 s).size = 1 + 4 + s.toUTF8.size := by
  simp [someStringPayloadBytesV1, stringPayloadBytesV1,
    ByteArray.size_append, encodeU32le_sizeV1, encodeU8, ByteArray.size_push,
    ByteArray.size_empty]
  omega

theorem callableKindViewBytes_size :
    callableKindViewBytesV1.size = 4 + "Callable.View".toUTF8.size + 2 := by
  have h := taggedBytes_zero_eq "Callable.View"
  simp [callableKindViewBytesV1, h, taggedHeaderBytes_size]

theorem callableKindInvBytes_size :
    callableKindInvBytesV1.size = 4 + "Callable.Invariant".toUTF8.size + 2 := by
  have h := taggedBytes_zero_eq "Callable.Invariant"
  simp [callableKindInvBytesV1, h, taggedHeaderBytes_size]

theorem visibilityPublicBytes_size :
    visibilityPublicBytesV1.size = 4 + "Visibility.Public".toUTF8.size + 2 := by
  have h := taggedBytes_zero_eq "Visibility.Public"
  simp [visibilityPublicBytesV1, h, taggedHeaderBytes_size]

theorem callableResultPublicBoolBytes_size :
    callableResultPublicBoolBytesV1.size =
      4 + "CallableResult".toUTF8.size + 2 + 4 + visibilityPublicBytesV1.size := by
  have h := taggedBytes_two_eq "CallableResult" (encodeU32le 0) visibilityPublicBytesV1
  simp [callableResultPublicBoolBytesV1, h, taggedHeaderBytes_size,
    ByteArray.size_append, encodeU32le_sizeV1]

theorem decode_kindView_mid (left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) :
    decodeCallableKindV1 ⟨left ++ callableKindViewBytesV1 ++ right, left.size, nesting⟩ =
      .ok (.view,
        ⟨left ++ callableKindViewBytesV1 ++ right,
          left.size + callableKindViewBytesV1.size, nesting⟩) := by
  have hshape :
      callableKindViewBytesV1 =
        encodeU32le (UInt32.ofNat "Callable.View".toUTF8.size) ++ "Callable.View".toUTF8 ++
          encodeU16le 0 := by
    simp only [callableKindViewBytesV1]
    have h := taggedBytes_zero_eq "Callable.View"
    simp only [h, taggedHeaderBytesV1]
  have hsz :
      callableKindViewBytesV1.size = 4 + "Callable.View".toUTF8.size + 2 := by
    simp [hshape, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1]
  have hpay :
      left ++ callableKindViewBytesV1 ++ right =
        left ++ encodeU32le (UInt32.ofNat "Callable.View".toUTF8.size) ++
          "Callable.View".toUTF8 ++ encodeU16le 0 ++ right := by
    simp [hshape, ByteArray.append_assoc]
  rw [hpay]
  let payP :=
    left ++ encodeU32le (UInt32.ofNat "Callable.View".toUTF8.size) ++
      "Callable.View".toUTF8 ++ (encodeU16le 0 ++ right)
  let payF :=
    left ++ encodeU32le (UInt32.ofNat "Callable.View".toUTF8.size) ++
      "Callable.View".toUTF8 ++ encodeU16le 0 ++ right
  have hPF : payP = payF := by simp [payP, payF, ByteArray.append_assoc]
  have hbodyP :
      decodeCallableKindBodyV1 ⟨payP, left.size, nesting + 1⟩ =
        .ok (.view, ⟨payP, left.size + callableKindViewBytesV1.size, nesting + 1⟩) := by
    apply decodeCallableKindBodyV1_view
    · exact decodeTag_ascii_midV1 left (encodeU16le 0 ++ right)
        "Callable.View" (nesting + 1) (by decide) (by decide)
        isAsciiTagBytes_Callable_View isAsciiTag_Callable_View
    · let L := left ++ encodeU32le (UInt32.ofNat "Callable.View".toUTF8.size) ++
        "Callable.View".toUTF8
      let R := right
      have hin : payP = L ++ encodeU16le (UInt16.ofNat 0) ++ R := by
        simp only [payP, L, R, ByteArray.append_assoc, u16_ofNat0]
      have hL : L.size = left.size + 4 + "Callable.View".toUTF8.size := by
        simp [L, ByteArray.size_append, encodeU32le_sizeV1]
      have h := decodeFieldCount_encode_midV1 L R 0 (nesting + 1) (by decide)
      rw [← hin, hL] at h
      have hend : left.size + 4 + "Callable.View".toUTF8.size + 2 =
          left.size + callableKindViewBytesV1.size := by
        rw [hsz]; omega
      rw [hend] at h
      exact h
  have hbodyF :
      decodeCallableKindBodyV1 ⟨payF, left.size, nesting + 1⟩ =
        .ok (.view, ⟨payF, left.size + callableKindViewBytesV1.size, nesting + 1⟩) := by
    simpa [hPF] using hbodyP
  exact decodeCallableKindV1_eq_of_bodyV1
    ⟨payF, left.size, nesting⟩ .view
    ⟨payF, left.size + callableKindViewBytesV1.size, nesting + 1⟩
    hdepth hbodyF

theorem decode_kindInv_mid (left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) :
    decodeCallableKindV1 ⟨left ++ callableKindInvBytesV1 ++ right, left.size, nesting⟩ =
      .ok (.invariant,
        ⟨left ++ callableKindInvBytesV1 ++ right,
          left.size + callableKindInvBytesV1.size, nesting⟩) := by
  have hshape :
      callableKindInvBytesV1 =
        encodeU32le (UInt32.ofNat "Callable.Invariant".toUTF8.size) ++
          "Callable.Invariant".toUTF8 ++ encodeU16le 0 := by
    simp only [callableKindInvBytesV1]
    have h := taggedBytes_zero_eq "Callable.Invariant"
    simp only [h, taggedHeaderBytesV1]
  have hsz :
      callableKindInvBytesV1.size = 4 + "Callable.Invariant".toUTF8.size + 2 := by
    simp [hshape, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1]
  have hpay :
      left ++ callableKindInvBytesV1 ++ right =
        left ++ encodeU32le (UInt32.ofNat "Callable.Invariant".toUTF8.size) ++
          "Callable.Invariant".toUTF8 ++ encodeU16le 0 ++ right := by
    simp [hshape, ByteArray.append_assoc]
  rw [hpay]
  let payP :=
    left ++ encodeU32le (UInt32.ofNat "Callable.Invariant".toUTF8.size) ++
      "Callable.Invariant".toUTF8 ++ (encodeU16le 0 ++ right)
  let payF :=
    left ++ encodeU32le (UInt32.ofNat "Callable.Invariant".toUTF8.size) ++
      "Callable.Invariant".toUTF8 ++ encodeU16le 0 ++ right
  have hPF : payP = payF := by simp [payP, payF, ByteArray.append_assoc]
  have hbodyP :
      decodeCallableKindBodyV1 ⟨payP, left.size, nesting + 1⟩ =
        .ok (.invariant, ⟨payP, left.size + callableKindInvBytesV1.size, nesting + 1⟩) := by
    apply decodeCallableKindBodyV1_invariant
    · exact decodeTag_ascii_midV1 left (encodeU16le 0 ++ right)
        "Callable.Invariant" (nesting + 1) (by decide) (by decide)
        isAsciiTagBytes_Callable_Invariant isAsciiTag_Callable_Invariant
    · let L := left ++ encodeU32le (UInt32.ofNat "Callable.Invariant".toUTF8.size) ++
        "Callable.Invariant".toUTF8
      let R := right
      have hin : payP = L ++ encodeU16le (UInt16.ofNat 0) ++ R := by
        simp only [payP, L, R, ByteArray.append_assoc, u16_ofNat0]
      have hL : L.size = left.size + 4 + "Callable.Invariant".toUTF8.size := by
        simp [L, ByteArray.size_append, encodeU32le_sizeV1]
      have h := decodeFieldCount_encode_midV1 L R 0 (nesting + 1) (by decide)
      rw [← hin, hL] at h
      have hend : left.size + 4 + "Callable.Invariant".toUTF8.size + 2 =
          left.size + callableKindInvBytesV1.size := by
        rw [hsz]; omega
      rw [hend] at h
      exact h
  have hbodyF :
      decodeCallableKindBodyV1 ⟨payF, left.size, nesting + 1⟩ =
        .ok (.invariant, ⟨payF, left.size + callableKindInvBytesV1.size, nesting + 1⟩) := by
    simpa [hPF] using hbodyP
  exact decodeCallableKindV1_eq_of_bodyV1
    ⟨payF, left.size, nesting⟩ .invariant
    ⟨payF, left.size + callableKindInvBytesV1.size, nesting + 1⟩
    hdepth hbodyF

theorem decode_visPublic_mid (left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) :
    decodeVisibilityV1 ⟨left ++ visibilityPublicBytesV1 ++ right, left.size, nesting⟩ =
      .ok (.public_,
        ⟨left ++ visibilityPublicBytesV1 ++ right,
          left.size + visibilityPublicBytesV1.size, nesting⟩) := by
  have hshape :
      visibilityPublicBytesV1 =
        encodeU32le (UInt32.ofNat "Visibility.Public".toUTF8.size) ++
          "Visibility.Public".toUTF8 ++ encodeU16le 0 := by
    simp only [visibilityPublicBytesV1]
    have h := taggedBytes_zero_eq "Visibility.Public"
    simp only [h, taggedHeaderBytesV1]
  have hsz :
      visibilityPublicBytesV1.size = 4 + "Visibility.Public".toUTF8.size + 2 := by
    simp [hshape, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1]
  have hpay :
      left ++ visibilityPublicBytesV1 ++ right =
        left ++ encodeU32le (UInt32.ofNat "Visibility.Public".toUTF8.size) ++
          "Visibility.Public".toUTF8 ++ encodeU16le 0 ++ right := by
    simp [hshape, ByteArray.append_assoc]
  rw [hpay]
  let payP :=
    left ++ encodeU32le (UInt32.ofNat "Visibility.Public".toUTF8.size) ++
      "Visibility.Public".toUTF8 ++ (encodeU16le 0 ++ right)
  let payF :=
    left ++ encodeU32le (UInt32.ofNat "Visibility.Public".toUTF8.size) ++
      "Visibility.Public".toUTF8 ++ encodeU16le 0 ++ right
  have hPF : payP = payF := by simp [payP, payF, ByteArray.append_assoc]
  have hbodyP :
      decodeVisibilityBodyV1 ⟨payP, left.size, nesting + 1⟩ =
        .ok (.public_, ⟨payP, left.size + visibilityPublicBytesV1.size, nesting + 1⟩) := by
    apply decodeVisibilityBodyV1_public
    · exact decodeTag_ascii_midV1 left (encodeU16le 0 ++ right)
        "Visibility.Public" (nesting + 1) (by decide) (by decide)
        isAsciiTagBytes_Visibility_Public isAsciiTag_Visibility_Public
    · let L := left ++ encodeU32le (UInt32.ofNat "Visibility.Public".toUTF8.size) ++
        "Visibility.Public".toUTF8
      let R := right
      have hin : payP = L ++ encodeU16le (UInt16.ofNat 0) ++ R := by
        simp only [payP, L, R, ByteArray.append_assoc, u16_ofNat0]
      have hL : L.size = left.size + 4 + "Visibility.Public".toUTF8.size := by
        simp [L, ByteArray.size_append, encodeU32le_sizeV1]
      have h := decodeFieldCount_encode_midV1 L R 0 (nesting + 1) (by decide)
      rw [← hin, hL] at h
      have hend : left.size + 4 + "Visibility.Public".toUTF8.size + 2 =
          left.size + visibilityPublicBytesV1.size := by
        rw [hsz]; omega
      rw [hend] at h
      exact h
  have hbodyF :
      decodeVisibilityBodyV1 ⟨payF, left.size, nesting + 1⟩ =
        .ok (.public_, ⟨payF, left.size + visibilityPublicBytesV1.size, nesting + 1⟩) := by
    simpa [hPF] using hbodyP
  exact decodeVisibilityV1_eq_of_bodyV1
    ⟨payF, left.size, nesting⟩ .public_
    ⟨payF, left.size + visibilityPublicBytesV1.size, nesting + 1⟩
    hdepth hbodyF

theorem decode_callableResultPublicBool_mid (left right : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting) :
    decodeCallableResultV1
        ⟨left ++ callableResultPublicBoolBytesV1 ++ right, left.size, nesting⟩ =
      .ok ({ typeId := 0, visibility := .public_ },
        ⟨left ++ callableResultPublicBoolBytesV1 ++ right,
          left.size + callableResultPublicBoolBytesV1.size, nesting⟩) := by
  have hdepth0 : nesting < maxNesting := Nat.lt_of_succ_lt hdepth
  have hdepth1 : nesting + 1 < maxNesting := hdepth
  have hshape :
      callableResultPublicBoolBytesV1 =
        encodeU32le (UInt32.ofNat "CallableResult".toUTF8.size) ++ "CallableResult".toUTF8 ++
          encodeU16le (UInt16.ofNat 2) ++ encodeU32le 0 ++ visibilityPublicBytesV1 := by
    simp only [callableResultPublicBoolBytesV1]
    have h := taggedBytes_two_eq "CallableResult" (encodeU32le 0) visibilityPublicBytesV1
    simp only [h, taggedHeaderBytesV1]
    simp [ByteArray.append_assoc]
  have hsz :
      callableResultPublicBoolBytesV1.size =
        4 + "CallableResult".toUTF8.size + 2 + 4 + visibilityPublicBytesV1.size := by
    simp [hshape, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1]
  have hpay :
      left ++ callableResultPublicBoolBytesV1 ++ right =
        left ++ encodeU32le (UInt32.ofNat "CallableResult".toUTF8.size) ++
          "CallableResult".toUTF8 ++ encodeU16le (UInt16.ofNat 2) ++
          encodeU32le 0 ++ visibilityPublicBytesV1 ++ right := by
    simp [hshape, ByteArray.append_assoc]
  rw [hpay]
  let input :=
    left ++ encodeU32le (UInt32.ofNat "CallableResult".toUTF8.size) ++
      "CallableResult".toUTF8 ++ encodeU16le (UInt16.ofNat 2) ++
      encodeU32le 0 ++ visibilityPublicBytesV1 ++ right
  change decodeCallableResultV1 ⟨input, left.size, nesting⟩ =
    .ok ({ typeId := 0, visibility := .public_ },
      ⟨input, left.size + callableResultPublicBoolBytesV1.size, nesting⟩)
  have htag :
      expectTag "CallableResult" 2 ⟨input, left.size, nesting + 1⟩ =
        .ok ((),
          ⟨input, left.size + (4 + "CallableResult".toUTF8.size + 2), nesting + 1⟩) := by
    let L := left
    let R := encodeU32le 0 ++ visibilityPublicBytesV1 ++ right
    have hin : input =
        L ++ taggedHeaderBytesV1 "CallableResult" (UInt16.ofNat 2) ++ R := by
      simp only [input, L, R, taggedHeaderBytesV1, ByteArray.append_assoc]
    have h :=
      expectTag_header_midV1 L R "CallableResult" 2 (nesting + 1)
        (by decide) (by decide) isAsciiTagBytes_CallableResult (by decide)
    have hszH := taggedHeaderBytes_size "CallableResult" (UInt16.ofNat 2)
    rw [← hin, hszH] at h
    simpa [L] using h
  have htype :
      decodeU32le
          ⟨input, left.size + (4 + "CallableResult".toUTF8.size + 2), nesting + 1⟩ =
        .ok (0,
          ⟨input, left.size + (4 + "CallableResult".toUTF8.size + 2) + 4,
            nesting + 1⟩) := by
    let L := left ++ encodeU32le (UInt32.ofNat "CallableResult".toUTF8.size) ++
      "CallableResult".toUTF8 ++ encodeU16le (UInt16.ofNat 2)
    let R := visibilityPublicBytesV1 ++ right
    have hin : input = L ++ encodeU32le 0 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = left.size + (4 + "CallableResult".toUTF8.size + 2) := by
      simp [L, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1]
      omega
    have h := decodeU32le_encode_midV1 L R 0 (nesting + 1)
    rw [← hin, hL] at h
    exact h
  have hvis :
      decodeVisibilityV1
          ⟨input, left.size + (4 + "CallableResult".toUTF8.size + 2) + 4, nesting + 1⟩ =
        .ok (.public_,
          ⟨input,
            left.size + (4 + "CallableResult".toUTF8.size + 2) + 4 +
              visibilityPublicBytesV1.size,
            nesting + 1⟩) := by
    let L := left ++ encodeU32le (UInt32.ofNat "CallableResult".toUTF8.size) ++
      "CallableResult".toUTF8 ++ encodeU16le (UInt16.ofNat 2) ++ encodeU32le 0
    let R := right
    have hin : input = L ++ visibilityPublicBytesV1 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = left.size + (4 + "CallableResult".toUTF8.size + 2) + 4 := by
      simp [L, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1]
      omega
    have h := decode_visPublic_mid L R (nesting + 1) hdepth1
    rw [← hin, hL] at h
    exact h
  have hend :
      left.size + (4 + "CallableResult".toUTF8.size + 2) + 4 +
          visibilityPublicBytesV1.size =
        left.size + callableResultPublicBoolBytesV1.size := by
    rw [hsz]; omega
  have hbody :=
    decodeCallableResultBodyV1_eq_of_fields
      ⟨input, left.size, nesting + 1⟩
      ⟨input, left.size + (4 + "CallableResult".toUTF8.size + 2), nesting + 1⟩
      ⟨input, left.size + (4 + "CallableResult".toUTF8.size + 2) + 4, nesting + 1⟩
      ⟨input,
        left.size + (4 + "CallableResult".toUTF8.size + 2) + 4 +
          visibilityPublicBytesV1.size,
        nesting + 1⟩
      0 .public_ htag htype hvis
  have hfull :=
    decodeCallableResultV1_eq_of_bodyV1
      ⟨input, left.size, nesting⟩
      { typeId := 0, visibility := .public_ }
      ⟨input,
        left.size + (4 + "CallableResult".toUTF8.size + 2) + 4 +
          visibilityPublicBytesV1.size,
        nesting + 1⟩
      hdepth0 hbody
  rw [hend] at hfull
  exact hfull


/-! ### View / invariant Callable mid-offset decode -/

/-- Mid-offset production decode of the simple-closure view callable.
    Sole free name premise is identifier legality of `viewName`. -/
theorem decode_viewCallable_mid (left right : ByteArray) (viewName : String)
    (hname : validateIdentifierComponent viewName = .ok ())
    (nesting : Nat) (hdepth : nesting + 3 < maxNesting) :
    decodeCallableV1
        ⟨left ++ viewCallableBytesV1 viewName ++ right, left.size, nesting⟩ =
      .ok (simpleClosureViewCallableV1 viewName,
        ⟨left ++ viewCallableBytesV1 viewName ++ right,
          left.size + (viewCallableBytesV1 viewName).size, nesting⟩) := by
  have hdepth0 : nesting < maxNesting := by omega
  have hdepth1 : nesting + 1 < maxNesting := by omega
  have hdepth2 : nesting + 2 < maxNesting := by omega
  have hdepth3 : nesting + 3 < maxNesting := hdepth
  have hnameSz := someStringPayloadBytes_sizeV1 viewName
  have hbytes := viewCallableBytes_eq viewName
  have hshape :
      viewCallableBytesV1 viewName =
        encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
          encodeU16le (UInt16.ofNat 9) ++
          encodeU32le 0 ++ callableKindViewBytesV1 ++
          someStringPayloadBytesV1 viewName ++ encodeU32le 0 ++
          callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++
          encodeU32le 1 ++ simpleClosureBlockBytesV1 ++
          encodeU32le 0 ++ encodeU8 0 := by
    rw [hbytes]
    have h := taggedBytes_nine_eq "Callable"
      (encodeU32le 0) callableKindViewBytesV1 (someStringPayloadBytesV1 viewName)
      (encodeU32le 0) callableResultPublicBoolBytesV1 (encodeU32le 0)
      (encodeU32le 1 ++ simpleClosureBlockBytesV1) (encodeU32le 0) (encodeU8 0)
    simp only [h, taggedHeaderBytesV1]
    simp [ByteArray.append_assoc]
  have hsz :
      (viewCallableBytesV1 viewName).size =
        4 + "Callable".toUTF8.size + 2 + 4 + callableKindViewBytesV1.size +
          (1 + 4 + viewName.toUTF8.size) + 4 +
          callableResultPublicBoolBytesV1.size + 4 + 4 +
          simpleClosureBlockBytesV1.size + 4 + 1 := by
    simp [hshape, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1,
      encodeU8, ByteArray.size_push, ByteArray.size_empty, hnameSz]
  have hpay :
      left ++ viewCallableBytesV1 viewName ++ right =
        left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
          encodeU16le (UInt16.ofNat 9) ++
          encodeU32le 0 ++ callableKindViewBytesV1 ++
          someStringPayloadBytesV1 viewName ++ encodeU32le 0 ++
          callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++
          encodeU32le 1 ++ simpleClosureBlockBytesV1 ++
          encodeU32le 0 ++ encodeU8 0 ++ right := by
    simp [hshape, ByteArray.append_assoc]
  rw [hpay]
  let input :=
    left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
      encodeU16le (UInt16.ofNat 9) ++
      encodeU32le 0 ++ callableKindViewBytesV1 ++
      someStringPayloadBytesV1 viewName ++ encodeU32le 0 ++
      callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++
      encodeU32le 1 ++ simpleClosureBlockBytesV1 ++
      encodeU32le 0 ++ encodeU8 0 ++ right
  change decodeCallableV1 ⟨input, left.size, nesting⟩ =
    .ok (simpleClosureViewCallableV1 viewName,
      ⟨input, left.size + (viewCallableBytesV1 viewName).size, nesting⟩)
  let oHdr := left.size + (4 + "Callable".toUTF8.size + 2)
  let oId := oHdr + 4
  let oKind := oId + callableKindViewBytesV1.size
  let oName := oKind + 1 + 4 + viewName.toUTF8.size
  let oParams := oName + 4
  let oResult := oParams + callableResultPublicBoolBytesV1.size
  let oEntry := oResult + 4
  let oBlocks := oEntry + 4
  let oBlockEnd := oBlocks + simpleClosureBlockBytesV1.size
  let oLoops := oBlockEnd + 4
  let oEnd := oLoops + 1
  have hend : oEnd = left.size + (viewCallableBytesV1 viewName).size := by
    simp only [oEnd, oLoops, oBlockEnd, oBlocks, oEntry, oResult, oParams, oName,
      oKind, oId, oHdr, hsz]
    omega
  have htag :
      expectTag "Callable" 9 ⟨input, left.size, nesting + 1⟩ =
        .ok ((), ⟨input, oHdr, nesting + 1⟩) := by
    let L := left
    let R :=
      encodeU32le 0 ++ callableKindViewBytesV1 ++ someStringPayloadBytesV1 viewName ++
        encodeU32le 0 ++ callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++
        encodeU32le 1 ++ simpleClosureBlockBytesV1 ++ encodeU32le 0 ++ encodeU8 0 ++
        right
    have hin : input = L ++ taggedHeaderBytesV1 "Callable" (UInt16.ofNat 9) ++ R := by
      simp only [input, L, R, taggedHeaderBytesV1, ByteArray.append_assoc]
    have h := expectTag_header_midV1 L R "Callable" 9 (nesting + 1)
      (by decide) (by decide) isAsciiTagBytes_Callable (by decide)
    have hszH := taggedHeaderBytes_size "Callable" (UInt16.ofNat 9)
    rw [← hin, hszH] at h
    simpa [L, oHdr] using h
  have hid :
      decodeU32le ⟨input, oHdr, nesting + 1⟩ =
        .ok (0, ⟨input, oId, nesting + 1⟩) := by
    let L := left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++
      "Callable".toUTF8 ++ encodeU16le (UInt16.ofNat 9)
    let R :=
      callableKindViewBytesV1 ++ someStringPayloadBytesV1 viewName ++ encodeU32le 0 ++
        callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++ encodeU32le 1 ++
        simpleClosureBlockBytesV1 ++ encodeU32le 0 ++ encodeU8 0 ++ right
    have hin : input = L ++ encodeU32le 0 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = oHdr := by
      simp [L, oHdr, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1]
      omega
    have h := decodeU32le_encode_midV1 L R 0 (nesting + 1)
    rw [← hin, hL] at h
    exact h
  have hkind :
      decodeCallableKindV1 ⟨input, oId, nesting + 1⟩ =
        .ok (.view, ⟨input, oKind, nesting + 1⟩) := by
    let L := left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++
      "Callable".toUTF8 ++ encodeU16le (UInt16.ofNat 9) ++ encodeU32le 0
    let R :=
      someStringPayloadBytesV1 viewName ++ encodeU32le 0 ++
        callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++ encodeU32le 1 ++
        simpleClosureBlockBytesV1 ++ encodeU32le 0 ++ encodeU8 0 ++ right
    have hin : input = L ++ callableKindViewBytesV1 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = oId := by
      simp [L, oId, oHdr, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1]
      omega
    have h := decode_kindView_mid L R (nesting + 1) hdepth1
    rw [← hin, hL] at h
    exact h
  have hnameD :
      decodeOption decodeString ⟨input, oKind, nesting + 1⟩ =
        .ok (some viewName, ⟨input, oName, nesting + 1⟩) := by
    let L :=
      left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
        encodeU16le (UInt16.ofNat 9) ++ encodeU32le 0 ++ callableKindViewBytesV1
    let R :=
      encodeU32le 0 ++ callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++
        encodeU32le 1 ++ simpleClosureBlockBytesV1 ++ encodeU32le 0 ++ encodeU8 0 ++
        right
    have hin : input = L ++ someStringPayloadBytesV1 viewName ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = oKind := by
      simp [L, oKind, oId, oHdr, ByteArray.size_append, encodeU32le_sizeV1,
        encodeU16le_sizeV1]
      omega
    have h :=
      decodeOptionString_some_identifier_midV1 L R viewName (nesting + 1) hname
    rw [← hin, hL] at h
    -- h ends at oKind + 1 + 4 + utf8 = oName by definition
    exact h
  have hparams :
      readArrayCountAtV1 input oName maxArrayElements = .ok (0, oParams) := by
    let L :=
      left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
        encodeU16le (UInt16.ofNat 9) ++ encodeU32le 0 ++ callableKindViewBytesV1 ++
        someStringPayloadBytesV1 viewName
    let R :=
      callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++ encodeU32le 1 ++
        simpleClosureBlockBytesV1 ++ encodeU32le 0 ++ encodeU8 0 ++ right
    have hin : input = L ++ encodeU32le (UInt32.ofNat 0) ++ R := by
      simp only [input, L, R, ByteArray.append_assoc, u32_ofNat0]
    have hL : L.size = oName := by
      simp [L, oName, oKind, oId, oHdr, ByteArray.size_append, encodeU32le_sizeV1,
        encodeU16le_sizeV1, hnameSz]
      omega
    have h := readArrayCount_encode_midV1 L R 0 maxArrayElements (by decide) (by decide)
    rw [← hin, hL] at h
    exact h
  have hresult :
      decodeCallableResultV1 ⟨input, oParams, nesting + 1⟩ =
        .ok ({ typeId := 0, visibility := .public_ },
          ⟨input, oResult, nesting + 1⟩) := by
    let L :=
      left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
        encodeU16le (UInt16.ofNat 9) ++ encodeU32le 0 ++ callableKindViewBytesV1 ++
        someStringPayloadBytesV1 viewName ++ encodeU32le 0
    let R :=
      encodeU32le 0 ++ encodeU32le 1 ++ simpleClosureBlockBytesV1 ++
        encodeU32le 0 ++ encodeU8 0 ++ right
    have hin : input = L ++ callableResultPublicBoolBytesV1 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = oParams := by
      simp [L, oParams, oName, oKind, oId, oHdr, ByteArray.size_append,
        encodeU32le_sizeV1, encodeU16le_sizeV1, hnameSz]
      omega
    have h := decode_callableResultPublicBool_mid L R (nesting + 1) hdepth2
    rw [← hin, hL] at h
    exact h
  have hentry :
      decodeU32le ⟨input, oResult, nesting + 1⟩ =
        .ok (0, ⟨input, oEntry, nesting + 1⟩) := by
    let L :=
      left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
        encodeU16le (UInt16.ofNat 9) ++ encodeU32le 0 ++ callableKindViewBytesV1 ++
        someStringPayloadBytesV1 viewName ++ encodeU32le 0 ++
        callableResultPublicBoolBytesV1
    let R :=
      encodeU32le 1 ++ simpleClosureBlockBytesV1 ++ encodeU32le 0 ++ encodeU8 0 ++ right
    have hin : input = L ++ encodeU32le 0 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = oResult := by
      simp [L, oResult, oParams, oName, oKind, oId, oHdr, ByteArray.size_append,
        encodeU32le_sizeV1, encodeU16le_sizeV1, hnameSz]
      omega
    have h := decodeU32le_encode_midV1 L R 0 (nesting + 1)
    rw [← hin, hL] at h
    exact h
  have hblocksCount :
      readArrayCountAtV1 input oEntry maxArrayElements = .ok (1, oBlocks) := by
    let L :=
      left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
        encodeU16le (UInt16.ofNat 9) ++ encodeU32le 0 ++ callableKindViewBytesV1 ++
        someStringPayloadBytesV1 viewName ++ encodeU32le 0 ++
        callableResultPublicBoolBytesV1 ++ encodeU32le 0
    let R := simpleClosureBlockBytesV1 ++ encodeU32le 0 ++ encodeU8 0 ++ right
    have hin : input = L ++ encodeU32le (UInt32.ofNat 1) ++ R := by
      simp only [input, L, R, ByteArray.append_assoc, u32_ofNat1]
    have hL : L.size = oEntry := by
      simp [L, oEntry, oResult, oParams, oName, oKind, oId, oHdr, ByteArray.size_append,
        encodeU32le_sizeV1, encodeU16le_sizeV1, hnameSz]
      omega
    have h := readArrayCount_encode_midV1 L R 1 maxArrayElements (by decide) (by decide)
    rw [← hin, hL] at h
    exact h
  have hblock :
      decodeBlockV1 ⟨input, oBlocks, nesting + 1⟩ =
        .ok (simpleClosureBlockV1, ⟨input, oBlockEnd, nesting + 1⟩) := by
    let L :=
      left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
        encodeU16le (UInt16.ofNat 9) ++ encodeU32le 0 ++ callableKindViewBytesV1 ++
        someStringPayloadBytesV1 viewName ++ encodeU32le 0 ++
        callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++ encodeU32le 1
    let R := encodeU32le 0 ++ encodeU8 0 ++ right
    have hin : input = L ++ simpleClosureBlockBytesV1 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = oBlocks := by
      simp [L, oBlocks, oEntry, oResult, oParams, oName, oKind, oId, oHdr,
        ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1, hnameSz]
      omega
    have h := decode_simpleClosureBlock_mid L R (nesting + 1) hdepth3
    rw [← hin, hL] at h
    exact h
  have hloops :
      readArrayCountAtV1 input oBlockEnd maxArrayElements = .ok (0, oLoops) := by
    let L :=
      left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
        encodeU16le (UInt16.ofNat 9) ++ encodeU32le 0 ++ callableKindViewBytesV1 ++
        someStringPayloadBytesV1 viewName ++ encodeU32le 0 ++
        callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++ encodeU32le 1 ++
        simpleClosureBlockBytesV1
    let R := encodeU8 0 ++ right
    have hin : input = L ++ encodeU32le (UInt32.ofNat 0) ++ R := by
      simp only [input, L, R, ByteArray.append_assoc, u32_ofNat0]
    have hL : L.size = oBlockEnd := by
      simp [L, oBlockEnd, oBlocks, oEntry, oResult, oParams, oName, oKind, oId, oHdr,
        ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1, hnameSz]
      omega
    have h := readArrayCount_encode_midV1 L R 0 maxArrayElements (by decide) (by decide)
    rw [← hin, hL] at h
    exact h
  have hsteps :
      decodeOption decodeU64le ⟨input, oLoops, nesting + 1⟩ =
        .ok (none, ⟨input, oEnd, nesting + 1⟩) := by
    let L :=
      left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
        encodeU16le (UInt16.ofNat 9) ++ encodeU32le 0 ++ callableKindViewBytesV1 ++
        someStringPayloadBytesV1 viewName ++ encodeU32le 0 ++
        callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++ encodeU32le 1 ++
        simpleClosureBlockBytesV1 ++ encodeU32le 0
    let R := right
    have hin : input = L ++ encodeU8 0 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = oLoops := by
      simp [L, oLoops, oBlockEnd, oBlocks, oEntry, oResult, oParams, oName, oKind, oId,
        oHdr, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1, hnameSz]
      omega
    have h := decodeOption_none_u64_midV1 L R (nesting + 1)
    rw [← hin, hL] at h
    exact h
  have hbody :=
    decodeCallableV1_singleBlockV1
      ⟨input, left.size, nesting⟩
      ⟨input, oHdr, nesting + 1⟩
      ⟨input, oId, nesting + 1⟩
      ⟨input, oKind, nesting + 1⟩
      ⟨input, oName, nesting + 1⟩
      ⟨input, oResult, nesting + 1⟩
      ⟨input, oEntry, nesting + 1⟩
      ⟨input, oBlockEnd, nesting + 1⟩
      ⟨input, oEnd, nesting + 1⟩
      oParams oBlocks oLoops 0 0 .view (some viewName)
      { typeId := 0, visibility := .public_ } simpleClosureBlockV1 none
      hdepth0 htag hid hkind hnameD hparams hresult hentry hblocksCount hblock hloops hsteps
  have hview :
      simpleClosureViewCallableV1 viewName =
        { id := 0, kind := .view, name := some viewName, params := #[],
          result := { typeId := 0, visibility := .public_ }, entryBlock := 0,
          blocks := #[simpleClosureBlockV1], loopBounds := #[], invariantSteps := none } := by
    rfl
  rw [← hview] at hbody
  rw [hend] at hbody
  exact hbody


/-- Mid-offset production decode of the simple-closure invariant callable.
    Sole free name premise is identifier legality of `invName`. -/
theorem decode_invCallable_mid (left right : ByteArray) (invName : String)
    (hname : validateIdentifierComponent invName = .ok ())
    (nesting : Nat) (hdepth : nesting + 3 < maxNesting) :
    decodeCallableV1
        ⟨left ++ invCallableBytesV1 invName ++ right, left.size, nesting⟩ =
      .ok (simpleClosureInvCallableV1 invName,
        ⟨left ++ invCallableBytesV1 invName ++ right,
          left.size + (invCallableBytesV1 invName).size, nesting⟩) := by
  have hdepth0 : nesting < maxNesting := by omega
  have hdepth1 : nesting + 1 < maxNesting := by omega
  have hdepth2 : nesting + 2 < maxNesting := by omega
  have hdepth3 : nesting + 3 < maxNesting := hdepth
  have hnameSz := someStringPayloadBytes_sizeV1 invName
  have hbytes := invCallableBytes_eq invName
  have hshape :
      invCallableBytesV1 invName =
        encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
          encodeU16le (UInt16.ofNat 9) ++
          encodeU32le 1 ++ callableKindInvBytesV1 ++
          someStringPayloadBytesV1 invName ++ encodeU32le 0 ++
          callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++
          encodeU32le 1 ++ simpleClosureBlockBytesV1 ++
          encodeU32le 0 ++ encodeU8 1 ++ encodeU64le 3 := by
    rw [hbytes]
    have h := taggedBytes_nine_eq "Callable"
      (encodeU32le 1) callableKindInvBytesV1 (someStringPayloadBytesV1 invName)
      (encodeU32le 0) callableResultPublicBoolBytesV1 (encodeU32le 0)
      (encodeU32le 1 ++ simpleClosureBlockBytesV1) (encodeU32le 0)
      (encodeU8 1 ++ encodeU64le 3)
    simp only [h, taggedHeaderBytesV1]
    simp [ByteArray.append_assoc]
  have hsz :
      (invCallableBytesV1 invName).size =
        4 + "Callable".toUTF8.size + 2 + 4 + callableKindInvBytesV1.size +
          (1 + 4 + invName.toUTF8.size) + 4 +
          callableResultPublicBoolBytesV1.size + 4 + 4 +
          simpleClosureBlockBytesV1.size + 4 + 1 + 8 := by
    simp [hshape, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1,
      encodeU8, ByteArray.size_push, ByteArray.size_empty, hnameSz, encodeU64le_sizeV1]
  have hpay :
      left ++ invCallableBytesV1 invName ++ right =
        left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
          encodeU16le (UInt16.ofNat 9) ++
          encodeU32le 1 ++ callableKindInvBytesV1 ++
          someStringPayloadBytesV1 invName ++ encodeU32le 0 ++
          callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++
          encodeU32le 1 ++ simpleClosureBlockBytesV1 ++
          encodeU32le 0 ++ encodeU8 1 ++ encodeU64le 3 ++ right := by
    simp [hshape, ByteArray.append_assoc]
  rw [hpay]
  let input :=
    left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
      encodeU16le (UInt16.ofNat 9) ++
      encodeU32le 1 ++ callableKindInvBytesV1 ++
      someStringPayloadBytesV1 invName ++ encodeU32le 0 ++
      callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++
      encodeU32le 1 ++ simpleClosureBlockBytesV1 ++
      encodeU32le 0 ++ encodeU8 1 ++ encodeU64le 3 ++ right
  change decodeCallableV1 ⟨input, left.size, nesting⟩ =
    .ok (simpleClosureInvCallableV1 invName,
      ⟨input, left.size + (invCallableBytesV1 invName).size, nesting⟩)
  let oHdr := left.size + (4 + "Callable".toUTF8.size + 2)
  let oId := oHdr + 4
  let oKind := oId + callableKindInvBytesV1.size
  let oName := oKind + 1 + 4 + invName.toUTF8.size
  let oParams := oName + 4
  let oResult := oParams + callableResultPublicBoolBytesV1.size
  let oEntry := oResult + 4
  let oBlocks := oEntry + 4
  let oBlockEnd := oBlocks + simpleClosureBlockBytesV1.size
  let oLoops := oBlockEnd + 4
  let oEnd := oLoops + 1 + 8
  have hend : oEnd = left.size + (invCallableBytesV1 invName).size := by
    simp only [oEnd, oLoops, oBlockEnd, oBlocks, oEntry, oResult, oParams, oName,
      oKind, oId, oHdr, hsz]
    omega
  have htag :
      expectTag "Callable" 9 ⟨input, left.size, nesting + 1⟩ =
        .ok ((), ⟨input, oHdr, nesting + 1⟩) := by
    let L := left
    let R :=
      encodeU32le 1 ++ callableKindInvBytesV1 ++ someStringPayloadBytesV1 invName ++
        encodeU32le 0 ++ callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++
        encodeU32le 1 ++ simpleClosureBlockBytesV1 ++ encodeU32le 0 ++
        encodeU8 1 ++ encodeU64le 3 ++ right
    have hin : input = L ++ taggedHeaderBytesV1 "Callable" (UInt16.ofNat 9) ++ R := by
      simp only [input, L, R, taggedHeaderBytesV1, ByteArray.append_assoc]
    have h := expectTag_header_midV1 L R "Callable" 9 (nesting + 1)
      (by decide) (by decide) isAsciiTagBytes_Callable (by decide)
    have hszH := taggedHeaderBytes_size "Callable" (UInt16.ofNat 9)
    rw [← hin, hszH] at h
    simpa [L, oHdr] using h
  have hid :
      decodeU32le ⟨input, oHdr, nesting + 1⟩ =
        .ok (1, ⟨input, oId, nesting + 1⟩) := by
    let L := left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++
      "Callable".toUTF8 ++ encodeU16le (UInt16.ofNat 9)
    let R :=
      callableKindInvBytesV1 ++ someStringPayloadBytesV1 invName ++ encodeU32le 0 ++
        callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++ encodeU32le 1 ++
        simpleClosureBlockBytesV1 ++ encodeU32le 0 ++ encodeU8 1 ++ encodeU64le 3 ++
        right
    have hin : input = L ++ encodeU32le 1 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = oHdr := by
      simp [L, oHdr, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1]
      omega
    have h := decodeU32le_encode_midV1 L R 1 (nesting + 1)
    rw [← hin, hL] at h
    exact h
  have hkind :
      decodeCallableKindV1 ⟨input, oId, nesting + 1⟩ =
        .ok (.invariant, ⟨input, oKind, nesting + 1⟩) := by
    let L := left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++
      "Callable".toUTF8 ++ encodeU16le (UInt16.ofNat 9) ++ encodeU32le 1
    let R :=
      someStringPayloadBytesV1 invName ++ encodeU32le 0 ++
        callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++ encodeU32le 1 ++
        simpleClosureBlockBytesV1 ++ encodeU32le 0 ++ encodeU8 1 ++ encodeU64le 3 ++
        right
    have hin : input = L ++ callableKindInvBytesV1 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = oId := by
      simp [L, oId, oHdr, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1]
      omega
    have h := decode_kindInv_mid L R (nesting + 1) hdepth1
    rw [← hin, hL] at h
    exact h
  have hnameD :
      decodeOption decodeString ⟨input, oKind, nesting + 1⟩ =
        .ok (some invName, ⟨input, oName, nesting + 1⟩) := by
    let L :=
      left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
        encodeU16le (UInt16.ofNat 9) ++ encodeU32le 1 ++ callableKindInvBytesV1
    let R :=
      encodeU32le 0 ++ callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++
        encodeU32le 1 ++ simpleClosureBlockBytesV1 ++ encodeU32le 0 ++
        encodeU8 1 ++ encodeU64le 3 ++ right
    have hin : input = L ++ someStringPayloadBytesV1 invName ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = oKind := by
      simp [L, oKind, oId, oHdr, ByteArray.size_append, encodeU32le_sizeV1,
        encodeU16le_sizeV1]
      omega
    have h :=
      decodeOptionString_some_identifier_midV1 L R invName (nesting + 1) hname
    rw [← hin, hL] at h
    exact h
  have hparams :
      readArrayCountAtV1 input oName maxArrayElements = .ok (0, oParams) := by
    let L :=
      left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
        encodeU16le (UInt16.ofNat 9) ++ encodeU32le 1 ++ callableKindInvBytesV1 ++
        someStringPayloadBytesV1 invName
    let R :=
      callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++ encodeU32le 1 ++
        simpleClosureBlockBytesV1 ++ encodeU32le 0 ++ encodeU8 1 ++ encodeU64le 3 ++
        right
    have hin : input = L ++ encodeU32le (UInt32.ofNat 0) ++ R := by
      simp only [input, L, R, ByteArray.append_assoc, u32_ofNat0]
    have hL : L.size = oName := by
      simp [L, oName, oKind, oId, oHdr, ByteArray.size_append, encodeU32le_sizeV1,
        encodeU16le_sizeV1, hnameSz]
      omega
    have h := readArrayCount_encode_midV1 L R 0 maxArrayElements (by decide) (by decide)
    rw [← hin, hL] at h
    exact h
  have hresult :
      decodeCallableResultV1 ⟨input, oParams, nesting + 1⟩ =
        .ok ({ typeId := 0, visibility := .public_ },
          ⟨input, oResult, nesting + 1⟩) := by
    let L :=
      left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
        encodeU16le (UInt16.ofNat 9) ++ encodeU32le 1 ++ callableKindInvBytesV1 ++
        someStringPayloadBytesV1 invName ++ encodeU32le 0
    let R :=
      encodeU32le 0 ++ encodeU32le 1 ++ simpleClosureBlockBytesV1 ++
        encodeU32le 0 ++ encodeU8 1 ++ encodeU64le 3 ++ right
    have hin : input = L ++ callableResultPublicBoolBytesV1 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = oParams := by
      simp [L, oParams, oName, oKind, oId, oHdr, ByteArray.size_append,
        encodeU32le_sizeV1, encodeU16le_sizeV1, hnameSz]
      omega
    have h := decode_callableResultPublicBool_mid L R (nesting + 1) hdepth2
    rw [← hin, hL] at h
    exact h
  have hentry :
      decodeU32le ⟨input, oResult, nesting + 1⟩ =
        .ok (0, ⟨input, oEntry, nesting + 1⟩) := by
    let L :=
      left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
        encodeU16le (UInt16.ofNat 9) ++ encodeU32le 1 ++ callableKindInvBytesV1 ++
        someStringPayloadBytesV1 invName ++ encodeU32le 0 ++
        callableResultPublicBoolBytesV1
    let R :=
      encodeU32le 1 ++ simpleClosureBlockBytesV1 ++ encodeU32le 0 ++
        encodeU8 1 ++ encodeU64le 3 ++ right
    have hin : input = L ++ encodeU32le 0 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = oResult := by
      simp [L, oResult, oParams, oName, oKind, oId, oHdr, ByteArray.size_append,
        encodeU32le_sizeV1, encodeU16le_sizeV1, hnameSz]
      omega
    have h := decodeU32le_encode_midV1 L R 0 (nesting + 1)
    rw [← hin, hL] at h
    exact h
  have hblocksCount :
      readArrayCountAtV1 input oEntry maxArrayElements = .ok (1, oBlocks) := by
    let L :=
      left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
        encodeU16le (UInt16.ofNat 9) ++ encodeU32le 1 ++ callableKindInvBytesV1 ++
        someStringPayloadBytesV1 invName ++ encodeU32le 0 ++
        callableResultPublicBoolBytesV1 ++ encodeU32le 0
    let R :=
      simpleClosureBlockBytesV1 ++ encodeU32le 0 ++ encodeU8 1 ++ encodeU64le 3 ++ right
    have hin : input = L ++ encodeU32le (UInt32.ofNat 1) ++ R := by
      simp only [input, L, R, ByteArray.append_assoc, u32_ofNat1]
    have hL : L.size = oEntry := by
      simp [L, oEntry, oResult, oParams, oName, oKind, oId, oHdr, ByteArray.size_append,
        encodeU32le_sizeV1, encodeU16le_sizeV1, hnameSz]
      omega
    have h := readArrayCount_encode_midV1 L R 1 maxArrayElements (by decide) (by decide)
    rw [← hin, hL] at h
    exact h
  have hblock :
      decodeBlockV1 ⟨input, oBlocks, nesting + 1⟩ =
        .ok (simpleClosureBlockV1, ⟨input, oBlockEnd, nesting + 1⟩) := by
    let L :=
      left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
        encodeU16le (UInt16.ofNat 9) ++ encodeU32le 1 ++ callableKindInvBytesV1 ++
        someStringPayloadBytesV1 invName ++ encodeU32le 0 ++
        callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++ encodeU32le 1
    let R := encodeU32le 0 ++ encodeU8 1 ++ encodeU64le 3 ++ right
    have hin : input = L ++ simpleClosureBlockBytesV1 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = oBlocks := by
      simp [L, oBlocks, oEntry, oResult, oParams, oName, oKind, oId, oHdr,
        ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1, hnameSz]
      omega
    have h := decode_simpleClosureBlock_mid L R (nesting + 1) hdepth3
    rw [← hin, hL] at h
    exact h
  have hloops :
      readArrayCountAtV1 input oBlockEnd maxArrayElements = .ok (0, oLoops) := by
    let L :=
      left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
        encodeU16le (UInt16.ofNat 9) ++ encodeU32le 1 ++ callableKindInvBytesV1 ++
        someStringPayloadBytesV1 invName ++ encodeU32le 0 ++
        callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++ encodeU32le 1 ++
        simpleClosureBlockBytesV1
    let R := encodeU8 1 ++ encodeU64le 3 ++ right
    have hin : input = L ++ encodeU32le (UInt32.ofNat 0) ++ R := by
      simp only [input, L, R, ByteArray.append_assoc, u32_ofNat0]
    have hL : L.size = oBlockEnd := by
      simp [L, oBlockEnd, oBlocks, oEntry, oResult, oParams, oName, oKind, oId, oHdr,
        ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1, hnameSz]
      omega
    have h := readArrayCount_encode_midV1 L R 0 maxArrayElements (by decide) (by decide)
    rw [← hin, hL] at h
    exact h
  have hsteps :
      decodeOption decodeU64le ⟨input, oLoops, nesting + 1⟩ =
        .ok (some 3, ⟨input, oEnd, nesting + 1⟩) := by
    let L :=
      left ++ encodeU32le (UInt32.ofNat "Callable".toUTF8.size) ++ "Callable".toUTF8 ++
        encodeU16le (UInt16.ofNat 9) ++ encodeU32le 1 ++ callableKindInvBytesV1 ++
        someStringPayloadBytesV1 invName ++ encodeU32le 0 ++
        callableResultPublicBoolBytesV1 ++ encodeU32le 0 ++ encodeU32le 1 ++
        simpleClosureBlockBytesV1 ++ encodeU32le 0
    let R := right
    have hin : input = L ++ encodeU8 1 ++ encodeU64le 3 ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = oLoops := by
      simp [L, oLoops, oBlockEnd, oBlocks, oEntry, oResult, oParams, oName, oKind, oId,
        oHdr, ByteArray.size_append, encodeU32le_sizeV1, encodeU16le_sizeV1, hnameSz]
      omega
    have h := decodeOption_some_u64_3_midV1 L R (nesting + 1)
    rw [← hin, hL] at h
    exact h
  have hbody :=
    decodeCallableV1_singleBlockV1
      ⟨input, left.size, nesting⟩
      ⟨input, oHdr, nesting + 1⟩
      ⟨input, oId, nesting + 1⟩
      ⟨input, oKind, nesting + 1⟩
      ⟨input, oName, nesting + 1⟩
      ⟨input, oResult, nesting + 1⟩
      ⟨input, oEntry, nesting + 1⟩
      ⟨input, oBlockEnd, nesting + 1⟩
      ⟨input, oEnd, nesting + 1⟩
      oParams oBlocks oLoops 1 0 .invariant (some invName)
      { typeId := 0, visibility := .public_ } simpleClosureBlockV1 (some 3)
      hdepth0 htag hid hkind hnameD hparams hresult hentry hblocksCount hblock hloops hsteps
  have hinv :
      simpleClosureInvCallableV1 invName =
        { id := 1, kind := .invariant, name := some invName, params := #[],
          result := { typeId := 0, visibility := .public_ }, entryBlock := 0,
          blocks := #[simpleClosureBlockV1], loopBounds := #[],
          invariantSteps := some 3 } := by
    rfl
  rw [← hinv] at hbody
  rw [hend] at hbody
  exact hbody

/-! ### Two-callable array mid-offset decode -/

theorem decode_callablesArray_mid (left right : ByteArray) (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p)
    (nesting : Nat) (hdepth : nesting + 3 < maxNesting) :
    decodeArray maxTableElements decodeCallableV1
        ⟨left ++ callablesArrayBytesV1 p ++ right, left.size, nesting⟩ =
      .ok (#[simpleClosureViewCallableV1 p.viewName,
            simpleClosureInvCallableV1 p.invName],
        ⟨left ++ callablesArrayBytesV1 p ++ right,
          left.size + (callablesArrayBytesV1 p).size, nesting⟩) := by
  have hshape :
      callablesArrayBytesV1 p =
        encodeU32le 2 ++ viewCallableBytesV1 p.viewName ++
          invCallableBytesV1 p.invName := by
    simp [callablesArrayBytesV1, ByteArray.append_assoc]
  -- normalize encodeU32le 2 spelling for readArrayCount (ofNat form)
  have hshape' :
      callablesArrayBytesV1 p =
        encodeU32le (UInt32.ofNat 2) ++ viewCallableBytesV1 p.viewName ++
          invCallableBytesV1 p.invName := by
    have h2 : encodeU32le 2 = encodeU32le (UInt32.ofNat 2) := rfl
    simp [callablesArrayBytesV1, h2, ByteArray.append_assoc]
  have hsz :
      (callablesArrayBytesV1 p).size =
        4 + (viewCallableBytesV1 p.viewName).size +
          (invCallableBytesV1 p.invName).size := by
    simp [hshape', ByteArray.size_append, encodeU32le_sizeV1]
  have hpay :
      left ++ callablesArrayBytesV1 p ++ right =
        left ++ encodeU32le (UInt32.ofNat 2) ++ viewCallableBytesV1 p.viewName ++
          invCallableBytesV1 p.invName ++ right := by
    simp [hshape', ByteArray.append_assoc]
  rw [hpay]
  let input :=
    left ++ encodeU32le (UInt32.ofNat 2) ++ viewCallableBytesV1 p.viewName ++
      invCallableBytesV1 p.invName ++ right
  change decodeArray maxTableElements decodeCallableV1 ⟨input, left.size, nesting⟩ =
    .ok (#[simpleClosureViewCallableV1 p.viewName,
          simpleClosureInvCallableV1 p.invName],
      ⟨input, left.size + (callablesArrayBytesV1 p).size, nesting⟩)
  let o0 := left.size + 4
  let o1 := o0 + (viewCallableBytesV1 p.viewName).size
  let oEnd := o1 + (invCallableBytesV1 p.invName).size
  have hend : oEnd = left.size + (callablesArrayBytesV1 p).size := by
    simp only [oEnd, o1, o0, hsz]; omega
  have hcount :
      readArrayCountAtV1 input left.size maxTableElements = .ok (2, o0) := by
    let L := left
    let R := viewCallableBytesV1 p.viewName ++ invCallableBytesV1 p.invName ++ right
    have hin : input = L ++ encodeU32le (UInt32.ofNat 2) ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have h := readArrayCount_encode_midV1 L R 2 maxTableElements (by decide) (by decide)
    rw [← hin] at h
    simpa [L, o0] using h
  have h0 :
      decodeCallableV1 ⟨input, o0, nesting⟩ =
        .ok (simpleClosureViewCallableV1 p.viewName, ⟨input, o1, nesting⟩) := by
    let L := left ++ encodeU32le (UInt32.ofNat 2)
    let R := invCallableBytesV1 p.invName ++ right
    have hin : input = L ++ viewCallableBytesV1 p.viewName ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = o0 := by
      simp [L, o0, ByteArray.size_append, encodeU32le_sizeV1]
    have h := decode_viewCallable_mid L R p.viewName legal.hview nesting hdepth
    rw [← hin, hL] at h
    exact h
  have h1 :
      decodeCallableV1 ⟨input, o1, nesting⟩ =
        .ok (simpleClosureInvCallableV1 p.invName, ⟨input, oEnd, nesting⟩) := by
    let L := left ++ encodeU32le (UInt32.ofNat 2) ++ viewCallableBytesV1 p.viewName
    let R := right
    have hin : input = L ++ invCallableBytesV1 p.invName ++ R := by
      simp only [input, L, R, ByteArray.append_assoc]
    have hL : L.size = o1 := by
      simp [L, o1, o0, ByteArray.size_append, encodeU32le_sizeV1]
    have h := decode_invCallable_mid L R p.invName legal.hinv nesting hdepth
    rw [← hin, hL] at h
    exact h
  have harr :=
    decodeArray_twoV1 maxTableElements decodeCallableV1
      ⟨input, left.size, nesting⟩ o0
      (simpleClosureViewCallableV1 p.viewName)
      (simpleClosureInvCallableV1 p.invName)
      ⟨input, o1, nesting⟩ ⟨input, oEnd, nesting⟩
      hcount h0 h1
  rw [hend] at harr
  exact harr

/-! ### Public Legal theorems (no free nested-decode premises) -/

/-- Public: mid-offset decode of the view callable under Legal params. -/
theorem decodeCallableV1_simpleClosureView_of_legal
    (left right : ByteArray) (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p)
    (nesting : Nat) (hdepth : nesting + 3 < maxNesting) :
    decodeCallableV1
        ⟨left ++ viewCallableBytesV1 p.viewName ++ right, left.size, nesting⟩ =
      .ok (simpleClosureViewCallableV1 p.viewName,
        ⟨left ++ viewCallableBytesV1 p.viewName ++ right,
          left.size + (viewCallableBytesV1 p.viewName).size, nesting⟩) :=
  decode_viewCallable_mid left right p.viewName legal.hview nesting hdepth

/-- Public: mid-offset decode of the invariant callable under Legal params. -/
theorem decodeCallableV1_simpleClosureInv_of_legal
    (left right : ByteArray) (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p)
    (nesting : Nat) (hdepth : nesting + 3 < maxNesting) :
    decodeCallableV1
        ⟨left ++ invCallableBytesV1 p.invName ++ right, left.size, nesting⟩ =
      .ok (simpleClosureInvCallableV1 p.invName,
        ⟨left ++ invCallableBytesV1 p.invName ++ right,
          left.size + (invCallableBytesV1 p.invName).size, nesting⟩) :=
  decode_invCallable_mid left right p.invName legal.hinv nesting hdepth

/-- Public: mid-offset decode of the two-callable array under Legal params. -/
theorem decodeCallableArrayV1_simpleClosure_of_legal
    (left right : ByteArray) (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p)
    (nesting : Nat) (hdepth : nesting + 3 < maxNesting) :
    decodeArray maxTableElements decodeCallableV1
        ⟨left ++ callablesArrayBytesV1 p ++ right, left.size, nesting⟩ =
      .ok (#[simpleClosureViewCallableV1 p.viewName,
            simpleClosureInvCallableV1 p.invName],
        ⟨left ++ callablesArrayBytesV1 p ++ right,
          left.size + (callablesArrayBytesV1 p).size, nesting⟩) :=
  decode_callablesArray_mid left right p legal nesting hdepth

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
