import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

-- C-5/B-SOL-MUL: real ELF+Mollusk coverage for UInt128/256 schoolbook mul.
-- Multiword state is the oracle surface; UInt64 return avoids conflating the
-- multiplication check with the separate wide return-data layout boundary.
program WideMul where
  state product128 : UInt128
  state product256 : UInt256

  init() do
    product128 := 0
    product256 := 0

  entry mul128(x : UInt128, y : UInt128) : UInt64 do
    product128 := x * y
    return 0

  entry mul256(x : UInt256, y : UInt256) : UInt64 do
    product256 := x * y
    return 0

end ProofForgeV2.Examples
