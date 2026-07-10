/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Pro-rata share vault (NEAR / multi-target honesty subset)

ERC-4626-**inspired** internal vault body for dual-deploy compare:

- Pro-rata convert (empty vault = 1:1) via `whenPositive` convertScratch
- Share balances + totalAssets / totalSupply
- `deposit` / `withdraw` / `donate` take **amount parameters** (no IERC20 pulls)

Not full `Stdlib.ERC4626` (EVM-primary external asset token). NEAR compare:

  `just near-compare-pro-rata-vault` / `-live`
-/
import ProofForge.Contract.Source

namespace Examples.Product.ProRataVault

open ProofForge.Contract.Source

def totalAssetsSlot : ScalarRef :=
  ProofForge.Contract.Surface.slot "totalAssets" .u64

def totalSupplySlot : ScalarRef :=
  ProofForge.Contract.Surface.slot "totalSupply" .u64

def convertScratch : ScalarRef :=
  ProofForge.Contract.Surface.slot "convertScratch" .u64

def shareBalances : MapRef :=
  { id := "shareBalances", keyType := .u64, valueType := .u64 }

/-- Seed `convertScratch` with 1:1 fallback; when supply > 0 overwrite with
    `amount * totalSupply / totalAssets`. -/
def applyConvertToShares (amount : ProofForge.IR.Expr) : EntryM Unit := do
  ProofForge.Contract.Surface.write convertScratch amount
  let ts := ProofForge.Contract.Surface.read totalSupplySlot
  ProofForge.Contract.Surface.whenPositive ts do
    let ta := ProofForge.Contract.Surface.read totalAssetsSlot
    ProofForge.Contract.Surface.requireNonZero ta "zero totalAssets"
    ProofForge.Contract.Surface.write convertScratch
      (ProofForge.Contract.Surface.div
        (ProofForge.Contract.Surface.mul amount ts) ta)

def applyConvertToAssets (amount : ProofForge.IR.Expr) : EntryM Unit := do
  ProofForge.Contract.Surface.write convertScratch amount
  let ts := ProofForge.Contract.Surface.read totalSupplySlot
  ProofForge.Contract.Surface.whenPositive ts do
    let ta := ProofForge.Contract.Surface.read totalAssetsSlot
    ProofForge.Contract.Surface.requireNonZero ta "zero totalAssets"
    ProofForge.Contract.Surface.write convertScratch
      (ProofForge.Contract.Surface.div
        (ProofForge.Contract.Surface.mul amount ta) ts)

contract_source ProRataVault do
  use ProofForge.Contract.Surface.scalar totalAssetsSlot
  use ProofForge.Contract.Surface.scalar totalSupplySlot
  use ProofForge.Contract.Surface.scalar convertScratch
  use ProofForge.Contract.Surface.mapState shareBalances

  event Deposit
  event Withdraw
  event Donate

  entry init do
    totalAssetsSlot := u64 0;
    totalSupplySlot := u64 0;
    convertScratch := u64 0;

  query total_assets returns(.u64) do
    return totalAssetsSlot;

  query total_supply returns(.u64) do
    return totalSupplySlot;

  query balance_of (who : .u64) returns(.u64) do
    return mapRead shareBalances who;

  -- Entries (not queries): convert uses convertScratch storage writes, which
  -- NEAR forbids in pure view context.
  entry convert_to_shares (assets : .u64) returns(.u64) do
    do applyConvertToShares (ProofForge.Contract.Surface.ref assets);
    return convertScratch;

  entry convert_to_assets (shares : .u64) returns(.u64) do
    do applyConvertToAssets (ProofForge.Contract.Surface.ref shares);
    return convertScratch;

  -- Increase assets without minting shares (donation / yield skew).
  entry donate (assets : .u64) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref assets)
      "zero assets";
    let ta : .u64 := totalAssetsSlot;
    totalAssetsSlot := ta +! assets;
    emit Donate indexed #[] data #[fieldAsName "assets" assets];

  entry deposit (assets : .u64) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref assets)
      "zero assets";
    do applyConvertToShares (ProofForge.Contract.Surface.ref assets);
    let shares : .u64 := convertScratch;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref shares)
      "zero shares";
    let who : .u64 := caller;
    let bal : .u64 := mapRead shareBalances who;
    do mapWrite shareBalances who (bal +! shares);
    let ta : .u64 := totalAssetsSlot;
    totalAssetsSlot := ta +! assets;
    let ts : .u64 := totalSupplySlot;
    totalSupplySlot := ts +! shares;
    emit Deposit indexed #[fieldAsName "caller" who]
      data #[fieldAsName "assets" assets, fieldAsName "shares" shares];

  entry withdraw (shares : .u64) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref shares)
      "zero shares";
    let who : .u64 := caller;
    let bal : .u64 := mapRead shareBalances who;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref bal)
      (ProofForge.Contract.Surface.ref shares) "insufficient shares";
    do applyConvertToAssets (ProofForge.Contract.Surface.ref shares);
    let assets : .u64 := convertScratch;
    do mapWrite shareBalances who (bal -! shares);
    let ts : .u64 := totalSupplySlot;
    totalSupplySlot := ts -! shares;
    let ta : .u64 := totalAssetsSlot;
    totalAssetsSlot := ta -! assets;
    emit Withdraw indexed #[fieldAsName "caller" who]
      data #[fieldAsName "assets" assets, fieldAsName "shares" shares];

end Examples.Product.ProRataVault
