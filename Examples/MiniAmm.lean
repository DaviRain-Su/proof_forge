import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0030 E4 MiniAMM **vault-internal math** demo (M0).
-- Constant-product AMM with internal LP share accounting:
--   * reserve0 / reserve1 / totalSupply / scratch / scratch2 : UInt64
--   * balances : Map Principal UInt64 (dense Principal-key pilot, cap-4)
-- No pf.assets transfer / balanceOfSelf here — deposits and swaps update
-- reserves directly (portable math / Anvil-Mollusk vectors without ERC-20/SPL).
-- Real-asset product surface: `Examples/MiniAmmAssets.lean` (ADR-0033 / M3).
--
-- Formalization (RESEARCH-023): platform L0/L1/L2 stack is generic; this file is
-- the **first business instance** for L1 (vault-internal). Stays **deployable**
-- (no nonempty inv — EVM/Solana materialize FC). L0 sample surface (any program
-- can copy the shape): `Examples/MiniAmmProofSurface.lean`. L1 MiniAmm sketch:
-- `ProofForgeV2.Semantic.MiniAmmSafetySketchV1` (instance, not the whole stack).
--
-- Permission / identity: LP shares keyed by `context.caller` (ADR-0031 S1).
-- Swap is open to any caller (updates reserves only).
--
-- Liquidity math (fee-free, not Uniswap V2 parity):
--   * first deposit (totalSupply == 0): LP = amount0 (no sqrt)
--   * later deposit:
--       LP = min(amount0 * totalSupply / reserve0,
--                amount1 * totalSupply / reserve1)
--   * swap0to1(amountIn, amountOutMin):
--       out = amountIn * r1 / (r0 + amountIn); require out >= amountOutMin
--   * swap1to0(amountIn, amountOutMin): symmetric
--   * removeLiquidity(lpAmount):
--       a0 = lp * r0 / totalSupply; a1 = lp * r1 / totalSupply;
--       burn caller's LP; shrink reserves; return a0
-- `scratch` / `scratch2` hold intermediates across Map StateStore effect
-- boundaries (Solana/EVM segment discipline: pure lets/computed binders
-- cannot be Map IndexSet RHS or cross effect sinks). Checked mul/div on
-- UInt64: overflow / zero-divisor reverts. Intermediate products must fit
-- UInt64.
--
-- Shared vectors: Tests.Semantic.MiniAmmVectorsV1
-- Solana product pin: Tests.Product.MiniAmmSolanaV1
-- Solana Mollusk fixture: runtime-tests/solana/fixtures/MiniAmmHybrid.lean
-- EVM host-optional: scripts/evm_mini_amm_anvil_smoke.sh
-- Engineering only: non-formal. M2 EVM compact Principal Map keeps Yul/creation
-- under ordinary solc + EIP-3860 (no code-size override required for this demo).
program MiniAmm where
  state reserve0 : UInt64
  state reserve1 : UInt64
  state totalSupply : UInt64
  state scratch : UInt64
  state scratch2 : UInt64
  state balances : Map Principal UInt64

  init() do
    reserve0 := 0
    reserve1 := 0
    totalSupply := 0
    scratch := 0
    scratch2 := 0
    balances := Map.empty()

  -- Mint LP to context.caller. Returns minted LP amount.
  entry addLiquidity(amount0 : UInt64, amount1 : UInt64) : UInt64 do
    assert amount0 > 0
    assert amount1 > 0
    if totalSupply == 0 then
      scratch := amount0
    else
      assert reserve0 > 0
      assert reserve1 > 0
      -- lp0 → scratch, lp1 → scratch2, then min into scratch
      scratch := amount0 * totalSupply / reserve0
      scratch2 := amount1 * totalSupply / reserve1
      if scratch2 < scratch then
        scratch := scratch2
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

  -- Constant-product swap token0 → token1. Vault-internal only.
  entry swap0to1(amountIn : UInt64, amountOutMin : UInt64) : UInt64 do
    assert amountIn > 0
    assert reserve0 > 0
    assert reserve1 > 0
    scratch := amountIn * reserve1 / (reserve0 + amountIn)
    assert scratch > 0
    assert scratch < reserve1
    assert scratch >= amountOutMin
    reserve0 := reserve0 + amountIn
    reserve1 := reserve1 - scratch
    return scratch

  -- Constant-product swap token1 → token0. Vault-internal only.
  entry swap1to0(amountIn : UInt64, amountOutMin : UInt64) : UInt64 do
    assert amountIn > 0
    assert reserve0 > 0
    assert reserve1 > 0
    scratch := amountIn * reserve0 / (reserve1 + amountIn)
    assert scratch > 0
    assert scratch < reserve0
    assert scratch >= amountOutMin
    reserve1 := reserve1 + amountIn
    reserve0 := reserve0 - scratch
    return scratch

  -- Burn `lpAmount` of caller's LP; shrink both reserves. Returns amount0 out.
  entry removeLiquidity(lpAmount : UInt64) : UInt64 do
    assert lpAmount > 0
    assert totalSupply > 0
    match balances[context.caller] with
    | Option.some(v) => do
      assert v >= lpAmount
      -- Burn LP first (match binder v cannot be used after later state stores).
      balances[context.caller] := v - lpAmount
      -- a0 → scratch, a1 → scratch2 from pre-burn reserves/totalSupply.
      scratch := lpAmount * reserve0 / totalSupply
      scratch2 := lpAmount * reserve1 / totalSupply
      reserve0 := reserve0 - scratch
      reserve1 := reserve1 - scratch2
      totalSupply := totalSupply - lpAmount
      return scratch
    | _ => do
      assert false
      return 0

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
