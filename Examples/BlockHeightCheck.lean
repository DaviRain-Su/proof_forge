import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0031 S2 / ADR-0030 E3: EVM context.blockHeight Plan open fixture.
-- Returns `context.blockHeight` (EVM NUMBER / Yul `number()` → UInt64) as a
-- view, and stamps it into state via an entry for receipt-block correlation.
-- Anvil gate: scripts/evm_blockheight_anvil_smoke.sh
-- Not imported by Examples.lean (target-specific, like CallerCheck).
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
