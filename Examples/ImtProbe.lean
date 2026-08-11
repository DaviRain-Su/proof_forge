import ProofForgeV2
namespace Examples
open ProofForgeV2.Language
-- IMT self-current pilot (not dense Map state).
-- Language: expression-position `call pf.imt.get|contains|set`.
-- Packs UInt64 as 256-bit limbs [v,0,0,0]; base_offset=0, capacity=2^20.
-- Cross-user / external-contract IMT remain fail-closed.
program ImtProbe where
  state last : UInt64

  init() do
    last := 0

  entry put(k : UInt64, v : UInt64) : UInt64 do
    let w : UInt64 := call pf.imt.set(k, v)
    last := w
    return w

  entry get(k : UInt64) : UInt64 do
    let v : UInt64 := call pf.imt.get(k)
    last := v
    return v

  entry has(k : UInt64) : UInt64 do
    let c : UInt64 := call pf.imt.contains(k)
    last := c
    return c

  view peek() : UInt64 do
    return last
end Examples
