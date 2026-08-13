import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0031 SYS-S5-SOLANA engineering fixture shape.
--
-- Honesty: `pf.crypto.keccak256` lowers to dedicated `sol_keccak256` on
-- the engineering Plan/IR/SBPF path (UInt256 LE word). The sole product
-- capability still rejects host-only keccak256 as neither
-- extension/caller nor body-only (`PF-REQ-UNSUPPORTED`). This file is
-- not a Mollusk product-runtime claim. Other `pf.crypto.*` stay fail
-- closed. Engineering record only.
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
