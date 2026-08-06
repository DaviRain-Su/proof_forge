import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0031 S1: CallerGate — CosmWasm runtime fixture for context.caller
-- (MessageInfo.sender → Principal wire identity).
-- init stores caller as owner; onlyOwner asserts byte-exact identity;
-- setOwner rebinds owner to the current sender; ping is a non-caller
-- entry in the same execute dispatcher (must not load MessageInfo.sender).
-- View has no sender and must not read context.caller (Plan FC).
-- Production-code-generated test fixture only — not a mainnet contract.
program CallerGate where
  state owner : Principal

  init() do
    owner := context.caller

  entry onlyOwner() : UInt64 do
    assert context.caller == owner
    return 1

  entry setOwner() : UInt64 do
    owner := context.caller
    return 1

  -- Mixed-dispatcher pin: no context.caller → no $pf_load_caller_principal
  -- in this branch (invalid/escaped senders must not trap here).
  entry ping() : UInt64 do
    return 1

  view peek() : UInt64 do
    return 0

end Examples
