/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Layer C — ERC-4626 vault mixin (pro-rata exchange rate)

Deployable vault **body** (you *are* the vault), not the Layer B external
client (`Protocols.Evm.IERC4626` / Product `external_vault`).

**Product v1 frozen (2026-07-09):** table below is the supported honesty
subset. Deferred (v2): fee-recipient push re-measure; non-EVM vault body
parity; performance fees / full OZ rounding matrix.

## Honesty bounds

| Feature | Behavior |
|---------|----------|
| Exchange rate | **Pro-rata**: `shares = assets * totalSupply / totalAssets` when supply > 0;
  empty vault (`totalSupply = 0`) is **1:1**. `convert*`, deposit, and redeem round
  down; the inverse `previewMint`/mint and `previewWithdraw`/withdraw paths round up. |
| Underlying ERC-20 | `deposit`/`mint` **pull** via IERC20 `transferFrom(caller, vaultSelf, amount)`;
  `withdraw`/`redeem` **push** via IERC20 `transfer(receiver, amount)`.
  Every mutating token call must return the ABI boolean word `1`; false reverts atomically.
  `vaultSelf` is init-set (portable `address(this)`). Method words are EVM
  selectors — **EVM-primary** packing. |
| Lifecycle safety | `init` is one-shot and validates non-zero asset, `vaultSelf == contractId`,
  and a non-zero fee recipient when fees are enabled. Deployment must invoke it atomically to
  avoid first-caller initialization. All four asset entrypoints share a reentrancy lock that is
  acquired before any external token call and released before success. |
| Share token | Minimal ERC-20 surface on **shares** |
| Entry fee | Optional **`feeBps` / 10000** on deposit/mint: fee shares mint to
  `feeRecipient`; user gets net. `mint(shares)` = **net** shares requested
  (gross = `shares * 10000 / (10000 - feeBps)` when fee > 0). |
| Exit fee | Same **`feeBps`** on withdraw/redeem: skim fee assets to
  `feeRecipient`; user receives net underlying. |
| Fee-on-transfer assets | **deposit/mint**: vault `balanceOf` **up-delta** after pull.
  `mint` treats that delta as a coverage check and always mints exactly the
  requested net/gross shares; insufficient FOT receipt reverts the pull.
  **withdraw/redeem**: vault **down-delta** for `totalAssets`; user push
  measures recipient `balanceOf` **up-delta** (event/return use actual
  received). Fee push to `feeRecipient` not re-measured on recipient. |
| `preview*` | assume non-FOT (requested ≈ actual); fees still applied in Spec |
| `max*` | conservative executable u64 limits; 100% fee disables all four paths |

Spec math lives in `Spec` (Nat formulas + fee/empty-vault theorems).
-/
import ProofForge.Contract.Source

namespace ProofForge.Contract.Stdlib.ERC4626

open ProofForge.Contract.Source

namespace Spec

structure State where
  totalAssets : Nat
  totalSupply : Nat

def empty : State := { totalAssets := 0, totalSupply := 0 }

/-- OpenZeppelin-style convert (floor). Empty supply → 1:1. -/
def convertToShares (s : State) (assets : Nat) : Nat :=
  if s.totalSupply == 0 || s.totalAssets == 0 then assets
  else assets * s.totalSupply / s.totalAssets

def convertToAssets (s : State) (shares : Nat) : Nat :=
  if s.totalSupply == 0 || s.totalAssets == 0 then shares
  else shares * s.totalAssets / s.totalSupply

/-- Overflow-safe mathematical ceiling division. A zero denominator is kept
    total for Spec use; live paths reject an inconsistent non-empty vault. -/
def ceilDiv (numerator denominator : Nat) : Nat :=
  if denominator == 0 then 0
  else
    numerator / denominator + if numerator % denominator == 0 then 0 else 1

/-- Inverse share quote used by `previewWithdraw`/withdraw (round up). -/
def convertToSharesUp (s : State) (assets : Nat) : Nat :=
  if s.totalSupply == 0 || s.totalAssets == 0 then assets
  else ceilDiv (assets * s.totalSupply) s.totalAssets

/-- Inverse asset quote used by `previewMint`/mint (round up). -/
def convertToAssetsUp (s : State) (shares : Nat) : Nat :=
  if s.totalSupply == 0 || s.totalAssets == 0 then shares
  else ceilDiv (shares * s.totalAssets) s.totalSupply

/-- Entry/exit fee amount from gross (`feeBps` basis points, floor). -/
def feeFromGross (gross feeBps : Nat) : Nat :=
  gross * feeBps / 10000

def entryFeeShares (gross feeBps : Nat) : Nat :=
  feeFromGross gross feeBps

def netAfterEntryFee (gross feeBps : Nat) : Nat :=
  gross - entryFeeShares gross feeBps

def exitFeeAssets (grossAssets feeBps : Nat) : Nat :=
  feeFromGross grossAssets feeBps

def netAfterExitFee (grossAssets feeBps : Nat) : Nat :=
  grossAssets - exitFeeAssets grossAssets feeBps

/-- Gross shares to mint so user receives `net` after entry fee (floor). -/
def grossSharesForNet (net feeBps : Nat) : Option Nat :=
  if feeBps == 0 then some net
  else if feeBps ≥ 10000 then none
  else
    let gross := net * 10000 / (10000 - feeBps)
    if gross == 0 || netAfterEntryFee gross feeBps == 0 then none
    else some gross

/-- Assets quoted by `previewMint`: apply entry-fee grossing first, then round
    the inverse pro-rata conversion up. -/
def previewMintAssets? (s : State) (netShares feeBps : Nat := 0) : Option Nat :=
  (grossSharesForNet netShares feeBps).map (convertToAssetsUp s)

/-- Shares quoted by `previewWithdraw` (round up). Exit fees affect the asset
    push in the current frozen subset, not the requested gross asset amount. -/
def previewWithdrawShares (s : State) (assets : Nat) : Nat :=
  convertToSharesUp s assets

/-- Mint exactly `netShares` when the actual pull covers the requested gross
    shares. Surplus conversion capacity is retained as vault backing. -/
def mintActual? (s : State) (netShares actualReceived : Nat) (feeBps : Nat := 0) :
    Option (State × Nat) := do
  if netShares == 0 || actualReceived == 0 then none else pure ()
  let gross ← grossSharesForNet netShares feeBps
  if gross == 0 || netAfterEntryFee gross feeBps != netShares then none
  else if convertToShares s actualReceived < gross then none
  else some ({
    totalAssets := s.totalAssets + actualReceived
    totalSupply := s.totalSupply + gross
  }, netShares)

/-- Gross asset limit accepted by `withdraw`; fee is applied inside withdraw. -/
def maxWithdrawAssets (s : State) (holderShares feeBps : Nat) : Nat :=
  if feeBps ≥ 10000 then 0
  else
    let shares := min holderShares s.totalSupply
    let grossAssets := convertToAssets s shares
    if netAfterExitFee grossAssets feeBps == 0 then 0 else grossAssets

/-- Executable share limit accepted by `redeem`. -/
def maxRedeemShares (s : State) (holderShares feeBps : Nat) : Nat :=
  if feeBps ≥ 10000 then 0
  else
    let shares := min holderShares s.totalSupply
    let grossAssets := convertToAssets s shares
    if netAfterExitFee grossAssets feeBps == 0 then 0 else shares

/-- Deposit; optional entry fee. Returns `(next, userShares)` where
`totalSupply` grows by **gross** shares (user + fee). -/
def deposit? (s : State) (assets : Nat) (feeBps : Nat := 0) : Option (State × Nat) :=
  if assets == 0 then none
  else
    let gross := convertToShares s assets
    if gross == 0 then none
    else
      let fee := entryFeeShares gross feeBps
      let user := gross - fee
      if user == 0 then none
      else some ({
        totalAssets := s.totalAssets + assets
        totalSupply := s.totalSupply + gross
      }, user)

