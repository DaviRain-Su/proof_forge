/-
Layer C ERC-4626 stdlib: pro-rata Spec + module surface.
-/
import ProofForge.Contract.Stdlib.ERC4626
import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Backend.WasmHost.EmitWat

namespace ProofForge.Tests.ERC4626Stdlib

open ProofForge.Contract.Stdlib.ERC4626.Spec

def require (c : Bool) (m : String) : IO Unit :=
  if c then pure () else throw (IO.userError m)

def main : IO UInt32 := do
  -- Empty vault is 1:1
  let s0 := empty
  require (s0.totalAssets == 0 && s0.totalSupply == 0) "empty zero"
  require (convertToShares s0 50 == 50) "empty convert shares"
  require (convertToAssets s0 50 == 50) "empty convert assets"
  require (entryFeeShares 1000 0 == 0) "fee zero"
  require (entryFeeShares 1000 100 == 10) "fee 1%"
  require (netAfterEntryFee 1000 100 == 990) "net after entry 1%"
  require (netAfterExitFee 1000 100 == 990) "net after exit 1%"
  require (grossSharesForNet 990 100 == some 1000) "gross for net mint"
  require (grossSharesForNet 100 0 == some 100) "gross identity"
  let sRounding : State := { totalAssets := 2, totalSupply := 3 }
  require (convertToAssetsUp sRounding 1 == 1)
    "previewMint inverse conversion rounds assets up"
  require (convertToSharesUp sRounding 1 == 2)
    "previewWithdraw inverse conversion rounds shares up"
  require (convertToAssetsUp sRounding 0 == 0 && convertToSharesUp sRounding 0 == 0)
    "inverse conversion preserves zero"
  require (convertToAssetsUp { totalAssets := 6, totalSupply := 3 } 1 == 2)
    "inverse conversion does not over-round exact division"
  require (previewMintAssets? sRounding 1 0 == some 1)
    "previewMint applies ceil conversion after zero-fee grossing"
  require (previewMintAssets? sRounding 990 100 == some 667)
    "previewMint applies ceil conversion after entry-fee grossing"
  require (previewWithdrawShares sRounding 1 == 2)
    "previewWithdraw uses ceil share conversion"
  -- fee-on-transfer: Spec accounts **actual** received (99), not requested (100)
  match depositActual? empty 99 0 with
  | none => throw (IO.userError "fot actual deposit")
  | some (sFot, shFot) =>
      require (shFot == 99 && sFot.totalAssets == 99) "fot uses actual delta"
  match deposit? s0 100 0 with
  | none => throw (IO.userError "deposit should succeed")
  | some (s1, shares1) =>
      require (shares1 == 100) "first deposit 1:1 shares"
      require (s1.totalAssets == 100 && s1.totalSupply == 100) "deposit amounts"
      -- still 1:1 after first deposit
      require (convertToShares s1 40 == 40) "post-deposit convert"
      match withdraw? s1 40 0 with
      | none => throw (IO.userError "withdraw should succeed")
      | some (s2, burned) =>
          require (burned == 40) "withdraw burns 1:1 shares"
          require (s2.totalAssets == 60 && s2.totalSupply == 60) "withdraw remaining"
      match withdraw? s1 200 0 with
      | some _ => throw (IO.userError "over-withdraw must fail")
      | none => pure ()
      match withdraw? sRounding 1 0 with
      | none => throw (IO.userError "rounded withdraw should succeed")
      | some (sRounded, burned) =>
          require (burned == 2) "withdraw burns the rounded-up share quote"
          require (sRounded.totalAssets == 1 && sRounded.totalSupply == 1)
            "rounded withdraw updates totals with the actual burned shares"
      -- pro-rata after donation: assets grow without minting shares
      let sDonated := { totalAssets := s1.totalAssets + 100, totalSupply := s1.totalSupply }
      require (convertToShares sDonated 100 == 50)
        "donation: 100 assets → 50 shares (100*100/200)"
      require (convertToAssets sDonated 50 == 100)
        "donation: 50 shares → 100 assets"
      match deposit? sDonated 100 0 with
      | none => throw (IO.userError "pro-rata deposit should succeed")
      | some (s3, sh3) =>
          require (sh3 == 50) "pro-rata mint shares"
          require (s3.totalAssets == 300 && s3.totalSupply == 150) "pro-rata totals"
      -- entry fee: user gets 99%, totalSupply still gross
      match deposit? empty 1000 100 with
      | none => throw (IO.userError "fee deposit should succeed")
      | some (sFee, userSh) =>
          require (userSh == 990) "user net after 1% fee"
          require (sFee.totalSupply == 1000 && sFee.totalAssets == 1000) "gross supply"
          -- exit fee: redeem all supply-equivalent path via Spec
          match redeem? sFee 1000 100 none with
          | none => throw (IO.userError "redeem with exit fee should succeed")
          | some (sOut, userAssets) =>
              require (userAssets == 990) "user net assets after 1% exit fee"
              require (sOut.totalAssets == 0 && sOut.totalSupply == 0) "emptied"
          -- exit FOT: planned leave 1000 but vault only lost 995
          match redeemFot? { totalAssets := 1000, totalSupply := 1000 } 1000 995 0 with
          | none => throw (IO.userError "redeemFot should succeed")
          | some (sFot, _) =>
              require (sFot.totalAssets == 5) "exit FOT books actual left"
              require (sFot.totalSupply == 0) "shares burned"
      match deposit? s1 0 0 with
      | some _ => throw (IO.userError "zero deposit must fail")
      | none => pure ()

  let m := ProofForge.Contract.Stdlib.ERC4626.module
  require (m.name == "ERC4626") "module name"
  for stateId in #["asset", "vaultSelf", "feeRecipient"] do
    let some state := m.state.find? (fun candidate => candidate.id == stateId)
      | throw (IO.userError s!"missing address state {stateId}")
    require (state.kind == .scalar && state.type == .address)
      s!"{stateId} must preserve full-width addresses"
  for stateId in #["erc4626Lock", "initialized"] do
    require (m.state.any (fun state => state.id == stateId && state.kind == .scalar &&
        state.type == .u64)) s!"missing scalar guard state {stateId}"
  let some init := m.entrypoints.find? (fun entrypoint => entrypoint.name == "init")
    | throw (IO.userError "missing init")
  require (init.paramAbiWords == #[some "address", some "address", none, some "address"])
    "init must expose address ABI words"
  let some assetGetter := m.entrypoints.find? (fun entrypoint => entrypoint.name == "asset")
    | throw (IO.userError "missing asset getter")
  require (assetGetter.returns == .address) "asset getter returns address"
  let some feeRecipientGetter :=
      m.entrypoints.find? (fun entrypoint => entrypoint.name == "feeRecipient")
    | throw (IO.userError "missing feeRecipient getter")
  require (feeRecipientGetter.returns == .address) "feeRecipient getter returns address"
  let names := m.entrypoints.map (·.name)
  for n in #["deposit", "mint", "withdraw", "redeem", "convertToShares",
              "convertToAssets", "totalAssets", "asset", "balanceOf", "maxWithdraw",
              "previewDeposit", "previewMint", "previewWithdraw", "previewRedeem"] do
    require (names.any (· == n)) s!"entrypoint {n}"

  require (m.capabilities.any (· == .crosscallInvoke)) "asset pull uses crosscall"
  require (m.state.any (fun s => s.id == "convertScratch")) "pro-rata scratch slot"
  require (m.state.any (fun s => s.id == "actualAssets")) "fot actual assets slot"
  require (m.state.any (fun s => s.id == "balanceScratch")) "fot balance scratch"
  require (m.state.any (fun s => s.id == "recvActual")) "recipient FOT slot"
  require (m.state.any (fun s => s.id == "recvBalScratch")) "recipient bal scratch"
  require (recipientReceived 1000 100 == 990) "recipient FOT 1%"

  match ProofForge.Backend.Evm.Plan.buildModulePlan m with
  | .error e => throw (IO.userError s!"EVM plan: {e.message}")
  | .ok _ => pure ()
  match ProofForge.Backend.Solana.SbpfAsm.renderModule m with
  | .ok _ => throw (IO.userError "Solana should reject EVM-primary IERC20 selector remotes")
  | .error e =>
      require (e.message.contains "peer" || e.message.contains "remote" ||
          e.message.contains "PortableHonesty")
        s!"Solana honesty diagnostic, got: {e.message}"
  -- NEAR: IERC20 selector remotes need a string pool; honest reject without it.
  match ProofForge.Backend.WasmHost.EmitWat.renderModule m with
  | .ok _ => throw (IO.userError "NEAR should reject empty nearCrosscallStrings for asset pull")
  | .error e =>
      require (e.message.contains "nearCrosscallStrings" || e.message.contains "crosscall" ||
          e.message.contains "Address")
        s!"NEAR honesty diagnostic, got: {e.message}"

  IO.println "erc4626-stdlib: ok (pro-rata·entry/exit fee·EVM; Solana/NEAR honest reject)"
  pure 0

end ProofForge.Tests.ERC4626Stdlib

def main : IO UInt32 :=
  ProofForge.Tests.ERC4626Stdlib.main
