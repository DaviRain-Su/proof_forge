import ProofForge.Contract.Builder
import ProofForge.Solana

namespace ProofForge.Solana.Examples.SplToken2022PausableCpi

open ProofForge.Contract.Builder
open ProofForge.Solana

def spec : ProofForge.Contract.ContractSpec :=
  build "SolanaSplToken2022PausableCpi" do
    scalarState "last_marker" .u64

    writableAccountConstraint "pausable_mint"
    signerAccountConstraint "pausable_authority"

    splToken2022InitializePausableConfig
      "token_2022_init_pausable_config"
      "pausable_mint"
      "pausable_authority"

    splToken2022Pause
      "token_2022_pause"
      "pausable_mint"
      "pausable_authority"

    splToken2022Resume
      "token_2022_resume"
      "pausable_mint"
      "pausable_authority"

    entrySelector "initialize_pausable_config" "01" do
      invokeSplToken2022InitializePausableConfig
        "token_2022_init_pausable_config"
        "pausable_mint"
        "pausable_authority"
      effect (storageScalarWrite "last_marker" (u64 1))

    entrySelector "pause" "02" do
      invokeSplToken2022Pause
        "token_2022_pause"
        "pausable_mint"
        "pausable_authority"
      effect (storageScalarWrite "last_marker" (u64 2))

    entrySelector "resume" "03" do
      invokeSplToken2022Resume
        "token_2022_resume"
        "pausable_mint"
        "pausable_authority"
      effect (storageScalarWrite "last_marker" (u64 3))

def module : ProofForge.IR.Module :=
  spec.module

end ProofForge.Solana.Examples.SplToken2022PausableCpi
