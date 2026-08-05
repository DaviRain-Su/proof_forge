import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0030 E2-NEAR product demo: env-read native balanceOfSelf.
-- `nativeBalance()` returns the contract account balance via host
-- `account_balance` (u128 LE) with a UInt64 range guard (high 64 bits
-- nonzero → trap). `acceptNative(amount)` exact-checks attached_deposit
-- and increments a tip counter. Token balanceOfSelf stays permanently
-- fail closed on NEAR (NEP-141 ft_balance_of is async cross-contract).
-- Engineering only: non-formal; runtime gate is near-sandbox.
-- Not imported by Examples.lean (target-specific).
program EnvReadJar where
  requires extension pf.assets version "1.1.0"
    digest "sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9"

  state tips : UInt64

  init(initial : UInt64) do
    tips := initial

  entry acceptNative(amount : UInt64) : UInt64 do
    call pf.assets.native.deposit(amount)
    tips := tips + amount
    return tips

  view nativeBalance() : UInt64 do
    return pf.assets.native.balanceOfSelf()

  view get() : UInt64 do
    return tips

end Examples
