/-
  Thin native-exe entry for the EVM Array-param L5 pin.
-/
import Tests.Materialization.EvmSmoke

unsafe def main : IO Unit :=
  Tests.Materialization.EvmSmoke.testArrayParam
