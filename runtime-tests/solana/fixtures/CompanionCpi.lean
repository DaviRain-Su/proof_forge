import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- #119 production-code-generated test-preactivation fixture.
-- Single-block straight-line handlers with companion.invoke / companion.fail only.
-- State write before CPI, CPI, post-call state write prove source order and
-- top-level rollback on inner failure. Not a product artifact path.
program CompanionCpi where
  requires extension solana.cpi.accounts version "1.0.0"
    digest "sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020"

  state value : UInt64

  init(initial : UInt64) do
    value := initial

  entry invokeOnce(account : Principal, delta : UInt64) : UInt64 do
    value := value + 1
    call solana.companion.invoke(account, delta)
    value := value + 2
    return value

  entry failOnce(account : Principal, delta : UInt64) : UInt64 do
    value := value + 1
    call solana.companion.fail(account, delta)
    value := value + 2
    return value

  view inspect() : UInt64 do
    return value

end Examples
