import ProofForgeV2

/- The first business-level initializer/view preservation slice. It certifies
the exact DSL subject through the production Reference semantics; deposit and
withdraw operations and target-artifact refinement are intentionally outside
this example's claim. -/

namespace Examples

open ProofForgeV2.Language

program VerifiedVaultPF where
  state reserves : UInt64
  state shares : UInt64

  init() do
    reserves := 0
    shares := 0

  view status() : UInt64 do
    return reserves

  invariant solvent : reserves == shares
  proof solvent preserving using VerifiedVaultPFProof.solvent

theorem VerifiedVaultPFProof.solvent :
    VerifiedVaultPF.ProofPreserving.solvent := by
  exact
    ProofForgeV2.Semantic.InitializerViewEqualityPreservationV1.preservationTheorem_of_subjectBodyV1
      VerifiedVaultPF.Proof.subjectDataV1.qualifiedName
      "reserves" "shares" "status" "solvent"
      VerifiedVaultPF.Proof.subjectDataV1
      VerifiedVaultPF.Proof.subjectBytesV1
      (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
      (by decide) (by decide) (by rfl)
      VerifiedVaultPF.Proof.subjectBodyEncodeOkV1

end Examples
