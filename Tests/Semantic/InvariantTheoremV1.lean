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

open ProofForgeV2.Semantic.ProofBridgeV1

/-- The exact canonical carrier passes the sole production validation path and
    yields the same closed semantic data used by the independent byte proof.
    Composition uses the parametric encode+decode bridge (no phase replay). -/
theorem validateCarrier_canonicalBytes :
    validateSemanticProgramV1 (⟨canonicalBytes⟩ : SemanticProgramV1) = .ok data :=
  validateSemanticProgramV1_eq_ok_of_encode_decode data canonicalBytes
    encodeData_canonicalBytes decodeData_canonicalBytes

/-- Proof-carrying validated carrier for the canonical fixture, minted only from
    production encode/decode witnesses. -/
def validatedCarrier_canonicalBytes : ValidatedSemanticProgramV1 :=
  ValidatedSemanticProgramV1.ofEncodeDecode data canonicalBytes
    encodeData_canonicalBytes decodeData_canonicalBytes

/-- Closed kernel theorem for canonical invariant ordinal zero. It follows the
    production carrier validation, state conformance, ordinal selection, and
    invariant machine path through `truth → truthLeaf → true`. -/
theorem invariantTheorem_canonicalBytes_ordinal0 :
    InvariantTheoremV1 (⟨canonicalBytes⟩ : SemanticProgramV1) 0 := by
  have hprogram :
      validatedCarrier_canonicalBytes.program =
        (⟨canonicalBytes⟩ : SemanticProgramV1) := rfl
  have hdata : validatedCarrier_canonicalBytes.data = data := rfl
  have hclosed :
      InvariantTheoremV1 validatedCarrier_canonicalBytes.program 0 := by
    apply invariantTheoremV1_of_validated validatedCarrier_canonicalBytes 0
    · change 0 < invariants.size
      decide
    · intro state hconforms
      rw [hprogram] at hconforms
      obtain ⟨hinitialized, overlay, hdecodeState⟩ :=
        stateConformsV1_elim_of_validate_eq_ok
          (⟨canonicalBytes⟩ : SemanticProgramV1) data state
          validateCarrier_canonicalBytes hconforms
      have hrun : runInvariantCallableV1 data 2 state = .returnedTrue := by
        apply runInvariantCallableV1_eq_returnedTrue_of_single_nullary_pureCall_true
          data state overlay 2 1 0 (some "truth") (some "truthLeaf") .public_ none
          hinitialized hdecodeState
        · rfl
        · rfl
        · rfl
        · rfl
      apply evalInvariantV1_eq_of_validated_selection
        (⟨canonicalBytes⟩ : SemanticProgramV1) data 0 truthDecl state overlay
        .returnedTrue validateCarrier_canonicalBytes hinitialized hdecodeState
      · rfl
      · exact hrun
  simpa [hprogram] using hclosed

/-- Ordinal mutation negative: OOR ordinal cannot satisfy the closed proposition. -/
theorem not_invariantTheorem_canonicalBytes_ordinal2 :
    ¬ InvariantTheoremV1 (⟨canonicalBytes⟩ : SemanticProgramV1) 2 :=
  not_invariantTheoremV1_of_oob_ordinal
    (⟨canonicalBytes⟩ : SemanticProgramV1) data 2
    validateCarrier_canonicalBytes (by decide)

end Tests.Semantic.InvariantABI.CanonicalInvariantFixtureV1
