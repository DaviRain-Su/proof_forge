import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

-- C-5/B-SOL-MUL residual: real ELF+Mollusk coverage for UInt128 multiword
-- div/mod (binary long division in EmitSbpfAsmV1). UInt256 remains a separate
-- focused oracle fixture; `WideDivDispatch` combines all four wide handlers to
-- pin the long-range BPF-to-BPF entrypoint dispatch under the locked assembler.
-- Multiword state is the oracle surface; UInt64 return avoids conflating the
-- arithmetic check with the separate wide return-data layout boundary.
-- Divisor-zero traps reuse the same entry surface with a zero rhs
-- (Custom(0x1001) arithmetic family).
program WideDiv where
  state result128 : UInt128

  init() do
    result128 := 0

  entry div128(x : UInt128, y : UInt128) : UInt64 do
    result128 := x / y
    return 0

  entry mod128(x : UInt128, y : UInt128) : UInt64 do
    result128 := x % y
    return 0

end ProofForgeV2.Examples
