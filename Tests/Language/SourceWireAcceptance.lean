import Tests.Language.SourceIdentity
import Tests.Language.SourceNodeTraversalV1
import Tests.Language.SourceSpan

namespace Tests.Language.SourceWireAcceptance

/-- TST-SRC-001 packaging: NodeId traversal/preimage and span suites, once each. -/
unsafe def run : IO Unit := do
  Tests.Language.SourceIdentity.run
  Tests.Language.SourceNodeTraversalV1.run
  Tests.Language.SourceSpan.run

end Tests.Language.SourceWireAcceptance
