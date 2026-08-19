/-
  Thin native-exe entry for EVM Option Int64 + Bytes + Principal/String return pins.
-/
import Tests.Materialization.EvmSmoke

unsafe def main : IO Unit := do
  Tests.Materialization.EvmSmoke.testOptionInt64Return
  Tests.Materialization.EvmSmoke.testBytesReturn
  Tests.Materialization.EvmSmoke.testPrincipalReturn
  Tests.Materialization.EvmSmoke.testStringReturn
  Tests.Materialization.EvmSmoke.testCryptoSha256BytesEvm
  Tests.Materialization.EvmSmoke.testCryptoMerkleVerifyKeccak256Evm
  Tests.Materialization.EvmSmoke.testConstStr
  Tests.Materialization.EvmSmoke.testStrMatch
