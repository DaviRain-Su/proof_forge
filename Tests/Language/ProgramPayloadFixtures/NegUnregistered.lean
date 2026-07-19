import ProofForgeV2.Core.Source
import Tests.Language.ProgramPayloadFixtures.Snapshot

namespace Tests.Language.ProgramPayloadFixtures.NegUnregistered
open ProofForgeV2.Source
def UnregProg : Program := Program.build "UnregProg" #[
  .entry { name := "run", params := #[], result := .u64, mode := .mutate
    body := #[.returnValue (.literal 0)] }]
#capture_program_payload_error UnregProg as unregPayloadError
end Tests.Language.ProgramPayloadFixtures.NegUnregistered
