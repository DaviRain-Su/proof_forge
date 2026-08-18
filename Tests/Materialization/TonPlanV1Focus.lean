/-
  Thin native-exe entry for TON Option/Bytes/Map view-return pins.
-/
import Tests.Materialization.TonPlanV1

unsafe def main : IO Unit := do
  Tests.Materialization.TonPlanV1.testOptionInt64Return
  Tests.Materialization.TonPlanV1.testBytesReturn
  Tests.Materialization.TonPlanV1.testMapReturn
  Tests.Materialization.TonPlanV1.testMapInt64Return
  Tests.Materialization.TonPlanV1.testMapParam
  Tests.Materialization.TonPlanV1.testPrincipalReturn
  Tests.Materialization.TonPlanV1.testStringReturn
