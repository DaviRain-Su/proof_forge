/-
  Targets host/ZK **fast** shard for ordinary CI.

  Omits NoirAcir live/golden capture and CosmWasmPlan heavy plan matrix
  (see TargetsHostSlow). Still covers Aleo, NEAR wasm/sandbox/host model,
  CosmWasm check fixtures, TON, Noir compile acceptance + relation model,
  Psy, Quint.
-/
import Tests.Shards.Runner
import Tests.Materialization.AleoPlanSchemaV1
import Tests.Materialization.AleoInstructionsV1
import Tests.Materialization.AleoPfAssetsV1
import Tests.Materialization.NearWasmAcceptance
import Tests.Materialization.NearSandboxAcceptance
import Tests.Materialization.NearHostModel
import Tests.Materialization.NearStaticAlignmentV1
import Tests.Materialization.CosmWasmCheckAcceptance
import Tests.Materialization.TonPlanV1
import Tests.Materialization.IcpPlanV1
import Tests.Materialization.NoirRelationModel
import Tests.Materialization.NoirCompileAcceptance
import Tests.Materialization.PsyPfAssetsV1
import Tests.Materialization.PsyDpnV1
import Tests.Materialization.QuintSourceV1
import Tests.Materialization.QuintAcceptance
import Tests.Materialization.SorobanPlanV1
import Tests.Materialization.OpenVmGuestSourceV1
import Tests.Product.TokenV1
import Tests.Product.TipJarNearV1
import Tests.Materialization.NearPfAssetsV1
import Tests.Product.TipJarCosmWasmV1
import Tests.Materialization.CosmWasmPfAssetsV1

open Tests.Shards

unsafe def main : IO Unit := do
  runSuite "Tests.Materialization.AleoPlanSchemaV1"
    Tests.Materialization.AleoPlanSchemaV1.run
  runSuite "Tests.Materialization.AleoInstructionsV1"
    Tests.Materialization.AleoInstructionsV1.run
  runSuite "Tests.Materialization.AleoPfAssetsV1" Tests.Materialization.AleoPfAssetsV1.run
  runSuite "Tests.Materialization.NearWasmAcceptance"
    Tests.Materialization.NearWasmAcceptance.run
  runSuite "Tests.Materialization.NearSandboxAcceptance"
    Tests.Materialization.NearSandboxAcceptance.run
  runSuite "Tests.Materialization.CosmWasmCheckAcceptance"
    Tests.Materialization.CosmWasmCheckAcceptance.run
  runSuite "Tests.Materialization.TonPlanV1" Tests.Materialization.TonPlanV1.run
  runSuite "Tests.Materialization.IcpPlanV1" Tests.Materialization.IcpPlanV1.run
  runSuite "Tests.Materialization.NoirCompileAcceptance"
    Tests.Materialization.NoirCompileAcceptance.run
  runSuite "Tests.Materialization.NearHostModel" Tests.Materialization.NearHostModel.run
  runSuite "Tests.Materialization.NearStaticAlignmentV1"
    Tests.Materialization.NearStaticAlignmentV1.run
  runSuite "Tests.Materialization.NoirRelationModel"
    Tests.Materialization.NoirRelationModel.run
  runSuite "Tests.Materialization.PsyPfAssetsV1" Tests.Materialization.PsyPfAssetsV1.run
  runSuite "Tests.Materialization.PsyDpnV1" Tests.Materialization.PsyDpnV1.run
  runSuite "Tests.Materialization.QuintSourceV1" Tests.Materialization.QuintSourceV1.run
  runSuite "Tests.Materialization.QuintAcceptance"
    Tests.Materialization.QuintAcceptance.run
  runSuite "Tests.Materialization.SorobanPlanV1" Tests.Materialization.SorobanPlanV1.run
  runSuite "Tests.Materialization.OpenVmGuestSourceV1"
    Tests.Materialization.OpenVmGuestSourceV1.run
  runSuite "Tests.Product.TokenV1/near" Tests.Product.TokenV1.runNear
  runSuite "Tests.Product.TokenV1/noir" Tests.Product.TokenV1.runNoir
  runSuite "Tests.Product.TipJarNearV1" Tests.Product.TipJarNearV1.run
  runSuite "Tests.Materialization.NearPfAssetsV1" Tests.Materialization.NearPfAssetsV1.run
  runSuite "Tests.Product.TipJarCosmWasmV1" Tests.Product.TipJarCosmWasmV1.run
  runSuite "Tests.Materialization.CosmWasmPfAssetsV1"
    Tests.Materialization.CosmWasmPfAssetsV1.run
  IO.println "shard-targets-host-fast: ok"
