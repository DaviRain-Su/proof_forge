/-
  Thin native-exe entry for TON Option Int64 + Bytes view-return pins.
-/
import Tests.Materialization.TonPlanV1

unsafe def main : IO Unit := do
  Tests.Materialization.TonPlanV1.testOptionInt64Return
  Tests.Materialization.TonPlanV1.testBytesReturn
