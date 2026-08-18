/-
  Thin native-exe entry for Noir Option/Bytes/Map B-RET pins.
-/
import Tests.Materialization.NoirRelationModel

unsafe def main : IO Unit := do
  Tests.Materialization.NoirRelationModel.testOptionInt64Return
  Tests.Materialization.NoirRelationModel.testBytesReturn
  Tests.Materialization.NoirRelationModel.testMapReturn
  Tests.Materialization.NoirRelationModel.testMapInt64Return
  Tests.Materialization.NoirRelationModel.testMapParam
  Tests.Materialization.NoirRelationModel.testPrincipalReturn
  Tests.Materialization.NoirRelationModel.testStringReturn
