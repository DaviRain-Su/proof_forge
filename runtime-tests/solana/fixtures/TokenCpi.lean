import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- #122 production-code-generated test-preactivation fixture.
-- Classic SPL Token CPI: transferChecked (external authority) +
-- transferCheckedPda (canonical current-program PDA authority /
-- invoke_signed). State write before CPI and after CPI proves source
-- order; *ThenOverflow forces full transaction rollback after a
-- successful Token CPI (balances + caller state).
--
-- Callee: catalog package token-classic-v1 (classic SPL Token program@v9.0.0).
-- Runtime ELF is a vendored source-built program@v9.0.0 test artifact
-- (runtime-tests/solana/token/token_classic_v1.so). Catalog
-- artifactBinding remains absent; profile boundary is testPreactivation +
-- activationDenied. Not proof-forge.output.v1 / not activated product sync.
program TokenCpi where
  requires extension solana.cpi.accounts version "1.0.0"
    digest "sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020"

  state value : UInt64

  init(initial : UInt64) do
    value := initial

  entry transferChecked(
      source : Principal,
      mint : Principal,
      destination : Principal,
      authority : Principal,
      amount : UInt64,
      decimals : UInt8
  ) : UInt64 do
    value := value + 1
    call solana.token.transferChecked(
      source, mint, destination, authority, amount, decimals)
    value := value + 2
    return value

  entry transferCheckedPda(
      source : Principal,
      mint : Principal,
      destination : Principal,
      authorityPda : Principal,
      seedAuthority : Principal,
      seedTag : UInt64,
      bump : UInt8,
      amount : UInt64,
      decimals : UInt8
  ) : UInt64 do
    value := value + 1
    call solana.token.transferCheckedPda(
      source, mint, destination, authorityPda,
      seedAuthority, seedTag, bump, amount, decimals)
    value := value + 2
    return value

  entry transferCheckedThenOverflow(
      source : Principal,
      mint : Principal,
      destination : Principal,
      authority : Principal,
      amount : UInt64,
      decimals : UInt8
  ) : UInt64 do
    value := value + 1
    call solana.token.transferChecked(
      source, mint, destination, authority, amount, decimals)
    -- Successful Token transfer then checked-add overflow: full rollback.
    value := value + 18446744073709551615
    return value

  entry transferCheckedPdaThenOverflow(
      source : Principal,
      mint : Principal,
      destination : Principal,
      authorityPda : Principal,
      seedAuthority : Principal,
      seedTag : UInt64,
      bump : UInt8,
      amount : UInt64,
      decimals : UInt8
  ) : UInt64 do
    value := value + 1
    call solana.token.transferCheckedPda(
      source, mint, destination, authorityPda,
      seedAuthority, seedTag, bump, amount, decimals)
    -- Successful PDA-authority transfer then overflow: full rollback of
    -- caller state and both token-account balances.
    value := value + 18446744073709551615
    return value

  view inspect() : UInt64 do
    return value

end Examples
