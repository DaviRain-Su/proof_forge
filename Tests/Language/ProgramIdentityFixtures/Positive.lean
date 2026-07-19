import ProofForgeV2.Core.Source
import ProofForgeV2.Language.ProgramExport
import Tests.Language.ProgramIdentityFixtures.Snapshot

namespace Tests.Language.ProgramIdentityFixtures.Positive
open ProofForgeV2.Source

-- Direct Program.mk (UInt64.ofNat) so PA82 structural decode succeeds.
@[proof_forge_program] def Alpha : Program :=
  Program.mk "Tests.Language.ProgramIdentityFixtures.Positive.Alpha" "Alpha"
    #[] #[] #[] #[] #[] #[] none
    #[{ name := "run", params := #[], result := .u64, mode := .mutate
        body := #[.returnValue (.literal (UInt64.ofNat 0))] }]
    #[] #[] #[] #[]

@[proof_forge_program] def Beta : Program :=
  Program.mk "Tests.Language.ProgramIdentityFixtures.Positive.Beta" "Beta"
    #[] #[] #[] #[] #[] #[] none
    #[{ name := "run", params := #[], result := .u64, mode := .mutate
        body := #[.returnValue (.literal (UInt64.ofNat 0))] }]
    #[] #[] #[] #[]

#snapshot_program_identities positiveIdentityRows
end Tests.Language.ProgramIdentityFixtures.Positive
