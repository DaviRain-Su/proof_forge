import Tests.Language.AggregateDeclarations
import Tests.Language.StateVisibility
import Tests.Language.FrontendParity
import Tests.Frontend.ProtocolV1
unsafe def main : IO Unit := do
  Tests.Language.AggregateDeclarations.run
  Tests.Language.StateVisibility.run
  Tests.Language.FrontendParity.run
  Tests.Frontend.ProtocolV1.run
  IO.println "shard-aggregate: ok"
