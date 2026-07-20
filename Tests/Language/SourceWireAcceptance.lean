import Tests.Language.SourceIdentity
import Tests.Language.SourceSpan

namespace Tests.Language.SourceWireAcceptance

/-- TST-SRC-001 packaging: existing NodeId/span development suites, once each. -/
unsafe def run : IO Unit := do
  Tests.Language.SourceIdentity.run
  Tests.Language.SourceSpan.run

end Tests.Language.SourceWireAcceptance
