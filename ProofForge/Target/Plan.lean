import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Target.Capability
import ProofForge.IR.Core.Syntax
import ProofForge.IR.Core.HostOp

namespace ProofForge.Target

/-! ## Typed Capability Operations

A capability operation is either a builtin (rendered to its old string form)
or a typed host operation (rendered to `namespace/name@major.minor.patch`).
JSON and learn artifacts remain wire-compatible through `.render`. -/

inductive CapabilityOperation
  | builtin (name : String)
  | hostOp (id : ProofForge.IR.Core.HostOpId)
  deriving BEq, Repr

def CapabilityOperation.render : CapabilityOperation → String
  | .builtin name => name
  | .hostOp id => id.render

instance : ToString CapabilityOperation where
  toString := CapabilityOperation.render

structure TargetMetadata where
  key : String
  value : String
  deriving Repr, BEq

structure CapabilityCall where
  capability : Capability
  operation : CapabilityOperation
  source? : Option String := none
  metadata : Array TargetMetadata := #[]
  deriving Repr, BEq

def CapabilityCall.fromCapability (capability : Capability) (source? : Option String := none)
    (metadata : Array TargetMetadata := #[]) : CapabilityCall := {
  capability := capability
  operation := .builtin capability.id
  source? := source?
  metadata := metadata
}

structure CapabilityPlan where
  targetId : String
  calls : Array CapabilityCall
  metadata : Array TargetMetadata := #[]
  deriving Repr

def CapabilityPlan.capabilities (plan : CapabilityPlan) : Array Capability :=
  plan.calls.map (fun call => call.capability)

end ProofForge.Target
