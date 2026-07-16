/-
Layer B fixture: Multicall3 external CALL client.
-/
import ProofForge.Contract.Builder
import ProofForge.Protocols.Evm.Multicall

namespace Examples.Backend.Evm.Contracts.MulticallClient

open ProofForge.Contract.Builder
open ProofForge.Protocols.Evm.Multicall

def spec : ProofForge.Contract.ContractSpec :=
  build "MulticallClient" do
    scalarState "last" .u64
    let mc ← declareMulticall "multicall.peer"
    entrySelectorWithParams "batch" "0eaa75fe" #[("tag", .u64)] .unit do
      letBind "_r" .u64 (aggregate mc #[localVar "tag"])
      effect (storageScalarWrite "last" (localVar "tag"))

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Backend.Evm.Contracts.MulticallClient
