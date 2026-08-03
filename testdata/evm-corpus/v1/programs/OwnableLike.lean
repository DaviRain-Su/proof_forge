import ProofForgeV2

open ProofForgeV2.Language

-- Minimal honest Ownable-like surface for EVMOZ-005 / F01 blocked case.
-- * owner is a public Principal identity (wire opaque body; not EVM address ABI)
-- * init records context.caller (no external caller parameter spoofing msg.sender)
-- * setValue enforces only-owner via byte-exact context.caller == owner
-- * authorized mutation updates value; unauthorized assert reverts with rollback
-- EVM Plan remains fail-closed on ContextRead (context.caller) until a future
-- target-owned cutover under ADR-0025. This fixture is not OZ/ABI credit.
program OwnableLike where
  state owner : Principal
  state value : UInt64

  init() do
    owner := context.caller
    value := 0

  entry setValue(v : UInt64) : UInt64 do
    assert context.caller == owner
    value := v
    return value

  view getValue() : UInt64 do
    return value
