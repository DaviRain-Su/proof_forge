/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Binary timelock vault (portable HostEnv timestamp)

Cliff-style lock: deposit is held until host `timestamp >= unlockAt`, then
claimable in full (not linear vesting — contrast `VestingVault`).

- `lock(amount, unlockAt)` — one-shot fund while empty
- `claim` — require `timestamp >= unlockAt`, credit `claimBalance`
- Internal ledger only — NEAR dual-deploy friendly

  lake env proof-forge build --target wasm-near --root . \
    -o build/timelock-vault Examples/Product/TimelockVault.lean

NEAR compare: `just near-compare-timelock-vault` / `-live`
-/
import ProofForge.Contract.Source

namespace Examples.Product.TimelockVault

open ProofForge.Contract.Source

def lockedSlot : ScalarRef :=
  ProofForge.Contract.Surface.slot "locked" .u64

def unlockAtSlot : ScalarRef :=
  ProofForge.Contract.Surface.slot "unlockAt" .u64

def claimBalanceSlot : ScalarRef :=
  ProofForge.Contract.Surface.slot "claimBalance" .u64

def claimedSlot : ScalarRef :=
  ProofForge.Contract.Surface.slot "claimed" .u64

contract_source TimelockVault do
  use ProofForge.Contract.Surface.scalar lockedSlot
  use ProofForge.Contract.Surface.scalar unlockAtSlot
  use ProofForge.Contract.Surface.scalar claimBalanceSlot
  use ProofForge.Contract.Surface.scalar claimedSlot

  event Locked
  event Claimed

  entry init do
    lockedSlot := u64 0;
    unlockAtSlot := u64 0;
    claimBalanceSlot := u64 0;
    claimedSlot := u64 0;

  entry lock (amount : .u64, unlockAt : .u64) do
    do ProofForge.Contract.Surface.requireEq
      (ProofForge.Contract.Surface.read lockedSlot) (u64 0) "already locked";
    do ProofForge.Contract.Surface.requireEq
      (ProofForge.Contract.Surface.read claimedSlot) (u64 0) "already claimed";
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref amount)
      "zero amount";
    lockedSlot := amount;
    unlockAtSlot := unlockAt;
    emit Locked indexed #[] data
      #[fieldAsName "amount" amount, fieldAsName "unlockAt" unlockAt];

  entry claim do
    do ProofForge.Contract.Surface.requireEq
      (ProofForge.Contract.Surface.read claimedSlot) (u64 0) "already claimed";
    let locked : .u64 := lockedSlot;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref locked)
      "nothing locked";
    let unlock : .u64 := unlockAtSlot;
    let now : .u64 := timestamp;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref now)
      (ProofForge.Contract.Surface.ref unlock) "still locked";
    claimedSlot := u64 1;
    lockedSlot := u64 0;
    let bal : .u64 := claimBalanceSlot;
    claimBalanceSlot := bal +! locked;
    emit Claimed indexed #[] data #[fieldAsName "amount" locked];

  query get_locked returns(.u64) do
    return lockedSlot;

  query get_unlock_at returns(.u64) do
    return unlockAtSlot;

  query claim_balance returns(.u64) do
    return claimBalanceSlot;

  query is_claimed returns(.u64) do
    return claimedSlot;

end Examples.Product.TimelockVault
