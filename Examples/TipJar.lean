import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0029 Phase A product demo: portable tip-jar over `pf.assets`.
-- Ordinary product path builds only for target `quint` (the sole profile
-- that advertises exact `extension.pf-assets` + `effect.synchronous-call`).
-- Other targets fail closed at requirement resolve (PF-REQ-UNSUPPORTED).
-- Model-layer evidence only: non-deployable, non-formal, not mainnet.
-- Not imported by Examples.lean (target-specific, like TransferSol).
program TipJar where
  requires extension pf.assets version "1.0.0"
    digest "sha256:97dfde7f7df228230828db4273086224bc28a4bc88c2f25457eaf0aee22aeeed"

  state tips : UInt64

  init(initial : UInt64) do
    tips := initial

  entry tip(dst : Principal, amount : UInt64) : UInt64 do
    call pf.assets.native.deposit(amount)
    call pf.assets.native.transfer(dst, amount)
    tips := tips + amount
    return tips

  view get() : UInt64 do
    return tips

end Examples
