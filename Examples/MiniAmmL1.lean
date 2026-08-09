import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- Wave-3 MiniAmm L1 P1 surface (RESEARCH-023 / ADR-0034).
-- Same vault-internal math as Examples/MiniAmm.lean plus executable empty-pool
-- invariant. Ordinary instance on shared Preservation ABI — no second step,
-- no MiniAmm-only Semantic helper. Deployable MiniAmm without inv remains
-- Examples/MiniAmm.lean (materializers may FC nonempty inv).
--
-- P1: totalSupply == 0 → reserve0 == 0 && reserve1 == 0
-- Engineering only; not formal TASK/TST; does not supersede ADR-0027.

program MiniAmmL1 where
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

  -- L1 P1 executable: empty pool implies zero reserves.
  invariant emptyPool :
    !(totalSupply == 0) || (reserve0 == 0 && reserve1 == 0)

end Examples
