import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0031 S2 residual Mollusk fixture (product path ELF under the sole
-- profile solana-sbpf-cpi-elf-v1).
--
-- Solana honesty: `context.blockHeight` = Clock.slot via the real
-- `sol_get_clock_sysvar` syscall (physical ≈400ms slot, **not** a logical
-- block number). No Clock account meta (syscall read). `pad` state pins the
-- entry store path (`stamp`) alongside the view-safe read (`height`).
-- `context.unixTimeSeconds` stays fail closed (2026-08-04 product decision).
program BlockHeight where
  state pad : UInt64

  init(initial : UInt64) do
    pad := initial

  -- View-safe slot read.
  view height() : UInt64 do
    return context.blockHeight

  -- Store the current slot for later `get()` correlation.
  entry stamp() : UInt64 do
    pad := context.blockHeight
    return pad

  view get() : UInt64 do
    return pad

end Examples
