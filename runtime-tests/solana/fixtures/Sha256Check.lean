import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0031 SYS-S5-SOLANA Mollusk fixture (product path ELF under the sole
-- profile solana-sbpf-cpi-elf-v1).
--
-- Honesty: `pf.crypto.sha256` is the dedicated `sol_sha256` host syscall,
-- not a CPI / hashed AddressBearing CALL. Input and result are one UInt256
-- word in little-endian limb order (hash of the 32-byte LE encoding).
-- Other `pf.crypto.*` stay fail closed. Engineering gate only.
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
