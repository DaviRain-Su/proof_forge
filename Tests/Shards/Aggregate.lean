import Tests.Language.AggregateDeclarations
import Tests.Language.StateVisibility
import Tests.Language.FrontendParity
unsafe def main : IO Unit := do
  Tests.Language.AggregateDeclarations.run
  Tests.Language.StateVisibility.run
  Tests.Language.FrontendParity.run
  IO.println "shard-aggregate: ok"
