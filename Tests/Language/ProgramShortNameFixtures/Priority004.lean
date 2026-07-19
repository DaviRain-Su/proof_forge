import ProofForgeV2.Core.Source
import ProofForgeV2.Language.ProgramExport
import Tests.Language.ProgramShortNameFixtures.Snapshot

namespace Tests.Language.ProgramShortNameFixtures.Priority004
open ProofForgeV2.Source

/-- qname ok; short lying + later sorted ZAlias → 004 at decode-all. -/
@[proof_forge_program] def ALie : Program :=
  Program.mk "Tests.Language.ProgramShortNameFixtures.Priority004.ALie" "NotALie"
    #[] #[] #[] #[] #[] #[] none
    #[{ name := "run", params := #[], result := .u64, mode := .mutate
        body := #[.returnValue (.literal (UInt64.ofNat 0))] }] #[] #[] #[] #[]

def aliasBase : Program :=
  Program.mk "Tests.Language.ProgramShortNameFixtures.Priority004.AliasBase" "AliasBase"
    #[] #[] #[] #[] #[] #[] none
    #[{ name := "run", params := #[], result := .u64, mode := .mutate
        body := #[.returnValue (.literal (UInt64.ofNat 2))] }] #[] #[] #[] #[]

@[proof_forge_program] def ZAlias : Program := aliasBase
#expect_payloads_prefix "PF-EXPORT-004" as shortPriority004Error
end Tests.Language.ProgramShortNameFixtures.Priority004
