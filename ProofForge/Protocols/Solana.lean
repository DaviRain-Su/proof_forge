/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Layer B — Solana protocol program clients

Thin product facade over the canonical Solana CPI builders and call shapes.

**Source of truth (do not duplicate packing here):**
- Call shapes: `ProofForge.Solana.Programs`
- Entry/module builders: `ProofForge.Solana.Builders`
- sBPF dataLayout packing: `ProofForge.Backend.Solana.Extension.Cpi`

Authors / Solana-extension modules should prefer importing this facade when
they mean “call an official program”, so Layer B is discoverable next to EVM
and NEAR protocol clients.
-/
import ProofForge.Solana.Programs
import ProofForge.Solana.Builders

namespace ProofForge.Protocols.Solana

open ProofForge.Solana

/-- Catalog id for docs / diagnostics. -/
def catalogId : String := "protocols.solana"

/-- Known protocol families with CPI packing (see `isSupportedCpiDataLayout`). -/
def knownFamilies : Array String := #[
  "system",
  "spl-token",
  "associated-token",
  "memo",
  "token-2022",
  "stake",
  "vote",
  "config",
  "metaplex"
]

/-- Packed dataLayout ids currently supported by the sBPF CPI lowerer. -/
def supportedDataLayouts : Array String := #[
  "system.transfer",
  "system.create_account",
  "spl-token.initialize_mint",
  "spl-token.initialize_account3",
  "spl-token.transfer_checked",
  "spl-token.mint_to",
  "spl-token.burn",
  "spl-token.approve",
  "spl-token.revoke",
  "spl-token.close_account",
  "spl-token.set_authority",
  "associated-token.create",
  "associated-token.create_idempotent",
  "memo.memo",
  "token-2022.initialize_transfer_fee_config",
  "token-2022.transfer_checked_with_fee",
  "token-2022.withdraw_withheld_tokens_from_mint",
  "token-2022.withdraw_withheld_tokens_from_accounts",
  "token-2022.harvest_withheld_tokens_to_mint",
  "token-2022.set_transfer_fee",
  "token-2022.initialize_non_transferable_mint",
  "token-2022.initialize_metadata_pointer",
  "token-2022.initialize_default_account_state",
  "token-2022.initialize_immutable_owner",
  "token-2022.initialize_permanent_delegate",
  "token-2022.initialize_interest_bearing_mint",
  "token-2022.enable_required_memo_transfers",
  "token-2022.initialize_transfer_hook",
  "token-2022.initialize_pausable_config",
  "token-2022.pause",
  "token-2022.resume",
  "stake.delegate_stake",
  "stake.deactivate",
  "stake.withdraw",
  "vote.vote",
  "config.create",
  "metaplex.create_metadata_account",
  "metaplex.update_metadata_account"
]

/-- Intentionally unsupported (compile-reject): confidential / crypto-hard layouts.
Must remain `isSupportedCpiDataLayout = false` — never pack empty CPI. -/
def rejectedLayoutExamples : Array String := #[
  "spl-token.confidential_transfer",
  "spl-token.confidential_transfer_init",
  "token-2022.confidential_transfer",
  "token-2022.confidential_transfer_init",
  "token-2022.zk_elgamal_proof"
]

/-- Inventory helper: true when layout is listed as confidential/crypto-hard. -/
def isConfidentialOrZkLayout (layout : String) : Bool :=
  rejectedLayoutExamples.contains layout ||
    layout.startsWith "spl-token.confidential" ||
    layout.startsWith "token-2022.confidential" ||
    layout.startsWith "token-2022.zk_"

-- Re-export high-traffic builders (implementation stays in Solana.*).

export ProofForge.Solana (
  systemProgram
  splTokenProgram
  splToken2022Program
  associatedTokenProgram
  memoProgram
  systemTransferCall
  systemCreateAccountCall
  memoCall
  splTokenTransferCheckedCall
  splTokenInitializeMintCall
  splTokenInitializeAccount3Call
  splTokenMintToCall
  splTokenBurnCall
  splTokenApproveCall
  splTokenRevokeCall
  splTokenCloseAccountCall
  splTokenSetAuthorityCall
  associatedTokenCreateCall
  splToken2022InitializeTransferFeeConfigCall
  splToken2022TransferCheckedWithFeeCall
  splToken2022PauseCall
  splToken2022ResumeCall
  systemTransfer
  invokeSystemTransfer
  systemCreateAccount
  invokeSystemCreateAccount
  memo
  invokeMemo
  splTokenTransferChecked
  invokeSplTokenTransferChecked
  splTokenInitializeMint
  invokeSplTokenInitializeMint
  splTokenInitializeAccount3
  invokeSplTokenInitializeAccount3
  splTokenMintTo
  invokeSplTokenMintTo
  splTokenBurn
  invokeSplTokenBurn
  splTokenApprove
  invokeSplTokenApprove
  splTokenRevoke
  invokeSplTokenRevoke
  splTokenCloseAccount
  invokeSplTokenCloseAccount
  splTokenSetAuthority
  invokeSplTokenSetAuthority
  associatedTokenCreate
  invokeAssociatedTokenCreate
  splToken2022InitializeTransferFeeConfig
  invokeSplToken2022InitializeTransferFeeConfig
  splToken2022TransferCheckedWithFee
  invokeSplToken2022TransferCheckedWithFee
  splToken2022Pause
  invokeSplToken2022Pause
  splToken2022Resume
  invokeSplToken2022Resume
  stakeProgram
  voteProgram
  configProgram
  metaplexTokenMetadataProgram
  stakeDelegateStakeCall
  stakeDeactivateCall
  stakeWithdrawCall
  voteVoteCall
  configCreateCall
  metaplexCreateMetadataCall
  metaplexUpdateMetadataCall
  stakeDelegateStake
  invokeStakeDelegateStake
  stakeDeactivate
  invokeStakeDeactivate
  stakeWithdraw
  invokeStakeWithdraw
  voteVote
  invokeVoteVote
  configCreate
  invokeConfigCreate
  metaplexCreateMetadata
  invokeMetaplexCreateMetadata
  metaplexUpdateMetadata
  invokeMetaplexUpdateMetadata
)

end ProofForge.Protocols.Solana
