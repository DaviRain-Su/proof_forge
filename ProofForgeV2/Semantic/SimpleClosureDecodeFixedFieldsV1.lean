import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.RequirementIdsV1
import ProofForgeV2.Semantic.SimpleClosureDecodeV1
import ProofForgeV2.Semantic.SimpleClosureEncodeV1
import ProofForgeV2.Semantic.SimpleClosureStructureCertV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.Wire.CodecRoundtripV1
import ProofForgeV2.Semantic.WireV1
import Init.Data.ByteArray.Lemmas
import Init.Data.Array.Lemmas

/-!
  ProofForgeV2.Semantic.SimpleClosureDecodeFixedFieldsV1 — B-SC-DEC fixed-fields leaf

  Production mid-offset encode→decode kernel lemmas for simple-closure fixed fields:

    1. Bool + UInt64 TypeDecl (each) and the two-element types array
    2. four empty tables (constants / logicalState / events / errors)
    3. `simpleClosureInvariantDeclV1 p.invName` + singleton invariants array
       (dynamic Unicode-legal invName)
    4. sole `value.bool` ProgramRequirements

  Public lemma contract: from production encode success or canonical fixed
  definitions (bytes authority via production encoder equality), the matching
  production decoder returns the exact value at `left ++ fieldBytes ++ right`
  with cursor offset `left.size + fieldBytes.size`, for arbitrary left/right
  and legal nesting (`nesting + depth < maxNesting`).

  Hard boundaries:
    * no decoder-success premises on public goals
    * no hardcoded Tests FQN
    * no axiom / sorry / native_decide / ofReduceBool / run_tac / unsafe / meta / IO
-/

set_option maxHeartbeats 80000000
set_option maxRecDepth 400000

namespace ProofForgeV2.Semantic.SimpleClosureDecodeFixedFieldsV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
open ProofForgeV2.Semantic.RequirementIdsV1
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.SimpleClosureDecodeV1
open ProofForgeV2.Semantic.SimpleClosureEncodeV1
open ProofForgeV2.Semantic.SimpleClosureStructureCertV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1

/-! ### Tagged header foundation -/

/-- Production tagged header = `u32le(|tag|) ++ tag ++ u16le(fieldCount)`. -/
def taggedHeaderBytesV1 (tag : String) (fieldCount : Nat) : ByteArray :=
  ((encodeU32le (UInt32.ofNat tag.toUTF8.size)).append tag.toUTF8).append
    (encodeU16le (UInt16.ofNat fieldCount))

theorem taggedHeaderBytesV1_size (tag : String) (fieldCount : Nat) :
    (taggedHeaderBytesV1 tag fieldCount).size = 4 + tag.toUTF8.size + 2 := by
  unfold taggedHeaderBytesV1
  change ((encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8) ++
      encodeU16le (UInt16.ofNat fieldCount)).size = 4 + tag.toUTF8.size + 2
  rw [ByteArray.size_append, ByteArray.size_append, encodeU32le_sizeV1,
    encodeU16le_sizeV1]

theorem ByteArray_bne_self_eq_false (a : ByteArray) : (a != a) = false := by
  simp [bne, ByteArray_beq_reflV1]

theorem readTagBytes_encode_midV1
    (left right : ByteArray) (tagBytes : ByteArray)
    (hnonempty : 1 ≤ tagBytes.size)
    (hmax : tagBytes.size ≤ maxTagAsciiBytes)
    (hfit : tagBytes.size ≤ UInt32.size - 1)
    (hascii : isAsciiTagBytesV1 tagBytes = true) :
    readTagBytesAtV1
        (left ++ encodeU32le (UInt32.ofNat tagBytes.size) ++ tagBytes ++ right)
        left.size =
      .ok (tagBytes, left.size + 4 + tagBytes.size) := by
  have hassoc :
      left ++ encodeU32le (UInt32.ofNat tagBytes.size) ++ tagBytes ++ right =
        left ++ encodeU32le (UInt32.ofNat tagBytes.size) ++ (tagBytes ++ right) := by
    simp [ByteArray.append_assoc]
  rw [hassoc]
  have hread :=
    readU32le_encode_midV1 left (tagBytes ++ right) (UInt32.ofNat tagBytes.size)
  have hto : (UInt32.ofNat tagBytes.size).toNat = tagBytes.size :=
    Nat.mod_eq_of_lt (Nat.lt_of_le_of_lt hfit (by decide))
  have htake :
      takeBytesAtV1
          (left ++ encodeU32le (UInt32.ofNat tagBytes.size) ++ (tagBytes ++ right))
          (left.size + 4) tagBytes.size = .ok tagBytes := by
    have hs4 : (encodeU32le (UInt32.ofNat tagBytes.size)).size = 4 :=
      encodeU32le_sizeV1 _
    have hA :
        left ++ encodeU32le (UInt32.ofNat tagBytes.size) ++ (tagBytes ++ right) =
          (left ++ encodeU32le (UInt32.ofNat tagBytes.size)) ++ tagBytes ++ right := by
      simp [ByteArray.append_assoc]
    have hoff :
        (left ++ encodeU32le (UInt32.ofNat tagBytes.size)).size = left.size + 4 := by
      rw [ByteArray.size_append, hs4]
    rw [hA, ← hoff]
    exact takeBytes_mid_payloadV1 _ tagBytes right
  unfold readTagBytesAtV1
  rw [hread]
  dsimp only
  have h1 : decide (1 ≤ tagBytes.size) = true := by simp [hnonempty]
  have h2 : decide (tagBytes.size ≤ maxTagAsciiBytes) = true := by simp [hmax]
  simp only [hto, h1, h2, Bool.and_self, Bool.not_true]
  rw [if_neg (by decide : ¬(false = true))]
  rw [htake]
  simp only [hascii, ↓reduceIte]

