import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

/-
  NEAR runtime-only Counter-shaped fixture.

  The public initializer exists solely because the current NEAR raw-KV
  profile rejects stateful programs without one. `increment` and `get` retain
  the exact business operations from Examples/Counter.lean, allowing the
  sandbox gate to reach the UInt64 overflow boundary without changing the
  sole product Counter or introducing a target-specific compiler fallback.
-/
program CounterOverflow where
  state count : UInt64

  init(initial : UInt64) do
    count := initial

  entry increment() : UInt64 do
    count := count + 2
    return count

  view get() : UInt64 do
    return count

end Examples
