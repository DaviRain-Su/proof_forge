import ProofForgeV2.Core.Source
import ProofForgeV2.Language.ProgramExport
import Tests.Language.ProgramIdentityFixtures.Snapshot

namespace Tests.Language.ProgramIdentityFixtures.Priority
open ProofForgeV2.Source

@[proof_forge_program] def CollideA : Program :=
  Program.mk "Tests.Language.ProgramIdentityFixtures.Priority.Shared" "Shared"
    #[] #[] #[] #[] #[] #[] none
    #[{ name := "run", params := #[], result := .u64, mode := .mutate
        body := #[.returnValue (.literal (UInt64.ofNat 0))] }]
    #[] #[] #[] #[]

@[proof_forge_program] def CollideB : Program :=
  Program.mk "Tests.Language.ProgramIdentityFixtures.Priority.Shared" "Shared"
    #[] #[] #[] #[] #[] #[] none
    #[{ name := "run", params := #[], result := .u64, mode := .mutate
        body := #[.returnValue (.literal (UInt64.ofNat 0))] }]
    #[] #[] #[] #[]

def aliasBase : Program :=
  Program.mk "Tests.Language.ProgramIdentityFixtures.Priority.AliasBase" "AliasBase"
    #[] #[] #[] #[] #[] #[] none
    #[{ name := "run", params := #[], result := .u64, mode := .mutate
        body := #[.returnValue (.literal (UInt64.ofNat 2))] }]
    #[] #[] #[] #[]

@[proof_forge_program] def ZAlias : Program := aliasBase

#expect_program_payloads_prefix "PF-EXPORT-004" as priorityDecodeError
end Tests.Language.ProgramIdentityFixtures.Priority
