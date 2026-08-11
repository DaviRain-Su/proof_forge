/-
  Targets host / ZK / model shard: NEAR, CosmWasm, TON, Noir, Psy, Quint, Aleo.

  Includes slower acceptance suites (Noir ACIR, CosmWasm plan, near-sandbox)
  so they no longer serialize behind EVM+Solana Lean pins in one process.
-/
import Tests.Materialization.AleoPlanSchemaV1
import Tests.Materialization.AleoInstructionsV1
import Tests.Materialization.AleoPfAssetsV1
import Tests.Materialization.NearWasmAcceptance
import Tests.Materialization.NearSandboxAcceptance
import Tests.Materialization.NearHostModel
import Tests.Materialization.NearStaticAlignmentV1
import Tests.Materialization.CosmWasmCheckAcceptance
import Tests.Materialization.CosmWasmPlanV1
import Tests.Materialization.TonPlanV1
import Tests.Materialization.NoirRelationModel
import Tests.Materialization.NoirCompileAcceptance
import Tests.Materialization.NoirAcirV1
import Tests.Materialization.PsyPfAssetsV1
import Tests.Materialization.PsyDpnV1
import Tests.Materialization.QuintSourceV1
import Tests.Materialization.QuintAcceptance

unsafe def main : IO Unit := do
  IO.eprintln "CP run"
  Tests.Materialization.AleoPlanSchemaV1.run
  Tests.Materialization.AleoInstructionsV1.run
  IO.eprintln "CP run"
  Tests.Materialization.AleoPfAssetsV1.run
  IO.eprintln "CP run"
  Tests.Materialization.NearWasmAcceptance.run
  IO.eprintln "CP run"
  Tests.Materialization.NearSandboxAcceptance.run
  IO.eprintln "CP run"
  Tests.Materialization.CosmWasmCheckAcceptance.run
  IO.eprintln "CP run"
  Tests.Materialization.CosmWasmPlanV1.run
  IO.eprintln "CP run"
  Tests.Materialization.TonPlanV1.run
  IO.eprintln "CP run"
  Tests.Materialization.NoirCompileAcceptance.run
  IO.eprintln "CP run"
  Tests.Materialization.NoirAcirV1.run
  IO.eprintln "CP run"
  Tests.Materialization.NearHostModel.run
  Tests.Materialization.NearStaticAlignmentV1.run
  IO.eprintln "CP run"
  Tests.Materialization.NoirRelationModel.run
  IO.eprintln "CP run"
  Tests.Materialization.PsyPfAssetsV1.run
  IO.eprintln "CP run"
  Tests.Materialization.PsyDpnV1.run
  IO.eprintln "CP run"
  Tests.Materialization.QuintSourceV1.run
  IO.eprintln "CP run"
  Tests.Materialization.QuintAcceptance.run
  IO.println "shard-targets-host: ok"
