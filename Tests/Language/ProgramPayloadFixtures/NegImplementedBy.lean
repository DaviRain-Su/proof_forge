import ProofForgeV2.Core.Source
import Tests.Language.ProgramPayloadFixtures.Snapshot

namespace Tests.Language.ProgramPayloadFixtures.NegImplementedBy
open ProofForgeV2.Source
def hand : Program := Program.build "ImplementedByProg" #[
  ProofForgeV2.Source.Item.entry ⟨"run", #[], .u64, .mutate,
    #[.returnValue (.literal 0)]⟩]
def replacementProg : Program :=
  Program.mk "ReplacementMustNotBeFollowed" "ReplacementMustNotBeFollowed"
    #[] #[] #[] #[] #[] #[] none #[] #[] #[] #[] #[]
@[implemented_by replacementProg, proof_forge_program]
def ImplementedByProg : Program := hand
#capture_program_payload_error ImplementedByProg as implementedByPayloadError
end Tests.Language.ProgramPayloadFixtures.NegImplementedBy
