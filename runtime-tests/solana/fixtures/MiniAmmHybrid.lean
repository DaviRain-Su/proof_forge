import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0030 E4 + ADR-0032 U1 Mollusk fixture (product path ELF under
-- solana-sbpf-cpi-elf-v1 full-body hybrid). **Same math as Examples/MiniAmm.lean**
-- (M0 vault-internal milestone).
--
-- Vault-internal constant-product AMM with internal LP share accounting:
--   * reserve0 / reserve1 / totalSupply / scratch / scratch2 : UInt64
--   * balances : Map Principal UInt64 (dense Principal-key pilot, cap-4)
-- No pf.assets transfer — deposits and swaps update reserves directly.
-- Hybrid has zero CPI sites (no sol_invoke*). Accounts: state + pf_caller
-- (context.caller = pf_caller signer Principal).
--
-- Liquidity math (fee-free, not Uniswap V2 parity):
--   * first deposit: LP = amount0 (no sqrt)
--   * later: LP = min(amount0*ts/r0, amount1*ts/r1)
--   * swap0to1 / swap1to0 with amountOutMin
--   * removeLiquidity(lpAmount) burns caller LP, returns amount0 out
-- `scratch` / `scratch2` hold intermediates across Map StateStore boundaries.
-- Checked mul/div on UInt64: overflow/zero-divisor reverts.
--
-- Engineering only: non-formal, non-mainnet. Host-optional Mollusk gate:
--   runtime-tests/solana/tests/miniamm_hybrid.rs
-- Shared vectors: Tests.Semantic.MiniAmmVectorsV1
program MiniAmmHybrid where
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

  entry addLiquidity(amount0 : UInt64, amount1 : UInt64) : UInt64 do
    assert amount0 > 0
    assert amount1 > 0
    if totalSupply == 0 then
      scratch := amount0
    else
      assert reserve0 > 0
      assert reserve1 > 0
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

  entry removeLiquidity(lpAmount : UInt64) : UInt64 do
    assert lpAmount > 0
    assert totalSupply > 0
    match balances[context.caller] with
    | Option.some(v) => do
      assert v >= lpAmount
      balances[context.caller] := v - lpAmount
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
