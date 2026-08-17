/-
  Thin native-exe entry for the Solana Array-param L5 pin.
-/
import Tests.Materialization.SolanaPlanV1

unsafe def main : IO Unit :=
  Tests.Materialization.SolanaPlanV1.testArrayParam
