import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0031 SYS-S5 runtime fixture. The mutating entry uses the exact
-- UInt256→UInt256 pf.crypto.keccak256 leaf and stores its digest; the view
-- only reads state and does not perform an ExternalCall.
-- EVM: native keccak256 opcode over one 32-byte BE word.
-- NEAR: env.keccak256 over the same 32-byte LE word as sha256.
-- Solana product capability still rejects host-only keccak256
-- (PF-REQ-UNSUPPORTED / body-only); engineering Plan/IR/SBPF remains
-- dedicated sol_keccak256.
-- Not imported by Examples.lean (host-optional companion fixture).
program Keccak256Check where
  state last : UInt256

  init() do
    last := 0

  entry hashWord(x : UInt256) : UInt256 do
    let h : UInt256 := call pf.crypto.keccak256(x)
    last := h
    return h

  view get() : UInt256 do
    return last

end Examples
