import ProofForge.Contract.Builder
import ProofForge.Solana

namespace ProofForge.Solana.Examples.SplToken2022TransferHook

open ProofForge.Contract.Builder
open ProofForge.Solana

def executeDiscriminator : String :=
  "692565c54bfb661a"

def spec : ProofForge.Contract.ContractSpec :=
  build "SolanaSplToken2022TransferHook" do
    accountOrder #[
      "source",
      "mint",
      "destination",
      "authority",
      "extra_account_meta_list",
      "sentinel",
      "system_program"
    ]
    readonlyAccountConstraint "source"
    readonlyAccountConstraint "mint"
    readonlyAccountConstraint "destination"
    readonlyAccountConstraint "authority"
    readonlyAccountConstraint "extra_account_meta_list"
    readonlyAccountConstraint "sentinel"
    readonlyAccountConstraint "system_program" "executable"

    systemCreateAccount
      "create_extra_account_meta_list"
      "source"
      "extra_account_meta_list"
      "rent_lamports"
      "extra_meta_space"
      "program"
      (signerSeeds := #[
        utf8Seed "extra-account-metas",
        accountSeed "mint",
        bumpSeed "extra_meta_bump"
      ])

    entrySelectorWithParams "initialize_extra_account_meta_list" "16"
        #[("rent_lamports", .u64), ("extra_meta_space", .u64), ("extra_meta_bump", .u64)]
        .unit do
      invokeSystemCreateAccount
        "create_extra_account_meta_list"
        "source"
        "extra_account_meta_list"
        "rent_lamports"
        "extra_meta_space"
        "program"
        (signerSeeds := #[
          utf8Seed "extra-account-metas",
          accountSeed "mint",
          bumpSeed "extra_meta_bump"
        ])
      initializeTransferHookExtraAccountMetaListWithAccounts
        "write_extra_account_meta_list"
        "extra_account_meta_list"
        #["sentinel", "system_program"]

    entrySelectorWithParams "execute" executeDiscriminator
        #[("amount", .u64)] .unit do
      assert (le (localVar "amount") (u64 50)) "transfer hook amount exceeds limit"

def module : ProofForge.IR.Module :=
  spec.module

end ProofForge.Solana.Examples.SplToken2022TransferHook
