/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Target-neutral Ownable authorization policy shared across the primary targets.

This file is the only Product authoring source. It normalizes directly from
`AuthoredContract` to checked Canonical Core and target-owned plans.
-/
import ProofForge.Contract.Source

namespace Examples.Product.Ownable

open ProofForge.Contract.Source

contract_source Ownable do
  state owner : .address
  state initialized : .u64

  event OwnershipTransferred #[
    indexedField previousOwner .address,
    indexedField newOwner .address
  ]

  entry init do
    do requireEq initialized (u64 0) "already initialized";
    initialized := u64 1;
    let sender : .address := caller;
    emit OwnershipTransferred #[
      indexedFieldAs previousOwner addressZero,
      indexedFieldAs newOwner sender
    ];
    owner := sender;

  query owner returns(.address) do
    return owner;

  entry transferOwnership (newOwner : .address) do
    do requireEq owner caller "caller is not owner";
    do requireNe newOwner addressZero "zero address";
    emit OwnershipTransferred #[
      indexedFieldAs previousOwner owner,
      indexedField newOwner
    ];
    owner := newOwner;

  entry renounceOwnership do
    do requireEq owner caller "caller is not owner";
    emit OwnershipTransferred #[
      indexedFieldAs previousOwner owner,
      indexedFieldAs newOwner addressZero
    ];
    owner := addressZero;

end Examples.Product.Ownable
