/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Aleo/Leo artifact metadata — the `aleo-leo` counterpart of
`ProofForge.Backend.Psy.Metadata` and `ProofForge.Backend.Evm.Metadata`.

Unlike Psy (which consumes a `PsyModulePlan`) and EVM (which consumes an
`EvmPlan`), the Aleo backend has no separate semantic-plan phase yet, so this
module derives the artifact metadata directly from the portable IR `Module`:
the entrypoint ABI surface, the on-chain state surface (every Aleo state lowers
to a Leo `mapping`, so the state surface is a list of `keyType => valueType`),
and the module's required capability set. `MetadataJson` renders this to the
`proof-forge-artifact.json` shape.
-/

import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Contract
import ProofForge.Target.Registry

namespace ProofForge.Backend.Aleo.Metadata

open ProofForge.IR

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

/-! ## On-chain state metadata -/

/-- One on-chain state declaration as lowered to Leo.

Every Aleo state lowers to a Leo `mapping`; scalars rewrite to a single-slot
`mapping id: u64 => T`, so the surface is uniformly `(id, keyType, valueType)`.
Unsupported storage shapes (array / dynamic array) are recorded with an
`"unsupported"` marker rather than silently dropped. -/
structure StateDescriptor where
  id : String
  keyType : String
  valueType : String
  deriving Repr, Inhabited, BEq

/-- The Leo mapping key/value spelling for a portable state declaration. -/
def stateDescriptor (state : StateDecl) : StateDescriptor :=
  match state.kind with
  | .scalar => { id := state.id, keyType := ValueType.u64.name, valueType := state.type.name }
  | .map keyType _ => { id := state.id, keyType := keyType.name, valueType := state.type.name }
  | .array _ | .dynamicArray =>
      { id := state.id, keyType := "unsupported", valueType := state.type.name }

def stateDescriptors (module : Module) : Array StateDescriptor :=
  module.state.map stateDescriptor

/-! ## Capability metadata -/

def pushUniqueCapability (caps : Array String) (cap : String) : Array String :=
  if caps.any (fun c => c == cap) then caps else caps.push cap

/-- Deduplicate while preserving first-seen order. -/
def dedupCapabilities (caps : Array String) : Array String :=
  caps.foldl pushUniqueCapability #[]

/-- The module's required capability ids (from the portable IR capability fold). -/
def moduleCapabilities (module : Module) : Array String :=
  dedupCapabilities (module.capabilities.map (·.id))

/-! ## Artifact metadata -/

structure ArtifactMetadata where
  targetId : String
  moduleName : String
  entrypoints : Array AbiEntrypointDescriptor
  state : Array StateDescriptor
  capabilities : Array String
  deriving Repr, Inhabited

/-- Build artifact metadata directly from a portable IR module (plan-free). -/
def buildArtifactMetadata (module : Module) : ArtifactMetadata :=
  {
    targetId := Target.aleoLeo.id
    moduleName := module.name
    entrypoints := abiEntrypointDescriptors module
    state := stateDescriptors module
    capabilities := moduleCapabilities module
  }

end ProofForge.Backend.Aleo.Metadata
