import Tests.Language.SourceIdentity
import Tests.Language.SourceNodeAssignmentCollisionV1
import Tests.Language.SourceNodeTraversalV1
import Tests.Language.SourceProgramWireFieldCountGoldenV1
import Tests.Language.SourceProgramWireGoldenV1
import Tests.Language.SourceProgramWireMarkerGoldenV1
import Tests.Language.SourceProgramWireUnknownTagGoldenV1
import Tests.Language.SourceSpan

namespace Tests.Language.SourceWireAcceptance

/-- TST-SRC-001 packaging: NodeId traversal/preimage and span suites, once each. -/
unsafe def run : IO Unit := do
  Tests.Language.SourceIdentity.run
  Tests.Language.SourceNodeTraversalV1.run
  Tests.Language.SourceNodeAssignmentCollisionV1.run
  Tests.Language.SourceProgramWireGoldenV1.run
  Tests.Language.SourceProgramWireFieldCountGoldenV1.run
  Tests.Language.SourceProgramWireMarkerGoldenV1.run
  Tests.Language.SourceProgramWireUnknownTagGoldenV1.run
  Tests.Language.SourceSpan.run

end Tests.Language.SourceWireAcceptance
