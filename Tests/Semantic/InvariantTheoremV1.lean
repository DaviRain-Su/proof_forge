/-
  Tests.Semantic.InvariantTheoremV1 — compile-time slot for the canonical
  invariant ABI kernel theorem.

  Closed `InvariantTheoremV1` on `⟨canonicalBytes⟩` previously required a
  transport decode witness; that unsafe/choice path was removed from
  `Tests.Semantic.InvariantABI` (Stage D usage-closure now closes structure
  at compile time; encode identity remains `encodeData_canonicalBytes`).

  Runtime IO in `Tests.Semantic.InvariantABI` and `Tests.Semantic.ProofBridgeV1`
  still exercise production encode/decode/validate on the same closed fixture.
-/
import Tests.Semantic.InvariantABI

namespace Tests.Semantic.InvariantABI.CanonicalInvariantFixtureV1

end Tests.Semantic.InvariantABI.CanonicalInvariantFixtureV1
