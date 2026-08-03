/-
  Tests.Semantic.ProofedEncodeCertV1 — encode-only kernel certificate for the
  Proofed simple carrier (`proofedData` / elaborator `subjectBytesV1`).

  Goal (structure lane supplies `hstructure` as a free hypothesis):
    encodeSemanticProgramDataV1 proofedData = .ok proofedBytes
  where `proofedBytes = Proofed.Proof.subjectBytesV1` (sole product identity).

  Bottom-up: QN, Bool/UInt64 types, empty tables, shared literal callables,
  InvariantDecl, value.bool requirement, root framing, magic append.
  No structure re-proof, no axiom/sorry/native_decide/ofReduceBool.
-/
import Tests.Semantic.ProofedCertV1
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Core.Common

set_option maxHeartbeats 200000000
set_option maxRecDepth 800000

namespace Tests.Semantic.ProofedEncodeCertV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.WireV1
open Tests.Semantic.ProofedCertV1
open Tests.Language.InlineProofAuthoringV1

/-! ### Transparent encode spines (definitionally equal to subjectBytesV1) -/

def proofedMagicSpine : TransparentByteSpineV1 :=
  [112, 102, 46, 115, 101, 109, 97, 110, 116, 105, 99, 46, 118, 49, 0]

def proofedRootHeaderSpine : TransparentByteSpineV1 :=
  [20, 0, 0, 0, 83, 101, 109, 97, 110, 116, 105, 99, 80, 114, 111, 103,
    114, 97, 109, 46, 68, 97, 116, 97, 9, 0]

def proofedQnSpine : TransparentByteSpineV1 := [
  4, 0, 0, 0, 5, 0, 0, 0, 84, 101, 115, 116, 115, 8, 0, 0, 0, 76, 97, 110, 103, 117, 97,
  103, 101, 22, 0, 0, 0, 73, 110, 108, 105, 110, 101, 80, 114, 111, 111,
  102, 65, 117, 116, 104, 111, 114, 105, 110, 103, 86, 49, 7, 0, 0, 0,
  80, 114, 111, 111, 102, 101, 100
]

def proofedTypesSpine : TransparentByteSpineV1 := [
  2, 0, 0, 0, 8, 0, 0, 0, 84, 121, 112, 101, 68, 101, 99, 108, 3, 0, 0, 0, 0, 0, 0,
  9, 0, 0, 0, 84, 121, 112, 101, 46, 66, 111, 111, 108, 0, 0, 8, 0, 0, 0, 84, 121, 112,
  101, 68, 101, 99, 108, 3, 0, 1, 0, 0, 0, 0, 9, 0, 0, 0, 84, 121, 112, 101, 46, 85,
  73, 110, 116, 1, 0, 64, 0
]

def proofedEmptySpine : TransparentByteSpineV1 := [0, 0, 0, 0]

def proofedViewSpine : TransparentByteSpineV1 := [
  8, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 9, 0, 0, 0, 0, 0, 13, 0, 0, 0, 67, 97, 108,
  108, 97, 98, 108, 101, 46, 86, 105, 101, 119, 0, 0, 1, 5, 0, 0, 0, 97, 108, 105, 118, 101,
  0, 0, 0, 0, 14, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116,
  2, 0, 0, 0, 0, 0, 17, 0, 0, 0, 86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117,
  98, 108, 105, 99, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 5, 0, 0, 0, 66, 108, 111, 99, 107, 4, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105,
  111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 10, 0, 0, 0, 79, 112, 46, 76, 105, 116, 101, 114, 97, 108, 2, 0, 0, 0, 0, 0, 1, 0, 0,
  0, 1, 11, 0, 0, 0, 84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110, 1, 0, 1, 0, 0, 0, 0,
  0, 0, 0, 0, 0
]

