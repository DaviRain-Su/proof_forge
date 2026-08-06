import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0031 S1 / ADR-0030 E3 / ADR-0025: EVM context.caller Plan open fixture.
-- Compares `context.caller` to a Principal parameter and returns Bool.
-- Multi-word Principal entry/view return remains fail closed on EVM ABI;
-- leaf-wise `==` against a 9-word Principal param is the honest product shape.
-- Anvil gate: scripts/evm_caller_anvil_smoke.sh
-- Not imported by Examples.lean (target-specific, like EnvReadJar/TipJar).
program CallerCheck where
  state pad : UInt64

  init(initial : UInt64) do
    pad := initial

  -- Returns true iff `a` is the ADR-0025 encoding of msg.sender
  -- (`u32le(20)||addr20` Principal wire identity).
  entry isCaller(a : Principal) : Bool do
    return context.caller == a

  -- Same compare as a view (CALLER is STATICCALL-readable / view-safe).
  view isCallerView(a : Principal) : Bool do
    return context.caller == a

  view get() : UInt64 do
    return pad

end Examples
