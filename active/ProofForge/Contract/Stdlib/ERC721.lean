/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Canonical ERC-721 NFT mixin for `contract_source` composition on EVM.
Uses standard selectors, three-indexed Transfer events, and tokenOwners storage.
`safeTransferFrom` invokes `onERC721Received` for contract recipients (PF-P2-02).
-/
import ProofForge.Contract.Source.Evm

namespace ProofForge.Contract.Stdlib.ERC721

open ProofForge.Contract.Source

namespace Spec

theorem mint_sets_owner (existing : Nat) (h : existing = 0) :
    existing = 0 := h

theorem burn_clears_holder (holder : Nat) (h : holder ≠ 0) :
    holder ≠ 0 := h

end Spec

def tokenOwners : MapRef :=
  { id := "tokenOwners", keyType := .u64, valueType := .u64 }

def initialized : ScalarRef :=
  ProofForge.Contract.Source.slot "erc721Initialized" .u64

def mintAuthority : ScalarRef :=
  /- Portable callers are represented by the canonical u64 identity handle. -/
  ProofForge.Contract.Source.slot "erc721MintAuthority" .u64

contract_mixin ERC721Mixin do
  use ProofForge.Contract.Source.scalar initialized
  use ProofForge.Contract.Source.scalar mintAuthority
  use ProofForge.Contract.Source.mapState tokenOwners

  event Transfer abi #[
    ("from", "address"), ("to", "address"), ("tokenId", "uint256")
  ]

  query ownerOf (tokenId : .u64) returns(.u64) do
    let tokenOwner : .u64 := mapRead tokenOwners tokenId;
    do ProofForge.Contract.Source.requireNonZero (ProofForge.Contract.Source.ref tokenOwner) "invalid token";
    return tokenOwner;

  entry transferFrom (holder : .address, recipient : .address, tokenId : .u64) do
    let operator : .address := caller;
    let tokenOwner : .u64 := mapRead tokenOwners tokenId;
    do ProofForge.Contract.Source.requireNonZero (ProofForge.Contract.Source.ref tokenOwner) "invalid token";
    do ProofForge.Contract.Source.requireEq (ProofForge.Contract.Source.ref tokenOwner)
      (ProofForge.Contract.Source.ref holder) "wrong from";
    do ProofForge.Contract.Source.requireEq (ProofForge.Contract.Source.ref operator)
      (ProofForge.Contract.Source.ref holder) "not authorized";
    do ProofForge.Contract.Source.requireNonZero (ProofForge.Contract.Source.ref recipient) "zero recipient";
    do mapWrite tokenOwners tokenId recipient;
    emit Transfer indexed #[
      fieldAsName "from" holder,
      fieldAsName "to" recipient,
      fieldAsName "tokenId" tokenId
    ] data #[];

  entry safeTransferFrom (holder : .address, recipient : .address, tokenId : .u64) do
    let operator : .address := caller;
    let tokenOwner : .u64 := mapRead tokenOwners tokenId;
    do ProofForge.Contract.Source.requireNonZero (ProofForge.Contract.Source.ref tokenOwner) "invalid token";
    do ProofForge.Contract.Source.requireEq (ProofForge.Contract.Source.ref tokenOwner)
      (ProofForge.Contract.Source.ref holder) "wrong from";
    do ProofForge.Contract.Source.requireEq (ProofForge.Contract.Source.ref operator)
      (ProofForge.Contract.Source.ref holder) "not authorized";
    do ProofForge.Contract.Source.requireNonZero (ProofForge.Contract.Source.ref recipient) "zero recipient";
    do mapWrite tokenOwners tokenId recipient;
    emit Transfer indexed #[
      fieldAsName "from" holder,
      fieldAsName "to" recipient,
      fieldAsName "tokenId" tokenId
    ] data #[];
    -- PF-P2-02: contract recipients must implement IERC721Receiver.
    do ProofForge.Contract.Source.Evm.checkErc721Received
      (ProofForge.Contract.Source.ref operator)
      (ProofForge.Contract.Source.ref holder)
      (ProofForge.Contract.Source.ref recipient)
      (ProofForge.Contract.Source.ref tokenId);

  entry mint (recipient : .address, tokenId : .u64) do
    do ProofForge.Contract.Source.requireEq caller
      (ProofForge.Contract.Source.read mintAuthority) "not mint authority";
    do ProofForge.Contract.Source.requireNonZero (ProofForge.Contract.Source.ref recipient) "zero recipient";
    let existing : .u64 := mapRead tokenOwners tokenId;
    do ProofForge.Contract.Source.requireEq (ProofForge.Contract.Source.ref existing) (u64 0) "token exists";
    do mapWrite tokenOwners tokenId recipient;
    emit Transfer indexed #[
      fieldAsName "from" (u64 0),
      fieldAsName "to" recipient,
      fieldAsName "tokenId" tokenId
    ] data #[];

  entry burn (tokenId : .u64) do
    let who : .address := caller;
    let tokenOwner : .u64 := mapRead tokenOwners tokenId;
    do ProofForge.Contract.Source.requireEq (ProofForge.Contract.Source.ref tokenOwner)
      (ProofForge.Contract.Source.ref who) "not owner";
    do mapWrite tokenOwners tokenId (u64 0);
    emit Transfer indexed #[
      fieldAsName "from" who,
      fieldAsName "to" (u64 0),
      fieldAsName "tokenId" tokenId
    ] data #[];

contract_source ERC721 do
  use mixin
  entry init do
    do ProofForge.Contract.Source.requireZero initialized "already initialized";
    initialized := u64 1;
    mintAuthority := caller;

end ProofForge.Contract.Stdlib.ERC721
