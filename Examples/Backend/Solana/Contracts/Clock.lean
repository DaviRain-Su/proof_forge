import ProofForge.Contract.Builder

namespace Examples.Backend.Solana.Contracts.Clock

open ProofForge.Contract.Builder

def spec : ProofForge.Contract.ContractSpec :=
  build "SolanaClock" do
    scalarState "last_slot" .u64

    entrySelector "record" "09" do
      letBind "slot" .u64 (contextRead .checkpointId)
      effect (storageScalarWrite "last_slot" (localVar "slot"))

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Backend.Solana.Contracts.Clock
