import ProofForgeV2.Core.Source
import Tests.Language.ProgramPayloadFixtures.Snapshot

namespace Tests.Language.ProgramPayloadFixtures.NegPartial
open ProofForgeV2.Source
def hand : Program := Program.build "PartialProg" #[
  .entry { name := "run", params := #[], result := .u64, mode := .mutate
    body := #[.returnValue (.literal 0)] }]
@[proof_forge_program] partial def PartialProg : Program := hand
#capture_program_payload_error PartialProg as partialPayloadError
end Tests.Language.ProgramPayloadFixtures.NegPartial
