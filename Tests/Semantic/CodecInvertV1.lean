/-
  Tests.Semantic.CodecInvertV1 — mig-a1 foundation: MidOffsetInvert,
  Visibility complete leaf, array zero helper, RootFieldInvert package shape.

  Does not claim full parametric decode∘encode for arbitrary programs.
-/
import ProofForgeV2.Semantic.Wire.CodecInvertV1
import ProofForgeV2.Semantic.WireV1

namespace Tests.Semantic.CodecInvertV1

open ProofForgeV2.Semantic.WireV1

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

/-- Runtime smoke: Visibility round-trip bytes. -/
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
  IO.println "Tests.Semantic.CodecInvertV1: OK"

end Tests.Semantic.CodecInvertV1
