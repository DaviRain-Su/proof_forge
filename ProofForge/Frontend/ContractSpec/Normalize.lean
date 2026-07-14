import ProofForge.IR.Legacy.Adapter

/-! # ContractSpec compatibility normalization

This is the sole production boundary allowed to know how the v1 compiler
exchange format reaches checked Canonical Core. Callers consume the neutral
normalization API and never import the legacy adapter directly.
-/

namespace ProofForge.Frontend.ContractSpec

/-- Normalize the v1 compiler exchange format into a checked canonical bundle.
Every adapter or validation failure remains terminal. -/
def normalize (spec : ProofForge.Contract.ContractSpec) :
    Except String ProofForge.IR.Canonical.CanonicalBundle :=
  match ProofForge.IR.Legacy.Adapter.adaptLegacy spec with
  | .ok bundle => .ok bundle
  | .error error => .error s!"canonical: source normalization failed: {repr error}"

end ProofForge.Frontend.ContractSpec
