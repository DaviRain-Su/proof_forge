import ProofForgeV2.Core.Source
import ProofForgeV2.Language.ProgramExport
import Tests.Language.ProgramShortNameFixtures.Snapshot

namespace Tests.Language.ProgramShortNameFixtures.Mismatch
open ProofForgeV2.Source

/-- Isolated one-liar env: PA84 qname exact; short name lying; both APIs. -/
@[proof_forge_program] def Lie : Program :=
  Program.mk "Tests.Language.ProgramShortNameFixtures.Mismatch.Lie" "Wrong"
    #[] #[] #[] #[] #[] #[] none
    #[{ name := "run", params := #[], result := .u64, mode := .mutate
        body := #[.returnValue (.literal (UInt64.ofNat 0))] }] #[] #[] #[] #[]

#expect_short_error_apis Lie as shortMismatchSingleError and shortMismatchTableError
end Tests.Language.ProgramShortNameFixtures.Mismatch
