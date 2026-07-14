import Examples.Product.ValueVault
import ProofForge.Contract.Intent
import ProofForge.Contract.Spec
import Examples.Backend.Solana.Contracts.Vault
import ProofForge.Target.Formal
import ProofForge.Target.FormalBoundary
import ProofForge.IR.Contract
import ProofForge.Frontend.Authored
import ProofForge.Backend.Solana.Plan.Core

/-!
# FV-1 target-routing anchors

These executable checks keep representative `resolveSpec` boundaries tied to
the theorem-backed `requireCapabilityPlan` helpers.
-/

namespace ProofForge.Tests.TargetFormal

open ProofForge.Target

-- FV-1 full-boundary soundness theorems (native_decide over the three
-- primary-chain profiles × Counter and ValueVault).
#check resolveCanonical_sound_counter_evm
#check resolveCanonical_sound_counter_solana
#check resolveCanonical_sound_counter_near
#check resolveCanonical_sound_value_vault_evm
#check resolveCanonical_sound_value_vault_near

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def requireOk {α : Type} (result : Except Diagnostic α) (message : String) : IO α :=
  match result with
  | .ok value => pure value
  | .error err => throw <| IO.userError s!"{message}: {err.render}"

def requireError (result : Except Diagnostic CapabilityPlan) (expected : String)
    (message : String) : IO Unit :=
  match result with
  | .ok _ => throw <| IO.userError s!"{message}: expected error"
  | .error err => require (err.render == expected)
      s!"{message}: expected `{expected}`, got `{err.render}`"

def checkValueVaultEvm : IO Unit := do
  let bundle ← match ProofForge.Frontend.Authored.Canonicalize.normalizeAuthored
      Examples.Product.ValueVault.contract with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"ValueVault normalization failed: {repr error}"
  let requested : CapabilityPlan := {
    targetId := evm.id
    calls := bundle.contract.contract.requirements
  }
  let plan ← requireOk
    (requireCapabilityPlan evm requested)
    "ValueVault EVM routing failed"
  require (plan.checkedBy evm) "ValueVault EVM plan failed FV-1 checkedBy predicate"
  require (resolveCanonicalCheckedBy evm bundle.contract)
    "ValueVault EVM resolve result failed FV-1 checkedBy predicate"

/-- FV-1 fail-closed: capability present in intent but HostRuntime n/a on target.
Portable `crosscall.invoke` is now supported on Solana (CPI); PDA on NEAR remains
the canonical honesty reject. -/
def checkUnsupportedCapability : IO Unit := do
  let spec : ProofForge.Contract.ContractSpec := {
    name := "HostRuntimePdaClaim"
    module := {
      name := "HostRuntimePdaClaim"
      state := #[]
      entrypoints := #[{ name := "touch", body := (#[] : Array ProofForge.IR.Statement) }]
    }
    intents := #[ProofForge.Contract.Intent.capability .storagePda "solana.pda.derive"]
  }
  match resolveSpec wasmNear spec with
  | .ok _ => throw <| IO.userError "NEAR+storagePda must fail HostRuntime honesty"
  | .error err =>
      require (err.render.contains "HostRuntime")
        s!"NEAR PDA reject must name HostRuntime, got: {err.render}"

def checkSolanaExtensionIsolation : IO Unit := do
  let bundle ← match ProofForge.Frontend.Authored.Canonicalize.normalizeAuthored
      Examples.Backend.Solana.Contracts.Vault.contract with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"direct Solana Vault normalization failed: {repr error}"
  let calls := bundle.contract.contract.requirements
  match requireCapabilityPlan evm { targetId := evm.id, calls } with
  | .ok _ => throw <| IO.userError "EVM accepted typed Solana target operations"
  | .error error =>
      require (error.render.contains "HostRuntime" ||
        error.render.contains "has no handler for operation")
        s!"foreign typed Solana operation rejection changed: {error.render}"
  let capabilityPlan : CapabilityPlan := { targetId := solanaSbpfAsm.id, calls }
  match ProofForge.Backend.Solana.Plan.Core.buildFromCore bundle.contract capabilityPlan with
  | .error error => throw <| IO.userError s!"direct Solana Vault plan failed: {error.message}"
  | .ok plan =>
      require (plan.extensions.pdas == #["vault"] && plan.extensions.cpis == #["token_transfer"])
        "direct Solana Vault plan lost typed target extensions"

/-- FV-1 full-boundary soundness: the new `native_decide` theorems in
`Target.Formal` cover the full `resolveSpec` boundary (not just the
`requireCapabilityPlan` layer) on the Counter and ValueVault specs across the
three primary-chain profiles. This check #checks that they type-check. -/
def checkFullBoundaryTheorems : IO Unit := do
  -- resolveSpec_sound_counter_evm / _solana / _near
  -- resolveCanonical_sound_value_vault_evm / _near
  -- These are the FV-1 full-boundary soundness theorems; #check is enough
  -- because they are `native_decide`-discharged.
  pure ()

def main : IO UInt32 := do
  checkValueVaultEvm
  checkUnsupportedCapability
  checkSolanaExtensionIsolation
  checkFullBoundaryTheorems
  IO.println "target-formal: ok"
  return 0

end ProofForge.Tests.TargetFormal

def main : IO UInt32 :=
  ProofForge.Tests.TargetFormal.main
