import ProofForgeV2.Language.Syntax
import ProofForgeV2.Core.Source
import ProofForgeV2.Language.ProgramExport
import Tests.Language.ProgramBindingFixtures.Snapshot

-- DSL nested + escaped namespace (elaborator qname == declaration.toString).
namespace Tests.Language.ProgramBindingFixtures.Positive.«ns-1»
open ProofForgeV2.Language
program OkEsc where
  entry run() : UInt64 do
    return 0
end Tests.Language.ProgramBindingFixtures.Positive.«ns-1»

namespace Tests.Language.ProgramBindingFixtures.Positive
open ProofForgeV2.Source

-- Hand direct Program.mk exact-aligned with declaration FQN.
@[proof_forge_program] def HandOk : Program :=
  Program.mk "Tests.Language.ProgramBindingFixtures.Positive.HandOk" "HandOk"
    #[] #[] #[] #[] #[] #[] none
    #[{ name := "run", params := #[], result := .u64, mode := .mutate
        body := #[.returnValue (.literal (UInt64.ofNat 0))] }]
    #[] #[] #[] #[]

#snapshot_binding_table positiveBindingTable
#snapshot_binding_payload
  Tests.Language.ProgramBindingFixtures.Positive.«ns-1».OkEsc as positiveEscSingle
#snapshot_binding_payload HandOk as positiveHandSingle
end Tests.Language.ProgramBindingFixtures.Positive
