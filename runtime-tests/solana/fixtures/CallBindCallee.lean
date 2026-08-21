import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- Product-built callee for the ADR-0053 outer AccountInfo runtime join.
program CallBindCallee where
  state count : UInt64

  init(initial : UInt64) do
    count := initial

  entry feed(delta : UInt64) : UInt64 do
    assert delta < 100
    count := count + delta
    return count

  view inspect() : UInt64 do
    return count

end Examples
