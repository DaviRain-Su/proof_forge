import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

/-- Phase-1 privacy boundary vector (APP-1 / FR-DoD).

    Four private UInt64 params summed into a **public** return is intentionally
    **disclosure-illegal** on the product path (`PF-VIS-001` private→public).
    Continuous product tests must fail closed here and must not emit
    manifest/ABI/logs carrying raw private values.

    Legal private-witness shapes (private param not flowing to a public sink)
    are covered by Noir PrivParam product paths — not this vector. -/
program PrivateSum4 where
  entry sum(private a : UInt64, private b : UInt64, private c : UInt64, private d : UInt64) : UInt64 do
    return a + b + c + d

end Examples
