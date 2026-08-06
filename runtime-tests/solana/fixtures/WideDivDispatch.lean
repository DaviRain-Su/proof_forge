import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

-- Verifier-backed dispatch probe: all four UInt128/256 div/mod handlers share
-- one product ELF. Entrypoint discriminator branches target adjacent stubs;
-- each stub uses a long-range BPF-to-BPF call to the handler body. This fixture
-- exists to catch signed-16-bit direct-branch regressions in the locked SBPF
-- assembler path; the focused arithmetic oracles remain in WideDiv/WideDiv256.
program WideDivDispatch where
  state count : UInt64

  init(i : UInt64) do
    count := i

  entry div128(x : UInt128, y : UInt128) : UInt128 do
    return x / y

  entry mod128(x : UInt128, y : UInt128) : UInt128 do
    return x % y

  entry div256(x : UInt256, y : UInt256) : UInt256 do
    return x / y

  entry mod256(x : UInt256, y : UInt256) : UInt256 do
    return x % y

  view get() : UInt64 do
    return count

end ProofForgeV2.Examples
