import ProofForgeV2

namespace Proofship

open ProofForgeV2.Language

-- ProofShip proof-twin (positive): certified family variant.
-- Exact parity-preservation shape: one public UInt64 slot, entry x := x + 2,
-- view return x, invariant x % 2 == 0, no initializer.
-- This file exercises the machine-checked GATE MECHANISM (ADR-0027/0034
-- generic preservation API). It is NOT the deploy file and does NOT claim the
-- RWA share rules are formally proven — see proofship-positioning §4 honesty.
program EvenStep where
  state total : UInt64

  entry addTwo() : UInt64 do
    total := total + 2
    return total

  view read() : UInt64 do
    return total

  invariant even : total % 2 == 0
  proof even preserving using EvenStepProof.even

theorem EvenStepProof.even : EvenStep.ProofPreserving.even := by
  exact
    ProofForgeV2.Semantic.UInt64ParityPreservationV1.preservationTheorem_of_subjectBodyV1
      EvenStep.Proof.subjectDataV1.qualifiedName
      "total" "addTwo" "read" "even" EvenStep.Proof.subjectBytesV1
      (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
      (by decide) (by decide) (by decide)
      EvenStep.Proof.subjectBodyEncodeOkV1

end Proofship
