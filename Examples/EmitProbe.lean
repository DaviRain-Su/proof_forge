import ProofForgeV2
namespace Examples
open ProofForgeV2.Language
program EmitProbe where
  event Ping(x : UInt64)
  state n : UInt64
  init(v : UInt64) do
    n := v
  entry ping(x : UInt64) : UInt64 do
    emit Ping(x)
    n := n + x
    return n
  view get() : UInt64 do
    return n
end Examples
