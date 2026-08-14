/-
  Thin native-exe entry for the ICP Plan/IR suite (ICP-2).
-/
import Tests.Materialization.IcpPlanV1

unsafe def main : IO Unit :=
  Tests.Materialization.IcpPlanV1.run