def proofedInvSpine : TransparentByteSpineV1 := [
  8, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 9, 0, 1, 0, 0, 0, 18, 0, 0, 0, 67, 97, 108,
  108, 97, 98, 108, 101, 46, 73, 110, 118, 97, 114, 105, 97, 110, 116, 0, 0, 1, 4, 0, 0, 0,
  115, 97, 102, 101, 0, 0, 0, 0, 14, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 82, 101,
  115, 117, 108, 116, 2, 0, 0, 0, 0, 0, 17, 0, 0, 0, 86, 105, 115, 105, 98, 105, 108, 105,
  116, 121, 46, 80, 117, 98, 108, 105, 99, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 5, 0, 0, 0, 66, 108,
  111, 99, 107, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114,
  117, 99, 116, 105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 79, 112, 46, 76, 105, 116, 101, 114, 97, 108, 2, 0, 0,
  0, 0, 0, 1, 0, 0, 0, 1, 11, 0, 0, 0, 84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110, 1,
  0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 0, 0, 0, 0, 0, 0, 0
]

def proofedCallablesSpine : TransparentByteSpineV1 :=
  [2, 0, 0, 0] ++ proofedViewSpine ++ proofedInvSpine

def proofedInvariantsSpine : TransparentByteSpineV1 := [
  1, 0, 0, 0, 13, 0, 0, 0, 73, 110, 118, 97, 114, 105, 97, 110, 116, 68, 101, 99, 108, 3, 0,
  0, 0, 0, 0, 4, 0, 0, 0, 115, 97, 102, 101, 1, 0, 0, 0
]

def proofedRequirementsSpine : TransparentByteSpineV1 := [
  19, 0, 0, 0, 80, 114, 111, 103, 114, 97, 109, 82, 101, 113, 117, 105, 114, 101, 109, 101,
  110, 116, 115, 1, 0, 1, 0, 0, 0, 18, 0, 0, 0, 82, 101, 113, 117, 105, 114, 101, 109, 101,
  110, 116, 82, 101, 113, 117, 101, 115, 116, 4, 0, 10, 0, 0, 0, 118, 97, 108, 117, 101, 46,
  98, 111, 111, 108, 5, 0, 0, 0, 49, 46, 48, 46, 48, 237, 52, 225, 6, 29, 14, 102, 99, 155,
  106, 118, 55, 29, 216, 166, 193, 204, 215, 46, 122, 154, 20, 116, 84, 218, 122, 83, 193, 167,
  71, 84, 124, 0, 0, 0, 0
]

def proofedBodySpine : TransparentByteSpineV1 :=
  proofedRootHeaderSpine ++ proofedQnSpine ++ proofedTypesSpine ++
    proofedEmptySpine ++ proofedEmptySpine ++ proofedEmptySpine ++ proofedEmptySpine ++
    proofedCallablesSpine ++ proofedInvariantsSpine ++ proofedRequirementsSpine

def proofedEncodeSpine : TransparentByteSpineV1 :=
  proofedMagicSpine ++ proofedBodySpine

theorem proofedEncodeSpine_length : proofedEncodeSpine.length = 802 := by
  rfl

/-- Encode-side spine is definitionally the elaborator subject bytes (sole identity). -/
theorem proofedEncodeSpine_eq_subjectBytes :
    ByteArray.mk proofedEncodeSpine.toArray = proofedBytes := by
  rfl

theorem proofedEncodeSpine_eq_subjectBytesV1 :
    ByteArray.mk proofedEncodeSpine.toArray = Proofed.Proof.subjectBytesV1 := by
  simpa [proofedBytes] using proofedEncodeSpine_eq_subjectBytes

/-! ### Spine append helper (production ByteArray framing identity) -/

theorem appendSpineBytes (left right : TransparentByteSpineV1) :
    (ByteArray.mk left.toArray).append (ByteArray.mk right.toArray) =
      ByteArray.mk (left ++ right).toArray := by
  apply ByteArray.ext
  simp [ByteArray.append]

/-! ### Field encodes (production encoders only) -/

theorem encodeQualifiedName_proofed :
    encodeQualifiedName proofedData.qualifiedName =
      .ok (ByteArray.mk proofedQnSpine.toArray) := by
  rfl

theorem encodeTypes_proofed :
    encodeArray encodeTypeDeclV1 proofedData.types =
      .ok (ByteArray.mk proofedTypesSpine.toArray) := by
  rfl

