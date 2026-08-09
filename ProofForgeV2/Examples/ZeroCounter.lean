import ProofForgeV2.Language.ProgramElaborationV1

/-!
  Ordinary ZeroCounter contract surface (wave-3′ mig-b2-zerocounter).

  Product-positive certification lives on the same-file program + author theorem
  path exercised by `Tests.Compiler.InlineProofCertifierV1` (nullary exact of
  `ZeroCounterPreservationV1.preservation_theorem` with pin golden).
  This module records the ordinary program shape under `ProofForgeV2.Examples`
  without embedding the heavy closed shape golden (which stays in
  `Semantic.ZeroCounterShapeV1` until mig-c1 deletes residual golden modules).

  No ClosedSubjectPin row. No `ProofInstances/` import. Engineering only.
-/

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

program ZeroCounter where
  state count : UInt64
  entry clear() : UInt64 do
    count := 0
    return count
  view get() : UInt64 do
    return count
  invariant zero : count == 0

/-- Canonical source text for non-CLI library tests (parity with EvenCounter). -/
def zeroCounterSourceTextV1 : String :=
  "program ZeroCounter where\n" ++
  "  state count : UInt64\n" ++
  "  entry clear() : UInt64 do\n" ++
  "    count := 0\n" ++
  "    return count\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n" ++
  "  invariant zero : count == 0\n"

end ProofForgeV2.Examples
