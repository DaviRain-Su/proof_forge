import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0031 S4: context.attachedValue Plan open fixture.
-- Returns `context.attachedValue` as a view (STATICCALL ⇒ 0) and stamps it
-- via a payable entry:
--   EVM → CALLVALUE / Yul `callvalue()` with UInt64 range guard
--          (Anvil: scripts/evm_attachedvalue_anvil_smoke.sh)
--   NEAR / CosmWasm → entry/init S4 leaves are open; this fixture's view
--      `peek()` attachedValue read remains fail closed (NEAR view / CW query)
--   Solana / Noir / Aleo / Psy / TON / Quint → Plan fail closed
-- Not imported by Examples.lean (target-runtime fixture, like ChainIdCheck).
program AttachedValueCheck where
  state paid : UInt64

  init(initial : UInt64) do
    paid := initial

  -- View-safe: STATICCALL forces CALLVALUE = 0, so this is always 0.
  view peek() : UInt64 do
    return context.attachedValue

  -- Payable entry: stores the invocation's attached wei (must be ≤ UInt64).
  entry collect() : UInt64 do
    paid := context.attachedValue
    return paid

  view get() : UInt64 do
    return paid

end Examples
