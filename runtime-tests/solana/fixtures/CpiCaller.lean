import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

-- BL-27 CPI caller: result-bearing call, void call, schedule, failing callee.
program CpiCaller where
  state count : UInt64

  init(i : UInt64) do
    count := i

  entry fetch(k : UInt64) : UInt64 do
    let x : UInt64 := call ledger.get(k)
    count := x
    return x

  entry note(x : UInt64) : UInt64 do
    call ledger.record(x)
    count := x
    return count

  entry later(x : UInt64) : UInt64 do
    schedule ledger.record(x)
    count := x
    return count

  entry boom(x : UInt64) : UInt64 do
    call ledger.fail(x)
    count := x
    return count

  view get() : UInt64 do
    return count

end ProofForgeV2.Examples
