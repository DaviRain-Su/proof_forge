import ProofForgeV2.Core.Common
import ProofForgeV2.Source.AstCanonicalRootV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstProgramValidateV1
import ProofForgeV2.Source.QualifiedNameV1

namespace ProofForgeV2.Source.ValidatedSourceV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstCanonicalRootV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstProgramValidateV1
open ProofForgeV2.Source.QualifiedNameV1

/-- A source unit that passed canonical-root and declaration-set validation. -/
structure ValidatedSourceV1 where
  private mk ::
  moduleName : SourceQualifiedNameV1
  programIdentity : SourceQualifiedNameV1
  program : ProgramV1

def validateSourceV1
    (moduleName programIdentity : SourceQualifiedNameV1)
    (program : ProgramV1) : Except String ValidatedSourceV1 := do
  let _ ← canonicalSourceAstBytesV1 moduleName programIdentity program
  validateProgramDeclSetV1 program
  pure ⟨moduleName, programIdentity, program⟩

def canonicalValidatedSourceAstBytesV1
    (source : ValidatedSourceV1) : Except String ByteArray :=
  canonicalSourceAstBytesV1 source.moduleName source.programIdentity source.program

def sourceHashV1 (source : ValidatedSourceV1) : Except String Digest := do
  let bytes ← canonicalValidatedSourceAstBytesV1 source
  domainSeparatedSha256 "pf.source.v1" bytes

end ProofForgeV2.Source.ValidatedSourceV1
