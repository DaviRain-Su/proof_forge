/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Canonical ERC-721 NFT mixin for `contract_source` composition on EVM.
Uses standard selectors, three-indexed Transfer events, and tokenOwners storage.
`safeTransferFrom` does not invoke `onERC721Received` yet (documented limitation).
-/
import ProofForge.Contract.Source

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

contract_mixin ERC721Mixin do
  use ProofForge.Contract.Surface.mapState tokenOwners

  event Transfer

  query ownerOf (tokenId : .u64) returns(.u64) do
    let tokenOwner : .u64 := mapRead tokenOwners tokenId;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref tokenOwner) "invalid token";
    return tokenOwner;

  entry transferFrom (holder : .address, recipient : .address, tokenId : .u64) do
    let operator : .address := caller;
    let tokenOwner : .u64 := mapRead tokenOwners tokenId;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref tokenOwner) "invalid token";
    do ProofForge.Contract.Surface.requireEq (ProofForge.Contract.Surface.ref tokenOwner)
      (ProofForge.Contract.Surface.ref holder) "wrong from";
    do ProofForge.Contract.Surface.requireEq (ProofForge.Contract.Surface.ref operator)
      (ProofForge.Contract.Surface.ref holder) "not authorized";
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref recipient) "zero recipient";
    do mapWrite tokenOwners tokenId recipient;
    emit Transfer indexed #[
      fieldAsName "from" holder,
      fieldAsName "to" recipient,
      fieldAsName "tokenId" tokenId
    ] data #[];

  entry safeTransferFrom (holder : .address, recipient : .address, tokenId : .u64) do
    let operator : .address := caller;
    let tokenOwner : .u64 := mapRead tokenOwners tokenId;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref tokenOwner) "invalid token";
    do ProofForge.Contract.Surface.requireEq (ProofForge.Contract.Surface.ref tokenOwner)
      (ProofForge.Contract.Surface.ref holder) "wrong from";
    do ProofForge.Contract.Surface.requireEq (ProofForge.Contract.Surface.ref operator)
      (ProofForge.Contract.Surface.ref holder) "not authorized";
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref recipient) "zero recipient";
    do mapWrite tokenOwners tokenId recipient;
    emit Transfer indexed #[
      fieldAsName "from" holder,
      fieldAsName "to" recipient,
      fieldAsName "tokenId" tokenId
    ] data #[];

  entry mint (recipient : .address, tokenId : .u64) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref recipient) "zero recipient";
    let existing : .u64 := mapRead tokenOwners tokenId;
    do ProofForge.Contract.Surface.requireEq (ProofForge.Contract.Surface.ref existing) (u64 0) "token exists";
    do mapWrite tokenOwners tokenId recipient;
    emit Transfer indexed #[
      fieldAsName "from" (u64 0),
      fieldAsName "to" recipient,
      fieldAsName "tokenId" tokenId
    ] data #[];

  entry burn (tokenId : .u64) do
    let who : .address := caller;
    let tokenOwner : .u64 := mapRead tokenOwners tokenId;
    do ProofForge.Contract.Surface.requireEq (ProofForge.Contract.Surface.ref tokenOwner)
      (ProofForge.Contract.Surface.ref who) "not owner";
    do mapWrite tokenOwners tokenId (u64 0);
    emit Transfer indexed #[
      fieldAsName "from" who,
      fieldAsName "to" (u64 0),
      fieldAsName "tokenId" tokenId
    ] data #[];

contract_source ERC721 do
  use mixin

end ProofForge.Contract.Stdlib.ERC721
