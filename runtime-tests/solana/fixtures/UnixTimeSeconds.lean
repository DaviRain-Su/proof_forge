import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- CAP-2 / CAP-D-SOL-TIME Mollusk fixture (product path ELF under the sole
-- profile solana-sbpf-cpi-elf-v1).
--
-- Solana honesty: `context.unixTimeSeconds` = Clock.unix_timestamp via the
-- real `sol_get_clock_sysvar` syscall (i64 at byte offset 32 of the Clock
-- sysvar). The i64 bits are loaded into a u64 register with no extra
-- sign/range guard — negative host timestamps appear as two's-complement
-- u64 values. Stake-weighted Clock, not a trusted wall clock. No Clock
-- account meta (syscall read). `pad` state pins the entry store path
-- (`stamp`) alongside the view-safe read (`now`).
program UnixTimeSeconds where
  state pad : UInt64

  init(initial : UInt64) do
    pad := initial

  -- View-safe unix-time read.
  view now() : UInt64 do
    return context.unixTimeSeconds

  -- Store the current unix timestamp for later `get()` correlation.
  entry stamp() : UInt64 do
    pad := context.unixTimeSeconds
    return pad

  view get() : UInt64 do
    return pad

end Examples
