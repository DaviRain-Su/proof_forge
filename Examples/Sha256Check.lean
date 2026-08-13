import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0031 SYS-S5-EVM first runtime fixture. The mutating entry uses the exact
-- UInt256→UInt256 pf.crypto.sha256 precompile leaf and stores its digest;
-- the view only reads state and does not perform an ExternalCall.
-- Not imported by Examples.lean (host-optional Anvil companion fixture).
program Sha256Check where
  state last : UInt256

  init() do
    last := 0

  entry hashWord(x : UInt256) : UInt256 do
    let h : UInt256 := call pf.crypto.sha256(x)
    last := h
    return h

  view get() : UInt256 do
    return last

end Examples
