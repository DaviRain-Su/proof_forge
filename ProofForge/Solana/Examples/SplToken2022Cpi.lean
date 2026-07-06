import ProofForge.Contract.Builder
import ProofForge.Solana

namespace ProofForge.Solana.Examples.SplToken2022Cpi

open ProofForge.Contract.Builder
open ProofForge.Solana

def spec : ProofForge.Contract.ContractSpec :=
  build "SolanaSplToken2022Cpi" do
    scalarState "last_amount" .u64
    scalarState "last_fee" .u64
    scalarState "last_basis_points" .u64
    scalarState "last_maximum_fee" .u64
    scalarState "last_marker" .u64

    writableAccountConstraint "mint"
    readonlyAccountConstraint "transfer_fee_config_authority"
    readonlyAccountConstraint "withdraw_withheld_authority"
    writableAccountConstraint "source"
    writableAccountConstraint "destination"
    signerAccountConstraint "authority"
    writableAccountConstraint "fee_receiver"
    writableAccountConstraint "withheld_source"
    writableAccountConstraint "metadata_pointer_mint"
    writableAccountConstraint "default_state_mint"
    writableAccountConstraint "immutable_owner_account"
    writableAccountConstraint "non_transferable_mint"
    writableAccountConstraint "permanent_delegate_mint"
    writableAccountConstraint "interest_bearing_mint"
    writableAccountConstraint "memo_transfer_account"
    writableAccountConstraint "transfer_hook_mint"
    readonlyAccountConstraint "metadata_pointer_authority"
    readonlyAccountConstraint "metadata_address"
    readonlyAccountConstraint "permanent_delegate"
    readonlyAccountConstraint "interest_rate_authority"
    readonlyAccountConstraint "transfer_hook_authority"
    readonlyAccountConstraint "transfer_hook_program"

    splToken2022InitializeTransferFeeConfig
      "token_2022_init_fee_config"
      "mint"
      "transfer_fee_config_authority"
      "withdraw_withheld_authority"
      "basis_points"
      "maximum_fee"

    splToken2022TransferCheckedWithFee
      "token_2022_transfer_with_fee"
      "source"
      "mint"
      "destination"
      "authority"
      "amount"
      "fee"
      9

    splToken2022WithdrawWithheldTokensFromMint
      "token_2022_withdraw_from_mint"
      "mint"
      "fee_receiver"
      "withdraw_withheld_authority"

    splToken2022WithdrawWithheldTokensFromAccounts
      "token_2022_withdraw_from_accounts"
      "mint"
      "fee_receiver"
      "withdraw_withheld_authority"
      #["withheld_source"]

    splToken2022HarvestWithheldTokensToMint
      "token_2022_harvest_to_mint"
      "mint"
      #["withheld_source"]

    splToken2022SetTransferFee
      "token_2022_set_transfer_fee"
      "mint"
      "transfer_fee_config_authority"
      "basis_points"
      "maximum_fee"

    splToken2022InitializeNonTransferableMint
      "token_2022_init_non_transferable"
      "non_transferable_mint"

    splToken2022InitializeMetadataPointer
      "token_2022_init_metadata_pointer"
      "metadata_pointer_mint"
      "metadata_pointer_authority"
      "metadata_address"

    splToken2022InitializeDefaultAccountState
      "token_2022_init_default_account_state"
      "default_state_mint"
      2

    splToken2022InitializeImmutableOwner
      "token_2022_init_immutable_owner"
      "immutable_owner_account"

    splToken2022InitializePermanentDelegate
      "token_2022_init_permanent_delegate"
      "permanent_delegate_mint"
      "permanent_delegate"

    splToken2022InitializeInterestBearingMint
      "token_2022_init_interest_bearing"
      "interest_bearing_mint"
      "interest_rate_authority"
      250

    splToken2022EnableRequiredMemoTransfers
      "token_2022_enable_memo_transfer"
      "memo_transfer_account"
      "authority"

    splToken2022InitializeTransferHook
      "token_2022_init_transfer_hook"
      "transfer_hook_mint"
      "transfer_hook_authority"
      "transfer_hook_program"

    entrySelectorWithParams "init_fee_config" "08"
        #[("basis_points", .u64), ("maximum_fee", .u64)] .unit do
      invokeSplToken2022InitializeTransferFeeConfig
        "token_2022_init_fee_config"
        "mint"
        "transfer_fee_config_authority"
        "withdraw_withheld_authority"
        "basis_points"
        "maximum_fee"
      effect (storageScalarWrite "last_basis_points" (localVar "basis_points"))
      effect (storageScalarWrite "last_maximum_fee" (localVar "maximum_fee"))

    entrySelectorWithParams "transfer_with_fee" "09"
        #[("amount", .u64), ("fee", .u64)] .unit do
      invokeSplToken2022TransferCheckedWithFee
        "token_2022_transfer_with_fee"
        "source"
        "mint"
        "destination"
        "authority"
        "amount"
        "fee"
        9
      effect (storageScalarWrite "last_amount" (localVar "amount"))
      effect (storageScalarWrite "last_fee" (localVar "fee"))

    entrySelector "withdraw_from_mint" "0a" do
      invokeSplToken2022WithdrawWithheldTokensFromMint
        "token_2022_withdraw_from_mint"
        "mint"
        "fee_receiver"
        "withdraw_withheld_authority"
      effect (storageScalarWrite "last_marker" (u64 1))

    entrySelector "withdraw_from_accounts" "0b" do
      invokeSplToken2022WithdrawWithheldTokensFromAccounts
        "token_2022_withdraw_from_accounts"
        "mint"
        "fee_receiver"
        "withdraw_withheld_authority"
        #["withheld_source"]
      effect (storageScalarWrite "last_marker" (u64 2))

    entrySelector "harvest_to_mint" "0c" do
      invokeSplToken2022HarvestWithheldTokensToMint
        "token_2022_harvest_to_mint"
        "mint"
        #["withheld_source"]
      effect (storageScalarWrite "last_marker" (u64 3))

    entrySelectorWithParams "set_transfer_fee" "0d"
        #[("basis_points", .u64), ("maximum_fee", .u64)] .unit do
      invokeSplToken2022SetTransferFee
        "token_2022_set_transfer_fee"
        "mint"
        "transfer_fee_config_authority"
        "basis_points"
        "maximum_fee"
      effect (storageScalarWrite "last_basis_points" (localVar "basis_points"))
      effect (storageScalarWrite "last_maximum_fee" (localVar "maximum_fee"))

    entrySelector "initialize_non_transferable" "0e" do
      invokeSplToken2022InitializeNonTransferableMint
        "token_2022_init_non_transferable"
        "non_transferable_mint"
      effect (storageScalarWrite "last_marker" (u64 4))

    entrySelector "initialize_metadata_pointer" "0f" do
      invokeSplToken2022InitializeMetadataPointer
        "token_2022_init_metadata_pointer"
        "metadata_pointer_mint"
        "metadata_pointer_authority"
        "metadata_address"
      effect (storageScalarWrite "last_marker" (u64 5))

    entrySelector "initialize_default_account_state" "10" do
      invokeSplToken2022InitializeDefaultAccountState
        "token_2022_init_default_account_state"
        "default_state_mint"
        2
      effect (storageScalarWrite "last_marker" (u64 6))

    entrySelector "initialize_immutable_owner" "11" do
      invokeSplToken2022InitializeImmutableOwner
        "token_2022_init_immutable_owner"
        "immutable_owner_account"
      effect (storageScalarWrite "last_marker" (u64 7))

    entrySelector "initialize_permanent_delegate" "12" do
      invokeSplToken2022InitializePermanentDelegate
        "token_2022_init_permanent_delegate"
        "permanent_delegate_mint"
        "permanent_delegate"
      effect (storageScalarWrite "last_marker" (u64 8))

    entrySelector "initialize_interest_bearing" "13" do
      invokeSplToken2022InitializeInterestBearingMint
        "token_2022_init_interest_bearing"
        "interest_bearing_mint"
        "interest_rate_authority"
        250
      effect (storageScalarWrite "last_marker" (u64 9))

    entrySelector "enable_memo_transfer" "14" do
      invokeSplToken2022EnableRequiredMemoTransfers
        "token_2022_enable_memo_transfer"
        "memo_transfer_account"
        "authority"
      effect (storageScalarWrite "last_marker" (u64 10))

    entrySelector "initialize_transfer_hook" "15" do
      invokeSplToken2022InitializeTransferHook
        "token_2022_init_transfer_hook"
        "transfer_hook_mint"
        "transfer_hook_authority"
        "transfer_hook_program"
      effect (storageScalarWrite "last_marker" (u64 11))

def module : ProofForge.IR.Module :=
  spec.module

end ProofForge.Solana.Examples.SplToken2022Cpi
