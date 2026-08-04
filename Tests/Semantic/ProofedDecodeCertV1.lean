/-
  Tests.Semantic.ProofedDecodeCertV1 — decode-only kernel certificate for the
  elaborator-generated Proofed simple carrier.

  Sole target:
    decodeSemanticProgramDataV1 proofedBytes = .ok proofedData

  `proofedBytes` is definitionally `Proofed.Proof.subjectBytesV1` (transparent
  spine). Composition is transport-only: CodecV1 framing/array helpers, no
  structure gate / encode lane.
-/
import Tests.Semantic.ProofedCertV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.RequirementIdsV1
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode

set_option maxHeartbeats 80000000
set_option maxRecDepth 400000

namespace Tests.Semantic.ProofedDecodeCertV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
open ProofForgeV2.Semantic.RequirementIdsV1
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.WireV1
open Tests.Semantic.ProofedCertV1
open Tests.Language.InlineProofAuthoringV1

/-! ### Transparent elaborator spine (definitionally `proofedBytes`) -/

def proofedMagicSpine : TransparentByteSpineV1 := [
  112, 102, 46, 115, 101, 109, 97, 110, 116, 105, 99, 46, 118, 49, 0
]

def proofedRootHeaderSpine : TransparentByteSpineV1 := [
  20, 0, 0, 0, 83, 101, 109, 97, 110, 116, 105, 99, 80, 114, 111, 103, 114, 97, 109, 46,
  68, 97, 116, 97, 9, 0
]

def proofedQualifiedNameSpine : TransparentByteSpineV1 := [
  4, 0, 0, 0, 5, 0, 0, 0, 84, 101, 115, 116, 115, 8, 0, 0, 0, 76, 97, 110, 103, 117, 97,
  103, 101, 22, 0, 0, 0, 73, 110, 108, 105, 110, 101, 80, 114, 111, 111, 102, 65, 117,
  116, 104, 111, 114, 105, 110, 103, 86, 49, 7, 0, 0, 0, 80, 114, 111, 111, 102, 101,
  100
]

def proofedTypesSpine : TransparentByteSpineV1 := [
  2, 0, 0, 0, 8, 0, 0, 0, 84, 121, 112, 101, 68, 101, 99, 108, 3, 0, 0, 0, 0, 0, 0, 9,
  0, 0, 0, 84, 121, 112, 101, 46, 66, 111, 111, 108, 0, 0, 8, 0, 0, 0, 84, 121, 112,
  101, 68, 101, 99, 108, 3, 0, 1, 0, 0, 0, 0, 9, 0, 0, 0, 84, 121, 112, 101, 46, 85, 73,
  110, 116, 1, 0, 64, 0
]

def proofedEmptyTablesSpine : TransparentByteSpineV1 := [
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
]

def proofedCallablesHeaderSpine : TransparentByteSpineV1 := [
  2, 0, 0, 0
]

def proofedViewCallableSpine : TransparentByteSpineV1 := [
  8, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 9, 0, 0, 0, 0, 0, 13, 0, 0, 0, 67, 97,
  108, 108, 97, 98, 108, 101, 46, 86, 105, 101, 119, 0, 0, 1, 5, 0, 0, 0, 97, 108, 105,
  118, 101, 0, 0, 0, 0, 14, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115,
  117, 108, 116, 2, 0, 0, 0, 0, 0, 17, 0, 0, 0, 86, 105, 115, 105, 98, 105, 108, 105,
  116, 121, 46, 80, 117, 98, 108, 105, 99, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 5, 0, 0, 0, 66,
  108, 111, 99, 107, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 11, 0, 0, 0, 73, 110,
  115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117,
  101, 68, 101, 102, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 79, 112, 46, 76, 105,
  116, 101, 114, 97, 108, 2, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 11, 0, 0, 0, 84, 101, 114,
  109, 46, 82, 101, 116, 117, 114, 110, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0
]

def proofedInvariantCallableSpine : TransparentByteSpineV1 := [
  8, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 9, 0, 1, 0, 0, 0, 18, 0, 0, 0, 67, 97,
  108, 108, 97, 98, 108, 101, 46, 73, 110, 118, 97, 114, 105, 97, 110, 116, 0, 0, 1, 4,
  0, 0, 0, 115, 97, 102, 101, 0, 0, 0, 0, 14, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108,
  101, 82, 101, 115, 117, 108, 116, 2, 0, 0, 0, 0, 0, 17, 0, 0, 0, 86, 105, 115, 105,
  98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99, 0, 0, 0, 0, 0, 0, 1, 0, 0,
  0, 5, 0, 0, 0, 66, 108, 111, 99, 107, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 11, 0,
  0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86,
  97, 108, 117, 101, 68, 101, 102, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 79, 112,
  46, 76, 105, 116, 101, 114, 97, 108, 2, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 11, 0, 0, 0, 84,
  101, 114, 109, 46, 82, 101, 116, 117, 114, 110, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3,
  0, 0, 0, 0, 0, 0, 0
]

def proofedInvariantsSpine : TransparentByteSpineV1 := [
  1, 0, 0, 0, 13, 0, 0, 0, 73, 110, 118, 97, 114, 105, 97, 110, 116, 68, 101, 99, 108,
  3, 0, 0, 0, 0, 0, 4, 0, 0, 0, 115, 97, 102, 101, 1, 0, 0, 0
]

def proofedRequirementsSpine : TransparentByteSpineV1 := [
  19, 0, 0, 0, 80, 114, 111, 103, 114, 97, 109, 82, 101, 113, 117, 105, 114, 101, 109,
  101, 110, 116, 115, 1, 0, 1, 0, 0, 0, 18, 0, 0, 0, 82, 101, 113, 117, 105, 114, 101,
  109, 101, 110, 116, 82, 101, 113, 117, 101, 115, 116, 4, 0, 10, 0, 0, 0, 118, 97, 108,
  117, 101, 46, 98, 111, 111, 108, 5, 0, 0, 0, 49, 46, 48, 46, 48, 237, 52, 225, 6, 29,
  14, 102, 99, 155, 106, 118, 55, 29, 216, 166, 193, 204, 215, 46, 122, 154, 20, 116,
  84, 218, 122, 83, 193, 167, 71, 84, 124, 0, 0, 0, 0
]

def proofedSpine : TransparentByteSpineV1 :=
  proofedMagicSpine ++ proofedRootHeaderSpine ++ proofedQualifiedNameSpine ++
    proofedTypesSpine ++ proofedEmptyTablesSpine ++ proofedCallablesHeaderSpine ++
    proofedViewCallableSpine ++ proofedInvariantCallableSpine ++
    proofedInvariantsSpine ++ proofedRequirementsSpine


theorem proofedSpine_length : proofedSpine.length = 802 := by rfl

theorem proofedBytes_eq_spine :
    proofedBytes = ByteArray.mk proofedSpine.toArray := by
  simp only [proofedBytes]
  rfl

/-- Local name for the elaborator-equal spine bytes (same as `proofedBytes`). -/
def proofedWireBytes : ByteArray := ByteArray.mk proofedSpine.toArray

theorem proofedWireBytes_eq_proofedBytes :
    proofedWireBytes = proofedBytes := proofedBytes_eq_spine.symm

/-! ### Shared private cursor helpers (InvariantABI style) -/

private theorem decodeProofedTagV1 (offset after nesting : Nat)
    (raw : TransparentByteSpineV1) (value : String)
    (hspine : readTagSpineBytesV1 proofedSpine offset = .ok (raw, after))
    (hutf8 : String.fromUTF8? (ByteArray.mk raw.toArray) = some value)
    (hascii : isAsciiTagV1 value = true) :
    decodeTag ⟨proofedWireBytes, offset, nesting⟩ =
      .ok (value, ⟨proofedWireBytes, after, nesting⟩) := by
  apply decodeTag_eq_of_valueV1 _ _ _ _ _ hutf8 hascii
  change readTagBytesAtV1 (ByteArray.mk proofedSpine.toArray) offset =
    .ok (ByteArray.mk raw.toArray, after)
  exact readTagBytesAtV1_eq_of_spine proofedSpine raw offset after hspine

private theorem decodeProofedZeroFieldsV1 (offset after nesting : Nat)
    (hspine : readSpineU16leV1 proofedSpine offset = .ok (0, after)) :
    decodeFieldCount 0 ⟨proofedWireBytes, offset, nesting⟩ =
      .ok ((), ⟨proofedWireBytes, after, nesting⟩) := by
  have hread : readU16leAtV1 proofedWireBytes offset = .ok (0, after) := by
    change readU16leAtV1 (ByteArray.mk proofedSpine.toArray) offset = .ok (0, after)
    rw [readU16leAtV1_refinesSpine, hspine]
  simpa using decodeFieldCount_eq_of_readU16leV1 0
    ⟨proofedWireBytes, offset, nesting⟩ 0 after hread

