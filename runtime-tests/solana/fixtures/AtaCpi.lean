import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- #123 production-code-generated test-preactivation fixture.
-- Classic Associated Token Account CreateIdempotent CPI. The ATA address is
-- derived from wallet/classic-Token/mint under the frozen ATA program. A state
-- write before and after CPI proves source order; the overflow handler forces
-- full rollback of payer lamports, the newly created ATA, and caller state.
-- Catalog ATA/Token artifact bindings remain absent and product sync remains
-- activationDenied. This fixture is not proof-forge.output.v1.
program AtaCpi where
  requires extension solana.cpi.accounts version "1.0.0"
    digest "sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020"

  state value : UInt64

  init(initial : UInt64) do
    value := initial

  entry createIdempotent(
      payer : Principal,
      ata : Principal,
      wallet : Principal,
      mint : Principal
  ) : UInt64 do
    value := value + 1
    call solana.ata.createIdempotent(payer, ata, wallet, mint)
    value := value + 2
    return value

  entry createIdempotentThenOverflow(
      payer : Principal,
      ata : Principal,
      wallet : Principal,
      mint : Principal
  ) : UInt64 do
    value := value + 1
    call solana.ata.createIdempotent(payer, ata, wallet, mint)
    value := value + 18446744073709551615
    return value

  view inspect() : UInt64 do
    return value

end Examples
