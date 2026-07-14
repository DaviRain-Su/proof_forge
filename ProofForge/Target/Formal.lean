import ProofForge.Target.Adapter
import ProofForge.IR.Canonical

namespace ProofForge.Target

/-!
# Target Capability Routing Formal Anchors

FV-1 tracks the core routing promise: a target-resolved plan must not silently
carry capabilities or target-extension metadata that the selected target cannot
handle. These theorems pin the checked boundary used by `resolveSpec`.
-/

theorem requireTargetExtensionMetadata_ok_iff (profile : TargetProfile)
    (calls : Array CapabilityCall) :
    requireTargetExtensionMetadata profile calls = .ok () ↔
      targetExtensionMetadataAllowed profile calls = true := by
  unfold requireTargetExtensionMetadata targetExtensionMetadataAllowed
  cases firstSolanaMetadataCall? calls with
  | none =>
      simp
  | some call =>
      by_cases hFamily : profile.family == TargetFamily.solana
      · simp [hFamily]
      · simp [hFamily]

theorem requireCapabilityPlan_sound {profile : TargetProfile} {plan checked : CapabilityPlan}
    (h : requireCapabilityPlan profile plan = .ok checked) :
    checked.checkedBy profile = true := by
  unfold requireCapabilityPlan at h
  cases hExt : requireTargetExtensionMetadata profile plan.calls with
  | error err =>
      simp [hExt] at h
  | ok _ =>
      cases hHost : requirePlanHostRuntimeHonesty profile plan with
      | error err =>
          simp [hExt, hHost] at h
      | ok _ =>
          cases hHostCall : firstUnsupportedHostOpCall? profile plan.calls with
          | some call =>
              simp [hExt, hHost, hHostCall] at h
          | none =>
              cases hCall : firstUnsupportedCapabilityCall? profile plan.calls with
              | some call =>
                  simp [hExt, hHost, hHostCall, hCall] at h
              | none =>
                  cases hCaps : requireCapabilities profile plan.capabilities with
                  | error err =>
                      simp [hExt, hHost, hHostCall, hCall, hCaps] at h
                  | ok _ =>
                      simp [hExt, hHost, hHostCall, hCall, hCaps] at h
                      subst checked
                      have hSupported : CapabilityPlan.supportedBy profile plan = true :=
                        (requireCapabilities_ok_iff profile plan.capabilities).mp hCaps
                      have hExtension : CapabilityPlan.targetExtensionsAllowed profile plan = true :=
                        (requireTargetExtensionMetadata_ok_iff profile plan.calls).mp hExt
                      simp [CapabilityPlan.checkedBy, hSupported, hExtension]

theorem requireCapabilityPlan_capability_sound {profile : TargetProfile}
    {plan checked : CapabilityPlan}
    (h : requireCapabilityPlan profile plan = .ok checked) :
    checked.supportedBy profile = true := by
  have hChecked := requireCapabilityPlan_sound h
  unfold CapabilityPlan.checkedBy at hChecked
  cases hSupported : checked.supportedBy profile
  · simp [hSupported] at hChecked
  · rfl

theorem requireCapabilityPlan_target_extension_sound {profile : TargetProfile}
    {plan checked : CapabilityPlan}
    (h : requireCapabilityPlan profile plan = .ok checked) :
    checked.targetExtensionsAllowed profile = true := by
  have hChecked := requireCapabilityPlan_sound h
  unfold CapabilityPlan.checkedBy at hChecked
  cases hSupported : checked.supportedBy profile
  · simp [hSupported] at hChecked
  · simp [hSupported] at hChecked
    exact hChecked

def ResolveResult.checkedBy (profile : TargetProfile)
    (result : Except Diagnostic CapabilityPlan) : Bool :=
  match result with
  | .ok plan => plan.checkedBy profile
  | .error _ => true

def resolveSpecCheckedBy (profile : TargetProfile)
    (spec : ProofForge.Contract.ContractSpec) : Bool :=
  ResolveResult.checkedBy profile (resolveSpec profile spec)

/-- Check the capability boundary for an already validated Canonical contract.
This is the direct-architecture counterpart of `resolveSpecCheckedBy`; it does
not reconstruct a `ContractSpec` or v1 `IR.Module`. -/
def resolveCanonicalCheckedBy (profile : TargetProfile)
    (checked : ProofForge.IR.Canonical.CheckedCanonicalContract) : Bool :=
  ResolveResult.checkedBy profile <| requireCapabilityPlan profile {
    targetId := profile.id
    calls := checked.contract.requirements
    metadata := #[]
  }

end ProofForge.Target
