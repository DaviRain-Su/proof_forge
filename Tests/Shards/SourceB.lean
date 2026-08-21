import Tests.Shards.Runner
import Tests.Language.SourceAstPatternDecodeV1
import Tests.Language.SourceAstSupportDecodeV1
import Tests.Language.SourceAstDeclDecodeV1
import Tests.Language.SourceAstSpinePlaceExprDecodeV1
import Tests.Language.SourceAstSpineStmtDecodeV1
import Tests.Language.SourceAstSpineDeclDecodeV1
import Tests.Language.SourceAstProgramItemDecodeV1
import Tests.Language.SourceAstProgramDecodeV1
import Tests.Language.SourceAstCanonicalRootDecodeV1
import Tests.Language.SourceIdentity
import Tests.Language.SourceNodeAssignmentCollisionV1
import Tests.Language.SourceNodeTraversalV1
import Tests.Language.SourceProgramWireBoundaryGoldenV1
import Tests.Language.SourceProgramWireFieldCountGoldenV1
import Tests.Language.SourceProgramWireGoldenV1
import Tests.Language.SourceProgramWireMarkerGoldenV1
import Tests.Language.SourceProgramWireUnknownTagGoldenV1
import Tests.Language.SourceSpan

open Tests.Shards

unsafe def main : IO Unit := do
  runSuite "Tests.Language.SourceAstPatternDecodeV1"
    Tests.Language.SourceAstPatternDecodeV1.run
  runSuite "Tests.Language.SourceAstSupportDecodeV1"
    Tests.Language.SourceAstSupportDecodeV1.run
  runSuite "Tests.Language.SourceAstDeclDecodeV1" Tests.Language.SourceAstDeclDecodeV1.run
  runSuite "Tests.Language.SourceAstSpinePlaceExprDecodeV1"
    Tests.Language.SourceAstSpinePlaceExprDecodeV1.run
  runSuite "Tests.Language.SourceAstSpineStmtDecodeV1"
    Tests.Language.SourceAstSpineStmtDecodeV1.run
  runSuite "Tests.Language.SourceAstSpineDeclDecodeV1"
    Tests.Language.SourceAstSpineDeclDecodeV1.run
  runSuite "Tests.Language.SourceAstProgramItemDecodeV1"
    Tests.Language.SourceAstProgramItemDecodeV1.run
  runSuite "Tests.Language.SourceAstProgramDecodeV1"
    Tests.Language.SourceAstProgramDecodeV1.run
  runSuite "Tests.Language.SourceAstCanonicalRootDecodeV1"
    Tests.Language.SourceAstCanonicalRootDecodeV1.run
  runSuite "Tests.Language.SourceIdentity" Tests.Language.SourceIdentity.run
  runSuite "Tests.Language.SourceNodeAssignmentCollisionV1"
    Tests.Language.SourceNodeAssignmentCollisionV1.run
  runSuite "Tests.Language.SourceNodeTraversalV1" Tests.Language.SourceNodeTraversalV1.run
  runSuite "Tests.Language.SourceProgramWireBoundaryGoldenV1"
    Tests.Language.SourceProgramWireBoundaryGoldenV1.run
  runSuite "Tests.Language.SourceProgramWireFieldCountGoldenV1"
    Tests.Language.SourceProgramWireFieldCountGoldenV1.run
  runSuite "Tests.Language.SourceProgramWireGoldenV1"
    Tests.Language.SourceProgramWireGoldenV1.run
  runSuite "Tests.Language.SourceProgramWireMarkerGoldenV1"
    Tests.Language.SourceProgramWireMarkerGoldenV1.run
  runSuite "Tests.Language.SourceProgramWireUnknownTagGoldenV1"
    Tests.Language.SourceProgramWireUnknownTagGoldenV1.run
  runSuite "Tests.Language.SourceSpan" Tests.Language.SourceSpan.run
  IO.println "shard-source-b: ok"
