import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- CAP-X-BYTES-NEAR-RT runtime fixture. The mutating entry uses the exact
-- Bytes N→UInt256 pf.crypto.sha256Bytes leaf (NEAR host env.sha256 over N
-- consecutive UInt8 leaves, N≤64) and stores its digest; the view only
-- reads state and does not perform an ExternalCall.
-- Vector bytes 01 02 03 04 are deliberately distinct from the UInt256
-- zero-word Sha256Check leaf. HostModel does not execute this syscall.
-- Not imported by Examples.lean (host-optional companion fixture).
program Sha256BytesCheck where
  state last : UInt256

  init() do
    last := 0

  entry hashBytes(data : Bytes 4) : UInt256 do
    let h : UInt256 := call pf.crypto.sha256Bytes(data)
    last := h
    return h

  view get() : UInt256 do
    return last

end Examples
