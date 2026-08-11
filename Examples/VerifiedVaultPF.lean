import ProofForgeV2

/- A business-level initializer/deposit/withdraw/view preservation slice. It
certifies the exact DSL subject through the production Reference semantics;
target-artifact refinement remains intentionally outside this example's claim. -/

namespace Examples

open ProofForgeV2.Language

program VerifiedVaultPF where
  state reserves : UInt64
  state shares : UInt64

  init() do
    reserves := 0
    shares := 0

  entry deposit(amount : UInt64) : UInt64 do
    reserves := reserves + amount
    shares := shares + amount
    return shares

  entry withdraw(amount : UInt64) : Unit do
    assert amount <= reserves
    assert amount <= shares
    reserves := reserves - amount
    shares := shares - amount

  view status() : UInt64 do
    return reserves

  invariant solvent : reserves == shares
  proof solvent preserving using VerifiedVaultPFProof.solvent

theorem VerifiedVaultPFProof.solvent :
    VerifiedVaultPF.ProofPreserving.solvent := by
  exact
    ProofForgeV2.Semantic.InitializerDepositWithdrawViewEqualityPreservationV1.preservationTheorem_of_subjectBodyV1
      VerifiedVaultPF.Proof.subjectDataV1.qualifiedName
      "reserves" "shares" "deposit" "amount" "withdraw" "amount"
      "status" "solvent"
      VerifiedVaultPF.Proof.subjectDataV1
      VerifiedVaultPF.Proof.subjectBytesV1
      (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
      (by rfl) (by rfl)
      (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
      (by decide) (by rfl)
      VerifiedVaultPF.Proof.subjectBodyEncodeOkV1

end Examples