/-- Withdraw `assets` from vault totals; user receives net after exit fee.
Returns `(next, sharesBurned)`. -/
def withdraw? (s : State) (assets : Nat) (feeBps : Nat := 0) : Option (State × Nat) :=
  if assets == 0 || assets > s.totalAssets then none
  else
    let shares := convertToSharesUp s assets
    if shares == 0 || shares > s.totalSupply then none
    else
      let userAssets := netAfterExitFee assets feeBps
      if userAssets == 0 then none
      else some ({
        totalAssets := s.totalAssets - assets
        totalSupply := s.totalSupply - shares
      }, shares)

/-- Redeem `shares`; user assets net of exit fee. Returns `(next, userAssets)`.
`actualLeft` is vault balance decrease after pushes (FOT-aware bookkeeping). -/
def redeem? (s : State) (shares : Nat) (feeBps : Nat := 0)
    (actualLeft? : Option Nat := none) : Option (State × Nat) :=
  if shares == 0 || shares > s.totalSupply then none
  else
    let assets := convertToAssets s shares
    if assets == 0 || assets > s.totalAssets then none
    else
      let userAssets := netAfterExitFee assets feeBps
      if userAssets == 0 then none
      else
        let left := actualLeft?.getD assets
        if left > s.totalAssets then none
        else some ({
          totalAssets := s.totalAssets - left
          totalSupply := s.totalSupply - shares
        }, userAssets)

/-- Exit FOT: book `actualLeft` vault decrease, not the planned transfer amount. -/
def redeemFot? (s : State) (shares actualLeft : Nat) (feeBps : Nat := 0) :
    Option (State × Nat) :=
  redeem? s shares feeBps (some actualLeft)

/-- Recipient-side FOT: amount credited to receiver after a push of `transferred`
    when the token skims `fotBps` on transfer (floor). -/
def recipientReceived (transferred fotBps : Nat) : Nat :=
  transferred - feeFromGross transferred fotBps

theorem empty_convert_shares (a : Nat) : convertToShares empty a = a := by
  simp [convertToShares, empty]

theorem empty_convert_assets (sh : Nat) : convertToAssets empty sh = sh := by
  simp [convertToAssets, empty]

theorem entry_fee_zero (g : Nat) : entryFeeShares g 0 = 0 := by
  simp [entryFeeShares, feeFromGross]

theorem entry_fee_one_percent :
    entryFeeShares 1000 100 = 10 := by
  decide

theorem deposit_fee_user_shares :
    netAfterEntryFee (convertToShares empty 1000) 100 = 990 := by
  decide

theorem exit_fee_one_percent :
    netAfterExitFee 1000 100 = 990 := by
  decide

theorem gross_for_net_zero_fee (n : Nat) :
    grossSharesForNet n 0 = some n := by
  simp [grossSharesForNet]

theorem gross_for_net_one_percent :
    grossSharesForNet 990 100 = some 1000 := by
  decide

/-- Fee-on-transfer honesty: Spec deposit uses **actual** received assets. -/
def depositActual? (s : State) (actualReceived : Nat) (feeBps : Nat := 0) :
    Option (State × Nat) :=
  deposit? s actualReceived feeBps

/-- After a first deposit of `a`, convert is still 1:1. -/
theorem convert_after_first_deposit (a assets : Nat) (ha : a ≠ 0) :
    convertToShares { totalAssets := a, totalSupply := a } assets = assets := by
  unfold convertToShares
  have h : (a == 0 || a == 0) = false := by simp [ha]
  rw [h]
  exact Nat.mul_div_cancel assets (Nat.pos_of_ne_zero ha)

/-- Concrete pro-rata: after donation doubles assets, deposit half-rates. -/
theorem convert_donation_example :
    convertToShares { totalAssets := 200, totalSupply := 100 } 100 = 50 := by
  native_decide

theorem convert_assets_donation_example :
    convertToAssets { totalAssets := 200, totalSupply := 100 } 50 = 100 := by
  native_decide

theorem inverse_rounding_example :
    convertToAssetsUp { totalAssets := 2, totalSupply := 3 } 1 = 1 ∧
    convertToSharesUp { totalAssets := 2, totalSupply := 3 } 1 = 2 := by
  native_decide

end Spec

def assetAddress : ScalarRef :=
  ProofForge.Contract.Surface.slot "asset" .address

def vaultSelf : ScalarRef :=
  ProofForge.Contract.Surface.slot "vaultSelf" .address

def totalAssetsSlot : ScalarRef :=
  ProofForge.Contract.Surface.slot "totalAssets" .u64

def totalSupply : ScalarRef :=
  ProofForge.Contract.Surface.slot "totalSupply" .u64

/-- Scratch for convert results (pro-rata branch). -/
def convertScratch : ScalarRef :=
  ProofForge.Contract.Surface.slot "convertScratch" .u64

/-- Scratch for entry-fee shares (`gross * feeBps / 10000`). -/
def feeScratch : ScalarRef :=
  ProofForge.Contract.Surface.slot "feeScratch" .u64

/-- Pre-pull `balanceOf(vaultSelf)` for fee-on-transfer delta. -/
def balanceScratch : ScalarRef :=
  ProofForge.Contract.Surface.slot "balanceScratch" .u64

/-- Actual assets received after pull (`balanceAfter - balanceBefore`). -/
def actualAssetsScratch : ScalarRef :=
  ProofForge.Contract.Surface.slot "actualAssets" .u64

/-- Pre-push recipient `balanceOf` for recipient-side FOT measure. -/
def recvBalScratch : ScalarRef :=
  ProofForge.Contract.Surface.slot "recvBalScratch" .u64

/-- Actual assets credited to receiver after user push (recipient up-delta). -/
def recvActualScratch : ScalarRef :=
  ProofForge.Contract.Surface.slot "recvActual" .u64

/-- Entry fee in basis points (0 = off, max 10000). -/
def feeBps : ScalarRef :=
  ProofForge.Contract.Surface.slot "feeBps" .u64

/-- Recipient of entry-fee share mints (must be non-zero when fee > 0). -/
def feeRecipient : ScalarRef :=
  ProofForge.Contract.Surface.slot "feeRecipient" .address

/-- Shared guard for all state-changing asset entrypoints. -/
def erc4626Lock : ScalarRef :=
  ProofForge.Contract.Surface.slot "erc4626Lock" .u64

/-- One-shot initialization marker. -/
def initialized : ScalarRef :=
  ProofForge.Contract.Surface.slot "initialized" .u64

/-- IERC20 `balanceOf(address)` selector. -/
def ierC20BalanceOfSelector : Nat := 0x70a08231
/-- IERC20 `transferFrom(address,address,uint256)` selector. -/
def ierC20TransferFromSelector : Nat := 0x23b872dd
/-- IERC20 `transfer(address,uint256)` selector. -/
def ierC20TransferSelector : Nat := 0xa9059cbb

def shareBalances : MapRef :=
  { id := "shareBalances", keyType := .u64, valueType := .u64 }

def shareAllowances : MapRef :=
  { id := "shareAllowances", keyType := .u64, valueType := .u64 }

def requireU64Result (value : ProofForge.IR.Expr) (message : String) : EntryM Unit :=
  ProofForge.Contract.Surface.requireGe
    (ProofForge.Contract.Surface.u64 0xffffffffffffffff) value message

