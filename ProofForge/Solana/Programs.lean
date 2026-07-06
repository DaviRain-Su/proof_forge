import ProofForge.Solana.Metadata

namespace ProofForge.Solana

open ProofForge.Target

def systemProgram : String :=
  "system_program"

def splTokenProgram : String :=
  "spl_token"

def splToken2022Program : String :=
  "spl_token_2022"

def associatedTokenProgram : String :=
  "associated_token"

def memoProgram : String :=
  "memo"

def memoMetadata : Array TargetMetadata :=
  #[
    kv "solana.cpi.protocol" "memo"
  ]

def tokenProtocolForProgram (tokenProgram : String) : String :=
  if tokenProgram == splToken2022Program then
    "token-2022"
  else
    "spl-token"

def signerForSeeds (name : String) (access : AccountAccess) (signerSeeds : Array String) : AccountMeta :=
  if signerSeeds.isEmpty then
    signerAccount name access
  else
    pdaSignerAccount name access

def systemMetadata : Array TargetMetadata :=
  #[
    kv "solana.cpi.protocol" "system"
  ]

def tokenMetadata (tokenProgram : String) : Array TargetMetadata :=
  #[
    kv "solana.cpi.protocol" (tokenProtocolForProgram tokenProgram)
  ]

def token2022Metadata : Array TargetMetadata :=
  tokenMetadata splToken2022Program

def associatedTokenMetadata : Array TargetMetadata :=
  #[
    kv "solana.cpi.protocol" "associated-token"
  ]

def systemTransferCall (name fromAccount to lamportsSource : String)
    (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := systemProgram
  instruction := "transfer"
  accounts := #[
    signerForSeeds fromAccount .writable signerSeeds,
    writableAccount to
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "system.transfer"
  extraMetadata := systemMetadata ++ #[
    kv "solana.cpi.lamports_source" lamportsSource
  ]
}

/-- Memo program CPI: logs a UTF-8 memo string on-chain. No accounts, no signer
    seeds — the memo is purely instruction data. -/
def memoCall (name memoSource : String) : CpiCall := {
  name := name
  program := memoProgram
  instruction := "memo"
  accounts := #[]
  signerSeeds := #[]
  dataLayout? := some "memo.memo"
  extraMetadata := memoMetadata ++ #[
    kv "solana.cpi.memo_source" memoSource
  ]
}

def systemCreateAccountCall (name payer newAccount lamportsSource spaceSource owner : String)
    (signerSeeds : Array String := #[]) (requireProgramAccount : Bool := true) : CpiCall := {
  name := name
  program := systemProgram
  instruction := "create_account"
  accounts := #[
    writableSignerAccount payer,
    signerForSeeds newAccount .writable signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "system.create_account"
  extraMetadata := systemMetadata ++ #[
    kv "solana.cpi.lamports_source" lamportsSource,
    kv "solana.cpi.space_source" spaceSource,
    kv "solana.cpi.owner" owner,
    kv "solana.cpi.require_program_account" (boolValue requireProgramAccount)
  ]
}

def splTokenTransferCheckedCall (name source mint destination authority amountSource : String)
    (decimals : Nat) (tokenProgram : String := splTokenProgram)
    (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := tokenProgram
  instruction := "transfer_checked"
  accounts := #[
    writableAccount source,
    readonlyAccount mint,
    writableAccount destination,
    signerForSeeds authority .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "spl-token.transfer_checked"
  extraMetadata := tokenMetadata tokenProgram ++ #[
    kv "solana.cpi.amount_source" amountSource,
    kv "solana.cpi.decimals" (toString decimals)
  ]
}

def splToken2022InitializeTransferFeeConfigCall
    (name mint transferFeeConfigAuthority withdrawWithheldAuthority basisPointsSource
      maximumFeeSource : String) : CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "initialize_transfer_fee_config"
  accounts := #[
    writableAccount mint
  ]
  dataLayout? := some "token-2022.initialize_transfer_fee_config"
  extraMetadata := token2022Metadata ++ #[
    kv "solana.cpi.transfer_fee_config_authority" transferFeeConfigAuthority,
    kv "solana.cpi.withdraw_withheld_authority" withdrawWithheldAuthority,
    kv "solana.cpi.transfer_fee_basis_points" basisPointsSource,
    kv "solana.cpi.maximum_fee" maximumFeeSource
  ]
}

def splToken2022TransferCheckedWithFeeCall
    (name source mint destination authority amountSource feeSource : String)
    (decimals : Nat) (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "transfer_checked_with_fee"
  accounts := #[
    writableAccount source,
    readonlyAccount mint,
    writableAccount destination,
    signerForSeeds authority .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "token-2022.transfer_checked_with_fee"
  extraMetadata := token2022Metadata ++ #[
    kv "solana.cpi.amount_source" amountSource,
    kv "solana.cpi.decimals" (toString decimals),
    kv "solana.cpi.fee_source" feeSource
  ]
}

