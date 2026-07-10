/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

NEP-141 Fungible Token stdlib mixin for `contract_source` composition on NEAR.

Implements the core NEP-141 interface:
- `ft_total_supply` — total token supply (query)
- `ft_balance_of` — balance for an account (query)
- `ft_transfer` — transfer tokens to receiver (entry, requires caller + amount)
- `ft_approve` — set allowance for a spender using a flat `(owner, spender)` hash key
- `ft_transfer_call` — transfer with `ft_on_transfer` promise + `ft_resolve_transfer` callback
- `ft_metadata` — token metadata (NEP-148: decimals)
- `storage_deposit` / `storage_withdraw` / `storage_balance_of` /
  `storage_balance_bounds` — NEP-145-lite U64 projections. `storage_withdraw`
  enforces the 1-yoctoNEAR minimum deposit guard (NEP-145 requirement).
  Predecessor refund via `promise_transfer` remains a TODO (requires a
  runtime-account-id promise effect, not just pool-index crosscall).

`module.nearCrosscallStrings` layout for this mixin:
- `0` = `ft_on_transfer` method name
- `1` = `ft_resolve_transfer` callback method name
- `2+` = receiver account ids registered via `near_account "..."` in `contract_source`

`ft_transfer_call` takes `receiver_idx : .u32` selecting a registered receiver account
(pool index = `receiver_idx + 2`). Portable `receiver_id : .hash` continues to key balances.
The NEP-145 functions model registration balances as U64 values because the
current portable ABI does not expose NEAR's JSON object return shape yet.
-/
import ProofForge.Contract.Builder
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

/-- Pool indices into `module.nearCrosscallStrings` (see module header). -/
def ftMethodOnTransferIdx : Nat := 0
def ftMethodResolveIdx : Nat := 1
def ftReceiverBaseIdx : Nat := 2

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
  { id := "balances", keyType := .hash, valueType := .u64 }

/-- Allowance mapping: hashTwoToOne(owner, spender) -> u64 allowance. -/
def allowances : MapRef :=
  { id := "allowances", keyType := .hash, valueType := .u64 }

/-- NEP-145 storage deposits: account hash -> U64 projected yoctoNEAR balance. -/
def storageDeposits : MapRef :=
  { id := "storageDeposits", keyType := .hash, valueType := .u64 }

/-- Pending promise callback context for `ft_resolve_transfer`. -/
def pendingSender : ScalarRef :=
  ProofForge.Contract.Surface.slot "_ftPendingSender" .hash

def pendingReceiver : ScalarRef :=
  ProofForge.Contract.Surface.slot "_ftPendingReceiver" .hash

def pendingAmount : ScalarRef :=
  ProofForge.Contract.Surface.slot "_ftPendingAmount" .u64

def refundFtUnused (sender receiver unused : ProofForge.IR.Expr) : EntryM Unit := do
  ProofForge.Contract.Surface.whenPositive unused do
    let senderBal := mapRead balances sender
    do mapWrite balances sender (senderBal +! unused);
    let recvBal := mapRead balances receiver
    do mapWrite balances receiver (recvBal -! unused)

def registerFtMethods : ProofForge.Contract.Builder.ModuleM Unit := do
  discard <| ProofForge.Contract.Builder.nearCrosscallString "ft_on_transfer"
  discard <| ProofForge.Contract.Builder.nearCrosscallString "ft_resolve_transfer"
  discard <| ProofForge.Contract.Builder.nearCrosscallString "demo.receiver.testnet"

contract_mixin NearFungibleTokenMixin do
  do registerFtMethods;
  use ProofForge.Contract.Surface.scalar totalSupply
  use ProofForge.Contract.Surface.scalar tokenDecimals
  use ProofForge.Contract.Surface.scalar storageRequired
  use ProofForge.Contract.Surface.scalar pendingSender
  use ProofForge.Contract.Surface.scalar pendingReceiver
  use ProofForge.Contract.Surface.scalar pendingAmount
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

  entry storage_withdraw (account_id : .hash, amount : .u64) do
    let deposit : .u64 := nativeValue;
    do ProofForge.Contract.Surface.requireEq callerHash
      (ProofForge.Contract.Surface.ref account_id) "storage withdraw caller mismatch";
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref deposit)
      (u64 1) "storage withdraw requires at least 1 yoctoNEAR deposit";
    let previous : .u64 := mapRead storageDeposits account_id;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref previous)
      (ProofForge.Contract.Surface.ref amount) "insufficient storage deposit";
    do mapWrite storageDeposits account_id (previous -! amount);

  entry ft_transfer (receiver_id : .hash, amount : .u64) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref amount) "zero amount";
    let sender : .hash := callerHash;
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
    let who : .hash := callerHash;
    let bal : .u64 := mapRead balances who;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref bal)
      (ProofForge.Contract.Surface.ref amount) "insufficient balance";
    do mapWrite balances who (bal -! amount);
    let ts : .u64 := totalSupply;
    totalSupply := ts -! amount;
    emit FBurn indexed #[fieldAsName "from" who] data #[fieldAsName "amount" amount];

  entry ft_approve (spender_id : .hash, amount : .u64) do
    let ownerAcct : .hash := callerHash;
    let allowanceKey : .hash := ProofForge.IR.Expr.hashTwoToOne (expr ownerAcct) (expr spender_id);
    do mapWrite allowances allowanceKey amount;
    emit FApproval indexed #[fieldAsName "owner" ownerAcct, fieldAsName "spender" spender_id] data #[fieldAsName "amount" amount];

  entry ft_transfer_call (receiver_id : .hash, receiver_idx : .u32, amount : .u64) returns(.u64) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref amount) "zero amount";
    let sender : .hash := callerHash;
    let srcBal : .u64 := mapRead balances sender;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref srcBal)
      (ProofForge.Contract.Surface.ref amount) "insufficient balance";
    do mapWrite balances sender (srcBal -! amount);
    let dstBal : .u64 := mapRead balances receiver_id;
    do mapWrite balances receiver_id (dstBal +! amount);
    emit FTransfer indexed #[fieldAsName "from" sender, fieldAsName "to" receiver_id] data #[fieldAsName "amount" amount];
    do ProofForge.Contract.Surface.write pendingSender (expr sender);
    do ProofForge.Contract.Surface.write pendingReceiver (expr receiver_id);
    do ProofForge.Contract.Surface.write pendingAmount (expr amount);
    return ProofForge.Contract.Surface.nearPromiseThen
      (ProofForge.Contract.Surface.nearCrosscallPool
        (addValue
          (ProofForge.Contract.Surface.cast (ProofForge.Contract.Surface.ref receiver_idx) .u64)
          (u64 ftReceiverBaseIdx))
        (ProofForge.Contract.Surface.nearAddressLit ftMethodOnTransferIdx)
        #[ProofForge.Contract.Surface.ref sender, ProofForge.Contract.Surface.ref amount]
        (u64 0))
      (ProofForge.Contract.Surface.nearAddressLit ftMethodResolveIdx)
      #[] (u64 0);

  entry ft_resolve_transfer returns(.u64) do
    let unused : .u64 := ProofForge.Contract.Surface.nearPromiseResultU64 (u64 0);
    let sender : .hash := pendingSender;
    let receiver : .hash := pendingReceiver;
    let amount : .u64 := pendingAmount;
    do refundFtUnused (expr sender) (expr receiver) (expr unused);
    return amount -! unused;

contract_source NearFungibleToken do
  use mixin
  entry init do
    totalSupply := u64 0;
    tokenDecimals := u64 18;
    storageRequired := u64 1;

end ProofForge.Contract.Stdlib.NearFungibleToken
