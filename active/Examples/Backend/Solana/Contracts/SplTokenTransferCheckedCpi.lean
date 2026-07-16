import ProofForge.Contract.Builder
import ProofForge.Contract.Source.Solana.Legacy

namespace Examples.Backend.Solana.Contracts.SplTokenTransferCheckedCpi

open ProofForge.Contract.Builder
open ProofForge.Contract.Source.Solana.Legacy

def spec : ProofForge.Contract.ContractSpec :=
  build "SolanaSplTokenTransferCheckedCpi" do
    scalarState "last_transfer_amount" .u64

    splTokenTransferChecked
      "token_transfer"
      "source"
      "mint"
      "destination"
      "authority"
      "amount"
      9

    entrySelectorWithParams "transfer" "03" #[("amount", .u64)] .unit do
      invokeSplTokenTransferChecked
        "token_transfer"
        "source"
        "mint"
        "destination"
        "authority"
        "amount"
        9
      effect (storageScalarWrite "last_transfer_amount" (localVar "amount"))

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Backend.Solana.Contracts.SplTokenTransferCheckedCpi
