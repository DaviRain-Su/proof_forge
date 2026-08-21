import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0053 Wave 3 product runtime fixture. The compile-time bind table appends
-- the callee state and executable callee program after this program's state.
program CallBindCaller where
  requires extension solana.cpi.accounts version "1.0.0"
    digest "sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020"

  state value : UInt64

  init(initial : UInt64) do
    value := initial

  entry invoke(delta : UInt64) : UInt64 do
    value := value + 1
    call Oracle.feed(delta)
    value := value + 2
    return value

  view inspect() : UInt64 do
    return value

end Examples
