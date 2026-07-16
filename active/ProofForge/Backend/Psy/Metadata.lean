/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Psy plan-driven metadata — the `psy-dpn` counterpart of
`ProofForge.Backend.Evm.Metadata`.

Consumes `ProofForge.Backend.Psy.Plan.PsyModulePlan` rather than re-discovering
facts from rendered `.psy` source. Produces the inputs needed by
`proof-forge-artifact.json` and deploy manifests: the entrypoint surface, event
surface, context ops, crosscall targets, and capability lists. Psy entrypoints
are addressed by method name (no selector), so the ABI surface is simpler than
EVM's.
-/

import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Backend.Psy.IR
import ProofForge.Backend.Psy.Plan
import ProofForge.IR.Contract

namespace ProofForge.Backend.Psy.Metadata

open ProofForge.IR
open ProofForge.Backend.Psy.IR
open ProofForge.Backend.Psy.Plan

/-! ## ABI entrypoint metadata -/

structure AbiParamDescriptor where
  name : String
  type : String
  deriving Repr, Inhabited, BEq

structure AbiEntrypointDescriptor where
  name : String
  params : Array AbiParamDescriptor
  returnType : String
  deriving Repr, Inhabited, BEq

def abiParamDescriptor (param : String × ValueType) : AbiParamDescriptor :=
  { name := param.fst, type := param.snd.name }

def abiEntrypointDescriptor (entrypoint : Entrypoint) : AbiEntrypointDescriptor :=
  {
    name := entrypoint.name
    params := entrypoint.params.map abiParamDescriptor
    returnType := entrypoint.returns.name
  }

def abiEntrypointDescriptors (module : Module) : Array AbiEntrypointDescriptor :=
  module.entrypoints.map abiEntrypointDescriptor

/-! ## ABI event metadata -/

structure AbiEventFieldDescriptor where
  name : String
  type : String
  deriving Repr, Inhabited, BEq

structure AbiEventDescriptor where
  name : String
  fields : Array AbiEventFieldDescriptor
  deriving Repr, Inhabited, BEq

def abiEventDescriptor (event : EventPlan) : AbiEventDescriptor :=
  {
    name := event.name
    fields := event.dataFields.map (fun (fieldName, fieldType) => { name := fieldName, type := fieldType })
  }

def pushUniqueEvent (events : Array AbiEventDescriptor) (event : AbiEventDescriptor) : Array AbiEventDescriptor :=
  if events.any (fun e => e.name == event.name && e.fields == event.fields) then events else events.push event

def dedupEvents (events : Array AbiEventDescriptor) : Array AbiEventDescriptor :=
  events.foldl pushUniqueEvent #[]

def abiEventDescriptors (plan : PsyModulePlan) : Array AbiEventDescriptor :=
  dedupEvents (plan.events.map abiEventDescriptor)

/-! ## Context and crosscall metadata -/

structure ContextOpDescriptor where
  name : String
  deriving Repr, Inhabited, BEq

def contextOpDescriptor (op : ContextOp) : ContextOpDescriptor :=
  { name := op.name }

def pushUniqueContextOp (ops : Array ContextOpDescriptor) (op : ContextOpDescriptor) : Array ContextOpDescriptor :=
  if ops.any (fun o => o.name == op.name) then ops else ops.push op

def dedupContextOps (ops : Array ContextOpDescriptor) : Array ContextOpDescriptor :=
  ops.foldl pushUniqueContextOp #[]

def contextOpDescriptors (plan : PsyModulePlan) : Array ContextOpDescriptor :=
  dedupContextOps (plan.contextOps.map contextOpDescriptor)

structure CrosscallDescriptor where
  targetContractId : String
  deriving Repr, Inhabited, BEq

def crosscallDescriptors (plan : PsyModulePlan) : Array CrosscallDescriptor :=
  let targets := plan.crosscalls.targets.map (fun target => { targetContractId := target })
  targets.foldl (fun acc c => if acc.any (fun existing => existing.targetContractId == c.targetContractId) then acc else acc.push c) #[]

def pushUniqueCapability (caps : Array String) (cap : String) : Array String :=
  if caps.any (fun c => c == cap) then caps else caps.push cap

def dedupCapabilities (caps : Array String) : Array String :=
  caps.foldl pushUniqueCapability #[]

/-! ## Artifact metadata -/

structure ArtifactMetadata where
  targetId : String
  moduleName : String
  entrypoints : Array AbiEntrypointDescriptor
  events : Array AbiEventDescriptor
  contextOps : Array ContextOpDescriptor
  crosscalls : Array CrosscallDescriptor
  capabilities : Array String
  deriving Repr, Inhabited

/-- Build artifact metadata from the semantic plan (Phase B3 metadata pass). -/
def buildArtifactMetadata (module : Module) (plan : PsyModulePlan) : ArtifactMetadata :=
  {
    targetId := "psy-dpn"
    moduleName := plan.name
    entrypoints := abiEntrypointDescriptors module
    events := abiEventDescriptors plan
    contextOps := contextOpDescriptors plan
    crosscalls := crosscallDescriptors plan
    capabilities := dedupCapabilities (plan.capabilities.map (·.id))
  }

/-- Build artifact metadata from a portable IR module (plan-first). -/
def buildPlanArtifactMetadata (module : Module) : Except PlanError ArtifactMetadata := do
  let plan ← buildModulePlan module
  .ok (buildArtifactMetadata module plan)

end ProofForge.Backend.Psy.Metadata