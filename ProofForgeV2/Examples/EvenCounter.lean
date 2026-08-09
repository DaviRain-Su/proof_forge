import ProofForgeV2.Language.ProgramElaborationV1

/-!
  Ordinary EvenCounter contract surface (wave-3′ mig-b1 redo).

  Product-positive certification lives on the same-file program + author theorem
  path exercised by `Tests.Compiler.InlineProofCertifierV1` (`exact`
  residual `ParityCounterPreservationV1.preservation_theorem`, which is a thin
  consumer of `PreservationShapeV1` increment-add-two / view-load / UInt64 parity
  families). Residual golden + pin remain until mig-c1; this module holds only
  the ordinary program surface under `ProofForgeV2.Examples`.

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
