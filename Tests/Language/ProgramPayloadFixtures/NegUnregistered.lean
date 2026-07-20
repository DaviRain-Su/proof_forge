import ProofForgeV2.Core.Source
import Tests.Language.ProgramPayloadFixtures.Snapshot

namespace Tests.Language.ProgramPayloadFixtures.NegUnregistered
open ProofForgeV2.Source
def UnregProg : Program := Program.build "UnregProg" #[
  ProofForgeV2.Source.Item.entry ⟨"run", #[], .u64, .mutate,
    #[.returnValue (.literal 0)]⟩]
#capture_program_payload_error UnregProg as unregPayloadError
end Tests.Language.ProgramPayloadFixtures.NegUnregistered
