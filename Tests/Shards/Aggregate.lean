import Tests.Shards.Runner
import Tests.Language.AggregateDeclarations
import Tests.Language.StateVisibility
import Tests.Language.FrontendParity
import Tests.Frontend.ProtocolV1

open Tests.Shards

unsafe def main : IO Unit := do
  runSuite "Tests.Language.AggregateDeclarations" Tests.Language.AggregateDeclarations.run
  runSuite "Tests.Language.StateVisibility" Tests.Language.StateVisibility.run
  runSuite "Tests.Language.FrontendParity" Tests.Language.FrontendParity.run
  runSuite "Tests.Frontend.ProtocolV1" Tests.Frontend.ProtocolV1.run
  IO.println "shard-aggregate: ok"
