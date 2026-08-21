/-
  Zero-tool product smoke shard.

  This shard is run with PROOF_FORGE_TOOL_ROOT pointing at a missing path. Real
  solc/sBPF/wat2wasm finalization belongs to the provisioned target shards.
-/
import Tests.Shards.Runner
import Tests.Product.StateCellV1Evm
import Tests.Product.PrivateSum4PrivacyV1
import Tests.Product.PerfCheckHarnessV1
import Tests.Product.TokenV1
import Tests.Product.TipJarQuintV1

open Tests.Shards

unsafe def main : IO Unit := do
  runSuite "Tests.Product.StateCellV1Evm" Tests.Product.StateCellV1Evm.run
  runSuite "Tests.Product.PrivateSum4PrivacyV1" Tests.Product.PrivateSum4PrivacyV1.run
  runSuite "Tests.Product.PerfCheckHarnessV1" Tests.Product.PerfCheckHarnessV1.run
  runSuite "Tests.Product.TokenV1/core" Tests.Product.TokenV1.runCore
  runSuite "Tests.Product.TipJarQuintV1" Tests.Product.TipJarQuintV1.run
  IO.println "shard-product-fast: ok"
