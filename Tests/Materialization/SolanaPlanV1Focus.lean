/-
  Thin native-exe entry for Solana Option/Bytes/Map B-RET pins.
-/
import Tests.Materialization.SolanaPlanV1

unsafe def main : IO Unit := do
  Tests.Materialization.SolanaPlanV1.testOptionInt64Return
  Tests.Materialization.SolanaPlanV1.testBytesReturn
  Tests.Materialization.SolanaPlanV1.testMapReturn
  Tests.Materialization.SolanaPlanV1.testMapInt64Return
  Tests.Materialization.SolanaPlanV1.testMapParam
  Tests.Materialization.SolanaPlanV1.testPrincipalReturn
  Tests.Materialization.SolanaPlanV1.testStringReturn
