/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

NEP-141 Fungible Token stdlib mixin for `contract_source` composition on NEAR.

Implements the core NEP-141 interface:
- `ft_total_supply` — total token supply (query)
- `ft_balance_of` — balance for an account (query)
- `ft_transfer` — transfer tokens to receiver (entry, requires caller + amount)
- `ft_metadata` — token metadata (NEP-148: decimals)
- `storage_deposit` / `storage_balance_of` / `storage_balance_bounds` — NEP-145
  starter surface using U64 projected balances

**Limitation:** `ft_transfer_call` requires the NEAR Promise API for
cross-contract calls. This mixin provides a stub that emits a log but does
not invoke the receiver's `ft_on_transfer` callback. Full `ft_transfer_call`
support requires Promise API lowering (deferred — see platform-gaps doc).
The NEP-145 functions model registration balances as U64 values because the
current portable ABI does not expose NEAR's JSON object return shape yet.
-/
import ProofForge.Contract.Source

namespace ProofForge.Contract.Stdlib.NearFungibleToken

open ProofForge.Contract.Source

namespace Spec

theorem transfer_conserves_supply {srcBal dstBal amount : Nat}
    (h_src : amount ≤ srcBal)
    : (srcBal - amount) + (dstBal + amount) = srcBal + dstBal := by
  omega

theorem mint_increases_supply {supply amount : Nat}
    : supply + amount ≥ supply := by omega

theorem burn_decreases_supply {supply amount : Nat}
    (h : amount ≤ supply)
    : supply - amount ≤ supply := by omega

end Spec

/-- Total token supply state (u64). -/
def totalSupply : ScalarRef :=
  ProofForge.Contract.Surface.slot "totalSupply" .u64

/-- Token decimals (NEP-148). -/
def tokenDecimals : ScalarRef :=
  ProofForge.Contract.Surface.slot "decimals" .u64

/-- Minimum storage deposit for account registration (U64 projection). -/
def storageRequired : ScalarRef :=
  ProofForge.Contract.Surface.slot "storageRequired" .u64

/-- Balance mapping: account hash -> u64 balance. -/
def balances : MapRef :=
  { id := "balances", keyType := .u64, valueType := .u64 }

/-- Allowance mapping: (owner, spender) -> u64 allowance (NEP-141 extension). -/
def allowances : MapRef :=
  { id := "allowances", keyType := .u64, valueType := .u64 }

/-- NEP-145 storage deposits: account hash -> U64 projected yoctoNEAR balance. -/
def storageDeposits : MapRef :=
  { id := "storageDeposits", keyType := .hash, valueType := .u64 }

contract_mixin NearFungibleTokenMixin do
  use ProofForge.Contract.Surface.scalar totalSupply
  use ProofForge.Contract.Surface.scalar tokenDecimals
  use ProofForge.Contract.Surface.scalar storageRequired
  use ProofForge.Contract.Surface.mapState balances
  use ProofForge.Contract.Surface.mapState allowances
  use ProofForge.Contract.Surface.mapState storageDeposits

  event FTransfer
  event FMint
  event FBurn
  event FApproval
  event StorageDeposit

  query ft_total_supply returns(.u64) do
    return totalSupply;

  query ft_balance_of (account_id : .hash) returns(.u64) do
    return mapRead balances account_id;

  query ft_metadata returns(.u64) do
    return tokenDecimals;

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
    emit StorageDeposit indexed #[fieldAsName "account" account_id] data #[fieldAsName "amount" amount];

  entry ft_transfer (receiver_id : .hash, amount : .u64) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref amount) "zero amount";
    let sender : .hash := caller;
    let srcBal : .u64 := mapRead balances sender;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref srcBal)
      (ProofForge.Contract.Surface.ref amount) "insufficient balance";
    do mapWrite balances sender (srcBal -! amount);
    let dstBal : .u64 := mapRead balances receiver_id;
    do mapWrite balances receiver_id (dstBal +! amount);
    emit FTransfer indexed #[fieldAsName "from" sender, fieldAsName "to" receiver_id] data #[fieldAsName "amount" amount];

  entry ft_mint (receiver_id : .hash, amount : .u64) do
    let srcBal : .u64 := mapRead balances receiver_id;
    do mapWrite balances receiver_id (srcBal +! amount);
    let ts : .u64 := totalSupply;
    totalSupply := ts +! amount;
    emit FMint indexed #[fieldAsName "to" receiver_id] data #[fieldAsName "amount" amount];

  entry ft_burn (amount : .u64) do
    let who : .hash := caller;
    let bal : .u64 := mapRead balances who;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref bal)
      (ProofForge.Contract.Surface.ref amount) "insufficient balance";
    do mapWrite balances who (bal -! amount);
    let ts : .u64 := totalSupply;
    totalSupply := ts -! amount;
    emit FBurn indexed #[fieldAsName "from" who] data #[fieldAsName "amount" amount];

  entry ft_approve (spender_id : .hash, amount : .u64) do
    let ownerAcct : .hash := caller;
    do pathWriteAllowance allowances (ProofForge.Contract.Surface.ref ownerAcct)
      (ProofForge.Contract.Surface.ref spender_id) amount;
    emit FApproval indexed #[fieldAsName "owner" ownerAcct, fieldAsName "spender" spender_id] data #[fieldAsName "amount" amount];

  entry ft_transfer_call (receiver_id : .hash, amount : .u64) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref amount) "zero amount";
    let sender : .hash := caller;
    let srcBal : .u64 := mapRead balances sender;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref srcBal)
      (ProofForge.Contract.Surface.ref amount) "insufficient balance";
    do mapWrite balances sender (srcBal -! amount);
    let dstBal : .u64 := mapRead balances receiver_id;
    do mapWrite balances receiver_id (dstBal +! amount);
    emit FTransfer indexed #[fieldAsName "from" sender, fieldAsName "to" receiver_id] data #[fieldAsName "amount" amount];
    do ProofForge.Contract.Surface.assertCondition (ProofForge.Contract.Surface.ne (ProofForge.Contract.Surface.ref amount) (u64 0)) "ft_transfer_call: promise callback not implemented";

contract_source NearFungibleToken do
  use mixin
  entry init do
    totalSupply := u64 0;
    tokenDecimals := u64 18;
    storageRequired := u64 1;

end ProofForge.Contract.Stdlib.NearFungibleToken
