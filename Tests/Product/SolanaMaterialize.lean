/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Phase B.2: portable IR → Solana accounts without Source.Solana authoring.
-/
import Examples.Product.Counter
import Examples.Product.ValueVault
import ProofForge.Backend.Solana.Extension
import ProofForge.Backend.Solana.Materialize
import ProofForge.Backend.Solana.Plan
import Examples.Backend.Solana.Contracts.Vault
import ProofForge.Target

open ProofForge.Backend.Solana.Materialize
open ProofForge.Backend.Solana.Extension
open ProofForge.Target

def require (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

def main : IO Unit := do
  -- Portable Counter: auto-portable materialization.
  let counter := Examples.Product.Counter.module
  require (supportsAutoPortable counter) "Counter must support auto-portable path"
  let counterReport := report counter {}
  require (counterReport.mode == .autoPortable)
    s!"Counter expected auto-portable, got {counterReport.mode.id}"
  require (counterReport.stateAccountCount == 1) "Counter should materialize one state account"
  require (counterReport.accounts.size == 1) "Counter default schema is one account"
  require (counterReport.accounts[0]!.name == "count")
    s!"Counter state account should be named from IR state id, got {counterReport.accounts[0]!.name}"
  require counterReport.accounts[0]!.writable "state account must be writable"
  require (counterReport.accounts[0]!.owner == "program") "state account owner is program"
  require (counterReport.storageBinding == "account-data")
    "storageBinding should be account-data"

  -- Plan build succeeds without extension plan.
  match ProofForge.Backend.Solana.Plan.buildSolanaModulePlan counter none with
  | .error e => throw (IO.userError s!"Counter plan failed: {e.message}")
  | .ok plan =>
      require (plan.accounts.size >= 1) "plan must list materialized accounts"
      require (plan.accounts.any fun a => a.name == "count")
        "plan accounts must include auto-materialized count"

  -- ValueVault portable: also auto-portable.
  let vault := Examples.Product.ValueVault.module
  let vaultReport := report vault {}
  require (vaultReport.mode == .autoPortable)
    s!"ValueVault expected auto-portable, got {vaultReport.mode.id}"
  require (vaultReport.stateAccountCount == 1) "ValueVault synthesizes one state account"

  -- Source.Solana Vault with PDA/accounts → extension-declared.
  let solanaVault := Examples.Backend.Solana.Contracts.Vault.module
  match resolveSpec solanaSbpfAsm Examples.Backend.Solana.Contracts.Vault.spec with
  | .error e => throw (IO.userError s!"Solana Vault resolve failed: {e.render}")
  | .ok capPlan =>
      let ext := ProgramExtensions.fromPlan capPlan
      require (hasDeclaredSurface ext)
        "Solana Vault fixture should declare extension surface"
      let extReport := report solanaVault ext
      require (extReport.mode == .extensionDeclared)
        s!"Solana Vault expected extension-declared, got {extReport.mode.id}"

  -- JSON report is well-formed enough for artifact embedding.
  let js := reportJson counterReport
  require (js.contains "auto-portable") "reportJson must include mode id"
  require (js.contains "count") "reportJson must include account name"

  IO.println "solana-auto-materialize: ok"
