import ProofForgeV2.Core.Source
import Tests.Language.ProgramPayloadFixtures.Snapshot

namespace Tests.Language.ProgramPayloadFixtures.NegImplementedBy
open ProofForgeV2.Source
def hand : Program := Program.build "ImplementedByProg" #[
  .entry { name := "run", params := #[], result := .u64, mode := .mutate
    body := #[.returnValue (.literal 0)] }]
opaque panicProg : Program := panic "must not execute implemented_by replacement"
@[implemented_by panicProg, proof_forge_program]
def ImplementedByProg : Program := hand
#capture_program_payload_error ImplementedByProg as implementedByPayloadError
end Tests.Language.ProgramPayloadFixtures.NegImplementedBy
