import ProofForgeV2.Language.Syntax
import ProofForgeV2.Core.Source
import ProofForgeV2.Language.ProgramExport
import Tests.Language.ProgramShortNameFixtures.Snapshot

namespace Tests.Language.ProgramShortNameFixtures.Positive
open ProofForgeV2.Language

program simple where
  entry run() : UInt64 do return 0

program «hyphen-prog» where
  entry run() : UInt64 do return 0

program «dot.prog» where
  entry run() : UInt64 do return 0

open ProofForgeV2.Source

@[proof_forge_program] def HandOk : Program :=
  Program.mk "Tests.Language.ProgramShortNameFixtures.Positive.HandOk" "HandOk"
    #[] #[] #[] #[] #[] #[] none
    #[{ name := "run", params := #[], result := .u64, mode := .mutate
        body := #[.returnValue (.literal (UInt64.ofNat 0))] }] #[] #[] #[] #[]

#snapshot_short_table positiveShortTable
#snapshot_short_payload simple as positiveSimpleSingle
#snapshot_short_payload «hyphen-prog» as positiveHyphenSingle
#snapshot_short_payload «dot.prog» as positiveDotSingle
#snapshot_short_payload HandOk as positiveHandSingle
end Tests.Language.ProgramShortNameFixtures.Positive
