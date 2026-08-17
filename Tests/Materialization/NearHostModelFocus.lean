/-
  Thin native-exe entry for the NEAR Map-param L6 pin.
-/
import Tests.Materialization.NearHostModel

unsafe def main : IO Unit :=
  Tests.Materialization.NearHostModel.testMapParam
