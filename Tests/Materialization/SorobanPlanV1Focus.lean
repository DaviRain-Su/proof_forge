/-
  Thin native-exe entry for the Soroban S0 Plan/IR suite.
-/
import Tests.Materialization.SorobanPlanV1

unsafe def main : IO Unit :=
  Tests.Materialization.SorobanPlanV1.run
