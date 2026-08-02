/-
  Tests.Semantic.InvariantTheoremV1 — closed kernel theorem for the canonical
  invariant ABI proof subject.

  Kept separate from the large independent byte-golden module so Lean can
  reuse that compiled fixture and elaborate only the final closed theorem.
  This is a concrete theorem, not corpus-wide TST-SEM/TST-PROOF evidence.
-/
import Tests.Semantic.InvariantABI

namespace Tests.Semantic.InvariantABI.CanonicalInvariantFixtureV1

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

/-- The exact canonical carrier passes the sole production validation path and
    yields the same closed semantic data used by the independent byte proof. -/
theorem validateCarrier_canonicalBytes :
    validateSemanticProgramV1 (⟨canonicalBytes⟩ : SemanticProgramV1) = .ok data := by
  apply validateSemanticProgramV1_eq_ok_of_identity
    (⟨canonicalBytes⟩ : SemanticProgramV1) data canonicalBytes
  · exact decodeData_canonicalBytes
  · exact encodeData_canonicalBytes
  · exact byteArray_beq_self canonicalBytes
  · exact semanticProgramStructure_data

/-- Closed kernel theorem for canonical invariant ordinal zero. It follows the
    production carrier validation, state conformance, ordinal selection, and
    invariant machine path through `truth → truthLeaf → true`. -/
theorem invariantTheorem_canonicalBytes_ordinal0 :
    InvariantTheoremV1 (⟨canonicalBytes⟩ : SemanticProgramV1) 0 := by
  apply invariantTheoremV1_of_validate_eq_ok
    (⟨canonicalBytes⟩ : SemanticProgramV1) data 0 validateCarrier_canonicalBytes
  · change 0 < invariants.size
    decide
  · intro state hconforms
    obtain ⟨hinitialized, overlay, hdecode⟩ :=
      stateConformsV1_elim_of_validate_eq_ok
        (⟨canonicalBytes⟩ : SemanticProgramV1) data state
        validateCarrier_canonicalBytes hconforms
    have hrun : runInvariantCallableV1 data 2 state = .returnedTrue := by
      apply runInvariantCallableV1_eq_returnedTrue_of_single_nullary_pureCall_true
        data state overlay 2 1 0 (some "truth") (some "truthLeaf") .public_ none
        hinitialized hdecode
      · rfl
      · rfl
      · rfl
      · rfl
    apply evalInvariantV1_eq_of_validated_selection
      (⟨canonicalBytes⟩ : SemanticProgramV1) data 0 truthDecl state overlay
      .returnedTrue validateCarrier_canonicalBytes hinitialized hdecode
    · rfl
    · exact hrun

end Tests.Semantic.InvariantABI.CanonicalInvariantFixtureV1
