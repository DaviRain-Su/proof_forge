/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Two-party escrow (portable)

Internal-ledger escrow for dual-deploy compare:

- `init(buyer, seller)` → status Empty
- `fund(amount)` → Funded (one-shot)
- `release` → seller claim; `refund` → buyer claim
- Status codes: 0 Empty · 1 Funded · 2 Released · 3 Refunded

No native deposit / external token — NEAR dual-deploy friendly.

  lake env proof-forge build --target wasm-near --root . \
    -o build/escrow-vault Examples/Product/EscrowVault.lean

NEAR compare: `just near-compare-escrow-vault` / `-live`
-/
import ProofForge.Contract.Source

namespace Examples.Product.EscrowVault

open ProofForge.Contract.Source

/-- 0 empty · 1 funded · 2 released · 3 refunded -/
def statusEmpty : Nat := 0
def statusFunded : Nat := 1
def statusReleased : Nat := 2
def statusRefunded : Nat := 3

def buyerSlot : ScalarRef :=
  ProofForge.Contract.Surface.slot "buyer" .u64

def sellerSlot : ScalarRef :=
  ProofForge.Contract.Surface.slot "seller" .u64

def amountSlot : ScalarRef :=
  ProofForge.Contract.Surface.slot "amount" .u64

def statusSlot : ScalarRef :=
  ProofForge.Contract.Surface.slot "status" .u64

def sellerClaimSlot : ScalarRef :=
  ProofForge.Contract.Surface.slot "sellerClaim" .u64

def buyerClaimSlot : ScalarRef :=
  ProofForge.Contract.Surface.slot "buyerClaim" .u64

contract_source EscrowVault do
  use ProofForge.Contract.Surface.scalar buyerSlot
  use ProofForge.Contract.Surface.scalar sellerSlot
  use ProofForge.Contract.Surface.scalar amountSlot
  use ProofForge.Contract.Surface.scalar statusSlot
  use ProofForge.Contract.Surface.scalar sellerClaimSlot
  use ProofForge.Contract.Surface.scalar buyerClaimSlot

  event Funded
  event Released
  event Refunded

  entry init (buyerId : .u64, sellerId : .u64) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref buyerId)
      "zero buyer";
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref sellerId)
      "zero seller";
    do ProofForge.Contract.Surface.requireNe (ProofForge.Contract.Surface.ref buyerId)
      (ProofForge.Contract.Surface.ref sellerId) "same party";
    buyerSlot := buyerId;
    sellerSlot := sellerId;
    amountSlot := u64 0;
    statusSlot := u64 statusEmpty;
    sellerClaimSlot := u64 0;
    buyerClaimSlot := u64 0;

  entry fund (amt : .u64) do
    do ProofForge.Contract.Surface.requireEq
      (ProofForge.Contract.Surface.read statusSlot) (u64 statusEmpty) "not empty";
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref amt)
      "zero amount";
    amountSlot := amt;
    statusSlot := u64 statusFunded;
    emit Funded indexed #[fieldAsName "buyer" (ProofForge.Contract.Surface.read buyerSlot)]
      data #[fieldAsName "amount" amt];

  entry release do
    do ProofForge.Contract.Surface.requireEq
      (ProofForge.Contract.Surface.read statusSlot) (u64 statusFunded) "not funded";
    let amt : .u64 := amountSlot;
    statusSlot := u64 statusReleased;
    sellerClaimSlot := amt;
    emit Released indexed #[fieldAsName "seller" (ProofForge.Contract.Surface.read sellerSlot)]
      data #[fieldAsName "amount" amt];

  entry refund do
    do ProofForge.Contract.Surface.requireEq
      (ProofForge.Contract.Surface.read statusSlot) (u64 statusFunded) "not funded";
    let amt : .u64 := amountSlot;
    statusSlot := u64 statusRefunded;
    buyerClaimSlot := amt;
    emit Refunded indexed #[fieldAsName "buyer" (ProofForge.Contract.Surface.read buyerSlot)]
      data #[fieldAsName "amount" amt];

  query get_status returns(.u64) do
    return statusSlot;

  query get_amount returns(.u64) do
    return amountSlot;

  query seller_claim returns(.u64) do
    return sellerClaimSlot;

  query buyer_claim returns(.u64) do
    return buyerClaimSlot;

  query get_buyer returns(.u64) do
    return buyerSlot;

  query get_seller returns(.u64) do
    return sellerSlot;

end Examples.Product.EscrowVault
