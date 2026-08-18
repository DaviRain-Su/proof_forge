/-
  Thin native-exe entry for EVM Option Int64 + Bytes return pins.
-/
import Tests.Materialization.EvmSmoke

unsafe def main : IO Unit := do
  Tests.Materialization.EvmSmoke.testOptionInt64Return
  Tests.Materialization.EvmSmoke.testBytesReturn
