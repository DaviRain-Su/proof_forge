import ProofForge.Frontend.Authored.Normalize

/-! # Authored ContractSpec normalization

This is the sole production boundary allowed to know how the current compiler
exchange format reaches checked Canonical Core. Callers consume this neutral
normalization API and never import its implementation directly.
-/

namespace ProofForge.Frontend.ContractSpec

/-- Normalize the authored compiler exchange format into a checked canonical
bundle. Every normalization or validation failure remains terminal. -/
def normalize (spec : ProofForge.Contract.ContractSpec) :
    Except String ProofForge.IR.Canonical.CanonicalBundle :=
  match ProofForge.Frontend.Authored.Normalize.normalizeContractSpec spec with
  | .ok bundle => .ok bundle
  | .error error => .error s!"canonical: source normalization failed: {repr error}"

end ProofForge.Frontend.ContractSpec
