import Init.Data.Array.Basic
import ProofForge.Contract.EvmConstructorInit
import ProofForge.Contract.Intent
import ProofForge.Contract.UpgradePolicy
import ProofForge.IR.Contract

namespace ProofForge.Contract

open ProofForge.IR

structure EvmConstructorParam where
  name : String
  abiType : String
  deriving Repr, BEq

structure ContractSpec where
  name : String
  module : ProofForge.IR.Module
  intents : Array Intent := #[]
  upgradePolicy? : Option UpgradePolicy := none
  proxyPattern? : Option ProxyPattern := none
  evmConstructorParams : Array EvmConstructorParam := #[]
  evmConstructorInitBindings : Array EvmConstructorInitBinding := #[]
  deriving Repr

def moduleIntent (module : ProofForge.IR.Module) : Intent := {
  kind := .module
  label := module.name
}

def stateIntent (state : StateDecl) : Intent := {
  kind := .state
  label := state.id
}

def entrypointIntent (entrypoint : Entrypoint) : Intent := {
  kind := .entrypoint
  label := entrypoint.name
}

def capabilityIntents (module : ProofForge.IR.Module) : Array Intent :=
  module.capabilities.map (fun capability => Intent.capability capability)

def intentsFromIR (module : ProofForge.IR.Module) : Array Intent :=
  #[moduleIntent module] ++
    module.state.map stateIntent ++
    module.entrypoints.map entrypointIntent ++
    capabilityIntents module

def ContractSpec.fromIR (module : ProofForge.IR.Module) : ContractSpec := {
  name := module.name
  module := module
  intents := intentsFromIR module
}

end ProofForge.Contract
