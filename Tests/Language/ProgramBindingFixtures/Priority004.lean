import ProofForgeV2.Core.Source
import ProofForgeV2.Language.ProgramExport
import Tests.Language.ProgramBindingFixtures.Snapshot

namespace Tests.Language.ProgramBindingFixtures.Priority004
open ProofForgeV2.Source

/-- Lying but structurally valid; sorts before ZAlias. -/
@[proof_forge_program] def ALie : Program :=
  Program.mk "Tests.Language.ProgramBindingFixtures.Priority004.NotALie" "NotALie"
    #[] #[] #[] #[] #[] #[] none
    #[{ name := "run", params := #[], result := .u64, mode := .mutate
        body := #[.returnValue (.literal (UInt64.ofNat 0))] }]
    #[] #[] #[] #[]

def aliasBase : Program :=
  Program.mk "Tests.Language.ProgramBindingFixtures.Priority004.AliasBase" "AliasBase"
    #[] #[] #[] #[] #[] #[] none
    #[{ name := "run", params := #[], result := .u64, mode := .mutate
        body := #[.returnValue (.literal (UInt64.ofNat 2))] }]
    #[] #[] #[] #[]

/-- Later FQN; const alias → PA82 PF-EXPORT-004 during decode-all (before binding). -/
@[proof_forge_program] def ZAlias : Program := aliasBase

#expect_payloads_prefix "PF-EXPORT-004" as priority004Error
end Tests.Language.ProgramBindingFixtures.Priority004
