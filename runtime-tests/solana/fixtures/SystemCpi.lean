import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- #121 production-code-generated test-preactivation fixture.
-- Native System Program CPI: transfer (unsigned) + createPdaAccount
-- (canonical PDA / invoke_signed, owner = current program).
-- State write before CPI and after CPI proves source order;
-- transferThenOverflow / createThenOverflow force full transaction
-- rollback after a successful System CPI. Not a product artifact path.
program SystemCpi where
  requires extension solana.cpi.accounts version "1.0.0"
    digest "sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020"

  state value : UInt64

  init(initial : UInt64) do
    value := initial

  entry transfer(
      payer : Principal,
      recipient : Principal,
      lamports : UInt64
  ) : UInt64 do
    value := value + 1
    call solana.system.transfer(payer, recipient, lamports)
    value := value + 2
    return value

  entry createPdaAccount(
      payer : Principal,
      pda : Principal,
      seedAuthority : Principal,
      seedTag : UInt64,
      bump : UInt8,
      lamports : UInt64,
      space : UInt64
  ) : UInt64 do
    value := value + 1
    call solana.system.createPdaAccount(
      payer, pda, seedAuthority, seedTag, bump, lamports, space)
    value := value + 2
    return value

  entry transferThenOverflow(
      payer : Principal,
      recipient : Principal,
      lamports : UInt64
  ) : UInt64 do
    value := value + 1
    call solana.system.transfer(payer, recipient, lamports)
    -- Successful System transfer then checked-add overflow: full rollback.
    value := value + 18446744073709551615
    return value

  entry createThenOverflow(
      payer : Principal,
      pda : Principal,
      seedAuthority : Principal,
      seedTag : UInt64,
      bump : UInt8,
      lamports : UInt64,
      space : UInt64
  ) : UInt64 do
    value := value + 1
    call solana.system.createPdaAccount(
      payer, pda, seedAuthority, seedTag, bump, lamports, space)
    -- Successful System create then checked-add overflow: full rollback
    -- of caller state, payer lamports, and PDA allocation.
    value := value + 18446744073709551615
    return value

  view inspect() : UInt64 do
    return value

end Examples