def addressWord (value : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.cast value .u64

def requireRemoteTrue (name : String) (value : ProofForge.IR.Expr) : EntryM Unit := do
  ProofForge.Contract.Builder.letBind name .u64 value
  ProofForge.Contract.Surface.requireEq
    (ProofForge.Contract.Builder.localVar name)
    (ProofForge.Contract.Surface.u64 1)
    "ERC20 operation returned false"

def requireFeeRecipientWhenEnabled
    (bps recipient : ProofForge.IR.Expr) : EntryM Unit :=
  ProofForge.Contract.Surface.whenPositive bps do
    ProofForge.Contract.Surface.requireNonZero recipient "zero feeRecipient"

/-- When `totalSupply > 0`, overwrite `convertScratch` with
    `amount * totalSupply / totalAssets` (floor). Caller must seed
    `convertScratch` with the empty-vault 1:1 fallback first. -/
def applyConvertToShares (amount : ProofForge.IR.Expr) : EntryM Unit := do
  let ts := ProofForge.Contract.Surface.read totalSupply
  ProofForge.Contract.Surface.whenPositive ts do
    let ta := ProofForge.Contract.Surface.read totalAssetsSlot
    ProofForge.Contract.Surface.requireNonZero ta "zero totalAssets"
    ProofForge.Contract.Surface.write convertScratch
      (ProofForge.Contract.Surface.div
        (ProofForge.Contract.Surface.mul amount ts) ta)

/-- When `totalSupply > 0`, overwrite `convertScratch` with
    `amount * totalAssets / totalSupply` (floor). -/
def applyConvertToAssets (amount : ProofForge.IR.Expr) : EntryM Unit := do
  let ts := ProofForge.Contract.Surface.read totalSupply
  ProofForge.Contract.Surface.whenPositive ts do
    let ta := ProofForge.Contract.Surface.read totalAssetsSlot
    ProofForge.Contract.Surface.requireNonZero ta "zero totalAssets"
    ProofForge.Contract.Surface.write convertScratch
      (ProofForge.Contract.Surface.div
        (ProofForge.Contract.Surface.mul amount ta) ts)

/-- Inverse pro-rata share conversion for withdraw. Computes quotient and
    remainder separately so rounding up cannot overflow via `n + d - 1`. -/
def applyConvertToSharesUp (amount : ProofForge.IR.Expr) : EntryM Unit := do
  let ts := ProofForge.Contract.Surface.read totalSupply
  ProofForge.Contract.Surface.whenPositive ts do
    let ta := ProofForge.Contract.Surface.read totalAssetsSlot
    ProofForge.Contract.Surface.requireNonZero ta "zero totalAssets"
    ProofForge.Contract.Builder.letBind "_pf_shares_up_numerator" .u64
      (ProofForge.Contract.Surface.mul amount ts)
    let numerator := ProofForge.Contract.Builder.localVar "_pf_shares_up_numerator"
    ProofForge.Contract.Builder.letBind "_pf_shares_up_quotient" .u64
      (ProofForge.Contract.Surface.div numerator ta)
    let quotient := ProofForge.Contract.Builder.localVar "_pf_shares_up_quotient"
    requireU64Result quotient "withdraw share quote overflow"
    ProofForge.Contract.Surface.write convertScratch
      quotient
    ProofForge.Contract.Surface.whenPositive (ProofForge.Contract.Builder.mod numerator ta) do
      ProofForge.Contract.Surface.requireNe quotient
        (ProofForge.Contract.Surface.u64 0xffffffffffffffff)
        "withdraw share quote overflow"
      ProofForge.Contract.Surface.write convertScratch
        (ProofForge.Contract.Surface.add
          quotient
          (ProofForge.Contract.Surface.u64 1))

/-- Inverse pro-rata asset conversion for mint; see `applyConvertToSharesUp`. -/
def applyConvertToAssetsUp (amount : ProofForge.IR.Expr) : EntryM Unit := do
  let ts := ProofForge.Contract.Surface.read totalSupply
  ProofForge.Contract.Surface.whenPositive ts do
    let ta := ProofForge.Contract.Surface.read totalAssetsSlot
    ProofForge.Contract.Surface.requireNonZero ta "zero totalAssets"
    ProofForge.Contract.Builder.letBind "_pf_assets_up_numerator" .u64
      (ProofForge.Contract.Surface.mul amount ta)
    let numerator := ProofForge.Contract.Builder.localVar "_pf_assets_up_numerator"
    ProofForge.Contract.Builder.letBind "_pf_assets_up_quotient" .u64
      (ProofForge.Contract.Surface.div numerator ts)
    let quotient := ProofForge.Contract.Builder.localVar "_pf_assets_up_quotient"
    requireU64Result quotient "mint asset quote overflow"
    ProofForge.Contract.Surface.write convertScratch
      quotient
    ProofForge.Contract.Surface.whenPositive (ProofForge.Contract.Builder.mod numerator ts) do
      ProofForge.Contract.Surface.requireNe quotient
        (ProofForge.Contract.Surface.u64 0xffffffffffffffff)
        "mint asset quote overflow"
      ProofForge.Contract.Surface.write convertScratch
        (ProofForge.Contract.Surface.add
          quotient
          (ProofForge.Contract.Surface.u64 1))

/-- `convertScratch` holds **gross** shares. Writes fee to `feeScratch` and
    net user shares back to `convertScratch`. -/
def applyEntryFee : EntryM Unit := do
  let gross := ProofForge.Contract.Surface.read convertScratch
  let bps := ProofForge.Contract.Surface.read feeBps
  ProofForge.Contract.Surface.write feeScratch (ProofForge.Contract.Surface.u64 0)
  ProofForge.Contract.Surface.whenPositive bps do
    ProofForge.Contract.Surface.write feeScratch
      (ProofForge.Contract.Surface.div
        (ProofForge.Contract.Surface.mul gross bps)
        (ProofForge.Contract.Surface.u64 10000))
    ProofForge.Contract.Surface.write convertScratch
      (ProofForge.Contract.Surface.sub gross
        (ProofForge.Contract.Surface.read feeScratch))

/-- `convertScratch` holds **gross** assets. Exit fee skim → `feeScratch`;
    net user assets remain in `convertScratch`. -/
def applyExitFee : EntryM Unit := do
  let gross := ProofForge.Contract.Surface.read convertScratch
  let bps := ProofForge.Contract.Surface.read feeBps
  ProofForge.Contract.Surface.write feeScratch (ProofForge.Contract.Surface.u64 0)
  ProofForge.Contract.Surface.whenPositive bps do
    ProofForge.Contract.Surface.write feeScratch
      (ProofForge.Contract.Surface.div
        (ProofForge.Contract.Surface.mul gross bps)
        (ProofForge.Contract.Surface.u64 10000))
    ProofForge.Contract.Surface.write convertScratch
      (ProofForge.Contract.Surface.sub gross
        (ProofForge.Contract.Surface.read feeScratch))

/-- `convertScratch` holds **net** shares desired. Overwrite with **gross** mint
    so the explicit mint allocation can issue exactly that net amount
    (`gross = net * 10000 / (10000 - feeBps)`). Fee 0 → identity. -/
def applyGrossFromNetShares : EntryM Unit := do
  let net := ProofForge.Contract.Surface.read convertScratch
  let bps := ProofForge.Contract.Surface.read feeBps
  ProofForge.Contract.Surface.whenPositive bps do
    ProofForge.Contract.Surface.requireNe bps (ProofForge.Contract.Surface.u64 10000)
      "feeBps 10000 blocks mint"
    let denom :=
      ProofForge.Contract.Surface.sub (ProofForge.Contract.Surface.u64 10000) bps
    ProofForge.Contract.Surface.write convertScratch
      (ProofForge.Contract.Surface.div
        (ProofForge.Contract.Surface.mul net (ProofForge.Contract.Surface.u64 10000))
        denom)

/-- Read-only conversion helper for ERC-4626 query entrypoints. The mutable
    result is an IR local, so view calls never use the persistent scratch slot. -/
def localConvertToShares (name : String) (amount : ProofForge.IR.Expr) :
    EntryM ProofForge.IR.Expr := do
  ProofForge.Contract.Builder.letMutBind name .u64 amount
  let ts := ProofForge.Contract.Surface.read totalSupply
  ProofForge.Contract.Surface.whenPositive ts do
    let ta := ProofForge.Contract.Surface.read totalAssetsSlot
    ProofForge.Contract.Surface.requireNonZero ta "zero totalAssets"
    ProofForge.Contract.Builder.assign (.local name)
      (ProofForge.Contract.Surface.div
        (ProofForge.Contract.Surface.mul amount ts) ta)
  requireU64Result (.local name) "share conversion overflow"
  pure (.local name)

/-- Read-only inverse conversion; see `localConvertToShares`. -/
def localConvertToAssets (name : String) (amount : ProofForge.IR.Expr) :
    EntryM ProofForge.IR.Expr := do
  ProofForge.Contract.Builder.letMutBind name .u64 amount
  let ts := ProofForge.Contract.Surface.read totalSupply
  ProofForge.Contract.Surface.whenPositive ts do
    let ta := ProofForge.Contract.Surface.read totalAssetsSlot
    ProofForge.Contract.Surface.requireNonZero ta "zero totalAssets"
    ProofForge.Contract.Builder.assign (.local name)
      (ProofForge.Contract.Surface.div
        (ProofForge.Contract.Surface.mul amount ta) ts)
  requireU64Result (.local name) "asset conversion overflow"
  pure (.local name)

/-- Read-only inverse share conversion with ceiling division. -/
def localConvertToSharesUp (name : String) (amount : ProofForge.IR.Expr) :
    EntryM ProofForge.IR.Expr := do
  ProofForge.Contract.Builder.letMutBind name .u64 amount
  let ts := ProofForge.Contract.Surface.read totalSupply
  ProofForge.Contract.Surface.whenPositive ts do
    let ta := ProofForge.Contract.Surface.read totalAssetsSlot
    ProofForge.Contract.Surface.requireNonZero ta "zero totalAssets"
    let numeratorName := name ++ "_numerator"
    ProofForge.Contract.Builder.letBind numeratorName .u64
      (ProofForge.Contract.Surface.mul amount ts)
    let numerator := ProofForge.Contract.Builder.localVar numeratorName
    let quotientName := name ++ "_quotient"
    ProofForge.Contract.Builder.letBind quotientName .u64
      (ProofForge.Contract.Surface.div numerator ta)
    let quotient := ProofForge.Contract.Builder.localVar quotientName
    requireU64Result quotient "withdraw share quote overflow"
    ProofForge.Contract.Builder.assign (.local name)
      quotient
    ProofForge.Contract.Surface.whenPositive (ProofForge.Contract.Builder.mod numerator ta) do
      ProofForge.Contract.Surface.requireNe quotient
        (ProofForge.Contract.Surface.u64 0xffffffffffffffff)
        "withdraw share quote overflow"
      ProofForge.Contract.Builder.assign (.local name)
        (ProofForge.Contract.Surface.add quotient (ProofForge.Contract.Surface.u64 1))
  pure (.local name)

/-- Read-only inverse asset conversion with ceiling division. -/
def localConvertToAssetsUp (name : String) (amount : ProofForge.IR.Expr) :
    EntryM ProofForge.IR.Expr := do
  ProofForge.Contract.Builder.letMutBind name .u64 amount
  let ts := ProofForge.Contract.Surface.read totalSupply
  ProofForge.Contract.Surface.whenPositive ts do
    let ta := ProofForge.Contract.Surface.read totalAssetsSlot
    ProofForge.Contract.Surface.requireNonZero ta "zero totalAssets"
    let numeratorName := name ++ "_numerator"
    ProofForge.Contract.Builder.letBind numeratorName .u64
      (ProofForge.Contract.Surface.mul amount ta)
    let numerator := ProofForge.Contract.Builder.localVar numeratorName
    let quotientName := name ++ "_quotient"
    ProofForge.Contract.Builder.letBind quotientName .u64
      (ProofForge.Contract.Surface.div numerator ts)
    let quotient := ProofForge.Contract.Builder.localVar quotientName
    requireU64Result quotient "mint asset quote overflow"
    ProofForge.Contract.Builder.assign (.local name)
      quotient
    ProofForge.Contract.Surface.whenPositive (ProofForge.Contract.Builder.mod numerator ts) do
      ProofForge.Contract.Surface.requireNe quotient
        (ProofForge.Contract.Surface.u64 0xffffffffffffffff)
        "mint asset quote overflow"
      ProofForge.Contract.Builder.assign (.local name)
        (ProofForge.Contract.Surface.add quotient (ProofForge.Contract.Surface.u64 1))
  pure (.local name)

/-- Read-only gross-share calculation for `previewMint`. -/
def localGrossFromNetShares (name : String) (net : ProofForge.IR.Expr) :
    EntryM ProofForge.IR.Expr := do
  ProofForge.Contract.Builder.letMutBind name .u64 net
  let bps := ProofForge.Contract.Surface.read feeBps
  ProofForge.Contract.Surface.whenPositive bps do
    ProofForge.Contract.Surface.requireNe bps (ProofForge.Contract.Surface.u64 10000)
      "feeBps 10000 blocks mint"
    let denom :=
      ProofForge.Contract.Surface.sub (ProofForge.Contract.Surface.u64 10000) bps
    ProofForge.Contract.Builder.assign (.local name)
      (ProofForge.Contract.Surface.div
        (ProofForge.Contract.Surface.mul net (ProofForge.Contract.Surface.u64 10000))
        denom)
  requireU64Result (.local name) "mint gross share quote overflow"
  pure (.local name)

/-- Read-only fee calculation. The explicit zero-fee branch avoids invoking a
    checked multiplication with a zero RHS and preserves the identity quote. -/
def localNetAfterFee (name : String) (gross : ProofForge.IR.Expr) :
    EntryM ProofForge.IR.Expr := do
  ProofForge.Contract.Builder.letMutBind name .u64 gross
  let bps := ProofForge.Contract.Surface.read feeBps
  ProofForge.Contract.Surface.whenPositive bps do
    ProofForge.Contract.Builder.assign (.local name)
      (ProofForge.Contract.Surface.sub gross
        (ProofForge.Contract.Surface.div
          (ProofForge.Contract.Surface.mul gross bps)
          (ProofForge.Contract.Surface.u64 10000)))
  requireU64Result (.local name) "fee-adjusted result overflow"
  pure (.local name)

def whenCondition (condition : ProofForge.IR.Expr) (body : EntryM Unit) : EntryM Unit := do
  let (_, entryBuilder) := body.run {}
  ProofForge.Contract.Builder.ifElse condition entryBuilder.body #[]

def capLocalU64 (name : String) (cap : ProofForge.IR.Expr) : EntryM Unit :=
  ProofForge.Contract.Builder.ifElse
    (ProofForge.Contract.Builder.lt cap (.local name))
    #[.assign (.local name) cap]
    #[]

/-- Cap one factor so a checked U64 multiplication by `multiplicand` cannot
    overflow. A zero factor needs no cap and avoids division by zero. -/
def capLocalForCheckedMul (name : String) (multiplicand : ProofForge.IR.Expr) : EntryM Unit :=
  ProofForge.Contract.Surface.whenPositive multiplicand do
    capLocalU64 name
      (ProofForge.Contract.Surface.div
        (ProofForge.Contract.Surface.u64 0xffffffffffffffff)
        multiplicand)

def assignLocalU64 (name : String) (value : ProofForge.IR.Expr) : EntryM Unit :=
  ProofForge.Contract.Builder.assign (.local name) value

def feeLimitsUsable : ProofForge.IR.Expr :=
  let bps := ProofForge.Contract.Surface.read feeBps
  let recipient := ProofForge.Contract.Surface.read feeRecipient
  ProofForge.Contract.Builder.boolAnd
    (ProofForge.Contract.Builder.lt bps (ProofForge.Contract.Surface.u64 10000))
    (ProofForge.Contract.Builder.boolOr
      (ProofForge.Contract.Builder.eq bps (ProofForge.Contract.Surface.u64 0))
      (ProofForge.Contract.Builder.ne recipient
        (ProofForge.Contract.Surface.cast (ProofForge.Contract.Surface.u64 0) .address)))

/-- Conservative executable deposit limit under u64 state/map capacities. -/
def localMaxDeposit (name : String) (receiver : ProofForge.IR.Expr) :
    EntryM ProofForge.IR.Expr := do
  let max := ProofForge.Contract.Surface.u64 0xffffffffffffffff
  let zero := ProofForge.Contract.Surface.u64 0
  ProofForge.Contract.Builder.letMutBind name .u64 zero
  whenCondition (ProofForge.Contract.Builder.ne receiver (ProofForge.Contract.Surface.u64 0)) do
    whenCondition feeLimitsUsable do
      let ta := ProofForge.Contract.Surface.read totalAssetsSlot
      let ts := ProofForge.Contract.Surface.read totalSupply
      let assetCapName := name ++ "_asset_cap"
      ProofForge.Contract.Builder.letMutBind assetCapName .u64
        (ProofForge.Contract.Surface.sub max ta)
      capLocalForCheckedMul assetCapName ts
      let assetCap := ProofForge.Contract.Builder.localVar assetCapName
      ProofForge.Contract.Builder.letMutBind (name ++ "_gross_cap") .u64
        (ProofForge.Contract.Surface.sub max ts)
      let grossCapName := name ++ "_gross_cap"
      capLocalU64 grossCapName
        (ProofForge.Contract.Surface.sub max
          (ProofForge.Contract.Surface.mapGet shareBalances receiver))
      let bps := ProofForge.Contract.Surface.read feeBps
      ProofForge.Contract.Surface.whenPositive bps do
        capLocalU64 grossCapName
          (ProofForge.Contract.Surface.sub max
            (ProofForge.Contract.Surface.mapGet shareBalances
              (addressWord (ProofForge.Contract.Surface.read feeRecipient))))
        capLocalForCheckedMul grossCapName bps
      assignLocalU64 name assetCap
      let grossCap := ProofForge.Contract.Builder.localVar grossCapName
      ProofForge.Contract.Surface.whenZero ts do
        capLocalU64 name grossCap
      ProofForge.Contract.Surface.whenPositive ts do
        ProofForge.Contract.Surface.whenZero ta do
          assignLocalU64 name zero
        ProofForge.Contract.Surface.whenPositive ta do
          ProofForge.Contract.Builder.letBind (name ++ "_gross_at_asset_cap") .u64
            (ProofForge.Contract.Surface.div
              (ProofForge.Contract.Surface.mul assetCap ts) ta)
          let grossAtAssetCap :=
            ProofForge.Contract.Builder.localVar (name ++ "_gross_at_asset_cap")
          whenCondition (ProofForge.Contract.Builder.gt grossAtAssetCap grossCap) do
            let reverseGrossName := name ++ "_reverse_gross_cap"
            ProofForge.Contract.Builder.letMutBind reverseGrossName .u64 grossCap
            capLocalForCheckedMul reverseGrossName ta
            assignLocalU64 name
              (ProofForge.Contract.Surface.div
                (ProofForge.Contract.Surface.mul
                  (ProofForge.Contract.Builder.localVar reverseGrossName) ta) ts)
          ProofForge.Contract.Builder.letBind (name ++ "_gross_final") .u64
            (ProofForge.Contract.Surface.div
              (ProofForge.Contract.Surface.mul (.local name) ts) ta)
          ProofForge.Contract.Surface.whenZero (.local (name ++ "_gross_final")) do
            assignLocalU64 name zero
  pure (.local name)

/-- Conservative executable net-share mint limit under u64 capacities. -/
def localMaxMint (name : String) (receiver : ProofForge.IR.Expr) :
    EntryM ProofForge.IR.Expr := do
  let max := ProofForge.Contract.Surface.u64 0xffffffffffffffff
  let zero := ProofForge.Contract.Surface.u64 0
  ProofForge.Contract.Builder.letMutBind name .u64 zero
  whenCondition (ProofForge.Contract.Builder.ne receiver (ProofForge.Contract.Surface.u64 0)) do
    whenCondition feeLimitsUsable do
      let ta := ProofForge.Contract.Surface.read totalAssetsSlot
      let ts := ProofForge.Contract.Surface.read totalSupply
      ProofForge.Contract.Builder.letMutBind (name ++ "_gross_cap") .u64
        (ProofForge.Contract.Surface.sub max ts)
      let grossCapName := name ++ "_gross_cap"
      let bps := ProofForge.Contract.Surface.read feeBps
      ProofForge.Contract.Surface.whenPositive bps do
        capLocalU64 grossCapName
          (ProofForge.Contract.Surface.sub max
            (ProofForge.Contract.Surface.mapGet shareBalances
              (addressWord (ProofForge.Contract.Surface.read feeRecipient))))
      let assetCapName := name ++ "_asset_cap"
      ProofForge.Contract.Builder.letMutBind assetCapName .u64
        (ProofForge.Contract.Surface.sub max ta)
      ProofForge.Contract.Surface.whenZero ts do
        capLocalU64 grossCapName (.local assetCapName)
      ProofForge.Contract.Surface.whenPositive ts do
        ProofForge.Contract.Surface.whenZero ta do
          assignLocalU64 grossCapName zero
        ProofForge.Contract.Surface.whenPositive ta do
          capLocalForCheckedMul assetCapName ts
          ProofForge.Contract.Builder.letBind (name ++ "_gross_from_asset_cap") .u64
            (ProofForge.Contract.Surface.div
              (ProofForge.Contract.Surface.mul (.local assetCapName) ts) ta)
          capLocalU64 grossCapName (.local (name ++ "_gross_from_asset_cap"))
      ProofForge.Contract.Surface.whenZero bps do
        assignLocalU64 name (.local grossCapName)
      ProofForge.Contract.Surface.whenPositive bps do
        capLocalForCheckedMul grossCapName bps
        localNetAfterFee (name ++ "_net_cap") (.local grossCapName) >>= fun netCap => do
          assignLocalU64 name netCap
          capLocalForCheckedMul name (ProofForge.Contract.Surface.u64 10000)
          localGrossFromNetShares (name ++ "_gross_needed") (.local name) >>= fun grossNeeded => do
            whenCondition (ProofForge.Contract.Builder.gt grossNeeded (.local grossCapName)) do
              assignLocalU64 name zero
      capLocalU64 name
        (ProofForge.Contract.Surface.sub max
          (ProofForge.Contract.Surface.mapGet shareBalances receiver))
  pure (.local name)

def localMaxExit (name : String) (holder : ProofForge.IR.Expr) (redeem : Bool) :
    EntryM ProofForge.IR.Expr := do
  let max := ProofForge.Contract.Surface.u64 0xffffffffffffffff
  let zero := ProofForge.Contract.Surface.u64 0
  ProofForge.Contract.Builder.letMutBind name .u64 zero
  whenCondition feeLimitsUsable do
    let sharesName := name ++ "_shares"
    ProofForge.Contract.Builder.letMutBind sharesName .u64
      (ProofForge.Contract.Surface.mapGet shareBalances holder)
    capLocalU64 sharesName (ProofForge.Contract.Surface.read totalSupply)
    let ts := ProofForge.Contract.Surface.read totalSupply
    let ta := ProofForge.Contract.Surface.read totalAssetsSlot
    ProofForge.Contract.Surface.whenPositive ts do
      ProofForge.Contract.Surface.whenPositive ta do
        capLocalForCheckedMul sharesName ta
        let grossName := name ++ "_gross_assets"
        ProofForge.Contract.Builder.letMutBind grossName .u64
          (ProofForge.Contract.Surface.div
            (ProofForge.Contract.Surface.mul (.local sharesName) ta) ts)
        let bps := ProofForge.Contract.Surface.read feeBps
        if redeem then
          ProofForge.Contract.Surface.whenPositive bps do
            let grossFeeCapName := name ++ "_gross_fee_cap"
            ProofForge.Contract.Builder.letMutBind grossFeeCapName .u64
              (ProofForge.Contract.Surface.div max bps)
            whenCondition
                (ProofForge.Contract.Builder.gt (.local grossName) (.local grossFeeCapName)) do
              capLocalForCheckedMul grossFeeCapName ts
              assignLocalU64 sharesName
                (ProofForge.Contract.Surface.div
                  (ProofForge.Contract.Surface.mul (.local grossFeeCapName) ts) ta)
              assignLocalU64 grossName
                (ProofForge.Contract.Surface.div
                  (ProofForge.Contract.Surface.mul (.local sharesName) ta) ts)
        else
          capLocalForCheckedMul grossName ts
          ProofForge.Contract.Surface.whenPositive bps do
            capLocalForCheckedMul grossName bps
        localNetAfterFee (name ++ "_net_assets") (.local grossName) >>= fun netAssets =>
          ProofForge.Contract.Surface.whenPositive netAssets do
            if redeem then assignLocalU64 name (.local sharesName)
            else assignLocalU64 name (.local grossName)
  pure (.local name)

/-- Mint fee shares to `feeRecipient` when fee > 0. -/
def mintFeeSharesIfAny : EntryM Unit := do
  let fee := ProofForge.Contract.Surface.read feeScratch
  ProofForge.Contract.Surface.whenPositive fee do
    let recip := ProofForge.Contract.Surface.read feeRecipient
    ProofForge.Contract.Surface.requireNonZero (addressWord recip) "zero feeRecipient"
    let recipKey := addressWord recip
    let bal :=
      ProofForge.Contract.Surface.mapGet shareBalances recipKey
    ProofForge.Contract.Surface.mapSet shareBalances recipKey
      (ProofForge.Contract.Surface.add bal fee)
    ProofForge.Contract.Surface.emitIndexed (ProofForge.Contract.Surface.event "Transfer")
      #[
        ProofForge.Contract.Surface.field "from" (ProofForge.Contract.Surface.u64 0),
        ProofForge.Contract.Surface.field "to" (addressWord recip)
      ]
      #[ProofForge.Contract.Surface.field "value" fee]

