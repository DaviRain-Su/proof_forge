import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0031 / B-CTX-OPEN: context.unixTimeSeconds Plan open fixture.
--   EVM  → timestamp()
--   NEAR → host block_timestamp() ns ÷ 10^9 (truncating)
-- Sandbox: scripts/near_runtime_test.sh suite `unixtimecheck`.
-- Engineering only — not formal/testnet. Not imported by Examples.lean.
program UnixTimeCheck where
  state pad : UInt64

  init(initial : UInt64) do
    pad := initial

  view seconds() : UInt64 do
    return context.unixTimeSeconds

  entry stamp() : UInt64 do
    pad := context.unixTimeSeconds
    return pad

  view get() : UInt64 do
    return pad

end Examples
