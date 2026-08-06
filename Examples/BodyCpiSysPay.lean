import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0032 U1 / P3-e multi-role demo: multi-block if + solana.system.transfer
-- on sole rail `solana-sbpf-cpi-elf-v1` (hasSites ∧ needsFullBody).
--
-- Engineering path (P3-e multi-role system.transfer):
--   * full-body LowerSemantic for if/CFG + state
--   * outer role table walk (state + payer + recipient + system program)
--   * AccountMeta fill + `sol_invoke_signed_c` with native System program id
--     (32 zeros) and SystemInstruction::Transfer 12B data packing
--   * synthesize tag `p3e-system-transfer-multi-role` / frameMode `unifiedCpi`
--
-- Prefer this vector over pf.assets vault CPI when validating System multi-role
-- CPI without Map/scratch complexity. Map+empty-meta remains BodyCpiMapTip.
--
-- Not imported by Examples.lean (target-specific product pin).
-- Mollusk: runtime-tests/solana/tests/body_cpi_sys_pay.rs (engineering differential).
-- Non-formal, non-mainnet.
program BodyCpiSysPay where
  requires extension solana.cpi.accounts version "1.0.0"
    digest "sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020"

  state bal : UInt64

  init() do
    bal := 0

  entry credit(x : UInt64) : UInt64 do
    bal := bal + x
    return bal

  entry pay(payer : Principal, recipient : Principal, amount : UInt64) : UInt64 do
    assert amount > 0
    if bal >= amount then
      bal := bal - amount
      call solana.system.transfer(payer, recipient, amount)
      return bal
    else
      return bal

  view get() : UInt64 do
    return bal

end Examples
