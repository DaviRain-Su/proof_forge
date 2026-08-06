import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0031 S1 NEAR product demo: context.caller → predecessor_account_id.
-- Canonical Principal wire = u32le(L)||account-id-utf8, packed as length +
-- 8×UInt64 LE body leaves (unused tail bytes 0). Entry/init only; view with
-- context.caller is Plan-fail-closed (NEAR view forbids predecessor).
-- Engineering only: non-formal; runtime gate is near-sandbox.
-- Not imported by Examples.lean (target-specific).
program CallerCheck where
  state pad : UInt64

  init(initial : UInt64) do
    pad := initial

  -- Returns true iff `a` is the Principal encoding of predecessor_account_id.
  entry isCaller(a : Principal) : Bool do
    return context.caller == a

  -- Asserts caller match then bumps pad (failure must hold state).
  entry bumpIfCaller(a : Principal) : UInt64 do
    assert context.caller == a
    pad := pad + 1
    return pad

  view get() : UInt64 do
    return pad

end Examples