/-- Snapshot `balanceOf(vaultSelf)` into `balanceScratch` (exit FOT measure start). -/
def beginVaultAssetMeasure : EntryM Unit := do
  let assetTok := addressWord (ProofForge.Contract.Surface.read assetAddress)
  let selfAddr := addressWord (ProofForge.Contract.Surface.read vaultSelf)
  let before :=
    ProofForge.Contract.Surface.remoteCall assetTok
      (ProofForge.Contract.Surface.u64 ierC20BalanceOfSelector) #[selfAddr]
  ProofForge.Contract.Surface.write balanceScratch before

/-- After pushes: `actualAssetsScratch = balanceScratch - balanceOf(vaultSelf)`. -/
def endVaultAssetMeasure : EntryM Unit := do
  let assetTok := addressWord (ProofForge.Contract.Surface.read assetAddress)
  let selfAddr := addressWord (ProofForge.Contract.Surface.read vaultSelf)
  let after :=
    ProofForge.Contract.Surface.remoteCall assetTok
      (ProofForge.Contract.Surface.u64 ierC20BalanceOfSelector) #[selfAddr]
  ProofForge.Contract.Builder.letBind "_pf_bal_after_push" .u64 after
  ProofForge.Contract.Surface.write actualAssetsScratch
    (ProofForge.Contract.Surface.sub
      (ProofForge.Contract.Surface.read balanceScratch)
      (ProofForge.Contract.Builder.localVar "_pf_bal_after_push"))
  ProofForge.Contract.Surface.requireNonZero
    (ProofForge.Contract.Surface.read actualAssetsScratch) "zero actual assets left vault"