private theorem decodeProofedOneFieldV1 (offset after nesting : Nat)
    (hspine : readSpineU16leV1 proofedSpine offset = .ok (1, after)) :
    decodeFieldCount 1 ⟨proofedWireBytes, offset, nesting⟩ =
      .ok ((), ⟨proofedWireBytes, after, nesting⟩) := by
  have hread : readU16leAtV1 proofedWireBytes offset = .ok (1, after) := by
    change readU16leAtV1 (ByteArray.mk proofedSpine.toArray) offset = .ok (1, after)
    rw [readU16leAtV1_refinesSpine, hspine]
  simpa using decodeFieldCount_eq_of_readU16leV1 1
    ⟨proofedWireBytes, offset, nesting⟩ 1 after hread

private theorem decodeProofedTwoFieldsV1 (offset after nesting : Nat)
    (hspine : readSpineU16leV1 proofedSpine offset = .ok (2, after)) :
    decodeFieldCount 2 ⟨proofedWireBytes, offset, nesting⟩ =
      .ok ((), ⟨proofedWireBytes, after, nesting⟩) := by
  have hread : readU16leAtV1 proofedWireBytes offset = .ok (2, after) := by
    change readU16leAtV1 (ByteArray.mk proofedSpine.toArray) offset = .ok (2, after)
    rw [readU16leAtV1_refinesSpine, hspine]
  simpa using decodeFieldCount_eq_of_readU16leV1 2
    ⟨proofedWireBytes, offset, nesting⟩ 2 after hread

private theorem decodeProofedU32V1 (offset after nesting value : Nat)
    (hspine : readSpineU32leV1 proofedSpine offset =
      .ok (UInt32.ofNat value, after)) :
    decodeU32le ⟨proofedWireBytes, offset, nesting⟩ =
      .ok (UInt32.ofNat value, ⟨proofedWireBytes, after, nesting⟩) := by
  apply decodeU32le_eq_of_readV1
  change readU32leAtV1 (ByteArray.mk proofedSpine.toArray) offset =
    .ok (UInt32.ofNat value, after)
  rw [readU32leAtV1_refinesSpine, hspine]

private theorem decodeProofedU16V1 (offset after nesting value : Nat)
    (hspine : readSpineU16leV1 proofedSpine offset =
      .ok (UInt16.ofNat value, after)) :
    decodeU16le ⟨proofedWireBytes, offset, nesting⟩ =
      .ok (UInt16.ofNat value, ⟨proofedWireBytes, after, nesting⟩) := by
  apply decodeU16le_eq_of_readV1
  change readU16leAtV1 (ByteArray.mk proofedSpine.toArray) offset =
    .ok (UInt16.ofNat value, after)
  rw [readU16leAtV1_refinesSpine, hspine]

private theorem decodeProofedU64V1 (offset after nesting value : Nat)
    (hspine : readSpineU64leV1 proofedSpine offset =
      .ok (UInt64.ofNat value, after)) :
    decodeU64le ⟨proofedWireBytes, offset, nesting⟩ =
      .ok (UInt64.ofNat value, ⟨proofedWireBytes, after, nesting⟩) := by
  apply decodeU64le_eq_of_readV1
  change readU64leAtV1 (ByteArray.mk proofedSpine.toArray) offset =
    .ok (UInt64.ofNat value, after)
  rw [readU64leAtV1_refinesSpine, hspine]

private theorem decodeAsciiString_of_read (bytes : ByteArray) (offset after : Nat)
    (raw : TransparentByteSpineV1) (value : String) (nesting : Nat)
    (hread : readSizedBytesAtV1 bytes offset maxStringBytes =
      .ok (ByteArray.mk raw.toArray, after))
    (hutf8 : String.fromUTF8? (ByteArray.mk raw.toArray) = some value)
    (hascii : isAscii value = true) :
    decodeString ⟨bytes, offset, nesting⟩ =
      .ok (value, ⟨bytes, after, nesting⟩) := by
  apply decodeString_eq_of_valueV1 _ _ _ _ hread hutf8
  exact requireNfc_eq_ok_of_isAscii value hascii

/-! ### Magic + root header -/

theorem consumeMagic_proofed :
    consumeMagic semanticProgramMagicV1 (start proofedWireBytes) =
      .ok ((), ⟨proofedWireBytes, 15, 0⟩) := by
  apply consumeMagic_eq_of_bytesV1
  change consumeMagicBytesAtV1 (ByteArray.mk proofedSpine.toArray) 0
      (ByteArray.mk proofedMagicSpine.toArray) = .ok 15
  rw [consumeMagicBytesAtV1_refinesSpine]
  unfold consumeMagicSpineBytesV1 takeSpineBytesV1 spineRemainingV1
  rw [proofedSpine_length]
  rfl

theorem expectRootTag_proofed :
    expectTag "SemanticProgram.Data" 9 ⟨proofedWireBytes, 15, 1⟩ =
      .ok ((), ⟨proofedWireBytes, 41, 1⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk proofedSpine.toArray) 15
      (ByteArray.mk [83, 101, 109, 97, 110, 116, 105, 99, 80, 114, 111, 103,
        114, 97, 109, 46, 68, 97, 116, 97].toArray) 9 = .ok 41
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [proofedSpine_length]
  rfl

/-! ### QualifiedName (4 components) -/

theorem readQnCount_proofed :
    readArrayCountAtV1 proofedWireBytes 41 256 = .ok (4, 45) := by
  change readArrayCountAtV1 (ByteArray.mk proofedSpine.toArray) 41 256 = .ok (4, 45)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

private theorem readSized_proofed (offset after : Nat) (raw : TransparentByteSpineV1)
    (hparts : readSizedSpineBytesV1 proofedSpine offset maxStringBytes =
      .ok (raw, after)) :
    readSizedBytesAtV1 proofedWireBytes offset maxStringBytes =
      .ok (ByteArray.mk raw.toArray, after) := by
  change readSizedBytesAtV1 (ByteArray.mk proofedSpine.toArray) offset maxStringBytes =
    .ok (ByteArray.mk raw.toArray, after)
  exact readSizedBytesAtV1_eq_of_spine proofedSpine raw offset maxStringBytes after hparts

theorem readQnTests_proofed :
    readSizedBytesAtV1 proofedWireBytes 45 maxStringBytes =
      .ok (ByteArray.mk [84, 101, 115, 116, 115].toArray, 54) := by
  apply readSized_proofed
  apply readSizedSpineBytesV1_eq_of_parts proofedSpine [84, 101, 115, 116, 115]
      45 maxStringBytes 5 49
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [proofedSpine_length]
    rfl

theorem readQnLanguage_proofed :
    readSizedBytesAtV1 proofedWireBytes 54 maxStringBytes =
      .ok (ByteArray.mk [76, 97, 110, 103, 117, 97, 103, 101].toArray, 66) := by
  apply readSized_proofed
  apply readSizedSpineBytesV1_eq_of_parts proofedSpine
      [76, 97, 110, 103, 117, 97, 103, 101] 54 maxStringBytes 8 58
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [proofedSpine_length]
    rfl

theorem readQnModule_proofed :
    readSizedBytesAtV1 proofedWireBytes 66 maxStringBytes =
      .ok (ByteArray.mk [73, 110, 108, 105, 110, 101, 80, 114, 111, 111, 102, 65, 117,
        116, 104, 111, 114, 105, 110, 103, 86, 49].toArray, 92) := by
  apply readSized_proofed
  apply readSizedSpineBytesV1_eq_of_parts proofedSpine
      [73, 110, 108, 105, 110, 101, 80, 114, 111, 111, 102, 65, 117, 116, 104, 111,
        114, 105, 110, 103, 86, 49] 66 maxStringBytes 22 70
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [proofedSpine_length]
    rfl

theorem readQnProofed_proofed :
    readSizedBytesAtV1 proofedWireBytes 92 maxStringBytes =
      .ok (ByteArray.mk [80, 114, 111, 111, 102, 101, 100].toArray, 103) := by
  apply readSized_proofed
  apply readSizedSpineBytesV1_eq_of_parts proofedSpine
      [80, 114, 111, 111, 102, 101, 100] 92 maxStringBytes 7 96
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [proofedSpine_length]
    rfl

theorem decodeQnTests_proofed :
    decodeString ⟨proofedWireBytes, 45, 1⟩ =
      .ok ("Tests", ⟨proofedWireBytes, 54, 1⟩) :=
  decodeAsciiString_of_read proofedWireBytes 45 54 [84, 101, 115, 116, 115] "Tests" 1
    readQnTests_proofed (by rfl) (by rfl)

theorem decodeQnLanguage_proofed :
    decodeString ⟨proofedWireBytes, 54, 1⟩ =
      .ok ("Language", ⟨proofedWireBytes, 66, 1⟩) :=
  decodeAsciiString_of_read proofedWireBytes 54 66
    [76, 97, 110, 103, 117, 97, 103, 101] "Language" 1
    readQnLanguage_proofed (by rfl) (by rfl)

