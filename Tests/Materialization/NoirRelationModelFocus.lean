/-
  Thin native-exe entry for Noir Option Int64 + Bytes return pins.
-/
import Tests.Materialization.NoirRelationModel

unsafe def main : IO Unit := do
  Tests.Materialization.NoirRelationModel.testOptionInt64Return
  Tests.Materialization.NoirRelationModel.testBytesReturn
