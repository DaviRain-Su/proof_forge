import ProofForgeV2.Source.AstProgramCodecV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.WireCodecV1

namespace ProofForgeV2.Source.AstCanonicalRootV1

open ProofForgeV2.Source.AstProgramCodecV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.WireCodecV1

private def fail (detail : String) : Except String α :=
  .error detail

private def nameMismatchErr :=
  "program name must equal the last program identity component"

private def lastComponent (name : SourceQualifiedNameV1) : SourceNameComponentV1 :=
  name.components.tail.back?.getD name.components.head

def canonicalSourceAstBytesV1
    (moduleName programIdentity : SourceQualifiedNameV1)
    (program : ProgramV1) : Except String ByteArray := do
  validateSourceProgramIdentityV1 moduleName programIdentity
  unless program.name == lastComponent programIdentity do
    return ← fail nameMismatchErr
  let moduleBytes ← encodeSourceQualifiedNameV1 moduleName
  let identityBytes ← encodeSourceQualifiedNameV1 programIdentity
  let programBytes ← encodeProgramV1 program
  pure (moduleBytes.append (identityBytes.append programBytes))

end ProofForgeV2.Source.AstCanonicalRootV1
