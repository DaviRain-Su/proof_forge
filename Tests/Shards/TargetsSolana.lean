/-
  Targets Solana Lean plan/CPI/asm/elf shard (no Mollusk Rust runtime).

  Mollusk stays in `just solana-runtime`. This process only runs Lean-side
  Solana materialization and emitter pins so it can parallelize with EVM/host.
-/
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

unsafe def main : IO Unit := do
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
  Tests.Targets.SolanaAsmV1.run
  IO.eprintln "CP run"
  Tests.Targets.SolanaElfV1.run
  IO.println "shard-targets-solana: ok"