theorem expectTaggedHeader_encode_midV1
    (left right : ByteArray) (tag : String) (fieldCount : Nat)
    (fieldsPayload : ByteArray)
    (hnonempty : 1 ≤ tag.toUTF8.size)
    (hmax : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (hfit : tag.toUTF8.size ≤ UInt32.size - 1)
    (hasciiBytes : isAsciiTagBytesV1 tag.toUTF8 = true)
    (hcountFit : fieldCount ≤ UInt16.size - 1) :
    expectTaggedHeaderBytesAtV1
        (left ++ taggedHeaderBytesV1 tag fieldCount ++ fieldsPayload ++ right)
        left.size tag.toUTF8 fieldCount =
      .ok (left.size + (taggedHeaderBytesV1 tag fieldCount).size) := by
  have henc :
      taggedHeaderBytesV1 tag fieldCount =
        encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++
          encodeU16le (UInt16.ofNat fieldCount) := by
    simp [taggedHeaderBytesV1, ByteArray.append_assoc]
  have hin :
      left ++ taggedHeaderBytesV1 tag fieldCount ++ fieldsPayload ++ right =
        left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++
          (encodeU16le (UInt16.ofNat fieldCount) ++ fieldsPayload ++ right) := by
    simp [henc, ByteArray.append_assoc]
  rw [hin]
  have htag :=
    readTagBytes_encode_midV1 left
      (encodeU16le (UInt16.ofNat fieldCount) ++ fieldsPayload ++ right)
      tag.toUTF8 hnonempty hmax hfit hasciiBytes
  unfold expectTaggedHeaderBytesAtV1
  rw [htag]
  dsimp only
  rw [ByteArray_bne_self_eq_false]
  rw [if_neg (by decide : ¬(false = true))]
  have hassoc2 :
      left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++
          (encodeU16le (UInt16.ofNat fieldCount) ++ fieldsPayload ++ right) =
        (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8) ++
          encodeU16le (UInt16.ofNat fieldCount) ++ (fieldsPayload ++ right) := by
    simp [ByteArray.append_assoc]
  have hszL :
      (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8).size =
        left.size + 4 + tag.toUTF8.size := by
    rw [ByteArray.size_append, ByteArray.size_append, encodeU32le_sizeV1]
  have hcount :
      readU16leAtV1
          (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++
            (encodeU16le (UInt16.ofNat fieldCount) ++ fieldsPayload ++ right))
          (left.size + 4 + tag.toUTF8.size) =
        .ok (UInt16.ofNat fieldCount,
          left.size + 4 + tag.toUTF8.size + 2) := by
    rw [hassoc2, ← hszL]
    simpa [hszL] using
      readU16le_encode_midV1
        (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8)
        (fieldsPayload ++ right) (UInt16.ofNat fieldCount)
  rw [hcount]
  dsimp only
  have htoC : (UInt16.ofNat fieldCount).toNat = fieldCount :=
    Nat.mod_eq_of_lt (Nat.lt_of_le_of_lt hcountFit (by decide))
  have heq : ((UInt16.ofNat fieldCount).toNat == fieldCount) = true := by
    simp [htoC]
  rw [heq, if_pos rfl]
  have : left.size + 4 + tag.toUTF8.size + 2 =
      left.size + (taggedHeaderBytesV1 tag fieldCount).size := by
    rw [taggedHeaderBytesV1_size]; omega
  exact congrArg Except.ok this

theorem expectTag_encode_midV1
    (left right : ByteArray) (tag : String) (fieldCount : Nat)
    (fieldsPayload : ByteArray) (nesting : Nat)
    (hnonempty : 1 ≤ tag.toUTF8.size)
    (hmax : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (hfit : tag.toUTF8.size ≤ UInt32.size - 1)
    (hasciiBytes : isAsciiTagBytesV1 tag.toUTF8 = true)
    (hcountFit : fieldCount ≤ UInt16.size - 1) :
    expectTag tag fieldCount
        ⟨left ++ taggedHeaderBytesV1 tag fieldCount ++ fieldsPayload ++ right,
          left.size, nesting⟩ =
      .ok ((),
        ⟨left ++ taggedHeaderBytesV1 tag fieldCount ++ fieldsPayload ++ right,
          left.size + (taggedHeaderBytesV1 tag fieldCount).size, nesting⟩) := by
  apply expectTag_eq_of_headerV1
  exact expectTaggedHeader_encode_midV1 left right tag fieldCount fieldsPayload
    hnonempty hmax hfit hasciiBytes hcountFit

theorem decodeTag_encode_midV1
    (left right : ByteArray) (tag : String) (nesting : Nat)
    (hnonempty : 1 ≤ tag.toUTF8.size)
    (hmax : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (hfit : tag.toUTF8.size ≤ UInt32.size - 1)
    (hasciiBytes : isAsciiTagBytesV1 tag.toUTF8 = true)
    (hasciiTag : isAsciiTagV1 tag = true) :
    decodeTag
        ⟨left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++ right,
          left.size, nesting⟩ =
      .ok (tag,
        ⟨left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++ right,
          left.size + 4 + tag.toUTF8.size, nesting⟩) := by
  apply decodeTag_eq_of_valueV1
  · exact readTagBytes_encode_midV1 left right tag.toUTF8 hnonempty hmax hfit hasciiBytes
  · exact fromUTF8?_toUTF8V1 tag
  · exact hasciiTag

/-! ### Fixed ASCII tag bytes -/

private theorem isAsciiBytes_Type_Bool :
    isAsciiTagBytesV1 "Type.Bool".toUTF8 = true := by
  have h : "Type.Bool".toUTF8 =
      ByteArray.mk #[84, 121, 112, 101, 46, 66, 111, 111, 108] := rfl
  rw [h]; simp [isAsciiTagBytesV1]

private theorem isAsciiBytes_Type_UInt :
    isAsciiTagBytesV1 "Type.UInt".toUTF8 = true := by
  have h : "Type.UInt".toUTF8 =
      ByteArray.mk #[84, 121, 112, 101, 46, 85, 73, 110, 116] := rfl
  rw [h]; simp [isAsciiTagBytesV1]

private theorem isAsciiBytes_TypeDecl :
    isAsciiTagBytesV1 "TypeDecl".toUTF8 = true := by
  have h : "TypeDecl".toUTF8 =
      ByteArray.mk #[84, 121, 112, 101, 68, 101, 99, 108] := rfl
  rw [h]; simp [isAsciiTagBytesV1]

private theorem isAsciiBytes_InvariantDecl :
    isAsciiTagBytesV1 "InvariantDecl".toUTF8 = true := by
  have h : "InvariantDecl".toUTF8 =
      ByteArray.mk #[73, 110, 118, 97, 114, 105, 97, 110, 116, 68, 101, 99, 108] := rfl
  rw [h]; simp [isAsciiTagBytesV1]

private theorem isAsciiBytes_ProgramRequirements :
    isAsciiTagBytesV1 "ProgramRequirements".toUTF8 = true := by
  have h : "ProgramRequirements".toUTF8 =
      ByteArray.mk #[80, 114, 111, 103, 114, 97, 109, 82, 101, 113, 117, 105, 114, 101,
        109, 101, 110, 116, 115] := rfl
  rw [h]; simp [isAsciiTagBytesV1]

private theorem isAsciiBytes_RequirementRequest :
    isAsciiTagBytesV1 "RequirementRequest".toUTF8 = true := by
  have h : "RequirementRequest".toUTF8 =
      ByteArray.mk #[82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 82, 101, 113,
        117, 101, 115, 116] := rfl
  rw [h]; simp [isAsciiTagBytesV1]

/-! ### TypeShape Bool / UInt64 encode + mid-offset decode -/

def typeShapeBoolBytesV1 : ByteArray := taggedHeaderBytesV1 "Type.Bool" 0

theorem encodeTypeShape_bool_eq_ok :
    encodeTypeShapeV1 (.bool : TypeShapeV1) = .ok typeShapeBoolBytesV1 := by
  change encodeNullary "Type.Bool" = .ok typeShapeBoolBytesV1
  have h := encodeNullary_eq_okV1 "Type.Bool" (by decide) (by decide) (by decide)
  have heq :
      (((encodeU32le (UInt32.ofNat "Type.Bool".toUTF8.size)).append
          "Type.Bool".toUTF8).append (encodeU16le 0)) =
        typeShapeBoolBytesV1 := by
    simp only [typeShapeBoolBytesV1, taggedHeaderBytesV1]
    rfl
  rwa [heq] at h

def typeShapeUInt64BytesV1 : ByteArray :=
  taggedHeaderBytesV1 "Type.UInt" 1 ++ encodeU16le 64

theorem encodeTypeShape_uint64_eq_ok :
    encodeTypeShapeV1 (.uint 64) = .ok typeShapeUInt64BytesV1 := by
  change encodeTagged "Type.UInt" #[encodeU16le 64] = .ok typeShapeUInt64BytesV1
  have h := encodeTagged_eq_okV1 "Type.UInt" #[encodeU16le 64]
    (by decide) (by decide) (by decide) (by decide) (by decide)
  have heq :
      taggedBytesV1 "Type.UInt" #[encodeU16le 64] = typeShapeUInt64BytesV1 := by
    simp only [typeShapeUInt64BytesV1, taggedBytesV1, taggedBytesFromBytesV1,
      appendTaggedFieldsV1, taggedHeaderBytesV1]
    rfl
  rwa [heq] at h

theorem decodeTypeShape_bool_midV1
    (left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) :
    decodeTypeShapeV1
        ⟨left ++ typeShapeBoolBytesV1 ++ right, left.size, nesting⟩ =
      .ok (.bool,
        ⟨left ++ typeShapeBoolBytesV1 ++ right,
          left.size + typeShapeBoolBytesV1.size, nesting⟩) := by
  refine decodeTypeShapeV1_eq_of_bodyV1
    ⟨left ++ typeShapeBoolBytesV1 ++ right, left.size, nesting⟩ .bool
    ⟨left ++ typeShapeBoolBytesV1 ++ right,
      left.size + typeShapeBoolBytesV1.size, nesting + 1⟩ hdepth ?_
  -- body
  have henc :
      typeShapeBoolBytesV1 =
        encodeU32le (UInt32.ofNat "Type.Bool".toUTF8.size) ++ "Type.Bool".toUTF8 ++
          encodeU16le 0 := by
    simp [typeShapeBoolBytesV1, taggedHeaderBytesV1, ByteArray.append_assoc]
  have hin :
      left ++ typeShapeBoolBytesV1 ++ right =
        left ++ encodeU32le (UInt32.ofNat "Type.Bool".toUTF8.size) ++
          "Type.Bool".toUTF8 ++ (encodeU16le 0 ++ right) := by
    simp [henc, ByteArray.append_assoc]
  have htag :
      decodeTag
          ⟨left ++ typeShapeBoolBytesV1 ++ right, left.size, nesting + 1⟩ =
        .ok ("Type.Bool",
          ⟨left ++ typeShapeBoolBytesV1 ++ right,
            left.size + 4 + "Type.Bool".toUTF8.size, nesting + 1⟩) := by
    rw [hin]
    have h :=
      decodeTag_encode_midV1 left (encodeU16le 0 ++ right) "Type.Bool" (nesting + 1)
        (by decide) (by decide) (by decide) isAsciiBytes_Type_Bool (by decide)
    simpa [hin.symm, ByteArray.append_assoc] using h
  have hszFinal :
      left.size + 4 + "Type.Bool".toUTF8.size + 2 =
        left.size + typeShapeBoolBytesV1.size := by
    simp only [typeShapeBoolBytesV1, taggedHeaderBytesV1_size]; omega
  have hfc :
      decodeFieldCount 0
          ⟨left ++ typeShapeBoolBytesV1 ++ right,
            left.size + 4 + "Type.Bool".toUTF8.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ typeShapeBoolBytesV1 ++ right,
            left.size + typeShapeBoolBytesV1.size, nesting + 1⟩) := by
    have hassoc :
        left ++ typeShapeBoolBytesV1 ++ right =
          (left ++ encodeU32le (UInt32.ofNat "Type.Bool".toUTF8.size) ++
            "Type.Bool".toUTF8) ++ encodeU16le 0 ++ right := by
      simp [henc, ByteArray.append_assoc]
    have hsz :
        (left ++ encodeU32le (UInt32.ofNat "Type.Bool".toUTF8.size) ++
          "Type.Bool".toUTF8).size =
          left.size + 4 + "Type.Bool".toUTF8.size := by
      rw [ByteArray.size_append, ByteArray.size_append, encodeU32le_sizeV1]
    have hread :
        readU16leAtV1 (left ++ typeShapeBoolBytesV1 ++ right)
            (left.size + 4 + "Type.Bool".toUTF8.size) =
          .ok (0, left.size + 4 + "Type.Bool".toUTF8.size + 2) := by
      rw [hassoc, ← hsz]
      simpa [hsz] using
        readU16le_encode_midV1
          (left ++ encodeU32le (UInt32.ofNat "Type.Bool".toUTF8.size) ++
            "Type.Bool".toUTF8)
          right 0
    -- rewrite target offset first
    rw [← hszFinal]
    have h := decodeFieldCount_eq_of_readU16leV1 0
      ⟨left ++ typeShapeBoolBytesV1 ++ right,
        left.size + 4 + "Type.Bool".toUTF8.size, nesting + 1⟩
      0 (left.size + 4 + "Type.Bool".toUTF8.size + 2) hread
    simpa using h
  exact decodeTypeShapeBodyV1_bool _ _ _ htag hfc

theorem decodeTypeShape_uint64_midV1
    (left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) :
    decodeTypeShapeV1
        ⟨left ++ typeShapeUInt64BytesV1 ++ right, left.size, nesting⟩ =
      .ok (.uint 64,
        ⟨left ++ typeShapeUInt64BytesV1 ++ right,
          left.size + typeShapeUInt64BytesV1.size, nesting⟩) := by
  refine decodeTypeShapeV1_eq_of_bodyV1
    ⟨left ++ typeShapeUInt64BytesV1 ++ right, left.size, nesting⟩ (.uint 64)
    ⟨left ++ typeShapeUInt64BytesV1 ++ right,
      left.size + typeShapeUInt64BytesV1.size, nesting + 1⟩ hdepth ?_
  have henc :
      typeShapeUInt64BytesV1 =
        encodeU32le (UInt32.ofNat "Type.UInt".toUTF8.size) ++ "Type.UInt".toUTF8 ++
          encodeU16le 1 ++ encodeU16le 64 := by
    simp [typeShapeUInt64BytesV1, taggedHeaderBytesV1, ByteArray.append_assoc]
  have hin :
      left ++ typeShapeUInt64BytesV1 ++ right =
        left ++ encodeU32le (UInt32.ofNat "Type.UInt".toUTF8.size) ++
          "Type.UInt".toUTF8 ++
          (encodeU16le 1 ++ encodeU16le 64 ++ right) := by
    simp [henc, ByteArray.append_assoc]
  have htag :
      decodeTag
          ⟨left ++ typeShapeUInt64BytesV1 ++ right, left.size, nesting + 1⟩ =
        .ok ("Type.UInt",
          ⟨left ++ typeShapeUInt64BytesV1 ++ right,
            left.size + 4 + "Type.UInt".toUTF8.size, nesting + 1⟩) := by
    rw [hin]
    have h :=
      decodeTag_encode_midV1 left
        (encodeU16le 1 ++ encodeU16le 64 ++ right) "Type.UInt" (nesting + 1)
        (by decide) (by decide) (by decide) isAsciiBytes_Type_UInt (by decide)
    simpa [hin.symm, ByteArray.append_assoc] using h
  have hfc :
      decodeFieldCount 1
          ⟨left ++ typeShapeUInt64BytesV1 ++ right,
            left.size + 4 + "Type.UInt".toUTF8.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ typeShapeUInt64BytesV1 ++ right,
            left.size + 4 + "Type.UInt".toUTF8.size + 2, nesting + 1⟩) := by
    have hassoc :
        left ++ typeShapeUInt64BytesV1 ++ right =
          (left ++ encodeU32le (UInt32.ofNat "Type.UInt".toUTF8.size) ++
            "Type.UInt".toUTF8) ++ encodeU16le 1 ++ (encodeU16le 64 ++ right) := by
      simp [henc, ByteArray.append_assoc]
    have hsz :
        (left ++ encodeU32le (UInt32.ofNat "Type.UInt".toUTF8.size) ++
          "Type.UInt".toUTF8).size =
          left.size + 4 + "Type.UInt".toUTF8.size := by
      rw [ByteArray.size_append, ByteArray.size_append, encodeU32le_sizeV1]
    have hread :
        readU16leAtV1 (left ++ typeShapeUInt64BytesV1 ++ right)
            (left.size + 4 + "Type.UInt".toUTF8.size) =
          .ok (1, left.size + 4 + "Type.UInt".toUTF8.size + 2) := by
      rw [hassoc, ← hsz]
      simpa [hsz] using
        readU16le_encode_midV1
          (left ++ encodeU32le (UInt32.ofNat "Type.UInt".toUTF8.size) ++
            "Type.UInt".toUTF8)
          (encodeU16le 64 ++ right) 1
    have h := decodeFieldCount_eq_of_readU16leV1 1
      ⟨left ++ typeShapeUInt64BytesV1 ++ right,
        left.size + 4 + "Type.UInt".toUTF8.size, nesting + 1⟩
      1 (left.size + 4 + "Type.UInt".toUTF8.size + 2) hread
    simpa using h
  have hszFinal :
      left.size + 4 + "Type.UInt".toUTF8.size + 2 + 2 =
        left.size + typeShapeUInt64BytesV1.size := by
    have hszHdr : (taggedHeaderBytesV1 "Type.UInt" 1).size =
        4 + "Type.UInt".toUTF8.size + 2 := taggedHeaderBytesV1_size _ _
    have hszW : (encodeU16le 64).size = 2 := encodeU16le_sizeV1 _
    simp only [typeShapeUInt64BytesV1]
    rw [ByteArray.size_append, hszHdr, hszW]
    omega
  have hwidth :
      decodeU16le
          ⟨left ++ typeShapeUInt64BytesV1 ++ right,
            left.size + 4 + "Type.UInt".toUTF8.size + 2, nesting + 1⟩ =
        .ok (64,
          ⟨left ++ typeShapeUInt64BytesV1 ++ right,
            left.size + typeShapeUInt64BytesV1.size, nesting + 1⟩) := by
    have hassoc :
        left ++ typeShapeUInt64BytesV1 ++ right =
          (left ++ encodeU32le (UInt32.ofNat "Type.UInt".toUTF8.size) ++
            "Type.UInt".toUTF8 ++ encodeU16le 1) ++ encodeU16le 64 ++ right := by
      simp [henc, ByteArray.append_assoc]
    have hsz :
        (left ++ encodeU32le (UInt32.ofNat "Type.UInt".toUTF8.size) ++
          "Type.UInt".toUTF8 ++ encodeU16le 1).size =
          left.size + 4 + "Type.UInt".toUTF8.size + 2 := by
      rw [ByteArray.size_append, ByteArray.size_append, ByteArray.size_append,
        encodeU32le_sizeV1, encodeU16le_sizeV1]
    apply decodeU16le_eq_of_readV1
    rw [← hszFinal, hassoc, ← hsz]
    simpa [hsz] using
      readU16le_encode_midV1
        (left ++ encodeU32le (UInt32.ofNat "Type.UInt".toUTF8.size) ++
          "Type.UInt".toUTF8 ++ encodeU16le 1)
        right 64
  exact decodeTypeShapeBodyV1_uint _ _ _ _ 64 htag hfc hwidth

