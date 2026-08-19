/-
  Thin native-exe entry for Psy Option/Map B-RET pins.
-/
import Tests.Materialization.PsyDpnV1

unsafe def main : IO Unit := do
  Tests.Materialization.PsyDpnV1.testOptionInt64Return
  Tests.Materialization.PsyDpnV1.testMapReturn
  Tests.Materialization.PsyDpnV1.testMapInt64Return
  Tests.Materialization.PsyDpnV1.testMapParam
  Tests.Materialization.PsyDpnV1.testPrincipalReturn
  Tests.Materialization.PsyDpnV1.testStringReturn
  Tests.Materialization.PsyDpnV1.testConstStr
  Tests.Materialization.PsyDpnV1.testStrMatch
