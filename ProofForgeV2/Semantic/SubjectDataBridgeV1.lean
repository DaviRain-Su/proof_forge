import ProofForgeV2.Semantic.ProofBridgeV1
import ProofForgeV2.Semantic.WireV1

/-!
  ProofForgeV2.Semantic.SubjectDataBridgeV1 — generic bridge from structured
  product subject data to the byte carrier (wave-3′ mig-a3-elab).

  Product elaborator emits:
    * `subjectDataV1 : SemanticProgramDataV1` — structured constructor spine
    * `subjectBytesV1 : ByteArray` — certifier identity (pin or transparent spine)
    * `subjectProgramV1 : SemanticProgramV1` — `{ canonicalBytes := subjectBytesV1 }`

  Authors should prove shape / preservation facts on `subjectDataV1` (and
  shape-family theorems in `PreservationShapeV1`), not by reducing large
  `subjectBytesV1` spines. Pin remains an optional golden accelerator only.

  Sole encode authority: `encodeSemanticProgramDataV1`. No second State/Effect/
  step. No contract-specific content.
-/

namespace ProofForgeV2.Semantic.SubjectDataBridgeV1

open ProofForgeV2.Semantic.ProofBridgeV1
open ProofForgeV2.Semantic.WireV1

/-- Sole production encode of structured subject data to carrier bytes. -/
def encodeSubjectBytesV1 (data : SemanticProgramDataV1) :
    Except SemanticWireErrorV1 ByteArray :=
  encodeSemanticProgramDataV1 data

/-- Package structured data + encode success as a Normalize encode witness. -/
def toEncodeWitnessV1
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes) :
    NormalizeEncodeWitnessV1 :=
  NormalizeEncodeWitnessV1.ofEncode data bytes hencode

/-- Byte carrier from structured data under an encode witness. -/
def programOfEncodeV1
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes) :
    SemanticProgramV1 :=
  (toEncodeWitnessV1 data bytes hencode).program

/-- Definitional: `programOfEncodeV1` carrier bytes are exactly the encode output. -/
theorem programOfEncodeV1_canonicalBytes
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes) :
    (programOfEncodeV1 data bytes hencode).canonicalBytes = bytes :=
  rfl

/-- Definitional: encode witness data is the structured subject. -/
theorem toEncodeWitnessV1_data
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes) :
    (toEncodeWitnessV1 data bytes hencode).data = data :=
  rfl

/-- Lift structured subject + encode + root-field invert to a validated carrier
    (no free decode hyp; reuses mig-a1-root composition). -/
def toValidatedOfInvertV1
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes)
    (hinvert : RootFieldInvertV1 data) :
    ValidatedSemanticProgramV1 :=
  (toEncodeWitnessV1 data bytes hencode).toValidated hinvert

/-- Validate from structured subject + encode + RootFieldInvert. -/
theorem validate_of_subjectData_invert
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes)
    (hinvert : RootFieldInvertV1 data) :
    validateSemanticProgramV1 (programOfEncodeV1 data bytes hencode) = .ok data :=
  validate_of_encode_witness (toEncodeWitnessV1 data bytes hencode) hinvert

/-- Validate from structured subject + encode + explicit transport decode. -/
theorem validate_of_subjectData_decode
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes)
    (hdecode : decodeSemanticProgramDataV1 bytes = .ok data) :
    validateSemanticProgramV1 (programOfEncodeV1 data bytes hencode) = .ok data :=
  validate_of_encode_decode_witness
    (toEncodeWitnessV1 data bytes hencode) hdecode

/-- Structure gate from encode success (re-export for subject-data authors). -/
theorem structure_of_subjectData_encode
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes) :
    validateSemanticProgramStructureV1 data = .ok () :=
  structure_of_encode_witness (toEncodeWitnessV1 data bytes hencode)

end ProofForgeV2.Semantic.SubjectDataBridgeV1
