import Tests.Materialization.TonPlanV1

/-- Focused TON Plan/IR/Tolk runner (`ton-plan-v1-focus`). -/
unsafe def main : IO Unit :=
  Tests.Materialization.TonPlanV1.run