theorem decodeQnModule_proofed :
    decodeString ⟨proofedWireBytes, 66, 1⟩ =
      .ok ("InlineProofAuthoringV1", ⟨proofedWireBytes, 92, 1⟩) :=
  decodeAsciiString_of_read proofedWireBytes 66 92
    [73, 110, 108, 105, 110, 101, 80, 114, 111, 111, 102, 65, 117, 116, 104, 111,
      114, 105, 110, 103, 86, 49] "InlineProofAuthoringV1" 1
    readQnModule_proofed (by rfl) (by rfl)

theorem decodeQnProofedName_proofed :
    decodeString ⟨proofedWireBytes, 92, 1⟩ =
      .ok ("Proofed", ⟨proofedWireBytes, 103, 1⟩) :=
  decodeAsciiString_of_read proofedWireBytes 92 103
    [80, 114, 111, 111, 102, 101, 100] "Proofed" 1
    readQnProofed_proofed (by rfl) (by rfl)

theorem decodeQualifiedName_proofed :
    decodeQualifiedName ⟨proofedWireBytes, 41, 1⟩ =
      .ok (qn, ⟨proofedWireBytes, 103, 1⟩) := by
  apply decodeQualifiedName_eq_of_arrayV1
  · apply decodeArray_fourV1
    · exact readQnCount_proofed
    · exact decodeQnTests_proofed
    · exact decodeQnLanguage_proofed
    · exact decodeQnModule_proofed
    · exact decodeQnProofedName_proofed
  · rfl

/-! ### Types (Bool + UInt64) -/

theorem readTypesCount_proofed :
    readArrayCountAtV1 proofedWireBytes 103 maxTableElements = .ok (2, 107) := by
  change readArrayCountAtV1 (ByteArray.mk proofedSpine.toArray) 103 maxTableElements =
    .ok (2, 107)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

theorem expectTypeDecl0_proofed :
    expectTag "TypeDecl" 3 ⟨proofedWireBytes, 107, 2⟩ =
      .ok ((), ⟨proofedWireBytes, 121, 2⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk proofedSpine.toArray) 107
      (ByteArray.mk [84, 121, 112, 101, 68, 101, 99, 108].toArray) 3 = .ok 121
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [proofedSpine_length]
  rfl

theorem expectTypeDecl1_proofed :
    expectTag "TypeDecl" 3 ⟨proofedWireBytes, 141, 2⟩ =
      .ok ((), ⟨proofedWireBytes, 155, 2⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk proofedSpine.toArray) 141
      (ByteArray.mk [84, 121, 112, 101, 68, 101, 99, 108].toArray) 3 = .ok 155
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [proofedSpine_length]
  rfl

theorem decodeTypeShapeBool_proofed :
    decodeTypeShapeV1 ⟨proofedWireBytes, 126, 2⟩ =
      .ok (.bool, ⟨proofedWireBytes, 141, 2⟩) := by
  refine decodeTypeShapeV1_eq_of_bodyV1 ⟨proofedWireBytes, 126, 2⟩ .bool
    ⟨proofedWireBytes, 141, 3⟩ (by decide) ?_
  apply decodeTypeShapeBodyV1_bool
  · apply decodeProofedTagV1 126 139 3
      [84, 121, 112, 101, 46, 66, 111, 111, 108] "Type.Bool"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [proofedSpine_length]
      rfl
    · rfl
    · rfl
  · apply decodeProofedZeroFieldsV1
    rfl

theorem decodeTypeShapeUInt64_proofed :
    decodeTypeShapeV1 ⟨proofedWireBytes, 160, 2⟩ =
      .ok (.uint 64, ⟨proofedWireBytes, 177, 2⟩) := by
  refine decodeTypeShapeV1_eq_of_bodyV1 ⟨proofedWireBytes, 160, 2⟩ (.uint 64)
    ⟨proofedWireBytes, 177, 3⟩ (by decide) ?_
  apply decodeTypeShapeBodyV1_uint
  · apply decodeProofedTagV1 160 173 3
      [84, 121, 112, 101, 46, 85, 73, 110, 116] "Type.UInt"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [proofedSpine_length]
      rfl
    · rfl
    · rfl
  · apply decodeProofedOneFieldV1
    rfl
  · apply decodeProofedU16V1
    rfl

theorem decodeTypeDecl0_proofed :
    decodeTypeDeclV1 ⟨proofedWireBytes, 107, 1⟩ =
      .ok (boolT, ⟨proofedWireBytes, 141, 1⟩) := by
  refine decodeTypeDeclV1_eq_of_bodyV1 ⟨proofedWireBytes, 107, 1⟩ boolT
    ⟨proofedWireBytes, 141, 2⟩ (by decide) ?_
  apply decodeTypeDeclBodyV1_eq_of_fields
  · exact expectTypeDecl0_proofed
  · apply decodeProofedU32V1
    rfl
  · apply decodeOption_noneV1
    apply decodeU8_eq_of_readV1
    change readByteAtV1 (ByteArray.mk proofedSpine.toArray) 125 = .ok 0
    rw [readByteAtV1_refinesSpine]
    rfl
  · exact decodeTypeShapeBool_proofed

theorem decodeTypeDecl1_proofed :
    decodeTypeDeclV1 ⟨proofedWireBytes, 141, 1⟩ =
      .ok (u64T, ⟨proofedWireBytes, 177, 1⟩) := by
  refine decodeTypeDeclV1_eq_of_bodyV1 ⟨proofedWireBytes, 141, 1⟩ u64T
    ⟨proofedWireBytes, 177, 2⟩ (by decide) ?_
  apply decodeTypeDeclBodyV1_eq_of_fields
  · exact expectTypeDecl1_proofed
  · apply decodeProofedU32V1
    rfl
  · apply decodeOption_noneV1
    apply decodeU8_eq_of_readV1
    change readByteAtV1 (ByteArray.mk proofedSpine.toArray) 159 = .ok 0
    rw [readByteAtV1_refinesSpine]
    rfl
  · exact decodeTypeShapeUInt64_proofed

