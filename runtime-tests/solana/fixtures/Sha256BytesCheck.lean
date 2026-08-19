import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- CAP-X-BYTES-SOL-MOLLUSK fixture (product path ELF under the sole
-- profile solana-sbpf-cpi-elf-v1).
--
-- Honesty: `pf.crypto.sha256Bytes(Bytes N) -> UInt256` is the dedicated
-- `sol_sha256` host syscall over a packed N-byte slice (N=4 here), not a
-- CPI / hashed AddressBearing CALL and not the UInt256-word `sha256` leaf.
-- Other `pf.crypto.*` stay fail closed. Engineering gate only.
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
