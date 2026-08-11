import ProofForgeV2

namespace Proofship

open ProofForgeV2.Language

-- ProofShip proof-twin (NEGATIVE verdict, FAST variant): the declared
-- `proof … using` target does not exist, so certification cannot be
-- established at all — elaboration fails in seconds and the gate produces
-- ZERO artifacts. This is the live negative path.
--
-- A subtler negative (mathematically false but well-formed claim, e.g.
-- x := x + 1 against a parity invariant, or a name-tampered subject) still
-- fails closed, but only after the documented deep kernel-reduction cliff
-- (8+ minutes); per plan that class is pre-recorded, not run live.
program EvenStepBad where
  state total : UInt64

  entry addTwo() : UInt64 do
    total := total + 2
    return total

  view read() : UInt64 do
    return total

  invariant even : total % 2 == 0
  proof even preserving using EvenStepBadProof.even

-- NOTE: no `theorem EvenStepBadProof.even` is defined anywhere — the proof
-- inventory references a theorem that does not exist.

end Proofship
