/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Portable VerifiedVault for the unified EVM entry path. Source-level financial
proofs remain in `VerifiedVault.Spec`; codegen uses portable IR only.
-/
import ProofForge.Contract.Source
import ProofForge.Contract.Stdlib.ReentrancyGuard

namespace VerifiedVault

open ProofForge.Contract.Source
open ProofForge.Contract.Stdlib.ReentrancyGuard

namespace Spec

structure State where
  reserves : Nat
  shares   : Nat

def solvent (s : State) : Prop := s.reserves = s.shares

def empty : State := { reserves := 0, shares := 0 }

def deposit? (s : State) (amount : Nat) : Option State :=
  some { reserves := s.reserves + amount, shares := s.shares + amount }

def withdraw? (s : State) (amount : Nat) : Option State :=
  if amount ≤ s.reserves ∧ amount ≤ s.shares then
    some { reserves := s.reserves - amount, shares := s.shares - amount }
  else none

def canWithdraw (s : State) (amount : Nat) : Bool :=
  amount ≤ s.reserves ∧ amount ≤ s.shares

theorem empty_solvent : solvent empty := by rfl

theorem deposit_preserves_solvent {s next : State} {amount : Nat}
    (h : solvent s) (hn : deposit? s amount = some next) : solvent next := by
  unfold deposit? at hn
  simp at hn
  rw [← hn]
  show s.reserves + amount = s.shares + amount
  rw [h]

theorem withdraw_preserves_solvent {s next : State} {amount : Nat}
    (h : solvent s) (hn : withdraw? s amount = some next) : solvent next := by
  unfold withdraw? at hn
  by_cases w : amount ≤ s.reserves ∧ amount ≤ s.shares
  · simp [w] at hn
    rw [← hn]; show s.reserves - amount = s.shares - amount; rw [h]
  · simp [w] at hn

theorem deposit_increases_shares {s next : State} {amount : Nat}
    (hn : deposit? s amount = some next) : next.shares = s.shares + amount := by
  unfold deposit? at hn; simp at hn; rw [← hn]

theorem withdraw_decreases_reserves {s next : State} {amount : Nat}
    (hn : withdraw? s amount = some next) : next.reserves = s.reserves - amount := by
  unfold withdraw? at hn
  by_cases w : amount ≤ s.reserves ∧ amount ≤ s.shares
  · simp [w] at hn; rw [← hn]
  · simp [w] at hn

end Spec

contract_source VerifiedVault do
  import ProofForge.Contract.Stdlib.ReentrancyGuard;

  state «owner» : .u64
  state initialized : .u64
  state reserves : .u64
  state totalShares : .u64
  mapping balances from .u64 to .u64

  entry init do
    do ProofForge.Contract.Source.requireZero initialized "already initialized";
    «owner» := caller;
    initialized := u64 1;
    reserves := u64 0;
    totalShares := u64 0;

  entry deposit do
    accepts_callvalue;
    do ProofForge.Contract.Source.requireNe (ProofForge.Contract.Source.read initialized) (u64 0) "not initialized";
    let depositor : .u64 := caller;
    let amount : .u64 := nativeValue;
    do ProofForge.Contract.Source.requireNonZero (ProofForge.Contract.Source.ref amount) "zero deposit";
    let curReserves : .u64 := reserves;
    reserves := curReserves +! amount;
    let curShares : .u64 := totalShares;
    totalShares := curShares +! amount;
    let bal : .u64 := mapRead balances depositor;
    do mapWrite balances depositor (bal +! amount);

  entry withdraw (amount : .u64) do
    do ProofForge.Contract.Source.requireNe (ProofForge.Contract.Source.read initialized) (u64 0) "not initialized";
    acquire_lock lock;
    let withdrawer : .u64 := caller;
    let bal : .u64 := mapRead balances withdrawer;
    do ProofForge.Contract.Source.requireGe (ProofForge.Contract.Source.ref bal) (ProofForge.Contract.Source.ref amount) "insufficient balance";
    let curReserves : .u64 := reserves;
    do ProofForge.Contract.Source.requireGe (ProofForge.Contract.Source.ref curReserves) (ProofForge.Contract.Source.ref amount) "insufficient reserves";
    let curShares : .u64 := totalShares;
    do ProofForge.Contract.Source.requireGe (ProofForge.Contract.Source.ref curShares) (ProofForge.Contract.Source.ref amount) "insufficient shares";
    reserves := curReserves -! amount;
    totalShares := curShares -! amount;
    do mapWrite balances withdrawer (bal -! amount);
    sendto withdrawer amount;
    release_lock lock;

  query reserves returns(.u64) do
    return reserves;

  query totalShares returns(.u64) do
    return totalShares;

  query balanceOf (depositor : .u64) returns(.u64) do
    return mapRead balances depositor;

  query getOwner returns(.u64) do
    return «owner»;

end VerifiedVault
