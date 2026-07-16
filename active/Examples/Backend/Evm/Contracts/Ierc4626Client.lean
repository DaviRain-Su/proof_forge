/-
Layer B fixture: IERC4626 external vault CALL client.
-/
import ProofForge.Contract.Builder
import ProofForge.Protocols.Evm.IERC4626

namespace Examples.Backend.Evm.Contracts.Ierc4626Client

open ProofForge.Contract.Builder
open ProofForge.Protocols.Evm.IERC4626

def spec : ProofForge.Contract.ContractSpec :=
  build "Ierc4626Client" do
    scalarState "last" .u64
    let vault ← declareVault "vault.peer"

    entrySelectorWithParams "readShares" "3f167e17" #[("assets", .u64)] .u64 do
      ret (convertToShares vault (localVar "assets"))

    entrySelectorWithParams "doDeposit" "90f87f7c"
        #[("assets", .u64), ("receiver", .u64)] .u64 do
      letBind "shares" .u64 (deposit vault (localVar "assets") (localVar "receiver"))
      effect (storageScalarWrite "last" (localVar "shares"))
      ret (localVar "shares")

    entrySelectorReturns "readTotalAssets" "ab795739" .u64 do
      ret (totalAssets vault)

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Backend.Evm.Contracts.Ierc4626Client
