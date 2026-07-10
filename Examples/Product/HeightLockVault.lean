/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Binary height-lock vault (portable HostEnv checkpointId)

Cliff-style lock until host **block height** (`checkpointId` / NEAR
`block_index`) reaches `unlockHeight`, then claimable in full.

Contrast:
- `TimelockVault` — wall-clock `timestamp`
- `VestingVault` — linear time vesting
- `HeightLockVault` — block-height gate

  lake env proof-forge build --target wasm-near --root . \
    -o build/height-lock-vault Examples/Product/HeightLockVault.lean

NEAR compare: `just near-compare-height-lock-vault` / `-live`
-/
import ProofForge.Contract.Source

namespace Examples.Product.HeightLockVault

open ProofForge.Contract.Source

def lockedSlot : ScalarRef :=
  ProofForge.Contract.Surface.slot "locked" .u64

def unlockHeightSlot : ScalarRef :=
  ProofForge.Contract.Surface.slot "unlockHeight" .u64

def claimBalanceSlot : ScalarRef :=
  ProofForge.Contract.Surface.slot "claimBalance" .u64

def claimedSlot : ScalarRef :=
  ProofForge.Contract.Surface.slot "claimed" .u64

contract_source HeightLockVault do
  use ProofForge.Contract.Surface.scalar lockedSlot
  use ProofForge.Contract.Surface.scalar unlockHeightSlot
  use ProofForge.Contract.Surface.scalar claimBalanceSlot
  use ProofForge.Contract.Surface.scalar claimedSlot

  event Locked
  event Claimed

  entry init do
    lockedSlot := u64 0;
    unlockHeightSlot := u64 0;
    claimBalanceSlot := u64 0;
    claimedSlot := u64 0;

  entry lock (amount : .u64, unlockHeight : .u64) do
    do ProofForge.Contract.Surface.requireEq
      (ProofForge.Contract.Surface.read lockedSlot) (u64 0) "already locked";
    do ProofForge.Contract.Surface.requireEq
      (ProofForge.Contract.Surface.read claimedSlot) (u64 0) "already claimed";
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref amount)
      "zero amount";
    lockedSlot := amount;
    unlockHeightSlot := unlockHeight;
    emit Locked indexed #[] data
      #[fieldAsName "amount" amount, fieldAsName "unlockHeight" unlockHeight];

  entry claim do
    do ProofForge.Contract.Surface.requireEq
      (ProofForge.Contract.Surface.read claimedSlot) (u64 0) "already claimed";
    let locked : .u64 := lockedSlot;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref locked)
      "nothing locked";
    let unlock : .u64 := unlockHeightSlot;
    let height : .u64 := checkpointId;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref height)
      (ProofForge.Contract.Surface.ref unlock) "height too low";
    claimedSlot := u64 1;
    lockedSlot := u64 0;
    let bal : .u64 := claimBalanceSlot;
    claimBalanceSlot := bal +! locked;
    emit Claimed indexed #[] data #[fieldAsName "amount" locked];

  query get_locked returns(.u64) do
    return lockedSlot;

  query get_unlock_height returns(.u64) do
    return unlockHeightSlot;

  query claim_balance returns(.u64) do
    return claimBalanceSlot;

  query is_claimed returns(.u64) do
    return claimedSlot;

end Examples.Product.HeightLockVault
