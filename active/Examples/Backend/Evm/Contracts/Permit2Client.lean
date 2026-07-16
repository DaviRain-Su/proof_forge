/-
Layer B fixture: Permit2 external CALL client.
-/
import ProofForge.Contract.Builder
import ProofForge.Protocols.Evm.Permit2

namespace Examples.Backend.Evm.Contracts.Permit2Client

open ProofForge.Contract.Builder
open ProofForge.Protocols.Evm.Permit2

def spec : ProofForge.Contract.ContractSpec :=
  build "Permit2Client" do
    scalarState "last" .u64
    let p2 ← declarePermit2 "permit2.peer"
    entrySelectorWithParams "pull" "0d42ae62"
        #[("from", .u64), ("to", .u64), ("amount", .u64), ("token", .u64)] .unit do
      letBind "_r" .u64
        (transferFrom p2 (localVar "from") (localVar "to") (localVar "amount") (localVar "token"))
      effect (storageScalarWrite "last" (localVar "amount"))

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Backend.Evm.Contracts.Permit2Client
