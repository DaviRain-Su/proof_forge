import Init.Data.Array.Basic
import ProofForge.Contract.EvmConstructorInit
import ProofForge.Contract.Intent
import ProofForge.Contract.UpgradePolicy
import ProofForge.IR.Contract

namespace ProofForge.Contract

open ProofForge.IR

/-- Deploy-time constructor parameter schema (name + host ABI type string).

Materialized as EVM constructor ABI today; other targets ignore until they
grow deploy-constructor lanes. Prefer this name over the historical
`EvmConstructorParam` alias. -/
structure ConstructorParam where
  name : String
  abiType : String
  deriving Repr, BEq

/-- Historical name — prefer `ConstructorParam`. -/
abbrev EvmConstructorParam := ConstructorParam

structure ContractSpec where
  name : String
  module : ProofForge.IR.Module
  intents : Array Intent := #[]
  upgradePolicy? : Option UpgradePolicy := none
  proxyPattern? : Option ProxyPattern := none
  /-- Deploy constructor parameter schema (EVM materialization today). -/
  constructorParams : Array ConstructorParam := #[]
  /-- Deploy constructor → storage init bindings (EVM materialization today). -/
  constructorInitBindings : Array ConstructorInitBinding := #[]
  /-- User-authored Quint safety invariants (`name`, expression string). -/
  quintInvariants : Array (String × String) := #[]
  quintLiveness : Array (String × String) := #[]
  /-- User-authored Lean invariants (`name`, predicate function qualified name).
  FV-8 / Track 1.7 authoring surface; the predicate is a `State → Bool`
  defined next to `contract_source` and verified pre-codegen. -/
  leanInvariants : Array (String × String) := #[]
  deriving Repr

/-- Historical field accessors — prefer `constructorParams` / `constructorInitBindings`. -/
def ContractSpec.evmConstructorParams (spec : ContractSpec) : Array ConstructorParam :=
  spec.constructorParams

def ContractSpec.evmConstructorInitBindings (spec : ContractSpec) : Array ConstructorInitBinding :=
  spec.constructorInitBindings

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
