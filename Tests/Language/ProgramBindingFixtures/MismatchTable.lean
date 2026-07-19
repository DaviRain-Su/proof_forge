import ProofForgeV2.Core.Source
import ProofForgeV2.Language.ProgramExport
import Tests.Language.ProgramBindingFixtures.Snapshot

namespace Tests.Language.ProgramBindingFixtures.MismatchTable
open ProofForgeV2.Source

/-- Isolated single-liar table (no PA83 Shared collision). -/
@[proof_forge_program] def Alone : Program :=
  Program.mk "Tests.Language.ProgramBindingFixtures.MismatchTable.Wrong" "Wrong"
    #[] #[] #[] #[] #[] #[] none
    #[{ name := "run", params := #[], result := .u64, mode := .mutate
        body := #[.returnValue (.literal (UInt64.ofNat 1))] }]
    #[] #[] #[] #[]

#expect_binding_error_payloads as mismatchTableError
end Tests.Language.ProgramBindingFixtures.MismatchTable
