import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

-- C-5/B-SOL-MUL residual: real ELF+Mollusk coverage for UInt256 multiword
-- div/mod. Kept separate from `WideDiv` for focused runtime arithmetic oracles;
-- `WideDivDispatch` independently combines UInt128/256 handlers and pins the
-- long-range BPF-to-BPF entrypoint dispatch under the locked assembler.
-- Divisor-zero traps reuse the same entry surface with a zero rhs
-- (Custom(0x1001) arithmetic family).
program WideDiv256 where
  state result256 : UInt256

  init() do
    result256 := 0

  entry div256(x : UInt256, y : UInt256) : UInt64 do
    result256 := x / y
    return 0

  entry mod256(x : UInt256, y : UInt256) : UInt64 do
    result256 := x % y
    return 0

end ProofForgeV2.Examples
