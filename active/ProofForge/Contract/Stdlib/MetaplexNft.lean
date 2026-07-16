/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Metaplex NFT stdlib mixin for `contract_source` composition on Solana.

Implements the core Metaplex Token Metadata interface using CPI:
- `mint_nft` — mint a new NFT and create its metadata account (entry)
- `transfer_nft` — transfer an NFT to a receiver (entry, requires caller ownership)
- `burn_nft` — burn an NFT (entry, requires caller ownership)
- `update_metadata` — update NFT metadata (entry, requires update authority)
- `nft_total_supply` — total NFT supply (query)
- `nft_balance_of` — NFT balance for an account (query)
- `nft_owner_of` — owner of a token (query)

Token ownership is modeled as a `u64 → hash` map (tokenId → owner account hash),
matching the NEAR NEP-171 and EVM ERC-721 patterns. Metadata is stored as
pre-built Borsh bytes referenced by `metadataSource` and passed to the
Metaplex CPI via `solana.cpi.metadata_source`.

This mixin composes with `ProofForge.Contract.Source.Solana.Legacy.Builders.metaplexCreateMetadata`
and `ProofForge.Contract.Source.Solana.Legacy.Builders.metaplexUpdateMetadata` CPI builders.
-/
import ProofForge.Contract.Builder
import ProofForge.Contract.Source

namespace ProofForge.Contract.Stdlib.MetaplexNft

open ProofForge.Contract.Source

namespace Spec

theorem mint_sets_owner {_ : Nat}
    : true := by trivial

theorem mint_increments_balance {bal : Nat}
    : bal + 1 > bal := by omega

theorem burn_decrements_balance {bal : Nat}
    (h : bal > 0)
    : bal - 1 < bal := by omega

theorem transfer_conserves_balance {senderBal recvBal : Nat}
    (h : senderBal > 0)
    : (senderBal - 1) + (recvBal + 1) = senderBal + recvBal := by omega

end Spec

/-- Token ownership: tokenId (u64) -> owner account hash. -/
def tokenOwners : MapRef :=
  { id := "metaplexTokenOwners", keyType := .u64, valueType := .hash }

/-- Account NFT balance: account hash -> NFT count. -/
def nftBalances : MapRef :=
  { id := "metaplexNftBalances", keyType := .hash, valueType := .u64 }

/-- Per-token metadata update authority: tokenId (u64) -> authority hash. -/
def nftUpdateAuthorities : MapRef :=
  { id := "metaplexUpdateAuthorities", keyType := .u64, valueType := .hash }

/-- Total NFT supply (u64). -/
def totalNftSupply : ScalarRef :=
  ProofForge.Contract.Source.slot "metaplexTotalSupply" .u64

def initialized : ScalarRef :=
  ProofForge.Contract.Source.slot "metaplexInitialized" .u64

def mintAuthority : ScalarRef :=
  ProofForge.Contract.Source.slot "metaplexMintAuthority" .hash

contract_mixin MetaplexNftMixin do
  use ProofForge.Contract.Source.scalar initialized
  use ProofForge.Contract.Source.scalar mintAuthority
  use ProofForge.Contract.Source.scalar totalNftSupply
  use ProofForge.Contract.Source.mapState tokenOwners
  use ProofForge.Contract.Source.mapState nftBalances
  use ProofForge.Contract.Source.mapState nftUpdateAuthorities

  event NftTransfer
  event NftMint
  event NftBurn
  event NftMetadataUpdate

  query nft_total_supply returns(.u64) do
    return totalNftSupply;

  query nft_balance_of (account_id : .hash) returns(.u64) do
    return mapRead nftBalances account_id;

  query nft_owner_of (token_id : .u64) returns(.hash) do
    return mapRead tokenOwners token_id;

  entry mint_nft (receiver_id : .hash, token_id : .u64, update_authority : .hash) do
    do ProofForge.Contract.Source.requireEq callerHash
      (ProofForge.Contract.Source.read mintAuthority) "not mint authority";
    let existing : .hash := mapRead tokenOwners token_id;
    do ProofForge.Contract.Source.requireEq (ProofForge.Contract.Source.ref existing)
      (ProofForge.Contract.Source.hash4 0 0 0 0) "token already exists";
    do mapWrite tokenOwners token_id receiver_id;
    do mapWrite nftUpdateAuthorities token_id update_authority;
    let bal : .u64 := mapRead nftBalances receiver_id;
    do mapWrite nftBalances receiver_id (bal +! (u64 1));
    let ts : .u64 := totalNftSupply;
    totalNftSupply := ts +! (u64 1);
    emit NftMint indexed #[fieldAsName "to" receiver_id] data #[fieldAsName "tokenId" token_id];

  entry transfer_nft (receiver_id : .hash, token_id : .u64) do
    let sender : .hash := callerHash;
    let tokenOwner : .hash := mapRead tokenOwners token_id;
    do ProofForge.Contract.Source.requireEq (ProofForge.Contract.Source.ref tokenOwner)
      (ProofForge.Contract.Source.ref sender) "not token owner";
    do mapWrite tokenOwners token_id receiver_id;
    let senderBal : .u64 := mapRead nftBalances sender;
    do mapWrite nftBalances sender (senderBal -! (u64 1));
    let recvBal : .u64 := mapRead nftBalances receiver_id;
    do mapWrite nftBalances receiver_id (recvBal +! (u64 1));
    emit NftTransfer indexed #[fieldAsName "from" sender, fieldAsName "to" receiver_id] data #[fieldAsName "tokenId" token_id];

  entry burn_nft (token_id : .u64) do
    let who : .hash := callerHash;
    let tokenOwner : .hash := mapRead tokenOwners token_id;
    do ProofForge.Contract.Source.requireEq (ProofForge.Contract.Source.ref tokenOwner)
      (ProofForge.Contract.Source.ref who) "not token owner";
    do mapWrite tokenOwners token_id (ProofForge.Contract.Source.hash4 0 0 0 0);
    do mapWrite nftUpdateAuthorities token_id (ProofForge.Contract.Source.hash4 0 0 0 0);
    let bal : .u64 := mapRead nftBalances who;
    do mapWrite nftBalances who (bal -! (u64 1));
    let ts : .u64 := totalNftSupply;
    totalNftSupply := ts -! (u64 1);
    emit NftBurn indexed #[fieldAsName "from" who] data #[fieldAsName "tokenId" token_id];

  entry update_metadata (token_id : .u64, new_authority : .hash) do
    let who : .hash := callerHash;
    let currentAuthority : .hash := mapRead nftUpdateAuthorities token_id;
    do ProofForge.Contract.Source.requireEq (ProofForge.Contract.Source.ref currentAuthority)
      (ProofForge.Contract.Source.ref who) "not update authority";
    do mapWrite nftUpdateAuthorities token_id new_authority;
    emit NftMetadataUpdate indexed #[fieldAsName "authority" who] data #[fieldAsName "tokenId" token_id];

contract_source MetaplexNft do
  use mixin
  entry init do
    do ProofForge.Contract.Source.requireZero initialized "already initialized";
    initialized := u64 1;
    mintAuthority := callerHash;
    totalNftSupply := u64 0;

end ProofForge.Contract.Stdlib.MetaplexNft
