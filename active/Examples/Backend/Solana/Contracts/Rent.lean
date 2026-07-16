import ProofForge.Contract.Builder
import ProofForge.Contract.Source.Solana.Legacy

namespace Examples.Backend.Solana.Contracts.Rent

open ProofForge.Contract.Builder

def spec : ProofForge.Contract.ContractSpec :=
  build "SolanaRent" do
    scalarState "lamports_per_byte_year" .u64

    entrySelector "record_rent" "0f" do
      ProofForge.Contract.Source.Solana.Legacy.rentLamportsPerByteYearToState
        "read_rent"
        "lamports_per_byte_year"

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Backend.Solana.Contracts.Rent
