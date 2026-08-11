/-
  Targets EVM / shared product-control shard.

  Registry, output identity, EVM plan/smoke/solc/cancun/corpus, cross-target
  materialization gates (`Tests.Materialization`), and CLI product pins that
  most EVM work touches. Kept separate from Solana CPI and host/ZK suites so
  CI can run them as independent processes (RSS + wall-clock).
-/
import Tests.Materialization.BuildSelectionV1
import Tests.Materialization.TargetRegistryV1
import Tests.Materialization.RegistryRootV1
import Tests.Materialization.RequirementResolverV1
import Tests.Materialization.IdentityChainV1
import Tests.Materialization.EvmPlanSchemaV1
import Tests.Materialization.EvmSmoke
import Tests.Materialization.EvmSolcAcceptance
import Tests.Materialization.OutputSetV1
import Tests.Materialization.OutputEnvelopeV1
import Tests.Materialization.EngineeringFinalizationV1
import Tests.Materialization.ArtifactContentV1
import Tests.Materialization.EngineeringDiskClosureV1
import Tests.Materialization.Targets
import Tests.Targets.EvmCancunV1
import Tests.Materialization.EvmCorpusBlockedV1
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
  Tests.Materialization.EvmSmoke.run
  IO.eprintln "CP run"
  Tests.Materialization.EvmSolcAcceptance.run
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
  IO.println "shard-targets-evm: ok"
