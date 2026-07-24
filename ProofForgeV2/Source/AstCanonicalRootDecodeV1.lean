import ProofForgeV2.Source.AstProgramDecodeV1
import ProofForgeV2.Source.DecodeBudgetV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Source.WireDecodeV1

namespace ProofForgeV2.Source.AstCanonicalRootDecodeV1

open ProofForgeV2.Source.AstProgramDecodeV1
open ProofForgeV2.Source.DecodeBudgetV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireDecodeV1

private def fail (detail : String) : Except String α :=
  .error detail

private def maxSourceBytesV1 : Nat :=
  16 * 1024 * 1024

/-- Decode one complete canonical Source.ProgramV1 root under the fixed v1 session limits. -/
def decodeCanonicalSourceAstBytesV1 (input : ByteArray) :
    Except String ValidatedSourceV1 := do
  if input.size > maxSourceBytesV1 then
    return ← fail "source exceeds the 16 MiB limit"
  let cursor := start input
  let (moduleName, cursor) ← decodeSourceQualifiedNameV1 cursor
  let (programIdentity, cursor) ← decodeSourceQualifiedIdV1 cursor
  let ((program, _residual), cursor) ←
    decodeProgramV1 256 { remainingNodes := 100000 } cursor
  finish cursor
  validateSourceV1 moduleName programIdentity program

end ProofForgeV2.Source.AstCanonicalRootDecodeV1
