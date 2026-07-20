import ProofForgeV2.Core.Source
import Tests.Language.ProgramPayloadFixtures.Snapshot

namespace Tests.Language.ProgramPayloadFixtures.NegUnsafe
open ProofForgeV2.Source
def hand : Program := Program.build "UnsafeProg" #[
  ProofForgeV2.Source.Item.entry ⟨"run", #[], .u64, .mutate,
    #[.returnValue (.literal 0)]⟩]
@[proof_forge_program] unsafe def UnsafeProg : Program := hand
#capture_program_payload_error UnsafeProg as unsafePayloadError
end Tests.Language.ProgramPayloadFixtures.NegUnsafe
