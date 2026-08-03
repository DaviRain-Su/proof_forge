import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

program ScheduleFlow where
  state count : UInt64

  init(x : UInt64) do
    count := x

  entry later() : UInt64 do
    schedule ledger.daily(count)
    count := count + 1
    return count

  view get() : UInt64 do
    return count

end ProofForgeV2.Examples
