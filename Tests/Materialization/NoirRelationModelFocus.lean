/-
  Thin native-exe entry for the Noir Array-param L5 pin.
-/
import Tests.Materialization.NoirRelationModel

unsafe def main : IO Unit :=
  Tests.Materialization.NoirRelationModel.testArrayParam
