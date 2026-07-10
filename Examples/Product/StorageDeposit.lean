/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Portable NEP-145-lite storage management for NEAR compare (N1.5).

U64 projections (not full NEP-145 JSON `StorageBalance` objects):

- `storage_balance_bounds` → min required deposit
- `storage_balance_of(account)` → cumulative registered deposit
- `storage_deposit(account)` → credit `nativeValue` when ≥ min
- `storage_withdraw(account, amount)` → caller-bound ledger debit when balance ≥ amount

This is not a complete NEP-145 withdrawal: it does not require exactly 1 yocto
or emit a predecessor refund Promise.

  lake env proof-forge build --target wasm-near --root . \
    -o build/storage-deposit Examples/Product/StorageDeposit.lean

NEAR compare: `just near-compare-storage-deposit` / `-live`
Offline lifecycle: `just near-storage-deposit-offline`
-/
import ProofForge.Contract.Source

namespace Examples.Product.StorageDeposit

open ProofForge.Contract.Source

contract_source StorageDeposit do
  state storageRequired : .u64
  mapping storageDeposits from .hash to .u64

  entry init do
    storageRequired := u64 1;

  query storage_balance_bounds returns(.u64) do
    return storageRequired;

  query storage_balance_of (account_id : .hash) returns(.u64) do
    return mapRead storageDeposits account_id;

  entry storage_deposit (account_id : .hash) do
    let amount : .u64 := nativeValue;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref amount)
      (ProofForge.Contract.Surface.read storageRequired) "storage deposit too small";
    let previous : .u64 := mapRead storageDeposits account_id;
    do mapWrite storageDeposits account_id (previous +! amount);

  entry storage_withdraw (account_id : .hash, amount : .u64) do
    do ProofForge.Contract.Surface.requireEq callerHash
      (ProofForge.Contract.Surface.ref account_id) "storage withdraw caller mismatch";
    let previous : .u64 := mapRead storageDeposits account_id;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref previous)
      (ProofForge.Contract.Surface.ref amount) "insufficient storage deposit";
    do mapWrite storageDeposits account_id (previous -! amount);

end Examples.Product.StorageDeposit
