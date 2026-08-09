/-
  Tests.Semantic.CodecInvertV1 — mig-a1 foundation + fields: MidOffsetInvert,
  Visibility complete leaf, array zero helper, InvariantDecl invert,
  empty tables, empty Requirements, Type.Bool, QN singleton.

  Does not claim full parametric decode∘encode for arbitrary programs.
-/
import ProofForgeV2.Semantic.Wire.CodecInvertV1
import ProofForgeV2.Semantic.Wire.CodecInvertFieldsV1
import ProofForgeV2.Semantic.WireV1

namespace Tests.Semantic.CodecInvertV1

open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Core.Common

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Positive theorem: public Visibility mid-offset invert at nesting 0. -/
theorem visibility_public_mid_nest0 :
    decodeVisibilityV1
        ⟨taggedHeaderBytesV1 "Visibility.Public" 0, 0, 0⟩ =
      .ok (.public_,
        ⟨taggedHeaderBytesV1 "Visibility.Public" 0,
          (taggedHeaderBytesV1 "Visibility.Public" 0).size, 0⟩) := by
  simpa [ByteArray.append_empty] using
    decodeVisibility_public_midV1 ByteArray.empty ByteArray.empty 0 (by decide)

/-- Positive theorem: encode success ⇒ mid-offset decode for all Visibility. -/
theorem visibility_of_encode_all (vis : VisibilityV1) :
    ∃ b, encodeVisibilityV1 vis = .ok b ∧
      decodeVisibilityV1 ⟨b, 0, 0⟩ = .ok (vis, ⟨b, b.size, 0⟩) := by
  match vis with
  | .public_ =>
      refine ⟨taggedHeaderBytesV1 "Visibility.Public" 0, encodeVisibility_public_eq, ?_⟩
      simpa [ByteArray.append_empty] using
        decodeVisibility_of_encode_midV1 .public_
          (taggedHeaderBytesV1 "Visibility.Public" 0) ByteArray.empty ByteArray.empty 0
          (by decide) encodeVisibility_public_eq
  | .private_ =>
      refine ⟨taggedHeaderBytesV1 "Visibility.Private" 0, encodeVisibility_private_eq, ?_⟩
      simpa [ByteArray.append_empty] using
        decodeVisibility_of_encode_midV1 .private_
          (taggedHeaderBytesV1 "Visibility.Private" 0) ByteArray.empty ByteArray.empty 0
          (by decide) encodeVisibility_private_eq
  | .commitment =>
      refine ⟨taggedHeaderBytesV1 "Visibility.Commitment" 0,
        encodeVisibility_commitment_eq, ?_⟩
      simpa [ByteArray.append_empty] using
        decodeVisibility_of_encode_midV1 .commitment
          (taggedHeaderBytesV1 "Visibility.Commitment" 0) ByteArray.empty ByteArray.empty 0
          (by decide) encodeVisibility_commitment_eq

/-- Positive theorem: MidOffsetInvert package for Visibility. -/
theorem visibility_midOffsetInvert :
    MidOffsetInvertV1 encodeVisibilityV1 decodeVisibilityV1 :=
  midOffsetInvert_encodeVisibility_decodeVisibility

