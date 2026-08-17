/-
  Thin native-exe entry for the XRPL Plan/IR suite (ADR-0049 Q0).
-/
import Tests.Materialization.XrplPlanV1

unsafe def main : IO Unit :=
  Tests.Materialization.XrplPlanV1.run
