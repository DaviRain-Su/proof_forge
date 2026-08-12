import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0031 S4 NEAR sandbox fixture: context.attachedValue → attached_deposit.
-- View must not read the key (NEAR ViewFunction forbids attached_deposit).
-- Not imported by Examples.lean.
program AttachedValueCheck where
  state paid : UInt64

  init(initial : UInt64) do
    paid := initial

  entry collect() : UInt64 do
    paid := context.attachedValue
    return paid

  view get() : UInt64 do
    return paid

end Examples
