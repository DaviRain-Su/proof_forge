/-
Layer B fixture: EIP-2612 permit external CALL client.
-/
import ProofForge.Contract.Builder
import ProofForge.Protocols.Evm.IERC20Permit

namespace Examples.Backend.Evm.Contracts.Ierc20PermitClient

open ProofForge.Contract.Builder
open ProofForge.Protocols.Evm.IERC20Permit

def spec : ProofForge.Contract.ContractSpec :=
  build "Ierc20PermitClient" do
    scalarState "last" .u64
    let token ← declareToken "permit.token"

    entrySelectorWithParams "runPermit" "3e18cf35"
        #[("owner", .u64), ("spender", .u64), ("value", .u64),
          ("deadline", .u64), ("v", .u64), ("r", .u64), ("s", .u64)] .unit do
      letBind "_ok" .u64
        (permit token (localVar "owner") (localVar "spender") (localVar "value")
          (localVar "deadline") (localVar "v") (localVar "r") (localVar "s"))
      effect (storageScalarWrite "last" (localVar "value"))

    entrySelectorWithParams "readNonce" "8c3f5563" #[("owner", .u64)] .u64 do
      ret (nonces token (localVar "owner"))

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Backend.Evm.Contracts.Ierc20PermitClient
