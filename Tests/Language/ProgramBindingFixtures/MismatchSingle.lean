import ProofForgeV2.Core.Source
import ProofForgeV2.Language.ProgramExport
import Tests.Language.ProgramBindingFixtures.Snapshot

namespace Tests.Language.ProgramBindingFixtures.MismatchSingle
open ProofForgeV2.Source

/-- Valid Program.mk decode, lying qualifiedName ≠ declaration FQN. -/
@[proof_forge_program] def Lie : Program :=
  Program.mk "Tests.Language.ProgramBindingFixtures.MismatchSingle.Other" "Other"
    #[] #[] #[] #[] #[] #[] none
    #[{ name := "run", params := #[], result := .u64, mode := .mutate
        body := #[.returnValue (.literal (UInt64.ofNat 0))] }]
    #[] #[] #[] #[]

#expect_binding_error_payload Lie as mismatchSingleError
end Tests.Language.ProgramBindingFixtures.MismatchSingle
