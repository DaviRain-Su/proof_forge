import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0030 E1-NEAR product demo: portable token tip-jar over
-- `pf.assets.token.transferAsync` for NEAR. The entry calls
-- `pf.assets.token.transferAsync(mint, dst, amount)` which lowers to a
-- fire-and-forget NEP-141 `ft_transfer` cross-contract Promise
-- (promise_batch_create + promise_batch_action_function_call with
-- 1 yoctoNEAR deposit). Sync `token.transfer` stays permanently fail closed
-- on NEAR (NEP-141 cross-contract calls are async). Engineering only:
-- non-formal, non-mainnet. Not imported by Examples.lean (target-specific).
program TokenJarAsync where
  requires extension pf.assets version "1.0.0"
    digest "sha256:97dfde7f7df228230828db4273086224bc28a4bc88c2f25457eaf0aee22aeeed"

  state tips : UInt64

  init(initial : UInt64) do
    tips := initial

  entry tipToken(mint : Principal, dst : Principal, amount : UInt64) : UInt64 do
    call pf.assets.token.transferAsync(mint, dst, amount)
    tips := tips + amount
    return tips

  view get() : UInt64 do
    return tips

end Examples