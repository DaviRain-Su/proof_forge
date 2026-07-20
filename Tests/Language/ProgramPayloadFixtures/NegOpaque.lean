import ProofForgeV2.Core.Source
import Tests.Language.ProgramPayloadFixtures.Snapshot

namespace Tests.Language.ProgramPayloadFixtures.NegOpaque
open ProofForgeV2.Source
def hand : Program := Program.build "OpaqueProg" #[
  ProofForgeV2.Source.Item.entry ⟨"run", #[], .u64, .mutate,
    #[.returnValue (.literal 0)]⟩]
@[proof_forge_program] opaque OpaqueProg : Program := hand
#capture_program_payload_error OpaqueProg as opaquePayloadError
end Tests.Language.ProgramPayloadFixtures.NegOpaque