theorem encodeConstants_proofed :
    encodeArray encodeConstantV1 proofedData.constants =
      .ok (ByteArray.mk proofedEmptySpine.toArray) := by
  rfl

theorem encodeLogicalState_proofed :
    encodeArray encodeStateDeclV1 proofedData.logicalState =
      .ok (ByteArray.mk proofedEmptySpine.toArray) := by
  rfl

theorem encodeEvents_proofed :
    encodeArray encodeEventDeclV1 proofedData.events =
      .ok (ByteArray.mk proofedEmptySpine.toArray) := by
  rfl

theorem encodeErrors_proofed :
    encodeArray encodeErrorDeclV1 proofedData.errors =
      .ok (ByteArray.mk proofedEmptySpine.toArray) := by
  rfl

theorem encodeView_proofed :
    encodeCallableV1 viewC = .ok (ByteArray.mk proofedViewSpine.toArray) := by
  rfl

theorem encodeInv_proofed :
    encodeCallableV1 invC = .ok (ByteArray.mk proofedInvSpine.toArray) := by
  rfl

theorem encodeCallables_proofed :
    encodeArray encodeCallableV1 proofedData.callables =
      .ok (ByteArray.mk proofedCallablesSpine.toArray) := by
  have htwo :=
    encodeArray_twoV1 encodeCallableV1 viewC invC
      (ByteArray.mk proofedViewSpine.toArray)
      (ByteArray.mk proofedInvSpine.toArray)
      encodeView_proofed encodeInv_proofed
  have hbytes :
      (encodeU32le 2).append
          ((ByteArray.mk proofedViewSpine.toArray).append
            (ByteArray.mk proofedInvSpine.toArray)) =
        ByteArray.mk proofedCallablesSpine.toArray := by
    rw [show encodeU32le 2 = ByteArray.mk (List.toArray [2, 0, 0, 0]) by rfl]
    rw [appendSpineBytes proofedViewSpine proofedInvSpine]
    rw [appendSpineBytes [2, 0, 0, 0] (proofedViewSpine ++ proofedInvSpine)]
    rfl
  change encodeArray encodeCallableV1 #[viewC, invC] =
    .ok (ByteArray.mk proofedCallablesSpine.toArray)
  rw [htwo, hbytes]

theorem encodeInvariants_proofed :
    encodeArray encodeInvariantDeclV1 proofedData.invariants =
      .ok (ByteArray.mk proofedInvariantsSpine.toArray) := by
  rfl

theorem encodeRequirements_proofed :
    encodeProgramRequirementsV1 proofedData.requirements =
      .ok (ByteArray.mk proofedRequirementsSpine.toArray) := by
  rfl

/-! ### Gate lemmas for root composition -/

theorem qnShape_proofed :
    validateProgramQualifiedNameShapeV1 proofedData.qualifiedName = .ok () := by
  have hqn : 2 ≤
      ({ head := "Tests", tail := #["Language", "InlineProofAuthoringV1", "Proofed"] } :
        NonEmptyArray String).toArray.size := by
    decide
  simp [validateProgramQualifiedNameShapeV1, proofedData, qn,
    Pure.pure, Except.pure, Bind.bind, Except.bind, hqn]

theorem tableSizes_proofed :
    checkTableSize proofedData.types.size = .ok () ∧
    checkTableSize proofedData.constants.size = .ok () ∧
    checkTableSize proofedData.logicalState.size = .ok () ∧
    checkTableSize proofedData.events.size = .ok () ∧
    checkTableSize proofedData.errors.size = .ok () ∧
    checkTableSize proofedData.callables.size = .ok () ∧
    checkTableSize proofedData.invariants.size = .ok () := by
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> rfl

theorem encodeBody_proofed :
    encodeTagged "SemanticProgram.Data" #[
      ByteArray.mk proofedQnSpine.toArray,
      ByteArray.mk proofedTypesSpine.toArray,
      ByteArray.mk proofedEmptySpine.toArray,
      ByteArray.mk proofedEmptySpine.toArray,
      ByteArray.mk proofedEmptySpine.toArray,
      ByteArray.mk proofedEmptySpine.toArray,
      ByteArray.mk proofedCallablesSpine.toArray,
      ByteArray.mk proofedInvariantsSpine.toArray,
      ByteArray.mk proofedRequirementsSpine.toArray] =
        .ok (ByteArray.mk proofedBodySpine.toArray) := by
  rw [encodeTagged_eq_ok_of_bytesV1 "SemanticProgram.Data"
    (ByteArray.mk #[83, 101, 109, 97, 110, 116, 105, 99, 80, 114, 111, 103,
      114, 97, 109, 46, 68, 97, 116, 97]) _ (by rfl) (by decide) (by decide)
      (by decide) (by decide) (by decide)]
  congr 1

