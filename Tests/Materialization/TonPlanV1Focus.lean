/-
  Thin native-exe entry for the TON Array-param L5 pin.
-/
import Tests.Materialization.TonPlanV1

unsafe def main : IO Unit :=
  Tests.Materialization.TonPlanV1.testArrayParam