/-- Push exit-fee assets to `feeRecipient` (IERC20 transfer; pair with measure). -/
def pushExitFeeAssetsIfAny : EntryM Unit := do
  let fee := ProofForge.Contract.Surface.read feeScratch
  ProofForge.Contract.Surface.whenPositive fee do
    let recip := ProofForge.Contract.Surface.read feeRecipient
    ProofForge.Contract.Surface.requireNonZero (addressWord recip) "zero feeRecipient"
    let assetTok := addressWord (ProofForge.Contract.Surface.read assetAddress)
    let sent :=
      ProofForge.Contract.Surface.remoteCall assetTok
        (ProofForge.Contract.Surface.u64 ierC20TransferSelector)
        #[addressWord recip, fee]
    requireRemoteTrue "_pf_exit_fee_push" sent

/-- Pull `amount` via transferFrom(caller, vaultSelf, amount), then set
    `actualAssetsScratch` to `balanceOf(vaultSelf)` up-delta (fee-on-transfer). -/
def pullAssetsMeasuring (amount : ProofForge.IR.Expr) : EntryM Unit := do
  let assetTok := addressWord (ProofForge.Contract.Surface.read assetAddress)
  let selfAddr := addressWord (ProofForge.Contract.Surface.read vaultSelf)
  let before :=
    ProofForge.Contract.Surface.remoteCall assetTok
      (ProofForge.Contract.Surface.u64 ierC20BalanceOfSelector) #[selfAddr]
  ProofForge.Contract.Surface.write balanceScratch before
  let pulled :=
    ProofForge.Contract.Surface.remoteCall assetTok
      (ProofForge.Contract.Surface.u64 ierC20TransferFromSelector)
      #[ProofForge.Contract.Surface.caller, selfAddr, amount]
  requireRemoteTrue "_pf_pull" pulled
  let after :=
    ProofForge.Contract.Surface.remoteCall assetTok
      (ProofForge.Contract.Surface.u64 ierC20BalanceOfSelector) #[selfAddr]
  ProofForge.Contract.Builder.letBind "_pf_bal_after" .u64 after
  ProofForge.Contract.Surface.write actualAssetsScratch
    (ProofForge.Contract.Surface.sub
      (ProofForge.Contract.Builder.localVar "_pf_bal_after")
      (ProofForge.Contract.Surface.read balanceScratch))
  ProofForge.Contract.Surface.requireNonZero
    (ProofForge.Contract.Surface.read actualAssetsScratch) "zero actual assets"