def splToken2022WithdrawWithheldTokensFromMintCall
    (name mint destination authority : String) (signerSeeds : Array String := #[]) :
    CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "withdraw_withheld_tokens_from_mint"
  accounts := #[
    writableAccount mint,
    writableAccount destination,
    signerForSeeds authority .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "token-2022.withdraw_withheld_tokens_from_mint"
  extraMetadata := token2022Metadata
}

def splToken2022WithdrawWithheldTokensFromAccountsCall
    (name mint destination authority : String) (sources : Array String)
    (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "withdraw_withheld_tokens_from_accounts"
  accounts :=
    #[
      readonlyAccount mint,
      writableAccount destination,
      signerForSeeds authority .readOnly signerSeeds
    ] ++ sources.map writableAccount
  signerSeeds := signerSeeds
  dataLayout? := some "token-2022.withdraw_withheld_tokens_from_accounts"
  extraMetadata := token2022Metadata ++ #[
    kv "solana.cpi.num_token_accounts" (toString sources.size)
  ]
}

def splToken2022HarvestWithheldTokensToMintCall
    (name mint : String) (sources : Array String) : CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "harvest_withheld_tokens_to_mint"
  accounts := #[writableAccount mint] ++ sources.map writableAccount
  dataLayout? := some "token-2022.harvest_withheld_tokens_to_mint"
  extraMetadata := token2022Metadata
}

def splToken2022SetTransferFeeCall
    (name mint authority basisPointsSource maximumFeeSource : String)
    (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "set_transfer_fee"
  accounts := #[
    writableAccount mint,
    signerForSeeds authority .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "token-2022.set_transfer_fee"
  extraMetadata := token2022Metadata ++ #[
    kv "solana.cpi.transfer_fee_basis_points" basisPointsSource,
    kv "solana.cpi.maximum_fee" maximumFeeSource
  ]
}

def splToken2022InitializeNonTransferableMintCall (name mint : String) :
    CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "initialize_non_transferable_mint"
  accounts := #[
    writableAccount mint
  ]
  dataLayout? := some "token-2022.initialize_non_transferable_mint"
  extraMetadata := token2022Metadata
}

def splToken2022InitializeMetadataPointerCall
    (name mint metadataPointerAuthority metadataAddress : String) : CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "initialize_metadata_pointer"
  accounts := #[
    writableAccount mint
  ]
  dataLayout? := some "token-2022.initialize_metadata_pointer"
  extraMetadata := token2022Metadata ++ #[
    kv "solana.cpi.metadata_pointer_authority" metadataPointerAuthority,
    kv "solana.cpi.metadata_address" metadataAddress
  ]
}

def splToken2022InitializeDefaultAccountStateCall
    (name mint : String) (accountState : Nat) : CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "initialize_default_account_state"
  accounts := #[
    writableAccount mint
  ]
  dataLayout? := some "token-2022.initialize_default_account_state"
  extraMetadata := token2022Metadata ++ #[
    kv "solana.cpi.default_account_state" (toString accountState)
  ]
}

def splToken2022InitializeImmutableOwnerCall (name account : String) :
    CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "initialize_immutable_owner"
  accounts := #[
    writableAccount account
  ]
  dataLayout? := some "token-2022.initialize_immutable_owner"
  extraMetadata := token2022Metadata
}

def splToken2022InitializePermanentDelegateCall
    (name mint permanentDelegate : String) : CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "initialize_permanent_delegate"
  accounts := #[
    writableAccount mint
  ]
  dataLayout? := some "token-2022.initialize_permanent_delegate"
  extraMetadata := token2022Metadata ++ #[
    kv "solana.cpi.permanent_delegate" permanentDelegate
  ]
}

def splToken2022InitializeInterestBearingMintCall
    (name mint rateAuthority : String) (rate : Nat) : CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "initialize_interest_bearing_mint"
  accounts := #[
    writableAccount mint
  ]
  dataLayout? := some "token-2022.initialize_interest_bearing_mint"
  extraMetadata := token2022Metadata ++ #[
    kv "solana.cpi.interest_rate_authority" rateAuthority,
    kv "solana.cpi.interest_rate" (toString rate)
  ]
}

def splToken2022EnableRequiredMemoTransfersCall
    (name account authority : String) (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "enable_required_memo_transfers"
  accounts := #[
    writableAccount account,
    signerForSeeds authority .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "token-2022.enable_required_memo_transfers"
  extraMetadata := token2022Metadata ++ #[
    kv "solana.cpi.memo_transfer_required" "true"
  ]
}

