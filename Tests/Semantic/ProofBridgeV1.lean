/-
  Tests.Semantic.ProofBridgeV1 — parametric encode/decode→validate bridge,
  proof-carrying validated carrier, closed positive, and byte/ordinal mutation
  negatives.

  Reuses the independent canonical invariant fixture encode/decode witnesses.
  Does not claim full parametric decode∘encode for arbitrary programs.
-/
import Tests.Semantic.InvariantABI
import ProofForgeV2.Semantic.ProofBridgeV1
import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.NormalizeV1

namespace Tests.Semantic.ProofBridgeV1

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.ProofBridgeV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1
open Tests.Semantic.InvariantABI.CanonicalInvariantFixtureV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Positive: encode+decode bridge closes production validation. -/
theorem validate_of_encode_decode_canonical :
    validateSemanticProgramV1 ⟨canonicalBytes⟩ = .ok data :=
  validateSemanticProgramV1_eq_ok_of_encode_decode data canonicalBytes
    encodeData_canonicalBytes decodeData_canonicalBytes

/-- Positive: encode success implies structure without replaying phases. -/
theorem structure_of_encode_canonical :
    validateSemanticProgramStructureV1 data = .ok () :=
  encodeSemanticProgramDataV1_ok_implies_structure data canonicalBytes
    encodeData_canonicalBytes

/-- Positive: Normalize encodeCarrier packages the same production encode. -/
theorem encodeCarrier_of_encode_canonical :
    encodeCarrierV1 data = .ok ⟨canonicalBytes⟩ :=
  encodeCarrierV1_eq_ok_of_encode data canonicalBytes encodeData_canonicalBytes

/-- Positive: invert encodeCarrier to recover the encode witness. -/
theorem encode_of_encodeCarrier_canonical :
    encodeSemanticProgramDataV1 data = .ok canonicalBytes :=
  encodeCarrierV1_ok_implies_encode data ⟨canonicalBytes⟩
    encodeCarrier_of_encode_canonical

/-- Positive: proof-carrying mint preserves exact product bytes/data. -/
theorem ofEncodeDecode_preserves_product_linkage :
    (ValidatedSemanticProgramV1.ofEncodeDecode data canonicalBytes
        encodeData_canonicalBytes decodeData_canonicalBytes).program =
      ⟨canonicalBytes⟩ ∧
    (ValidatedSemanticProgramV1.ofEncodeDecode data canonicalBytes
        encodeData_canonicalBytes decodeData_canonicalBytes).data = data :=
  ⟨rfl, rfl⟩

/-- Positive: closed InvariantTheorem via validated-carrier bridge at ordinal 0. -/
theorem invariantTheorem_via_validated_carrier :
    InvariantTheoremV1 ⟨canonicalBytes⟩ 0 := by
  let carrier := ValidatedSemanticProgramV1.ofEncodeDecode data canonicalBytes
    encodeData_canonicalBytes decodeData_canonicalBytes
  have hprogram : carrier.program = ⟨canonicalBytes⟩ := rfl
  have hclosed : InvariantTheoremV1 carrier.program 0 := by
    apply invariantTheoremV1_of_validated carrier 0
    · change 0 < invariants.size
      decide
    · intro state hconforms
      rw [hprogram] at hconforms
      obtain ⟨hinitialized, overlay, hdecodeState⟩ :=
        stateConformsV1_elim_of_validate_eq_ok
          ⟨canonicalBytes⟩ data state validate_of_encode_decode_canonical hconforms
      have hrun : runInvariantCallableV1 data 2 state = .returnedTrue := by
        apply runInvariantCallableV1_eq_returnedTrue_of_single_nullary_pureCall_true
          data state overlay 2 1 0 (some "truth") (some "truthLeaf") .public_ none
          hinitialized hdecodeState
        · rfl
        · rfl
        · rfl
        · rfl
      apply evalInvariantV1_eq_of_validated_selection
        ⟨canonicalBytes⟩ data 0 truthDecl state overlay .returnedTrue
        validate_of_encode_decode_canonical hinitialized hdecodeState
      · rfl
      · exact hrun
  simpa [hprogram] using hclosed

/-- Byte-mutation negative (theorem): same decoded data with non-identical
    bytes fails validation as `.nonCanonical`. -/
theorem validate_error_on_trailing_byte_when_decode_recovers_data
    (mutated : ByteArray)
    (hdecode : decodeSemanticProgramDataV1 mutated = .ok data)
    (hmismatch : (canonicalBytes == mutated) = false) :
    validateSemanticProgramV1 ⟨mutated⟩ = .error .nonCanonical :=
  validateSemanticProgramV1_eq_error_of_encode_decode_mismatch data canonicalBytes
    mutated encodeData_canonicalBytes hdecode hmismatch

/-- Ordinal-mutation negative (theorem): OOR ordinal is not a theorem. -/
theorem not_theorem_ordinal_oob :
    ¬ InvariantTheoremV1 ⟨canonicalBytes⟩ 99 :=
  not_invariantTheoremV1_of_oob_ordinal ⟨canonicalBytes⟩ data 99
    validate_of_encode_decode_canonical (by decide)

/-- Runtime: flip one carrier byte → validation fails closed.
    Also pins falsehood ordinal does not always return true. -/
def run : IO Unit := do
  -- Bridge positive at runtime
  match validateSemanticProgramV1 ⟨canonicalBytes⟩ with
  | .error e => throw <| IO.userError s!"canonical validate failed: {repr e}"
  | .ok recovered =>
      expect (recovered == data) "encode+decode bridge recovers exact data"
  -- Byte mutation: flip first magic byte
  if canonicalBytes.size == 0 then
    throw <| IO.userError "canonical bytes unexpectedly empty"
  let mutated :=
    Id.run do
      let mut out := canonicalBytes
      let b0 := out.get! 0
      out := out.set! 0 (b0 <<< 1 ||| 1)
      pure out
  expect ((canonicalBytes == mutated) == false) "mutation changes bytes"
  match validateSemanticProgramV1 ⟨mutated⟩ with
  | .ok _ => throw <| IO.userError "mutated carrier must not validate"
  | .error _ => pure ()
  -- Ordinal mutation: falsehood (ordinal 1) can return false on conforming state
  let state ← match initialLogicalStateV1 ⟨canonicalBytes⟩ with
    | .ok s =>
        pure { s with initialized := true }
    | .error e => throw <| IO.userError s!"initial state: {repr e}"
  expect (stateConformsBoolV1 ⟨canonicalBytes⟩ state) "conforming initial state"
  match evalInvariantV1 ⟨canonicalBytes⟩ 1 state with
  | .returnedFalse => pure ()
  | .returnedTrue =>
      throw <| IO.userError "falsehood ordinal must not always return true"
  | other =>
      throw <| IO.userError s!"falsehood ordinal unexpected: {repr other}"
  -- OOR ordinal traps
  match evalInvariantV1 ⟨canonicalBytes⟩ 99 state with
  | .trapped => pure ()
  | other => throw <| IO.userError s!"OOR ordinal must trap: {repr other}"

end Tests.Semantic.ProofBridgeV1
