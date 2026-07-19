import ProofForgeV2.Core.Source
import Tests.Language.ProgramPayloadFixtures.Snapshot

namespace Tests.Language.ProgramPayloadFixtures.NegUnsafe
open ProofForgeV2.Source
def hand : Program := Program.build "UnsafeProg" #[
  .entry { name := "run", params := #[], result := .u64, mode := .mutate
    body := #[.returnValue (.literal 0)] }]
@[proof_forge_program] unsafe def UnsafeProg : Program := hand
#capture_program_payload_error UnsafeProg as unsafePayloadError
end Tests.Language.ProgramPayloadFixtures.NegUnsafe
