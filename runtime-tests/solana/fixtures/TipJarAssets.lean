import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0029 Phase B1 Mollusk fixture vector (product path ELF under
-- solana-sbpf-cpi-elf-v1). Same shape as Examples/TipJar.lean.
-- Mollusk harness integration is owned by main-agent merge
-- (scripts/solana_runtime_test.sh / tests/tipjar_assets.rs); this file is the
-- continuous fixture source for that gate.
--
-- Runtime expectations (for future Mollusk suite):
--   * init(initial): state tips = initial; vault PDA may be absent pre-deposit
--   * tip(dst, amount): ensure vault PDA (payer=caller outer signer), System
--     transfer caller→vault, System transfer vault→dst (invoke_signed,
--     seeds proof-forge:vault:v1 + bump 255..1), tips += amount
--   * insufficient caller lamports → full snapshot rollback
--   * vault underfund on transfer → System CPI fail + full rollback
--   * success path: caller debit, vault net-zero (deposit then transfer same
--     amount), dst credit, tips increased, source order preserved
program TipJarAssets where
  requires extension pf.assets version "1.1.0"
    digest "sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9"

  state tips : UInt64

  init(initial : UInt64) do
    tips := initial

  entry tip(dst : Principal, amount : UInt64) : UInt64 do
    call pf.assets.native.deposit(amount)
    call pf.assets.native.transfer(dst, amount)
    tips := tips + amount
    return tips

  view get() : UInt64 do
    return tips

end Examples
