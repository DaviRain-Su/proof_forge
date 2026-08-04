import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- #124 production-code-generated test-preactivation fixture.
-- Composite escrow CPI: native System createPdaAccount + classic ATA
-- createIdempotent (vault ATA under authority PDA) + classic Token
-- transferChecked (deposit) + transferCheckedPda (release/refund under
-- current-program-tagged-v1 PDA authority / invoke_signed).
--
-- Handler IDs are dense source order:
--   0 init
--   1 initializeVault
--   2 deposit
--   3 release
--   4 refund
--   5 initializeThenOverflow
--   6 depositThenOverflow
--   7 releaseThenOverflow
--   8 refundThenOverflow
--   9 inspect
--
-- State write before CPI and after CPI proves source order; *ThenOverflow
-- forces full single-outer-instruction rollback after successful inner CPI
-- (initialize rolls back System PDA + ATA; deposit/release/refund roll back
-- Token balances + caller state). Caller program id pin is all-0x59.
-- Catalog ATA/Token artifactBinding remains absent; boundary is
-- testPreactivation + activationDenied. Not proof-forge.output.v1 / not
-- activated product sync.
program EscrowCpi where
  requires extension solana.cpi.accounts version "1.0.0"
    digest "sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020"

  state value : UInt64

  init(initial : UInt64) do
    value := initial

  entry initializeVault(
      payer : Principal,
      authorityPda : Principal,
      seedAuthority : Principal,
      seedTag : UInt64,
      bump : UInt8,
      vaultAta : Principal,
      mint : Principal,
      pdaLamports : UInt64,
      pdaSpace : UInt64
  ) : UInt64 do
    value := value + 1
    call solana.system.createPdaAccount(
      payer, authorityPda, seedAuthority, seedTag, bump, pdaLamports, pdaSpace)
    call solana.ata.createIdempotent(payer, vaultAta, authorityPda, mint)
    value := value + 2
    return value

  entry deposit(
      source : Principal,
      mint : Principal,
      vaultAta : Principal,
      userAuthority : Principal,
      amount : UInt64,
      decimals : UInt8
  ) : UInt64 do
    value := value + 1
    call solana.token.transferChecked(
      source, mint, vaultAta, userAuthority, amount, decimals)
    value := value + 2
    return value

  entry release(
      vaultAta : Principal,
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
      vaultAta, mint, destination, authorityPda,
      seedAuthority, seedTag, bump, amount, decimals)
    value := value + 2
    return value

  entry refund(
      vaultAta : Principal,
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
      vaultAta, mint, destination, authorityPda,
      seedAuthority, seedTag, bump, amount, decimals)
    value := value + 2
    return value

  entry initializeThenOverflow(
      payer : Principal,
      authorityPda : Principal,
      seedAuthority : Principal,
      seedTag : UInt64,
      bump : UInt8,
      vaultAta : Principal,
      mint : Principal,
      pdaLamports : UInt64,
      pdaSpace : UInt64
  ) : UInt64 do
    value := value + 1
    call solana.system.createPdaAccount(
      payer, authorityPda, seedAuthority, seedTag, bump, pdaLamports, pdaSpace)
    call solana.ata.createIdempotent(payer, vaultAta, authorityPda, mint)
    -- Successful System+ATA then checked-add overflow: full rollback of
    -- caller state, payer lamports, new PDA, and new vault ATA.
    value := value + 18446744073709551615
    return value

  entry depositThenOverflow(
      source : Principal,
      mint : Principal,
      vaultAta : Principal,
      userAuthority : Principal,
      amount : UInt64,
      decimals : UInt8
  ) : UInt64 do
    value := value + 1
    call solana.token.transferChecked(
      source, mint, vaultAta, userAuthority, amount, decimals)
    value := value + 18446744073709551615
    return value

  entry releaseThenOverflow(
      vaultAta : Principal,
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
      vaultAta, mint, destination, authorityPda,
      seedAuthority, seedTag, bump, amount, decimals)
    value := value + 18446744073709551615
    return value

  entry refundThenOverflow(
      vaultAta : Principal,
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
      vaultAta, mint, destination, authorityPda,
      seedAuthority, seedTag, bump, amount, decimals)
    value := value + 18446744073709551615
    return value

  view inspect() : UInt64 do
    return value

end Examples
