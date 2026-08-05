import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0030 E2-3 product demo: env-read balanceOfSelf on EVM.
-- `nativeBalance()` returns the contract's ETH balance (SELFBALANCE).
-- `tokenBalance(mint)` returns the contract's ERC-20 balance for `mint`
--   (STATICCALL balanceOf(address)).
-- `tipToken(mint, dst, amount)` transfers `amount` of token `mint` from the
--   program's self vault to `dst` (ERC-20 transfer via controlled dynamic
--   callee) and increments a tip counter.
-- Chain-neutral source: each target's catalog/lowering decides the
-- realization — EVM: SELFBALANCE + STATICCALL balanceOf + ERC-20 transfer.
-- Not imported by Examples.lean (target-specific, like TokenJar/TipJar).
-- Engineering only: non-formal; runtime gates are Anvil.
program EnvReadJar where
  requires extension pf.assets version "1.1.0"
    digest "sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9"

  state tips : UInt64

  init(initial : UInt64) do
    tips := initial

  entry acceptNative(amount : UInt64) : UInt64 do
    call pf.assets.native.deposit(amount)
    return amount

  view nativeBalance() : UInt64 do
    return pf.assets.native.balanceOfSelf()

  view tokenBalance(mint : Principal) : UInt64 do
    return pf.assets.token.balanceOfSelf(mint)

  entry tipToken(mint : Principal, dst : Principal, amount : UInt64) : UInt64 do
    call pf.assets.token.transfer(mint, dst, amount)
    tips := tips + amount
    return tips

  view get() : UInt64 do
    return tips

end Examples