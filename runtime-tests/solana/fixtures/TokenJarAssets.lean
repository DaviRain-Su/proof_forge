import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0030 E1b: TokenJarAssets — runtime fixture for Mollusk product acceptance.
-- Same structure as Examples/TokenJar.lean but used by runtime-tests/solana.
-- `tipToken` calls `pf.assets.token.transfer(mint, dst, amount)` → classic SPL
-- `transferChecked` (vault ATA → dst ATA) under vault PDA authority.
-- Runtime test: create mint, fund vault ATA, tipToken success/rollback/negatives.
-- Not a mainnet contract; production-code-generated test fixture only.
program TokenJarAssets where
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