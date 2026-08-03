import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- #120 production-code-generated test-preactivation fixture.
-- Canonical PDA / bump / invoke_signed against pinned companion-v1.
-- State write before CPI, signed CPI, post-call state write prove source
-- order; invokeSignedThenOverflow forces full transaction rollback after a
-- successful inner CPI. Not a product artifact path.
program CompanionPdaCpi where
  requires extension solana.cpi.accounts version "1.0.0"
    digest "sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020"

  state value : UInt64

  init(initial : UInt64) do
    value := initial

  entry invokeSigned(
      account : Principal,
      authorityPda : Principal,
      seedAuthority : Principal,
      seedTag : UInt64,
      bump : UInt8,
      delta : UInt64
  ) : UInt64 do
    value := value + 1
    call solana.companion.invokeSigned(
      account, authorityPda, seedAuthority, seedTag, bump, delta)
    value := value + 2
    return value

  entry invokeSignedThenOverflow(
      account : Principal,
      authorityPda : Principal,
      seedAuthority : Principal,
      seedTag : UInt64,
      bump : UInt8,
      delta : UInt64
  ) : UInt64 do
    value := value + 1
    call solana.companion.invokeSigned(
      account, authorityPda, seedAuthority, seedTag, bump, delta)
    -- Successful CPI then checked-add overflow: full transaction rollback.
    value := value + 18446744073709551615
    return value

  view inspect() : UInt64 do
    return value

end Examples