theorem magic_append_body_eq_proofedBytes :
    (encodeMagicPrefix semanticProgramMagicV1).append
        (ByteArray.mk proofedBodySpine.toArray) =
      proofedBytes := by
  rw [show encodeMagicPrefix semanticProgramMagicV1 =
    ByteArray.mk proofedMagicSpine.toArray by rfl]
  rw [appendSpineBytes]
  exact proofedEncodeSpine_eq_subjectBytes

theorem outSize_proofed :
    ((encodeMagicPrefix semanticProgramMagicV1).append
        (ByteArray.mk proofedBodySpine.toArray)).size ≤
      maxCanonicalProgramBytes := by
  rw [magic_append_body_eq_proofedBytes]
  change proofedEncodeSpine.length ≤ maxCanonicalProgramBytes
  rw [proofedEncodeSpine_length]
  decide

/-! ### Target theorem: structure ⇒ encode equals elaborator subject bytes -/

/-- Encode-only kernel certificate. Structure is a free hypothesis from the
    parallel structure lane; this module does not re-prove structure. -/
theorem encodeData_proofed_of_structure
    (hstructure : validateSemanticProgramStructureV1 proofedData = .ok ()) :
    encodeSemanticProgramDataV1 proofedData = .ok proofedBytes := by
  have hsizes := tableSizes_proofed
  have hroot : encodeSemanticProgramDataV1 proofedData =
      .ok ((encodeMagicPrefix semanticProgramMagicV1).append
        (ByteArray.mk proofedBodySpine.toArray)) := by
    apply encodeSemanticProgramDataV1_eq_of_fields proofedData
      (ByteArray.mk proofedQnSpine.toArray)
      (ByteArray.mk proofedTypesSpine.toArray)
      (ByteArray.mk proofedEmptySpine.toArray)
      (ByteArray.mk proofedEmptySpine.toArray)
      (ByteArray.mk proofedEmptySpine.toArray)
      (ByteArray.mk proofedEmptySpine.toArray)
      (ByteArray.mk proofedCallablesSpine.toArray)
      (ByteArray.mk proofedInvariantsSpine.toArray)
      (ByteArray.mk proofedRequirementsSpine.toArray)
      (ByteArray.mk proofedBodySpine.toArray)
    · exact qnShape_proofed
    · exact hsizes.1
    · exact hsizes.2.1
    · exact hsizes.2.2.1
    · exact hsizes.2.2.2.1
    · exact hsizes.2.2.2.2.1
    · exact hsizes.2.2.2.2.2.1
    · exact hsizes.2.2.2.2.2.2
    · exact hstructure
    · exact encodeQualifiedName_proofed
    · exact encodeTypes_proofed
    · exact encodeConstants_proofed
    · exact encodeLogicalState_proofed
    · exact encodeEvents_proofed
    · exact encodeErrors_proofed
    · exact encodeCallables_proofed
    · exact encodeInvariants_proofed
    · exact encodeRequirements_proofed
    · exact encodeBody_proofed
    · exact outSize_proofed
  rw [hroot, magic_append_body_eq_proofedBytes]

/-- Same statement with elaborator name explicit. -/
theorem encodeData_subjectBytesV1_of_structure
    (hstructure : validateSemanticProgramStructureV1 proofedData = .ok ()) :
    encodeSemanticProgramDataV1 proofedData =
      .ok Proofed.Proof.subjectBytesV1 := by
  simpa [proofedBytes] using encodeData_proofed_of_structure hstructure

end Tests.Semantic.ProofedEncodeCertV1