def splToken2022InitializeTransferHookCall
    (name mint authority transferHookProgram : String) : CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "initialize_transfer_hook"
  accounts := #[
    writableAccount mint
  ]
  dataLayout? := some "token-2022.initialize_transfer_hook"
  extraMetadata := token2022Metadata ++ #[
    kv "solana.cpi.transfer_hook_authority" authority,
    kv "solana.cpi.transfer_hook_program" transferHookProgram
  ]
}

def splToken2022InitializePausableConfigCall
    (name mint authority : String) : CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "initialize_pausable_config"
  accounts := #[
    writableAccount mint
  ]
  dataLayout? := some "token-2022.initialize_pausable_config"
  extraMetadata := token2022Metadata ++ #[
    kv "solana.cpi.pausable_authority" authority
  ]
}

def splToken2022PauseCall
    (name mint authority : String) (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "pause"
  accounts := #[
    writableAccount mint,
    signerForSeeds authority .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "token-2022.pause"
  extraMetadata := token2022Metadata
}

def splToken2022ResumeCall
    (name mint authority : String) (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "resume"
  accounts := #[
    writableAccount mint,
    signerForSeeds authority .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "token-2022.resume"
  extraMetadata := token2022Metadata
}

def splTokenMintToCall (name mint destination authority amountSource : String)
    (tokenProgram : String := splTokenProgram) (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := tokenProgram
  instruction := "mint_to"
  accounts := #[
    writableAccount mint,
    writableAccount destination,
    signerForSeeds authority .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "spl-token.mint_to"
  extraMetadata := tokenMetadata tokenProgram ++ #[
    kv "solana.cpi.amount_source" amountSource
  ]
}

def splTokenBurnCall (name source mint authority amountSource : String)
    (tokenProgram : String := splTokenProgram) (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := tokenProgram
  instruction := "burn"
  accounts := #[
    writableAccount source,
    writableAccount mint,
    signerForSeeds authority .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "spl-token.burn"
  extraMetadata := tokenMetadata tokenProgram ++ #[
    kv "solana.cpi.amount_source" amountSource
  ]
}

def splTokenApproveCall (name source delegate owner amountSource : String)
    (tokenProgram : String := splTokenProgram) (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := tokenProgram
  instruction := "approve"
  accounts := #[
    writableAccount source,
    readonlyAccount delegate,
    signerForSeeds owner .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "spl-token.approve"
  extraMetadata := tokenMetadata tokenProgram ++ #[
    kv "solana.cpi.amount_source" amountSource
  ]
}

def splTokenRevokeCall (name source owner : String) (tokenProgram : String := splTokenProgram)
    (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := tokenProgram
  instruction := "revoke"
  accounts := #[
    writableAccount source,
    signerForSeeds owner .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "spl-token.revoke"
  extraMetadata := tokenMetadata tokenProgram
}

def splTokenCloseAccountCall (name account destination authority : String)
    (tokenProgram : String := splTokenProgram) (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := tokenProgram
  instruction := "close_account"
  accounts := #[
    writableAccount account,
    writableAccount destination,
    signerForSeeds authority .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "spl-token.close_account"
  extraMetadata := tokenMetadata tokenProgram
}

def splTokenSetAuthorityCall (name account authority authorityType newAuthority : String)
    (tokenProgram : String := splTokenProgram) (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := tokenProgram
  instruction := "set_authority"
  accounts := #[
    writableAccount account,
    signerForSeeds authority .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "spl-token.set_authority"
  extraMetadata := tokenMetadata tokenProgram ++ #[
    kv "solana.cpi.authority_type" authorityType,
    kv "solana.cpi.new_authority" newAuthority
  ]
}

def associatedTokenCreateCall (name funding account wallet mint : String)
    (idempotent : Bool := true)
    (associatedProgram : String := associatedTokenProgram)
    (systemProgramName : String := systemProgram)
    (tokenProgramName : String := splTokenProgram)
    (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := associatedProgram
  instruction := if idempotent then "create_idempotent" else "create"
  accounts := #[
    signerForSeeds funding .writable signerSeeds,
    writableAccount account,
    readonlyAccount wallet,
    readonlyAccount mint,
    readonlyAccount systemProgramName,
    readonlyAccount tokenProgramName
  ]
  signerSeeds := signerSeeds
  dataLayout? := some (if idempotent then "associated-token.create_idempotent" else "associated-token.create")
  extraMetadata := associatedTokenMetadata ++ #[
    kv "solana.cpi.token_program" tokenProgramName
  ]
}

end ProofForge.Solana
