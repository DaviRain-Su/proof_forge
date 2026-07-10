import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Contract.Spec
import ProofForge.IR.Mutability
import ProofForge.Contract.UpgradePolicy.Lower
import ProofForge.Target.Check
import ProofForge.Target.HostRuntime
import ProofForge.Target.PortableHonesty
import ProofForge.Target.Plan

namespace ProofForge.Target

open ProofForge.Target.HostRuntime
open ProofForge.Target.PortableHonesty

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

/-- Capability calls for a spec: union of intent-declared and module-derived
capabilities, deduplicated. Previously this was intent-OR-module (intents
silently dropped module capabilities when present), which let `resolveSpec`
return `.ok` for a module using an unsupported capability. -/
def capabilityCallsForSpec (spec : ProofForge.Contract.ContractSpec) : Array CapabilityCall :=
  let intentCalls := intentCapabilityCalls spec
  let moduleCalls := moduleCapabilityCalls spec.module
  (intentCalls ++ moduleCalls).foldl
    (fun acc call =>
      if acc.any (fun existing => existing == call) then acc
      else acc.push call)
    #[]

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

/-- Layer A HostRuntime honesty: capabilities requested by the plan must have
real native bindings on this target (not `n/a`). Runs before profile capability
membership so PDA-on-NEAR etc. name HostRuntime in the diagnostic. -/
def requirePlanHostRuntimeHonesty (profile : TargetProfile) (plan : CapabilityPlan) :
    Except Diagnostic Unit :=
  match requireHostRuntimeHonesty profile.id plan.capabilities with
  | .ok () => .ok ()
  | .error msg => .error { message := msg }

def requireCapabilityPlan (profile : TargetProfile) (plan : CapabilityPlan) :
    Except Diagnostic CapabilityPlan :=
  match requireTargetExtensionMetadata profile plan.calls with
  | .error err => .error err
  | .ok () =>
      match requirePlanHostRuntimeHonesty profile plan with
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
  match ProofForge.IR.Mutability.validateModule spec.module with
  | .ok () => pure ()
  | .error message => .error { message }
  -- Portable honesty (HostEnv / Identity / sync-crosscall / upgrade materialize).
  -- Uses materializeUpgrade (UUPS-only EVM, etc.) rather than checkSupported alone
  -- so transparent proxy and missing lowers fail closed before codegen.
  match requirePortableHonesty profile.id spec.module spec.upgradePolicy? spec.proxyPattern? with
  | .ok () => pure ()
  | .error message => .error { message }
  -- FV-5 checked-overflow gate: a module that declares `overflowChecked`
  -- (Solidity-0.8-style revert-on-overflow) can only resolve to a target whose
  -- profile declares the `arith.checked` capability. This is a standalone gate
  -- (separate from the per-call capability plan) because `overflowChecked` is a
  -- module-level property that the per-intent call derivation does not surface.
  if spec.module.overflowChecked && !(profile.capabilities.contains .checkedArithmetic) then
    .error {
      message := s!"target `{profile.id}` does not support capability `arith.checked`: \
        module `{spec.module.name}` declares checked overflow but the target profile \
        lowers to wrapping arithmetic (silent overflow)"
    }
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
