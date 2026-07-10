/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Linear vesting vault (portable HostEnv timestamp)

Cliff-free linear vesting of a u64 allocation over `[start, start+duration]`.

- `vested` / `releasable` / `release` use host `timestamp` (HostEnv block time)
- `release` credits `released` and beneficiary `claimBalance` (internal ledger)
- No external token pulls — NEAR dual-deploy friendly

NEAR view forbids `storage_write`, so `vested` / `releasable` are **entries**
(they materialize via `vestedScratch`). Pure views: `claim_balance`,
`total_allocation`, `released_amount`.

  lake env proof-forge build --target wasm-near --root . \
    -o build/vesting-vault Examples/Product/VestingVault.lean

NEAR compare: `just near-compare-vesting-vault` / `-live`
-/
import ProofForge.Contract.Source

namespace Examples.Product.VestingVault

open ProofForge.Contract.Source

def beneficiary : ScalarRef :=
  ProofForge.Contract.Surface.slot "beneficiary" .u64

def totalAllocation : ScalarRef :=
  ProofForge.Contract.Surface.slot "totalAllocation" .u64

def released : ScalarRef :=
  ProofForge.Contract.Surface.slot "released" .u64

def startTime : ScalarRef :=
  ProofForge.Contract.Surface.slot "startTime" .u64

def duration : ScalarRef :=
  ProofForge.Contract.Surface.slot "duration" .u64

def claimBalance : ScalarRef :=
  ProofForge.Contract.Surface.slot "claimBalance" .u64

def vestedScratch : ScalarRef :=
  ProofForge.Contract.Surface.slot "vestedScratch" .u64

/-- Write vested amount into `vestedScratch` from host timestamp.

    Tests use `startTime = 0`. Fully vested when `elapsed >= duration`;
    otherwise `total * elapsed / duration`. Safe for large live host times
    (nanoseconds) because the pro-rate branch only runs when `elapsed < duration`.
-/
def computeVested : EntryM Unit := do
  let now := ProofForge.Contract.Surface.timestamp
  let start := ProofForge.Contract.Surface.read startTime
  let dur := ProofForge.Contract.Surface.read duration
  let total := ProofForge.Contract.Surface.read totalAllocation
  let elapsed := ProofForge.Contract.Surface.sub now start
  -- Default: fully vested (covers live NEAR ns timestamps ≫ duration).
  ProofForge.Contract.Surface.write vestedScratch total
  -- If still vesting (elapsed < duration), overwrite with pro-rate.
  let prorateBody : EntryM Unit := do
    ProofForge.Contract.Surface.requireNonZero dur "zero duration"
    ProofForge.Contract.Surface.write vestedScratch
      (ProofForge.Contract.Surface.div
        (ProofForge.Contract.Surface.mul total elapsed) dur)
  let (_, prorateB) := prorateBody.run {}
  ProofForge.Contract.Builder.ifElse
    (ProofForge.Contract.Builder.lt elapsed dur) prorateB.body #[]

contract_source VestingVault do
  use ProofForge.Contract.Surface.scalar beneficiary
  use ProofForge.Contract.Surface.scalar totalAllocation
  use ProofForge.Contract.Surface.scalar released
  use ProofForge.Contract.Surface.scalar startTime
  use ProofForge.Contract.Surface.scalar duration
  use ProofForge.Contract.Surface.scalar claimBalance
  use ProofForge.Contract.Surface.scalar vestedScratch

  event Released

  entry init (who : .u64, total : .u64, start : .u64, dur : .u64) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref total)
      "zero total";
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref dur)
      "zero duration";
    beneficiary := who;
    totalAllocation := total;
    released := u64 0;
    startTime := start;
    duration := dur;
    claimBalance := u64 0;
    vestedScratch := u64 0;

  -- Entries (not queries): computeVested writes vestedScratch (NEAR view-safe).
  entry vested returns(.u64) do
    do computeVested;
    return vestedScratch;

  entry releasable returns(.u64) do
    do computeVested;
    let v : .u64 := vestedScratch;
    let r : .u64 := released;
    return v -! r;

  query claim_balance returns(.u64) do
    return claimBalance;

  query total_allocation returns(.u64) do
    return totalAllocation;

  query released_amount returns(.u64) do
    return released;

  entry release do
    do computeVested;
    let v : .u64 := vestedScratch;
    let r : .u64 := released;
    let amount : .u64 := v -! r;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref amount)
      "nothing releasable";
    released := r +! amount;
    let bal : .u64 := claimBalance;
    claimBalance := bal +! amount;
    emit Released indexed #[fieldAsName "beneficiary" (ProofForge.Contract.Surface.read beneficiary)]
      data #[fieldAsName "amount" amount];

end Examples.Product.VestingVault
