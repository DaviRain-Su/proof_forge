/-
ERC-4626 inverse quote rounding regression.
-/
import ProofForge.Contract.Stdlib.ERC4626

namespace ProofForge.Tests.ERC4626Rounding

open ProofForge.Contract.Stdlib.ERC4626.Spec

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw (IO.userError message)

def main : IO UInt32 := do
  let rounding : State := { totalAssets := 2, totalSupply := 3 }
  require (convertToAssetsUp rounding 1 == 1)
    "previewMint must round required assets up"
  require (convertToSharesUp rounding 1 == 2)
    "previewWithdraw must round required shares up"
  require (convertToAssetsUp rounding 0 == 0 && convertToSharesUp rounding 0 == 0)
    "ceil conversion must preserve zero"
  require (convertToAssetsUp { totalAssets := 6, totalSupply := 3 } 1 == 2)
    "ceil conversion must preserve exact division"
  require (previewMintAssets? rounding 990 100 == some 667)
    "previewMint must round up after fee grossing"
  require (previewWithdrawShares rounding 1 == 2)
    "previewWithdraw must use ceil share conversion"
  match withdraw? rounding 1 0 with
  | none => throw (IO.userError "rounded withdraw should succeed")
  | some (next, burned) =>
      require (burned == 2) "withdraw must burn its rounded-up quote"
      require (next.totalAssets == 1 && next.totalSupply == 1)
        "withdraw totals must match the rounded-up burn"
  match mintActual? { totalAssets := 2, totalSupply := 100 } 1 1 0 with
  | none => throw (IO.userError "covered mint should succeed")
  | some (next, userShares) =>
      require (userShares == 1) "mint must issue exactly the requested net shares"
      require (next.totalAssets == 3 && next.totalSupply == 101)
        "surplus share capacity must not increase the requested mint"
  match mintActual? { totalAssets := 200, totalSupply := 300 } 150 99 0 with
  | none => pure ()
  | some _ =>
      throw (IO.userError
        "mint must reject when FOT actual assets do not cover requested gross shares")
  let exitState : State := { totalAssets := 200, totalSupply := 300 }
  require (maxWithdrawAssets exitState 300 100 == 200)
    "maxWithdraw must return gross assets without applying the exit fee twice"
  require (maxRedeemShares exitState 300 100 == 300)
    "maxRedeem must return an executable full share balance"
  require (maxWithdrawAssets exitState 300 10000 == 0)
    "100 percent exit fee must disable withdraw"
  require (maxRedeemShares exitState 300 10000 == 0)
    "100 percent exit fee must disable redeem"
  IO.println "erc4626-rounding: ok"
  pure 0

end ProofForge.Tests.ERC4626Rounding

def main : IO UInt32 :=
  ProofForge.Tests.ERC4626Rounding.main
