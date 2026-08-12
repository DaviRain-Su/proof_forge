import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0031 S3: context.contractId Plan open fixture.
-- Wire key remains `proof-forge.context.self.v1` (ADR-0031 S3b).
-- Source spelling is `contractId` because Lean treats bare `self`/`this` as
-- keywords and escaped identifiers are excluded from exact ContextRead match.
-- Compares `context.contractId` to a Principal parameter and returns Bool.
--   EVM      → ADDRESS / `address()` → u32le(20)||addr20
--   NEAR     → current_account_id UTF-8 Principal leaves (view-safe)
--   CosmWasm → Env.contract.address UTF-8 Principal leaves (view-safe)
-- Not imported by Examples.lean (target-runtime fixture, like CallerCheck).
program SelfIdentityCheck where
  state pad : UInt64

  init(initial : UInt64) do
    pad := initial

  entry isSelf(a : Principal) : Bool do
    return context.contractId == a

  view isSelfView(a : Principal) : Bool do
    return context.contractId == a

  view get() : UInt64 do
    return pad

end Examples