theorem decodeTypes_proofed :
    decodeArray maxTableElements decodeTypeDeclV1 ⟨proofedWireBytes, 103, 1⟩ =
      .ok (#[boolT, u64T], ⟨proofedWireBytes, 177, 1⟩) := by
  have h := decodeArray_twoV1 maxTableElements decodeTypeDeclV1
    ⟨proofedWireBytes, 103, 1⟩ 107 boolT u64T
    ⟨proofedWireBytes, 141, 1⟩ ⟨proofedWireBytes, 177, 1⟩
    readTypesCount_proofed decodeTypeDecl0_proofed decodeTypeDecl1_proofed
  simpa using h

/-! ### Four empty tables -/

theorem decodeConstants_proofed :
    decodeArray maxTableElements decodeConstantV1 ⟨proofedWireBytes, 177, 1⟩ =
      .ok (#[], ⟨proofedWireBytes, 181, 1⟩) := by
  apply decodeArray_zeroV1
  change readArrayCountAtV1 (ByteArray.mk proofedSpine.toArray) 177 maxTableElements =
    .ok (0, 181)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

theorem decodeLogicalState_proofed :
    decodeArray maxTableElements decodeStateDeclV1 ⟨proofedWireBytes, 181, 1⟩ =
      .ok (#[], ⟨proofedWireBytes, 185, 1⟩) := by
  apply decodeArray_zeroV1
  change readArrayCountAtV1 (ByteArray.mk proofedSpine.toArray) 181 maxTableElements =
    .ok (0, 185)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

theorem decodeEvents_proofed :
    decodeArray maxTableElements decodeEventDeclV1 ⟨proofedWireBytes, 185, 1⟩ =
      .ok (#[], ⟨proofedWireBytes, 189, 1⟩) := by
  apply decodeArray_zeroV1
  change readArrayCountAtV1 (ByteArray.mk proofedSpine.toArray) 185 maxTableElements =
    .ok (0, 189)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

theorem decodeErrors_proofed :
    decodeArray maxTableElements decodeErrorDeclV1 ⟨proofedWireBytes, 189, 1⟩ =
      .ok (#[], ⟨proofedWireBytes, 193, 1⟩) := by
  apply decodeArray_zeroV1
  change readArrayCountAtV1 (ByteArray.mk proofedSpine.toArray) 189 maxTableElements =
    .ok (0, 193)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

/-! ### Callables: view `alive` + invariant `safe` (shared literal-true block) -/

private theorem encodeU8_one : encodeU8 1 = ByteArray.mk #[1] := rfl

theorem readCallablesCount_proofed :
    readArrayCountAtV1 proofedWireBytes 193 maxTableElements = .ok (2, 197) := by
  change readArrayCountAtV1 (ByteArray.mk proofedSpine.toArray) 193 maxTableElements =
    .ok (2, 197)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

/-! #### View callable `alive` (197→418) -/
theorem expectViewCallable_proofed :
    expectTag "Callable" 9 ⟨proofedWireBytes, 197, 2⟩ =
      .ok ((), ⟨proofedWireBytes, 211, 2⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk proofedSpine.toArray) 197
      (ByteArray.mk [67, 97, 108, 108, 97, 98, 108, 101].toArray) 9 = .ok 211
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [proofedSpine_length]
  rfl

theorem decodeViewKind_proofed :
    decodeCallableKindV1 ⟨proofedWireBytes, 215, 2⟩ =
      .ok (.view, ⟨proofedWireBytes, 234, 2⟩) := by
  refine decodeCallableKindV1_eq_of_bodyV1 ⟨proofedWireBytes, 215, 2⟩ .view
    ⟨proofedWireBytes, 234, 3⟩ (by decide) ?_
  apply decodeCallableKindBodyV1_view
  · apply decodeProofedTagV1 215 232 3
      [67, 97, 108, 108, 97, 98, 108, 101, 46, 86, 105, 101, 119] "Callable.View"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [proofedSpine_length]
      rfl
    · rfl
    · rfl
  · apply decodeProofedZeroFieldsV1
    rfl

theorem readViewName_proofed :
    readSizedBytesAtV1 proofedWireBytes 235 maxStringBytes =
      .ok (ByteArray.mk [97, 108, 105, 118, 101].toArray, 244) := by
  apply readSized_proofed
  apply readSizedSpineBytesV1_eq_of_parts proofedSpine [97, 108, 105, 118, 101]
      235 maxStringBytes 5 239
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [proofedSpine_length]
    rfl

theorem decodeViewName_proofed :
    decodeOption decodeString ⟨proofedWireBytes, 234, 2⟩ =
      .ok (some "alive", ⟨proofedWireBytes, 244, 2⟩) := by
  apply decodeOption_someV1 decodeString ⟨proofedWireBytes, 234, 2⟩
    ⟨proofedWireBytes, 235, 2⟩ ⟨proofedWireBytes, 244, 2⟩ "alive"
  · apply decodeU8_eq_of_readV1
    change readByteAtV1 (ByteArray.mk proofedSpine.toArray) 234 = .ok 1
    rw [readByteAtV1_refinesSpine]
    rfl
  · exact decodeAsciiString_of_read proofedWireBytes 235 244
      [97, 108, 105, 118, 101] "alive" 2 readViewName_proofed (by rfl) (by rfl)

theorem expectViewResult_proofed :
    expectTag "CallableResult" 2 ⟨proofedWireBytes, 248, 3⟩ =
      .ok ((), ⟨proofedWireBytes, 268, 3⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk proofedSpine.toArray) 248
      (ByteArray.mk [67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108,
        116].toArray) 2 = .ok 268
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [proofedSpine_length]
  rfl

theorem decodeViewResult_proofed :
    decodeCallableResultV1 ⟨proofedWireBytes, 248, 2⟩ =
      .ok ({ typeId := 0, visibility := .public_ }, ⟨proofedWireBytes, 295, 2⟩) := by
  refine decodeCallableResultV1_eq_of_bodyV1 ⟨proofedWireBytes, 248, 2⟩
    { typeId := 0, visibility := .public_ } ⟨proofedWireBytes, 295, 3⟩ (by decide) ?_
  apply decodeCallableResultBodyV1_eq_of_fields
  · exact expectViewResult_proofed
  · apply decodeProofedU32V1
    rfl
  · refine decodeVisibilityV1_eq_of_bodyV1 ⟨proofedWireBytes, 272, 3⟩ .public_
      ⟨proofedWireBytes, 295, 4⟩ (by decide) ?_
    apply decodeVisibilityBodyV1_public
    · apply decodeProofedTagV1 272 293 4
        [86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99]
        "Visibility.Public"
      · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
        rw [proofedSpine_length]
        rfl
      · rfl
      · rfl
    · apply decodeProofedZeroFieldsV1
      rfl

theorem expectViewBlock_proofed :
    expectTag "Block" 4 ⟨proofedWireBytes, 303, 3⟩ =
      .ok ((), ⟨proofedWireBytes, 314, 3⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk proofedSpine.toArray) 303
      (ByteArray.mk [66, 108, 111, 99, 107].toArray) 4 = .ok 314
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [proofedSpine_length]
  rfl

theorem expectViewInstruction_proofed :
    expectTag "Instruction" 2 ⟨proofedWireBytes, 326, 4⟩ =
      .ok ((), ⟨proofedWireBytes, 343, 4⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk proofedSpine.toArray) 326
      (ByteArray.mk [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110].toArray) 2 =
      .ok 343
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [proofedSpine_length]
  rfl

theorem decodeViewInstruction_proofed :
    decodeInstructionV1 ⟨proofedWireBytes, 326, 3⟩ =
      .ok (litTrue, ⟨proofedWireBytes, 391, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨proofedWireBytes, 326, 3⟩
    ⟨proofedWireBytes, 343, 4⟩ ⟨proofedWireBytes, 366, 4⟩
    ⟨proofedWireBytes, 391, 4⟩ (some { valueId := 0, typeId := 0 })
    (.literal 0 (ByteArray.mk #[1])) (by decide) expectViewInstruction_proofed
    (by
      apply decodeOption_someV1 decodeValueDefV1 ⟨proofedWireBytes, 343, 4⟩
        ⟨proofedWireBytes, 344, 4⟩ ⟨proofedWireBytes, 366, 4⟩
        { valueId := 0, typeId := 0 }
      · apply decodeU8_eq_of_readV1
        change readByteAtV1 (ByteArray.mk proofedSpine.toArray) 343 = .ok 1
        rw [readByteAtV1_refinesSpine]
        rfl
      · apply decodeValueDefV1_eq_of_fieldsV1 ⟨proofedWireBytes, 344, 4⟩
          ⟨proofedWireBytes, 358, 5⟩ ⟨proofedWireBytes, 362, 5⟩
          ⟨proofedWireBytes, 366, 5⟩ 0 0 (by decide)
        · apply expectTag_eq_of_headerV1
          change expectTaggedHeaderBytesAtV1 (ByteArray.mk proofedSpine.toArray) 344
              (ByteArray.mk [86, 97, 108, 117, 101, 68, 101, 102].toArray) 2 = .ok 358
          rw [expectTaggedHeaderBytesAtV1_refinesSpine]
          unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
            spineRemainingV1 readSpineU16leV1
          rw [proofedSpine_length]
          rfl
        · apply decodeProofedU32V1; rfl
        · apply decodeProofedU32V1; rfl)
    (by
      apply decodeSemanticOpV1_literal ⟨proofedWireBytes, 366, 4⟩
        ⟨proofedWireBytes, 380, 5⟩ ⟨proofedWireBytes, 382, 5⟩
        ⟨proofedWireBytes, 386, 5⟩ ⟨proofedWireBytes, 391, 5⟩ 0 (ByteArray.mk #[1])
        (by decide)
      · apply decodeProofedTagV1 366 380 5
          [79, 112, 46, 76, 105, 116, 101, 114, 97, 108] "Op.Literal"
        · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
          rw [proofedSpine_length]
          rfl
        · rfl
        · rfl
      · apply decodeProofedTwoFieldsV1; rfl
      · apply decodeProofedU32V1; rfl
      · have hread : readSizedBytesAtV1 proofedWireBytes 386 maxCanonicalProgramBytes =
            .ok (ByteArray.mk #[1], 391) := by
          change readSizedBytesAtV1 (ByteArray.mk proofedSpine.toArray) 386
            maxCanonicalProgramBytes = .ok (ByteArray.mk [1].toArray, 391)
          apply readSizedBytesAtV1_eq_of_spine
          apply readSizedSpineBytesV1_eq_of_parts proofedSpine [1] 386
            maxCanonicalProgramBytes 1 390
          · rfl
          · decide
          · decide
          · unfold takeSpineBytesV1 spineRemainingV1
            rw [proofedSpine_length]
            rfl
        simp only [decodeByteArray, hread, Bind.bind, Pure.pure, Except.bind, Except.pure])
  simpa [litTrue, encodeU8_one] using h

theorem decodeViewReturn_proofed :
    decodeTerminatorV1 ⟨proofedWireBytes, 391, 3⟩ =
      .ok (.return_ (some 0), ⟨proofedWireBytes, 413, 3⟩) := by
  apply decodeTerminatorV1_return ⟨proofedWireBytes, 391, 3⟩
    ⟨proofedWireBytes, 406, 4⟩ ⟨proofedWireBytes, 408, 4⟩
    ⟨proofedWireBytes, 413, 4⟩ (some 0) (by decide)
  · apply decodeProofedTagV1 391 406 4
      [84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110] "Term.Return"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [proofedSpine_length]
      rfl
    · rfl
    · rfl
  · apply decodeProofedOneFieldV1; rfl
  · apply decodeOption_someV1 decodeU32le ⟨proofedWireBytes, 408, 4⟩
      ⟨proofedWireBytes, 409, 4⟩ ⟨proofedWireBytes, 413, 4⟩ 0
    · apply decodeU8_eq_of_readV1
      change readByteAtV1 (ByteArray.mk proofedSpine.toArray) 408 = .ok 1
      rw [readByteAtV1_refinesSpine]
      rfl
    · apply decodeProofedU32V1; rfl

theorem decodeViewBlock_proofed :
    decodeBlockV1 ⟨proofedWireBytes, 303, 2⟩ =
      .ok (singleBlock, ⟨proofedWireBytes, 413, 2⟩) := by
  apply decodeBlockV1_oneInstructionV1 ⟨proofedWireBytes, 303, 2⟩
    ⟨proofedWireBytes, 314, 3⟩ ⟨proofedWireBytes, 318, 3⟩
    ⟨proofedWireBytes, 391, 3⟩ ⟨proofedWireBytes, 413, 3⟩
    322 326 0 litTrue (.return_ (some 0)) (by decide)
  · exact expectViewBlock_proofed
  · apply decodeProofedU32V1; rfl
  · change readArrayCountAtV1 (ByteArray.mk proofedSpine.toArray) 318
      maxArrayElements = .ok (0, 322)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · change readArrayCountAtV1 (ByteArray.mk proofedSpine.toArray) 322
      maxArrayElements = .ok (1, 326)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeViewInstruction_proofed
  · exact decodeViewReturn_proofed

theorem decodeViewSteps_proofed :
    decodeOption decodeU64le ⟨proofedWireBytes, 417, 2⟩ =
      .ok (none, ⟨proofedWireBytes, 418, 2⟩) := by
  apply decodeOption_noneV1
  apply decodeU8_eq_of_readV1
  change readByteAtV1 (ByteArray.mk proofedSpine.toArray) 417 = .ok 0
  rw [readByteAtV1_refinesSpine]
  rfl

theorem decodeView_proofed :
    decodeCallableV1 ⟨proofedWireBytes, 197, 1⟩ =
      .ok (viewC, ⟨proofedWireBytes, 418, 1⟩) := by
  have h := decodeCallableV1_singleBlockV1
    ⟨proofedWireBytes, 197, 1⟩ ⟨proofedWireBytes, 211, 2⟩
    ⟨proofedWireBytes, 215, 2⟩ ⟨proofedWireBytes, 234, 2⟩
    ⟨proofedWireBytes, 244, 2⟩ ⟨proofedWireBytes, 295, 2⟩
    ⟨proofedWireBytes, 299, 2⟩ ⟨proofedWireBytes, 413, 2⟩
    ⟨proofedWireBytes, 418, 2⟩ 248 303 417 0 0 .view (some "alive")
    { typeId := 0, visibility := .public_ } singleBlock none (by decide)
    expectViewCallable_proofed (decodeProofedU32V1 211 215 2 0 (by rfl))
    decodeViewKind_proofed decodeViewName_proofed (by
      change readArrayCountAtV1 (ByteArray.mk proofedSpine.toArray) 244
        maxArrayElements = .ok (0, 248)
      rw [readArrayCountAtV1_refinesSpine]; rfl)
    decodeViewResult_proofed (decodeProofedU32V1 295 299 2 0 (by rfl))
    (by
      change readArrayCountAtV1 (ByteArray.mk proofedSpine.toArray) 299
        maxArrayElements = .ok (1, 303)
      rw [readArrayCountAtV1_refinesSpine]; rfl)
    decodeViewBlock_proofed (by
      change readArrayCountAtV1 (ByteArray.mk proofedSpine.toArray) 413
        maxArrayElements = .ok (0, 417)
      rw [readArrayCountAtV1_refinesSpine]; rfl)
    decodeViewSteps_proofed
  simpa [viewC] using h

/-! #### Invariant callable `safe` (418→651) -/

theorem expectInvCallable_proofed :
    expectTag "Callable" 9 ⟨proofedWireBytes, 418, 2⟩ =
      .ok ((), ⟨proofedWireBytes, 432, 2⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk proofedSpine.toArray) 418
      (ByteArray.mk [67, 97, 108, 108, 97, 98, 108, 101].toArray) 9 = .ok 432
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [proofedSpine_length]
  rfl

theorem decodeInvKind_proofed :
    decodeCallableKindV1 ⟨proofedWireBytes, 436, 2⟩ =
      .ok (.invariant, ⟨proofedWireBytes, 460, 2⟩) := by
  refine decodeCallableKindV1_eq_of_bodyV1 ⟨proofedWireBytes, 436, 2⟩ .invariant
    ⟨proofedWireBytes, 460, 3⟩ (by decide) ?_
  apply decodeCallableKindBodyV1_invariant
  · apply decodeProofedTagV1 436 458 3
      [67, 97, 108, 108, 97, 98, 108, 101, 46, 73, 110, 118, 97, 114, 105, 97, 110, 116]
      "Callable.Invariant"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [proofedSpine_length]
      rfl
    · rfl
    · rfl
  · apply decodeProofedZeroFieldsV1; rfl

theorem readInvName_proofed :
    readSizedBytesAtV1 proofedWireBytes 461 maxStringBytes =
      .ok (ByteArray.mk [115, 97, 102, 101].toArray, 469) := by
  apply readSized_proofed
  apply readSizedSpineBytesV1_eq_of_parts proofedSpine [115, 97, 102, 101]
      461 maxStringBytes 4 465
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [proofedSpine_length]
    rfl

theorem decodeInvName_proofed :
    decodeOption decodeString ⟨proofedWireBytes, 460, 2⟩ =
      .ok (some "safe", ⟨proofedWireBytes, 469, 2⟩) := by
  apply decodeOption_someV1 decodeString ⟨proofedWireBytes, 460, 2⟩
    ⟨proofedWireBytes, 461, 2⟩ ⟨proofedWireBytes, 469, 2⟩ "safe"
  · apply decodeU8_eq_of_readV1
    change readByteAtV1 (ByteArray.mk proofedSpine.toArray) 460 = .ok 1
    rw [readByteAtV1_refinesSpine]; rfl
  · exact decodeAsciiString_of_read proofedWireBytes 461 469
      [115, 97, 102, 101] "safe" 2 readInvName_proofed (by rfl) (by rfl)

theorem expectInvResult_proofed :
    expectTag "CallableResult" 2 ⟨proofedWireBytes, 473, 3⟩ =
      .ok ((), ⟨proofedWireBytes, 493, 3⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk proofedSpine.toArray) 473
      (ByteArray.mk [67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108,
        116].toArray) 2 = .ok 493
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [proofedSpine_length]
  rfl

theorem decodeInvResult_proofed :
    decodeCallableResultV1 ⟨proofedWireBytes, 473, 2⟩ =
      .ok ({ typeId := 0, visibility := .public_ }, ⟨proofedWireBytes, 520, 2⟩) := by
  refine decodeCallableResultV1_eq_of_bodyV1 ⟨proofedWireBytes, 473, 2⟩
    { typeId := 0, visibility := .public_ } ⟨proofedWireBytes, 520, 3⟩ (by decide) ?_
  apply decodeCallableResultBodyV1_eq_of_fields
  · exact expectInvResult_proofed
  · apply decodeProofedU32V1; rfl
  · refine decodeVisibilityV1_eq_of_bodyV1 ⟨proofedWireBytes, 497, 3⟩ .public_
      ⟨proofedWireBytes, 520, 4⟩ (by decide) ?_
    apply decodeVisibilityBodyV1_public
    · apply decodeProofedTagV1 497 518 4
        [86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99]
        "Visibility.Public"
      · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
        rw [proofedSpine_length]; rfl
      · rfl
      · rfl
    · apply decodeProofedZeroFieldsV1; rfl

theorem expectInvBlock_proofed :
    expectTag "Block" 4 ⟨proofedWireBytes, 528, 3⟩ =
      .ok ((), ⟨proofedWireBytes, 539, 3⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk proofedSpine.toArray) 528
      (ByteArray.mk [66, 108, 111, 99, 107].toArray) 4 = .ok 539
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [proofedSpine_length]
  rfl

theorem expectInvInstruction_proofed :
    expectTag "Instruction" 2 ⟨proofedWireBytes, 551, 4⟩ =
      .ok ((), ⟨proofedWireBytes, 568, 4⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk proofedSpine.toArray) 551
      (ByteArray.mk [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110].toArray) 2 =
      .ok 568
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [proofedSpine_length]
  rfl

theorem decodeInvInstruction_proofed :
    decodeInstructionV1 ⟨proofedWireBytes, 551, 3⟩ =
      .ok (litTrue, ⟨proofedWireBytes, 616, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨proofedWireBytes, 551, 3⟩
    ⟨proofedWireBytes, 568, 4⟩ ⟨proofedWireBytes, 591, 4⟩
    ⟨proofedWireBytes, 616, 4⟩ (some { valueId := 0, typeId := 0 })
    (.literal 0 (ByteArray.mk #[1])) (by decide) expectInvInstruction_proofed
    (by
      apply decodeOption_someV1 decodeValueDefV1 ⟨proofedWireBytes, 568, 4⟩
        ⟨proofedWireBytes, 569, 4⟩ ⟨proofedWireBytes, 591, 4⟩
        { valueId := 0, typeId := 0 }
      · apply decodeU8_eq_of_readV1
        change readByteAtV1 (ByteArray.mk proofedSpine.toArray) 568 = .ok 1
        rw [readByteAtV1_refinesSpine]; rfl
      · apply decodeValueDefV1_eq_of_fieldsV1 ⟨proofedWireBytes, 569, 4⟩
          ⟨proofedWireBytes, 583, 5⟩ ⟨proofedWireBytes, 587, 5⟩
          ⟨proofedWireBytes, 591, 5⟩ 0 0 (by decide)
        · apply expectTag_eq_of_headerV1
          change expectTaggedHeaderBytesAtV1 (ByteArray.mk proofedSpine.toArray) 569
              (ByteArray.mk [86, 97, 108, 117, 101, 68, 101, 102].toArray) 2 = .ok 583
          rw [expectTaggedHeaderBytesAtV1_refinesSpine]
          unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
            spineRemainingV1 readSpineU16leV1
          rw [proofedSpine_length]; rfl
        · apply decodeProofedU32V1; rfl
        · apply decodeProofedU32V1; rfl)
    (by
      apply decodeSemanticOpV1_literal ⟨proofedWireBytes, 591, 4⟩
        ⟨proofedWireBytes, 605, 5⟩ ⟨proofedWireBytes, 607, 5⟩
        ⟨proofedWireBytes, 611, 5⟩ ⟨proofedWireBytes, 616, 5⟩ 0 (ByteArray.mk #[1])
        (by decide)
      · apply decodeProofedTagV1 591 605 5
          [79, 112, 46, 76, 105, 116, 101, 114, 97, 108] "Op.Literal"
        · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
          rw [proofedSpine_length]; rfl
        · rfl
        · rfl
      · apply decodeProofedTwoFieldsV1; rfl
      · apply decodeProofedU32V1; rfl
      · have hread : readSizedBytesAtV1 proofedWireBytes 611 maxCanonicalProgramBytes =
            .ok (ByteArray.mk #[1], 616) := by
          change readSizedBytesAtV1 (ByteArray.mk proofedSpine.toArray) 611
            maxCanonicalProgramBytes = .ok (ByteArray.mk [1].toArray, 616)
          apply readSizedBytesAtV1_eq_of_spine
          apply readSizedSpineBytesV1_eq_of_parts proofedSpine [1] 611
            maxCanonicalProgramBytes 1 615
          · rfl
          · decide
          · decide
          · unfold takeSpineBytesV1 spineRemainingV1
            rw [proofedSpine_length]; rfl
        simp only [decodeByteArray, hread, Bind.bind, Pure.pure, Except.bind, Except.pure])
  simpa [litTrue, encodeU8_one] using h

theorem decodeInvReturn_proofed :
    decodeTerminatorV1 ⟨proofedWireBytes, 616, 3⟩ =
      .ok (.return_ (some 0), ⟨proofedWireBytes, 638, 3⟩) := by
  apply decodeTerminatorV1_return ⟨proofedWireBytes, 616, 3⟩
    ⟨proofedWireBytes, 631, 4⟩ ⟨proofedWireBytes, 633, 4⟩
    ⟨proofedWireBytes, 638, 4⟩ (some 0) (by decide)
  · apply decodeProofedTagV1 616 631 4
      [84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110] "Term.Return"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [proofedSpine_length]; rfl
    · rfl
    · rfl
  · apply decodeProofedOneFieldV1; rfl
  · apply decodeOption_someV1 decodeU32le ⟨proofedWireBytes, 633, 4⟩
      ⟨proofedWireBytes, 634, 4⟩ ⟨proofedWireBytes, 638, 4⟩ 0
    · apply decodeU8_eq_of_readV1
      change readByteAtV1 (ByteArray.mk proofedSpine.toArray) 633 = .ok 1
      rw [readByteAtV1_refinesSpine]; rfl
    · apply decodeProofedU32V1; rfl

theorem decodeInvBlock_proofed :
    decodeBlockV1 ⟨proofedWireBytes, 528, 2⟩ =
      .ok (singleBlock, ⟨proofedWireBytes, 638, 2⟩) := by
  apply decodeBlockV1_oneInstructionV1 ⟨proofedWireBytes, 528, 2⟩
    ⟨proofedWireBytes, 539, 3⟩ ⟨proofedWireBytes, 543, 3⟩
    ⟨proofedWireBytes, 616, 3⟩ ⟨proofedWireBytes, 638, 3⟩
    547 551 0 litTrue (.return_ (some 0)) (by decide)
  · exact expectInvBlock_proofed
  · apply decodeProofedU32V1; rfl
  · change readArrayCountAtV1 (ByteArray.mk proofedSpine.toArray) 543
      maxArrayElements = .ok (0, 547)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · change readArrayCountAtV1 (ByteArray.mk proofedSpine.toArray) 547
      maxArrayElements = .ok (1, 551)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeInvInstruction_proofed
  · exact decodeInvReturn_proofed

theorem decodeInvSteps_proofed :
    decodeOption decodeU64le ⟨proofedWireBytes, 642, 2⟩ =
      .ok (some 3, ⟨proofedWireBytes, 651, 2⟩) := by
  apply decodeOption_someV1 decodeU64le ⟨proofedWireBytes, 642, 2⟩
    ⟨proofedWireBytes, 643, 2⟩ ⟨proofedWireBytes, 651, 2⟩ 3
  · apply decodeU8_eq_of_readV1
    change readByteAtV1 (ByteArray.mk proofedSpine.toArray) 642 = .ok 1
    rw [readByteAtV1_refinesSpine]; rfl
  · apply decodeProofedU64V1; rfl

theorem decodeInv_proofed :
    decodeCallableV1 ⟨proofedWireBytes, 418, 1⟩ =
      .ok (invC, ⟨proofedWireBytes, 651, 1⟩) := by
  have h := decodeCallableV1_singleBlockV1
    ⟨proofedWireBytes, 418, 1⟩ ⟨proofedWireBytes, 432, 2⟩
    ⟨proofedWireBytes, 436, 2⟩ ⟨proofedWireBytes, 460, 2⟩
    ⟨proofedWireBytes, 469, 2⟩ ⟨proofedWireBytes, 520, 2⟩
    ⟨proofedWireBytes, 524, 2⟩ ⟨proofedWireBytes, 638, 2⟩
    ⟨proofedWireBytes, 651, 2⟩ 473 528 642 1 0 .invariant (some "safe")
    { typeId := 0, visibility := .public_ } singleBlock (some 3) (by decide)
    expectInvCallable_proofed (decodeProofedU32V1 432 436 2 1 (by rfl))
    decodeInvKind_proofed decodeInvName_proofed (by
      change readArrayCountAtV1 (ByteArray.mk proofedSpine.toArray) 469
        maxArrayElements = .ok (0, 473)
      rw [readArrayCountAtV1_refinesSpine]; rfl)
    decodeInvResult_proofed (decodeProofedU32V1 520 524 2 0 (by rfl))
    (by
      change readArrayCountAtV1 (ByteArray.mk proofedSpine.toArray) 524
        maxArrayElements = .ok (1, 528)
      rw [readArrayCountAtV1_refinesSpine]; rfl)
    decodeInvBlock_proofed (by
      change readArrayCountAtV1 (ByteArray.mk proofedSpine.toArray) 638
        maxArrayElements = .ok (0, 642)
      rw [readArrayCountAtV1_refinesSpine]; rfl)
    decodeInvSteps_proofed
  simpa [invC] using h

theorem decodeCallables_proofed :
    decodeArray maxTableElements decodeCallableV1 ⟨proofedWireBytes, 193, 1⟩ =
      .ok (#[viewC, invC], ⟨proofedWireBytes, 651, 1⟩) := by
  have h := decodeArray_twoV1 maxTableElements decodeCallableV1
    ⟨proofedWireBytes, 193, 1⟩ 197 viewC invC
    ⟨proofedWireBytes, 418, 1⟩ ⟨proofedWireBytes, 651, 1⟩
    readCallablesCount_proofed decodeView_proofed decodeInv_proofed
  simpa using h

/-! ### Invariants (one row) -/

theorem readInvariantsCount_proofed :
    readArrayCountAtV1 proofedWireBytes 651 maxTableElements = .ok (1, 655) := by
  change readArrayCountAtV1 (ByteArray.mk proofedSpine.toArray) 651 maxTableElements =
    .ok (1, 655)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

theorem expectInvariantDecl_proofed :
    expectTag "InvariantDecl" 3 ⟨proofedWireBytes, 655, 2⟩ =
      .ok ((), ⟨proofedWireBytes, 674, 2⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk proofedSpine.toArray) 655
      (ByteArray.mk [73, 110, 118, 97, 114, 105, 97, 110, 116, 68, 101, 99, 108].toArray)
      3 = .ok 674
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [proofedSpine_length]
  rfl

theorem readInvDeclName_proofed :
    readSizedBytesAtV1 proofedWireBytes 678 maxStringBytes =
      .ok (ByteArray.mk [115, 97, 102, 101].toArray, 686) := by
  apply readSized_proofed
  apply readSizedSpineBytesV1_eq_of_parts proofedSpine [115, 97, 102, 101]
      678 maxStringBytes 4 682
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [proofedSpine_length]; rfl

theorem decodeInvariantDecl_proofed :
    decodeInvariantDeclV1 ⟨proofedWireBytes, 655, 1⟩ =
      .ok ({ id := 0, name := "safe", callableId := 1 }, ⟨proofedWireBytes, 690, 1⟩) := by
  refine decodeInvariantDeclV1_eq_of_bodyV1 ⟨proofedWireBytes, 655, 1⟩
    { id := 0, name := "safe", callableId := 1 }
    ⟨proofedWireBytes, 690, 2⟩ (by decide) ?_
  apply decodeInvariantDeclBodyV1_eq_of_fields
  · exact expectInvariantDecl_proofed
  · apply decodeProofedU32V1; rfl
  · exact decodeAsciiString_of_read proofedWireBytes 678 686
      [115, 97, 102, 101] "safe" 2 readInvDeclName_proofed (by rfl) (by rfl)
  · apply decodeProofedU32V1; rfl

theorem decodeInvariants_proofed :
    decodeArray maxTableElements decodeInvariantDeclV1 ⟨proofedWireBytes, 651, 1⟩ =
      .ok (#[{ id := 0, name := "safe", callableId := 1 }],
        ⟨proofedWireBytes, 690, 1⟩) := by
  exact decodeArray_oneV1 maxTableElements decodeInvariantDeclV1
    ⟨proofedWireBytes, 651, 1⟩ 655
    { id := 0, name := "safe", callableId := 1 }
    ⟨proofedWireBytes, 690, 1⟩
    readInvariantsCount_proofed decodeInvariantDecl_proofed

/-! ### ProgramRequirements (value.bool singleton) 690→802 -/

/-- Exact wire requirement row for `value.bool` (transparent S2 digest spine). -/
def wireBoolReq : RequirementRequestV1 := {
  id := "value.bool"
  version := s2RequirementVersionV1
  digest := {
    algorithm := .sha256
    bytes := ProofForgeV2.Semantic.RequirementsV1.s2ValueBoolDigestBytesV1
  }
  predicates := #[]
}

theorem s2Version_eq_catalogCore :
    s2RequirementVersionV1 = s2CatalogSemVerCoreV1 := rfl

theorem isS2_value_bool :
    ProofForgeV2.Semantic.RequirementsV1.isS2CatalogIdV1 "value.bool" = true := by
  unfold ProofForgeV2.Semantic.RequirementsV1.isS2CatalogIdV1
  change s2CatalogIdsWireOrderListV1.contains "value.bool" = true
  unfold s2CatalogIdsWireOrderListV1
  simp only [s2EffectAsyncWorkflowIdV1, s2EffectEventIdV1, s2EffectSyncCallIdV1,
    s2FailureAtomicRollbackIdV1, s2StatePersistentIdV1, s2ValueBoolIdV1,
    s2ValueCheckedArithmeticIdV1]
  decide

theorem dig_value_bool :
    ProofForgeV2.Semantic.RequirementsV1.engineeringRequirementDigestV1 "value.bool" =
      .ok {
        algorithm := .sha256
        bytes := ProofForgeV2.Semantic.RequirementsV1.s2ValueBoolDigestBytesV1
      } := by
  unfold ProofForgeV2.Semantic.RequirementsV1.engineeringRequirementDigestV1
  simp only [s2EffectAsyncWorkflowIdV1, s2EffectEventIdV1, s2EffectSyncCallIdV1,
    s2FailureAtomicRollbackIdV1, s2StatePersistentIdV1, s2ValueBoolIdV1,
    s2ValueCheckedArithmeticIdV1]
  rfl

theorem mkS2_value_bool :
    ProofForgeV2.Semantic.RequirementsV1.mkS2RequirementRequestV1 "value.bool" =
      .ok wireBoolReq := by
  unfold ProofForgeV2.Semantic.RequirementsV1.mkS2RequirementRequestV1
  simp only [isS2_value_bool, dig_value_bool, wireBoolReq, ↓reduceIte,
    Bind.bind, Pure.pure, Except.bind, Except.pure]

theorem boolReq_eq_wire : boolReq = wireBoolReq := by
  -- Both sides use the transparent `s2ValueBoolDigestBytesV1` spine.
  unfold boolReq wireBoolReq
  rfl

theorem expectProgramRequirements_proofed :
    expectTag "ProgramRequirements" 1 ⟨proofedWireBytes, 690, 2⟩ =
      .ok ((), ⟨proofedWireBytes, 715, 2⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk proofedSpine.toArray) 690
      (ByteArray.mk [80, 114, 111, 103, 114, 97, 109, 82, 101, 113, 117, 105, 114, 101,
        109, 101, 110, 116, 115].toArray) 1 = .ok 715
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [proofedSpine_length]
  rfl

theorem readRequirementsCount_proofed :
    readArrayCountAtV1 proofedWireBytes 715 maxArrayElements = .ok (1, 719) := by
  change readArrayCountAtV1 (ByteArray.mk proofedSpine.toArray) 715 maxArrayElements =
    .ok (1, 719)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

theorem expectRequirementRequest_proofed :
    expectTag "RequirementRequest" 4 ⟨proofedWireBytes, 719, 3⟩ =
      .ok ((), ⟨proofedWireBytes, 743, 3⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk proofedSpine.toArray) 719
      (ByteArray.mk [82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 82, 101, 113,
        117, 101, 115, 116].toArray) 4 = .ok 743
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [proofedSpine_length]
  rfl

theorem readReqId_proofed :
    readSizedBytesAtV1 proofedWireBytes 743 maxStringBytes =
      .ok (ByteArray.mk [118, 97, 108, 117, 101, 46, 98, 111, 111, 108].toArray, 757) := by
  apply readSized_proofed
  apply readSizedSpineBytesV1_eq_of_parts proofedSpine
      [118, 97, 108, 117, 101, 46, 98, 111, 111, 108] 743 maxStringBytes 10 747
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [proofedSpine_length]
    rfl

theorem decodeReqId_proofed :
    decodeString ⟨proofedWireBytes, 743, 3⟩ =
      .ok ("value.bool", ⟨proofedWireBytes, 757, 3⟩) :=
  decodeAsciiString_of_read proofedWireBytes 743 757
    [118, 97, 108, 117, 101, 46, 98, 111, 111, 108] "value.bool" 3
    readReqId_proofed (by rfl) (by rfl)

theorem readReqVersion_proofed :
    readSizedBytesAtV1 proofedWireBytes 757 maxStringBytes =
      .ok (ByteArray.mk [49, 46, 48, 46, 48].toArray, 766) := by
  apply readSized_proofed
  apply readSizedSpineBytesV1_eq_of_parts proofedSpine
      [49, 46, 48, 46, 48] 757 maxStringBytes 5 761
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [proofedSpine_length]
    rfl

theorem decodeReqVersionString_proofed :
    decodeString ⟨proofedWireBytes, 757, 3⟩ =
      .ok ("1.0.0", ⟨proofedWireBytes, 766, 3⟩) :=
  decodeAsciiString_of_read proofedWireBytes 757 766
    [49, 46, 48, 46, 48] "1.0.0" 3
    readReqVersion_proofed (by rfl) (by rfl)

theorem decodeReqVersion_proofed :
    decodeSemVer ⟨proofedWireBytes, 757, 3⟩ =
      .ok (s2RequirementVersionV1, ⟨proofedWireBytes, 766, 3⟩) := by
  apply decodeSemVer_eq_of_stringV1 _ _ _ s2RequirementVersionV1
    decodeReqVersionString_proofed
  · -- parseSemVer "1.0.0" = .ok s2CatalogSemVerCoreV1 = .ok s2RequirementVersionV1
    have h := parseSemVer_1_0_0
    rw [s2Version_eq_catalogCore.symm] at h
    exact h

private def valueBoolDigestSpine : TransparentByteSpineV1 :=
  [237, 52, 225, 6, 29, 14, 102, 99, 155, 106, 118, 55, 29, 216, 166, 193,
    204, 215, 46, 122, 154, 20, 116, 84, 218, 122, 83, 193, 167, 71, 84, 124]

theorem valueBoolDigestSpine_length : valueBoolDigestSpine.length = 32 := by rfl

private abbrev valueBoolDigestBytes : ByteArray :=
  ProofForgeV2.Semantic.RequirementsV1.s2ValueBoolDigestBytesV1

theorem valueBoolDigestSpine_eq_bytes :
    ByteArray.mk valueBoolDigestSpine.toArray = valueBoolDigestBytes := by
  unfold valueBoolDigestBytes
    ProofForgeV2.Semantic.RequirementsV1.s2ValueBoolDigestBytesV1
    valueBoolDigestSpine
  rfl

theorem takeDigest_proofed :
    takeBytesAtV1 proofedWireBytes 766 32 = .ok valueBoolDigestBytes := by
  have hspine : takeSpineBytesV1 proofedSpine 766 32 = .ok valueBoolDigestSpine := by
    unfold takeSpineBytesV1 spineRemainingV1 valueBoolDigestSpine
    rw [proofedSpine_length]
    rfl
  have htake :
      takeBytesAtV1 (ByteArray.mk proofedSpine.toArray) 766 valueBoolDigestSpine.length =
        .ok (ByteArray.mk valueBoolDigestSpine.toArray) :=
    takeBytesAtV1_eq_of_spine proofedSpine valueBoolDigestSpine 766 hspine
  rw [valueBoolDigestSpine_length, valueBoolDigestSpine_eq_bytes] at htake
  exact htake

theorem valueBoolDigestBytes_size :
    valueBoolDigestBytes.size = 32 := by
  rw [← valueBoolDigestSpine_eq_bytes]
  -- size(ByteArray.mk xs.toArray) = xs.length, and spine length is 32.
  have h : (ByteArray.mk valueBoolDigestSpine.toArray).size = valueBoolDigestSpine.length := by
    rfl
  rw [h, valueBoolDigestSpine_length]

theorem validateDigest_valueBool :
    validateDigest { algorithm := .sha256, bytes := valueBoolDigestBytes } = .ok () := by
  simp only [validateDigest, valueBoolDigestBytes_size, ↓reduceIte, Pure.pure, Except.pure]

theorem decodeDigest_proofed :
    decodeDigest ⟨proofedWireBytes, 766, 3⟩ =
      .ok ({ algorithm := .sha256, bytes := valueBoolDigestBytes },
        ⟨proofedWireBytes, 798, 3⟩) :=
  decodeDigest_eq_of_takeV1 ⟨proofedWireBytes, 766, 3⟩ valueBoolDigestBytes
    takeDigest_proofed validateDigest_valueBool

theorem decodeReqPredicates_proofed :
    decodeArray maxArrayElements decodeRequirementPredicateV1
        ⟨proofedWireBytes, 798, 3⟩ =
      .ok (#[], ⟨proofedWireBytes, 802, 3⟩) := by
  apply decodeArray_zeroV1
  change readArrayCountAtV1 (ByteArray.mk proofedSpine.toArray) 798 maxArrayElements =
    .ok (0, 802)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

theorem decodeRequirementRequest_proofed :
    decodeRequirementRequestV1 ⟨proofedWireBytes, 719, 2⟩ =
      .ok (wireBoolReq, ⟨proofedWireBytes, 802, 2⟩) := by
  unfold decodeRequirementRequestV1 withTaggedNesting
  have hdepth : (2 : Nat) < maxNesting := by decide
  -- Body runs at `nesting + 1` (= 3); restate field successes at that cursor.
  have htag :
      expectTag "RequirementRequest" 4 ⟨proofedWireBytes, 719, 2 + 1⟩ =
        .ok ((), ⟨proofedWireBytes, 743, 2 + 1⟩) := by
    simpa using expectRequirementRequest_proofed
  have hid :
      decodeString ⟨proofedWireBytes, 743, 2 + 1⟩ =
        .ok ("value.bool", ⟨proofedWireBytes, 757, 2 + 1⟩) := by
    simpa using decodeReqId_proofed
  have hver :
      decodeSemVer ⟨proofedWireBytes, 757, 2 + 1⟩ =
        .ok (s2RequirementVersionV1, ⟨proofedWireBytes, 766, 2 + 1⟩) := by
    simpa using decodeReqVersion_proofed
  have hdig :
      decodeDigest ⟨proofedWireBytes, 766, 2 + 1⟩ =
        .ok ({ algorithm := .sha256, bytes := valueBoolDigestBytes },
          ⟨proofedWireBytes, 798, 2 + 1⟩) := by
    simpa using decodeDigest_proofed
  have hpred :
      decodeArray maxArrayElements decodeRequirementPredicateV1
          ⟨proofedWireBytes, 798, 2 + 1⟩ =
        .ok (#[], ⟨proofedWireBytes, 802, 2 + 1⟩) := by
    simpa using decodeReqPredicates_proofed
  simp only [hdepth, ↓reduceIte, Bind.bind, Pure.pure, Except.bind, Except.pure,
    htag, hid, hver, hdig, hpred, wireBoolReq]

theorem decodeRequirements_proofed :
    decodeProgramRequirementsV1 ⟨proofedWireBytes, 690, 1⟩ =
      .ok ({ items := #[wireBoolReq] }, ⟨proofedWireBytes, 802, 1⟩) := by
  refine decodeProgramRequirementsV1_eq_of_bodyV1 ⟨proofedWireBytes, 690, 1⟩
    { items := #[wireBoolReq] } ⟨proofedWireBytes, 802, 2⟩ (by decide) ?_
  apply decodeProgramRequirementsBodyV1_eq_of_fields
  · exact expectProgramRequirements_proofed
  · exact decodeArray_oneV1 maxArrayElements decodeRequirementRequestV1
      ⟨proofedWireBytes, 715, 2⟩ 719 wireBoolReq ⟨proofedWireBytes, 802, 2⟩
      readRequirementsCount_proofed decodeRequirementRequest_proofed

/-! ### Full transport framing → `proofedData` -/

theorem decodeTaggedData_proofed :
    decodeSemanticProgramDataTaggedV1 ⟨proofedWireBytes, 15, 0⟩ =
      .ok (proofedData, ⟨proofedWireBytes, 802, 0⟩) := by
  have h := decodeSemanticProgramDataTaggedV1_eq_of_fields
    ⟨proofedWireBytes, 15, 0⟩ ⟨proofedWireBytes, 41, 1⟩
    ⟨proofedWireBytes, 103, 1⟩ ⟨proofedWireBytes, 177, 1⟩
    ⟨proofedWireBytes, 181, 1⟩ ⟨proofedWireBytes, 185, 1⟩
    ⟨proofedWireBytes, 189, 1⟩ ⟨proofedWireBytes, 193, 1⟩
    ⟨proofedWireBytes, 651, 1⟩ ⟨proofedWireBytes, 690, 1⟩
    ⟨proofedWireBytes, 802, 1⟩ qn #[boolT, u64T] #[] #[] #[] #[]
    #[viewC, invC] #[{ id := 0, name := "safe", callableId := 1 }]
    { items := #[wireBoolReq] } (by decide)
    expectRootTag_proofed decodeQualifiedName_proofed decodeTypes_proofed
    decodeConstants_proofed decodeLogicalState_proofed decodeEvents_proofed
    decodeErrors_proofed decodeCallables_proofed decodeInvariants_proofed
    decodeRequirements_proofed
  -- Align requirements items with `proofedData` (boolReq = wireBoolReq).
  have hreq : ({ items := #[wireBoolReq] } : ProgramRequirementsV1) =
      proofedData.requirements := by
    simp only [proofedData, boolReq_eq_wire]
  -- Align full data record.
  have hdata :
      ({
        qualifiedName := qn
        types := #[boolT, u64T]
        constants := #[]
        logicalState := #[]
        events := #[]
        errors := #[]
        callables := #[viewC, invC]
        invariants := #[{ id := 0, name := "safe", callableId := 1 }]
        requirements := { items := #[wireBoolReq] }
      } : SemanticProgramDataV1) = proofedData := by
    simp only [proofedData, boolReq_eq_wire]
  simpa [hdata] using h

theorem finish_proofed :
    finish ⟨proofedWireBytes, 802, 0⟩ = .ok () := by
  apply finish_eq_ok_of_offset_sizeV1
  change 802 = proofedSpine.length
  exact proofedSpine_length.symm

/-- Decode-only kernel certificate: elaborator `proofedBytes` transport-decodes
    to exact `proofedData` (no structure gate). -/
theorem decodeData_proofed :
    decodeSemanticProgramDataV1 proofedBytes = .ok proofedData := by
  have hwire : proofedBytes = proofedWireBytes := proofedBytes_eq_spine
  rw [hwire]
  apply decodeSemanticProgramDataV1_eq_of_framing proofedWireBytes
    ⟨proofedWireBytes, 15, 0⟩ ⟨proofedWireBytes, 802, 0⟩ proofedData
  · change proofedSpine.length ≤ maxCanonicalProgramBytes
    rw [proofedSpine_length]
    decide
  · exact consumeMagic_proofed
  · exact decodeTaggedData_proofed
  · exact finish_proofed

/-- Same statement with elaborator name explicit. -/
theorem decodeData_subjectBytesV1 :
    decodeSemanticProgramDataV1 Proofed.Proof.subjectBytesV1 = .ok proofedData := by
  simpa [proofedBytes] using decodeData_proofed

end Tests.Semantic.ProofedDecodeCertV1
