import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

program Sha256BytesTon where
  state last : UInt256

  init() do
    last := 0

  entry probe(data : Bytes 4) : UInt256 do
    let h : UInt256 := call pf.crypto.sha256Bytes(data)
    last := h
    return last

  view get() : UInt256 do
    return last

end Examples
