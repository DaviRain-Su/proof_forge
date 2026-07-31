import Tests.Language.SourceWireAcceptance
import Tests.Language.SourceWireCodecV1
import Tests.Language.SourceWireDecodeV1
import Tests.Language.SourceNameComponentV1
import Tests.Language.SourceQualifiedNameV1
import Tests.Language.SourceAstLeafV1
import Tests.Language.SourceAstSupportV1
import Tests.Language.SourceAstPatternV1
import Tests.Language.SourceAstDeclV1
import Tests.Language.SourceAstSpineV1
import Tests.Language.SourceAstSpineCodecV1
import Tests.Language.SourceAstSpineDeclV1
import Tests.Language.SourceAstProgramItemV1
import Tests.Language.SourceAstProgramV1
import Tests.Language.SourceAstCanonicalRootV1
import Tests.Language.SourceAstProgramValidateV1
import Tests.Language.SourceAstWideEncoderV1
import Tests.Language.SourceAstScalarDecodeV1
import Tests.Language.SourceAstTypeDecodeV1
unsafe def main : IO Unit := do
  Tests.Language.SourceWireAcceptance.run
  Tests.Language.SourceWireCodecV1.run
  Tests.Language.SourceWireDecodeV1.run
  Tests.Language.SourceNameComponentV1.run
  Tests.Language.SourceQualifiedNameV1.run
  Tests.Language.SourceAstLeafV1.run
  Tests.Language.SourceAstSupportV1.run
  Tests.Language.SourceAstPatternV1.run
  Tests.Language.SourceAstDeclV1.run
  Tests.Language.SourceAstSpineV1.run
  Tests.Language.SourceAstSpineCodecV1.run
  Tests.Language.SourceAstSpineDeclV1.run
  Tests.Language.SourceAstProgramItemV1.run
  Tests.Language.SourceAstProgramV1.run
  Tests.Language.SourceAstCanonicalRootV1.run
  Tests.Language.SourceAstProgramValidateV1.run
  Tests.Language.SourceAstWideEncoderV1.run
  Tests.Language.SourceAstScalarDecodeV1.run
  Tests.Language.SourceAstTypeDecodeV1.run
  IO.println "shard-source: ok"
