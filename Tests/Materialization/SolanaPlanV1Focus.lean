/-
  Thin native-exe entry for Solana Option Int64 + Bytes return pins.
-/
import Tests.Materialization.SolanaPlanV1

unsafe def main : IO Unit := do
  Tests.Materialization.SolanaPlanV1.testOptionInt64Return
  Tests.Materialization.SolanaPlanV1.testBytesReturn
