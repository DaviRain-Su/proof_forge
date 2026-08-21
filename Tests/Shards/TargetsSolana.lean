/-
  Targets Solana Lean plan/CPI/asm/elf shard (no Mollusk Rust runtime).

  Mollusk stays in `just solana-runtime`. This process only runs Lean-side
  Solana materialization and emitter pins so it can parallelize with EVM/host.
-/
import Tests.Shards.Runner
import Tests.Materialization.SolanaPlanV1
import Tests.Materialization.SolanaStaticAlignmentV1
import Tests.Materialization.SolanaCpiPlanV1
import Tests.Materialization.SolanaCpiDeriveV1
import Tests.Materialization.SolanaCpiPreflightV1
import Tests.Materialization.SolanaCpiUnsignedV1
import Tests.Materialization.SolanaCpiPdaV1
import Tests.Materialization.SolanaCpiSystemV1
import Tests.Materialization.SolanaCpiTokenV1
import Tests.Materialization.SolanaCpiAtaV1
import Tests.Materialization.SolanaCpiEscrowV1
import Tests.Materialization.SolanaCpiPfAssetsV1
import Tests.Materialization.SolanaCpiActivationV1
import Tests.Materialization.SolanaProductSynthesizeV1
import Tests.Targets.SolanaAsmV1
import Tests.Targets.SolanaElfV1
import Tests.Product.TokenV1
import Tests.Product.TipJarSolanaV1
import Tests.Product.TokenJarSolanaV1
import Tests.Product.MiniAmmSolanaV1

open Tests.Shards

unsafe def main : IO Unit := do
  runSuite "Tests.Materialization.SolanaPlanV1" Tests.Materialization.SolanaPlanV1.run
  runSuite "Tests.Materialization.SolanaStaticAlignmentV1"
    Tests.Materialization.SolanaStaticAlignmentV1.run
  runSuite "Tests.Materialization.SolanaCpiPlanV1"
    Tests.Materialization.SolanaCpiPlanV1.run
  runSuite "Tests.Materialization.SolanaCpiDeriveV1"
    Tests.Materialization.SolanaCpiDeriveV1.run
  runSuite "Tests.Materialization.SolanaCpiPreflightV1"
    Tests.Materialization.SolanaCpiPreflightV1.run
  runSuite "Tests.Materialization.SolanaCpiUnsignedV1"
    Tests.Materialization.SolanaCpiUnsignedV1.run
  runSuite "Tests.Materialization.SolanaCpiPdaV1"
    Tests.Materialization.SolanaCpiPdaV1.run
  runSuite "Tests.Materialization.SolanaCpiSystemV1"
    Tests.Materialization.SolanaCpiSystemV1.run
  runSuite "Tests.Materialization.SolanaCpiTokenV1"
    Tests.Materialization.SolanaCpiTokenV1.run
  runSuite "Tests.Materialization.SolanaCpiAtaV1"
    Tests.Materialization.SolanaCpiAtaV1.run
  runSuite "Tests.Materialization.SolanaCpiEscrowV1"
    Tests.Materialization.SolanaCpiEscrowV1.run
  runSuite "Tests.Materialization.SolanaCpiPfAssetsV1"
    Tests.Materialization.SolanaCpiPfAssetsV1.run
  runSuite "Tests.Materialization.SolanaCpiActivationV1"
    Tests.Materialization.SolanaCpiActivationV1.run
  runSuite "Tests.Materialization.SolanaProductSynthesizeV1"
    Tests.Materialization.SolanaProductSynthesizeV1.run
  runSuite "Tests.Targets.SolanaAsmV1" Tests.Targets.SolanaAsmV1.run
  runSuite "Tests.Targets.SolanaElfV1" Tests.Targets.SolanaElfV1.run
  runSuite "Tests.Product.TokenV1/solana" Tests.Product.TokenV1.runSolana
  runSuite "Tests.Product.TipJarSolanaV1" Tests.Product.TipJarSolanaV1.run
  runSuite "Tests.Product.TokenJarSolanaV1" Tests.Product.TokenJarSolanaV1.run
  runSuite "Tests.Product.MiniAmmSolanaV1" Tests.Product.MiniAmmSolanaV1.run
  IO.println "shard-targets-solana: ok"
