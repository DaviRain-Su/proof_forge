/-
  Thin native-exe entry for NEAR Option Int64 + Map Int64 return pins.
-/
import Tests.Materialization.NearHostModel

unsafe def main : IO Unit := do
  Tests.Materialization.NearHostModel.testOptionInt64Return
  Tests.Materialization.NearHostModel.testMapInt64Return
