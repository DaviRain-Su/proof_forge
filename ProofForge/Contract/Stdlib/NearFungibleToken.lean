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
- `ft_metadata` — structured NEP-148 token metadata
- full NEP-145 storage management with JSON `StorageBalance` objects,
  exact one-yocto guards, predecessor refunds, unregister, and measured byte cost

`module.crosscallStrings` layout for this mixin:
- `0` = `ft_on_transfer` method name
- `1` = `ft_resolve_transfer` callback method name

`ft_transfer_call` passes its runtime `receiver_id` directly to
`promise_create`; receiver and callback arguments use named JSON objects.
-/
import ProofForge.Contract.Builder
import ProofForge.Contract.Source.Near
import ProofForge.Target.HostOps.Near

namespace ProofForge.Contract.Stdlib.NearFungibleToken

open ProofForge.Contract.Source
open ProofForge.Contract.Source.Near

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

/-- Pool indices into `module.crosscallStrings` (see module header). -/
def ftMethodOnTransferIdx : Nat := 0
def ftMethodResolveIdx : Nat := 1

/-- Total token supply state (u128). -/
def totalSupply : ScalarRef :=
  ProofForge.Contract.Surface.slot "totalSupply" .u128

/-- Token decimals (NEP-148). -/
def tokenDecimals : ScalarRef :=
  ProofForge.Contract.Surface.slot "decimals" .u64

/-- Token name (NEP-148 metadata, stored as u64 projection for v0). -/
def tokenName : ScalarRef :=
  ProofForge.Contract.Surface.slot "tokenName" .u64

/-- Token symbol (NEP-148 metadata, stored as u64 projection for v0). -/
def tokenSymbol : ScalarRef :=
  ProofForge.Contract.Surface.slot "tokenSymbol" .u64

/-- Minimum storage deposit and protocol byte price, both in yoctoNEAR. -/
def storageRequired : ScalarRef :=
  ProofForge.Contract.Surface.slot "storageRequired" .u128

def storageByteCost : ScalarRef :=
  ProofForge.Contract.Surface.slot "storageByteCost" .u128

/-- Balance mapping: account id string -> u128 balance. -/
def balances : MapRef :=
  { id := "balances", keyType := .string, valueType := .u128 }

/-- Allowance mapping: hashTwoToOne(owner, spender) -> u128 allowance. -/
def allowances : MapRef :=
  { id := "allowances", keyType := .hash, valueType := .u128 }

/-- NEP-145 locked deposits and measured registration bytes. -/
def storageDeposits : MapRef :=
  { id := "storageDeposits", keyType := .string, valueType := .u128 }

def storageBytes : MapRef :=
  { id := "storageBytes", keyType := .string, valueType := .u64 }

def storageBalanceDecl : ProofForge.IR.StructDecl := {
  name := "StorageBalance"
  fields := #[
    { id := "total", type := .u128 },
    { id := "available", type := .u128 }
  ]
}

def storageBalanceBoundsDecl : ProofForge.IR.StructDecl := {
  name := "StorageBalanceBounds"
  fields := #[
    { id := "min", type := .u128 },
    { id := "max", type := .u128 }
  ]
}

def fungibleTokenMetadataDecl : ProofForge.IR.StructDecl := {
  name := "FungibleTokenMetadata"
  fields := #[
    { id := "spec", type := .string },
    { id := "name", type := .string },
    { id := "symbol", type := .string },
    { id := "icon", type := .string },
    { id := "reference", type := .string },
    { id := "decimals", type := .u64 }
  ]
}

def storageBalanceValue (total : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  .structLit "StorageBalance" #[
    ("total", total), ("available", u128 0)
  ]

def storageBalanceBoundsValue (min : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  .structLit "StorageBalanceBounds" #[
    ("min", min), ("max", u128 0)
  ]

def fungibleTokenMetadataValue : ProofForge.IR.Expr :=
  .structLit "FungibleTokenMetadata" #[
    ("spec", .literal (.string "ft-1.0.0")),
    ("name", .literal (.string "ProofForge Token")),
    ("symbol", .literal (.string "PFT")),
    ("icon", .literal (.string "")),
    ("reference", .literal (.string "")),
    ("decimals", ProofForge.Contract.Surface.read tokenDecimals)
  ]

def mapDelete (mapRef : MapRef) (key : ProofForge.IR.Expr) : EntryM Unit :=
  ProofForge.Contract.Builder.effect (.storageMapDelete mapRef.id key)

def entryBody (body : EntryM Unit) : Array ProofForge.IR.Statement :=
  (body.run {}).2.body

