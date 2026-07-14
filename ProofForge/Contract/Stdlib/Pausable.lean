/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Portable Pausable emergency-stop mixin for `contract_source` composition.

`pause` / `unpause` are **unauthenticated** so hosts can compose ownership
separately. For OpenZeppelin-style only-owner pause, use
`ProofForge.Contract.Stdlib.OwnablePausable` (or compose Ownable + this mixin
with custom entries).
-/
import ProofForge.Contract.Source

namespace ProofForge.Contract.Stdlib.Pausable

open ProofForge.Contract.Source

namespace Spec

def paused (s : Nat) : Prop := s ≠ 0

theorem not_paused_zero : ¬ paused 0 := by simp [paused]

end Spec

def «paused» : ScalarRef :=
  ProofForge.Contract.Source.slot "paused" .u64

contract_mixin PausableMixin do
  use ProofForge.Contract.Source.scalar «paused»

  query «paused» returns(.u64) do
    return «paused»;

  entry pause do
    guard_not_paused «paused»;
    «paused» := u64 1;

  entry unpause do
    guard_paused «paused»;
    «paused» := u64 0;

contract_source Pausable do
  use mixin

end ProofForge.Contract.Stdlib.Pausable
