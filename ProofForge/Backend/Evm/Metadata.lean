import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.Lower
import ProofForge.IR.Contract
import ProofForge.Target.Adapter

/-! # EVM plan-driven metadata (RFC 0004 Metadata pass)

Consumes `Plan.ModulePlan` rather than re-discovering facts from rendered Yul.
This is the `Metadata.lean` module from the RFC 0004 proposed module shape. It
produces the inputs needed by `proof-forge-artifact.json` and deploy manifests:
the `abi.entrypoints` surface, `abi.events` surface, capability lists, and
module identity. -/

namespace ProofForge.Backend.Evm.Metadata

open ProofForge.IR
open ProofForge.Target
open ProofForge.Backend.Evm.Plan

/-! ## ABI entrypoint metadata -/

structure AbiParamDescriptor where
  name : String
  type : String
  deriving Repr, Inhabited

structure AbiEntrypointDescriptor where
  name : String
  selector : String
  params : Array AbiParamDescriptor
  returnType : String
  deriving Repr, Inhabited

def abiParamDescriptor (param : AbiParamPlan) : AbiParamDescriptor :=
  { name := param.name, type := param.type.name }

def abiEntrypointDescriptor (entrypoint : EntrypointPlan) : AbiEntrypointDescriptor :=
  {
    name := entrypoint.name
    selector := entrypoint.selector
    params := entrypoint.params.map abiParamDescriptor
    returnType := entrypoint.returns.returnType.name
  }

def abiEntrypointDescriptors (plan : ModulePlan) : Array AbiEntrypointDescriptor :=
  plan.entrypoints.map abiEntrypointDescriptor

/-! ## ABI event metadata -/

structure AbiEventFieldDescriptor where
  name : String
  type : String
  indexed : Bool
  deriving Repr, Inhabited

structure AbiEventDescriptor where
  name : String
  signature : String
  fields : Array AbiEventFieldDescriptor
  deriving Repr, Inhabited

def abiEventFieldDescriptor (field : EventFieldPlan) : AbiEventFieldDescriptor :=
  {
    name := field.name
    type := field.abiType?.getD field.type.name
    indexed := field.indexed
  }

def abiEventDescriptor (event : EventPlan) : AbiEventDescriptor :=
  {
    name := event.name
    signature := event.signature
    fields := event.fields.map abiEventFieldDescriptor
  }

def abiEventDescriptors (plan : ModulePlan) : Array AbiEventDescriptor :=
  plan.events.map abiEventDescriptor

/-! ## Capability metadata -/

def capabilityDescriptor (cap : Capability) : String :=
  cap.id

def capabilityDescriptors (plan : ModulePlan) : Array String :=
  plan.capabilities.map capabilityDescriptor


/-! ## Artifact metadata summary -/

structure ArtifactMetadata where
  moduleName : String
  targetId : String
  entrypoints : Array AbiEntrypointDescriptor
  events : Array AbiEventDescriptor
  capabilities : Array String
  deriving Repr

instance : Inhabited ArtifactMetadata := ⟨{ moduleName := "", targetId := "", entrypoints := #[], events := #[], capabilities := #[] }⟩

def buildArtifactMetadata (plan : ModulePlan) : ArtifactMetadata :=
  {
    moduleName := plan.metadata.moduleName
    targetId := plan.targetPlan.targetId
    entrypoints := abiEntrypointDescriptors plan
    events := abiEventDescriptors plan
    capabilities := capabilityDescriptors plan
  }

/-! ## Deploy metadata summary -/

structure DeployMetadata where
  moduleName : String
  targetId : String
  entrypointSelectors : Array (String × String)
  deriving Repr, Inhabited

def buildDeployMetadata (plan : ModulePlan) : DeployMetadata :=
  {
    moduleName := plan.metadata.moduleName
    targetId := plan.targetPlan.targetId
    entrypointSelectors := plan.entrypoints.map fun ep => (ep.name, ep.selector)
  }

end ProofForge.Backend.Evm.Metadata
