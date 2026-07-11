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

/-- Token name (NEP-148 metadata, stored as u64 projection for v0). -/
def tokenName : ScalarRef :=
  ProofForge.Contract.Surface.slot "tokenName" .u64

/-- Token symbol (NEP-148 metadata, stored as u64 projection for v0). -/
def tokenSymbol : ScalarRef :=
  ProofForge.Contract.Surface.slot "tokenSymbol" .u64

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

/-- One-shot initialization marker and mint authority. -/
def initialized : ScalarRef :=
  ProofForge.Contract.Surface.slot "initialized" .u64

def mintAuthority : ScalarRef :=
  ProofForge.Contract.Surface.slot "mintAuthority" .hash

/-- Monotonic callback id and per-transfer resolver context. -/
def nextTransferId : ScalarRef :=
  ProofForge.Contract.Surface.slot "nextTransferId" .u64

def pendingAmounts : MapRef :=
  { id := "pendingAmounts", keyType := .u64, valueType := .u64 }

def pendingActive : MapRef :=
  { id := "pendingActive", keyType := .u64, valueType := .u64 }

def refundFtUnused (sender receiver refund : ProofForge.IR.Expr) : EntryM Unit := do
  ProofForge.Contract.Surface.whenPositive refund do
    let senderBal := mapRead balances sender
    do mapWrite balances sender (senderBal +! refund);
    let recvBal := mapRead balances receiver
    do mapWrite balances receiver (recvBal -! refund)

def boundedRefund (unused amount receiverBalance : ProofForge.IR.Expr) : EntryM ProofForge.IR.Expr := do
  ProofForge.Contract.Builder.letMutBind "refund" .u64 unused
  ProofForge.Contract.Builder.ifElse
    (ProofForge.Contract.Builder.lt amount (.local "refund"))
    #[.assign (.local "refund") amount]
    #[]
  ProofForge.Contract.Builder.ifElse
    (ProofForge.Contract.Builder.lt receiverBalance (.local "refund"))
    #[.assign (.local "refund") receiverBalance]
    #[]
  pure (.local "refund")

def callbackUnused (amount : ProofForge.IR.Expr) : EntryM ProofForge.IR.Expr := do
  ProofForge.Contract.Builder.letMutBind "unused" .u64 amount
  ProofForge.Contract.Builder.ifElse
    (ProofForge.Contract.Builder.eq (.nearPromiseResultStatus (u64 0)) (u64 1))
    #[.assign (.local "unused") (.nearPromiseResultU64 (u64 0))]
    #[]
  pure (.local "unused")

def registerFtMethods : ProofForge.Contract.Builder.ModuleM Unit := do
  discard <| ProofForge.Contract.Builder.nearCrosscallString "ft_on_transfer"
  discard <| ProofForge.Contract.Builder.nearCrosscallString "ft_resolve_transfer"
  discard <| ProofForge.Contract.Builder.nearCrosscallString "demo.receiver.testnet"

contract_mixin NearFungibleTokenMixin do
  do registerFtMethods;
  use ProofForge.Contract.Surface.scalar totalSupply
  use ProofForge.Contract.Surface.scalar tokenDecimals
  use ProofForge.Contract.Surface.scalar tokenName
  use ProofForge.Contract.Surface.scalar tokenSymbol
  use ProofForge.Contract.Surface.scalar storageRequired
  use ProofForge.Contract.Surface.scalar initialized
  use ProofForge.Contract.Surface.scalar mintAuthority
  use ProofForge.Contract.Surface.scalar nextTransferId
  use ProofForge.Contract.Surface.mapState balances
  use ProofForge.Contract.Surface.mapState allowances
  use ProofForge.Contract.Surface.mapState storageDeposits
  use ProofForge.Contract.Surface.mapState pendingAmounts
  use ProofForge.Contract.Surface.mapState pendingActive

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

  query ft_metadata_name returns(.u64) do
    return tokenName;

  query ft_metadata_symbol returns(.u64) do
    return tokenSymbol;

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
    do ProofForge.Contract.Surface.requireEq callerHash
      (ProofForge.Contract.Surface.read mintAuthority) "not mint authority";
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
    let transferId : .u64 := nextTransferId;
    nextTransferId := transferId +! u64 1;
    do mapWrite pendingAmounts transferId amount;
    do mapWrite pendingActive transferId (u64 1);
    return ProofForge.Contract.Surface.nearPromiseThen
      (ProofForge.Contract.Surface.nearCrosscallPool
        (addValue
          (ProofForge.Contract.Surface.cast (ProofForge.Contract.Surface.ref receiver_idx) .u64)
          (u64 ftReceiverBaseIdx))
        (ProofForge.Contract.Surface.nearAddressLit ftMethodOnTransferIdx)
        #[ProofForge.Contract.Surface.ref sender, ProofForge.Contract.Surface.ref amount]
        (u64 0))
      (ProofForge.Contract.Surface.nearAddressLit ftMethodResolveIdx)
      #[ProofForge.Contract.Surface.ref transferId, ProofForge.Contract.Surface.ref sender,
        ProofForge.Contract.Surface.ref receiver_id] (u64 0);

  entry ft_resolve_transfer (transfer_id : .u64, sender : .hash, receiver : .hash) returns(.u64) do
    do ProofForge.Contract.Surface.requireEq caller contractId "callback must be private";
    do ProofForge.Contract.Surface.requireEq .nearPromiseResultsCount (u64 1)
      "callback requires exactly one promise result";
    let active : .u64 := mapRead pendingActive transfer_id;
    do ProofForge.Contract.Surface.requireEq (ProofForge.Contract.Surface.ref active) (u64 1)
      "pending transfer missing";
    let amount : .u64 := mapRead pendingAmounts transfer_id;
    do mapWrite pendingActive transfer_id (u64 0);
    do discard <| callbackUnused (expr amount);
    let receiverBalance : .u64 := mapRead balances receiver;
    do discard <| boundedRefund (.local "unused") (expr amount) (expr receiverBalance);
    do refundFtUnused (expr sender) (expr receiver) (.local "refund");
    return amount -! ProofForge.IR.Expr.local "refund";

contract_source NearFungibleToken do
  use mixin
  entry init do
    do ProofForge.Contract.Surface.requireZero initialized "already initialized";
    initialized := u64 1;
    mintAuthority := callerHash;
    totalSupply := u64 0;
    tokenDecimals := u64 18;
    tokenName := u64 0;
    tokenSymbol := u64 0;
    storageRequired := u64 1;

end ProofForge.Contract.Stdlib.NearFungibleToken
