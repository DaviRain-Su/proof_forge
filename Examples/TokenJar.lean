import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0030 E1a product demo: portable token tip-jar over `pf.assets`.
-- `tipToken(mint, dst, amount)` transfers `amount` of ERC-20 `mint` tokens
-- from the contract's own balance to `dst` and increments a tip counter.
-- The token contract address is a **controlled dynamic callee** (catalog
-- token family only; generic dynamic callee stays fail closed). EVM vault
-- = contract's own ERC-20 balance (no extra state).
-- Not imported by Examples.lean (target-specific, like TipJar/TransferSol).
-- Engineering only: non-formal; Anvil runtime gate is main-agent merge.
program TokenJar where
  requires extension pf.assets version "1.0.0"
    digest "sha256:97dfde7f7df228230828db4273086224bc28a4bc88c2f25457eaf0aee22aeeed"

  state tips : UInt64

  init(initial : UInt64) do
    tips := initial

  entry tipToken(mint : Principal, dst : Principal, amount : UInt64) : UInt64 do
    call pf.assets.token.transfer(mint, dst, amount)
    tips := tips + amount
    return tips

  view get() : UInt64 do
    return tips

end Examples