import Tests.Materialization.BuildSelectionV1
import Tests.Materialization.TargetRegistryV1
import Tests.Materialization.RequirementResolverV1
import Tests.Materialization.OutputEnvelopeV1
import Tests.Materialization.EngineeringFinalizationV1
import Tests.Materialization.EngineeringDiskClosureV1
import Tests.Materialization.Targets
import Tests.Materialization.Aleo
import Tests.Materialization.NearHostModel
import Tests.Materialization.NoirRelationModel
import Tests.Materialization.SolanaPlanV1
import Tests.CLI.Emit
import Tests.CLI.ToolchainPolicy
import Tests.CLI.DiagnosticsV1
unsafe def main : IO Unit := do
  IO.eprintln "CP run"
  Tests.Materialization.BuildSelectionV1.run
  IO.eprintln "CP run"
  Tests.Materialization.TargetRegistryV1.run
  IO.eprintln "CP run"
  Tests.Materialization.RequirementResolverV1.run
  IO.eprintln "CP run"
  Tests.Materialization.OutputEnvelopeV1.run
  IO.eprintln "CP run"
  Tests.Materialization.EngineeringFinalizationV1.run
  IO.eprintln "CP run"
  Tests.Materialization.EngineeringDiskClosureV1.run
  IO.eprintln "CP run"
  Tests.Materialization.run
  IO.eprintln "CP run"
  Tests.Materialization.Aleo.run
  IO.eprintln "CP run"
  Tests.Materialization.NearHostModel.run
  IO.eprintln "CP run"
  Tests.Materialization.NoirRelationModel.run
  IO.eprintln "CP run"
  Tests.Materialization.SolanaPlanV1.run
  IO.eprintln "CP run"
  Tests.CLI.Emit.run
  IO.eprintln "CP run"
  Tests.CLI.ToolchainPolicy.run
  IO.eprintln "CP run"
  Tests.CLI.DiagnosticsV1.run
  IO.println "shard-targets: ok"
