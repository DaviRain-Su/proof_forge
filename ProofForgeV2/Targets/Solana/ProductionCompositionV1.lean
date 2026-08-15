import ProofForgeV2.Targets.Solana.ProductionProviderV1

/-!
# Contract-independent Solana production composition gate

This module factors the fail-closed Boolean boundary shared by production
subjects. A resolver must first return an exact source-derived subject; only
then are its Reference-observation and provider checkers evaluated.

The gate is parameterized by the subject type and both checkers. It contains no
contract registry, business relation, provider trace, evaluator, or transition.
-/

namespace ProofForgeV2.Targets.Solana

/-- Resolve one production subject and evaluate its checker. Resolution failure
    is rejected rather than replaced by a default subject. -/
def checkCertifiedSolanaProductionSubjectV1
    (result : Except String α) (checker : α → Bool) : Bool :=
  match result with
  | .error _ => false
  | .ok value => checker value

/-- A successful subject gate retains the exact resolver equation and checker
    result. -/
theorem checkCertifiedSolanaProductionSubjectV1_sound
    (result : Except String α) (checker : α → Bool)
    (checked : checkCertifiedSolanaProductionSubjectV1 result checker = true) :
    ∃ value, result = .ok value ∧ checker value = true := by
  unfold checkCertifiedSolanaProductionSubjectV1 at checked
  cases hresult : result with
  | error error => simp [hresult] at checked
  | ok value =>
      simp [hresult] at checked
      exact ⟨value, rfl, checked⟩

/-- Fail-closed composition of a source-derived subject, a Reference-side
    observation checker, and a provider-side certificate checker. -/
def checkCertifiedSolanaProductionCompositionV1
    (result : Except String α)
    (referenceChecker providerChecker : α → Bool) : Bool :=
  checkCertifiedSolanaProductionSubjectV1 result fun subject =>
    referenceChecker subject && providerChecker subject

/-- A successful composition gate recovers one shared subject and successful
    results for both supplied checkers. It does not interpret either result. -/
theorem checkCertifiedSolanaProductionCompositionV1_sound
    (result : Except String α)
    (referenceChecker providerChecker : α → Bool)
    (checked : checkCertifiedSolanaProductionCompositionV1 result
      referenceChecker providerChecker = true) :
    ∃ value,
      result = .ok value ∧
      referenceChecker value = true ∧
      providerChecker value = true := by
  rcases checkCertifiedSolanaProductionSubjectV1_sound result
      (fun subject => referenceChecker subject && providerChecker subject)
      checked with ⟨value, hresult, hchecked⟩
  simp only [Bool.and_eq_true] at hchecked
  exact ⟨value, hresult, hchecked.1, hchecked.2⟩

end ProofForgeV2.Targets.Solana
