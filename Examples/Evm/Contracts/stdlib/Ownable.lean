/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Portable Ownable access-control primitive authored with `contract_source`.
-/
import ProofForge.Contract.Source

namespace Ownable

open ProofForge.Contract.Source

namespace Spec

structure State where
  ownerAddr : Nat

def initialized (s : State) : Prop := s.ownerAddr ≠ 0

def isOwner (s : State) (caller : Nat) : Prop := caller = s.ownerAddr

theorem isOwner_refl (s : State) : isOwner s s.ownerAddr := by rfl

end Spec

contract_source Ownable do
  state «owner» : .u64

  entry init do
    do ProofForge.Contract.Surface.requireZero «owner» "already initialized";
    do ProofForge.Contract.Surface.write «owner» caller;

  query «owner» returns(.u64) do
    return «owner»;

  entry transferOwnership (newOwner : .u64) do
    do ProofForge.Contract.Surface.requireOwner «owner»;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref newOwner) "zero address";
    «owner» := newOwner;

  entry renounceOwnership do
    do ProofForge.Contract.Surface.requireOwner «owner»;
    «owner» := u64 0;

end Ownable
