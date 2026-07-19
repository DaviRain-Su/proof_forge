import ProofForgeV2.Core.Source
import Tests.Language.ProgramPayloadFixtures.Snapshot

namespace Tests.Language.ProgramPayloadFixtures.NegOpaque
open ProofForgeV2.Source
def hand : Program := Program.build "OpaqueProg" #[
  .entry { name := "run", params := #[], result := .u64, mode := .mutate
    body := #[.returnValue (.literal 0)] }]
@[proof_forge_program] opaque OpaqueProg : Program := hand
#capture_program_payload_error OpaqueProg as opaquePayloadError
end Tests.Language.ProgramPayloadFixtures.NegOpaque