/-- Push `amount` to `recipient` via IERC20 transfer (pair with vault measure). -/
def pushAssets (recipient amount : ProofForge.IR.Expr) : EntryM Unit := do
  let assetTok := addressWord (ProofForge.Contract.Surface.read assetAddress)
  let sent :=
    ProofForge.Contract.Surface.remoteCall assetTok
      (ProofForge.Contract.Surface.u64 ierC20TransferSelector) #[recipient, amount]
  requireRemoteTrue "_pf_push" sent

/-- Push to receiver and set `recvActualScratch` = recipient balance **up-delta**
    (recipient-side fee-on-transfer honesty). -/
def pushAssetsMeasuringRecv (recipient amount : ProofForge.IR.Expr) : EntryM Unit := do
  let assetTok := addressWord (ProofForge.Contract.Surface.read assetAddress)
  let before :=
    ProofForge.Contract.Surface.remoteCall assetTok
      (ProofForge.Contract.Surface.u64 ierC20BalanceOfSelector) #[recipient]
  ProofForge.Contract.Surface.write recvBalScratch before
  let sent :=
    ProofForge.Contract.Surface.remoteCall assetTok
      (ProofForge.Contract.Surface.u64 ierC20TransferSelector) #[recipient, amount]
  requireRemoteTrue "_pf_push_recv" sent
  let after :=
    ProofForge.Contract.Surface.remoteCall assetTok
      (ProofForge.Contract.Surface.u64 ierC20BalanceOfSelector) #[recipient]
  ProofForge.Contract.Builder.letBind "_pf_recv_after" .u64 after
  ProofForge.Contract.Surface.write recvActualScratch
    (ProofForge.Contract.Surface.sub
      (ProofForge.Contract.Builder.localVar "_pf_recv_after")
      (ProofForge.Contract.Surface.read recvBalScratch))

