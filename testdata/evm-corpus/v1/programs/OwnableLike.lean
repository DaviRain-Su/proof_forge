import ProofForgeV2

open ProofForgeV2.Language

-- Minimal honest Ownable-like surface for EVMOZ-005 / ADR-0031 S1 caller open.
-- * owner is a public Principal identity (wire opaque body; not EVM address ABI)
-- * init records context.caller (no external caller parameter spoofing msg.sender)
-- * setValue enforces only-owner via byte-exact context.caller == owner
-- * authorized mutation updates value; unauthorized assert reverts with rollback
-- EVM Plan admits ContextRead (context.caller) via ADR-0025 encoding
-- (`CALLER` → `u32le(20)||addr20` Principal leaves). This fixture is not
-- OZ/ABI/family credit (F01 observation credit still independent).
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
