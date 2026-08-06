import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0033 / E4 MiniAMM **real-asset** product surface (M3 freeze).
-- Same constant-product math as `Examples/MiniAmm.lean` (M0), plus:
--   * `mint0` / `mint1` Principal state (init)
--   * vault credit = balanceOfSelf(mint) - reserve (pre-fund model)
--   * successful swaps / removeLiquidity pay out via pf.assets.token.transfer
--
-- Funding path (honest; no transferFrom):
--   1. User (or router) transfers token0/token1 into this program's vault
--      in a **prior** top-level transaction.
--   2. User calls addLiquidity / swap* / removeLiquidity.
--   3. If the AMM entry reverts, pre-funded tokens remain in the vault as
--      unaccounted credit — they are NOT auto-refunded with the entry.
-- See docs/adr/0033-miniamm-asset-transaction-model.md.
--
-- LP shares: Map Principal UInt64 keyed by context.caller (cap-4 pilot).
-- Engineering only: non-formal; M4/M5 own dual-mint runtime gates.
program MiniAmmAssets where
  requires extension pf.assets version "1.1.0"
    digest "sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9"

  state mint0 : Principal
  state mint1 : Principal
  state reserve0 : UInt64
  state reserve1 : UInt64
  state totalSupply : UInt64
  state scratch : UInt64
  state scratch2 : UInt64
  state balances : Map Principal UInt64

  -- Zero-arg init (two Principal ctor params = 18 ABI words → solc StackTooDeep
  -- on Yul ctor lets). Mints are set once via `configure` before any liquidity.
  init() do
    reserve0 := 0
    reserve1 := 0
    totalSupply := 0
    scratch := 0
    scratch2 := 0
    balances := Map.empty()

  -- One-shot mint pair binding. Allowed only while pool is empty.
  entry configure(m0 : Principal, m1 : Principal) : UInt64 do
    assert totalSupply == 0
    assert reserve0 == 0
    assert reserve1 == 0
    mint0 := m0
    mint1 := m1
    return 0

  -- Mint LP to context.caller. Requires pre-funded credit ≥ amounts.
  entry addLiquidity(amount0 : UInt64, amount1 : UInt64) : UInt64 do
    assert amount0 > 0
    assert amount1 > 0
    -- credit0 = balanceOfSelf(mint0) - reserve0
    scratch := pf.assets.token.balanceOfSelf(mint0)
    assert scratch >= reserve0
    scratch := scratch - reserve0
    assert scratch >= amount0
    -- credit1
    scratch2 := pf.assets.token.balanceOfSelf(mint1)
    assert scratch2 >= reserve1
    scratch2 := scratch2 - reserve1
    assert scratch2 >= amount1
    -- LP mint math (M0): first deposit LP = amount0; later bilateral min
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

  -- amountIn = full token0 credit (pre-fund delta). Pays token1 to caller.
  entry swap0to1(amountOutMin : UInt64) : UInt64 do
    scratch := pf.assets.token.balanceOfSelf(mint0)
    assert scratch > reserve0
    scratch := scratch - reserve0
    assert scratch > 0
    assert reserve0 > 0
    assert reserve1 > 0
    scratch2 := scratch * reserve1 / (reserve0 + scratch)
    assert scratch2 > 0
    assert scratch2 < reserve1
    assert scratch2 >= amountOutMin
    reserve0 := reserve0 + scratch
    reserve1 := reserve1 - scratch2
    call pf.assets.token.transfer(mint1, context.caller, scratch2)
    return scratch2

  entry swap1to0(amountOutMin : UInt64) : UInt64 do
    scratch := pf.assets.token.balanceOfSelf(mint1)
    assert scratch > reserve1
    scratch := scratch - reserve1
    assert scratch > 0
    assert reserve0 > 0
    assert reserve1 > 0
    scratch2 := scratch * reserve0 / (reserve1 + scratch)
    assert scratch2 > 0
    assert scratch2 < reserve0
    assert scratch2 >= amountOutMin
    reserve1 := reserve1 + scratch
    reserve0 := reserve0 - scratch2
    call pf.assets.token.transfer(mint0, context.caller, scratch2)
    return scratch2

  -- Burn LP; pay both tokens to caller. Returns amount0 out.
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
      call pf.assets.token.transfer(mint0, context.caller, scratch)
      call pf.assets.token.transfer(mint1, context.caller, scratch2)
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

  view tokenBalance0() : UInt64 do
    return pf.assets.token.balanceOfSelf(mint0)

  view tokenBalance1() : UInt64 do
    return pf.assets.token.balanceOfSelf(mint1)

end Examples
