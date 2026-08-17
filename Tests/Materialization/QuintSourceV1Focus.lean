/-
  Thin native-exe entry for the Quint Q0 Plan/IR suite.
-/
import Tests.Materialization.QuintSourceV1

unsafe def main : IO Unit :=
  Tests.Materialization.QuintSourceV1.run
