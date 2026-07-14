import Examples.Product.ValueVault
import ProofForge.Backend.Solana.Package
import ProofForge.Backend.Solana.Plan.Core
import ProofForge.Frontend.Authored.Canonicalize
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Tests.ValueVaultExample

open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

def checkedValueVault : IO ProofForge.IR.Canonical.CheckedCanonicalContract := do
  match ProofForge.Frontend.Authored.Canonicalize.normalizeAuthored
      Examples.Product.ValueVault.contract with
  | .ok bundle => pure bundle.contract
  | .error error => throw <| IO.userError s!"ValueVault normalization failed: {repr error}"

def capabilityPlanFor
    (profile : TargetProfile)
    (checked : ProofForge.IR.Canonical.CheckedCanonicalContract) :
    Except Diagnostic CapabilityPlan :=
  requireCapabilityPlan profile {
    targetId := profile.id
    calls := checked.contract.requirements
  }

def requireCapability (plan : CapabilityPlan) (capability : Capability) : IO Unit :=
  require (plan.capabilities.contains capability)
    s!"ValueVault plan for `{plan.targetId}` missing capability `{capability.id}`"

def requireRoutableTarget
    (checked : ProofForge.IR.Canonical.CheckedCanonicalContract)
    (profile : TargetProfile) : IO Unit := do
  let plan ← match capabilityPlanFor profile checked with
    | .ok plan => pure plan
    | .error error =>
        throw <| IO.userError s!"ValueVault routing failed for `{profile.id}`: {error.render}"
  requireCapability plan .storageScalar
  requireCapability plan .eventsEmit
  requireCapability plan .envBlock
  require (plan.calls.all fun call =>
      call.metadata.all fun item => !item.key.startsWith "solana.")
    s!"ValueVault carried Solana metadata into shared Canonical requirements for `{profile.id}`"

def requireRejectedTarget
    (checked : ProofForge.IR.Canonical.CheckedCanonicalContract)
    (profile : TargetProfile) (expected : String) : IO Unit := do
  match capabilityPlanFor profile checked with
  | .ok _ => throw <| IO.userError s!"ValueVault unexpectedly routed through `{profile.id}`"
  | .error error =>
      require (error.render.contains expected || error.render.contains "HostRuntime")
        s!"`{profile.id}` rejection did not name `{expected}` or HostRuntime: {error.render}"

def requireAuthoredShape : IO Unit := do
  let contract := Examples.Product.ValueVault.contract
  require (contract.name == "ValueVault") "ValueVault contract name mismatch"
  require (contract.state.map (·.name) == #[
    "balance", "released", "fees", "last_value", "last_checkpoint", "operations"])
    "ValueVault authored state declaration drift"
  require (contract.entrypoints.map (·.name) == #[
    "initialize", "deposit", "charge_fee", "release", "snapshot",
    "get_balance", "get_net_value"])
    "ValueVault authored entrypoint order drift"
  require (contract.events.map (·.name) == #[
    "VaultInitialized", "ValueDeposited", "ValueCharged", "ValueReleased",
    "ValueSnapshot"])
    "ValueVault authored event schema drift"
  let some snapshot := contract.entrypoints.find? (·.name == "snapshot")
    | throw <| IO.userError "ValueVault snapshot entrypoint missing"
  match snapshot.mutability with
  | .call => pure ()
  | .view => throw (IO.userError
      "ValueVault snapshot writes state and emits an event, so it must remain a call")

def requireSolanaRender
    (checked : ProofForge.IR.Canonical.CheckedCanonicalContract) : IO Unit := do
  let capabilityPlan ← match capabilityPlanFor solanaSbpfAsm checked with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError error.render
  let plan ← match ProofForge.Backend.Solana.Plan.Core.buildFromCore checked capabilityPlan with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError error.message
  let package ← match ProofForge.Backend.Solana.Package.renderPackageFromPlan
      "portable-value-vault" plan with
    | .ok package => pure package
    | .error error => throw <| IO.userError error.message
  let some asmFile := package.files.find? (·.path == package.asmPath)
    | throw <| IO.userError "ValueVault Solana package missing sBPF assembly"
  let some manifestFile := package.files.find? (·.path == package.manifestPath)
    | throw <| IO.userError "ValueVault Solana package missing manifest.toml"
  let asm := asmFile.contents
  let manifest := manifestFile.contents
  for name in #["deposit", "charge_fee", "snapshot"] do
    require (manifest.contains s!"name = \"{name}\"")
      s!"ValueVault manifest missing `{name}`"
  require (contains asm "ValueDeposited") "ValueVault assembly missing ValueDeposited"
  require (contains asm "ValueSnapshot") "ValueVault assembly missing ValueSnapshot"
  require (contains asm "sol_get_clock_sysvar")
    "ValueVault assembly missing portable block-number materialization"

def main : IO UInt32 := do
  requireAuthoredShape
  let checked ← checkedValueVault
  for profile in #[evm, wasmNear, solanaSbpfAsm] do
    requireRoutableTarget checked profile
  requireRejectedTarget checked wasmCosmWasm "env.block"
  requireSolanaRender checked
  IO.println "value-vault-example: ok"
  return 0

end ProofForge.Tests.ValueVaultExample

def main : IO UInt32 :=
  ProofForge.Tests.ValueVaultExample.main