/-! ### TypeDecl Bool / UInt64 + types array -/

def optionNoneBytesV1 : ByteArray := encodeU8 0

theorem encodeOptionString_none_eq_ok :
    encodeOption encodeString (none : Option String) = .ok optionNoneBytesV1 := by
  rfl

theorem decodeOptionString_none_midV1
    (left right : ByteArray) (nesting : Nat) :
    decodeOption decodeString
        ⟨left ++ optionNoneBytesV1 ++ right, left.size, nesting⟩ =
      .ok (none,
        ⟨left ++ optionNoneBytesV1 ++ right, left.size + 1, nesting⟩) := by
  have hs : optionNoneBytesV1.size = 1 := by
    simp [optionNoneBytesV1, encodeU8, ByteArray.size_push, ByteArray.size_empty]
  have hg : optionNoneBytesV1.data[0]? = some 0 := by
    simp [optionNoneBytesV1, encodeU8, ByteArray.data_push, ByteArray.data_empty]
  have hmarker :
      decodeU8 ⟨left ++ optionNoneBytesV1 ++ right, left.size, nesting⟩ =
        .ok (0, ⟨left ++ optionNoneBytesV1 ++ right, left.size + 1, nesting⟩) := by
    apply decodeU8_eq_of_readV1
    exact readByte_mid_payloadV1 left optionNoneBytesV1 right 0 0
      (by simp [hs]) hg
  exact decodeOption_noneV1 decodeString _ _ hmarker

def typeDeclBoolBytesV1 : ByteArray :=
  taggedHeaderBytesV1 "TypeDecl" 3 ++
    encodeU32le 0 ++ optionNoneBytesV1 ++ typeShapeBoolBytesV1

theorem encodeTypeDecl_bool_eq_ok :
    encodeTypeDeclV1 simpleClosureBoolTypeV1 = .ok typeDeclBoolBytesV1 := by
  simp only [encodeTypeDeclV1, simpleClosureBoolTypeV1, encodeOptionString_none_eq_ok,
    encodeTypeShape_bool_eq_ok, Bind.bind, Pure.pure, Except.bind, Except.pure]
  have htag := encodeTagged_eq_okV1 "TypeDecl"
    #[encodeU32le 0, optionNoneBytesV1, typeShapeBoolBytesV1]
    (by decide) (by decide) (by decide) (by decide) (by decide)
  have heq :
      taggedBytesV1 "TypeDecl"
          #[encodeU32le 0, optionNoneBytesV1, typeShapeBoolBytesV1] =
        typeDeclBoolBytesV1 := by
    simp only [typeDeclBoolBytesV1, taggedBytesV1, taggedBytesFromBytesV1,
      appendTaggedFieldsV1, taggedHeaderBytesV1]
    rfl
  rwa [heq] at htag

def typeDeclUInt64BytesV1 : ByteArray :=
  taggedHeaderBytesV1 "TypeDecl" 3 ++
    encodeU32le 1 ++ optionNoneBytesV1 ++ typeShapeUInt64BytesV1

theorem encodeTypeDecl_uint64_eq_ok :
    encodeTypeDeclV1 simpleClosureUInt64TypeV1 = .ok typeDeclUInt64BytesV1 := by
  simp only [encodeTypeDeclV1, simpleClosureUInt64TypeV1, encodeOptionString_none_eq_ok,
    encodeTypeShape_uint64_eq_ok, Bind.bind, Pure.pure, Except.bind, Except.pure]
  have htag := encodeTagged_eq_okV1 "TypeDecl"
    #[encodeU32le 1, optionNoneBytesV1, typeShapeUInt64BytesV1]
    (by decide) (by decide) (by decide) (by decide) (by decide)
  have heq :
      taggedBytesV1 "TypeDecl"
          #[encodeU32le 1, optionNoneBytesV1, typeShapeUInt64BytesV1] =
        typeDeclUInt64BytesV1 := by
    simp only [typeDeclUInt64BytesV1, taggedBytesV1, taggedBytesFromBytesV1,
      appendTaggedFieldsV1, taggedHeaderBytesV1]
    rfl
  rwa [heq] at htag

def typesArrayBytesV1 : ByteArray :=
  encodeU32le 2 ++ typeDeclBoolBytesV1 ++ typeDeclUInt64BytesV1

theorem encodeTypes_simpleClosure_eq_ok :
    encodeArray encodeTypeDeclV1
        #[simpleClosureBoolTypeV1, simpleClosureUInt64TypeV1] =
      .ok typesArrayBytesV1 := by
  have h :=
    encodeArray_twoV1 encodeTypeDeclV1
      simpleClosureBoolTypeV1 simpleClosureUInt64TypeV1
      typeDeclBoolBytesV1 typeDeclUInt64BytesV1
      encodeTypeDecl_bool_eq_ok encodeTypeDecl_uint64_eq_ok
  simpa [typesArrayBytesV1, ByteArray.append_assoc] using h

theorem encodeTypes_materialize_eq_ok (p : SimpleClosureParamsV1) :
    encodeArray encodeTypeDeclV1 (materializeSimpleClosureDataV1 p).types =
      .ok typesArrayBytesV1 := by
  simpa [materializeSimpleClosureDataV1] using encodeTypes_simpleClosure_eq_ok

/-- Mid-offset decode of anonymous Bool TypeDecl. -/
theorem decodeTypeDecl_bool_midV1
    (left right : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting) :
    decodeTypeDeclV1
        ⟨left ++ typeDeclBoolBytesV1 ++ right, left.size, nesting⟩ =
      .ok (simpleClosureBoolTypeV1,
        ⟨left ++ typeDeclBoolBytesV1 ++ right,
          left.size + typeDeclBoolBytesV1.size, nesting⟩) := by
  have houter : nesting < maxNesting := Nat.lt_of_succ_lt hdepth
  refine decodeTypeDeclV1_eq_of_bodyV1
    ⟨left ++ typeDeclBoolBytesV1 ++ right, left.size, nesting⟩
    simpleClosureBoolTypeV1
    ⟨left ++ typeDeclBoolBytesV1 ++ right,
      left.size + typeDeclBoolBytesV1.size, nesting + 1⟩ houter ?_
  have htag :
      expectTag "TypeDecl" 3
          ⟨left ++ typeDeclBoolBytesV1 ++ right, left.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ typeDeclBoolBytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size, nesting + 1⟩) := by
    have hin :
        left ++ typeDeclBoolBytesV1 ++ right =
          left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++
            (encodeU32le 0 ++ optionNoneBytesV1 ++ typeShapeBoolBytesV1) ++ right := by
      simp [typeDeclBoolBytesV1, ByteArray.append_assoc]
    rw [hin]
    exact expectTag_encode_midV1 left right "TypeDecl" 3
      (encodeU32le 0 ++ optionNoneBytesV1 ++ typeShapeBoolBytesV1) (nesting + 1)
      (by decide) (by decide) (by decide) isAsciiBytes_TypeDecl (by decide)
  have hid :
      decodeU32le
          ⟨left ++ typeDeclBoolBytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size, nesting + 1⟩ =
        .ok (0,
          ⟨left ++ typeDeclBoolBytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4, nesting + 1⟩) := by
    have hassoc :
        left ++ typeDeclBoolBytesV1 ++ right =
          (left ++ taggedHeaderBytesV1 "TypeDecl" 3) ++ encodeU32le 0 ++
            (optionNoneBytesV1 ++ typeShapeBoolBytesV1 ++ right) := by
      simp [typeDeclBoolBytesV1, ByteArray.append_assoc]
    have hsz :
        (left ++ taggedHeaderBytesV1 "TypeDecl" 3).size =
          left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size := by
      rw [ByteArray.size_append]
    apply decodeU32le_eq_of_readV1
    rw [hassoc, ← hsz]
    simpa [hsz] using
      readU32le_encode_midV1 (left ++ taggedHeaderBytesV1 "TypeDecl" 3)
        (optionNoneBytesV1 ++ typeShapeBoolBytesV1 ++ right) 0
  have hname :
      decodeOption decodeString
          ⟨left ++ typeDeclBoolBytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4, nesting + 1⟩ =
        .ok (none,
          ⟨left ++ typeDeclBoolBytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4 + 1,
            nesting + 1⟩) := by
    have hassoc :
        left ++ typeDeclBoolBytesV1 ++ right =
          (left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le 0) ++
            optionNoneBytesV1 ++ (typeShapeBoolBytesV1 ++ right) := by
      simp [typeDeclBoolBytesV1, ByteArray.append_assoc]
    have hsz :
        (left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le 0).size =
          left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4 := by
      rw [ByteArray.size_append, ByteArray.size_append, encodeU32le_sizeV1]
    have h :=
      decodeOptionString_none_midV1
        (left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le 0)
        (typeShapeBoolBytesV1 ++ right) (nesting + 1)
    simpa [hassoc.symm, hsz] using h
  have hshape :
      decodeTypeShapeV1
          ⟨left ++ typeDeclBoolBytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4 + 1,
            nesting + 1⟩ =
        .ok (.bool,
          ⟨left ++ typeDeclBoolBytesV1 ++ right,
            left.size + typeDeclBoolBytesV1.size, nesting + 1⟩) := by
    have hassoc :
        left ++ typeDeclBoolBytesV1 ++ right =
          (left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le 0 ++
            optionNoneBytesV1) ++ typeShapeBoolBytesV1 ++ right := by
      simp [typeDeclBoolBytesV1, ByteArray.append_assoc]
    have hsz :
        (left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le 0 ++
          optionNoneBytesV1).size =
          left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4 + 1 := by
      simp only [optionNoneBytesV1, encodeU8]
      rw [ByteArray.size_append, ByteArray.size_append, ByteArray.size_append,
        encodeU32le_sizeV1, ByteArray.size_push, ByteArray.size_empty]
    have hszFinal :
        left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4 + 1 +
            typeShapeBoolBytesV1.size =
          left.size + typeDeclBoolBytesV1.size := by
      simp only [typeDeclBoolBytesV1, optionNoneBytesV1, encodeU8]
      rw [ByteArray.size_append, ByteArray.size_append, ByteArray.size_append,
        encodeU32le_sizeV1, ByteArray.size_push, ByteArray.size_empty]
      ac_rfl
    have h :=
      decodeTypeShape_bool_midV1
        (left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le 0 ++
          optionNoneBytesV1)
        right (nesting + 1) hdepth
    simpa [hassoc.symm, hsz, hszFinal] using h
  have hbody :=
    decodeTypeDeclBodyV1_eq_of_fields
      ⟨left ++ typeDeclBoolBytesV1 ++ right, left.size, nesting + 1⟩
      ⟨left ++ typeDeclBoolBytesV1 ++ right,
        left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size, nesting + 1⟩
      ⟨left ++ typeDeclBoolBytesV1 ++ right,
        left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4, nesting + 1⟩
      ⟨left ++ typeDeclBoolBytesV1 ++ right,
        left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4 + 1, nesting + 1⟩
      ⟨left ++ typeDeclBoolBytesV1 ++ right,
        left.size + typeDeclBoolBytesV1.size, nesting + 1⟩
      0 none .bool htag hid hname hshape
  simpa [simpleClosureBoolTypeV1] using hbody

