import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0030 E2-4-CW: EnvReadJar — CosmWasm runtime fixture for env-read product
-- acceptance. `nativeBalance`/`tokenBalance` views exercise the read-only
-- `env.query_chain` channel (bank balance / CW20 smart query); `tip`/`tipToken`
-- entries keep the C1/E1-CW flows for state and SubMsg context.
-- Not a mainnet contract; production-code-generated test fixture only.
program EnvReadJar where
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

  entry tipToken(mint : Principal, dst : Principal, amount : UInt64) : UInt64 do
    call pf.assets.token.transfer(mint, dst, amount)
    tips := tips + amount
    return tips

  view get() : UInt64 do
    return tips

  view nativeBalance() : UInt64 do
    return pf.assets.native.balanceOfSelf()

  view tokenBalance(mint : Principal) : UInt64 do
    return pf.assets.token.balanceOfSelf(mint)

end Examples
