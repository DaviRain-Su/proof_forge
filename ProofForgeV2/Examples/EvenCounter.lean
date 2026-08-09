import ProofForgeV2.Language.ProgramElaborationV1

/-!
  Ordinary EvenCounter contract surface (wave-3′ mig-b1-evencounter).

  Product-positive certification lives on the same-file program + author theorem
  path exercised by `Tests.Compiler.InlineProofCertifierV1` (non-pin
  `ParityCounterPreservationV1.preservation_theorem_of_eq_bytes` transport).
  This module records the ordinary program shape under `ProofForgeV2.Examples`
  without embedding the heavy closed shape golden (which stays in
  `Semantic.ParityCounterShapeV1` until mig-c1 deletes residual golden modules).

  No ClosedSubjectPin row. No `ProofInstances/` import. Engineering only.
-/

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

program EvenCounter where
  state count : UInt64
  entry increment() : UInt64 do
    count := count + 2
    return count
  view get() : UInt64 do
    return count
  invariant even : count % 2 == 0

/-- Canonical source text for non-CLI library tests (parity with Counter). -/
def evenCounterSourceTextV1 : String :=
  "program EvenCounter where\n" ++
  "  state count : UInt64\n" ++
  "  entry increment() : UInt64 do\n" ++
  "    count := count + 2\n" ++
  "    return count\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n" ++
  "  invariant even : count % 2 == 0\n"

end ProofForgeV2.Examples