/-- Positive theorem: empty array mid-offset invert. -/
theorem array_zero_mid :
    decodeArray 10 (decodeVisibilityV1)
        ⟨encodeU32le 0, 0, 0⟩ =
      .ok (#[], ⟨encodeU32le 0, 4, 0⟩) := by
  simpa [ByteArray.append_empty] using
    decodeArray_of_encodeArray_zero_midV1 encodeVisibilityV1 decodeVisibilityV1 10
      ByteArray.empty ByteArray.empty 0

/-- Positive theorem: InvariantDecl MidOffsetInvert package. -/
theorem invariantDecl_midOffsetInvert :
    MidOffsetInvertV1 encodeInvariantDeclV1 decodeInvariantDeclV1 :=
  midOffsetInvert_encodeInvariantDecl_decodeInvariantDecl

/-- Positive theorem: empty constants table mid-offset invert. -/
theorem empty_constants_table_mid :
    decodeArray maxTableElements decodeConstantV1 ⟨encodeU32le 0, 0, 0⟩ =
      .ok (#[], ⟨encodeU32le 0, 4, 0⟩) := by
  have henc : encodeArray encodeConstantV1 (#[] : Array ConstantV1) = .ok (encodeU32le 0) :=
    encodeArray_zeroV1 encodeConstantV1
  simpa [ByteArray.append_empty, encodeU32le_sizeV1] using
    midOffsetInvert_empty_constants_table (encodeU32le 0) ByteArray.empty ByteArray.empty 0
      henc

/-- Positive theorem: empty ProgramRequirements mid-offset invert. -/
theorem empty_requirements_mid :
    ∃ b, encodeProgramRequirementsV1 { items := #[] } = .ok b ∧
      decodeProgramRequirementsV1 ⟨b, 0, 0⟩ =
        .ok ({ items := #[] }, ⟨b, b.size, 0⟩) := by
  -- Encode empty requirements via production path.
  have henc :
      encodeProgramRequirementsV1 { items := #[] } =
        .ok (taggedBytesV1 "ProgramRequirements" #[encodeU32le 0]) := by
    have hempty := encodeArray_zeroV1 encodeRequirementRequestV1
    have htag :=
      encodeTagged_eq_okV1 "ProgramRequirements" #[encodeU32le 0]
        (by decide) (by decide) (by decide) (by decide) (by decide)
    simp only [encodeProgramRequirementsV1, hempty, htag, Bind.bind, Pure.pure,
      Except.bind, Except.pure]
  refine ⟨taggedBytesV1 "ProgramRequirements" #[encodeU32le 0], henc, ?_⟩
  simpa [ByteArray.append_empty] using
    decodeProgramRequirements_empty_of_encode_midV1
      (taggedBytesV1 "ProgramRequirements" #[encodeU32le 0])
      ByteArray.empty ByteArray.empty 0 (by decide) henc

/-- Runtime smoke: Visibility + InvariantDecl + empty tables. -/
def run : IO Unit := do
  let cases : Array VisibilityV1 := #[.public_, .private_, .commitment]
  for vis in cases do
    match encodeVisibilityV1 vis with
    | .error e => throw <| IO.userError s!"encode failed: {repr e}"
    | .ok b =>
        match decodeVisibilityV1 ⟨b, 0, 0⟩ with
        | .error e => throw <| IO.userError s!"decode failed: {repr e}"
        | .ok (vis', c) =>
            expect (vis' == vis) s!"visibility mismatch"
            expect (c.offset == b.size) s!"cursor not at end"
  -- empty array
  match decodeArray 10 decodeVisibilityV1 ⟨encodeU32le 0, 0, 0⟩ with
  | .error e => throw <| IO.userError s!"empty array decode failed: {repr e}"
  | .ok (arr, c) =>
      expect (arr.size == 0) "expected empty array"
      expect (c.offset == 4) "expected post-header cursor"
  -- empty constants table
  match encodeArray encodeConstantV1 (#[] : Array ConstantV1) with
  | .error e => throw <| IO.userError s!"empty constants encode failed: {repr e}"
  | .ok b =>
      match decodeArray maxTableElements decodeConstantV1 ⟨b, 0, 0⟩ with
      | .error e => throw <| IO.userError s!"empty constants decode failed: {repr e}"
      | .ok (arr, c) =>
          expect (arr.size == 0) "expected empty constants"
          expect (c.offset == b.size) "constants cursor not at end"
  -- empty ProgramRequirements
  match encodeProgramRequirementsV1 { items := #[] } with
  | .error e => throw <| IO.userError s!"empty requirements encode failed: {repr e}"
  | .ok b =>
      match decodeProgramRequirementsV1 ⟨b, 0, 0⟩ with
      | .error e => throw <| IO.userError s!"empty requirements decode failed: {repr e}"
      | .ok (r, c) =>
          expect (r.items.size == 0) "expected empty requirements items"
          expect (c.offset == b.size) "requirements cursor not at end"
  -- InvariantDecl round-trip
  let inv : InvariantDeclV1 := { id := 0, name := "even", callableId := 1 }
  match encodeInvariantDeclV1 inv with
  | .error e => throw <| IO.userError s!"invariant encode failed: {repr e}"
  | .ok b =>
      match decodeInvariantDeclV1 ⟨b, 0, 0⟩ with
      | .error e => throw <| IO.userError s!"invariant decode failed: {repr e}"
      | .ok (inv', c) =>
          expect (inv'.name == inv.name) "invariant name mismatch"
          expect (inv'.id == inv.id) "invariant id mismatch"
          expect (inv'.callableId == inv.callableId) "invariant callable mismatch"
          expect (c.offset == b.size) "invariant cursor not at end"
  IO.println "Tests.Semantic.CodecInvertV1: OK"

end Tests.Semantic.CodecInvertV1
