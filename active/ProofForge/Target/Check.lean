import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Target.Registry

namespace ProofForge.Target

structure CapabilityError where
  targetId : String
  capability : Capability
  message : String
  deriving Repr

def CapabilityError.render (err : CapabilityError) : String :=
  s!"target `{err.targetId}` does not support capability `{err.capability.id}`: {err.message}"

def capabilityError (profile : TargetProfile) (capability : Capability) : CapabilityError := {
  targetId := profile.id
  capability := capability
  message := "capability is not present in the target profile"
}

def firstUnsupportedCapability? (profile : TargetProfile) (capabilities : Array Capability) :
    Option Capability :=
  capabilities.find? (fun capability => !hasCapability profile capability)

def allCapabilitiesSupported (profile : TargetProfile) (capabilities : Array Capability) :
    Bool :=
  (firstUnsupportedCapability? profile capabilities).isNone

def requireCapability (profile : TargetProfile) (capability : Capability) : Except CapabilityError Unit :=
  if hasCapability profile capability then
    .ok ()
  else
    .error (capabilityError profile capability)

def requireCapabilities (profile : TargetProfile) (capabilities : Array Capability) : Except CapabilityError Unit := do
  match firstUnsupportedCapability? profile capabilities with
  | some capability => .error (capabilityError profile capability)
  | none => .ok ()

theorem requireCapability_ok_iff (profile : TargetProfile) (capability : Capability) :
    requireCapability profile capability = .ok () ↔ hasCapability profile capability = true := by
  unfold requireCapability
  by_cases h : hasCapability profile capability
  · simp [h]
  · simp [h]

theorem requireCapabilities_ok_iff (profile : TargetProfile) (capabilities : Array Capability) :
    requireCapabilities profile capabilities = .ok () ↔
      allCapabilitiesSupported profile capabilities = true := by
  unfold requireCapabilities allCapabilitiesSupported
  cases firstUnsupportedCapability? profile capabilities <;> simp

end ProofForge.Target
