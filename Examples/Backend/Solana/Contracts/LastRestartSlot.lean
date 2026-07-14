import ProofForge.Contract.Builder
import ProofForge.Contract.Source.Solana.Legacy

namespace Examples.Backend.Solana.Contracts.LastRestartSlot

open ProofForge.Contract.Builder

def spec : ProofForge.Contract.ContractSpec :=
  build "SolanaLastRestartSlot" do
    scalarState "last_restart_slot" .u64

    entrySelector "record_last_restart_slot" "11" do
      ProofForge.Contract.Source.Solana.Legacy.lastRestartSlotToState
        "read_last_restart_slot"
        "last_restart_slot"

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Backend.Solana.Contracts.LastRestartSlot
