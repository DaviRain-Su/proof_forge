import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Compiler.CanonicalPipeline
import ProofForge.Contract.Source.Evm
import ProofForge.Contract.Spec
import ProofForge.IR.Legacy.Adapter

open ProofForge.IR
open ProofForge.IR.Core
open ProofForge.IR.Canonical
open ProofForge.Target

private def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def initCodeHex := "69602a60005260206000f3600052600a6016f3"

private def createModule : ProofForge.IR.Module := {
  name := "EvmCreateHostOp"
  state := #[]
  entrypoints := #[{
    name := "deploy"
    selector? := some "01020304"
    params := #[]
    «returns» := .address
    body := #[.return (ProofForge.Contract.Source.Evm.create2Deploy
      (.literal (.u128 0)) (.literal (.hash4 0 0 0 7)) initCodeHex)]
  }]
}

private def hostCallIds (checked : CheckedCanonicalContract) : Array ProofForge.Target.HostOpId :=
  checked.contract.module.functions.flatMap fun function =>
    function.blocks.flatMap fun block =>
      block.instructions.filterMap fun instruction => match instruction.op with
        | .hostCall call => some call.id
        | _ => none

private def planHasCreate2 (plan : ProofForge.Backend.Evm.Plan.ModulePlan) : Bool :=
  plan.entrypoints.any fun entrypoint =>
    entrypoint.body.any fun statement => match statement with
      | .letBind _ .address (.create .create2 _ (some _) code) => code == initCodeHex
      | _ => false

def main : IO Unit := do
  let spec := ProofForge.Contract.ContractSpec.fromIR createModule
  let checked <- match ProofForge.IR.Legacy.Adapter.adaptLegacy spec with
    | .ok bundle => pure bundle.contract
    | .error error => throw (IO.userError s!"CREATE2 adaptation failed: {repr error}")
  require (hostCallIds checked == #[ProofForge.Target.HostOps.Evm.create2Sig.id])
    "CREATE2 authoring did not normalize to the exact EVM HostOp ID"
  match ProofForge.Compiler.runStrictCanonicalTargetGate "evm" spec with
  | .ok _ => pure ()
  | .error error => throw (IO.userError s!"strict EVM CREATE2 gate failed: {error}")
  require ((ProofForge.Compiler.checkHostOpHandlers "wasm-near" checked).size == 1)
    "NEAR accepted the EVM CREATE2 HostOp"
  require ((ProofForge.Compiler.checkHostOpHandlers "solana-sbpf-asm" checked).size == 1)
    "Solana accepted the EVM CREATE2 HostOp"
  let capPlan : CapabilityPlan := {
    targetId := "evm"
    calls := checked.contract.requirements
  }
  let plan <- match ProofForge.Backend.Evm.Plan.Core.buildFromCore checked capPlan with
    | .ok plan => pure plan
    | .error error => throw (IO.userError s!"EVM CREATE2 plan failed: {error.message}")
  require (planHasCreate2 plan) "CREATE2 HostOp did not reach the EVM semantic plan"
  require (plan.creates == #[{ mode := .create2, initCodeHex }])
    "CREATE2 helper requirement was not collected from the canonical plan"
  IO.println "evm-create-hostop: ok"
