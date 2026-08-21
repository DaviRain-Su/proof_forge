/-
  Targets EVM / shared product-control shard.

  Registry, output identity, EVM plan/smoke/solc/cancun/corpus, cross-target
  materialization gates (`Tests.Materialization`), and CLI product pins that
  most EVM work touches. Kept separate from Solana CPI and host/ZK suites so
  CI can run them as independent processes (RSS + wall-clock).
-/
import Tests.Shards.Runner
import Tests.Materialization.BuildSelectionV1
import Tests.Materialization.CallBindV1
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
import Tests.Materialization.EvmOutcomeAdapterV1
import Tests.CLI.Emit
import Tests.CLI.ToolchainPolicy
import Tests.CLI.DiagnosticsV1
import Tests.CLI.ResourceFlagsV1
import Tests.CLI.InlineProofProductV1
import Tests.Product.TokenV1
import Tests.Product.TipJarEvmV1
import Tests.Materialization.EvmPfAssetsV1
import Tests.Product.TokenJarEvmV1

open Tests.Shards

unsafe def main : IO Unit := do
  runSuite "Tests.Materialization.BuildSelectionV1"
    Tests.Materialization.BuildSelectionV1.run
  runSuite "Tests.Materialization.CallBindV1" Tests.Materialization.CallBindV1.run
  runSuite "Tests.Materialization.TargetRegistryV1"
    Tests.Materialization.TargetRegistryV1.run
  runSuite "Tests.Materialization.RegistryRootV1" Tests.Materialization.RegistryRootV1.run
  runSuite "Tests.Materialization.RequirementResolverV1"
    Tests.Materialization.RequirementResolverV1.run
  runSuite "Tests.Materialization.IdentityChainV1" Tests.Materialization.IdentityChainV1.run
  runSuite "Tests.Materialization.EvmPlanSchemaV1" Tests.Materialization.EvmPlanSchemaV1.run
  runSuite "Tests.Materialization.EvmSmoke" Tests.Materialization.EvmSmoke.run
  runSuite "Tests.Materialization.EvmSolcAcceptance"
    Tests.Materialization.EvmSolcAcceptance.run
  runSuite "Tests.Materialization.OutputSetV1" Tests.Materialization.OutputSetV1.run
  runSuite "Tests.Materialization.OutputEnvelopeV1" Tests.Materialization.OutputEnvelopeV1.run
  runSuite "Tests.Materialization.EngineeringFinalizationV1"
    Tests.Materialization.EngineeringFinalizationV1.run
  runSuite "Tests.Materialization.ArtifactContentV1"
    Tests.Materialization.ArtifactContentV1.run
  runSuite "Tests.Materialization.EngineeringDiskClosureV1"
    Tests.Materialization.EngineeringDiskClosureV1.run
  runSuite "Tests.Materialization.Targets" Tests.Materialization.run
  runSuite "Tests.Targets.EvmCancunV1" Tests.Targets.EvmCancunV1.run
  runSuite "Tests.Materialization.EvmCorpusBlockedV1"
    Tests.Materialization.EvmCorpusBlockedV1.run
  runSuite "Tests.Materialization.EvmOutcomeAdapterV1"
    Tests.Materialization.EvmOutcomeAdapterV1.run
  runSuite "Tests.CLI.Emit" Tests.CLI.Emit.run
  runSuite "Tests.CLI.ToolchainPolicy" Tests.CLI.ToolchainPolicy.run
  runSuite "Tests.CLI.DiagnosticsV1" Tests.CLI.DiagnosticsV1.run
  runSuite "Tests.CLI.ResourceFlagsV1" Tests.CLI.ResourceFlagsV1.run
  runSuite "Tests.CLI.InlineProofProductV1" Tests.CLI.InlineProofProductV1.run
  runSuite "Tests.Product.TokenV1/evm" Tests.Product.TokenV1.runEvm
  runSuite "Tests.Product.TipJarEvmV1" Tests.Product.TipJarEvmV1.run
  runSuite "Tests.Materialization.EvmPfAssetsV1" Tests.Materialization.EvmPfAssetsV1.run
  runSuite "Tests.Product.TokenJarEvmV1" Tests.Product.TokenJarEvmV1.run
  IO.println "shard-targets-evm: ok"
