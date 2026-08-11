import ProofForgeV2

namespace Proofship

open ProofForgeV2.Language

-- ProofShip proof-twin (positive, business-flavored): share-conservation shape.
-- Certified through the production Reference semantics via the generic
-- name-parameterized InitializerViewEquality family (main @ 4947062af):
-- two UInt64 slots zero-initialized, nullary view, public equality invariant.
-- Honesty: this exercises the machine-checked GATE on a certified family;
-- the RWA deploy file carries no invariant (EVM fails closed on nonempty
-- invariants). We do NOT claim the deploy contract's rules are formally proven.
program ShareConservation where
  state issued : UInt64
  state distributed : UInt64

  init() do
    issued := 0
    distributed := 0

  view issuedTotal() : UInt64 do
    return issued

  invariant conserved : issued == distributed
  proof conserved preserving using ShareConservationProof.conserved

theorem ShareConservationProof.conserved :
    ShareConservation.ProofPreserving.conserved := by
  exact
    ProofForgeV2.Semantic.InitializerViewEqualityPreservationV1.preservationTheorem_of_subjectBodyV1
      ShareConservation.Proof.subjectDataV1.qualifiedName
      "issued" "distributed" "issuedTotal" "conserved"
      ShareConservation.Proof.subjectDataV1
      ShareConservation.Proof.subjectBytesV1
      (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
      (by decide) (by decide) (by rfl)
      ShareConservation.Proof.subjectBodyEncodeOkV1

end Proofship
