import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0031 S2 / ADR-0030 E3: context.blockHeight Plan open fixture.
-- Returns `context.blockHeight` as a view and stamps it via entry:
--   EVM      → NUMBER / Yul `number()`  (Anvil: scripts/evm_blockheight_anvil_smoke.sh)
--   NEAR     → host `block_index()`     (sandbox: near_runtime_test suite blockheightcheck)
--   CosmWasm → Env.block.height         (cw-vm: runtime-tests/cosmwasm/tests/block_height.rs)
-- Not imported by Examples.lean (target-runtime fixture, like CallerCheck).
program BlockHeightCheck where
  state pad : UInt64

  init(initial : UInt64) do
    pad := initial

  -- View-safe block height (NUMBER is STATICCALL-readable).
  view height() : UInt64 do
    return context.blockHeight

  -- Store the current block height for later `get()` correlation with the
  -- transaction's receipt block number.
  entry stamp() : UInt64 do
    pad := context.blockHeight
    return pad

  view get() : UInt64 do
    return pad

end Examples
