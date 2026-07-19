import ProofForgeV2.Core.Source
import ProofForgeV2.Language.ProgramExport
import Tests.Language.ProgramIdentityFixtures.Snapshot

namespace Tests.Language.ProgramIdentityFixtures.Duplicate
open ProofForgeV2.Source

@[proof_forge_program] def DupA : Program :=
  Program.mk "Tests.Language.ProgramIdentityFixtures.Duplicate.Shared" "Shared"
    #[] #[] #[] #[] #[] #[] none
    #[{ name := "run", params := #[], result := .u64, mode := .mutate
        body := #[.returnValue (.literal (UInt64.ofNat 0))] }]
    #[] #[] #[] #[]

@[proof_forge_program] def DupB : Program :=
  Program.mk "Tests.Language.ProgramIdentityFixtures.Duplicate.Shared" "Shared"
    #[] #[] #[] #[] #[] #[] none
    #[{ name := "run", params := #[], result := .u64, mode := .mutate
        body := #[.returnValue (.literal (UInt64.ofNat 0))] }]
    #[] #[] #[] #[]

#expect_program_identities_error
  "PF-EXPORT-001: duplicate exported program identity" as duplicateIdentityError
end Tests.Language.ProgramIdentityFixtures.Duplicate
