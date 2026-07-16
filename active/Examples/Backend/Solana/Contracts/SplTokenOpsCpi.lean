import ProofForge.Contract.Builder
import ProofForge.Contract.Source.Solana.Legacy

namespace Examples.Backend.Solana.Contracts.SplTokenOpsCpi

open ProofForge.Contract.Builder
open ProofForge.Contract.Source.Solana.Legacy

def spec : ProofForge.Contract.ContractSpec :=
  build "SolanaSplTokenOpsCpi" do
    scalarState "last_mint_amount" .u64
    scalarState "last_burn_amount" .u64
    scalarState "last_approve_amount" .u64
    scalarState "last_revoke_marker" .u64

    writableAccountConstraint "mint"
    writableAccountConstraint "destination"
    signerAccountConstraint "authority"
    writableAccountConstraint "source"
    readonlyAccountConstraint "delegate"

    splTokenMintTo
      "token_mint"
      "mint"
      "destination"
      "authority"
      "amount"

    splTokenBurn
      "token_burn"
      "source"
      "mint"
      "authority"
      "amount"

    splTokenApprove
      "token_approve"
      "source"
      "delegate"
      "authority"
      "amount"

    splTokenRevoke
      "token_revoke"
      "source"
      "authority"

    entrySelectorWithParams "mint" "04" #[("amount", .u64)] .unit do
      invokeSplTokenMintTo
        "token_mint"
        "mint"
        "destination"
        "authority"
        "amount"
      effect (storageScalarWrite "last_mint_amount" (localVar "amount"))

    entrySelectorWithParams "burn" "05" #[("amount", .u64)] .unit do
      invokeSplTokenBurn
        "token_burn"
        "source"
        "mint"
        "authority"
        "amount"
      effect (storageScalarWrite "last_burn_amount" (localVar "amount"))

    entrySelectorWithParams "approve" "06" #[("amount", .u64)] .unit do
      invokeSplTokenApprove
        "token_approve"
        "source"
        "delegate"
        "authority"
        "amount"
      effect (storageScalarWrite "last_approve_amount" (localVar "amount"))

    entrySelector "revoke" "07" do
      invokeSplTokenRevoke
        "token_revoke"
        "source"
        "authority"
      effect (storageScalarWrite "last_revoke_marker" (u64 1))

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Backend.Solana.Contracts.SplTokenOpsCpi
