import ProofForgeV2

namespace UserArithOps

open ProofForgeV2.Language

/- ArithOps: checked mul/div/mod + unary bitNot product surface used by the
   EVM Anvil differential. `scale` overflows (UInt64) exactly when
   `count * factor` does; `bits` must return `(2^64 - 1) - x` (masked).
   NOTE: a doc comment (`/-- ... -/`) directly above `program` fails to
   parse (Lean attaches doc comments only to declaration commands). -/
program ArithOps where
  state count : UInt64

  init(initial : UInt64) do
    count := initial

  entry scale(factor : UInt64, divisor : UInt64) : UInt64 do
    count := count * factor / divisor + count % divisor
    return count

  entry bits(x : UInt64) : UInt64 do
    return ~x

end UserArithOps
