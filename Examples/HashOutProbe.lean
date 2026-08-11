import ProofForgeV2
namespace Examples
open ProofForgeV2.Language
-- Full HashOut multi-limb product ABI (`Array UInt64 4`).
-- Admitted only for hashNoPad / hashTwoToOne (official simulate fills
-- hash_out_arrays). keccak/context stay UInt64 limb0 (HashProbe / ContextProbe).
-- Session fail-closes on Poseidon; authority is psy_user_cli simulate.
program HashOutProbe where
  state last0 : UInt64

  init() do
    last0 := 0

  entry hashPairFull(a : UInt64, b : UInt64) : Array UInt64 4 do
    let h : Array UInt64 4 := call pf.crypto.hashNoPad(a, b)
    last0 := h[0]
    return h

  entry hashCombineFull(
      a0 : UInt64, a1 : UInt64, a2 : UInt64, a3 : UInt64,
      b0 : UInt64, b1 : UInt64, b2 : UInt64, b3 : UInt64
  ) : Array UInt64 4 do
    let h : Array UInt64 4 := call pf.crypto.hashTwoToOne(a0, a1, a2, a3, b0, b1, b2, b3)
    last0 := h[0]
    return h

  view getLast0() : UInt64 do
    return last0
end Examples
