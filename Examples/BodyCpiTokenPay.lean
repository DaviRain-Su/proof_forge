import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0030 / ADR-0032 M4b multi-role demo: multi-block if +
-- pf.assets.token.transfer on sole rail `solana-sbpf-cpi-elf-v1`
-- (hasSites ∧ needsFullBody, single CPI site, no Map).
--
-- Engineering path (M4b multi-role token.transfer):
--   * full-body LowerSemantic for if/CFG + UInt64 state
--   * outer role walk (state + mint + dst + caller + programs + ATAs + vault)
--   * ATA createIdempotent ×2 + transferCheckedPda invoke_signed
--   * synthesize tag `m4b-token-transfer-multi-role` / frameMode `unifiedCpi`
--
-- Prefer this vector over MiniAmmAssets when validating token multi-role CPI
-- without dense Principal Map stack pressure (MiniAmmAssets dual-mint Map
-- remains empty-meta residual until Map temp + multi-site stamping close).
--
-- Not imported by Examples.lean (target-specific product pin).
-- Mollusk: runtime-tests/solana/tests/body_cpi_token_pay.rs (11/11 engineering
-- differential: existing/fresh ATA transfer, skip-CPI else, rollback, negatives).
-- Non-formal, non-mainnet.
program BodyCpiTokenPay where
  requires extension pf.assets version "1.1.0"
    digest "sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9"

  state paid : UInt64

  init() do
    paid := 0

  entry credit(x : UInt64) : UInt64 do
    paid := paid + x
    return paid

  -- Pre-fund vault ATA off-chain / by protocol; payout mint→to when paid ≥ amount.
  entry pay(mint : Principal, to : Principal, amount : UInt64) : UInt64 do
    assert amount > 0
    if paid >= amount then
      paid := paid - amount
      call pf.assets.token.transfer(mint, to, amount)
      return paid
    else
      return paid

  view get() : UInt64 do
    return paid

end Examples
