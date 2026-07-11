import ProofForge.IR.Core.HostOp

/-! # Typed Target HostOp Handler Registry

Per-target handler registry for host operations. A handler maps a typed
`HostOpId` to target-specific plan operations.
-/

namespace ProofForge.Target

open ProofForge.IR.Core

/-- A handler for one host operation on one target. -/
structure HostOpHandler (PlanOp : Type) where
  targetId : String
  id : HostOpId
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
    (targetId : String) (id : HostOpId) : Option (HostOpHandler PlanOp) :=
  reg.handlers.find? (fun h => h.targetId == targetId && h.id == id)

/-- Check if a handler exists for a given target and host-op ID. -/
def HostOpRegistry.hasHandler {PlanOp : Type} (reg : HostOpRegistry PlanOp)
    (targetId : String) (id : HostOpId) : Bool :=
  (reg.lookup targetId id).isSome

end ProofForge.Target