theorem decodeTypeDecl_uint64_midV1
    (left right : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting) :
    decodeTypeDeclV1
        ⟨left ++ typeDeclUInt64BytesV1 ++ right, left.size, nesting⟩ =
      .ok (simpleClosureUInt64TypeV1,
        ⟨left ++ typeDeclUInt64BytesV1 ++ right,
          left.size + typeDeclUInt64BytesV1.size, nesting⟩) := by
  have houter : nesting < maxNesting := Nat.lt_of_succ_lt hdepth
  refine decodeTypeDeclV1_eq_of_bodyV1
    ⟨left ++ typeDeclUInt64BytesV1 ++ right, left.size, nesting⟩
    simpleClosureUInt64TypeV1
    ⟨left ++ typeDeclUInt64BytesV1 ++ right,
      left.size + typeDeclUInt64BytesV1.size, nesting + 1⟩ houter ?_
  have htag :
      expectTag "TypeDecl" 3
          ⟨left ++ typeDeclUInt64BytesV1 ++ right, left.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ typeDeclUInt64BytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size, nesting + 1⟩) := by
    have hin :
        left ++ typeDeclUInt64BytesV1 ++ right =
          left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++
            (encodeU32le 1 ++ optionNoneBytesV1 ++ typeShapeUInt64BytesV1) ++ right := by
      simp [typeDeclUInt64BytesV1, ByteArray.append_assoc]
    rw [hin]
    exact expectTag_encode_midV1 left right "TypeDecl" 3
      (encodeU32le 1 ++ optionNoneBytesV1 ++ typeShapeUInt64BytesV1) (nesting + 1)
      (by decide) (by decide) (by decide) isAsciiBytes_TypeDecl (by decide)
  have hid :
      decodeU32le
          ⟨left ++ typeDeclUInt64BytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size, nesting + 1⟩ =
        .ok (1,
          ⟨left ++ typeDeclUInt64BytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4, nesting + 1⟩) := by
    have hassoc :
        left ++ typeDeclUInt64BytesV1 ++ right =
          (left ++ taggedHeaderBytesV1 "TypeDecl" 3) ++ encodeU32le 1 ++
            (optionNoneBytesV1 ++ typeShapeUInt64BytesV1 ++ right) := by
      simp [typeDeclUInt64BytesV1, ByteArray.append_assoc]
    have hsz :
        (left ++ taggedHeaderBytesV1 "TypeDecl" 3).size =
          left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size := by
      rw [ByteArray.size_append]
    apply decodeU32le_eq_of_readV1
    rw [hassoc, ← hsz]
    simpa [hsz] using
      readU32le_encode_midV1 (left ++ taggedHeaderBytesV1 "TypeDecl" 3)
        (optionNoneBytesV1 ++ typeShapeUInt64BytesV1 ++ right) 1
  have hname :
      decodeOption decodeString
          ⟨left ++ typeDeclUInt64BytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4, nesting + 1⟩ =
        .ok (none,
          ⟨left ++ typeDeclUInt64BytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4 + 1,
            nesting + 1⟩) := by
    have hassoc :
        left ++ typeDeclUInt64BytesV1 ++ right =
          (left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le 1) ++
            optionNoneBytesV1 ++ (typeShapeUInt64BytesV1 ++ right) := by
      simp [typeDeclUInt64BytesV1, ByteArray.append_assoc]
    have hsz :
        (left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le 1).size =
          left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4 := by
      rw [ByteArray.size_append, ByteArray.size_append, encodeU32le_sizeV1]
    have h :=
      decodeOptionString_none_midV1
        (left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le 1)
        (typeShapeUInt64BytesV1 ++ right) (nesting + 1)
    simpa [hassoc.symm, hsz] using h
  have hshape :
      decodeTypeShapeV1
          ⟨left ++ typeDeclUInt64BytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4 + 1,
            nesting + 1⟩ =
        .ok (.uint 64,
          ⟨left ++ typeDeclUInt64BytesV1 ++ right,
            left.size + typeDeclUInt64BytesV1.size, nesting + 1⟩) := by
    have hassoc :
        left ++ typeDeclUInt64BytesV1 ++ right =
          (left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le 1 ++
            optionNoneBytesV1) ++ typeShapeUInt64BytesV1 ++ right := by
      simp [typeDeclUInt64BytesV1, ByteArray.append_assoc]
    have hsz :
        (left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le 1 ++
          optionNoneBytesV1).size =
          left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4 + 1 := by
      simp only [optionNoneBytesV1, encodeU8]
      rw [ByteArray.size_append, ByteArray.size_append, ByteArray.size_append,
        encodeU32le_sizeV1, ByteArray.size_push, ByteArray.size_empty]
    have hszFinal :
        left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4 + 1 +
            typeShapeUInt64BytesV1.size =
          left.size + typeDeclUInt64BytesV1.size := by
      simp only [typeDeclUInt64BytesV1, optionNoneBytesV1, encodeU8]
      rw [ByteArray.size_append, ByteArray.size_append, ByteArray.size_append,
        encodeU32le_sizeV1, ByteArray.size_push, ByteArray.size_empty]
      ac_rfl
    have h :=
      decodeTypeShape_uint64_midV1
        (left ++ taggedHeaderBytesV1 "TypeDecl" 3 ++ encodeU32le 1 ++
          optionNoneBytesV1)
        right (nesting + 1) hdepth
    simpa [hassoc.symm, hsz, hszFinal] using h
  have hbody :=
    decodeTypeDeclBodyV1_eq_of_fields
      ⟨left ++ typeDeclUInt64BytesV1 ++ right, left.size, nesting + 1⟩
      ⟨left ++ typeDeclUInt64BytesV1 ++ right,
        left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size, nesting + 1⟩
      ⟨left ++ typeDeclUInt64BytesV1 ++ right,
        left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4, nesting + 1⟩
      ⟨left ++ typeDeclUInt64BytesV1 ++ right,
        left.size + (taggedHeaderBytesV1 "TypeDecl" 3).size + 4 + 1, nesting + 1⟩
      ⟨left ++ typeDeclUInt64BytesV1 ++ right,
        left.size + typeDeclUInt64BytesV1.size, nesting + 1⟩
      1 none (.uint 64) htag hid hname hshape
  simpa [simpleClosureUInt64TypeV1] using hbody

theorem decodeTypes_simpleClosure_midV1
    (left right : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting) :
    decodeArray maxTableElements decodeTypeDeclV1
        ⟨left ++ typesArrayBytesV1 ++ right, left.size, nesting⟩ =
      .ok (#[simpleClosureBoolTypeV1, simpleClosureUInt64TypeV1],
        ⟨left ++ typesArrayBytesV1 ++ right,
          left.size + typesArrayBytesV1.size, nesting⟩) := by
  have hcount :
      readArrayCountAtV1 (left ++ typesArrayBytesV1 ++ right) left.size
          maxTableElements =
        .ok (2, left.size + 4) := by
    have hin :
        left ++ typesArrayBytesV1 ++ right =
          left ++ encodeU32le 2 ++
            (typeDeclBoolBytesV1 ++ typeDeclUInt64BytesV1 ++ right) := by
      simp [typesArrayBytesV1, ByteArray.append_assoc]
    rw [hin]
    exact readArrayCount_encode_midV1 left
      (typeDeclBoolBytesV1 ++ typeDeclUInt64BytesV1 ++ right) 2 maxTableElements
      (by decide) (by decide)
  have h0 :
      decodeTypeDeclV1
          ⟨left ++ typesArrayBytesV1 ++ right, left.size + 4, nesting⟩ =
        .ok (simpleClosureBoolTypeV1,
          ⟨left ++ typesArrayBytesV1 ++ right,
            left.size + 4 + typeDeclBoolBytesV1.size, nesting⟩) := by
    have hassoc :
        left ++ typesArrayBytesV1 ++ right =
          (left ++ encodeU32le 2) ++ typeDeclBoolBytesV1 ++
            (typeDeclUInt64BytesV1 ++ right) := by
      simp [typesArrayBytesV1, ByteArray.append_assoc]
    have hsz : (left ++ encodeU32le 2).size = left.size + 4 := by
      rw [ByteArray.size_append, encodeU32le_sizeV1]
    have h :=
      decodeTypeDecl_bool_midV1 (left ++ encodeU32le 2)
        (typeDeclUInt64BytesV1 ++ right) nesting hdepth
    simpa [hassoc.symm, hsz] using h
  have h1 :
      decodeTypeDeclV1
          ⟨left ++ typesArrayBytesV1 ++ right,
            left.size + 4 + typeDeclBoolBytesV1.size, nesting⟩ =
        .ok (simpleClosureUInt64TypeV1,
          ⟨left ++ typesArrayBytesV1 ++ right,
            left.size + typesArrayBytesV1.size, nesting⟩) := by
    have hassoc :
        left ++ typesArrayBytesV1 ++ right =
          (left ++ encodeU32le 2 ++ typeDeclBoolBytesV1) ++ typeDeclUInt64BytesV1 ++
            right := by
      simp [typesArrayBytesV1, ByteArray.append_assoc]
    have hsz :
        (left ++ encodeU32le 2 ++ typeDeclBoolBytesV1).size =
          left.size + 4 + typeDeclBoolBytesV1.size := by
      rw [ByteArray.size_append, ByteArray.size_append, encodeU32le_sizeV1]
    have hszFinal :
        left.size + 4 + typeDeclBoolBytesV1.size + typeDeclUInt64BytesV1.size =
          left.size + typesArrayBytesV1.size := by
      simp only [typesArrayBytesV1]
      rw [ByteArray.size_append, ByteArray.size_append, encodeU32le_sizeV1]
      omega
    have h :=
      decodeTypeDecl_uint64_midV1
        (left ++ encodeU32le 2 ++ typeDeclBoolBytesV1) right nesting hdepth
    simpa [hassoc.symm, hsz, hszFinal] using h
  exact decodeArray_twoV1 maxTableElements decodeTypeDeclV1
    ⟨left ++ typesArrayBytesV1 ++ right, left.size, nesting⟩
    (left.size + 4)
    simpleClosureBoolTypeV1 simpleClosureUInt64TypeV1
    ⟨left ++ typesArrayBytesV1 ++ right,
      left.size + 4 + typeDeclBoolBytesV1.size, nesting⟩
    ⟨left ++ typesArrayBytesV1 ++ right,
      left.size + typesArrayBytesV1.size, nesting⟩
    hcount h0 h1

