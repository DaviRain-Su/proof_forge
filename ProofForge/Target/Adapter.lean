import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Contract.Spec
import ProofForge.Contract.UpgradePolicy.Lower
import ProofForge.Target.Check
import ProofForge.Target.Plan

namespace ProofForge.Target

structure Diagnostic where
  message : String
  deriving Repr, Inhabited

def Diagnostic.render (diagnostic : Diagnostic) : String :=
  diagnostic.message

def Diagnostic.fromCapabilityError (err : CapabilityError) : Diagnostic := {
  message := err.render
}

def intentCapabilityCalls (spec : ProofForge.Contract.ContractSpec) : Array CapabilityCall :=
  spec.intents.foldl
    (fun calls intent =>
      match intent.capability? with
      | some capability => calls.push {
          capability := capability
          operation := intent.label
          source? := intent.source?
          metadata := intent.metadata
        }
      | none => calls)
    #[]

def moduleCapabilityCalls (module : ProofForge.IR.Module) : Array CapabilityCall :=
  module.capabilities.map (fun capability => CapabilityCall.fromCapability capability)

def capabilityCallsForSpec (spec : ProofForge.Contract.ContractSpec) : Array CapabilityCall :=
  let calls := intentCapabilityCalls spec
  if calls.size == 0 then
    moduleCapabilityCalls spec.module
  else
    calls

def defaultMetadata (profile : TargetProfile) (spec : ProofForge.Contract.ContractSpec) : Array TargetMetadata := #[
  { key := "contract", value := spec.name },
  { key := "target", value := profile.id },
  { key := "resolver", value := "ir-capability-plan-v0" }
] ++ upgradePolicyMetadata spec ++ proxyPatternMetadata spec
where
  upgradePolicyMetadata (spec : ProofForge.Contract.ContractSpec) : Array TargetMetadata :=
    match spec.upgradePolicy? with
    | none => #[]
    | some policy =>
        let base := #[
          { key := "upgrade.policy.kind", value := policy.kind }
        ]
        match policy with
        | .immutable => base
        | .authority keyRef => base.push { key := "upgrade.policy.key_ref", value := keyRef }
        | .governance ref => base.push { key := "upgrade.policy.ref", value := ref }

  proxyPatternMetadata (spec : ProofForge.Contract.ContractSpec) : Array TargetMetadata :=
    match spec.proxyPattern? with
    | none => #[]
    | some pattern => #[
        { key := "upgrade.proxy.pattern", value := pattern.kind }
      ]

def metadataRequiresSolana (metadata : Array TargetMetadata) : Bool :=
  metadata.any (fun item => item.key.startsWith "solana.")

def firstSolanaMetadataCall? (calls : Array CapabilityCall) : Option CapabilityCall :=
  calls.find? (fun call => metadataRequiresSolana call.metadata)

def targetExtensionMetadataAllowed (profile : TargetProfile) (calls : Array CapabilityCall) : Bool :=
  match firstSolanaMetadataCall? calls with
  | none => true
  | some _ => profile.family == .solana

def solanaExtensionMetadataError (profile : TargetProfile) (call : CapabilityCall) : Diagnostic := {
  message := s!"target `{profile.id}` cannot use Solana target extension metadata on operation `{call.operation}`"
}

def firstUnsupportedCapabilityCall? (profile : TargetProfile) (calls : Array CapabilityCall) :
    Option CapabilityCall :=
  calls.find? (fun call => !hasCapability profile call.capability)

def unsupportedCapabilityCallDiagnostic (profile : TargetProfile) (call : CapabilityCall) :
    Diagnostic :=
  let sourceFragment :=
    match call.source? with
    | none => ""
    | some source => s!" on operation `{call.operation}` at `{source}`"
  {
    message :=
      s!"target `{profile.id}` does not support capability `{call.capability.id}`{sourceFragment}: capability is not present in the target profile"
  }

def requireTargetExtensionMetadata (profile : TargetProfile) (calls : Array CapabilityCall) :
    Except Diagnostic Unit := do
  match firstSolanaMetadataCall? calls with
  | none => .ok ()
  | some call =>
      if profile.family == .solana then
        .ok ()
      else
        .error (solanaExtensionMetadataError profile call)

def CapabilityPlan.supportedBy (profile : TargetProfile) (plan : CapabilityPlan) : Bool :=
  allCapabilitiesSupported profile plan.capabilities

def CapabilityPlan.targetExtensionsAllowed (profile : TargetProfile) (plan : CapabilityPlan) : Bool :=
  targetExtensionMetadataAllowed profile plan.calls

def CapabilityPlan.checkedBy (profile : TargetProfile) (plan : CapabilityPlan) : Bool :=
  plan.supportedBy profile && plan.targetExtensionsAllowed profile

def requireCapabilityPlan (profile : TargetProfile) (plan : CapabilityPlan) :
    Except Diagnostic CapabilityPlan :=
  match requireTargetExtensionMetadata profile plan.calls with
  | .error err => .error err
  | .ok () =>
      match firstUnsupportedCapabilityCall? profile plan.calls with
      | some call => .error (unsupportedCapabilityCallDiagnostic profile call)
      | none =>
          match requireCapabilities profile plan.capabilities with
          | .ok () => .ok plan
          | .error err => .error (Diagnostic.fromCapabilityError err)

def defaultResolve (profile : TargetProfile) (spec : ProofForge.Contract.ContractSpec) :
    Except Diagnostic CapabilityPlan := do
  match spec.upgradePolicy? with
  | none => pure ()
  | some policy =>
      match ProofForge.Contract.UpgradePolicy.checkSupported profile.id policy spec.proxyPattern? with
      | .ok () => pure ()
      | .error message => .error { message }
  let plan : CapabilityPlan := {
    targetId := profile.id
    calls := capabilityCallsForSpec spec
    metadata := defaultMetadata profile spec
  }
  requireCapabilityPlan profile plan

structure TargetAdapter where
  profile : TargetProfile
  resolve : ProofForge.Contract.ContractSpec -> Except Diagnostic CapabilityPlan

def TargetAdapter.default (profile : TargetProfile) : TargetAdapter := {
  profile := profile
  resolve := defaultResolve profile
}

def resolveSpec (profile : TargetProfile) (spec : ProofForge.Contract.ContractSpec) :
    Except Diagnostic CapabilityPlan :=
  (TargetAdapter.default profile).resolve spec

def resolveModule (profile : TargetProfile) (module : ProofForge.IR.Module) :
    Except Diagnostic CapabilityPlan :=
  resolveSpec profile (ProofForge.Contract.ContractSpec.fromIR module)

end ProofForge.Target
