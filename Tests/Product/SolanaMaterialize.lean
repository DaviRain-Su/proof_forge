/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Phase B.2: portable IR → Solana accounts without Source.Solana authoring.
-/
import Examples.Product.ValueVault
import ProofForge.Backend.Solana.Extension
import ProofForge.Backend.Solana.Materialize
import ProofForge.Backend.Solana.Plan
import Examples.Backend.Solana.Contracts.Vault
import ProofForge.Target
import ProofForge.Frontend.Authored
import ProofForge.Backend.Solana.Plan.Core
import ProofForge.IR.Examples.Counter

open ProofForge.Backend.Solana.Materialize
open ProofForge.Backend.Solana.Extension
open ProofForge.Target

def require (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

def main : IO Unit := do
  -- Explicit v1 materialization fixture. The public Product Counter now enters
  -- through Authored/Core and is covered by the direct target-plan gates.
  let counter := ProofForge.IR.Examples.Counter.module
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

  -- Source.Solana Vault reaches the target-owned plan directly.
  let bundle ← match ProofForge.Frontend.Authored.Canonicalize.normalizeAuthored
      Examples.Backend.Solana.Contracts.Vault.contract with
    | .ok bundle => pure bundle
    | .error error => throw (IO.userError s!"Solana Vault normalization failed: {repr error}")
  let capPlan : CapabilityPlan := {
    targetId := solanaSbpfAsm.id
    calls := bundle.contract.contract.requirements
  }
  match ProofForge.Backend.Solana.Plan.Core.buildFromCore bundle.contract capPlan with
  | .error error => throw (IO.userError s!"Solana Vault plan failed: {error.message}")
  | .ok plan =>
      require (hasDeclaredSurface plan.lowerCtxSeed.extensions)
        "Solana Vault direct plan should declare its target-owned extension surface"
      require (plan.extensions.pdas == #["vault"] && plan.extensions.cpis == #["token_transfer"])
        "Solana Vault direct plan lost PDA/CPI materialization"

  -- JSON report is well-formed enough for artifact embedding.
  let js := reportJson counterReport
  require (js.contains "auto-portable") "reportJson must include mode id"
  require (js.contains "count") "reportJson must include account name"

  IO.println "solana-auto-materialize: ok"