/-! ### Four empty tables -/

abbrev emptyTableBytesV1 : ByteArray := encodeU32le 0

theorem decodeEmptyTable_midV1
    (maxCount : Nat) (decode : Decoder α)
    (left right : ByteArray) (nesting : Nat) :
    decodeArray maxCount decode
        ⟨left ++ emptyTableBytesV1 ++ right, left.size, nesting⟩ =
      .ok (#[],
        ⟨left ++ emptyTableBytesV1 ++ right, left.size + 4, nesting⟩) :=
  decodeArray_encode_zero_midV1 maxCount decode left right nesting

theorem decodeEmptyConstants_materialize_midV1
    (left right : ByteArray) (nesting : Nat) :
    decodeArray maxTableElements decodeConstantV1
        ⟨left ++ emptyTableBytesV1 ++ right, left.size, nesting⟩ =
      .ok (#[], ⟨left ++ emptyTableBytesV1 ++ right, left.size + 4, nesting⟩) :=
  decodeEmptyTable_midV1 _ _ left right nesting

theorem decodeEmptyLogicalState_materialize_midV1
    (left right : ByteArray) (nesting : Nat) :
    decodeArray maxTableElements decodeStateDeclV1
        ⟨left ++ emptyTableBytesV1 ++ right, left.size, nesting⟩ =
      .ok (#[], ⟨left ++ emptyTableBytesV1 ++ right, left.size + 4, nesting⟩) :=
  decodeEmptyTable_midV1 _ _ left right nesting

theorem decodeEmptyEvents_materialize_midV1
    (left right : ByteArray) (nesting : Nat) :
    decodeArray maxTableElements decodeEventDeclV1
        ⟨left ++ emptyTableBytesV1 ++ right, left.size, nesting⟩ =
      .ok (#[], ⟨left ++ emptyTableBytesV1 ++ right, left.size + 4, nesting⟩) :=
  decodeEmptyTable_midV1 _ _ left right nesting

theorem decodeEmptyErrors_materialize_midV1
    (left right : ByteArray) (nesting : Nat) :
    decodeArray maxTableElements decodeErrorDeclV1
        ⟨left ++ emptyTableBytesV1 ++ right, left.size, nesting⟩ =
      .ok (#[], ⟨left ++ emptyTableBytesV1 ++ right, left.size + 4, nesting⟩) :=
  decodeEmptyTable_midV1 _ _ left right nesting

theorem encodeEmptyTables_materialize (p : SimpleClosureParamsV1) :
    encodeArray encodeConstantV1 (materializeSimpleClosureDataV1 p).constants =
      .ok emptyTableBytesV1 ∧
    encodeArray encodeStateDeclV1 (materializeSimpleClosureDataV1 p).logicalState =
      .ok emptyTableBytesV1 ∧
    encodeArray encodeEventDeclV1 (materializeSimpleClosureDataV1 p).events =
      .ok emptyTableBytesV1 ∧
    encodeArray encodeErrorDeclV1 (materializeSimpleClosureDataV1 p).errors =
      .ok emptyTableBytesV1 :=
  materialize_empty_tables_encode p

/-! ### InvariantDecl (dynamic legal invName) -/

def invariantDeclPayloadBytesV1 (invName : String) : ByteArray :=
  encodeU32le 0 ++ stringPayloadBytesV1 invName ++ encodeU32le 1

def invariantDeclBytesV1 (invName : String) : ByteArray :=
  taggedHeaderBytesV1 "InvariantDecl" 3 ++ invariantDeclPayloadBytesV1 invName

theorem encodeInvariantDecl_of_identifier
    (invName : String)
    (hident : validateIdentifierComponent invName = .ok ()) :
    encodeInvariantDeclV1 (simpleClosureInvariantDeclV1 invName) =
      .ok (invariantDeclBytesV1 invName) := by
  have hstr := encodeString_of_identifierV1 invName hident
  simp only [encodeInvariantDeclV1, simpleClosureInvariantDeclV1, hstr,
    Bind.bind, Pure.pure, Except.bind, Except.pure]
  have htag :=
    encodeTagged_eq_okV1 "InvariantDecl"
      #[encodeU32le 0, stringPayloadBytesV1 invName, encodeU32le 1]
      (by decide) (by decide) (by decide) (by decide)
      (by
        change 3 ≤ UInt16.size - 1
        decide)
  have heq :
      taggedBytesV1 "InvariantDecl"
          #[encodeU32le 0, stringPayloadBytesV1 invName, encodeU32le 1] =
        invariantDeclBytesV1 invName := by
    simp only [invariantDeclBytesV1, invariantDeclPayloadBytesV1, taggedBytesV1,
      taggedBytesFromBytesV1, appendTaggedFieldsV1, taggedHeaderBytesV1]
    rfl
  rwa [heq] at htag

theorem encodeInvariantDecl_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    encodeInvariantDeclV1 (simpleClosureInvariantDeclV1 p.invName) =
      .ok (invariantDeclBytesV1 p.invName) :=
  encodeInvariantDecl_of_identifier p.invName legal.hinv

def invariantsArrayBytesV1 (invName : String) : ByteArray :=
  encodeU32le 1 ++ invariantDeclBytesV1 invName

theorem encodeInvariants_array_of_identifier
    (invName : String)
    (hident : validateIdentifierComponent invName = .ok ()) :
    encodeArray encodeInvariantDeclV1 #[simpleClosureInvariantDeclV1 invName] =
      .ok (invariantsArrayBytesV1 invName) := by
  have h1 := encodeInvariantDecl_of_identifier invName hident
  have h :=
    encodeArray_oneV1 encodeInvariantDeclV1
      (simpleClosureInvariantDeclV1 invName) (invariantDeclBytesV1 invName) h1
  simpa [invariantsArrayBytesV1] using h

theorem encodeInvariants_materialize_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    encodeArray encodeInvariantDeclV1 (materializeSimpleClosureDataV1 p).invariants =
      .ok (invariantsArrayBytesV1 p.invName) := by
  have h := encodeInvariants_array_of_identifier p.invName legal.hinv
  simpa [materializeSimpleClosureDataV1] using h

theorem decodeInvariantDecl_of_identifier_midV1
    (left right : ByteArray) (invName : String) (nesting : Nat)
    (hident : validateIdentifierComponent invName = .ok ())
    (hdepth : nesting < maxNesting) :
    decodeInvariantDeclV1
        ⟨left ++ invariantDeclBytesV1 invName ++ right, left.size, nesting⟩ =
      .ok (simpleClosureInvariantDeclV1 invName,
        ⟨left ++ invariantDeclBytesV1 invName ++ right,
          left.size + (invariantDeclBytesV1 invName).size, nesting⟩) := by
  refine decodeInvariantDeclV1_eq_of_bodyV1
    ⟨left ++ invariantDeclBytesV1 invName ++ right, left.size, nesting⟩
    (simpleClosureInvariantDeclV1 invName)
    ⟨left ++ invariantDeclBytesV1 invName ++ right,
      left.size + (invariantDeclBytesV1 invName).size, nesting + 1⟩ hdepth ?_
  have htag :
      expectTag "InvariantDecl" 3
          ⟨left ++ invariantDeclBytesV1 invName ++ right, left.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ invariantDeclBytesV1 invName ++ right,
            left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size,
            nesting + 1⟩) := by
    have hin :
        left ++ invariantDeclBytesV1 invName ++ right =
          left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++
            invariantDeclPayloadBytesV1 invName ++ right := by
      simp [invariantDeclBytesV1, ByteArray.append_assoc]
    rw [hin]
    exact expectTag_encode_midV1 left right "InvariantDecl" 3
      (invariantDeclPayloadBytesV1 invName) (nesting + 1)
      (by decide) (by decide) (by decide) isAsciiBytes_InvariantDecl (by decide)
  have hid :
      decodeU32le
          ⟨left ++ invariantDeclBytesV1 invName ++ right,
            left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size, nesting + 1⟩ =
        .ok (0,
          ⟨left ++ invariantDeclBytesV1 invName ++ right,
            left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4,
            nesting + 1⟩) := by
    have hassoc :
        left ++ invariantDeclBytesV1 invName ++ right =
          (left ++ taggedHeaderBytesV1 "InvariantDecl" 3) ++ encodeU32le 0 ++
            (stringPayloadBytesV1 invName ++ encodeU32le 1 ++ right) := by
      simp [invariantDeclBytesV1, invariantDeclPayloadBytesV1, ByteArray.append_assoc]
    have hsz :
        (left ++ taggedHeaderBytesV1 "InvariantDecl" 3).size =
          left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size := by
      rw [ByteArray.size_append]
    apply decodeU32le_eq_of_readV1
    rw [hassoc, ← hsz]
    simpa [hsz] using
      readU32le_encode_midV1 (left ++ taggedHeaderBytesV1 "InvariantDecl" 3)
        (stringPayloadBytesV1 invName ++ encodeU32le 1 ++ right) 0
  have hszP : (stringPayloadBytesV1 invName).size = 4 + invName.toUTF8.size := by
    simp only [stringPayloadBytesV1]
    change (encodeU32le (UInt32.ofNat invName.toUTF8.size) ++ invName.toUTF8).size =
      4 + invName.toUTF8.size
    rw [ByteArray.size_append, encodeU32le_sizeV1]
  have hname :
      decodeString
          ⟨left ++ invariantDeclBytesV1 invName ++ right,
            left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4,
            nesting + 1⟩ =
        .ok (invName,
          ⟨left ++ invariantDeclBytesV1 invName ++ right,
            left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4 +
              (stringPayloadBytesV1 invName).size,
            nesting + 1⟩) := by
    have hassoc :
        left ++ invariantDeclBytesV1 invName ++ right =
          (left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++ encodeU32le 0) ++
            stringPayloadBytesV1 invName ++ (encodeU32le 1 ++ right) := by
      simp [invariantDeclBytesV1, invariantDeclPayloadBytesV1, ByteArray.append_assoc]
    have hsz :
        (left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++ encodeU32le 0).size =
          left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4 := by
      change ((left ++ taggedHeaderBytesV1 "InvariantDecl" 3) ++ encodeU32le 0).size =
        left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4
      rw [ByteArray.size_append, ByteArray.size_append, encodeU32le_sizeV1]
    have hoff :
        left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4 +
            4 + invName.toUTF8.size =
          left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4 +
            (stringPayloadBytesV1 invName).size := by
      rw [hszP]; omega
    -- Prove with rewritten target offset first
    rw [← hoff]
    have h :=
      decodeString_of_identifier_midV1
        (left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++ encodeU32le 0)
        (encodeU32le 1 ++ right) invName (nesting + 1) hident
    simpa [hassoc.symm, hsz] using h
  have hcall :
      decodeU32le
          ⟨left ++ invariantDeclBytesV1 invName ++ right,
            left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4 +
              (stringPayloadBytesV1 invName).size,
            nesting + 1⟩ =
        .ok (1,
          ⟨left ++ invariantDeclBytesV1 invName ++ right,
            left.size + (invariantDeclBytesV1 invName).size, nesting + 1⟩) := by
    have hassoc :
        left ++ invariantDeclBytesV1 invName ++ right =
          (left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++ encodeU32le 0 ++
            stringPayloadBytesV1 invName) ++ encodeU32le 1 ++ right := by
      simp [invariantDeclBytesV1, invariantDeclPayloadBytesV1, ByteArray.append_assoc]
    have hsz :
        (left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++ encodeU32le 0 ++
          stringPayloadBytesV1 invName).size =
          left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4 +
            (stringPayloadBytesV1 invName).size := by
      change
        (((left ++ taggedHeaderBytesV1 "InvariantDecl" 3) ++ encodeU32le 0) ++
            stringPayloadBytesV1 invName).size =
          left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4 +
            (stringPayloadBytesV1 invName).size
      rw [ByteArray.size_append, ByteArray.size_append, ByteArray.size_append,
        encodeU32le_sizeV1]
    have hszFinal :
        left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4 +
            (stringPayloadBytesV1 invName).size + 4 =
          left.size + (invariantDeclBytesV1 invName).size := by
      simp only [invariantDeclBytesV1, invariantDeclPayloadBytesV1]
      change
          left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4 +
              (stringPayloadBytesV1 invName).size + 4 =
            left.size +
              (taggedHeaderBytesV1 "InvariantDecl" 3 ++
                encodeU32le 0 ++ stringPayloadBytesV1 invName ++ encodeU32le 1).size
      rw [ByteArray.size_append, ByteArray.size_append, ByteArray.size_append,
        encodeU32le_sizeV1 (0 : UInt32), encodeU32le_sizeV1 (1 : UInt32)]
      ac_rfl
    apply decodeU32le_eq_of_readV1
    rw [← hszFinal, hassoc, ← hsz]
    simpa [hsz] using
      readU32le_encode_midV1
        (left ++ taggedHeaderBytesV1 "InvariantDecl" 3 ++ encodeU32le 0 ++
          stringPayloadBytesV1 invName)
        right 1
  have hbody :=
    decodeInvariantDeclBodyV1_eq_of_fields
      ⟨left ++ invariantDeclBytesV1 invName ++ right, left.size, nesting + 1⟩
      ⟨left ++ invariantDeclBytesV1 invName ++ right,
        left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size, nesting + 1⟩
      ⟨left ++ invariantDeclBytesV1 invName ++ right,
        left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4, nesting + 1⟩
      ⟨left ++ invariantDeclBytesV1 invName ++ right,
        left.size + (taggedHeaderBytesV1 "InvariantDecl" 3).size + 4 +
          (stringPayloadBytesV1 invName).size, nesting + 1⟩
      ⟨left ++ invariantDeclBytesV1 invName ++ right,
        left.size + (invariantDeclBytesV1 invName).size, nesting + 1⟩
      0 1 invName htag hid hname hcall
  simpa [simpleClosureInvariantDeclV1] using hbody

theorem decodeInvariantDecl_of_legal_midV1
    (left right : ByteArray) (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) (nesting : Nat)
    (hdepth : nesting < maxNesting) :
    decodeInvariantDeclV1
        ⟨left ++ invariantDeclBytesV1 p.invName ++ right, left.size, nesting⟩ =
      .ok (simpleClosureInvariantDeclV1 p.invName,
        ⟨left ++ invariantDeclBytesV1 p.invName ++ right,
          left.size + (invariantDeclBytesV1 p.invName).size, nesting⟩) :=
  decodeInvariantDecl_of_identifier_midV1 left right p.invName nesting legal.hinv hdepth

theorem decodeInvariants_array_of_identifier_midV1
    (left right : ByteArray) (invName : String) (nesting : Nat)
    (hident : validateIdentifierComponent invName = .ok ())
    (hdepth : nesting < maxNesting) :
    decodeArray maxTableElements decodeInvariantDeclV1
        ⟨left ++ invariantsArrayBytesV1 invName ++ right, left.size, nesting⟩ =
      .ok (#[simpleClosureInvariantDeclV1 invName],
        ⟨left ++ invariantsArrayBytesV1 invName ++ right,
          left.size + (invariantsArrayBytesV1 invName).size, nesting⟩) := by
  have hcount :
      readArrayCountAtV1 (left ++ invariantsArrayBytesV1 invName ++ right)
          left.size maxTableElements =
        .ok (1, left.size + 4) := by
    have hin :
        left ++ invariantsArrayBytesV1 invName ++ right =
          left ++ encodeU32le 1 ++ (invariantDeclBytesV1 invName ++ right) := by
      simp [invariantsArrayBytesV1, ByteArray.append_assoc]
    rw [hin]
    exact readArrayCount_encode_midV1 left (invariantDeclBytesV1 invName ++ right)
      1 maxTableElements (by decide) (by decide)
  have h0 :
      decodeInvariantDeclV1
          ⟨left ++ invariantsArrayBytesV1 invName ++ right, left.size + 4, nesting⟩ =
        .ok (simpleClosureInvariantDeclV1 invName,
          ⟨left ++ invariantsArrayBytesV1 invName ++ right,
            left.size + (invariantsArrayBytesV1 invName).size, nesting⟩) := by
    have hassoc :
        left ++ invariantsArrayBytesV1 invName ++ right =
          (left ++ encodeU32le 1) ++ invariantDeclBytesV1 invName ++ right := by
      simp [invariantsArrayBytesV1, ByteArray.append_assoc]
    have hsz : (left ++ encodeU32le 1).size = left.size + 4 := by
      rw [ByteArray.size_append, encodeU32le_sizeV1]
    have hszFinal :
        left.size + 4 + (invariantDeclBytesV1 invName).size =
          left.size + (invariantsArrayBytesV1 invName).size := by
      simp only [invariantsArrayBytesV1]
      rw [ByteArray.size_append, encodeU32le_sizeV1]
      ac_rfl
    have h :=
      decodeInvariantDecl_of_identifier_midV1 (left ++ encodeU32le 1) right invName
        nesting hident hdepth
    simpa [hassoc.symm, hsz, hszFinal] using h
  exact decodeArray_oneV1 maxTableElements decodeInvariantDeclV1
    ⟨left ++ invariantsArrayBytesV1 invName ++ right, left.size, nesting⟩
    (left.size + 4) (simpleClosureInvariantDeclV1 invName)
    ⟨left ++ invariantsArrayBytesV1 invName ++ right,
      left.size + (invariantsArrayBytesV1 invName).size, nesting⟩
    hcount h0

theorem decodeInvariants_array_of_legal_midV1
    (left right : ByteArray) (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) (nesting : Nat)
    (hdepth : nesting < maxNesting) :
    decodeArray maxTableElements decodeInvariantDeclV1
        ⟨left ++ invariantsArrayBytesV1 p.invName ++ right, left.size, nesting⟩ =
      .ok (#[simpleClosureInvariantDeclV1 p.invName],
        ⟨left ++ invariantsArrayBytesV1 p.invName ++ right,
          left.size + (invariantsArrayBytesV1 p.invName).size, nesting⟩) :=
  decodeInvariants_array_of_identifier_midV1 left right p.invName nesting
    legal.hinv hdepth

/-! ### Sole value.bool ProgramRequirements -/

private theorem s2ValueBoolDigestBytesV1_size :
    s2ValueBoolDigestBytesV1.size = 32 := by
  simp only [s2ValueBoolDigestBytesV1]
  rfl

private theorem validateDigest_valueBool :
    validateDigest
        { algorithm := .sha256, bytes := s2ValueBoolDigestBytesV1 } = .ok () := by
  simp only [validateDigest, s2ValueBoolDigestBytesV1_size, ↓reduceIte,
    Pure.pure, Except.pure]

private theorem encodeDigest_valueBool_eq_ok :
    encodeDigest { algorithm := .sha256, bytes := s2ValueBoolDigestBytesV1 } =
      .ok s2ValueBoolDigestBytesV1 := by
  simp only [encodeDigest, mapCommon, validateDigest_valueBool, Bind.bind, Pure.pure,
    Except.bind, Except.pure]

private theorem s2RequirementVersion_eq_core :
    s2RequirementVersionV1 = s2CatalogSemVerCoreV1 := rfl

private theorem renderSemVer_s2_eq_ok :
    renderSemVer s2RequirementVersionV1 = .ok "1.0.0" := by
  simp only [s2RequirementVersion_eq_core, renderSemVer, s2CatalogSemVerCoreV1]
  rfl

private theorem encodeString_value_bool_eq_ok :
    encodeString s2ValueBoolIdV1 = .ok (stringPayloadBytesV1 s2ValueBoolIdV1) := by
  have hascii : isAscii s2ValueBoolIdV1 = true := by
    simp only [s2ValueBoolIdV1]; decide
  exact encodeString_eq_stringPayloadV1 s2ValueBoolIdV1
    (requireNfc_eq_ok_of_isAscii _ hascii) (by decide)

private theorem encodeString_1_0_0_eq_ok :
    encodeString "1.0.0" = .ok (stringPayloadBytesV1 "1.0.0") :=
  encodeString_eq_stringPayloadV1 "1.0.0"
    (requireNfc_eq_ok_of_isAscii _ (by decide)) (by decide)

private theorem encodeSemVer_s2_eq_ok :
    encodeSemVer s2RequirementVersionV1 =
      .ok (stringPayloadBytesV1 "1.0.0") := by
  simp only [encodeSemVer, mapCommon, renderSemVer_s2_eq_ok, Bind.bind, Pure.pure,
    Except.bind, Except.pure, encodeString_1_0_0_eq_ok]

def requirementRequestValueBoolBytesV1 : ByteArray :=
  taggedHeaderBytesV1 "RequirementRequest" 4 ++
    stringPayloadBytesV1 s2ValueBoolIdV1 ++
    stringPayloadBytesV1 "1.0.0" ++
    s2ValueBoolDigestBytesV1 ++
    encodeU32le 0

theorem encodeRequirementRequest_valueBool_eq_ok :
    encodeRequirementRequestV1 simpleClosureBoolRequirementV1 =
      .ok requirementRequestValueBoolBytesV1 := by
  simp only [encodeRequirementRequestV1, simpleClosureBoolRequirementV1,
    encodeString_value_bool_eq_ok, encodeSemVer_s2_eq_ok, encodeDigest_valueBool_eq_ok,
    encodeArray_zeroV1, Bind.bind, Pure.pure, Except.bind, Except.pure]
  have htag :=
    encodeTagged_eq_okV1 "RequirementRequest"
      #[stringPayloadBytesV1 s2ValueBoolIdV1, stringPayloadBytesV1 "1.0.0",
        s2ValueBoolDigestBytesV1, encodeU32le 0]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  have heq :
      taggedBytesV1 "RequirementRequest"
          #[stringPayloadBytesV1 s2ValueBoolIdV1, stringPayloadBytesV1 "1.0.0",
            s2ValueBoolDigestBytesV1, encodeU32le 0] =
        requirementRequestValueBoolBytesV1 := by
    simp only [requirementRequestValueBoolBytesV1, taggedBytesV1, taggedBytesFromBytesV1,
      appendTaggedFieldsV1, taggedHeaderBytesV1]
    rfl
  rwa [heq] at htag

def programRequirementsValueBoolBytesV1 : ByteArray :=
  taggedHeaderBytesV1 "ProgramRequirements" 1 ++
    encodeU32le 1 ++ requirementRequestValueBoolBytesV1

theorem encodeProgramRequirements_valueBool_eq_ok :
    encodeProgramRequirementsV1 { items := #[simpleClosureBoolRequirementV1] } =
      .ok programRequirementsValueBoolBytesV1 := by
  have hitem := encodeRequirementRequest_valueBool_eq_ok
  have harr :=
    encodeArray_oneV1 encodeRequirementRequestV1 simpleClosureBoolRequirementV1
      requirementRequestValueBoolBytesV1 hitem
  simp only [encodeProgramRequirementsV1, harr, Bind.bind, Pure.pure, Except.bind,
    Except.pure]
  have htag :=
    encodeTagged_eq_okV1 "ProgramRequirements"
      #[encodeU32le 1 ++ requirementRequestValueBoolBytesV1]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  have heq :
      taggedBytesV1 "ProgramRequirements"
          #[encodeU32le 1 ++ requirementRequestValueBoolBytesV1] =
        programRequirementsValueBoolBytesV1 := by
    simp only [programRequirementsValueBoolBytesV1, taggedBytesV1, taggedBytesFromBytesV1,
      appendTaggedFieldsV1, taggedHeaderBytesV1]
    rfl
  rwa [heq] at htag

theorem encodeRequirements_materialize_eq_ok (p : SimpleClosureParamsV1) :
    encodeProgramRequirementsV1 (materializeSimpleClosureDataV1 p).requirements =
      .ok programRequirementsValueBoolBytesV1 := by
  simpa [materializeSimpleClosureDataV1] using
    encodeProgramRequirements_valueBool_eq_ok

/-- Mid-offset decode of sole value.bool RequirementRequest. -/
theorem decodeRequirementRequest_valueBool_midV1
    (left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) :
    decodeRequirementRequestV1
        ⟨left ++ requirementRequestValueBoolBytesV1 ++ right, left.size, nesting⟩ =
      .ok (simpleClosureBoolRequirementV1,
        ⟨left ++ requirementRequestValueBoolBytesV1 ++ right,
          left.size + requirementRequestValueBoolBytesV1.size, nesting⟩) := by
  -- Expand withTaggedNesting
  have hnest : nesting < maxNesting := hdepth
  have htag :
      expectTag "RequirementRequest" 4
          ⟨left ++ requirementRequestValueBoolBytesV1 ++ right, left.size,
            nesting + 1⟩ =
        .ok ((),
          ⟨left ++ requirementRequestValueBoolBytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size,
            nesting + 1⟩) := by
    have hin :
        left ++ requirementRequestValueBoolBytesV1 ++ right =
          left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++
            (stringPayloadBytesV1 s2ValueBoolIdV1 ++ stringPayloadBytesV1 "1.0.0" ++
              s2ValueBoolDigestBytesV1 ++ encodeU32le 0) ++ right := by
      simp [requirementRequestValueBoolBytesV1, ByteArray.append_assoc]
    rw [hin]
    exact expectTag_encode_midV1 left right "RequirementRequest" 4
      (stringPayloadBytesV1 s2ValueBoolIdV1 ++ stringPayloadBytesV1 "1.0.0" ++
        s2ValueBoolDigestBytesV1 ++ encodeU32le 0)
      (nesting + 1) (by decide) (by decide) (by decide)
      isAsciiBytes_RequirementRequest (by decide)
  have hid :
      decodeString
          ⟨left ++ requirementRequestValueBoolBytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size,
            nesting + 1⟩ =
        .ok (s2ValueBoolIdV1,
          ⟨left ++ requirementRequestValueBoolBytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size +
              (stringPayloadBytesV1 s2ValueBoolIdV1).size,
            nesting + 1⟩) := by
    have hassoc :
        left ++ requirementRequestValueBoolBytesV1 ++ right =
          (left ++ taggedHeaderBytesV1 "RequirementRequest" 4) ++
            stringPayloadBytesV1 s2ValueBoolIdV1 ++
            (stringPayloadBytesV1 "1.0.0" ++ s2ValueBoolDigestBytesV1 ++
              encodeU32le 0 ++ right) := by
      simp [requirementRequestValueBoolBytesV1, ByteArray.append_assoc]
    have hsz :
        (left ++ taggedHeaderBytesV1 "RequirementRequest" 4).size =
          left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size := by
      rw [ByteArray.size_append]
    have hascii : isAscii s2ValueBoolIdV1 = true := by
      simp only [s2ValueBoolIdV1]; decide
    have hszP : (stringPayloadBytesV1 s2ValueBoolIdV1).size =
        4 + s2ValueBoolIdV1.toUTF8.size := by
      simp only [stringPayloadBytesV1]
      change (encodeU32le (UInt32.ofNat s2ValueBoolIdV1.toUTF8.size) ++
          s2ValueBoolIdV1.toUTF8).size = 4 + s2ValueBoolIdV1.toUTF8.size
      rw [ByteArray.size_append, encodeU32le_sizeV1]
    have h :=
      decodeString_nfc_midV1
        (left ++ taggedHeaderBytesV1 "RequirementRequest" 4)
        (stringPayloadBytesV1 "1.0.0" ++ s2ValueBoolDigestBytesV1 ++
          encodeU32le 0 ++ right)
        s2ValueBoolIdV1 (nesting + 1)
        (requireNfc_eq_ok_of_isAscii _ hascii) (by decide)
    -- Align final offset form to payload size
    have hoff :
        left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size +
            4 + s2ValueBoolIdV1.toUTF8.size =
          left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size +
            (stringPayloadBytesV1 s2ValueBoolIdV1).size := by
      rw [hszP]; omega
    rw [← hoff]
    simpa [hassoc.symm, hsz] using h
  have hver :
      decodeSemVer
          ⟨left ++ requirementRequestValueBoolBytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size +
              (stringPayloadBytesV1 s2ValueBoolIdV1).size,
            nesting + 1⟩ =
        .ok (s2RequirementVersionV1,
          ⟨left ++ requirementRequestValueBoolBytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size +
              (stringPayloadBytesV1 s2ValueBoolIdV1).size +
              (stringPayloadBytesV1 "1.0.0").size,
            nesting + 1⟩) := by
    have hassoc :
        left ++ requirementRequestValueBoolBytesV1 ++ right =
          (left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++
            stringPayloadBytesV1 s2ValueBoolIdV1) ++
            stringPayloadBytesV1 "1.0.0" ++
            (s2ValueBoolDigestBytesV1 ++ encodeU32le 0 ++ right) := by
      simp [requirementRequestValueBoolBytesV1, ByteArray.append_assoc]
    have hsz :
        (left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++
          stringPayloadBytesV1 s2ValueBoolIdV1).size =
          left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size +
            (stringPayloadBytesV1 s2ValueBoolIdV1).size := by
      change
        ((left ++ taggedHeaderBytesV1 "RequirementRequest" 4) ++
            stringPayloadBytesV1 s2ValueBoolIdV1).size =
          left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size +
            (stringPayloadBytesV1 s2ValueBoolIdV1).size
      rw [ByteArray.size_append, ByteArray.size_append]
    have hszP : (stringPayloadBytesV1 "1.0.0").size = 4 + "1.0.0".toUTF8.size := by
      simp only [stringPayloadBytesV1]
      change (encodeU32le (UInt32.ofNat "1.0.0".toUTF8.size) ++ "1.0.0".toUTF8).size =
        4 + "1.0.0".toUTF8.size
      rw [ByteArray.size_append, encodeU32le_sizeV1]
    have hstr :
        decodeString
            ⟨left ++ requirementRequestValueBoolBytesV1 ++ right,
              left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size +
                (stringPayloadBytesV1 s2ValueBoolIdV1).size,
              nesting + 1⟩ =
          .ok ("1.0.0",
            ⟨left ++ requirementRequestValueBoolBytesV1 ++ right,
              left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size +
                (stringPayloadBytesV1 s2ValueBoolIdV1).size +
                (stringPayloadBytesV1 "1.0.0").size,
              nesting + 1⟩) := by
      have hoff :
          left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size +
              (stringPayloadBytesV1 s2ValueBoolIdV1).size +
              4 + "1.0.0".toUTF8.size =
            left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size +
              (stringPayloadBytesV1 s2ValueBoolIdV1).size +
              (stringPayloadBytesV1 "1.0.0").size := by
        rw [hszP]; omega
      rw [← hoff]
      have h :=
        decodeString_nfc_midV1
          (left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++
            stringPayloadBytesV1 s2ValueBoolIdV1)
          (s2ValueBoolDigestBytesV1 ++ encodeU32le 0 ++ right)
          "1.0.0" (nesting + 1)
          (requireNfc_eq_ok_of_isAscii _ (by decide)) (by decide)
      simpa [hassoc.symm, hsz] using h
    apply decodeSemVer_eq_of_stringV1 _ _ _ s2RequirementVersionV1 hstr
    simpa [s2RequirementVersion_eq_core] using parseSemVer_1_0_0
  have hdig :
      decodeDigest
          ⟨left ++ requirementRequestValueBoolBytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size +
              (stringPayloadBytesV1 s2ValueBoolIdV1).size +
              (stringPayloadBytesV1 "1.0.0").size,
            nesting + 1⟩ =
        .ok ({ algorithm := .sha256, bytes := s2ValueBoolDigestBytesV1 },
          ⟨left ++ requirementRequestValueBoolBytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size +
              (stringPayloadBytesV1 s2ValueBoolIdV1).size +
              (stringPayloadBytesV1 "1.0.0").size + 32,
            nesting + 1⟩) := by
    have hassoc :
        left ++ requirementRequestValueBoolBytesV1 ++ right =
          (left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++
            stringPayloadBytesV1 s2ValueBoolIdV1 ++
            stringPayloadBytesV1 "1.0.0") ++
            s2ValueBoolDigestBytesV1 ++ (encodeU32le 0 ++ right) := by
      simp [requirementRequestValueBoolBytesV1, ByteArray.append_assoc]
    have hsz :
        (left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++
          stringPayloadBytesV1 s2ValueBoolIdV1 ++
          stringPayloadBytesV1 "1.0.0").size =
          left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size +
            (stringPayloadBytesV1 s2ValueBoolIdV1).size +
            (stringPayloadBytesV1 "1.0.0").size := by
      rw [ByteArray.size_append, ByteArray.size_append, ByteArray.size_append]
    have hszDig : s2ValueBoolDigestBytesV1.size = 32 := by
      simp only [s2ValueBoolDigestBytesV1]; decide
    have htake :
        takeBytesAtV1 (left ++ requirementRequestValueBoolBytesV1 ++ right)
            (left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size +
              (stringPayloadBytesV1 s2ValueBoolIdV1).size +
              (stringPayloadBytesV1 "1.0.0").size)
            32 =
          .ok s2ValueBoolDigestBytesV1 := by
      rw [hassoc, ← hsz, ← hszDig]
      simpa [hszDig] using
        takeBytes_mid_payloadV1
          (left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++
            stringPayloadBytesV1 s2ValueBoolIdV1 ++
            stringPayloadBytesV1 "1.0.0")
          s2ValueBoolDigestBytesV1 (encodeU32le 0 ++ right)
    exact decodeDigest_eq_of_takeV1 _ _ htake validateDigest_valueBool
  have hpred :
      decodeArray maxArrayElements decodeRequirementPredicateV1
          ⟨left ++ requirementRequestValueBoolBytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size +
              (stringPayloadBytesV1 s2ValueBoolIdV1).size +
              (stringPayloadBytesV1 "1.0.0").size + 32,
            nesting + 1⟩ =
        .ok (#[],
          ⟨left ++ requirementRequestValueBoolBytesV1 ++ right,
            left.size + requirementRequestValueBoolBytesV1.size, nesting + 1⟩) := by
    have hassoc :
        left ++ requirementRequestValueBoolBytesV1 ++ right =
          (left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++
            stringPayloadBytesV1 s2ValueBoolIdV1 ++
            stringPayloadBytesV1 "1.0.0" ++ s2ValueBoolDigestBytesV1) ++
            encodeU32le 0 ++ right := by
      simp [requirementRequestValueBoolBytesV1, ByteArray.append_assoc]
    have h32 : s2ValueBoolDigestBytesV1.size = 32 := by
      simp only [s2ValueBoolDigestBytesV1]; decide
    have hsz :
        (left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++
          stringPayloadBytesV1 s2ValueBoolIdV1 ++
          stringPayloadBytesV1 "1.0.0" ++ s2ValueBoolDigestBytesV1).size =
          left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size +
            (stringPayloadBytesV1 s2ValueBoolIdV1).size +
            (stringPayloadBytesV1 "1.0.0").size + 32 := by
      rw [ByteArray.size_append, ByteArray.size_append, ByteArray.size_append,
        ByteArray.size_append, h32]
    have hszFinal :
        left.size + (taggedHeaderBytesV1 "RequirementRequest" 4).size +
            (stringPayloadBytesV1 s2ValueBoolIdV1).size +
            (stringPayloadBytesV1 "1.0.0").size + 32 + 4 =
          left.size + requirementRequestValueBoolBytesV1.size := by
      simp only [requirementRequestValueBoolBytesV1]
      rw [ByteArray.size_append, ByteArray.size_append, ByteArray.size_append,
        ByteArray.size_append, encodeU32le_sizeV1, h32]
      omega
    have h :=
      decodeArray_encode_zero_midV1 maxArrayElements decodeRequirementPredicateV1
        (left ++ taggedHeaderBytesV1 "RequirementRequest" 4 ++
          stringPayloadBytesV1 s2ValueBoolIdV1 ++
          stringPayloadBytesV1 "1.0.0" ++ s2ValueBoolDigestBytesV1)
        right (nesting + 1)
    simpa [hassoc.symm, hsz, hszFinal] using h
  -- Assemble via withTaggedNesting + sequential field successes.
  simp only [decodeRequirementRequestV1, withTaggedNesting, hnest, ↓reduceIte,
    Bind.bind, Pure.pure, Except.bind, Except.pure]
  simp only [htag, hid, hver, hdig, hpred]
  simp [simpleClosureBoolRequirementV1, s2ValueBoolIdV1]

theorem decodeProgramRequirements_valueBool_midV1
    (left right : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting) :
    decodeProgramRequirementsV1
        ⟨left ++ programRequirementsValueBoolBytesV1 ++ right, left.size, nesting⟩ =
      .ok ({ items := #[simpleClosureBoolRequirementV1] },
        ⟨left ++ programRequirementsValueBoolBytesV1 ++ right,
          left.size + programRequirementsValueBoolBytesV1.size, nesting⟩) := by
  have houter : nesting < maxNesting := Nat.lt_of_succ_lt hdepth
  refine decodeProgramRequirementsV1_eq_of_bodyV1
    ⟨left ++ programRequirementsValueBoolBytesV1 ++ right, left.size, nesting⟩
    { items := #[simpleClosureBoolRequirementV1] }
    ⟨left ++ programRequirementsValueBoolBytesV1 ++ right,
      left.size + programRequirementsValueBoolBytesV1.size, nesting + 1⟩ houter ?_
  have htag :
      expectTag "ProgramRequirements" 1
          ⟨left ++ programRequirementsValueBoolBytesV1 ++ right, left.size,
            nesting + 1⟩ =
        .ok ((),
          ⟨left ++ programRequirementsValueBoolBytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size,
            nesting + 1⟩) := by
    have hin :
        left ++ programRequirementsValueBoolBytesV1 ++ right =
          left ++ taggedHeaderBytesV1 "ProgramRequirements" 1 ++
            (encodeU32le 1 ++ requirementRequestValueBoolBytesV1) ++ right := by
      simp [programRequirementsValueBoolBytesV1, ByteArray.append_assoc]
    rw [hin]
    exact expectTag_encode_midV1 left right "ProgramRequirements" 1
      (encodeU32le 1 ++ requirementRequestValueBoolBytesV1) (nesting + 1)
      (by decide) (by decide) (by decide) isAsciiBytes_ProgramRequirements (by decide)
  have hitems :
      decodeArray maxArrayElements decodeRequirementRequestV1
          ⟨left ++ programRequirementsValueBoolBytesV1 ++ right,
            left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size,
            nesting + 1⟩ =
        .ok (#[simpleClosureBoolRequirementV1],
          ⟨left ++ programRequirementsValueBoolBytesV1 ++ right,
            left.size + programRequirementsValueBoolBytesV1.size, nesting + 1⟩) := by
    have hcount :
        readArrayCountAtV1 (left ++ programRequirementsValueBoolBytesV1 ++ right)
            (left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size)
            maxArrayElements =
          .ok (1,
            left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size + 4) := by
      have hassoc :
          left ++ programRequirementsValueBoolBytesV1 ++ right =
            (left ++ taggedHeaderBytesV1 "ProgramRequirements" 1) ++
              encodeU32le 1 ++ (requirementRequestValueBoolBytesV1 ++ right) := by
        simp [programRequirementsValueBoolBytesV1, ByteArray.append_assoc]
      have hsz :
          (left ++ taggedHeaderBytesV1 "ProgramRequirements" 1).size =
            left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size := by
        rw [ByteArray.size_append]
      rw [hassoc, ← hsz]
      simpa [hsz] using
        readArrayCount_encode_midV1
          (left ++ taggedHeaderBytesV1 "ProgramRequirements" 1)
          (requirementRequestValueBoolBytesV1 ++ right) 1 maxArrayElements
          (by decide) (by decide)
    have h0 :
        decodeRequirementRequestV1
            ⟨left ++ programRequirementsValueBoolBytesV1 ++ right,
              left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size + 4,
              nesting + 1⟩ =
          .ok (simpleClosureBoolRequirementV1,
            ⟨left ++ programRequirementsValueBoolBytesV1 ++ right,
              left.size + programRequirementsValueBoolBytesV1.size,
              nesting + 1⟩) := by
      have hassoc :
          left ++ programRequirementsValueBoolBytesV1 ++ right =
            (left ++ taggedHeaderBytesV1 "ProgramRequirements" 1 ++
              encodeU32le 1) ++ requirementRequestValueBoolBytesV1 ++ right := by
        simp [programRequirementsValueBoolBytesV1, ByteArray.append_assoc]
      have hsz :
          (left ++ taggedHeaderBytesV1 "ProgramRequirements" 1 ++
            encodeU32le 1).size =
            left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size + 4 := by
        rw [ByteArray.size_append, ByteArray.size_append, encodeU32le_sizeV1]
      have hszFinal :
          left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size + 4 +
              requirementRequestValueBoolBytesV1.size =
            left.size + programRequirementsValueBoolBytesV1.size := by
        simp only [programRequirementsValueBoolBytesV1]
        rw [ByteArray.size_append, ByteArray.size_append, encodeU32le_sizeV1]
        omega
      have h :=
        decodeRequirementRequest_valueBool_midV1
          (left ++ taggedHeaderBytesV1 "ProgramRequirements" 1 ++ encodeU32le 1)
          right (nesting + 1) hdepth
      simpa [hassoc.symm, hsz, hszFinal] using h
    exact decodeArray_oneV1 maxArrayElements decodeRequirementRequestV1
      ⟨left ++ programRequirementsValueBoolBytesV1 ++ right,
        left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size,
        nesting + 1⟩
      (left.size + (taggedHeaderBytesV1 "ProgramRequirements" 1).size + 4)
      simpleClosureBoolRequirementV1
      ⟨left ++ programRequirementsValueBoolBytesV1 ++ right,
        left.size + programRequirementsValueBoolBytesV1.size, nesting + 1⟩
      hcount h0
  exact decodeProgramRequirementsBodyV1_eq_of_fields _ _ _ _ htag hitems

/-! ### Demo + Unicode kernel witnesses (no Tests FQN) -/

def demoParamsV1 : SimpleClosureParamsV1 :=
  { qnHead := "Module"
    qnTail := #["Prog"]
    viewName := "alive"
    invName := "safe" }

private theorem ident_Module :
    validateIdentifierComponent "Module" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "Module" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem ident_Prog :
    validateIdentifierComponent "Prog" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "Prog" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem ident_alive :
    validateIdentifierComponent "alive" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "alive" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem ident_safe :
    validateIdentifierComponent "safe" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "safe" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

theorem demoParams_legal : SimpleClosureParamsLegalV1 demoParamsV1 := by
  refine {
    hqnSize := by decide
    hdistinct := by decide
    hqnHead := ident_Module
    hqnTail := ?_
    hview := ident_alive
    hinv := ident_safe
  }
  intro i hi
  have : i = 0 := by
    simp [demoParamsV1] at hi
    omega
  subst this
  exact ident_Prog

theorem demo_decodeTypes_mid (left right : ByteArray) :
    decodeArray maxTableElements decodeTypeDeclV1
        ⟨left ++ typesArrayBytesV1 ++ right, left.size, 1⟩ =
      .ok (#[simpleClosureBoolTypeV1, simpleClosureUInt64TypeV1],
        ⟨left ++ typesArrayBytesV1 ++ right,
          left.size + typesArrayBytesV1.size, 1⟩) :=
  decodeTypes_simpleClosure_midV1 left right 1 (by decide)

theorem demo_decodeInvariants_mid (left right : ByteArray) :
    decodeArray maxTableElements decodeInvariantDeclV1
        ⟨left ++ invariantsArrayBytesV1 demoParamsV1.invName ++ right,
          left.size, 1⟩ =
      .ok (#[simpleClosureInvariantDeclV1 demoParamsV1.invName],
        ⟨left ++ invariantsArrayBytesV1 demoParamsV1.invName ++ right,
          left.size + (invariantsArrayBytesV1 demoParamsV1.invName).size, 1⟩) :=
  decodeInvariants_array_of_legal_midV1 left right demoParamsV1 demoParams_legal 1
    (by decide)

theorem demo_decodeRequirements_mid (left right : ByteArray) :
    decodeProgramRequirementsV1
        ⟨left ++ programRequirementsValueBoolBytesV1 ++ right, left.size, 1⟩ =
      .ok ({ items := #[simpleClosureBoolRequirementV1] },
        ⟨left ++ programRequirementsValueBoolBytesV1 ++ right,
          left.size + programRequirementsValueBoolBytesV1.size, 1⟩) :=
  decodeProgramRequirements_valueBool_midV1 left right 1 (by decide)

def unicodeLegalParamsV1 : SimpleClosureParamsV1 :=
  { qnHead := "ModuleΑ"
    qnTail := #["ProgΒ"]
    viewName := "aliveΑ"
    invName := "safeΒ" }

theorem encodeInvariantDecl_of_identifier_param
    (invName : String)
    (hident : validateIdentifierComponent invName = .ok ()) :
    encodeInvariantDeclV1 (simpleClosureInvariantDeclV1 invName) =
      .ok (invariantDeclBytesV1 invName) :=
  encodeInvariantDecl_of_identifier invName hident

theorem decodeInvariantDecl_of_identifier_param_mid
    (left right : ByteArray) (invName : String) (nesting : Nat)
    (hident : validateIdentifierComponent invName = .ok ())
    (hdepth : nesting < maxNesting) :
    decodeInvariantDeclV1
        ⟨left ++ invariantDeclBytesV1 invName ++ right, left.size, nesting⟩ =
      .ok (simpleClosureInvariantDeclV1 invName,
        ⟨left ++ invariantDeclBytesV1 invName ++ right,
          left.size + (invariantDeclBytesV1 invName).size, nesting⟩) :=
  decodeInvariantDecl_of_identifier_midV1 left right invName nesting hident hdepth

end ProofForgeV2.Semantic.SimpleClosureDecodeFixedFieldsV1
