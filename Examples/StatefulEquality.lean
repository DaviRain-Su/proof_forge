import ProofForgeV2

/- A Reference-certified synchronization example.  This does not claim target
refinement or preservation for arbitrary contracts. -/

namespace Examples

open ProofForgeV2.Language

program StatefulEquality where
  state reserves : UInt64
  state shares : UInt64

  entry sync(amount : UInt64) : UInt64 do
    reserves := amount
    shares := amount
    return shares

  invariant solvent : reserves == shares
  proof solvent preserving using StatefulEqualityProof.solvent

theorem StatefulEqualityProof.solvent : StatefulEquality.ProofPreserving.solvent := by
  exact
    ProofForgeV2.Semantic.StatefulEqualityPreservationV1.preservationTheorem_of_subjectBodyV1
      StatefulEquality.Proof.subjectDataV1.qualifiedName
      "reserves" "shares" "sync" "amount" "solvent"
      StatefulEquality.Proof.subjectDataV1
      StatefulEquality.Proof.subjectBytesV1
      (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
      (by decide) (by decide) (by rfl)
      StatefulEquality.Proof.subjectBodyEncodeOkV1

end Examples
