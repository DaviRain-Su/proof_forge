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
  | hostOp (id : ProofForge.Target.HostOpId)
  deriving BEq, Repr

def CapabilityOperation.render : CapabilityOperation → String
  | .builtin name => name
  | .hostOp id => id.render

def CapabilityOperation.hasIdentity : CapabilityOperation → Bool
  | .builtin name => !name.isEmpty
  | .hostOp id => !id.namespace_.isEmpty && !id.name.isEmpty

instance : ToString CapabilityOperation where
  toString := CapabilityOperation.render

structure TargetMetadata where
  key : String
  value : String
  deriving Repr, BEq

/-- Target-neutral values for versioned operation payloads. Target catalogs own
the field schema and validation; the shared carrier never interprets field
names or introduces target-specific constructors. -/
inductive OperationPayloadValue where
  | text (value : String)
  | natural (value : Nat)
  | flag (value : Bool)
  | texts (values : Array String)
  | naturals (values : Array Nat)
  | flags (values : Array Bool)
  | optionalText (value : Option String)
  | optionalNatural (value : Option Nat)
  deriving Repr, BEq

structure OperationPayloadField where
  name : String
  value : OperationPayloadValue
  deriving Repr, BEq

abbrev OperationPayload := Array OperationPayloadField

namespace OperationPayload

def value? (payload : OperationPayload) (name : String) : Option OperationPayloadValue :=
  payload.find? (fun field => field.name == name) |>.map (·.value)

def wellFormed (payload : OperationPayload) : Bool :=
  let result : Array String × Bool := payload.foldl (fun state field =>
    let duplicate := state.1.contains field.name
    (if duplicate then state.1 else state.1.push field.name, state.2 && !duplicate))
    (#[], true)
  payload.all (fun field => !field.name.isEmpty) && result.2

end OperationPayload

structure CapabilityCall where
  capability : Capability
  operation : CapabilityOperation
  source? : Option String := none
  metadata : Array TargetMetadata := #[]
  payload : OperationPayload := #[]
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
