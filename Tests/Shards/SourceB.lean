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
unsafe def main : IO Unit := do
  Tests.Language.SourceAstPatternDecodeV1.run
  Tests.Language.SourceAstSupportDecodeV1.run
  Tests.Language.SourceAstDeclDecodeV1.run
  Tests.Language.SourceAstSpinePlaceExprDecodeV1.run
  Tests.Language.SourceAstSpineStmtDecodeV1.run
  Tests.Language.SourceAstSpineDeclDecodeV1.run
  Tests.Language.SourceAstProgramItemDecodeV1.run
  Tests.Language.SourceAstProgramDecodeV1.run
  Tests.Language.SourceAstCanonicalRootDecodeV1.run
  Tests.Language.SourceIdentity.run
  Tests.Language.SourceNodeAssignmentCollisionV1.run
  Tests.Language.SourceNodeTraversalV1.run
  Tests.Language.SourceProgramWireBoundaryGoldenV1.run
  Tests.Language.SourceProgramWireFieldCountGoldenV1.run
  Tests.Language.SourceProgramWireGoldenV1.run
  Tests.Language.SourceProgramWireMarkerGoldenV1.run
  Tests.Language.SourceProgramWireUnknownTagGoldenV1.run
  Tests.Language.SourceSpan.run
  IO.println "shard-source-b: ok"
