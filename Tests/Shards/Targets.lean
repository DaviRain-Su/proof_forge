import Tests.Materialization.BuildSelectionV1
import Tests.Materialization.TargetRegistryV1
import Tests.Materialization.RegistryRootV1
import Tests.Materialization.RequirementResolverV1
import Tests.Materialization.IdentityChainV1
import Tests.Materialization.EvmPlanSchemaV1
import Tests.Materialization.AleoPlanSchemaV1
import Tests.Materialization.EvmSmoke
import Tests.Materialization.EvmSolcAcceptance
import Tests.Materialization.NearWasmAcceptance
import Tests.Materialization.NearSandboxAcceptance
import Tests.Materialization.CosmWasmCheckAcceptance
import Tests.Materialization.CosmWasmPlanV1
import Tests.Materialization.TonPlanV1
import Tests.Materialization.OutputSetV1

import Tests.Materialization.OutputEnvelopeV1
import Tests.Materialization.EngineeringFinalizationV1
import Tests.Materialization.ArtifactContentV1
import Tests.Materialization.EngineeringDiskClosureV1
import Tests.Materialization.Targets
import Tests.Materialization.Aleo
import Tests.Materialization.AleoPfAssetsV1
import Tests.Materialization.AleoAcceptance
import Tests.Materialization.AleoCompiledFinalizationV1
import Tests.Materialization.NearHostModel
import Tests.Materialization.NoirRelationModel
import Tests.Materialization.NoirCompileAcceptance
import Tests.Materialization.SolanaPlanV1
import Tests.Materialization.SolanaCpiPlanV1
import Tests.Materialization.SolanaCpiDeriveV1
import Tests.Materialization.SolanaCpiPreflightV1
import Tests.Materialization.SolanaCpiUnsignedV1
import Tests.Materialization.SolanaCpiPdaV1
import Tests.Materialization.SolanaCpiSystemV1
import Tests.Materialization.SolanaCpiTokenV1
import Tests.Materialization.SolanaCpiAtaV1
import Tests.Materialization.SolanaCpiEscrowV1
import Tests.Materialization.SolanaCpiActivationV1
import Tests.Targets.SolanaAsmV1
import Tests.Targets.SolanaElfV1
import Tests.Targets.EvmCancunV1
import Tests.Materialization.EvmCorpusBlockedV1
import Tests.Materialization.PsySourceV1
import Tests.Materialization.PsyPfAssetsV1
import Tests.Materialization.PsyDpnV1
import Tests.Materialization.PsyAcceptance
import Tests.Materialization.QuintSourceV1
import Tests.Materialization.QuintAcceptance
import Tests.CLI.Emit
import Tests.CLI.ToolchainPolicy
import Tests.CLI.DiagnosticsV1
import Tests.CLI.ResourceFlagsV1
import Tests.CLI.InlineProofProductV1
unsafe def main : IO Unit := do
  IO.eprintln "CP run"
  Tests.Materialization.BuildSelectionV1.run
  IO.eprintln "CP run"
  Tests.Materialization.TargetRegistryV1.run
  IO.eprintln "CP run"
  Tests.Materialization.RegistryRootV1.run
  IO.eprintln "CP run"
  Tests.Materialization.RequirementResolverV1.run
  IO.eprintln "CP run"
  Tests.Materialization.IdentityChainV1.run
  IO.eprintln "CP run"
  Tests.Materialization.EvmPlanSchemaV1.run
  IO.eprintln "CP run"
  Tests.Materialization.AleoPlanSchemaV1.run
  IO.eprintln "CP run"
  Tests.Materialization.EvmSmoke.run
  IO.eprintln "CP run"
  Tests.Materialization.EvmSolcAcceptance.run
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
  Tests.Materialization.OutputSetV1.run

  IO.eprintln "CP run"
  Tests.Materialization.OutputEnvelopeV1.run
  IO.eprintln "CP run"
  Tests.Materialization.EngineeringFinalizationV1.run
  IO.eprintln "CP run"
  Tests.Materialization.ArtifactContentV1.run
  IO.eprintln "CP run"
  Tests.Materialization.EngineeringDiskClosureV1.run
  IO.eprintln "CP run"
  Tests.Materialization.run
  IO.eprintln "CP run"
  Tests.Materialization.Aleo.run
  IO.eprintln "CP run"
  Tests.Materialization.AleoPfAssetsV1.run
  IO.eprintln "CP run"
  Tests.Materialization.AleoAcceptance.run
  IO.eprintln "CP run"
  Tests.Materialization.AleoCompiledFinalizationV1.run
  IO.eprintln "CP run"
  Tests.Materialization.NoirCompileAcceptance.run
  IO.eprintln "CP run"
  Tests.Materialization.NearHostModel.run
  IO.eprintln "CP run"
  Tests.Materialization.NoirRelationModel.run
  IO.eprintln "CP run"
  Tests.Materialization.SolanaPlanV1.run
  IO.eprintln "CP run"
  Tests.Materialization.SolanaCpiPlanV1.run
  IO.eprintln "CP run"
  Tests.Materialization.SolanaCpiDeriveV1.run
  IO.eprintln "CP run"
  Tests.Materialization.SolanaCpiPreflightV1.run
  Tests.Materialization.SolanaCpiUnsignedV1.run
  Tests.Materialization.SolanaCpiPdaV1.run
  Tests.Materialization.SolanaCpiSystemV1.run
  Tests.Materialization.SolanaCpiTokenV1.run
  Tests.Materialization.SolanaCpiAtaV1.run
  Tests.Materialization.SolanaCpiEscrowV1.run
  Tests.Materialization.SolanaCpiActivationV1.run
  IO.eprintln "CP run"
  Tests.Materialization.PsySourceV1.run
  IO.eprintln "CP run"
  Tests.Materialization.PsyPfAssetsV1.run
  IO.eprintln "CP run"
  Tests.Materialization.PsyDpnV1.run
  IO.eprintln "CP run"
  Tests.Materialization.PsyAcceptance.run
  IO.eprintln "CP run"
  Tests.Materialization.QuintSourceV1.run
  IO.eprintln "CP run"
  Tests.Materialization.QuintAcceptance.run
  IO.eprintln "CP run"
  Tests.Targets.SolanaAsmV1.run
  IO.eprintln "CP run"
  Tests.Targets.SolanaElfV1.run
  IO.eprintln "CP run"
  Tests.Targets.EvmCancunV1.run
  IO.eprintln "CP run"
  Tests.Materialization.EvmCorpusBlockedV1.run
  IO.eprintln "CP run"
  Tests.CLI.Emit.run
  IO.eprintln "CP run"
  Tests.CLI.ToolchainPolicy.run
  IO.eprintln "CP run"
  Tests.CLI.DiagnosticsV1.run
  IO.eprintln "CP run"
  Tests.CLI.ResourceFlagsV1.run
  IO.eprintln "CP run"
  Tests.CLI.InlineProofProductV1.run
  IO.println "shard-targets: ok"
