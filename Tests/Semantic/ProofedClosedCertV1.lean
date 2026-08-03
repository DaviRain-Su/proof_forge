/-
  Tests.Semantic.ProofedClosedCertV1 — final kernel composition of the Proofed
  simple-closure certificate chain.

  Closes, without free validation hypotheses:
    InvariantTheoremV1 Proofed.Proof.subjectProgramV1 0
  and the ordinary authoring name:
    ProofedProof.safe : Proofed.Proof.safe

  Composition only (no re-proof of structure/encode/decode/evaluator lanes):
    structure_proofed
      → encodeData_proofed_of_structure
      → decodeData_proofed
      → ValidatedSemanticProgramV1.ofEncodeDecode
      → invariantTheorem_proofed_of_validated_carrier

  Hard boundaries:
    * no axiom / sorry / native_decide / ofReduceBool / run_tac / unsafe / meta / IO
    * no ProgramElaboration / CLI / second semantic model / residual encoder
    * theorem compilation is the test (no runtime suite)
-/
import Tests.Semantic.ProofedCertV1
import Tests.Semantic.ProofedEncodeCertV1
import Tests.Semantic.ProofedDecodeCertV1
import Tests.Semantic.SimpleClosureCertV1
import ProofForgeV2.Semantic.ProofBridgeV1
import ProofForgeV2.Semantic.InvariantABI

namespace Tests.Semantic.ProofedClosedCertV1

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ProofBridgeV1
open ProofForgeV2.Semantic.WireV1
open Tests.Semantic.ProofedCertV1
open Tests.Semantic.ProofedDecodeCertV1
open Tests.Semantic.ProofedEncodeCertV1
open Tests.Semantic.SimpleClosureCertV1
open Tests.Language.InlineProofAuthoringV1

/-! ### Closed encode from structure certificate -/

/-- Structure lane + encode-only certificate: production encode of `proofedData`
    is exact elaborator `proofedBytes` / `subjectBytesV1`. -/
theorem encodeData_proofed :
    encodeSemanticProgramDataV1 proofedData = .ok proofedBytes :=
  encodeData_proofed_of_structure structure_proofed

/-! ### Validated product carrier (sole mint path) -/

/-- Proof-carrying validated carrier for the elaborator Proofed subject.
    Minted only from production encode/decode witnesses. -/
def validatedCarrier_proofed : ValidatedSemanticProgramV1 :=
  ValidatedSemanticProgramV1.ofEncodeDecode proofedData proofedBytes
    encodeData_proofed decodeData_proofed

theorem validatedCarrier_proofed_program :
    validatedCarrier_proofed.program = Proofed.Proof.subjectProgramV1 :=
  rfl

theorem validatedCarrier_proofed_data :
    validatedCarrier_proofed.data = proofedData :=
  rfl

theorem validate_subjectProgramV1 :
    validateSemanticProgramV1 Proofed.Proof.subjectProgramV1 = .ok proofedData := by
  have h := validatedCarrier_proofed.hvalidate
  -- carrier.program is definitionally subjectProgramV1; data is proofedData
  simpa [validatedCarrier_proofed_program, validatedCarrier_proofed_data] using h

/-! ### Closed invariant theorem at ordinal 0 -/

/-- Final kernel composition: elaborator subject closes ordinal-0
    `InvariantTheoremV1` via the production simple-closure bridge. -/
theorem invariantTheorem_proofed_closed :
    InvariantTheoremV1 Proofed.Proof.subjectProgramV1 0 := by
  have hclosed :
      InvariantTheoremV1 validatedCarrier_proofed.program 0 :=
    invariantTheorem_proofed_of_validated_carrier
      validatedCarrier_proofed validatedCarrier_proofed_data
  simpa [validatedCarrier_proofed_program] using hclosed

end Tests.Semantic.ProofedClosedCertV1

/-! ### Ordinary authoring theorem name

    The inline surface `proof safe using ProofedProof.safe` only *references*
    this name; it is not declared in the authoring fixture. The conditional
    `ProofedProof.safe_of_validate` remains in ProofedCertV1 as a lane lemma.
    This is the closed, hypothesis-free ordinary theorem.
-/

namespace ProofedProof

open ProofForgeV2.Semantic.InvariantABI
open Tests.Semantic.ProofedClosedCertV1
open Tests.Language.InlineProofAuthoringV1

/-- Exact product obligation for `proof safe using ProofedProof.safe`. -/
theorem safe : Proofed.Proof.safe := by
  change InvariantTheoremV1 Proofed.Proof.subjectProgramV1 0
  exact invariantTheorem_proofed_closed

end ProofedProof
