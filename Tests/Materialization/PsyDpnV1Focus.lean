/-
  Thin native-exe entry for the Psy Array-param L5 pin.
-/
import Tests.Materialization.PsyDpnV1

unsafe def main : IO Unit :=
  Tests.Materialization.PsyDpnV1.testOptionInt64Return
