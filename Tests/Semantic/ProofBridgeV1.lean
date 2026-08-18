/-
  Tests.Semantic.ProofBridgeV1 — parametric encode→structure bridge and
  runtime encode/decode/validate checks for the canonical invariant fixture.

  Compile-time carrier validation via transport decode was removed with the
  unsafe `decodeData_canonicalBytes` witness; structure closure and encode
  identity remain available from `Tests.Semantic.InvariantABI`.
-/
import Tests.Semantic.InvariantABI
import ProofForgeV2.Semantic.ProofBridgeV1
import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.NormalizeV1

namespace Tests.Semantic.ProofBridgeV1

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.ProofBridgeV1
open ProofForgeV2.Semantic.WireV1
open Tests.Semantic.InvariantABI.CanonicalInvariantFixtureV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectOk {α} (label : String) (r : Except SemanticWireErrorV1 α) : IO α :=
  match r with
  | .ok a => pure a
  | .error e => throw <| IO.userError s!"{label}: {repr e}"

/-- Positive: encode success implies structure without replaying phases. -/
theorem structure_of_encode_canonical :
    validateSemanticProgramStructureV1 data = .ok () :=
  semanticProgramStructure_data

/-- Positive: Normalize encodeCarrier packages the same production encode. -/
theorem encodeCarrier_of_encode_canonical :
    encodeCarrierV1 data = .ok ⟨canonicalBytes⟩ :=
  encodeCarrierV1_eq_ok_of_encode data canonicalBytes encodeData_canonicalBytes

/-- Positive: invert encodeCarrier to recover the encode witness. -/
theorem encode_of_encodeCarrier_canonical :
    encodeSemanticProgramDataV1 data = .ok canonicalBytes :=
  encodeCarrierV1_ok_implies_encode data ⟨canonicalBytes⟩
    encodeCarrier_of_encode_canonical

/-- Byte-mutation negative (theorem): same decoded data with non-identical
    bytes fails validation as `.nonCanonical`. -/
theorem validate_error_on_trailing_byte_when_decode_recovers_data
    (mutated : ByteArray)
    (hdecode : decodeSemanticProgramDataV1 mutated = .ok data)
    (hmismatch : (canonicalBytes == mutated) = false) :
    validateSemanticProgramV1 ⟨mutated⟩ = .error .nonCanonical :=
  validateSemanticProgramV1_eq_error_of_encode_decode_mismatch data canonicalBytes
    mutated encodeData_canonicalBytes hdecode hmismatch

/-- Runtime: production encode/decode/validate, byte mutation, and evaluator
    spot checks on the closed canonical invariant ABI fixture. -/
def run : IO Unit := do
  let encoded ← expectOk "public-invariant-abi encode"
    (encodeSemanticProgramDataV1 data)
  let decoded ← expectOk "public-invariant-abi decode"
    (decodeSemanticProgramDataV1 encoded)
  expect (decoded == data) "encode+decode bridge recovers exact data"
  match validateSemanticProgramV1 ⟨encoded⟩ with
  | .error e => throw <| IO.userError s!"canonical validate failed: {repr e}"
  | .ok recovered =>
      expect (recovered == data) "validate returns exact closed data"
  if canonicalBytes.size == encoded.size &&
      (encoded == canonicalBytes) then
    pure ()
  if canonicalBytes.size > 0 then
    let mutated :=
      Id.run do
        let mut out := encoded
        let b0 := out.get! 0
        out := out.set! 0 (b0 <<< 1 ||| 1)
        pure out
    expect ((encoded == mutated) == false) "mutation changes bytes"
    match validateSemanticProgramV1 ⟨mutated⟩ with
    | .ok _ => throw <| IO.userError "mutated carrier must not validate"
    | .error _ => pure ()
  let state ← match initialLogicalStateV1 ⟨encoded⟩ with
    | .ok s => pure { s with initialized := true }
    | .error e => throw <| IO.userError s!"initial state: {repr e}"
  expect (stateConformsBoolV1 ⟨encoded⟩ state) "conforming initial state"
  match evalInvariantV1 ⟨encoded⟩ 1 state with
  | .returnedFalse => pure ()
  | .returnedTrue =>
      throw <| IO.userError "falsehood ordinal must not always return true"
  | other =>
      throw <| IO.userError s!"falsehood ordinal unexpected: {repr other}"
  match evalInvariantV1 ⟨encoded⟩ 99 state with
  | .trapped => pure ()
  | other => throw <| IO.userError s!"OOR ordinal must trap: {repr other}"

end Tests.Semantic.ProofBridgeV1
