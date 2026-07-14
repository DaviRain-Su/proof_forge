import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Evm.IR
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

private def requireErrorContains (needle : String) (result : Except String α) : IO Unit :=
  match result with
  | .error message =>
      require (message.contains needle)
        s!"expected error containing `{needle}`, got `{message}`"
  | .ok _ => throw (IO.userError s!"expected error containing `{needle}`")

private def initCodeHex := "69602a60005260206000f3600052600a6016f3"

private def createModule : ProofForge.IR.Module := {
  name := "EvmCreateHostOp"
  state := #[]
  entrypoints := #[
    {
      name := "deploy"
      selector? := some "01020304"
      params := #[]
      «returns» := .address
      body := #[.return (ProofForge.Contract.Source.Evm.createDeploy
        (.literal (.u128 0)) initCodeHex)]
    },
    {
      name := "deploy2"
      selector? := some "05060708"
      params := #[]
      «returns» := .address
      body := #[.return (ProofForge.Contract.Source.Evm.create2Deploy
        (.literal (.u128 0)) (.literal (.hash4 0 0 0 7)) initCodeHex)]
    }
  ]
}

private def createFixture (name : String) (body : ProofForge.IR.Expr) : ProofForge.IR.Module := {
  name
  state := #[]
  entrypoints := #[{
    name := "deploy"
    selector? := some "01020304"
    params := #[]
    «returns» := .address
    body := #[.return body]
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

private def planHasCreate (plan : ProofForge.Backend.Evm.Plan.ModulePlan) : Bool :=
  plan.entrypoints.any fun entrypoint =>
    entrypoint.body.any fun statement => match statement with
      | .letBind _ .address (.create .create _ none code) => code == initCodeHex
      | _ => false

def main : IO Unit := do
  let spec := ProofForge.Contract.ContractSpec.fromIR createModule
  let checked <- match ProofForge.IR.Legacy.Adapter.adaptLegacy spec with
    | .ok bundle => pure bundle.contract
    | .error error => throw (IO.userError s!"CREATE adaptation failed: {repr error}")
  require (hostCallIds checked == #[ProofForge.Target.HostOps.Evm.createSig.id,
      ProofForge.Target.HostOps.Evm.create2Sig.id])
    "CREATE authoring did not normalize to the exact EVM HostOp IDs"
  match ProofForge.Compiler.runStrictCanonicalTargetGate "evm" spec with
  | .ok _ => pure ()
  | .error error => throw (IO.userError s!"strict EVM CREATE2 gate failed: {error}")
  require ((ProofForge.Compiler.checkHostOpHandlers "wasm-near" checked).size == 2)
    "NEAR accepted EVM CREATE HostOps"
  require ((ProofForge.Compiler.checkHostOpHandlers "solana-sbpf-asm" checked).size == 2)
    "Solana accepted EVM CREATE HostOps"
  let capPlan : CapabilityPlan := {
    targetId := "evm"
    calls := checked.contract.requirements
  }
  let plan <- match ProofForge.Backend.Evm.Plan.Core.buildFromCore checked capPlan with
    | .ok plan => pure plan
    | .error error => throw (IO.userError s!"EVM CREATE2 plan failed: {error.message}")
  require (planHasCreate plan && planHasCreate2 plan)
    "CREATE HostOps did not reach the EVM semantic plan"
  require (plan.creates == #[{ mode := .create, initCodeHex },
      { mode := .create2, initCodeHex }])
    "CREATE helper requirements were not collected from the canonical plan"
  let yul <- match ProofForge.Backend.Evm.IR.renderCanonicalModuleWithPlan plan with
    | .ok yul => pure yul
    | .error error => throw (IO.userError s!"canonical CREATE Yul failed: {error.message}")
  require (yul.contains s!"function __proof_forge_create_{initCodeHex}")
    "canonical Yul did not emit the CREATE helper"
  require (yul.contains s!"function __proof_forge_create2_{initCodeHex}")
    "canonical Yul did not emit the CREATE2 helper"
  requireErrorContains "CoreType.u128" <|
    ProofForge.Compiler.runStrictCanonicalTargetGate "evm" <|
      ProofForge.Contract.ContractSpec.fromIR <|
        createFixture "BadCreateCallValue" <|
          ProofForge.Contract.Source.Evm.createDeploy (.literal (.bool true)) "6000"
  requireErrorContains "init code must contain only hex digits" <|
    ProofForge.Compiler.runStrictCanonicalTargetGate "evm" <|
      ProofForge.Contract.ContractSpec.fromIR <|
        createFixture "BadCreateInitCode" <|
          ProofForge.Contract.Source.Evm.createDeploy (.literal (.u128 0)) "60zz"
  requireErrorContains "CoreType.hash" <|
    ProofForge.Compiler.runStrictCanonicalTargetGate "evm" <|
      ProofForge.Contract.ContractSpec.fromIR <|
        createFixture "BadCreate2Salt" <|
          ProofForge.Contract.Source.Evm.create2Deploy
            (.literal (.u128 0)) (.literal (.bool true)) "6000"
  IO.println "evm-create-hostop: ok"
