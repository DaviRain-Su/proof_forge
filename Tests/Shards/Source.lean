import Tests.Shards.Runner
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

open Tests.Shards

unsafe def main : IO Unit := do
  runSuite "Tests.Language.SourceWireAcceptance" Tests.Language.SourceWireAcceptance.run
  runSuite "Tests.Language.SourceWireCodecV1" Tests.Language.SourceWireCodecV1.run
  runSuite "Tests.Language.SourceWireDecodeV1" Tests.Language.SourceWireDecodeV1.run
  runSuite "Tests.Language.SourceNameComponentV1" Tests.Language.SourceNameComponentV1.run
  runSuite "Tests.Language.SourceQualifiedNameV1" Tests.Language.SourceQualifiedNameV1.run
  runSuite "Tests.Language.SourceAstLeafV1" Tests.Language.SourceAstLeafV1.run
  runSuite "Tests.Language.SourceAstSupportV1" Tests.Language.SourceAstSupportV1.run
  runSuite "Tests.Language.SourceAstPatternV1" Tests.Language.SourceAstPatternV1.run
  runSuite "Tests.Language.SourceAstDeclV1" Tests.Language.SourceAstDeclV1.run
  runSuite "Tests.Language.SourceAstSpineV1" Tests.Language.SourceAstSpineV1.run
  runSuite "Tests.Language.SourceAstSpineCodecV1" Tests.Language.SourceAstSpineCodecV1.run
  runSuite "Tests.Language.SourceAstSpineDeclV1" Tests.Language.SourceAstSpineDeclV1.run
  runSuite "Tests.Language.SourceAstProgramItemV1"
    Tests.Language.SourceAstProgramItemV1.run
  runSuite "Tests.Language.SourceAstProgramV1" Tests.Language.SourceAstProgramV1.run
  runSuite "Tests.Language.SourceAstCanonicalRootV1"
    Tests.Language.SourceAstCanonicalRootV1.run
  runSuite "Tests.Language.SourceAstProgramValidateV1"
    Tests.Language.SourceAstProgramValidateV1.run
  runSuite "Tests.Language.SourceAstWideEncoderV1" Tests.Language.SourceAstWideEncoderV1.run
  runSuite "Tests.Language.SourceAstScalarDecodeV1"
    Tests.Language.SourceAstScalarDecodeV1.run
  runSuite "Tests.Language.SourceAstTypeDecodeV1" Tests.Language.SourceAstTypeDecodeV1.run
  IO.println "shard-source: ok"
