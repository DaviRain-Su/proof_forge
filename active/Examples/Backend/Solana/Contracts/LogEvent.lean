import ProofForge.Contract.Builder
import ProofForge.Contract.Source.Solana.Legacy

namespace Examples.Backend.Solana.Contracts.LogEvent

open ProofForge.Contract.Builder
open ProofForge.Contract.Source.Solana.Legacy

def spec : ProofForge.Contract.ContractSpec :=
  build "SolanaLogEvent" do
    scalarState "last_logged_amount" .u64

    entrySelectorWithParams "emit" "08" #[("amount", .u64)] .unit do
      effect (eventEmit "AmountEvent" #[("amount", localVar "amount")])
      effect (storageScalarWrite "last_logged_amount" (localVar "amount"))

    entrySelector "log_state_pubkey" "09" do
      logAccountPubkey "log_state_account" "last_logged_amount"

    entrySelector "log_state_data" "0a" do
      logStateData "log_amount_data" "last_logged_amount" 8

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Backend.Solana.Contracts.LogEvent
