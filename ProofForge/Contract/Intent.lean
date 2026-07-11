import Init.Data.String.Basic
import ProofForge.Target.Plan

namespace ProofForge.Contract

inductive IntentKind where
  | module
  | state
  | entrypoint
  | capability
  deriving BEq, DecidableEq, Repr

def IntentKind.id : IntentKind -> String
  | .module => "module"
  | .state => "state"
  | .entrypoint => "entrypoint"
  | .capability => "capability"

structure Intent where
  kind : IntentKind
  label : String
  capability? : Option ProofForge.Target.Capability := none
  source? : Option String := none
  metadata : Array ProofForge.Target.TargetMetadata := #[]
  deriving Repr, BEq

def Intent.capability (capability : ProofForge.Target.Capability) (operation : String := capability.id)
    (source? : Option String := none) (metadata : Array ProofForge.Target.TargetMetadata := #[]) : Intent := {
  kind := .capability
  label := operation
  capability? := some capability
  source?
  metadata := metadata
}

end ProofForge.Contract