def storageDepositNewBody : EntryM Unit := do
  ProofForge.Contract.Surface.requireGe (ProofForge.IR.Expr.local "attached")
    (ProofForge.Contract.Surface.read storageRequired) "storage deposit too small"
  ProofForge.Contract.Builder.letBind "registration_before" .u64 nearStorageUsage
  mapWrite balances (ProofForge.IR.Expr.local "storage_account") (u128 0)
  mapWrite storageDeposits (ProofForge.IR.Expr.local "storage_account")
    (ProofForge.Contract.Surface.read storageRequired)
  mapWrite storageBytes (ProofForge.IR.Expr.local "storage_account") (u64 1)
  ProofForge.Contract.Builder.letBind "registration_after" .u64 nearStorageUsage
  ProofForge.Contract.Builder.letBind "registration_used" .u64
    (ProofForge.Contract.Builder.sub (ProofForge.IR.Expr.local "registration_after")
      (ProofForge.IR.Expr.local "registration_before"))
  mapWrite storageBytes (ProofForge.IR.Expr.local "storage_account")
    (ProofForge.IR.Expr.local "registration_used")
  ProofForge.Contract.Builder.assign (ProofForge.IR.Expr.local "storage_total")
    (ProofForge.Contract.Surface.read storageRequired)
  ProofForge.Contract.Builder.letBind "storage_deposit_excess" .u128
    (ProofForge.Contract.Builder.sub (ProofForge.IR.Expr.local "attached")
      (ProofForge.Contract.Surface.read storageRequired))
  ProofForge.Contract.Builder.ifElse
    (ProofForge.Contract.Builder.gt (ProofForge.IR.Expr.local "storage_deposit_excess") (u128 0))
    #[.letBind "storage_deposit_refund" .u64
      (nearPromiseTransfer (ProofForge.IR.Expr.local "storage_account")
        (ProofForge.IR.Expr.local "storage_deposit_excess"))]
    #[]

def storageDepositExistingBody : EntryM Unit :=
  ProofForge.Contract.Builder.ifElse
    (ProofForge.Contract.Builder.gt (ProofForge.IR.Expr.local "attached") (u128 0))
    #[.letBind "storage_deposit_existing_refund" .u64
      (nearPromiseTransfer (ProofForge.IR.Expr.local "storage_account")
        (ProofForge.IR.Expr.local "attached"))]
    #[]

def storageUnregisterBody : EntryM Unit := do
  ProofForge.Contract.Builder.letBind "unregister_token_balance" .u128
    (mapRead balances (ProofForge.IR.Expr.local "account"))
  ProofForge.Contract.Builder.ifElse (ProofForge.IR.Expr.local "force") #[] #[
    .assert (ProofForge.Contract.Builder.eq
      (ProofForge.IR.Expr.local "unregister_token_balance") (u128 0))
      "positive token balance requires force" none
  ]
  ProofForge.Contract.Builder.ifElse
    (ProofForge.Contract.Builder.gt (ProofForge.IR.Expr.local "unregister_token_balance") (u128 0))
    #[
      .letBind "unregister_supply" .u128 (ProofForge.Contract.Surface.read totalSupply),
      .effect (.storageScalarWrite totalSupply.id
        (ProofForge.Contract.Builder.sub (ProofForge.IR.Expr.local "unregister_supply")
          (ProofForge.IR.Expr.local "unregister_token_balance")))
    ] #[]
  ProofForge.Contract.Builder.letBind "unregister_locked" .u128
    (mapRead storageDeposits (ProofForge.IR.Expr.local "account"))
  mapDelete balances (ProofForge.IR.Expr.local "account")
  mapDelete storageDeposits (ProofForge.IR.Expr.local "account")
  mapDelete storageBytes (ProofForge.IR.Expr.local "account")
  ProofForge.Contract.Builder.letBind "unregister_refund_amount" .u128
    (ProofForge.Contract.Builder.add (ProofForge.IR.Expr.local "unregister_locked") (u128 1))
  ProofForge.Contract.Builder.letBind "unregister_refund" .u64
    (nearPromiseTransfer (ProofForge.IR.Expr.local "account")
      (ProofForge.IR.Expr.local "unregister_refund_amount"))
  ProofForge.Contract.Builder.assign (ProofForge.IR.Expr.local "removed") (boolLit true)

/-- One-shot initialization marker and mint authority. -/
def initialized : ScalarRef :=
  ProofForge.Contract.Surface.slot "initialized" .u64

