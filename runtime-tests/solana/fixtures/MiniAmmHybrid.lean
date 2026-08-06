import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0030 E4 + ADR-0032 U1 Mollusk fixture (product path ELF under
-- solana-sbpf-cpi-elf-v1 full-body hybrid). Same math as Examples/MiniAmm.lean.
--
-- Vault-internal constant-product AMM with internal LP share accounting:
--   * reserve0 / reserve1 / totalSupply / scratch : UInt64
--   * balances : Map Principal UInt64 (dense Principal-key pilot, cap-4)
-- No pf.assets transfer — deposits and swaps update reserves directly.
-- Hybrid has zero CPI sites (no sol_invoke*). Accounts: state + pf_caller
-- (from cpi-plan accountRoles; context.caller = pf_caller signer Principal).
--
-- Liquidity math (honest subset, not Uniswap V2 parity):
--   * first deposit (totalSupply == 0): LP minted = amount0 (no sqrt)
--   * later deposit: LP = amount0 * totalSupply / reserve0
--     (single-sided formula; amount1 still credited to reserve1)
--   * swap0to1: amountOut = amountIn * r1 / (r0 + amountIn)  (fee-free)
-- `scratch` holds the minted LP across the Map StateStore effect boundary.
-- Checked mul/div on UInt64: overflow/zero-divisor reverts.
--
-- Engineering only: non-formal, non-mainnet. Host-optional Mollusk gate:
--   runtime-tests/solana/tests/miniamm_hybrid.rs
-- Residual (documented in the Rust suite): full-body hybrid EmitSbpfAsm still
-- entrypoint-hardcodes num_accounts==1 while caller-admitting handlers require
-- num_accounts==2; multi-account layout hardening is a separate EmitSbpfAsm
-- follow-up. Product build/plan/IR pins always run; success-path Mollusk is
-- gated on that residual being closed.
program MiniAmmHybrid where
  state reserve0 : UInt64
  state reserve1 : UInt64
  state totalSupply : UInt64
  state scratch : UInt64
  state balances : Map Principal UInt64

  init() do
    reserve0 := 0
    reserve1 := 0
    totalSupply := 0
    scratch := 0
    balances := Map.empty()

  -- Mint LP to context.caller. Returns minted LP amount.
  entry addLiquidity(amount0 : UInt64, amount1 : UInt64) : UInt64 do
    assert amount0 > 0
    assert amount1 > 0
    if totalSupply == 0 then
      scratch := amount0
    else
      assert reserve0 > 0
      scratch := amount0 * totalSupply / reserve0
    assert scratch > 0
    match balances[context.caller] with
    | Option.some(v) => do
      balances[context.caller] := v + scratch
      totalSupply := totalSupply + scratch
      reserve0 := reserve0 + amount0
      reserve1 := reserve1 + amount1
      return scratch
    | _ => do
      balances[context.caller] := scratch
      totalSupply := totalSupply + scratch
      reserve0 := reserve0 + amount0
      reserve1 := reserve1 + amount1
      return scratch

  -- Constant-product swap token0 → token1. Updates reserves only
  -- (no external token transfer). Returns amountOut via scratch.
  entry swap0to1(amountIn : UInt64) : UInt64 do
    assert amountIn > 0
    assert reserve0 > 0
    assert reserve1 > 0
    scratch := amountIn * reserve1 / (reserve0 + amountIn)
    assert scratch > 0
    assert scratch < reserve1
    reserve0 := reserve0 + amountIn
    reserve1 := reserve1 - scratch
    return scratch

  view getReserve0() : UInt64 do
    return reserve0

  view getReserve1() : UInt64 do
    return reserve1

  view getTotalSupply() : UInt64 do
    return totalSupply

  view balanceOf(who : Principal) : UInt64 do
    match balances[who] with
    | Option.some(v) => do
      return v
    | _ => do
      return 0

end Examples
