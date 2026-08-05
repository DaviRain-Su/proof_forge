import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0029 Phase C2 product demo: portable tip-jar over `pf.assets` async
-- variant for NEAR. Ordinary product path builds only for target `near`
-- (the sole profile that advertises exact `extension.pf-assets` with a
-- fire-and-forget Promise transfer). NEAR has no synchronous external
-- transfer, so `pf.assets.native.transfer` stays permanently fail closed
-- there and this demo spells the async variant. Other targets fail closed
-- on `pf.assets.native.transferAsync` (sync-bound lanes do not offer the
-- weak async variant). Engineering only: non-formal, non-mainnet.
-- Not imported by Examples.lean (target-specific, like TipJar/TransferSol).
program TipJarAsync where
  requires extension pf.assets version "1.0.0"
    digest "sha256:97dfde7f7df228230828db4273086224bc28a4bc88c2f25457eaf0aee22aeeed"

  state tips : UInt64

  init(initial : UInt64) do
    tips := initial

  entry tip(dst : Principal, amount : UInt64) : UInt64 do
    call pf.assets.native.deposit(amount)
    call pf.assets.native.transferAsync(dst, amount)
    tips := tips + amount
    return tips

  view get() : UInt64 do
    return tips

end Examples
