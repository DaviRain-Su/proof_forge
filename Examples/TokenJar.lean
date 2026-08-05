import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0030 E1 product demo: portable token tip-jar over `pf.assets`.
-- `tipToken(mint, dst, amount)` transfers `amount` of the token `mint`
-- from the program's self vault to `dst` and increments a tip counter.
-- Chain-neutral source: each target's catalog/lowering decides the
-- realization — EVM: ERC-20 `transfer(address,uint256)` via controlled
-- dynamic callee (catalog token family only); Solana: classic SPL
-- `transferChecked` from the vault ATA (PDA `invoke_signed`). Sync-only
-- lanes: NEAR token QNs stay fail closed.
-- Not imported by Examples.lean (target-specific, like TipJar/TransferSol).
-- Engineering only: non-formal; runtime gates are Anvil/Mollusk.
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
