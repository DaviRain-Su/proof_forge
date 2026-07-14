import ProofForge.Contract.Examples.ValueVault
import ProofForge.Contract.Intent
import ProofForge.Contract.Spec
import Examples.Backend.Solana.Contracts.Vault
import ProofForge.Target.Formal
import ProofForge.Target.FormalBoundary
import ProofForge.IR.Contract

/-!
# FV-1 target-routing anchors

These executable checks keep representative `resolveSpec` boundaries tied to
the theorem-backed `requireCapabilityPlan` helpers.
-/

namespace ProofForge.Tests.TargetFormal

open ProofForge.Target

-- FV-1 full-boundary soundness theorems (native_decide over the three
-- primary-chain profiles × Counter and ValueVault).
#check resolveSpec_sound_counter_evm
#check resolveSpec_sound_counter_solana
#check resolveSpec_sound_counter_near
#check resolveSpec_sound_value_vault_evm
#check resolveSpec_sound_value_vault_near

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
  let plan ← requireOk
    (resolveSpec evm ProofForge.Contract.Examples.ValueVault.spec)
    "ValueVault EVM routing failed"
  require (plan.checkedBy evm) "ValueVault EVM plan failed FV-1 checkedBy predicate"
  require (resolveSpecCheckedBy evm ProofForge.Contract.Examples.ValueVault.spec)
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
  requireError (resolveSpec evm Examples.Backend.Solana.Contracts.Vault.spec)
    "target `evm` cannot use Solana target extension metadata on operation `solana.runtime.allocator`"
    "Solana target-extension metadata must be rejected on EVM"
  let solanaPlan ← requireOk
    (resolveSpec solanaSbpfAsm Examples.Backend.Solana.Contracts.Vault.spec)
    "Solana Vault routing failed"
  require (solanaPlan.checkedBy solanaSbpfAsm)
    "Solana Vault plan failed FV-1 checkedBy predicate"

/-- FV-1 full-boundary soundness: the new `native_decide` theorems in
`Target.Formal` cover the full `resolveSpec` boundary (not just the
`requireCapabilityPlan` layer) on the Counter and ValueVault specs across the
three primary-chain profiles. This check #checks that they type-check. -/
def checkFullBoundaryTheorems : IO Unit := do
  -- resolveSpec_sound_counter_evm / _solana / _near
  -- resolveSpec_sound_value_vault_evm / _near
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
