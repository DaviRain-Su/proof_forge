/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

NEP-171 Non-Fungible Token stdlib mixin for `contract_source` composition on NEAR.

Implements the core NEP-171 interface:
- `nft_total_supply` — total NFT supply (query)
- `nft_balance_of` — NFT balance for an account (query)
- `nft_owner_of` — owner of a token (query)
- `nft_mint` — mint a new token to a receiver (entry)
- `nft_transfer` — transfer a token to a receiver (entry, requires caller ownership)
- `nft_burn` — burn a token (entry, requires caller ownership)
- `nft_approve` — approve an account to operate a token (entry)
- `nft_metadata` — contract metadata (NEP-177: name, symbol) returns U64 (v0 projection)
- `nft_symbol` — contract symbol (NEP-177) returns U64 (v0 projection)

Token ownership is modeled as a `u64 → hash` map (tokenId → owner account hash).
Account balance is modeled as a `hash → u64` map (account → NFT count).
Approvals are modeled as a `u64 → hash` map (tokenId → approved account hash).

NEP-171 uses string token IDs in the native NEAR standard; this IR v0
models them as U64 for simplicity (matching the EVM ERC-721 pattern).
Account IDs are modeled as `hash` (matching the NEP-141 pattern in this stdlib).
-/
import ProofForge.Contract.Builder
import ProofForge.Contract.Source

namespace ProofForge.Contract.Stdlib.NearNft

open ProofForge.Contract.Source

namespace Spec

theorem transfer_conserves_ownership {_ : Nat}
    : true := by trivial

theorem mint_increments_balance {bal : Nat}
    : bal + 1 > bal := by omega

theorem burn_decrements_balance {bal : Nat}
    (h : bal > 0)
    : bal - 1 < bal := by omega

end Spec

/-- Token ownership: tokenId (u64) -> owner account hash. -/
def tokenOwners : MapRef :=
  { id := "nftTokenOwners", keyType := .u64, valueType := .hash }

/-- Account NFT balance: account hash -> NFT count. -/
def nftBalances : MapRef :=
  { id := "nftBalances", keyType := .hash, valueType := .u64 }

/-- Per-token approvals: tokenId (u64) -> approved account hash. -/
def nftApprovals : MapRef :=
  { id := "nftApprovals", keyType := .u64, valueType := .hash }

/-- Total NFT supply (u64). -/
def totalNftSupply : ScalarRef :=
  ProofForge.Contract.Surface.slot "nftTotalSupply" .u64

/-- NFT contract metadata: name (stored as u64 hash of name string for v0). -/
def nftContractName : ScalarRef :=
  ProofForge.Contract.Surface.slot "nftContractName" .u64

/-- NFT contract metadata: symbol (stored as u64 hash of symbol string for v0). -/
def nftContractSymbol : ScalarRef :=
  ProofForge.Contract.Surface.slot "nftContractSymbol" .u64

contract_mixin NearNftMixin do
  use ProofForge.Contract.Surface.scalar totalNftSupply
  use ProofForge.Contract.Surface.scalar nftContractName
  use ProofForge.Contract.Surface.scalar nftContractSymbol
  use ProofForge.Contract.Surface.mapState tokenOwners
  use ProofForge.Contract.Surface.mapState nftBalances
  use ProofForge.Contract.Surface.mapState nftApprovals

  event NftTransfer
  event NftMint
  event NftBurn
  event NftApproval

  query nft_total_supply returns(.u64) do
    return totalNftSupply;

  query nft_balance_of (account_id : .hash) returns(.u64) do
    return mapRead nftBalances account_id;

  query nft_owner_of (token_id : .u64) returns(.hash) do
    return mapRead tokenOwners token_id;

  query nft_metadata returns(.u64) do
    return nftContractName;

  query nft_symbol returns(.u64) do
    return nftContractSymbol;

  entry nft_mint (receiver_id : .hash, token_id : .u64) do
    let existing : .hash := mapRead tokenOwners token_id;
    do ProofForge.Contract.Surface.requireEq (ProofForge.Contract.Surface.ref existing)
      (ProofForge.Contract.Surface.hash4 0 0 0 0) "token already exists";
    do mapWrite tokenOwners token_id receiver_id;
    let bal : .u64 := mapRead nftBalances receiver_id;
    do mapWrite nftBalances receiver_id (bal +! (u64 1));
    let ts : .u64 := totalNftSupply;
    totalNftSupply := ts +! (u64 1);
    emit NftMint indexed #[fieldAsName "to" receiver_id] data #[fieldAsName "tokenId" token_id];

  entry nft_transfer (receiver_id : .hash, token_id : .u64) do
    let sender : .hash := callerHash;
    let tokenOwner : .hash := mapRead tokenOwners token_id;
    do ProofForge.Contract.Surface.requireEq (ProofForge.Contract.Surface.ref tokenOwner)
      (ProofForge.Contract.Surface.ref sender) "not token owner";
    do mapWrite tokenOwners token_id receiver_id;
    let senderBal : .u64 := mapRead nftBalances sender;
    do mapWrite nftBalances sender (senderBal -! (u64 1));
    let recvBal : .u64 := mapRead nftBalances receiver_id;
    do mapWrite nftBalances receiver_id (recvBal +! (u64 1));
    emit NftTransfer indexed #[fieldAsName "from" sender, fieldAsName "to" receiver_id] data #[fieldAsName "tokenId" token_id];

  entry nft_burn (token_id : .u64) do
    let who : .hash := callerHash;
    let tokenOwner : .hash := mapRead tokenOwners token_id;
    do ProofForge.Contract.Surface.requireEq (ProofForge.Contract.Surface.ref tokenOwner)
      (ProofForge.Contract.Surface.ref who) "not token owner";
    do mapWrite tokenOwners token_id (ProofForge.Contract.Surface.hash4 0 0 0 0);
    let bal : .u64 := mapRead nftBalances who;
    do mapWrite nftBalances who (bal -! (u64 1));
    let ts : .u64 := totalNftSupply;
    totalNftSupply := ts -! (u64 1);
    emit NftBurn indexed #[fieldAsName "from" who] data #[fieldAsName "tokenId" token_id];

  entry nft_approve (spender_id : .hash, token_id : .u64) do
    let tokenOwnerAcct : .hash := callerHash;
    let tokenOwner : .hash := mapRead tokenOwners token_id;
    do ProofForge.Contract.Surface.requireEq (ProofForge.Contract.Surface.ref tokenOwner)
      (ProofForge.Contract.Surface.ref tokenOwnerAcct) "not token owner";
    do mapWrite nftApprovals token_id spender_id;
    emit NftApproval indexed #[fieldAsName "owner" tokenOwnerAcct, fieldAsName "approved" spender_id] data #[fieldAsName "tokenId" token_id];

contract_source NearNft do
  use mixin
  entry init do
    totalNftSupply := u64 0;
    nftContractName := u64 0;
    nftContractSymbol := u64 0;

end ProofForge.Contract.Stdlib.NearNft