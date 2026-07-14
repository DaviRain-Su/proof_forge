/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Portable Ownable access-control mixin for `contract_source` composition.
To combine with ERC-20 in one contract, use the official `compose` API and import
`ProofForge.Contract.Stdlib.Compose.Specs` rather than chaining both mixins directly.
-/
import ProofForge.Contract.Source

namespace ProofForge.Contract.Stdlib.Ownable

open ProofForge.Contract.Source

namespace Spec

structure State where
  ownerAddr : Nat

def initialized (s : State) : Prop := s.ownerAddr ≠ 0

def isOwner (s : State) (caller : Nat) : Prop := caller = s.ownerAddr

theorem isOwner_refl (s : State) : isOwner s s.ownerAddr := by rfl

end Spec

def «owner» : ScalarRef :=
  ProofForge.Contract.Source.slot "owner" .u64

def ownableInitialized : ScalarRef :=
  ProofForge.Contract.Source.slot "ownableInitialized" .u64

contract_mixin OwnableMixin do
  use ProofForge.Contract.Source.scalar «owner»
  use ProofForge.Contract.Source.scalar ownableInitialized

  event OwnershipTransferred abi #[
    ("previousOwner", "address"),
    ("newOwner", "address")
  ]

  use ProofForge.Contract.Source.view
    (ProofForge.Contract.Source.methodWithReturnAbi "owner" #[] .u64 "address")
    (ProofForge.Contract.Source.ret (ProofForge.Contract.Source.read «owner»))

  entry transferOwnership (newOwner : .address) do
    guard_owner «owner»;
    do ProofForge.Contract.Source.requireNonZero (ProofForge.Contract.Source.ref newOwner) "zero address";
    emit OwnershipTransferred indexed #[
      fieldAsName "previousOwner" (ProofForge.Contract.Source.read «owner»),
      fieldAsName "newOwner"
        (ProofForge.Contract.Source.cast (ProofForge.Contract.Source.ref newOwner) .u64)
    ] data #[];
    «owner» := newOwner;

  entry renounceOwnership do
    guard_owner «owner»;
    emit OwnershipTransferred indexed #[
      fieldAsName "previousOwner" (ProofForge.Contract.Source.read «owner»),
      fieldAsName "newOwner" (u64 0)
    ] data #[];
    «owner» := u64 0;

contract_source Ownable do
  event OwnershipTransferred
  use mixin
  entry init do
    do ProofForge.Contract.Source.requireZero ownableInitialized "already initialized";
    ownableInitialized := u64 1;
    emit OwnershipTransferred indexed #[
      fieldAsName "previousOwner" (u64 0),
      fieldAsName "newOwner" (ProofForge.Contract.Source.cast caller .u64)
    ] data #[];
    «owner» := caller;

end ProofForge.Contract.Stdlib.Ownable
