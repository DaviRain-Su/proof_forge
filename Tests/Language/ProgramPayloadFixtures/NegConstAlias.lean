import ProofForgeV2.Core.Source
import Tests.Language.ProgramPayloadFixtures.Snapshot

namespace Tests.Language.ProgramPayloadFixtures.NegConstAlias
open ProofForgeV2.Source
def baseProg : Program := Program.build "AliasProg" #[
  .entry { name := "run", params := #[], result := .u64, mode := .mutate
    body := #[.returnValue (.literal 0)] }]
@[proof_forge_program] def AliasProg : Program := baseProg
#capture_program_payload_error AliasProg as aliasPayloadError
#capture_program_payloads_error as aliasTableError
end Tests.Language.ProgramPayloadFixtures.NegConstAlias