contract_mixin ERC4626Mixin do
  use ProofForge.Contract.Surface.scalar assetAddress
  use ProofForge.Contract.Surface.scalar vaultSelf
  use ProofForge.Contract.Surface.scalar totalAssetsSlot
  use ProofForge.Contract.Surface.scalar totalSupply
  use ProofForge.Contract.Surface.scalar convertScratch
  use ProofForge.Contract.Surface.scalar feeScratch
  use ProofForge.Contract.Surface.scalar balanceScratch
  use ProofForge.Contract.Surface.scalar actualAssetsScratch
  use ProofForge.Contract.Surface.scalar recvBalScratch
  use ProofForge.Contract.Surface.scalar recvActualScratch
  use ProofForge.Contract.Surface.scalar feeBps
  use ProofForge.Contract.Surface.scalar feeRecipient
  use ProofForge.Contract.Surface.scalar erc4626Lock
  use ProofForge.Contract.Surface.scalar initialized
  use ProofForge.Contract.Surface.mapState shareBalances
  use ProofForge.Contract.Surface.mapState shareAllowances

  event Deposit abi #[
    ("sender", "address"), ("owner", "address"),
    ("assets", "uint256"), ("shares", "uint256")
  ]
  event Withdraw abi #[
    ("sender", "address"), ("receiver", "address"), ("owner", "address"),
    ("assets", "uint256"), ("shares", "uint256")
  ]
  event Transfer abi #[
    ("from", "address"), ("to", "address"), ("value", "uint256")
  ]
  event Approval abi #[
    ("owner", "address"), ("spender", "address"), ("value", "uint256")
  ]

  query «asset» returns(.address) do
    return assetAddress;

  query totalAssets returns(.u64) do
    return totalAssetsSlot;

  query totalSupply returns(.u64) do
    return totalSupply;

  query balanceOf (who : .address) returns(.u64) do
    return mapRead shareBalances who;

  -- pro-rata: empty supply → identity; else assets * supply / totalAssets (floor)
  query convertToShares (assets : .u64) returns(.u64) do
    do localConvertToShares "_pf_convert_shares" (ProofForge.Contract.Surface.ref assets) >>=
      ProofForge.Contract.Builder.ret;

  query convertToAssets (shares : .u64) returns(.u64) do
    do localConvertToAssets "_pf_convert_assets" (ProofForge.Contract.Surface.ref shares) >>=
      ProofForge.Contract.Builder.ret;

  query maxDeposit (who : .address) returns(.u64) do
    do localMaxDeposit "_pf_max_deposit" (ProofForge.Contract.Surface.ref who) >>=
      ProofForge.Contract.Builder.ret;

  query maxMint (who : .address) returns(.u64) do
    do localMaxMint "_pf_max_mint" (ProofForge.Contract.Surface.ref who) >>=
      ProofForge.Contract.Builder.ret;

  query maxWithdraw (holder : .address) returns(.u64) do
    do localMaxExit "_pf_max_withdraw" (ProofForge.Contract.Surface.ref holder) false >>=
      ProofForge.Contract.Builder.ret;

  query maxRedeem (holder : .address) returns(.u64) do
    do localMaxExit "_pf_max_redeem" (ProofForge.Contract.Surface.ref holder) true >>=
      ProofForge.Contract.Builder.ret;

  query feeBps returns(.u64) do
    return feeBps;

  query feeRecipient returns(.address) do
    return feeRecipient;

  -- preview: net after entry fee (deposit/mint) or exit fee (withdraw/redeem)
  query previewDeposit (assets : .u64) returns(.u64) do
    do localConvertToShares "_pf_preview_deposit" (ProofForge.Contract.Surface.ref assets) >>=
      fun gross => localNetAfterFee "_pf_preview_deposit_net" gross >>=
        ProofForge.Contract.Builder.ret;

  query previewMint (shares : .u64) returns(.u64) do
    -- assets required so user receives **net** `shares` after entry fee
    do localGrossFromNetShares "_pf_preview_mint_gross"
      (ProofForge.Contract.Surface.ref shares) >>= fun gross =>
      localConvertToAssetsUp "_pf_preview_mint_assets" gross >>=
      ProofForge.Contract.Builder.ret;

  query previewWithdraw (assets : .u64) returns(.u64) do
    -- shares burned to withdraw `assets` from vault (user gets net after exit fee)
    do localConvertToSharesUp "_pf_preview_withdraw" (ProofForge.Contract.Surface.ref assets) >>=
      ProofForge.Contract.Builder.ret;

  query previewRedeem (shares : .u64) returns(.u64) do
    -- net assets user receives after exit fee
    do localConvertToAssets "_pf_preview_redeem" (ProofForge.Contract.Surface.ref shares) >>=
      fun gross => localNetAfterFee "_pf_preview_redeem_net" gross >>=
        ProofForge.Contract.Builder.ret;

  entry deposit (assets : .u64, receiver : .address) returns(.u64) do
    acquire_lock erc4626Lock;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref receiver)
      "zero receiver";
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref assets)
      "zero assets";
    -- Pull first; account **actual** balance delta (fee-on-transfer safe)
    do pullAssetsMeasuring (ProofForge.Contract.Surface.ref assets);
    let actual : .u64 := actualAssetsScratch;
    convertScratch := actual;
    do applyConvertToShares (ProofForge.Contract.Surface.ref actual);
    let gross : .u64 := convertScratch;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref gross)
      "zero shares";
    do applyEntryFee;
    let shares : .u64 := convertScratch;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref shares)
      "zero net shares";
    let ta : .u64 := totalAssetsSlot;
    totalAssetsSlot := ta +! actual;
    let ts : .u64 := totalSupply;
    totalSupply := ts +! gross;
    let bal : .u64 := mapRead shareBalances receiver;
    do mapWrite shareBalances receiver (bal +! shares);
    do mintFeeSharesIfAny;
    emit Deposit indexed #[
      fieldAsName "sender" caller,
      fieldAsName "owner" receiver
    ] data #[
      fieldAsName "assets" actual,
      fieldAsName "shares" shares
    ];
    emit Transfer indexed #[
      fieldAsName "from" (u64 0),
      fieldAsName "to" receiver
    ] data #[
      fieldAsName "value" shares
    ];
    release_lock erc4626Lock;
    return shares;

  entry mint (shares : .u64, receiver : .address) returns(.u64) do
    acquire_lock erc4626Lock;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref receiver)
      "zero receiver";
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref shares)
      "zero shares";
    -- Pull the previewed amount, then use the actual delta only as a coverage
    -- check. Mint always issues exactly the requested net/gross share amounts.
    convertScratch := shares;
    do applyGrossFromNetShares;
    let grossWanted : .u64 := convertScratch;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref grossWanted)
      "zero gross shares";
    convertScratch := grossWanted;
    do applyConvertToAssetsUp (ProofForge.Contract.Surface.ref grossWanted);
    let assetsWanted : .u64 := convertScratch;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref assetsWanted)
      "zero assets";
    do pullAssetsMeasuring (ProofForge.Contract.Surface.ref assetsWanted);
    let actual : .u64 := actualAssetsScratch;
    convertScratch := actual;
    do applyConvertToShares (ProofForge.Contract.Surface.ref actual);
    let grossAvailable : .u64 := convertScratch;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref grossAvailable)
      (ProofForge.Contract.Surface.ref grossWanted) "insufficient actual assets";
    feeScratch := grossWanted -! shares;
    let userShares : .u64 := shares;
    let ta : .u64 := totalAssetsSlot;
    totalAssetsSlot := ta +! actual;
    let ts : .u64 := totalSupply;
    totalSupply := ts +! grossWanted;
    let bal : .u64 := mapRead shareBalances receiver;
    do mapWrite shareBalances receiver (bal +! userShares);
    do mintFeeSharesIfAny;
    emit Deposit indexed #[
      fieldAsName "sender" caller,
      fieldAsName "owner" receiver
    ] data #[
      fieldAsName "assets" actual,
      fieldAsName "shares" userShares
    ];
    emit Transfer indexed #[
      fieldAsName "from" (u64 0),
      fieldAsName "to" receiver
    ] data #[
      fieldAsName "value" userShares
    ];
    release_lock erc4626Lock;
    return actual;

  entry withdraw (assets : .u64, receiver : .address, holder : .address) returns(.u64) do
    acquire_lock erc4626Lock;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref receiver)
      "zero receiver";
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref assets)
      "zero assets";
    do ProofForge.Contract.Surface.requireEq caller (ProofForge.Contract.Surface.ref holder)
      "not holder";
    -- Plan shares / net user assets from requested `assets` (exit fee skim)
    convertScratch := assets;
    do applyConvertToSharesUp (ProofForge.Contract.Surface.ref assets);
    let shares : .u64 := convertScratch;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref shares)
      "zero shares";
    convertScratch := assets;
    do applyExitFee;
    let userAssets : .u64 := convertScratch;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref userAssets)
      "zero net assets";
    let ownerBal : .u64 := mapRead shareBalances holder;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref ownerBal)
      (ProofForge.Contract.Surface.ref shares) "insufficient shares";
    do mapWrite shareBalances holder (ownerBal -! shares);
    let ts : .u64 := totalSupply;
    totalSupply := ts -! shares;
    -- Vault measure for totalAssets; recipient measure for event/return honesty
    do beginVaultAssetMeasure;
    do pushAssetsMeasuringRecv (ProofForge.Contract.Surface.ref receiver)
      (ProofForge.Contract.Surface.ref userAssets);
    do pushExitFeeAssetsIfAny;
    do endVaultAssetMeasure;
    let actualLeft : .u64 := actualAssetsScratch;
    let actualRecv : .u64 := recvActualScratch;
    do ProofForge.Contract.Surface.requireGe
      (ProofForge.Contract.Surface.read totalAssetsSlot)
      (ProofForge.Contract.Surface.ref actualLeft) "actual left > totalAssets";
    let ta : .u64 := totalAssetsSlot;
    totalAssetsSlot := ta -! actualLeft;
    emit Withdraw indexed #[
      fieldAsName "sender" caller,
      fieldAsName "receiver" receiver,
      fieldAsName "owner" holder
    ] data #[
      fieldAsName "assets" actualRecv,
      fieldAsName "shares" shares
    ];
    emit Transfer indexed #[
      fieldAsName "from" holder,
      fieldAsName "to" (u64 0)
    ] data #[
      fieldAsName "value" shares
    ];
    release_lock erc4626Lock;
    return shares;

  entry redeem (shares : .u64, receiver : .address, holder : .address) returns(.u64) do
    acquire_lock erc4626Lock;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref receiver)
      "zero receiver";
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref shares)
      "zero shares";
    do ProofForge.Contract.Surface.requireEq caller (ProofForge.Contract.Surface.ref holder)
      "not holder";
    convertScratch := shares;
    do applyConvertToAssets (ProofForge.Contract.Surface.ref shares);
    let grossAssets : .u64 := convertScratch;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref grossAssets)
      "zero assets";
    convertScratch := grossAssets;
    do applyExitFee;
    let userAssets : .u64 := convertScratch;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref userAssets)
      "zero net assets";
    let ownerBal : .u64 := mapRead shareBalances holder;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref ownerBal)
      (ProofForge.Contract.Surface.ref shares) "insufficient shares";
    do mapWrite shareBalances holder (ownerBal -! shares);
    let ts : .u64 := totalSupply;
    totalSupply := ts -! shares;
    do beginVaultAssetMeasure;
    do pushAssetsMeasuringRecv (ProofForge.Contract.Surface.ref receiver)
      (ProofForge.Contract.Surface.ref userAssets);
    do pushExitFeeAssetsIfAny;
    do endVaultAssetMeasure;
    let actualLeft : .u64 := actualAssetsScratch;
    let actualRecv : .u64 := recvActualScratch;
    do ProofForge.Contract.Surface.requireGe
      (ProofForge.Contract.Surface.read totalAssetsSlot)
      (ProofForge.Contract.Surface.ref actualLeft) "actual left > totalAssets";
    let ta : .u64 := totalAssetsSlot;
    totalAssetsSlot := ta -! actualLeft;
    emit Withdraw indexed #[
      fieldAsName "sender" caller,
      fieldAsName "receiver" receiver,
      fieldAsName "owner" holder
    ] data #[
      fieldAsName "assets" actualRecv,
      fieldAsName "shares" shares
    ];
    release_lock erc4626Lock;
    return actualRecv;

  entry transfer (recipient : .address, amount : .u64) returns(.bool) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref recipient)
      "zero recipient";
    let sender : .address := caller;
    let srcBal : .u64 := mapRead shareBalances sender;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref srcBal)
      (ProofForge.Contract.Surface.ref amount) "insufficient balance";
    do mapWrite shareBalances sender (srcBal -! amount);
    let dstBal : .u64 := mapRead shareBalances recipient;
    do mapWrite shareBalances recipient (dstBal +! amount);
    emit Transfer indexed #[
      fieldAsName "from" sender,
      fieldAsName "to" recipient
    ] data #[
      fieldAsName "value" amount
    ];
    return boolLit true;

  entry approve (spender : .address, amount : .u64) returns(.bool) do
    let holder : .address := caller;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref spender)
      "zero spender";
    do pathWriteAllowance shareAllowances (ProofForge.Contract.Surface.ref holder)
      (ProofForge.Contract.Surface.ref spender) amount;
    emit Approval indexed #[
      fieldAsName "owner" holder,
      fieldAsName "spender" spender
    ] data #[
      fieldAsName "value" amount
    ];
    return boolLit true;

