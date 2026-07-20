import ProofForgeV2.Core.Source
import Tests.Language.ProgramPayloadFixtures.Snapshot

namespace Tests.Language.ProgramPayloadFixtures.NegPartial
open ProofForgeV2.Source
def hand : Program := Program.build "PartialProg" #[
  ProofForgeV2.Source.Item.entry ⟨"run", #[], .u64, .mutate,
    #[.returnValue (.literal 0)]⟩]
@[proof_forge_program] partial def PartialProg : Program := hand
#capture_program_payload_error PartialProg as partialPayloadError
end Tests.Language.ProgramPayloadFixtures.NegPartial
