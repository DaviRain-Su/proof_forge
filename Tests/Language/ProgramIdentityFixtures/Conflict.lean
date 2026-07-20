import ProofForgeV2.Core.Source
import ProofForgeV2.Language.ProgramExport
import Tests.Language.ProgramIdentityFixtures.Snapshot

namespace Tests.Language.ProgramIdentityFixtures.Conflict
open ProofForgeV2.Source

@[proof_forge_program] def ConA : Program :=
  Program.mk "Tests.Language.ProgramIdentityFixtures.Conflict.Shared" "Shared"
    #[] #[] #[] #[] #[] #[] none
    #[{ name := "run", params := #[], result := .u64, mode := .mutate
        body := #[.returnValue (.literal (UInt64.ofNat 0))] }]
    #[] #[] #[] #[]

@[proof_forge_program] def ConB : Program :=
  Program.mk "Tests.Language.ProgramIdentityFixtures.Conflict.Shared" "Shared"
    #[] #[] #[] #[] #[] #[] none
    #[{ name := "run", params := #[], result := .u64, mode := .mutate
        body := #[.returnValue (.literal (UInt64.ofNat 1))] }]
    #[] #[] #[] #[]

#expect_program_identities_error
  "PF-EXPORT-001: conflicting exported program identity" as conflictIdentityError
end Tests.Language.ProgramIdentityFixtures.Conflict
