import ProofForge.IR.Core.HostOp
import ProofForge.Target.Check

/-! # Typed Target HostOp Handler Registry

Per-target handler registry for host operations. A handler maps a typed
`HostOpId` to target-specific plan operations.
-/

namespace ProofForge.Target

open ProofForge.IR.Core

/-- A handler for one host operation on one target. -/
structure HostOpHandler (PlanOp : Type) where
  targetId : String
  id : ProofForge.Target.HostOpId
  lower : Array PlanOp

/-- A registry of host-op handlers for one target plan type. -/
structure HostOpRegistry (PlanOp : Type) where
  handlers : Array (HostOpHandler PlanOp) := #[]

/-- Empty registry. -/
def HostOpRegistry.empty (PlanOp : Type) : HostOpRegistry PlanOp :=
  ⟨#[]⟩

/-- Register a handler. Duplicate target+ID is an error, not last-write-wins. -/
def HostOpRegistry.register {PlanOp : Type} (reg : HostOpRegistry PlanOp)
    (handler : HostOpHandler PlanOp) :
    Except String (HostOpRegistry PlanOp) :=
  if reg.handlers.any (fun h => h.targetId == handler.targetId && h.id == handler.id) then
    .error s!"duplicate host-op handler"
  else
    .ok ⟨reg.handlers.push handler⟩

/-- Look up a handler for a given target and host-op ID. -/
def HostOpRegistry.lookup {PlanOp : Type} (reg : HostOpRegistry PlanOp)
    (targetId : String) (id : ProofForge.Target.HostOpId) : Option (HostOpHandler PlanOp) :=
  reg.handlers.find? (fun h => h.targetId == targetId && h.id == id)

/-- Check if a handler exists for a given target and host-op ID. -/
def HostOpRegistry.hasHandler {PlanOp : Type} (reg : HostOpRegistry PlanOp)
    (targetId : String) (id : ProofForge.Target.HostOpId) : Bool :=
  (reg.lookup targetId id).isSome

inductive HostOpResolutionError where
  | missingCapability (targetId : String) (capability : Capability)
  | missingHandler (targetId : String) (id : ProofForge.Target.HostOpId)
  | invalidPlan (targetId : String) (id : ProofForge.Target.HostOpId) (message : String)
  deriving Repr, BEq

/-- Resolve a typed HostOp for one target. Capability membership, handler
ownership, and the target plan's own validator are all mandatory. -/
def HostOpRegistry.resolve {PlanOp : Type} (reg : HostOpRegistry PlanOp)
    (profile : TargetProfile) (sig : ProofForge.IR.Core.HostOp.HostOpSig)
    (validatePlan : Array PlanOp -> Except String Unit) :
    Except HostOpResolutionError (Array PlanOp) := do
  match firstUnsupportedCapability? profile sig.requiredCapabilities with
  | some capability =>
      throw (.missingCapability profile.id capability)
  | none => pure ()
  let handler <- match reg.lookup profile.id sig.id with
    | some handler => pure handler
    | none => throw (.missingHandler profile.id sig.id)
  match validatePlan handler.lower with
  | .ok () => pure handler.lower
  | .error message => throw (.invalidPlan profile.id sig.id message)

end ProofForge.Target