contract_source ERC4626 do
  use mixin
  -- feeBpsVal ∈ [0, 10000]; feeRecipientAddr used only when fee shares > 0
  entry init (assetAddr : .address, selfAddr : .address,
      feeBpsVal : .u64, feeRecipientAddr : .address) do
    do ProofForge.Contract.Surface.requireEq
      (ProofForge.Contract.Surface.read initialized) (u64 0) "already initialized";
    initialized := u64 1;
    do ProofForge.Contract.Surface.requireNonZero
      (ProofForge.Contract.Surface.ref assetAddr) "zero asset";
    do ProofForge.Contract.Surface.requireEq
      (ProofForge.Contract.Surface.cast (ProofForge.Contract.Surface.ref selfAddr) .address)
      (ProofForge.Contract.Surface.cast ProofForge.Contract.Surface.contractId .address)
      "vaultSelf != contractId";
    do ProofForge.Contract.Surface.requireGe (u64 10000)
      (ProofForge.Contract.Surface.ref feeBpsVal) "feeBps > 10000";
    do requireFeeRecipientWhenEnabled
      (ProofForge.Contract.Surface.ref feeBpsVal)
      (ProofForge.Contract.Surface.ref feeRecipientAddr);
    assetAddress := ProofForge.Contract.Surface.cast
      (ProofForge.Contract.Surface.ref assetAddr) .address;
    vaultSelf := ProofForge.Contract.Surface.cast
      (ProofForge.Contract.Surface.ref selfAddr) .address;
    feeBps := feeBpsVal;
    feeRecipient := ProofForge.Contract.Surface.cast
      (ProofForge.Contract.Surface.ref feeRecipientAddr) .address;
    totalAssetsSlot := u64 0;
    totalSupply := u64 0;
    feeScratch := u64 0;

end ProofForge.Contract.Stdlib.ERC4626
