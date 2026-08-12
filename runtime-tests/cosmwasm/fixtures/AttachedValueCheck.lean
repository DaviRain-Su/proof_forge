import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0031 S4 CosmWasm mock fixture: context.attachedValue → info.funds
-- single-denom `stake` amount. View must not read the key (query has no
-- MessageInfo). Not imported by Examples.lean.
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
