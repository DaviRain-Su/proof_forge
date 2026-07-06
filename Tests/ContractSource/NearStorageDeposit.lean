/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Minimal NEAR storage-management fixture for target-first EmitWat smoke tests.
-/
import ProofForge.Contract.Source

namespace Tests.ContractSource.NearStorageDeposit

open ProofForge.Contract.Source

contract_source NearStorageDeposit do
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

end Tests.ContractSource.NearStorageDeposit
