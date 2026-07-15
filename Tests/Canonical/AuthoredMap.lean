import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Solana.Plan.Core
import ProofForge.Backend.WasmHost.NearModulePlan.Core
import ProofForge.Contract.Source
import ProofForge.Frontend.Authored.Canonicalize
import ProofForge.Target.Registry

namespace ProofForge.Tests.Canonical.AuthoredMap

open ProofForge.Contract.Source
open ProofForge.Frontend.Authored.Canonicalize
open ProofForge.IR.Core
open ProofForge.Target

contract_source MapProbe do
  mapping values from .u64 to .u64

  entry set (key : .u64, value : .u64) do
    do mapWrite values key value;

  query get (key : .u64) returns(.u64) do
    return mapRead values key;

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def capabilityPlan (targetId : String)
    (bundle : ProofForge.IR.Canonical.CanonicalBundle) : CapabilityPlan := {
  targetId
  calls := bundle.contract.contract.requirements
}

def operations (bundle : ProofForge.IR.Canonical.CanonicalBundle) : Array InstructionOp :=
  bundle.contract.contract.module.functions.flatMap fun function =>
    function.blocks.flatMap fun block => block.instructions.map (·.op)

def withEvmSelectors
    (checked : ProofForge.IR.Canonical.CheckedCanonicalContract) :
    IO ProofForge.IR.Canonical.CheckedCanonicalContract := do
  let entrypoints := checked.contract.interface.entrypoints.map fun entrypoint =>
    let selector? := match entrypoint.name with
      | "set" => some "1ab06ee5"
      | "get" => some "9507d39a"
      | _ => entrypoint.selector?
    { entrypoint with selector? }
  let canonical := { checked.contract with
    interface := { checked.contract.interface with entrypoints } }
  match ProofForge.IR.Canonical.validateCanonical canonical with
  | .ok hydrated => pure hydrated
  | .error error => throw <| IO.userError s!"EVM selector hydration failed: {repr error}"

def main : IO Unit := do
  let bundle <- match normalizeAuthored contract with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"direct map normalization failed: {repr error}"
  require (bundle.contract.contract.module.state.any fun declaration =>
      match declaration.shape with
      | .map .u64 .u64 (some 256) => true
      | _ => false)
    "direct mapping declaration did not normalize to target-neutral Core map state"
  let ops := operations bundle
  require (ops.any fun operation => match operation with
      | .storageStore { path := #[.mapKey _], resultType := .u64, .. } _ => true
      | _ => false)
    "direct mapWrite did not normalize to a Core map-key store"
  require (ops.any fun operation => match operation with
      | .storageLoad { path := #[.mapKey _], resultType := .u64, .. } => true
      | _ => false)
    "direct mapRead did not normalize to a Core map-key load"

  let evmChecked <- withEvmSelectors bundle.contract
  match ProofForge.Backend.Evm.Plan.Core.buildFromCore evmChecked
      (capabilityPlan evm.id bundle) with
  | .ok _ => pure ()
  | .error error => throw <| IO.userError s!"EVM direct map plan failed: {error.message}"
  match ProofForge.Backend.Solana.Plan.Core.buildFromCore bundle.contract
      (capabilityPlan solanaSbpfAsm.id bundle) with
  | .ok _ => pure ()
  | .error error => throw <| IO.userError s!"Solana direct map plan failed: {error.message}"
  match ProofForge.Backend.WasmHost.NearModulePlan.Core.buildFromCore bundle.contract
      (capabilityPlan wasmNear.id bundle) with
  | .ok _ => pure ()
  | .error error => throw <| IO.userError s!"NEAR direct map plan failed: {error.message}"
  IO.println "authored-map: ok"

end ProofForge.Tests.Canonical.AuthoredMap

def main : IO Unit :=
  ProofForge.Tests.Canonical.AuthoredMap.main
