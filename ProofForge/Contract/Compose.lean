/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Merge `ContractSpec` values built in separate Lean modules. Use this instead of
chaining `m1 *> m2` when both stdlib mixins must appear in one artifact: evaluating
`Ownable.mixin` in the same module that also imports `ERC20` currently crashes the
Lean interpreter (CS-2.7).
-/
import ProofForge.Contract.Spec

namespace ProofForge.Contract.Compose

open ProofForge.IR

def mergeModules (name : String) (left right : Module) : Module :=
  { name := name
    structs := left.structs ++ right.structs
    state := left.state ++ right.state
    entrypoints := left.entrypoints ++ right.entrypoints
    eventAbiWords := left.eventAbiWords ++ right.eventAbiWords
    proxyPattern? := left.proxyPattern? <|> right.proxyPattern? }

def mergeSpecs (name : String) (left right : ContractSpec) : ContractSpec :=
  { name := name
    module := mergeModules name left.module right.module
    intents := left.intents ++ right.intents
    upgradePolicy? := left.upgradePolicy? <|> right.upgradePolicy?
    proxyPattern? := left.proxyPattern? <|> right.proxyPattern?
    constructorParams := left.constructorParams ++ right.constructorParams
    constructorInitBindings := left.constructorInitBindings ++ right.constructorInitBindings
    quintInvariants := left.quintInvariants ++ right.quintInvariants
    quintLiveness := left.quintLiveness ++ right.quintLiveness
    leanInvariants := left.leanInvariants ++ right.leanInvariants }

def mergeMany (name : String) (specs : Array ContractSpec) : ContractSpec :=
  match specs.toList with
  | [] => ContractSpec.fromIR { name := name, structs := #[], state := #[], entrypoints := #[] }
  | spec :: rest => rest.foldl (mergeSpecs name) spec

def mergeExtension (name : String) (base extension : ContractSpec) : ContractSpec :=
  mergeSpecs name base extension

end ProofForge.Contract.Compose
