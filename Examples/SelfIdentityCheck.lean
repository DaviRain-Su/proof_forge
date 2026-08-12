import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0031 S3: context.self Plan open fixture.
-- Compares `context.self` to a Principal parameter and returns Bool.
-- Multi-word Principal entry/view return remains fail closed on EVM ABI;
-- leaf-wise `==` against a 9-word Principal param is the honest product shape.
--   EVM      → ADDRESS / `address()` → u32le(20)||addr20
--   NEAR     → current_account_id UTF-8 Principal leaves (view-safe)
--   CosmWasm → Env.contract.address UTF-8 Principal leaves (view-safe)
-- Not imported by Examples.lean (target-runtime fixture, like CallerCheck).
program SelfIdentityCheck where
  state pad : UInt64

  init(initial : UInt64) do
    pad := initial

  entry isSelf(a : Principal) : Bool do
    return context.self == a

  view isSelfView(a : Principal) : Bool do
    return context.self == a

  view get() : UInt64 do
    return pad

end Examples
