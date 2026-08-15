import Tests.Materialization.CosmWasmPlanV1

/-- Focused CosmWasm Plan/IR/WAT runner (`cosmwasm-plan-v1-focus`). -/
unsafe def main : IO Unit :=
  Tests.Materialization.CosmWasmPlanV1.run