def mintAuthority : ScalarRef :=
  ProofForge.Contract.Surface.slot "mintAuthority" .hash

/-- Monotonic callback id and per-transfer resolver context. -/
def nextTransferId : ScalarRef :=
  ProofForge.Contract.Surface.slot "nextTransferId" .u64

def pendingAmounts : MapRef :=
  { id := "pendingAmounts", keyType := .u64, valueType := .u128 }

def pendingActive : MapRef :=
  { id := "pendingActive", keyType := .u64, valueType := .u64 }

def refundFtUnused (sender receiver refund : ProofForge.IR.Expr) : EntryM Unit := do
  let body : EntryM Unit := do
    let senderBal := mapRead balances sender
    do mapWrite balances sender (senderBal +! refund);
    let recvBal := mapRead balances receiver
    do mapWrite balances receiver (recvBal -! refund)
  let (_, entryBuilder) := body.run {}
  ProofForge.Contract.Builder.ifElse
    (ProofForge.Contract.Builder.gt refund (u128 0)) entryBuilder.body #[]

def boundedRefund (unused amount receiverBalance : ProofForge.IR.Expr) : EntryM ProofForge.IR.Expr := do
  ProofForge.Contract.Builder.letMutBind "refund" .u128 unused
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
  ProofForge.Contract.Builder.letMutBind "unused" .u128 amount
  ProofForge.Contract.Builder.ifElse
    (ProofForge.Contract.Builder.eq
      (.hostCall ProofForge.Target.HostOps.Near.promiseResultStatusSig.id #[u64 0]
        .u64 #[.nearPromise])
      (u64 1))
    #[.assign (.local "unused")
      (.hostCall ProofForge.Target.HostOps.Near.promiseResultU128Sig.id #[u64 0]
        .u128 #[.nearPromise])]
    #[]
  pure (.local "unused")

def registerFtMethods : ProofForge.Contract.Builder.ModuleM Unit := do
  discard <| ProofForge.Contract.Builder.nearCrosscallString "ft_on_transfer"
  discard <| ProofForge.Contract.Builder.nearCrosscallString "ft_resolve_transfer"

contract_mixin NearFungibleTokenMixin do
  do registerFtMethods;
  do ProofForge.Contract.Builder.struct storageBalanceDecl;
  do ProofForge.Contract.Builder.struct storageBalanceBoundsDecl;
  do ProofForge.Contract.Builder.struct fungibleTokenMetadataDecl;
  use ProofForge.Contract.Surface.scalar totalSupply
  use ProofForge.Contract.Surface.scalar tokenDecimals
  use ProofForge.Contract.Surface.scalar tokenName
  use ProofForge.Contract.Surface.scalar tokenSymbol
  use ProofForge.Contract.Surface.scalar storageRequired
  use ProofForge.Contract.Surface.scalar storageByteCost
  use ProofForge.Contract.Surface.scalar initialized
  use ProofForge.Contract.Surface.scalar mintAuthority
  use ProofForge.Contract.Surface.scalar nextTransferId
  use ProofForge.Contract.Surface.mapState balances
  use ProofForge.Contract.Surface.mapState allowances
  use ProofForge.Contract.Surface.mapState storageDeposits
  use ProofForge.Contract.Surface.mapState storageBytes
  use ProofForge.Contract.Surface.mapState pendingAmounts
  use ProofForge.Contract.Surface.mapState pendingActive

  event ft_transfer
  event ft_mint
  event ft_burn
  event ft_approval
  event storage_deposit

  query ft_total_supply returns(.u128) do
    return totalSupply;

  query ft_balance_of (account_id : .string) returns(.u128) do
    return mapRead balances account_id;

  query ft_metadata returns(.structType "FungibleTokenMetadata") do
    return fungibleTokenMetadataValue;

  query storage_balance_bounds returns(.structType "StorageBalanceBounds") do
    return storageBalanceBoundsValue (ProofForge.Contract.Surface.read storageRequired);

  query storage_balance_of (account_id : .string) returns(.structType "StorageBalance") do
    return storageBalanceValue (mapRead storageDeposits account_id);

  entry storage_deposit (account_id : .string, registration_only : .bool)
      returns(.structType "StorageBalance") do
    do ProofForge.Contract.Builder.letMutBind "storage_account" .string (expr account_id);
    do ProofForge.Contract.Builder.ifElse
      (ProofForge.Contract.Builder.eq (ProofForge.IR.Expr.local "storage_account") (.literal (.string "")))
      #[.assign (.local "storage_account") callerAccountId] #[];
    let attached : .u128 := callValueU128;
    let registered_bytes : .u64 := mapRead storageBytes (ProofForge.IR.Expr.local "storage_account");
    do ProofForge.Contract.Builder.letMutBind "storage_total" .u128
      (mapRead storageDeposits (ProofForge.IR.Expr.local "storage_account"));
    do ProofForge.Contract.Builder.ifElse
      (ProofForge.Contract.Builder.eq (expr registered_bytes) (u64 0))
      (entryBody storageDepositNewBody)
      (entryBody storageDepositExistingBody);
    emit storage_deposit indexed #[fieldAsName "account_id" (ProofForge.IR.Expr.local "storage_account")]
      data #[fieldAsName "amount" (ProofForge.IR.Expr.local "storage_total")];
    return storageBalanceValue (ProofForge.IR.Expr.local "storage_total");

  entry storage_withdraw (amount : .u128) returns(.structType "StorageBalance") do
    do ProofForge.Contract.Surface.requireEq callValueU128 (u128 1)
      "storage withdraw requires exactly 1 yoctoNEAR";
    let account : .string := callerAccountId;
    let registered_bytes : .u64 := mapRead storageBytes account;
    do ProofForge.Contract.Surface.requireGe (expr registered_bytes) (u64 1)
      "account is not registered";
    do ProofForge.Contract.Surface.requireEq (expr amount) (u128 0)
      "available storage balance is zero";
    return storageBalanceValue (mapRead storageDeposits account);

  entry storage_unregister (force : .bool) returns(.bool) do
    do ProofForge.Contract.Surface.requireEq callValueU128 (u128 1)
      "storage unregister requires exactly 1 yoctoNEAR";
    let account : .string := callerAccountId;
    let registered_bytes : .u64 := mapRead storageBytes account;
    do ProofForge.Contract.Builder.letMutBind "removed" .bool (boolLit false);
    do ProofForge.Contract.Builder.ifElse
      (ProofForge.Contract.Builder.gt (expr registered_bytes) (u64 0))
      (entryBody storageUnregisterBody) #[];
    return ProofForge.IR.Expr.local "removed";

  entry ft_transfer (receiver_id : .string, amount : .u128, memo : .string) do
    let deposit : .u64 := nativeValue;
    do ProofForge.Contract.Surface.requireEq (ProofForge.Contract.Surface.ref deposit)
      (u64 1) "ft_transfer requires exactly 1 yoctoNEAR";
    do ProofForge.Contract.Builder.assert (ProofForge.Contract.Builder.gt (ProofForge.Contract.Surface.ref amount) (u128 0)) "zero amount";
    let receiverStorage : .u64 := mapRead storageBytes receiver_id;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref receiverStorage)
      (u64 1) "receiver is not registered";
    let sender : .string := callerAccountId;
    let srcBal : .u128 := mapRead balances sender;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref srcBal)
      (ProofForge.Contract.Surface.ref amount) "insufficient balance";
    do mapWrite balances sender (srcBal -! amount);
    let dstBal : .u128 := mapRead balances receiver_id;
    do mapWrite balances receiver_id (dstBal +! amount);
    emit ft_transfer indexed #[fieldAsName "old_owner_id" sender, fieldAsName "new_owner_id" receiver_id] data #[fieldAsName "amount" amount];

  entry ft_mint (receiver_id : .string, amount : .u128) do
    do ProofForge.Contract.Surface.requireEq callerHash
      (ProofForge.Contract.Surface.read mintAuthority) "not mint authority";
    let srcBal : .u128 := mapRead balances receiver_id;
    do mapWrite balances receiver_id (srcBal +! amount);
    let ts : .u128 := totalSupply;
    totalSupply := ts +! amount;
    emit ft_mint indexed #[fieldAsName "owner_id" receiver_id] data #[fieldAsName "amount" amount];

  entry ft_burn (amount : .u128) do
    let who : .string := callerAccountId;
    let bal : .u128 := mapRead balances who;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref bal)
      (ProofForge.Contract.Surface.ref amount) "insufficient balance";
    do mapWrite balances who (bal -! amount);
    let ts : .u128 := totalSupply;
    totalSupply := ts -! amount;
    emit ft_burn indexed #[fieldAsName "owner_id" who] data #[fieldAsName "amount" amount];

  entry ft_approve (spender_id : .hash, amount : .u128) do
    let ownerAcct : .hash := callerHash;
    let allowanceKey : .hash := ProofForge.IR.Expr.hashTwoToOne (expr ownerAcct) (expr spender_id);
    do mapWrite allowances allowanceKey amount;
    emit ft_approval indexed #[fieldAsName "owner" ownerAcct, fieldAsName "spender" spender_id] data #[fieldAsName "amount" amount];

  entry ft_transfer_call (receiver_id : .string, amount : .u128, memo : .string,
      msg : .string) returns(.u64) do
    let deposit : .u64 := nativeValue;
    do ProofForge.Contract.Surface.requireEq (ProofForge.Contract.Surface.ref deposit)
      (u64 1) "ft_transfer_call requires exactly 1 yoctoNEAR";
    do ProofForge.Contract.Builder.assert (ProofForge.Contract.Builder.gt (ProofForge.Contract.Surface.ref amount) (u128 0)) "zero amount";
    let receiverStorage : .u64 := mapRead storageBytes receiver_id;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref receiverStorage)
      (u64 1) "receiver is not registered";
    let sender : .string := callerAccountId;
    let srcBal : .u128 := mapRead balances sender;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref srcBal)
      (ProofForge.Contract.Surface.ref amount) "insufficient balance";
    do mapWrite balances sender (srcBal -! amount);
    let dstBal : .u128 := mapRead balances receiver_id;
    do mapWrite balances receiver_id (dstBal +! amount);
    emit ft_transfer indexed #[fieldAsName "old_owner_id" sender, fieldAsName "new_owner_id" receiver_id] data #[fieldAsName "amount" amount];
    let transferId : .u64 := nextTransferId;
    nextTransferId := transferId +! u64 1;
    do mapWrite pendingAmounts transferId amount;
    do mapWrite pendingActive transferId (u64 1);
    return ProofForge.Contract.Surface.crosscallContinue
      (nearCrosscallPool
        (ProofForge.Contract.Surface.ref receiver_id)
        (nearAddressLit ftMethodOnTransferIdx)
        #[ProofForge.Contract.Surface.ref sender, ProofForge.Contract.Surface.ref amount,
          ProofForge.Contract.Surface.ref msg]
        (u64 0) #["sender_id", "amount", "msg"])
      (nearAddressLit ftMethodResolveIdx)
      #[ProofForge.Contract.Surface.ref transferId, ProofForge.Contract.Surface.ref sender,
        ProofForge.Contract.Surface.ref receiver_id] (u64 0)
      #["transfer_id", "sender", "receiver"];

  entry ft_resolve_transfer (transfer_id : .u64, sender : .string, receiver : .string) returns(.u128) do
    do ProofForge.Contract.Surface.requireEq caller contractId "callback must be private";
    do ProofForge.Contract.Surface.requireEq
      (.hostCall ProofForge.Target.HostOps.Near.promiseResultsCountSig.id #[] .u64 #[.nearPromise])
      (u64 1)
      "callback requires exactly one promise result";
    let active : .u64 := mapRead pendingActive transfer_id;
    do ProofForge.Contract.Surface.requireEq (ProofForge.Contract.Surface.ref active) (u64 1)
      "pending transfer missing";
    let amount : .u128 := mapRead pendingAmounts transfer_id;
    do mapWrite pendingActive transfer_id (u64 0);
    do discard <| callbackUnused (expr amount);
    let receiverBalance : .u128 := mapRead balances receiver;
    do discard <| boundedRefund (.local "unused") (expr amount) (expr receiverBalance);
    do refundFtUnused (expr sender) (expr receiver) (.local "refund");
    return amount -! ProofForge.IR.Expr.local "refund";

contract_source NearFungibleToken do
  use mixin
  entry init do
    do ProofForge.Contract.Surface.requireZero initialized "already initialized";
    initialized := u64 1;
    mintAuthority := callerHash;
    totalSupply := u128 0;
    tokenDecimals := u64 18;
    tokenName := u64 0;
    tokenSymbol := u64 0;
    storageByteCost := u128 10000000000000000000;
    let before : .u64 := nearStorageUsage;
    let dummy : .string := ProofForge.IR.Expr.literal (.string "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    do mapWrite balances dummy (u128 0);
    do mapWrite storageDeposits dummy (u128 0);
    do mapWrite storageBytes dummy (u64 1);
    let after : .u64 := nearStorageUsage;
    let used : .u128 := ProofForge.Contract.Surface.cast (after -! before) .u128;
    storageRequired := used *! ProofForge.Contract.Surface.read storageByteCost;
    do mapDelete balances (expr dummy);
    do mapDelete storageDeposits (expr dummy);
    do mapDelete storageBytes (expr dummy);

end ProofForge.Contract.Stdlib.NearFungibleToken
