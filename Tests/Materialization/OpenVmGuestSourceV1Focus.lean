/-
  Thin native-exe entry for the OpenVM O0 Plan/IR suite.
-/
import Tests.Materialization.OpenVmGuestSourceV1

unsafe def main : IO Unit :=
  Tests.Materialization.OpenVmGuestSourceV1.run
