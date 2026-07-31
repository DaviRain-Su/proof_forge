import ProofForgeV2.Semantic.InvariantFoundationV1

/-
  ProofForgeV2.Semantic.InvariantABI — public invariant proof ABI façade.

  The state carrier, canonical state codec/defaults, and StateConformsV1 are
  defined by the lower InvariantFoundationV1 module under this same namespace.
  Keeping this façade above that foundation leaves an acyclic dependency path
  for the later ABI-owned evalInvariantV1 / InvariantTheoremV1 definitions.
-/
