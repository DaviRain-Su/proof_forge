import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0033 / M4 MiniAMM real-asset product surface (EVM + Solana sole rail).
-- Math matches Examples/MiniAmm.lean (M0). Asset path:
--   * Solana CPI: Principal args to pf.assets.token.* must be direct public
--     entry parameters (not state / context.caller).
--   * Entry credit measurement via balanceOfSelf is EVM-ok; Solana product
--     path currently uses **declared amountIn** on swaps (pre-fund still
--     required off-chain / by protocol). Views expose balanceOfSelf for mint.
--   * Dual-mint vault ATA roles are mint-param keyed (M4 derive fix).
--   * Solana M4c: multi-role token CPI on sole rail — dense Map Principal
--     specialized ops (temps ~102/55), dynamic role table N=21 (ROLE_BASE
--     0x540), per-site stamp product_mr_token_0..3 for dual-mint transfers.
--     Product pins: MiniAmmAssetsSolanaV1 + MiniAmmAssetsEvmV1.
--   * Dual-chain runtime: Solana Mollusk miniamm_assets 10/10 + EVM Anvil
--     scripts/evm_miniamm_assets_anvil_smoke.sh (M5 dual ERC-20, same source).
--
-- Pre-fund honesty: user funds vault first; AMM revert does not auto-refund.
program MiniAmmAssets where
  requires extension pf.assets version "1.1.0"
    digest "sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9"

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

  -- Pure vault-internal mint of LP (tokens already pre-funded into vault).
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

  -- Declared amountIn (pre-fund mint0 by that amount). Pays mint1 to `to`.
  entry swap0to1(
      mint1 : Principal, to : Principal,
      amountIn : UInt64, amountOutMin : UInt64) : UInt64 do
    assert amountIn > 0
    assert reserve0 > 0
    assert reserve1 > 0
    scratch := amountIn * reserve1 / (reserve0 + amountIn)
    assert scratch > 0
    assert scratch < reserve1
    assert scratch >= amountOutMin
    reserve0 := reserve0 + amountIn
    reserve1 := reserve1 - scratch
    call pf.assets.token.transfer(mint1, to, scratch)
    return scratch

  entry swap1to0(
      mint0 : Principal, to : Principal,
      amountIn : UInt64, amountOutMin : UInt64) : UInt64 do
    assert amountIn > 0
    assert reserve0 > 0
    assert reserve1 > 0
    scratch := amountIn * reserve0 / (reserve1 + amountIn)
    assert scratch > 0
    assert scratch < reserve0
    assert scratch >= amountOutMin
    reserve1 := reserve1 + amountIn
    reserve0 := reserve0 - scratch
    call pf.assets.token.transfer(mint0, to, scratch)
    return scratch

  -- Burn LP; pay both tokens to `to` (dual mint vault ATA + dual transfer).
  entry removeLiquidity(
      mint0 : Principal, mint1 : Principal, to : Principal,
      lpAmount : UInt64) : UInt64 do
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
      call pf.assets.token.transfer(mint0, to, scratch)
      call pf.assets.token.transfer(mint1, to, scratch2)
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

  -- token.balanceOfSelf views: EVM admits freely; Solana full-body LowerSemantic
  -- pilot does not yet lower Op.EnvRead in body IR (escrow TokenJar keeps
  -- env-read on the straight-line CPI path). M5 Anvil can still assert ERC-20
  -- balances off-program; Solana Mollusk reads vault ATA data directly.

end Examples
