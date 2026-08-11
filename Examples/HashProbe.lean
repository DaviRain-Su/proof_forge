import ProofForgeV2
namespace Examples
open ProofForgeV2.Language
-- ADR-0039 crypto gadgets (expression-position pf.crypto.*):
--   hashNoPad / hashPad : 1..8 Felts → first HashOut limb
--   hashTwoToOne        : 8 Felts (left||right HashOut) → first limb
--   keccak256           : 1..16 words → first u32 limb as UInt64
-- Session harness fail-closes; authority is psy_user_cli simulate.
program HashProbe where
  state h : UInt64

  init() do
    h := 0

  entry hashPair(a : UInt64, b : UInt64) : UInt64 do
    let x : UInt64 := call pf.crypto.hashNoPad(a, b)
    h := x
    return x

  entry hashPadPair(a : UInt64, b : UInt64) : UInt64 do
    let x : UInt64 := call pf.crypto.hashPad(a, b)
    h := x
    return x

  entry hashCombine(
      a0 : UInt64, a1 : UInt64, a2 : UInt64, a3 : UInt64,
      b0 : UInt64, b1 : UInt64, b2 : UInt64, b3 : UInt64
  ) : UInt64 do
    let x : UInt64 := call pf.crypto.hashTwoToOne(a0, a1, a2, a3, b0, b1, b2, b3)
    h := x
    return x

  entry keccakWord(w : UInt64) : UInt64 do
    let x : UInt64 := call pf.crypto.keccak256(w)
    h := x
    return x

  view get() : UInt64 do
    return h
end Examples
