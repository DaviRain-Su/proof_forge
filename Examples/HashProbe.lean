import ProofForgeV2
namespace Examples
open ProofForgeV2.Language
-- Poseidon hashNoPad probe (ADR-0037): expression-position
-- `call pf.crypto.hashNoPad(a, b)` lowers to DPN op 21; product returns first HashOut limb.
program HashProbe where
  state h : UInt64

  init() do
    h := 0

  entry hashPair(a : UInt64, b : UInt64) : UInt64 do
    let x : UInt64 := call pf.crypto.hashNoPad(a, b)
    h := x
    return x

  view get() : UInt64 do
    return h
end Examples
